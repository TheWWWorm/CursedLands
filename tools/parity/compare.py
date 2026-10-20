"""Strict trace comparison. Native expectations never enter the remake process."""
import hashlib
import json
import math


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def first_difference(expected, actual, tolerances=None, path="$"):
    """Return the first differing field in deterministic traversal order."""
    tolerances = tolerances or {}
    if isinstance(expected, bool) or isinstance(actual, bool):
        equal = type(expected) is type(actual) and expected == actual
    elif isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        if not math.isfinite(expected) or not math.isfinite(actual):
            return {"field": path, "reason": "nonfinite_number", "expected": str(expected), "actual": str(actual)}
        tolerance = tolerances.get(path.rsplit(".", 1)[-1], {}).get("abs", 0)
        equal = abs(expected - actual) <= tolerance
        if not equal:
            return {"field": path, "reason": "value", "expected": expected, "actual": actual, "delta": actual - expected, "absolute_tolerance": tolerance}
    elif isinstance(expected, dict) and isinstance(actual, dict):
        if set(expected) != set(actual):
            return {"field": path, "reason": "fields", "missing": sorted(set(expected) - set(actual)), "extra": sorted(set(actual) - set(expected))}
        for key in sorted(expected):
            found = first_difference(expected[key], actual[key], tolerances, path + "." + key)
            if found:
                return found
        return None
    elif isinstance(expected, list) and isinstance(actual, list):
        # Inspect the shared prefix before reporting a missing trailing event.
        for i, (a, b) in enumerate(zip(expected, actual)):
            found = first_difference(a, b, tolerances, f"{path}[{i}]")
            if found:
                return found
        if len(expected) != len(actual):
            return {"field": path + f"[{min(len(expected), len(actual))}]", "reason": "length", "expected_length": len(expected), "actual_length": len(actual)}
        return None
    else:
        equal = type(expected) is type(actual) and expected == actual
    return None if equal else {"field": path, "reason": "value_or_type", "expected": expected, "actual": actual}


def validate_trace(trace, inputs, role):
    if trace.get("schema") != 1 or trace.get("role") != role:
        raise ValueError(f"Invalid {role} trace header")
    if trace.get("input_sha256") != digest(inputs):
        raise ValueError(f"{role} trace belongs to different inputs")
    rows = trace.get("scenarios")
    if not isinstance(rows, list):
        raise ValueError(f"{role} trace has no scenario list")
    wanted = [r["id"] for r in inputs["scenarios"]]
    if [r.get("id") for r in rows] != wanted:
        raise ValueError(f"{role} scenario identities/order differ from the requested suite")
    for row, case in zip(rows, inputs["scenarios"]):
        steps = row.get("steps")
        if not isinstance(steps, list) or not steps:
            raise ValueError(f"{role} {row['id']} has an empty/incomplete trace")
        for i, step in enumerate(steps):
            if set(step) != {"step", "state"} or isinstance(step["step"], bool) or step["step"] != i or not isinstance(step["state"], dict) or not step["state"]:
                raise ValueError(f"{role} {row['id']} has an invalid step {i}")
        counted_inputs = {"clock": "frames", "script_random": "words", "sight_factor": "postures",
                          "faction_relation": "values"}
        expected_count = len(case["inputs"][counted_inputs[case["kind"]]]) if case["kind"] in counted_inputs else (
            None if case["kind"] == "cast_rank" else 1)
        if expected_count is not None and len(steps) != expected_count:
            raise ValueError(f"{role} {row['id']} captured {len(steps)} of {expected_count} requested steps")
        if case["kind"] == "cast_rank":
            for i, step in enumerate(steps):
                state = step["state"]
                if (set(state) != {"selected", "remaining"} or type(state["selected"]) is not int
                        or not isinstance(state["remaining"], list)
                        or any(type(uid) is not int for uid in state["remaining"])):
                    raise ValueError(f"{role} {row['id']} has an invalid selection observation")
                terminal = state["selected"] == -1 or not state["remaining"]
                if terminal != (i == len(steps) - 1):
                    raise ValueError(f"{role} {row['id']} has a truncated or overlong selection trace")
    # Also rejects NaN/Infinity in otherwise matching captures.
    canonical(trace)


def compare(inputs, native, remake):
    validate_trace(native, inputs, "original")
    validate_trace(remake, inputs, "remake")
    if native.get("executable_sha256") != inputs["reference"]["executable_sha256"]:
        raise ValueError("Original capture executable does not match the reference identity")
    results = []
    for case, expected, actual in zip(inputs["scenarios"], native["scenarios"], remake["scenarios"]):
        difference = first_difference(expected["steps"], actual["steps"], inputs["contracts"][case["kind"]]["tolerances"], "$.steps")
        result = {"id": case["id"], "kind": case["kind"], "status": "mismatch" if difference else "match",
                  "original_steps": len(expected["steps"]), "remake_steps": len(actual["steps"]),
                  "original_trace_sha256": digest(expected["steps"]), "remake_trace_sha256": digest(actual["steps"])}
        if difference:
            result["first_divergence"] = difference
        results.append(result)
    mismatches = sum(r["status"] == "mismatch" for r in results)
    return {"schema": 1, "status": "mismatch" if mismatches else "match", "input_sha256": digest(inputs),
            "reference": inputs["reference"], "counts": {"scenarios": len(results), "matches": len(results) - mismatches,
            "mismatches": mismatches, "original_steps": sum(r["original_steps"] for r in results)},
            "scenarios": results}
