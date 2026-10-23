extends "lia_campaign_map_points.gd"
## Same map-control matrix with the base game's explicit asset inventory.
func missing_maps() -> Array: return ["gz21g"]
func unused_edges() -> Array: return ["gz15h_gz15h","gz4g_bz4g","gz5g_gz6g"]
func marker_fixture() -> String: return "res://tools/tests/fixtures/base_campaign_quest_markers.json"
func result_marker() -> String: return "BASE_CAMPAIGN_MAP_POINTS"
func campaign_name() -> String: return "base Evil Islands"
func starting_areas() -> int: return 1
func scripted_only_maps() -> Array: return ["gz20g"]
