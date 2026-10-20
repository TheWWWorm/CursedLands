extends "creature_projectile_origins.gd"
## Reuse every launch/animation/replay assertion with authored Astral actors.
## Completion marker CREATURE_PROJECTILE_ORIGINS is emitted by the base suite.
## The Portal Terror's map template is explicit, as in creature_damage.gd.
const ASTRAL_ACTORS := {
	"DragonBrownM16":"zone3 DragonBrown",
	"DragonGreenM12":"zone9 DragonGreen",
	"DragonBlueM14":"zone1 DragonBlue",
	"ToadM1":"zonezero Toad",
	"BatDarkM12":"zone1 Bat",
	"EvileyeGreenM13":"zone3 Evileye",
	"EvileyeRedM12":"zone4 Evileye",
	"BansheeDarkM12Canyon":"zone2 Banshee Mage1",
	"OctopusHadaganM13":"zone4 Octopus",
	"ShadowM13":"zone31 Shadow",
	"SuccubGreyM13Canyon":"zonezero Succub",
	"UnicornBlackM15":"zone22 Unicorn Black",
	"Rick":"bz14g Rick",
	"DriadGreenM7":"zone21 Driad White Mage1",
	"DriadDarkM9":"zone22 Driad Blue Mage1",
	"AncientCurseM25":"zone1 JunEvil",
	"WillowispM1":"zone7 Willowisp1",
	"Human Hero":"Human Hero",
	"DriadDarkA7":"zone21 Driad White Archer1",
	"GoblinA1":"zone7 Goblin Archer",
	"CyclopsA16":"zone11 Cyclop",
	"Human Mercenary Thief":"Human Hero",
	"OrcFemaleA3":"zone9 Orc Archer1 F",
}

func fixture_record(id: String) -> Dictionary:
	var record := super.fixture_record(id)
	record.prototype = ASTRAL_ACTORS[id]
	if id == "AncientCurseM25": record.template = "unmocu"
	return record
