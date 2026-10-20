# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **incomplete**.

Completed 40 of 281 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| animation | 7 | 7 | 0 | 0 | 2325 |
| commands | 3 | 3 | 0 | 0 | 983 |
| creatures | 6 | 6 | 0 | 0 | 12023 |
| effects | 8 | 8 | 0 | 0 | 71755 |
| quests | 11 | 11 | 0 | 0 | 491 |
| stealth | 5 | 5 | 0 | 0 | 3032 |

Capture error: KeyboardInterrupt


## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `quests/script_dead_predicates` | passed | 12 | 0 | [log](tests/quests/script_dead_predicates/run.log) |
| `quests/script_hero_references` | passed | 11 | 0 | [log](tests/quests/script_hero_references/run.log) |
| `quests/story_coop_predicates` | passed | 101 | 0 | [log](tests/quests/story_coop_predicates/run.log) |
| `quests/story_coop_traps` | passed | 55 | 0 | [log](tests/quests/story_coop_traps/run.log) |
| `quests/story_coop_effects` | passed | 167 | 0 | [log](tests/quests/story_coop_effects/run.log) |
| `quests/quest_carriers` | passed | 12 | 0 | [log](tests/quests/quest_carriers/run.log) |
| `quests/quest_inventory_lifecycle` | passed | 20 | 0 | [log](tests/quests/quest_inventory_lifecycle/run.log) |
| `quests/quest_rewards` | passed | 4 | 0 | [log](tests/quests/quest_rewards/run.log) |
| `quests/quest_actor_removal` | passed | 24 | 0 | [log](tests/quests/quest_actor_removal/run.log) |
| `quests/catacomb_group_lever` | passed | 26 | 0 | [log](tests/quests/catacomb_group_lever/run.log) |
| `quests/lever_transition_save` | passed | 59 | 0 | [log](tests/quests/lever_transition_save/run.log) |
| `creatures/ai_activity_health` | passed | 45 | 0 | [log](tests/creatures/ai_activity_health/run.log) |
| `creatures/ai_activity_senses` | passed | 7340 | 0 | [log](tests/creatures/ai_activity_senses/run.log) |
| `creatures/ai_live_eligibility` | passed | 4589 | 0 | [log](tests/creatures/ai_live_eligibility/run.log) |
| `creatures/ai_reaction_recipients` | passed | 7 | 0 | [log](tests/creatures/ai_reaction_recipients/run.log) |
| `creatures/creature_alerts` | passed | 20 | 0 | [log](tests/creatures/creature_alerts/run.log) |
| `creatures/creature_damage` | passed | 22 | 0 | [log](tests/creatures/creature_damage/run.log) |
| `animation/creature_weapon_animations` | passed | 196 | 0 | [log](tests/animation/creature_weapon_animations/run.log) |
| `animation/direct_gait_continuity` | passed | 1920 | 0 | [log](tests/animation/direct_gait_continuity/run.log) |
| `animation/direct_moving_attacks` | passed | 15 | 0 | [log](tests/animation/direct_moving_attacks/run.log) |
| `animation/direct_moving_casts` | passed | 48 | 0 | [log](tests/animation/direct_moving_casts/run.log) |
| `animation/paused_spawn_pose` | passed | 42 | 0 | [log](tests/animation/paused_spawn_pose/run.log) |
| `animation/paused_load_pose` | passed | 50 | 0 | [log](tests/animation/paused_load_pose/run.log) |
| `animation/dialogue_poses` | passed | 54 | 0 | [log](tests/animation/dialogue_poses/run.log) |
| `effects/creature_effect_attachments` | passed | 1739 | 0 | [log](tests/effects/creature_effect_attachments/run.log) |
| `effects/creature_projectile_origins` | passed | 186 | 0 | [log](tests/effects/creature_projectile_origins/run.log) |
| `effects/particle_delay_lifetime` | passed | 57 | 0 | [log](tests/effects/particle_delay_lifetime/run.log) |
| `effects/repeated_spells` | passed | 86 | 0 | [log](tests/effects/repeated_spells/run.log) |
| `effects/fire_particles` | passed | 43389 | 0 | [log](tests/effects/fire_particles/run.log) |
| `effects/tornado_particles` | passed | 26244 | 0 | [log](tests/effects/tornado_particles/run.log) |
| `effects/healing_presentation` | passed | 22 | 0 | [log](tests/effects/healing_presentation/run.log) |
| `effects/delayed_cast_lifetime` | passed | 32 | 0 | [log](tests/effects/delayed_cast_lifetime/run.log) |
| `stealth/stealth_effects` | passed | 19 | 0 | [log](tests/stealth/stealth_effects/run.log) |
| `stealth/stealth_effects_net` | passed | 15 | 0 | [log](tests/stealth/stealth_effects_net/run.log) |
| `stealth/perception_batch` | passed | 2857 | 0 | [log](tests/stealth/perception_batch/run.log) |
| `stealth/unit_visibility` | passed | 72 | 0 | [log](tests/stealth/unit_visibility/run.log) |
| `stealth/hidden_presentation` | passed | 69 | 0 | [log](tests/stealth/hidden_presentation/run.log) |
| `commands/combat_inputs` | passed | 918 | 0 | [log](tests/commands/combat_inputs/run.log) |
| `commands/direct_command_priority` | passed | 37 | 0 | [log](tests/commands/direct_command_priority/run.log) |
| `commands/issue_campaign_orders` | passed | 28 | 0 | [log](tests/commands/issue_campaign_orders/run.log) |

## Scope

0 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
