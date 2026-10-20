# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **passed**.

Completed 49 of 49 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| coop | 46 | 46 | 0 | 0 | 1637 |
| network | 3 | 3 | 0 | 0 | 251 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `network/snapshot_codec` | passed | 209 | 0 | [log](tests/network/snapshot_codec/run.log) |
| `network/snapshot_recovery` | passed | 18 | 0 | [log](tests/network/snapshot_recovery/run.log) |
| `network/campaign_state_transport` | passed | 24 | 0 | [log](tests/network/campaign_state_transport/run.log) |
| `coop/coop_campaign_classes` | passed | 34 | 0 | [log](tests/coop/coop_campaign_classes/run.log) |
| `coop/coop_campaign_classes_astral` | passed | 25 | 0 | [log](tests/coop/coop_campaign_classes_astral/run.log) |
| `coop/coop_fresh_start` | passed | 15 | 0 | [log](tests/coop/coop_fresh_start/run.log) |
| `coop/coop_fresh_start_astral` | passed | 15 | 0 | [log](tests/coop/coop_fresh_start_astral/run.log) |
| `coop/coop_fresh_start_guards` | passed | 76 | 0 | [log](tests/coop/coop_fresh_start_guards/run.log) |
| `coop/coop_fresh_start_guards_astral` | passed | 75 | 0 | [log](tests/coop/coop_fresh_start_guards_astral/run.log) |
| `coop/coop_guest_roles` | passed | 51 | 0 | [log](tests/coop/coop_guest_roles/run.log) |
| `coop/coop_guest_roles_astral` | passed | 38 | 0 | [log](tests/coop/coop_guest_roles_astral/run.log) |
| `coop/coop_guest_roles_net` | passed | 31 | 0 | [log](tests/coop/coop_guest_roles_net/run.log) |
| `coop/coop_guest_roles_net_astral` | passed | 31 | 0 | [log](tests/coop/coop_guest_roles_net_astral/run.log) |
| `coop/coop_party_switch` | passed | 23 | 0 | [log](tests/coop/coop_party_switch/run.log) |
| `coop/coop_permissions` | passed | 31 | 0 | [log](tests/coop/coop_permissions/run.log) |
| `coop/coop_progress_chapters` | passed | 7 | 0 | [log](tests/coop/coop_progress_chapters/run.log) |
| `coop/coop_progress_chapters_astral` | passed | 17 | 0 | [log](tests/coop/coop_progress_chapters_astral/run.log) |
| `coop/coop_progress_cleanup` | passed | 11 | 0 | [log](tests/coop/coop_progress_cleanup/run.log) |
| `coop/coop_progress_context` | passed | 72 | 0 | [log](tests/coop/coop_progress_context/run.log) |
| `coop/coop_progress_context_astral` | passed | 76 | 0 | [log](tests/coop/coop_progress_context_astral/run.log) |
| `coop/coop_progress_context_network` | passed | 56 | 0 | [log](tests/coop/coop_progress_context_network/run.log) |
| `coop/coop_progress_context_network_astral` | passed | 45 | 0 | [log](tests/coop/coop_progress_context_network_astral/run.log) |
| `coop/coop_progress_travel` | passed | 15 | 0 | [log](tests/coop/coop_progress_travel/run.log) |
| `coop/coop_progress_travel_astral` | passed | 15 | 0 | [log](tests/coop/coop_progress_travel_astral/run.log) |
| `coop/coop_rename_reconnect` | passed | 155 | 0 | [log](tests/coop/coop_rename_reconnect/run.log) |
| `coop/coop_rename_reconnect_astral` | passed | 155 | 0 | [log](tests/coop/coop_rename_reconnect_astral/run.log) |
| `coop/coop_save_effects` | passed | 31 | 0 | [log](tests/coop/coop_save_effects/run.log) |
| `coop/coop_shared_checkpoint` | passed | 25 | 0 | [log](tests/coop/coop_shared_checkpoint/run.log) |
| `coop/coop_shared_checkpoint_astral` | passed | 25 | 0 | [log](tests/coop/coop_shared_checkpoint_astral/run.log) |
| `coop/coop_shared_checkpoint_net` | passed | 25 | 0 | [log](tests/coop/coop_shared_checkpoint_net/run.log) |
| `coop/coop_shared_checkpoint_net_astral` | passed | 25 | 0 | [log](tests/coop/coop_shared_checkpoint_net_astral/run.log) |
| `coop/coop_solo_return` | passed | 99 | 0 | [log](tests/coop/coop_solo_return/run.log) |
| `coop/coop_solo_return_dependents` | passed | 10 | 0 | [log](tests/coop/coop_solo_return_dependents/run.log) |
| `coop/coop_solo_return_dependents_astral` | passed | 10 | 0 | [log](tests/coop/coop_solo_return_dependents_astral/run.log) |
| `coop/coop_solo_return_guards` | passed | 18 | 0 | [log](tests/coop/coop_solo_return_guards/run.log) |
| `coop/coop_solo_return_guards_astral` | passed | 18 | 0 | [log](tests/coop/coop_solo_return_guards_astral/run.log) |
| `coop/coop_solo_return_older_host` | passed | 22 | 0 | [log](tests/coop/coop_solo_return_older_host/run.log) |
| `coop/coop_solo_return_older_host_astral` | passed | 22 | 0 | [log](tests/coop/coop_solo_return_older_host_astral/run.log) |
| `coop/coop_solo_return_roles` | passed | 10 | 0 | [log](tests/coop/coop_solo_return_roles/run.log) |
| `coop/coop_solo_return_roles_astral` | passed | 12 | 0 | [log](tests/coop/coop_solo_return_roles_astral/run.log) |
| `coop/coop_solo_return_transport` | passed | 35 | 0 | [log](tests/coop/coop_solo_return_transport/run.log) |
| `coop/coop_vm_projection` | passed | 36 | 0 | [log](tests/coop/coop_vm_projection/run.log) |
| `coop/coop_vm_projection_astral` | passed | 21 | 0 | [log](tests/coop/coop_vm_projection_astral/run.log) |
| `coop/coop_vm_solo` | passed | 30 | 0 | [log](tests/coop/coop_vm_solo/run.log) |
| `coop/coop_vm_solo_trap` | passed | 24 | 0 | [log](tests/coop/coop_vm_solo_trap/run.log) |
| `coop/coop_zone_transfer` | passed | 20 | 0 | [log](tests/coop/coop_zone_transfer/run.log) |
| `coop/coop_zone_transfer_astral` | passed | 20 | 0 | [log](tests/coop/coop_zone_transfer_astral/run.log) |
| `coop/coop_fresh_start_before_start` | passed | 15 | 0 | [log](tests/coop/coop_fresh_start_before_start/run.log) |
| `coop/coop_fresh_start_astral_before_start` | passed | 15 | 0 | [log](tests/coop/coop_fresh_start_astral_before_start/run.log) |

## Scope

0 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
