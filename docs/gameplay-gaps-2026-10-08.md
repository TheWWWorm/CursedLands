# Gameplay follow-up — 8 October 2026

Baseline: performance checkpoint `329512c`. User reports were observed in published Experimental 1.0.3 version 5 on Windows, Ryzen 7945HX / RTX 4090 Mobile. A source inspection or focused regression is not a completed chapter playthrough. Items remain open until the evidence below establishes their scope.

The additional [campaign audit](/home/llm2x/Documents/EI/local/implementation-gaps-2026-10-07.md) supplies findings G01–G10 and original-data probes. Its findings were investigations, not fixes. Preserve original campaign behavior where it is established; campaign co-op must extend story roles consistently to guests.

## Player reports

| ID | Report / required behavior | Status |
| --- | --- | --- |
| U01 | Distant creatures blink for host/client; turning hides enemies and corpses in LiA. Compare original relevance, perception, geometry and retained corpses. | Investigating |
| U02 | Tutorial/other zone transfers notify distant clients late; old-map commands can reach the new map. Freeze input and show loading at transfer start; reject commands from earlier worlds. | Fixed command-generation fence and immediate loading transaction; real ENet transfer/reload regression passes. Windows playthrough pending. |
| U03 | Camp exit is available during the Terror attack. Honor authored exit locks. | Open |
| U04 | Guests fail to follow the host through the broken barrier while fleeing Terror. | Open |
| U05 | Catacombs melee reaches enemies far below an elevator. Enforce appropriate vertical reach. | Open |
| U06 | Catacombs elevator is cramped for co-op, sticks at bottom, and upper lever cannot summon it. Check original lever/mover behavior and party boarding. | Open |
| U07 | Camera drops below bridges/elevators or into lower water/pits. | Open |
| U08 | Catacombs exit leaves client at ~4 FPS until reload; transfer/cutscene handoff is slow/buggy. Check retained worlds/resources and presentation lifecycle. | Open |
| U09 | Terror kills party/villagers after Catacombs; compare authored reset/despawn conditions. | Open |
| U10 | LiA guest death offers reload options that both exit to menu. Use the appropriate client failure screen. | Fixed scripted LiA failure routing to co-op notice; guest has no reload action. Rendered ENet regression passes. |
| U11 | Host and client characters lag, jump and catch up during ordinary co-op. Measure authority updates and interpolation under real load. | Open |
| U12 | Shelter exit opens an empty travel map instead of the authored direct transfer. | Open; current source already distinguishes direct destinations, needs original-route test |
| U13 | Selecting travel closes the map onto a frozen world before showing loading. Cover both desktop and deferred mobile presentation. | Loading overlay is prepared before travel UI closes; deferred presentation regression passes. |
| U14 | Long paths have no preview line. | Open |
| U15 | Classic peaceful zones allow keyboard/controller forced attack, spells and crouching. Enforce at authority as well as UI. | Open |
| U16 | Base campaign lizards lack visible pitchforks. | Open |
| U17 | Dialogue camera is obstructed by scenery. | Open |
| U18 | Spell icons show prototype colors instead of the actual spell's colors. | Open |
| U19 | Invisible zero-price rune appears in Gipath. | Open |
| U20 | Repeated identical items for sale create separate stacks; merge into the current sale stack. | Open |
| U21 | Zak uses stealing lines when walking up to camp NPCs to talk. | Open |
| U22 | Sold inventory disappears slowly, especially when hosting co-op. Apply sale presentation atomically after confirmation. | Open |
| U23 | Steal/turn in/kill/loot duplicates the quest pair Резак и Шило; check equivalent quest-carrier cases. | Open |
| U24 | Quest objects such as Dragon Amulet and Cage Key remain after their authored removal. | Open |
| U25 | Verify tamed dragon's departure after harpies against original scripts; user observed eventual departure. | Open |
| U26 | Rejoining with a changed name updates overhead text but leaves the old name in character preview. | Open |
| U27 | Experimental third-person mode: behind-shoulder view, persistent HP bars, free aimed attacks including peaceful zones, WASD movement and mouse camera/attacks; default mode for gamepad. Preserve classic controls as a selectable mode. | Requested; open |

## Campaign audit findings

| ID | Required follow-up | Status |
| --- | --- | --- |
| G01 | Party-switching dialogue corrupts host/guest purse ownership inside `with_purse`. Verify cash and item ownership through switch, return and save/load. | Fixed nested purse ownership and campaign bag operations; original Nalo handler + guest RPC + save/reload/disconnect pass. |
| G02 | Guest progress package omits current/waiting parties, bags and companions; merge can advance story with the wrong character. | Reproduced by audit; open |
| G03 | LiA import selects dormant pre-chapter hero/bag. Distinguish permanent chapter progression from temporary substitute characters. | Fixed protagonist import for normal LiA chapters and temporary Shaina; original-data chapter tests pass. |
| G04 | Disconnect/death changes script protagonist; abandoned guest counts as mercenary. Keep narrative identity independent of connection/liveness. | Fixed protagonist/mercenary identity independent of guest disconnect or protagonist death; state tests and real Nalo disconnect pass. |
| G05 | `Heroes` drops dead story members before authored party-death predicates run. Preserve required story roster for those predicates. | Fixed required story corpses in Heroes; actual LiA CheckFail predicate tests pass. Optional guest death stays separate. |
| G06 | Named parties disable LiA camp catch-up for late joiners/partial receipts. | Fixed named-party camp catch-up; six branches and saved idempotence pass. |
| G07 | Co-op ownership/order changes the meaning of fixed story-roster indexes. Separate narrative roles from added guests; audit effects intended for everyone. | Fixed stable story-role indexes including guest-owned Kel. Effects intended for every co-op participant still need map-specific adaptation. |
| G08 | Define/test guest participation in temporary protagonist chapters, including equipment, disguise and script constraints. | Behavior/design coverage open |
| G09 | Pets are suppressed and later forgotten in named parties. Distinguish accompanying pets from persistent waiting pets. | Audit state reproduction; open |
| G10 | In-place party redeployment fails to reconcile guest-owned companions. | Source-backed risk; open |

## Validation and checkpoints

Performance results and their limits remain in [the large-area checkpoint](large-area-performance-checkpoint-2026-10-08.md). The first gameplay checkpoint covers transfer safety, scripted co-op failure UI and campaign roster/purse identity. It raises the network protocol to 7; all peers must use the same build.

[Validation receipt](gameplay-transfer-roster-validation.json) records the production export and isolated original-data tests: 31 base / 58 LiA roster checks, 130 camp-grant checks, 22 real ENet Nalo handoff checks, 21 rendered LiA transfer/death checks and 15 rendered movie checks. The pre-fix production baseline fails 18 roster and 8 transfer checks in the corresponding earlier fixtures. The Nalo test exercises the guest's actual dialogue-completion RPC, separate cash/items, deployment, save/reload and disconnect; it is a prepared checkpoint, not the full rescue quest.

Rendered two-world fixtures pass with the engine's safe render-thread mode. Separate render-thread attempts produced buffer-update errors or timeouts and are retained as failed validation; shipping-default two-process presentation still needs a separate test. Xvfb results establish correctness only. These fixes have not yet been packaged for Windows or checked on Retroid, and they do not establish a new performance gain.

Full chapter playthroughs, guest progress-package structure (G02), pets/redeployment (G09/G10), remaining player reports and experimental third-person mode remain open. This document tracks coverage rather than treating source inspection as completion.
