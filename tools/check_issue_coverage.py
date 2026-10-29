#!/usr/bin/env python3
"""Every issue the changelog says was fixed must have a registered regression test.

The rule in AGENTS.md ("every fix includes a regression test in the same
change") had no enforcement, and the tracker shows the cost: the same reports
reopened under new numbers (animation skip #109/#113/#118/#120, game speed
#62/#98/#116/#119, corpse targeting #95/#103/#112, menu frames #89/#105/#111)
after fixes landed whose tests were never registered or never written.

This check reads the issue links in CHANGELOG.md and requires each issue to
appear in the `issues` list of at least one entry of
tools/parity/gameplay_catalog.json (the one registry of both runners), or in
tools/issue_coverage_exceptions.json with a reason. Issues fixed before the registries recorded links were seeded
into the exceptions file on 2026-10-28; remove an entry when a test is
registered for it. Run without arguments; exit 1 lists the uncovered issues.
"""
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
CHANGELOG = REPO / "CHANGELOG.md"
CATALOG = REPO / "tools/parity/gameplay_catalog.json"
EXCEPTIONS = REPO / "tools/issue_coverage_exceptions.json"
ISSUE_LINK = re.compile(r"\[#(\d+)\]\(https://github\.com/[^)]+/issues/\1\)")


def changelog_issues():
    """Issue numbers the changelog links, with the release each appears under."""
    release = "Unreleased"
    found = {}
    for line in CHANGELOG.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            release = line[3:].split(" ")[0]
        for match in ISSUE_LINK.finditer(line):
            found.setdefault(int(match.group(1)), release)
    return found


def registered_issues():
    covered = {}
    for row in json.loads(CATALOG.read_text(encoding="utf-8"))["tests"]:
        for issue in row.get("issues", []) or []:
            covered.setdefault(int(issue), []).append(row["id"])
    return covered


def exceptions():
    data = json.loads(EXCEPTIONS.read_text(encoding="utf-8")) if EXCEPTIONS.is_file() else {}
    for key, reason in data.items():
        if not key.isdigit() or not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"issue_coverage_exceptions.json: entry {key!r} needs a numeric key and a reason")
    return {int(key): reason for key, reason in data.items()}


def uncovered():
    covered = registered_issues()
    excused = exceptions()
    stale = sorted(issue for issue in excused if issue in covered)
    missing = {issue: release for issue, release in changelog_issues().items()
               if issue not in covered and issue not in excused}
    return missing, stale


def main():
    missing, stale = uncovered()
    for issue, release in sorted(missing.items()):
        print(f"#{issue} ({release}): no registered case lists it in `issues`")
    for issue in stale:
        print(f"#{issue}: covered now; remove it from tools/issue_coverage_exceptions.json")
    covered = registered_issues()
    linked = changelog_issues()
    print(f"{len(linked)} changelog issues, {sum(1 for i in linked if i in covered)} with registered tests, "
          f"{len(exceptions())} excused, {len(missing)} uncovered")
    return 1 if missing or stale else 0


if __name__ == "__main__":
    sys.exit(main())
