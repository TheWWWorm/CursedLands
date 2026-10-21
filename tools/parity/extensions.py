"""Discover independently maintained comparison families.

A family lives in three files that never edit the shared runner:

- ``cases_ext_<name>.py``: ``contracts(campaign)`` returns ``{kind: contract}``
  for that campaign (empty when unsupported) and ``scenarios(seed, fuzz)``
  returns input rows. ``STEP_COUNTS`` optionally maps a kind to the input key
  whose length is the expected step count (default: one step), and
  ``validate(case, steps, role)`` optionally rejects malformed observations.
  ``authored(game_dir, limit)`` optionally returns ``(rows, summary)`` built
  from the owned installation when ``--authored-quests`` is given.
- ``native_ext_<name>.py``: ``CAPTURES = {kind: function(original, inputs)}``.
- ``remake_ext_<name>.gd``: staged as ``res://tools/parity_ext/<name>.gd``;
  ``func kinds() -> Array`` and ``func capture(kind, data, trace) -> Array``.

Modules load in sorted order. A kind may be declared by only one family.
"""
import importlib
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _modules(prefix):
    return [importlib.import_module(p.stem) for p in sorted(HERE.glob(prefix + "*.py"))]


def case_modules():
    return _modules("cases_ext_")


def native_captures():
    result = {}
    for module in _modules("native_ext_"):
        for kind, function in module.CAPTURES.items():
            if kind in result:
                raise ValueError(f"Native capture {kind} is declared twice")
            result[kind] = function
    return result


def contracts(campaign):
    result = {}
    for module in case_modules():
        for kind, contract in module.contracts(campaign).items():
            if kind in result:
                raise ValueError(f"Contract {kind} is declared twice")
            result[kind] = contract
    return result


def scenarios(seed, fuzz):
    rows = []
    for module in case_modules():
        rows.extend(module.scenarios(seed, fuzz))
    return rows


def step_counts():
    result = {}
    for module in case_modules():
        result.update(getattr(module, "STEP_COUNTS", {}))
    return result


def validator(kind):
    for module in case_modules():
        if kind in module.contracts("original") or kind in module.contracts("lost_in_astral"):
            return getattr(module, "validate", None)
    return None


def authored(inputs, game_dir, limit):
    """Append installation-derived rows; summaries go under ``authored_extensions``."""
    summaries = {}
    for module in case_modules():
        if hasattr(module, "authored"):
            supported = module.contracts(inputs["reference"]["campaign"])
            rows, summary = module.authored(game_dir, limit)
            rows = [r for r in rows if r["kind"] in supported]
            for row in rows:
                inputs["contracts"].setdefault(row["kind"], supported[row["kind"]])
            inputs["scenarios"].extend(rows)
            summaries[module.__name__.removeprefix("cases_ext_")] = summary
    if summaries:
        inputs["authored_extensions"] = summaries
    return inputs


def remake_scripts():
    return sorted(HERE.glob("remake_ext_*.gd"))
