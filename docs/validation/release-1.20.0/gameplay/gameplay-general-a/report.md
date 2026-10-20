# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **error**.

Completed 75 of 75 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| animation | 3 | 3 | 0 | 0 | 83 |
| arena | 9 | 9 | 0 | 0 | 3400 |
| combat | 3 | 3 | 0 | 0 | 8468 |
| commands | 6 | 6 | 0 | 0 | 323 |
| creatures | 2 | 2 | 0 | 0 | 42 |
| dialogue | 5 | 4 | 0 | 1 | 53 |
| effects | 2 | 2 | 0 | 0 | 1757 |
| interface | 2 | 2 | 0 | 0 | 870 |
| inventory | 10 | 10 | 0 | 0 | 321 |
| party | 1 | 1 | 0 | 0 | 23 |
| pathing | 7 | 7 | 0 | 0 | 25142 |
| persistence | 5 | 5 | 0 | 0 | 53 |
| progression | 4 | 4 | 0 | 0 | 249 |
| quests | 8 | 8 | 0 | 0 | 171 |
| settings | 1 | 1 | 0 | 0 | 14939 |
| spells | 4 | 3 | 0 | 1 | 132 |
| stealth | 3 | 3 | 0 | 0 | 84 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `commands/direct_interactions` | passed | 8 | 0 | [log](tests/commands/direct_interactions/run.log) |
| `commands/exhausted_interactions` | passed | 192 | 0 | [log](tests/commands/exhausted_interactions/run.log) |
| `pathing/nav_topology` | passed | 7072 | 0 | [log](tests/pathing/nav_topology/run.log) |
| `pathing/nav_ray` | passed | 17835 | 0 | [log](tests/pathing/nav_ray/run.log) |
| `pathing/path_preview` | passed | 8 | 0 | [log](tests/pathing/path_preview/run.log) |
| `quests/quest_rewards_astral` | passed | 12 | 0 | [log](tests/quests/quest_rewards_astral/run.log) |
| `effects/creature_effect_attachments_astral` | passed | 1554 | 0 | [log](tests/effects/creature_effect_attachments_astral/run.log) |
| `stealth/patrol_escape_alerts` | passed | 14 | 0 | [log](tests/stealth/patrol_escape_alerts/run.log) |
| `spells/spell_stamina_wait` | passed | 47 | 0 | [log](tests/spells/spell_stamina_wait/run.log) |
| `spells/spell_requirements_coop` | error | 0 | 0 | [log](tests/spells/spell_requirements_coop/run.log) |
| `spells/spell_constructor_transactions` | passed | 52 | 0 | [log](tests/spells/spell_constructor_transactions/run.log) |
| `inventory/market_prices` | passed | 28 | 0 | [log](tests/inventory/market_prices/run.log) |
| `progression/training_reset` | passed | 99 | 0 | [log](tests/progression/training_reset/run.log) |
| `inventory/market_prices_astral` | passed | 25 | 0 | [log](tests/inventory/market_prices_astral/run.log) |
| `progression/training_reset_astral` | passed | 99 | 0 | [log](tests/progression/training_reset_astral/run.log) |
| `inventory/rune_loot` | passed | 15 | 0 | [log](tests/inventory/rune_loot/run.log) |
| `progression/training_coop` | passed | 27 | 0 | [log](tests/progression/training_coop/run.log) |
| `progression/fallen_party_xp` | passed | 24 | 0 | [log](tests/progression/fallen_party_xp/run.log) |
| `party/party_dependents` | passed | 23 | 0 | [log](tests/party/party_dependents/run.log) |
| `persistence/save_actor_refs` | passed | 14 | 0 | [log](tests/persistence/save_actor_refs/run.log) |
| `persistence/save_cast` | passed | 8 | 0 | [log](tests/persistence/save_cast/run.log) |
| `persistence/save_pet` | passed | 8 | 0 | [log](tests/persistence/save_pet/run.log) |
| `persistence/save_consumed_cast` | passed | 8 | 0 | [log](tests/persistence/save_consumed_cast/run.log) |
| `combat/direct_accuracy` | passed | 11 | 0 | [log](tests/combat/direct_accuracy/run.log) |
| `combat/body_records` | passed | 4029 | 0 | [log](tests/combat/body_records/run.log) |
| `quests/catacomb_mechanisms` | passed | 15 | 0 | [log](tests/quests/catacomb_mechanisms/run.log) |
| `commands/direct_spell_selection` | passed | 15 | 0 | [log](tests/commands/direct_spell_selection/run.log) |
| `spells/stamina_regen` | passed | 33 | 0 | [log](tests/spells/stamina_regen/run.log) |
| `effects/effect_tick_boundaries` | passed | 203 | 0 | [log](tests/effects/effect_tick_boundaries/run.log) |
| `inventory/belt_weight_astral` | passed | 72 | 0 | [log](tests/inventory/belt_weight_astral/run.log) |
| `inventory/enchanted_equipment` | passed | 37 | 0 | [log](tests/inventory/enchanted_equipment/run.log) |
| `inventory/enchanted_equipment_net` | passed | 13 | 0 | [log](tests/inventory/enchanted_equipment_net/run.log) |
| `inventory/coop_loot_grants` | passed | 28 | 0 | [log](tests/inventory/coop_loot_grants/run.log) |
| `inventory/recruited_equipment_net` | passed | 22 | 0 | [log](tests/inventory/recruited_equipment_net/run.log) |
| `inventory/pickup_messages` | passed | 5 | 0 | [log](tests/inventory/pickup_messages/run.log) |
| `dialogue/dialogue_approach` | passed | 18 | 0 | [log](tests/dialogue/dialogue_approach/run.log) |
| `dialogue/dialogue_highlights` | error | 0 | 0 | [log](tests/dialogue/dialogue_highlights/run.log) |
| `dialogue/ingos_lovkach` | passed | 15 | 0 | [log](tests/dialogue/ingos_lovkach/run.log) |
| `dialogue/elder_departure` | passed | 6 | 0 | [log](tests/dialogue/elder_departure/run.log) |
| `dialogue/nalo_rescue_entry` | passed | 14 | 0 | [log](tests/dialogue/nalo_rescue_entry/run.log) |
| `quests/tunnel_guard` | passed | 9 | 0 | [log](tests/quests/tunnel_guard/run.log) |
| `quests/shelter_kel` | passed | 33 | 0 | [log](tests/quests/shelter_kel/run.log) |
| `quests/zone7_arrival` | passed | 29 | 0 | [log](tests/quests/zone7_arrival/run.log) |
| `quests/lia_revenge_return` | passed | 13 | 0 | [log](tests/quests/lia_revenge_return/run.log) |
| `quests/lia_tomb_exit` | passed | 36 | 0 | [log](tests/quests/lia_tomb_exit/run.log) |
| `pathing/catacomb_capacity` | passed | 45 | 0 | [log](tests/pathing/catacomb_capacity/run.log) |
| `pathing/dynamic_navigation` | passed | 140 | 0 | [log](tests/pathing/dynamic_navigation/run.log) |
| `persistence/profile_save_seed` | passed | 15 | 0 | [log](tests/persistence/profile_save_seed/run.log) |
| `interface/wiki_quest_locales` | passed | 672 | 0 | [log](tests/interface/wiki_quest_locales/run.log) |
| `commands/first_person_actions` | passed | 64 | 0 | [log](tests/commands/first_person_actions/run.log) |
| `commands/direct_quest_bindings` | passed | 5 | 0 | [log](tests/commands/direct_quest_bindings/run.log) |
| `animation/direct_attack_stance` | passed | 39 | 0 | [log](tests/animation/direct_attack_stance/run.log) |
| `pathing/direct_movement` | passed | 33 | 0 | [log](tests/pathing/direct_movement/run.log) |
| `pathing/travel_reveal_astral` | passed | 9 | 0 | [log](tests/pathing/travel_reveal_astral/run.log) |
| `creatures/peasant_help_astral` | passed | 8 | 0 | [log](tests/creatures/peasant_help_astral/run.log) |
| `creatures/added_actor_tombstones` | passed | 34 | 0 | [log](tests/creatures/added_actor_tombstones/run.log) |
| `combat/wisp_native_callbacks` | passed | 4428 | 0 | [log](tests/combat/wisp_native_callbacks/run.log) |
| `arena/arena_economy` | passed | 590 | 0 | [log](tests/arena/arena_economy/run.log) |
| `arena/arena_flow` | passed | 235 | 0 | [log](tests/arena/arena_flow/run.log) |
| `arena/arena_live_shop` | passed | 120 | 0 | [log](tests/arena/arena_live_shop/run.log) |
| `arena/arena_result_health` | passed | 11 | 0 | [log](tests/arena/arena_result_health/run.log) |
| `arena/arena_sale_quotes` | passed | 254 | 0 | [log](tests/arena/arena_sale_quotes/run.log) |
| `arena/arena_species` | passed | 2154 | 0 | [log](tests/arena/arena_species/run.log) |
| `arena/arena_pve_lifecycle` | passed | 12 | 0 | [log](tests/arena/arena_pve_lifecycle/run.log) |
| `arena/arena_filtered_spells` | passed | 3 | 0 | [log](tests/arena/arena_filtered_spells/run.log) |
| `arena/arena_bot_planner` | passed | 21 | 0 | [log](tests/arena/arena_bot_planner/run.log) |
| `quests/shelter_kel_solo` | passed | 24 | 0 | [log](tests/quests/shelter_kel_solo/run.log) |
| `stealth/steal_lifecycle` | passed | 35 | 0 | [log](tests/stealth/steal_lifecycle/run.log) |
| `stealth/steal_lifecycle_astral` | passed | 35 | 0 | [log](tests/stealth/steal_lifecycle_astral/run.log) |
| `settings/option_localization_matrix` | passed | 14939 | 0 | [log](tests/settings/option_localization_matrix/run.log) |
| `inventory/camp_action_lifecycle_astral` | passed | 76 | 0 | [log](tests/inventory/camp_action_lifecycle_astral/run.log) |
| `interface/issue_ui_controls` | passed | 198 | 0 | [log](tests/interface/issue_ui_controls/run.log) |
| `animation/safe_zone_appearance` | passed | 11 | 0 | [log](tests/animation/safe_zone_appearance/run.log) |
| `animation/unit_presentation_timing` | passed | 33 | 0 | [log](tests/animation/unit_presentation_timing/run.log) |
| `commands/mine_worker_cadence` | passed | 39 | 0 | [log](tests/commands/mine_worker_cadence/run.log) |

### spells/spell_requirements_coop

Expected exactly one SPELL_REQUIREMENTS_COOP summary, found 0

- ERROR: Couldn't create an ENet host.
- ERROR: Scene fixture setup or wait failed

### dialogue/dialogue_highlights

Expected exactly one DIALOGUE_HIGHLIGHTS summary, found 0

- FAIL open highlight host
- ERROR: Couldn't create an ENet host.

## Scope

0 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
