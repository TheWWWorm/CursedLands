# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **failed**.

Completed 75 of 75 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| animation | 3 | 3 | 0 | 0 | 529 |
| arena | 9 | 9 | 0 | 0 | 4343 |
| combat | 1 | 1 | 0 | 0 | 584 |
| commands | 7 | 7 | 0 | 0 | 9752 |
| creatures | 4 | 4 | 0 | 0 | 13132 |
| dialogue | 6 | 6 | 0 | 0 | 195 |
| effects | 1 | 1 | 0 | 0 | 186 |
| interface | 1 | 1 | 0 | 0 | 2883 |
| inventory | 13 | 12 | 1 | 0 | 3742 |
| party | 2 | 2 | 0 | 0 | 34 |
| pathing | 7 | 7 | 0 | 0 | 18107 |
| persistence | 6 | 6 | 0 | 0 | 99 |
| progression | 1 | 1 | 0 | 0 | 96 |
| quests | 8 | 8 | 0 | 0 | 776 |
| settings | 2 | 2 | 0 | 0 | 54 |
| spells | 4 | 4 | 0 | 0 | 27749 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `commands/command_retry` | passed | 29 | 0 | [log](tests/commands/command_retry/run.log) |
| `pathing/nav_turn_native` | passed | 2997 | 0 | [log](tests/pathing/nav_turn_native/run.log) |
| `pathing/nav_dynamic_topology` | passed | 11102 | 0 | [log](tests/pathing/nav_dynamic_topology/run.log) |
| `pathing/nav_relocation_bounds` | passed | 3892 | 0 | [log](tests/pathing/nav_relocation_bounds/run.log) |
| `pathing/direct_passages` | passed | 53 | 0 | [log](tests/pathing/direct_passages/run.log) |
| `animation/creature_weapon_animations_astral` | passed | 328 | 0 | [log](tests/animation/creature_weapon_animations_astral/run.log) |
| `effects/creature_projectile_origins_astral` | passed | 186 | 0 | [log](tests/effects/creature_projectile_origins_astral/run.log) |
| `quests/story_guard_escape` | passed | 11 | 0 | [log](tests/quests/story_guard_escape/run.log) |
| `spells/spell_stamina_network` | passed | 14 | 0 | [log](tests/spells/spell_stamina_network/run.log) |
| `spells/spell_requirements_coop_astral` | passed | 17 | 0 | [log](tests/spells/spell_requirements_coop_astral/run.log) |
| `spells/shop_spells` | passed | 13680 | 0 | [log](tests/spells/shop_spells/run.log) |
| `inventory/gipat_infusions` | passed | 36 | 0 | [log](tests/inventory/gipat_infusions/run.log) |
| `spells/shop_spells_astral` | passed | 14038 | 0 | [log](tests/spells/shop_spells_astral/run.log) |
| `inventory/gipat_infusions_astral` | passed | 35 | 0 | [log](tests/inventory/gipat_infusions_astral/run.log) |
| `inventory/camp_transactions` | passed | 53 | 0 | [log](tests/inventory/camp_transactions/run.log) |
| `inventory/special_equipment` | passed | 493 | 0 | [log](tests/inventory/special_equipment/run.log) |
| `progression/xp_distribution` | passed | 96 | 0 | [log](tests/progression/xp_distribution/run.log) |
| `party/pet_waiting` | passed | 13 | 0 | [log](tests/party/pet_waiting/run.log) |
| `persistence/save_state_fields` | passed | 18 | 0 | [log](tests/persistence/save_state_fields/run.log) |
| `persistence/save_frozen_clock` | passed | 6 | 0 | [log](tests/persistence/save_frozen_clock/run.log) |
| `persistence/save_taming` | passed | 18 | 0 | [log](tests/persistence/save_taming/run.log) |
| `persistence/save_boundaries` | passed | 30 | 0 | [log](tests/persistence/save_boundaries/run.log) |
| `persistence/load_spell_boundary` | passed | 12 | 0 | [log](tests/persistence/load_spell_boundary/run.log) |
| `combat/archer_range` | passed | 584 | 0 | [log](tests/combat/archer_range/run.log) |
| `creatures/unit_simulation_state` | passed | 11824 | 0 | [log](tests/creatures/unit_simulation_state/run.log) |
| `quests/story_coop_dragon` | passed | 40 | 0 | [log](tests/quests/story_coop_dragon/run.log) |
| `commands/direct_release_aim` | passed | 57 | 0 | [log](tests/commands/direct_release_aim/run.log) |
| `inventory/item_instance_matrix` | passed | 1370 | 0 | [log](tests/inventory/item_instance_matrix/run.log) |
| `inventory/item_instance_matrix_astral` | passed | 1370 | 0 | [log](tests/inventory/item_instance_matrix_astral/run.log) |
| `inventory/belt_weight` | passed | 72 | 0 | [log](tests/inventory/belt_weight/run.log) |
| `inventory/camp_grants` | passed | 130 | 0 | [log](tests/inventory/camp_grants/run.log) |
| `inventory/enchanted_equipment_astral` | passed | 37 | 0 | [log](tests/inventory/enchanted_equipment_astral/run.log) |
| `inventory/enchanted_equipment_net_astral` | passed | 13 | 0 | [log](tests/inventory/enchanted_equipment_net_astral/run.log) |
| `inventory/coop_loot_network` | failed | 41 | 1 | [log](tests/inventory/coop_loot_network/run.log) |
| `inventory/recruited_equipment_net_astral` | passed | 16 | 0 | [log](tests/inventory/recruited_equipment_net_astral/run.log) |
| `dialogue/authored_village_talk` | passed | 90 | 0 | [log](tests/dialogue/authored_village_talk/run.log) |
| `dialogue/dialogue_feedback` | passed | 16 | 0 | [log](tests/dialogue/dialogue_feedback/run.log) |
| `dialogue/ingos_guards` | passed | 15 | 0 | [log](tests/dialogue/ingos_guards/run.log) |
| `dialogue/gipat_captive_dialogue` | passed | 27 | 0 | [log](tests/dialogue/gipat_captive_dialogue/run.log) |
| `dialogue/shaina_disguise_entry` | passed | 26 | 0 | [log](tests/dialogue/shaina_disguise_entry/run.log) |
| `quests/shelter_departure` | passed | 11 | 0 | [log](tests/quests/shelter_departure/run.log) |
| `quests/slave_camp_escape` | passed | 31 | 0 | [log](tests/quests/slave_camp_escape/run.log) |
| `quests/island_return` | passed | 39 | 0 | [log](tests/quests/island_return/run.log) |
| `quests/lia_slave_lists_return` | passed | 21 | 0 | [log](tests/quests/lia_slave_lists_return/run.log) |
| `pathing/client_placement` | passed | 18 | 0 | [log](tests/pathing/client_placement/run.log) |
| `pathing/catacomb_capacity_net` | passed | 36 | 0 | [log](tests/pathing/catacomb_capacity_net/run.log) |
| `settings/single_player_rules` | passed | 52 | 0 | [log](tests/settings/single_player_rules/run.log) |
| `settings/audio_bus_routes` | passed | 2 | 0 | [log](tests/settings/audio_bus_routes/run.log) |
| `persistence/profile_save_seed_astral` | passed | 15 | 0 | [log](tests/persistence/profile_save_seed_astral/run.log) |
| `interface/wiki_quest_locales_astral` | passed | 2883 | 0 | [log](tests/interface/wiki_quest_locales_astral/run.log) |
| `commands/direct_aim_selection` | passed | 17 | 0 | [log](tests/commands/direct_aim_selection/run.log) |
| `commands/touch_unit_picking` | passed | 1352 | 0 | [log](tests/commands/touch_unit_picking/run.log) |
| `party/revive_camera` | passed | 21 | 0 | [log](tests/party/revive_camera/run.log) |
| `pathing/travel_reveal` | passed | 9 | 0 | [log](tests/pathing/travel_reveal/run.log) |
| `creatures/peasant_help` | passed | 8 | 0 | [log](tests/creatures/peasant_help/run.log) |
| `creatures/added_actor_lifetime` | passed | 17 | 0 | [log](tests/creatures/added_actor_lifetime/run.log) |
| `creatures/registry_queries` | passed | 1283 | 0 | [log](tests/creatures/registry_queries/run.log) |
| `arena/arena_alliances` | passed | 602 | 0 | [log](tests/arena/arena_alliances/run.log) |
| `arena/arena_elimination_places` | passed | 12 | 0 | [log](tests/arena/arena_elimination_places/run.log) |
| `arena/arena_formation` | passed | 22 | 0 | [log](tests/arena/arena_formation/run.log) |
| `arena/arena_recruitment` | passed | 2006 | 0 | [log](tests/arena/arena_recruitment/run.log) |
| `arena/arena_roster` | passed | 1515 | 0 | [log](tests/arena/arena_roster/run.log) |
| `arena/arena_solo_recovery` | passed | 8 | 0 | [log](tests/arena/arena_solo_recovery/run.log) |
| `arena/arena_tournament` | passed | 157 | 0 | [log](tests/arena/arena_tournament/run.log) |
| `arena/arena_battle_limits` | passed | 9 | 0 | [log](tests/arena/arena_battle_limits/run.log) |
| `arena/arena_damage_retention` | passed | 12 | 0 | [log](tests/arena/arena_damage_retention/run.log) |
| `dialogue/gipat_captive_dialogue_hermit_first` | passed | 21 | 0 | [log](tests/dialogue/gipat_captive_dialogue_hermit_first/run.log) |
| `quests/shelter_kel_named` | passed | 33 | 0 | [log](tests/quests/shelter_kel_named/run.log) |
| `quests/side_quest_lifecycle` | passed | 590 | 0 | [log](tests/quests/side_quest_lifecycle/run.log) |
| `inventory/camp_action_lifecycle` | passed | 76 | 0 | [log](tests/inventory/camp_action_lifecycle/run.log) |
| `commands/travel_command_lifecycle` | passed | 21 | 0 | [log](tests/commands/travel_command_lifecycle/run.log) |
| `commands/travel_command_lifecycle_astral` | passed | 21 | 0 | [log](tests/commands/travel_command_lifecycle_astral/run.log) |
| `animation/equipment_continuity` | passed | 56 | 0 | [log](tests/animation/equipment_continuity/run.log) |
| `commands/worker_clock` | passed | 8255 | 0 | [log](tests/commands/worker_clock/run.log) |
| `animation/network_render_clock` | passed | 145 | 0 | [log](tests/animation/network_render_clock/run.log) |

### inventory/coop_loot_network

Failed assertions:

- FAIL each player receives one corpse pickup notice at 1.0x race=false

## Scope

0 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
