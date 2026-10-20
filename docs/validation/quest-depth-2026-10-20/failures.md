# Quest progression failure disposition

**No unresolved failures in the qualified selection.** All 4,373 original comparisons match; all 52 selected remake configurations pass after the fixture correction below.

The previous VM (`db43e9bc`) produces 42 failures per campaign with the new inputs, in two fresh captures per side. Only `vm.gd` changes between the rollback control and fixed runtime. All 502 original observation hashes remain identical.

These 84 failing scenario/reference pairs represent repeated tests of several causes, not 84 distinct player bugs. Earlier adapter setup errors are excluded from this count.

| Campaign | Scenario | First differing field before fix | Original | Previous remake | Final |
|---|---|---|---|---|---|
| original | `quest_predicate/progression_item_bag_2_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| original | `quest_predicate/progression_item_bag_2_3_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| original | `quest_predicate/progression_item_bag_3_2_3_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| original | `quest_predicate/progression_WasLooted_missing` | `$.steps[0].state.truth` | `true` | `false` | Matches |
| original | `quest_program/sleep_-2` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_0` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_0.25` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_0.5` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_2.5` | `$.steps[2].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_12` | `$.steps[12].state.finished` | `true` | `false` | Matches |
| original | `quest_program/until_initial_1` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/until_initial_-1` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/until_initial_2` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/zero_delays_do_not_split_body` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| original | `quest_program/dynamic_delay_8` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| original | `quest_program/dynamic_delay_2` | `$.steps[2].state.finished` | `false` | `true` | Matches |
| original | `quest_program/dynamic_delay_12` | `$.steps[5].state.finished` | `true` | `false` | Matches |
| original | `quest_program/dynamic_delay_3` | `$.steps[3].state.finished` | `false` | `true` | Matches |
| original | `quest_program/sleep_sequence_003` | `$.steps[12].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_004` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_008` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_009` | `$.steps[0].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_010` | `$.steps[6].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_011` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_012` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_013` | `$.steps[4].state.values.phase` | `1077936128` | `1073741824` | Matches |
| original | `quest_program/sleep_sequence_014` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_015` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_016` | `$.steps[8].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_017` | `$.steps[2].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_018` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_019` | `$.steps[4].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_020` | `$.steps[7].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_022` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| original | `quest_program/sleep_sequence_023` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_024` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_025` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_028` | `$.steps[7].state.values.phase` | `1077936128` | `1073741824` | Matches |
| original | `quest_program/sleep_sequence_029` | `$.steps[5].state.values.phase` | `1077936128` | `1073741824` | Matches |
| original | `quest_program/sleep_sequence_032` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| original | `quest_program/sleep_sequence_033` | `$.steps[6].state.values.phase` | `1077936128` | `1073741824` | Matches |
| original | `quest_program/sleep_sequence_035` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_predicate/progression_item_bag_2_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| lost_in_astral | `quest_predicate/progression_item_bag_2_3_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| lost_in_astral | `quest_predicate/progression_item_bag_3_2_3_other_player` | `$.steps[0].state.truth` | `false` | `true` | Matches |
| lost_in_astral | `quest_predicate/progression_WasLooted_missing` | `$.steps[0].state.truth` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_-2` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_0` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_0.25` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_0.5` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_2.5` | `$.steps[2].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_12` | `$.steps[12].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/until_initial_1` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/until_initial_-1` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/until_initial_2` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/zero_delays_do_not_split_body` | `$.steps[0].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/dynamic_delay_8` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/dynamic_delay_2` | `$.steps[2].state.finished` | `false` | `true` | Matches |
| lost_in_astral | `quest_program/dynamic_delay_12` | `$.steps[5].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/dynamic_delay_3` | `$.steps[3].state.finished` | `false` | `true` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_003` | `$.steps[12].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_004` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_008` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_009` | `$.steps[0].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_010` | `$.steps[6].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_011` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_012` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_013` | `$.steps[4].state.values.phase` | `1077936128` | `1073741824` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_014` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_015` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_016` | `$.steps[8].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_017` | `$.steps[2].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_018` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_019` | `$.steps[4].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_020` | `$.steps[7].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_022` | `$.steps[3].state.finished` | `true` | `false` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_023` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_024` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_025` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_028` | `$.steps[7].state.values.phase` | `1077936128` | `1073741824` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_029` | `$.steps[5].state.values.phase` | `1077936128` | `1073741824` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_032` | `$.steps[1].state.observed_bits[0]` | `1065353216` | `0` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_033` | `$.steps[6].state.values.phase` | `1077936128` | `1073741824` | Matches |
| lost_in_astral | `quest_program/sleep_sequence_035` | `$.steps[0].state.values.phase` | `1065353216` | `0` | Matches |

## Regression fixture correction

`quests/story_coop_effects` initially completed 167 checks with two failed cooldown assertions. It advanced wall-clock time without running the intervening logic ticks. The original dispatcher counts actual runs. The fixture now advances all 25 acid-trap and 40 shrine ticks, adds no-early-resume assertions, and passes all 169 checks. The two original outcome assertions remain unchanged.

The complete initial failure messages, rerun source/log hashes, and latest result for each configuration are retained in [gameplay-results.json](gameplay-results.json).

Unknowns remain: native reward delivery, carried-unit quest inventory, full thread scheduling/spawning, original save serialization and complete campaign playthroughs are outside this selection.
