# Native Windows path-tracing save-load validation

## Changes

The D3D12 DXR patch now restricts enhanced-barrier synchronization scopes to
the access type. Constant-buffer barriers retain ray-tracing shader access but
exclude acceleration-structure builds. Vertex-fetch and shading-rate masks
retain their upstream scopes. Enhanced barriers stay enabled.

Responsive path tracing also retains bounded history across gradual daylight
updates. The campaign clock changes the sun direction, sun colour and sky every
frame. Exact comparisons discarded almost all temporal samples during ordinary
outdoor gameplay. Small daylight changes now use the same short history as
local-light flutter. Larger changes, source extinction, projection changes and
camera cuts still reset; Still scene mode still requires exact lighting.
This reduces avoidable noise without increasing the ray budget. Low-quality
single-sample path tracing can still show noise.

## Native failure evidence

The original Windows engine reproduces the failure when tracing is followed by
a TLAS rebuild and another frame-uniform upload. The minimal GPU fixture starts
with hidden geometry, reveals it, traces, then updates the TLAS and resizes.

The rejected constant-buffer transition has `SyncBefore=0x800100`
(`BUILD_RAYTRACING_ACCELERATION_STRUCTURE | RAYTRACING`), `AccessBefore=0x2`
(`CONSTANT_BUFFER`), `SyncAfter=0x200` (`COPY`) and `AccessAfter=0x400`
(`COPY_DEST`). Command-list close returns `0x80070057` (`E_INVALIDARG`), followed
by device removal with reason `0x887a0001` (`DXGI_ERROR_INVALID_CALL`). A later
resource binding faults in `nvwgf2umx.dll`; that is downstream of the rejected
command list. The access/synchronization rules are documented in Microsoft's
[Enhanced Barriers specification](https://microsoft.github.io/DirectX-Specs/d3d/D3D12EnhancedBarriers.html).

Both legacy barriers and corrected enhanced barriers pass the reproducer.
The final executable uses corrected enhanced barriers, with no temporary
barrier override, per-barrier logging or pre-binding diagnostic trap.

## Build and test environment

- Windows 10.0.26300, NVIDIA GeForce RTX 4090 Laptop GPU, native D3D12.
- Game source: `6da52705a0afc13ced823622ad0f81489349f508` plus this change.
- Godot source: `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`, sixteen common
  patches, uniform-stage patch, FSR patch, corrected DXR patch, device diagnostics.
- MinGW GCC 15.2, `target=template_release`, `production=yes`, `optimize=speed`,
  `lto=none`, `d3d12=yes`, `use_fsr_sdk=yes`, Agility SDK 1.618.5, FSR SDK 2.3.0.
- All twenty patches apply to clean pinned sources; all 62 patched source files
  match the files compiled into the final template.
- The final executable is exported with the rebuilt template, resource editing
  enabled and the approved icon. Its native code matches the template; all six
  embedded Windows icon sizes match the approved ICO's decoded pixels.
- Tests use an isolated profile with a copied `gz1g` starting-area save and its
  HD texture mod, free cursor, visible FPS and muted audio. Player preferences
  and saves are unchanged. The full frontend/simulation-worker path is used.

## Regression coverage

`water_raytrace_device.gd` passes 25 GPU readback checks, including the
hidden-to-visible TLAS sequence, subsequent update, resize, alpha rejection and
teardown. `path_trace_device.gd` passes 17 checks covering bounce energy,
emission, glossy transport, history, resize and teardown.

`path_trace_light_history.gd` passes 49 controller/GPU checks. These cover
gradual daylight with simultaneous torch flutter, bounded low-FPS history,
immediate resets for larger lighting changes and extinguished sources,
projection changes, strict/progressive modes, and actual diffuse/glossy history
weights on the GPU.

The full save-load fixture waits for a fresh device after each load before
checking active frames and output availability. `--require-history` also checks
that ordinary lighting updates retain history on most active frames. This
avoids counting the previous world's last output as a successful reload.

At Low quality with two bounces, the final native executable completes three
loads with 1,343 active traced frames and no failures. The six-second observation
periods contain 380, 405 and 404 active frames respectively; all 1,189 reuse
history. Each load creates a new device and completes scene preparation before
measurement. The display is 3840 x 2126 and the traced output is 1920 x 1063.
The previous exact-daylight policy repeatedly reset history during this same
running campaign. These counts verify history continuity, not a percentage
reduction in visible noise.

Medium quality with four bounces also completes two loads without failures,
rendering at 2880 x 1595. Its observation periods contain 163 and 162 active
frames; all 325 reuse history. These runs use normal runtime settings with
`EI_D3D12_DIAGNOSTICS` unset. The 49 lighting-history checks additionally pass
on native Vulkan 1.4.357. Detailed machine-readable results are in
[`results.json`](results.json).

Example invocation, using an isolated profile containing a copied save:

```text
CursedLands.exe --audio-driver Dummy --rendering-driver d3d12 -- --tool=res://tools/tests/path_trace_save_load.gd --save-slot=save6 --cycles=3 --pt-mode=1 --quality=0 --require-history --output=user://results.json
```

Local build and detailed logs are under `builds/windows-pt-save-load-fixed/`
and `builds/pt-save-load/`. This is an unpublished development build. Validation
on this GPU does not qualify other GPUs or replace long-duration gameplay tests.
