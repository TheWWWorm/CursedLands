# Packaged regression dependencies

Three Autochess checks initially failed to load their external benchmark superclasses because the packaged regression runner copied only top-level test scripts. The same staging omission also excluded nested JSON fixtures used by clock tests.

The runner now preserves tests, nested fixtures and benchmark helpers in their relative directory layout and resolves tool-resource references there. The new unit test runs the actual packaged-runner entry point and fails against the previous implementation with "relative benchmark superclass was not staged." All ten runner tests pass after the correction; the three Autochess checks pass against the unchanged release pack. Initial failures and successful reruns are retained separately.

The mechanism-picking fixture completed all 5,205 assertions but reported dummy-renderer cleanup errors with the Linux desktop's separate render thread. An independent repeat reproduced the errors; the identical pack and fixture passed without errors with Safe rendering-thread mode. Both production campaign and Autochess authority workers already request Safe mode. The headless runner now matches those workers, with a regression assertion for its launch arguments. All 70 headless cases were rerun; graphical cases retain the package's normal renderer settings. The initial diagnostic is not ignored or classified as an allowed error.

Original-game source and Wine comparison are inapplicable: this is Python test-tool staging, with no counterpart in the original executable and no production-game behavior change. The affected gameplay fixtures and assertions remain unchanged.
