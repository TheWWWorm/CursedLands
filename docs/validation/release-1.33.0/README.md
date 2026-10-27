# Release 1.33.0 candidate validation

The release record in the parent directory identifies the tested candidate game tree, package hashes, platform scope and limits. 44 packaged Linux checks (30411 assertions) ran with the release executable, PCK and native libraries in isolated muted profiles; rendered cases used GPU Lab. They cover the #118 and #119 fixes, native script expressions, Odalisque and round damage, unavailable graphics settings, loading and path-tracing changes, and Odalisque layout in English, Russian and German at 720p, 1440p and 4K.

Five Windows cases ran the packaged executable, PCK and rebuilt native DLL through GE-Proton 11-11 and D3D12/VKD3D with one locked writable prefix. All five exports contain the same 455 compiled game scripts. Browser tests cover a fresh start and the service-worker upgrade from the published 1.32.0 archive while preserving storage.

Full-resolution candidate captures are retained under the workspace's `Evidence/releases/1.33.0`; the manifest records dimensions and hashes. Native Windows, macOS and Android device runtime limits are stated in the release record.
