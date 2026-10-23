extends "lia_campaign_support.gd"
## Base-campaign chapter checkpoints reuse the same normal interaction,
## save/load and travel helpers. Earlier chapter prerequisites are explicit;
## the objective being measured must never be assigned by a fixture.

func expected_campaign() -> String:
	return CampaignProfile.ORIGINAL

# Headless map creation can complete synchronously. Yield after each load so
# the prior queued world is freed before another checkpoint allocates a map.
func enter(zone: String) -> void:
	await super.enter(zone)
	await frames()

func roundtrip(slot: String, vars: Array, items: Array = []) -> void:
	await super.roundtrip(slot,vars,items)
	await frames()
