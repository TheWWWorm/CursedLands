# Complete unresolved comparison failures — 20 October 2026

There are **72 differing scenarios across two executable references**: 53 base-game cases and 19 Astral cases. The 19 shared quest cases appear once below with both campaigns listed. Multiple rows exercise the same underlying behavior; these are not 72 distinct player-facing bugs.

Every listed result repeated identically in two fresh captures per side. `*_bits` values below are decoded for readability; the stored comparison uses exact float32 bits. Steps are zero-based. The [machine-readable results](scenario-results.json) preserve every passing and failing case.

| Scenario | Reference | First differing field | Original | Remake |
|---|---|---|---|---|
| `quest_predicate/IsEqual_3` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/IsEqual_4` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/IsEqual_5` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/nested_rounded_sum` | base + astral | `$.steps[0].state.truth` | true | false |
| `quest_predicate/nested_division` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/string_2` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/string_4` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/rectangle_10_10` | base + astral | `$.steps[0].state.truth` | true | false |
| `quest_predicate/rectangle_10_5` | base + astral | `$.steps[0].state.truth` | true | false |
| `quest_predicate/rectangle_5_10` | base + astral | `$.steps[0].state.truth` | true | false |
| `quest_predicate/rectangle_reversed` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_predicate/rectangle_degenerate` | base + astral | `$.steps[0].state.truth` | true | false |
| `quest_predicate/distance_point_[0.1, 0.2]` | base + astral | `$.steps[0].state.value_bits` | 0.2236067951 (`0x3e64f92e`) | 0.22360681 (`0x3e64f92f`) |
| `quest_predicate/distance_units_[0.1, 0.2]` | base + astral | `$.steps[0].state.value_bits` | 0.2236067951 (`0x3e64f92e`) | 0.22360681 (`0x3e64f92f`) |
| `quest_predicate/distance_missing_unit` | base + astral | `$.steps[0].state.value_bits` | 1.000000015e+30 (`0x7149f2ca`) | 99999 (`0x47c34f80`) |
| `quest_predicate/distance_missing_point` | base + astral | `$.steps[0].state.value_bits` | 1.000000015e+30 (`0x7149f2ca`) | 99999 (`0x47c34f80`) |
| `quest_predicate/missing_distance_large_threshold` | base + astral | `$.steps[0].state.truth` | false | true |
| `quest_trigger/enter_leave_reenter_rectangle` | base + astral | `$.steps[3].state.dispatches` | 3 | 2 |
| `quest_trigger/nested_equality` | base + astral | `$.steps[1].state.dispatches` | 0 | 1 |
| `body_health/head_state2_hp-64` | base | `$.steps[2].state.parts[0].cur_bits` | -64 (`0xc2800000`) | -63.99950027 (`0xc27fff7d`) |
| `body_health/head_state2_hp0` | base | `$.steps[2].state.hp_bits` | 64 (`0x42800000`) | 64.00050354 (`0x42800042`) |
| `body_health/head_state2_hp0.0009` | base | `$.steps[2].state.hp_bits` | 64.00090027 (`0x42800076`) | 64.00140381 (`0x428000b8`) |
| `body_health/head_state2_hp0.001` | base | `$.steps[1].state.parts[0].state` | 2 | 3 |
| `body_health/head_state2_hp16` | base | `$.steps[1].state.parts[0].state` | 2 | 3 |
| `body_health/head_state3_hp-64` | base | `$.steps[2].state.parts[0].cur_bits` | -64 (`0xc2800000`) | -63.99950027 (`0xc27fff7d`) |
| `body_health/head_state3_hp0` | base | `$.steps[2].state.hp_bits` | 64 (`0x42800000`) | 64.00050354 (`0x42800042`) |
| `body_health/head_state3_hp0.0009` | base | `$.steps[2].state.hp_bits` | 64.00090027 (`0x42800076`) | 64.00140381 (`0x428000b8`) |
| `body_health/head_state3_hp0.001` | base | `$.steps[2].state.hp_bits` | 64.00099945 (`0x42800083`) | 64.00150299 (`0x428000c5`) |
| `body_health/head_state3_hp16` | base | `$.steps[2].state.hp_bits` | 80 (`0x42a00000`) | 80.00050354 (`0x42a00042`) |
| `body_health/multiple_wounds` | base | `$.steps[1].state.hp_bits` | -51.00000381 (`0xc24c0001`) | -51 (`0xc24c0000`) |
| `body_health/seeded_000` | base | `$.steps[2].state.hp_bits` | -20.25598335 (`0xc1a20c41`) | -20.25598717 (`0xc1a20c43`) |
| `body_health/seeded_001` | base | `$.steps[1].state.parts[3].cur_bits` | -16.44324112 (`0xc1838bc2`) | -16.44323921 (`0xc1838bc1`) |
| `body_health/seeded_002` | base | `$.steps[2].state.hp_bits` | -105.8342819 (`0xc2d3ab27`) | -105.8342896 (`0xc2d3ab28`) |
| `body_health/seeded_003` | base | `$.steps[2].state.hp_bits` | -49.84621429 (`0xc2476286`) | -49.84621811 (`0xc2476287`) |
| `body_health/seeded_004` | base | `$.steps[2].state.hp_bits` | -19.67436218 (`0xc19d6518`) | -19.67436028 (`0xc19d6517`) |
| `body_health/seeded_005` | base | `$.steps[1].state.parts[4].cur_bits` | -1.586330414 (`0xbfcb0ce0`) | -1.586330056 (`0xbfcb0cdd`) |
| `body_health/seeded_006` | base | `$.steps[2].state.parts[1].cur_bits` | -12.74598503 (`0xc14bef8e`) | -12.74598598 (`0xc14bef8f`) |
| `body_health/seeded_008` | base | `$.steps[1].state.parts[0].cur_bits` | 17.49833298 (`0x418bfc96`) | 17.49833107 (`0x418bfc95`) |
| `body_health/seeded_009` | base | `$.steps[2].state.parts[0].cur_bits` | -41.08757401 (`0xc22459ad`) | -41.08757019 (`0xc22459ac`) |
| `body_health/seeded_010` | base | `$.steps[2].state.parts[5].cur_bits` | 29.46263123 (`0x41ebb378`) | 29.46262932 (`0x41ebb377`) |
| `body_health/seeded_011` | base | `$.steps[1].state.parts[1].cur_bits` | 2.430588245 (`0x401b8ec2`) | 2.430588007 (`0x401b8ec1`) |
| `quest_trigger/authored/zone2/VCheck#0#88/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#115/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#116/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#117/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#118/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#119/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#120/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#121/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#122/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#279/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#295/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |
| `quest_trigger/authored/zone19/VCheck#0#300/block0` | base | `$.steps[3].state.dispatches` | 2 | 1 |

## Authored trigger locations

These are condition replays with supplied actor positions, not proof of completed or blocked quests. At each listed upper corner the original dispatches the trigger body and the remake does not.

| Map/script | Tested upper corner | Original MOB SHA-256 |
|---|---|---|
| `zone2.mob` / `VCheck#0#88` | `[62.0, 155.0]` | `b6ad605534da2e0bd2418f2ebf3965d42ce0eaf00efbb476a8a5a6abb7d674b5` |
| `zone19.mob` / `VCheck#0#115` | `[361.0, 140.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#116` | `[396.0, 127.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#117` | `[383.0, 140.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#118` | `[414.11, 143.89]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#119` | `[370.89, 155.11]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#120` | `[414.0, 150.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#121` | `[389.89, 165.11]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#122` | `[412.0, 152.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#279` | `[113.0, 330.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#295` | `[147.0, 263.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
| `zone19.mob` / `VCheck#0#300` | `[260.0, 90.0]` | `cb84eaf58818f6cea27fe71f3da0d678abc3cf8118b544f3dc0a59b957b1ab68` |
