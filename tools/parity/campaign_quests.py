"""Extract supported condition lists from owned MOBs; never infer outcomes.

This deliberately conservative reader skips a whole condition list when any
call/binding is outside the native adapter. It does not replace unsupported
conditions with True or claim to execute trigger bodies.
"""
from collections import Counter, defaultdict
import hashlib
from pathlib import Path
import re
import struct

# Argument types in the original script language, not implementation formulas.
SIGNATURES = {
    **{name: "nn" for name in ["IsEqual", "IsLess", "IsGreater", "Add", "Sub", "Mul", "Div"]},
    "Not": "n", **{name: "u" for name in ["HP", "MaxHP", "GetX", "GetY", "GetObjectID", "IsAlive", "IsDead"]},
    "DistanceUnitUnit": "uu", "DistanceUnitPoint": "unn", "UnitInSquare": "unnnn",
    "GetLeverState": "u", "GSGetVar": "ns", "IsEqualString": "ss",
}
TOKEN = re.compile(r'//[^\n]*|"(?:[^"]*)"|[(),=:]|[^\s(),=:"]+')


def script_bytes(data):
    root, end = struct.unpack_from("<II", data)
    if root != 0xa000 or not 8 <= end <= len(data):
        raise ValueError("Invalid MOB root")
    result, at = None, 8
    while at < end:
        kind, size = struct.unpack_from("<II", data, at)
        if size < 8 or at + size > end:
            raise ValueError("Invalid MOB child")
        body = data[at + 8:at + size]
        if kind in (0xacceecca, 0xacceeccb):
            if result is not None:
                raise ValueError("Ambiguous MOB script")
            if kind == 0xacceeccb:
                key, = struct.unpack_from("<I", body)
                decoded = bytearray()
                for value in body[4:]:
                    key = (key * 214013 + 2531011) & 0xffffffff
                    decoded.append(value ^ ((key >> 16) & 255))
                body = bytes(decoded)
            result = body
        at += size
    return result or b""


class Reader:
    def __init__(self, text):
        self.tokens = [t for t in TOKEN.findall(text.rstrip("\0")) if not t.startswith("//")]
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else ""

    def take(self, expected=None):
        token = self.peek()
        if not token or expected is not None and token != expected:
            raise ValueError(f"Expected {expected}, found {token}")
        self.i += 1
        return token

    def skip_group(self):
        self.take("(")
        depth = 1
        while depth:
            t = self.take()
            depth += (t == "(") - (t == ")")

    def expression(self):
        t = self.take()
        if self.peek() == "(":
            self.take("(")
            args = []
            while self.peek() != ")":
                args.append(self.expression())
                if self.peek() != ",": break
                self.take(",")
            self.take(")")
            return {"call": t, "args": args}
        if t.startswith('"'):
            return {"string": t[1:-1]}
        try:
            return float(t)
        except ValueError:
            return {"symbol": t}

    def blocks(self):
        rows = []
        while self.peek():
            token = self.take()
            if token in ("GlobalVars", "WorldScript"):
                self.skip_group()
            elif token == "DeclareScript":
                self.take()
                self.skip_group()
            elif token == "Script":
                name = self.take()
                self.take("(")
                block = 0
                while self.peek() != ")":
                    self.take("if")
                    self.take("(")
                    conditions = []
                    while self.peek() != ")":
                        conditions.append(self.expression())
                        if self.peek() == ",": self.take(",")
                    self.take(")")
                    self.take("then")
                    self.skip_group()
                    rows.append((name, block, conditions))
                    block += 1
                self.take(")")
            else:
                raise ValueError(f"Unsupported top-level token {token}")
        return rows


def normalize(expression, bindings, kind="n"):
    if kind == "s":
        if not isinstance(expression, dict) or "string" not in expression:
            raise ValueError("dynamic string")
        expression["string"].encode("ascii")
        return expression
    if kind == "u":
        if not isinstance(expression, dict) or "symbol" not in expression:
            raise ValueError("dynamic actor lookup")
        name = expression["symbol"]
        if name == "NULL":
            return {"unit": -1}
        if name not in bindings:
            bindings[name] = len(bindings)
        return {"unit": bindings[name]}
    if isinstance(expression, (float, int)):
        return expression
    name = expression.get("call", "")
    if name not in SIGNATURES:
        raise ValueError("call/binding:" + (name or next(iter(expression))))
    signature = SIGNATURES[name]
    if len(signature) != len(expression["args"]):
        raise ValueError("arity:" + name)
    return {"call": name, "args": [normalize(arg, bindings, k) for arg, k in zip(expression["args"], signature)]}


def samples(conditions, count):
    points = [[0, 0], [1000, 1000]]
    levers, variables = set(), set()
    pairwise = [False]

    def walk(e):
        if not isinstance(e, dict) or "call" not in e:
            return
        args = e["args"]
        if e["call"] == "GetLeverState" and args[0]["unit"] >= 0: levers.add(args[0]["unit"])
        if e["call"] == "GSGetVar": variables.add(args[1]["string"])
        if e["call"] == "DistanceUnitUnit": pairwise[0] = True
        if e["call"] == "UnitInSquare" and all(isinstance(x, (int, float)) for x in args[1:]):
            x1, y1, x2, y2 = args[1:]
            points.extend([[x1, y1], [x2, y2], [(x1+x2)/2, (y1+y2)/2],
                           [x1-0.001, y1], [x2+0.001, y2]])
        if e["call"] == "DistanceUnitPoint" and all(isinstance(x, (int, float)) for x in args[1:]):
            points.extend([args[1:], [args[1]+1, args[2]], [args[1]+10, args[2]]])
        for arg in args:
            walk(arg)

    for c in conditions:
        walk(c)
    unique = list(dict.fromkeys(tuple(p) for p in points))
    snapshots = []
    for p in unique:
        snapshots.append({"units": [{"pos": list(p), "hp": 100, "max_hp": 100, "dead": False, "uid": i+1}
                                    for i in range(count)]})
    if pairwise[0]:
        for x in [0, .001, 1, 3, 5, 10, 1000]:
            snapshots.append({"units": [{"pos": [x if i == 0 else 0, 0], "hp": 100, "max_hp": 100,
                                         "dead": False, "uid": i+1} for i in range(count)]})
    for value in [0, 1, 2, -1]:
        records = [{"pos": list(unique[-1]), "hp": 100, "max_hp": 100, "dead": False, "uid": i+1}
                   for i in range(count)]
        for i in levers: records[i]["lever"] = value
        snapshots.append({"units": records, "variables": {key: value for key in variables}})
    snapshots.append({"units": [{"pos": list(unique[-1]), "hp": 0, "max_hp": 100, "dead": True, "uid": i+1}
                                for i in range(count)]})
    snapshots.append({"units": [None] * count})
    return snapshots


def has_call(expression, name):
    return isinstance(expression, dict) and "call" in expression and (
        expression["call"] == name or any(has_call(arg, name) for arg in expression["args"]))


def append_campaign_cases(inputs, game_dir, limit=120):
    """Round-robin maps so a cap cannot select just the first region."""
    by_map, skipped, sources = defaultdict(list), Counter(), []
    for path in sorted((Path(game_dir) / "maps").glob("*.mob")):
        raw = path.read_bytes()
        text = script_bytes(raw)
        if not text:
            continue
        fingerprint = hashlib.sha256(raw).hexdigest()
        try:
            blocks = Reader(text.decode("cp1251")).blocks()
        except ValueError as exc:
            # Unsupported grammar is visible in the source audit.
            skipped["parse:" + str(exc)] += 1
            continue
        sources.append({"mob": path.name, "sha256": fingerprint, "condition_lists": len(blocks)})
        for name, index, conditions in blocks:
            if not conditions:
                skipped["empty authored conditions"] += 1
                continue
            bindings = {}
            try:
                converted = [normalize(c, bindings) for c in conditions]
                if not all(isinstance(c, dict) and "call" in c for c in converted):
                    raise ValueError("constant condition root")
                # Constant-only gates add little campaign coverage.
                if not bindings and not any(has_call(c, "GSGetVar") for c in converted):
                    raise ValueError("no actor binding")
            except (ValueError, UnicodeError) as exc:
                skipped[str(exc)] += 1
                continue
            by_map[path.name].append({
                "id": f"quest_trigger/authored/{path.stem}/{name}/block{index}",
                "kind": "quest_trigger",
                "source": {"mob": path.name, "sha256": fingerprint, "script": name, "block": index,
                           "actor_bindings": bindings},
                "inputs": {"conditions": converted, "snapshots": samples(converted, len(bindings))},
            })
    eligible = sum(map(len, by_map.values()))
    selected = []
    cap = eligible if limit == 0 else limit
    while len(selected) < cap and any(by_map.values()):
        for rows in by_map.values():
            if rows and len(selected) < cap:
                selected.append(rows.pop(0))
    if not selected:
        raise ValueError("No supported authored quest condition lists found")
    inputs["scenarios"].extend(selected)
    inputs["authored_quests"] = {
        "scope": "Unmodified condition trees with supplied actor records; trigger bodies are not replayed.",
        "eligible_condition_lists": eligible, "selected_condition_lists": len(selected),
        "limit": limit, "skipped": dict(sorted(skipped.items())), "sources": sources,
    }
    return inputs
