# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **error**.

Completed 259 of 259 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| animation | 9 | 9 | 0 | 0 | 2694 |
| arena | 21 | 20 | 1 | 0 | 8338 |
| combat | 4 | 4 | 0 | 0 | 9052 |
| commands | 14 | 14 | 0 | 0 | 2764 |
| coop | 48 | 46 | 0 | 2 | 1667 |
| creatures | 12 | 12 | 0 | 0 | 25192 |
| dialogue | 11 | 11 | 0 | 0 | 290 |
| effects | 11 | 11 | 0 | 0 | 73698 |
| interface | 9 | 8 | 0 | 1 | 3724 |
| inventory | 26 | 26 | 0 | 0 | 4323 |
| network | 3 | 3 | 0 | 0 | 251 |
| party | 3 | 3 | 0 | 0 | 57 |
| pathing | 14 | 14 | 0 | 0 | 43249 |
| persistence | 12 | 12 | 0 | 0 | 195 |
| progression | 5 | 5 | 0 | 0 | 345 |
| quests | 27 | 27 | 0 | 0 | 1438 |
| settings | 14 | 14 | 0 | 0 | 15564 |
| spells | 8 | 8 | 0 | 0 | 27898 |
| stealth | 8 | 8 | 0 | 0 | 3116 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `quests/script_dead_predicates` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/script_dead_predicates/run.log) |
| `quests/script_hero_references` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/script_hero_references/run.log) |
| `quests/story_coop_predicates` | passed | 101 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/story_coop_predicates/run.log) |
| `quests/story_coop_traps` | passed | 55 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/story_coop_traps/run.log) |
| `quests/story_coop_effects` | passed | 167 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/story_coop_effects/run.log) |
| `quests/quest_carriers` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/quest_carriers/run.log) |
| `quests/quest_inventory_lifecycle` | passed | 20 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/quest_inventory_lifecycle/run.log) |
| `quests/quest_rewards` | passed | 4 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/quest_rewards/run.log) |
| `quests/quest_actor_removal` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/quest_actor_removal/run.log) |
| `quests/catacomb_group_lever` | passed | 26 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/catacomb_group_lever/run.log) |
| `quests/lever_transition_save` | passed | 59 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/lever_transition_save/run.log) |
| `creatures/ai_activity_health` | passed | 45 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/ai_activity_health/run.log) |
| `creatures/ai_activity_senses` | passed | 7340 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/ai_activity_senses/run.log) |
| `creatures/ai_live_eligibility` | passed | 4589 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/ai_live_eligibility/run.log) |
| `creatures/ai_reaction_recipients` | passed | 7 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/ai_reaction_recipients/run.log) |
| `creatures/creature_alerts` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/creature_alerts/run.log) |
| `creatures/creature_damage` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/creatures/creature_damage/run.log) |
| `animation/creature_weapon_animations` | passed | 196 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/creature_weapon_animations/run.log) |
| `animation/direct_gait_continuity` | passed | 1920 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/direct_gait_continuity/run.log) |
| `animation/direct_moving_attacks` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/direct_moving_attacks/run.log) |
| `animation/direct_moving_casts` | passed | 50 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/direct_moving_casts/run.log) |
| `animation/paused_spawn_pose` | passed | 42 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/paused_spawn_pose/run.log) |
| `animation/paused_load_pose` | passed | 50 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/paused_load_pose/run.log) |
| `animation/dialogue_poses` | passed | 54 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/dialogue_poses/run.log) |
| `effects/creature_effect_attachments` | passed | 1739 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/creature_effect_attachments/run.log) |
| `effects/creature_projectile_origins` | passed | 186 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/projectile-fixture-qualification/tests/effects/creature_projectile_origins/run.log) |
| `effects/particle_delay_lifetime` | passed | 57 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/particle_delay_lifetime/run.log) |
| `effects/repeated_spells` | passed | 86 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/repeated_spells/run.log) |
| `effects/fire_particles` | passed | 43389 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/fire_particles/run.log) |
| `effects/tornado_particles` | passed | 26244 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/tornado_particles/run.log) |
| `effects/healing_presentation` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/healing_presentation/run.log) |
| `effects/delayed_cast_lifetime` | passed | 32 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/delayed_cast_lifetime/run.log) |
| `stealth/stealth_effects` | passed | 19 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/stealth/stealth_effects/run.log) |
| `stealth/stealth_effects_net` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/stealth/stealth_effects_net/run.log) |
| `stealth/perception_batch` | passed | 2857 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/stealth/perception_batch/run.log) |
| `stealth/unit_visibility` | passed | 72 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/summary-format-qualification/tests/stealth/unit_visibility/run.log) |
| `stealth/hidden_presentation` | passed | 69 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/stealth/hidden_presentation/run.log) |
| `commands/combat_inputs` | passed | 918 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/commands/combat_inputs/run.log) |
| `commands/direct_command_priority` | passed | 37 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/commands/direct_command_priority/run.log) |
| `commands/issue_campaign_orders` | passed | 28 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/commands/issue_campaign_orders/run.log) |
| `commands/direct_interactions` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/command-fixture-qualification/tests/commands/direct_interactions/run.log) |
| `commands/command_retry` | passed | 29 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/commands/command_retry/run.log) |
| `commands/exhausted_interactions` | passed | 192 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/command-fixture-qualification/tests/commands/exhausted_interactions/run.log) |
| `pathing/nav_turn_native` | passed | 2997 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/pathing/nav_turn_native/run.log) |
| `pathing/nav_topology` | passed | 7072 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/pathing/nav_topology/run.log) |
| `pathing/nav_dynamic_topology` | passed | 11102 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/pathing/nav_dynamic_topology/run.log) |
| `pathing/nav_ray` | passed | 17835 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/pathing/nav_ray/run.log) |
| `pathing/nav_relocation_bounds` | passed | 3892 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/summary-format-qualification/tests/pathing/nav_relocation_bounds/run.log) |
| `pathing/path_preview` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/pathing/path_preview/run.log) |
| `pathing/direct_passages` | passed | 53 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/summary-format-qualification/tests/pathing/direct_passages/run.log) |
| `quests/quest_rewards_astral` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/quest_rewards_astral/run.log) |
| `animation/creature_weapon_animations_astral` | passed | 328 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/animation/creature_weapon_animations_astral/run.log) |
| `effects/creature_effect_attachments_astral` | passed | 1554 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/effects/creature_effect_attachments_astral/run.log) |
| `effects/creature_projectile_origins_astral` | passed | 186 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/projectile-fixture-qualification/tests/effects/creature_projectile_origins_astral/run.log) |
| `stealth/patrol_escape_alerts` | passed | 14 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/stealth/patrol_escape_alerts/run.log) |
| `quests/story_guard_escape` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/gameplay-qualification/tests/quests/story_guard_escape/run.log) |
| `spells/spell_stamina_wait` | passed | 47 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/spell_stamina_wait/run.log) |
| `spells/spell_stamina_network` | passed | 14 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/spells/spell_stamina_network/run.log) |
| `spells/spell_requirements_coop` | passed | 17 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/spell_requirements_coop/run.log) |
| `spells/spell_requirements_coop_astral` | passed | 17 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/spell_requirements_coop_astral/run.log) |
| `spells/spell_constructor_transactions` | passed | 52 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/spells/spell_constructor_transactions/run.log) |
| `spells/shop_spells` | passed | 13680 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/shop_spells/run.log) |
| `inventory/market_prices` | passed | 28 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/market_prices/run.log) |
| `inventory/gipat_infusions` | passed | 36 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/gipat_infusions/run.log) |
| `progression/training_reset` | passed | 99 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-counts/tests/progression/training_reset/run.log) |
| `spells/shop_spells_astral` | passed | 14038 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/shop_spells_astral/run.log) |
| `inventory/market_prices_astral` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/market_prices_astral/run.log) |
| `inventory/gipat_infusions_astral` | passed | 35 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/gipat_infusions_astral/run.log) |
| `progression/training_reset_astral` | passed | 99 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-counts/tests/progression/training_reset_astral/run.log) |
| `inventory/camp_transactions` | passed | 53 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/inventory/camp_transactions/run.log) |
| `inventory/rune_loot` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/rune_loot/run.log) |
| `inventory/special_equipment` | passed | 493 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/inventory/special_equipment/run.log) |
| `progression/training_coop` | passed | 27 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/progression/training_coop/run.log) |
| `progression/xp_distribution` | passed | 96 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/progression/xp_distribution/run.log) |
| `progression/fallen_party_xp` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/progression/fallen_party_xp/run.log) |
| `party/pet_waiting` | passed | 13 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/party/pet_waiting/run.log) |
| `party/party_dependents` | passed | 23 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/party/party_dependents/run.log) |
| `persistence/save_state_fields` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_state_fields/run.log) |
| `persistence/save_actor_refs` | passed | 14 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_actor_refs/run.log) |
| `persistence/save_frozen_clock` | passed | 6 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_frozen_clock/run.log) |
| `persistence/save_cast` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_cast/run.log) |
| `persistence/save_taming` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_taming/run.log) |
| `persistence/save_pet` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_pet/run.log) |
| `persistence/save_boundaries` | passed | 30 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_boundaries/run.log) |
| `persistence/save_consumed_cast` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/save_consumed_cast/run.log) |
| `persistence/load_spell_boundary` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/persistence/load_spell_boundary/run.log) |
| `combat/direct_accuracy` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/combat/direct_accuracy/run.log) |
| `combat/archer_range` | passed | 584 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-fixtures/tests/combat/archer_range/run.log) |
| `combat/body_records` | passed | 4029 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-fixtures/tests/combat/body_records/run.log) |
| `creatures/unit_simulation_state` | passed | 11824 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-fixtures/tests/creatures/unit_simulation_state/run.log) |
| `network/snapshot_codec` | passed | 209 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/network/snapshot_codec/run.log) |
| `network/snapshot_recovery` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-fixtures/tests/network/snapshot_recovery/run.log) |
| `network/campaign_state_transport` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/network/campaign_state_transport/run.log) |
| `quests/catacomb_mechanisms` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/quests/catacomb_mechanisms/run.log) |
| `quests/story_coop_dragon` | passed | 40 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/quests/story_coop_dragon/run.log) |
| `commands/direct_spell_selection` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/commands/direct_spell_selection/run.log) |
| `commands/direct_release_aim` | passed | 57 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/commands/direct_release_aim/run.log) |
| `spells/stamina_regen` | passed | 33 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-first/tests/spells/stamina_regen/run.log) |
| `inventory/item_instance_matrix` | passed | 1370 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-matrix/tests/inventory/item_instance_matrix/run.log) |
| `inventory/item_instance_matrix_astral` | passed | 1370 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-matrix/tests/inventory/item_instance_matrix_astral/run.log) |
| `effects/effect_tick_boundaries` | passed | 203 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/expanded-matrix/tests/effects/effect_tick_boundaries/run.log) |
| `inventory/belt_weight` | passed | 72 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/belt_weight/run.log) |
| `inventory/belt_weight_astral` | passed | 72 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/belt_weight_astral/run.log) |
| `inventory/camp_grants` | passed | 130 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-new/tests/inventory/camp_grants/run.log) |
| `inventory/enchanted_equipment` | passed | 37 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/enchanted_equipment/run.log) |
| `inventory/enchanted_equipment_astral` | passed | 37 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/enchanted_equipment_astral/run.log) |
| `inventory/enchanted_equipment_net` | passed | 13 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/enchanted_equipment_net/run.log) |
| `inventory/enchanted_equipment_net_astral` | passed | 13 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/enchanted_equipment_net_astral/run.log) |
| `inventory/coop_trade` | passed | 38 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/coop_trade/run.log) |
| `inventory/coop_loot_grants` | passed | 28 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/coop_loot_grants/run.log) |
| `inventory/coop_loot_network` | passed | 41 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/coop_loot_network/run.log) |
| `inventory/recruited_equipment_net` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/inventory/recruited_equipment_net/run.log) |
| `inventory/recruited_equipment_net_astral` | passed | 16 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/inventory/recruited_equipment_net_astral/run.log) |
| `inventory/pickup_messages` | passed | 5 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/pickup_messages/run.log) |
| `inventory/camp_inventory_ui` | passed | 109 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/camp_inventory_ui/run.log) |
| `inventory/camp_inventory_ui_astral` | passed | 113 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/inventory/camp_inventory_ui_astral/run.log) |
| `dialogue/authored_village_talk` | passed | 90 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/authored_village_talk/run.log) |
| `dialogue/dialogue_approach` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/dialogue_approach/run.log) |
| `dialogue/dialogue_feedback` | passed | 16 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/dialogue_feedback/run.log) |
| `dialogue/dialogue_highlights` | passed | 42 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/dialogue_highlights/run.log) |
| `dialogue/ingos_guards` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/ingos_guards/run.log) |
| `dialogue/ingos_lovkach` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/ingos_lovkach/run.log) |
| `dialogue/elder_departure` | passed | 6 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/elder_departure/run.log) |
| `dialogue/gipat_captive_dialogue` | passed | 27 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/gipat_captive_dialogue/run.log) |
| `dialogue/nalo_rescue_entry` | passed | 14 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/dialogue/nalo_rescue_entry/run.log) |
| `dialogue/shaina_disguise_entry` | passed | 26 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/dialogue/shaina_disguise_entry/run.log) |
| `quests/tunnel_guard` | passed | 9 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/tunnel_guard/run.log) |
| `quests/shelter_departure` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/quests/shelter_departure/run.log) |
| `quests/shelter_kel` | passed | 33 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/shelter_kel/run.log) |
| `quests/slave_camp_escape` | passed | 31 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/quests/slave_camp_escape/run.log) |
| `quests/zone7_arrival` | passed | 29 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/zone7_arrival/run.log) |
| `quests/island_return` | passed | 39 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/quests/island_return/run.log) |
| `quests/lia_revenge_return` | passed | 13 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/lia_revenge_return/run.log) |
| `quests/lia_slave_lists_return` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/lia_slave_lists_return/run.log) |
| `quests/lia_tomb_exit` | passed | 36 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/lia_tomb_exit/run.log) |
| `coop/coop_campaign_classes` | passed | 34 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_campaign_classes/run.log) |
| `coop/coop_campaign_classes_astral` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_campaign_classes_astral/run.log) |
| `coop/coop_fresh_start` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_fresh_start/run.log) |
| `coop/coop_fresh_start_astral` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_fresh_start_astral/run.log) |
| `coop/coop_fresh_start_guards` | error | 76 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_fresh_start_guards/run.log) |
| `coop/coop_fresh_start_guards_astral` | error | 75 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_fresh_start_guards_astral/run.log) |
| `coop/coop_guest_roles` | passed | 51 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_guest_roles/run.log) |
| `coop/coop_guest_roles_astral` | passed | 38 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_guest_roles_astral/run.log) |
| `coop/coop_guest_roles_net` | passed | 31 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_guest_roles_net/run.log) |
| `coop/coop_guest_roles_net_astral` | passed | 31 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_guest_roles_net_astral/run.log) |
| `coop/coop_party_switch` | passed | 23 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/coop/coop_party_switch/run.log) |
| `coop/coop_permissions` | passed | 31 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-corrected/tests/coop/coop_permissions/run.log) |
| `coop/coop_progress_chapters` | passed | 7 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_chapters/run.log) |
| `coop/coop_progress_chapters_astral` | passed | 17 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_chapters_astral/run.log) |
| `coop/coop_progress_cleanup` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_cleanup/run.log) |
| `coop/coop_progress_context` | passed | 72 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_context/run.log) |
| `coop/coop_progress_context_astral` | passed | 76 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_context_astral/run.log) |
| `coop/coop_progress_context_network` | passed | 56 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_context_network/run.log) |
| `coop/coop_progress_context_network_astral` | passed | 45 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_context_network_astral/run.log) |
| `coop/coop_progress_travel` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_travel/run.log) |
| `coop/coop_progress_travel_astral` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_progress_travel_astral/run.log) |
| `coop/coop_rename_reconnect` | passed | 155 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_rename_reconnect/run.log) |
| `coop/coop_rename_reconnect_astral` | passed | 155 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_rename_reconnect_astral/run.log) |
| `coop/coop_save_effects` | passed | 31 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_save_effects/run.log) |
| `coop/coop_shared_checkpoint` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_shared_checkpoint/run.log) |
| `coop/coop_shared_checkpoint_astral` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_shared_checkpoint_astral/run.log) |
| `coop/coop_shared_checkpoint_net` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_shared_checkpoint_net/run.log) |
| `coop/coop_shared_checkpoint_net_astral` | passed | 25 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_shared_checkpoint_net_astral/run.log) |
| `coop/coop_solo_return` | passed | 99 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_solo_return/run.log) |
| `coop/coop_solo_return_dependents` | passed | 10 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_dependents/run.log) |
| `coop/coop_solo_return_dependents_astral` | passed | 10 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_dependents_astral/run.log) |
| `coop/coop_solo_return_guards` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_guards/run.log) |
| `coop/coop_solo_return_guards_astral` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_guards_astral/run.log) |
| `coop/coop_solo_return_older_host` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_solo_return_older_host/run.log) |
| `coop/coop_solo_return_older_host_astral` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_solo_return_older_host_astral/run.log) |
| `coop/coop_solo_return_roles` | passed | 10 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_roles/run.log) |
| `coop/coop_solo_return_roles_astral` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_solo_return_roles_astral/run.log) |
| `coop/coop_solo_return_transport` | passed | 35 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_solo_return_transport/run.log) |
| `coop/coop_vm_projection` | passed | 36 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_vm_projection/run.log) |
| `coop/coop_vm_projection_astral` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_vm_projection_astral/run.log) |
| `coop/coop_vm_solo` | passed | 30 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_vm_solo/run.log) |
| `coop/coop_vm_solo_trap` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/coop/coop_vm_solo_trap/run.log) |
| `coop/coop_zone_transfer` | passed | 20 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_zone_transfer/run.log) |
| `coop/coop_zone_transfer_astral` | passed | 20 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_zone_transfer_astral/run.log) |
| `coop/coop_progress_preview` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_progress_preview/run.log) |
| `coop/coop_progress_preview_astral` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/coop/coop_progress_preview_astral/run.log) |
| `pathing/client_placement` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/client_placement/run.log) |
| `pathing/catacomb_capacity` | passed | 45 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/catacomb_capacity/run.log) |
| `pathing/catacomb_capacity_net` | passed | 36 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/catacomb_capacity_net/run.log) |
| `pathing/dynamic_navigation` | passed | 140 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/dynamic_navigation/run.log) |
| `settings/single_player_rules` | passed | 52 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/single_player_rules/run.log) |
| `settings/player_profile` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/player_profile/run.log) |
| `settings/control_mode_options` | passed | 14 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/control_mode_options/run.log) |
| `settings/camera_guest_options` | passed | 42 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/settings/camera_guest_options/run.log) |
| `settings/direct_settings` | passed | 66 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/direct_settings/run.log) |
| `settings/graphics_options` | passed | 435 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/graphics_options/run.log) |
| `settings/graphics_presets` | passed | 259 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-graphics-stable/tests/settings/graphics_presets/run.log) |
| `settings/audio_bus_routes` | passed | 2 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/audio_bus_routes/run.log) |
| `settings/audio_echo_options` | passed | 16 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/audio_echo_options/run.log) |
| `persistence/network_save_choices` | passed | 43 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/persistence/network_save_choices/run.log) |
| `persistence/profile_save_seed` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/persistence/profile_save_seed/run.log) |
| `persistence/profile_save_seed_astral` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/persistence/profile_save_seed_astral/run.log) |
| `interface/character_buff_icons` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/interface/character_buff_icons/run.log) |
| `interface/loading_progress` | passed | 5 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/interface/loading_progress/run.log) |
| `interface/loading_cover` | error | 0 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/interface/loading_cover/run.log) |
| `interface/tooltip_lifetime_ui` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/interface/tooltip_lifetime_ui/run.log) |
| `interface/side_quest_panel_ui` | passed | 86 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/interface/side_quest_panel_ui/run.log) |
| `interface/wiki_quest_locales` | passed | 672 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/interface/wiki_quest_locales/run.log) |
| `interface/wiki_quest_locales_astral` | passed | 2883 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/interface/wiki_quest_locales_astral/run.log) |
| `commands/first_person_actions` | passed | 64 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/commands/first_person_actions/run.log) |
| `commands/direct_aim_selection` | passed | 17 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/commands/direct_aim_selection/run.log) |
| `commands/direct_quest_bindings` | passed | 5 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/commands/direct_quest_bindings/run.log) |
| `commands/touch_unit_picking` | passed | 1352 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/commands/touch_unit_picking/run.log) |
| `animation/direct_attack_stance` | passed | 39 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/animation/direct_attack_stance/run.log) |
| `party/revive_camera` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/party/revive_camera/run.log) |
| `pathing/direct_movement` | passed | 33 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/direct_movement/run.log) |
| `pathing/travel_reveal` | passed | 9 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/travel_reveal/run.log) |
| `pathing/travel_reveal_astral` | passed | 9 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/pathing/travel_reveal_astral/run.log) |
| `creatures/peasant_help` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/creatures/peasant_help/run.log) |
| `creatures/peasant_help_astral` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/creatures/peasant_help_astral/run.log) |
| `creatures/added_actor_lifetime` | passed | 17 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/creatures/added_actor_lifetime/run.log) |
| `creatures/added_actor_tombstones` | passed | 34 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/creatures/added_actor_tombstones/run.log) |
| `creatures/registry_queries` | passed | 1283 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/creatures/registry_queries/run.log) |
| `combat/wisp_native_callbacks` | passed | 4428 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/combat/wisp_native_callbacks/run.log) |
| `arena/arena_alliances` | passed | 602 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_alliances/run.log) |
| `arena/arena_economy` | passed | 590 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_economy/run.log) |
| `arena/arena_elimination_places` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_elimination_places/run.log) |
| `arena/arena_flow` | passed | 235 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/arena/arena_flow/run.log) |
| `arena/arena_formation` | passed | 22 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_formation/run.log) |
| `arena/arena_live_shop` | passed | 120 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_live_shop/run.log) |
| `arena/arena_recruitment` | passed | 2006 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/arena/arena_recruitment/run.log) |
| `arena/arena_result_health` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_result_health/run.log) |
| `arena/arena_roster` | passed | 1515 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_roster/run.log) |
| `arena/arena_round_lifecycle` | failed | 569 | 3 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-ui-recheck/tests/arena/arena_round_lifecycle/run.log) |
| `arena/arena_sale_quotes` | passed | 254 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_sale_quotes/run.log) |
| `arena/arena_saved_opening` | passed | 11 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-saved-opening/tests/arena/arena_saved_opening/run.log) |
| `arena/arena_solo_recovery` | passed | 8 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_solo_recovery/run.log) |
| `arena/arena_species` | passed | 2154 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_species/run.log) |
| `arena/arena_standings_results` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_standings_results/run.log) |
| `arena/arena_tournament` | passed | 154 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_tournament/run.log) |
| `arena/arena_pve_lifecycle` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_pve_lifecycle/run.log) |
| `arena/arena_battle_limits` | passed | 9 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_battle_limits/run.log) |
| `arena/arena_filtered_spells` | passed | 3 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_filtered_spells/run.log) |
| `arena/arena_damage_retention` | passed | 12 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_damage_retention/run.log) |
| `arena/arena_bot_planner` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/arena/arena_bot_planner/run.log) |
| `dialogue/gipat_captive_dialogue_hermit_first` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/dialogue/gipat_captive_dialogue_hermit_first/run.log) |
| `quests/shelter_kel_solo` | passed | 24 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/shelter_kel_solo/run.log) |
| `quests/shelter_kel_named` | passed | 33 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/quests/shelter_kel_named/run.log) |
| `coop/coop_fresh_start_before_start` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_fresh_start_before_start/run.log) |
| `coop/coop_fresh_start_astral_before_start` | passed | 15 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-dependent-recheck/tests/coop/coop_fresh_start_astral_before_start/run.log) |
| `settings/camera_guest_options_ru` | passed | 42 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/settings/camera_guest_options_ru/run.log) |
| `settings/camera_guest_options_de` | passed | 42 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-final-fixtures/tests/settings/camera_guest_options_de/run.log) |
| `settings/audio_echo_options_ru` | passed | 16 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/audio_echo_options_ru/run.log) |
| `settings/audio_echo_options_de` | passed | 16 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/settings/audio_echo_options_de/run.log) |
| `interface/character_buff_icons_ru` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/interface/character_buff_icons_ru/run.log) |
| `interface/character_buff_icons_de` | passed | 18 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-first/tests/interface/character_buff_icons_de/run.log) |
| `stealth/steal_lifecycle` | passed | 35 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-lifecycles/tests/stealth/steal_lifecycle/run.log) |
| `stealth/steal_lifecycle_astral` | passed | 35 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-lifecycles/tests/stealth/steal_lifecycle_astral/run.log) |
| `quests/side_quest_lifecycle` | passed | 590 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-side-recheck/tests/quests/side_quest_lifecycle/run.log) |
| `settings/option_localization_matrix` | passed | 14538 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-lifecycles/tests/settings/option_localization_matrix/run.log) |
| `inventory/camp_action_lifecycle` | passed | 76 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-crafting/tests/inventory/camp_action_lifecycle/run.log) |
| `inventory/camp_action_lifecycle_astral` | passed | 76 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-crafting/tests/inventory/camp_action_lifecycle_astral/run.log) |
| `commands/travel_command_lifecycle` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-travel-fixed/tests/commands/travel_command_lifecycle/run.log) |
| `commands/travel_command_lifecycle_astral` | passed | 21 | 0 | [log](/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/encounter-travel-fixed/tests/commands/travel_command_lifecycle_astral/run.log) |

### coop/coop_fresh_start_guards

Runtime/script diagnostics; assertion results are not a clean run

- SCRIPT ERROR: Invalid operands 'int' and 'bool' in operator '!='.
- SCRIPT ERROR: Invalid operands 'int' and 'bool' in operator '!='.

### coop/coop_fresh_start_guards_astral

Runtime/script diagnostics; assertion results are not a clean run

- SCRIPT ERROR: Invalid operands 'int' and 'bool' in operator '!='.
- SCRIPT ERROR: Invalid operands 'int' and 'bool' in operator '!='.

### interface/loading_cover

Expected exactly one LOADING_COVER summary, found 0

- ERROR: Parameter "canvas_item" is null.
- ERROR: Parameter "canvas_item" is null.
- ERROR: Parameter "canvas_item" is null.

### arena/arena_round_lifecycle

Failed assertions:

- FAIL menu pauses combat at 2x
- FAIL menu pauses combat at 2x
- FAIL menu pauses combat at 2x

## Scope

27 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
