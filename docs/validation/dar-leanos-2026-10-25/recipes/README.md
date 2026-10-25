# Frozen measurement inputs

The three GDScript files here preserve the exact ABBA fixture used for all four accepted runs. They use the shared helpers from `tools/tests/`; they are snapshots to place over a staged test fixture directory, not independent game projects. `run_accepted_pair.py` records the sequential run order and local private runtime bootstrap invocation. The platform-specific Wine/NVIDIA setup remains in the local evidence workspace and is not distributed with these fixtures.

The maintained route is registered as `dar_leanos_route` in `tools/regressions.json`. Run it through `tools/check_regressions.py` with the qualified custom engine, adjacent pack and owned LiA data. The normal route is capped at 30 FPS. For a timed run pass `--dar-benchmark` to the route and schedule it as a GPU Lab heavy job. Preserve exactly the same fixture, map population, cache seed, GPU, resolution and settings for both builds. Record generated and rendered frames separately.
