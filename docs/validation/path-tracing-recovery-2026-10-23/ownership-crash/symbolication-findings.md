# Separate-render-thread disposal crash

This is an offline GDB reading of the existing core; no target process was launched.
The executable Build ID is `498084aefc8728f9620cf4e796c9cae53b3fd03d`.
Its mapping starts at `0x555555554000`. Reproduce with the exact argv in
`symbolicate-dispose-command.json`; output is `symbolicate-dispose.log`.

## Observed core state

- Crashing LWP 196808, WorkerThread 0, PC `0x555558af9059` (image offset `0x35a5059`).
- Destination register RDI is `0x348`; source RSI is `0x555578f7b900`.
- Source Variant is type 1 (BOOL), value false.
- The caller frame stores GDScriptFunction pointer `0x55557c13bc10` and instruction index 0.
- Its two StringName fields decode to **dispose** and **res://src/game/fx/scene_raytrace_device.gd**.
- The VM's address-base array contains a valid stack, valid constants, and **null member storage**.
- Instruction words are `[0x15, 0x02000023, 0x01000000]`: ASSIGN to member 35 from constant 0.
- Member 35 is `_published_valid`; the first statement of this function is `_published_valid=false`.

## Derived native mapping

The native routine starts at image offset `0x35a5040`; its self-assignment check,
Variant type comparison and type switch through 0x26 match
`Variant::operator=(const Variant&)` in `core/variant/variant.cpp:2653`.
The fault is at +0x19 while reading the destination type.
The caller is `GDScriptFunction::call` (entry offset `0x773550`) in its
`OPCODE_ASSIGN` block, return offset `0x778ea6`; this matches the source address
calculation at `modules/gdscript/gdscript_vm.cpp:719` and opcode block at line 1384.
Member index 35 times 24-byte Variant is 840 (`0x348`), exactly the fault address.

This directly identifies the failing script assignment and null member base.
An instance being destroyed concurrently with an ordinary queued Callable is
consistent with these observations. A matching full native symbol table was
not available, so this report does not claim a complete native-stack mapping.

## Local symbol search

The original `engine/godot-water-rt.x86_64` and its Linux `.o`/`.a` link inputs
were purged. The known base `tooltip-engine/bin/...perf_lto` and copies found
under local scratchpads are stripped with a different Build ID
`947006134805154e175a1444a4423c1414e7baed`. Installed Godot 4.7 Linux templates
are stripped and are not this custom build. No full engine rebuild was needed.

REA's optional binary-layout provider was unavailable because no
`REA_PWNTOOLS_PYTHON` was configured. All positive evidence above is from local
GDB, objdump and source comparison, not a REA analysis result.
