# Release 1.31.0 validation

The release record in the parent directory contains the acceptance scope and platform limits. The final package regressions exercise the exact exported executable and PCK, with 446 compiled scripts verified byte-identical across all five platforms. Existing E2 and integrated-source results remain linked separately and are not double-counted.

The first registered PT water run failed because its manifest selected OpenGL. A negative-control unit test fails both affected registrations; the corrected Forward+ registrations and both actual GPU water cases pass. No assertion was weakened and no game code changed for this runner correction. The initial failed result is retained alongside the final results.

Full final-package UI captures in EN/RU/DE at 1080p, 1440p and 4K are retained under the workstation Evidence/releases/1.31.0/ui directory. The earlier native 4K E2 recording is retained in Evidence/e2/fixes-20261026/ui. Representative native-resolution screenshots, logs, source hashes and the exact release recipes are retained here. GPU Lab assigned devices automatically; Wine tests used one locked writable prefix, with reference seeds and toolchains unchanged.

The LiA mountain flashes and attribution of the exact recorded loading delay and stutters remain open. This publication does not claim those reports completely resolved. See the E2 investigation for the verified fixes and remaining uncertainty.
