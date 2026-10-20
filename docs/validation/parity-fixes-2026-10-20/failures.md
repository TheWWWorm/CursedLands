# Failure disposition

Outstanding original-comparison failures: **0 of 3,511 scenarios**.

Outstanding failures in the selected gameplay regressions: **0 of 54
configurations**, using each configuration's latest qualified result.
One fixture teardown error in the initial run was corrected and passed twice;
its original error and reruns remain in [gameplay-results.json](gameplay-results.json).

All 72 previously reported cases and 101 newly exposed failing cases now match. Counts are scenario/reference pairs, not distinct player bugs.

Final captures retain every previous scenario and exactly the same original observation hashes. No tolerance was widened and no failing case was excluded.

| Reference | Phase | Scenario | First differing field | Original | Earlier remake | Final |
|---|---|---|---|---|---|---|
| original | previously_reported | `quest_predicate/IsEqual_3` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/IsEqual_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/IsEqual_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/nested_rounded_sum` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | previously_reported | `quest_predicate/nested_division` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/string_2` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/string_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/rectangle_10_10` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | previously_reported | `quest_predicate/rectangle_10_5` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | previously_reported | `quest_predicate/rectangle_5_10` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | previously_reported | `quest_predicate/rectangle_reversed` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_predicate/rectangle_degenerate` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | previously_reported | `quest_predicate/distance_point_[0.1, 0.2]` | `$.steps[0].state.value_bits` | `1046804782` | `1046804783` | match |
| original | previously_reported | `quest_predicate/distance_units_[0.1, 0.2]` | `$.steps[0].state.value_bits` | `1046804782` | `1046804783` | match |
| original | previously_reported | `quest_predicate/distance_missing_unit` | `$.steps[0].state.value_bits` | `1900671690` | `1203982208` | match |
| original | previously_reported | `quest_predicate/distance_missing_point` | `$.steps[0].state.value_bits` | `1900671690` | `1203982208` | match |
| original | previously_reported | `quest_predicate/missing_distance_large_threshold` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | previously_reported | `quest_trigger/enter_leave_reenter_rectangle` | `$.steps[3].state.dispatches` | `3` | `2` | match |
| original | previously_reported | `quest_trigger/nested_equality` | `$.steps[1].state.dispatches` | `0` | `1` | match |
| original | previously_reported | `body_health/head_state2_hp-64` | `$.steps[2].state.parts[0].cur_bits` | `3263168512` | `3263168381` | match |
| original | previously_reported | `body_health/head_state2_hp0` | `$.steps[2].state.hp_bits` | `1115684864` | `1115684930` | match |
| original | previously_reported | `body_health/head_state2_hp0.0009` | `$.steps[2].state.hp_bits` | `1115684982` | `1115685048` | match |
| original | previously_reported | `body_health/head_state2_hp0.001` | `$.steps[1].state.parts[0].state` | `2` | `3` | match |
| original | previously_reported | `body_health/head_state2_hp16` | `$.steps[1].state.parts[0].state` | `2` | `3` | match |
| original | previously_reported | `body_health/head_state3_hp-64` | `$.steps[2].state.parts[0].cur_bits` | `3263168512` | `3263168381` | match |
| original | previously_reported | `body_health/head_state3_hp0` | `$.steps[2].state.hp_bits` | `1115684864` | `1115684930` | match |
| original | previously_reported | `body_health/head_state3_hp0.0009` | `$.steps[2].state.hp_bits` | `1115684982` | `1115685048` | match |
| original | previously_reported | `body_health/head_state3_hp0.001` | `$.steps[2].state.hp_bits` | `1115684995` | `1115685061` | match |
| original | previously_reported | `body_health/head_state3_hp16` | `$.steps[2].state.hp_bits` | `1117782016` | `1117782082` | match |
| original | previously_reported | `body_health/multiple_wounds` | `$.steps[1].state.hp_bits` | `3259760641` | `3259760640` | match |
| original | previously_reported | `body_health/seeded_000` | `$.steps[2].state.hp_bits` | `3248622657` | `3248622659` | match |
| original | previously_reported | `body_health/seeded_001` | `$.steps[1].state.parts[3].cur_bits` | `3246623682` | `3246623681` | match |
| original | previously_reported | `body_health/seeded_002` | `$.steps[2].state.hp_bits` | `3268651815` | `3268651816` | match |
| original | previously_reported | `body_health/seeded_003` | `$.steps[2].state.hp_bits` | `3259458182` | `3259458183` | match |
| original | previously_reported | `body_health/seeded_004` | `$.steps[2].state.hp_bits` | `3248317720` | `3248317719` | match |
| original | previously_reported | `body_health/seeded_005` | `$.steps[1].state.parts[4].cur_bits` | `3217755360` | `3217755357` | match |
| original | previously_reported | `body_health/seeded_006` | `$.steps[2].state.parts[1].cur_bits` | `3242979214` | `3242979215` | match |
| original | previously_reported | `body_health/seeded_008` | `$.steps[1].state.parts[0].cur_bits` | `1099693206` | `1099693205` | match |
| original | previously_reported | `body_health/seeded_009` | `$.steps[2].state.parts[0].cur_bits` | `3257162157` | `3257162156` | match |
| original | previously_reported | `body_health/seeded_010` | `$.steps[2].state.parts[5].cur_bits` | `1105965944` | `1105965943` | match |
| original | previously_reported | `body_health/seeded_011` | `$.steps[1].state.parts[1].cur_bits` | `1075547842` | `1075547841` | match |
| original | previously_reported | `quest_trigger/authored/zone2/VCheck#0#88/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#115/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#116/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#117/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#118/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#119/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#120/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#121/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#122/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#279/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#295/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| original | previously_reported | `quest_trigger/authored/zone19/VCheck#0#300/block0` | `$.steps[3].state.dispatches` | `2` | `1` | match |
| lost_in_astral | previously_reported | `quest_predicate/IsEqual_3` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/IsEqual_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/IsEqual_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/nested_rounded_sum` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | previously_reported | `quest_predicate/nested_division` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/string_2` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/string_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/rectangle_10_10` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | previously_reported | `quest_predicate/rectangle_10_5` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | previously_reported | `quest_predicate/rectangle_5_10` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | previously_reported | `quest_predicate/rectangle_reversed` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_predicate/rectangle_degenerate` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | previously_reported | `quest_predicate/distance_point_[0.1, 0.2]` | `$.steps[0].state.value_bits` | `1046804782` | `1046804783` | match |
| lost_in_astral | previously_reported | `quest_predicate/distance_units_[0.1, 0.2]` | `$.steps[0].state.value_bits` | `1046804782` | `1046804783` | match |
| lost_in_astral | previously_reported | `quest_predicate/distance_missing_unit` | `$.steps[0].state.value_bits` | `1900671690` | `1203982208` | match |
| lost_in_astral | previously_reported | `quest_predicate/distance_missing_point` | `$.steps[0].state.value_bits` | `1900671690` | `1203982208` | match |
| lost_in_astral | previously_reported | `quest_predicate/missing_distance_large_threshold` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | previously_reported | `quest_trigger/enter_leave_reenter_rectangle` | `$.steps[3].state.dispatches` | `3` | `2` | match |
| lost_in_astral | previously_reported | `quest_trigger/nested_equality` | `$.steps[1].state.dispatches` | `0` | `1` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_empty_Any_constant_one` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_empty_Any_constant_two` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_empty_Every_constant_zero` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_empty_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_0_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_1_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_0_1_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_1_0_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| lost_in_astral | newly_exposed | `quest_predicate/group_2_1_0_Every_constant_two` | `$.steps[0].state.value_bits` | `1073741824` | `1065353216` | match |
| original | newly_exposed | `quest_predicate/area_rectangle_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_rectangle_2` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_rectangle_3` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_reversed_x_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_reversed_x_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_reversed_x_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_reversed_y_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_reversed_y_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_reversed_y_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_point_0` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_circle_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_circle_6` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_negative_circle_0` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_negative_circle_5` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_negative_circle_7` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_zero_circle_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_union_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_union_6` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_union_9` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_000_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_003_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_004_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_005_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_006_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_007_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_009_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_010_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_011_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_014_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_015_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_016_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_017_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_017_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_018_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_019_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_020_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_021_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/area_fractional_corner_023_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_rectangle_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_rectangle_2` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_rectangle_3` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_x_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_x_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_x_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_y_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_y_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_reversed_y_5` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_point_0` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_circle_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_circle_6` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_negative_circle_0` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_negative_circle_5` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_negative_circle_7` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_zero_circle_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_union_4` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_union_6` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_union_9` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_000_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_003_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_004_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_005_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_006_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_007_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_009_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_010_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_011_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_014_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_015_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_016_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_017_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_017_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_018_1` | `$.steps[0].state.truth` | `True` | `False` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_019_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_020_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_021_0` | `$.steps[0].state.truth` | `False` | `True` | match |
| lost_in_astral | newly_exposed | `quest_predicate/area_fractional_corner_023_1` | `$.steps[0].state.truth` | `False` | `True` | match |
| original | newly_exposed | `quest_predicate/distance_translated_004` | `$.steps[0].state.value_bits` | `1175374317` | `1175374316` | match |
| original | newly_exposed | `quest_predicate/distance_translated_012` | `$.steps[0].state.value_bits` | `1170441877` | `1170441876` | match |
| original | newly_exposed | `quest_predicate/distance_translated_031` | `$.steps[0].state.value_bits` | `1181241429` | `1181241428` | match |
| original | newly_exposed | `quest_predicate/distance_translated_036` | `$.steps[0].state.value_bits` | `1170828029` | `1170828028` | match |
| original | newly_exposed | `quest_predicate/distance_translated_041` | `$.steps[0].state.value_bits` | `1176077119` | `1176077120` | match |
| original | newly_exposed | `quest_predicate/distance_translated_043` | `$.steps[0].state.value_bits` | `1179084550` | `1179084549` | match |
| original | newly_exposed | `quest_predicate/distance_translated_046` | `$.steps[0].state.value_bits` | `1186586135` | `1186586134` | match |
| original | newly_exposed | `quest_predicate/distance_translated_047` | `$.steps[0].state.value_bits` | `1173855309` | `1173855308` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_004` | `$.steps[0].state.value_bits` | `1175374317` | `1175374316` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_012` | `$.steps[0].state.value_bits` | `1170441877` | `1170441876` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_031` | `$.steps[0].state.value_bits` | `1181241429` | `1181241428` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_036` | `$.steps[0].state.value_bits` | `1170828029` | `1170828028` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_041` | `$.steps[0].state.value_bits` | `1176077119` | `1176077120` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_043` | `$.steps[0].state.value_bits` | `1179084550` | `1179084549` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_046` | `$.steps[0].state.value_bits` | `1186586135` | `1186586134` | match |
| lost_in_astral | newly_exposed | `quest_predicate/distance_translated_047` | `$.steps[0].state.value_bits` | `1173855309` | `1173855308` | match |

Bit-field values are unsigned IEEE-754 float32 encodings. See the JSON receipt for exact capture locations and hashes. These results cover the declared inputs and supplied boundaries; untested campaign execution remains unknown.
