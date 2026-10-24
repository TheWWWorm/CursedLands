#!/usr/bin/env python3
"""Retired entry point for the permanently withdrawn RTX 30 mod package."""

WITHDRAWN = 'RTX 30 / dlssg_for_sm86 was permanently withdrawn on 2026-10-24. Packaging and publication are disabled. See docs/integrations/dlssg-sm86.md.'


def prepare(*args, **kwargs):
    raise RuntimeError(WITHDRAWN)


if __name__ == "__main__":
    raise SystemExit(WITHDRAWN)
