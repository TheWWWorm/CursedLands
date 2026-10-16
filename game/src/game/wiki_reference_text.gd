class_name WikiReferenceText
extends RefCounted
## Reuse the public wiki's reviewed LiA translations inside a wiki read scope.
## A fingerprint ties each translation to its original Russian archive text;
## localized editions and changed mod text are never replaced by ID alone.
## Russian continues to use the installed archive.

static func apply() -> void:
	if GameData.campaign_id != CampaignProfile.ASTRAL or not RemakeText.lang in ["en", "de"]: return
	var language := 1 if RemakeText.lang == "en" else 2
	for key: String in TEXTS:
		var record: Array = TEXTS[key]
		if GameData.text(key).sha256_text() == record[0]: GameData._text_cache[key] = record[language]

const TEXTS := {
	"armor gipat_brigand_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_boots tiger_hide": [
		"56cbc591c2efa9d05d713e66255a1ec8beb650d8e1f60f228aba4e1e6cbf9d50",
		"Gipath boots of tiger skin\nAnyone who has spent time marching through the woods will appreciate the stealth that fur footwear provides.",
		"Gipather Tigerfellstiefel\nWer öfter im Wald unterwegs ist, wird die Bequemlichkeit und den leisen Tritt von Fellstiefeln zu schätzen wissen."
	],
	"armor gipat_brigand_boots tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_boots tiger_hide_white": [
		"c41f4796c3919007de1a3735cb7e0a3adb2b18d730ccf999512ca87ff4a5d40a",
		"Snow tiger's fur boots\nThese boots tread as softly as tiger paws on snow, but offer no protection.",
		"Stiefel aus Schneetigerfell\nDiese Stiefel treten so leise auf Schnee wie Tigerpfoten, bieten aber keinen Schutz."
	],
	"armor gipat_brigand_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_gloves tiger_hide": [
		"d55dcf9f818b02c5e18fe3a504e01c49aefc15783ad6770de99a41951e198801",
		"Gipath gauntlets of tiger skin\nA decent ornament, and at least some protection.",
		"Gipather Handschuhe aus Tigerfell\nEin hübsches Schmuckstück und immerhin etwas Schutz."
	],
	"armor gipat_brigand_gloves tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_gloves tiger_hide_white": [
		"ff28e065d75e0c08ff0b63b8d37e6fb6b7ccee2fd834a9a360a889bbabeb13b0",
		"Snow tiger's fur gauntlets\nThe governor would like these bracers for his collection.",
		"Handschuhe aus Schneetigerfell\nDer Gouverneur hätte diese Armschienen gern für seine Sammlung."
	],
	"armor gipat_brigand_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_helm tiger_hide": [
		"f3a272e61371113e295a45c945ea8402e8b0a2d5a0def438c182e8b0969f4cd9",
		"Gipath \"Tiger Head\" helmet\nA good helmet for frightening the easily impressed.",
		"Gipather Tigerkopf-Helm\nEin guter Helm, um schreckhafte Menschen einzuschüchtern."
	],
	"armor gipat_brigand_helm tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_helm tiger_hide_white": [
		"51690c0bcc5e2bb02833632ba44b1844938ddd3d6defbec65bc3c292cec68069",
		"\"Snow Tiger's head\" helmet\nBetter looking than a plain fur cap, and a little stronger!",
		"Schneetigerkopf-Helm\nSchöner als eine einfache Fellmütze und etwas robuster!"
	],
	"armor gipat_brigand_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_leggins tiger_hide": [
		"af511ec33fdb45843d6b97b7480de9fafad59091ec25a8dede118e780ffcbebb",
		"Gipath leggings of tiger skin\nA beautiful, if not particularly useful, object.",
		"Gipather Beinlinge aus Tigerfell\nEin schönes, wenn auch nicht besonders nützliches Stück."
	],
	"armor gipat_brigand_leggins tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_leggins tiger_hide_white": [
		"66b13f8959a770757568a28e04b767969c33c98c42567392e41b19d4d0d943c3",
		"Snow tiger fur leggings\nReliable protection for your legs against the cold.",
		"Beinlinge aus Schneetigerfell\nZuverlässiger Kälteschutz für die Beine."
	],
	"armor gipat_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_pants tiger_hide": [
		"8146a260d5340b14763bc120cef7b109473c6b2a7e5f688e444c27c2cbb4e8d6",
		"Gipath trousers of tiger skin\nThese trousers are well suited to long forest journeys and look good, too.",
		"Gipather Tigerfellhosen\nDiese Hose eignet sich für lange Waldmärsche und sieht dabei gut aus."
	],
	"armor gipat_brigand_pants tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_pants tiger_hide_white": [
		"4dc2683c6f12c8ed1ba5c2f8eb4512ab39575abf8379d23500dff08582fd5c61",
		"Snow tiger's fur trousers\nSimply handsome trousers that keep out the cold.",
		"Hosen aus Schneetigerfell\nEinfach eine schöne Hose, die vor Kälte schützt."
	],
	"armor gipat_brigand_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_plate tiger_hide": [
		"434309bd22a1224ff6f1f56ebfd11130bdd99b034924e2fee963f71246389f76",
		"Gipath hunting coat of tiger skin\nYoung sorceresses adore these cloaks.",
		"Gipather Jagdmantel aus Tigerfell\nJunge Zauberinnen lieben solche Umhänge."
	],
	"armor gipat_brigand_plate tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_plate tiger_hide_white": [
		"c3f0497561e8584c0947d3cbd1c4976a283ca72254c44cbb502ba08af04478cf",
		"Snow tiger fur cloak\nSnow Tiger's fur provides perfect camouflage in snow.",
		"Umhang aus Schneetigerfell\nSchneetigerfell bietet die perfekte Tarnung im Schnee!"
	],
	"armor gipat_brigand_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_prototype tiger_hide": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_prototype tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_prototype tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_shirt tiger_hide": [
		"6078093a7e438c50eda51cad8107550fb19d3bb0e84e731c9a2b398eecadd88e",
		"Gipath breastplate of tiger skin\nOffers some protection and looks better than a plain breastplate.",
		"Gipather Brustpanzer aus Tigerfell\nBietet etwas Schutz und sieht besser aus als ein einfacher Brustpanzer."
	],
	"armor gipat_brigand_shirt tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_brigand_shirt tiger_hide_white": [
		"31c27cb9f5e422b08f6775c385088ba899aa4b1891962ae838ada5ca0499a64f",
		"Snow tiger's fur breastplate\nBeautiful, and above all, warm!",
		"Brustpanzer aus Schneetigerfell\nSchön und vor allem warm!"
	],
	"armor gipat_high_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_boots tanned_thin": [
		"cdc3a4d7fd41e0334126ef4abf50cac4886977dd1347ff1573bc5a550cbf9c76",
		"Gipath stitched boots of hard leather\nNow you can risk getting into a fight - but not into combat!",
		"Gipather genähte Stiefel aus derbem Leder\nDiese Stiefel sind für eine Schlägerei ausreichend, für einen ernsthaften Kampf taugen sie allerdings nicht!"
	],
	"armor gipat_high_boots thick": [
		"c70277348a05138b6582a3d78b98ccfe84fc9647d198576e9ccba5fb5f995696",
		"Stitched Gipath boots · Tough leather\nGood price/performance ratio.",
		"Gipather genähte Stiefel · Starkes Leder\nAnnehmbarer Schutz zu einem guten Preis."
	],
	"armor gipat_high_boots thin": [
		"02ab6c634e99f680c324f021a379c6702fc273e37cd8f5bb1b0c19496115b70e",
		"Gipath stitched boots of thin leather\nThey are light and relatively strong.",
		"Gipather genähte Stiefel aus dünnem Leder\nLeicht und trotzdem stabil."
	],
	"armor gipat_high_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_gloves tanned_thin": [
		"ea14012716f57c79de8223141630e76f5f41af7a60c61234b782078fbbc189f9",
		"Gipath stitched gauntlets of hard leather\nWolf's teeth will no longer present any danger to you - but beware of more dangerous creatures!",
		"Gipather genähte Handschuhe aus derbem Leder\nStärker als jeder Wolfszahn - aber es gibt Gefährlicheres als Wölfe."
	],
	"armor gipat_high_gloves thick": [
		"89f8b54f789014db53afc1fe09ec7938d3b737375a538ad886603688165490ec",
		"Stitched Gipath gauntlets · Tough leather\nThey protect almost the full length of the arms reasonably well.",
		"Gipather genähte Handschuhe · Starkes Leder\nSie schützen die Arme fast auf ganzer Länge recht gut."
	],
	"armor gipat_high_gloves thin": [
		"de370ac62a4a393f2d6f4c65e4d71a5afeaa2de4af2c4a04dd0ea5b36d2440a2",
		"Gipath stitched gauntlets of thin leather\nProvide almost complete protection for your arms, though the material could be better.",
		"Gipather genähte Handschuhe aus dünnem Leder\nBedecken fast den ganzen Arm. Das Material könnte allerdings besser sein."
	],
	"armor gipat_high_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_helm tanned_thin": [
		"dc8b42a072739ff7e30f5dec4af734a2a03e02d332fc2a51733eaf29ee628cb3",
		"Gipath stitched helmet of hard leather\nGood protection for the head. Better is possible, but not easy to make.",
		"Gipather genähter Helm aus derbem Leder\nGuter Kopfschutz. Besseres ist möglich, aber schwer herzustellen."
	],
	"armor gipat_high_helm thick": [
		"1c66e0a00221ec579f6575d4d7239cb851d50ae3614f70711c21c072aeaa0107",
		"Stitched Gipath helmet · Tough leather\nDecent head protection, but not against every kind of weapon.",
		"Gipather genähter Helm · Starkes Leder\nOrdentlicher Kopfschutz, aber nicht gegen jede Waffenart."
	],
	"armor gipat_high_helm thin": [
		"446bda1addf31e9e39aa4c2250f27f5c4fdcfbc282e8841a269dfa741f228b85",
		"Gipath stitched helmet of thin leather\nDecent head protection, but you should still avoid exposure to the axe!",
		"Gipather genähter Helm aus dünnem Leder\nEin guter Kopfschutz - kann aber gegen eine Axt nicht viel ausrichten!"
	],
	"armor gipat_high_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_leggins tanned_thin": [
		"c5d4e67551d0d650f5a1d7bcda91e5b4eb79dabd8b22d668d9d0ed6eb4397e78",
		"Gipath stitched leggings of hard leather\nGood additional leg protection.",
		"Gipather genähte Beinlinge aus derbem Leder\nEin guter zusätzlicher Schutz für die Beine."
	],
	"armor gipat_high_leggins thick": [
		"b30c008a5cdb372c3b45c7e58d2005da3ecd93944675e3bbfb12608011454c8f",
		"Stitched Gipath leggings · Tough leather\nThey look good and protect better.",
		"Gipather genähte Beinlinge · Starkes Leder\nBieten guten Schutz und sind sehr dekorativ."
	],
	"armor gipat_high_leggins thin": [
		"0f31bdbfdbba0afc3f884422e56d01d05e1513bc06a8516c2a61e4013c93388a",
		"Gipath stitched leggings of thin leather\nNot the best choice of material, but it can still stop a weak blow.",
		"Gipather genähte Beinlinge aus dünnem Leder\nNicht die beste Materialwahl, doch einen schwachen Schlag hält es ab."
	],
	"armor gipat_high_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_pants tanned_thin": [
		"8e363dd53673a311dfe38630e8876b604cec0aa48644ef6a09bedccb59bbf227",
		"Long quilted Gipath trousers · Hard leather\nUncomfortable on long journeys, but they protect your feet well in battle.",
		"Lange gesteppte Gipath-Hose · Hartes Leder\nAuf langen Wegen unbequem, doch im Kampf schützen sie die Füße gut."
	],
	"armor gipat_high_pants thick": [
		"57309e9c903429fd098b6ad61bc21b47d60438d76d47b2b027103d74a69b81b0",
		"Long quilted Gipath trousers · Tough leather\nGive your legs adequate protection.",
		"Lange gesteppte Gipath-Hose · Starkes Leder\nGuter Schutz für die Beine."
	],
	"armor gipat_high_pants thin": [
		"7f6a181e9d0a9cf156dc6dbe6a2a12b7cb73bf01b9fa56448441606dbb26d115",
		"Long quilted Gipath trousers · Thin leather\nProtect your legs from top to bottom - as well as you can expect from thin leather.",
		"Lange gesteppte Gipath-Hose · Dünnes Leder\nSchützen die Beine von oben bis unten - so, wie man es von dünnem Leder erwarten kann."
	],
	"armor gipat_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_plate tanned_thin": [
		"dadecb4b97b28ad96ef060fca174bccfdc3c422fd14da0f29e2940a40a950c34",
		"Gipath stitched coat of hard leather\nWorthy protection for your body.",
		"Gipather genähter Mantel aus derbem Leder\nPerfekter Schutz für den ganzen Körper."
	],
	"armor gipat_high_plate thick": [
		"1a6bd1803973c1a82a31d60b7067c7f6e5632f6436d1c47f9005b53b0832d8a4",
		"Quilted Gipath cloak · Tough leather\nGood cut, decent material. Sensible choice if your resources are limited.",
		"Gesteppter Gipath-Umhang · Starkes Leder\nGuter Schnitt, anständiges Material. Eine gute Wahl, wenn nicht ausreichend Geld zur Verfügung steht."
	],
	"armor gipat_high_plate thin": [
		"9707a21e8395e558763b7e7ae7fd56da6a6d783073ed5abcd5caa32e0ff57319",
		"Gipath stitched coat of thin leather\nGood cut, but rather poor material.",
		"Gipather genähter Mantel aus dünnem Leder\nGuter Schnitt, aber nur mittelmäßiges Material."
	],
	"armor gipat_high_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_high_shirt tanned_thin": [
		"c10753ef08b39865b703e5564fe0bfe8753e73405809550c534181ff63965c39",
		"Gipath stitched breastplate of hard leather\nA bit heavy, but provides good protection for your body.",
		"Gipather genähter Brustpanzer aus derbem Leder\nBietet perfekten Schutz - ist allerdings sehr schwer."
	],
	"armor gipat_high_shirt thick": [
		"d0edbdde41417b26dc0efaeaba1df30bea36dbe98593fc0f2f5d878aefdc4880",
		"Stitched Gipath breastplate · Tough leather\nProvides decent protection for your shoulders and part of your back.",
		"Gipather genähter Brustpanzer · Starkes Leder\nAngemessener Schutz für Schultern und einen Teil des Rückens."
	],
	"armor gipat_high_shirt thin": [
		"0337a638b3fa422d7c33fd231ba20bb2771a61d4114da25902664ca2a2e76eb2",
		"Gipath stitched breastplate of thin leather\nIt is not bad, but there's definitely better materials.",
		"Gipather genähter Brustpanzer aus dünnem Leder\nNicht der schlechteste. Das Material könnte aber besser sein."
	],
	"armor gipat_highest2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots lizard_black": [
		"260c93a9646b2efbbf91bf9ae48d92d9a2cc61944f961b575b7958aa87b73b12",
		"Rough Gipath boots · Mountain lizard hide\nThese boots can walk through mud and over the bodies of your enemies.",
		"Grobe Gipath-Stiefel · Bergechsenhaut\nMit diesen Stiefeln kann man durch Schlamm und über die Leichen seiner Feinde gehen."
	],
	"armor gipat_highest2_boots lizard_blue": [
		"b04a5878305cd731bea340165807bd58d0f84fa9ef174df7c5b82d052ed21a58",
		"Rough Gipath boots · Lake lizard hide\nNo swamp will frighten you in these boots.",
		"Grobe Gipath-Stiefel · Seeechsenhaut\nMit diesen Stiefeln braucht ihr keinen Sumpf zu fürchten."
	],
	"armor gipat_highest2_boots lizard_green": [
		"ab20393ea572af8fbe470c73018d0be47787fc7aade69b2504f834fb5a4d45d2",
		"Rough Gipath boots · Forest lizard hide\nGood enough to start with. A thicker hide would be better.",
		"Grobe Gipath-Stiefel · Waldechsenhaut\nFür den Anfang reicht es. Eine dickere Haut wäre besser."
	],
	"armor gipat_highest2_boots ogre": [
		"43e3641bfa2db6763555f3415e1e6215e6762d2acb0f5466400707b20647d917",
		"Rough Gipath boots · Ogre hide\nThese boots mark you as a capable warrior.",
		"Grobe Gipath-Stiefel · Ogerhaut\nDiese Stiefel zeigen, dass ihr ein fähiger Krieger seid."
	],
	"armor gipat_highest2_boots troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots troll_blue": [
		"841acc2facd58dd1e78edd175768cc7cb734f796c3365af411c5cf802853429a",
		"Rough Gipath boots · Blue Troll hide\nThese boots are good for walking in snow, and little else.",
		"Grobe Gipath-Stiefel · Blaue Trollhaut\nDiese Stiefel taugen zum Gehen im Schnee, sonst zu nichts."
	],
	"armor gipat_highest2_boots troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_boots troll_green": [
		"270e7490a0c134ecdcb911405ddf5df94b9024aa42395959aec2eef2b37cec71",
		"Rough Gipath boots · Green Troll hide\nThe finest boots you can find on Gipath.",
		"Grobe Gipath-Stiefel · Grüne Trollhaut\nDie besten Stiefel, die man auf Gipath finden kann."
	],
	"armor gipat_highest2_boots troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves lizard_black": [
		"fc622635531ccf62924afa066ea6e4cb48c135937227382a013bb56ccfa11741",
		"Rough Gipath gloves · Mountain lizard hide\nOnly experienced warriors wear these gloves.",
		"Grobe Gipath-Handschuhe · Bergechsenhaut\nDiese Handschuhe tragen nur erfahrene Krieger."
	],
	"armor gipat_highest2_gloves lizard_blue": [
		"c9f0922c5ab8b62f3867bef8bdc477d471ed3962bd11025e2d907ebce7bc13e7",
		"Rough Gipath gloves · Lake lizard hide\nAn excellent aid for novice warriors.",
		"Grobe Gipath-Handschuhe · Seeechsenhaut\nEine ausgezeichnete Hilfe für angehende Krieger."
	],
	"armor gipat_highest2_gloves lizard_green": [
		"a50c5497fec8877c157775133c1e0f4a9388405770bdb4e572959d1bd12a11aa",
		"Rough Gipath gloves · Forest lizard hide\nExcellent gloves for a hunter, but unsuitable for a warrior.",
		"Grobe Gipath-Handschuhe · Waldechsenhaut\nAusgezeichnete Handschuhe für einen Jäger, doch für einen Krieger ungeeignet."
	],
	"armor gipat_highest2_gloves ogre": [
		"47029995e98e0cd1919122b389ae582c68424d6411a43f7d57f5f0e245e7e8dc",
		"Rough Gipath gloves · Ogre hide\nHands in these gloves can grasp hot coals or claim an enemy's life.",
		"Grobe Gipath-Handschuhe · Ogerhaut\nHände in diesen Handschuhen können glühende Kohlen greifen oder einem Feind das Leben nehmen."
	],
	"armor gipat_highest2_gloves troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves troll_blue": [
		"e351c207760635f9de846398114f02600c65e6b5dc280749496ea9a3b8b1a01c",
		"Rough Gipath gloves · Blue Troll hide\nThese gloves protect against the cold, but not snow tiger fangs.",
		"Grobe Gipath-Handschuhe · Blaue Trollhaut\nDiese Handschuhe schützen vor Kälte, aber nicht vor den Zähnen der Schneetiger."
	],
	"armor gipat_highest2_gloves troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_gloves troll_green": [
		"d3531bff7a80b9d79e6d32eae512978f0dfa6814fe51bed36677525dc9c17f83",
		"Rough Gipath gloves · Green Troll hide\nThese are the best gloves on Gipath.",
		"Grobe Gipath-Handschuhe · Grüne Trollhaut\nDies sind die besten Handschuhe auf Gipath."
	],
	"armor gipat_highest2_gloves troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm lizard_black": [
		"f98dfc25a3797c95c9fe99f142b40b5ead0bb07f3ce090ff2d2a1b433c30f455",
		"Rough Gipath helmet · Mountain lizard hide\nAn excellent helmet with a hefty price.",
		"Grober Gipath-Helm · Bergechsenhaut\nEin ausgezeichneter Helm mit einem stolzen Preis."
	],
	"armor gipat_highest2_helm lizard_blue": [
		"f6bb359bc40ec181f70290a7f9b313365a30d17da14917c1af54bbb8a0d11dab",
		"Rough Gipath helmet · Lake lizard hide\nThis helmet protects the head and looks decent, too.",
		"Grober Gipath-Helm · Seeechsenhaut\nDieser Helm schützt den Kopf und sieht auch ordentlich aus."
	],
	"armor gipat_highest2_helm lizard_green": [
		"de9c00664c76406d6f325db92fcb656c6157e8302bcf2ded49227f17041c1668",
		"Rough Gipath helmet · Forest lizard hide\nThis helmet can protect against a fairly weak blow.",
		"Grober Gipath-Helm · Waldechsenhaut\nDieser Helm kann einen schwächeren Schlag abfangen."
	],
	"armor gipat_highest2_helm ogre": [
		"ab304fc98d39fd54a0d84762ca58607b4206c1cf91f0aa5b019585f1e45c7cf8",
		"Rough Gipath helmet · Ogre hide\nEvery free hunter dreams of a helmet like this.",
		"Grober Gipath-Helm · Ogerhaut\nVon einem solchen Helm träumt jeder freie Jäger."
	],
	"armor gipat_highest2_helm troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm troll_blue": [
		"b81eb31e373d869ee2233c167abf18ebd334cde9efc5c174c7b8e1b7404b94e2",
		"Rough Gipath helmet · Blue Troll hide\nDo not wear this helmet in town unless you enjoy being laughed at.",
		"Grober Gipath-Helm · Blaue Trollhaut\nMit diesem Helm sollte man sich nicht in der Stadt zeigen, sonst wird man ausgelacht."
	],
	"armor gipat_highest2_helm troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_helm troll_green": [
		"d267069f81b77965b3f473a94884e32e36373090496b15da715e70838acaf0c7",
		"Rough Gipath helmet · Green Troll hide\nThe finest helmet on all of Gipath.",
		"Grober Gipath-Helm · Grüne Trollhaut\nDer beste Helm auf ganz Gipath."
	],
	"armor gipat_highest2_helm troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins lizard_black": [
		"edcffbaf7d616af22a8b22fcfa32e1b41231fd01d5d92e22767a117157ba69a0",
		"Rough Gipath leggings · Mountain lizard hide\nGood material means good protection.",
		"Grobe Gipath-Beinschienen · Bergechsenhaut\nGutes Material bedeutet guten Schutz."
	],
	"armor gipat_highest2_leggins lizard_blue": [
		"4cb06a69200f7d83fcc044c25383228e4f59ad23a27484104e39cb66ac46f1d4",
		"Rough Gipath leggings · Lake lizard hide\nThese leggings offer decent protection at a low price.",
		"Grobe Gipath-Beinschienen · Seeechsenhaut\nDiese Beinschienen bieten ordentlichen Schutz zu einem niedrigen Preis."
	],
	"armor gipat_highest2_leggins lizard_green": [
		"708cc4385e816985a48587a51ea3dbec1994381c768b134ef57ff894696239ec",
		"Rough Gipath leggings · Forest lizard hide\nThese leggings can protect the legs from a blow. That is about all that can be said for them.",
		"Grobe Gipath-Beinschienen · Waldechsenhaut\nDiese Beinschienen können einen Schlag abfangen. Viel mehr lässt sich nicht über sie sagen."
	],
	"armor gipat_highest2_leggins ogre": [
		"9cd1ac56235a5d3105c08484c2cf0abd16709add75109a03df6d86db5738d9df",
		"Rough Gipath leggings · Ogre hide\nThese leggings will frighten the bravest orc, but merely anger an ogre.",
		"Grobe Gipath-Beinschienen · Ogerhaut\nDiese Beinschienen erschrecken selbst den mutigsten Ork, einen Oger machen sie nur wütend."
	],
	"armor gipat_highest2_leggins troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins troll_blue": [
		"7347558be2c36f2c0362f964edb6e0f9aa19fa400fe2cf8e1bf132bdc3b288e3",
		"Rough Gipath leggings · Blue Troll hide\nThese leggings are a waste of money.",
		"Grobe Gipath-Beinschienen · Blaue Trollhaut\nDiese Beinschienen sind Geldverschwendung."
	],
	"armor gipat_highest2_leggins troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_leggins troll_green": [
		"5362e74d05b48ba66ff9360e5b12d9b0695301a5c33a2fb613f94401172a72f2",
		"Rough Gipath leggings · Green Troll hide\nYou will find no better leggings on Gipath.",
		"Grobe Gipath-Beinschienen · Grüne Trollhaut\nBessere Beinschienen findet man auf Gipath nicht."
	],
	"armor gipat_highest2_leggins troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants lizard_black": [
		"08416bbc42c3f502211405d4d9780683567e98c8193adcd4719d6bc7f1090fea",
		"Rough Gipath trousers · Mountain lizard hide\nThe hide once protected a mountain lizard; now it protects you.",
		"Grobe Gipath-Hose · Bergechsenhaut\nDiese Haut schützte einst eine Bergechse, jetzt schützt sie euch."
	],
	"armor gipat_highest2_pants lizard_blue": [
		"18dca173597881432799311e9dc8b80c9077445fe4cb88b498a414c08645a4f4",
		"Rough Gipath trousers · Lake lizard hide\nSimply a good piece of equipment.",
		"Grobe Gipath-Hose · Seeechsenhaut\nEinfach ein gutes Ausrüstungsstück."
	],
	"armor gipat_highest2_pants lizard_green": [
		"f4e8390d9ee377f59daf4dde7ef05704c03dc0b8cf8d1cd710ceb144460852ba",
		"Rough Gipath trousers · Forest lizard hide\nThese trousers protect well against fangs, but not spears.",
		"Grobe Gipath-Hose · Waldechsenhaut\nDiese Hose schützt gut vor Fangzähnen, aber nicht vor Speeren."
	],
	"armor gipat_highest2_pants ogre": [
		"1d4b1d30c678e28cd752e5d0e72621ee899f1442ae95823a7bfb0bac6b2d2c9a",
		"Rough Gipath trousers · Ogre hide\nIn these trousers, your enemies are no more dangerous than mosquitoes.",
		"Grobe Gipath-Hose · Ogerhaut\nIn dieser Hose sind eure Feinde nicht gefährlicher als Mücken."
	],
	"armor gipat_highest2_pants troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants troll_blue": [
		"6c27cff51b1857bf906fff40297fe1366f41abf193e744e09a53321c677d4c2a",
		"Rough Gipath trousers · Blue Troll hide\nThe only virtue of these trousers is having something to wear.",
		"Grobe Gipath-Hose · Blaue Trollhaut\nDer einzige Vorzug dieser Hose: Man hat etwas anzuziehen."
	],
	"armor gipat_highest2_pants troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_pants troll_green": [
		"db148b0b12b9c0de215c48fca15f5544af2a41a2909bdbfe32e109d6d2319b7f",
		"Rough Gipath trousers · Green Troll hide\nThese trousers are the best on Gipath.",
		"Grobe Gipath-Hose · Grüne Trollhaut\nDiese Hose ist die beste auf Gipath."
	],
	"armor gipat_highest2_pants troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate lizard_black": [
		"8f4fef693b0dd8e6347515a269c54c314a164314003234a2a65dfa8b452e0c1a",
		"Rough Gipath coat · Mountain lizard hide\nFew can afford this coat.",
		"Grober Gipath-Mantel · Bergechsenhaut\nDiesen Mantel können sich nur wenige leisten."
	],
	"armor gipat_highest2_plate lizard_blue": [
		"76ff3164a7be537107f2049980cfb08934cbe6fba6815ca1267f05c2cb413de2",
		"Rough Gipath coat · Lake lizard hide\nThe material is good for a coat, but better can be found.",
		"Grober Gipath-Mantel · Seeechsenhaut\nDas Material ist für einen Mantel gut, doch es gibt besseres."
	],
	"armor gipat_highest2_plate lizard_green": [
		"32607b71bfae7b6d229e7d6f9b823a24065217ec9807508f0f88baae1b198e88",
		"Rough Gipath coat · Forest lizard hide\nForest lizard hide is not well suited to a coat like this.",
		"Grober Gipath-Mantel · Waldechsenhaut\nWaldechsenhaut eignet sich nicht besonders für einen solchen Mantel."
	],
	"armor gipat_highest2_plate ogre": [
		"c620b1034e113174236188007de7d448e64b48d093d6db920e6b4d0f560256b9",
		"Rough Gipath coat · Ogre hide\nIn this coat, you will be feared more than an ogre.",
		"Grober Gipath-Mantel · Ogerhaut\nIn diesem Mantel fürchtet man euch mehr als einen Oger."
	],
	"armor gipat_highest2_plate troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate troll_blue": [
		"64186ff177029ab59106450e792046a7ff58bbce77e20aba9c0cacb91072e0d2",
		"Rough Gipath coat · Blue Troll hide\nThis coat will make people mistake you for a savage.",
		"Grober Gipath-Mantel · Blaue Trollhaut\nIn diesem Mantel hält man euch für einen Wilden."
	],
	"armor gipat_highest2_plate troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_plate troll_green": [
		"90643608c2210fa3d62309dd11fa55b98cc6c497a6b22c3bda9b20e3ffc4fd45",
		"Rough Gipath coat · Green Troll hide\nYou will find no better coat on Gipath.",
		"Grober Gipath-Mantel · Grüne Trollhaut\nEinen besseren Mantel findet man auf Gipath nicht."
	],
	"armor gipat_highest2_plate troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype troll_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype troll_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_prototype troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt lizard_black": [
		"c44385bdc0f317a355ba112ade1fe09431af2a675d5a2a4ee4f02b2eabb12898",
		"Rough Gipath shirt · Mountain lizard hide\nThis shirt provides good protection for the arms and torso.",
		"Grobes Gipath-Hemd · Bergechsenhaut\nDieses Hemd schützt Arme und Oberkörper gut."
	],
	"armor gipat_highest2_shirt lizard_blue": [
		"991a44085fc010e29967d6dbf7992b28f96962da1ab35a4039fa96c006e4637e",
		"Rough Gipath shirt · Lake lizard hide\nA shirt fit for a wedding or your enemies' funerals.",
		"Grobes Gipath-Hemd · Seeechsenhaut\nEin Hemd für Hochzeiten und die Beerdigungen eurer Feinde."
	],
	"armor gipat_highest2_shirt lizard_green": [
		"b3f790fb2b7897f474b678c159d46bf9300c5071bdc958658ab254f659612ed6",
		"Rough Gipath shirt · Forest lizard hide\nThis shirt will last forever.",
		"Grobes Gipath-Hemd · Waldechsenhaut\nDieses Hemd ist unverwüstlich."
	],
	"armor gipat_highest2_shirt ogre": [
		"87cfb134f992226be942727d473e6825ea9a2e2e89a49114d9f16f80305e105f",
		"Rough Gipath shirt · Ogre hide\nThe ogre whose hide made this shirt has suffered enough.",
		"Grobes Gipath-Hemd · Ogerhaut\nDer Oger, aus dessen Haut dieses Hemd besteht, hat genug gelitten."
	],
	"armor gipat_highest2_shirt troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt troll_blue": [
		"970b2a45d83b7b80f5a476604fffe4aa7e7f5fd3017824b66ec61f9fac10ddbe",
		"Rough Gipath shirt · Blue Troll hide\nOn Gipath this would be the finest armour, but on Ingos it is just rough rags.",
		"Grobes Gipath-Hemd · Blaue Trollhaut\nAuf Gipath wäre dies die beste Rüstung, doch auf Ingos sind es bloß grobe Lumpen."
	],
	"armor gipat_highest2_shirt troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest2_shirt troll_green": [
		"431a63a3a78fefbde817570c97ec81ac2f4baf48d57c343dc0f7afc4a979e2da",
		"Rough Gipath shirt · Green Troll hide\nThe best shirt on Gipath.",
		"Grobes Gipath-Hemd · Grüne Trollhaut\nDas beste Hemd auf Gipath."
	],
	"armor gipat_highest2_shirt troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_boots tanned_thin": [
		"4229239db10c4c5167516336a45c3c738f2f9c7d877ddc69de8b0a32df8c3bde",
		"Gipath heavy boots of hard leather\nRather mediocre boots, but inexpensive.",
		"Gipather schwere Stiefel aus derbem Leder\nZiemlich mittelmäßige Stiefel, aber günstig."
	],
	"armor gipat_highest_boots thick": [
		"75bf0ca3aa7c72b4eab78d45fbec2d06301f640fad883dd32b40e7fa41eb0035",
		"Heavy Gipath high boots · Tough leather\nThese boots suggest an unlucky or mediocre hunter.",
		"Gipather schwere Schaftstiefel · Starkes Leder\nDiese Stiefel deuten auf einen glücklosen oder mittelmäßigen Jäger hin."
	],
	"armor gipat_highest_boots thin": [
		"38bb7f8cfd23994c880b53b8b8d8b1289232c21f2330a22feb9b16a1f4964db5",
		"Gipath heavy boots of thin leather\nThe only virtue of these boots is that you are no longer barefoot.",
		"Gipather schwere Stiefel aus dünnem Leder\nDer einzige Vorzug dieser Stiefel: Man ist nicht mehr barfuß."
	],
	"armor gipat_highest_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_gloves tanned_thin": [
		"14a82e7abdd7e7c13639748234588832810b609d9b8afe07b68f72af8ab98368",
		"Gipath heavy gauntlets of hard leather\nThese gloves suit a hunter, but not a warrior.",
		"Gipather schwere Handschuhe aus derbem Leder\nDiese Handschuhe passen zu einem Jäger, aber nicht zu einem Krieger."
	],
	"armor gipat_highest_gloves thick": [
		"c23f466432b09be4a4ec0b5cbd74a1051bc1ad8c662433cc2c89c58a0605884d",
		"Heavy Gipath long gauntlets · Tough leather\nPoor tailoring and poor material. What use are these?",
		"Gipather schwere lange Handschuhe · Starkes Leder\nSchlechter Schnitt und schlechtes Material. Wozu soll das gut sein?"
	],
	"armor gipat_highest_gloves thin": [
		"d95cd7c74c0eb7b539c92d00e5fb996df263084af0e6649d47512c02a1db6d15",
		"Gipath heavy gauntlets of thin leather\nThese gloves have one undeniable virtue: you have them.",
		"Gipather schwere Handschuhe aus dünnem Leder\nDiese Handschuhe haben einen unbestreitbaren Vorzug: Man besitzt sie."
	],
	"armor gipat_highest_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_helm tanned_thin": [
		"4a200c914c36c44cffaded302b2c95e2cd08e15ce940e9f5b8e85caa0919d1d8",
		"Gipath heavy helmet of hard leather\nA warrior who values their head will find a better helmet.",
		"Gipather schwerer Helm aus derbem Leder\nWer seinen Kopf schätzt, sucht sich einen besseren Helm."
	],
	"armor gipat_highest_helm thick": [
		"da09f6939041997f79a95acf3f5b64c0be07f005694ca1fba8e1bbe56e5c7b6e",
		"Heavy Gipath helmet · Tough leather\nA goblin meeting someone in this helmet will laugh for a long time. The wearer, sadly, will not.",
		"Gipather schwerer Helm · Starkes Leder\nEin Goblin, der jemanden mit diesem Helm trifft, wird lange lachen. Der Träger leider nicht."
	],
	"armor gipat_highest_helm thin": [
		"b6f2f39b763c8cc7de43f04ab0826e574db75de229685073b8f4a761cac63e8e",
		"Gipath heavy helmet of thin leather\nA head that considers this a helmet is hardly worth protecting!",
		"Gipather schwerer Helm aus dünnem Leder\nEin Kopf, der das für einen Helm hält, braucht wohl keinen Schutz!"
	],
	"armor gipat_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_leggins tanned_thin": [
		"9bb27830a2d7fec7e40665ffdfce5084035393440ab15e4310f15e192264762d",
		"Gipath heavy leggings of hard leather\nThese leggings protect against a young boar. Hunting a mature beast calls for stronger armour.",
		"Gipather schwere Beinlinge aus derbem Leder\nDiese Beinschienen schützen vor einem jungen Eber. Für ausgewachsene Tiere braucht man stärkere Rüstung."
	],
	"armor gipat_highest_leggins thick": [
		"2db46b5b28b5875afe9eaa960ad97f4809796216c775bfec8699323ab84d50ad",
		"Heavy Gipath leggings · Tough leather\nThe protection matches the price: poor.",
		"Gipather schwere Beinlinge · Starkes Leder\nDer Schutz entspricht dem Preis: schlecht."
	],
	"armor gipat_highest_leggins thin": [
		"a316f728daf72da9ae5988312d82127b2a7a744d94538281aac9afb8fb5eec71",
		"Gipath heavy leggings of thin leather\nThese are leggings? A poor joke.",
		"Gipather schwere Beinlinge aus dünnem Leder\nDas sollen Beinschienen sein? Ein schlechter Scherz."
	],
	"armor gipat_highest_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_pants tanned_thin": [
		"8b1d2b2d28d156a431e099c55b06b1533e640ad263894268b26756b69c50634c",
		"Heavy Gipath long trousers · Hard leather\nPlain work trousers. Something stronger is needed against teeth and claws.",
		"Gipather schwere Hosen · Hartes Leder\nEinfache Arbeitshose. Gegen Zähne und Krallen braucht man etwas Festeres."
	],
	"armor gipat_highest_pants thick": [
		"0dc5947745e226a477156f37d7f84f994a67e9de59911782bfd69f7b48a10ac2",
		"Heavy Gipath long trousers · Tough leather\nNot the best protection for your feet, but inexpensive.",
		"Gipather schwere Hosen · Starkes Leder\nNicht der beste Schutz für die Füße, dafür günstig."
	],
	"armor gipat_highest_pants thin": [
		"bc14bc530b3e481ea30a303e3e2fdf634a777a243618f778b1a9d675e9827b28",
		"Heavy Gipath long trousers · Thin leather\nThese trousers will cover your nakedness.",
		"Gipather schwere Hosen · Dünnes Leder\nMit dieser Hose kann man seine Blöße bedecken."
	],
	"armor gipat_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_plate tanned_thin": [
		"f2d22818a6a795a428e9aa498ca19710341618bf379bb6c5c26857bd40ad4116",
		"Gipath heavy coat of hard leather\nThis coat is light and allows free movement, but better protection must be sought elsewhere.",
		"Gipather schwerer Mantel aus derbem Leder\nDieser Mantel ist leicht und lässt Bewegungsfreiheit, doch für besseren Schutz muss man weitersuchen."
	],
	"armor gipat_highest_plate thick": [
		"e7696919e7bef87c9a930f9a15c46407a979b6e46f04248b60e118534c4ddfb7",
		"Heavy Gipath coat · Tough leather\nThis coat could barely protect you from thorny bushes.",
		"Gipather schwerer Mantel · Starkes Leder\nDieser Mantel schützt kaum vor Dornenbüschen."
	],
	"armor gipat_highest_plate thin": [
		"c267ebcfea989a1450d06e97da0091439d46ecddf5dee15d696903b92ff9c7ec",
		"Gipath heavy coat of thin leather\nOnly the poor wear coats like these.",
		"Gipather schwerer Mantel aus dünnem Leder\nSolche Mäntel tragen nur arme Leute."
	],
	"armor gipat_highest_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_highest_shirt tanned_thin": [
		"7eacc99951439e7dca77c174f9ed3598e5a75753e9de9e8cb6b61aa6db83d48f",
		"Gipath heavy shirt of hard leather\nCheap and cheerful.",
		"Gipather schweres Hemd aus derbem Leder\nBillig und brauchbar."
	],
	"armor gipat_highest_shirt thick": [
		"4e0a54a3716e6b7656a9c5e554cd0b69baab16330d4bcd5ad42b3e190d0de4b0",
		"Heavy Gipath shirt · Tough leather\nThis shirt keeps off rain reasonably well, but water still runs down the collar.",
		"Gipather schweres Hemd · Starkes Leder\nDieses Hemd hält Regen recht gut ab, doch am Kragen läuft trotzdem Wasser hinein."
	],
	"armor gipat_highest_shirt thin": [
		"876ee9654a4a050ba49bdf0ef7494236f9c79bb4576732c7b324f92b940dbc4b",
		"Gipath heavy shirt of thin leather\nThis shirt will only protect against mosquito bites.",
		"Gipather schweres Hemd aus dünnem Leder\nDieses Hemd schützt nur vor Mückenstichen."
	],
	"armor gipat_low_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_boots tanned_thin": [
		"2ec0bfc955f2be0f415cdb76e28f3be0d58004fd33482edfc9c306f4479f3be5",
		"Gipath light boots of hard leather\nDecent footwear if you do not have far to go.",
		"Gipather leichte Stiefel aus derbem Leder\nGute Stiefel - wenn man nicht weit laufen muss."
	],
	"armor gipat_low_boots thick": [
		"8baddbba8122bfef3179689b32d4d7aaddfc1d153fe732e35ab09f93f51dd1c7",
		"Light Gipath boots · Tough leather\nQuite average footwear. You could do better than that.",
		"Gipather leichte Stiefel · Starkes Leder\nWeit verbreitet, aber es gibt bessere Stiefel."
	],
	"armor gipat_low_boots thin": [
		"c849f4c3ef244fdc066465b8e3fe2d0c8e42274174e8a9e629418800807fbcb1",
		"Gipath light boots of thin leather\nBetter than walking barefoot, but not by much.",
		"Gipather leichte Stiefel aus dünnem Leder\nBesser als barfuß zu laufen, aber nicht viel."
	],
	"armor gipat_low_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_gloves tanned_thin": [
		"befdd34dcd20866c539459b66d415f16cce58f7be78037a4b038ff04be83432f",
		"Gipath light gauntlets of hard leather\nNow you can risk getting into a fight - but not into combat!",
		"Gipather leichte Handschuhe aus derbem Leder\nFür eine Schlägerei ausreichend, für einen ernsthaften Kampf taugen sie allerdings nicht!"
	],
	"armor gipat_low_gloves thick": [
		"c40cd3b5e737bcef596623d0221c9cc3d73d506f48dadbc564f184a32dc8cc25",
		"Light Gipath gauntlets · Tough leather\nDespite their solid appearance, they still provide more decoration than protection.",
		"Gipather leichte Handschuhe · Starkes Leder\nObwohl sie sehr stabil aussehen, sind diese Handschuhe mehr was fürs Auge als für den Kampf."
	],
	"armor gipat_low_gloves thin": [
		"f6a1a35be8cc6ce59757bef63fa8ad31ff03a529f2c86b218f55047891c29fbb",
		"Gipath light gauntlets of thin leather\nThese won't really protect your arms... But at least you will look like a warrior!",
		"Gipather leichte Handschuhe aus dünnem Leder\nDiese Handschuhe bieten kaum Schutz, aber man sieht wenigstens aus wie ein Krieger!"
	],
	"armor gipat_low_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_helm tanned_thin": [
		"9c5e9349a2b7eb8817c7f2aa559206829969e22e53814fdefad26d6b3cfee6fa",
		"Gipath light helmet of hard leather\nNow you can risk getting into a fight - but not into combat!",
		"Gipather leichter Helm aus derbem Leder\nFür eine Schlägerei ausreichend, für einen ernsthaften Kampf taugen sie allerdings nicht!"
	],
	"armor gipat_low_helm thick": [
		"f6ff3ffadfd092116c8375e79fdb67f797f5e67f802f979c210a426b3deb0aa8",
		"Light Gipath helmet · Tough leather\nIt will protect you from a pine cone falling on your head, but not from a stone…",
		"Gipather leichter Helm · Starkes Leder\nTannenzapfen können einem mit diesem Helm ruhig auf den Kopf fallen, Steinen sollte man aus dem Weg gehen..."
	],
	"armor gipat_low_helm thin": [
		"502cf54b6e2d4f012d99e72589faf0bcca7ba1d5a002fbfe41bc1c2b38d3dacb",
		"Gipath light helmet of thin leather\nMore decoration than protection.",
		"Gipather leichter Helm aus dünnem Leder\nMehr zur Verzierung als zum Schutz."
	],
	"armor gipat_low_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_leggins tanned_thin": [
		"846e8ad3ebd387d3cd717ce8514d86173163e47c93d9ae74ee6b9d2182287fed",
		"Gipath light leggings of hard leather\nMaybe they will save you from a wolf's teeth ... But, sadly, not from a blade or an axe.",
		"Gipather leichte Beinlinge aus derbem Leder\nSchützen wohl gegen den Biss eines Wolfs, aber kaum gegen eine Axt!"
	],
	"armor gipat_low_leggins thick": [
		"8138a6df7a12f1fcf795fbc93209b43d429d51793b02fffb7c8c7cd73417bfe9",
		"Light Gipath leggings · Tough leather\nCannot say they are totally useless. But you will not get much use out of them!",
		"Gipather leichte Beinlinge · Starkes Leder\nSind nicht völlig unnütz. Es gibt aber Besseres."
	],
	"armor gipat_low_leggins thin": [
		"f206ad4bfb9b5664b803f21646c7fe0c0bca1981aa6ce68dad8b1beef79d3ad5",
		"Gipath light leggings of thin leather\nThey save your knees and feet from accidental scratches and bruises, but not from weapons!",
		"Gipather leichte Beinlinge aus dünnem Leder\nSchützen die Beine gegen Stacheln und Dornen - nicht aber gegen Äxte und Klingen."
	],
	"armor gipat_low_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_pants tanned_thin": [
		"bc59f27e061b73d71e764d2c8f45e3d130f9eba0aa975d8173d7b43447d70045",
		"Gipath light trousers of hard leather\nThe hard leather is good, but it would be better still if these leggings were a bit longer!",
		"Gipather leichte Hosen aus derbem Leder\nDas derbe Leder ist gut, aber die Hosen könnten ein bisschen länger sein."
	],
	"armor gipat_low_pants thick": [
		"c4460ede9375a5b5b590281475ba9dda2396ffb1f70e488c78f8fd2910e0c4ed",
		"Light Gipath shorts · Tough leather\nProvide some protection; every little bit helps when such a valuable body part is at stake...",
		"Gipather leichte kurze Hosen · Starkes Leder\nBieten einen gewissen Schutz für die Beine."
	],
	"armor gipat_low_pants thin": [
		"1048eb1a9c833201dd221df08ad1e8692f3464d8edd33c78ebb2c51801dadb48",
		"Gipath light trousers of thin leather\nFlimsy protection, especially for such a valuable body part...",
		"Gipather leichte Hosen aus dünnem Leder\nBieten nur geringen Schutz für die Beine."
	],
	"armor gipat_low_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_plate tanned_thin": [
		"e50b2ec6cf98f7168ef9eb8bec6b55fc33d125196db553a92460b6e6c5d86848",
		"Gipath light shirt of hard leather\nMaybe they will save you from a wolf's teeth ... But, sadly, not from a blade or an axe.",
		"Gipather leichtes Hemd aus derbem Leder\nSchützen wohl gegen den Biss eines Wolfs, aber kaum gegen eine Axt!"
	],
	"armor gipat_low_plate thick": [
		"1d59750e0ca620b81753fe0636bba553b168c25feef3e78636b1a15c914166d9",
		"Light Gipath shirt · Tough leather\nIt will cover what your breastplate leaves unprotected. But it leaves a bit to be desired…",
		"Gipather leichtes Hemd · Starkes Leder\nSchützt die Bereiche, die der Brustpanzer nicht bedeckt. Ist aber keineswegs undurchdringlich."
	],
	"armor gipat_low_plate thin": [
		"a318b58d8dfed7ff6290fd25e0794e3f8bb7f53b5f28c7971b640674ac99a3e3",
		"Gipath light shirt of thin leather\nNot the best option, but sufficient if you do not have anything else.",
		"Gipather leichtes Hemd aus dünnem Leder\nNicht die beste Wahl, aber ausreichend, wenn nichts anderes zur Verfügung steht."
	],
	"armor gipat_low_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_low_shirt tanned_thin": [
		"8d0d1458c67346eaab5e536d95956ba8d7e0460b1cdbf5bf36eaaa9959497efb",
		"Gipath light breastplate of hard leather\nA piece of hard leather covering upper body, it provides good protection from light weapons.",
		"Gipather leichter Brustpanzer aus derbem Leder\nBietet dem Oberkörper guten Schutz gegen leichte Waffen."
	],
	"armor gipat_low_shirt thick": [
		"413060d765afeb8b475fa8a8699ffa82001ad2d6a16b5169a839520d96d05916",
		"Light Gipath breastplate · Tough leather\nA piece of tough leather partly covering the body. Offers little protection.",
		"Gipather leichter Brustpanzer · Starkes Leder\nEin Stück festen Leders, das den Körper teilweise bedeckt. Bietet wenig Schutz."
	],
	"armor gipat_low_shirt thin": [
		"24c7718153bb3bc1865a2e3b1e787e6ddc0e14c6812381d1b7992808e2e5ef24",
		"Gipath light breastplate of thin leather\nA piece of thin leather covering part of your upper body... it may even protect you from the sun's rays.",
		"Gipather leichter Brustpanzer aus dünnem Leder\nEin dünnes Stückchen Leder - schützt höchstens vor Wind."
	],
	"armor gipat_medium_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_boots tanned_thin": [
		"cc9fe2523b41f1e8eea5abc6b5c1985eddbe2b6806c0b2e4c855aa0a74a5cf42",
		"Gipath simple boots of hard leather\nThe best leather boots possible.",
		"Gipather einfache Stiefel aus derbem Leder\nDie besten Lederstiefel, die es gibt."
	],
	"armor gipat_medium_boots thick": [
		"93c10e80259f3c206185e6ffe5aa0d418f4e0585e5d1c8e1d342ad9d24278550",
		"Simple Gipath boots · Tough leather\nSimple and comfortable. And not very expensive, either.",
		"Gipather einfache Stiefel · Starkes Leder\nEinfach, bequem und preiswert."
	],
	"armor gipat_medium_boots thin": [
		"749f0d9ab90d263a36172bc20f49b636a2b724008a0a62cf56aeafc870376389",
		"Gipath simple boots of thin leather\nNot very protective - but you cannot expect much for that sort of price, can you?",
		"Gipather einfache Stiefel aus dünnem Leder\nNicht gerade stabil - aber für diesen Preis kann man auch nicht mehr erwarten."
	],
	"armor gipat_medium_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_gloves tanned_thin": [
		"0ffd07a13c344a802199fd8d76e0e919bd5102534542f5ea68f4969b12baea3e",
		"Gipath simple gauntlets of hard leather\nDecent protection for the part of your arm which it covers. Unfortunately, most of your arm remains bare!",
		"Gipather einfache Handschuhe aus derbem Leder\nBieten guten Schutz - leider bleiben große Teile des Arms unbedeckt."
	],
	"armor gipat_medium_gloves thick": [
		"549784ff865f38dcf3d6270281148b96c408af208a832bfb206d074d67662ddd",
		"Simple Gipath gauntlets · Tough leather\nThey can protect part of your arm from accidental scratches and cuts.",
		"Gipather einfache Handschuhe · Starkes Leder\nSchützen die Hände vor Dornen und Stacheln."
	],
	"armor gipat_medium_gloves thin": [
		"bba7a77c9c66b346dee6c5c76d262342dd2044fc841cfabd9c1823a01de7bfec",
		"Gipath simple gauntlets of thin leather\nThey look good, but are not very useful for protection.",
		"Gipather einfache Handschuhe aus dünnem Leder\nSehen schön aus - sind aber wenig nützlich."
	],
	"armor gipat_medium_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_helm tanned_thin": [
		"0a73e200605f0b0cba7caa7e41b67278a68c3c6ee868c15065b66d3964e13e5f",
		"Gipath simple helmet of hard leather\nSuch a helmet will save your head from the first strike, but not the second one …",
		"Gipather einfacher Helm aus derbem Leder\nDieser Helm schützt wohl vor einem Schlag - kaum aber vor dem zweiten."
	],
	"armor gipat_medium_helm thick": [
		"72a750a13cb90fef4f32d8c40acf83f98a3d8fd5d053c861ad54f0616fadf202",
		"Simple Gipath helmet · Tough leather\nIt will protect you from a pine cone falling on your head, but not from a stone…",
		"Gipather einfacher Helm · Starkes Leder\nTannenzapfen können einem mit diesem Helm ruhig auf den Kopf fallen. Steinen geht man besser aus dem Weg..."
	],
	"armor gipat_medium_helm thin": [
		"58374ce523c57f06c93e3356fd82feb00ee26e7df4b229ebbef1eed78d0075fe",
		"Gipath simple helmet of thin leather\nBetter than nothing, but another material would be worth considering.",
		"Gipather einfacher Helm aus dünnem Leder\nBesser als nichts, doch anderes Material wäre eine Überlegung wert."
	],
	"armor gipat_medium_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_leggins tanned_thin": [
		"99adf6d261ad7bd46b082b46640e3d71bc948258f9ef3af2c3d8cabdba44555a",
		"Gipath simple leggings of hard leather\nProvides decent protection for your legs, but with that sort of material other designs may be better.",
		"Gipather einfache Beinlinge aus derbem Leder\nAnständiger Schutz für die Beine. Besser wäre aber ein anderer Schnitt."
	],
	"armor gipat_medium_leggins thick": [
		"7cf905e67d910f3a767acad877ddcac8eb2b03f54b65dca423de8a626ce1f9ef",
		"Simple Gipath leggings · Tough leather\nGive added protection to your legs, though better is available.",
		"Gipather einfache Beinlinge · Starkes Leder\nZusätzlicher Schutz für die Beine - nicht allzu stabil."
	],
	"armor gipat_medium_leggins thin": [
		"f079ea743c535370c7c12930a91aef3722761e80bbb3a9433af339ce7032ea78",
		"Gipath simple leggings of thin leather\nThey will protect your legs from splinters and thorns ... what else could you expect for that price?",
		"Gipather einfache Beinlinge aus dünnem Leder\nSchutz gegen Splitter und Dornen. Mehr kann man für den Preis auch nicht erwarten!"
	],
	"armor gipat_medium_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_pants tanned_thin": [
		"87946f942fb2729ec6af0e287b13469f3440141a8011c644622a76d1b4890f68",
		"Simple Gipath shorts · Hard leather\nProvide decent protection for the part of the leg they cover. Unfortunately, most of your leg remains bare!",
		"Gipather einfache kurze Hosen · Hartes Leder\nBieten guten Schutz - bedecken aber nur einen kleinen Teil des Beins."
	],
	"armor gipat_medium_pants thick": [
		"809f4a706fcec8f84a5387e191ba98e5084e53e475b028044bb32352ec3555af",
		"Simple Gipath shorts · Tough leather\nNothing special. Just pants, really, except they are a bit tougher than the ones made of thin leather.",
		"Gipather einfache kurze Hosen · Starkes Leder\nNichts Besonderes. Allerdings ein bisschen stabiler als Hosen aus dünnem Leder."
	],
	"armor gipat_medium_pants thin": [
		"91645a32b915f9ff4c0f31cd0491c26c3026e6fd11bd0e0f9b88cf6a0c716332",
		"Simple Gipath shorts · Thin leather\nThese are nothing special. Not a lot of protection, for not a lot of money.",
		"Gipather einfache kurze Hosen · Dünnes Leder\nNichts Besonderes. Ganz normale Hosen."
	],
	"armor gipat_medium_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_plate tanned_thin": [
		"fb493a9872b05e4d0cc6901514e0584446654268d46ac85707cad06c5cfe4095",
		"Gipath simple coat of hard leather\nDecent protection from a wolf's teeth and a boar's fangs, but it may not stand up against sharp weapons.",
		"Gipather einfacher Mantel aus derbem Leder\nSchützt wohl gegen den Biss eines Wolfs, aber kaum gegen eine Axt!"
	],
	"armor gipat_medium_plate thick": [
		"c650c24fa833414d930d8946dd97067940767d7aa026ebc2afaecdf94986ce5f",
		"Simple Gipath cloak · Tough leather\nNow you can risk venturing into a forest. (providing, of course, you do not go too far).",
		"Gipather einfacher Umhang · Starkes Leder\nErhöht die Chancen, wohlbehalten aus dem Wald zurückzukehren - solange man nicht zu tief hineingeht."
	],
	"armor gipat_medium_plate thin": [
		"6e3677e89dc9edbbbb7af2528969b9f522fa0d50242e3b86bb8a311d5aceb2bc",
		"Gipath simple coat of thin leather\nA strange mix of design and material. Only very poor people would think of making such things.",
		"Gipather einfacher Mantel aus dünnem Leder\nSeltsamer Schnitt, merkwürdiges Material. Minderwertige Ware."
	],
	"armor gipat_medium_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_medium_shirt tanned_thin": [
		"f532b7e3eb57a1b5e88b7e2aa8bfd72d4502c01e5a9d0e68ef0c0e44b51a3fc7",
		"Gipath simple breastplate of hard leather\nDecent price/performance ratio.",
		"Gipather einfacher Brustpanzer aus derbem Leder\nAnnehmbarer Schutz zu einem guten Preis."
	],
	"armor gipat_medium_shirt thick": [
		"9d79cd24516f421c2e1dbb036aa277861eeef0edf9d1b213aacbd7bf4c649293",
		"Simple Gipath breastplate · Tough leather\nIt is not bad, but certainly better is available.",
		"Gipather einfacher Brustpanzer · Starkes Leder\nNicht schlecht für einen einfachen Brustpanzer."
	],
	"armor gipat_medium_shirt thin": [
		"17cfd780d61cbd26ce93a94f8af347bd92a3a9e72c5c9e35ae1d34093958f41d",
		"Gipath simple breastplate of thin leather\nHere is a garment for these who do not anticipate very dangerous encounters.",
		"Gipather einfacher Brustpanzer aus dünnem Leder\nNur für Leute, denen keine ernsthafte Gefahr droht."
	],
	"armor gipat_special_brigand_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_helm tiger_hide": [
		"924e6761051b0de4436b2a59c1223645a89004b522d5c6641f2d16958ef6b9bb",
		"Kroshka's cap\nKroshka wears this cap.",
		"Kroshkas Mütze\nDiese Mütze trägt Kroshka."
	],
	"armor gipat_special_brigand_helm tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_helm tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_pants tiger_hide": [
		"9171631bbc2741ca00285aedbacfd9ad5e56d0e7e0893c8accd550bc0ba71f31",
		"Kroshka's trousers\nThese trousers were made especially for Kroshka.",
		"Kroshkas Hose\nDiese Hose wurde eigens für Kroshka angefertigt."
	],
	"armor gipat_special_brigand_pants tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_pants tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_plate tiger_hide": [
		"eaf03a68d79d2589bf4d249efd1c0e827664e5e5a445f5c9e3f2c45e275928e6",
		"Kroshka's cloak\nKroshka wears this kind of cloak.",
		"Kroshkas Umhang\nEinen solchen Umhang trägt Kroshka."
	],
	"armor gipat_special_brigand_plate tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_plate tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_shirt tiger_hide": [
		"27d4d3579dbf6d6fa3510ca047265cd03455d765f68953c48cc30142bef344d9",
		"Kroshka's hide\nThe great Kroshka wears this armour.",
		"Kroshkas Fell\nDiese Rüstung trägt die große Kroshka."
	],
	"armor gipat_special_brigand_shirt tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_brigand_shirt tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_high_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_high_plate tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_high_plate thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_high_plate thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_helm tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_helm thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_helm thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_leggins tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_leggins thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_leggins thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_plate tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_plate thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor gipat_special_highest_plate thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_boots tanned_thin": [
		"8ebe828d0ed0ecd9aa0c78bda006502016b7a353ba24272f9a6e0db7141175af",
		"Khadaganian hard leather leggings\nVery good for long marches.",
		"Khadaganianische Beinlinge aus derbem Leder\nPerfekt für lange Märsche."
	],
	"armor hadagan_brigand_boots thick": [
		"90a67e508b4ca0833e14fa4a9b76f03d4d3c25fafa88ff67adf664768c7fe6e3",
		"Khadaganian leather leggings · Tough leather\nGood enough for hunters, but not for warriors.",
		"Khadaganianische Leder-Beinlinge · Starkes Leder\nGeeignet für Jäger - nicht aber für Krieger."
	],
	"armor hadagan_brigand_boots thin": [
		"1cb31b728faaffe14145a1d745591a0522b1045c3ac7205736f2eb6871983321",
		"Khadaganian thin leather leggings\nNot strong, but light.",
		"Khadaganianische Beinlinge aus dünnem Leder\nNicht sehr stabil, aber leicht."
	],
	"armor hadagan_brigand_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_gloves tanned_thin": [
		"a15187086d9850f6de75bdd7d4f577e074317f96e71eb2de354b23db3f6a01fa",
		"Khadaganian hard leather gauntlets\nEnough to turn a wolf's fangs, most likely.",
		"Khadaganianische Handschuhe aus derbem Leder\nDie sind nicht für jeden Wolf zu durchdringen."
	],
	"armor hadagan_brigand_gloves thick": [
		"6da3447f62bf162b3acedaadbe3a69aa7f5e1c18cc815da80ca8dd430cacbd30",
		"Khadaganian leather gauntlets · Tough leather\nThese will protect your hands from thorns - and maybe even from wolf's teeth.",
		"Khadaganianische Lederhandschuhe · Starkes Leder\nSchützen die Hände vor Dornen - und vielleicht auch vor Wölfen."
	],
	"armor hadagan_brigand_gloves thin": [
		"b5a5ba8a30c85c4e23d112b2781ae2f92df2397c2d30c996bfca0a3c76e70833",
		"Khadaganian thin leather gauntlets\nGood enough for a fist fight at a village festival.",
		"Khadaganianische Handschuhe aus dünnem Leder\nNur ausreichend für eine Schlägerei auf dem Dorffest."
	],
	"armor hadagan_brigand_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_helm tanned_thin": [
		"79903aaf774177d8524745837881bcda6ca31f1848ca16ff339619a80b2c5542",
		"Khadaganian hard leather helmet\nThis may save you from a blow to the head.",
		"Khadaganianischer Helm aus derbem Leder\nDieser Helm kann unter Umständen den Kopf vor einem schlecht gezielten Schlag retten."
	],
	"armor hadagan_brigand_helm thick": [
		"70a2a2a3bffbf91810238ca463358efcf3734a8cfdcbb5dc52cacc2bc8f9657c",
		"Khadaganian leather helmet · Tough leather\nProvides certain protection, but do not rely on it too much in combat.",
		"Khadaganianischer Lederhelm · Starkes Leder\nBietet angemessenen Schutz, ist aber kaum für den Kampf geeignet."
	],
	"armor hadagan_brigand_helm thin": [
		"ed2b2f185d3afc4c03320866bddceb76cacaa1addbc574a7fddf2acb134a2363",
		"Khadaganian thin leather helmet\nThis will protect your head from a falling pine cone - but not from a good blow.",
		"Khadaganianischer Helm aus dünnem Leder\nTannenzapfen können einem mit diesem Helm ruhig auf den Kopf fallen. Ein Stein besser nicht..."
	],
	"armor hadagan_brigand_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_leggins tanned_thin": [
		"f1c82f2cc7abe99346423586f298dd4719e4405c721e3ef0e59368dc94ec4a3b",
		"Khadaganian hard leather top leggings\nDo not kick a sleeping Tiger when you are wearing only these…",
		"Khadag. Überbeinlinge aus derbem Leder\nMit diesen Beinlingen sollte man nicht unbedingt einen schlafenden Tiger treten."
	],
	"armor hadagan_brigand_leggins thick": [
		"52a31ab2dc728068218698b28442cb906b38fd4c1a97b7181c7540401c465f0e",
		"Khadaganian leather top leggings · Tough leather\nWould come in handy for a walk in thorny vegetation.",
		"Khadaganianische Überbeinlinge aus Leder · Starkes Leder\nSchutz gegen Stacheln und Dornen."
	],
	"armor hadagan_brigand_leggins thin": [
		"82a202ba48aadfcfe09d33a92748b6ed51e9aed7ac512271a5f9e7a3047b3be6",
		"Khadaganian thin leather top leggings\nAlmost completely useless in combat.",
		"Khadag. Überbeinlinge aus dünnem Leder\nIm Kampf nahezu vollkommen wertlos."
	],
	"armor hadagan_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_pants tanned_thin": [
		"98e6bcba9b7dd5fa6f806fc3ad52c405665e7a8efb10f41947409a6ebcc5484c",
		"Khadaganian hard leather trousers\nThey offer a little protection, though they are not meant for serious combat.",
		"Khadaganianische Hosen aus derbem Leder\nSie bieten etwas Schutz, sind aber nicht für ernsthafte Kämpfe gedacht."
	],
	"armor hadagan_brigand_pants thick": [
		"75bc4d0aa49cd0c4f553332e27e2f2982357054d03d18cdb3292d8c135cd9b56",
		"Khadaganian leather trousers · Tough leather\nThese will save you from a spider's bite... But not from much more.",
		"Khadaganianische Lederhosen · Starkes Leder\nDen Biss einer Spinne können diese Hosen abwehren - mehr allerdings auch nicht."
	],
	"armor hadagan_brigand_pants thin": [
		"b57d854bc176eaa96e43ecd66e8bcaaef76bb58df628b1dae427f9f02aa255ab",
		"Khadaganian thin leather trousers\nAlmost no protection at all, at least they're comfortable.",
		"Khadaganianische Hosen aus dünnem Leder\nBieten keinen Schutz, sind aber sehr angenehm zu tragen."
	],
	"armor hadagan_brigand_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_plate tanned_thin": [
		"642a52fbb5e0b889c3690623a382d9720b5c0be44be2e8710ec441c44551ed13",
		"Khadaganian hard leather coat\nProvides decent protection against wild beasts.",
		"Khadaganianischer Mantel aus derbem Leder\nAnnehmbarer Schutz vor den Angriffen wilder Tiere."
	],
	"armor hadagan_brigand_plate thick": [
		"e9c7307a91adba795e03328fab311c78b82915ac90317ff0c4f84afb7807201c",
		"Khadaganian leather coat · Tough leather\nGood for travel - if you are not expecting to face enemies.",
		"Khadaganianischer Ledermantel · Starkes Leder\nGut für Reisen, auf denen man nicht erwartet angegriffen zu werden."
	],
	"armor hadagan_brigand_plate thin": [
		"572c27a41d9a946e313a9be223a558077862ce5ba9b8148da7fb24866f987822",
		"Khadaganian thin leather coat\nThin and flimsy - but light.",
		"Khadaganianischer Mantel aus dünnem Leder\nDünn - aber leicht."
	],
	"armor hadagan_brigand_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_brigand_shirt tanned_thin": [
		"658fc76707cf43fb1bd49a81b613a47985634312f5606d7e6d9ad82838b74b63",
		"Khadaganian leather lower breastplate · Hard leather\nThis is some good protective equipment.",
		"Khadaganianischer großer Brustpanzer aus Leder · Hartes Leder\nEine wahrlich beachtliche Panzerung."
	],
	"armor hadagan_brigand_shirt thick": [
		"e687b83cc4896d934f3922b22ba20a1ae152259b139fae1431198fd0573c56f4",
		"Khadaganian leather lower breastplate · Tough leather\nStronger than thin leather. Good enough for hunting.",
		"Khadaganianischer großer Brustpanzer aus Leder · Starkes Leder\nEtwas stabiler als dünnes Leder. Ausreichend für die Jagd."
	],
	"armor hadagan_brigand_shirt thin": [
		"1c0e16c05bc67ced7cdd9d8bb6e6c09d658e1d8fd84e4ef9b49b974d10db51fb",
		"Khadaganian leather lower breastplate · Thin leather\nThin leather is not the best possible protection for a warrior.",
		"Khadaganianischer großer Brustpanzer aus Leder · Dünnes Leder\nDünnes Leder ist nichts für einen Krieger."
	],
	"armor hadagan_high1_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots bronze": [
		"5f58d4f6e65ecec2b57db33c62b507ec66ebcb148677c1e2a5add9755e3654ee",
		"Khadaganian bronze laminar boots\nUse better material, and they will be perfect!",
		"Khadaganianische Bronze-Panzerstiefel\nEin anderes Material  - und sie wären perfekt."
	],
	"armor hadagan_high1_boots iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_boots steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves bronze": [
		"aed172698994b5283a275ae064375f6a7be16e04af3ad855e873b9127ed63214",
		"Khadaganian bronze laminar gauntlets\nBronze is too soft and heavy to protect well.",
		"Khadaganianische Bronze-Panzerhandschuhe\nBronze ist zu weich und zu schwer, um Handschuhe daraus zu machen."
	],
	"armor hadagan_high1_gloves iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_gloves steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants bronze": [
		"96958756dc224dc23650bad2efa9ef83143731ce329a3eedddc035897cff25bb",
		"Khadaganian bronze chainmail trousers\nWill not last long in combat...",
		"Khadaganianische Kettenhosen aus Bronze\nHält keinen Kampf lange aus."
	],
	"armor hadagan_high1_pants iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_pants steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt bronze": [
		"fc07de1ba3df25dc08733f71412c309ab168e99fd410d0b752df6a67cf355d60",
		"Light Hadagan chain mail · Bronze\nToo heavy and uncomfortable...",
		"Leichtes hadaganisches Kettenhemd · Bronze\nZu schwer und unbequem ..."
	],
	"armor hadagan_high1_shirt iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high1_shirt steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_boots adamantium": [
		"90fce0df38285cd6a6308befbbfb4795cc8d96989050619f6021c7a395789789",
		"Khadaganian adamantite laminar boots\nProtect your feet from almost any blow.",
		"Khadaganianische Adamant-Panzerstiefel\nSchützt die Füße gegen fast alles."
	],
	"armor hadagan_high2_boots bronze": [
		"5f58d4f6e65ecec2b57db33c62b507ec66ebcb148677c1e2a5add9755e3654ee",
		"Khadaganian bronze laminar boots\nUse better material, and they will be perfect!",
		"Khadaganianische Bronze-Panzerstiefel\nEin anderes Material  - und sie wären perfekt."
	],
	"armor hadagan_high2_boots iron": [
		"b6db618bf71b2dda77df9138e21dc607e77d3d952763801cc0750bb6c3ef2afb",
		"Khadaganian iron laminar boots\nGood protection, but not the best possible.",
		"Khadaganianische Eisen-Panzerstiefel\nGuter Schutz. Es gibt aber bessere."
	],
	"armor hadagan_high2_boots meteoric": [
		"da50d34763a68dbfae06f4f52c27cf99d6bf5bc3e153d8b979b83267a3f25571",
		"Khadaganian meteorite laminar boots\nTogether with the leggings, these make perfect protection for feet and legs!!",
		"Khadag. Meteorit-Eisen-Panzerstiefel\nZusammen mit Beinlingen der ideale Beinschutz."
	],
	"armor hadagan_high2_boots mithrill": [
		"f6ef2ac85fc289f2bb25ac8f8f51432e81ce9d927a9ba4801ce5fd4bfb6a3b52",
		"Khadaganian mithrill laminar boots\nWorth any price!",
		"Khadaganianische Mithril-Panzerstiefel\nWas sie auch kosten mögen - sie sind ihr Geld wert."
	],
	"armor hadagan_high2_boots steel": [
		"4a817d5138bec7b03988d518c2a740d8f5adec66553e6b1a9f858a72d70e0c44",
		"Khadaganian steel laminar boots\nTogether with the leggings, these provide excellent protection for legs and feet.",
		"Khadaganianische Stahl-Panzerstiefel\nZusammen mit Beinlingen der ideale Beinschutz."
	],
	"armor hadagan_high2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_gloves adamantium": [
		"8d5e7fa8cb83c91fbf772050d493044ad546acd3c9d049db2b952392bcdf517a",
		"Khadaganian adamantite laminar gauntlets\nOnly meteorite gauntlets are better!",
		"Khadaganianische Adamant-Panzerhandschuhe\nNur Handschuhe aus Meteorit-Eisen sind besser!"
	],
	"armor hadagan_high2_gloves bronze": [
		"aed172698994b5283a275ae064375f6a7be16e04af3ad855e873b9127ed63214",
		"Khadaganian bronze laminar gauntlets\nBronze is too soft and heavy to protect well.",
		"Khadaganianische Bronze-Panzerhandschuhe\nBronze ist zu weich und zu schwer, um Handschuhe daraus zu machen."
	],
	"armor hadagan_high2_gloves iron": [
		"17a5529741d0b9e410a47b1c8ba943ee2b20f2cb445f6ed1aa6b6334cb1bf61d",
		"Khadaganian iron laminar gauntlets\nSuch high-class armor should be made of better metals.",
		"Khadaganianische Eisen-Panzerhandschuhe\nHochwertige Panzerung ist normalerweise aus besserem Metall."
	],
	"armor hadagan_high2_gloves meteoric": [
		"45d57b72ac9983e0b1cacaf61995a5d1c95cee4e065c8af448106bf62a044ef6",
		"Khadaganian meteorite laminar gauntlets\nThese can easily fend off a sword blow!",
		"Khadag. M.-Eisen-Panzerhandschuhe\nMit denen kann man sogar einen Schwerthieb abwehren!"
	],
	"armor hadagan_high2_gloves mithrill": [
		"a445081b4ba3e0fe7f7ddee4b03d334dbb0b9dd13cb24dc0a75c5cd12804a1d3",
		"Khadaganian mithrill laminar gauntlets\nMithrill's lightness and flexibility make it perfect armor material!",
		"Khadaganianische Mithril-Panzerhandschuhe\nDurch sein geringes Gewicht und die hohe Flexibilität ist Mithril das ideale Material für Handschuhe."
	],
	"armor hadagan_high2_gloves steel": [
		"fef8719a7346e4ddae67c806eb2b51fc126046e43c2edfa624eecc57abdda7cf",
		"Khadaganian steel laminar gauntlets\nSerious protection.",
		"Khadaganianische Stahl-Panzerhandschuhe\nExtrem hohe Widerstandsfähigkeit."
	],
	"armor hadagan_high2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_helm adamantium": [
		"775bbf384b94f1e4cb071ef68fb3f8e4a5bf75ae3f357fe2a63fbcdfc3521856",
		"Khadaganian forged adamantite helmet\nIt is pretty, it is strong... and expensive.",
		"Khadaganianischer geschmiedeter Adamanthelm\nSchön, stabil... und teuer."
	],
	"armor hadagan_high2_helm bronze": [
		"aa98a02c548adf56763403a33d3013286bd8fcdc4eeafc5e3342088c20a515ce",
		"Khadaganian forged bronze helmet\nPerfectly made! If only there were better metal available…",
		"Khadaganianischer geschmiedeter Bronzehelm\nPerfekt verarbeitet! Aber das Material lässt zu wünschen übrig."
	],
	"armor hadagan_high2_helm iron": [
		"3f071908972e5f74627cfc123f310258f591ecc72d00d242ae6a15d55e48df5a",
		"Khadaganian forged iron helmet\nYou should add decent material to the smith's good work.",
		"Khadaganianischer geschmiedeter Eisenhelm\nDiese Schmiedearbeit hätte besseres Material verdient."
	],
	"armor hadagan_high2_helm meteoric": [
		"2e7c30e6c394b61ce23feb46e2dd1b8ac8a0c287bd120f62b72de26999642ed7",
		"Khadaganian forged meteorite helmet\nThe worst which can happen to your head now is a concussion!",
		"Khadag. geschmiedeter Meteorit-Eisenhelm\nMit diesem Helm ist das Schlimmste, was einem passieren kann, eine Gehirnerschütterung."
	],
	"armor hadagan_high2_helm mithrill": [
		"0a24a528eb9560ec6603be63191c3aa9ad06c8738ca12ae119c4018a99f8f89e",
		"Khadaganian forged mithrill helmet\nFew weapons can pierce this helmet.",
		"Khadaganianischer geschmiedeter Mithrilhelm\nDiesem Helm kann keine Waffe etwas anhaben."
	],
	"armor hadagan_high2_helm steel": [
		"75e9b23a411494702b8614636bc6ccbc4d1f18ed9b16882cdf05f1a90079a0d9",
		"Khadaganian steel forged helmet\nVery good head protection.",
		"Khadaganianischer geschmiedeter Stahlhelm\nExzellenter Kopfschutz."
	],
	"armor hadagan_high2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_leggins adamantium": [
		"f39d8ffd975ae43983beb10eea7d658a41a975fc669587943002403a57f5f2db",
		"Khadaganian forged top leggings · Adamantite\nProbably the best leggings.",
		"Khadaganianische geschm. Überbeinlinge · Adamantit\nWahrscheinlich die besten Beinlinge."
	],
	"armor hadagan_high2_leggins bronze": [
		"963050c9c3d980cca4f429fb332e61c6c2ddba8e506c727f95dcc0ab7946421f",
		"Khadaganian forged bronze top leggings\nGood work - but cheap material …",
		"Khadag. geschmiedete Bronze-Überbeinlinge\nGute Arbeit - schlechtes Material."
	],
	"armor hadagan_high2_leggins iron": [
		"5824d05fac9cfcd53576ea8c50b6778d0997f04fec311b40b5e1b73aa1e5fc5f",
		"Khadaganian forged iron top leggings\nGood additional leg protection.",
		"Khadag. geschmiedete Eisen-Überbeinlinge\nEin guter zusätzlicher Schutz für die Beine."
	],
	"armor hadagan_high2_leggins meteoric": [
		"1b1236094a3290fe4ae78211d99219cc0971d908b7738f9d76663461aa05c48f",
		"Khadaganian forged top leggings · Meteorite\nA perfect mix of metal and design!",
		"Khadaganianische geschm. Überbeinlinge · Meteorit\nDie perfekte Mischung aus Material und Schnitt."
	],
	"armor hadagan_high2_leggins mithrill": [
		"23edbe52a66bdbbf74576f7ee5dfa40343638fa526fb36067ce845fad2227ec2",
		"Khadaganian forged top leggings · Mithrill\nGood price/quality ratio.",
		"Khadaganianische geschm. Überbeinlinge · Mithril\nGuter Schutz zu einem annehmbaren Preis."
	],
	"armor hadagan_high2_leggins steel": [
		"107513c6a5c434452e31f2f86a7a264873fb68b7f026ef83b53fd71927baf879",
		"Khadaganian forged steel top leggings\nVery good additional leg protection.",
		"Khadag. geschmiedete Stahl-Überbeinlinge\nSehr guter Zusatzschutz für die Beine!"
	],
	"armor hadagan_high2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_pants adamantium": [
		"ce486809cfeed46c8133e6caeb66bbc0d51f2b34281d626fcd9521b5b8ce9829",
		"Khadaganian chainmail trousers · Adamantite\nA silly Tiger would simply break its teeth on these.",
		"Khadaganianische Kettenhosen · Adamantit\nAn dieser Hose würde sich jeder Tiger die Zähne ausbeißen."
	],
	"armor hadagan_high2_pants bronze": [
		"96958756dc224dc23650bad2efa9ef83143731ce329a3eedddc035897cff25bb",
		"Khadaganian bronze chainmail trousers\nWill not last long in combat...",
		"Khadaganianische Kettenhosen aus Bronze\nHält keinen Kampf lange aus."
	],
	"armor hadagan_high2_pants iron": [
		"73d896fcd3fb31828c559e7c80382527587e2cc31f235a662ec48a716903cbe3",
		"Khadaganian iron chainmail trousers\nGood leg protection.",
		"Khadaganianische Kettenhosen aus Eisen\nGuter Schutz für die Beine."
	],
	"armor hadagan_high2_pants meteoric": [
		"40abaf80ef0a419b419846dbcf2fc7f9b504bfb0f1f8d46d28a76352f96a91be",
		"Khadaganian meteorite chainmail trousers\nThe very best!",
		"Khadaganianische Kettenhosen aus Meteorit-Eisen\nDie besten!"
	],
	"armor hadagan_high2_pants mithrill": [
		"7e155dc7c9422d4a54e0b3e07d110a1a1a0943b9dd122119057a89e57a17559e",
		"Khadaganian mithrill chainmail trousers\nThey are light - but not to make running away from the enemy easier!",
		"Khadaganianische Kettenhosen aus Mithril\nSehr leicht - aber sicherlich nicht, um eine Flucht leichter zu machen."
	],
	"armor hadagan_high2_pants steel": [
		"10d3e31678b444eb27ce79486bde38fe53e7fcce0575810dd52c228662e306f6",
		"Khadaganian steel chainmail trousers\nThese would serve an experienced warrior well.",
		"Khadaganianische Kettenhosen aus Stahl\nGenau das Richtige für einen erfahrenen Krieger."
	],
	"armor hadagan_high2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_plate adamantium": [
		"c654fb6f73497af235c7d2fbd7f48e6ca3013b531a11c7a631117ec386f119e3",
		"Khadaganian forged adamantite cuirass\nYou can rely on this in the heat of battle!",
		"Khadag. geschmiedeter Brustharnisch - Adamant\nAuch bei schweren Kämpfen absolut verlässlich."
	],
	"armor hadagan_high2_plate bronze": [
		"506f983f8544b7f1dd0b78ef10d88b376cd2dff06d0113af362636b328c5c161",
		"Khadaganian forged bronze cuirass\nWhy carry heavy and inefficient armor?",
		"Khadag. geschmiedeter Brustharnisch - Bronze\nEine schwere und ineffiziente Rüstung."
	],
	"armor hadagan_high2_plate iron": [
		"bd5ccfefdcd4c8fdaf5b49e2592719620cb39f80301bd22b98370f201421294c",
		"Khadaganian forged iron cuirass\nDecent body and arm protection.",
		"Khadag. geschmiedeter Brustharnisch - Eisen\nAngemessener Schutz für Arme und Körper."
	],
	"armor hadagan_high2_plate meteoric": [
		"530ab52c5c41e21db70034101c151a558b22e628919e51f5be5316a5038e8e0e",
		"Khadaganian forged meteorite cuirass\nIt is almost impossible to find anything better!",
		"Khadag. geschmiedeter Brustharnisch - Meteorit-Eisen\nEs gibt fast nichts Besseres."
	],
	"armor hadagan_high2_plate mithrill": [
		"080b5ee7022629ccc47a00fc098ea095b3d3747035310a824c0b196b9ed4cc5f",
		"Khadaganian forged mithrill cuirass\nGood protection is worth any price.",
		"Khadag. geschmiedeter Brustharnisch - Mithril\nGuter Schutz hat seinen Preis!"
	],
	"armor hadagan_high2_plate steel": [
		"1a3174ae01cc16875392fae98cc98cfc75cb51034ab8f1a5c7a65aa30474400b",
		"Khadaganian forged steel cuirass\nVery serious protection for a skilled fighter.",
		"Khadag. geschmiedeter Brustharnisch - Stahl\nEine erstklassige Rüstung für erfahrene Kämpfer."
	],
	"armor hadagan_high2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high2_shirt adamantium": [
		"9bd2e475cfa3f7d2f5c0925460e077be417df987c54c6eed39246008106cb13f",
		"Light Hadagan chain mail · Adamantite\nAdamantite is very expensive, but it is worth it!",
		"Leichtes hadaganisches Kettenhemd · Adamantit\nAdamant ist seinen Preis immer wert!"
	],
	"armor hadagan_high2_shirt bronze": [
		"fc07de1ba3df25dc08733f71412c309ab168e99fd410d0b752df6a67cf355d60",
		"Light Hadagan chain mail · Bronze\nToo heavy and uncomfortable...",
		"Leichtes hadaganisches Kettenhemd · Bronze\nZu schwer und unbequem ..."
	],
	"armor hadagan_high2_shirt iron": [
		"ff9debb920d35511e6107cd073a630c9db448410522dddb90062c887d4c07bad",
		"Light Hadagan chain mail · Iron\nBetter than bronze, but there's better yet available…",
		"Leichtes hadaganisches Kettenhemd · Eisen\nEisen ist besser als Bronze - aber noch lange nicht perfekt."
	],
	"armor hadagan_high2_shirt meteoric": [
		"2b4605961db4485fc550913b86acea34d95ce34510ff549c6c765628560a4f8d",
		"Light Hadagan chain mail · Meteorite\nBetter can be found, but only at an outrageous price!",
		"Leichtes hadaganisches Kettenhemd · Meteorit\nBesseres gibt es, aber nur zu einem unverschämten Preis!"
	],
	"armor hadagan_high2_shirt mithrill": [
		"508626849c4ea4b1b3a1219a8bd80bdd209779a31dbdcb70a590788f394c796f",
		"Light Hadagan chain mail · Mithrill\nNot very cheap, but one of the strongest.",
		"Leichtes hadaganisches Kettenhemd · Mithril\nNicht gerade billig, aber eine der besten."
	],
	"armor hadagan_high2_shirt steel": [
		"03d9608878c8f153c43b958bb542f6b08eebcec1cfb64abb25fe167632ecd192",
		"Light Hadagan chain mail · Steel\nA stray arrow will not pierce this chain mail.",
		"Leichtes hadaganisches Kettenhemd · Stahl\nEin verirrter Pfeil durchdringt dieses Kettenhemd nicht."
	],
	"armor hadagan_high_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots dragon_black": [
		"68233d9f7975abd9d6877845e5c40d4a92cd277eef74e2d2db88a3228be3fd0a",
		"Khadaganian boots of Blue Dragon hide\nYou can only improve these if you reinforce them with metal!",
		"Khadaganianische Stiefel aus blauer Drachenhaut\nUm diese Stiefel noch zu verbessern, müsste man sie mit Metall verstärken."
	],
	"armor hadagan_high_boots dragon_green": [
		"47960250f2433ce5c0d06ce98fa4c62debc80e2be0185d1cf99509b81ac57e72",
		"Khadaganian boots of Green Dragon hide\nComfortable and strong!",
		"Khadaganianische Stiefel aus grüner Drachenhaut\nBequem und widerstandsfähig."
	],
	"armor hadagan_high_boots dragon_red": [
		"a2ab24f9a96d382dd37eac852e26b56d4f62d11e1298437150be2ee0a971f0d1",
		"Khadaganian boots of Red Dragon hide\nYou can walk on burning coals in these!",
		"Khadaganianische Stiefel aus roter Drachenhaut\nMit diesen Stiefeln kann man über glühende Kohlen laufen!"
	],
	"armor hadagan_high_boots lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots troll_black": [
		"58ce37fbd17fc63f20c36eaf8ab69c174f1ddab229c5ab89100368fc87b57059",
		"Khadaganian boots of black Troll hide\nOnly Dragon hide boots are better!",
		"Khadaganianische Stiefel aus schwarzer Trollhaut\nNur Drachenleder ist besser!"
	],
	"armor hadagan_high_boots troll_blue": [
		"626b38b23a35474782ca7f154d3663107c5aa923da94432e7f88ea4f05e101d3",
		"Khadaganian boots of blue Troll hide\nYou can walk safely in these!",
		"Khadaganianische Stiefel aus blauer Trollhaut\nIn denen kann man sich sicher fühlen!"
	],
	"armor hadagan_high_boots troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_boots troll_green": [
		"df1c21252787be0ae67a8a9a8c11bb95150bee6294b48e163416c2f7d1864879",
		"Khadaganian thick hide boots · Green Troll hide\nThey protect your feet from more than swamp mud!",
		"Khadaganianische schwere Lederstiefel · Grüne Trollhaut\nSie schützen die Füße vor mehr als nur Sumpfschlamm!"
	],
	"armor hadagan_high_boots troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves dragon_black": [
		"4c8029c88dcc4d8f01a8d2b2b4cfb001c432a82cb2b1cfce9f3fa95207b71f62",
		"Khadaganian gauntlets of Blue Dragon hide\nThe best of light gauntlets!",
		"Khadaganianische Handschuhe aus blauer Drachenhaut\nDie besten aller leichten Handschuhe."
	],
	"armor hadagan_high_gloves dragon_green": [
		"4c825f1280e1f171038b8f34fb8ba7e6717f9e315ebb1af86f0a06efb7b6d9e5",
		"Khadaganian gauntlets of Green Dragon hide\nYou can rely on them in combat!",
		"Khadaganianische Handschuhe aus grüner Drachenhaut\nBieten auch in einem Kampf verlässlichen Schutz!"
	],
	"armor hadagan_high_gloves dragon_red": [
		"c305abd6f45fcb4289c0481254c0268fee9f16d2786c8bd7e7e170f8dda36252",
		"Khadaganian gauntlets of Red Dragon hide\nDragon hide provides the maximum protection any leather can offer.",
		"Khadaganianische Handschuhe aus roter Drachenhaut\nDrachenleder bietet den bestmöglichen Schutz."
	],
	"armor hadagan_high_gloves lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves troll_black": [
		"749daa1d86f5d9bf148fa7c237db5cce91bdeb74882006525d9ab56f0d283fa7",
		"Khadaganian gauntlets of black Troll hide\nGood protection from poor weapons.",
		"Khadaganianische Handschuhe aus schwarzer Trollhaut\nGuter Schutz gegen leichte Waffen."
	],
	"armor hadagan_high_gloves troll_blue": [
		"dc4a5651645044e568685d7e73f588ab49084936e298d1e8485039030167111f",
		"Khadaganian gauntlets of blue Troll hide\nProvide decent protection in combat.",
		"Khadaganianische Handschuhe aus blauer Trollhaut\nBieten guten Schutz im Kampf!"
	],
	"armor hadagan_high_gloves troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_gloves troll_green": [
		"1168a6e1c25ad9186f1371a1ad9d828405caf696a65444cf21b1d8f45e43bb53",
		"Khadaganian gauntlets of green Troll hide\nGood equipment, and not just for a fistfight at a village fair!",
		"Khadaganianische Handschuhe aus grüner Trollhaut\nNicht unbedingt nur für die Schlägerei auf dem Dorffest!"
	],
	"armor hadagan_high_gloves troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_helm adamantium": [
		"69eff4f8cafa14abab574446257c1dde9f7f3d8960e2a7454b8b8846cda4ce62",
		"Khadaganian light adamantite helmet\nNot the best possible design for this material!",
		"Khadaganianischer leichter Adamanthelm\nDas exzellente Material hätte eine bessere Form verdient!"
	],
	"armor hadagan_high_helm bronze": [
		"15524bd0c359dbc88965a8fb4b54dc11ea01818aeb10add3a42d2063730bbb5d",
		"Khadaganian light bronze helmet\nYou wouldn't call it light after a couple of hours!",
		"Khadaganianischer leichter Bronzehelm\nNach ein paar Stunden wird man ihn nicht mehr 'leicht' nennen!"
	],
	"armor hadagan_high_helm iron": [
		"ce6f4b49ae7ec970e0a0445b8ce99083f9befe2c00acac2e5cde0fd65ff4ae0f",
		"Khadaganian light iron helmet\nSoft cloth hides tough metal...",
		"Khadaganianischer leichter Eisenhelm\nDas harte Metall wird von weichem Stoff verborgen."
	],
	"armor hadagan_high_helm meteoric": [
		"1413dfbab1453b89ec76e1d5842457fd905b9e145683bef7670dd63dca46c6d6",
		"Khadaganian light meteorite helmet\nIt is a waste, really - to use meteorite iron like that!",
		"Khadaganianischer leichter Meteorithelm\nReine Verschwendung von Meteorit-Eisen."
	],
	"armor hadagan_high_helm mithrill": [
		"2f01d28251d16110a723726d753187589918bbcde662d03eceb3cd30e0e8b265",
		"Khadaganian light mithrill helmet\nIt is light, it is pretty, and it's strong!",
		"Khadaganianischer leichter Mithril-Helm\nLeicht, kunstvoll gefertigt und widerstandsfähig."
	],
	"armor hadagan_high_helm steel": [
		"d3a6ab963f875c4a21ddb2138d47379b8cf05763836ea9cd4c5779d8bbf7a94f",
		"Khadaganian light steel helmet\nNot too expensive, but provides decent protection.",
		"Khadaganianischer leichter Stahlhelm\nGuter Schutz zu einem guten Preis!"
	],
	"armor hadagan_high_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_leggins adamantium": [
		"5d17eef31a06fa3515b0b68381fc22eb4fa365f7ef9fa2365341d1848b593151",
		"Khadaganian chainmail trousers · Adamantite\nThis metal is too expensive to use it for such simple armor.",
		"Khadaganianische Kettenhosen · Adamantit\nDas Material ist eigentlich zu wertvoll, um es zu einer so einfachen Rüstung zu verarbeiten."
	],
	"armor hadagan_high_leggins bronze": [
		"ca268f863a06b45449960551434a349d81ad4e822dea7c7799291e7341d6356d",
		"Khadaganian bronze chainmail trousers\nBronze onlays provide additional protection - and weight...",
		"Khadaganianische Kettenhosen aus Bronze\nBronzeauflagen bieten zusätzlichen Schutz - und machen diese Hosen schwerer!"
	],
	"armor hadagan_high_leggins iron": [
		"b4f304c1669d3ff06a260dda1acb2e9062e0baccb02ffe9ec0ec837909b8233d",
		"Khadaganian iron chainmail trousers\nThey are reinforced with metal and protect the wearer from blows from simple weapons.",
		"Khadaganianische Kettenhosen aus Eisen\nDie Hosen sind mit Metall verstärkt und schützen dadurch vor leichten Waffen."
	],
	"armor hadagan_high_leggins meteoric": [
		"2e7733e5db3935f0fbb17dc57384587fbadbdd26ed987855c96af7743cc8e0c4",
		"Khadaganian meteorite chainmail trousers\nMeteorite iron is too good for this design!",
		"Khadaganianische Kettenhosen aus Meteorit-Eisen\nMeteorit-Eisen ist eigentlich zu kostbar für diese Art von Hosen."
	],
	"armor hadagan_high_leggins mithrill": [
		"1841827f2b6e1dbcbeafe45e456ea6555400d236ed5ecb15201ba98e800644f4",
		"Khadaganian mithrill chainmail trousers\nThese are really light - and provide good protection.",
		"Khadaganianische Kettenhosen aus Mithril\nSind sehr leicht, bieten aber trotzdem guten Schutz."
	],
	"armor hadagan_high_leggins steel": [
		"5527dfb4d7f5e3a3995c16c2ac283d20957eaa3b05603fdd8911e6f3c0cc53eb",
		"Khadaganian steel chainmail trousers\nThese ensure freedom of movement and provide decent protection.",
		"Khadaganianische Kettenhosen aus Stahl\nGroße Bewegungsfreiheit und guter Schutz."
	],
	"armor hadagan_high_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants dragon_black": [
		"5cf5f0b95e33a7b6c8fbc21fe5ffe46d49fb008e57dd085375c5673edce7773f",
		"Khadaganian trousers of Blue Dragon hide\nProbably the best leather trousers.",
		"Khadaganianische Hosen aus blauer Drachenhaut\nWahrscheinlich die besten Hosen aus Leder."
	],
	"armor hadagan_high_pants dragon_green": [
		"1e239c26ec8a66ec4f90d0a4248c09ed97c61e04855a37b39e7b30274e47c1fd",
		"Khadaganian trousers of Green Dragon hide\nStrong and light - a good choice!",
		"Khadaganianische Hosen aus grüner Drachenhaut\nLeicht und stabil - eine gute Wahl!"
	],
	"armor hadagan_high_pants dragon_red": [
		"0dda9ac180d7052e6f25e95f754acc2c57be30a88a0cfd4e61ff1e194e0df3ff",
		"Khadaganian trousers of Red Dragon hide\nA good mix of comfort and protection.",
		"Khadaganianische Hosen aus roter Drachenhaut\nEine gute Kombination aus Bewegungsfreiheit und Schutz."
	],
	"armor hadagan_high_pants lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants troll_black": [
		"42ca015cfcc6dd1066432ee0ae5570551c2e414f41e85ae1eb52d0c70a348db1",
		"Khadaganian trousers of black Troll hide\nReliable, and they ensure freedom of movement, too.",
		"Khadaganianische Hosen aus schwarzer Trollhaut\nVerlässlich und bequem."
	],
	"armor hadagan_high_pants troll_blue": [
		"b7f83ca0e29373c59022be647baa3c548b696615dd16b8b26f510f78704ed3be",
		"Khadaganian trousers of blue Troll hide\nGood protection from poor weapons.",
		"Khadaganianische Hosen aus blauer Trollhaut\nBieten guten Schutz vor sehr leichten Waffen."
	],
	"armor hadagan_high_pants troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_pants troll_green": [
		"f9698f60229c6174aae72549a11d1d3822ebcbd111de8074a597505fd225c2f3",
		"Khadaganian trousers of green Troll hide\nNot a bad pair of pants.",
		"Khadaganianische Hosen aus grüner Trollhaut\nNicht der schlechteste Schutz."
	],
	"armor hadagan_high_pants troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_plate adamantium": [
		"7c1bc9b5a17c99ae7cf0d196e09159043124172d5dd72071012690906b709f9d",
		"Khadaganian light adamantite cuirass\nA strange choice: rare metal and simple design.",
		"Khadaganianischer l. Brustharnisch aus Adamant\nEine merkwürdige Kombination: kostbares Metall und eine einfache Form."
	],
	"armor hadagan_high_plate bronze": [
		"a92422c5bb8bdf04c620958fbde73d4a25ea2c0472561788c13ec88642eb840e",
		"Khadaganian light bronze cuirass\nIt is quite heavy, really...",
		"Khadaganianischer l. Brustharnisch aus Bronze\nSehr, sehr schwer!"
	],
	"armor hadagan_high_plate iron": [
		"1c3916ea2dc6132c25419ca0a7b28f5f6d85806d7e810f36d90bd76cc249dc52",
		"Khadaganian light iron cuirass\nProvides some serious protection.",
		"Khadaganianischer l. Brustharnisch aus Eisen\nBietet extrem guten Schutz."
	],
	"armor hadagan_high_plate meteoric": [
		"a3ca3bec8eb25983b1c5994096dd243de285786bb61038905bb8039694462c75",
		"Khadaganian light meteorite cuirass\nAn exotic combination of design and material!",
		"Khadag. l. Brustharnisch aus Meteorit-Eisen\nEine ungewöhnliche Kombination von Form und Material."
	],
	"armor hadagan_high_plate mithrill": [
		"0e59b2440ae4b00d1eb71ef0e8c5966d632ba31caaa3735553d41fe342132da6",
		"Khadaganian light mithrill cuirass\nEnsures freedom of movement and provides decent protection.",
		"Khadaganianischer l. Brustharnisch aus Mithril\nHohe Bewegungsfreiheit und vergleichsweise guter Schutz."
	],
	"armor hadagan_high_plate steel": [
		"d0b09ba904e2643a7b60ba2200ae377a46c98a4400b4c5b341fdfca398175c85",
		"Khadaganian light steel cuirass\nWill protect you from simple weapons.",
		"Khadaganianischer l. Brustharnisch aus Stahl\nSchützt vor leichten Waffen."
	],
	"armor hadagan_high_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype troll_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype troll_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_prototype troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt dragon_black": [
		"1e4c1e57734bf2171b3a1e4deb7ca1bc45f2d07559802f4739c40d774d4c84f2",
		"Khadaganian armor of Blue Dragon hide\nA very strong leather armor.",
		"Khadaganianische Rüstung aus blauer Drachenhaut\nSehr starke Lederrüstung."
	],
	"armor hadagan_high_shirt dragon_green": [
		"1b750468a61a19beb2b817ce225bc9bc60e814b61a72b10d424774b0a72292ef",
		"Khadaganian armor of Green Dragon hide\nGood protection - and not just from poor weapons.",
		"Khadaganianische Rüstung aus grüner Drachenhaut\nGuter Schutz auch gegen stärkere Waffen."
	],
	"armor hadagan_high_shirt dragon_red": [
		"ab16fd7ba14fb97a443000408004203ba0c395815478afb26a3af3d57d19fca8",
		"Khadaganian armor of Red Dragon hide\nDragon hide is the best material for leather armor.",
		"Khadaganianische Rüstung aus roter Drachenhaut\nDrachenleder bietet den bestmöglichen Schutz."
	],
	"armor hadagan_high_shirt lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt troll_black": [
		"f5a8e9947f8d1cceb924e6f04db0d88016f743fd193823d6ef917046ad143ee8",
		"Khadaganian armor of black Troll hide\nStrong and reliable armor - but not for serious combat.",
		"Khadaganianische Rüstung aus schwarzer Trollhaut\nStabile Rüstung, die allerdings nicht für größere Kämpfe geeignet ist."
	],
	"armor hadagan_high_shirt troll_blue": [
		"d16917486f4bd5be8283744b83f48fbdbe6d2b2e65e197b437b7615973e23b5c",
		"Khadaganian armor of blue Troll hide\nGood protection from poor weapons.",
		"Khadaganianische Rüstung aus blauer Trollhaut\nGuter Schutz vor leichten Waffen."
	],
	"armor hadagan_high_shirt troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_high_shirt troll_green": [
		"1c1c7c6e92e3f93861f3cdaca00cbc1ae1e9ff53d7ed07da4242e9e462c900db",
		"Khadaganian armor of green Troll hide\nProvides decent protection.",
		"Khadaganianische Rüstung aus grüner Trollhaut\nBietet annehmbaren Schutz."
	],
	"armor hadagan_high_shirt troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_boots adamantium": [
		"6edb78594fc9e01a370a8fd002207427796419bf68343e566a7f74e71bb63179",
		"Heavy Hadagan boots · Adamantite\nWith these, you could even kick an ogre in the backside.",
		"Schwere hadaganische Stiefel · Adamantit\nDamit kann man sogar einem Oger einen Tritt verpassen."
	],
	"armor hadagan_highest2_boots bronze": [
		"87aa9ebe0cccb2e6334e3327e2e510525484b3366ed6dd50a179009ed642c375",
		"Heavy Hadagan boots · Bronze\nA waste of a good blueprint.",
		"Schwere hadaganische Stiefel · Bronze\nVerschwendung eines guten Bauplans."
	],
	"armor hadagan_highest2_boots iron": [
		"512ab8272d3a6a95909a3143bfdcbe63d8c17fb6f9a992133fa753e1152ad074",
		"Heavy Hadagan boots · Iron\nThis blueprint deserved better material.",
		"Schwere hadaganische Stiefel · Eisen\nDieser Bauplan hätte besseres Material verdient."
	],
	"armor hadagan_highest2_boots meteoric": [
		"af6b5ec6df45d14612bd4c76b56b5f9d54965af3c0b62cb8b6cca303d9a140ec",
		"Heavy Hadagan boots · Meteorite\nThe best metal boots.",
		"Schwere hadaganische Stiefel · Meteorit\nDie besten Stiefel aus Metall."
	],
	"armor hadagan_highest2_boots mithrill": [
		"e08f0cd8ddebd569a49bb97e97095eca9efc9f2253fa96d7d42a7d09909d4411",
		"Heavy Hadagan boots · Mithrill\nGood protection for the feet, though not cheap.",
		"Schwere hadaganische Stiefel · Mithril\nGuter Schutz für die Füße, wenn auch nicht billig."
	],
	"armor hadagan_highest2_boots steel": [
		"f60af2827d2e0c1983ea3eb38b2f4df92ce7375ee061e489d1ae778a80ecf898",
		"Heavy Hadagan boots · Steel\nGood, but better can be found for this price.",
		"Schwere hadaganische Stiefel · Stahl\nGut, aber für diesen Preis gibt es Besseres."
	],
	"armor hadagan_highest2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_gloves adamantium": [
		"ad894996e79a37e5267853e659d6df7062d547dd0109dc93a60b695ee4c76498",
		"Heavy Hadagan bracers · Adamantite\nThese could withstand a knife stab!",
		"Schwere hadaganische Armschienen · Adamantit\nDenen kann sogar ein Messer nichts anhaben!"
	],
	"armor hadagan_highest2_gloves bronze": [
		"1e651de9372cc4fbeb35cf0f8a4580873db2682506cd7dc0ae5d5f4bc828b8de",
		"Heavy Hadagan bracers · Bronze\nThe material does not suit the blueprint.",
		"Schwere hadaganische Armschienen · Bronze\nDas Material passt nicht zum Bauplan."
	],
	"armor hadagan_highest2_gloves iron": [
		"8a7e828b050486dd821f21710cf077db9eb5647cb012ec06807eb757c23d6915",
		"Heavy Hadagan bracers · Iron\nThis blueprint should not have been wasted on them.",
		"Schwere hadaganische Armschienen · Eisen\nDafür hätte man diesen Bauplan nicht verschwenden sollen."
	],
	"armor hadagan_highest2_gloves meteoric": [
		"4b3564a736bb194ce7488e043d8ab75fd142eda95584e7030b01b4e8f10ccfb9",
		"Heavy Hadagan bracers · Meteorite\nThe best metal bracers!",
		"Schwere hadaganische Armschienen · Meteorit\nDie besten Armschienen aus Metall!"
	],
	"armor hadagan_highest2_gloves mithrill": [
		"3dc9ecdbcdfc9eb7a6032493203ee7e6e42491670259beb574e2d1eb541be772",
		"Heavy Hadagan bracers · Mithrill\nWith these, you can fight without a weapon!",
		"Schwere hadaganische Armschienen · Mithril\nDamit kann man auch ohne Waffe kämpfen!"
	],
	"armor hadagan_highest2_gloves steel": [
		"58c19c5a3474e95a45fa707efca19e91a58bbb8ddd6b3b5a433c5e9f4c8accf3",
		"Heavy Hadagan bracers · Steel\nSerious protection for your arms!",
		"Schwere hadaganische Armschienen · Stahl\nErnsthafter Schutz für die Arme!"
	],
	"armor hadagan_highest2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_helm adamantium": [
		"e1fd796fde81ffef5e9cece46db7fc376535beed4c436af8874c0c9131226828",
		"Khadaganian heavy adamantite helmet\nYou can beat this with stone or steel - with no success!",
		"Khadaganianischer schwerer Adamanthelm\nEin Helm, der Stein und Stahl gleichermaßen gut widersteht."
	],
	"armor hadagan_highest2_helm bronze": [
		"b8236b42db97054c0bfbe43f3489a5d34b783ae4211f91ed9bb5ed3922342fef",
		"Khadaganian heavy bronze helmet\nAn absurd mix of design and material!",
		"Khadaganianischer schwerer Bronzehelm\nEine absurde Mischung aus Form und Material."
	],
	"armor hadagan_highest2_helm iron": [
		"163050df2a459226261128dc312d4b56fbef51b2ec4ea9b9ea63a8d61c76d056",
		"Khadaganian heavy iron helmet\nIron is not the best possible material for a heavy helmet.",
		"Khadaganianischer schwerer Eisenhelm\nEisen ist nicht gerade das beste Material für einen schweren Helm."
	],
	"armor hadagan_highest2_helm meteoric": [
		"55bd98e22e2d5c0174112cc959614ad5a99e03710ca93c2b76af6319bef9640f",
		"Khadaganian heavy meteorite helmet\nThe best of all metal helmets!",
		"Khadaganianischer schwerer Meteorit-Eisenhelm\nDer beste aller Metallhelme."
	],
	"armor hadagan_highest2_helm mithrill": [
		"62f95f08a95d7f637db60e266c1ef1ab46d9b5195b271fe5ada4547c23f9a767",
		"Khadaganian heavy mithrill helmet\nOne of the best!",
		"Khadaganianischer schwerer Mithrilhelm\nEiner der besten."
	],
	"armor hadagan_highest2_helm steel": [
		"dc19ba6dcb49b7a62dbd4234e33ec5b9ec9680ebece17910cafabe328ccc375a",
		"Khadaganian heavy steel helmet\nIt is not cheap, but provides good protection.",
		"Khadaganianischer schwerer Stahlhelm\nNicht gerade billig, bietet aber guten Schutz vor Angriffen."
	],
	"armor hadagan_highest2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_leggins adamantium": [
		"244bfa5cf81eef02c4667e00eda7f5fb5d8bcbcb5884314b83f1dbd11e6e37dc",
		"Khadaganian heavy adamantite leggings\nWorth paying a bit extra!",
		"Khadaganianische schwere Beinlinge aus Adamant\nIst nahezu jeden Preis wert."
	],
	"armor hadagan_highest2_leggins bronze": [
		"d4e1ac55d7b8b1f581b439b2426f325a5913c1431ce9083bdcfde344a51d6999",
		"Khadaganian heavy bronze leggings\nSuch good work - and such poor metal!",
		"Khadaganianische schwere Beinlinge aus Bronze\nBeste Arbeit, aber leider schlechtestes Material."
	],
	"armor hadagan_highest2_leggins iron": [
		"da4f5e014f0c7c04e62d00b7b56e4d2af466917c199d9716ae4f22d8ecb3952c",
		"Khadaganian heavy iron leggings\nIron is not the best choice for this design.",
		"Khadaganianische schwere Beinlinge aus Eisen\nEisen ist nicht unbedingt das beste Material für Beinlinge."
	],
	"armor hadagan_highest2_leggins meteoric": [
		"76b20934b71ffbceeddfd2decaf01fa48333bb859c1d7b3baed4bb7e6fe04286",
		"Khadaganian heavy meteorite leggings\nThe best of metal leggings!",
		"Khadaganianische schwere Beinlinge aus Meteorit-Eisen\nDie besten Beinlinge!"
	],
	"armor hadagan_highest2_leggins mithrill": [
		"b2cb0b652575285656c5e476155b29e62bde6ddffa8efd3092ff02676e762a39",
		"Khadaganian heavy mithrill leggings\nOne of the best in Khadagan!",
		"Khadaganianische schwere Beinlinge aus Mithril\nMit das Beste, was man in Khadagan kriegen kann."
	],
	"armor hadagan_highest2_leggins steel": [
		"3975430cb1c31f7c331fe03a460b9de8f7c50aacc6b3d5b348e0d9680e1dc5b7",
		"Khadaganian heavy steel leggings\nThese really are heavy, but good protection!",
		"Khadaganianische schwere Beinlinge aus Stahl\nSehr, sehr schwer. Aber zuverlässig."
	],
	"armor hadagan_highest2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_pants adamantium": [
		"d11c7abf3af41060bd5209b8dfe30380f803e24ecb07e834d4300e9d53714f01",
		"Khadaganian heavy trousers · Adamantite\nExcellent material for excellent armour!",
		"Khadaganianische schwere Hosen · Adamantit\nAusgezeichnetes Material für eine ausgezeichnete Rüstung!"
	],
	"armor hadagan_highest2_pants bronze": [
		"c6fbcb4ca989715d2d6b0f32038112cea684718dc043de24f85f98e90889dce0",
		"Khadaganian heavy trousers · Bronze\nMaking this armour from bronze is utter foolishness.",
		"Khadaganianische schwere Hosen · Bronze\nDiese Rüstung aus Bronze zu fertigen ist völlig unsinnig."
	],
	"armor hadagan_highest2_pants iron": [
		"ba373ac4a7245cfeb4f83888d038ed7e078841c9acdff331136b251fa7f2c972",
		"Khadaganian heavy trousers · Iron\nA rather poor choice of material.",
		"Khadaganianische schwere Hosen · Eisen\nEine eher schlechte Materialwahl."
	],
	"armor hadagan_highest2_pants meteoric": [
		"11fb65cd3c3f5827c95266939e94ea380cf7e6809dac1f41165f8596f3d89037",
		"Khadaganian heavy trousers · Meteorite\nThe best metal trousers.",
		"Khadaganianische schwere Hosen · Meteorit\nDie beste Hose aus Metall."
	],
	"armor hadagan_highest2_pants mithrill": [
		"5a100e844dba38ebb632d301171a00dc35ee7c3a1195cd6de06b490393cdbbae",
		"Khadaganian heavy trousers · Mithrill\nMithril is light, but the armour is still heavy.",
		"Khadaganianische schwere Hosen · Mithril\nMithril ist leicht, doch die Rüstung bleibt schwer."
	],
	"armor hadagan_highest2_pants steel": [
		"3d8fc361793bd734b733e7e93798d72d23fb95a23301d1d65c22a84aa74d14e7",
		"Khadaganian heavy trousers · Steel\nYou will not run far in these, but the protection is solid.",
		"Khadaganianische schwere Hosen · Stahl\nWeit laufen kann man darin nicht, doch der Schutz ist solide."
	],
	"armor hadagan_highest2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_plate adamantium": [
		"fa665f55eb5f32d5a67a93bbcc09faf2eb0daa6501c7136dae1aeb02bf891c41",
		"Khadaganian heavy adamantite cuirass\nAn excellent cuirass!",
		"Khadaganianischer schw. Brusth. aus Adamant\nEin fantastischer Brustharnisch!"
	],
	"armor hadagan_highest2_plate bronze": [
		"5002fdbd286ac0e0a23d8112cf76d0c4e029e3a5e21b2938ebd2a20502b795ad",
		"Khadaganian heavy bronze cuirass\nBronze is not the best choice for this design.",
		"Khadaganianischer schw. Brustharnisch aus Bronze\nBronze ist eine schlechte Wahl für diese Art von Rüstung."
	],
	"armor hadagan_highest2_plate iron": [
		"2b13a6c40bd3c33bad95a14d9193ff448cfac67192e076f9a4cec0ee13a6fa3c",
		"Khadaganian heavy iron cuirass\nYou should try looking for a stronger metal!",
		"Khadaganianischer schw. Brustharnisch aus Eisen\nMan sollte sich nach einem besseren Metall umsehen."
	],
	"armor hadagan_highest2_plate meteoric": [
		"74a7a280d151a606d04c0cb5025c1908d11dfd1c359840e2344bf70a67e65597",
		"Khadaganian heavy meteorite cuirass\nA sword would break trying to pierce this cuirass!",
		"Khadaganianischer schw. Brustharnisch aus Meteorit-Eisen\nEin Schwert würde eher brechen als diesen Panzer zu durchdringen."
	],
	"armor hadagan_highest2_plate mithrill": [
		"01dae9d2743349d10b378c5cff24c6189cf5b23ab23e2f04ab78551323564d6b",
		"Khadaganian heavy mithrill cuirass\nFew weapons would pierce this cuirass!",
		"Khadaganianischer schw. Brustharnisch aus Mithril\nNicht jede Waffe ist in der Lage, diesen Panzer zu durchbrechen."
	],
	"armor hadagan_highest2_plate steel": [
		"00e1c4c5f9ba9ec90ce4b2babd1fc13136b94584d43fa0db29e845a7214adda0",
		"Khadaganian heavy steel cuirass\nThis is good armor.",
		"Khadaganianischer schw. Brustharnisch aus Stahl\nEin mehr als akzeptabler Brustharnisch."
	],
	"armor hadagan_highest2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest2_shirt adamantium": [
		"a511a088a7237ac5a3d035159ae53c6a13603e9dc862d6adae064d6892dbe628",
		"Khadaganian heavy shirt · Adamantite\nStrong armour... but expensive, too.",
		"Khadaganianisches schweres Hemd · Adamantit\nStarke Rüstung ... aber auch ein stolzer Preis."
	],
	"armor hadagan_highest2_shirt bronze": [
		"14252a6e4b4b4b05151c5e0324d60be875a05d3d2ee9d8427b0d9cf84a60e117",
		"Khadaganian heavy shirt · Bronze\nIt would be hard to find someone willing to ruin this blueprint by making bronze armour.",
		"Khadaganianisches schweres Hemd · Bronze\nMan wird kaum jemanden finden, der diesen Bauplan für eine Bronzerüstung verschwenden würde."
	],
	"armor hadagan_highest2_shirt iron": [
		"787255af11538f5a1c707ba19c4c4dc03a26dce64587c327a22c457f49c10254",
		"Khadaganian heavy shirt · Iron\nNot the best choice of material.",
		"Khadaganianisches schweres Hemd · Eisen\nNicht die beste Materialwahl."
	],
	"armor hadagan_highest2_shirt meteoric": [
		"d3719385684f22f3e3690c794b40755c4c0d293a8f3769a2af61fbb005891183",
		"Khadaganian heavy shirt · Meteorite\nThe best metal chain mail, with a price to match.",
		"Khadaganianisches schweres Hemd · Meteorit\nDas beste Kettenhemd aus Metall, mit entsprechendem Preis."
	],
	"armor hadagan_highest2_shirt mithrill": [
		"ee0a76515d3618d4701fbcbfe5df8f2b354ac1a4ab529df15e02382d5c848bd3",
		"Khadaganian heavy shirt · Mithrill\nMithril makes it lighter without sacrificing excellent protection!",
		"Khadaganianisches schweres Hemd · Mithril\nMithril macht sie leichter, bei ausgezeichnetem Schutz!"
	],
	"armor hadagan_highest2_shirt steel": [
		"a43aa50e1115986620037eedc752b7b48afd895b2f55cdc837740c44f61660e4",
		"Khadaganian heavy shirt · Steel\nYou can face an arrow without fear in this.",
		"Khadaganianisches schweres Hemd · Stahl\nDamit kann man einem Pfeil furchtlos die Brust bieten."
	],
	"armor hadagan_highest_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_boots adamantium": [
		"fe3c73b6d7f10af34214ba0392c97705ceabba017213e0a89504625ccaeef4da",
		"Khadaganian reinforced boots · Adamantite\nAn expensive but classy armor.",
		"Khadaganianische verstärkte Stiefel · Adamantit\nTeure, aber gute Panzerung."
	],
	"armor hadagan_highest_boots bronze": [
		"067a242d0f2a6c375d322feca40339820f73892382e7c3bfad1b7839ee7e1fb1",
		"Khadaganian bronze reinforced boots\nThe extra protection is not worth the extra weight.",
		"Khadaganianische bronzeverstärkte Stiefel\nDer zusätzliche Schutz ist auf keinen Fall das hohe Gewicht wert."
	],
	"armor hadagan_highest_boots iron": [
		"a0745bff9917f0c5f02d556e5c79d77270d390794fe0329d61e365a2a54e6eec",
		"Khadaganian iron reinforced boots\nGood protection from poor weapons.",
		"Khadaganianische eisenverstärkte Stiefel\nGuter Schutz gegen leichte Waffen."
	],
	"armor hadagan_highest_boots meteoric": [
		"1a6e1d8c5cb1ac04f075f5c6f7dbe1db738d2e511ea712d214593732c6fa8de0",
		"Khadaganian meteorite reinforced boots\nIf you have meteorite iron to spare, the protection level will be excellent.",
		"Khadag. Meteorit-Eisenv. Stiefel\nGuter Schutz für den, der es sich leisten kann."
	],
	"armor hadagan_highest_boots mithrill": [
		"90d57937f5bcfb018138e5c42903437047eee4d58d1adb93066f1b5054bbd4a0",
		"Khadaganian mithrill reinforced boots\nMithrill gives you almost no extra weight, but it does provides extra protection.",
		"Khadaganianische mithrilverstärkte Stiefel\nMithril ist leicht, bietet aber exzellenten Schutz."
	],
	"armor hadagan_highest_boots steel": [
		"3b2433bcac3085afca66ce76d7450a7be16a20684fde4ccfa70a382c2928225b",
		"Khadaganian steel reinforced boots\nSteel plates provide additional strength.",
		"Khadaganianische stahlverstärkte Stiefel\nBesserer Schutz durch zusätzliche Stahlplatten."
	],
	"armor hadagan_highest_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_gloves adamantium": [
		"4c6e78007e34164707c9772f61f9a8a328adee39183fdb4ee6d95300de481d23",
		"Khadaganian adamantite reinforced gauntlets\nAdamantite plates are expensive but they can save your life.",
		"Khadaganianische adamantverstärkte Handschuhe\nAdamanteinlagen sind teuer - können dir aber das Leben retten."
	],
	"armor hadagan_highest_gloves bronze": [
		"f5b52ab8c2a59aaaa56e4297b659c244e19abe648aa2763e1c1493dd5b002acd",
		"Khadaganian bronze reinforced gauntlets\nIt does not pay to economize on the metal!",
		"Khadaganianische bronzeverstärkte Handschuhe\nEs lohnt sich einfach nicht, am Metall zu sparen."
	],
	"armor hadagan_highest_gloves iron": [
		"3623232b0e24881272134ec15d563672d43a09d4be75d9dcb8badf6ac9d471c1",
		"Khadaganian iron reinforced gauntlets\nEven steel would give more protection.",
		"Khadaganianische eisenverstärkte Handschuhe\nSelbst Stahl schützt besser."
	],
	"armor hadagan_highest_gloves meteoric": [
		"9f0230c709ccd1fe26f52d666435c6f24ae7e42a79c8fcdb5065d34c1f709561",
		"Khadaganian meteorite reinforced gauntlets\nThese could withstand a knife stab!",
		"Khadag. Meteorit-Eisenv. Handschuhe\nDenen kann sogar ein Messer nichts anhaben!"
	],
	"armor hadagan_highest_gloves mithrill": [
		"d7bd1d4661d61fc325a45f18894085997f028c187c9589771beb39ef12b4a17a",
		"Khadaganian mithrill reinforced gauntlets\nForged mithrill provides much better protection.",
		"Khadaganianische mithrilverstärkte Handschuhe\nGeschmiedetes Mithril bietet besonders großen Schutz."
	],
	"armor hadagan_highest_gloves steel": [
		"83d2f51061bdd2fde9505aab8d600658962f39af72ad014f7b82ea826da6e48f",
		"Khadaganian steel reinforced gauntlets\nNot too expensive, and rather good.",
		"Khadaganianische stahlverstärkte Handschuhe\nNicht sehr teuer, aber trotzdem gut."
	],
	"armor hadagan_highest_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_helm adamantium": [
		"d327dfabdf311877d5009f6e8d4446bf45e55971f4239b1c485200aa3a1840d1",
		"Khadaganian adamantite reinforced helmet\nAdamantite is worth any price.",
		"Khadaganianischer adamantverstärkter Helm\nAdamant ist seinen Preis immer wert!"
	],
	"armor hadagan_highest_helm bronze": [
		"2ef75459756d31f275da15e4da3d507e0455b28ea34218ac497e82f3f8185ba5",
		"Khadaganian bronze reinforced helmet\nBronze should be used for simpler designs!",
		"Khadaganianischer bronzeverstärkter Helm\nBronze sollte nur für einfache Gegenstände verwendet werden."
	],
	"armor hadagan_highest_helm iron": [
		"09eb232a31406aa8fee5cfbb28002f803ee575a3be35729720e2393d417037e8",
		"Khadaganian iron reinforced helmet\nDespite the smith's skill, this will not protect you from the blows of good weapons.",
		"Khadaganianischer eisenverstärkter Helm\nGute Schmiedearbeit allein kann nicht vor schweren Waffen schützen."
	],
	"armor hadagan_highest_helm meteoric": [
		"0f72d55b06facaf7726fb9d2f21bc711c9e1cebf00726296ab5ccae1835f9816",
		"Khadaganian meteorite reinforced helmet\nDo not beat walls with your head wearing this one - you will have to pay for the damage.",
		"Khadag. Meteorit-Eisenv. Helm\nMit diesem Helm kann man zur Not auch mit dem Kopf durch die Wand."
	],
	"armor hadagan_highest_helm mithrill": [
		"e416575803c008f41768209ed9345d4cfc23b36933ddcfb086de02f5fe277989",
		"Khadaganian mithrill reinforced helmet\nNot the most expensive of helmets, but still serious head protection.",
		"Khadaganianischer mithrilverstärkter Helm\nNicht besonders teuer, aber trotzdem ein guter Helm."
	],
	"armor hadagan_highest_helm steel": [
		"306fa00774e4e86a413a9c3906ca3b55977ecc4ac57d5384c21b88073457e96a",
		"Khadaganian steel reinforced helmet\nNot too pretty - and not too expensive either.",
		"Khadaganianischer stahlverstärkter Helm\nEin preiswerter Helm. Dafür aber auch nicht besonders schön!"
	],
	"armor hadagan_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_leggins adamantium": [
		"2dae0f717a69862ae10e8afdd8380cd17f87b41d9497dfdb85985485648d7bc4",
		"Khadaganian adamantite reinforced leggings\nThese will protect you from almost any blow!",
		"Khadaganianische adamantverstärkte Beinlinge\nKaum eine Waffe kann diesen Beinlingen etwas anhaben."
	],
	"armor hadagan_highest_leggins bronze": [
		"3a1f88e8f420afbdee983bc1ba957f974d2208d061bd0f4bc2c1202e78f4a488",
		"Khadaganian bronze reinforced leggings\nToo heavy and inefficient.",
		"Khadaganianische bronzeverstärkte Beinlinge\nSchwer und ineffizient."
	],
	"armor hadagan_highest_leggins iron": [
		"e79de4e1e7ebf189ec1627820d9d6f51641b913ebb043ebc41cf3f3e93ca1098",
		"Khadaganian iron reinforced leggings\nNot too much protection.",
		"Khadaganianische eisenverstärkte Beinlinge\nBieten keinen großartigen Schutz."
	],
	"armor hadagan_highest_leggins meteoric": [
		"c50d91e646eea45d66797f777af464d0853ea0170ed6417f66e79ca4c30738ed",
		"Khadaganian meteorite reinforced leggings\nA perfect mix of freedom and protection!",
		"Khadag. Meteorit-Eisenv. Beinlinge\nEine perfekte Mischung aus Bewegungsfreiheit und Schutz."
	],
	"armor hadagan_highest_leggins mithrill": [
		"009f48de9fbd322b3d3d0eb9b470ea6db8b2ccd519444510699f05c25fb66777",
		"Khadaganian mithrill reinforced leggings\nThe material speaks for itself.",
		"Khadaganianische mithrilverstärkte Beinlinge\nDas verwendete Material sagt eigentlich schon alles."
	],
	"armor hadagan_highest_leggins steel": [
		"25e75a53a6070de25564c86bf599dd3bade449eca96c73a8b0957a40fd28c30e",
		"Khadaganian steel reinforced leggings\nChainmail leggings reinforced with metal plates will protect your back.",
		"Khadaganianische stahlverstärkte Beinlinge\nDiese mit Metallplatten besetzten Ketten-Beinlinge schützen auch vor Angriffen von hinten."
	],
	"armor hadagan_highest_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_pants adamantium": [
		"841475bbb91767928cddd17ed2ffa19c6f8c8c7ff7f6f41cb2572b9a9de0eea7",
		"Khadaganian reinforced adamantite chainmail trousers\nFew weapons could pierce this armor.",
		"Khadaganianische adamantverstärkte Kettenhosen\nDiese Hose kann nicht von jeder Waffe durchdrungen werden."
	],
	"armor hadagan_highest_pants bronze": [
		"6047c05484888b43585bc759c5bc8e81e8b6872f8c00e29f429336e60d48d85b",
		"Khadaganian reinforced bronze chainmail trousers\nNot the best choice of metal for good armor.",
		"Khadaganianische bronzeverstärkte Kettenhosen\nKaum das richtige Metall für eine Rüstung."
	],
	"armor hadagan_highest_pants iron": [
		"82737a35e4b2cba2c66c6c947fa40ae19e441decc148545aad75a72f6a177aeb",
		"Khadaganian reinforced iron chainmail trousers\nQuite reliable, but not in hard combat.",
		"Khadaganianische eisenverstärkte Kettenhosen\nWiderstandsfähig, aber nicht für große Kämpfe geeignet."
	],
	"armor hadagan_highest_pants meteoric": [
		"b98f4263dfc8150215a1a7384ce5f78a135831dadbe47c143b9efd52f9aa6da9",
		"Khadaganian reinforced meteorite chainmail trousers\nExpensive but most efficient armor!",
		"Khadag. Meteorit-Eisenv. Kettenhosen\nEine teure, aber sehr wirkungsvolle Panzerung."
	],
	"armor hadagan_highest_pants mithrill": [
		"2ac45f715b8de2049f7ef8b68ac57fc9d62fa1ec6f2e8357fea2d82c102b42f6",
		"Khadaganian reinforced mithrill chainmail trousers\nThese will protect you, and not just from thorns.",
		"Khadaganianische mithrilverstärkte Kettenhosen\nDie schützen vor mehr als nur Dornen!"
	],
	"armor hadagan_highest_pants steel": [
		"efdfbdd8396e547c003b7d91bab97ec1d445ce56e0926db0c5c83c67be1c0385",
		"Khadaganian reinforced steel chainmail trousers\nSteel provides good leg protection.",
		"Khadaganianische stahlverstärkte Kettenhosen\nDer Stahl bietet zusätzlichen Schutz für die Beine."
	],
	"armor hadagan_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_plate adamantium": [
		"a29d264be751e2bfd55cb1157268ea164df83e2974afe29b1e9503ed96c73ffb",
		"Khadaganian adamantite reinforced cuirass\nAs any adamantite armor is, this is worth the high price.",
		"Khadag. adamantverstärkter Brustharnisch\nAdamant ist seinen Preis immer wert!"
	],
	"armor hadagan_highest_plate bronze": [
		"160d43b7b8ec572fb30e4fe624eacf45974e3196b07992f1943e56657d44f5cb",
		"Khadaganian bronze reinforced cuirass\nNot a sensible choice of metal for this blueprint!",
		"Khadaganianischer bronzeverstärkter Brustharnisch\nNicht gerade eine gute Wahl für diese Art von Panzerung."
	],
	"armor hadagan_highest_plate iron": [
		"a64a78c8ad8df49bc983168be215fd5bdab170a713f06d8fa880b4407bc6d49e",
		"Khadaganian iron reinforced cuirass\nIron plates on top of a chainmail cuirass provide additional protection.",
		"Khadaganianischer eisenverstärkter Brustharnisch\nEisenplatten auf einem Ketten-Brustharnisch sorgen für zusätzlichen Schutz."
	],
	"armor hadagan_highest_plate meteoric": [
		"00bd9a8c0af1ff05c4d97cc2967b2339c3c608f67f56ecbe5f8ca533365b261e",
		"Khadaganian meteorite reinforced cuirass\nA perfect mix of free movement and protection!",
		"Khadag. Meteorit-Eisenv. Brustharnisch\nEine gute Kombination aus Bewegungsfreiheit und Schutz."
	],
	"armor hadagan_highest_plate mithrill": [
		"7e378b9c8eb547fab529acc3573d281c913d09a4ce1247aa55e06e61863c77e4",
		"Khadaganian mithrill reinforced cuirass\nIt's main strength is freedom of movement during combat.",
		"Khadaganianischer mithrilverstärkter Brustharnisch\nBietet besonders große Bewegungsfreiheit im Kampf."
	],
	"armor hadagan_highest_plate steel": [
		"9bf41c82cd268ffdb3c3f1a7250d74fc1575fbc25da92ca067ba33a760692366",
		"Khadaganian steel reinforced cuirass\nGood price/protection ration.",
		"Khadaganianischer stahlverstärkter Brustharnisch\nGuter Schutz zu einem angemessenen Preis."
	],
	"armor hadagan_highest_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_highest_shirt adamantium": [
		"580d026171ef7b431787fc5666a3c0f133186d06813699adb6ca137a965593aa",
		"Khadaganian reinforced adamantite chainmail\nNot the cheapest armor, but this does provide good body protection.",
		"Khadaganianisches adamantverstärktes Kettenhemd\nNicht gerade billig. Bietet aber guten Schutz."
	],
	"armor hadagan_highest_shirt bronze": [
		"68782e5c5d256b78286c07595aaf89bb3f85296f7f5ca27beab68c7fe638deca",
		"Khadaganian reinforced bronze chainmail\nHeavy and not too efficient armor.",
		"Khadaganianisches bronzeverstärktes Kettenhemd\nSchwer und ineffizient!"
	],
	"armor hadagan_highest_shirt iron": [
		"a40d74d90118a11a3d8e88b39f7d920a7921ab966ba0e2266f9ac8cd2c1c359d",
		"Khadaganian reinforced iron chainmail\nIron plates are a bit stronger than bronze ones...",
		"Khadaganianisches eisenverstärktes Kettenhemd\nEisenplatten sind etwas stabiler als Bronzeplatten."
	],
	"armor hadagan_highest_shirt meteoric": [
		"a9340dbd1199238f04329a29bc4b93dd9a0332c82934488349db9143b7271c7b",
		"Khadaganian reinforced meteorite chainmail\nVery reliable body protection!",
		"Khadag. Meteorit-Eisenv. Kettenhemd\nEin sehr zuverlässiger Körperschutz."
	],
	"armor hadagan_highest_shirt mithrill": [
		"9837c7c875f4ae31688bdcc83305872742addc1c0240fadacf96d041c34b50e8",
		"Khadaganian reinforced mithrill chainmail\nLight and strong armor.",
		"Khadaganianisches mithrilverstärktes Kettenhemd\nEine leichte und stabile Panzerung."
	],
	"armor hadagan_highest_shirt steel": [
		"f26d5d48dc21a43d42e3ebcb5dd075a4350a5a6d9f0145ca35e29d9b9fbce180",
		"Khadaganian reinforced steel chainmail\nNot too expensive, and provides decent protection.",
		"Khadaganianisches stahlverstärktes Kettenhemd\nNicht sehr teuer, aber trotzdem eine gute Panzerung."
	],
	"armor hadagan_low_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_boots cotton": [
		"1af3c005c672a784314f785e4186ebc06680c9eb815e6ca83b6f3f421beaa132",
		"Light cotton boots\nPoor boots for poor people…",
		"Leichte Baumwollstiefel\nAuch arme Leute brauchen Schuhe."
	],
	"armor hadagan_low_boots silk_blue": [
		"5bbcee3cb37569a92f93ea101b277bc1116dd6890db3bd2feb3fc4c51f0351ed",
		"Light silk boots\nSilk is prettier than wool, but it does not provide any protection.",
		"Leichte Seidenstiefel\nSeide sieht besser aus als Wolle - bietet aber keinerlei Schutz."
	],
	"armor hadagan_low_boots silk_red": [
		"4a9389e4837286d200d3093922e3daeabc27ae63d0a3600ae6add4dedf26ff28",
		"Light woollen boots\nPlain and simple cloth boots.",
		"Leichte Wollstiefel\nEinfache Stiefel."
	],
	"armor hadagan_low_boots wool": [
		"61533b73f40cf481e04c5cbef2cdbd72302257779ee263aec49957b013a77ca9",
		"Light boots of rough fabric\nA simple plain garment made of rough fabric.",
		"Leichte Stiefel aus grobem Stoff\nEinfache Stiefel aus grobem Stoff."
	],
	"armor hadagan_low_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_gloves cotton": [
		"3719ba393c568d326a5d3913b9b97b00751d7e149c68e8abbd1af43228b14669",
		"Cotton gauntlets\nJust a piece of cloth, really.",
		"Baumwollhandschuhe\nNur ein Stück Stoff."
	],
	"armor hadagan_low_gloves silk_blue": [
		"d9b60b367175481a26928363f177f6204c885df38f9354047970361cf7207d08",
		"Silk gauntlets\nCloth gauntlets - maybe they would protect you from thorns.",
		"Seidenhandschuhe\nStoffhandschuhe bieten kaum Schutz."
	],
	"armor hadagan_low_gloves silk_red": [
		"f1042a7aa0560fe2cc17df19613766e16be4b567e25a3167554e51f240b0a6ec",
		"Woollen gauntlets\nCloth gauntlets provide hardly any protection at all.",
		"Wollhandschuhe\nWollhandschuhe schützen vor Kälte - mehr aber auch nicht."
	],
	"armor hadagan_low_gloves wool": [
		"b450298d30ddfc341e85527b9d7690cac4c0f9325ec3ac09d0fdc8682264d225",
		"Light gauntlets of rough fabric\nA simple plain garment made of rough fabric.",
		"Leichte Handschuhe aus grobem Stoff\nEinfache Stiefel aus grobem Stoff."
	],
	"armor hadagan_low_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_helm tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_helm thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_helm thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_leggins tanned_thin": [
		"8fd7145dc7b8985a8728df1ff62d15ef133a6e8c3e158a72e3aec65bedb97ab7",
		"Light top trousers of hard leather\nGood enough for working, but not for fighting.",
		"Leichte Überhosen aus derbem Leder\nGut für die Arbeit - aber nicht für den Kampf."
	],
	"armor hadagan_low_leggins thick": [
		"e87bc0c4db60a7a4ee606d3a237b15b5ffe00af02e4e875b802ff750861a969e",
		"Khadaganian light top trousers · Tough leather\nThese cannot be considered serious leg protection.",
		"Khadaganianische leichte Überhosen · Starkes Leder\nKein ernst zu nehmender Beinschutz."
	],
	"armor hadagan_low_leggins thin": [
		"99cc3ca91193fb511690c35d92108223cc29673cc4b52193e13b0d08678b2161",
		"Light top trousers of thin leather\nThese are just for show, not for protection.",
		"Leichte Überhosen aus dünnem Leder\nBieten kaum Schutz, sehen aber gut aus."
	],
	"armor hadagan_low_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_pants cotton": [
		"7d3fdd2e60fa398131713a9fe0d9cb5aad0e4dbd2f1f9de39def396be37c7f04",
		"Light cotton trousers\nAbout all these do is cover your nakedness...",
		"Leichte Baumwollhosen\nWenigstens ist man damit nicht mehr nackt."
	],
	"armor hadagan_low_pants silk_blue": [
		"81ceb1ccf7547d2425bdce0019616815590bfb4e5d1590c06162db53587be928",
		"Light silk trousers\nNot very serious protection, maybe from wind or dust.",
		"Leichte Seidenhosen\nBieten allerhöchstens Schutz vor Wind und Staub."
	],
	"armor hadagan_low_pants silk_red": [
		"9ba007807c26137c18636bb2910a9d7ac231637080211a6722d4b041b78be988",
		"Light woollen trousers\nJust trousers - no more, no less.",
		"Leichte Wollhosen\nHosen - nicht mehr und nicht weniger."
	],
	"armor hadagan_low_pants wool": [
		"114e04c449d3b722fa6ae61c3f395afc7171f9faf060ec40e8cbecdb08613d32",
		"Light trousers of rough fabric\nA simple plain garment made of rough fabric.",
		"Leichte Hosen aus grobem Stoff\nEinfache Stiefel aus grobem Stoff."
	],
	"armor hadagan_low_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_plate tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_plate thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_plate thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_prototype wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_low_shirt cotton": [
		"95fbc443552de397290429eb9e4070859da18057b9d3ac74ade75778badcb5c0",
		"Light cotton shirt\nA sleeveless shirt of average quality.",
		"Leichtes Baumwollhemd\nEin Hemd durchschnittlicher Qualität."
	],
	"armor hadagan_low_shirt silk_blue": [
		"9135f6bb5954e262f47c8499c7058cd76f6f6d143f662fc5b109daad41a55cda",
		"Light silk shirt\nStronger than others, but not much fancier.",
		"Leichtes Seidenhemd\nEtwas widerstandsfähiger, aber sonst nicht wirklich etwas Besonderes."
	],
	"armor hadagan_low_shirt silk_red": [
		"05c406ba08a6c09527cf9be3531a4bb7e4db796c9ed7d3b690ceb6d1c1fd5a82",
		"Light woollen shirt\nA simple sleeveless shirt.",
		"Leichtes Wollhemd\nEin einfaches Hemd."
	],
	"armor hadagan_low_shirt wool": [
		"8423630a7c640115bc991e7663f318515e50845aa648c4b28f4964acaae615b9",
		"Light shirt\nA simple plain garment made of rough fabric.",
		"Leichtes Hemd\nEinfache Stiefel aus grobem Stoff."
	],
	"armor hadagan_medium2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_boots tanned_thin": [
		"d276348d8d82a4cadb437854c37556598c2fe93da10726577fd742d499284046",
		"Quilted boots · Hard leather\nNow you can risk getting into a fight - but not into combat!",
		"Gesteppte Stiefel · Hartes Leder\nDiese Stiefel sind für eine Schlägerei ausreichend, für einen ernsthaften Kampf taugen sie allerdings nicht!"
	],
	"armor hadagan_medium2_boots thick": [
		"cdfd6f5490d90c54a55e26275f5af7918e9bd2c9c4501f927b221f4f53f104c2",
		"Quilted boots · Tough leather\nGood price/performance ratio.",
		"Gesteppte Stiefel · Starkes Leder\nAnnehmbarer Schutz zu einem guten Preis."
	],
	"armor hadagan_medium2_boots thin": [
		"7d3094104c7bc38c65b921d308abb86db8103f8af7e5a72eb75253a36def6dcf",
		"Quilted boots · Thin leather\nThey are light and relatively strong.",
		"Gesteppte Stiefel · Dünnes Leder\nLeicht und trotzdem stabil."
	],
	"armor hadagan_medium2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_gloves tanned_thin": [
		"6bbcf25422b068560b3de886ba575209775f48408fc8e0f2bde48d46fa0d4096",
		"Quilted bracers · Hard leather\nHyena fangs no longer threaten your hands, but stronger enemies may lie ahead!",
		"Gesteppte Armschienen · Hartes Leder\nHyänenzähne bedrohen die Hände nicht mehr, doch unterwegs könnten stärkere Feinde warten!"
	],
	"armor hadagan_medium2_gloves thick": [
		"ad27783193eb6191f7478b051dab98b085596e8603b9e156b9123fc8891cec46",
		"Quilted bracers · Tough leather\nProvide decent protection for nearly the entire length of your arms.",
		"Gesteppte Armschienen · Starkes Leder\nGuter Schutz für fast den ganzen Arm."
	],
	"armor hadagan_medium2_gloves thin": [
		"71dfd48895158c06bb78f92a1c26aba20bed016a6cdfe11bf53ba8bcc32bd8ba",
		"Quilted bracers · Thin leather\nProvide almost complete protection for your arms, though the material could be better.",
		"Gesteppte Armschienen · Dünnes Leder\nBedecken fast den ganzen Arm. Das Material könnte allerdings besser sein."
	],
	"armor hadagan_medium2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_helm tanned_thin": [
		"4fdec3878e50e9a8146a5f018c856c22d36293c702905544715564f1cf655f4a",
		"Quilted helmet · Hard leather\nGood head protection. You can get better still, but it shall not be easy.",
		"Gesteppter Helm · Hartes Leder\nEin nahezu perfekter Kopfschutz - es wird schwer, noch etwas Besseres zu finden."
	],
	"armor hadagan_medium2_helm thick": [
		"9e377be8991fc75ba50741a398bf50b53fed33f6dedf998b75e1e8f08bc1fd62",
		"Quilted helmet · Tough leather\nDecent head protection, but by no means universal.",
		"Gesteppter Helm · Starkes Leder\nEin guter Kopfschutz - aber nur begrenzt einsetzbar."
	],
	"armor hadagan_medium2_helm thin": [
		"6611ccdd4d738e9d42a24c63a50f14e91fcfbb8324194a1e011ff3cc3d5dbb15",
		"Quilted helmet · Thin leather\nDecent head protection, but you should still avoid exposure to the axe!",
		"Gesteppter Helm · Dünnes Leder\nEin guter Kopfschutz - kann aber gegen eine Axt nicht viel ausrichten!"
	],
	"armor hadagan_medium2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_leggins tanned_thin": [
		"5fd1cd140cb9a6623d587b26df975124f52620f819a24029d919a70448bc9bd1",
		"Quilted leggings · Hard leather\nGood additional leg protection.",
		"Gesteppte Beinschienen · Hartes Leder\nEin guter zusätzlicher Schutz für die Beine."
	],
	"armor hadagan_medium2_leggins thick": [
		"a2186c7b56787dd918ce866dec16fba1785afa8b38b7f60db4d6e7879e824a9a",
		"Quilted leggings · Tough leather\nThey look good and protect better.",
		"Gesteppte Beinschienen · Starkes Leder\nBieten guten Schutz und sind sehr dekorativ."
	],
	"armor hadagan_medium2_leggins thin": [
		"bcb4ff57e2c2942fd69fa8d06f63ae975c5402374f1fe47427c36f1e4b42a368",
		"Quilted leggings · Thin leather\nNot the best material, though they would still protect you from the weaker blows.",
		"Gesteppte Beinschienen · Dünnes Leder\nNicht das beste Material - schützt aber immer noch gegen leichte Waffen."
	],
	"armor hadagan_medium2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_pants tanned_thin": [
		"5d0cb5b21469351d2c001fd807600a0b4e9b54dfa05e1c3a6ae0da622864a603",
		"Quilted trousers · Hard leather\nNot very comfortable for walking long distances, but excellent leg protection in combat.",
		"Gesteppte Hose · Hartes Leder\nNicht gerade geeignet für lange Märsche, aber perfekter Beinschutz im Kampf."
	],
	"armor hadagan_medium2_pants thick": [
		"91a9ba13acc707ebe4ed7909f2481a6736cb462e605e9e12179437083c6db1a2",
		"Quilted trousers · Tough leather\nGive your legs adequate protection.",
		"Gesteppte Hose · Starkes Leder\nGuter Schutz für die Beine."
	],
	"armor hadagan_medium2_pants thin": [
		"f7a1612058dcca425c18798714857e472af3eb206e9781175af1f286c3f05205",
		"Quilted trousers · Thin leather\nProtect your legs from top to bottom - as well as you can expect from thin leather.",
		"Gesteppte Hose · Dünnes Leder\nSchützen die Beine von oben bis unten - so, wie man es von dünnem Leder erwarten kann."
	],
	"armor hadagan_medium2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_plate tanned_thin": [
		"69c13ba772b61fc97cc9acbd1b803e365dd8847ff9fdfa4b467b4d453f965373",
		"Quilted cloak · Hard leather\nWorthy protection for your body.",
		"Gesteppter Umhang · Hartes Leder\nPerfekter Schutz für den ganzen Körper."
	],
	"armor hadagan_medium2_plate thick": [
		"a1952e278505e5f1e830c84dc0caa378da2942e9d920d26f97ddc23ad5f92656",
		"Quilted cloak · Tough leather\nGood cut, decent material. Sensible choice if your resources are limited.",
		"Gesteppter Umhang · Starkes Leder\nGuter Schnitt, anständiges Material. Eine gute Wahl, wenn nicht ausreichend Geld zur Verfügung steht."
	],
	"armor hadagan_medium2_plate thin": [
		"5c9b7949e9f6f56279190baf1be2ffabc542ca188e2f7b4cab62e8a3afe54ea8",
		"Quilted cloak · Thin leather\nGood cut, but rather poor material.",
		"Gesteppter Umhang · Dünnes Leder\nGuter Schnitt, aber nur mittelmäßiges Material."
	],
	"armor hadagan_medium2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium2_shirt tanned_thin": [
		"c2acde0f15cd6cbcb847a529d89379d926ce0a2d3c3494153058193fa1b29419",
		"Quilted breastplate · Hard leather\nA bit heavy, but provides good protection for your body.",
		"Gesteppter Brustschutz · Hartes Leder\nBietet perfekten Schutz - ist allerdings sehr schwer."
	],
	"armor hadagan_medium2_shirt thick": [
		"f2f8ad008490805287c588d92ea8e7e2984d75f5ae9f29e3ec3b31b5e66b5ef6",
		"Quilted breastplate · Tough leather\nProvides decent protection for your shoulders and part of your back.",
		"Gesteppter Brustschutz · Starkes Leder\nAngemessener Schutz für Schultern und einen Teil des Rückens."
	],
	"armor hadagan_medium2_shirt thin": [
		"1a394150c1118c8b57df8b062122ddd24b9f65d4b73c66a83be04281ba6b5166",
		"Quilted breastplate · Thin leather\nIt is not bad, but there's definitely better materials.",
		"Gesteppter Brustschutz · Dünnes Leder\nNicht der schlechteste. Das Material könnte aber besser sein."
	],
	"armor hadagan_medium_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_boots cotton": [
		"0dafafa6c3515cd4fe43172748b2e5e7362bc82bed365d289cf8b69a7eab1174",
		"Light Khadaganian cotton boots\nThese look better than rough fabric boots, but the quality is almost as bad.",
		"Khadaganianische leichte Baumwollstiefel\nSehen besser aus als Stiefel aus grobem Stoff. Die Qualität lässt allerdings zu wünschen übrig."
	],
	"armor hadagan_medium_boots silk_blue": [
		"a99038b6e66df64a17447ce5dd062c9aa3d525c35ff19e03d22cc1d8366cdc16",
		"Light Khadaganian silk boots\nLook very nice!  Not much protection though.",
		"Khadaganianische leichte Seidenstiefel\nSehen gut aus!"
	],
	"armor hadagan_medium_boots silk_red": [
		"beb6f481bfc848df2585d309bc1bc14fc059a51de5caf91b49721680dae6ba05",
		"Light Khadaganian woollen boots\nThese certainly are waterproof.",
		"Khadaganianische leichte Wollstiefel\nDiese Stiefel sind auf jeden Fall wasserdicht."
	],
	"armor hadagan_medium_boots wool": [
		"5c5c00c0fb889b73e99571fcb38013b3ea49c93af237c381048f94d8a71e4fd5",
		"Light Khadaganian boots of rough fabric\nRough fabric deteriorates almost immediately...",
		"Khadaganianische leichte Stiefel aus grobem Stoff\nGrober Stoff verschleißt zu schnell."
	],
	"armor hadagan_medium_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_gloves cotton": [
		"e8df456f6d80f5ac853ec9c3c3eb6f30985b4dcc5ecd074f856cf2b063482703",
		"Khadaganian cotton gauntlets\nNot much good in a fight…",
		"Khadaganianische Baumwollhandschuhe\nHöchstens ausreichend für eine harmlose Keilerei."
	],
	"armor hadagan_medium_gloves silk_blue": [
		"062fda4503d0f3c95ed197eea4bc811ba40b1777e3c81ecf77cf83376066050d",
		"Khadaganian silk gauntlets\nThese may look nice, but no cloth can provide real protection...",
		"Khadaganianische Seidenhandschuhe\nSehen gut aus, bieten aber keinen ernst zu nehmenden Schutz."
	],
	"armor hadagan_medium_gloves silk_red": [
		"a3c7be21b56ccd8a23f5200ca401d39878a65dc6e8661bffccc311e47b05dab2",
		"Khadaganian woollen gauntlets\nThese may save you from thorns.",
		"Khadaganianische Wollhandschuhe\nDiese Handschuhe schützen vor Dornen, aber auch nicht viel mehr."
	],
	"armor hadagan_medium_gloves wool": [
		"8cf338c8a5cc47850002af6ea35cd7a71dbd47dbcc69460d32e40e64a3e9972d",
		"Khadaganian rough fabric gauntlets\nThese may save you from a sprain.",
		"Khadaganianische Handschuhe aus grobem Stoff\nEtwas bessere Handschuhe."
	],
	"armor hadagan_medium_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_helm cotton": [
		"7de25f8576b6b27bbe5773a6af3069d77ec1ef673dee17821886c724e6694e27",
		"Khadaganian cotton turban\nA common Khadagan headgear.",
		"Khadaganianischer Baumwollturban\nEine verbreitete Khadaganianische Kopfbedeckung."
	],
	"armor hadagan_medium_helm silk_blue": [
		"3aa2419cfe161b50fb18527188df39626e3bdfa6e5c2cd3f253bbf4585a64078",
		"Khadaganian silk turban\nA rich citizen would be proud to wear this.",
		"Khadaganianischer Seidenturban\nSelbst die Reichsten würden ihn mit Stolz tragen."
	],
	"armor hadagan_medium_helm silk_red": [
		"bd78e6462276e33248a6e7b364b4c9d6819f7e6f4b4af24604d4ff0a0759e1d9",
		"Khadaganian woollen turban\nBetter wear this in cold weather.",
		"Khadaganianischer Wollturban\nIdeal für kaltes Wetter."
	],
	"armor hadagan_medium_helm wool": [
		"08acb0fa270b550d052ee2168499a97e9b2fb820c3448ccff47738f2fecd663a",
		"Khadaganian turban of rough fabric\nOnly the poorest Khadagans wear these...",
		"Khadaganianischer Turban aus grobem Stoff\nNur die ärmsten der Armen tragen einen solchen Turban."
	],
	"armor hadagan_medium_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_leggins cotton": [
		"2b878f55df420dff697dd69472d334b331ec9de81f1e750865b11bdbecef2cb0",
		"Khadaganian cotton trousers\nA common Khadagan garment.",
		"Khadaganianische Baumwollhosen\nSehr verbreitetes Kleidungsstück."
	],
	"armor hadagan_medium_leggins silk_blue": [
		"45d34fc9385eb142b5ff708c326164ab5cf3d2e250748565c5d6cd875466a423",
		"Khadaganian silk trousers\nStrong and it looks good too!",
		"Khadaganianische Seidenhosen\nSehen gut aus und sind durchaus widerstandsfähig."
	],
	"armor hadagan_medium_leggins silk_red": [
		"c65b85b4e45b0eab4121a4dbd2a52d54271f17551870611653ab4d631ccc7027",
		"Khadaganian woollen trousers\nA good cut, and comfortable too.",
		"Khadaganianische Wollhosen\nGuter Schnitt - bequemer Sitz."
	],
	"armor hadagan_medium_leggins wool": [
		"447fefd6d1abd92713a64239371bf1638cc570e2225eb2578b8361b152c2d624",
		"Khadaganian rough fabric trousers\nIf you can afford something better, why not?",
		"Khadaganianische Hosen aus grobem Stoff\nWer sich etwas Besseres leisten kann, sollte es tun."
	],
	"armor hadagan_medium_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_pants cotton": [
		"13ade59336aa3a8a9d00ab6cd202c1cfe02024e113bb689b3a8dd2e682ff7612",
		"Long Khadaganian cotton trousers\nAny cheap bazaar has these aplenty.",
		"Khadaganianische lange Baumwollhosen\nSolche Hosen findet man auf jedem billigen Basar."
	],
	"armor hadagan_medium_pants silk_blue": [
		"2be2fea95b688cbc6fe3f608003e0f7faa8e6b65349ed2cea65cf525ecdfdd34",
		"Long Khadaganian silk trousers\nThese do look good, and the cost reflects that!",
		"Khadaganianische lange Seidenhosen\nSehen gut aus und ihr Preis ist entsprechend."
	],
	"armor hadagan_medium_pants silk_red": [
		"f2b261f8fe6678c0fc89391571487df933894b7eb428dd8d6224f1f6c8f261f6",
		"Long Khadaganian woollen trousers\nCitizens with a middle income wear such apparel.",
		"Khadaganianische lange Wollhosen\nTypische Kleidung der einfachen Leute."
	],
	"armor hadagan_medium_pants wool": [
		"b4a13184eb77b9b2f3e5c365626c21ab953129759f3dfa255ae0909045ed13e8",
		"Long Khadaganian trousers of rough fabric\nJust trousers, really - you cannot do without them, or can you?",
		"Khadaganianische lange Hosen aus grobem Stoff\nEinfache Hosen ohne besondere Eigenschaften."
	],
	"armor hadagan_medium_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_plate cotton": [
		"50a0ad95e5f883dc82de53e06d0e622fe2730e8645c9c10ae9408c8b80c3c832",
		"Khadaganian cotton coat\nA common Khadagan garment.",
		"Khadaganianischer Baumwollmantel\nSehr verbreitetes Kleidungsstück."
	],
	"armor hadagan_medium_plate silk_blue": [
		"606de37c1033648a503d363929fcd3c19bdcc90ef054870dcb6a7b2df0b50ec2",
		"Khadaganian silk coat\nA most distinguished garment!",
		"Khadaganianischer Seidenmantel\nSehr edles Kleidungsstück!"
	],
	"armor hadagan_medium_plate silk_red": [
		"a665a621910924ef500e356d5e294a629beccf63ce947571076ad7925d43e609",
		"Khadaganian woollen coat\nWell cut, and decent material too.",
		"Khadaganianischer Wollmantel\nGuter Schnitt - anständiges Material."
	],
	"armor hadagan_medium_plate wool": [
		"8314c560e8e456014314dcbd9117b0f739b5a4692c68f20fed00d7364e477e5e",
		"Khadaganian coat of rough fabric\nIt would be a shame to wear this in public…",
		"Khadaganianischer Mantel aus grobem Stoff\nIn der Öffentlichkeit kann man sich damit fast nicht zeigen."
	],
	"armor hadagan_medium_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_prototype cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_prototype silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_prototype silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_prototype wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_medium_shirt cotton": [
		"96b6fffa8f467c6c7e1c60e4cc22e89c04896c46e977c4375b06e91edb6ade5b",
		"Long Khadaganian cotton shirt\nCotton is not much better than rough fabric...",
		"Khadaganianisches langes Baumwollhemd\nBaumwolle ist kaum besser als grober Stoff."
	],
	"armor hadagan_medium_shirt silk_blue": [
		"469b21ed1768709343233cdc53c0f7b25827bfca64e3390c594f93f555742d5f",
		"Long Khadaganian silk shirt\nThis would look better in a tavern than in combat.",
		"Khadaganianisches langes Seidenhemd\nDieses Hemd trägt man besser beim Zechen als im Kampf."
	],
	"armor hadagan_medium_shirt silk_red": [
		"59a2febb8e4ca5d54af2747306ae88f817ee5a6b0caaa7ff17226184a30f48ec",
		"Long Khadaganian woollen shirt\nThis will protect your skin from sun, not from weapons.",
		"Khadaganianisches langes Wollhemd\nSchützt vor Sonne - nicht vor Waffen."
	],
	"armor hadagan_medium_shirt wool": [
		"024bc75beca372c6b97dca1e3993b8cf69a789391e06b4a314ff19157a2f523c",
		"Long Khadaganian shirt of rough fabric\nGood enough to wear for work.",
		"Khadaganianisches langes Hemd aus grobem Stoff\nFür Arbeiter reicht es."
	],
	"armor hadagan_special_brigand_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_leggins tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_leggins thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_leggins thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_pants tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_pants thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_pants thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_shirt tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_shirt thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor hadagan_special_brigand_shirt thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_boots diamond": [
		"89525a43f4ee4c61674969de072f5b3dd6718ef7adadb89572a643dac94e9b1c",
		"Joon light diamond leggings\nOne cannot find such craftsmen nowadays.....",
		"Leichte Diamant-Beinlinge der Joon\nDas Produkt längst vergangener Handwerkskunst..."
	],
	"armor jun_high_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_gloves diamond": [
		"4ff3ebc70c3eb219bb9fee3d9b85962a2f89d7065981bd3ddcf766cf2ad41a59",
		"Joon diamond gauntlets\nNo modern craftsman can make such things...",
		"Diamanthandschuhe der Joon\nHeute wird so etwas Edles gar nicht mehr hergestellt."
	],
	"armor jun_high_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_helm diamond": [
		"ed78ca5c41a1d7ff1793d82e512f32f8fe7366f97f7b1372021856899b5ec582",
		"Joon diamond helmet\nNo one knows the ancient secrets of such craftsmanship...",
		"Diamanthelm der Joon\nDas Geheimnis für die Herstellung solcher Gegenstände ist längst vergessen."
	],
	"armor jun_high_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_leggins diamond": [
		"6c0205ecb1dc169504a7b05c727517b93b0bf9c42ae084608cab6b08851229e7",
		"Joon diamond full leggings\nAnyone would trade half a lifetime for such skill...",
		"Schwere Diamant-Beinlinge der Joon\nFür eine solche Kunstfertigkeit würde ein Handwerker Jahre seines Lebens opfern."
	],
	"armor jun_high_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_pants diamond": [
		"aa608756b518d8c1f305b611465e8c9f616e80df5418dde2cb2dc46fb7cd7dbd",
		"Joon diamond trousers\nEven the best of craftsmen could not make such a garment!",
		"Diamanthosen der Joon\nEs gibt niemanden, der noch so etwas herstellen könnte."
	],
	"armor jun_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_plate diamond": [
		"df0164868d1aef19812bdc204205ad09b42341bd3b24ad785ed23d5f7a7a87af",
		"Joon diamond cuirass\nNo craftsmen remain who know how to make such things...",
		"Diamant-Brustharnisch der Joon\nEs gibt keine Handwerker mehr, die solche Dinge herstellen können ..."
	],
	"armor jun_high_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_prototype diamond": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor jun_high_shirt diamond": [
		"f2714c8fbeeb43bd9382812b3dfc2ea23caa314544b67b586583a42d63385210",
		"Joon diamond shirt\nNo living craftsman still knows how to make such things...",
		"Diamanthemd der Joon\nKein lebender Handwerker weiß noch, wie man solche Dinge herstellt ..."
	],
	"armor kania_brigand_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_boots tanned_thin": [
		"4f8bbad74e0b87d7fcbf8f53581f1327e51fe46587cf650e9578b7417c09cd8c",
		"Canian heavy boots of hard leather\nMany a beast would break their teeth on these!",
		"Canianische schwere Stiefel aus derbem Leder\nMit diesen Stiefeln muss man kaum eine Kreatur fürchten."
	],
	"armor kania_brigand_boots thick": [
		"db4f2365c1869cab8bf27cf09f4a931330962a03f7899ff2c168bfd102f8344b",
		"Heavy Canian boots · Tough leather\nThe material is stronger than thin leather - and the price is higher.",
		"Canianische schwere Stiefel · Starkes Leder\nBesser als dünnes Leder - und teurer."
	],
	"armor kania_brigand_boots thin": [
		"e4d4ca8426c9635ad4fcffcb2112195f565983dcb8b9c0f66bae0823e0b2b70d",
		"Canian heavy boots of thin leather\nLight and comfortable, but not too strong....",
		"Canianische schwere Stiefel aus dünnem Leder\nLeicht und bequem - aber nicht gerade widerstandsfähig."
	],
	"armor kania_brigand_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_gloves tanned_thin": [
		"39ffab10258af28d60708e9add54579650e905342d0b7d765c0e25fe39d32999",
		"Canian heavy gauntlets of hard leather\nGood protection, and good freedom of movement.",
		"Canianische schwere Handschuhe aus derbem Leder\nEine Kombination aus großer Bewegungsfreiheit und gutem Schutz."
	],
	"armor kania_brigand_gloves thick": [
		"f2fd355a2cd548a3a28b3946af070c76874fe4d6b1cafeab30fb23230d27aa18",
		"Heavy Canian gauntlets · Tough leather\nThese would protect your arms in a tavern knife fight.",
		"Canianische schwere Handschuhe · Starkes Leder\nReichen für eine kleine Messerstecherei."
	],
	"armor kania_brigand_gloves thin": [
		"629a840f54e8b55ef160e4f81498a5f396b7d80f65291239f382cefc209268a9",
		"Canian heavy gauntlets of thin leather\nWell, if this is all you can afford...",
		"Canianische schwere Handschuhe aus dünnem Leder\nNur für die, die sich nicht mehr leisten können."
	],
	"armor kania_brigand_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_helm tanned_thin": [
		"0d2ddf56d2e9abe07e9662f5afb83ab6fd3bb51fbb94f240b43e092944251e27",
		"Canian heavy helmet of hard leather\nProtects your head, and not just from the cold!",
		"Canianischer schwerer Helm aus derbem Leder\nSchützt den Kopf nicht vor Kälte."
	],
	"armor kania_brigand_helm thick": [
		"2925eafac33d5f1d134add27b94cb1a61a9108b72e8e43b51ea345a3c6ec9ac8",
		"Heavy Canian helmet · Tough leather\nIt is well-made and strong.",
		"Canianischer schwerer Helm · Starkes Leder\nLeicht und sehr stabil!"
	],
	"armor kania_brigand_helm thin": [
		"bbaaa55e28a8cd40a6a8c754b5c58c65d06890828da1b04e4cf86bee5c5d4328",
		"Canian heavy helmet of thin leather\nYou should look for a stronger material...",
		"Canianischer schwerer Helm aus dünnem Leder\nEin härteres Material wäre besser."
	],
	"armor kania_brigand_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_leggins tanned_thin": [
		"e0e242a741219e618516797e958f0eae4a0c3b67063a5cec0c17f0e6ee5f434b",
		"Canian heavy top trousers of hard leather\nProvides decent protection and also ensures freedom of movement.",
		"Canianische schwere Überhosen aus derbem Leder\nBieten guten Schutz und sind bequem zu tragen."
	],
	"armor kania_brigand_leggins thick": [
		"dadc0c2ccb03539495518c1b1ce84851648306c8c66c23cb783006d2a43135e3",
		"Heavy Canian top trousers · Tough leather\nThese are better, but you could still find better trousers.",
		"Canianische schwere Überhose · Starkes Leder\nNicht schlecht. Aber es gibt Besseres."
	],
	"armor kania_brigand_leggins thin": [
		"206b8d704c9ade0d651e264d587ffb41719bb7e33d6c58db110e32316c064c3c",
		"Canian heavy top trousers of thin leather\nThe material is a bit thin - maybe you should pay a bit more for something better?",
		"Canianische schwere Überhosen aus dünnem Leder\nDas Material ist etwas zu dünn - vielleicht sollte man etwas mehr für dickeres Leder ausgeben."
	],
	"armor kania_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_pants tanned_thin": [
		"df17e84f66b3a8dc53ef7807e541648b22558e0c162d24803fd6f7d2a17354a0",
		"Canian heavy trousers of hard leather\nA good choice for a warrior who wishes both protection and freedom of movement.",
		"Canianische schwere Hosen aus derbem Leder\nIdeal für einen Krieger, der Wert auf Schutz und Beweglichkeit legt."
	],
	"armor kania_brigand_pants thick": [
		"1568eba67b095b6f6c89a71156fcf3ec59b3a2e6f4a2b4d39099d56e86c9da00",
		"Heavy Canian trousers · Tough leather\nA Tiger would not break any teeth on these, but at least you can run quickly.",
		"Canianische schwere Hose · Starkes Leder\nWiderstehen zwar nicht jedem Tigerbiss, bieten aber dafür große Bewegungsfreiheit."
	],
	"armor kania_brigand_pants thin": [
		"c9576ab81bd5b0f5727d581741f55e391de1820c48261101302e56a897aa3d48",
		"Canian heavy trousers of thin leather\nA bit thin, but comfortable.",
		"Canianische schwere Hosen aus dünnem Leder\nDünn, aber bequem!"
	],
	"armor kania_brigand_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_plate tanned_thin": [
		"dddc31437394e7328e23aeaf4ffb1f38e284282169d30014fa29ec5c46823383",
		"Canian heavy coat of hard leather\nProtects you from a knife stab in the back!",
		"Canianischer schwerer Mantel aus derbem Leder\nSchützt vor Messerstichen in den Rücken!"
	],
	"armor kania_brigand_plate thick": [
		"3f43c900acbe80ec98bbf99591c5d559693825f15712b14d757c4a624d95e2e3",
		"Heavy Canian coat · Tough leather\nGood choice - provides protection and freedom of movement.",
		"Canianischer schwerer Mantel · Starkes Leder\nEine gute Wahl - eine sinnvolle Mischung aus Schutz und Beweglichkeit."
	],
	"armor kania_brigand_plate thin": [
		"949af4fc2ad829705010dd559c2efd79971159befdc8b62c20e28f4d5c796ca6",
		"Canian heavy coat of thin leather\nYou should consider using another material for this type of coat…",
		"Canianischer schwerer Mantel aus dünnem Leder\nEin anderes Material wäre für diesen Mantel besser."
	],
	"armor kania_brigand_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_prototype tanned_thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_prototype thick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_prototype thin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_brigand_shirt tanned_thin": [
		"773f3eb56ad537af53441efc3c702685909d47853893553858ebeb9a9c368b97",
		"Canian heavy jerkin of hard leather\nGood mix of protection and freedom of movement.",
		"Canianische schwere Weste aus derbem Leder\nBietet guten Schutz und ist bequem zu tragen."
	],
	"armor kania_brigand_shirt thick": [
		"f8a75c8b76b8bd93987f14267448c70e77cc21a3c0794be7e1a507732f41dd29",
		"Heavy Canian jerkin · Tough leather\nBetter than a thin leather shirt, and ensures freedom of movement too.",
		"Canianischer schwerer Wams · Starkes Leder\nBesser als ein Hemd aus dünnem Leder. Bietet guten Schutz."
	],
	"armor kania_brigand_shirt thin": [
		"c8740635f65a367f1bb6f4281ae05bf80f2a8fd63d1b76116ab095fa26a19b77",
		"Canian heavy jerkin of thin leather\nProvides freedom of movement - and some protection too.",
		"Canianische schwere Weste aus dünnem Leder\nGroße Bewegungsfreiheit, aber nur geringer Schutz."
	],
	"armor kania_high2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_boots adamantium": [
		"ea3ffd7cd43053f2860051838a0c1410237ad6b01127ee58f1a10022d74c07e4",
		"Canian army adamantite boots\nUsed by Canian army leaders.",
		"Canianische Militärstiefel aus Adamant\nDie Führer der canianischen Armee würden niemals etwas anderes tragen."
	],
	"armor kania_high2_boots bronze": [
		"4c8549c4663e827eb33680ba6f3d0cebf08895c571cf0e36609781494fd4fea1",
		"Canian army bronze boots\nHeavy and uncomfortable - just right for raw recruits.",
		"Canianische Armeestiefel aus Bronze\nSchwer und unbequem - genau die richtige Ausrüstung für einfache Rekruten."
	],
	"armor kania_high2_boots iron": [
		"ec772e0204b42b80de8f50f2dbad381e0ed6424e37ce4cece3d9b68ed1deef2b",
		"Canian army iron boots\nStandard Canian army boots for privates.",
		"Canianische Armeestiefel aus Eisen\nCanianische Standardausrüstung für einfache Soldaten."
	],
	"armor kania_high2_boots meteoric": [
		"4cc8f81bb0f02b12f19d3fa7888f60c77c0d4a946f8024051f8cfe4d0e429d9c",
		"Canian army meteorite boots\nThese are for military chiefs and the scions of rich families only...",
		"Canianische Armeestiefel aus Meteorit-Eisen\nStiefel für hochrangige Offiziere und Söhne reicher Familien."
	],
	"armor kania_high2_boots mithrill": [
		"d173ec680783bef1054d5eedd15b0679dde4666b962dc536f33d28ca38ab584c",
		"Canian army mithrill boots\nApproved by the Emperor as standard for the guard force of the Canian Veterans.",
		"Canianische Armeestiefel aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_boots steel": [
		"2c2d733bc8f545be20850522ede5def1e06b26f29efa7efd99608e3340b5050e",
		"Canian army steel boots\nCanian army issue for officers.",
		"Canianische Armeestiefel aus Stahl\nCanianische Standardausrüstung für Offiziere."
	],
	"armor kania_high2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_gloves adamantium": [
		"2e9c8e86c598c941bcec1e3da02d72c5fa26286c1b8241aa1b1354badee436c0",
		"Canian army adamantite high gauntlets\nStandard for Canian military chiefs.",
		"Canianische l. Armee-Handschuhe - Adamant\nCanianische Standardausrüstung für hochrangige Offiziere."
	],
	"armor kania_high2_gloves bronze": [
		"dacfaf3af67d4bc66ce7fa21ca864a983adc9db82ac45f8d731a90a1d4a59584",
		"Canian army bronze high gauntlets\nOnly raw recruits would wear these without complaint.",
		"Canianische lange Armee-Handschuhe aus Bronze\nNur Rekruten würden sich klaglos damit herumplagen."
	],
	"armor kania_high2_gloves iron": [
		"1b8b6cbfeb4e04db88d91ff36803478594c39b773af35ed637f883cf585933be",
		"Canian army iron high gauntlets\nIssued to Canian privates.",
		"Canianische lange Armee-Handschuhe aus Eisen\nAusrüstung für einfache Soldaten."
	],
	"armor kania_high2_gloves meteoric": [
		"bee96373d7953430fa050860a9e5b935aa52d2414946c1c01497f27f286d1ea4",
		"Canian army meteorite high gauntlets\nNot every officer can afford these!",
		"Canianische l. Armee-Handsch. - Meteorit-Eisen\nSind nicht für jeden Offizier erschwinglich!"
	],
	"armor kania_high2_gloves mithrill": [
		"127318ba60ab8c682a88d8098c02a0d4818eacba634c163ed08f7597d94b2896",
		"Canian army mithrill high gauntlets\nApproved by the Emperor as standard for the guard force of the Canian Veterans.",
		"Canianische lange Armee-Handschuhe aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_gloves steel": [
		"b9f31bfc7d85457fc2f69b5b9a46034d4e2706ceef4baea605cef9ff434da79a",
		"Canian army steel high gauntlets\nHigh gauntlets for officers.",
		"Canianische lange Armee-Handschuhe aus Stahl\nLange Handschuhe für Offiziere."
	],
	"armor kania_high2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_helm adamantium": [
		"20593de68b8e7a72b3bc54033c3e334c561c048d5b5193302abe98a6835110c3",
		"Canian army adamantite helmet\nAnyone wearing a helmet like this would be immediately recognized as a high-ranking officer.",
		"Canianischer Armeehelm aus Adamant\nMit diesem Helm wird man überall als höherer Offizier erkannt."
	],
	"armor kania_high2_helm bronze": [
		"414a82ca7d272d4a63e57008658d57db9fc08f35a3d9422e996e3e70ac754e33",
		"Canian army bronze helmet\nTrain hard, fight easy - this helmet says it all....",
		"Canianischer Armeehelm aus Bronze\nDieser Helm ist unglaublich schwer."
	],
	"armor kania_high2_helm iron": [
		"7ca98c0f4f9e6c7e63cb9be5e471cdcef60aa9c4eb9ca366ede592dbce3c709c",
		"Canian army iron helmet\nHelmet for Canian army privates.",
		"Canianischer Armeehelm aus Eisen\nHelm für einfache Soldaten."
	],
	"armor kania_high2_helm meteoric": [
		"1f895d89edc84c4e1316ba2a119d3d1ff99b28101cfdce38c9fa334b0344c74b",
		"Canian army meteorite helmet\nLooks awesome - and costs an awesome amount!",
		"Canianischer Armeehelm aus Meteorit-Eisen\nSieht gut aus - ist aber unglaublich teuer."
	],
	"armor kania_high2_helm mithrill": [
		"afe4d1d5290cb96555d4e94e8bec875578d9dc78e5924e6d0f01779e03e9ffeb",
		"Canian army mithrill helmet\nApproved by the Emperor as standard for the guard force of the Canian Veterans .",
		"Canianischer Armeehelm aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_helm steel": [
		"534f36e866d2ba64e945d412d3061639929496b330cf0ffcc29195f9f7b47c39",
		"Canian army steel helmet\nStandard for Canian army officers.",
		"Canianischer Armeehelm aus Stahl\nCanianische Standardausrüstung für Offiziere."
	],
	"armor kania_high2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_leggins adamantium": [
		"eb9fb2df309070cca10eb42ba65fdbbc4c2068485dc50666517527cf7718b0c1",
		"Canian army adamantite leggings\nA simple soldier would never even see such leggings.",
		"Canianische Armee-Beinlinge aus Adamant\nDer einfache Soldat bekommt solche Beinlinge nicht einmal zu sehen."
	],
	"armor kania_high2_leggins bronze": [
		"3eb987507f60c891236d32774810b86799aa6809db4434f2343a303590ae98ba",
		"Canian army bronze leggings\nIssued to Canian army raw recruits.",
		"Canianische Armee-Beinlinge aus Bronze\nAusrüstung für Rekruten."
	],
	"armor kania_high2_leggins iron": [
		"77943baca5357c1370e3bfec89dacb9f9e8b0a8b9347948331e62ab7fedddf79",
		"Canian army iron leggings\nThese are for privates.",
		"Canianische Armee-Beinlinge aus Eisen\nAusrüstung für einfache Soldaten."
	],
	"armor kania_high2_leggins meteoric": [
		"bb70990f2ba02ded64129b1a85e1d8c317f2ac1dd29ffca339803c7de7a6d894",
		"Canian army meteorite leggings\nIt would be very difficult to find better leggings in Canian - or more expensive ones!",
		"Canianische Armee-Beinlinge aus Meteorit-Eisen\nEs gibt keine besseren Beinlinge in Canian - und keine kostspieligeren!"
	],
	"armor kania_high2_leggins mithrill": [
		"eb604c7408ca2b41abdc8567f5769ec9427bedff0a51b215bd55573ebdb74917",
		"Canian army mithrill leggings\nApproved by the Emperor as standard for the guard force of the Canian Veterans.",
		"Canianische Armee-Beinlinge aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_leggins steel": [
		"189c10b820f6241dafd88af90c4614c79c9720c3a7dac17503e9c9b5bff6ce82",
		"Canian army steel leggings\nThese are for officers.",
		"Canianische Armee-Beinlinge aus Stahl\nBeinlinge für Offiziere."
	],
	"armor kania_high2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_pants adamantium": [
		"6c2f6a80e48c566f107a06830ea13eadbf01e0f9613609019889a271cc9870ac",
		"Canian army chainmail trousers · Adamantite\nApproved for Canian army military chiefs .",
		"Canianische Armee-Kettenhosen · Adamantit\nReserviert für die Führer der Armee."
	],
	"armor kania_high2_pants bronze": [
		"add57f3d960ccf73ff186cdb4e7683d7c9a8f42943d7c262c1bdfe6d96ee28be",
		"Canian army bronze chainmail trousers\nOnly raw recruits wear these.",
		"Canianische Armee-Kettenhosen aus Bronze\nNur Rekruten würden sich klaglos damit herumplagen."
	],
	"armor kania_high2_pants iron": [
		"75be24751de359f5e84e61a96312285ad441e57a6713a810661626cbe652258a",
		"Canian army iron chainmail  trousers\nApproved as standard for privates.",
		"Canianische Armee-Kettenhosen aus Eisen\nCanianische Standardausrüstung für einfache Soldaten."
	],
	"armor kania_high2_pants meteoric": [
		"c1b05cb8758c839e5c520607a29973370420f265faf4cc308feeb34c4a63e08a",
		"Cania army leggings\nApproved by the Emperor as Cania army standard.",
		"Canianische Armee-Kettenh. aus Meteorit-Eisen\nStandardausrüstung der Canianischen Armee."
	],
	"armor kania_high2_pants mithrill": [
		"a2db4d60ce02b675a8a6c53e1a0698f84e20ca6d94c76f9810b8e4795b04d41a",
		"Canian army mithrill chainmail  trousers\nApproved by the Emperor as standard for the guard force of the Canian Veterans.",
		"Canianische Armee-Kettenhosen aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_pants steel": [
		"897daaf2add531fe5d5ef489cad430c755b2747154a450a7053974bc26ac6911",
		"Canian army steel chainmail  trousers\nArmy standard for officers.",
		"Canianische Armee-Kettenhosen aus Stahl\nCanianische Standardausrüstung für Offiziere."
	],
	"armor kania_high2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_plate adamantium": [
		"3a1bea5f42693df9973ea5e2c8c149dcf96f7027f2fbf3f6d6a37f0dde522c7e",
		"Canian army adamantite cuirass\nA luxurious and reliable armor, standard for Canian military chiefs .",
		"Canianischer Armee-Brusth. aus Adamant\nEdel und zuverlässig - die Führer der canianischen Armee bevorzugen diese Art von Ausrüstung."
	],
	"armor kania_high2_plate bronze": [
		"3c9bad9b247d006e4281a1f9e49ce794eb4f1feacfad8d216826593cb1474de3",
		"Canian army bronze cuirass\nThese are issued to raw recruits - that tells the whole story.",
		"Canianischer Armee-Brusth. aus Bronze\nAusrüstung für Rekruten - das sagt alles."
	],
	"armor kania_high2_plate iron": [
		"7a388503f4a41dfa55a0e450a480a7802e61c00edab7371371f862d90d3b526e",
		"Canian army iron cuirass\nA cuirass for privates.",
		"Canianischer Armee-Brustharnisch aus Eisen\nBrustharnisch für einfache Soldaten."
	],
	"armor kania_high2_plate meteoric": [
		"2420f0282d11758d29ee3342d17342a60057ddca5e281315069739e7763a2f9e",
		"Canian army meteorite cuirass\nYou could find something even better and more expensive, but t'will not be a simple task!",
		"Canianischer Armee-Brusth. aus Meteorit-Eisen\nEs wird schwer sein, etwas Besseres zu finden."
	],
	"armor kania_high2_plate mithrill": [
		"e5f7e1a2b2f8682319ef4e5388f276348b430a55fa371147b726c112c18d3afe",
		"Canian army mithrill cuirass\nApproved by the Emperor as standard for the guard force of the Canian Veterans.",
		"Canianischer Armee-Brusth. aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_plate steel": [
		"dada727df9ef2b026ff55e2d00cbf72af96f43047a7f1aad0d3cf25bdb17930a",
		"Canian army steel cuirass\nArmy standard for officers.",
		"Canianischer Armee-Brustharnisch aus Stahl\nCanianische Standardausrüstung für Offiziere."
	],
	"armor kania_high2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high2_shirt adamantium": [
		"e71d9e26e00cb856818a69718718d940f1b6ce5877911d53421e6d5cc83231a3",
		"Canian army adamantite chainmail\nApproved by the Emperor for Canian army military chiefs .",
		"Canianischer Armee-Kettenp. aus Adamant\nVom Imperator für die Führer der Armee genehmigt."
	],
	"armor kania_high2_shirt bronze": [
		"b72ec314175aa4c4b1ba1aa5d2a8c35a3b85a021bae8e80a871a36971d9a72f4",
		"Canian army bronze chainmail\nRaw recruits usually wear these - for exercise and general use.",
		"Canianischer Armee-Kettenp. aus Bronze\nWird viel von einfachen Rekruten während der Ausbildung getragen."
	],
	"armor kania_high2_shirt iron": [
		"16abeb482185aa20cb3b241573abdef8e008b988a3f863aec302aae7ae4e9dda",
		"Canian army iron chainmail\nChainmail for Canian privates.",
		"Canianischer Armee-Kettenpanzer aus Eisen\nEin Kettenpanzer für einfache Soldaten."
	],
	"armor kania_high2_shirt meteoric": [
		"c05b3f5f92995e46ec6b35fa5002869e3d00c3c543578e0c625b27d7ae8873c6",
		"Canian army meteorite chainmail\nOnly military chiefs can have these - sometimes.",
		"Canianischer Armee-Kettenp. aus Meteorit-Eisen\nNicht mal alle Führer der Armee können sich den leisten!"
	],
	"armor kania_high2_shirt mithrill": [
		"24f78be146a29eef6646c05c46fa47eb77fbb3c58a6f85e5762bed2607fd55f6",
		"Canian army mithrill chainmail\nApproved by the Emperor as standard for the guard force of the Canian Veterans .",
		"Canianischer Armee-Kettenp. aus Mithril\nVom Imperator angewiesene Ausrüstung für die Veteranen der Leibgarde."
	],
	"armor kania_high2_shirt steel": [
		"89e863a946f5f7455ebdd940bfcb8875f6a1b48914373bbc0ccc9e7f566bf679",
		"Canian army steel chainmail\nArmy standard for officers.",
		"Canianischer Armee-Kettenpanzer aus Stahl\nCanianische Standardausrüstung für Offiziere."
	],
	"armor kania_high_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_boots dragon_black": [
		"45554ea012deefbc537f61b9b8affb2a5c2c3b1df05b227dfecfbbd7c492f963",
		"Canian light boots of Blue Dragon hide\nNot the best possible protection in combat, but not bad…",
		"Canianische leichte Stiefel aus blauer Drachenhaut\nNicht gerade optimaler Schutz in einem Kampf, aber es gibt auch Schlechteres."
	],
	"armor kania_high_boots dragon_green": [
		"3dc40ba9b9c50a750aeccce1fa4c0b588ecafe68281d907c33c05883e9b4d942",
		"Canian light boots of Green Dragon hide\nDo not dance on swords in these, but otherwise...",
		"Canianische leichte Stiefel aus grüner Drachenhaut\nSolange man nicht direkt in einen Schwerthieb läuft, sind diese Stiefel absolut ausreichend."
	],
	"armor kania_high_boots dragon_red": [
		"3ee6b7753387e7fd5472840849d39ebe912115780dfcf6b79ddbed184b377f7b",
		"Canian light boots of Red Dragon hide\nYou can walk on more than soft green grass in these boots.",
		"Canianische leichte Stiefel aus roter Drachenhaut\nMit denen kann man nicht nur im weichen Gras laufen."
	],
	"armor kania_high_boots lizard_black": [
		"576db5f172dd1c91ef4bb98135a7ee7948847e380eceb26be9cd30c7cc875f9f",
		"Light Canian combat boots · Mountain lizard hide\nOnly troll-hide boots are better.",
		"Canianische leichte Kampfstiefel · Bergechsenhaut\nNur Stiefel aus Trollhaut sind besser."
	],
	"armor kania_high_boots lizard_blue": [
		"7ffdecd83ec3f0717a12866677e2643a9ee198320183714face3cd7fb78e9c9d",
		"Light Canian combat boots · Lake lizard hide\nNot the best possible protection in combat, but not bad…",
		"Canianische leichte Kampfstiefel · Seeechsenhaut\nNicht gerade optimaler Schutz in einem Kampf, aber es gibt auch Schlechteres."
	],
	"armor kania_high_boots lizard_green": [
		"b1319cefcb29b16aa5380273467a35dc354cef9a4982cc077ffd346160273e55",
		"Light Canian combat boots · Forest lizard hide\nDo not dance on swords in these, but otherwise...",
		"Canianische leichte Kampfstiefel · Waldechsenhaut\nSolange man nicht direkt in einen Schwerthieb läuft, sind diese Stiefel absolut ausreichend."
	],
	"armor kania_high_boots ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_boots troll_black": [
		"0f359b2e02efd68091f3b1f9a076bbaf622e1496b040c0431ed4fcf7022e2a8a",
		"Canian light boots of black Troll hide\nOnly boots made of Dragon hide are better.",
		"Canianische leichte Stiefel aus schwarzer Trollhaut\nNur Stiefel aus Drachenhaut sind besser."
	],
	"armor kania_high_boots troll_blue": [
		"5576d0e0e677b7ef23278407bbf3aea2dab2ae02897451af51f25476bf852668",
		"Canian light boots of blue Troll hide\nThey are not very cheap - but the quality matches the price.",
		"Canianische leichte Stiefel aus blauer Trollhaut\nNicht gerade billig, aber ihren Preis absolut wert."
	],
	"armor kania_high_boots troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_boots troll_green": [
		"8922e09495d6f4315fdc97de851b6a82e241dd194fc763542dc298b881c87f00",
		"Canian light boots of green Troll hide\nDo not rely too much on these for protection.",
		"Canianische leichte Stiefel aus grüner Trollhaut\nDiese Stiefel bieten keinen optimalen Schutz."
	],
	"armor kania_high_boots troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_gloves dragon_black": [
		"98325be7c375850d5733f301abe18345bf5111eb6f67ad2325532b2bae597004",
		"Canian light gauntlets of Blue Dragon hide\nAgainst a sword? No....but they might help against a knife.",
		"Canianische leichte Handschuhe aus blauer Drachenhaut\nIn ein Schwert kann man mit ihnen nicht greifen, aber vielleicht in ein Messer..."
	],
	"armor kania_high_gloves dragon_green": [
		"a85530547f3821caacbc8378a7cccad1fa2e66be995cc5ce36902a963a767b16",
		"Canian light gauntlets of Green Dragon hide\nDo not try fishing in boiling water with these...you will find them good enough for combat...",
		"Canianische leichte Handschuhe aus grüner Drachenhaut\nAlles halten sie nicht ab, aber im Kampf bieten sie angemessenen Schutz."
	],
	"armor kania_high_gloves dragon_red": [
		"5664ceb5abcb7509ab21d59ac664c6c91e4dc3c657e007a3d2d4f27f79a36131",
		"Canian light gauntlets of Red Dragon hide\nThese would save you from a knife - and mayhap from bites too.",
		"Canianische leichte Handschuhe aus roter Drachenhaut\nBieten Schutz vor leichten Waffen und Tierbissen."
	],
	"armor kania_high_gloves lizard_black": [
		"a17056f59fc8fb32c3746d9f25473cb3e9311a507a2ac4d4f72f78e42d52e036",
		"Light Canian combat gauntlets · Mountain lizard hide\nIf a brazen wolf decides to have the owner of these for dinner, that will be one sorry wolf!!",
		"Canianische leichte Kampfhandschuhe · Bergechsenhaut\nDie widerstehen auch dem stärksten Wolfszahn."
	],
	"armor kania_high_gloves lizard_blue": [
		"9c4c54854812fff0692be92c281874d954bee88076a0135bc2c64fcd1365463b",
		"Light Canian combat gauntlets · Lake lizard hide\nAgainst a sword? No....but they might help against a knife.",
		"Canianische leichte Kampfhandschuhe · Seeechsenhaut\nIn ein Schwert kann man mit ihnen nicht greifen, aber vielleicht in ein Messer..."
	],
	"armor kania_high_gloves lizard_green": [
		"9c792fd14a5d392c02a3f892accd8a53a8c531ad82befcc19638feb4cc9e74e2",
		"Light Canian combat gauntlets · Forest lizard hide\nDo not try fishing in boiling water with these...you will find them good enough for combat...",
		"Canianische leichte Kampfhandschuhe · Waldechsenhaut\nAlles halten sie nicht ab, aber im Kampf bieten sie angemessenen Schutz."
	],
	"armor kania_high_gloves ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_gloves troll_black": [
		"6be8d182eeb7b0f91eb33f38f13a4d895f68ff13c42bf5c0afead00bccffb260",
		"Canian light gauntlets of black Troll hide\nIf a brazen wolf decides to have the owner of these for dinner, that will be one sorry wolf!!",
		"Canianische leichte Handschuhe aus schwarzer Trollhaut\nDie widerstehen auch dem stärksten Wolfszahn."
	],
	"armor kania_high_gloves troll_blue": [
		"7b6466bcdbf60695dcf2fc17f1721d546349aca72b23693430f093926e9ee726",
		"Canian light gauntlets of blue Troll hide\nThese provide decent hand protection.",
		"Canianische leichte Handschuhe aus blauer Trollhaut\nGuter Schutz für die Hände."
	],
	"armor kania_high_gloves troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_gloves troll_green": [
		"04ce0c20262eed76f320ca986188a3c37776211973f4b82aa8293fb369bbc386",
		"Canian light gauntlets of green Troll hide\nWill provide some additional hand protection.",
		"Canianische leichte Handschuhe aus grüner Trollhaut\nGuter zusätzlicher Schutz für die Hände."
	],
	"armor kania_high_gloves troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_helm adamantium": [
		"eb0df92ca49624f19d561b2f6605e0dc44b70ddae058891c7e82e88b25b2cae8",
		"Canian light adamantite helmet\nNot every weapon can cleave this one!",
		"Canianischer leichter Adamanthelm\nDieser Helm ist nicht von jeder Waffe zu durchdringen."
	],
	"armor kania_high_helm bronze": [
		"7c4def594a39fe7bbd2a6fa824afb132571643504ea34155ed30aea5886b81c1",
		"Canian light bronze helmet\nInexpensive, but can be broken by almost any weapon.",
		"Canianischer leichter Bronzehelm\nGünstig, bietet aber auch kaum Schutz gegen Waffen!"
	],
	"armor kania_high_helm iron": [
		"19506827987df4ffa2080cd1a7f9ff0d3d82ec10e3421fba924da9a2d524a199",
		"Canian light iron helmet\nWill protect your head from side blows, but the material is rather poor.",
		"Canianischer leichter Eisenhelm\nGuter seitlicher Schutz für den Kopf, aber das Material lässt zu wünschen übrig."
	],
	"armor kania_high_helm meteoric": [
		"1ffb343f73d0622fccf3b89874905ff62bcba4de42cbabf058d53c09aa32c413",
		"Canian light meteorite helmet\nThis helmet would only protect you from a direct blow to the face.",
		"Canianischer leichter Meteorit-Eisenhelm\nSchützt das Gesicht - aber leider auch nicht viel mehr."
	],
	"armor kania_high_helm mithrill": [
		"53fff6f391003edde11baa0de5baab135d0e1cfe748b9443907c689747f2641b",
		"Canian light mithrill helmet\nA really light - and reliable - helmet.",
		"Canianischer leichter Mithrilhelm\nEin leichter, zuverlässiger Helm."
	],
	"armor kania_high_helm steel": [
		"12271aabc46c7540fbcdd166a03cf005c4a94d88db1ea7dbdadc07d149cddc26",
		"Canian light steel helmet\nSerious protection in combat, especially for experienced warriors.",
		"Canianischer leichter Stahlhelm\nGuter Schutz im Kampf. Ideal für erfahrene Krieger."
	],
	"armor kania_high_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_leggins adamantium": [
		"683329de9a5f8603dc84fbcdb31a6eaf5a880f9a003c806e67746875843a0b22",
		"Canian light adamantite leggings\nAdamantite is expensive but reliable protection is worth the money.",
		"Canianische leichte Beinlinge aus Adamant\nAdamant ist jeden Preis wert."
	],
	"armor kania_high_leggins bronze": [
		"a68fa705f34ab855d7e95cf11be9ffe9443b4b0f5c16736081529a847d161a95",
		"Canian light bronze leggings\nThey may be called light, but bronze is still a heavy metal...",
		"Canianische leichte Beinlinge aus Bronze\nLeicht bezieht sich hierbei bestimmt nicht aufs Gewicht."
	],
	"armor kania_high_leggins iron": [
		"4bc14520235a5ecc7054dd6d7a5d314435ced25e7da7dbc6776b7c28ffc33b92",
		"Canian light iron leggings\nIron gives better protection than bronze, but you could still find something more reliable.",
		"Canianische leichte Beinlinge aus Eisen\nEisen ist besser als Bronze, aber es gibt stabileres Material."
	],
	"armor kania_high_leggins meteoric": [
		"5576e12d839283894fa637ae39c71f2a7c37942526776abc09408f7f38283e58",
		"Canian light meteorite leggings\nThese would protect from any blow - except one from the back...",
		"Canianische leichte Beinlinge aus Meteorit-Eisen\nSchützen vor jedem Angriff - es sei denn, er gilt dem Rücken."
	],
	"armor kania_high_leggins mithrill": [
		"9b3423c156fd6d7e9fab35001689d73ba0575760c68396dcd04d4503ccfe0d97",
		"Canian light mithrill leggings\nEven a Tiger would break its teeth on such leggings!",
		"Canianische leichte Beinlinge aus Mithril\nDaran würde sich sogar ein Tiger die Zähne ausbeißen!"
	],
	"armor kania_high_leggins steel": [
		"3360370ce250802cb49a08363afb06cb5916b0712020e8cb4fadcb557a8a97ce",
		"Canian light steel leggings\nSteel provides real protection, and the price is not too high either.",
		"Canianische leichte Beinlinge aus Stahl\nStahl bietet guten Schutz bei gutem Preis."
	],
	"armor kania_high_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_pants dragon_black": [
		"8072f524e02e24eed3091a80038b7b8d39be3089e78362f71da54fa58360d675",
		"Canian trousers of Blue Dragon hide\nWould resist more than just a chance arrow!",
		"Canianische Hosen aus blauer Drachenhaut\nHält einiges mehr als nur verirrte Pfeile aus!"
	],
	"armor kania_high_pants dragon_green": [
		"82b3a7fb951c6ef672613d22c893b572702c3919e9b37759fca3490d1abd82de",
		"Canian trousers of Green Dragon hide\nThese will not save you from a battle axe, but they will easily withstand lighter weapons.",
		"Canianische Hosen aus grüner Drachenhaut\nHält vielleicht keine Streitaxt auf, aber bietet guten Schutz gegen leichte Waffen."
	],
	"armor kania_high_pants dragon_red": [
		"491bd54f5ceec7dc311ea0efd344abb3031d3426a816530dae88a1a48c4c6fae",
		"Canian trousers of Red Dragon hide\nYou can fall into a fire with these!",
		"Canianische Hosen aus roter Drachenhaut\nSelbst Feuer kann dieser Hose nichts anhaben."
	],
	"armor kania_high_pants lizard_black": [
		"c00cb9984e8123e0fe571e1370e1d0859b26915c8a2b11f9b67d93d084f552de",
		"Canian thick hide trousers · Mountain lizard hide\nExpensive - but worth it!",
		"Canianische dicke Lederhose · Bergechsenhaut\nTeuer, aber den Preis wert!"
	],
	"armor kania_high_pants lizard_blue": [
		"085b1e9043b45546784fa3d2db005623337cabb9be2488648cbc3c0a8c46e389",
		"Canian thick hide trousers · Lake lizard hide\nWould resist more than just a chance arrow!",
		"Canianische dicke Lederhose · Seeechsenhaut\nHält einiges mehr als nur verirrte Pfeile aus!"
	],
	"armor kania_high_pants lizard_green": [
		"f8ea87f106a70ae9185c760cafdf18f7ed33da6c41669c55a4a56948957a8d9b",
		"Canian thick hide trousers · Forest lizard hide\nThese will not save you from a battle axe, but they will easily withstand lighter weapons.",
		"Canianische dicke Lederhose · Waldechsenhaut\nHält vielleicht keine Streitaxt auf, aber bietet guten Schutz gegen leichte Waffen."
	],
	"armor kania_high_pants ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_pants troll_black": [
		"68f06fb66e33bb34fdfa3e45e72ba22b1dff327014584639316f78091a6eafe2",
		"Canian trousers of black Troll hide\nExpensive - but worth it!",
		"Canianische Hosen aus schwarzer Trollhaut\nTeuer, aber den Preis wert!"
	],
	"armor kania_high_pants troll_blue": [
		"ccd39a3fefc60d3b4da44a0eaa62ba9ee0afe0ced9a51b47a72e2d52edb67365",
		"Canian trousers of blue Troll hide\nWith these, you can walk in the woods at night, with nary a care in the world!",
		"Canianische Hosen aus blauer Trollhaut\nMit dieser Hose kann man sich auch bei Nacht im Wald sicher fühlen."
	],
	"armor kania_high_pants troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_pants troll_green": [
		"23259a18a39667e69db03fbe3478fa15063191c7f39c8e2369b9c27eeeeff591",
		"Canian trousers of green Troll hide\nThese will protect you from the teeth of the wolf, but the fangs of the Tiger are another story....",
		"Canianische Hosen aus grüner Trollhaut\nMit Wölfen kann es diese Hose wohl aufnehmen. Kaum aber mit Tigern."
	],
	"armor kania_high_pants troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_plate adamantium": [
		"60ca514b0a331fdc3dcfb6dd6a40cc94a6fded7c12a816b29a35a7ba9a06ae64",
		"Canian light adamantite cuirass\nProvides reliable protection and also ensures freedom of movement.",
		"Canianischer l. Brustharnisch aus Adamant\nHohe Bewegungsfreiheit, aber gleichzeitig gute Panzerung."
	],
	"armor kania_high_plate bronze": [
		"1dee692ced06f68d976a28363cbcffe307eba0d718948b0189644ca9a62eabd2",
		"Canian light bronze cuirass\nProvides additional protection from sharp weapons, but try to find a better material.",
		"Canianischer l. Brustharnisch aus Bronze\nBietet einen gewissen Schutz vor scharfen Waffen, aber ein anderes Material wäre besser."
	],
	"armor kania_high_plate iron": [
		"13195eac6cfe6657903a55a9e4be6300f081a2918b065d5fb4fca38e019cc54c",
		"Canian light iron cuirass\nWould probably resist a chance arrow.",
		"Canianischer l. Brustharnisch aus Eisen\nKann vermutlich einen verirrten Pfeil abwehren."
	],
	"armor kania_high_plate meteoric": [
		"e811760fcc89a96521dc15ac3f866f85d60ce1d7639e303a37d0a7b330c26034",
		"Canian light meteorite cuirass\nMeteorite iron provides the best possible protection and also ensures freedom of movement!",
		"Canianischer l. Brustharnisch aus Meteorit-Eisen\nMeteorit-Eisen bietet bestmöglichen Schutz, lässt aber genügend Bewegungsfreiheit."
	],
	"armor kania_high_plate mithrill": [
		"afa3341034dd6c97a10814046b51c81a7ab9e9c05238f0013d97b7222c522224",
		"Canian light mithrill cuirass\nMithrill's lightness and strength ensure that this cuirass provides good protection.",
		"Canianischer l. Brustharnisch aus Mithril\nMithril ist stabil und flexibel. Genau das Richtige für einen Harnisch."
	],
	"armor kania_high_plate steel": [
		"a07dfce9e9ce9736dc339056e2d41374811d423442430547f5988c17bad458f4",
		"Canian light steel cuirass\nProvides decent protection and also ensures freedom of movement.",
		"Canianischer l. Brustharnisch aus Stahl\nHohe Bewegungsfreiheit, aber gleichzeitig eine annehmbare Panzerung."
	],
	"armor kania_high_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype dragon_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype dragon_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype dragon_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype lizard_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype lizard_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype lizard_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype troll_black": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype troll_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype troll_green": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_prototype troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_shirt dragon_black": [
		"b0df285b9faa4d96c78fd0a7a586c65d74def0517d321d4301037d9c7b3efd33",
		"Canian jerkin of Blue Dragon hide\nThis sort of armor can provide excellent protection!",
		"Canianische Weste aus blauer Drachenhaut\nDiese Art von Panzerung bietet hervorragenden Schutz."
	],
	"armor kania_high_shirt dragon_green": [
		"68c1f207d7df7faae124806356b3bc614ac455bc019cfb8d01ec792e7b9b07bc",
		"Canian jerkin of Green Dragon hide\nGreen Dragon hide is very strong!",
		"Canianische Weste aus grüner Drachenhaut\nGrüne Drachenhaut ist äußerst stabil!"
	],
	"armor kania_high_shirt dragon_red": [
		"cf4d67ad0e1f5d27485ea80f2a26b48340be21c60d2f81a0d7ea617a8fe4c60a",
		"Canian jerkin of Red Dragon hide\nWill protect you from more than arrows!",
		"Canianische Weste aus roter Drachenhaut\nWidersteht nicht nur Pfeilen."
	],
	"armor kania_high_shirt lizard_black": [
		"ceba8ca22a36b28a0f52fb58143ee1870e7fb829395acc1b1568f89f015a0adf",
		"Canian thick hide jerkin · Mountain lizard hide\nYou do not have to beware of an arrow shot from behind some tree, if you wear this!",
		"Canianischer dicker Lederwams · Bergechsenhaut\nMit dieser Weste braucht man nicht mal einen Pfeil aus dem Hinterhalt zu fürchten!"
	],
	"armor kania_high_shirt lizard_blue": [
		"04dce583d84761a2bdff0b98eef5ccde9e2d0c4f3d3aec375ac27a9590787bfa",
		"Canian thick hide jerkin · Lake lizard hide\nThis sort of armor can provide excellent protection!",
		"Canianischer dicker Lederwams · Seeechsenhaut\nDiese Art von Panzerung bietet hervorragenden Schutz."
	],
	"armor kania_high_shirt lizard_green": [
		"38f5f63ef57947740c96cfc17585dc49858d19e8e8d826bc61a9cd7e7fec260f",
		"Canian thick hide jerkin · Forest lizard hide\nForest lizard hide is not very strong!",
		"Canianischer dicker Lederwams · Waldechsenhaut\nWaldechsenhaut ist nicht besonders fest!"
	],
	"armor kania_high_shirt ogre": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_shirt troll_black": [
		"99283c10b5ef45f759df651905077c6cf74c3e425cde344e90fdbadbf8238398",
		"Canian jerkin of black Troll hide\nYou do not have to beware of an arrow shot from behind some tree, if you wear this!",
		"Canianische Weste aus schwarzer Trollhaut\nMit dieser Weste braucht man nicht mal einen Pfeil aus dem Hinterhalt zu fürchten!"
	],
	"armor kania_high_shirt troll_blue": [
		"4edebc11300c432e0a0de5e781a0be877bcb6736c6da912063c7bc8f7f956125",
		"Canian jerkin of blue Troll hide\nThis will protect you from a chance arrow from a short bow.",
		"Canianische Weste aus blauer Trollhaut\nBietet einen gewissen Schutz vor verirrten Pfeilen von Kurzbögen."
	],
	"armor kania_high_shirt troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_high_shirt troll_green": [
		"ddbbe3afed54425963a4fdcef19bc96e41a91e8121c39421a3fb636286d2ef3c",
		"Canian jerkin of green Troll hide\nMore suited to combat than the hunt!",
		"Canianische Weste aus grüner Trollhaut\nWeniger für die Jagd als für den Kampf gedacht."
	],
	"armor kania_high_shirt troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_boots adamantium": [
		"da94c06563adaf86c386aff40c6148e6b1a061c9a9623225e85d62c9f951ae5e",
		"Canian heavy army boots · Adamantite\nWith these, you could even kick an ogre in the backside.",
		"Canianische schwere Armeestiefel · Adamantit\nDamit kann man sogar einem Oger einen Tritt verpassen."
	],
	"armor kania_highest2_boots bronze": [
		"01a4918984a6e3aa979923885af3ccf561b9192425cd20b6443e4e7444a94788",
		"Canian heavy army boots · Bronze\nA waste of a good blueprint.",
		"Canianische schwere Armeestiefel · Bronze\nVerschwendung eines guten Bauplans."
	],
	"armor kania_highest2_boots iron": [
		"a53276e057df49e4fa5a64ce97721095244b25bd312adcbf721d5174d0273e91",
		"Canian heavy army boots · Iron\nThis blueprint deserved better material.",
		"Canianische schwere Armeestiefel · Eisen\nDieser Bauplan hätte besseres Material verdient."
	],
	"armor kania_highest2_boots meteoric": [
		"dfd4b04adf34d2345ab872f29d1c1d101ad89fa6821d84eaf368f6503ab82fd3",
		"Canian heavy army boots · Meteorite\nThe best metal boots.",
		"Canianische schwere Armeestiefel · Meteorit\nDie besten Stiefel aus Metall."
	],
	"armor kania_highest2_boots mithrill": [
		"3bff8cfdc8aad4013853b95808b29056c448bf825c191aae15c6d11e1107c74e",
		"Canian heavy army boots · Mithrill\nGood protection for the feet, though not cheap.",
		"Canianische schwere Armeestiefel · Mithril\nGuter Schutz für die Füße, wenn auch nicht billig."
	],
	"armor kania_highest2_boots steel": [
		"0a95fa4273a9ffa078f17831ec085c17c20c6ae4a65ab3b7e120f610030a3189",
		"Canian heavy army boots · Steel\nGood, but better can be found for this price.",
		"Canianische schwere Armeestiefel · Stahl\nGut, aber für diesen Preis gibt es Besseres."
	],
	"armor kania_highest2_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_gloves adamantium": [
		"6047c348c6458480403cb84361ba7c4472a3a7adfcd210754cf22f6b75eaea2d",
		"Canian heavy army gauntlets · Adamantite\nThese could withstand a knife stab!",
		"Canianische schwere Armeehandschuhe · Adamantit\nDenen kann sogar ein Messer nichts anhaben!"
	],
	"armor kania_highest2_gloves bronze": [
		"b009b0cb51f8d73a92061c3076a83c5041215d090e63dba20bba2391308f9255",
		"Canian heavy army gauntlets · Bronze\nThe material does not suit the blueprint.",
		"Canianische schwere Armeehandschuhe · Bronze\nDas Material passt nicht zum Bauplan."
	],
	"armor kania_highest2_gloves iron": [
		"0b1b5cc584ca59b136e0602623d5ba6f55040bf39b6d6ede5c8a9add848600f4",
		"Canian heavy army gauntlets · Iron\nThis blueprint should not have been wasted on them.",
		"Canianische schwere Armeehandschuhe · Eisen\nDafür hätte man diesen Bauplan nicht verschwenden sollen."
	],
	"armor kania_highest2_gloves meteoric": [
		"e7317c32eebe0380b5d27d3a1f7bd87f4358461c9cb7b89d50725bd7c0035363",
		"Canian heavy army gauntlets · Meteorite\nThe best metal bracers!",
		"Canianische schwere Armeehandschuhe · Meteorit\nDie besten Armschienen aus Metall!"
	],
	"armor kania_highest2_gloves mithrill": [
		"4cfafe6f025a0e80996789cbe4d63cd932b533bf82161fa7d144c481f6d6cfb0",
		"Canian heavy army gauntlets · Mithrill\nWith these, you can fight without a weapon!",
		"Canianische schwere Armeehandschuhe · Mithril\nDamit kann man auch ohne Waffe kämpfen!"
	],
	"armor kania_highest2_gloves steel": [
		"61cb1684838ccd15c5fcd694d794b5fab20014765bd3e34e0e9ba3d02d1653a5",
		"Canian heavy army gauntlets · Steel\nSerious protection for your arms!",
		"Canianische schwere Armeehandschuhe · Stahl\nErnsthafter Schutz für die Arme!"
	],
	"armor kania_highest2_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_helm adamantium": [
		"0eab0e9307d069882fcdc19d5c834bbbbd194e1a7b04571f7126cf236823d80f",
		"Canian army heavy adamantite helmet\nOnly senior officers can afford these.",
		"Canianischer schwerer Helm aus Adamant\nNur langgediente Offiziere können sich einen solchen Helm leisten."
	],
	"armor kania_highest2_helm bronze": [
		"c98c38559add5064973e4a9c92142e85300c2b6a4034590e1838f427ed500bb1",
		"Canian army heavy bronze helmet\nThese are made to order - for the very poor soldiers.",
		"Canianischer schwerer Helm aus Bronze\nEin Helm für arme Leute!"
	],
	"armor kania_highest2_helm iron": [
		"46839c404e46a181bad5a0f5c1df7a67e2b8520b9f2cf52488cfa3fe9d3ecc2d",
		"Canian army heavy iron helmet\nIssued to Canian soldiers who stand in the front line of battle.",
		"Canianischer schwerer Helm aus Eisen\nWird an jene Canianischen Soldaten ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_helm meteoric": [
		"087ab2a59069607123fd6d842306fb7851b9ff51b6f9224690f292ad2eb0d3bd",
		"Canian army heavy meteorite  helmet\nThis looks awesome indeed, as does the price!",
		"Canianischer schwerer Helm aus Meteorit-Eisen\nSieht gut aus - und kostet entsprechend viel."
	],
	"armor kania_highest2_helm mithrill": [
		"0419e5e548a447f96a66a4e5395ce560e1e8b7b21e2d65ab583762b9fbd37cd6",
		"Canian army heavy mithrill  helmet\nIssued to the best veterans of the Canian army.",
		"Canianischer schwerer Helm aus Mithril\nNur für verdiente Veteranen der Canianischen Armee."
	],
	"armor kania_highest2_helm steel": [
		"acd7781ce60a09132b5ca194f6a880aa5ca2972cbcc9b4b7349e13f92fce89a4",
		"Canian army heavy steel helmet\nIssued to Canian officers who stand in the front line of battle.",
		"Canianischer schwerer Helm aus Stahl\nWird an jene canianischen Offiziere ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_leggins adamantium": [
		"8d17481cb135bdebafaabdd179e5000d73ff7c3a05cd36f24b65894f506c1018",
		"Canian army heavy adamantite leggings\nOnly high-ranking officers order these.",
		"Canianische schwere Armee-Beinlinge aus Adamant\nNur hochrangige Offiziere können sich solche Beinlinge leisten."
	],
	"armor kania_highest2_leggins bronze": [
		"71b6b6316bd65b228510f272e5eff91fe9f1cd1bcf12aea1b322321f99a3bdbc",
		"Canian army heavy bronze leggings\nThe army does not use these any more: bronze is too heavy and soft.",
		"Canianische schwere Armee-Beinlinge aus Bronze\nWird von der Armee nicht mehr verwendet. Bronze ist zu weich und zu schwer!"
	],
	"armor kania_highest2_leggins iron": [
		"0d4e0dbec9e147c360d624e60cd31d618ee8dc8d32611f19f4a1f7f36f90e1ef",
		"Canian army heavy iron leggings\nIssued to Canian soldiers who stand in the front line of battle.",
		"Canianische schwere Armee-Beinlinge aus Eisen\nWird an jene canianischen Soldaten ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_leggins meteoric": [
		"678566cee8dcc28129cb6aa6df86c38b9c2d7489ca6a7d076de960fc31096d58",
		"Canian army heavy meteorite leggings\nThe best of Canian armor! And the price is more frightening than a Tiger...",
		"Canian. schw. Armee-Beinlinge - Meteorit-Eisen\nDas Beste, was die canianische Armee zu bieten hat. Der Preis ist fast so furchteinflößend wie ein Tiger..."
	],
	"armor kania_highest2_leggins mithrill": [
		"546494ff0c424b5d0d4307e72ff6c7223161365f1b5468c46bfbfdc68780ece7",
		"Canian army heavy mithrill leggings\nIssued only to Canian veterans.",
		"Canianische schwere Armee-Beinlinge aus Mithril\nNur für verdiente Veteranen der canianischen Armee."
	],
	"armor kania_highest2_leggins steel": [
		"7473378f959fe53aed625b8cde0d5102f27e882f9eeb6dfc417003d245d2f301",
		"Canian army heavy steel leggings\nIssued to Canian officers who stand in the front line of battle.",
		"Canianische schwere Armee-Beinlinge aus Stahl\nWird an jene canianischen Offiziere ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_pants adamantium": [
		"d103931cad688ad048ad04ec02db9baa9c74ffc71cf91734dba3a97b71d66316",
		"Canian heavy army trousers · Adamantite\nExcellent material for excellent armour!",
		"Canianische schwere Armeehose · Adamantit\nAusgezeichnetes Material für eine ausgezeichnete Rüstung!"
	],
	"armor kania_highest2_pants bronze": [
		"6a43d0031afc8c7d5f3a15a0d9340592eaabe1fa5f6d3e9c83868e5dee6e365c",
		"Canian heavy army trousers · Bronze\nMaking this armour from bronze is utter foolishness.",
		"Canianische schwere Armeehose · Bronze\nDiese Rüstung aus Bronze zu fertigen ist völlig unsinnig."
	],
	"armor kania_highest2_pants iron": [
		"a88032a9c5b8c2bf2f74e2e653e5a7ac2a65647d8c63ee45e289bc06dbf2fc94",
		"Canian heavy army trousers · Iron\nA rather poor choice of material.",
		"Canianische schwere Armeehose · Eisen\nEine eher schlechte Materialwahl."
	],
	"armor kania_highest2_pants meteoric": [
		"c6ce82b1764d8a7a6d38acfa9387521584e75e3c9d17d33b8506684a8d214bfc",
		"Canian heavy army trousers · Meteorite\nThe best metal trousers.",
		"Canianische schwere Armeehose · Meteorit\nDie beste Hose aus Metall."
	],
	"armor kania_highest2_pants mithrill": [
		"15b07fdf831034db28c1504643daf57059fa28d111a68a15b95e354d9dc59424",
		"Canian heavy army trousers · Mithrill\nMithril is light, but the armour is still heavy.",
		"Canianische schwere Armeehose · Mithril\nMithril ist leicht, doch die Rüstung bleibt schwer."
	],
	"armor kania_highest2_pants steel": [
		"78281fd2cc19729cbcd8e36a106d4f3d38af267dadc7b01b5e6ab652aec79076",
		"Canian heavy army trousers · Steel\nYou will not run far in these, but the protection is solid.",
		"Canianische schwere Armeehose · Stahl\nWeit laufen kann man darin nicht, doch der Schutz ist solide."
	],
	"armor kania_highest2_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_plate adamantium": [
		"f177d35ad7ce3313d19743b708b3dc501d75f733afaea483ceb8f828ce6ec94a",
		"Canian army heavy adamantite cuirass\nNot every Canian officer can afford this!",
		"Canianischer schw. Armee-Brusth. aus Adamant\nNicht für jeden Offizier erschwinglich!"
	],
	"armor kania_highest2_plate bronze": [
		"a16bf55a932245d4de92fa4e8835ae37934a6455fbbd39a7ba5a405e1cebe466",
		"Canian army heavy bronze cuirass\nThey do not make these for the modern army - bronze is too heavy and unreliable.",
		"Canianischer schw. Armee-Brusth. aus Bronze\nWird von der Armee selten verwendet. Bronze ist zu weich und zu schwer!"
	],
	"armor kania_highest2_plate iron": [
		"aa429f754f50cdb4e294559fc79af5f41a7a5ad4323441cb13caae61806151a2",
		"Canian army heavy iron cuirass\nIssued to Canian soldiers who stand in the front line of battle.",
		"Canianischer schw. Armee-Brustharnisch aus Eisen\nWird an jene canianischen Soldaten ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_plate meteoric": [
		"5830768a55335c6e6b28565150b198fce69392c4f177c2f18b1a90c33bc22b78",
		"Canian army heavy meteorite cuirass\nThis is not armor, it is a work of art! And the price is appropriate...",
		"Canianischer schw. Armee-Brusth. aus M.-Eisen\nDas ist kein Harnisch, das ist ein Kunstwerk! Der Preis ist leider entsprechend."
	],
	"armor kania_highest2_plate mithrill": [
		"859ec6c72eceafcc296f5556f2dbccc68b2384774d5719292c21094a32131134",
		"Canian army heavy mithrill cuirass\nIssued only to Canian veterans.",
		"Canianischer schw. Armee-Brusth. aus Mithril\nNur für verdiente Veteranen der canianischen Armee."
	],
	"armor kania_highest2_plate steel": [
		"725305ff0fa1690682be3f39a1b6c490bd804677ef6304934da8a8ff7dc510b1",
		"Canian army heavy steel cuirass\nIssued to Canian officers who stand in the front line of battle.",
		"Canianischer schw. Armee-Brustharnisch aus Stahl\nWird an jene canianischen Offiziere ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"armor kania_highest2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest2_shirt adamantium": [
		"40c652c314cb0130b4721c07d9e63f5d77f1d6b11c3c6e1f7f5dd45690170ead",
		"Heavy Canian plate shirt · Adamantite\nStrong armour... but expensive, too.",
		"Schweres kanisches Plattenhemd · Adamantit\nStarke Rüstung ... aber auch ein stolzer Preis."
	],
	"armor kania_highest2_shirt bronze": [
		"c4caefd1e5bab4dade1061956ec3d285cc489d144656b41458f31037c70e8837",
		"Heavy Canian plate shirt · Bronze\nIt would be hard to find someone willing to ruin this blueprint by making bronze armour.",
		"Schweres kanisches Plattenhemd · Bronze\nMan wird kaum jemanden finden, der diesen Bauplan für eine Bronzerüstung verschwenden würde."
	],
	"armor kania_highest2_shirt iron": [
		"79aef3bc49cb63f48d2386ecdff1f2d78f3841740f5fa0e600774c79edc3443b",
		"Heavy Canian plate shirt · Iron\nNot the best choice of material.",
		"Schweres kanisches Plattenhemd · Eisen\nNicht die beste Materialwahl."
	],
	"armor kania_highest2_shirt meteoric": [
		"a3ce85f25da219a549d2c82554f6dcd56a08c0f097c3c9365ae81dbb922d520d",
		"Heavy Canian plate shirt · Meteorite\nThe best metal chain mail, with a price to match.",
		"Schweres kanisches Plattenhemd · Meteorit\nDas beste Kettenhemd aus Metall, mit entsprechendem Preis."
	],
	"armor kania_highest2_shirt mithrill": [
		"853020c273dcffe88b4eecf5f8482d53605d55827ccfffbbf11f17a34d1e8ca1",
		"Heavy Canian plate shirt · Mithrill\nMithril makes it lighter without sacrificing excellent protection!",
		"Schweres kanisches Plattenhemd · Mithril\nMithril macht sie leichter, bei ausgezeichnetem Schutz!"
	],
	"armor kania_highest2_shirt steel": [
		"67fcde7844ac9edadd75fa8c0dffba5ada3fd9879e26f3d79923253c8d5968c3",
		"Heavy Canian plate shirt · Steel\nYou can face an arrow without fear in this.",
		"Schweres kanisches Plattenhemd · Stahl\nDamit kann man einem Pfeil furchtlos die Brust bieten."
	],
	"armor kania_highest_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_boots adamantium": [
		"bdd93e16136565ca6a4fe1a6a1035a540aff17197df66cf9df13422d3eae5028",
		"Canian combat adamantite boots\nWorth the price.",
		"Canianische Kampfstiefel aus Adamant\nAdamant ist immer seinen Preis wert."
	],
	"armor kania_highest_boots bronze": [
		"be2dcd64b39fec7e2d524a1ddce9f20a99361a17243a962b8c6b366332f5dba2",
		"Canian combat bronze boots\nNot the lightest material for footwear, and not very good protection either.",
		"Canianische Kampfstiefel aus Bronze\nSchweres Material, das kaum Schutz bietet."
	],
	"armor kania_highest_boots iron": [
		"a5d1892889ef19ebd7ac644b521136173bc1702a8b3d142a459261bd258fa462",
		"Canian combat iron boots\nThese are not as high as the light high boots, but the parts they do cover are protected better.",
		"Canianische Kampfstiefel aus Eisen\nSind nicht ganz so hoch wie die leichten Stiefel, bieten aber besseren Schutz."
	],
	"armor kania_highest_boots meteoric": [
		"4a9e2d24cad668610fe3f12e1fc248cc078b2e9b7fab4c5e7d4713b9f47b4c32",
		"Canian combat meteorite boots\nSo light and reliable - they are obviously \"out of this world!\"",
		"Canianische Kampfstiefel aus Meteorit-Eisen\nSo leicht und widerstandsfähig, dass es fast schon unheimlich ist."
	],
	"armor kania_highest_boots mithrill": [
		"4f5b73a4bad3a63b1635edd2ad041fba0e0df36bae70a5fbe5a859b5d1bcb63b",
		"Canian combat mithrill boots\nLight, comfortable, reliable - mithrill is unmistakeable!",
		"Canianische Kampfstiefel aus Mithril\nLeicht, bequem und zuverlässig - Mithril ist eben Mithril."
	],
	"armor kania_highest_boots steel": [
		"9e383d13534881535372620597dc743accc4a7f284bfb4303b93d814f44aeb31",
		"Canian combat steel boots\nDifficult to flee from wild beasts in these!",
		"Canianische Kampfstiefel aus Stahl\nAuf Schnelligkeit darf man in diesen Stiefeln nicht setzen."
	],
	"armor kania_highest_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_gloves adamantium": [
		"8dfd545df1a571871ad238eb68a891590dc3843c43ea86881a302b132ca9d30b",
		"Canian adamantite combat gauntlets\nAdamantite inlays increase the price - but the level of protection too - indeed an important factor!",
		"Canianische Kampf-Handschuhe - Adamant\nAdamant-Auflagen erhöhen den Schutz - und den Preis."
	],
	"armor kania_highest_gloves bronze": [
		"44578bcd184b1bd24c6424ec39ff5327d057ad1bf45c54f9cd949ff31dabc9cd",
		"Canian bronze combat gauntlets\nUncomfortable and not too strong. Only people with few resources would buy these.",
		"Canianische Kampf-Handschuhe aus Bronze\nUnbequem und nicht gerade stabil. Handschuhe für die, denen wenig Geld zur Verfügung steht."
	],
	"armor kania_highest_gloves iron": [
		"b27099e0cead5e5538268e12a4a1d00cb527bf8cb25a3b42bfc6ac7e0438da59",
		"Canian iron combat gauntlets\nCheap - and not great.",
		"Canianische Kampf-Handschuhe aus Eisen\nNicht gerade gut - aber billig!"
	],
	"armor kania_highest_gloves meteoric": [
		"25081942ffe6e42cb1958125a7bda0aea2f3eda4b88074b1a59acac843131c28",
		"Canian meteorite combat gauntlets\nThere is simply no way to pierce forged meteorite iron!",
		"Canianische Kampf-Handsch. - Meteorit-Eisen\nKeine Waffe kann es mit geschmiedetem Meteorit-Eisen aufnehmen."
	],
	"armor kania_highest_gloves mithrill": [
		"46cdf1c282634331bd32800a6da2084d22ddbea0ea49097ff61d8f80c5a58f5e",
		"Canian mithrill combat gauntlets\nNot many weapons could pierce these.",
		"Canianische Kampf-Handschuhe aus Mithril\nDiese Handschuhe widerstehen fast jeder Waffe."
	],
	"armor kania_highest_gloves steel": [
		"4c66d7203b4fa0654edd6753ada0bb66bc43eeac708238fdb89d5384b5776d00",
		"Canian steel combat gauntlets\nNot bad, but do not rely on them too much in serious combat.",
		"Canianische Kampf-Handschuhe aus Stahl\nIm offenen Kampf sollte man sich nicht auf diese Handschuhe verlassen."
	],
	"armor kania_highest_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_helm adamantium": [
		"a2da330e9567b77eae72b3c4478d3b1f5896ff98cfb05eed6f92051594cc3b48",
		"Canian adamantite winged helmet\nVery expensive, but just as reliable!",
		"Canianischer Flügelhelm aus Adamant\nSehr teuer, aber ebenso zuverlässig!"
	],
	"armor kania_highest_helm bronze": [
		"e32707b8fb35f6a31fcea1e96855cfc2415ed8a6a6a459b3722e6b19856bd0c5",
		"Canian bronze winged helmet\nIt is not so much protection as moral advantage: it looks so mean...",
		"Canianischer Flügelhelm aus Bronze\nBietet kaum Schutz, sieht aber böse aus und macht großen Eindruck!"
	],
	"armor kania_highest_helm iron": [
		"5837686b10ca0eef5a7d19b076791f0bc80b2914b3e6469c89222ffb54f4bd36",
		"Canian iron winged helmet\nStronger than bronze, but you could find a better material still.",
		"Canianischer Flügelhelm aus Eisen\nBesser als Bronze, aber trotzdem alles andere als perfekt."
	],
	"armor kania_highest_helm meteoric": [
		"408971b2b7dde3ea3c28e878049cd3c38631942917d6715f83fb9fb0506af702",
		"Canian meteorite winged helmet\nNo cutting off of wings with this one!",
		"Canianischer Flügelhelm aus Meteorit-Eisen\nSchwingen, die niemals brechen!"
	],
	"armor kania_highest_helm mithrill": [
		"dc8c0f99d410b548fef3f253dbbc5afc5f6733309af8f287c8b63a375e4b42fa",
		"Canian mithrill winged helmet\nYou could use this as a target for the village bowmen's archery training without fear of damage.",
		"Canianischer Flügelhelm aus Mithril\nAuf diesen Helm kann man gefahrlos eine Zielscheibe malen - der Träger bleibt garantiert unverletzt."
	],
	"armor kania_highest_helm steel": [
		"936c4f81f4fa1502d821329c3b86173b6492349ea4335df8e9af2d2192caabc4",
		"Canian steel winged helmet\nThis will not only instill fear into the enemy, it will also provide excellent head protection.",
		"Canianischer Flügelhelm aus Stahl\nSchützt den Kopf und sieht beeindruckend aus."
	],
	"armor kania_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_leggins adamantium": [
		"aecdbf80746f0b7822f7a7bec1945c3962a1b8ac65ae453f7c0da8d3cf078903",
		"Canian heavy adamantite leggings\nA sensible enemy would think twice before he attacked a person who was wearing these.",
		"Canianische schwere Beinlinge aus Adamant\nEin Angreifer sollte sich gut überlegen, was er tut."
	],
	"armor kania_highest_leggins bronze": [
		"e586067436a430d7c82afad70641923bd4055ea7225190dc273bb36f4c6859f7",
		"Canian heavy bronze leggings\nNot the most sensible choice of material.",
		"Canianische schwere Beinlinge aus Bronze\nNicht gerade das beste Material."
	],
	"armor kania_highest_leggins iron": [
		"8597e9c1264c6d014e599df9d9e401e51dac934ce97cb4b8ff1418f613edbb6e",
		"Canian heavy iron leggings\nCould you try to find something better?",
		"Canianische schwere Beinlinge aus Eisen\nEs gibt Besseres!"
	],
	"armor kania_highest_leggins meteoric": [
		"0649ad171ddca67a515e287afeb3317b27e2db4abd8b9563459b6f2324382491",
		"Canian heavy meteorite leggings\nNo way to dance in these - but that's not what their for, is it?",
		"Canianische schwere Beinlinge aus Meteorit-Eisen\nNicht gerade die richtigen Beinlinge zum Tanzen - aber wer will das schon?!"
	],
	"armor kania_highest_leggins mithrill": [
		"990571566d2326dee607090b20d54846841d7e589c4b103025e4c0f955f08b80",
		"Canian heavy mithrill leggings\nIt would be silly to economise on armor which could save your life.",
		"Canianische schwere Beinlinge aus Mithril\nAn der Rüstung sollte man besser nicht sparen!"
	],
	"armor kania_highest_leggins steel": [
		"202f0ecc126fcd6570cf90fefcb4e2b9fd08acf87e489f6eb3b88b3462aec549",
		"Canian heavy steel leggings\nThat is real protection, and the price is reasonable too.",
		"Canianische schwere Beinlinge aus Stahl\nSie bieten guten Schutz zu einem guten Preis."
	],
	"armor kania_highest_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_pants adamantium": [
		"70de8feb756ca704db4c3b5b37983f3c598145c579014ae235f11ade0bdb94fb",
		"Canian adamantite chainmail trousers\nSuch lightness and  reliability are certainly worth the price!",
		"Canianische Kettenhosen aus Adamant\nGeringes Gewicht und hohe Stabilität haben nun mal ihren Preis."
	],
	"armor kania_highest_pants bronze": [
		"3511078c549caef614cfc1cf93975e8a4f3bd7505ea036a7eae0b4915cc34865",
		"Canian bronze chainmail trousers\nBronze is heavy anyway, and here we have the thick weave...",
		"Canianische Kettenhosen aus Bronze\nBronze ist ohnehin schon schwer, aber doppelte Lagen..."
	],
	"armor kania_highest_pants iron": [
		"aca4be0132be2a1a1924d8c9ffbe59edc25063011ba1291300b80b8c78a94a2d",
		"Canian iron chainmail trousers\nNot the worst possible material for this armor.",
		"Canianische Kettenhosen aus Eisen\nNicht das schlechteste Material für Panzerung."
	],
	"armor kania_highest_pants meteoric": [
		"ff794dac4506bb0a4a64a770dba84963f445c63d71e020108c5a61c7bfa39124",
		"Canian meteorite chainmail trousers\nThe material speaks for itself.",
		"Canianische Meteorit-Kettenhosen\nDas verwendete Material sagt eigentlich schon alles."
	],
	"armor kania_highest_pants mithrill": [
		"96d3280bcca987302ceb360adbb37d4951e580211a76aaceff76561e531a6cf4",
		"Canian mithrill chainmail trousers\nSuch trousers are very good in combat, and they are not too expensive.",
		"Canianische Kettenhosen aus Mithril\nIdeal für den Kampf - und gar nicht mal so teuer."
	],
	"armor kania_highest_pants steel": [
		"45f28d7ea9b211a97a463487da4bc9b10db4996d0af99d23017a27104e33e91c",
		"Canian steel chainmail trousers\nThese provide additional leg protection due to their thicker weave.",
		"Canianische Kettenhosen aus Stahl\nBesonders guter Schutz für die Beine durch dickes Material."
	],
	"armor kania_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_plate adamantium": [
		"a33e91336bf795bede0a197ada9eb285c4a59510356d038875944a75c76cbf88",
		"Canian heavy adamantite cuirass\nIf your enemy is armed with anything less than steel, you may simply ignore him.",
		"Canianischer schw. Brustharnisch aus Adamant\nWenn der Gegner keine Waffen aus Stahl hat, kann man ihn mit diesem Harnisch einfach ignorieren."
	],
	"armor kania_highest_plate bronze": [
		"d30c40ecc7cf6d22c83bcb5e3efd3e75b35299fe703efe65be0163e956aa955e",
		"Canian heavy bronze cuirass\nAdditional inlays make the cuirass even heavier…",
		"Canianischer schw. Brustharnisch aus Bronze\nZusätzliche Auflagen sorgen für zusätzliches Gewicht."
	],
	"armor kania_highest_plate iron": [
		"c259ead7e5c26ff3b279d1925fcff980aed3d088f63e623c0420113e12b35b92",
		"Canian heavy iron cuirass\nForged iron is better than bronze but worse than common steel...",
		"Canianischer schw. Brustharnisch aus Eisen\nGeschmiedetes Eisen ist besser als Bronze, aber schlechter als einfacher Stahl."
	],
	"armor kania_highest_plate meteoric": [
		"bd9da8c7f4f2941d67ec72c5f75e3fb84da0920879aabea0892dc7d28186706e",
		"Canian heavy meteorite cuirass\nIf you wear these, you can forget about the need to protect yourself during combat!",
		"Canianischer schw. Brusth. aus Meteorit-Eisen\nMit diesem Brustharnisch muss man kaum etwas fürchten!"
	],
	"armor kania_highest_plate mithrill": [
		"ce4071a1fd2c308f2ba68186dc6de1ff257942815807c7a0f0991035b07ab927",
		"Canian heavy mithrill cuirass\nOne of the best to wear in combat.",
		"Canianischer schw. Brustharnisch aus Mithril\nPerfekt für den Kampf!"
	],
	"armor kania_highest_plate steel": [
		"658f289ffd78b0cbb9ff4787167b0feeba89f76e7e8a795d41b2ab51d76c4634",
		"Canian heavy steel cuirass\nWearing this, you could deal with brigands easily.",
		"Canianischer schw. Brustharnisch aus Stahl\nDamit kann man gegen Banditen antreten oder einen Söldner zur Vernunft bringen."
	],
	"armor kania_highest_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_highest_shirt adamantium": [
		"f41aa8665bd0036974491113ad936b43b82d742a703e2fb826b68a173c8f5660",
		"Canian adamantite chainmail shirt\nYou can rely on this in serious combat.",
		"Canianisches Kettenhemd aus Adamant\nSehr zuverlässig auch in schweren Kämpfen."
	],
	"armor kania_highest_shirt bronze": [
		"3aeec4ead6a47c411bbc19970708657df1ecbe3f961907f57091a1fd0b2ad22b",
		"Canian bronze chainmail shirt\nA bit too heavy, and the additional protection is no real compensation for the extra weight.",
		"Canianisches Kettenhemd aus Bronze\nDer Schutz rechtfertigt auf keinen Fall das zusätzliche Gewicht."
	],
	"armor kania_highest_shirt iron": [
		"41e46ce6fb4cf0919ead23c553fb2a9f0ef3dca2b518a56d2639b3b208fa1519",
		"Canian iron chainmail shirt\nThe chainmail weave provides extra toughness, but you could find a better material.",
		"Canianisches Kettenhemd aus Eisen\nDie Verarbeitung ist gut, aber das Material könnte besser sein."
	],
	"armor kania_highest_shirt meteoric": [
		"7ecde756855f6bb86dd16335db09631c7c9d375aeaf32dbf292d56f33508edb4",
		"Canian meteorite chainmail shirt\nYou would be hard pressed to harm anyone who wears this shirt!",
		"Canianisches Kettenhemd aus Meteorit-Eisen\nDenen, die so was tragen, ist kaum etwas anzuhaben."
	],
	"armor kania_highest_shirt mithrill": [
		"532033eebf23c3343bc33fc1a9461d332f3e951e94d9d3a9f384a58a257617be",
		"Canian mithrill chainmail shirt\nEven the thick weave does not make this too heavy.",
		"Canianisches Kettenhemd aus Mithril\nSelbst die dichte, dicke Verarbeitung bringt nicht zu viel Gewicht."
	],
	"armor kania_highest_shirt steel": [
		"acf2a5ae0706dc5583a61a6c1a269439fddb346734c08c2f482d16ad26f28afa",
		"Canian steel chainmail shirt\nThis would withstand an arrow shot from an average crossbow.",
		"Canianisches Kettenhemd aus Stahl\nWidersteht ohne weiteres dem Schuss einer Armbrust."
	],
	"armor kania_low_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_boots cotton": [
		"e9bef37cef25e9a9bb8063d108f76359677b89f6af5a614a7537ac0138ac2dab",
		"Canian cotton boots for farmers\nTypical footwear for farmers.",
		"Canianische Bauernstiefel aus Baumwolle\nTypische Stiefel für Feldarbeiter."
	],
	"armor kania_low_boots silk_blue": [
		"f42a20a3297925c98b5f13dff319b4881aa59596b534f146611dc0bf1e116005",
		"Canian silk boots for farmers\nThey look good and are strong enough.",
		"Canianische Bauernstiefel aus Seide\nWiderstandsfähig und hübsch anzusehen."
	],
	"armor kania_low_boots silk_red": [
		"686789433b171d8d12867bbaf89a419250f4a513dd725527ded02b53fbcaf449",
		"Canian woollen boots for farmers\nDo not rely too much on these for protection.",
		"Canianische Bauernstiefel aus Wolle\nDiese Stiefel bieten keinen optimalen Schutz."
	],
	"armor kania_low_boots wool": [
		"f13170ee7c2b60d56599457b4ce56976542c81f2a13ea434d1f795b2eb357c1e",
		"Canian rough fabric boots for farmers\nWell, they are at least waterproof.",
		"Canianische Bauernstiefel aus grobem Stoff\nImmerhin wasserdicht!"
	],
	"armor kania_low_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_gloves cotton": [
		"fe4d885faf4a02dacddefcacfd0c776a043b86195b3f54c6705106ac9b52b250",
		"Canian cotton gauntlets for farmers\nThe quality is in line with the price.",
		"Canianische Bauernhandschuhe aus Baumwolle\nDie Qualität entspricht dem Preis."
	],
	"armor kania_low_gloves silk_blue": [
		"5c36c867506a8566709cd9c831b1d93ce33d42a6b6ed0c1bb7475af58a26d6a9",
		"Canian silk gauntlets for farmers\nNice looking, and good enough for a friendly fight.",
		"Canianische Bauernhandschuhe aus Seide\nSehen gut aus und sind ausreichend für eine kleine Rangelei."
	],
	"armor kania_low_gloves silk_red": [
		"b8c85b65e3a4797deddf7fe0403d4f628196eb360e0463ae1d2485ae39207ace",
		"Canian woollen gauntlets for farmers\nGood enough for a fight - providing of course it is a fist fight at a village spring fair.",
		"Canianische Bauernhandschuhe aus Wolle\nSind ausreichend für eine Schlägerei auf dem Dorffest."
	],
	"armor kania_low_gloves wool": [
		"88f32829624e6c87c26785b16ef848767f0c18a8e9eb5dc98d68b9b1f457bea5",
		"Canian rough fabric gauntlets for farmers\nRough fabric cannot provide any serious protection.",
		"Canianische Bauernhandschuhe aus grobem Stoff\nGrober Stoff bietet kaum Schutz!"
	],
	"armor kania_low_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_helm tanned_thin": [
		"47386ceceb2d52e6dc0bd5551d964dcc9e8d445ba4e3ca935b0c509964e51968",
		"Canian hard hat for farmers\nThis one will protect you from the cold and from sun stroke.",
		"Canianischer Bauernhut aus derbem Leder\nSchützt vor Sonne und Kälte!"
	],
	"armor kania_low_helm thick": [
		"989056c0aa12b0ba879375215cf32aa08cb19a3725b2c0fb076a046fbe23e308",
		"Canian farmer's hat · Tough leather\nThis would protect you from the heat of the sun, but not the heat of battle!",
		"Canianischer Bauernhut · Starkes Leder\nGut gegen die Sonne - aber kaum gegen Feinde."
	],
	"armor kania_low_helm thin": [
		"453d6e31f344cc166c1901a52cb28395a720c9d72c45d6ce66a5f1433a4543dd",
		"Canian thin leather hat for farmers\nA poor man cannot afford anything better...",
		"Canianischer Bauernhut aus dünnem Leder\nEin Hut für arme Leute."
	],
	"armor kania_low_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_leggins tanned_thin": [
		"e1ff09174e661da53a5cb8782f04b073411c9ec33625a2c72f55d8c0795c83e8",
		"Canian light top trousers of hard leather\nThese would protect you, and not only from thorns.",
		"Canianische leichte Überhosen aus derbem Leder\nSchützen gegen mehr als Dornen!"
	],
	"armor kania_low_leggins thick": [
		"dcea25816eda78a955c4e302b5505c12db4b03c849389d9278fb7c6db0d68548",
		"Canian light top trousers · Tough leather\nThey are warm and comfortable - what else could a farmer need?",
		"Canianische leichte Überhosen · Starkes Leder\nWarm und bequem - was gibt es Besseres für die Feldarbeit?"
	],
	"armor kania_low_leggins thin": [
		"8cad8ac81dc4eeca0dd5418fcc6abfaee78ede4e85eb5125bbdb9c2ecd90ac74",
		"Canian light top trousers of thin leather\nThey are warm... To a poor man, that's something.",
		"Canianische leichte Überhosen aus dünnem Leder\nSie sind warm - für arme Leute reicht das."
	],
	"armor kania_low_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_pants cotton": [
		"3ee431d2d12546ad80da4e51f0cebcd67cc6f83834ad915d6c1a65f111972ec0",
		"Canian cotton trousers for farmers\nThe quality is in line with the price. But they look decent.",
		"Canianische Bauernhosen aus Baumwolle\nDie Qualität entspricht dem Preis. Immerhin sehen sie gut aus."
	],
	"armor kania_low_pants silk_blue": [
		"302fb678a36beae8e182aa93d940e1e1fa207b747edbf238636ddd8e9af6e00b",
		"Canian silk trousers for farmers\nSunday clothes, but strong enough.",
		"Canianische Bauernhosen aus Seide\nFesttagskleidung. Aber trotzdem widerstandsfähig."
	],
	"armor kania_low_pants silk_red": [
		"694ce9133ce93a0d215e1617a4ead3a87ec11230138665367da829763d4043af",
		"Canian woollen trousers for farmers\nThese will protect you from the teeth of the wolf, but the fangs of the Tiger are another story....",
		"Canianische Bauernhosen aus Wolle\nMit Wölfen kann es diese Hose wohl aufnehmen. Kaum aber mit Tigern."
	],
	"armor kania_low_pants wool": [
		"65bac4377c2c41c96e7893a5fdba627b82e024497ac94329619f865d6500a8f9",
		"Canian rough fabric trousers for farmers\nOnly suitable for working the land.",
		"Canianische Bauernhosen aus grobem Stoff\nNur für die Feldarbeit!"
	],
	"armor kania_low_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_plate tanned_thin": [
		"02fe79fd341708318ea1a7575a0d84495b3bdc22c5859a7e88f1065543dfa3e4",
		"Canian light coat of hard leather\nNot very good protection from weapons, but this will cover your chainmail shirt - if you have one, that is.",
		"Canianischer leichter Mantel aus derbem Leder\nSchützt kaum gegen Waffen, bedeckt aber das Kettenhemd. Wenn man denn eins hat..."
	],
	"armor kania_low_plate thick": [
		"d93853e3c4a245c9981906abda67b8263d1be2bad429c6c38f9b5f055a5f1ca8",
		"Canian light coat · Tough leather\nA very undistinguished coat - one could do much better that that.",
		"Canianischer leichter Mantel · Starkes Leder\nKein guter Mantel - es gibt Besseres!"
	],
	"armor kania_low_plate thin": [
		"56b7de233a011480f892141884ab9ae78676e5985c69d23c34aa326055c22390",
		"Canian light coat of thin leather\nWould hardly protect you from the rain...",
		"Canianischer leichter Mantel aus dünnem Leder\nSchützt nicht einmal vor Regen."
	],
	"armor kania_low_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_prototype cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_prototype silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_prototype silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_prototype wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_low_shirt cotton": [
		"7ba6007db315d4fdd642b8a2731588f015e0d82be86eae8a360546f5e68157c0",
		"Canian cotton shirt for farmers\nThe only difference with rough fabric one is, it looks a bit better.",
		"Canianisches Bauernhemd aus Baumwolle\nSieht besser aus als grober Stoff."
	],
	"armor kania_low_shirt silk_blue": [
		"b831135148e69c318e68aecfa52514c6da4ad7423923b05d074dbbc9d17d9e66",
		"Canian silk shirt for farmers\nA farmer wearing such a shirt would look good at a village festival.",
		"Canianisches Bauernhemd aus Seide\nIdeal für Bauern auf dem Dorffest!"
	],
	"armor kania_low_shirt silk_red": [
		"39b86f0d30827aa5b3cfbbbbddaaa59ab7284ce9315c2d404d57e71e26182eb5",
		"Canian woollen shirt for farmers\nGood enough for farming, but hardly for fighting.",
		"Canianisches Bauernhemd aus Wolle\nGut für die Feldarbeit - aber kaum für den Kampf."
	],
	"armor kania_low_shirt wool": [
		"e28b439969af8287e8704d5c8000488f0f611524a5915a64a55506d8b1e54687",
		"Canian rough fabric shirt for farmers\nPeople who wear such shirts do not think of battles.",
		"Canianisches Bauernhemd aus grobem Stoff\nEin Hemd für Menschen, die keine Feinde haben."
	],
	"armor kania_medium_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_boots cotton": [
		"c7994786ab6e12089717282bffeb3c00859171278a2b6bff7c7f14572fcbac99",
		"Canian cotton hunting boots\nThey look good enough - before you try them out on your first expedition.",
		"Canianische Jagdstiefel aus Baumwolle\nSie sehen gut aus - bevor man das erste Mal in der Wildnis war."
	],
	"armor kania_medium_boots silk_blue": [
		"4f72af315aa87142a1ff7409bf8008fd0a1e49ecd140af31112acbe4d1c36943",
		"Canian silk hunting boots\nGood footwear for hunting, and respectable enough for the village fair.",
		"Canianische Jagdstiefel aus Seide\nGut für die Jagd. Kann man aber auch in der Stadt tragen."
	],
	"armor kania_medium_boots silk_red": [
		"c7d6d280a7a10c946b63b477bb0e67455348d224f4e948a722f44d5b2450893f",
		"Canian woollen hunting boots\nGood footwear for hunting.",
		"Canianische Jagdstiefel aus Wolle\nGut für die Jagd."
	],
	"armor kania_medium_boots wool": [
		"df4b7a7c3b1c73201c22533bef0d309989e105a656e5e4f85f71c5038b9176a8",
		"Canian hunting boots of rough fabric\nOnly the poorest hunter would wear these...",
		"Canianische Jagdstiefel aus grobem Stoff\nNur arme Jäger tragen solche Stiefel."
	],
	"armor kania_medium_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_gloves cotton": [
		"cdd5f1f3383a015207d7020e313aabb2ab02a2ecaeeff7617dac42a7fcde4919",
		"Canian cotton hunting gauntlets\nNot very much different from the ones for farmers.",
		"Canianische Jagdhandschuhe aus Baumwolle\nKaum anders als die Bauernhandschuhe."
	],
	"armor kania_medium_gloves silk_blue": [
		"cfddec454fa1811edb6086b3a7da420fd6aa62fb23d9b0f908780d6c24264e63",
		"Canian silk hunting gauntlets\nStrong and pretty. Decent protection for a modest price.",
		"Canianische Jagdhandschuhe aus Seide\nWiderstandsfähig und elegant. Annehmbarer Schutz zu einem guten Preis!"
	],
	"armor kania_medium_gloves silk_red": [
		"366b72d763083d3a2516fdd5fca8ba3482b91cbdf2f736c11acca1dc7b0329f4",
		"Canian woollen hunting gauntlets\nThese may save you from the bite of a wolf.",
		"Canianische Jagdhandschuhe aus Wolle\nMit diesen Handschuhen kann man sogar einem Wolf entgegentreten."
	],
	"armor kania_medium_gloves wool": [
		"916c45cbf403c3edae8c9c6186d048d0c7bfdcc8ba92cdd06ff2541fdf8baf57",
		"Canian hunting gauntlets of rough fabric\nA rag is a rag.",
		"Canianische Jagdhandschuhe aus grobem Stoff\nFetzen bleibt Fetzen!"
	],
	"armor kania_medium_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_helm cotton": [
		"1cba3fd232df94380f56aa9ddbdc7478dfe40b001235d0a9a60a3f2f270121c3",
		"Canian cotton hunting hat\nYou could find better material than that.",
		"Canianischer Jagdhut aus Baumwolle\nEs gibt besseres Material."
	],
	"armor kania_medium_helm silk_blue": [
		"1170ad09fc53689fd96bee58895fca6db674bfbfba398d1f89c36d34f1b36a56",
		"Canian silk hunting hat\nThe girls would just love it - and it is excellent for travelling in the woods too.",
		"Canianischer Jagdhut aus Seide\nIdeal für eine Reise durch den Wald - und sieht auch nicht so schlecht aus."
	],
	"armor kania_medium_helm silk_red": [
		"1313d243e2c389fb08b3ff634cc3773c330a4eaae072b385e37da6ee5ce06a3c",
		"Canian woollen hunting hat\nA feather in your cap is guaranteed - in this hat it is a permanent fixture!",
		"Canianischer Jagdhut aus Wolle\nImmerhin ist die Feder angenäht."
	],
	"armor kania_medium_helm wool": [
		"a801ed9af98ceba9b8f30097d4d81eceee9106fdf4c804d6cd660206c59d3d93",
		"Canian hunting hat of rough fabric\nThis would tear at the first contact with rough scrub - it wouldn't be a great loss either!",
		"Canianischer Jagdhut aus grobem Stoff\nNicht gerade widerstandsfähig, aber wenn er kaputtgeht, ist es wenigstens kein Verlust."
	],
	"armor kania_medium_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_leggins cotton": [
		"e4aa2830baed10aa40dc7cd6b64c80481d0763131c5656edd4f007e270a6171d",
		"Canian cotton top hunting trousers\nThese look good enough, and the price is decent.",
		"Canianische Jagd-Überhosen aus Baumwolle\nSieht gut aus und ist preiswert!"
	],
	"armor kania_medium_leggins silk_blue": [
		"e6eff46f92638ea50ceb66aad7f712548bb92f06d6441c2a49cee56106c342c3",
		"Canian silk top hunting trousers\nThese would look good even after a very long trip!",
		"Canianische Jagd-Überhosen aus Seide\nÜbersteht auch ohne weiteres eine lange Reise."
	],
	"armor kania_medium_leggins silk_red": [
		"8817203284d246e72296c7d6a53c83f754903313d7b1aa3a7f4353e997205023",
		"Canian woollen top hunting trousers\nYou will not freeze in these!",
		"Canianische Jagd-Überhosen aus Wolle\nMit der friert man bestimmt nicht."
	],
	"armor kania_medium_leggins wool": [
		"ae0fcdf43e15bb6505e3509130d0166a69dbe95613efb2334837ef2b28d81959",
		"Canian top hunting trousers of rough fabric\nAlas, not too strong, alas...",
		"Canianische Jagd-Überhosen aus grobem Stoff\nNicht besonders gutes Material…"
	],
	"armor kania_medium_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_pants cotton": [
		"94c7d46466afc4ff5a602f58076c5044d666461afd20360dd670262cb3d962d2",
		"Canian cotton hunting trousers\nSpecially designed to make you comfortable during long hikes.",
		"Canianische Jagdhosen aus Baumwolle\nSpeziell für längere Wanderungen gedacht."
	],
	"armor kania_medium_pants silk_blue": [
		"1fe69f7f7a4c5a6409be7b27f7a6aafbc47fc456e8bb30882d3ea6a46e399539",
		"Canian silk hunting trousers\nWill not save you in battle, but indispensable for hunting.",
		"Canianische Jagdhosen aus Seide\nNicht für den Kampf geeignet - aber unersetzlich bei der Jagd!"
	],
	"armor kania_medium_pants silk_red": [
		"24b1a5c23b26c74fefcca9a2129179a6aae0c9f517ee42ac569fe981f1667052",
		"Canian woollen hunting trousers\nThey are strong and comfortable - what more do you want?",
		"Canianische Jagdhosen aus Wolle\nWiderstandsfähig und bequem - was will man mehr?!"
	],
	"armor kania_medium_pants wool": [
		"b78dae0d1f42dd446beab4999151299eeaaded1e6eeebdba5f435cf08ba5ccaa",
		"Canian hunting trousers of rough fabric\nThey would only last for a few days, but for that sort of price ....probably the best you will find.",
		"Canianische Jagdhosen aus grobem Stoff\nHalten meist nur wenige Tage, aber bei dem Preis kann man nicht mehr erwarten."
	],
	"armor kania_medium_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_plate cotton": [
		"ada533d1d6412360cfae0f81c3e1d4c8de493e0ef88342e56d93827e2eefab35",
		"Canian cotton hunting jerkin\nThe tailor did his best to make this cheap material look good.",
		"Canianische Jagdweste aus Baumwolle\nDer Schneider hat sein Bestes gegeben: Für eine billige Weste sieht sie nicht schlecht aus."
	],
	"armor kania_medium_plate silk_blue": [
		"9fe7904c936823cc07e5c2a9f372abf85fd0e74436b4e6abe301027e6be1ffe7",
		"Canian silk hunting jerkin\nOnly lucky hunters wear these!",
		"Canianische Jagdweste aus Seide\nNur besonders wohlhabende Jäger können sich so etwas leisten!"
	],
	"armor kania_medium_plate silk_red": [
		"82d89cbb11dccc2f004783bdf996cb5b3831f3ae9315e2c523504d2e451556ca",
		"Canian woollen hunting jerkin\nNot every wolf could bite through this... but look for better protection for real combat.",
		"Canianische Jagdweste aus Wolle\nWidersteht ohne weiteres Wölfen - aber leider kaum einem Messer."
	],
	"armor kania_medium_plate wool": [
		"e96bc844ac0f52ca1f7807ed34732afd4406a0765a0be6239ad8817653559ac6",
		"Canian hunting jerkin of rough fabric\nSuch a good blueprint - and such poor material.",
		"Canianische Jagdweste aus grobem Stoff\nGuter Schnitt, schlechtes Material."
	],
	"armor kania_medium_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_prototype cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_prototype silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_prototype silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_prototype wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_medium_shirt cotton": [
		"37c0f1d8adb614463798b1476fa588312ea3c585d90d824f27f157819b73bedd",
		"Canian cotton hunting jerkin\nLong sleeves provide better protection for your arms, but you should try a better material.",
		"Canianischer Jagdwams aus Baumwolle\nDie langen Ärmel bieten guten Schutz. Aber das Material könnte besser sein."
	],
	"armor kania_medium_shirt silk_blue": [
		"c959c1a850310dd3e4bbcd288a147b1d0e0d3b93ea7bb19c2a4df929d0cc0bb4",
		"Canian silk hunting jerkin\nA lucky hunter could afford this....",
		"Canianischer Jagdwams aus Seide\nNur wohlhabende Jäger können sich so etwas leisten!"
	],
	"armor kania_medium_shirt silk_red": [
		"b445b040f4a7268ebebc753150b0e60374d01edd3cc2940a039ace2a973d3dc9",
		"Canian woollen hunting jerkin\nThis is good for travelling in the woods.",
		"Canianischer Jagdwams aus Wolle\nIdeal für Reisen durch den Wald."
	],
	"armor kania_medium_shirt wool": [
		"d7cabd54cf9d9776093e5300f1702c8a7c299c0d5e976d8df5c84f2043a2d84a",
		"Canian hunting jerkin of rough fabric\nRough fabric is not the best protection. Even the long sleeves are no compensation.",
		"Canianischer Jagdwams aus grobem Stoff\nDer grobe Stoff bietet kaum Schutz. Da können auch die langen Ärmel nichts dran ändern!"
	],
	"armor kania_special_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins meteoric": [
		"bdf2b5e0901458fc0e1bcf1752e134e6bb194a8c4a2459b410d933db7b995a01",
		"Leggings worn by warriors of the Skull army.\nLeggings worn by the most elite unit of the Hadagan army.",
		"Beinschienen der Krieger der Totenkopfarmee.\nBeinschienen der Elitetruppe des hadaganischen Heeres."
	],
	"armor kania_special_highest_leggins mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_leggins steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate meteoric": [
		"b0c30f9c8f32b5074751b40492e6868287d4d24890b38741ca797408634c5ccf",
		"Cuirass worn by warriors of the Skull army.\nWarriors wearing these cuirasses can spread panic among their enemies by their appearance alone.",
		"Brustpanzer der Krieger der Totenkopfarmee.\nKrieger in diesen Brustpanzern können allein durch ihren Anblick Panik unter den Feinden verbreiten."
	],
	"armor kania_special_highest_plate mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_highest_plate steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_helm wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_leggins wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate cotton": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate silk_blue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate silk_red": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor kania_special_medium_plate wool": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_boots steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_gloves steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm iron": [
		"fce8654be1855f11fa60ae752dae518a8bb1b6b0562faa9fcd178a22ee8a864d",
		"Ancient helmet\nRusty, but still better than leather!",
		"Antiker Helm\nRostig, aber immer noch besser als Leder!"
	],
	"armor uniquegipathadagan_helm meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_helm steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_leggins steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_pants steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate adamantium": [
		"bb0ee4e631234daf352ba9956e59b58d2eecfde90c7e5ea71ff3317d99df8410",
		"Dead man's cuirass\nThis cuirass could frighten even a zombie!",
		"Brustpanzer des Toten\nDieser Brustpanzer könnte sogar einen Zombie erschrecken!"
	],
	"armor uniquegipathadagan_plate bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_plate steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquegipathadagan_shirt steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_helm tiger_hide": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_helm tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_helm tiger_hide_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_leggins steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniquehadagan_plate steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_boots steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_gloves steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_helm steel": [
		"1af3d99342bfce71fa74b4afebf21e9a8fad33471c36522abd117a8c682a29da",
		"The family helmet of Knight Brissen\nNo one could make a blueprint of this helmet - the craftsmanship is exquisite!",
		"Ritter Brissens Familienhelm\nEs ist sinnlos, diesen Helm nachmachen zu wollen. Es ist ein einzigartiges Meisterwerk!"
	],
	"armor uniqueingos_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_leggins steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_pants steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_plate steel": [
		"626786f9cf77b05ed1654642e86ddf90b00c16c99b1f85954e11530bfea79187",
		"Baldie's family cuirass\nOnly one craftsman could make such a cuirass - and he took his secret with him to the grave...",
		"Erbbrustpanzer des Diebes „Der Kahle“\nNur ein Mensch konnte jemals solche Harnische herstellen. Das Geheimnis ruht mit ihm in seinem Grab."
	],
	"armor uniqueingos_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_prototype steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"armor uniqueingos_shirt steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ambushkey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ambushkey01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ambushkey02": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ambushkey03": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ambushkey04": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr animalmoney": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr apelsin": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr awl": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr axe": [
		"df209aa9a97d21ef4b871588ddc3a3f9b5ed6676f6ab6f4b7fb7ccb7b19732dc",
		"Metal axe\nEasy to make, easy to use!",
		"Metall-Axt\nEinfach herzustellen, leicht zu benutzen!"
	],
	"instr baburletter": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_hammer": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bad_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr banan": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheegipathfighter_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheegipathmage_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheehadaganfighter_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheehadaganmage_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheejfighter_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheejfighter_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheejmage_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bansheejmage_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bat_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr batblack": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr batred_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr batred_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr batred_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr batred_4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr battle_axe": [
		"16db20aef0b8a1905f35173b76c633d4c3afe731df0102022bb824b7996acfe8",
		"Metal battle axe\nThe battle axe is heavier than the simple axe, and it can cause much more damage.",
		"Streitaxt aus Metall\nDie Kampfaxt ist schwerer und nicht ganz so einfach zu benutzen wie die normale Axt. Aber sie ist wirkungsvoller."
	],
	"instr beholderred": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr beholdersimple": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr beholderyellow_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bone_club": [
		"cac9af3899c2cc420ac6a6fa48a4535dff7af2e7cd54b9089d323c496a8a42c6",
		"Bone club\nThe simplest and most ancient weapon.",
		"Knüppel aus Knochen\nDie einfachste und älteste aller Waffen!"
	],
	"instr bone_crossbow": [
		"7e003f54907c79043b4a2659e0ae989566734d67b7aba6e15b30c80c99cfdca0",
		"Bone crossbow\nThe result of applying advanced techniques to materials at hand.",
		"Knochenarmbrust\nDas Ergebnis fortschrittlicher Verfahren mit vorhandenen Materialien."
	],
	"instr bone_dagger": [
		"e4a4399fcddbd20cab351070cefc15ce34ef8bb16ee74905aa1b263d22b1b4f4",
		"Bone knife\nBetter than stone!",
		"Knochenmesser\nBesser als Stein!"
	],
	"instr bone_long_bow": [
		"52d68e15e59e69872bae22d03670454cc1cf4cc25eee49304bd6ea6ed0d6085d",
		"Long bone bow\nAn arrow shot with such a bow hits much harder than one shot from the short bow.",
		"Langbogen aus Knochen\nVerschießt Pfeile mit wesentlich höherer Geschwindigkeit als der normale Bogen."
	],
	"instr bone_long_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr bone_short_bow": [
		"2a2dbb2b4ab53a32154af80c5644b628c6bd2abce3ce17ebc5e3af4e21e37567",
		"Short bone bow\nThis bow is reinforced with bone, making it better than an ordinary one.",
		"Kurzbogen aus Knochen\nDieser Bogen ist, im Gegensatz zu einem normalen, mit Knochen verstärkt."
	],
	"instr bone_spear": [
		"e9c919623507ed538537fb9177bca2a9badf66a09eb1462c8d81fbfd1b61122f",
		"Bone spear\nYou can make a bone spearhead sharper than a stone one.",
		"Knochenspeer\nSpeerspitzen aus Knochen sind schärfer als jene aus Stein."
	],
	"instr burnbaby": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr caboom": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr cagekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr capitalitems": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr cheat_dagger": [
		"dd461430c40130bbd2558769ffe533b0149390db88fd2d4e6a43505209ef7e28",
		"Ritual knife\nLooks rather impressive, but it is not a combat weapon.",
		"Ritualdolch\nSieht eindrucksvoll aus, taugt aber nicht für den Kampf!"
	],
	"instr chestkey": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr clerkkey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crash_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr crossbow": [
		"b6d789e3ee3a49c3487760c0e7a1fdd6a5de9637f9a144c003544ec7f278498a",
		"Crossbow\nThis can't shoot as quickly as a bow, but can pierce heavier armor.",
		"Armbrust\nSchießt langsamer als ein Bogen, kann aber auch schwere Rüstungen durchdringen."
	],
	"instr crystal_axe": [
		"1d78d524d354c249817698683cedee5a762f63d09db5f8012d0b43c161b78b57",
		"Crystal axe\nThe best possible axe.",
		"Kristall-Axt\nEs gibt keine bessere Axt!"
	],
	"instr crystal_crossbow": [
		"5080c4f0d500a325165a570b8afb5f8b8327f2a953db2faf9552bb6f6ff59da9",
		"Crystal crossbow\nThe best possible crossbow.",
		"Kristall-Armbrust\nEs gibt keine bessere Armbrust!"
	],
	"instr crystal_dagger": [
		"7ac2a5ad5a03900e161ece405d33c94252ccb863501ab37af8d229d6504164a6",
		"Crystal dagger\nThe best possible dagger.",
		"Kristall-Dolch\nEs gibt keinen besseren Dolch!"
	],
	"instr crystal_mace": [
		"f96030f211c0a3d491b4b5e0627632dfd52cb67a34e0b75fa5c0dfcba694ee87",
		"Crystal mace\nLook at me and die -  that is the crystal mace!",
		"Kristall-Streitkolben\nEs gibt keinen besseren Streitkolben!"
	],
	"instr crystal_spear": [
		"4a78bd0b350b60f973329d6762e8080b5b6b72387d286594b5cbbda3d1806325",
		"Crystal spear\nYou cannot find a better spear!",
		"Kristall-Speer\nEs gibt keinen besseren Speer!"
	],
	"instr crystal_sword": [
		"81b8a87f4991743e890b535a9c5af760c79a600c664f0c6c32a09a24f9943a0d",
		"Crystal sword\nThe best possible sword.",
		"Kristall-Schwert\nEs gibt kein besseres Schwert!"
	],
	"instr curved_dagger": [
		"31fd11f7f4f0d923b76aea7f1893e41479f250b6ac77de42442b69da03a5dff5",
		"Dirk\nIts shape causes more damage than a straight dagger.",
		"Dirk\nRichtet aufgrund seiner Form wesentlich mehr Schaden als ein normaler Dolch an."
	],
	"instr dagger": [
		"89252fd72c80f6ad98ee5f0fd72ad3ef4829ebeddc1f5a362babe4e00070298d",
		"Dagger\nA quick, simple weapon. Use it with a backstab and you will have an edge.",
		"Dolch\nEine leichte, einfach zu handhabende Waffe, die vor allem beim Angriff von hinten Vorteile hat."
	],
	"instr danger_sensor": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr darrow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr deadbrissen": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr dflower": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr doggray": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr dogred": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr dragonpoison": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr dumblever": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elementalice1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elementalice2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elementallava": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elementallava_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elementallava_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr elemmat": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr fakedocument00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr foxtail1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr foxtail2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr fsword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gepard_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gepard_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gepard_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_brigand_boots": [
		"a0fa19718852f38e850414e5f38822c96283e35e19e3391fc12857c50d8ee70b",
		"Hunting Gipath boots\nAnyone who has spent time marching through the woods will appreciate the stealth that fur footwear provides.",
		"Gipather Jagdstiefel\nWer öfter im Wald unterwegs ist, wird die Bequemlichkeit und den leisen Tritt von Fellstiefeln zu schätzen wissen."
	],
	"instr gipat_brigand_gloves": [
		"e1302cd08bbe92bc910af2c478d835a25c42f14930a039ce5c88961091b6e2d3",
		"Hunting Gipath gauntlets\nGood decoration plus additional protection!",
		"Gipather Jagdhandschuhe\nKunstvoll gearbeitete Handschuhe, die zusätzlichen Schutz bieten."
	],
	"instr gipat_brigand_helm": [
		"48157bce8696a309b6d839b0c7b82a2fd49e7d0f0813795694bfd9638421dd21",
		"Hunting Gipath helmet\nSuch headgear should give its owner the strength and cunning of wild beasts!",
		"Gipather Jagdhelm\nDieser Helm soll seinem Träger die Kraft eines wilden Tieres verleihen."
	],
	"instr gipat_brigand_leggins": [
		"9b766b43032657ed75ab22da1f30ba8dab2ac243221c0cf5905895ec231acea2",
		"Hunting Gipath leggings\nOf course, you may feel a bit hot in these, but it is a small price to pay for such good leg protection.",
		"Gipather Jagd-Beinlinge\nEs wird schnell warm unter diesen Beinlingen. Aber dieses Problem ist vernachlässigbar."
	],
	"instr gipat_brigand_pants": [
		"9ccbece4dfccd9cf006bc5724f4748141d466fd9df8585443beef1e966495192",
		"Hunting Gipath shorts\nProvide decent protection and are suitable for long marches through the woods.",
		"Gipather kurze Jagdhosen\nBieten guten Schutz und sind auch für lange Waldmärsche geeignet."
	],
	"instr gipat_brigand_plate": [
		"0da791035cf5641a95fb78f32a052682f47223b7ab69a60615d6c77c71d93812",
		"Hunting Gipath cloak\nThis supplements the breastplate, it protects your elbows and shoulders from blows.",
		"Gipather Jagdumhang\nGute Ergänzung zum Brustpanzer - schützt zusätzlich die Arme und Ellenbogen vor Treffern."
	],
	"instr gipat_brigand_prototype": [
		"c28f6023bfad5f076b871a63699e84b4bc57c0259ab9fde103ea40e0fe486f2c",
		"Gipat_Brigand_Prototype\nGipat_Brigand_Prototype",
		"Gipat_Brigand_Prototype\nGipat_Brigand_Prototype"
	],
	"instr gipat_brigand_shirt": [
		"9fa2ed0258e04b24fa8fbe71d60f842e3aa37006ba921964a8b351967ca95108",
		"Hunting Gipath breastplate\nProvides decent protection and looks better than a simple breastplate.",
		"Gipather Jagd-Brustpanzer\nBietet guten Schutz und sieht besser aus als ein normaler Brustpanzer."
	],
	"instr gipat_high_boots": [
		"f23260b69aa8ec5904f2ca341f59017fbb089c7fcfbf37648339bbd53fec5e5e",
		"Stitched Gipath boots\nA pair of stitched boots is a couple of steps in the right direction.",
		"Gipather genähte Stiefel\nGenähte Stiefel sind schon mal ein Schritt in die richtige Richtung."
	],
	"instr gipat_high_gloves": [
		"bc15941a5108cfc23ded3a76ac64292fc3886160c27770bff13d31ed6c5f0e7b",
		"Stitched Gipath gauntlets\nTailored and quilted bracers protect more of the arm than light, plain or even hunting ones.",
		"Gipather genähte Handschuhe\nZugeschnittene und gesteppte Armschienen schützen mehr vom Arm als leichte, einfache oder sogar Jagdarmschienen."
	],
	"instr gipat_high_helm": [
		"86b0865f8959a72e43d7402878a47221e5328ecb3a011b68b49401a7ffff4c7d",
		"Stitched Gipath helmet\nIf you do not pay for a nicely cut helmet, you can get a nicely cut head!",
		"Gipather genähter Helm\nEs lohnt sich nicht, am Helm zu sparen!"
	],
	"instr gipat_high_leggins": [
		"a5b7c4091f1a2a48cfba09c19f6611604955ef117a88089a690b5c169a379b2f",
		"Stitched Gipath leggings\nExtra protection and elegance for extra money!",
		"Gipather genähte Beinlinge\nZusätzlicher Schutz und Eleganz haben ihren Preis."
	],
	"instr gipat_high_pants": [
		"ac5153442a54daadc8ff12a49c7ba4d10c7fb3c76276a43fc0ab5fc7815a69da",
		"Long quilted Gipath trousers\nDue to their cut, they provide much better protection for the legs than shorts.",
		"Lange gesteppte Gipath-Hose\nDie langen Hosenbeine bieten mehr Schutz."
	],
	"instr gipat_high_plate": [
		"30095e737fb25eef6dbe7193a101016cf93f106ebcb7fdc9136f20a39ce074bf",
		"Quilted Gipath cloak\nDue to efficient use of material, this provides good full-length arm protection.",
		"Gesteppter Gipath-Umhang\nDie gute Verarbeitung des Materials bieten annehmbaren Schutz für den ganzen Arm!"
	],
	"instr gipat_high_prototype": [
		"9aa2d67d64de5ba5b05c61ef15f17d76b4269f415b46f42038b07a529a35f5db",
		"Gipat_High_Prototype\nGipat_High_Prototype",
		"Gipat_High_Prototype\nGipat_High_Prototype"
	],
	"instr gipat_high_shirt": [
		"107447ba3a0f7e3217dcb93d5e55f2ceed5a666fb992bd23b77c2290fb000a1d",
		"Stitched Gipath breastplate\nIt takes longer to make, but provides better shoulder protection.",
		"Gipather genähter Brustpanzer\nLangwieriger in der Herstellung, bietet aber besseren Schutz für die Schultern."
	],
	"instr gipat_highest2_boots": [
		"37a5563b2a018738df027b15130bdf3430acf190f2a63bc98b1f926634ed3b66",
		"Rough Gipath boots\nMaking boots from hide takes great skill.",
		"Grobe Gipath-Stiefel\nStiefel aus Haut zu nähen erfordert großes Können."
	],
	"instr gipat_highest2_gloves": [
		"9ae2b351cdb9efb4bb1f944f6fdcea4f99a7c1c1fea79bdb0cedca8d070654f0",
		"Rough Gipath gloves\nThis complex blueprint takes a long time to turn into armour.",
		"Grobe Gipath-Handschuhe\nNach diesem aufwendigen Bauplan eine Rüstung zu fertigen dauert lange."
	],
	"instr gipat_highest2_helm": [
		"4b1678a6618b5c11bc5f8515c6ab2d5fb75dbfb6153b9d75db4c584746d6c025",
		"Rough Gipath helmet\nAn excellent helmet at a substantial price.",
		"Grober Gipath-Helm\nEin ausgezeichneter Helm zu einem beachtlichen Preis."
	],
	"instr gipat_highest2_leggins": [
		"80939bb02b06a48e9893f76e35be77b673ad454aca7c1affbcc1d88db7bdd6eb",
		"Rough Gipath leggings\nA superb blueprint at a considerable price.",
		"Grobe Gipath-Beinschienen\nEin hervorragender Bauplan zu einem beachtlichen Preis."
	],
	"instr gipat_highest2_pants": [
		"cca3c53b73013c35e09f181e0bd0a89d15b8730bb05ee70c3badde9c87bbedea",
		"Rough Gipath trousers\nOn Gipath, the blueprint for such armour costs a fortune.",
		"Grobe Gipath-Hose\nAuf Gipath kostet der Bauplan für eine solche Rüstung ein Vermögen."
	],
	"instr gipat_highest2_plate": [
		"8fd81a2c43b4300b16ebdd85908b91d84aff9ef5b02933c2ce63e0c312d716bc",
		"Rough Gipath coat\nA first-class coat, but difficult to make.",
		"Grober Gipath-Mantel\nEin erstklassiger Mantel, aber schwer herzustellen."
	],
	"instr gipat_highest2_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_highest2_shirt": [
		"920c84476afb57d82fa7455063e059d0520c6e05709989f37ecfc5c3f608cf72",
		"Rough Gipath shirt\nExcellent protection, though expensive.",
		"Grobes Gipath-Hemd\nAusgezeichneter, wenn auch teurer Schutz."
	],
	"instr gipat_highest_boots": [
		"c9f1cd1c04d308a5145177e18842ec027bcedcc2997ad5f0b7229a27d3d83bb4",
		"Heavy Gipath high boots\nThe best footwear you can hope to make under the circumstances.",
		"Gipather schwere Schaftstiefel\nDas Beste, was man unter diesen Umständen finden kann."
	],
	"instr gipat_highest_gloves": [
		"e20ae098614580dca7353b43567539765dd708e3c80ebbb041ae668156e13b45",
		"Heavy Gipath long gauntlets\nProvide practically full-length arm protection.",
		"Gipather schwere lange Handschuhe\nSchützen fast den ganzen Arm!"
	],
	"instr gipat_highest_helm": [
		"f5b46172158a3f569e51ca2065cf5c1d8892ce4afe67c969ca5ab537b6bdf881",
		"Heavy Gipath helmet\nNot too impressive to look at, but provides better head protection than any other Gipath helmet.",
		"Gipather schwerer Helm\nSieht nicht so gut aus, schützt aber besser als jeder andere gipather Helm."
	],
	"instr gipat_highest_leggins": [
		"335f880987b45a965f448944bc948c04c56caa114915ba09389628a0960fff07",
		"Heavy Gipath leggings\nIf you wear them on top of long trousers, you will have better leg protection than with any other Gipath armor.",
		"Gipather schwere Beinlinge\nZusammen mit langen Hosen die beste Beinpanzerung, die es auf Gipath gibt!"
	],
	"instr gipat_highest_pants": [
		"5c179b2a2fd7d33447dbfa8f4c706abb3b1a9a27a62f3ebb446aedf2ab6a626a",
		"Heavy Gipath long trousers\nGood protection from the belt down to the ankles.",
		"Gipather schwere Hosen\nGuter Schutz für das ganze Bein."
	],
	"instr gipat_highest_plate": [
		"6637ff439fe8aae18f5221f77a25084c1f6121d4ac1563013ad802336d1a1c84",
		"Heavy Gipath coat\nNo other Gipath armor can give you better arm and shoulder protection.",
		"Gipather schwerer Mantel\nKeine Rüstung auf Gipath schützt Rücken und Schultern so gut."
	],
	"instr gipat_highest_prototype": [
		"1a37a7eadaf7aff131b9e2ea35b4e3b6f1dd4dd109b320ff2f1be27398678f1b",
		"Gipat_Highest_Prototype\nGipat_Highest_Prototype",
		"Gipat_Highest_Prototype\nGipat_Highest_Prototype"
	],
	"instr gipat_highest_shirt": [
		"f11a7f4474f6cea27fdbead36a953f9920b09bc8e4d034fc2e7605a93c0b978e",
		"Heavy Gipath shirt\nProvides full-length arm and shoulder protection.",
		"Gipather schweres Hemd\nSchützt Arm und Schultern!"
	],
	"instr gipat_low_boots": [
		"cee3af1dcfb923663dad98a5f47613e8fa8b7ead71ac0ff3e9ad5096334c4d92",
		"Light Gipath boots\nYou will be safe from splinters ... Well,  at least that is something, is it not?",
		"Gipather leichte Stiefel\nMit denen tritt man sich wenigstens keinen Splitter in den Fuß."
	],
	"instr gipat_low_gloves": [
		"700ae1ba33981e9381f3b49326ee492b65375285168eccc65a1c212260a416a8",
		"Light Gipath gauntlets\nBetter to have this sort of arm protection than none at all.",
		"Gipather leichte Handschuhe\nDiese Handschuhe sind immer noch besser als gar nichts."
	],
	"instr gipat_low_helm": [
		"9a441c624b13bbdfe008ae43569fe428d3be2006befad0ee2f4d24b240f2a7e1",
		"Light Gipath helmet\nThe head needs some covering, if only to keep off the sun.",
		"Gipather leichter Helm\nDer Kopf braucht irgendeine Bedeckung, schon zum Schutz vor der Sonne."
	],
	"instr gipat_low_leggins": [
		"0933a5450bf5b626bc2f527cfc5a57f7f3df5a2b0c207a2e244dc5afaaa23dce",
		"Light Gipath leggings\nProtect your knees and feet from accidental scratches and bruises - but not from serious weapons!",
		"Gipather leichte Beinlinge\nSchützen die Knie und Füße vor Dornen und Stacheln, aber nicht vor richtigen Waffen."
	],
	"instr gipat_low_pants": [
		"59bebe52052cc6597ab16c06d6496d13ce9b371d6700b705a663e4b065153e33",
		"Light Gipath shorts\nYou should wear these more for decency than for serious protection in combat.",
		"Gipather leichte kurze Hosen\nMehr etwas um sich zu bedecken als für den Kampf."
	],
	"instr gipat_low_plate": [
		"052555d7b3f723f7352aad2d50d5cb5a47c39f849fc5177cee75d6f5266468de",
		"Light Gipath shirt\nProvides additional protection for breast, neck and shoulders if you wear it with your breastplate.",
		"Gipather leichtes Hemd\nZusammen mit dem Brustpanzer der ideale Schutz für Schulter, Nacken und Brust."
	],
	"instr gipat_low_prototype": [
		"72d3aff03a7c9bbe04ce2685f306861ed21d4ec510590b9cd45be9e397781800",
		"Gipat_Low_Prototype\nGipat_Low_Prototype",
		"Gipat_Low_Prototype\nGipat_Low_Prototype"
	],
	"instr gipat_low_shirt": [
		"0846e7840a19400f442f8c6adfc2310421bc02a94bcf2bd7468907699e5e6586",
		"Light Gipath breastplate\nWill protect your shoulders, chest and part of your back from the sun's rays.",
		"Gipather leichter Brustpanzer\nSchützt Brust, Schultern und Teile des Rückens - allerdings nur vor Sonnenstrahlen..."
	],
	"instr gipat_medium_boots": [
		"4e983d492e4a0fa28ecc49f200dc0820d83060908c76839c62334f029a4e3520",
		"Simple Gipath boots\nDue to their cut, they provide better protection than light boots.",
		"Gipather einfache Stiefel\nSind besser geschnitten als die leichten Stiefel und bieten deshalb mehr Schutz."
	],
	"instr gipat_medium_gloves": [
		"fe8658b556a1d35ae3d02040479bce0518f05e6d42419e36e2ca1907f3eb88eb",
		"Simple Gipath gauntlets\nDue to their cut, they provide better protection than light gauntlets.",
		"Gipather einfache Handschuhe\nSind besser geschnitten als die leichten Handschuhe und bieten deshalb mehr Schutz."
	],
	"instr gipat_medium_helm": [
		"c513bca2efbfe7cf38675d55652b3c6e6ce54feee1ff68a8f676dcb3fbf65d98",
		"Simple Gipath helmet\nDue to its cut, it provides better protection than a light helmet.",
		"Gipather einfacher Helm\nIst besser geschnitten als der leichte Helm und bietet deshalb mehr Schutz."
	],
	"instr gipat_medium_leggins": [
		"7b33d1e05ca8c04b6f5d20a4eb3551d4d68f8c3cfef098724905c61b605d252b",
		"Simple Gipath leggings\nDue to their cut, they provide better protection than light leggings.",
		"Gipather einfache Beinlinge\nSind besser geschnitten als die leichten Beinlinge und bieten deshalb mehr Schutz."
	],
	"instr gipat_medium_pants": [
		"b21a986cf7e4d7c2260be8c70743c7e29a340e40572bb506f4cc21a049662791",
		"Simple Gipath shorts\nDue to their cut, these provide better protection than light shorts.",
		"Gipather einfache kurze Hosen\nSind besser geschnitten als die leichten kurzen Hosen und bieten deshalb mehr Schutz."
	],
	"instr gipat_medium_plate": [
		"e934d21a8933b7ca54bbce5587ee06a5be91c508b6a0c1498ca6e45b193a9de0",
		"Simple Gipath cloak\nIts cut helps it give better protection than a light shirt.",
		"Gipather einfacher Umhang\nIst besser geschnitten als der leichte Umhang und bietet deshalb mehr Schutz."
	],
	"instr gipat_medium_prototype": [
		"bbbff78401a126014a843345c5bbe34150a68c919ab07f276de68698d0fd17b3",
		"Gipat_Medium_Prototype\nGipat_Medium_Prototype",
		"Gipat_Medium_Prototype\nGipat_Medium_Prototype"
	],
	"instr gipat_medium_shirt": [
		"453713480e8b56c4c6992bac4794217f3e1ae08413d31c3bb0b66c8a497c6173",
		"Simple Gipath breastplate\nDue to its cut, this provides better protection than a light breastplate.",
		"Gipather einfacher Brustpanzer\nIst besser geschnitten als der leichte Brustpanzer und bietet deshalb mehr Schutz."
	],
	"instr gipat_special_brigand_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_brigand_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_high_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_highest_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr gipat_special_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinarcher1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinarcher2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinarcher3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinfighter1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinfighter2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goblinfighter3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goldnugget": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr goldnugget00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr golemcenterkey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr greenleaf": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hadagan_brigand_boots": [
		"675261e2c64e9a81d1c585ab437e89c2e17cd98543e1128e4a06ee04fde838c5",
		"Khadaganian leather leggings\nGood protection from the fangs of beasts, but not from the weapons of enemies.",
		"Khadaganianische Leder-Beinlinge\nGuter Schutz vor wilden Tieren - aber kaum vor Waffen."
	],
	"instr hadagan_brigand_gloves": [
		"518f871c8d01260e8e8630b39eb8b9d748b40ff95e928726e594ee5c37dd3eb5",
		"Khadaganian leather gauntlets\nA match for wolves' fangs.",
		"Khadaganianische Lederhandschuhe\nEinen Wolfbiss halten sie durchaus ab."
	],
	"instr hadagan_brigand_helm": [
		"02a6fc944c672de5869c73f8af6ae7f11445876b452681a06cefbcc9cc63e2a8",
		"Khadaganian leather helmet\nIf you are struck on the head with a club, this will not help much. But it can protect you from a glancing blow.",
		"Khadaganianischer Lederhelm\nEinen Kopftreffer mit einer Keule hält man damit nicht aus, aber einen abgeglittenen Schlag schon."
	],
	"instr hadagan_brigand_leggins": [
		"7ac9719c9c4268abe61d946740582a60e4730697d3cc77476a24b30ddfef251a",
		"Khadaganian leather top leggings\nDo not anger sleeping Tigers while wearing these…",
		"Khadaganianische Überbeinlinge aus Leder\nIn diesen Beinlingen sollte man sich von Tigern lieber fernhalten."
	],
	"instr hadagan_brigand_pants": [
		"39295504581791b9c275e51ca23bfdaba0ff01633d1999fc46710dc11bdd826c",
		"Khadaganian leather trousers\nThese will save you from a spider's bite... But not from much more.",
		"Khadaganianische Lederhosen\nDen Biss einer Spinne können diese Hosen abwehren - mehr allerdings auch nicht."
	],
	"instr hadagan_brigand_plate": [
		"37883418c5ea26750523f97ac14aee28cd12ba836c88f2a5f772f67b27f80069",
		"Khadaganian leather coat\nThis one will come in very handy during a long hike.",
		"Khadaganianischer Ledermantel\nIdeal für lange Märsche!"
	],
	"instr hadagan_brigand_prototype": [
		"0bdb1c289b3d7315c19a626aaab2086a00038f98c2f9202fe0187312428a8228",
		"Hadagan_Brigand_Prototype\nHadagan_Brigand_Prototype",
		"Hadagan_Brigand_Prototype\nHadagan_Brigand_Prototype"
	],
	"instr hadagan_brigand_shirt": [
		"16ea092e857f9047e1dd550d76e2a290bcdfc8d72b70411ae3b302dd77b98f8a",
		"Khadaganian leather lower breastplate\nVery nice... Provided you have a real breastplate on top of it!",
		"Khadaganianischer großer Brustpanzer aus Leder\nSehr gut - wenn man noch einen richtigen Brustpanzer darüber trägt."
	],
	"instr hadagan_high1_boots": [
		"607ca1ab393daf5536a302dc8c591a8c092938c762f671a73219ad5adde582b4",
		"Khadaganian laminar boots\nNot bad boots. Not good ones, either.",
		"Khadaganianische Panzerstiefel\nKeine schlechten Stiefel. Aber auch keine guten."
	],
	"instr hadagan_high1_gloves": [
		"fa9860e078848c41b43d7a656be7aa44dc0cd41d671bd3cf1bd5630a0b8a72d6",
		"Khadaganian laminar gauntlets\nGood bracers for a new recruit.",
		"Khadaganianische Panzer-Beinlinge\nGute Armschienen für einen Rekruten."
	],
	"instr hadagan_high1_pants": [
		"d05fd682c31a826c0825fc25a1f0df7bfbc6d395ff77b49b70457bdbcb63cd90",
		"Khadaganian chainmail trousers\nWill not last long in combat...",
		"Khadaganianische Kettenhosen\nHält keinen Kampf lange aus."
	],
	"instr hadagan_high1_shirt": [
		"d61e6fbca805924ed5166e16b66b8520d7e1832382d8a16cb6bb3c9ce76c6817",
		"Light Hadagan chain mail\nToo heavy and uncomfortable...",
		"Leichtes hadaganisches Kettenhemd\nZu schwer und unbequem ..."
	],
	"instr hadagan_high2_boots": [
		"22933012faa269d693d00e35ce2b1db9eb88a0e45672311522fe3441a1a66bde",
		"Hadagan plate shoes\nThey shield the legs from any blow.",
		"Hadaganische Plattenschuhe\nSie schützen die Beine vor jedem Schlag."
	],
	"instr hadagan_high2_gloves": [
		"2f278b4784d8601252cb1075b1b42d793f0ad47fa89f790c6d5299b867cb1230",
		"Khadaganian laminar gauntlets\nIn these you can fend off even a sword blow.",
		"Khadaganianische Panzer-Beinlinge\nWiderstehen sogar einem Schwerthieb!"
	],
	"instr hadagan_high2_helm": [
		"78620eaa0f27fb87e80351beb2970cdd84182171345967bab89b138c48e7137d",
		"Khadaganian forged helmet\nThe worst scenario for the wearer would be a bad headache.",
		"Khadaganianischer geschmiedeter Helm\nDas Schlimmste, was einem mit diesem Helm noch passieren kann, ist eine Gehirnerschütterung."
	],
	"instr hadagan_high2_leggins": [
		"e8a3aaf60efbe6d7b646cd64b0640e2be2d1417364a73888a006a6e3e08f9fb0",
		"Khadaganian forged top leggings\nGood additional leg protection.",
		"Khadaganianische geschm. Überbeinlinge\nEin guter zusätzlicher Schutz für die Beine."
	],
	"instr hadagan_high2_pants": [
		"1e7954805ad56e81369613612cb4998c71c6e5811be5fd106cb4707755dd8f86",
		"Khadaganian chainmail trousers\nTwo layers of mail are better than one!",
		"Khadaganianische Kettenhosen\nZwei Lagen Geflecht sind besser als eine!"
	],
	"instr hadagan_high2_plate": [
		"c9e25d94d0b21716b4d9762b0db0d6fc305704e0e4889fcc34c4b59901268b50",
		"Khadaganian forged cuirass\nMakes a living and dangerous metal statue out of the owner.",
		"Khadaganianischer geschmiedeter Brustharnisch\nDer Träger dieser Rüstung wird fast schon zu einer wandelnden Metallstatue."
	],
	"instr hadagan_high2_prototype": [
		"343155a6e29b5a8b9043bb93177316fc905a297d20aa573410ea9744b76503a7",
		"Hadagan_High2_Prototype\nHadagan_High2_Prototype",
		"Hadagan_High2_Prototype\nHadagan_High2_Prototype"
	],
	"instr hadagan_high2_shirt": [
		"79de1c9f09a04f47c812b7d99d97d954b3eb370a16aa1978a4f941b2ab46972d",
		"Light Hadagan chain mail\nUnlike the Canian version, this has two layers with a finer weave.",
		"Leichtes hadaganisches Kettenhemd\nAnders als die kanische Ausführung hat diese zwei Lagen mit feinerem Geflecht."
	],
	"instr hadagan_high_boots": [
		"1f7f68b5a7e9d9099e9a78f9fee56f6b34d1c6dc80bcf2cf7fcca242a4fb8605",
		"Khadaganian thick hide boots\nExcellent in a chance skirmish, but not too reliable in real combat.",
		"Khadaganianische schwere Lederstiefel\nBieten in ernsthaften Kämpfen wenig Schutz."
	],
	"instr hadagan_high_gloves": [
		"d9f263cced1970e864b80681d901d40080146e2e4fe8ef44da647c765f2a66e0",
		"Khadaganian thick hide gauntlets\nProvide some arm protection from poor weapons.",
		"Khadaganianische schwere lange Handschuhe\nSchützen die Arme gegen leichte Waffen."
	],
	"instr hadagan_high_helm": [
		"3de155c3373530079b01c99a6b54a4d35b54c3e3560d744bd837fb39d754b5ef",
		"Khadaganian light helmet\nSoft cloth hides tough metal...",
		"Khadaganianischer leichter Helm\nWeiches Tuch verbirgt starkes Metall."
	],
	"instr hadagan_high_leggins": [
		"92af11a58e77a621d91a54082225fec765dd058e8461118c4acaf46fc456ccef",
		"Khadaganian chainmail trousers\nThey are reinforced with metal and protect the wearer from blows from simple weapons.",
		"Khadaganianische Kettenhosen\nDie Hosen sind mit Metall verstärkt und schützen dadurch vor leichten Waffen."
	],
	"instr hadagan_high_pants": [
		"9abfe41ffdfe224583ccb3f86d45c0a6c10be2efeb8fba3964744ec017859839",
		"Khadaganian thick hide trousers\nProvides good protection from poor weapons.",
		"Khadaganianische schwere Lederhosen\nGuter Schutz vor leichten Waffen."
	],
	"instr hadagan_high_plate": [
		"88be72c84773b2434fcfc98541c1acab6bee490816b67effcd3fa8bfbde7f293",
		"Khadaganian light cuirass\nWill protect you from simple weapons.",
		"Khadaganianischer leichter Brustpanzer\nSchützt vor leichten Waffen."
	],
	"instr hadagan_high_prototype": [
		"9cd06d7f662f509a76a4ddb22fc6237491887d8ebfbb07cf861a3c7b88ccc400",
		"Hadagan_High_Prototype\nHadagan_High_Prototype",
		"Hadagan_High_Prototype\nHadagan_High_Prototype"
	],
	"instr hadagan_high_shirt": [
		"8aea28b05a08d702a173b91ed751063169b107f9e072c22f105b41e117106ccc",
		"Khadaganian light armor\nProvides decent protection.",
		"Khadaganianische leichte Rüstung\nBietet annehmbaren Schutz."
	],
	"instr hadagan_highest2_boots": [
		"aa28354ae6ae1b9b777d45a707bf8de7988d4f381f19e14f5a510505645247f5",
		"Heavy Hadagan boots\nNot too light, but most reliable.",
		"Schwere hadaganische Stiefel\nNicht gerade leicht - aber verlässlich."
	],
	"instr hadagan_highest2_gloves": [
		"02f512f087522bb26e7bab98305ebdd83e48eb045b4c238022ab74a3f5122bc4",
		"Heavy Hadagan bracers\nAn excellent blueprint!",
		"Schwere hadaganische Armschienen\nEin ausgezeichneter Bauplan!"
	],
	"instr hadagan_highest2_helm": [
		"615846eb612981c55cc684b0bdd24fabac4a16661dfd29cbecea9b3c40e82c62",
		"Khadaganian heavy helmet\nYou could hammer this with something heavy for a long time - with no effect!",
		"Khadaganianischer schwerer Helm\nAuf diesen Helm kann man lange einschlagen - man wird nichts erreichen."
	],
	"instr hadagan_highest2_leggins": [
		"d9e684f48e333229cfa1070a5de7c08cced3ffee4e28609ae1ee2800828b44aa",
		"Khadaganian heavy leggings\nThe best of metal leggings!",
		"Khadaganianische schwere Beinlinge\nDie besten Beinlinge!"
	],
	"instr hadagan_highest2_pants": [
		"52cbb606cee4cce42ce86e1330d4825f21852fba39d7ff12893f91ded9065726",
		"Khadaganian heavy trousers\nComfortable and reliable - the best in Khadagan!",
		"Khadaganianische schwere Hosen\nBequem und zuverlässig - das Beste in Khadagan!"
	],
	"instr hadagan_highest2_plate": [
		"da24d395f26d7a82b689766d607d427de31e8f04e205ec9026e41449445036bb",
		"Khadaganian heavy cuirass\nA sword would break trying to pierce this cuirass!",
		"Khadag. schwerer Brustharnisch\nEin Schwert würde eher brechen als diesen Panzer zu durchdringen."
	],
	"instr hadagan_highest2_prototype": [
		"0eaf91b5a24708a744776973842f49fc473c58be215d09d5a1ffd3f7ecaf628c",
		"Hadagan_Highest2_Prototype\nHadagan_Highest2_Prototype",
		"Hadagan_Highest2_Prototype\nHadagan_Highest2_Prototype"
	],
	"instr hadagan_highest2_shirt": [
		"dff427c983efce4744979b0fedd96435064c8fbe14f5f663480225233914de59",
		"Khadaganian heavy shirt\nReally good protection!",
		"Khadaganianisches schweres Hemd\nEs gibt nichts Besseres."
	],
	"instr hadagan_highest_boots": [
		"24834793d8828d481cbf8a93f284a46aad799fc61134bb6cb0ec9715828b7798",
		"Khadaganian reinforced boots\nBoots, reinforced with forged plates.",
		"Khadaganianische verstärkte Stiefel\nMetallverstärkungen bieten zusätzlichen Schutz."
	],
	"instr hadagan_highest_gloves": [
		"b269a4fdcfe353f4cdf9a4b3d54ecb885a02428c504e8a4096759e7ef173cbfc",
		"Khadaganian reinforced gauntlets\nForged metal plates ensure much greater protection.",
		"Khadaganianische verstärkte Handschuhe\nGeschmiedete Metallverstärkungen bieten zusätzlichen Schutz."
	],
	"instr hadagan_highest_helm": [
		"9c75e41744a26e29ae6ab8c0fe36bc48a37057671803391cc95efb8d4f0d7715",
		"Khadaganian reinforced helmet\nDecent head protection.",
		"Khadaganianischer verstärkter Helm\nEin guter Kopfschutz."
	],
	"instr hadagan_highest_leggins": [
		"ef58e239be938970a321c55853b600161bedaf88d766e6056d1781399f2542eb",
		"Khadaganian reinforced leggings\nChainmail leggings reinforced with metal plates will protect you from the weapons of backstabbers.",
		"Khadaganianische verstärkte Beinlinge\nDiese verstärkten Beinlinge schützen auch bei Angriffen von hinten."
	],
	"instr hadagan_highest_pants": [
		"061fa0d96de41677a842e6dad1599e97f0234773290534316db421780ad52bf3",
		"Khadaganian reinforced chainmail trousers\nChainmail trousers reinforced with metal plates.",
		"Khadaganianische verstärkte Kettenhosen\nKettenhose mit zusätzlichen Metallverstärkungen."
	],
	"instr hadagan_highest_plate": [
		"1e4bab6f3a172a00d3ce9293b7d6f8eea844e453a291fed93fbae367362a3747",
		"Khadaganian reinforced cuirass\nChainmail cuirass reinforced with metal plates.",
		"Khadaganianischer verstärkter Brustharnisch\nBrustharnisch mit zusätzlichen Metallverstärkungen."
	],
	"instr hadagan_highest_prototype": [
		"9384301b108985f976396e0aea342cffb017c80bcbae9d8289aacbc81d1c7507",
		"Hadagan_Highest_Prototype\nHadagan_Highest_Prototype",
		"Hadagan_Highest_Prototype\nHadagan_Highest_Prototype"
	],
	"instr hadagan_highest_shirt": [
		"36d1a72d5019461a3085ba37952d6805cea80e0d71ea4cc420c865916cf6055a",
		"Khadaganian reinforced chainmail shirt\nA chainmail shirt reinforced with metal plates artfully woven in..",
		"Khadaganianisches verstärktes Kettenhemd\nEin Kettenhemd mit kunstvoll eingearbeiteten Metallverstärkungen."
	],
	"instr hadagan_low_boots": [
		"33fc84d6ea27645d32dd93a951a89eb948f38e1526cbfc1c79fc9a4fa827aaed",
		"Light boots\nPlain and simple cloth boots.",
		"Leichte Stiefel\nEinfache Stiefel."
	],
	"instr hadagan_low_gloves": [
		"5c67777d93cfa9aca3690fcb15209a108f3a9b73696bb56ced2be0cdaea4a7c8",
		"Light gauntlets\nCloth gauntlets, they will only save your ankle from a sprain.",
		"Leichte Handschuhe\nWirklicher Schutz ist von diesen Handschuhen nicht zu erwarten."
	],
	"instr hadagan_low_helm": [
		"c5be68ca8f8e1307bd3ae0cac9d233ac09c18b50240fb84999608ccb220f2960",
		"Khadaganianian hood\nPlain and cheap headgear. The quality is in line with the price.",
		"Khadaganianische Kapuze\nEine simple Kopfbedeckung für wenig Geld."
	],
	"instr hadagan_low_leggins": [
		"ebb95a9a381a1514a80184a661332a258d6b4c936e78e12fa6cdd7447f285ed2",
		"Khadaganian light top trousers\nThe second layer of cloth cannot be considered as serious leg protection.",
		"Khadaganianische leichte Überhosen\nAuch eine zweite Lage Stoff bietet noch keinen Schutz."
	],
	"instr hadagan_low_pants": [
		"f5024f4b0475a0a6a3df8ff24ce22d368031fd8d523d7ffc61dfbdcb820091a5",
		"Light trousers\nAbout all these do is cover your nakedness...",
		"Leichte Hosen\nWenigstens ist man damit nicht mehr nackt."
	],
	"instr hadagan_low_plate": [
		"78b744f229d79d9cf745fc62aa520cfb67972779641b4410cae68824897395fe",
		"Khadaganian light top collar\nProvides some additional shoulder and arm protection.",
		"Khadaganianischer leichter Überkragen\nWärmt Schultern und Arme."
	],
	"instr hadagan_low_prototype": [
		"679d9cfe1faa74b7e4a90f3adb022aded3158caffee576c8f1826efb0c4874c4",
		"Hadagan_Low_Prototype\nHadagan_Low_Prototype",
		"Hadagan_Low_Prototype\nHadagan_Low_Prototype"
	],
	"instr hadagan_low_shirt": [
		"8fd8524e040bcd43582f7e4d487824206dee69be1827b99b5e4d212ee567a1bd",
		"Light shirt\nA simple sleeveless shirt.",
		"Leichtes Hemd\nEin einfaches Hemd."
	],
	"instr hadagan_medium2_boots": [
		"0229b2849a3fe8316ef2d12fcd0a71af2c1cb7a00147d7ab056112b60ba71be9",
		"Quilted boots\nA pair of stitched boots is a couple of steps in the right direction.",
		"Gesteppte Stiefel\nGenähte Stiefel sind schon mal ein Schritt in die richtige Richtung."
	],
	"instr hadagan_medium2_gloves": [
		"3184103ef29c46299e439211ff81ad787bae7c2639508aa02e7d58d6a4ebd153",
		"Quilted bracers\nTailored and quilted bracers protect most of the arm.",
		"Gesteppte Armschienen\nZugeschnittene und gesteppte Armschienen schützen den größten Teil des Arms."
	],
	"instr hadagan_medium2_helm": [
		"3c9285c50dd9640a023da33f64d0268fb0a5b6d8df382953839b680a1c743fc2",
		"Quilted helmet\nIf you do not pay for a nicely cut helmet, you can get a nicely cut head!",
		"Gesteppter Helm\nEs lohnt sich nicht, am Helm zu sparen!"
	],
	"instr hadagan_medium2_leggins": [
		"6509cc8c9d47db32b864d43923d9924c4987b9f9410479904e32e681b4346c96",
		"Quilted leggings\nExtra protection and elegance for extra money!",
		"Gesteppte Beinschienen\nZusätzlicher Schutz und Eleganz haben ihren Preis."
	],
	"instr hadagan_medium2_pants": [
		"24e99a965bf447b058182753524020156ae23066fa19f745c866a33ec474cf60",
		"Quilted trousers\nTheir cut protects most of the legs.",
		"Gesteppte Hose\nIhr Schnitt schützt den größten Teil der Beine."
	],
	"instr hadagan_medium2_plate": [
		"db6fb35bb23e671c66d3416ea535ed5834b8af5fd8490d9416a396a356ad4dda",
		"Quilted cloak\nDue to efficient use of material, this provides good full-length arm protection.",
		"Gesteppter Umhang\nDie gute Verarbeitung des Materials bieten annehmbaren Schutz für den ganzen Arm!"
	],
	"instr hadagan_medium2_prototype": [
		"ec9a6f71af35e0451e641d92fb414a48ee90cd6f42ea307139830c6353419205",
		"Hadagan_Medium2_Prototype\nHadagan_Medium2_Prototype",
		"Hadagan_Medium2_Prototype\nHadagan_Medium2_Prototype"
	],
	"instr hadagan_medium2_shirt": [
		"2dc48133617ed6bd67b29969b5c6bb0461436785c417a57993dfe185f9fed4ad",
		"Quilted breastplate\nIt takes longer to make, but provides better shoulder protection.",
		"Gesteppter Brustschutz\nLangwieriger in der Herstellung, bietet aber besseren Schutz für die Schultern."
	],
	"instr hadagan_medium_boots": [
		"cffc78b829c79ee26952688e71106e1cdf2682e7a26d352de29b691b187f5f33",
		"Light Khadaganian boots\nAt least they are waterproof...",
		"Khadaganianische leichte Stiefel\nAuf jeden Fall wasserdicht!"
	],
	"instr hadagan_medium_gloves": [
		"76a3a32dd526481bd7850d3c12f78e2ee32d349135242b6186ba32a1b80d3291",
		"Cloth Khadaganian gauntlets\nNice - but not particularly useful.",
		"Khadaganianische Stoffhandschuhe\nSehen gut aus, sind aber nicht besonders nützlich."
	],
	"instr hadagan_medium_helm": [
		"095f98e027d98700fc7c5c558ec9d9cca94179bd796b5b745ef6bfb794bb9067",
		"Khadaganian turban\nBoth rich and poor can wear one. The material for the rich will be different, however...",
		"Khadaganianischer Turban\nEs gibt ihn für Reiche und für Arme. Nur das Material ist jeweils unterschiedlich..."
	],
	"instr hadagan_medium_leggins": [
		"d53f87392a9407cb582a46ed6e31e53678db6a67778d4e396fbb4e14b924aeea",
		"Khadaganian top long trousers\nA common Khadagan garment.",
		"Khadaganianische lange Überhosen\nSehr verbreitetes Kleidungsstück."
	],
	"instr hadagan_medium_pants": [
		"6330c041dde4dc2821b52459a701ded6514e4b2469d8a12e8ad40d5718ad5b33",
		"Long Khadaganian trousers\nJust pants, really - we all must have some ready for wear...",
		"Khadaganianische lange Hosen\nEine einfache Hose - nicht mehr und nicht weniger."
	],
	"instr hadagan_medium_plate": [
		"e024a55c1ffd61e819ad97fd502871cca3d719147c0aa3fa76ec1f1e5dd38a3f",
		"Khadaganian coat\nThe richer the man, the more impressive the coat.",
		"Khadaganianischer Mantel\nKleider machen Leute..."
	],
	"instr hadagan_medium_prototype": [
		"e69121d27ba93c0fd87e226546feb1b494212238d3d6d985856f3d3e05b95e40",
		"Hadagan_Medium_Prototype\nHadagan_Medium_Prototype",
		"Hadagan_Medium_Prototype\nHadagan_Medium_Prototype"
	],
	"instr hadagan_medium_shirt": [
		"cdb1c85abfb12dda633ac500e61d88342404b9dd43f3a335ba4d68f490fa9e28",
		"Long Khadaganian shirt\nIn this, you would be better off in a tavern than in combat.",
		"Khadaganianisches langes Hemd\nDarin wäre man besser in einer Taverne als im Kampf aufgehoben."
	],
	"instr hadagan_special_brigand_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hadagan_special_brigand_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hadagan_special_brigand_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hadogancagekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hadogancavekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hammer": [
		"384e62d53d1e96a48ecb3492b86abdaf60fdf632341420f18623cce41b71f22d",
		"Combat hammer\nAn advanced hammer, really. Useless at home, but can be very useful in a fight.",
		"Kampfhammer\nEin weiterentwickelter Hammer. Als Werkzeug völlig nutzlos, aber im Kampf sehr wirkungsvoll."
	],
	"instr head00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr herocagekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr his_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hyena_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hyena_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr hyena_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr instruction_armor": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr instruction_quick_item": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr instruction_weapon": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jamul": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jcontrol": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jdocs": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jkey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jmap": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jmaterial": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jmush": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jpump": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jtoys": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jun_high_boots": [
		"6ec0c7950378dd8c909fa602b538bec2261f4a3c4847977ccc0b058fb0fb7635",
		"Joon light leggings\nOne cannot find such craftsmen nowadays.....",
		"Leichte Joon-Beinlinge\nDas Produkt längst vergangener Handwerkskunst..."
	],
	"instr jun_high_gloves": [
		"d181b8e7299bd6783a25976eb4bb8a9a0d23245b8ddf995a66438e8f3761099d",
		"Joon gauntlets\nNo modern craftsman can make such things...",
		"Joon-Handschuhe\nHeute wird so etwas Edles gar nicht mehr hergestellt."
	],
	"instr jun_high_helm": [
		"039c75caba03003ea9b0a31c7cafeeff302aae1210fecc0a593e857c7dc5026c",
		"Joon helmet\nNo one knows the ancient secrets of such craftsmanship...",
		"Joon-Helm\nDas Geheimnis für die Herstellung solcher Gegenstände ist längst vergessen."
	],
	"instr jun_high_leggins": [
		"a55791f85f4c46166d583c892688b0984f0ccc70931750f62199c7f79c6094ee",
		"Joon full leggings\nThe ability to make such things would be worth half a lifetime to most...",
		"Schwere Joon-Beinlinge\nEin jeder würde sein halbes Leben gegen die Fähigkeit eintauschen, solche Dinge herstellen zu können..."
	],
	"instr jun_high_pants": [
		"02c40e29387891eb9e19fa06c2fbe64b5df24bec68bce23bb778bb8fe9e9150c",
		"Joon trousers\nEven the best of craftsmen are not up to making trousers of such quality!",
		"Joon-Hose\nSo etwas könnte heute niemand mehr herstellen."
	],
	"instr jun_high_plate": [
		"696a9c67251bea08fd55707b007e1aba1a723796415a9aa044ee98c20203003d",
		"Joon cuirass\nNo craftsmen remain who know how to make such things...",
		"Joon-Brustharnisch\nEs gibt keine Handwerker mehr, die solche Dinge herstellen können ..."
	],
	"instr jun_high_prototype": [
		"1493b61153c9e0848bafb0f46c2e3a26c05b30a9f49429e88ae0e11ef84d9c8d",
		"Jun_High_Prototype\nJun_High_Prototype",
		"Jun_High_Prototype\nJun_High_Prototype"
	],
	"instr jun_high_shirt": [
		"620e6dce2b18734bc53028dbd65e9b548145d907b36d81295cac8059d3b36cf9",
		"Joon shirt\nNo modern craftsman can make such things...",
		"Joon-Hemd\nVollendete Handwerkskunst, wie es sie heute nicht mehr gibt."
	],
	"instr jzombie_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr jzombie_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kania_brigand_boots": [
		"5327065ec3e36a48a7ddb0ced414de60580f72722502b88d9ff495f4a2891610",
		"Heavy Canian boots\nMany a beast would break their teeth on these!",
		"Canianische schwere Stiefel\nMit diesen Stiefeln muss man kaum eine Kreatur fürchten."
	],
	"instr kania_brigand_gloves": [
		"01d215a1059c73e2274b77d7fad19ba67da5fb48b70efd6d1264f2b65c0dd491",
		"Heavy Canian gauntlets\nReliable protection from a knife stab in a chance fight.",
		"Canianische schwere Handschuhe\nZuverlässiger Schutz vor Messerstichen bei einem kleinen Kampf."
	],
	"instr kania_brigand_helm": [
		"110ee0726929306923c584539d0aa35e2fbaefb57c7e7a6934ade7ab4e8d330f",
		"Heavy Canian helmet\nProtects your head, and not just from the cold!",
		"Canianischer schwerer Helm\nSchützt den Kopf nicht vor Kälte."
	],
	"instr kania_brigand_leggins": [
		"faa2e356eba24987eab0e15cbd395205b729e9bd6b15b99bea00227bdf08ee6c",
		"Heavy Canian top trousers\nProvides decent protection and also ensures freedom of movement.",
		"Canianische schwere Überhose\nBieten guten Schutz und sind bequem zu tragen."
	],
	"instr kania_brigand_pants": [
		"152c3d385586d0c132e8d2d02647e104e4fe756efa35b297ae1d1533c9b5d0a0",
		"Heavy Canian trousers\nA good choice for a warrior who wishes both protection and freedom of movement.",
		"Canianische schwere Hose\nIdeal für einen Krieger, der Wert auf Schutz und Beweglichkeit legt."
	],
	"instr kania_brigand_plate": [
		"d7b13c1bb256c59554464261d3206f39dc8f7a8d1e211f02b9c0320e659d61eb",
		"Heavy Canian coat\nIf the wearer of this owner is stabbed from the rear, he will still have a chance to get revenge!",
		"Canianischer schwerer Mantel\nWird der Eigentümer von hinten angegriffen, so hat er trotzdem eine Chance zurückzuschlagen!"
	],
	"instr kania_brigand_prototype": [
		"467feefe9c61d094fd8abdd090ef3aea4b01ced48422e4d6c01a1b23d28515fd",
		"Kania_Brigand_Prototype\nKania_Brigand_Prototype",
		"Kania_Brigand_Prototype\nKania_Brigand_Prototype"
	],
	"instr kania_brigand_shirt": [
		"b29a580310419369786813d78b9540ec7dd4ab23b2d108ebd3367ada7a499303",
		"Heavy Canian jerkin\nA good compromise between comfort and protection.",
		"Canianischer schwerer Wams\nEin gelungener Kompromiss aus Bequemlichkeit und Schutz."
	],
	"instr kania_high2_boots": [
		"b5c63ef0e6e017c1600e1aca7237426591a84b38927d847f8ef215b232371529",
		"Canian army boots\nSoldiers walk the roads of war in these - what more can you want?",
		"Canianische Armeestiefel\nSoldaten marschieren damit in den Krieg - was will man mehr?"
	],
	"instr kania_high2_gloves": [
		"c3f2b9324c1c31c0a8e098b0338bb334e2f54b2f27bbf9bb2b8e9677a7277959",
		"Canian army high gauntlets\nThese can fend off a light weapon blow!",
		"Canianische lange Armeehandschuhe\nDie können nur Treffer von leichten Waffen abhalten!"
	],
	"instr kania_high2_helm": [
		"1d50d85d79b9c02708f1adc9768489b2720a99b52ac376f4a429322ae4f82f18",
		"Canian army helmet\nThe wearer looks formidable - and his head is safe.",
		"Canianischer Armeehelm\nDer Besitzer sieht damit ausgesprochen furchteinflößend aus - und sein Kopf ist geschützt."
	],
	"instr kania_high2_leggins": [
		"6111b47510ad7d8cf7c51daf6398ba4be208c7fee95d04aa05e9c458ffb7df07",
		"Canian army leggings\nApproved by the Emperor as standard Canian army issue.",
		"Canianische Armeebeinlinge\nVom Imperator genehmigte Ausrüstung für die Armee."
	],
	"instr kania_high2_pants": [
		"c4b919676d6d6ad9aa6d8b710562cf2f42ed9ed8b1256c882397d0238651f5e6",
		"Canian army chainmail trousers\nNot every arrow would pierce that weave.",
		"Canianische Armee-Kettenhosen\nNicht jeder Pfeil kann dieses Metallgewebe durchdringen."
	],
	"instr kania_high2_plate": [
		"157e7ad2137ad510ba6726f1f9de2bcf2c21403798bb9dc9c9db311a04c3cbba",
		"Canian army cuirass\nNo brigand would try to backstab the wearer of this!",
		"Canianischer Armee-Brustharnisch\nKein Bandit würde es wagen, den Besitzer rücklings anzugreifen!"
	],
	"instr kania_high2_prototype": [
		"dd0c534d48d48408aca055ae966c9e0bad154058cfb6dd838ef8bf47f7e5a732",
		"Kania_High2_Prototype\nKania_High2_Prototype",
		"Kania_High2_Prototype\nKania_High2_Prototype"
	],
	"instr kania_high2_shirt": [
		"dae926f7e54cf3cd55aa2f7f025538b736a18e6bd1d20b665723b8ffedc7720d",
		"Canian army chainmail shirt\nThis is standard Canian army issue - which confirms the quality.",
		"Canianisches Armee-Kettenhemd\nCanianische Standardmilitärausrüstung - ein Zeichen für Qualität."
	],
	"instr kania_high_boots": [
		"e1feedab5fe6dc08a935a9fb5e1e65b11a57bc5e171590ad4772d1621565485b",
		"Light Canian combat boots\nDo not rely too much on these for protection.",
		"Canianische leichte Kampfstiefel\nDiese Stiefel bieten keinen optimalen Schutz."
	],
	"instr kania_high_gloves": [
		"49153262cfd24e6bfd59ac9690e190eefbac3e2d559f787af7d18ffc80a73286",
		"Light Canian combat gauntlets\nWill provide some additional hand protection.",
		"Canianische leichte Kampfhandschuhe\nGuter zusätzlicher Schutz für die Hände."
	],
	"instr kania_high_helm": [
		"e7f1be2544d63f1d379c22ecff7fc2f69b256d4265301940754f4e9fbb9e013d",
		"Light Canian metal helmet\nGood head protection from side blows, but no match for a direct blow to the face.",
		"Canianischer leichter Metallhelm\nGuter Kopfschutz gegen seitliche Schläge, aber kein Schutz gegen direkte Schläge ins Gesicht."
	],
	"instr kania_high_leggins": [
		"6bfc474839be3510a42525abc26892b064ccaba56922408623a25d3f10c61c96",
		"Light Canian metal leggings\nMetal plates will not protect you from blows from behind.",
		"Canianische leichte Metallbeinlinge\nDie Metallplatten schützen nicht vor Angriffen von hinten."
	],
	"instr kania_high_pants": [
		"5b083f9b7f9e75b482bde73150bdfd70fd6f425c7e224388d64a9741cae7d4b7",
		"Canian thick hide trousers\nThese will protect you from the teeth of the wolf, but the fangs of the Tiger are another story....",
		"Canianische dicke Lederhose\nMit Wölfen kann es diese Hose wohl aufnehmen. Kaum aber mit Tigern."
	],
	"instr kania_high_plate": [
		"b93a086ecd29cd912af39a63c95102abe15bd91f04c3f55138338ca8191e9145",
		"Light Canian cuirass\nProvides additional protection from sharp weapons.",
		"Canianischer leichter Brustharnisch\nBietet zusätzlichen Schutz gegen scharfe Waffen."
	],
	"instr kania_high_prototype": [
		"0c9c964fdf9b1bc15b14b3c112f9c3b40e6ee7d21abaf66838ddec3b931421da",
		"Kania_High_Prototype\nKania_High_Prototype",
		"Kania_High_Prototype\nKania_High_Prototype"
	],
	"instr kania_high_shirt": [
		"b99d104b13735d9ee5b5d39f53cbdd1559574a532465de8d62d1deb62a3029a1",
		"Canian thick hide jerkin\nThis will protect you from a chance arrow from a short bow.",
		"Canianischer dicker Lederwams\nBietet einen gewissen Schutz vor verirrten Pfeilen von Kurzbögen."
	],
	"instr kania_highest2_boots": [
		"44a489a0de053c4ddd1aae2fb62e95785368e5cf474ce020983c012dd20d5f8e",
		"Canian heavy army boots\nWith these you can kick Trolls and not hurt your toe!",
		"Canianische schwere Armeestiefel\nDamit kann man Trolle treten..."
	],
	"instr kania_highest2_gloves": [
		"f043766920b96fe16a7180e3df0b6c502e3be40e48e5045cad33dade841e5482",
		"Canian heavy army gauntlets\nYou'll not cut your hand in a gauntlet like this!",
		"Canianische schwere Armeehandschuhe\nMit einem solchen Handschuh ist die Hand nahezu perfekt geschützt."
	],
	"instr kania_highest2_helm": [
		"153ca21edcbb4074ad13caea8557e8d1095b8e961720733d6079beafb75c0d3e",
		"Canian heavy army helmet\nFormidable protection!",
		"Canianischer schwerer Armeehelm\nHervorragender Schutz!"
	],
	"instr kania_highest2_leggins": [
		"75271600dec0818a57585e8e7c3580f71e53a17a5737b4d1256ac235b524b20f",
		"Canian heavy army leggings\nIssued to Canian soldiers who stand in the front line of battle.",
		"Canianische schwere Armeebeinlinge\nWird an jene canianischen Soldaten ausgegeben, die im Kampf in der ersten Reihe stehen müssen."
	],
	"instr kania_highest2_pants": [
		"ae7498a741b60e72b80b609a531263767b4291a305af4af8176cac6e10a9cfa5",
		"Canian heavy army trousers\nIf you sit on a poisonous frog, you wouldn't even notice it.",
		"Canianische schwere Armeehose\nDamit würde man es nicht mal bemerken, wenn man sich auf eine giftige Kröte setzte."
	],
	"instr kania_highest2_plate": [
		"6afae5ff809e1372d9bdb4eadd980b0611e9aa297514803575961bee0c054f68",
		"Canian heavy army cuirass\nHardly anything can cut through this!",
		"Canianischer schwerer Armeebrustharnisch\nEine Reihe von Soldaten, die solche Brustharnische tragen, ist ein unüberwindliches Hindernis!"
	],
	"instr kania_highest2_prototype": [
		"f3d24cfa7ca7726cc5154904f3ae68cfb7e816cb1ba58fcd7994a8a3132533ca",
		"Kania_Highest2_Prototype\nKania_Highest2_Prototype",
		"Kania_Highest2_Prototype\nKania_Highest2_Prototype"
	],
	"instr kania_highest2_shirt": [
		"76b933273f9ee1c94edf0ba15d4655bfae0713a324411a75ab2f83986f57746e",
		"Heavy Canian plate shirt\nThis armour could stand on the ground by itself...",
		"Schweres kanisches Plattenhemd\nDiese Rüstung könnte von allein auf dem Boden stehen ..."
	],
	"instr kania_highest_boots": [
		"51bcb2dd7fa38fc1c22223bb184d1bf0a2084e389ac7d26855369dba69502acf",
		"Canian chainmail boots\nThey do not cover as much of the leg as light boots do, but they at least provide better protection for portion they cover!",
		"Canianische Kettenstiefel\nSie bedecken einen kleineren Teil des Beins als die leichten Stiefel, aber der bedeckte Teil ist besser geschützt."
	],
	"instr kania_highest_gloves": [
		"3c8e18964396253b10a056499666370259078d9817ccb273abf826f246e87fb7",
		"Reinforced Canian combat gauntlets\nThe metal inlays provide better arm protection than light combat gauntlets.",
		"Canianische verstärkte Kampfhandschuhe\nBieten aufgrund der Metallbeschläge besseren Schutz für die Arme als leichte Panzerhandschuhe."
	],
	"instr kania_highest_helm": [
		"39d65f1cea42279b41178733000f4960dd952e21f25faef54078a4f14fe780a9",
		"Winged Canian helmet\nThis is not just protection, this looks menacing!",
		"Canianischer Flügelhelm\nBietet nicht nur Schutz, sondern auch einen moralischen Vorteil: Er sieht so gefährlich aus..."
	],
	"instr kania_highest_leggins": [
		"cf8fca9908dd83d26944bd3613588c57035fb7ef1baf079f8c84f6514b62159c",
		"Heavy Canian leggings\nNot for a dance - for battle!",
		"Canianische schwere Beinlinge\nZum Tanzen nicht geeignet - aber das ist auch nicht ihr Zweck."
	],
	"instr kania_highest_pants": [
		"79dea1449d0f136c2362cc048435138a5da91467b818454fdbc8d35e631e5bc5",
		"Canian chainmail trousers\nThese provide additional leg protection due to their thicker weave.",
		"Canianische Kettenhose\nBesonders guter Schutz für die Beine durch dickes Material."
	],
	"instr kania_highest_plate": [
		"ca58bbf13bac4566e2337cc196137d794d10fd6d26ec994a0cef110b01fda709",
		"Heavy Canian cuirass\nWith the forged onlays, they provide better protection than a light cuirass.",
		"Canianischer schwerer Brustharnisch\nBesserer Schutz als der leichte Brustharnisch aufgrund geschmiedeter Beschläge."
	],
	"instr kania_highest_prototype": [
		"ea8f583de97d270398b4573865e2eaa8eee44dd3d28b0d1024bbc5cc1354448d",
		"Kania_Highest_Prototype\nKania_Highest_Prototype",
		"Kania_Highest_Prototype\nKania_Highest_Prototype"
	],
	"instr kania_highest_shirt": [
		"0e176b99fad2796a664f73d8a7328c6c786795eabf28463c87011efadddcd616",
		"Canian chainmail shirt\nBetter than a leather jerkin; it softens the blows.",
		"Canianisches Kettenhemd\nBesser als ein Lederwams; mildert Treffer ab."
	],
	"instr kania_low_boots": [
		"692437437c5afe92fd2f1afb94e11a4e6ce3dfbcc9cd316fe9ae53d1f617dd52",
		"Canian boots for farmers\nWell, they are at least waterproof.",
		"Canianische Bauernstiefel\nImmerhin wasserdicht!"
	],
	"instr kania_low_gloves": [
		"8fd1d3d1585110b6fa2ff755ea0e28942b031cd2db4a2c63006f496a9850dadb",
		"Canian gauntlets for farmers\nSuitable for fighting - provided, of course, it is fist fighting at a spring fair.",
		"Canianische Bauernhandschuhe\nGeeignet für den Kampf - natürlich nur, wenn es um ein Gerangel bei einem Dorffest geht."
	],
	"instr kania_low_helm": [
		"bbc6491e1de321460e8b2937b7c5640da528bbab1dec53a6987a8728dc407929",
		"Canian farmer's hat\nThis would protect you from the heat of the sun, but not the heat of battle!",
		"Canianischer Bauernhut\nGut gegen die Sonne - aber kaum gegen Feinde."
	],
	"instr kania_low_leggins": [
		"819ee15e75cc12e3a93b248cf6ce883ebf625d0ec69521df18a0a7dec9e64de9",
		"Canian light top trousers\nThey are warm... To a poor man, that's something.",
		"Canianische leichte Überhosen\nSie sind warm - für arme Leute reicht das."
	],
	"instr kania_low_pants": [
		"fe485bb1f99c5a0581041276a40aab0fb2359f2e4c9bec54a263302e19a270e7",
		"Canian farmer's trousers\nThese will protect you from the teeth of the wolf, but the fangs of the Tiger are another story....",
		"Canianische Bauernhose\nMit Wölfen kann es diese Hose wohl aufnehmen. Kaum aber mit Tigern."
	],
	"instr kania_low_plate": [
		"e63ce8d90e34a2b542092e3417e6f476210f14acc9bf60c95433f0da832e81c3",
		"Canian light coat\nNot very good protection from weapons, but this will cover your chainmail shirt - if you have one, that is.",
		"Canianischer leichter Mantel\nSchützt kaum gegen Waffen, bedeckt aber das Kettenhemd. Wenn man denn eins hat..."
	],
	"instr kania_low_prototype": [
		"bf4738437e5f161e77a5573b011f8610ac0c1e39c2606d4c17060ca5bde2a0ad",
		"Kania_Low_Prototype\nKania_Low_Prototype",
		"Kania_Low_Prototype\nKania_Low_Prototype"
	],
	"instr kania_low_shirt": [
		"e0cac4393435253e1456e0ad171914ca4cd3c33d8d15a7a63809bf24bf162a89",
		"Canian farmer's shirt\nGood enough for farming, but hardly for fighting.",
		"Canianisches Bauernhemd\nGut für die Feldarbeit - aber kaum für den Kampf."
	],
	"instr kania_medium_boots": [
		"228b202f54825cbc624bc617505f1e3949068e0f031a2f066053ff6ccdda5320",
		"Canian hunting boots\nGood footwear for hunting.",
		"Canianische Jagdstiefel\nGut für die Jagd."
	],
	"instr kania_medium_gloves": [
		"970c6f72aee5676b9681af5b392457a45bc3990c7e8dc607cce18fbbc07b927a",
		"Canian hunting gauntlets\nNot very much different from the ones for farmers.",
		"Canianische Jagdhandschuhe\nKaum anders als die Bauernhandschuhe."
	],
	"instr kania_medium_helm": [
		"c8497ecfefc14b55f86e212ed95b56602184404f8ced51406fb9ebe387562966",
		"Canian hunting hat\nA feather in your cap is guaranteed - in this hat it is a permanent fixture!",
		"Canianischer Jagdhut\nImmerhin ist die Feder angenäht."
	],
	"instr kania_medium_leggins": [
		"19699f299a5e53291dfc1a02974f95cb16edefbdccb958b18722cc1d9b687189",
		"Canian top hunting trousers\nYou will not freeze in these!",
		"Canianische Jagdüberhose\nMit der friert man bestimmt nicht."
	],
	"instr kania_medium_pants": [
		"905920ff73cbe45ac8f01ab0abfe60a888483d7989077292546705a6542b7253",
		"Canian hunting trousers\nTheir cut makes them comfortable for long marches.",
		"Canianische Jagdhose\nAufgrund ihres Schnitts gut für lange Märsche geeignet."
	],
	"instr kania_medium_plate": [
		"607e387dbc3fc1ae34e91b95aea50e1a1611c8888c15bbf48af53864ff50946b",
		"Canian hunting jerkin\nNot every wolf could bite through this... but you cannot say the same for knives.",
		"Canianischer Jagdwams\nNicht jeder Wolf könnte durch diesen Wams durchbeißen... Aber ein Messer käme sicher durch."
	],
	"instr kania_medium_prototype": [
		"b58f010d268a3841ad636e595737b7638b5d8077c2670251ea20e0133687824b",
		"Kania_Medium_Prototype\nKania_Medium_Prototype",
		"Kania_Medium_Prototype\nKania_Medium_Prototype"
	],
	"instr kania_medium_shirt": [
		"2bf9d171dcc9cdf806f1991679e3b0aaa694fcae8b399c7f8e94db714b31aeff",
		"Canian hunting jerkin\nProvides better arm protection due to its long sleeves.",
		"Canianischer Jagdwams\nBesserer Schutz für die Arme aufgrund langer Ärmel."
	],
	"instr kania_special_highest_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kania_special_highest_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kania_special_medium_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kania_special_medium_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kania_special_medium_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kel1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kel2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kel3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kel4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr key01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey02": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey03": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey04": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey05": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey06": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kkey07": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kleverbook": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr knote01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kokos": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kwater01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr kwater02": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr large_potion_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr large_potion_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr large_potion_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr long_bow": [
		"4d92561e6b1963810eced78aaaa0ebedfd768785bc5e06ff9e2f29849c47cdd6",
		"Long bow\nA good ratio of arrow power and speed of shooting.",
		"Langbogen\nGutes Verhältnis zwischen Spannkraft der Sehne und Schussgeschwindigkeit."
	],
	"instr long_crossbow": [
		"347b4addcee22d81d0064e34903b9fc307c1789b25e72788c789acc36ca6deb3",
		"Heavy crossbow\nSlower than a regular one, but still more powerful!",
		"Schwere Armbrust\nLangsamer als eine gewöhnliche Armbrust, hat aber dafür auch mehr Durchschlagkraft!"
	],
	"instr long_spear": [
		"6142df381c20375f49e60cf1f32334c5a1fbf483ebdad57a0677f1807a6af0f2",
		"Long spear\nThis will make even the most antagonistic people keep their distance.",
		"Langspeer\nDadurch kann man die aufdringlichsten Gesellen auf Distanz halten."
	],
	"instr long_sword": [
		"abb3a48ca511b4999f50b09fac9221112604e84924d67399ba7cce10ec775f28",
		"Long sword\nA serious weapon, especially if you use quality material.",
		"Langschwert\nGefährliche Waffe, besonders wenn Metall hoher Qualität verwendet wird."
	],
	"instr mace": [
		"5cb2c9e02b8db37f48ad9b524d9ef68e4bffda63780b4a1fda1a193b50a0ab64",
		"Mace\nA step forward compared to hammers - both in terms of efficiency and price.",
		"Streitkolben\nDem gewöhnlichen Hammer um einiges voraus, sowohl was Wirkung als auch was den Preis angeht."
	],
	"instr magedocs": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr magicitems": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr map00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr mindcontrol": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr money": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr mushroom1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr mushroom2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr necklace": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr new_bow": [
		"019c4b2b9c2b14050451304c77c59ecc4b69ee07c184e52427f83c9da5f58a53",
		"Crystal bow\nThe best of bows.",
		"Kristallbogen\nDer beste Bogen."
	],
	"instr note": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note02": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note03": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note04": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note05": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note06": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr note07": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ogrefood": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ogrekey": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ogrekey1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ogrekey2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ogrepresent": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr orcgear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr palantirbroken00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr palantirwork00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr paper": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr percovka": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr potion_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr potion_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr potion_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr potion_enlarge": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr potion_shrink": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr ragu": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rat_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rat_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rat_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rat_4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rat_5": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr report": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr rune": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr saber": [
		"b65d8fb34eee3794c716039fbf19dd91c29bd28bc097fb99eee80bbcb562c2b8",
		"Metal sabre\nYou can strike with a sabre faster than with a long sword, but it causes less damage to the enemy.",
		"Metallsäbel\nMit einem Säbel kann man schneller zuschlagen als mit einem Langschwert, aber er fügt dem Feind weniger Schaden zu."
	],
	"instr sackbabur": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr sackhunter": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr sackofbones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr sackofgold00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr sackofmat": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr serp": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr shadow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr shell": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr short_bow": [
		"4c3e825fb8684f158e6f36a72c4532616a62ec055a66fb0b446caaa7edb4cf89",
		"Short bow\nIn this case, power was sacrificed for speed.",
		"Kurzbogen\nHier wurde der Schnelligkeit Vorzug gegenüber der Durchschlagskraft gegeben."
	],
	"instr small_potion_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr small_potion_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr small_potion_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr spear": [
		"85ad12939fd6021669ccd19ae7c56084bc34fc3edc606d127805d9345e255660",
		"Spear\nA good weapon, especially if you use quality material.",
		"Speer\nKeine schlechte Waffe, vor allem wenn hochwertiges Material verwendet wird."
	],
	"instr spell_container": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr spider_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr spider_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr spider_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr spiked_club": [
		"8572fc603c50f97b2a650039b2b367df4ce9d494d0fe39bb47957238493c414b",
		"Heavy spiked mace\nThat is a really scary weapon if you know how to use it!",
		"Schwerer Streitkolben mit Stacheln\nEine wirklich furchteinflößende Waffe, wenn man sie zu führen weiß. Selbst wenn man es nicht weiß..."
	],
	"instr spiked_mace": [
		"424e57b7cae31330c25aed002d4e5b64bc75cb9b7a328c4d0c8480cd3e272245",
		"Spiked mace\nThe spikes make this mace even more awesome.",
		"Streitkolben mit Stacheln\nDurch die Spitzen wird dieser Streitkolben noch gefährlicher."
	],
	"instr stone_axe": [
		"056e16bbf97df98736c3b21ca6c437a1cccebd1cc8310439a984e5fc6c437ec5",
		"Stone axe\nThe simplest axe, and thus, not very efficient. But the price is quite acceptable.",
		"Steinaxt\nEine einfache, nicht sehr wirkungsvolle Axt. Aber der Preis ist akzeptabel."
	],
	"instr stone_battle_axe": [
		"b1c30c855c1304518b29f0eccd6eaf06d6a82c96ab0343e03895acd37f104a4f",
		"Stone battle axe\nThe battle axe is heavier than a simple axe, so it causes more damage.",
		"Steinstreitaxt\nDie Streitaxt ist schwerer als die normale Axt und richtet mehr Schaden an, ist aber im Kampf schwieriger zu führen."
	],
	"instr stone_battle_hammer": [
		"a711ad342a2397c0e356ce04b82978f8f29a6b02bad74c0c67b46a2b4ca3314d",
		"Heavy stone hammer\nWith this hammer you will not strike quickly, but every blow will cause serious damage to the enemy.",
		"Schwerer Steinhammer\nMit diesem Hammer kann man zwar nicht schnell zuschlagen, aber jeder Schlag richtet schweren Schaden an."
	],
	"instr stone_battle_sword": [
		"1e14bfe2334fe654f984145e81cbe32ab090523252dee222fe32197acfa39851",
		"Stone battle sword\nA fearsome weapon in an experienced warrior's hands.",
		"Steinkampfschwert\nEine furchterregende Waffe in den Händen eines erfahrenen Kriegers."
	],
	"instr stone_dagger": [
		"2cf0f88c5b1410e0b1a8e779da354c7a874c4f45e792d87670ad38047b3dbf53",
		"Stone dagger\nA simple but worthy piercing weapon. You do not need much material to make it.",
		"Steindolch\nEine einfache, aber nützliche Stichwaffe. Man braucht nur wenig Material, um sie herzustellen."
	],
	"instr stone_short_bow": [
		"fb2a6d66e79ce45a8c374476981a7563e124fda181e6e7aa2134a2d0abc46254",
		"Bow (stone head arrows)\nStone is not the best possible material, but it will have to do for now.",
		"Bogen (Steinpfeilspitzen)\nStein ist nicht das beste Material, muss aber für den Anfang genügen."
	],
	"instr stone_spear": [
		"6fc867889a6782f7a4df8d8c4ba1f85c230cbb6662ca9dd939ba072110c93ec9",
		"Stone spear\nThe simplest possible spear.",
		"Steinspeer\nDer einfachste Speer."
	],
	"instr stone_sword": [
		"4fa4f7d209f018e5a41c47dd857242dcba5e0b16931f4f80a7a9c5287011505c",
		"Stone sword\nThe weapon for those who cannot lay their hands on a metal sword.",
		"Steinschwert\nDas ist eine Waffe für diejenigen, die sich kein Metallschwert leisten können."
	],
	"instr succubusgreen": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr succubusj": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr succubusred": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr superspear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr sveralc": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr svermark": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr swampflower": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr teleportkey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr teleportkey01": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thief_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thiefsack": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thiefsack1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr thiefsack2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr tigers": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr tiny_potion_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr tiny_potion_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr tiny_potion_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad2_j": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad_4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr toad_j": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr traderkey1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr traderkey2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr unicornblack": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr unicornwhite": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr unique_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr unique_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquegipathadagan_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquehadagan_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquehadagan_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniquehadagan_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_boots": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_gloves": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_helm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_leggins": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_pants": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_plate": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr uniqueingos_shirt": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wand_1": [
		"2c586b8859830cccfda7304b334606621852e19d63ba1da379717b0ca7cf61f0",
		"Stone wand\nSuch a wand may contain simple spells (no need to have an \"object\" rune for that).",
		"Steinzauberstab\nIn einem solchem Zauberstab können einfache Zaubersprüche schlummern (keine \"Objektrune\" nötig)."
	],
	"instr wand_2": [
		"e7c189c355f443eb574c55638e32812cd4eef9a00e641d9b65102fa92b3c47a8",
		"Bone wand\nSuch wand may contain simple spells (no need to have an \"object\" rune for that).",
		"Knochenzauberstab\nIn einem solchem Zauberstab können einfache Zaubersprüche schlummern (keine \"Objektrune\" nötig)."
	],
	"instr wand_3": [
		"4c87b3e5da2cfb48918105f8106dcf6e6af8cd7e1e2f1c50988a2d9890498ede",
		"Metal wand\nSuch a wand may contain simple spells (no need to have \"object\" rune for that).",
		"Metallzauberstab\nIn einem solchem Zauberstab können einfache Zaubersprüche schlummern (keine \"Objektrune\" nötig)."
	],
	"instr wand_4": [
		"fd5f1f087a54cea18867b480534bb1f290f5c78406cb965ec6e6cfb0e5ee5980",
		"Carved metal wand\nSuch a wand may contain simple spells (no need to have \"object\" rune for that).",
		"Verzierter Metallzauberstab\nIn einem solchem Zauberstab können einfache Zaubersprüche schlummern (keine \"Objektrune\" nötig)."
	],
	"instr wand_5": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wand_6": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr willowisp_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr willowisp_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr willowisp_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfgray_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfgray_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfgray_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfhead1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfhead2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfwhite_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfwhite_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfwhite_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr wolfwhite_4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr zakknife": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"instr zombie_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem apelsin": [
		"080aac6a373edea393897c231a1db4b04d39726f9fa3f56454e484f918da75ee",
		"Oranges\nNot worth much, but always in demand.",
		"Orangen\nNicht viel wert, aber immer gefragt."
	],
	"litem apelsin ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem banan": [
		"a990efca0050e5123bea834a55b00ed418debc9566b40af41fe1235169bd6bd1",
		"Banana\nOne banana, one coin.",
		"Banane\nEine Banane, eine Münze."
	],
	"litem banan ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheegipathfighter_1": [
		"c38c93c565f49ff10063a0f50788c3d359eeadb95243572668d39ca9aa10158b",
		"Banshee cloak\nLegend has it that such a cloak can protect you from ghosts.",
		"Todesfeemantel\nDer Legende zufolge kann ein solcher Umhang vor Geistern schützen."
	],
	"litem bansheegipathfighter_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheegipathmage_1": [
		"4cc0edf38609ea16c04f90f3ad57087c714615f3ca83a125cdc8c451e7284807",
		"Banshee stone\nThey say this stone will protect a home from evil magic.",
		"Todesfeestein\nMan sagt, dieser Stein schützt vor böser Zauberei."
	],
	"litem bansheegipathmage_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheehadaganfighter_1": [
		"9d17a79c22c994764d7bc618d81a935ebfddfcf6834e366fed0f02e6137496d8",
		"Black banshee cloak\nLegend has it that a banshee cloak keeps other ghosts away from your home.",
		"Schwarzer Todesfeemantel\nDer Legende zufolge hält der Umhang der Todesfee andere Geister vom Haus fern."
	],
	"litem bansheehadaganfighter_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheehadaganmage_1": [
		"face2bbb5f11464259a8ed58a8d1b17d6483a9cf5e6aba917e1f94bc95914381",
		"Black banshee stone\nThey say this stone will protect a home from evil magic.",
		"Schwarzer Todesfeestein\nMan sagt, dieser Stein schützt vor böser Zauberei."
	],
	"litem bansheehadaganmage_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheejfighter_1": [
		"ae220e28748eee6756a568f5955d2bed736c9ff5f8a28f56e61fc8d486031cca",
		"Royal banshee's robe\nThis robe is said to protect against certain ghosts.",
		"Gewand einer königlichen Banshee\nDieses Gewand soll vor bestimmten Geistern schützen."
	],
	"litem bansheejfighter_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheejfighter_2": [
		"3965394e1108cd52caf1bbe820841f9d349ddf7009f95c13c9c53dc804a59db6",
		"Mighty royal banshee's robe\nThis robe is said to protect against any ghost.",
		"Gewand einer mächtigen königlichen Banshee\nDieses Gewand soll vor jedem Geist schützen."
	],
	"litem bansheejfighter_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheejmage_1": [
		"dd7d0118bbb20e492566e78167ea7e8c2794a5c437e78972b26aaf4a1fd795b8",
		"Royal banshee's stone\nThis stone is believed to protect a home from evil magic.",
		"Stein einer königlichen Banshee\nDieser Stein soll das Haus vor böser Magie schützen."
	],
	"litem bansheejmage_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bansheejmage_2": [
		"66269ddd6fdfeae7ef08bdc151e449e788d227307decfe64e58215ff54142f45",
		"Strong royal banshee's stone\nThis stone is believed to protect a home from all evil magic.",
		"Stein einer starken königlichen Banshee\nDieser Stein soll das Haus vor jeder bösen Magie schützen."
	],
	"litem bansheejmage_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem bat_1": [
		"81c7f3af7998ff8252443099c7c1ba46130ff7da969ac22f0e81a205a8c8df80",
		"Wings of small bat\nA provident man may find some uses for the wings' leather.",
		"Flügel der kleinen Fledermaus\nEin vorausschauender Mann könnte die Lederflügel sicher gebrauchen."
	],
	"litem bat_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem batblack": [
		"397c5fd5afb02ca5e47d3dd7e0c7915429435527d1dbb5605b2ed726f3c866d1",
		"Wings of black fox-bat\nThey say Witches buy them to make their potions...",
		"Flügel der schwarzen Wolfs-Fledermaus\nMan sagt, dass Hexen sie für ihre Zaubertränke kaufen..."
	],
	"litem batblack ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem batred_1": [
		"81c7f3af7998ff8252443099c7c1ba46130ff7da969ac22f0e81a205a8c8df80",
		"Wings of small bat\nA provident man may find some uses for the wings' leather.",
		"Flügel der kleinen Fledermaus\nEin vorausschauender Mann könnte die Lederflügel sicher gebrauchen."
	],
	"litem batred_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem batred_2": [
		"40ec2e60351fc8f44f5a415d1490f9ba7fae43374412238342d2280c5a46e875",
		"Bat wings\nThey can fetch you a few coins in the shop. Anything at all is useful.",
		"Fledermausflügel\nIm Laden bringen die sicher ein paar Münzen. Könnte nützlich sein."
	],
	"litem batred_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem batred_3": [
		"27021b95c91575c0a6980c3eaa960e63ecd1dfee9e887f4baf7230f55fcc7f52",
		"Wings of large bat\nIts leather has various domestic uses, so it can fetch you a few coins in the shop.",
		"Flügel der großen Fledermaus\nFür das Leder gibt es verschiedene Verwendungen, daher bekommt man beim Händler dafür bestimmt ein paar Münzen."
	],
	"litem batred_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem batred_4": [
		"0695806f3dcff926511f18feb5e3c3036f2aea6b6e5bd18a6d1b5dc604cc667c",
		"Giant bat wings\nThe skin is stronger and there is more of it, so it can earn good money.",
		"Riesenfledermausflügel\nDie Haut ist fester und größer, also kann man gut daran verdienen."
	],
	"litem batred_4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem beholderred": [
		"c930ab94ba3aec23872f73659ebbf949e5257f1ce8db1d2ccbd67f98a856013e",
		"Eye of young Red Evileye\nA valuable trophy - you are lucky!",
		"Auge des jungen roten Bösauges\nEine kostbare Trophäe - welch ein Glück!"
	],
	"litem beholderred ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem beholdersimple": [
		"53864dbdf830257cdf18c6fba81496cc74b39d1d9be979964f05f915f2503ffc",
		"Evil eye's eye\nAn evil eye's eye is said to bring good luck.",
		"Auge eines bösen Auges\nDas Auge eines bösen Auges soll Glück bringen."
	],
	"litem beholdersimple ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem beholderyellow_1": [
		"58a8ed6fad0b9f79511c84498fef5fef7e96b74495f5f708333db41bd1190fcf",
		"Eye of young Green Evileye\nThey say the eye of Evileye brings luck, so you can always sell it.",
		"Auge des jungen grünen Bösauges\nMan sagt, das Auge eines Bösauges bringt Glück, man kann es also gut weiterverkaufen."
	],
	"litem beholderyellow_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem doggray": [
		"55efa365b3355bf9385b864c39fbb3dceeaba3bf8905049aef526ab065a5804b",
		"Dog tail\nMakes a good collar.",
		"Hundeschwanz\nDaraus kann man einen guten Kragen machen."
	],
	"litem doggray ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem dogred": [
		"55efa365b3355bf9385b864c39fbb3dceeaba3bf8905049aef526ab065a5804b",
		"Dog tail\nMakes a good collar.",
		"Hundeschwanz\nDaraus kann man einen guten Kragen machen."
	],
	"litem dogred ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem elementalice1": [
		"cac1ff6917413e191b5b030cbb4eeb65ff5e68359c366912ea72c559f201eecf",
		"Crystal of cold\nUsed for keeping cellars cool in summer.",
		"Frostkristall\nDamit hält man im Sommer den Keller kühl."
	],
	"litem elementalice1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem elementalice2": [
		"4ad4f7f77382ac8c12c0c44530fed178c4fe107dda48e0fd28e2927f23e74dc1",
		"Large crystal of cold\nUsed for transporting meat and other products in summer.",
		"Großer Frostkristall\nFür den Transport von Fleisch und anderen Gütern im Sommer."
	],
	"litem elementalice2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem elementallava": [
		"448ca2a117f7fb4f51e767c4843fc27ab400c728a2f092268c77bb5ac55ac43e",
		"Crystal of warmth\nJust the thing to warm the bed for old people or for the sick.",
		"Wärmekristall\nDamit wärmt man das Bett für alte oder kranke Menschen."
	],
	"litem elementallava ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem elementallava_1": [
		"0d36727ac906e77a02832a0aa608aadfdba5d97d69c55bfb7058d5fab41c49d1",
		"Small crystal of warmth\nGood for warming wine or soup.",
		"Kleiner Wärmekristall\nDamit wärmt man Wein oder Suppe."
	],
	"litem elementallava_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem elementallava_2": [
		"448ca2a117f7fb4f51e767c4843fc27ab400c728a2f092268c77bb5ac55ac43e",
		"Crystal of warmth\nJust the thing to warm the bed for old people or for the sick.",
		"Wärmekristall\nDamit wärmt man das Bett für alte oder kranke Menschen."
	],
	"litem elementallava_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem foxtail1": [
		"09968b6f2c3cdd1acc4c03b287d22931fcc8c9dde98ad99257f525b0b33c5804",
		"Fox tail\nIt will do for a small collar.",
		"Fuchsschwanz\nDas reicht für einen kleinen Kragen."
	],
	"litem foxtail1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem foxtail2": [
		"9980d4663d7131ccece19b8d514cc707118c79b183061bdfdf20107be63ee3e5",
		"Large fox tail\nA large tail makes a fine collar.",
		"Großer Fuchsschwanz\nAus einem großen Schwanz wird ein schöner Kragen."
	],
	"litem foxtail2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem gepard_1": [
		"ce3b0dd96aadaf030cf66d6e050a7e51746572551438ff7abd4a911c5a3ee7c5",
		"Young cheetah hide\nA beautiful hide, but too small and unsuitable for armour.",
		"Haut eines jungen Geparden\nEine schöne Haut, aber zu klein und für Rüstungen ungeeignet."
	],
	"litem gepard_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem gepard_2": [
		"d1269b5a047fd23e7e8ae370243e2eb5fb8e2ed47b892dc7e32ca698103a836b",
		"Adult cheetah hide\nA hide to show off to the poor.",
		"Haut eines ausgewachsenen Geparden\nMit dieser Haut kann man vor den Armen angeben."
	],
	"litem gepard_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem gepard_3": [
		"158d97377126371c22ed5858e07df29c0aa2f8c76750b719b857ddc7bb556c54",
		"Mature leopard hide\nA townsman could decorate his home with this hide.",
		"Haut eines alten Leoparden\nMit dieser Haut könnte ein Stadtbewohner sein Heim schmücken."
	],
	"litem gepard_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinarcher1": [
		"75e3d2657c3d4e82b727ddacf8c6fa681c8ea463dc39fa5561e98b5ee0b569ad",
		"Goblin sling from thin leather\nThis leather can no longer be used to make things. But you can use it for patching!",
		"Goblinschleuder aus dünnem Leder\nAus diesem Leder kann man nichts mehr herstellen. Aber zum Flicken ist es noch zu gebrauchen!"
	],
	"litem goblinarcher1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinarcher2": [
		"58076e67b51fc5a06258bd6a5114fe44675dcdd3683daa978bb0677c1dcf0f3c",
		"Goblin sling from tough leather\nOnly good for patches!",
		"Goblinschleuder aus starkem Leder\nNur für Flicken zu gebrauchen!"
	],
	"litem goblinarcher2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinarcher3": [
		"bb86c4253b8f65f5aca5dec94aef8824af22975eb5a4e404974c1fd787b5f634",
		"Goblin sling from hard leather\nThick leather clothes need thick leather patches!",
		"Goblinschleuder aus hartem Leder\nKleidung aus dickem Leder braucht Flicken aus dickem Leder!"
	],
	"litem goblinarcher3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinfighter1": [
		"83bef62325695255a76741f0e952bc71adb6e082de87e4fb290249b4750a7b67",
		"Old Goblin pike\nA useless piece of junk. Throw away the head and burn the wood.",
		"Alter Goblinspieß\nZu nichts zu gebrauchen. Die Spitze sollte man wegwerfen und das Holz verbrennen."
	],
	"litem goblinfighter1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinfighter2": [
		"b1f6709dc488c9a83b8db8b4cd665af5dde4982c2dce0a5df6becd6bae23bbf6",
		"Goblin pike\nJust firewood, really.",
		"Goblinspieß\nNur als Feuerholz zu gebrauchen."
	],
	"litem goblinfighter2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem goblinfighter3": [
		"4059d4f15f8cc56ade342a893eb4bce07cbc38de75165c4ec88bfd0b3a8e1e93",
		"New Goblin pike\nBurns well, otherwise useless.",
		"Neuer Goblinspieß\nBrennt gut - aber mehr auch nicht."
	],
	"litem goblinfighter3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem hyena_1": [
		"8fcb088bcfd1f5c33910e12bbc06f9c9d09e4e43ad2e8631f33ed40397121aed",
		"Ears of small hyena\nThere is a reward for killing hyenas, so any merchant would pay you for this trophy.",
		"Ohren der kleinen Hyäne\nFür das Töten von Hyänen gibt es eine Belohnung, also wird jeder Händler für diese Trophäe bares Geld bezahlen."
	],
	"litem hyena_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem hyena_2": [
		"31b365c9bd536b4f0fa4ee849b24cead85c195af40111335e2ec11fec88e3574",
		"Ears of hyena\nThere is a reward for killing hyenas, so any merchant would pay you for this trophy.",
		"Ohren der Hyäne\nFür das Töten von Hyänen gibt es eine Belohnung, also wird jeder Händler für diese Trophäe bares Geld bezahlen."
	],
	"litem hyena_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem hyena_3": [
		"1a4b820058e4a723c52a297ba44904a6299efee3c153fb1f66fb10a9c78f8443",
		"Ears of large hyena\nThere is a reward for killing hyenas, so any merchant would pay you for this trophy.",
		"Ohren der großen Hyäne\nFür das Töten von Hyänen gibt es eine Belohnung, also wird jeder Händler für diese Trophäe bares Geld bezahlen."
	],
	"litem hyena_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_armor": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_armor ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_quick_item": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_quick_item ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_weapon": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem instruction_weapon ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem jzombie_1": [
		"b4fbe2fb84c023e3688742e173d74cd49995503d27dac152e7a962bb0c9478f9",
		"Ominous amulet\nThis is a bad thing, humans should leave it alone! Sell it...",
		"Geheimnisvolles Amulett\nMenschen sollten davon lieber die Finger lassen! Am besten verkauft man es gleich wieder..."
	],
	"litem jzombie_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem jzombie_2": [
		"6600e73138ff09959b1f6ed27e58d3a419c887f3e0b9b9e533e4e966d05655ad",
		"Strong ominous amulet\nThis is a bad thing, humans should leave it alone! Sell it...",
		"Starkes geheimnisvolles Amulett\nMenschen sollten davon lieber die Finger lassen! Am besten verkauft man es gleich wieder..."
	],
	"litem jzombie_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem kokos": [
		"c018ae51792a98599f550673bb68ab815d8bfdc2fe168d317bfb8b33a4e3e9a4",
		"Coconut\nSuch a large nut will fetch plenty of money.",
		"Kokosnuss\nEine so große Nuss bringt viel Geld ein."
	],
	"litem kokos ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem material": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem material tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem material troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem material troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem money": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem money ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem mushroom1": [
		"8f2700639f97c3e7a038a086013fe822e24ffaee05c19a52e82585f70b344cf6",
		"Filling mushroom\nSlippery, but filling...",
		"Sättigender Pilz\nGlitschig, aber sättigend ..."
	],
	"litem mushroom1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem mushroom2": [
		"043e7ff99d04fbdac6f8114eb99e6fb23d2c4711002420747d9cd4d5b66a3bcd",
		"Tasty mushroom\nA mushroom like this can fetch a handsome sum.",
		"Schmackhafter Pilz\nEin solcher Pilz kann eine hübsche Summe einbringen."
	],
	"litem mushroom2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem prototype": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem prototype ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rat_1": [
		"e6cc17671a07c5bd65d74f306a0239919fa05d22c5d0416dde5a3c4047f3673e",
		"Small rat tail\nDried and salted, these make an excellent snack with ale!",
		"Kleiner Rattenschwanz\nGetrocknet und gesalzen schmecken sie hervorragend zum Bier!"
	],
	"litem rat_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rat_2": [
		"c90ceb247ab54746f937dd423a63e4efc8e0b696c74eff77481581cd3a4dd9ad",
		"Rat tail\nDried and salted, they taste good washed down with a glass of ale.",
		"Rattenschwanz\nSolche getrockneten und gesalzenen Knabbereien passen bestens zum Bier."
	],
	"litem rat_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rat_3": [
		"e43243e6481a3ddc7693b5baffc5c12d6cc9da97e862e4b3cce3178771fa4466",
		"Large rat tail\nDried and salted, this would go very well with a mug of beer!",
		"Großer Rattenschwanz\nGetrocknet und gesalzen schmecken die hervorragend zum Bier!"
	],
	"litem rat_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rat_4": [
		"a0dcb56e60253c586311c7f1596959193b321606bed5c4763b6ef93232b3d8dc",
		"Small rat tail\nRat tail soup is the favourite dish of the poor.",
		"Kleiner Rattenschwanz\nRattenschwanzsuppe ist das Leibgericht der Armen."
	],
	"litem rat_4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rat_5": [
		"314b8edcb861fa0a2db6ac0004af828b6053ee61cf1dda4f500740cc74f27b57",
		"Rat tail\nYou can make a strong rope out of dried rat tails.",
		"Rattenschwanz\nAus getrockneten Rattenschwänzen kann man robuste Seile spinnen."
	],
	"litem rat_5 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rune": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem rune ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem shadow": [
		"96657ce1c8f7cd7ce74061e4dc647606d4f1c0060892915d6cbf8f3417c1de6e",
		"Black sorcerer claw\nThey say when restless souls leave killed shadows, they settle in these claws. Magicians will always buy them.",
		"Schwarze Hexerklaue\nMan sagt, wenn ruhelose Seelen getötete Schatten hinterlassen, dann lassen sie sich hierin nieder. Magier kaufen sie daher immer gern."
	],
	"litem shadow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem spider_1": [
		"26cfc04c3ff40ef8fd3b00ea51753cbcdb0285c5148982353df93f4c73cde136",
		"Sting of young spider\nIn crushed form these are used to make drugs and paints.",
		"Stachel einer jungen Spinne\nIn Pulverform werden sie verwendet, um Heilmittel und Farbe herzustellen."
	],
	"litem spider_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem spider_2": [
		"ac64d77714e4a27b22032566392b19e9c3ad8e0fd6ca0b3fb564ce782906c1f2",
		"Spider sting\nThey are cheap but are widely used, so they are always in demand.",
		"Spinnenstachel\nSie sind billig, werden aber häufig verwendet, weshalb die Nachfrage immer sehr groß ist."
	],
	"litem spider_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem spider_3": [
		"dc9402f0513cede22a1ea076aaf18ebc4350c112a0d20546ca3ec84e98c789bb",
		"Big spider sting\nCrushed spider stings are popular among aging noblemen - to restore certain youthful properties.",
		"Großer Spinnenstachel\nZerstoßene Spinnenstachel sind bei alternden Adligen beliebt - sie sollen verjüngend wirken."
	],
	"litem spider_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem succubusgreen": [
		"440c4cbdabe7935c564f7c3400fd8b0b5642db4c98307915cd39a34e4e464187",
		"Adult Harpy head\nThis can be bought for a practical joke. It would be an expensive one, though.",
		"Kopf der erwachsenen Harpyie\nKann für einen Streich benutzt werden. Wäre allerdings ein ziemlich teurer Spaß."
	],
	"litem succubusgreen ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem succubusj": [
		"440c4cbdabe7935c564f7c3400fd8b0b5642db4c98307915cd39a34e4e464187",
		"Adult Harpy head\nThis can be bought for a practical joke. It would be an expensive one, though.",
		"Kopf der erwachsenen Harpyie\nKann für einen Streich benutzt werden. Wäre allerdings ein ziemlich teurer Spaß."
	],
	"litem succubusj ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem succubusred": [
		"5243332ddafd78b9e4668191263be1bf1004893d9071c932fc217bbbaed20825",
		"Head of adult red harpy\nA head like this on a stake outside the settlement gates will scare off other harpies.",
		"Kopf einer erwachsenen roten Harpyie\nEin solcher Kopf auf einem Pfahl vor dem Siedlungstor schreckt andere Harpyien ab."
	],
	"litem succubusred ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem tigers": [
		"10015b6e97325366299fdc438373876b0966085dc223a7644a6406e0d0d18010",
		"Tiger hide\nAn intact giant tiger hide is very valuable.",
		"Tigerhaut\nEine unversehrte Riesentigerhaut ist sehr wertvoll."
	],
	"litem tigers ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad2_j": [
		"d633b34c73257b08ab2344e610c763958eea1ccdac00196d34c5a3de9edb7cf6",
		"Large grey toad legs\nThe meat from a large grey toad's legs is considered a delicacy.",
		"Große graue Krötenbeine\nDas Fleisch großer grauer Krötenbeine gilt als Delikatesse."
	],
	"litem toad2_j ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad_1": [
		"3b5898d7beafd8bb7f799156dc6e26c9bbc611089325c2e520e0196a42bee042",
		"Small Toad legs\nToads spit poison, true, but the meat is edible tasty, so there is always a demand for it.",
		"Kleine Krötenbeine\nKröten verspritzen zwar Gift, aber ihr Fleisch ist essbar. Daher gibt es immer eine Nachfrage."
	],
	"litem toad_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad_2": [
		"6500d02f1ff109a2f3ddb0c3657731a62b9ea74ad239e5c92ac2a7e4f4f2b21b",
		"Toad legs\nThey pay good money for those: a good addition to a family dinner table.",
		"Krötenbeine\nDafür erhält man gutes Geld: ein Leckerbissen an jedem Tisch."
	],
	"litem toad_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad_3": [
		"5151d6a59680f60c6bbda2862e145af837af8cabad2ec1926990ff7e48401704",
		"Fat toad legs\nAn adult toad's legs have more meat, and it is tenderer, so they fetch a good price.",
		"Dicke Krötenbeine\nDie Beine einer ausgewachsenen Kröte haben mehr und zarteres Fleisch und erzielen einen guten Preis."
	],
	"litem toad_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad_4": [
		"506755d5b0fb63e56530958d84015839e2c98fe0e5942e641a1dd276f828b99c",
		"Fat Toad legs\nA mature toad's tender legs are an expensive delicacy.",
		"Fette Krötenbeine\nDie zarten Beine einer ausgewachsenen Kröte sind eine teure Delikatesse."
	],
	"litem toad_4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem toad_j": [
		"48250d7d6c369d0d0386ec5c5807a0039dfe0aa1aa8525d413a809364575da4a",
		"Grey toad legs\nThe meat from a small grey toad's legs is edible but unpleasant.",
		"Graue Krötenbeine\nDas Fleisch kleiner grauer Krötenbeine ist essbar, schmeckt aber schlecht."
	],
	"litem toad_j ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem unicornblack": [
		"a570f2000f0e701b64cd1ba48cc8ae131b18ddea82e5dd576f199dedcefdfc46",
		"Horn of Black Unicorn\nA very rare thing, and a good antidote too.",
		"Horn eines schwarzen Einhorns\nSehr selten und außerdem ein gutes Gegengift."
	],
	"litem unicornblack ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem unicornwhite": [
		"21c0a92505410924895066da18eef4ed1a0209002f2a3c4efd3ed3aa55e493af",
		"Horn of White Unicorn\nThere'll be no problem selling such a prize!",
		"Horn eines weißen Einhorns\nDafür besteht stets gute Nachfrage!"
	],
	"litem unicornwhite ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem willowisp_1": [
		"a21735f874c9c5c32e0a19338b4fad9f619145c9d33f19acadb5ea32c1d8249f",
		"Small luminous stone\nUsed for lighting homes, instead of candles.",
		"Kleiner leuchtender Stein\nWird statt Kerzen oder Lampen zur Beleuchtung verwendet."
	],
	"litem willowisp_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem willowisp_2": [
		"918c15413e8f215fec73cb06b67a0954101c51c7f9eccf36479bc3c78d7978ce",
		"Luminous stone\nUsed by the villagers for lighting their homes.",
		"Leuchtender Stein\nDie Dörfler beleuchten damit ihre Häuser."
	],
	"litem willowisp_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem willowisp_3": [
		"ddb242ad352b4a28a4ef7b3f70d60e8c7676b1b079ea3a3aefdcccad4769e3ae",
		"Large luminous stone\nUsed by the villagers for street lighting.",
		"Großer leuchtender Stein\nDie Dörfler beleuchten damit ihre Straßen."
	],
	"litem willowisp_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfgray_1": [
		"dc2ea3530546d600137026e46fafbd6c439d17a059bdcf36bd5aae6e7c708555",
		"Wolf cub fangs\nThey are inexpensive, but you can always sell them.",
		"Fänge des Wolfsjungen\nSie sind nicht teuer, aber leicht zu verkaufen."
	],
	"litem wolfgray_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfgray_2": [
		"e947421f081d1c10a35e4f3e0735c062a24ab3211d6abb15f2427fe695c47c01",
		"Wolf fangs\nThey are in demand as decoration material.",
		"Wolffänge\nSie werden als Schmuck durchaus geschätzt."
	],
	"litem wolfgray_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfgray_3": [
		"b41c678b59bedf1393dd68dcc034114223276361321ff59ab97d4270ec94ec47",
		"Large wolf fangs\nThe bigger the fangs, the more expensive the necklace.",
		"Große Wolffänge\nJe größer die Fänge, desto teurer die Kette."
	],
	"litem wolfgray_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfhead1": [
		"3b277ef12a236805255cbf9de1dc211df76cab1cf249cae9faa81a7d7bc0b26c",
		"Brown wolf's head\nKilling wolves earns a good bounty.",
		"Kopf eines braunen Wolfes\nFür erlegte Wölfe gibt es eine gute Belohnung."
	],
	"litem wolfhead1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfhead2": [
		"0e82d1c8cec28eab7b197da09186f21122ac5206065413a7ab62bf92f7692bcd",
		"Black wolf's head\nKilling black wolves pays very well.",
		"Kopf eines schwarzen Wolfes\nFür erlegte schwarze Wölfe wird sehr gut bezahlt."
	],
	"litem wolfhead2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfwhite_1": [
		"edccaf9637534f947bcb182d4d658be48953cae6dd1f6c363722f626a5c1cdec",
		"Young White Wolf fangs\nA young white wolf is a more prestigious trophy than a young grey one.",
		"Fänge eines jungen weißen Wolfs\nEin junger weißer Wolf ist eine angesehenere Jagdbeute als ein junger grauer."
	],
	"litem wolfwhite_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfwhite_2": [
		"7c074476b75f10bdb779da43119733d686b9425b73232923577cebb83764e10c",
		"White Wolf fangs\nA necklace made of those will be more expensive than one made of common wolves' fangs.",
		"Fänge des weißen Wolfs\nEine solche Kette wäre teurer als eine aus den Fängen eines gewöhnlichen Wolfs."
	],
	"litem wolfwhite_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfwhite_3": [
		"8a34ddf3546fffd0c5f7eee3d5d5199f5cf91ff91471d9ff75e4e1e1b97723b2",
		"Adult white wolf's fangs\nA necklace of these fangs is expensive but beautiful.",
		"Fangzähne eines ausgewachsenen weißen Wolfes\nEine Kette aus diesen Fangzähnen ist teuer, aber schön."
	],
	"litem wolfwhite_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem wolfwhite_4": [
		"21d4e676432cb954db0f465e4f26dfb4529a84e3d89d7797f39bfa50c490317e",
		"Large White Wolf fangs\nThe most expensive decorations are made of these.",
		"Fänge des großen weißen Wolfs\nDaraus werden die teuersten Schmuckstücke hergestellt."
	],
	"litem wolfwhite_4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"litem zombie_1": [
		"ec687f036bb65e1f5d3b453542726f2607b769d72204882495335ae695e8900e",
		"Simple ominous amulet\nThis is a bad thing, humans should leave it alone! Sell it...",
		"Einfaches geheimnisvolles Amulett\nMenschen sollten davon lieber die Finger lassen! Am besten verkauft man es gleich wieder..."
	],
	"litem zombie_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"material adamantium": [
		"968e9bd3f97d071b93f2596f9bd00d1765269fa1b032b0cb6df1875fe1ed2454",
		"Adamantite\nVery good material for making weapons and armor.",
		"Adamantit\nSehr gutes Material für die Herstellung von Waffen und Panzerung."
	],
	"material bronze": [
		"f2315e1effb6dee807b1db599cbf46438eed6f79a14560562a27364dcc5b3aa1",
		"Bronze\nThe cheapest and softest metal.",
		"Bronze\nDas billigste und weichste Metall."
	],
	"material burned_bones": [
		"63641171c24f9ed9055f1fa74621bc841ac299be844f225fecfc718ba5c53cc6",
		"Hard bone\nHard bone weapons can be made both sharper and stronger than tough bone ones.",
		"Harter Knochen\nWaffen aus harten Knochen sind nicht nur schärfer, sondern auch robuster als Waffen aus festen Knochen."
	],
	"material cotton": [
		"43deee62c1c573f85470ec81ab2372976ebad15fa4e3e2fc02e489d5062eae48",
		"Cotton\nCotton is not much more expensive than rough fabric, but it does looks better.",
		"Baumwolle\nBaumwolle ist nicht viel teurer als grobes Gewebe, sieht aber viel besser aus."
	],
	"material decayed_bones": [
		"a7cacd613a54fe12688f6f8ef80b6981bee68d8eda281b444266684fa8dcca33",
		"Thin bone\nThis material is easy to get, but it is practically impossible to make decent weapons out of it.",
		"Dünner Knochen\nDieses Material ist ohne weiteres zu bekommen, aber man kann keine anständigen Waffen daraus machen."
	],
	"material diamond": [
		"116fc21dcef734c05851469c847c2358be3834742cbe4feca606d7204f61967d",
		"Diamond\nOnly the best craftsmen of the bygone race knew the secret of processing this material.",
		"Diamant\nNur die besten Handwerker des ausgestorbenen Volkes wussten, wie dieses Material verarbeitet werden muss."
	],
	"material dragon_black": [
		"73c4c4e5e0a65a1eb0aa7083cd4c86e635907d3a20af2e6dc294833568c01253",
		"Blue Dragon hide\nDragon hide makes strong leather armor, with good protection against lightning strikes.",
		"Blaue Drachenhaut\nAus blauer Drachenhaut fertigt man starken Lederschutz an, der gut gegen Blitze schützt."
	],
	"material dragon_black_bones": [
		"bfcb6c4942d534fe27db7a34ce88e1bfab0bd9aa81686901a84e366aa6395975",
		"Blue Dragon bone\nThe perfect material for bone weapons! But it is not at all easy to obtain…",
		"Blauer Drachenknochen\nDas perfekte Material für Knochenwaffen! Leider nicht leicht zu bekommen..."
	],
	"material dragon_green": [
		"8f884ee5c77d15d7862b99475271fb29572ad2597c23de43cbca9b32d8f6fbcb",
		"Green Dragon hide\nDragon hide makes strong leather armor, with good protection against acid.",
		"Grüne Drachenhaut\nAus grüner Drachenhaut fertigt man starken Lederschutz an, der gut gegen Säure schützt."
	],
	"material dragon_green_bones": [
		"0f2e5bf4f05a6fb13a797244bcac5c34fba2dacf3fddae1ff84244b71f2746e8",
		"Green Dragon bone\nGreat for constructing bone weapons.",
		"Grüner Drachenknochen\nFast perfekt für Knochenwaffen."
	],
	"material dragon_red": [
		"4f6bda264b98fc3b1e51efba7201611bbfc3cb6a18066c30f135e1a840d9cfa6",
		"Red Dragon hide\nDragon hide makes strong leather armor, with good protection against fire.",
		"Rote Drachenhaut\nAus roter Drachenhaut fertigt man starken Lederschutz an, der gut gegen Feuer schützt."
	],
	"material dragon_red_bones": [
		"1abd88bcbceff30f44184483feb580ed1365554e6bd58a1384da5152ab5ea9ee",
		"Red Dragon bone\nA very good material for bone weapons.",
		"Roter Drachenknochen\nSehr gutes Material für Knochenwaffen."
	],
	"material dry_bones": [
		"64cfdd406cac731b481be82d15815483d14a4efee4b6a5a8b1f3fc6d46b4d8b4",
		"Tough bone\nTough bone weapons can be honed sharper than thin bone ones..",
		"Fester Knochen\nWaffen aus festen Knochen können schärfer geschliffen werden als die aus dünnen."
	],
	"material granite": [
		"18d007da55d5e10b85f7970d15491449c5de8f642397f0930a1d3f854f57a753",
		"Granite\nHeavier and nicer looking than ordinary stone. Makes better weapons, too.",
		"Granit\nSchwerer und schöner als normaler Stein. Ist auch besser für Waffen geeignet."
	],
	"material iron": [
		"9b5d14a6699feee72554cd8412fcf50773c0964ef9ac23a6ffa6891c66cf2489",
		"Iron\nIron is better than bronze but inferior to other metals.",
		"Eisen\nEisen ist besser als Bronze, aber schlechter als andere Metalle."
	],
	"material lizard_black": [
		"f37f1d60686b3adadd0431ea628cec0dedb79189b215461584d1bbf13f64b569",
		"Mountain lizard hide\nRough, strong and reliable.",
		"Bergechsenhaut\nGrob, fest und zuverlässig."
	],
	"material lizard_blue": [
		"e90d2fe3374d125eb0a7d82ec2296ae87e0bbb4b626cbe206ad0babf2802a711",
		"Lake lizard hide\nThis hide can be made into dependable armour.",
		"Seeechsenhaut\nAus dieser Haut lässt sich zuverlässige Rüstung fertigen."
	],
	"material lizard_green": [
		"0a0a48f9dae94657ddd3ca089520709900e4f08cb41bf91937b87af7d842311d",
		"Forest lizard hide\nNot a very strong hide, but inexpensive.",
		"Waldechsenhaut\nKeine besonders feste Haut, aber günstig."
	],
	"material malachite": [
		"23910ed7674926a92d1393296a317943fd17eaf33bff18d50646cfab82a33e5e",
		"Obsidian\nThe best material for stone weapons capable of carrying powerful spells.",
		"Obsidian\nDas beste Material für Steinwaffen; kann mächtige Zauber aufnehmen."
	],
	"material meteoric": [
		"e63698033b45953d520e6c24b57d71b67f07defefcb9a811ad862eb651052449",
		"Meteorite\nThe strongest metal, ideal for making weapons or armour.",
		"Meteorit\nDas stärkste Metall, ideal zur Herstellung von Waffen und Rüstungen."
	],
	"material mithrill": [
		"b8fbe71eebd83427d01c444fc1e6874331b0b75856327010acb707d43514b5b8",
		"Mithrill\nLightweight, very hard metal. Mithrill objects are capable of carrying strong spells.",
		"Mithril\nLeichtes, sehr hartes Metall. Gegenstände, die daraus hergestellt wurden, können sehr mächtige Zauber aufnehmen."
	],
	"material ogre": [
		"7095216a72ea1bbf2cca8612ca819df873775a8fe4096c90cfd1f6271ec2c941",
		"Ogre hide\nOgres never part with this hide... while alive.",
		"Ogerhaut\nOger trennen sich niemals von dieser Haut ... zu Lebzeiten."
	],
	"material rock": [
		"20237c2155718dd2a3c1851769238bb28718eb205a31258261ae4d0e7ca4d1cd",
		"Stone\nOrdinary stone. Of course you can make weapons from it, but the quality would be rather poor.",
		"Stein\nGewöhnlicher Stein. Man könnte zwar Waffen daraus herstellen, aber die Qualität wäre ziemlich erbärmlich."
	],
	"material scrab_bones": [
		"6f0069750804ac273e0d31b0de7752de82dab513a69efa5cd6f04a798c045905",
		"Shell bones\nShell bone is not easy to come by. But the result is worth the effort!",
		"Panzerknochen\nAn Panzerknochen kommt man nicht so leicht heran. Aber es ist die Mühe allemal wert!"
	],
	"material silicon": [
		"93c88af1fa6a2ca8eb5271571ca9e8a8edf445bb355ec958bb40992005d1c05c",
		"Silicon\nA decent material for stone weapons.",
		"Silizium\nGutes Material für Steinwaffen."
	],
	"material silk_blue": [
		"9a0a677719240a29b45d8017498728bd0ffcf996aa6d434ecc8895651c2be8f1",
		"Silk\nThis is a most expensive fabric, valued not only for its appearance, but also for its durability.",
		"Seide\nDer teuerste Stoff, nicht nur aufgrund seiner Schönheit, sondern auch aufgrund der Lebensdauer."
	],
	"material silk_red": [
		"bd45986cde359e0883037420a437ff5b1849966854fb4c5fe699b513183b617d",
		"Wool\nWool fabric is strong and can even absorb a blow  (though not very well).",
		"Wolle\nWollstoff ist robust und kann sogar einen Hieb abmildern (wenn auch keinen allzu starken)."
	],
	"material steel": [
		"7a49893c3342489fa111885c3bf0cd8b84363277018fec8428ba859ece56215c",
		"Steel\nCommon steel.",
		"Stahl\nGewöhnlicher Stahl."
	],
	"material tanned_thin": [
		"4b6c9e2ae646e53db0c552d8c412150f46a32f75d460cf8a7f03e40854471eaf",
		"Hard leather\nThe best material for leather armor.",
		"Hartes Leder\nDas beste Material für Lederrüstungen."
	],
	"material thick": [
		"f24faf897d86e9cf9aca9ba4dadc276089915e35df3a21c19986c80cbc370688",
		"Tough leather\nCommon material for leather armor.",
		"Starkes Leder\nNormales Material für Lederrüstungen."
	],
	"material thin": [
		"4273b89d8f585dca342af6a881e065803e2ed82b7a5020ea8d71756da05d3f28",
		"Thin leather\nThe flimsiest and weakest material for making leather armor. Use it only when nothing better is available.",
		"Dünnes Leder\nDas dünnste und schwächste Material für Lederrüstungen. Sollte nur verwendet werden, wenn nichts Besseres da ist."
	],
	"material tiger_hide": [
		"b110dd6c399367141fffc6d4da432d011cf36937611f26a5b433ade129c888f1",
		"Tiger skin\nTiger skin is used for making beautiful and very hard armor.",
		"Tigerfell\nTigerfell wird für schöne und sehr robuste Panzerungen verwendet."
	],
	"material tiger_hide2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"material tiger_hide_white": [
		"01566340a91359db6ba2cf9d814dc53760dfe831498ae362732c5c5ef25abb1b",
		"Snow Tiger skin\nSnow Tiger skin is beautiful, strong, reliable... and expensive!",
		"Schneetigerfell\nSchneetigerfell ist schön, stark, robust… und teuer!"
	],
	"material troll_black": [
		"ed638f5484a54e01e12719005f3376b11857c97e7eda8cfb339356dd94a5a4d0",
		"Black Troll hide\nTroll hide makes very strong leather armor.",
		"Schwarze Trollhaut\nAus Trollhaut stellt man sehr starke Lederrüstungen her."
	],
	"material troll_blue": [
		"81b8f871d34df16df1796e3ee2ab6d8d18c9dd2eedcb14e3c08a8fd9a0a68c1d",
		"Blue Troll hide\nTroll hide makes very strong leather armor.",
		"Blaue Trollhaut\nAus Trollhaut stellt man sehr starke Lederrüstungen her."
	],
	"material troll_blue2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"material troll_green": [
		"c5624e34b9830a03de67034ffa7f2a656349fd0f0e2e0886386a6638af1a63fa",
		"Green Troll hide\nTroll hide makes very strong leather armor.",
		"Grüne Trollhaut\nAus Trollhaut stellt man sehr starke Lederrüstungen her."
	],
	"material troll_green2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"material wool": [
		"84d38dc889a1e867f14042ae05c7b40644797d38e50b3942f802f045a887bdbf",
		"Rough fabric\nThe cheapest fabric and lowest quality. Only very poor people wear such clothes.",
		"Grober Stoff\nDas billigste Gewebe der geringsten Qualität. Nur die ganz Armen tragen solche Kleider."
	],
	"modifier a0": [
		"e58a0074e45a78f96e1da7a3498f4dab5d353f1d5b2af3b45a9e656a12a1b418",
		"Slightly wider area\nAdds half the original spell area. A+",
		"Etwas größerer Wirkungsbereich\nVergrößert den ursprünglichen Wirkungsbereich um die Hälfte. F+"
	],
	"modifier a1": [
		"e4dcb9e4a8ee44547e6fd25772b76c868c13a7cb55a24ec99fded4f9a18c2b5c",
		"Extra Area\nDoubles the spell's initial coverage area.\nA+",
		"Vergrößerter Wirkungsbereich\nVerdoppelt den ursprünglichen Wirkungsbereich des Zaubers.\nWb1"
	],
	"modifier a2": [
		"d8f9fcab996bc93ca7af9aac10d1bc04261b8a162ef07f33aa7142dbe3e84663",
		"Ultra Area\nTriples the area covered by the spell.\nA++",
		"Stark vergrößerter Wirkungsbereich\nVerdreifacht den ursprünglichen Wirkungsbereich des Zaubers.\nWb2"
	],
	"modifier c1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier c2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier c3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier c4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier c5": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier d0": [
		"b6c2feaeaa914f7cea0988c656c0df98bff696c656bcb720d9da5b1125016c31",
		"Extended duration\nAdds half the original spell duration. T+",
		"Verlängerte Wirkung\nVerlängert die ursprüngliche Wirkungsdauer um die Hälfte. D+"
	],
	"modifier d1": [
		"9699ddd9db6b847338af2f1111df6c808dddf55221994bc7d7fb189ede599b1c",
		"Extra Duration\nDoubles the spell's duration.\nD+",
		"Verlängerte Wirkungsdauer\nVerdoppelt die ursprüngliche Wirkungsdauer des Zaubers.\nD1"
	],
	"modifier d2": [
		"b4179bbc0748de4a188fa320df8b1a335e9163c778a784f401f92b1c60e804d5",
		"Ultra Duration\nTriples the spell's duration.\nD++",
		"Stark verlängerte Wirkungsdauer\nVerdreifacht die ursprüngliche Wirkungsdauer des Zaubers.\nD2"
	],
	"modifier e0": [
		"01d08f485f6af4ff0787ed566dbfe3eab4e626203e17d4db54503418901dccfc",
		"Minor enhancement\nAdds half the original spell effect. E+",
		"Kleine Verstärkung\nErhöht die ursprüngliche Zauberwirkung um die Hälfte. W+"
	],
	"modifier e1": [
		"b59351b873a8bf131a3e9ee042b4e84ef53640f37aa5a534f83038cb8c35b91a",
		"Extra Effect\nAdds the original spell effect again, doubling it. E++",
		"Verbesserte Wirkung\nVerdoppelt die ursprüngliche Zauberwirkung. W++"
	],
	"modifier e2": [
		"3a63a16395ff1bfe1ab5817848f1c5b92d3536d6c95cf763ea1220a800423d55",
		"Ultra Effect\nAdds twice the original spell effect, for three times the base effect. E+++",
		"Stark verbesserte Wirkung\nFügt das Doppelte der ursprünglichen Wirkung hinzu, insgesamt also die dreifache Grundwirkung. W+++"
	],
	"modifier e3": [
		"ffe1372b8302f275659bcff826bb8ff0583c800e7bf31ea119d9b6c8687cc34d",
		"Super enhancement\nEnhances the spell effect to its limit. E#",
		"Superverstärkung\nVerstärkt die Zauberwirkung bis zum Äußersten. W#"
	],
	"modifier ee0": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier ee1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier ee2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier ee3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier ee4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier ee5": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"modifier fe": [
		"ea60b6f98cb4daf04a9b04a30e73a0feb6a35c02a434cc0ddbc0fa5590b25034",
		"Enemy Filter\nThe spell will only affect the Magician's enemies.\n:En",
		"Gegner-Filter\nDer Zauber wirkt nur auf die Gegner des Magiers.\n:Gg"
	],
	"modifier ff": [
		"95678a4af3e4574a6572e9e613c211074f86a0d19e5ed334a070822d5ccf74d4",
		"Friend Filter\nThe spell will only affect the Magician's allies.\n:Fr",
		"Gruppen-Filter\nDer Zauber wirkt nur auf die Mitglieder der Gruppe des Magiers.\n:Fr"
	],
	"modifier fg": [
		"7e1448259187d030c30e0e2e058f48f028d457f9e3f9a212f550d0ee18b179fb",
		"Goblin Filter\nThe spell will only affect Goblins.\n:Go",
		"Goblin-Filter\nDer Zauber wirkt nur auf Goblins.\n:Go"
	],
	"modifier fh": [
		"2b40ecc74aa0a1fcf560a3f848806789d8e1d9cbe96a7babf0a3185fa902929a",
		"Human Filter\nThe spell will only affect humans.\n:Hu",
		"Menschen-Filter\nDer Zauber wirkt nur auf Menschen.\n:M"
	],
	"modifier fl": [
		"144aa7c00174a108ca2d54fbeabd9f550d8ca4feefdc2ab1636c9f08dcc0bae3",
		"Lizard Filter\nThe spell will only affect Lizards.\n:Dr",
		"Echsen-Filter\nDer Zauber wirkt nur auf Echsen.\n:E"
	],
	"modifier fo": [
		"23e1a8da261153184bb3d946fcb6148f45c8fd8b1991a52877b447d4f7d8fe00",
		"Orc Filter\nThe spell will only affect Orcs.\n:Or",
		"Ork-Filter\nDer Zauber wirkt nur auf Orks.\n:Or"
	],
	"modifier ic": [
		"936b6d6af73dbeab1402a5fd80b4e3cb9d0512df95330d128ef14551a245f723",
		"Item: Continuous\nYou can insert the spell into an object and it will be cast continuously, as long as the object has enough energy.\nIc",
		"Gegenstand: Permanent\nDer Zauber kann auf ein Objekt übertragen werden. Er wird dann so lange aufrechterhalten, solange das Objekt über genügend Energie verfügt.\nG-p"
	],
	"modifier im1": [
		"a0c97eec2d61c29229f4503523ce3ebb369c0211a0992f56ffc06a061b00f493",
		"Item: Extra Energy\nDecreases the amount of energy used by the inserted spell.\nP-",
		"Gegenstand: Verbessertes Potential\nReduziert die Energie, die von dem auf das Objekt übertragenen Zauber benötigt wird.\nPt1"
	],
	"modifier im2": [
		"ba0670a296acbf36aec3ec03888b21217b024ec6ddf0610b617b51610801505d",
		"Item: Ultra Energy\nSignificantly decreases the amount of energy used by the inserted spell.\nP--",
		"Gegenstand: Stark verbessertes Potential\nReduziert deutlich die Energie, die von dem auf das Objekt übertragenen Zauber benötigt wird.\nPt2"
	],
	"modifier ir1": [
		"5a27a0f6345d05bf82d1d1fb7f9776bd96a75c7206cb187b5bd6775ff71642d7",
		"Item: Extra Regeneration\nSpeeds up energy regeneration in the object carrying this spell.\nG+",
		"Gegenstand: Beschleunigte Regeneration\nVerringert die Zeit, die das Objekt mit diesem Zauber benötigt, um die verbrauchte Energie wiederherzustellen.\nRg1"
	],
	"modifier ir2": [
		"fe7da532a446adbc0085c17a5b8ec2a537da3d7e665c811f0e1548250d219e89",
		"Item: Ultra Regeneration\nSignificantly speeds up energy regeneration in the object carrying this spell.\nG++",
		"Gegenstand: Stark beschleunigte Regeneration\nVerringert deutlich die Zeit, die das Objekt mit diesem Zauber benötigt, um die verbrauchte Energie wiederherzustellen.\nRg2"
	],
	"modifier it": [
		"0b131d2b5b09233dc8c7c2a541c4df8a72a0918cdb2ef828a5fbe359171ef079",
		"Item: Trigger\nYou can insert the spell into an object. The spell will be triggered when the object is used or struck.\nIt",
		"Gegenstand: Auslösbar\nDer Zauber kann auf ein Objekt übertragen werden. Er wird angewendet, wenn das Objekt benutzt oder getroffen wird.\nG-a"
	],
	"modifier m1": [
		"ac6ad445b44ec6cc6e68ce79ae8229b065f7e42fa93d0172d3b8f037ef148494",
		"Extra Energy\nDecreases the amount of stamina used when casting the spell.\nM-",
		"Verbessertes Potential\nReduziert die Energie, die benötigt wird, um den Zauber auszusprechen.\nP1"
	],
	"modifier m2": [
		"745a81779f71016de0b4c581b20d44801b2fe753abadfa91ab5c1c1f95c26e43",
		"Ultra Energy\nSignificantly decreases the amount of stamina used when casting the spell.\nM--",
		"Stark verbessertes Potential\nReduziert deutlich die Energie, die benötigt wird, um den Zauber auszusprechen.\nP2"
	],
	"modifier r0": [
		"b5a360fde72ccb542f8cf666e82d5888b746e9f55fdf79db04b23f2f494575cb",
		"Extended range\nAdds half the original spell range. R+",
		"Erhöhte Reichweite\nErhöht die ursprüngliche Reichweite um die Hälfte. R+"
	],
	"modifier r1": [
		"7c99cfa964ea38a318086601ec2451c341ed27800b6e579ac4e5ce1a0fb7374d",
		"Extra Range\nDoubles the spell's range.\nR+",
		"Vergrößerte Reichweite\nVerdoppelt die ursprüngliche Reichweite des Zaubers.\nRw1"
	],
	"modifier r2": [
		"6fbdeee536a59f5497240b0725519d5ce9490e5757af8c7c60896d8df07837ff",
		"Ultra Range\nTriples the spell's range.\nR++",
		"Stark vergrößerte Reichweite\nVerdreifacht die ursprüngliche Reichweite des Zaubers.\nRw2"
	],
	"modifier t1": [
		"2a28f3a178b6ac524c24de48c95bbc4ce416f729a150e2a767a1086f63b49a26",
		"Extra Targets\nThe spell will also affect another target nearby.\nT+",
		"Zusätzliches Ziel\nDer Zauber wirkt sich auch auf ein weiteres in der Nähe befindliches Ziel aus.\nZ+1"
	],
	"modifier t2": [
		"3f6fe475e73b3c9b6c35ca85b8436437f44511c0defe6c4c9f4d9b20e75d5e29",
		"Ultra Targets\nThe spell will also affect two other targets nearby.\nT++",
		"Zwei zusätzliche Ziele\nDer Zauber wirkt sich auch auf zwei weitere in der Nähe befindliche Ziele aus.\nZ+2"
	],
	"perk astral": [
		"5956b4e678933149544b89e1e2591a14725e4475d9fbf1f6defa8aff56152da2",
		"Astral Magic\nThis skill allows you to create and use spells of the Astral Magic school. These are very different in nature - e.g. Healing or Paralysis. Magic abilities depend on skill in the particular magic school (Skill) and the character's Intelligence.",
		"Astralmagie\nEine Fertigkeit, die die Erschaffung und Anwendung von Zaubern der Schule der Astralmagie ermöglicht. Die Zauber sind in ihrer Wirkung sehr unterschiedlich - von der Heilung bis zur Paralyse. Die magischen Fähigkeiten eines Charakters hängen von seiner Fertigkeit in einer besonderen Schule und von seiner Intelligenz ab."
	],
	"perk elemental": [
		"7812c9e965d6ac17340b537f6ba32eb4033220f011ebf4dc69317abf6928b48d",
		"Elemental Magic\nA skill which allows you to create and use spells of the Elemental Magic school. Most destructive spells are in this category - e.g. Fireball. Magic abilities depend on the skill in a particular magic school (Skill) and the character's Intelligence.",
		"Elementarmagie\nEine Fertigkeit, die die Erschaffung und Anwendung von Zaubern der Schule der Elementarmagie ermöglicht. Dazu gehören sehr mächtige Zauber, zum Beispiel der Feuerball. Die magischen Fähigkeiten eines Charakters hängen von seiner Fertigkeit in einer besonderen Schule und von seiner Intelligenz ab."
	],
	"perk sense": [
		"831dcb84de8f4814a881641963712820ec8b2aa552ed622f95c1e410dc40287a",
		"Sensory Magic\nA skill which allows the character to create and use spells of the Sensory Magic school. These are mainly informational spells - e.g. Eagle Sight. Magic abilities depend on the skill in a particular magic school (Skill) and the character's Intelligence.",
		"Magie der Sinne\nEine Fertigkeit, die die Erschaffung und Anwendung von Zaubern der Schule der Magie der Sinne ermöglicht. Durch diese Zauber gelangt man zumeist an neue Informationen - zum Beispiel mit dem Zauber Adlerauge. Die magischen Fähigkeiten eines Charakters hängen von seiner Fertigkeit in einer besonderen Schule und von seiner Intelligenz ab."
	],
	"pers bz11g dog": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human archer f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human chieftan m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human fighter1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human fighter2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human fighter3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human fireman m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human mage f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human master m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human shava f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human sheriff m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker3 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker4 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human talker5 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz11g human warrior m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz12g human daughter f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz12g human witch f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz13g dragonblue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz14g golemhorizontal": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz14g golemvertical": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz14g jun girl f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz14g rick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz1h human clerk m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human archer1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human fighter1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human fighter2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human fighter3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human fireman m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human governor m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human guard m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human his m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker3 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker4 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human talker4 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human trader m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz21k human trapper m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human archer1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human brissen m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human fighter1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human fireman f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human leader f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human lovkach m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human mage m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker3 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker4 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human talker4 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human thief m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz22k human woodcuter m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz23k driad green archer1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz23k driad green mage1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz23k driad leader m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz23k unicorn white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human citizen f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human citizen m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human fireman m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human karim m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human krrasta f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human peasants f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human peasants m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz2h human rindail m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human archer1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human baron m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human bson m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human fighter1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human fighter2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human fighter3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human necro m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human stark m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker3 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker3 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker4 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j human talker4 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j jun deva f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz31j junofil m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz32j human doctor m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human blademaster m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human cookie f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human fatboy m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human guard m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human hatul m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human kehel m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human kuzn m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human peasants f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human peasants m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human student1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human student2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h human thickboy m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz3h ratsmall": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz4h evileye": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz4h octopus": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz4h octopus 2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human clothest f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human fireman m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human fruitt f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human jug f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human peasants f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human peasants m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human pod m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human potiont m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human sitter m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human slavetrader m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human smith m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talker m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerf f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerf m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerk1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerk2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerv f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human talkerv m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human van1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz5h human van2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human boss m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human firegirl f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human slave f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human slave m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human student1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human student1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human student2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz7h human student2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g batred": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g human thief m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g lizardblue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc archer1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc archer2 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc fighter1 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc fighter2 m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc mage1 f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g orc tanichey m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g shaivar m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers bz8g wolfwhite": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers fq15 dog": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers hero1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers hero2": [
		"7c3bde33eee2062c4dfd7239c9e36478b29ae6c9c841d1f10b4ca8ebb4f3aa84",
		"Kir",
		"Kir"
	],
	"pers hero3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers hero4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers human hero": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers merc2": [
		"cb144e7ed15c8af5cd67d40cade3709a7c0ab11dac433d0ff866d034668fd9ac",
		"Kel",
		"Kel"
	],
	"pers merc2g": [
		"cb144e7ed15c8af5cd67d40cade3709a7c0ab11dac433d0ff866d034668fd9ac",
		"Kel",
		"Kel"
	],
	"pers merc8": [
		"2b14d0b813292039cf11f9e59c803e704de76846a44189f80de12cf4aa136511",
		"Feiruz",
		"Feiruz"
	],
	"pers q11h human deadman m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers q7j human dartas m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers zone1 fly": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers zone3 human citizen f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"pers zone3 human citizen m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem danger_sensor": [
		"c5e3728fb0bf4ec68cefed3edcb65347dc76626de9fc473113fd07437fa8ced3",
		"Crystal\nA good thing! Pity there's no one who could teach you how to use it, though...",
		"Kristall\nEin nützlicher Gegenstand! Nur schade, dass keiner weiß, wie man ihn benutzt…"
	],
	"qitem danger_sensor ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem large_potion_1": [
		"3c6ac1c3d4d1cd9e0ef28ecd21d80a6eb35d43735c2c83f3a27d9db52d13ddc6",
		"Potion of dead man's sight\nGreatly increases the character's sight radius.",
		"Trank der Totensicht\nErhöht den Sichtradius der Figur deutlich."
	],
	"qitem large_potion_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem large_potion_2": [
		"9d8ebb281d89428ff09e6c40ac05a15e9f260bff7ece97629ac7efa02536499f",
		"Potion of magic protection\nPlaces a powerful magical shield around the hero.",
		"Trank des Magieschutzes\nErrichtet einen mächtigen magischen Schild um den Helden."
	],
	"qitem large_potion_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem large_potion_3": [
		"43ec6f514564b81da5dafd03403767c637bcb8eece38eed13e12d65e947559e9",
		"Sensory potion — paralysis\nPrevents the enemy from moving.",
		"Sinnestrank — Lähmung\nHindert den Gegner an der Bewegung."
	],
	"qitem large_potion_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem potion_1": [
		"53d61f32a044e84b7b902f1cff77a2221b3e2bfbaafb549141bddf39d8e73a01",
		"Potion of regeneration\nGreatly increases the character's regeneration rate.",
		"Regenerationstrank\nErhöht die Regenerationsrate der Figur stark."
	],
	"qitem potion_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem potion_2": [
		"23d7eb37b36e86abd8b164619c58a63ac3719e5e4bc6599d9989ecf36bf9589b",
		"Potion of strength\nBriefly increases the character's health and damage.",
		"Stärketrank\nErhöht kurzzeitig Lebenspunkte und Schaden der Figur."
	],
	"qitem potion_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem potion_3": [
		"bceb63cd63209988244ded2efbdf5cf6d242dd02995f4db092288a41631eecf1",
		"Potion of invisibility\nMakes the character much harder to notice.",
		"Unsichtbarkeitstrank\nMacht die Figur deutlich schwerer erkennbar."
	],
	"qitem potion_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem potion_enlarge": [
		"b601a01e17728612505d58c8b4bb6514fd767211fcbe0c6667ed4d189ee2f917",
		"Astral crystal — teleport\nTeleports over a great distance. The destination must not be blocked by obstacles.",
		"Astralkristall — Teleportation\nTeleportiert über große Entfernung. Hindernisse dürfen das Ziel nicht verdecken."
	],
	"qitem potion_enlarge ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem potion_shrink": [
		"d84f6d73e4e05bb6cce1b6b1686ed543867b5714aaa130587074f3ca1b1eff0a",
		"Elemental crystal — storm\nCalls down five immensely powerful lightning bolts on enemies.",
		"Elementarkristall — Sturm\nLässt fünf gewaltige Blitze auf die Feinde niedergehen."
	],
	"qitem potion_shrink ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem small_potion_1": [
		"3f4cc4f48dde9d088da6f82fc5c6f055f29ae10fe212a3236a907c3bdd9185bc",
		"Healing potion\nInstantly restores 70 health.",
		"Heiltrank\nStellt sofort 70 Lebenspunkte wieder her."
	],
	"qitem small_potion_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem small_potion_2": [
		"611cef6709720e608d3c8ed9abafcf0034a7b4fc7d397fef97d2500f1c45fc37",
		"Potion of slowing\nReduces the enemy's movement and attack speed.",
		"Trank der Verlangsamung\nVerringert Bewegungs- und Angriffsgeschwindigkeit des Gegners."
	],
	"qitem small_potion_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem small_potion_3": [
		"2f210e75862d795301e7ff1a3580f0fb169008ae19b268590ba83216c0d13a00",
		"Potion of keen sight\nIncreases the character's sight radius.",
		"Trank des Scharfblicks\nErhöht den Sichtradius der Figur."
	],
	"qitem small_potion_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem spell_container": [
		"545934921d5b20c6349103a16b5a933676435775a362039ce1eeb5e0ad7e77f6",
		"Something magical\nA strange thing indeed... and there's no one who could even give a hint as to what it is for...",
		"Etwas Magisches\nEin seltsames Ding... Und keiner weiß so genau, wofür es überhaupt gut ist."
	],
	"qitem spell_container ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem tiny_potion_1": [
		"05e2f7af8278282b5c252cdeaa0ecc675e73529889de8e60138c288d25e9546f",
		"Minor healing potion\nInstantly restores 30 health.",
		"Kleiner Heiltrank\nStellt sofort 30 Lebenspunkte wieder her."
	],
	"qitem tiny_potion_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem tiny_potion_2": [
		"ed0a3a47ce9112ee7b03f63b4b7a73715f9575515ca2daa1421a6b1faab17ac2",
		"Minor haste potion\nTemporarily increases the character's action speed.",
		"Kleiner Trank der Hast\nErhöht vorübergehend die Handlungsgeschwindigkeit der Figur."
	],
	"qitem tiny_potion_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem tiny_potion_3": [
		"d8590e800143e5e60582507e5d825510f1f04beffb1f5f0b2e09aa8a7dfa4f70",
		"Potion of silent steps\nMakes the hero's footsteps silent for a time.",
		"Trank der lautlosen Schritte\nMacht die Schritte des Helden vorübergehend lautlos."
	],
	"qitem tiny_potion_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_1 granite": [
		"d00c60d2a128f45c45a0dc949a84fda70e0d3d069c89fefaa447b87186157d0a",
		"Granite wand\nA bit better than stone but worse than all others.",
		"Zauberstab aus Granit\nBesser als normaler Stein, aber schlechter als alles andere."
	],
	"qitem wand_1 malachite": [
		"16b8cf455792ace07aecdf915ce5a30249ba1b27dfc58f2a6fe28d871307c642",
		"Obsidian wand\nThe best of stone wands.",
		"Zauberstab aus Obsidian\nDer beste aller steinernen Zauberstäbe!"
	],
	"qitem wand_1 rock": [
		"c34a3b7969dd2a5391888805a50e31ca1987b2154a955c25145e493ea2a52b2a",
		"Stone wand\nThe simplest and weakest of wands.",
		"Steinzauberstab\nDer einfachste und schwächste Zauberstab!"
	],
	"qitem wand_1 silicon": [
		"48c6d22e3688128cc8b9e3f4af59835a1ef352a70ee84e2634d96a3f8b141114",
		"Silicon wand\nA decent stone wand.",
		"Zauberstab aus Silizium\nEin angemessener Zauberstab."
	],
	"qitem wand_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_2 burned_bones": [
		"da385b9738e9dea31bf9f5f4dbd70b5815b2b6389c13ebc12c74c035e55182e9",
		"Hard bone wand\nA good choice for a trained magician.",
		"Zauberstab aus hartem Knochen\nIdeal für den erfahrenen Magier."
	],
	"qitem wand_2 decayed_bones": [
		"40033bbd3d3ea487b1246334f6b01e2d6bdf2d4d4c9e1813f07f729585d921d3",
		"Thin bone wand\nA simple bone wand.",
		"Zauberstab aus einfachem Knochen\nEin einfacher Knochenstab."
	],
	"qitem wand_2 dragon_black_bones": [
		"6f896024605a63a3da231012fab835ad02d0e37f7bc8da3c5e652ce29c51b1d3",
		"Blue Dragon bone wand\nDragon bones enable one to use a very high level of magic.",
		"Zauberstab aus blauem Drachenknochen\nDrachenknochen sind auch für sehr komplexe Magie geeignet."
	],
	"qitem wand_2 dragon_green_bones": [
		"7cb95b5324742f7e9e700b51b45fac8589a4543dda0c8e74726eb3d89953e733",
		"Green Dragon bone wand\nDragon bones enable one to use a very high level of magic.",
		"Zauberstab aus grünem Drachenknochen\nDrachenknochen sind auch für sehr komplexe Magie geeignet."
	],
	"qitem wand_2 dragon_red_bones": [
		"dd444a3ef0614aae727ac6c9e84c284ecbd6cd111e0c63c3a7891776e8c8b865",
		"Red Dragon bone wand\nDragon bones enable one to use a very high level of magic.",
		"Zauberstab aus rotem Drachenknochen\nDrachenknochen sind auch für sehr komplexe Magie geeignet."
	],
	"qitem wand_2 dry_bones": [
		"9cea9b1dd5c6aa315e3f9decec556d035cdbd53dcdf4763dcae4c4692c6040a6",
		"Tough bone wand\nA decent bone wand.",
		"Stabiler Zauberstab aus festem Knochen\nEin annehmbarer Knochenzauberstab."
	],
	"qitem wand_2 scrab_bones": [
		"3a89573c76a3baef6fbcbdd912c2611ce6a6be52a1d8576962c2e5da3b8c81fa",
		"Shell bone wand\nGood material - gives good effect.",
		"Zauberstab aus Panzerknochen\nGutes Material zahlt sich aus."
	],
	"qitem wand_3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_3 adamantium": [
		"00e080f1c0a35612f3ce0f9a505e8cfb7e8d01c90d8b76259a7c4595e2580d72",
		"Adamantite wand\nYou can cast very powerful spells with this wand.",
		"Zauberstab aus Adamant\nMit diesem Stab kann man auch die stärksten Zauber aussprechen."
	],
	"qitem wand_3 bronze": [
		"e8b0d9bef8777a0449973260d18f763dd120dae8d9244cb96175e77b795d96e9",
		"Bronze wand\nThe simplest of metal wands. An experienced magician deserves something better.",
		"Zauberstab aus Bronze\nDer einfachste aller Metallzauberstäbe. Ein guter Zauberer verdient Besseres."
	],
	"qitem wand_3 iron": [
		"8cd765649ac6f842d344c51769f4f7cdadf87bb704836cff80b1608b630ed0de",
		"Iron wand\nBetter than bronze, but worse than any other metal wand.",
		"Zauberstab aus Eisen\nBesser als Bronze, aber schlechter als jeder andere Zauberstab aus Metall."
	],
	"qitem wand_3 meteoric": [
		"28a0dd5cbb70de59a36cc3e4419b0583145a84d5e0cad69d4b07f3593d59664c",
		"Meteorite wand\nOnly an experienced magician can fully use its potential!",
		"Zauberstab aus Meteorit-Eisen\nNur erfahrene Magier können das ganze Potenzial dieses Zauberstabes nutzen."
	],
	"qitem wand_3 mithrill": [
		"788030858d5b9839a792a5801827286bae6fa651a8d0cd2da4bee466519cec98",
		"Mithrill wand\nMithrill is light and strong and also absorbs magic wonderfully.",
		"Zauberstab aus Mithril\nMithril ist leicht, stabil und nimmt sehr gut Magie auf."
	],
	"qitem wand_3 steel": [
		"013a61f140625de99e8cfef4e0f2cea3445ee923b5c83d9ff3e22b7ce88f1385",
		"Steel wand\nSteel doesn't just make good weapons.",
		"Zauberstab aus Stahl\nStahl ist nicht nur für Waffen geeignet."
	],
	"qitem wand_4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_4 adamantium": [
		"2ddbce98b960137444cce7c0eda38921f4ad1d55e96c1a3dc98306571cc0fc30",
		"Decorative adamantite wand\nThis one will shoot magic just as well as the adamantite crossbow shoots arrows.",
		"Kunstvoll gearbeiteter Zauberstab aus Adamant\nVerstärkt Zauber mindestens so gut, wie eine Adamant-Armbrust Pfeile verschießt."
	],
	"qitem wand_4 bronze": [
		"689efabea587006beb2294c06f1f62dc2e9585448152d3fc401ce8ada36cf632",
		"Decorative bronze wand\nYou could choose a more serious material for a decorative wand!",
		"Kunstvoll gearbeiteter Zauberstab aus Bronze\nDas Material ist für einen solch kunstvollen Zauberstab mehr als unangemessen."
	],
	"qitem wand_4 iron": [
		"7e9864ab6de0dd6ac088a4a1e938491e813d02c538164bf8024c6f44e4751d4c",
		"Decorative iron wand\nIt will work, but not well enough for a master magician.",
		"Kunstvoll gearbeiteter Zauberstab aus Eisen\nDer Zauberstab erfüllt seinen Zweck, ist aber nicht gut genug für einen Meister."
	],
	"qitem wand_4 meteoric": [
		"729eefc84adcc595c0fa282e8d5af26b27e3ff9cf91bd03fe66fa92ffb241528",
		"Decorative meteorite wand\nThe best of all possible magic wands.",
		"Kunstvoll gearbeiteter Zauberstab aus Meteorit-Eisen\nDer beste aller möglichen Zauberstäbe!"
	],
	"qitem wand_4 mithrill": [
		"85247b96af803a1057a3c2b043f0741a832af65b8db194898b724d5b1d159f4e",
		"Decorative mithrill wand\nMany magicians in this world dream about having one!",
		"Kunstvoll gearbeiteter Zauberstab aus Mithril\nViele Magier können nicht einmal von so einem Stab träumen."
	],
	"qitem wand_4 steel": [
		"5c3692bcb6baa73d1573816649b61792097826fedba6e8ad6bd9df514d586574",
		"Decorative steel wand\nNot a bad choice!",
		"Kunstvoll gearbeiteter Zauberstab aus Stahl\nNicht der schlechteste aller Zauberstäbe!"
	],
	"qitem wand_5": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 burned_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 decayed_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 dragon_black_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 dragon_green_bones": [
		"e42b8ef2efa2f074cbc1b3204691e0e023ce19b8daa056cf5b3df1eb1b0d5d23",
		"Green Dragon horn\nA magical Dragon horn used by Lizards.",
		"Grünes Drachenhorn\nEin magisches Drachenhorn, wie es von Echsen benutzt wird."
	],
	"qitem wand_5 dragon_red_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 dry_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_5 scrab_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_6": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_6 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_6 granite": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_6 malachite": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"qitem wand_6 rock": [
		"770d5e6e7ec9fa1fd0d881c902aa2aa0a79356c72d84da58a27b67c6df417810",
		"Goblin doll\nA magical stone doll used by Goblins.",
		"Goblin-Figur\nEine magische Steinfigur, wie sie von Goblins benutzt wird."
	],
	"qitem wand_6 silicon": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ambushkey00": [
		"65d654979acf7ea930f5f29697d7af58a0705db16ed06f9eb9f39bf91a0293f5",
		"Traps key\nA figurine that disables magical traps.",
		"Fallenschlüssel\nEine Figur, die magische Fallen deaktiviert."
	],
	"questitem ambushkey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ambushkey01": [
		"93e173ec3e0cdb3175f59dd44bdca5d60b1373db16238c065108b47b15c6f5fa",
		"Pyramid key\nA figurine that activates the magical pyramid.",
		"Pyramidenschlüssel\nEine Figur, die die magische Pyramide aktiviert."
	],
	"questitem ambushkey01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ambushkey02": [
		"145e0380dc6bec6b67eb329e910e017ea05cf56a0af883a4b7ca286f4eeffb06",
		"Key to the mountain gates\nA figurine that opens the gates in the mountains.",
		"Schlüssel zum Bergtor\nEine Figur, die das Tor in den Bergen öffnet."
	],
	"questitem ambushkey02 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ambushkey03": [
		"69bb88030d450ef56273725c8b3e7b6edfe339601bca568fe833071e2da8d5b3",
		"Gate key\nA figurine that opens the gates in the lizards' dungeons.",
		"Schlüssel zum Tor\nEine Figur, die das Tor in den Echsenverliesen öffnet."
	],
	"questitem ambushkey03 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ambushkey04": [
		"a47948873b83256340a76c5eb1788c4bb99c1e399178e84b7b94cb0646ccab68",
		"Key\nThis figurine was clearly made by a Jun craftsman.",
		"Schlüssel\nDiese Figur wurde eindeutig von einem Handwerker der Jun gefertigt."
	],
	"questitem ambushkey04 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem animalmoney": [
		"8b04d61b453944dda6217a382306c77ccb708cc09ef75452b61bc1190d639d28",
		"Cash box\nThis chest contains gifts for the capital and the beastmasters' money.",
		"Geldkasse\nDiese Truhe enthält Geschenke für die Hauptstadt und das Geld der Bestienmeister."
	],
	"questitem animalmoney ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem awl": [
		"9c7f3e0e340402c9539e532f09a7ec06ec821728bce54c410ce68a648f385623",
		"Magic needle\nThe magic needle can be used to make superb armour.",
		"Magische Nadel\nMit der magischen Nadel lässt sich hervorragende Rüstung herstellen."
	],
	"questitem awl ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem baburletter": [
		"2b7c116e82b4dbd4ce82aed4c104c0d012516aee380789188452ee78948d3300",
		"Letter to Babur\nIn this letter, the bandits offer Babur work. Payment is guaranteed.",
		"Brief an Babur\nIn diesem Brief bieten die Banditen Babur Arbeit an. Bezahlung ist garantiert."
	],
	"questitem baburletter ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem burnbaby": [
		"b34d6ea0cad749c7a3a64805832030802867e1b9ae5ed5b9d99145b05dac2ae3",
		"Necromancers' scroll\nThis scroll can reanimate a corpse prepared for the procedure.",
		"Schriftrolle der Nekromanten\nDiese Schriftrolle kann eine entsprechend vorbereitete Leiche wiederbeleben."
	],
	"questitem burnbaby ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem caboom": [
		"e78d8a38023d435f9e672752c1eb0184fb19cd06275cdbb92352cb66f3690653",
		"Explosive powder\nEnough to blow a whole mountain apart.",
		"Sprengpulver\nGenug, um einen ganzen Berg zu sprengen."
	],
	"questitem caboom ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem cagekey00": [
		"7465b433f941f01d386ed2cbbcc8e7b34feaab21f65a85a8587472f9619fce6b",
		"Merchant's key\nFeiruz needs this key.",
		"Schlüssel des Händlers\nFeiruz braucht diesen Schlüssel."
	],
	"questitem cagekey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem capitalitems": [
		"54dafd64542e919b143eeda872f1319b25fb770ca4805ce8a563c5c48887bd17",
		"Empty chest\nThis chest should have contained gifts for the capital... but it is empty!",
		"Leere Truhe\nDiese Truhe sollte Geschenke für die Hauptstadt enthalten ... doch sie ist leer!"
	],
	"questitem capitalitems ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem chestkey": [
		"2e6b9a2c022a94e353424a524fa8ccb0a6648b9987de077551903cf6812afbc7",
		"Universal key\nSince nobody will ever see this description, any nonsense could go here... The funniest part is that you are reading it anyway.",
		"Universalschlüssel\nDa diese Beschreibung ohnehin niemand sieht, könnte hier jeder Unsinn stehen ... Das Lustigste ist, dass ihr sie trotzdem lest."
	],
	"questitem chestkey ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem clerkkey00": [
		"04b9691751387b50b8399ffa5024c9bd198d7c76b4601a304d2f51ed91740fb0",
		"Official's key\nThis key unlocks the barred gate in the expedition camp.",
		"Schlüssel des Beamten\nDieser Schlüssel öffnet das Gittertor im Expeditionslager."
	],
	"questitem clerkkey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem darrow": [
		"6d9cef5c043b6513a8c00283ed7bb899b579be696b23361707bdc2c34afd98c1",
		"Blue Clan mage's arrow\nA good gift for Governor Valrasian.",
		"Pfeil des Magiers des Blauen Clans\nEin gutes Geschenk für Gouverneur Valrasian."
	],
	"questitem darrow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem deadbrissen": [
		"6efaed74d46fa1ad4628e1b5871818d851bae150f43a4e92c79cdd88839f7882",
		"Evidence\nBrissen was killed with this weapon.",
		"Beweisstück\nMit dieser Waffe wurde Brissen getötet."
	],
	"questitem deadbrissen ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem dflower": [
		"b4347b691d2c4f9ead703da189e83ddd61903d9553f14ae9550d559dea6e018f",
		"Sacred flower\nThis flower can summon the Green Clan chief.",
		"Heilige Blume\nMit dieser Blume kann man den Häuptling des Grünen Clans rufen."
	],
	"questitem dflower ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem dragonpoison": [
		"88382120612ddb19fb3addbd1ee9277a0d85a8b3864fc943d8a6aac845cea911",
		"Slave lists\nThis lists the names and distinguishing features of every slave in the enclosure when the Terror attacked.",
		"Sklavenlisten\nHier stehen Namen und besondere Merkmale aller Sklaven, die beim Angriff des Schreckens im Pferch waren."
	],
	"questitem dragonpoison ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem dumblever": [
		"b89c98a9d510123c41f2a9bff0441d84ba292ea8ca253ba76d45488a496f01e2",
		"Stick\nThe weapon of the working class! This stick can smash anything within reach.",
		"Stock\nDie Waffe des Proletariats! Mit diesem Stock lässt sich alles in Reichweite zerschlagen."
	],
	"questitem dumblever ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem elemmat": [
		"f61b92054fd981cad2f2ca67e104449936686af90cf0e9b6adf6243afb3a8d3e",
		"Ice elemental samples\nThese samples are needed to discover why the elementals have appeared.",
		"Proben von Eiselementaren\nMit diesen Proben soll die Ursache für das Auftauchen der Elementare ermittelt werden."
	],
	"questitem elemmat ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem fakedocument00": [
		"c31c93a3b7d757ac6651a67ae8020ec2f54630b9517c6978f64d2d416187b4b3",
		"Ancient parchment\nThe crumpled, torn paper bears the barely legible words: “You cannot drink away experience.”",
		"Uraltes Pergament\nAuf dem zerknitterten, löchrigen Papier steht kaum lesbar: „Erfahrung kann man nicht vertrinken.“"
	],
	"questitem fakedocument00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem goldnugget": [
		"2492b1e94e8097b316bb4cfcf18f9f4a033abccea11065a5bc368822974ceee6",
		"Emperor's seal\nAny Khadagan man absolutely must give this seal to the Emperor's guard under penalty of horrible death.",
		"Siegel des Imperators\nJeder Bürger Khadagans ist zur sofortigen Rückgabe dieses Siegels verpflichtet - unter Androhung der Todesstrafe!"
	],
	"questitem goldnugget ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem goldnugget00": [
		"c608f38e85f2be8c964abcc1692be8608d04095d6fd6819505fef594cf5e247e",
		"Golden nugget\nA weighty argument.",
		"Goldklumpen\nEin gewichtiges Argument."
	],
	"questitem goldnugget00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem golemcenterkey00": [
		"41011b664e1aeed590d6cc6bf43f17599cfbf5a5e3ec3b8e8ab1d4fd28152a5e",
		"Key for altar\nUse it to switch off the mechanical killers - the Golems.",
		"Schlüssel für den Altar\nWird gebraucht, um die Golems auszuschalten."
	],
	"questitem golemcenterkey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem greenleaf": [
		"4280fbd2c3b511aa416351b6a418cd20b479dbf54dabbf1d0d8e5b00a8618bdf",
		"Green leaf\nWith this leaf, the woodland folk's traps pose no threat.",
		"Grünes Blatt\nMit diesem Blatt braucht man die Fallen des Waldvolkes nicht zu fürchten."
	],
	"questitem greenleaf ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem hadogancagekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem hadogancagekey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem hadogancavekey00": [
		"0e1fc48d4ec18bec34a269f7a9268616a4aa01fc05c95158cc24e3e7d401619a",
		"Cell key\nThis key opens the prisoners' cells.",
		"Zellenschlüssel\nDieser Schlüssel öffnet die Zellen der Gefangenen."
	],
	"questitem hadogancavekey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem head00": [
		"64ae230349c69ea53e0c1170efa761eb36c51b14b7900f38bd669cb5022fe18e",
		"Prisoner's head\nThis object may have served its owner well in life, but he clearly has no use for it now...",
		"Kopf des Gefangenen\nDieses Stück mag seinem Besitzer zu Lebzeiten gute Dienste geleistet haben, doch jetzt braucht er es offensichtlich nicht mehr ..."
	],
	"questitem head00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem herocagekey00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem herocagekey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jamul": [
		"3be62f11c90b2dc4346a8e40cddbd7aa5fc7ba9ba984944c445e5c42632360fd",
		"Amulet\nThis amulet helps open the cave entrance.",
		"Amulett\nDieses Amulett hilft, den Höhleneingang zu öffnen."
	],
	"questitem jamul ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jcontrol": [
		"4111ea232beef90db1b68c3367a52f8fe63938e1c4368b9a4af58133aba1159b",
		"Amulet of domination\nThis amulet can subdue powerful creatures.",
		"Amulett der Unterwerfung\nMit diesem Amulett lassen sich mächtige Wesen unterwerfen."
	],
	"questitem jcontrol ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jdocs": [
		"7509fcd100b9f6bdb7353beb420a03b85fee16e7ce94b7326d3ef995c82b1417",
		"Secret report\nThese documents contain information about the Hadagan army.",
		"Geheimer Bericht\nDiese Dokumente enthalten Informationen über das hadaganische Heer."
	],
	"questitem jdocs ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jkey00": [
		"3115423f21f0930601b614c512c5ba4d6d1144d76a0ccbef110e55db3a190755",
		"Key\nThis key opens the eastern door in the Jun cache.",
		"Schlüssel\nDieser Schlüssel öffnet die östliche Tür im Versteck der Jun."
	],
	"questitem jkey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jmap": [
		"9bd5c58941a42c5b834fb799b3f34f675d04d702fa889dcf6c7430c8167aa6f3",
		"Map of the area\nThis map shows the positions of all Firez's troops.",
		"Karte der Umgebung\nDiese Karte zeigt die Stellungen aller Truppen von Firez."
	],
	"questitem jmap ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jmaterial": [
		"d6448ba3aff86d42287f5bec9bbc399c92b61b985d7763955a04ae0a0e1eec89",
		"Bag of ore\nThis bag contains first-class ore.",
		"Sack mit Erz\nDieser Sack enthält erstklassiges Erz."
	],
	"questitem jmaterial ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jmush": [
		"e1b3d34278ca79b7672b3bc97eff35f28928fc75119a342d08d07704c90b50dd",
		"Poisonous mushrooms\nThis bag is full of poisonous mushrooms.",
		"Giftpilze\nDieser Sack ist voller Giftpilze."
	],
	"questitem jmush ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jpump": [
		"e69a616576670e2e223e2b52b974a59004edbfe6270f6b1624eca79769ad024f",
		"Pumpkin\nThe bag contains a large, ripe pumpkin.",
		"Kürbis\nIm Sack liegt ein großer, reifer Kürbis."
	],
	"questitem jpump ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem jtoys": [
		"9de0bc6eaa77294677825c69b54c99fa1e7b663b11812d42b4f2ab4ba225e056",
		"Trinkets\nThe chest contains Tai-Ilara's trinkets.",
		"Kleinigkeiten\nDie Truhe enthält Tai-Ilaras Kleinigkeiten."
	],
	"questitem jtoys ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kel1": [
		"6292dc24318509bb9e06188a210854709a2f6d10f02b887f6ab94046dedaa56f",
		"Piece of the Rod of Life\nLegend says the powerful artefact was broken into three pieces...",
		"Teil des Stabs des Lebens\nDer Legende nach wurde das mächtige Artefakt in drei Teile zerbrochen ..."
	],
	"questitem kel1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kel2": [
		"6292dc24318509bb9e06188a210854709a2f6d10f02b887f6ab94046dedaa56f",
		"Piece of the Rod of Life\nLegend says the powerful artefact was broken into three pieces...",
		"Teil des Stabs des Lebens\nDer Legende nach wurde das mächtige Artefakt in drei Teile zerbrochen ..."
	],
	"questitem kel2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kel3": [
		"6292dc24318509bb9e06188a210854709a2f6d10f02b887f6ab94046dedaa56f",
		"Piece of the Rod of Life\nLegend says the powerful artefact was broken into three pieces...",
		"Teil des Stabs des Lebens\nDer Legende nach wurde das mächtige Artefakt in drei Teile zerbrochen ..."
	],
	"questitem kel3 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kel4": [
		"e310e66dd4644e3e269b587e4a7b92f8bf88aa21b1d61114637c0e0275dc6626",
		"Rod of Life\nThe Rod of Life, popularly known as the “What-a-stick!”",
		"Stab des Lebens\nDer Stab des Lebens, im Volksmund auch der „Donnerwetter-Stab“ genannt."
	],
	"questitem kel4 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem key01": [
		"4d34c0d4e570ef009ca9cdddee9aeb6b470d1267d483cfe118ea8673e73f54e0",
		"Box key\nThis key opens the box of healing remedies.",
		"Kistenschlüssel\nDieser Schlüssel öffnet die Kiste mit Heilmitteln."
	],
	"questitem key01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey01": [
		"abf722a90d4bee0153acdac30a4cb5c5e3fda7d0c64bfbec6613316b75ec71e7",
		"Key to the mine gates\nOpens the gates to the mines in the north of the mining area.",
		"Schlüssel zum Minentor\nÖffnet das Tor zu den Minen im Norden des Bergbaugebiets."
	],
	"questitem kkey01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey02": [
		"e6f723b00d85046438ca53ec208387bb6261ac799e2a1a48e079a3f4fd053af7",
		"Key from the mines\nThis key grants access to the eastern mines.",
		"Schlüssel aus den Minen\nDieser Schlüssel gewährt Zugang zum östlichen Teil der Minen."
	],
	"questitem kkey02 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey03": [
		"668dae1e41bef6399a6d55366bfeab1688e79fe10313b0a35c20c0868723b03d",
		"Key to the gorge gates\nThis key opens the gorge southeast of the town outskirts.",
		"Schlüssel zum Schluchttor\nDieser Schlüssel öffnet den Zugang zur Schlucht südöstlich der Stadt."
	],
	"questitem kkey03 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey04": [
		"b103c40b8bde3a7cd81290d98cdaad057d411963d0731b128efea173b52c195d",
		"Key to the secret cave gates\nThis key opens the entrance to the cave holding the artefact.",
		"Schlüssel zum Tor der geheimen Höhle\nDieser Schlüssel öffnet den Eingang zur Höhle mit dem Artefakt."
	],
	"questitem kkey04 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey05": [
		"5538a6dcc488d96009e9591b6037da131daa4ca4467eb1ebd76fbd65b2116ca7",
		"Gate key\nThis key opens the gates in the portal cave.",
		"Schlüssel zum Tor\nDieser Schlüssel öffnet das Tor in der Portalhöhle."
	],
	"questitem kkey05 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey06": [
		"cc79346fb01f15623406af0736e1db1da0e55df39655e4332932983ed89ceeec",
		"Key to the abandoned mines\nThis key opens the gates to the abandoned mines.",
		"Schlüssel zu den verlassenen Minen\nDieser Schlüssel öffnet das Tor zu den verlassenen Minen."
	],
	"questitem kkey06 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kkey07": [
		"8a6fdf8563d8e2972bd05951bbfb8078ea08845dd0ff0ea5bc2d6f46ac7b9c62",
		"Key\nKeys like these operate levers in the mines.",
		"Schlüssel\nSolche Schlüssel werden für Hebel in den Minen verwendet."
	],
	"questitem kkey07 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kleverbook": [
		"b790a9dd9ae0c27950eea164b28b940e960862a4cfc41dbe57cef515fe802ef7",
		"Book from observatory\nThis book explains how to restore energy to magical items.",
		"Buch aus dem Observatorium\nDieses Buch erklärt, wie man die Energie magischer Gegenstände wiederherstellt."
	],
	"questitem kleverbook ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem knote01": [
		"71a7ff472d5d3d46653250a92c573b93cf6daa0ee9553b1578385f275209707f",
		"Letter to the sentry\nThis letter must be delivered to the mine guard.",
		"Brief an den Wachposten\nDieser Brief muss dem Minenwächter übergeben werden."
	],
	"questitem knote01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kwater01": [
		"fa6fde5d75aaf1166149abc7dc07616d72621716d59429780b1bd01cbb0fef20",
		"Empty bucket\nAn ordinary wooden bucket.",
		"Leerer Eimer\nEin gewöhnlicher Holzeimer."
	],
	"questitem kwater01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem kwater02": [
		"9b077dcb00601e5f89f5cd59da44ed40fdb14709113dcb4accad1a76942ad89c",
		"Full bucket\nThe bucket is filled to the brim with water.",
		"Voller Eimer\nDer Eimer ist bis zum Rand mit Wasser gefüllt."
	],
	"questitem kwater02 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem magedocs": [
		"d98b267555fb8f78df0117e1162e69e18e25f155faed485b897f3c1d73fa2795",
		"Mine pass\nThis pass can prove the old mage's innocence.",
		"Passierschein für die Minen\nDieser Passierschein kann die Unschuld des alten Magiers beweisen."
	],
	"questitem magedocs ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem magicitems": [
		"b783232af2cdcd2fd4064f9f8c441ddb2e775f2d6dd9eee7f79a9e29d060ec7d",
		"Magical ingredients\nHis needs these ingredients.",
		"Magische Zutaten\nHis braucht diese Zutaten."
	],
	"questitem magicitems ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem map00": [
		"fe3ba392b339ca2585592d266d3b4518ed429e8aac33a0eaf712f4025dbd099f",
		"Map of the catacombs\nThis map shows a quiet escape route from the portal fortress.",
		"Karte der Katakomben\nDiese Karte zeigt einen unauffälligen Fluchtweg aus der Portalfestung."
	],
	"questitem map00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem mindcontrol": [
		"4d81ba74dd49494aaa3b497813569adaed1cf80a1f89a69cfbe5eb95acaf89b3",
		"Wormface amulet\nThis amulet can control a harpy's mind!",
		"Wurmgesicht-Amulett\nDieses Amulett kann den Geist einer Harpyie beherrschen!"
	],
	"questitem mindcontrol ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem necklace": [
		"5c6891c17be79067ac21d2e18f8315a781b3116d97da4bd600e84f2a9ae479e6",
		"Kel's necklace\nSimple, yet striking.",
		"Kels Halskette\nEinfach und doch eindrucksvoll."
	],
	"questitem necklace ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note00": [
		"9b2b4b451f4e43e84e7cde12c7fd315262420ab9937ed7ea52661f8c1a5fedbf",
		"Documents\nThese papers describe why their bearer must travel to Suslanger.",
		"Dokumente\nDiese Papiere beschreiben, weshalb ihr Besitzer nach Suslanger reisen muss."
	],
	"questitem note00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note01": [
		"0364bb198113d59911bd9111149c7d460cc023acc46d14ec95efdbd6de254be3",
		"Letter to the blackmailers\nThis letter must be delivered to the blackmailers.",
		"Brief an die Erpresser\nDieser Brief muss den Erpressern übergeben werden."
	],
	"questitem note01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note02": [
		"6ede3e9edb6a19815b29d410f81bf2ee294804f9454338c6119704d424a15277",
		"Meteorite samples\nThese meteorite samples came from a remote, abandoned allod.",
		"Meteoritenproben\nDiese Meteoritenproben stammen von einem abgelegenen, verlassenen Allod."
	],
	"questitem note02 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note03": [
		"308722338e369a999ace4271b656fd3c4ca56da3fad157939c0b04de12b2a317",
		"Letter to the blackmailer\nThis letter is meant to attract the blackmailer's attention.",
		"Brief an den Erpresser\nDieser Brief soll die Aufmerksamkeit des Erpressers wecken."
	],
	"questitem note03 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note04": [
		"6a374c470d6db81376e6695a8c16593a322eb95bda5e281ec7dd5dc0475d55e1",
		"Paper from a caravaneer's body\nThis dying message reveals the true cause of the caravan's destruction.",
		"Papier von der Leiche eines Karawanenführers\nDiese letzte Nachricht verrät die wahre Ursache für den Untergang der Karawane."
	],
	"questitem note04 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note05": [
		"f38e32313ccf1c5c23e1d22691a0abdfb160f49634f0cfca7895e7a2fabd0997",
		"Documents\nThese documents allow entry into the Hadagan army.",
		"Dokumente\nMit diesen Dokumenten kann man dem hadaganischen Heer beitreten."
	],
	"questitem note05 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note06": [
		"cddd15f72f78228f01e273cc3085c0e1c83b29d838042be5cf4e1a9af3cc9e13",
		"Portal pass\nBlah, blah, blah.",
		"Passierschein für das Portal\nBla, bla, bla."
	],
	"questitem note06 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem note07": [
		"b4d14a8cce53780f06530ce3f0a4bbab15c19f664ea323b9c28d823b4a8e6600",
		"Package of documents\nThe package contains documents for the leader of the Gipath expedition.",
		"Dokumentenpaket\nDas Paket enthält Dokumente für den Leiter der Gipath-Expedition."
	],
	"questitem note07 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ogrefood": [
		"a7317268e06eeae10b94dcfc506d593551bebf4f293b7539d9ca70a90cd0a2f3",
		"Bag of food\nThe bag contains roast pork.",
		"Sack mit Nahrung\nIm Sack liegt Schweinebraten."
	],
	"questitem ogrefood ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ogrekey": [
		"d17c69648a3d6216cb5d92fb94ace39a1c4b7dd65738784a1e671d459ad50c50",
		"Hadagan key\nKey to the chest in the Hadagan expedition camp.",
		"Hadaganischer Schlüssel\nSchlüssel zur Truhe im hadaganischen Expeditionslager."
	],
	"questitem ogrekey ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ogrekey1": [
		"921c79d570205c2c680e87d95c7b9fb9251d5d4dd6a49c4bfe70ecf64d77e8b9",
		"Ogre chief's key\nThis key is needed to free Babur.",
		"Schlüssel des Ogerhäuptlings\nDieser Schlüssel wird benötigt, um Babur zu befreien."
	],
	"questitem ogrekey1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ogrekey2": [
		"5a4e18f5e94aecd3704235298a71d3b0d0d3b207a5a4ae5fdfaf8c97a8ca43e2",
		"Ogre elder's key\nThis key is needed to free Babur.",
		"Schlüssel des Ogerältesten\nDieser Schlüssel wird benötigt, um Babur zu befreien."
	],
	"questitem ogrekey2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ogrepresent": [
		"5b9471852db99bcf45681fc217eaa1b8c65120c50495af9359b5b7e84c0cc477",
		"Necklace\nThis necklace would make an excellent gift for Airi.",
		"Halskette\nDiese Halskette wäre ein ausgezeichnetes Geschenk für Airi."
	],
	"questitem ogrepresent ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem orcgear": [
		"9a3654fe1a9973887852050742d477b2b79180b7f1df337dcc132f5a0bce4791",
		"Island Orcs' mechanism\nRequired to reach the orc islands.",
		"Zahnrad der Insel-Orks\nWird benötigt, um die Orkinseln zu erreichen."
	],
	"questitem orcgear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem palantirbroken00": [
		"c4448152f084435c88a4dc8c133f34c3dae91e578486914a538db13145175b42",
		"Magic orb\nAn ancient magical artefact, drained of energy.",
		"Magische Kugel\nEin uraltes magisches Artefakt ohne Energie."
	],
	"questitem palantirbroken00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem palantirwork00": [
		"519fde3fbe364e8722f3a786aac5d16c32bb95f91530bad33e9a002cbc7c2275",
		"Magic orb\nAn ancient magical artefact, fully charged.",
		"Magische Kugel\nEin uraltes magisches Artefakt voller Energie."
	],
	"questitem palantirwork00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem paper": [
		"c129c4b38d39243c5ef33b0996485dc310eed64ce357161ef21e778b653d55b9",
		"Official stationery\nThe most important documents are written on paper like this.",
		"Amtliches Papier\nAuf solchem Papier verfasst man die wichtigsten Dokumente."
	],
	"questitem paper ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem percovka": [
		"1648f6ef383bdaa6180db78708bd2ef2f10fe12bcca3aad15a2c7ae92b605321",
		"Garlic tincture\nThis potion is extremely effective against the undead.",
		"Knoblauchtinktur\nDieser Trank wirkt außerordentlich gut gegen Untote."
	],
	"questitem percovka ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem ragu": [
		"595c97a7c4af986df98b97579bd38ea1480d3f2635d97d7df1c7ebe041e7c7e7",
		"Poisoned stew\nThis food can be used to poison Dar-Ulgorn's guards.",
		"Vergifteter Eintopf\nMit dieser Nahrung kann man Dar-Ulgorns Wachen vergiften."
	],
	"questitem ragu ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem report": [
		"c153a3cb272a8924348ed58458ddbe45174183196b6f8aa214fb2a4f6e7f8554",
		"Report\nThis report describes the events at the scholars' ruined estate.",
		"Bericht\nDieser Bericht beschreibt die Ereignisse im zerstörten Anwesen der Gelehrten."
	],
	"questitem report ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackbabur": [
		"cb1765d67195f506dd633c6af3cffaeeb0bd9d68e3b40cb362dd6e5cd64c2008",
		"Bag of materials\nThis bag contains useless materials.",
		"Sack mit Materialien\nDieser Sack enthält nutzlose Materialien."
	],
	"questitem sackbabur ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackhunter": [
		"01b6e52f01665fb8006cd5a6b5b027a5bec405eb080afcd2262ea2de6374230e",
		"Bag of loot\nThis bag contains the settlement hunters' catch.",
		"Beutesack\nDieser Sack enthält die Beute der Jäger aus der Siedlung."
	],
	"questitem sackhunter ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackofbones": [
		"1b769d01143aa62ebc7d870235cdfcff87c0943b73fe147f79c69244673bc08d",
		"Bag of wormface corpses\nThis is exactly what it looks like: a large, heavy bag of corpses.",
		"Sack mit Wurmgesicht-Leichen\nDas ist genau das, wonach es aussieht: ein großer, schwerer Sack voller Leichen."
	],
	"questitem sackofbones ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackofgold00": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackofgold00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sackofmat": [
		"bb4a309039e1215aad36cd8155123c86832998e465d03f3d79ad246be0ad5d4c",
		"Bag of materials\nThe bag contains materials from an abandoned Canian mine.",
		"Sack mit Materialien\nIm Sack liegen Materialien aus einer verlassenen kanischen Mine."
	],
	"questitem sackofmat ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem shell": [
		"01918bdf9b6082f7872460a64332d5ed7eeb7da5bdbf573efb8d60c8c0739c10",
		"Big shell\nThe Lizards' idol, a symbol of peace. Lizards behave less aggressively near a shell.",
		"Große Muschel\nEin Symbol des Friedens und eine Reliquie der Echsen. In der Nähe einer solchen großen Muschel verhalten sich Echsen weniger aggressiv."
	],
	"questitem shell ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem superspear": [
		"eafaa6ae73ab63c7a73a998733c74f695f99c2f87cb12af00302d483a020cd22",
		"Healing draught\nThis potion can restore Sahili's strength...",
		"Heiltrank\nMit diesem Trank lassen sich Sahilis Kräfte wiederherstellen ..."
	],
	"questitem superspear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem sveralc": [
		"b3fb8732161667109a585de625b5dbab191dffce40e3f630512e5b0d05d69f4a",
		"Balm\nThe vial contains the woodland folk's healing balm.",
		"Balsam\nDas Fläschchen enthält Heilbalsam des Waldvolkes."
	],
	"questitem sveralc ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem svermark": [
		"6934ed43acbc82620f908924faa113cea8aa623205e9a1053f96cab337053d43",
		"Sver's token\nThe Green Clan chief will recognize a friend on seeing this token.",
		"Svers Zeichen\nAn diesem Zeichen erkennt der Häuptling des Grünen Clans einen Freund."
	],
	"questitem svermark ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem swampflower": [
		"98008c660359e7eb0ff57f85f971bf580c9de2179ac8457a93f1affaeb204352",
		"Swamp flower\nEstera the healer needs this flower.",
		"Sumpfblume\nDie Heilerin Estera braucht diese Blume."
	],
	"questitem swampflower ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem teleportkey00": [
		"a0caf842e950d62cd2e77133ee038e3dcb69a5d708e329a1fd8b6254845204d8",
		"Portal key\nUse this to activate the Portal.",
		"Schlüssel zum Portal\nWird benötigt, um das Portal zu öffnen."
	],
	"questitem teleportkey00 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem teleportkey01": [
		"a0caf842e950d62cd2e77133ee038e3dcb69a5d708e329a1fd8b6254845204d8",
		"Portal key\nUse this to activate the Portal.",
		"Schlüssel zum Portal\nWird benötigt, um das Portal zu öffnen."
	],
	"questitem teleportkey01 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem thiefsack": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem thiefsack ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem thiefsack1": [
		"3774588c610807376d927e1b0f20864db84fc02f21773fbe50033f1af52d2b88",
		"The thief's bag\nThis bag contains items looted by Alia.",
		"Sack der Diebin\nDieser Sack enthält Alias Beute."
	],
	"questitem thiefsack1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem thiefsack2": [
		"92ed91474361d7fb202a6bd63d93d774ccdc25e7a89a7242fc8f5592a9fe1fa7",
		"The thief's belongings\nThis holds the loot Alia managed to steal.",
		"Habseligkeiten der Diebin\nHier liegt die Beute, die Alia stehlen konnte."
	],
	"questitem thiefsack2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem traderkey1": [
		"d96516524910f26373df51b14296282055fd08990c137378f39e79de4a8e1fdd",
		"Gate key\nThis key opens the estate entrance in the north of the Portal area.",
		"Schlüssel zum Tor\nDieser Schlüssel öffnet den Eingang zum Anwesen im Norden des Portalgebiets."
	],
	"questitem traderkey1 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem traderkey2": [
		"e7238c53bfeb545a060bf93706767d9e3f0bdeb336d5feb710346f6a751f1e22",
		"Lift key\nThis key is needed to start the lift.",
		"Aufzugschlüssel\nDieser Schlüssel wird benötigt, um den Aufzug zu starten."
	],
	"questitem traderkey2 ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"questitem zakknife": [
		"98bcf5046fdde2cd17aea8e63c7c04bcc3e18a7988e553823b7b6b70f33509a5",
		"The Chosen One's dagger\nThis dagger means a great deal to Babur.",
		"Dolch des Auserwählten\nDieser Dolch bedeutet Babur sehr viel."
	],
	"questitem zakknife ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell acid_column": [
		"57a974c1cae70e2b4b3c288b652d47bb8ff494884ddb32b1e20ef77a0d1faa2d",
		"Acid fountain\nThis is an area effect spell. A fountain of acid causes damage to everyone around.",
		"Säurefontäne\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Personen werden von einer Säurefontäne verletzt."
	],
	"spell acid_fog": [
		"3de56b946b32e20b55d337cbe714b2eab88d34f5d0b52354477ff9858dab6edd",
		"Acid fog\nThis spell is directed at a location and not at a specific target. It causes acid damage to everyone inside the fog.",
		"Säurenebel\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Personen nehmen Schaden durch die Säure."
	],
	"spell acid_ray": [
		"e50696b4c1eb8d054bacdfa0189ba8076bd2bb893471ed59b7cc023694dc917e",
		"Acid blast\nA spray of acid which always hits the target.",
		"Säurekugel\nEine Kugel aus reiner Säure, die immer ihr Ziel trifft."
	],
	"spell antimagic": [
		"9c7aeabcd19aa441ec46b42f0f9f4a00e0295ea55877c0145785de0822a5f33f",
		"Protection from magic\nThis spell protects you from the Magic of any of the three Elements.",
		"Schutz vor Magie\nDieser Zauber schützt gegen Magie aller drei Elemente."
	],
	"spell arrow": [
		"0a503a7f950373819fcb4c9cf9ae1f69ae9e91462b2950c49e8828b89c2346b9",
		"Fire arrow\nAn arrow of fire which always hits the target.",
		"Feuerpfeil\nEin Pfeil aus Feuer, der immer sein Ziel trifft."
	],
	"spell campfire": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell charm": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell clairvoyence": [
		"e7d3eab12544e1007372c9896e0c3b805f54bcc88f04ed40f673dfd50d55e529",
		"Clairvoyance\nReveals enemies in a wide area around the caster.",
		"Hellsehen\nZeigt Feinde in einem großen Umkreis um den Zaubernden."
	],
	"spell comprehend": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell curse_magic": [
		"99115325f7dc4a450e5f46f03410da60ca992bfdabe4fedb7791f210b084693b",
		"Astral rift\nA stream of pure astral energy that always hits its intended enemy.",
		"Astralriss\nEin Strom reiner Astralenergie, der den anvisierten Gegner immer trifft."
	],
	"spell detect_life": [
		"69c511e112bf71ec5f3fa873efe2241d80afcfeb71707e9bfeb84d264a103ca2",
		"Dead man's sight\nAllows the target to sense all creatures within a certain radius.",
		"Totensicht\nLässt das Ziel alle Wesen in einem bestimmten Umkreis wahrnehmen."
	],
	"spell eagle_sight": [
		"b6ba39acac339550bfa51aa49b2f9bc1ed92abf1a980ece0630584a3b6a58409",
		"Eagle sight\nIncreases sight radius.",
		"Adlerauge\nErhöht den Sichtradius."
	],
	"spell enlarge": [
		"b1a806149b2c73949071cef02bb8c31129ce5efadee0d3d6f1188a8d0cc7e565",
		"Enlargement\nIncreases the size of the selected target.",
		"Vergrößerung\nVergrößert das ausgewählte Ziel."
	],
	"spell feeblemind": [
		"ef6200ba92105fb68b631911f3f6425abb18fbe82e8fff61474b6747e4f78108",
		"Feeblemind\nPrevents your enemy from casting spells for some time (to cast this spell, the target must be visible).",
		"Delirium\nMacht es dem Gegner für bestimmte Zeit unmöglich, einen Zauber einzusetzen (Ziel muss in Sichtweite sein!)."
	],
	"spell fireball": [
		"b5797056c768f225d8bd1cd088dbeb4d10cbea908d05314546626d329896a17b",
		"Fireball\nThis is an area effect spell. The fireball will cause damage to everyone near the explosion.",
		"Feuerkugel\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Personen im Wirkungskreis werden verletzt."
	],
	"spell firewall": [
		"d561fd825d9f93fbf169a93a836b4758e21ecdd1c9da0a3d692a7715a19553b7",
		"Fire wall\nThis is an area effect spell. A wall of fierce fire damages everyone within its range.",
		"Feuerwand\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Personen im Wirkungsbereich werden verletzt."
	],
	"spell fireworks": [
		"da48b37dc44935cbe9f79746c7d7fecfadf8b0885d13e880cfc9d053ff7003cf",
		"Fireworks\nWill only attract the attention of an enemy who sees or hears it, without raising a general alarm.",
		"Feuerwerk\nDer Zauber lockt alle Gegner an, die ihn sehen oder hören. Dabei wird kein Alarm ausgelöst!"
	],
	"spell healing": [
		"1fc92e4fa7b067ba62937efa97a4d7b1620a014adebe0dc82fbdf50c4e8fde5e",
		"Healing\nRestores health damaged in combat.",
		"Heilen\nStellt die Lebenskraft nach einem Kampf wieder her."
	],
	"spell infravision": [
		"09be2a8b0f59a3365bcf5b6dfcd66b9d3e033c074fd25a5040ce5fec59332ae3",
		"Night vision\nEnables one to see as well in darkness as in daylight.",
		"Nachtsicht\nDer Zauber verleiht einem Charakter die Fähigkeit der Nachtsicht."
	],
	"spell inv_lit": [
		"7666393fa68db21bf47824a33a96512ef9bf37ba471a806ce6cfba32d1830c4b",
		"Celestial lightning\nThis is an area effect spell. The lightning strike causes damage to everyone who is close by.",
		"Himmelsleuchten\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Personen im Wirkungsbereich werden verletzt."
	],
	"spell invisibility": [
		"bf7bb33b756933e3c03038f831c44a6c53ea86d31f83db55200e1ff7bb64e269",
		"Invisibility\nThis spell doubles your invisibility to enemies.",
		"Unsichtbar\nDas Ziel dieses Zaubers ist für Gegner doppelt so schlecht zu sehen wie vorher."
	],
	"spell lichdom": [
		"45df0b3d3716a462b8c7a24c934d6437a1a0955b3286d3ef418050c4f8e9c6d8",
		"Dead man\nMakes the target invisible to the undead and Dead man's sight magic, but still visible to normal sight.",
		"Totengestalt\nMacht das Ziel für Untote und den Zauber Totensicht unsichtbar. Für normale Augen bleibt es sichtbar."
	],
	"spell lightning": [
		"ca0f17af50aa580b99287ccfd23ee6bf82b975ec6ec9861032007b3128d4bb61",
		"Lightning\nA lightning strike which always hits the target.",
		"Blitzschlag\nEin Blitzschlag, der immer sein Ziel findet."
	],
	"spell link": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell litnwall": [
		"9f8b7979c19f03b653536020d785e6967ec51a676688d4e64df0a09349bb3f7f",
		"Lightning barrier\nThis is an area effect spell. The barrier causes lightning damage to anyone trying to cross it.",
		"Blitz-Barriere\nDieser Zauber wird auf einen bestimmten Punkt angewendet. Jeder, der die Barriere zu überschreitet, wird verletzt."
	],
	"spell possession": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell prot_acid": [
		"6afbeb590bbc12f988b17654b8d90728bced1fe5dbe825bb48b2b550de943339",
		"Protection from acid\nThe person protected by this spell becomes less vulnerable to acid effects.",
		"Schutz vor Säure\nSchützt die Person, auf die er angewendet wird, vor Verätzungen."
	],
	"spell prot_electro": [
		"5d834b715e67dd99c68d614ec15e4c42cc240a2fd3ed07653c4f0f38785bc2cb",
		"Protection from lightning\nThe person protected by this spell becomes less vulnerable to lightning effects.",
		"Schutz vor Blitzschlag\nSchützt die Person, auf die er angewendet wird, vor Blitzschlag."
	],
	"spell prot_fire": [
		"73d0b3240de121d9133e73f0a20359f4a42010a52f96109c87b16d4b959369dd",
		"Protection from fire\nThe person protected by this spell becomes less vulnerable to the effects of fire.",
		"Schutz vor Feuer\nSchützt die Person, auf die er angewendet wird, vor Verbrennungen."
	],
	"spell regeneration": [
		"77c3dbc1ba1964fafbc8436190508d267cf4708a7d20209362e2dfd1aeeae800",
		"Regeneration\nIncreases the speed of health recovery.",
		"Regeneration\nBeschleunigt die Regeneration."
	],
	"spell rick_magic": [
		"93b21b035cad9c9475f6cb74e0b3e220ab9a99a6aed6e4906a0fb1ad0d0b7ae8",
		"Destruction\nA powerful strike that always hits its intended enemy.",
		"Zerstörung\nEin mächtiger Schlag, der den anvisierten Gegner immer trifft."
	],
	"spell shapechange": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell shrink": [
		"74c488c2bea298568c3d600f8a256c06589ca2aaa2a7502f30b2d1f642b5e7d7",
		"Shrinking\nReduces the size of the selected target.",
		"Schrumpfen\nVerkleinert das ausgewählte Ziel."
	],
	"spell silence": [
		"598e2144f8c3b4dab8aa27e4901b296d3f79f54b1841dca18a38987c3aa6522b",
		"Silence\nThis doubles your \"silence\" value making it twice harder for the enemy to hear you.",
		"Magische Stille\nDas Objekt dieses Zaubers ist vom Gegner doppelt so schlecht zu hören wie vorher."
	],
	"spell slow": [
		"2385b183ea4b0f1edd7e7d023941e8f7533f4e913ba4a64432dba7db1c116082",
		"Deceleration\nAllows you to slow down the speed of blows which are struck and of spell casting.",
		"Verlangsamen\nVerringert die Geschwindigkeit von Angriffen oder Zaubersprüchen."
	],
	"spell speed": [
		"b20dca4ad23f2d81307b24f8bfdf462d115c7f280bb7478fde82ea1cc29472a3",
		"Haste\nAllows you to increase the speed of blows which are struck and of spell casting.",
		"Beschleunigen\nErhöht die Geschwindigkeit von Angriffen oder Zaubersprüchen."
	],
	"spell stench": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"spell strength": [
		"c5967e2951a7d032952a12fc4c073df6ab96a265670189cf85a95fbc30024e08",
		"Strengthen\nAllows you to temporarily increase a character's health and the damage he can cause to enemies.",
		"Zusätzliche Kraft\nErhöht die Stärke des Charakters. Lebenskraft steigt und er kann Gegnern größeren Schaden zufügen."
	],
	"spell stun": [
		"8368e54b6330f982c93360bfe4ce2f37e9b8de330bed3d731b7208d66c96e026",
		"Paralysis\nAllows to paralyse your enemy for a certain period of time (to cast it, the enemy must be visible to you).",
		"Lähmung\nLähmt den Gegner für eine bestimmte Zeit (Das Ziel muss in Sicht sein!)."
	],
	"spell teleport": [
		"610c021c28383db48dc33fd012e236afa9bc154be5c8eaa5484d7fc1cc515250",
		"Teleportation\nInstant displacement from one point to another (to cast this spell, you must see the destination).",
		"Teleportierung\nTransportiert das Objekt sofort von einem Ort an den anderen (Der Zielort muss in Sichtweite sein!)."
	],
	"spell vision_fog": [
		"e54922e9d162b3eff1efc1826e45268982f9bdf6863b32cdaf29554e671cf7bf",
		"Field of vision\nAllows you to see what the spell's target is seeing...",
		"Fremde Augen\nLässt den Charakter den Sichtbereich des Objekts sehen, auf das der Zauber angewendet wurde."
	],
	"spell weak": [
		"7c72454152f8d3bfe6702be8b62a421e6cc379623765362d6240672e2e0ff157",
		"Weaken\nAllows you to temporarily weaken your opponent and lessen the damage he can cause.",
		"Schwächung\nSchwächt für eine gewisse Zeit den Gegner."
	],
	"string item_armor_lower": [
		"4cd86ae047d4d8e1ac310743ef0753ab0fd08b29fffdc92f0609e1cb07c370bd",
		"Light armor",
		"Leichte Rüstung"
	],
	"string item_armor_upper": [
		"8e4b7bb306d204f78317c8b21846aeb5744b17e098a51dd2586b7deaee913149",
		"Heavy armor",
		"Schwere Rüstung"
	],
	"string item_loot": [
		"403dc01e4c4028ae6e9219d828801c748685c1e50573ccc1b57cb70acd5ded38",
		"Item for sale",
		"Beute"
	],
	"string item_quest": [
		"d14b6c14dfcc893ecba31b3b3211df7d22a30a206d30b299526e83451965dc0b",
		"Quest item",
		"Wichtiger Gegenstand"
	],
	"string item_wand": [
		"acc833f11b4798d37c72c6af95fc50750b14e85049b6cd7d81ba61fc19a00d34",
		"Wand",
		"Zauberstab"
	],
	"string item_weapon": [
		"8fd2e86570ef0fd6e6a7ad8a9d3f212a69e6889dfa41c015c636b70ef38f399f",
		"Weapon:",
		"Waffe:"
	],
	"unit antilopa": [
		"f1ed44c3a73c3aec887cb0f17533ebd07b6ac1e90a2f041222a090eb1bc0a2ff",
		"Antelope",
		"Antilope"
	],
	"unit bz11g_dog": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_archer_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_chieftan_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_fighter1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_fighter2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_fighter3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_fireman_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_mage_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_master_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_shava_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_sheriff_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker3_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker4_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_talker5_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz11g_human_warrior_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz12g_human_daughter_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz12g_human_witch_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz13g_dragonblue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz14g_golemhorizontal": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz14g_golemvertical": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz14g_jun_girl_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz14g_rick": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz1h_human_clerk_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz1r_human_fighter_m": [
		"05075cfca102e7f4d3bfcdc3af356b361774db616b18e2ee55dc1c5633df641d",
		"Recruiter",
		"Anwerber"
	],
	"unit bz21k_human_archer1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_fighter1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_fighter2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_fighter3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_fireman_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_governor_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_guard_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_his_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker3_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker4_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_talker4_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_trader_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz21k_human_trapper_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_archer1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_brissen_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_fighter1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_fireman_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_leader_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_lovkach_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_mage_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker3_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker4_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_talker4_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_thief_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz22k_human_woodcuter_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz23k_driad_green_archer1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz23k_driad_green_mage1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz23k_driad_leader_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz23k_unicorn_white": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_alija_f": [
		"11d8b55e8c1855700d798d414dcd2ed676296f2d8d431024d0cd9cfc0acfcd21",
		"Alia",
		"Alia"
	],
	"unit bz2h_human_citizen_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_citizen_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_feiruz_m": [
		"3988c2fa3f73285c2ee25937602415f1c29621212b853f6eaed83f477901410a",
		"Feiruz",
		"Feiruz"
	],
	"unit bz2h_human_fireman_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_karim_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_krrasta_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_peasants_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_peasants_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz2h_human_rindail_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_archer1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_baron_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_bson_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_fighter1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_fighter2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_fighter3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_necro_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_stark_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker3_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker3_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker4_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_human_talker4_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_jun_deva_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz31j_junofil_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz32j_human_doctor_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_blademaster_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_cookie_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_fatboy_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_guard_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_hatul_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_kehel_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_kuzn_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_peasants_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_peasants_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_sahilja_f": [
		"ee3fcd8f1b7d5f1264b175c2a78939758f3d640aab3b5f73e340aa0a08bb5858",
		"Sahilia",
		"Sahilia"
	],
	"unit bz3h_human_student1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_student2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_human_thickboy_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz3h_ratsmall": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz4h_evileye": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz4h_octopus": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz4h_octopus_2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_clothest_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_fireman_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_fruitt_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_jug_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_peasants_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_peasants_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_pod_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_potiont_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_sitter_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_slavetrader_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_smith_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talker_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerf_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerf_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerk1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerk2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerv_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_talkerv_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_van1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz5h_human_van2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_boss_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_firegirl_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_slave_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_slave_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_student1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_student1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_student2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz7h_human_student2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_batred": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_human_thief_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_lizardblue": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_archer1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_archer2_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_fighter1_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_fighter2_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_mage1_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_orc_tanichey_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_shaivar_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit bz8g_wolfwhite": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit cow": [
		"4a7636acc1557b3b9103ce1032b5aabd4e141b447014f39926b727ab9eaed176",
		"Cow",
		"Kuh"
	],
	"unit deer": [
		"967a12189ad864849b5ab710a0a07d9e81b1001da520022bde084816f70877f8",
		"Deer",
		"Reh"
	],
	"unit fq10_goblin_boss": [
		"9d5ea4b0b6125e4a084e3300fecf0d34255168b5c8f74b93beef2ff375d865f0",
		"Go-Go the Third",
		"Go-Go der Dritte"
	],
	"unit fq11_skeletoninvalid": [
		"d62f421155ff6c017d6a9cf112c1f098905c0cd3dab8ecc632f918e473d0bdea",
		"Skeleton legs",
		"Skelettbeine"
	],
	"unit fq12_ogre": [
		"40c3aa9188399cfaa103e35a8f8e53ccb11dc6497119a0bf05b190a28074c5f9",
		"Gluttonous ogre",
		"Gefräßiger Oger"
	],
	"unit fq15_dog": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit fq8_evilbush": [
		"67a71c734131a4db5832388a4b9f2242fd180423ee0943d8e6413ade9c80d287",
		"Mad plant",
		"Verrückte Pflanze"
	],
	"unit fq9_human_clerk_m": [
		"c2fd7df8cf1f04814ac8cf3b330039c10786bdbbc36a81e8ed51b3d182ed2e9c",
		"Official",
		"Diplomat"
	],
	"unit hare": [
		"b1fb7e22a8ed2e84906c596bb47e34f325823a6bf1aff942ab924fcc9e8e18f7",
		"Hare",
		"Hase"
	],
	"unit hero1": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit hero2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit hero3": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit hero4": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit horse_red": [
		"782adb66ca3ee012d4d97c513c51ef248b1899459f5c5eb5ec3f65ea417c0349",
		"Horse",
		"Pferd"
	],
	"unit horse_wild": [
		"77c196afec802502727ed513ae2cebac174a3e2a71592518f96234a7bb50e541",
		"Wild horse",
		"Wildpferd"
	],
	"unit human_hero": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit merc2": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit merc2g": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit merc8": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit pig": [
		"e08bdca2eb6545df543d64a55046ca9e2dcca4edd27349c45b565810bd265437",
		"Pig",
		"Schwein"
	],
	"unit q10k_human_archer_f": [
		"5b0ae02600a0a0b9e0565a214fa9759e9173defe4d6adb77e9809970019834b8",
		"Archer woman",
		"Bogenschützin"
	],
	"unit q10k_human_fighter_m": [
		"3fa079527279f54a28d613bbd05565273d9d19a87054afd126e7c1c63dfce47d",
		"Warrior",
		"Krieger"
	],
	"unit q11h_human_deadman_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit q11h_human_guard_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit q11k_elemental_ice": [
		"e8015277361676ae50548e86da1458016f921c7f745cdd1bb191a365ebe11549",
		"Small ice elemental",
		"Kleiner Eiselementar"
	],
	"unit q12h_human_captain_m": [
		"9c7fa83a5b0b3efe10c1e088c0a8d16fd4c85e6363deb9d6a458864e060371fc",
		"Caravaneer",
		"Karawanenführer"
	],
	"unit q12h_human_citizen_m": [
		"4a08cc2a291060aff3e14ed466c8df3e9c4ea29ad99135b1e9bd9fbae60bf30c",
		"Suspicious townsman",
		"Verdächtiger Stadtbewohner"
	],
	"unit q12h_human_gangster_m": [
		"d0c2a18b816e52abdc6c70522d45cc07e63d38a8fd489544d6a18fd205e133bc",
		"Bandit",
		"Bandit"
	],
	"unit q12j_human_archer1_f": [
		"c951136759390f3e4783d8cf2d0a351cb859056127cd43112203eb05c8600a94",
		"Rookie archer",
		"Einfacher Bogenschütze"
	],
	"unit q12j_human_fighter1_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q12j_human_fighter2_m": [
		"be139bd7b33b6d9f727fc9fc7ebee7caf4b947f1947d6c91e9268674cbc29acf",
		"Officer",
		"Offizier"
	],
	"unit q12j_human_mage_m": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit q13g_human_archer_f": [
		"9a9d2fc93c9a0f8bff5e6de3cd955756b681296eb31aab6183d4832180da893e",
		"Female hunter",
		"Jägerin"
	],
	"unit q13g_human_fighter_m": [
		"bf363caf820ed28fa0ae2e955a712c9ba57c5de7b3a645307969ed6c4e076de2",
		"Hunter",
		"Jäger"
	],
	"unit q13h_human_fighter_m": [
		"7767acafeb498725a53e935c1b1dae6bad294c281392ae83513a1843379dd95d",
		"Drunken guard",
		"Betrunkener Wächter"
	],
	"unit q13h_human_sahilja_f": [
		"11d8b55e8c1855700d798d414dcd2ed676296f2d8d431024d0cd9cfc0acfcd21",
		"Alia",
		"Alia"
	],
	"unit q13h_human_vor_f": [
		"4c8db5b11be0915deeb51a342196f4bdf40cc810749508f2df457d4da563f24b",
		"Shaina",
		"Shaina"
	],
	"unit q13h_human_vor_m": [
		"c2bf6118ba97a843b2015e1c5ea21dfd502b2e7b6666cef549ea0a1549c80270",
		"Thief",
		"Dieb"
	],
	"unit q13k_human_fighter_m": [
		"2d7d7c78c9247230cd14d1a16e24a3a0737de2ae06919da7dffd798a586b1285",
		"Mysterious stranger",
		"Geheimnisvoller Fremder"
	],
	"unit q13k_human_leader_f": [
		"18f10c7b42e4ff51e72010016a4c5c82a82e23eb4f025970d6f40769257ea1e0",
		"Geraldine",
		"Geraldine"
	],
	"unit q14h_human_fighter_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q14h_human_vor_f": [
		"ee3fcd8f1b7d5f1264b175c2a78939758f3d640aab3b5f73e340aa0a08bb5858",
		"Sahilia",
		"Sahilia"
	],
	"unit q14h_human_vor_m": [
		"c2bf6118ba97a843b2015e1c5ea21dfd502b2e7b6666cef549ea0a1549c80270",
		"Thief",
		"Dieb"
	],
	"unit q15g_human_archer_f": [
		"87e9c2695884d22a7a00e8109b166f4de916bf7542bab1495fa9b0e5f1f8d113",
		"Caravan guard woman",
		"Karawanenwächterin"
	],
	"unit q15g_human_fighter_m": [
		"88478ff56700c7cad5a38b561b6cbd2a91f30a614ef062f3a7117bb4ebfed27b",
		"Caravan guard",
		"Karawanenwächter"
	],
	"unit q15g_human_thief_m": [
		"3470392970b6ee414d3ae45debd498e6da41e794f1931822d6a5652c9b0437a3",
		"Free hunter",
		"Freier Jäger"
	],
	"unit q15h_human_sahilja_f": [
		"11d8b55e8c1855700d798d414dcd2ed676296f2d8d431024d0cd9cfc0acfcd21",
		"Alia",
		"Alia"
	],
	"unit q15j_human_fighter1_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q15j_human_fighter2_m": [
		"be139bd7b33b6d9f727fc9fc7ebee7caf4b947f1947d6c91e9268674cbc29acf",
		"Officer",
		"Offizier"
	],
	"unit q15j_human_fighter3_m": [
		"9a65490546f5a92baaff1637a67507fba3e905a8fefd65341015b554a52abc6f",
		"Sentry",
		"Wachposten"
	],
	"unit q15j_human_mage_m": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit q16h_human_fighter_m": [
		"990b1e81d33338ebd99d350e50191ad31b290c7443c1d0fe17ea909abc4026a1",
		"Treasure hunter",
		"Schatzsucher"
	],
	"unit q17h_human_fighter_m": [
		"f76fd4c3fb61d51f256aad038456e58ddf3d7483b8955044f2468ba9217efba0",
		"Kharad",
		"Kharad"
	],
	"unit q17j_human_guard_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit q17j_jun_deva_f": [
		"2eb37697e8b34ea3949ea5b8f1e16a17052625f3e06e08f877d3ed193984c4e5",
		"Tai-Ilara",
		"Tai-Ilara"
	],
	"unit q17j_jun_slave_m": [
		"8cc30327ddc984bc800ed18cc80be240c23e1374e6d517e66860f98114126b2a",
		"Jun",
		"Jun"
	],
	"unit q17j_junofil_m": [
		"a3d116ceb80bd41c9f4171ebe8fc8e0ebf628ac73e606c6aeab0a2a55c4a9c0e",
		"Tui-Len",
		"Tui-Len"
	],
	"unit q17k_human_fighter_m": [
		"34cacff9b3ad1069168012eb441526ae97605a45d407c9cf1ba6f5b1b1505394",
		"Bandit",
		"Bandit"
	],
	"unit q17k_human_his_m": [
		"5f010163df7f1f082b1eb370f3769bc9873172128cb035ad8ecdc8eebcc4e589",
		"Rinas",
		"Rinas"
	],
	"unit q17oh_human_fighter_m": [
		"d86997391d6ee189268993c4a4494a4d8abf1cd924c66b661bf403fa8f67261a",
		"Sleepy guard",
		"Schläfriger Wächter"
	],
	"unit q18g_orc_mage_f": [
		"94507a9221f38875ae999b70bc04bd4b28a607c7e8bb62ad8d3a7e282a97d4a1",
		"Shaman woman with a necklace",
		"Schamanin mit Halskette"
	],
	"unit q18h_human_archer_f": [
		"ab58156a4cc59ddb01816b92ec580984d3ed97ecb2b93773b24e96ef2abf9311",
		"Archer recruit",
		"Schützenrekrut"
	],
	"unit q18h_human_fighter_m": [
		"66b74929c8dafdd41cbeab5d4d47582d738542b89adbd9b81ce1d9cb75bee694",
		"Warrior recruit",
		"Kriegerrekrut"
	],
	"unit q18h_human_mage_f": [
		"462bd95f1c2de398942ab66492ba17cd29b45dfd5c1ebc374be96e7163d6fa3c",
		"Mage recruit",
		"Magierrekrut"
	],
	"unit q18h_human_pufighter1_m": [
		"ae76504d2ff1d8510049931912b4480440bdeead1f3bb57b01a85e278e2b464b",
		"Defender of the last refuge",
		"Verteidiger der letzten Zuflucht"
	],
	"unit q18h_human_pufighter2_m": [
		"ae76504d2ff1d8510049931912b4480440bdeead1f3bb57b01a85e278e2b464b",
		"Defender of the last refuge",
		"Verteidiger der letzten Zuflucht"
	],
	"unit q18k_human_fighter_m": [
		"e9283f8bfd7dc2226a471b69df28757b1fa59d3aef5b840da7792c1904b13914",
		"Crooked",
		"Schiefauge"
	],
	"unit q1j_human_fighter1_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q1j_human_fighter2_m": [
		"be139bd7b33b6d9f727fc9fc7ebee7caf4b947f1947d6c91e9268674cbc29acf",
		"Officer",
		"Offizier"
	],
	"unit q1j_human_fighter3_m": [
		"556b04b8a8cfd046f39e54f22cf636ed439cd1562fc19eacedea3e63c0a379de",
		"Guard",
		"Wache"
	],
	"unit q1j_human_mage_m": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit q1j_zombie_f": [
		"f895224e7625b2ce71df98b1d0b73199fce19dede1d5995aae2ed8a6a540ab2d",
		"Zombified guard woman",
		"Zombifizierte Wächterin"
	],
	"unit q1j_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit q20h_human_mage_m": [
		"09cde9f83601c1dfb0467f24d4846077ef41b567463846d33deb4769a668bf03",
		"Necromancer researcher",
		"Nekromantenforscher"
	],
	"unit q20j_cyclop": [
		"a014c13c938616a929ecb35a3339cb00aa72804131017533492db12fdb33ebc1",
		"Cyclops",
		"Zyklop"
	],
	"unit q20j_dragon": [
		"20c2b73e0d316aa9c6e84da4db86c388d46cff2758b93d803efd63dd6a1ab099",
		"Dragon",
		"Drache"
	],
	"unit q21g_human_witch_f": [
		"1c887b285bf69eb0ecd37702e17c558ce052deeb352fcea32386bf6bdc3bc9dc",
		"Estera",
		"Estera"
	],
	"unit q21h_human_lab_f": [
		"05d92c96024e89bcb40d9ced3ae74c91d4873f2c57b92b0d22630b1f3250400a",
		"Laboratory assistant",
		"Laborantin"
	],
	"unit q21h_zombie1_m": [
		"436a1cfaacab5d080670fd0053cc7b8db19ace4d22900a12b79db4a027f558b3",
		"Zombified scholar",
		"Zombifizierter Gelehrter"
	],
	"unit q21j_human_archer1_f": [
		"c951136759390f3e4783d8cf2d0a351cb859056127cd43112203eb05c8600a94",
		"Rookie archer",
		"Einfacher Bogenschütze"
	],
	"unit q21j_human_baron_m": [
		"9f4ec4735b22626195b790b8d14e79f237904876c641f1070f2004910a7b6b0d",
		"Baron Virill",
		"Baron Virill"
	],
	"unit q21j_human_dartas_m": [
		"f17aafbfdbf058ffa09ff02bd2efda8b009c015e71e0f0bcb4c5b5fc1f7e4124",
		"Dartas",
		"Dartas"
	],
	"unit q21j_human_fighter1_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q21j_human_fighter2_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q21j_human_fighter3_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit q21j_human_mage_m": [
		"dd94484b15a77f70913b2f56eacf387a96790e46ad4e60bcfcb65943f752948a",
		"Magician",
		"Zauberer"
	],
	"unit q21j_shadow": [
		"695e5b356990833394c0871ab6992eacaf5319675e0ad2fe2a3b7f7a94c1e5be",
		"Shadow",
		"Schatten"
	],
	"unit q21j_skeleton": [
		"80bcfca180c469706c6488e69bc2c00f9a2d4779895fd7bac12392a07b86fa8f",
		"Reinforced armoured skeleton",
		"Verstärktes gepanzertes Skelett"
	],
	"unit q21j_undead_archer_m": [
		"1cee735bab03ca4e69762350f84caae2a1adc05dd024c1f64c378c028314ea90",
		"Ghoul archer",
		"Ghulschütze"
	],
	"unit q21j_undead_fighter1_m": [
		"642b034f66e9185d252e5b9674aa77a59a1a09c35b92ca059ede6c7600149655",
		"Ghoul warrior",
		"Ghulkrieger"
	],
	"unit q21j_undead_fighter2_m": [
		"642b034f66e9185d252e5b9674aa77a59a1a09c35b92ca059ede6c7600149655",
		"Ghoul warrior",
		"Ghulkrieger"
	],
	"unit q21j_undead_mage_m": [
		"fa92b69d67f2b695d783b07c866a6c252421f67638411f5c9076264a437dcc3c",
		"Ghoul mage",
		"Ghulmagier"
	],
	"unit q21j_zombie_f": [
		"b8bc41d8cb9e0071758c4d349a5ec1e347d28fc99fb371924b2664e3a2cfcd40",
		"Zombified warrior woman",
		"Zombifizierte Kriegerin"
	],
	"unit q21j_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit q21oh_ogre": [
		"a60433b8529198ba59d5dd4db0474cc2107ec797c75fe2f4c3435b95ef8d5207",
		"Sand ogre",
		"Sandoger"
	],
	"unit q21oh_troll_black": [
		"6f161167abdeac3a6a447c0c38165868d1e06daa6a07c440cad46e8f5f01a645",
		"Black troll",
		"Schwarzer Troll"
	],
	"unit q22g_orc_mage_f": [
		"4a9808e94e20ff86e21bb74f6169154b759adef39e5bab27fdf9c9fcd7630e3f",
		"Shaman with a cogwheel",
		"Schamane mit Zahnrad"
	],
	"unit q22h_octopus": [
		"806717afba7a166fda93fade6ee7797a5a661e24d2505d4d666bd73048080d47",
		"Adult wormhead",
		"Ausgewachsener Wurmkopf"
	],
	"unit q23g_human_archer_f": [
		"b5d913c219981a423bce14bc667b2ab4e846b462e7290aa12bf30caa09828c22",
		"The Chosen One's archer",
		"Bogenschützin des Auserwählten"
	],
	"unit q23g_human_fighter_m": [
		"bad56b0476bb94ed7743874fa8dd12e8e5d97143c68bfdb3b29578a2b9566c4f",
		"The Chosen One's warrior",
		"Krieger des Auserwählten"
	],
	"unit q23g_human_mage_f": [
		"2247f8eb183f05054b85ee730063cc34ec04d2603bae342151ca28f48e756724",
		"The Chosen One's sorceress",
		"Zauberin des Auserwählten"
	],
	"unit q24g_ogre": [
		"fe31741e4684801caf47dd91673d5de3728e9d589cbdc097698f68707dba2471",
		"Ogre elder",
		"Ogerältester"
	],
	"unit q24h_human_hostage1_m": [
		"eb55eac3a781676c6f15000537e0b2c4ec2dcc4d9e5780b91e1c994268057c4c",
		"Hostage",
		"Geisel"
	],
	"unit q24h_human_hostage2_m": [
		"a8d8a80d02982454d2d7ea8a93b4ecd0e551b1cc37209c30eed20f3a514ea6e6",
		"Captive",
		"Gefangener"
	],
	"unit q24h_human_raz1_m": [
		"c1de781e0725d1596923e6dca3a5488a33fb42f9b9846f5fb84db1bd9ffc58be",
		"Inexperienced rapist",
		"Unerfahrener Vergewaltiger"
	],
	"unit q24h_human_raz2_m": [
		"6ed98d77d73b6bec1067d155be099e8ccab2b9a6a4c237ee57f72d2d094b7c38",
		"Born killer",
		"Geborener Mörder"
	],
	"unit q25g_human_archer_f": [
		"3b7a70b6f5f061f513c751a1bc88cdd9b32acb3cbf0fd832b4d943896afac041",
		"Experienced free huntress",
		"Erfahrene freie Jägerin"
	],
	"unit q25g_human_fighter_m": [
		"cff951d7b4aa40c3a84d6ed996378f599b47500b20445705ec106ee87f598b67",
		"Experienced free hunter",
		"Erfahrener freier Jäger"
	],
	"unit q25g_human_mage_f": [
		"b04ac4bedfb3435a4cbf1b6c957830af0f6b93baa59732c9a5ed8c411d48f2f6",
		"Experienced free sorceress",
		"Erfahrene freie Zauberin"
	],
	"unit q25g_orc_archer_f": [
		"185f99b51870cc74448b3898e8311e9a49102696c29ee9e5ada7f520694681e9",
		"Adult female Orc",
		"Ausgewachsener weiblicher Ork"
	],
	"unit q25g_orc_fighter_m": [
		"69cf0ba21b815cd1c7dfe36a0146d21cd0e442a19ca2e421bf8d799a8cfa7937",
		"Adult Orc",
		"Ausgewachsener Ork"
	],
	"unit q25g_orc_mage_f": [
		"1b490666dda06eee85c5a5c6790be3f42f39244b45ad759d28acd3ec7eab8aad",
		"Skillful Orc seer",
		"Erfahrener Ork-Seher"
	],
	"unit q2g_ogre": [
		"550622afa372e1fc9a7dffcc451c609e7f399a8ea96dbdc5d0fd75ada757e253",
		"Sleepy ogre",
		"Schläfriger Oger"
	],
	"unit q2h_human_peasants_f": [
		"cfccf1939e53c3538861fbaeab945fc2a6af638c19eadfc5e4340b3d5794d605",
		"Female official",
		"Beamtin"
	],
	"unit q2h_human_peasants_m": [
		"c2fd7df8cf1f04814ac8cf3b330039c10786bdbbc36a81e8ed51b3d182ed2e9c",
		"Official",
		"Diplomat"
	],
	"unit q2j_zombie_f": [
		"f895224e7625b2ce71df98b1d0b73199fce19dede1d5995aae2ed8a6a540ab2d",
		"Zombified guard woman",
		"Zombifizierte Wächterin"
	],
	"unit q2j_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit q2k_tigerwhite": [
		"b39a9c7aadcb32ff4fee7a7f527676b3580988c226581237e2ef74be3f5dfe44",
		"Tame snow tiger",
		"Zahmer Schneetiger"
	],
	"unit q3j_human_fighter_m": [
		"6906c395ece3e4fbf9d3fc008496e3bc438bdfc975c1bd2d6d69f6825a679de3",
		"Khadaganian soldier",
		"Khadaganischer Soldat"
	],
	"unit q3k_driad_white_mage": [
		"45300570fb5238faa23dd2957c681819ace2e2ff37963a3547d097d2bdb842e9",
		"Woodland mage\n(White Clan)",
		"Waldmagier\n(Weißer Clan)"
	],
	"unit q4j_human_necro_m": [
		"dadaa3d43d15c185bb33f101cfb81adcadcf2f494224de0b72223c14b6fcbc96",
		"Old necromancer",
		"Alter Totenbeschwörer"
	],
	"unit q5h_human_kapr_m": [
		"2dd2a2103c72a7b938c209226fc303185ba8f537fadac1089a78b3552f0aa76c",
		"Captain of the guard",
		"Hauptmann der Wache"
	],
	"unit q5j_skeleton": [
		"7cbc89c927d241d1eddfcc832a22b010c212a38de4e2a6541e012a7ad7a8e998",
		"Hero's skeleton",
		"Skelett eines Helden"
	],
	"unit q6g_batred": [
		"71e53cbd4b2431401273e48033a5b5bf16557aa05fe53bfb7a3bd5aa79ef08d2",
		"Young bat",
		"Junge Fledermaus"
	],
	"unit q6g_orc_fighter_m": [
		"aa782a265f2f4936d335c413f6192d80f09f55b00195798f5b5259055dc8ec25",
		"Young Orc",
		"Junger Ork"
	],
	"unit q6g_succub": [
		"fbc5a6aa0c2af23a456ecb67daa99b5f73de4bfb8acce666b82d3010d22f7f2d",
		"Young cowardly harpy",
		"Junge feige Harpyie"
	],
	"unit q6g_urktar_m": [
		"8752b5a568e700a39148034f818946c9ac9f00ca1f2f8b7d837c35ecd6ecbbfb",
		"Urk-Tar",
		"Urk-Tar"
	],
	"unit q6h_human_letter_m": [
		"6c4b668dd9d212f55efcb724ff21f1b7579f98f25c683050705aca99f973e1d6",
		"Messenger",
		"Bote"
	],
	"unit q6h_human_zasada_m": [
		"239f0aee26394a27e701ed5b9e224337923b7cb0233f1ee870f3c39fa25f397e",
		"Spy",
		"Spion"
	],
	"unit q7g_orc_wife_f": [
		"40bf7b24efcbeb1bea17fa8a682779684d64e939192a9bdbec17226d53230ae7",
		"Chief's wife",
		"Frau des Häuptlings"
	],
	"unit q7j_human_dartas_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit q8k_tigerwhite": [
		"2f02792b268f01207eda87fc9f9fdd7d7101275cf7380578529794fc49c1a9bf",
		"Ferocious snow tiger",
		"Wilder Schneetiger"
	],
	"unit q9g_lizardgreen": [
		"58a5ae824bb0e41b4afac9b5ee391517d81dcd1d30e16d495b88aac2d5617efa",
		"Forest lizard",
		"Waldechse"
	],
	"unit q9g_orc_archer_f": [
		"f3f662d470fb0905b0b7502384f6fdf62b04fe1c05374a1a7421fc9c769ae474",
		"Young female Orc",
		"Junger weiblicher Ork"
	],
	"unit q9g_orc_fighter_m": [
		"aa782a265f2f4936d335c413f6192d80f09f55b00195798f5b5259055dc8ec25",
		"Young Orc",
		"Junger Ork"
	],
	"unit q9g_orc_mage_f": [
		"e8d2b02720595d47c5df70c9c873e6325110b6245f7c32c5363019d59d0d7730",
		"Untrained shaman",
		"Unausgebildeter Schamane"
	],
	"unit q9h_human_kapr_m": [
		"89abd3269da7c994d3e35f76d62ad2ba1bb0099633c3bd6b31b87ceb6dcacb38",
		"Blackmailer",
		"Erpresser"
	],
	"unit q9k_human_fighter_m": [
		"0c22e8300895f7d8ae0e46afb23808fd3aa54e6ec69b13e327eaa6bb4a1772ff",
		"Spy",
		"Spion"
	],
	"unit zebra": [
		"dfa1179f0e470d34bee8768953d4371687b131213ac9fcf1e2f6223580e72894",
		"Zebra",
		"Zebra"
	],
	"unit zone10_banshee_fighter": [
		"175f66a3ff6bb0c776d1f7bb4794fb92521fb880e0779948878f0705128ef3f8",
		"Swamp banshee",
		"Sumpfbanshee"
	],
	"unit zone10_banshee_mage": [
		"027b0b8177c4af328cb995f608fa760f07b31575291f5ced53d07d12140cc3f1",
		"Magical swamp banshee",
		"Magische Sumpfbanshee"
	],
	"unit zone10_batred": [
		"27fb09ebc59fdac6565b589d21f9cfc2e16342a886a65d9d55a96799f6a0b5e9",
		"Adult mouse",
		"Ausgewachsene Maus"
	],
	"unit zone10_boardark1": [
		"875553ed96f97cb8996f9fc174e0b28ce31a8e9434d647d4a35aff8a042fcd77",
		"Young black boar",
		"Junges schwarzes Wildschwein"
	],
	"unit zone10_boardark2": [
		"f60abc4d56565371bc11732c2779f6b66a395aa421884baf7ea56ef58b2db6cf",
		"Adult black boar",
		"Ausgewachsenes schwarzes Wildschwein"
	],
	"unit zone10_dog": [
		"302177e9823d74e189d76b86e483d341713a5169a0ae4aac3d48616fc935c9fb",
		"Guard dog",
		"Wachhund"
	],
	"unit zone10_goblin_archer": [
		"c71fe141babcb817793135629424617cdd500fef8764f16f94bd470821aca9e3",
		"Veteran Goblin with a sling",
		"Goblin-Veteran mit Schleuder"
	],
	"unit zone10_goblin_fighter": [
		"f4fdb3b0422e00719331bb4ee93a06138a303b7158159f65ba9b01335bb70108",
		"Veteran Goblin with a spear",
		"Goblin-Veteran mit Speer"
	],
	"unit zone10_human_archer1_f": [
		"ecf69cd3719c78896ededc1c1b972485a7e44cad6cf437d4bba86769b358a8ff",
		"Experienced archer woman",
		"Erfahrene Bogenschützin"
	],
	"unit zone10_human_archer2_f": [
		"a3ca60eae8a3011b3cd57a2855bfa1e178be00f30131e318b4aefacb7eb8af8f",
		"Village woman",
		"Dorfbewohnerin"
	],
	"unit zone10_human_fighter1_m": [
		"e40053214149d57aac191ced311e4cd99406bf7930673181eefa8e5dc1f6aef2",
		"Soldier",
		"Soldat"
	],
	"unit zone10_human_fighter2_m": [
		"a82dfda7cb05fb65e39038a66f8c6928c970eba5e2ce2b6c4bc44a9e20406710",
		"Villager",
		"Dorfbewohner"
	],
	"unit zone10_human_fighter3_m": [
		"f0244e7c474178d22e0c3838f9775bb37e7bfe39a11b03634ac74acd32bb490c",
		"Captain",
		"Hauptmann"
	],
	"unit zone10_human_mage1_f": [
		"a33385bf627a8a2a96b0b0e96322aa298660faa308c4916f1d95e78965f669aa",
		"Sorceress",
		"Zauberin"
	],
	"unit zone10_human_mage2_f": [
		"0fbca11180ead3bccabeed829ff98a79b12eda0fdf36ab3f3ae2d7b0908da498",
		"Experienced sorceress",
		"Erfahrene Zauberin"
	],
	"unit zone10_ogre": [
		"fe994381b35852ceb948a436c9b63a51122c375b5589db059cd225251f3ad76f",
		"Displeased ogre",
		"Unzufriedener Oger"
	],
	"unit zone10_toad": [
		"e6513be90358375cbf9428fbf40b22c6bde8a0d449684104b2a9bf4daff2e596",
		"Adult poisonous toad",
		"Ausgewachsene giftige Kröte"
	],
	"unit zone10_trollgreen": [
		"17bad49d6f2696651f401fe0201dc133804a01e9d79fbe109ba020bb7a081de3",
		"Wild green troll",
		"Wilder grüner Troll"
	],
	"unit zone10_wolfwhite1": [
		"fcd41553cd714baf059d3c456a04a377cf67e4a6a20ae5dcfa2c26a371a3f010",
		"Young white wolf",
		"Junger weißer Wolf"
	],
	"unit zone10_wolfwhite2": [
		"aedbc5dd29b81e00834c2253fee056e04430dcf46d71a7006416c504254e732f",
		"Adult white wolf",
		"Ausgewachsener weißer Wolf"
	],
	"unit zone11_batred": [
		"71e53cbd4b2431401273e48033a5b5bf16557aa05fe53bfb7a3bd5aa79ef08d2",
		"Young bat",
		"Junge Fledermaus"
	],
	"unit zone11_boarred1": [
		"178c0b324b9d3dd2ec6c150ea743bc55cf8b5100b976f24c078ee65ecd6a7b13",
		"Young boar",
		"Junges Wildschwein"
	],
	"unit zone11_boarred2": [
		"1eb77425a626ade605358e5787b8bc45c561c1afb33f922fa66ad4efe99bb5eb",
		"Adult boar",
		"Ausgewachsenes Wildschwein"
	],
	"unit zone11_cyclop": [
		"80d7b43b9f9af5b7f7412d38bfca5ba3f5136a540177becf3d5fb8bfee339d30",
		"Old cyclops",
		"Alter Zyklop"
	],
	"unit zone11_dragonblue": [
		"97aa354514e99151f96fa9da6a343fe51a13baa0e5cebd5ad349a60bf57cb1cd",
		"Blue dragon",
		"Blauer Drache"
	],
	"unit zone11_dragongreen": [
		"b61674ff99b6b2d11a7e313dff31d19167e196f21b03a9aa35053240696d907b",
		"Green dragon",
		"Grüner Drache"
	],
	"unit zone11_lizardblue": [
		"431b15a0bae6d004c5ab053797444f4b9bcd0dd9a1efc926aae71a7103866468",
		"Lake lizard",
		"See-Echse"
	],
	"unit zone11_lizardgreen": [
		"58a5ae824bb0e41b4afac9b5ee391517d81dcd1d30e16d495b88aac2d5617efa",
		"Forest lizard",
		"Waldechse"
	],
	"unit zone11_tigerred1": [
		"4f65d14c7a2ef7eba60619316da5dd38f3f28327474b6975f32fa73324c0b997",
		"Young tiger",
		"Junger Tiger"
	],
	"unit zone11_tigerred2": [
		"003c6c8220a58b302d9bf92e95d391d9e283f1b7ab54dcfe8b049ffaedf97492",
		"Adult tiger",
		"Ausgewachsener Tiger"
	],
	"unit zone11_toad": [
		"7b0c21fd2d1acf6c7ebfbeb76d584eb41399108897064ecf1d9aaf7c93df7ed7",
		"Young poisonous toad",
		"Junge giftige Kröte"
	],
	"unit zone11_trollgreen": [
		"eed7f39605cf549927648f0f66fce308f1a8935504a2b980a94bf76de9921f9f",
		"Green troll",
		"Grüner Troll"
	],
	"unit zone11_wolfgrey1": [
		"866366133f29eb326ec4ae8ae311e62a36986e62b4e5cd39cc095c3976af72d8",
		"Young grey wolf",
		"Junger grauer Wolf"
	],
	"unit zone11_wolfgrey2": [
		"76353a724e0d1913ec12bfcdd1b6ddc03aa09be776cbda5a926f1385e8fe286e",
		"Adult grey wolf",
		"Ausgewachsener grauer Wolf"
	],
	"unit zone11dun1_lizardblue": [
		"431b15a0bae6d004c5ab053797444f4b9bcd0dd9a1efc926aae71a7103866468",
		"Lake lizard",
		"See-Echse"
	],
	"unit zone11dun1_lizardmonstr": [
		"7c934e5efc9f81fc2ef09a38c7ebf14f54f405667a2c6798bf7c008d1f8c9d00",
		"Tomb guardian",
		"Grabwächter"
	],
	"unit zone12_batred": [
		"1af803b44b9169e5fa0efcf495caa38f928ce0af7a9356f4ffbbe33229d7eec8",
		"Mature mouse",
		"Alte Maus"
	],
	"unit zone12_elemental_earth": [
		"9fc830795e0cac4fd5cc31e1a92e8d2542c3b273c876aa249f8d8f30dc21c966",
		"Stone elemental",
		"Steinelementar"
	],
	"unit zone12_evileye": [
		"3c82ecd9e4204b4f565719db7b19eb6f8d3f939585cd78a76832f39c46b0f77c",
		"Evil eye",
		"Böses Auge"
	],
	"unit zone12_goblin_archer": [
		"1c44127226dd0befdd5288659af986cd76808633ca313b4041c8ccd15f198e0c",
		"Trained Goblin with a sling",
		"Ausgebildeter Goblin mit Schleuder"
	],
	"unit zone12_goblin_fighter": [
		"0be8db871c57113e61aacc8e94338fe6392189454507ec70b6b24e6a65c9861d",
		"Trained Goblin with a spear",
		"Ausgebildeter Goblin mit Speer"
	],
	"unit zone12_orc_archer1_f": [
		"76a06d5fa3806d1a774e98b5402da2931e85e8294240f584de0a6b823b82e7a3",
		"Mature cave orc woman",
		"Alte Höhlenorkin"
	],
	"unit zone12_orc_fighter1_m": [
		"105ca38cb58132c6f7c3d145e75fd5d9f6f0296d04a9ee2874c8e0a7b3b59398",
		"Mature cave orc",
		"Alter Höhlenork"
	],
	"unit zone12_orc_mage1_f": [
		"69a9438497fab19d33dec652709eae30a76385acec7eea5a126a13cc5696403e",
		"Mature cave shaman",
		"Alter Höhlenschamane"
	],
	"unit zone12_scrab": [
		"62ca416d00f7e5dd7b1c6b4c55f027ff2b7589be3441238c68064d4bcd5ce3b8",
		"Armadillo",
		"Blutreißer"
	],
	"unit zone13_banshee_fighter": [
		"175f66a3ff6bb0c776d1f7bb4794fb92521fb880e0779948878f0705128ef3f8",
		"Swamp banshee",
		"Sumpfbanshee"
	],
	"unit zone13_banshee_mage": [
		"027b0b8177c4af328cb995f608fa760f07b31575291f5ced53d07d12140cc3f1",
		"Magical swamp banshee",
		"Magische Sumpfbanshee"
	],
	"unit zone13_boardark": [
		"af5d14d7169f6e869e4d78ce3a834b06ef3649184e071d8af44dde9722ddde4c",
		"Veteran black boar",
		"Schwarzes Wildschwein (Veteran)"
	],
	"unit zone13_trollgreen": [
		"8b70faac43f64482c4ff59d5c954621ed961844a158396605d430d46903ac740",
		"Tamed green troll",
		"Gezähmter grüner Troll"
	],
	"unit zone13_willowisp": [
		"8af8a3f7d5f3ffe89933076da1826057e24f095fb8e365a43dbfe2247b09650a",
		"Burning Will-o'-the-wisp",
		"Brennendes Irrlicht"
	],
	"unit zone13_wolfwhite": [
		"20e258539ac508fb7dfde0676d53375ba5153d0c063e73267376f31ffb9715b5",
		"Veteran white wolf",
		"Weißer Wolf (Veteran)"
	],
	"unit zone14_elemental_earth": [
		"9fc830795e0cac4fd5cc31e1a92e8d2542c3b273c876aa249f8d8f30dc21c966",
		"Stone elemental",
		"Steinelementar"
	],
	"unit zone14_elemental_lava": [
		"29e9afd129c118adbfbd682dd6101a38f421c447c13f16d74e621c989d2e63ed",
		"Lava elemental",
		"Lava-Element"
	],
	"unit zone14_golem_horizontal": [
		"7c6e8b5e137e6811456162ff7c78ea0c33d75ff29f4b6097275f4122b8d0fb98",
		"Golem",
		"Golem"
	],
	"unit zone14_golem_vertical": [
		"7c6e8b5e137e6811456162ff7c78ea0c33d75ff29f4b6097275f4122b8d0fb98",
		"Golem",
		"Golem"
	],
	"unit zone15_banshee_fighter": [
		"175f66a3ff6bb0c776d1f7bb4794fb92521fb880e0779948878f0705128ef3f8",
		"Swamp banshee",
		"Sumpfbanshee"
	],
	"unit zone15_banshee_mage": [
		"027b0b8177c4af328cb995f608fa760f07b31575291f5ced53d07d12140cc3f1",
		"Magical swamp banshee",
		"Magische Sumpfbanshee"
	],
	"unit zone15_boarred1": [
		"1eb77425a626ade605358e5787b8bc45c561c1afb33f922fa66ad4efe99bb5eb",
		"Adult boar",
		"Ausgewachsenes Wildschwein"
	],
	"unit zone15_dog": [
		"302177e9823d74e189d76b86e483d341713a5169a0ae4aac3d48616fc935c9fb",
		"Guard dog",
		"Wachhund"
	],
	"unit zone15_human_archer1_f": [
		"ecf69cd3719c78896ededc1c1b972485a7e44cad6cf437d4bba86769b358a8ff",
		"Experienced archer woman",
		"Erfahrene Bogenschützin"
	],
	"unit zone15_human_archer2_f": [
		"2472190cac1f57a3a3da2d019ef09536936df5862fe6d9f1c7763654e28b02c0",
		"Archer woman",
		"Bogenschützin"
	],
	"unit zone15_human_boss_m": [
		"d1cc181cb94f054accd1abe7f174b7eb57ea13c31f0007c6c46f99bea9cf5c98",
		"Khador the Rowdy",
		"Khador das Raubein"
	],
	"unit zone15_human_citizen_f": [
		"a3ca60eae8a3011b3cd57a2855bfa1e178be00f30131e318b4aefacb7eb8af8f",
		"Village woman",
		"Dorfbewohnerin"
	],
	"unit zone15_human_citizen_m": [
		"a82dfda7cb05fb65e39038a66f8c6928c970eba5e2ce2b6c4bc44a9e20406710",
		"Villager",
		"Dorfbewohner"
	],
	"unit zone15_human_elder_m": [
		"f07e57ed3ddf1b23083f62a3411dcc93ad6a1a8656bfa4e7687d589d8c8dc95a",
		"Rivar the Hulk",
		"Rivar der Mächtige"
	],
	"unit zone15_human_fighter1_m": [
		"e40053214149d57aac191ced311e4cd99406bf7930673181eefa8e5dc1f6aef2",
		"Soldier",
		"Soldat"
	],
	"unit zone15_human_fighter2_m": [
		"15595101c10d053532958bca90a02b87af90c2dc226d70c58e9547c5f5c774c7",
		"Warrior",
		"Krieger"
	],
	"unit zone15_human_mage1_f": [
		"0fbca11180ead3bccabeed829ff98a79b12eda0fdf36ab3f3ae2d7b0908da498",
		"Experienced sorceress",
		"Erfahrene Zauberin"
	],
	"unit zone15_human_master_m": [
		"41ae58641bc775aa3520a28df190504ab673f948dcf1c99b2474b99463a9038c",
		"Babur the Tightfist",
		"Babur der Faustschwinger"
	],
	"unit zone15_ogre": [
		"636d8f334f66f90a21c6047e132eee9853db40fca0a0210b8db02cbb03662cad",
		"Lonely robbed ogre",
		"Einsamer beraubter Oger"
	],
	"unit zone15_pyatak": [
		"4f226bd134eedac13758ed6059e9e617bf41d98ab8f1f447f02800678007bacc",
		"Pyatak the angry boar",
		"Pjatak, der wütende Eber"
	],
	"unit zone15_toad1": [
		"7b0c21fd2d1acf6c7ebfbeb76d584eb41399108897064ecf1d9aaf7c93df7ed7",
		"Young poisonous toad",
		"Junge giftige Kröte"
	],
	"unit zone15_toad2": [
		"773d416937395291d0ef7759f6ddda63f25e5e70aa0c1d26d36de15c1ed1f1da",
		"Strong poisonous toad",
		"Starke giftige Kröte"
	],
	"unit zone15_wolfgrey1": [
		"76353a724e0d1913ec12bfcdd1b6ddc03aa09be776cbda5a926f1385e8fe286e",
		"Adult grey wolf",
		"Ausgewachsener grauer Wolf"
	],
	"unit zone16_banshee_fighter": [
		"175f66a3ff6bb0c776d1f7bb4794fb92521fb880e0779948878f0705128ef3f8",
		"Swamp banshee",
		"Sumpfbanshee"
	],
	"unit zone16_banshee_mage": [
		"027b0b8177c4af328cb995f608fa760f07b31575291f5ced53d07d12140cc3f1",
		"Magical swamp banshee",
		"Magische Sumpfbanshee"
	],
	"unit zone16_batred": [
		"1af803b44b9169e5fa0efcf495caa38f928ce0af7a9356f4ffbbe33229d7eec8",
		"Mature mouse",
		"Alte Maus"
	],
	"unit zone16_boarred1": [
		"178c0b324b9d3dd2ec6c150ea743bc55cf8b5100b976f24c078ee65ecd6a7b13",
		"Young boar",
		"Junges Wildschwein"
	],
	"unit zone16_boarred2": [
		"1eb77425a626ade605358e5787b8bc45c561c1afb33f922fa66ad4efe99bb5eb",
		"Adult boar",
		"Ausgewachsenes Wildschwein"
	],
	"unit zone16_goblin_archer1": [
		"c71fe141babcb817793135629424617cdd500fef8764f16f94bd470821aca9e3",
		"Veteran Goblin with a sling",
		"Goblin-Veteran mit Schleuder"
	],
	"unit zone16_goblin_fighter1": [
		"f4fdb3b0422e00719331bb4ee93a06138a303b7158159f65ba9b01335bb70108",
		"Veteran Goblin with a spear",
		"Goblin-Veteran mit Speer"
	],
	"unit zone16_ogre1": [
		"1c38e01e94cbd03441e24e8d9a0ca181df4546e44b665ef07574b7a17eeb6e73",
		"Famished ogre",
		"Ausgehungerter Oger"
	],
	"unit zone16_ogre2": [
		"560fc6d4c1c0b6e0c37337a5660c7caed786be8be2557e53ad5a7f45a899ac97",
		"Ogre chief",
		"Ogerhäuptling"
	],
	"unit zone16_orc_archer1_f": [
		"ee8c11f6086e79c22d126b24a3aa63c9ee5668b6aefd22cc6a9dba24c8dcad71",
		"Adult island orc woman",
		"Ausgewachsene Inselorkin"
	],
	"unit zone16_orc_archer2_f": [
		"9b7f599d6e246a9038f9429ed1a0084d1261683ddfb7efe959289cc1a506cde8",
		"Orc overseer woman",
		"Orkaufseherin"
	],
	"unit zone16_orc_archer3_f": [
		"786f891a6bb1383e77f1ac4d33b9c4a89dcd848bd119bbda7ec84c0b7666cf9b",
		"Orc assassin woman",
		"Orkassassinin"
	],
	"unit zone16_orc_archer4_f": [
		"773322a67f7ec627f26b1d0321306a7ca24d273cd3d92b97b6804309f65b052f",
		"Sharpshooting island orc woman",
		"Treffsichere Inselorkin"
	],
	"unit zone16_orc_fighter1_m": [
		"e14b22781d69102b543a8503917e8143785950578d23da7e51e91e428e622422",
		"Adult island orc",
		"Ausgewachsener Inselork"
	],
	"unit zone16_orc_fighter2_m": [
		"7ee9557ba117e1f845960acf43322819f3605e75bd4ed9a04d0854624b7a1c49",
		"Orc overseer",
		"Orkaufseher"
	],
	"unit zone16_orc_fighter3_m": [
		"ff32604f79cc499cd0a074351055d53ba138e18fd70782f98ba19108b02d827e",
		"Orc assassin",
		"Orkassassine"
	],
	"unit zone16_orc_mage1_f": [
		"722c34afc89a62bd0f4ce9aa079cf9e5aa2f144efedd7a8ff3dd85f02edf40f2",
		"Trained island shaman",
		"Ausgebildeter Inselschamane"
	],
	"unit zone16_orc_mage2_f": [
		"d20bbcf8b68e62e4a8b0d79fbb363e7268fa3ca39f8aca9b32308b2e103bca13",
		"Shaman overseer",
		"Schamanenaufseher"
	],
	"unit zone16_orc_mage3_f": [
		"e1670552e10fbf76757799f36fbe1fc492264584eca278f3270dc737fa942216",
		"Shaman assassin",
		"Schamanenassassine"
	],
	"unit zone16_tigerred1": [
		"003c6c8220a58b302d9bf92e95d391d9e283f1b7ab54dcfe8b049ffaedf97492",
		"Adult tiger",
		"Ausgewachsener Tiger"
	],
	"unit zone16_tigerred2": [
		"1000a2539948b153effc5eaffc0349d14873fa6540fa63b58ebf974e2836aaf3",
		"Strong tiger",
		"Starker Tiger"
	],
	"unit zone16_toad1": [
		"7b0c21fd2d1acf6c7ebfbeb76d584eb41399108897064ecf1d9aaf7c93df7ed7",
		"Young poisonous toad",
		"Junge giftige Kröte"
	],
	"unit zone16_toad2": [
		"773d416937395291d0ef7759f6ddda63f25e5e70aa0c1d26d36de15c1ed1f1da",
		"Strong poisonous toad",
		"Starke giftige Kröte"
	],
	"unit zone16_trollgreen": [
		"17bad49d6f2696651f401fe0201dc133804a01e9d79fbe109ba020bb7a081de3",
		"Wild green troll",
		"Wilder grüner Troll"
	],
	"unit zone16_willowisp": [
		"8af8a3f7d5f3ffe89933076da1826057e24f095fb8e365a43dbfe2247b09650a",
		"Burning Will-o'-the-wisp",
		"Brennendes Irrlicht"
	],
	"unit zone16_wolfgrey1": [
		"866366133f29eb326ec4ae8ae311e62a36986e62b4e5cd39cc095c3976af72d8",
		"Young grey wolf",
		"Junger grauer Wolf"
	],
	"unit zone16_wolfgrey2": [
		"76353a724e0d1913ec12bfcdd1b6ddc03aa09be776cbda5a926f1385e8fe286e",
		"Adult grey wolf",
		"Ausgewachsener grauer Wolf"
	],
	"unit zone1_bat": [
		"a3fbf6215e126393562e68c751f89a39f76a444858ee3397314289a2ddf0c0aa",
		"Bat",
		"Fledermaus"
	],
	"unit zone1_dragonblue": [
		"eaccf306879670a48254e8fe2e85899366884aeb2c3e371019518f1ebd53e56f",
		"Black dragon",
		"Schwarzer Drache"
	],
	"unit zone1_fly": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit zone1_human_archer1_f": [
		"f499cae55a8d586efdff4447026deb2b9f7e6320e6246a808fc5526f9ee64441",
		"Rank-and-file guard woman",
		"Einfache Wächterin"
	],
	"unit zone1_human_archer2_f": [
		"6f7048141f4e3666fb10b4de3a5ce541206e64af86dc9d2af71fadf870b90585",
		"Sergeant of the guard",
		"Feldwebel der Wache"
	],
	"unit zone1_human_citizen_f": [
		"dbd6854aa28cea58cee49d41e06ff049309ef1707678f30c74f0c85683ee4e26",
		"Poor townswoman",
		"Arme Stadtbewohnerin"
	],
	"unit zone1_human_citizen_m": [
		"7851f36cf053666b2ac5c57329c5075015866380fd98dc26e08d12141affbdcf",
		"Destitute townsman",
		"Mittelloser Stadtbewohner"
	],
	"unit zone1_human_citizens_m": [
		"7be572d97a26f646418fbb7b777b18b1374c0eeb7c3365dec41f8be9a6553335",
		"Sick townsman",
		"Kranker Stadtbewohner"
	],
	"unit zone1_human_expeditor_m": [
		"c1a88a4f276470ede3e4d90058b7d5832a05b72e02a693ea4537f51c59beec10",
		"Expedition commander",
		"Kommandant der Expedition"
	],
	"unit zone1_human_fighter0_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit zone1_human_fighter1_m": [
		"48fef685b2fbb8b234731ddbe7f88f1ab1229ce22361b5bec84b028cf7103802",
		"Rank-and-file guard",
		"Einfacher Wächter"
	],
	"unit zone1_human_fighter2_m": [
		"b3cb5de49185590f8f8fde761735d632a8c04a43b21c5061067269642bee94c3",
		"Guard sergeant",
		"Wachfeldwebel"
	],
	"unit zone1_human_fighter3_m": [
		"6aec3c49f9991e8f7b4191fb92a3f25e46a3e1d74005c291ed726aafeb998520",
		"Guard lieutenant",
		"Wachleutnant"
	],
	"unit zone1_human_hellman_m": [
		"9087bc1137be3c2b28693418bc9ddfa8d4071fb6fe52a31147a6dbc8d372db7f",
		"Slave",
		"Sklave"
	],
	"unit zone1_human_mage1_f": [
		"e764cdaac4f996ce8046ac005c14ec56d19ae22c1fa56096dfef6175e647c948",
		"Inexperienced mage",
		"Unerfahrener Magier"
	],
	"unit zone1_human_mage2_f": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit zone1_human_map_m": [
		"9490d38b8fb602ded89f8b7ea109de5e2b412b4d645d919bbc7bc5800cb002af",
		"Captain",
		"Hauptmann"
	],
	"unit zone1_human_overseer_m": [
		"64ecb36f25b2514f6dcf67fda59ee3229f91b8f6f7b8d09498a36c17deaf33aa",
		"Slavedriver",
		"Sklaventreiber"
	],
	"unit zone1_human_peasants_f": [
		"0d14359cecea1b0403a753d2475af9156bf8483fb840122d3ab40d8fd2400fd8",
		"Female peon",
		"Arbeiterin"
	],
	"unit zone1_human_peasants_m": [
		"1f13d50704ef27979ccb7b00b1e3f4820589dddbc62687f6e91b9080e95be4ef",
		"Peon",
		"Arbeiter"
	],
	"unit zone1_human_portalkey_m": [
		"766e435582150ecd0a39e075a2a02c2dd9f5c0c95ca4851b1aad844fcf92a175",
		"General Game Error",
		"General Game Error"
	],
	"unit zone1_human_raja_m": [
		"f248ed9ced4128245737cc86cb47cf475d6e58f70f0d4695ebcf4e9710b78e4e",
		"Evil cunning rajah",
		"Böser listiger Radscha"
	],
	"unit zone1_human_trader_m": [
		"0fcd605e99012dc379f7080b60f5fc4d783c0078ad9e1cb4d2c141798374ccee",
		"Merchant",
		"Händler"
	],
	"unit zone1_hyena": [
		"716ffba5db68e49f6efb7d1c50e186c6267dc250109a040183337e708b1e779a",
		"Young hyena",
		"Junge Hyäne"
	],
	"unit zone1_junevil": [
		"8137bd88ae4597c8cb326d3f9823d81087c2f76c7e016052585413f1ceea1f87",
		"Terror",
		"Schrecken"
	],
	"unit zone1_leopard1": [
		"0452f7d1f2046003bbe2b066f2aeb5cfe1c3a9ad8740ddccc1283a877fce1318",
		"Young cheetah",
		"Junger Gepard"
	],
	"unit zone1_leopard2": [
		"0f3c1b547148cbf8fc91f406fc95eb0706ef8499c66336686261eaf070a64d31",
		"Adult cheetah",
		"Ausgewachsener Gepard"
	],
	"unit zone1_ogre1": [
		"1759953617e557fbc1b2a8cbaca546751ba51984c8dd196859306bb607c2b4a3",
		"Young sand ogre",
		"Junger Sand-Oger"
	],
	"unit zone1_ogre2": [
		"89b37b0124449c2473aaddd8c4f595ca1bae6ae32a2c246fe907b776f39ee4b0",
		"Ageing sand ogre",
		"Alternder Sandoger"
	],
	"unit zone1_spider": [
		"111ad640f5024fff74a078597b5468351296558804cc2ff6a6e6d1419ad8beeb",
		"Young giant spider",
		"Junge Riesenspinne"
	],
	"unit zone1_wall": [
		"368b39395d2c27bb166902e187969da56409480a12fbbec1e66c6eaf40e08df4",
		"Fence",
		"Zaun"
	],
	"unit zone1_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone1dun1_human_thief_m": [
		"83d40ba35adf910664101a93c482c8451a7f11fb8c2c1a7f02396aa82e71bc39",
		"Criminal",
		"Verbrecher"
	],
	"unit zone1dun1_rat": [
		"00aba49fb43b6f944c10269561d6d4315e710fec19676a16075f945ff708f358",
		"Young well-fed rat",
		"Junge satte Ratte"
	],
	"unit zone1dun2_bat": [
		"347bf5562a5eded2e8554a4a05200570d697eb46384a6dc6d8c0b3fafaadc03c",
		"Small bat",
		"Kleine Fledermaus"
	],
	"unit zone1dun2_rat": [
		"f2f05ecfa9194ed37de48f13eb7f711a1f351cce69936a85a53c418087f4c72d",
		"Young rat",
		"Junge Ratte"
	],
	"unit zone21_dog1": [
		"a9a931616081df18ce26c4b2b909aee300f37f811780a51e4baed3b9ceb34035",
		"Dog",
		"Hund"
	],
	"unit zone21_driad_white_archer1": [
		"a1d00ece233aa1b56957fca475a2b70ae72bb149f03793ddf38ded827fffa36b",
		"Woodland archer\n(White Clan)",
		"Waldschütze\n(Weißer Clan)"
	],
	"unit zone21_driad_white_mage1": [
		"45300570fb5238faa23dd2957c681819ace2e2ff37963a3547d097d2bdb842e9",
		"Woodland mage\n(White Clan)",
		"Waldmagier\n(Weißer Clan)"
	],
	"unit zone21_elemental_ice": [
		"cebc4d598ed12eac2a398307d49e7c67e0960e7ff55f47ee305a5dd7787fbdbc",
		"Ice elemental",
		"Eiselementar"
	],
	"unit zone21_human_archer1_f": [
		"9a5d773ecf3099bbaf3703c5024610019f3736deec4e065b76ae12639bb18f7f",
		"Rank-and-file archer woman",
		"Einfache Bogenschützin"
	],
	"unit zone21_human_digger_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone21_human_doctor_f": [
		"48082f5b6548d4bcb7df4e9f4a8d4d698c65ce4b6be1bde57d67c59f384b7be9",
		"Healer",
		"Heiler"
	],
	"unit zone21_human_fighter1_m": [
		"5cf0858eb61f365c64d1cc9de2b308a37594749b923881abe8e5257adf9158ed",
		"Rank-and-file warrior",
		"Einfacher Krieger"
	],
	"unit zone21_human_hunter_f": [
		"8b35945a3aa5ae706d25e5913408016eb15d744b66888c1150feae92d32ca428",
		"Female hunter",
		"Jägerin"
	],
	"unit zone21_human_mage1_f": [
		"25c8d5a0bd5d318cdf04811caaa38f4da3793c99dce217ac56358f35ed0d0e38",
		"Rookie warrior magician",
		"Einfacher Kriegermagier"
	],
	"unit zone21_human_peasant_f": [
		"5d0d9dc7a3ab39779deefe7fbaa7bcfdc20e72343cd2fdd241bad5bdc3fa8dd5",
		"Female commoner",
		"Einfache Bürgerin"
	],
	"unit zone21_human_peasant_m": [
		"161bb4359905d8ffff8f5dd9b4a5773a7d9e2cdda551ebc22e6a2506cb03e245",
		"Commoner",
		"Einfacher Bürger"
	],
	"unit zone21_human_woodcuter_m": [
		"4507dba57b43fa6e0aed4e00c2f0fe381944efa625bf84ba67d1e27d5d3dff8e",
		"Woodcutter",
		"Holzfäller"
	],
	"unit zone21_tigerwhite1": [
		"9e324eb116d5cb5d23f75baa126274e297137cc384c2e97f2feddaa5cc765c2e",
		"Young snow tiger",
		"Junger Schneetiger"
	],
	"unit zone21_tigerwhite2": [
		"5cc7f88afb7e8e51e2c4c717e19d28f06d4c21251fa2dbe32c75b687921eb091",
		"Adult snow tiger",
		"Ausgewachsener Schneetiger"
	],
	"unit zone21_trollblue": [
		"3411e748acef08d17b1b9e5b4efd65c6cdbf4006f99db2129e627a141e63cd84",
		"Blue troll",
		"Blauer Troll"
	],
	"unit zone21_unicorn_white": [
		"854a5dc5e3f0318f98e18f97a266e2b02e33ce57d2b3306d6076d664be9a8d03",
		"White unicorn",
		"Weißes Einhorn"
	],
	"unit zone22_dog1": [
		"a9a931616081df18ce26c4b2b909aee300f37f811780a51e4baed3b9ceb34035",
		"Dog",
		"Hund"
	],
	"unit zone22_driad_blue_archer1": [
		"3ceb7d1006aa02db53f4c2e01c796a089ddc09796f718e18950edca47d7261ab",
		"Woodland archer\n(Blue Clan)",
		"Waldschütze\n(Blauer Clan)"
	],
	"unit zone22_driad_blue_mage1": [
		"f1ce4d79f44b1400c8865cf45f437a518e15ca7643b87966685708e857c089be",
		"Woodland mage\n(Blue Clan)",
		"Waldmagier\n(Blauer Clan)"
	],
	"unit zone22_human_archer1_f": [
		"9a5d773ecf3099bbaf3703c5024610019f3736deec4e065b76ae12639bb18f7f",
		"Rank-and-file archer woman",
		"Einfache Bogenschützin"
	],
	"unit zone22_human_digger1_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone22_human_digger2_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone22_human_fighter1_m": [
		"5cf0858eb61f365c64d1cc9de2b308a37594749b923881abe8e5257adf9158ed",
		"Rank-and-file warrior",
		"Einfacher Krieger"
	],
	"unit zone22_human_fighter2_m": [
		"0aa453dec29b9051b7e582715cf9aeeb74cc8ab6e9334969b5ba59099ffe04b0",
		"Guard",
		"Wache"
	],
	"unit zone22_human_mage1_f": [
		"25c8d5a0bd5d318cdf04811caaa38f4da3793c99dce217ac56358f35ed0d0e38",
		"Rookie warrior magician",
		"Einfacher Kriegermagier"
	],
	"unit zone22_human_peasant_f": [
		"5d0d9dc7a3ab39779deefe7fbaa7bcfdc20e72343cd2fdd241bad5bdc3fa8dd5",
		"Female commoner",
		"Einfache Bürgerin"
	],
	"unit zone22_human_peasant_m": [
		"161bb4359905d8ffff8f5dd9b4a5773a7d9e2cdda551ebc22e6a2506cb03e245",
		"Commoner",
		"Einfacher Bürger"
	],
	"unit zone22_human_woodcuter_m": [
		"4507dba57b43fa6e0aed4e00c2f0fe381944efa625bf84ba67d1e27d5d3dff8e",
		"Woodcutter",
		"Holzfäller"
	],
	"unit zone22_tigerwhite1": [
		"9e324eb116d5cb5d23f75baa126274e297137cc384c2e97f2feddaa5cc765c2e",
		"Young snow tiger",
		"Junger Schneetiger"
	],
	"unit zone22_tigerwhite2": [
		"b988ce2523cbe37bf388b26b76a6b7bde941a7baf7045408bc4402eaa686b276",
		"Veteran white tiger",
		"Weißer Tiger (Veteran)"
	],
	"unit zone22_trollblue": [
		"3411e748acef08d17b1b9e5b4efd65c6cdbf4006f99db2129e627a141e63cd84",
		"Blue troll",
		"Blauer Troll"
	],
	"unit zone22_unicorn_black": [
		"e70978a05e0723a786c5115cd216ce8492426c9cad16782419f0a4032e8fa08b",
		"Black unicorn",
		"Schwarzes Einhorn"
	],
	"unit zone22dun1_bat": [
		"594f10b9eb6c596554f7cdc10182eaefe8999e129cffb75864ec733639ff7b90",
		"Giant bat",
		"Riesenfledermaus"
	],
	"unit zone22dun1_elemental_ice": [
		"cebc4d598ed12eac2a398307d49e7c67e0960e7ff55f47ee305a5dd7787fbdbc",
		"Ice elemental",
		"Eiselementar"
	],
	"unit zone22dun1_evileye": [
		"866b0bdcdbdcf28a1b98f3c1dc767cf63c325a1825bcbe82977bc429d4706b85",
		"Red evil eye",
		"Rotes böses Auge"
	],
	"unit zone22dun1_octopus": [
		"eee3362dde7955abf532d7169ad58fef3952e1dfa734d511518435819c612f5d",
		"Young black wormhead",
		"Junger schwarzer Wurmkopf"
	],
	"unit zone22dun1_rat": [
		"612e66b5cdc82d42800a6b8b151f4e5899058e1c85882a80f59a53be31b1f560",
		"Adult cave rat",
		"Ausgewachsene Höhlenratte"
	],
	"unit zone22dun1_succubblue": [
		"168e2ef70b67b6cfbc99d029f34e9e0a2b64cc773dcf59fad5abf73d974f9240",
		"Grey harpy",
		"Graue Harpyie"
	],
	"unit zone23_dog1": [
		"a9a931616081df18ce26c4b2b909aee300f37f811780a51e4baed3b9ceb34035",
		"Dog",
		"Hund"
	],
	"unit zone23_elemental_ice": [
		"cebc4d598ed12eac2a398307d49e7c67e0960e7ff55f47ee305a5dd7787fbdbc",
		"Ice elemental",
		"Eiselementar"
	],
	"unit zone23_human_archer1_f": [
		"0dad608ccfd22f7df9c29e65919411d6040cc1e036cc3af750ea193d45b36bba",
		"Untrained archer woman",
		"Unausgebildete Bogenschützin"
	],
	"unit zone23_human_archer2_f": [
		"e4156d1317faa7749b570e6058fb03e67a533ffd49c032c4d851d30dceaacaa6",
		"Mercenary female archer",
		"Söldner-Bogenschützin"
	],
	"unit zone23_human_digger_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone23_human_doctor_f": [
		"48082f5b6548d4bcb7df4e9f4a8d4d698c65ce4b6be1bde57d67c59f384b7be9",
		"Healer",
		"Heiler"
	],
	"unit zone23_human_fighter1_m": [
		"43bb0eeeb6f1b52dff4579d4a02698252722318ea8179d960b99230aa13ed247",
		"Untrained warrior",
		"Unausgebildeter Krieger"
	],
	"unit zone23_human_fighter2_m": [
		"7753261f2406204fd53cd01a2c296b989bb4f5342ad6eba76794b25ba645acd3",
		"Mercenary soldier",
		"Söldner"
	],
	"unit zone23_human_fighter3_m": [
		"f8e7dc3995debe0e0face502bc52d4d9be9385df87f3a0bfc894c77338c6ab1d",
		"Experienced mercenary warrior",
		"Erfahrener Söldnerkrieger"
	],
	"unit zone23_human_mage1_f": [
		"66cc0644436253301ef48400c3b06da2e0ea696158887b13fedb9fc1dfbaa582",
		"Mercenary mage",
		"Söldnermagier"
	],
	"unit zone23_human_peasant_f": [
		"5d0d9dc7a3ab39779deefe7fbaa7bcfdc20e72343cd2fdd241bad5bdc3fa8dd5",
		"Female commoner",
		"Einfache Bürgerin"
	],
	"unit zone23_human_peasant_m": [
		"161bb4359905d8ffff8f5dd9b4a5773a7d9e2cdda551ebc22e6a2506cb03e245",
		"Commoner",
		"Einfacher Bürger"
	],
	"unit zone23_human_woodcuter_m": [
		"4507dba57b43fa6e0aed4e00c2f0fe381944efa625bf84ba67d1e27d5d3dff8e",
		"Woodcutter",
		"Holzfäller"
	],
	"unit zone23_tigerwhite1": [
		"9e324eb116d5cb5d23f75baa126274e297137cc384c2e97f2feddaa5cc765c2e",
		"Young snow tiger",
		"Junger Schneetiger"
	],
	"unit zone23_tigerwhite2": [
		"5cc7f88afb7e8e51e2c4c717e19d28f06d4c21251fa2dbe32c75b687921eb091",
		"Adult snow tiger",
		"Ausgewachsener Schneetiger"
	],
	"unit zone23_trollblue": [
		"3411e748acef08d17b1b9e5b4efd65c6cdbf4006f99db2129e627a141e63cd84",
		"Blue troll",
		"Blauer Troll"
	],
	"unit zone24_bat": [
		"371d48a015dab6cb1533bb06c1ff51791edf5ddc4060eb40f1c3ff79c7b46f53",
		"Black bat",
		"Schwarze Fledermaus"
	],
	"unit zone24_evileye": [
		"866b0bdcdbdcf28a1b98f3c1dc767cf63c325a1825bcbe82977bc429d4706b85",
		"Red evil eye",
		"Rotes böses Auge"
	],
	"unit zone24_human_digger1_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone24_human_digger2_m": [
		"6a8146294edc1716270c766b733da9f5970feedb010468af1ba7a18d2c866b1f",
		"Miner",
		"Minenarbeiter"
	],
	"unit zone24_human_doctor_f": [
		"2615168fcbe3dd8970c3d67a8bc4bc86f6960bc7bfc0e7c7dd46ca878822ad10",
		"Experienced healer",
		"Erfahrener Heiler"
	],
	"unit zone24_human_fighter1_m": [
		"0aa453dec29b9051b7e582715cf9aeeb74cc8ab6e9334969b5ba59099ffe04b0",
		"Guard",
		"Wache"
	],
	"unit zone24_octopus": [
		"eee3362dde7955abf532d7169ad58fef3952e1dfa734d511518435819c612f5d",
		"Young black wormhead",
		"Junger schwarzer Wurmkopf"
	],
	"unit zone24_succubblue": [
		"168e2ef70b67b6cfbc99d029f34e9e0a2b64cc773dcf59fad5abf73d974f9240",
		"Grey harpy",
		"Graue Harpyie"
	],
	"unit zone25_dog1": [
		"a9a931616081df18ce26c4b2b909aee300f37f811780a51e4baed3b9ceb34035",
		"Dog",
		"Hund"
	],
	"unit zone25_elemental_ice": [
		"f92a4262677073f18c8b7da1b85fb423a949d19b5ee14f9d5dfbc0fc80b531a2",
		"Large ice elemental",
		"Großer Eiselementar"
	],
	"unit zone25_human_doctor_f": [
		"48082f5b6548d4bcb7df4e9f4a8d4d698c65ce4b6be1bde57d67c59f384b7be9",
		"Healer",
		"Heiler"
	],
	"unit zone25_human_hunter_f": [
		"8b35945a3aa5ae706d25e5913408016eb15d744b66888c1150feae92d32ca428",
		"Female hunter",
		"Jägerin"
	],
	"unit zone25_human_peasant_f": [
		"5d0d9dc7a3ab39779deefe7fbaa7bcfdc20e72343cd2fdd241bad5bdc3fa8dd5",
		"Female commoner",
		"Einfache Bürgerin"
	],
	"unit zone25_human_peasant_m": [
		"161bb4359905d8ffff8f5dd9b4a5773a7d9e2cdda551ebc22e6a2506cb03e245",
		"Commoner",
		"Einfacher Bürger"
	],
	"unit zone25_human_woodcuter_m": [
		"4507dba57b43fa6e0aed4e00c2f0fe381944efa625bf84ba67d1e27d5d3dff8e",
		"Woodcutter",
		"Holzfäller"
	],
	"unit zone25_ogre": [
		"ea94c21bd097e2cc9589ee23ad6c092a99b58f4728df254296b442207930d4cc",
		"Snow ogre",
		"Schneeoger"
	],
	"unit zone25_unicorn_white": [
		"9f90c57ab74a2d4373fc175d5064e68c9a50b4910a7934bb6b4bfdb80443642f",
		"Wild white unicorn",
		"Wildes weißes Einhorn"
	],
	"unit zone26_bat": [
		"371d48a015dab6cb1533bb06c1ff51791edf5ddc4060eb40f1c3ff79c7b46f53",
		"Black bat",
		"Schwarze Fledermaus"
	],
	"unit zone26_elemental_ice": [
		"f92a4262677073f18c8b7da1b85fb423a949d19b5ee14f9d5dfbc0fc80b531a2",
		"Large ice elemental",
		"Großer Eiselementar"
	],
	"unit zone26_evileye": [
		"866b0bdcdbdcf28a1b98f3c1dc767cf63c325a1825bcbe82977bc429d4706b85",
		"Red evil eye",
		"Rotes böses Auge"
	],
	"unit zone26_ogre": [
		"ea94c21bd097e2cc9589ee23ad6c092a99b58f4728df254296b442207930d4cc",
		"Snow ogre",
		"Schneeoger"
	],
	"unit zone26_succubblue": [
		"168e2ef70b67b6cfbc99d029f34e9e0a2b64cc773dcf59fad5abf73d974f9240",
		"Grey harpy",
		"Graue Harpyie"
	],
	"unit zone2_banshee_fighter1": [
		"1d9ebf705a1bdf73ca288e67468de78f87b77d7c6ef48eb49b3b9515b9e7c33f",
		"Black banshee with a scythe",
		"Schwarze Banshee mit Sense"
	],
	"unit zone2_banshee_fighter2": [
		"1d9ebf705a1bdf73ca288e67468de78f87b77d7c6ef48eb49b3b9515b9e7c33f",
		"Black banshee with a scythe",
		"Schwarze Banshee mit Sense"
	],
	"unit zone2_banshee_mage1": [
		"d40ea3306ecf4e9655cbfcf3d6d9aa6bbb285d8283f882ad93d92783e4a28ce3",
		"Magical black banshee",
		"Magische schwarze Banshee"
	],
	"unit zone2_banshee_mage2": [
		"d40ea3306ecf4e9655cbfcf3d6d9aa6bbb285d8283f882ad93d92783e4a28ce3",
		"Magical black banshee",
		"Magische schwarze Banshee"
	],
	"unit zone2_dragonblue": [
		"eaccf306879670a48254e8fe2e85899366884aeb2c3e371019518f1ebd53e56f",
		"Black dragon",
		"Schwarzer Drache"
	],
	"unit zone2_human_archer1_f": [
		"f499cae55a8d586efdff4447026deb2b9f7e6320e6246a808fc5526f9ee64441",
		"Rank-and-file guard woman",
		"Einfache Wächterin"
	],
	"unit zone2_human_archer2_f": [
		"6f7048141f4e3666fb10b4de3a5ce541206e64af86dc9d2af71fadf870b90585",
		"Sergeant of the guard",
		"Feldwebel der Wache"
	],
	"unit zone2_human_citizen_f": [
		"dbd6854aa28cea58cee49d41e06ff049309ef1707678f30c74f0c85683ee4e26",
		"Poor townswoman",
		"Arme Stadtbewohnerin"
	],
	"unit zone2_human_citizen_m": [
		"7851f36cf053666b2ac5c57329c5075015866380fd98dc26e08d12141affbdcf",
		"Destitute townsman",
		"Mittelloser Stadtbewohner"
	],
	"unit zone2_human_citizens_m": [
		"7be572d97a26f646418fbb7b777b18b1374c0eeb7c3365dec41f8be9a6553335",
		"Sick townsman",
		"Kranker Stadtbewohner"
	],
	"unit zone2_human_fighter1_m": [
		"48fef685b2fbb8b234731ddbe7f88f1ab1229ce22361b5bec84b028cf7103802",
		"Rank-and-file guard",
		"Einfacher Wächter"
	],
	"unit zone2_human_fighter2_m": [
		"b3cb5de49185590f8f8fde761735d632a8c04a43b21c5061067269642bee94c3",
		"Guard sergeant",
		"Wachfeldwebel"
	],
	"unit zone2_human_fighter3_m": [
		"64ecb36f25b2514f6dcf67fda59ee3229f91b8f6f7b8d09498a36c17deaf33aa",
		"Slavedriver",
		"Sklaventreiber"
	],
	"unit zone2_human_mage1_f": [
		"e764cdaac4f996ce8046ac005c14ec56d19ae22c1fa56096dfef6175e647c948",
		"Inexperienced mage",
		"Unerfahrener Magier"
	],
	"unit zone2_human_mage2_f": [
		"e764cdaac4f996ce8046ac005c14ec56d19ae22c1fa56096dfef6175e647c948",
		"Inexperienced mage",
		"Unerfahrener Magier"
	],
	"unit zone2_human_mage3_f": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit zone2_human_peasants_m": [
		"1f13d50704ef27979ccb7b00b1e3f4820589dddbc62687f6e91b9080e95be4ef",
		"Peon",
		"Arbeiter"
	],
	"unit zone2_hyena": [
		"0fbf8b56c711023571d949b6fa04cfd7b5a39ef50e9b1e7c106ea39ec0842597",
		"Adult hyena",
		"Ausgewachsene Hyäne"
	],
	"unit zone2_leopard1": [
		"0452f7d1f2046003bbe2b066f2aeb5cfe1c3a9ad8740ddccc1283a877fce1318",
		"Young cheetah",
		"Junger Gepard"
	],
	"unit zone2_leopard2": [
		"0f3c1b547148cbf8fc91f406fc95eb0706ef8499c66336686261eaf070a64d31",
		"Adult cheetah",
		"Ausgewachsener Gepard"
	],
	"unit zone2_ogre": [
		"5087a3140856aff36e3b7d23964c670d61759b0c8c9e1797e2b6e48980c70582",
		"Well-fed sand ogre",
		"Satter Sandoger"
	],
	"unit zone2_spider": [
		"34f58c4806e216c04457d0b430ff5bb97ba0a9d016026175506895d1c4312dbb",
		"Adult giant spider",
		"Ausgewachsene Riesenspinne"
	],
	"unit zone2_troll": [
		"a39b4475b53e65187dc7e239a47abb0f43b2d660508a58520ee82e54ab042c92",
		"Slow black troll",
		"Langsamer schwarzer Troll"
	],
	"unit zone2_zombie1_f": [
		"654e0149467bb13ac4c5ea6afd1e46bcc8b3fab5a8e186c64b93e483f6ed25d1",
		"Zombified laboratory assistant",
		"Zombifizierte Laborantin"
	],
	"unit zone2_zombie1_m": [
		"436a1cfaacab5d080670fd0053cc7b8db19ace4d22900a12b79db4a027f558b3",
		"Zombified scholar",
		"Zombifizierter Gelehrter"
	],
	"unit zone2_zombie2_f": [
		"654e0149467bb13ac4c5ea6afd1e46bcc8b3fab5a8e186c64b93e483f6ed25d1",
		"Zombified laboratory assistant",
		"Zombifizierte Laborantin"
	],
	"unit zone2_zombie2_m": [
		"436a1cfaacab5d080670fd0053cc7b8db19ace4d22900a12b79db4a027f558b3",
		"Zombified scholar",
		"Zombifizierter Gelehrter"
	],
	"unit zone31_banshee_fighter1": [
		"ad102e1f34fbc46ca3af2c1c9c65033383e58a2f35950d696d60fa3fa853b406",
		"Royal banshee",
		"Königliche Banshee"
	],
	"unit zone31_banshee_mage1": [
		"fd784b2b94631927351a9546e531bd46f3f67232db5f785f7359a5baa7405766",
		"Magical royal banshee",
		"Magische königliche Banshee"
	],
	"unit zone31_boardark": [
		"288a7450efcb8ccbdf7d613a9f12bf54bfb9e51bffbe2b72a9b47daf9d9d9e0c",
		"Black boar",
		"Schwarzer Eber"
	],
	"unit zone31_dog": [
		"bf14a778a4f38d568af61ce55bab00d9e812f54a0826d8d65c8ddd500a68f0a5",
		"Dog",
		"Hund"
	],
	"unit zone31_fox1": [
		"cdef89b74e8327f47e9c4f463021925aabea448322861f50c47de4ee9cc91167",
		"Young fox",
		"Junger Fuchs"
	],
	"unit zone31_fox2": [
		"8ce73cea566a3684f0977afca90c8ebcf69ddfa938802e1767e272ddad228b6a",
		"Adult fox",
		"Ausgewachsener Fuchs"
	],
	"unit zone31_human_gangster_m": [
		"33a373e96c41a84496f2446029ed4103eb1f3c2be3d63c9ed75f680f5272aee6",
		"Brigand",
		"Bandit"
	],
	"unit zone31_human_peasant_f": [
		"4fb0d234b2218bc5055f043a745cfc64d9119d7ad563661ff7df854c2ab7bcc2",
		"Peasant woman",
		"Bäuerin"
	],
	"unit zone31_human_peasant_m": [
		"a304853176d773cd71c766553cd32f1fa9e93e6740bf9aa359220deec4005e93",
		"Peasant",
		"Bauer"
	],
	"unit zone31_ogre": [
		"66bbe1cc46a97ca1ab15e5178d9cd119e44030eae45397dbd3791a175328ce10",
		"Ogre",
		"Oger"
	],
	"unit zone31_scrab": [
		"f018f2d4ae4bca9caf8eaabf684979177f8c0c4597862366e8eeba2cf042ccbb",
		"Adult armadillo",
		"Ausgewachsener Blutreißer"
	],
	"unit zone31_scrab0": [
		"ad3cea04c749534bd054b8ac7a4a5f91d496969b60393f5bb31b340b5433337e",
		"Young armadillo",
		"Blutreißer-Jungtier"
	],
	"unit zone31_shadow": [
		"4a957851c052ec69892d30d505da2086d6172e876b86f4bc52053e79ff265f6e",
		"Shadow",
		"Schatten"
	],
	"unit zone31_skeleton": [
		"3f08feeab628e2123d0c618e3d283dbe3814095910e8e42cbce4c7ef6fd4283d",
		"Armoured skeleton",
		"Gepanzertes Skelett"
	],
	"unit zone31_succub": [
		"c36e418f1e14e1d0ad7cf46e3f3d3dba29a1a8ba9494dc10739f2af739092ab3",
		"Mature harpy",
		"Alte Harpyie"
	],
	"unit zone31_tiger": [
		"e5c82567536c5ce9e1f2dc0d16a7a70310cc963adfb596c057378e0bb23ea7e0",
		"Giant tiger",
		"Riesentiger"
	],
	"unit zone31_toad1": [
		"aaa4817a2ae2c2df61c46bae80c7100b1b2d3e4c475392c773963146b6efa496",
		"Small toad",
		"Kleine Kröte"
	],
	"unit zone31_toad2": [
		"7c29938d2fa22c57b77e643029d4e87788e791ad44f586d88f54a5a245a5e175",
		"Giant toad",
		"Riesenkröte"
	],
	"unit zone31_wolfbraun": [
		"69c1aff7d4dc250502908e3bd9605fa701e40173dc3ca6324351d47b30c71bfc",
		"Brown wolf",
		"Brauner Wolf"
	],
	"unit zone31_zombie_f": [
		"b8bc41d8cb9e0071758c4d349a5ec1e347d28fc99fb371924b2664e3a2cfcd40",
		"Zombified warrior woman",
		"Zombifizierte Kriegerin"
	],
	"unit zone31_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone32_deaddeer": [
		"c9c6d1c04cccecc14c12e4cda483db7501b3cab20e3421d60c4ffb1819b03a65",
		"Dead deer",
		"Toter Hirsch"
	],
	"unit zone32_dragonblue": [
		"97aa354514e99151f96fa9da6a343fe51a13baa0e5cebd5ad349a60bf57cb1cd",
		"Blue dragon",
		"Blauer Drache"
	],
	"unit zone32_dragonred": [
		"83e0e5b9b4d53309754c9405030ff64f5ec83e89ec9c9bef3d6682ea8302e96f",
		"Red dragon",
		"Roter Drache"
	],
	"unit zone32_fox1": [
		"cdef89b74e8327f47e9c4f463021925aabea448322861f50c47de4ee9cc91167",
		"Young fox",
		"Junger Fuchs"
	],
	"unit zone32_fox2": [
		"8ce73cea566a3684f0977afca90c8ebcf69ddfa938802e1767e272ddad228b6a",
		"Adult fox",
		"Ausgewachsener Fuchs"
	],
	"unit zone32_popper": [
		"588475c6d7009b1c9d00b15469850c29595601d7f32b7e9b387df69dc12c0494",
		"Sick hare",
		"Kranker Hase"
	],
	"unit zone32_skeleton": [
		"3f08feeab628e2123d0c618e3d283dbe3814095910e8e42cbce4c7ef6fd4283d",
		"Armoured skeleton",
		"Gepanzertes Skelett"
	],
	"unit zone32_toad1": [
		"aaa4817a2ae2c2df61c46bae80c7100b1b2d3e4c475392c773963146b6efa496",
		"Small toad",
		"Kleine Kröte"
	],
	"unit zone32_toad2": [
		"7c29938d2fa22c57b77e643029d4e87788e791ad44f586d88f54a5a245a5e175",
		"Giant toad",
		"Riesenkröte"
	],
	"unit zone32_wolfbraun": [
		"69c1aff7d4dc250502908e3bd9605fa701e40173dc3ca6324351d47b30c71bfc",
		"Brown wolf",
		"Brauner Wolf"
	],
	"unit zone33_dragonblue": [
		"97aa354514e99151f96fa9da6a343fe51a13baa0e5cebd5ad349a60bf57cb1cd",
		"Blue dragon",
		"Blauer Drache"
	],
	"unit zone33_human_archer1_m": [
		"af44071d0c90ca623da0be0441e7d1795e0585a684a60ee79781f27fa7ed9850",
		"Hadagan archer",
		"Hadaganischer Schütze"
	],
	"unit zone33_human_fighter1_m": [
		"6906c395ece3e4fbf9d3fc008496e3bc438bdfc975c1bd2d6d69f6825a679de3",
		"Khadaganian soldier",
		"Khadaganischer Soldat"
	],
	"unit zone33_human_fighter2_m": [
		"6906c395ece3e4fbf9d3fc008496e3bc438bdfc975c1bd2d6d69f6825a679de3",
		"Khadaganian soldier",
		"Khadaganischer Soldat"
	],
	"unit zone33_human_mage1_f": [
		"4142da49dace67a31db98eae7737bd93589229fbc1a32df7a2402bb4bbbb140b",
		"Necromancer",
		"Totenbeschwörer"
	],
	"unit zone33_ogre": [
		"66bbe1cc46a97ca1ab15e5178d9cd119e44030eae45397dbd3791a175328ce10",
		"Ogre",
		"Oger"
	],
	"unit zone33_scrab": [
		"f018f2d4ae4bca9caf8eaabf684979177f8c0c4597862366e8eeba2cf042ccbb",
		"Adult armadillo",
		"Ausgewachsener Blutreißer"
	],
	"unit zone33_scrab0": [
		"ad3cea04c749534bd054b8ac7a4a5f91d496969b60393f5bb31b340b5433337e",
		"Young armadillo",
		"Blutreißer-Jungtier"
	],
	"unit zone33_skeleton": [
		"3f08feeab628e2123d0c618e3d283dbe3814095910e8e42cbce4c7ef6fd4283d",
		"Armoured skeleton",
		"Gepanzertes Skelett"
	],
	"unit zone33_tiger": [
		"e5c82567536c5ce9e1f2dc0d16a7a70310cc963adfb596c057378e0bb23ea7e0",
		"Giant tiger",
		"Riesentiger"
	],
	"unit zone33_troll": [
		"6f161167abdeac3a6a447c0c38165868d1e06daa6a07c440cad46e8f5f01a645",
		"Black troll",
		"Schwarzer Troll"
	],
	"unit zone33_undead_fighter1_m": [
		"5d315c67ec3c6d558e2b71d463d2a37e8011c88c4745ed9fee48279bc24d9b35",
		"Ghoul",
		"Ghoul"
	],
	"unit zone33_undead_fighter2_m": [
		"5d315c67ec3c6d558e2b71d463d2a37e8011c88c4745ed9fee48279bc24d9b35",
		"Ghoul",
		"Ghoul"
	],
	"unit zone33_undead_fighter3_m": [
		"5d315c67ec3c6d558e2b71d463d2a37e8011c88c4745ed9fee48279bc24d9b35",
		"Ghoul",
		"Ghoul"
	],
	"unit zone33_wolfbraun": [
		"69c1aff7d4dc250502908e3bd9605fa701e40173dc3ca6324351d47b30c71bfc",
		"Brown wolf",
		"Brauner Wolf"
	],
	"unit zone33_zombie_f": [
		"b8bc41d8cb9e0071758c4d349a5ec1e347d28fc99fb371924b2664e3a2cfcd40",
		"Zombified warrior woman",
		"Zombifizierte Kriegerin"
	],
	"unit zone33_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone34_banshee_fighter1": [
		"ad102e1f34fbc46ca3af2c1c9c65033383e58a2f35950d696d60fa3fa853b406",
		"Royal banshee",
		"Königliche Banshee"
	],
	"unit zone34_banshee_mage1": [
		"fd784b2b94631927351a9546e531bd46f3f67232db5f785f7359a5baa7405766",
		"Magical royal banshee",
		"Magische königliche Banshee"
	],
	"unit zone34_deaddeer": [
		"c9c6d1c04cccecc14c12e4cda483db7501b3cab20e3421d60c4ffb1819b03a65",
		"Dead deer",
		"Toter Hirsch"
	],
	"unit zone34_human_archer1_m": [
		"af44071d0c90ca623da0be0441e7d1795e0585a684a60ee79781f27fa7ed9850",
		"Hadagan archer",
		"Hadaganischer Schütze"
	],
	"unit zone34_human_fighter1_m": [
		"6906c395ece3e4fbf9d3fc008496e3bc438bdfc975c1bd2d6d69f6825a679de3",
		"Khadaganian soldier",
		"Khadaganischer Soldat"
	],
	"unit zone34_human_fighter2_m": [
		"6906c395ece3e4fbf9d3fc008496e3bc438bdfc975c1bd2d6d69f6825a679de3",
		"Khadaganian soldier",
		"Khadaganischer Soldat"
	],
	"unit zone34_human_mage1_f": [
		"4142da49dace67a31db98eae7737bd93589229fbc1a32df7a2402bb4bbbb140b",
		"Necromancer",
		"Totenbeschwörer"
	],
	"unit zone34_ogre": [
		"4e99cfecaff04b314f7846f32d9dda04cf7e813151bd38506dca9127dbaf5904",
		"Veteran Ogre",
		"Oger-Veteran"
	],
	"unit zone34_scrab": [
		"f018f2d4ae4bca9caf8eaabf684979177f8c0c4597862366e8eeba2cf042ccbb",
		"Adult armadillo",
		"Ausgewachsener Blutreißer"
	],
	"unit zone34_scrab0": [
		"ad3cea04c749534bd054b8ac7a4a5f91d496969b60393f5bb31b340b5433337e",
		"Young armadillo",
		"Blutreißer-Jungtier"
	],
	"unit zone34_shadow": [
		"4a957851c052ec69892d30d505da2086d6172e876b86f4bc52053e79ff265f6e",
		"Shadow",
		"Schatten"
	],
	"unit zone34_skeleton": [
		"6f31ae382e1eb25695345bf5ebc730b58ba9d2bd6e594f4159befaae0095c507",
		"Skeleton",
		"Skelett"
	],
	"unit zone34_succub": [
		"c36e418f1e14e1d0ad7cf46e3f3d3dba29a1a8ba9494dc10739f2af739092ab3",
		"Mature harpy",
		"Alte Harpyie"
	],
	"unit zone34_troll": [
		"6f161167abdeac3a6a447c0c38165868d1e06daa6a07c440cad46e8f5f01a645",
		"Black troll",
		"Schwarzer Troll"
	],
	"unit zone34_wolfblack": [
		"7438d72f3b2b7d54072acac4cda6c29375ec1e88b9734dd904a0a07f835dc082",
		"Werewolf",
		"Werwolf"
	],
	"unit zone34_zombie_f": [
		"b8bc41d8cb9e0071758c4d349a5ec1e347d28fc99fb371924b2664e3a2cfcd40",
		"Zombified warrior woman",
		"Zombifizierte Kriegerin"
	],
	"unit zone34_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone35_banshee_fighter1": [
		"ad102e1f34fbc46ca3af2c1c9c65033383e58a2f35950d696d60fa3fa853b406",
		"Royal banshee",
		"Königliche Banshee"
	],
	"unit zone35_banshee_mage1": [
		"fd784b2b94631927351a9546e531bd46f3f67232db5f785f7359a5baa7405766",
		"Magical royal banshee",
		"Magische königliche Banshee"
	],
	"unit zone35_deaddeer": [
		"bd793705917b99636573b708e95b01a34c3a607e5f764d67ea265099ee2c9d20",
		"Angry deer",
		"Wütender Hirsch"
	],
	"unit zone35_dragonblue": [
		"97aa354514e99151f96fa9da6a343fe51a13baa0e5cebd5ad349a60bf57cb1cd",
		"Blue dragon",
		"Blauer Drache"
	],
	"unit zone35_human_archer1_m": [
		"ee719ffc642ca998cd764fff1529258a3a02cc3c4692992995ba1ea651a4864d",
		"Archer jailer",
		"Schützenkerkermeister"
	],
	"unit zone35_human_fighter1_m": [
		"1bd56acd6c6240ad6f611da4af548256be6fd55324d597db5d73ad0bd49f25a1",
		"Warrior jailer",
		"Kriegerkerkermeister"
	],
	"unit zone35_ogre": [
		"4e99cfecaff04b314f7846f32d9dda04cf7e813151bd38506dca9127dbaf5904",
		"Veteran Ogre",
		"Oger-Veteran"
	],
	"unit zone35_shadow": [
		"695e5b356990833394c0871ab6992eacaf5319675e0ad2fe2a3b7f7a94c1e5be",
		"Shadow",
		"Schatten"
	],
	"unit zone35_skeleton": [
		"c66523c8eef89cd4951a1a44b2ff7415199c96f7e2c3523e5606862f479ae72e",
		"Reinforced armoured skeleton",
		"Verstärktes gepanzertes Skelett"
	],
	"unit zone35_undead_archer_m": [
		"a734c24dce85076fbde23faa9e33ae7610abbc07aa5438a5b364206833da427b",
		"Ghoul archer",
		"Ghulschütze"
	],
	"unit zone35_undead_fighter1_m": [
		"afe42327c377a3deec3a2c0b69f8f843017ea7cf3dda0cd95517a4b4f4cfd6d0",
		"Ghoul",
		"Ghoul"
	],
	"unit zone35_undead_fighter2_m": [
		"afe42327c377a3deec3a2c0b69f8f843017ea7cf3dda0cd95517a4b4f4cfd6d0",
		"Ghoul",
		"Ghoul"
	],
	"unit zone35_undead_mage_m": [
		"e6edff373bd6dd967c8cd4825a39731666dffcec568601ad162c804973ce6231",
		"Ghoul mage",
		"Ghulmagier"
	],
	"unit zone35_wolfblack": [
		"7438d72f3b2b7d54072acac4cda6c29375ec1e88b9734dd904a0a07f835dc082",
		"Werewolf",
		"Werwolf"
	],
	"unit zone35_zombie_f": [
		"b8bc41d8cb9e0071758c4d349a5ec1e347d28fc99fb371924b2664e3a2cfcd40",
		"Zombified warrior woman",
		"Zombifizierte Kriegerin"
	],
	"unit zone35_zombie_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone3_banshee_fighter1": [
		"1d9ebf705a1bdf73ca288e67468de78f87b77d7c6ef48eb49b3b9515b9e7c33f",
		"Black banshee with a scythe",
		"Schwarze Banshee mit Sense"
	],
	"unit zone3_banshee_mage1": [
		"d40ea3306ecf4e9655cbfcf3d6d9aa6bbb285d8283f882ad93d92783e4a28ce3",
		"Magical black banshee",
		"Magische schwarze Banshee"
	],
	"unit zone3_dragonbrown": [
		"83e0e5b9b4d53309754c9405030ff64f5ec83e89ec9c9bef3d6682ea8302e96f",
		"Red dragon",
		"Roter Drache"
	],
	"unit zone3_evileye": [
		"bd31edbd5627810023fc2cb1a0108cda28c35800e8612520d50d8cdac18ff5cf",
		"Green evil eye",
		"Grünes böses Auge"
	],
	"unit zone3_human_archer1_f": [
		"f499cae55a8d586efdff4447026deb2b9f7e6320e6246a808fc5526f9ee64441",
		"Rank-and-file guard woman",
		"Einfache Wächterin"
	],
	"unit zone3_human_citizen_f": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit zone3_human_citizen_m": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"unit zone3_human_fighter1_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit zone3_human_fighter2_m": [
		"48fef685b2fbb8b234731ddbe7f88f1ab1229ce22361b5bec84b028cf7103802",
		"Rank-and-file guard",
		"Einfacher Wächter"
	],
	"unit zone3_human_fighter3_m": [
		"6aec3c49f9991e8f7b4191fb92a3f25e46a3e1d74005c291ed726aafeb998520",
		"Guard lieutenant",
		"Wachleutnant"
	],
	"unit zone3_human_mage1_f": [
		"e764cdaac4f996ce8046ac005c14ec56d19ae22c1fa56096dfef6175e647c948",
		"Inexperienced mage",
		"Unerfahrener Magier"
	],
	"unit zone3_human_mage2_f": [
		"3bb82887182b6e30458445784d6b71bbe7a1eb9732cb77ba0f731aec6bfc16fe",
		"Magician",
		"Zauberer"
	],
	"unit zone3_human_peasants_f": [
		"0d14359cecea1b0403a753d2475af9156bf8483fb840122d3ab40d8fd2400fd8",
		"Female peon",
		"Arbeiterin"
	],
	"unit zone3_human_peasants_m": [
		"1f13d50704ef27979ccb7b00b1e3f4820589dddbc62687f6e91b9080e95be4ef",
		"Peon",
		"Arbeiter"
	],
	"unit zone3_hyena": [
		"48effa1ef4152b22fdb0bdadb6a7db063dac2c45ffe0e3d7bfd6ab8d39228850",
		"Mature hyena",
		"Alte Hyäne"
	],
	"unit zone3_leopard1": [
		"0f3c1b547148cbf8fc91f406fc95eb0706ef8499c66336686261eaf070a64d31",
		"Adult cheetah",
		"Ausgewachsener Gepard"
	],
	"unit zone3_leopard2": [
		"2d1dab6646ab23baa8d95f1c723891b87a7ffd6c8bb95cbe8908f6ba7f2f1501",
		"Mature cheetah",
		"Alter Gepard"
	],
	"unit zone3_ogre1": [
		"e54af42cb7ac515ad21f96812885cdcbb6904b29660d05f3d161a6dec5d52667",
		"Fat sand ogre",
		"Dicker Sandoger"
	],
	"unit zone3_ogre2": [
		"1759953617e557fbc1b2a8cbaca546751ba51984c8dd196859306bb607c2b4a3",
		"Young sand ogre",
		"Junger Sand-Oger"
	],
	"unit zone3_ogre3": [
		"485d90931ea34e8ce2116c38f58eae1fb70f9410eaaca662a3a934493584c819",
		"Bored sand ogre",
		"Gelangweilter Sandoger"
	],
	"unit zone3_spider": [
		"a2957bba4a03d5df69f7659616552884d5f4bb54b0f976d498ffa85601b24220",
		"Mature giant spider",
		"Alte Riesenspinne"
	],
	"unit zone3_zombie1_f": [
		"b65dc3f118de8ee7f9cd83e39cc4078219884fca7a1cd821dfdd006747e407d2",
		"Female guard zombie",
		"Weiblicher Wach-Zombie"
	],
	"unit zone3_zombie1_m": [
		"395fde6e2e227168b15939bd1a75834e618d9a86b8fc45dac65ce21560ce653d",
		"Soldier zombie",
		"Soldaten-Zombie"
	],
	"unit zone3dun1_human_fighter_m": [
		"195b60069f2cbf9ac9179562b0c36316858f45bf1e92b97d38ba881dddbf81ad",
		"Jailer",
		"Kerkermeister"
	],
	"unit zone3dun1_human_palach0_m": [
		"e5ac50af672a0fa4769aa7365758b6a9a78a6dfbdd34dff1efd22f7f58efe8cd",
		"Pleased executioner",
		"Zufriedener Henker"
	],
	"unit zone3dun1_human_palach1_m": [
		"2ec8c838fa5c9ba7945d4262f7a52b862a48a43f497a246ed41365759d633bf1",
		"Displeased executioner",
		"Unzufriedener Henker"
	],
	"unit zone3dun1_human_peasants_m": [
		"e985d0c703ef25bd7cd259b8f3c9a233c071127b30543f0008af9b872aed4e62",
		"Prisoner",
		"Gefangener"
	],
	"unit zone3dun1_rat1": [
		"06fd90b12a20bbb17d97b74ba407f69a90279a87a8eb0c16cb48770c879b3837",
		"Grave rat",
		"Grabratte"
	],
	"unit zone3dun1_rat2": [
		"c08def26dab267d01c26bb8bdb18c1f5bfb415a55c4e2d7d80f4d9e20ddb3489",
		"Well-fed carrion eater",
		"Satter Aasfresser"
	],
	"unit zone3dun1_sahilia_f": [
		"11d8b55e8c1855700d798d414dcd2ed676296f2d8d431024d0cd9cfc0acfcd21",
		"Alia",
		"Alia"
	],
	"unit zone4_elemental_earth": [
		"303567bf40ac1c499ba2c44dc9cba0ab470c790fedf889e4b0d1cf54b7045ef3",
		"Earth elemental",
		"Erd-Element"
	],
	"unit zone4_elemental_lava": [
		"29e9afd129c118adbfbd682dd6101a38f421c447c13f16d74e621c989d2e63ed",
		"Lava elemental",
		"Lava-Element"
	],
	"unit zone4_evileye": [
		"bd31edbd5627810023fc2cb1a0108cda28c35800e8612520d50d8cdac18ff5cf",
		"Green evil eye",
		"Grünes böses Auge"
	],
	"unit zone4_octopus": [
		"806717afba7a166fda93fade6ee7797a5a661e24d2505d4d666bd73048080d47",
		"Adult wormhead",
		"Ausgewachsener Wurmkopf"
	],
	"unit zone4_rat1": [
		"9786135f212695d843f07ae7c42b0ffde85ba413e4f22fb2615e753a781b5d20",
		"Young cave rat",
		"Junge Höhlenratte"
	],
	"unit zone4_rat2": [
		"612e66b5cdc82d42800a6b8b151f4e5899058e1c85882a80f59a53be31b1f560",
		"Adult cave rat",
		"Ausgewachsene Höhlenratte"
	],
	"unit zone5_human_archer1_f": [
		"f499cae55a8d586efdff4447026deb2b9f7e6320e6246a808fc5526f9ee64441",
		"Rank-and-file guard woman",
		"Einfache Wächterin"
	],
	"unit zone5_human_fighter1_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit zone5_human_fighter2_m": [
		"48fef685b2fbb8b234731ddbe7f88f1ab1229ce22361b5bec84b028cf7103802",
		"Rank-and-file guard",
		"Einfacher Wächter"
	],
	"unit zone5_human_mage1_f": [
		"e764cdaac4f996ce8046ac005c14ec56d19ae22c1fa56096dfef6175e647c948",
		"Inexperienced mage",
		"Unerfahrener Magier"
	],
	"unit zone5_hyena": [
		"48effa1ef4152b22fdb0bdadb6a7db063dac2c45ffe0e3d7bfd6ab8d39228850",
		"Mature hyena",
		"Alte Hyäne"
	],
	"unit zone5_leopard1": [
		"0f3c1b547148cbf8fc91f406fc95eb0706ef8499c66336686261eaf070a64d31",
		"Adult cheetah",
		"Ausgewachsener Gepard"
	],
	"unit zone5_leopard2": [
		"2d1dab6646ab23baa8d95f1c723891b87a7ffd6c8bb95cbe8908f6ba7f2f1501",
		"Mature cheetah",
		"Alter Gepard"
	],
	"unit zone5_spider": [
		"a2957bba4a03d5df69f7659616552884d5f4bb54b0f976d498ffa85601b24220",
		"Mature giant spider",
		"Alte Riesenspinne"
	],
	"unit zone7_batred1": [
		"71e53cbd4b2431401273e48033a5b5bf16557aa05fe53bfb7a3bd5aa79ef08d2",
		"Young bat",
		"Junge Fledermaus"
	],
	"unit zone7_boarred1": [
		"178c0b324b9d3dd2ec6c150ea743bc55cf8b5100b976f24c078ee65ecd6a7b13",
		"Young boar",
		"Junges Wildschwein"
	],
	"unit zone7_boarred2": [
		"1eb77425a626ade605358e5787b8bc45c561c1afb33f922fa66ad4efe99bb5eb",
		"Adult boar",
		"Ausgewachsenes Wildschwein"
	],
	"unit zone7_elemental": [
		"fe4abb4fefb0bb797045881df4ea3cad0fd3003b13908ff0e68fe2163edf76f5",
		"Elemental guardian",
		"Elementarwächter"
	],
	"unit zone7_goblin_archer": [
		"ae642a400f8f8ad3bcacf074eb1888f2917961b4cae16e56df7cdb591da14865",
		"Goblin with a sling",
		"Goblin mit Schleuder"
	],
	"unit zone7_goblin_boss": [
		"a3082c205b42fc46dfdf306a42146dc831e269f818e923748e6fdd391b02f96b",
		"Goblin chief",
		"Goblinhäuptling"
	],
	"unit zone7_goblin_fighter": [
		"4c591f650dfbfaeb33185c87823e73c366ddb76b19c812d04de26294d761a190",
		"Goblin with a spear",
		"Goblin mit Speer"
	],
	"unit zone7_skeleton1": [
		"62d790a97933a06f02edf48582e2dcc914e9251ec8a7d172d5def6d19a928e74",
		"Commoner's skeleton",
		"Skelett"
	],
	"unit zone7_skeleton2": [
		"0c17f6ae7cd36cfb9e27b240a12e199f497651437c50cebe34ec4ade1d71970b",
		"Soldier's skeleton",
		"Soldatenskelett"
	],
	"unit zone7_skeletondark": [
		"e001eee9c43e123bdfd581637b5de299d1970e9128b011691ce9df08b6106369",
		"Veteran warrior skeleton",
		"Skelett-Veteran"
	],
	"unit zone7_skeletondarkw": [
		"b8e122bba5bd53fe27468b8fcf1a7c1b93823ced695d72a545b161e54c57023a",
		"Officer's skeleton",
		"Skelett eines Offiziers"
	],
	"unit zone7_tigerred1": [
		"4f65d14c7a2ef7eba60619316da5dd38f3f28327474b6975f32fa73324c0b997",
		"Young tiger",
		"Junger Tiger"
	],
	"unit zone7_tigerred2": [
		"003c6c8220a58b302d9bf92e95d391d9e283f1b7ab54dcfe8b049ffaedf97492",
		"Adult tiger",
		"Ausgewachsener Tiger"
	],
	"unit zone7_toad": [
		"7b0c21fd2d1acf6c7ebfbeb76d584eb41399108897064ecf1d9aaf7c93df7ed7",
		"Young poisonous toad",
		"Junge giftige Kröte"
	],
	"unit zone7_undead_fighter_m": [
		"f2bdf872555702e99c2190aff1d0f83b0536b7bbcdaea29a74a92b114b78f216",
		"Ghoul warrior",
		"Ghulkrieger"
	],
	"unit zone7_undead_mage_m": [
		"ea5b1a60d901af62898fa7c4d05dda8ee003f80a5de77a103c3cdbcc45c1af9a",
		"Ghoul mage",
		"Ghulmagier"
	],
	"unit zone7_willowisp1": [
		"d6cf214cde307dc9e6a3873036f67a38bfa15a2c0ce7e3f0c6c0139c7f0a02f3",
		"Will-o'-the-wisp",
		"Irrlicht"
	],
	"unit zone7_wolfgrey1": [
		"866366133f29eb326ec4ae8ae311e62a36986e62b4e5cd39cc095c3976af72d8",
		"Young grey wolf",
		"Junger grauer Wolf"
	],
	"unit zone7_wolfgrey2": [
		"76353a724e0d1913ec12bfcdd1b6ddc03aa09be776cbda5a926f1385e8fe286e",
		"Adult grey wolf",
		"Ausgewachsener grauer Wolf"
	],
	"unit zone9_batred": [
		"a3fbf6215e126393562e68c751f89a39f76a444858ee3397314289a2ddf0c0aa",
		"Bat",
		"Fledermaus"
	],
	"unit zone9_boardark1": [
		"875553ed96f97cb8996f9fc174e0b28ce31a8e9434d647d4a35aff8a042fcd77",
		"Young black boar",
		"Junges schwarzes Wildschwein"
	],
	"unit zone9_boardark2": [
		"288a7450efcb8ccbdf7d613a9f12bf54bfb9e51bffbe2b72a9b47daf9d9d9e0c",
		"Black boar",
		"Schwarzer Eber"
	],
	"unit zone9_boarred1": [
		"178c0b324b9d3dd2ec6c150ea743bc55cf8b5100b976f24c078ee65ecd6a7b13",
		"Young boar",
		"Junges Wildschwein"
	],
	"unit zone9_boarred2": [
		"e72f928ba84242796be6104cf1ae063912b671c1cea01fe7be52ffbb6570dd0b",
		"Veteran boar",
		"Wildschwein (Veteran)"
	],
	"unit zone9_dragongreen": [
		"b61674ff99b6b2d11a7e313dff31d19167e196f21b03a9aa35053240696d907b",
		"Green dragon",
		"Grüner Drache"
	],
	"unit zone9_goblin_archer": [
		"1c44127226dd0befdd5288659af986cd76808633ca313b4041c8ccd15f198e0c",
		"Trained Goblin with a sling",
		"Ausgebildeter Goblin mit Schleuder"
	],
	"unit zone9_goblin_fighter": [
		"0be8db871c57113e61aacc8e94338fe6392189454507ec70b6b24e6a65c9861d",
		"Trained Goblin with a spear",
		"Ausgebildeter Goblin mit Speer"
	],
	"unit zone9_human_archer1_f": [
		"2604c3e29886c8ba03c3cb51124865956ccb1a570476ff8ba887496d913ab281",
		"Inexperienced archer woman",
		"Unerfahrene Bogenschützin"
	],
	"unit zone9_human_fighter1_m": [
		"44e9d907d2273bd51453684dd51a415964ee378fdeea55e1303f77aed9967b21",
		"Inexperienced warrior",
		"Unerfahrener Krieger"
	],
	"unit zone9_human_fighter2_m": [
		"e40053214149d57aac191ced311e4cd99406bf7930673181eefa8e5dc1f6aef2",
		"Soldier",
		"Soldat"
	],
	"unit zone9_human_mage1_f": [
		"8c02a90855c381eba6e5a85f5795181d90df14904d1d12c7a369eabcfec17faf",
		"Inexperienced sorceress",
		"Unerfahrene Zauberin"
	],
	"unit zone9_lizardblack": [
		"b6a56adde8178cc9c27b2857d4231062fcc47eeacfe94106be94ce3d120dce74",
		"Mountain lizard",
		"Bergechse"
	],
	"unit zone9_lizardgreen1": [
		"58a5ae824bb0e41b4afac9b5ee391517d81dcd1d30e16d495b88aac2d5617efa",
		"Forest lizard",
		"Waldechse"
	],
	"unit zone9_ogre": [
		"394bf35881fbef43c64bcd6fc164a2002583d05e004a1aa63d9391ee452d0218",
		"Hungry ogre",
		"Hungriger Oger"
	],
	"unit zone9_orc_archer1_f": [
		"ed963f374e2b272e426bdb8334e16078fce8e16de41461622c16a9dcd55df74d",
		"Veteran female Orc",
		"Weiblicher Ork (Veteran)"
	],
	"unit zone9_orc_archer2_f": [
		"ed963f374e2b272e426bdb8334e16078fce8e16de41461622c16a9dcd55df74d",
		"Veteran female Orc",
		"Weiblicher Ork (Veteran)"
	],
	"unit zone9_orc_fighter1_m": [
		"af0cb490d37c588c683c908be3357bf48425cbb8a93f41fb130f55db2cc796da",
		"Veteran Orc",
		"Ork-Veteran"
	],
	"unit zone9_orc_fighter2_m": [
		"af0cb490d37c588c683c908be3357bf48425cbb8a93f41fb130f55db2cc796da",
		"Veteran Orc",
		"Ork-Veteran"
	],
	"unit zone9_orc_mage1_f": [
		"1b490666dda06eee85c5a5c6790be3f42f39244b45ad759d28acd3ec7eab8aad",
		"Skillful Orc seer",
		"Erfahrener Ork-Seher"
	],
	"unit zone9_succub": [
		"2e8e3bf66ca37f08e37220fe249c7d6f4694c7928665d544eb45bf954d19fbd3",
		"Adult Harpy",
		"Erwachsene Harpyie"
	],
	"unit zone9_toad1": [
		"c2163a0db24aaf8fc462c4d4a69721f11569224e41b7b2fa9a64ec96d0c717a4",
		"Poisonous toad",
		"Giftkröte"
	],
	"unit zone9_trollgreen": [
		"8b70faac43f64482c4ff59d5c954621ed961844a158396605d430d46903ac740",
		"Tamed green troll",
		"Gezähmter grüner Troll"
	],
	"unit zone9_willowisp": [
		"8a1c4eccba5e197ae4d327dd0cda5b8ab72c61043c22307a948c874e653c5734",
		"Hot Will-o'-the-wisp",
		"Heißes Irrlicht"
	],
	"unit zone9_wolfgrey1": [
		"866366133f29eb326ec4ae8ae311e62a36986e62b4e5cd39cc095c3976af72d8",
		"Young grey wolf",
		"Junger grauer Wolf"
	],
	"unit zone9_wolfgrey2": [
		"f73f8c84752d568480e797eaabdd09a09981ff8b642946bb85d644797612576f",
		"Mature grey wolf",
		"Alter grauer Wolf"
	],
	"unit zone9_wolfwhite1": [
		"fcd41553cd714baf059d3c456a04a377cf67e4a6a20ae5dcfa2c26a371a3f010",
		"Young white wolf",
		"Junger weißer Wolf"
	],
	"unit zone9_wolfwhite2": [
		"f7d7298e7e9f224f0624a889268b55f72e58e54e36386da54cf3600e90c09a95",
		"White wolf",
		"Weißer Wolf"
	],
	"unit zonefinal_jun_firez_m": [
		"4c23fdff74c64f30e7ceb5a8c61ac3ae9f999d9cb76dc974d353ef1f4b1a618f",
		"Firez",
		"Firez"
	],
	"unit zonefinal_skeleton": [
		"8f2c3d4b6b1f4339d640fed0a0a652b1be887627d86d9e20b3f2e65cad4305b8",
		"Golden skeleton",
		"Goldenes Skelett"
	],
	"unit zonezero_human_fighter1_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit zonezero_human_fighter2_m": [
		"f38088da8af455f437437451cc618d56e60037e0af9cade14286476d55e16aa6",
		"Guard",
		"Wache"
	],
	"unit zonezero_human_fighter3_m": [
		"64720cc2f0797363409b3ecf965e4b5db27a87480cc3616d03caa187cbe21dda",
		"Firez's guardsman",
		"Gardist von Firez"
	],
	"unit zonezero_rat": [
		"d73484f4f04fd60bb7f4679f7216abc82857bd94887cc3523420943def0fd541",
		"Mouse",
		"Maus"
	],
	"unit zonezero_scrab": [
		"ad3cea04c749534bd054b8ac7a4a5f91d496969b60393f5bb31b340b5433337e",
		"Young armadillo",
		"Blutreißer-Jungtier"
	],
	"unit zonezero_skeleton": [
		"83660c296d8296f9ba853e6f9fa0a5f5f4023780c294e1e71d93ad96c8d7b186",
		"Child's skeleton",
		"Skelett eines Kindes"
	],
	"unit zonezero_succub": [
		"1f16e791cb3838d0f60611398f7de0759e8d2e0c4970f6c209ae0a2ea76098b1",
		"Stone harpy",
		"Steinharpyie"
	],
	"unit zonezero_toad": [
		"c2163a0db24aaf8fc462c4d4a69721f11569224e41b7b2fa9a64ec96d0c717a4",
		"Poisonous toad",
		"Giftkröte"
	],
	"weapon axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon axe adamantium": [
		"3c8b3b4a94b051c9da9e43639fed4d4bf93fb0a27799f081cac4fbf2cb963804",
		"Adamantite axe\nThis weapon is very expensive - but it is worth it.",
		"Adamant-Axt\nAdamant ist immer seinen Preis wert."
	],
	"weapon axe bronze": [
		"34a0008a14d391eb2d3fb2a667a36f2d3bb4a7dfcb039c90e824d33d1525f790",
		"Bronze axe\nThe simplest of metal axes. Do not rely on it too much.",
		"Bronze-Axt\nDie einfachste aller Metalläxte. Man sollte sich nicht zu sehr darauf verlassen."
	],
	"weapon axe iron": [
		"ff8fcbc1682fb1ba587298578b874c562c5d2ac8eaefafa390d4d82369ca4577",
		"Iron axe\nThis causes more damage than a bronze one. But there are better materials than iron.",
		"Eisen-Axt\nRichtet mehr Schaden als eine Bronzeaxt an. Aber es gibt besseres Material."
	],
	"weapon axe meteoric": [
		"3c0de0a4d4703722525a43844feb32facfd51b0c920b27d93faf8f13c1d40b87",
		"Meteorite axe\nIn the hands of an experienced fighter, this can really make the enemy suffer...",
		"Meteorit-Eisen-Axt\nIn der Hand eines erfahrenen Kämpfers eine Furcht erregende Waffe."
	],
	"weapon axe mithrill": [
		"988f9a205515ea915f015ed9383be94eb14d64c659b8e55475195ca4e048c613",
		"Mithrill axe\nLight, sharp, finely honed... and expensive.",
		"Mithril-Axt\nLeicht, stabil, scharf. Aber teuer..."
	],
	"weapon axe steel": [
		"da32d543676b1fe5f751d726dd8c6da726ab6111996c61d02d4afbc65431d89a",
		"Steel axe\nThis won't penetrate all types armor, but it can still be dangerous in the hands of an experienced fighter…",
		"Stahl-Axt\nKann es nicht mit jeder Rüstung aufnehmen, ist aber trotzdem keine schlechte Waffe."
	],
	"weapon bad_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe bronze": [
		"d939e0f4c2c4584ed2bda539e1ea026ec0c9f721740fc0ea0b290cbe5564debf",
		"Flimsy axe\nThis axe can chop firewood. Or make a mess of it...",
		"Wackelige Axt\nMit dieser Axt kann man Brennholz hacken. Oder zertrümmern ..."
	],
	"weapon bad_axe iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_axe steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow bronze": [
		"80ab8da3c99bc48e4b4deae772b4809a37694b0bbc4a3561fbd73a50e5bdb5a3",
		"Battered crossbow\nCan also serve as a club in close combat. It is no great loss.",
		"Ramponierte Armbrust\nKann im Nahkampf auch als Keule dienen. Schade wäre es nicht darum."
	],
	"weapon bad_crossbow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_crossbow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger bronze": [
		"d0679155c57fa0d8d3ea6a59f4c56bd4dd2aec241f1621fb2aa24b25950bdabc",
		"Kitchen knife\nThis knife can separate a hyena's ears from its head.",
		"Küchenmesser\nMit diesem Messer lassen sich einer Hyäne die Ohren vom Kopf trennen."
	],
	"weapon bad_dagger iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_dagger steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer bronze": [
		"8b9c210d7f6288d5c8e1af34c69054a87a7042f5b65e62f3d35252f3241d03a8",
		"Club\nIdeal for beating dust from carpets and sense into slaves.",
		"Knüppel\nIdeal, um Staub aus Teppichen und Verstand in Sklavenköpfe zu prügeln."
	],
	"weapon bad_hammer iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_hammer steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow bronze": [
		"eebbc6514b771d484c64584aea3810389982ca040798ee24415a33840333613c",
		"Old bow\nA good aid for a novice archer who dreams of mastering the craft.",
		"Alter Bogen\nEine gute Hilfe für einen angehenden Bogenschützen, der von Meisterschaft träumt."
	],
	"weapon bad_short_bow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_short_bow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear bronze": [
		"ac536bde9ab83739e47d7944fb82aa283b5b0d26dee6b2f904b6ff0478a4c0da",
		"Poor pike\nThe name says it all.",
		"Schlechte Pike\nDer Name sagt alles."
	],
	"weapon bad_spear iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_spear steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword bronze": [
		"abba4388f5a703fba3a9a4186c8861d218e803d9111bed6578068a4e1e99be5e",
		"Unbalanced sword\nYou will not swing this sword around easily!",
		"Unausgewogenes Schwert\nDieses Schwert lässt sich nicht leicht schwingen!"
	],
	"weapon bad_sword iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bad_sword steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon battle_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon battle_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon battle_axe adamantium": [
		"101c0bc031d679bcaa5eb69493ca95890343678b49720b8fef809f66982e9df8",
		"Adamantite battle axe\nThis is worth the price and good enough for serious fighting.",
		"Streitaxt aus Adamant\nDiese Axt ist absolut kampftauglich und damit ihren Preis wert!"
	],
	"weapon battle_axe bronze": [
		"e8de18c8dc165d08874a09c4aec812680cd8bfa5bc09e794014d720c49f9490d",
		"Bronze battle axe\nThis is not much better than a simple bronze axe.",
		"Streitaxt aus Bronze\nBesser als die einfache Bronzeaxt. Aber nicht viel besser..."
	],
	"weapon battle_axe iron": [
		"594d1be0244c222985c8643c4425d0f6064125fe259e00589dbb4789b86a1667",
		"Iron battle axe\nThere are better materials than this - if you can afford them, of course.",
		"Streitaxt aus Eisen\nEs gibt Besseres - wenn man es sich leisten kann."
	],
	"weapon battle_axe meteoric": [
		"557b707040c2635c3ef5fd5c473b8f95560e5115adfd9694d50e6bc37b0a5521",
		"Meteorite battle axe\nYou would be hard pressed to find armor which would withstand this axe, even in the coffers of kings.",
		"Streitaxt aus Meteorit-Eisen\nEs gibt kaum eine Rüstung, die dieser Axt gewachsen ist."
	],
	"weapon battle_axe mithrill": [
		"6392fe588dc6c8420f961b2e9e46292f96e6a694086f2c879324c008d8330019",
		"Mithrill battle axe\nReally good... And the price is appropriate.",
		"Streitaxt aus Mithril\nEine wirklich gute Waffe - der Preis ist dementsprechend."
	],
	"weapon battle_axe steel": [
		"b8d544b99f52ee040a0e31666a8bec945d3d0734eb64c70344c4767c229fd245",
		"Steel battle axe\nThis one is not bad at all! Though your opponent may have even better armor...",
		"Streitaxt aus Stahl\nKeine schlechte Waffe. Aber die Rüstung des Gegners könnte eventuell stärker sein."
	],
	"weapon bone_club": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_club ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_club burned_bones": [
		"84d19e5e2185946aecc49ab741f7295eb286049da33e3f3d6f86e0b7eaa797c0",
		"Bone club (hard bone)\nA good instrument to use on alone Orc.",
		"Knüppel aus hartem Knochen\nIdeal, um einem einzelnen Ork das Fürchten zu lehren."
	],
	"weapon bone_club decayed_bones": [
		"f441edb7f5ff00f0c5dcdd469d6975e4e035e15bbda2a6a1743fd49fb2036b34",
		"Bone club (thin bone)\nA club is a club.",
		"Knüppel aus einfachem Knochen\nEin Knüppel bleibt ein Knüppel!"
	],
	"weapon bone_club dragon_black_bones": [
		"37b3510bbbb5e266720c55c4f4dc9f13e0e224df648ab1c7c22eb77cc779fc87",
		"Bone club (Blue Dragon bone)\nPerfect for charging with a spell!",
		"Knüppel aus blauem Drachenknochen\nWenn man diesen Knüppel auch noch mit einem Zauber belegt..."
	],
	"weapon bone_club dragon_green_bones": [
		"811d1c1256a5a81a3a70497e828f73f3badfcd525582fd89c27d92f3bc20948e",
		"Bone club (Green Dragon bone)\nA blow from this club will leave no one indifferent!",
		"Knüppel aus grünem Drachenknochen\nEin Schlag mit dieser Keule lässt niemanden kalt!"
	],
	"weapon bone_club dragon_red_bones": [
		"392d79aa4cdbc9e113f1f8119a6f7210e10eb15c04bf67897990561e6f12f3f9",
		"Bone club (Red Dragon bone)\nNow you definitely cannot call this just a club...",
		"Knüppel aus rotem Drachenknochen\nDefinitiv mehr als bloß irgendein Knüppel..."
	],
	"weapon bone_club dry_bones": [
		"e8c8738dea0cc696996173191efce244dcc09a10edf7b2740b2efde937abcf9f",
		"Bone club (tough bone)\nUsing this, you could deal with a Goblin, but do not be so sure with an Orc!",
		"Knüppel aus festem Knochen\nMit einem Goblin kann es dieser Knüppel aufnehmen. Bei Orks kann man sich da nicht mehr so sicher sein."
	],
	"weapon bone_club scrab_bones": [
		"1a9c41f7c246a0bace0077d06ac1c3a37d9ae7b10a98f8f93a45f6740524404b",
		"Bone club (shell bone)\nShell bone is a good material for all kinds of weapons.",
		"Knüppel aus Panzerknochen\nPanzerknochen sind ein gutes Material für jegliche Art von Waffen."
	],
	"weapon bone_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_crossbow burned_bones": [
		"a9b495e68f25befed84665666718eae5afc52a8f0b2b577dc1543d8e78d28659",
		"Bone crossbow · Hard bone\nFor those short of money but eager to shoot a mechanical toy.",
		"Knochenarmbrust · Harter Knochen\nFür alle, die wenig Geld haben, aber unbedingt mit einem mechanischen Spielzeug schießen wollen."
	],
	"weapon bone_crossbow decayed_bones": [
		"981b8c57e2eee22fc8da3563f7e357e7858bb9dba4adf7e14a30e9225c0681ae",
		"Bone crossbow · Thin bone\nMaking a crossbow on Gipath is an art. Using thin bone for it is madness.",
		"Knochenarmbrust · Dünner Knochen\nAuf Gipath eine Armbrust zu bauen ist eine Kunst. Dafür dünnen Knochen zu verwenden ist Wahnsinn."
	],
	"weapon bone_crossbow dragon_black_bones": [
		"9cd63a95139df23a8ff8e571b8f771bfb9b2dcf225d0b5148d457a4462f9ae3e",
		"Bone crossbow · Blue Dragon bone\nNo better crossbow can be found on Gipath.",
		"Knochenarmbrust · Blauer Drachenknochen\nEine bessere Armbrust findet man auf Gipath nicht."
	],
	"weapon bone_crossbow dragon_green_bones": [
		"ff1c71ef7b6e1ef120178649d0870fc406ca950a7af7ab38beeefde848f3b3da",
		"Bone crossbow · Green Dragon bone\nThis magnificent weapon will cost a great deal of money.",
		"Knochenarmbrust · Grüner Drachenknochen\nDiese prächtige Waffe kostet sehr viel Geld."
	],
	"weapon bone_crossbow dragon_red_bones": [
		"729e7c290cece96af9bdb86b0a8d8505779e5f5d78019dbd742256d515d7de1c",
		"Bone crossbow · Red Dragon bone\nA troll had better beware.",
		"Knochenarmbrust · Roter Drachenknochen\nDa sollte sich ein Troll in Acht nehmen."
	],
	"weapon bone_crossbow dry_bones": [
		"d14bc76d83ccdf5b574f68fd8b0e4c0f20641c4464c884f3745937874eb65213",
		"Bone crossbow · Tough bone\nAn excellent weapon made from poor material.",
		"Knochenarmbrust · Fester Knochen\nEine ausgezeichnete Waffe aus schlechtem Material."
	],
	"weapon bone_crossbow scrab_bones": [
		"4b3e9a915a93d53f7cadba825a6516fefe6bf9aa127e904425bf06bc7ab17c47",
		"Bone crossbow · Shell bones\nDecent price/performance ratio.",
		"Knochenarmbrust · Panzerknochen\nAnnehmbarer Schutz zu einem guten Preis."
	],
	"weapon bone_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_dagger burned_bones": [
		"e73713c2856dbfc9d55baf02bc1c151dbcb0de3fb901eff8594ffffab062609b",
		"Bone knife · Hard bone\nGood enough to begin with.",
		"Knochenmesser · Harter Knochen\nFür den Anfang gut genug."
	],
	"weapon bone_dagger decayed_bones": [
		"57e1cb734deb1141ae08dba8c2399d39a045883ce634410a7b49e3654dfc418e",
		"Bone knife · Thin bone\nA bone knife is better than stone, but this material is a very poor choice.",
		"Knochenmesser · Dünner Knochen\nEin Knochenmesser ist besser als Stein, doch dieses Material ist äußerst schlecht gewählt."
	],
	"weapon bone_dagger dragon_black_bones": [
		"0d302230eab75911b0504f28e38dc4a8a4eb2fd98f7f323ab3a6173634816ea7",
		"Bone knife · Blue Dragon bone\nThe very best knife on Gipath.",
		"Knochenmesser · Blauer Drachenknochen\nDas allerbeste Messer auf Gipath."
	],
	"weapon bone_dagger dragon_green_bones": [
		"f003a048bad3f76e68ed6848fdacd533002559fe0bede611014e0c96b90256f9",
		"Bone knife · Green Dragon bone\nA true fighting knife.",
		"Knochenmesser · Grüner Drachenknochen\nEin echtes Kampfmesser."
	],
	"weapon bone_dagger dragon_red_bones": [
		"a5be98e47696faee4b862e5f4c4f0cac2b8aeaf74bf5370a68bd0a4646e3a481",
		"Bone knife · Red Dragon bone\nA knife like this is a sign of high social standing.",
		"Knochenmesser · Roter Drachenknochen\nEin solches Messer zeugt von hohem gesellschaftlichem Rang."
	],
	"weapon bone_dagger dry_bones": [
		"37003e5638cdb7f44cc63f0669946727ffd4ecb880fb1a2694a76facbff54eab",
		"Bone knife · Tough bone\nSlightly better than a thin-bone knife.",
		"Knochenmesser · Fester Knochen\nEtwas besser als ein Messer aus dünnem Knochen."
	],
	"weapon bone_dagger scrab_bones": [
		"dc57be05aaee03dca79ec701a7eb0c84fc80149d9b9dc69ef6b02a933642968c",
		"Bone knife · Shell bones\nWith this knife alone, you can face a black boar without fear.",
		"Knochenmesser · Panzerknochen\nMit diesem Messer allein kann man einem schwarzen Eber furchtlos begegnen."
	],
	"weapon bone_long_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_bow burned_bones": [
		"9ee4697e26265a277d17cd741f01dee39efb7e96cb96cdaa121c1b13cead37d3",
		"Long bone bow (hard bone)\nAn improvement on a dry bone bow.",
		"Langbogen aus hartem Knochen\nBesser als ein einfacher Knochenbogen."
	],
	"weapon bone_long_bow decayed_bones": [
		"b684994190d625ded541bca8319320cd295d574797fc4ebee3e80b8a37716447",
		"Long bone bow (thin bone)\nGood enough for training or hunting.",
		"Langbogen aus einfachem Knochen\nBestenfalls gut genug für die Jagd…"
	],
	"weapon bone_long_bow dragon_black_bones": [
		"ccba38cf237394f611363e30945a13b11ab9df54192395cb7726300df00cfa10",
		"Long bone bow (Blue Dragon bone)\nA remarkable material put to good use!",
		"Langbogen aus blauem Drachenknochen\nEine gute Waffe aus einem bemerkenswerten Material."
	],
	"weapon bone_long_bow dragon_green_bones": [
		"2d03a22c93a7faa9f910bb3c8cbd65f82bc33e6f2cfc07fafd8cf58616a50f1b",
		"Long bone bow (Green Dragon bone)\nFew other bone bows can compare with this one!",
		"Langbogen aus grünem Drachenknochen\nNur wenige Bögen können sich mit diesem messen."
	],
	"weapon bone_long_bow dragon_red_bones": [
		"764676bdfbc371f42127e0226f316f6b1fa9d91eb104e72a1f1b9e5a87e65da3",
		"Long bone bow (Red Dragon bone)\nOne of the best kinds of long bone bows.",
		"Langbogen aus rotem Drachenknochen\nEiner der besten Langbögen."
	],
	"weapon bone_long_bow dry_bones": [
		"d1ace9cc85eb0baf21ccf262f0afec2794703c66f766d07cc5a56652c2008828",
		"Long bone bow (tough bone)\nNot the worst option, but there are better weapons than this!",
		"Langbogen aus festem Knochen\nNicht der schlechteste Bogen, aber es gibt bessere!"
	],
	"weapon bone_long_bow scrab_bones": [
		"09db73ca7c1d4e3d7bbdef695def8d30a779863e9a122300bc3b788056060df6",
		"Long bone bow (shell bone)\nNot a bad thing to have with you when you go for a walk!",
		"Langbogen aus Panzerknochen\nEin wertvoller Begleiter für jede Art von Unternehmung."
	],
	"weapon bone_long_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow burned_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow decayed_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow dragon_black_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow dragon_green_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow dragon_red_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow dry_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_long_crossbow scrab_bones": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_short_bow burned_bones": [
		"30e85162e6c6721e6895b8bae8d5b654eff07dcfb819d415d3c731cb4df90b7c",
		"Short bone bow (hard bone)\nArrows shot from this one are dangerous and not just for Goblins!",
		"Kurzbogen aus hartem Knochen\nDamit treibt man nicht nur Goblins in die Flucht!"
	],
	"weapon bone_short_bow decayed_bones": [
		"7855752d6e8b9ffc8570e5159fefecc851341ded78d4cd5bc44c5ee5f811c27b",
		"Short bone bow (thin bone)\nNot a bad weapon, but some enemies will not even notice it....",
		"Kurzbogen aus einfachem Knochen\nKein schlechter Bogen, aber er wird nicht unbedingt auf alle Gegner Eindruck machen."
	],
	"weapon bone_short_bow dragon_black_bones": [
		"244baa2bc4003b45ef2e723c7f683df1654ba3666a218a3448820034e7d647ec",
		"Short bone bow (Blue Dragon bone)\nImpossible to find a better bone bow - except for the ones infused with magic.",
		"Kurzbogen aus blauem Drachenknochen\nNur magische Bögen sind besser."
	],
	"weapon bone_short_bow dragon_green_bones": [
		"2919c620282e39d1b2bf74a195074d809c0e285d77d5f86cf993729b0cef1698",
		"Short bone bow (Green Dragon bone)\nIn a different league altogether...",
		"Kurzbogen aus grünem Drachenknochen\nEs gibt nur wenig Vergleichbares."
	],
	"weapon bone_short_bow dragon_red_bones": [
		"0b5894a0a0d4501696f4fd2acecae8fcd92cb9802de089854fbfd9f1330c4004",
		"Short bone bow (Red Dragon bone)\nOne of the best kinds of bone bows.",
		"Kurzbogen aus rotem Drachenknochen\nEiner der besten Knochenbögen!"
	],
	"weapon bone_short_bow dry_bones": [
		"5d59f90a4c1b5e64800e6cd035563f898d916890d9ea2fd0370af64e3cf38ebc",
		"Short bone bow (tough bone)\nBetter than a simple bow, but you should think about trying a more decent material...",
		"Kurzbogen aus festem Knochen\nBesser als ein normaler Bogen. Aber es gibt sicherlich noch besseres Material."
	],
	"weapon bone_short_bow scrab_bones": [
		"2259062300b0fa3a26b497971288df80ba34430c4ba7c6a5799bc18c4f150ccb",
		"Short bone bow (shell bone)\nNo one is going to like being hit by arrows shot from this bow.",
		"Kurzbogen aus Panzerknochen\nEin Pfeil von diesem Bogen ist für jeden Gegner ein Problem."
	],
	"weapon bone_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon bone_spear burned_bones": [
		"65ecd0a35eac43a4ec4124031b385f0fd7a8f861fd53c1ba2cb4dd794cd624e3",
		"Bone spear (hard bone)\nNot a bad weapon against Goblins... but that's it.",
		"Speer aus hartem Knochen\nNicht schlecht gegen Goblins... Aber mehr auch nicht."
	],
	"weapon bone_spear decayed_bones": [
		"1c0597c1cfdf02d0b2a62bd25fc460a5412cdfedd39173b6cd9cb5bb25f16ff4",
		"Bone spear (thin bone)\nMuch lighter than stone spears -  about all you can say for it.",
		"Speer aus einfachem Knochen\nWesentlich leichter als ein Steinspeer. Das ist aber auch schon alles!"
	],
	"weapon bone_spear dragon_black_bones": [
		"008660559887f94da3bd3be82b6cf8925f98f63a9d16beadf35126ac88d56138",
		"Bone spear (Blue Dragon bone)\nThe only way to better a Dragon bone spear is to infuse it with a powerful spell...",
		"Speer aus blauem Drachenknochen\nNur verzaubert sind Drachenspeere noch besser."
	],
	"weapon bone_spear dragon_green_bones": [
		"77af46e568d3b68aafe38280a9cbd5d361616cae30898588e400d736129b5451",
		"Bone spear (Green Dragon bone)\nA Dragon bone spear is a good thing. A magical one is even better.",
		"Speer aus grünem Drachenknochen\nDas Einzige, was einen Drachenspeer übertrifft, ist ein magischer Drachenspeer."
	],
	"weapon bone_spear dragon_red_bones": [
		"8c4a1574c91f3a8a70f7571cf3962e56da62e7a9e0d2cbbfeb089b9d0b23b390",
		"Bone spear (Red Dragon bone)\nA spear made of Dragon bone is a decent weapon. A magician could make it better still.",
		"Speer aus rotem Drachenknochen\nEin Speer aus Drachenknochen ist eine beachtliche Waffe. Ein Magier könnte ihn mit Zaubern noch verbessern."
	],
	"weapon bone_spear dry_bones": [
		"ef4e2736f95fb87033b0cf7720ac3efeb49a523383e0f1f389b48a9d432f2f8a",
		"Bone spear (tough bone)\nThis is sharper than one made of thin bone; but maybe you should get something better?",
		"Speer aus festem Knochen\nSchärfer als einfacher Knochen. Aber vielleicht sollte es doch ein besseres Material sein?"
	],
	"weapon bone_spear scrab_bones": [
		"b3f601f664f0925a3fa6278fcb34be346e724712fc5c28c3dc565c1b43ed1ce9",
		"Bone spear (shell bone)\nNow this is something serious.",
		"Speer aus Panzerknochen\nDas ist eine akzeptable Waffe!"
	],
	"weapon cheat_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon cheat_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon cheat_dagger adamantium": [
		"d7dd6713afb762954dade4a586342921abf9fcefba23fe79bdc21978cd5f4906",
		"Ritual knife · Adamantite\nThis metal is far too expensive to waste on trifles like this!",
		"Ritualdolch · Adamantit\nDas Metall ist einfach zu teuer, um es mit so einem Spielzeug zu verschwenden."
	],
	"weapon cheat_dagger bronze": [
		"2e1088f730f459b1975f5f5be056fd827a2d429655abf39901b78e9a559568fd",
		"Ritual knife · Bronze\nYes... you should start looking for something more serious as soon as possible...",
		"Ritualdolch · Bronze\nDu solltest dich schnellstens nach etwas anderem umsehen."
	],
	"weapon cheat_dagger iron": [
		"f937f53eeeca6a7e8660c1ed01341dad6a744ee7a4b43609e64239ddf5449124",
		"Ritual knife · Iron\nIron, bronze - not much difference really.",
		"Ritualdolch · Eisen\nEisen, Bronze - es macht keinen großen Unterschied."
	],
	"weapon cheat_dagger meteoric": [
		"153548654d52bdd3fb96d00ff6d0a344cbbca13e7548204658024fa69965153e",
		"Ritual knife · Meteorite\nIs meteorite iron really so cheap you would waste it like this?",
		"Ritualdolch · Meteorit\nMan sollte Meteorit-Eisen nicht so verschwenden!"
	],
	"weapon cheat_dagger mithrill": [
		"e759a8cf6081e4751fcf3630d51f0d7a9251617dd7dc8ff77793b2df22e3749b",
		"Ritual knife · Mithrill\nOne could find a better use for mithrill!",
		"Ritualdolch · Mithril\nAus Mithril kann man sicherlich bessere Sachen machen."
	],
	"weapon cheat_dagger steel": [
		"59838550cdbacd68c61d30a1fa3a0d07dd4026e558abeece4c467ff5871f196b",
		"Ritual knife · Steel\nLooks exquisite, but it is not much use.",
		"Ritualdolch · Stahl\nSieht gut aus, ist aber kaum von Nutzen."
	],
	"weapon crash_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe bronze": [
		"c3a3cbf0f22d0c965b2c41594a44528c1ee2f59c8834325f0535a065962be1bf",
		"Overhardened hatchet\nThis axe will do for chasing rats.",
		"Überhärtetes Beil\nMit dieser Axt kann man Ratten jagen."
	],
	"weapon crash_axe iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_axe steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow bronze": [
		"cfa7bb22da105231473b724a96af5aef1dfbc253145f83d864a58974ea06cf12",
		"Old crossbow\nPierces leather armour from a hundred paces.",
		"Alte Armbrust\nDurchschlägt Lederrüstung auf hundert Schritte."
	],
	"weapon crash_crossbow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_crossbow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger bronze": [
		"436ecff733c7dc0c8e954ae881c542d5d6b6081d002685730a9098c5d26f2438",
		"Stiletto\nIt will do to begin with.",
		"Stilett\nFür den Anfang reicht es."
	],
	"weapon crash_dagger iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_dagger steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow bronze": [
		"0dd583aea6416d0cea37cb1306f868b65544b4406ba4d224ece019e088290ff2",
		"Poor bow\nThe best value for money.",
		"Schlechter Bogen\nDas beste Preis-Leistungs-Verhältnis."
	],
	"weapon crash_short_bow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_short_bow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear bronze": [
		"b0f10ba7ed9d486f7abfca8151e244fa04ab364571d5e70611b96010c3aa51e6",
		"Light pike\nA decent weapon for a beginner.",
		"Leichte Pike\nEine ordentliche Waffe für Anfänger."
	],
	"weapon crash_spear iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_spear steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword bronze": [
		"2c945eb6a5682b62c3514b13e093eb733a4b0099a7de3c075108204809fc2619",
		"Broken sword\nA good blade, apart from having been cracked and hastily reforged.",
		"Zerbrochenes Schwert\nEine gute Klinge, wenn man davon absieht, dass sie angebrochen war und hastig neu geschmiedet wurde."
	],
	"weapon crash_sword iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crash_sword steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crossbow adamantium": [
		"64ca0678f0e12c37d26bb5f4b55a83aa734921328885f3a7ac100c4cd026dea8",
		"Adamantite crossbow\nWith this one in your hands, you can afford to be a bit impolite.",
		"Adamant-Armbrust\nMit dieser Armbrust kann man sich jederzeit Respekt verschaffen."
	],
	"weapon crossbow bronze": [
		"682c1e8a20ae9bb9f604f91588873cf2230fe7a10e74b2b712758dc7451c6254",
		"Bronze crossbow\nDo not expect too much of a bronze crossbow.",
		"Bronze-Armbrust\nVon einer Bronze-Armbrust sollte man nicht zu viel erwarten."
	],
	"weapon crossbow iron": [
		"ae5e80ffe71a4e0e37437f397340835ac445d6bff022e4edc065499a2d9d97b1",
		"Iron crossbow\nLike any other iron item, this crossbow is better than the bronze but worse than the steel.",
		"Eisen-Armbrust\nEisen ist grundsätzlich ein bisschen besser als Bronze, aber schlechter als Stahl."
	],
	"weapon crossbow meteoric": [
		"73479c3f058a898e62eaf710d055ca510afb35ecd7569672b51440c46c11b58c",
		"Meteorite crossbow\nAbout the only way to improve on it is to add an extra spring.",
		"Meteorit-Eisen-Armbrust\nNur mit einer zusätzlichen Feder könnte man diese Armbrust noch besser machen."
	],
	"weapon crossbow mithrill": [
		"8dc5c4fb1193f3b7d0b4164b42116f0c7250f483f18d9db85cd252405e960fe9",
		"Mithrill crossbow\nA strong and long-range weapon. Go for it!",
		"Mithril-Armbrust\nEine durchschlagende Waffe mit hoher Reichweite. Was will man mehr?"
	],
	"weapon crossbow steel": [
		"42242c55add62340ae773cc441edf9d6a8b9df0400c05376eba0c6cd27251ed4",
		"Steel crossbow\nBolts shot from a steel crossbow pierce even very good armor.",
		"Stahl-Armbrust\nAuch Gegner mit sehr guten Rüstungen sollten sich vor dieser Armbrust in Acht nehmen."
	],
	"weapon crystal_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_axe diamond": [
		"a2d8ba819978b1323dee8c6c1a3c10576a390663dd27471adbfcaed5345da07b",
		"Diamond axe\nThe only thing better than a diamond weapon is a diamond weapon infused with magic...",
		"Diamant-Axt\nNur magische Waffen sind besser als Diamant."
	],
	"weapon crystal_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_crossbow diamond": [
		"f732f80227137428d049b27ac749feee3888a536f37d39e282277be121626c27",
		"Diamond crossbow\nThis does not come cheap: but a bolt shot from this crossbow will pierce any kind of armor at all.",
		"Diamant-Armbrust\nQualität hat ihren Preis: Es gibt absolut keine Rüstung, die dieser Armbrust etwas entgegenzusetzen hätte."
	],
	"weapon crystal_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_dagger diamond": [
		"6fc2d0bbbf5e79923d2c0d57cfac7a35d20e73d9ee247f0fd7387cdc63cd774d",
		"Diamond dagger\nA stab with a diamond dagger is as fatal as a lightning strike!",
		"Diamant-Dolch\nEin Stoß mit diesem Dolch in den Rücken des Gegners lässt ihn wie vom Blitz getroffen zu Boden gehen!"
	],
	"weapon crystal_mace": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_mace ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_mace diamond": [
		"a3d6c0128f948481c5c0e11f297e5b0b2c09a20c5a811cd53d22e637b2035479",
		"Diamond mace\nEven meteorite iron will not resist its blows!",
		"Diamant-Streitkolben\nSelbst Meteorit-Eisen kann mit dieser Waffe nicht mithalten!"
	],
	"weapon crystal_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_spear diamond": [
		"4f376a5ecb95520053d3c879d0449cb091b56bb3cf723d221b493e326b3ac208",
		"Diamond spear\nNo armor will resist a diamond spear!",
		"Diamant-Speer\nEs gibt nichts, das stärker ist als ein Diamant-Speer."
	],
	"weapon crystal_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon crystal_sword diamond": [
		"371fdc88666c3d0b1ba3daba7069617cefbb7439315c48bfe54f7d8660bfb4f2",
		"Diamond sword\nA whole crystal sword is as awesome in combat as it is beautiful in your hand.",
		"Diamant-Schwert\nEin Diamantschwert liegt nicht nur gut in der Hand, es ist auch eine ernst zu nehmende Waffe."
	],
	"weapon curved_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon curved_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon curved_dagger adamantium": [
		"3457f03fdc3bbeb5f9031bb1f8b58ede1456275d130b405a81d982107632983b",
		"Adamantine dirk\nSharp enough to slit even a troll's throat!",
		"Adamant-Dirk\nScharf genug, um selbst einem Troll die Kehle durchzuschneiden!"
	],
	"weapon curved_dagger bronze": [
		"eb2acd988552f704cef6703bb440d6ff54ae40a344935131caa49d6c2172de6e",
		"Bronze dirk\nMore reliable than a simple dagger, lighter than a sword. But try for something better...",
		"Bronze-Dirk\nBesser als ein einfacher Dolch, leichter als ein Schwert. Aber das Material könnte wirklich besser sein."
	],
	"weapon curved_dagger iron": [
		"133fb003e7819a7ca715bf314fd297ba1c63d5fea6156b813e8d5abaf6197d68",
		"Iron dirk\nNot the worst possible dirk, but a lot worse than a steel one!",
		"Eisen-Dirk\nNicht schlecht, aber Stahl wäre ein Fortschritt."
	],
	"weapon curved_dagger meteoric": [
		"baa86f8f4072196dc18f23153e4907b711a58a61c91ab8f08c948a22f04197a3",
		"Meteorite dirk\nThe very best! But the price, of course, tends to scare one off...",
		"Meteorit-Eisen-Dirk\nDas Beste! Der Preis ist allerdings auch nicht schlecht."
	],
	"weapon curved_dagger mithrill": [
		"36a9c14acac0ebe35928586c506b7146bb6f248fae1b7f2c60707ab103ac025c",
		"Mithrill dirk\nLight, sharp, finely honed... and expensive.",
		"Mithril-Dirk\nLeicht, stabil, scharf. Dafür aber auch nicht billig..."
	],
	"weapon curved_dagger steel": [
		"2277e743f361ef00c09273af85a7606f42728effe5aaa954967eeeec6107f3b0",
		"Steel dirk\nA serious weapon in the hands of an experienced warrior...",
		"Stahl-Dirk\nIn den Händen eines erfahrenen Kämpfers eine gefährliche Waffe."
	],
	"weapon dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon dagger adamantium": [
		"057487aeba671d0b9968bede137b7fe980e171fd7b30bb69c67b88423d55cfb3",
		"Adamantite dagger\nOne of the best daggers available on this world.",
		"Adamant-Dolch\nEiner der besten Dolche, die es zu kaufen gibt."
	],
	"weapon dagger bronze": [
		"562a7714834c228e0a491655ef5c12b1b97b0b89bb41d0fa8b0072c0bb1c8c11",
		"Bronze dagger\nThe best way to kill with this is to stab your enemy in the back.",
		"Bronze-Dolch\nMit diesem Dolch sollte man sein Opfer nur von hinten angreifen."
	],
	"weapon dagger iron": [
		"c86fd7b2a3c7d719fc8a03cf75a6d26c0f220b0f9da7a4cb98243f6ed74d7cd4",
		"Iron dagger\nModest....both in terms of price and quality.",
		"Eisen-Dolch\nBescheidener Preis, aber auch nur bescheidene Qualität."
	],
	"weapon dagger meteoric": [
		"003d31ec97fa2a69cea39791c22039341b3ffbf32325135b46ee92506f93e9e5",
		"Meteorite dagger\nCauses maximum damage possible. To achieve more, you would need a magician, not a blacksmith.",
		"Meteorit-Eisen-Dolch\nEin Schmied könnte diesen Dolch nicht mehr verbessern. Dafür braucht es schon einen Magier!"
	],
	"weapon dagger mithrill": [
		"ee363a26d8ba74d60bf948a6564083aa708bbb64af6030ae8d38093e96969a2b",
		"Mithrill dagger\nEnough to punish any sentry who dozes off.",
		"Mithril-Dolch\nDamit lässt sich jeder eingenickte Wachposten bestrafen."
	],
	"weapon dagger steel": [
		"3bfa0bc1488f91184b00aa00e5cb87f11b01f61a2ca5a851df82c49730fd8c7d",
		"Steel dagger\nA steel dagger is a worthy weapon! But steel cannot get through all kinds of armor.",
		"Stahl-Dolch\nStahl ist nicht schlecht, kann es aber nicht mit jeder Rüstung aufnehmen."
	],
	"weapon fsword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon fsword steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon hammer": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon hammer ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon hammer adamantium": [
		"d86337644c40de30df1a3fe2cb5de8ec7f14bf9cd9b0a6463e6f0a568d68c1d6",
		"Adamantite battle hammer\nAn exotic weapon. You do not see these often!",
		"Streithammer aus Adamant\nEine exotische Waffe. So etwas sieht man selten!"
	],
	"weapon hammer bronze": [
		"e8786e228a6efb260888d6063405aef22d756ebb10cca91441ad421deaabd124",
		"Bronze battle hammer\nGood enough for training, but try not to use this if you get into serious trouble!",
		"Streithammer aus Bronze\nHöchstens als Übungswaffe zu gebrauchen…"
	],
	"weapon hammer iron": [
		"6a5efb24e174425c65d3cca438b9afba136d75d45ef5510893a9715fbd6a7e47",
		"Iron battle hammer\nIn an \"iron on iron\" fight, this will be good enough.",
		"Streithammer aus Eisen\nWenn der Gegner auch nichts Besseres als Eisen hat, ist dieser Hammer durchaus annehmbar."
	],
	"weapon hammer meteoric": [
		"7782e8dcbbf1d773a48e13b8ffef5d87f3b1b197974d696f6f89e079d232db07",
		"Meteorite battle hammer\nMakes an unforgettable impression on your enemies...",
		"Streithammer aus Meteorit-Eisen\nDieser Hammer hinterlässt einen bleibenden Eindruck beim Gegner!"
	],
	"weapon hammer mithrill": [
		"80dfa25a99ad3595e6f1e4ccd4968e7fc244938bf9bdc7c499ee3f4b0864ba26",
		"Mithrill battle hammer\nOne can find better uses for mithrill than simply smashing heads with it...",
		"Streithammer aus Mithril\nAus Mithril kann man noch bessere Waffen machen."
	],
	"weapon hammer steel": [
		"5724f8eea62fb9323bf405daba0a5cdaac9e1367e90aa6a49f5f71040f896794",
		"Steel battle hammer\nMany would have to take this one seriously!",
		"Streithammer aus Stahl\nMit diesem Hammer wird man von den meisten Gegnern sehr ernst genommen."
	],
	"weapon his_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon his_dagger steel": [
		"a1516aced17af4bf1d93c94f2c0b2b65f608779e9b09ea5898a934c7c8ac3456",
		"His's knife\nAn excellent knife.",
		"His' Messer\nEin ausgezeichnetes Messer."
	],
	"weapon long_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_bow adamantium": [
		"05b1f4aa855bcba2ee3633b0c21d127727ac4e36ace09cdede77523ee29fe85a",
		"Long adamantite bow\nNot every warrior can wear armor capable of withstanding arrows from this bow.",
		"Langbogen aus Adamant\nNicht jeder Krieger ist in der Lage, eine Rüstung zu tragen, die Pfeilen von diesem Bogen widerstehen könnte."
	],
	"weapon long_bow bronze": [
		"c334c755cd4968a8f2c726aa0a64c64b6fe3ab15b3e10313507e97df9fd52e6f",
		"Long bronze bow\nA long bow is better than a short one. But think about obtaining better material....",
		"Langbogen aus Bronze\nLangbögen sind meist besser als Kurzbögen. Aber vielleicht sollte er aus einem anderen Material sein..."
	],
	"weapon long_bow iron": [
		"68c2b96cfcf0108ac1e4e4bbe920a23b62e58b81ac79ccb32c6be968229d37f2",
		"Long iron bow\nNot a bad weapon if you want to shoot somebody in the back.",
		"Langbogen aus Eisen\nEine gute Waffe, wenn man seinem Gegner in den Rücken schießen will."
	],
	"weapon long_bow meteoric": [
		"ed222990434f9f1132e59656fbe137804fd9c5392f3ba9102ca2dfa36f82256c",
		"Long meteorite bow\nWould you like something better still? Forget it, this is the best!",
		"Langbogen aus Meteorit-Eisen\nEtwas Besseres wird man kaum noch finden."
	],
	"weapon long_bow mithrill": [
		"bc410045351f01bc360d2c2e025f066fb3241191df025f24e7ed22b14b3cdcbb",
		"Long mithrill bow\nAn arrow shot from this bow hurts a lot more than the sting of a hornet!",
		"Langbogen aus Mithril\nDie Pfeile von diesem Bogen werden so manch einem das Fürchten lehren."
	],
	"weapon long_bow steel": [
		"3531f4af2f0576a1beac1624b14e82a59b72304e861cdc4e1751507548f376e4",
		"Long steel bow\nAn opponent armed with this one is a worthy enemy.",
		"Langbogen aus Stahl\nJemand mit einem solchen Bogen ist ein würdiger Gegner."
	],
	"weapon long_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_crossbow adamantium": [
		"f0f81794f246400bec0a881835feff6f9478b551fa0e8bb571dc50cb72805660",
		"Heavy adamantite crossbow\nA long-range and powerful weapon - one of the most awesome on this world.",
		"Schwere Armbrust aus Adamant\nEine durchschlagende Waffe mit hoher Reichweite. Man wird nur schwer etwas Besseres finden."
	],
	"weapon long_crossbow bronze": [
		"dad4eac4bda661ea524cf1d40a2a6bb3e738c303207cbe83a7e3fd86ac121787",
		"Heavy bronze crossbow\nAn extra spring is useful even in a bronze crossbow.",
		"Schwere Armbrust aus Bronze\nEine zusätzliche Feder ist selbst bei einer Bronzearmbrust nützlich."
	],
	"weapon long_crossbow iron": [
		"ec1d735012f2c4b5f5ae6006eeffeeba7d9ad7c75cc7a734e94447c5914b5336",
		"Heavy iron crossbow\nNot the most awesome of crossbows... but do not write it off yet.",
		"Schwere Armbrust aus Eisen\nNicht die beste aller Armbrüste, aber auch nicht vollkommen unbrauchbar."
	],
	"weapon long_crossbow meteoric": [
		"7fb9ce8cca6339d35b3327e7be87a73ccbce8315a4d2bdfe3c3cc0eee31c9395",
		"Heavy meteorite crossbow\nAn arrow shot from this one will cut through adamantite armor like a steel needle cuts through paper!",
		"Schwere Armbrust aus Meteorit-Eisen\nEin Bolzen dieser Armbrust durchschlägt auch die beste Adamant-Rüstung."
	],
	"weapon long_crossbow mithrill": [
		"7b5a123cda3f826a2b479c60091d59896261a1f89b4262631590220d84e46f68",
		"Heavy mithrill crossbow\nTough and flexible mithrill is an excellent material for crossbows.",
		"Schwere Armbrust aus Mithril\nMithril ist das ideale Material für Armbrüste."
	],
	"weapon long_crossbow steel": [
		"f6e120f0fe2a2e1fb85aff6eb53cfbf3841c6e24087aabebecf7b2f2dc5d5be3",
		"Heavy steel crossbow\nA good weapon!",
		"Schwere Armbrust aus Stahl\nEine gute Waffe!"
	],
	"weapon long_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_spear adamantium": [
		"c967a271d129cf6ae532aff7a03397bb7074458158ab6a4d0e0a59295dc9f450",
		"Long adamantite spear\nA very good weapon. And costs very good money.",
		"Langspeer aus Adamant\nEine sehr, sehr gute Waffe. Das spiegelt sich auch im Preis wider."
	],
	"weapon long_spear bronze": [
		"405be618fcaa9f3814efa5aa838cff1b27345ef87e99a66b19ba29d955dd773d",
		"Long bronze spear\nBetter than a simple bronze spear, but that is small comfort...",
		"Langspeer aus Bronze\nBesser als ein einfacher Bronzespeer - was aber nicht viel heißen will."
	],
	"weapon long_spear iron": [
		"553bbb4b714583dc055c208c63808c9c25f1500bed97e96567c82dc9b7278dfc",
		"Long iron spear\nNot the best of long spears, but not the most expensive either.",
		"Langspeer aus Eisen\nNicht gerade der beste, aber immerhin ist der Preis vernünftig."
	],
	"weapon long_spear meteoric": [
		"c1fa9c307255d7845c518cc997bf2628ced2814a7e26cabdf7d7225ff43ba4b8",
		"Long meteorite spear\nAbsolutely the best!",
		"Langspeer aus Meteorit-Eisen\nAbsolut herausragend!"
	],
	"weapon long_spear mithrill": [
		"e5323b425739c7b16a25d9afe3bbd44cbd18a8cdf69328c8e3a78679ff2ed828",
		"Long mithrill spear\nThe material and the quality are most impressive; certainly worth the price!",
		"Langspeer aus Mithril\nQualität und Material sind beeindruckend gut. Dieser Speer ist seinen Preis auf jeden Fall wert."
	],
	"weapon long_spear steel": [
		"c7318b2823c3fe97dd4d2c3601bfc358288817edfa0c36d57ebdfa74725591b2",
		"Long steel spear\nThis one would fend many an opponent off...",
		"Langspeer aus Stahl\nDamit kann man seine Gegner durchaus auf Distanz halten."
	],
	"weapon long_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon long_sword adamantium": [
		"6b12c9c3a90871f1d75fd205775558aac85fa60eac8456d2ef4cf38e56c3a337",
		"Adamantite long sword\nEven a less than experienced fighter could win a serious battle with this one!",
		"Langschwert aus Adamant\nSelbst weniger erfahrene Krieger haben mit diesem Schwert einen definitiven Vorteil."
	],
	"weapon long_sword bronze": [
		"948f27e1f96c5b411baad0506abdedc870551b82768d769db6fe33828156026d",
		"Bronze long sword\nA bronze sword is fine if your opponent forgot to get good armor.",
		"Langschwert aus Bronze\nSolange der Gegner keine Rüstung hat, ist sogar ein Bronzeschwert eine annehmbare Waffe."
	],
	"weapon long_sword iron": [
		"27d4ef3f7adfdc60d479fa5cdf25e38efbc52d3f4bb5f9a55d141837ebe5c2fd",
		"Iron long sword\nThis causes more damage than a bronze one, but it cannot pierce many types of armor.",
		"Langschwert aus Eisen\nRichtet mehr Schaden an als ein Bronzeschwert. Es gibt aber Besseres."
	],
	"weapon long_sword meteoric": [
		"f7c456479a771961cc0dea8ba098356d6aa6ca323fd9cae7b1bf5b30314a289e",
		"Meteorite long sword\nNo blacksmith could make a better long sword!",
		"Langschwert aus Meteorit-Eisen\nEin besseres Schwert kann man fast gar nicht herstellen."
	],
	"weapon long_sword mithrill": [
		"721540ada54edd5bf2cdae08845d592d06eac55fe67825b0f6314e61cb43c664",
		"Mithrill long sword\nExpensive, but worth it!",
		"Langschwert aus Mithril\nTeuer, aber seinen Preis wert!"
	],
	"weapon long_sword steel": [
		"52510ec1c0337f334cd25a8b3930964200b14a126405360cc934aeb9bd65ab73",
		"Steel long sword\nA serious weapon in the hands of an experienced fighter...",
		"Langschwert aus Stahl\nIn den Händen eines erfahrenen Kämpfers eine gefährliche Waffe."
	],
	"weapon mace": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon mace ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon mace adamantium": [
		"32af16886c08feb88ae05029c9d72073cffeb50a4391d53eadfcdbcf46c2dea7",
		"Adamantite mace\nWith a heavy item like this in your hand, you can take on anything.",
		"Streitkolben aus Adamant\nMit dieser Waffe kann man sich in jeden Kampf stürzen!"
	],
	"weapon mace bronze": [
		"43714bbfdab2875a5696d3b85e8f0d3453fbeb7c6bf164dbb5133d10df6f67d9",
		"Mace · Bronze\nInexpensive but impressive. At least in terms of appearance.",
		"Streitkolben · Bronze\nNicht sehr teuer, sieht aber immerhin eindrucksvoll aus."
	],
	"weapon mace iron": [
		"97477cecfba0c906fda782ca1f637b7f2c267a7ac5a04b4f0ca4f9e8e7cb5e98",
		"Iron mace\nNot as nice looking as a bronze one, but it will cause greater damage.",
		"Streitkolben aus Eisen\nSieht nicht so gut aus wie Bronze, richtet aber wesentlich mehr Schaden an."
	],
	"weapon mace meteoric": [
		"b84aaa6df654f5dee32146f0ff1f3de0c259b9d88084dc9bc618aee2ff72c68c",
		"Meteorite mace\nThe only thing better than a meteorite mace is a spiked meteorite mace.",
		"Streitkolben aus Meteorit-Eisen\nNur ein Streitkolben mit Dornen aus Meteorit-Eisen ist noch besser."
	],
	"weapon mace mithrill": [
		"174c3ff50271c3dfaf5b1eb9fb437d2e22a3d920633a6d25d8b07575262cd59e",
		"Mithrill mace\nA most serious weapon. And not cheap either.",
		"Streitkolben aus Mithril\nEine gute Waffe - und nicht gerade billig."
	],
	"weapon mace steel": [
		"e7017f649db901844c9c00cb5d212694432091052cf2aa87b36ca958904e7a01",
		"Steel mace\nThe heaviness of the steel makes the blows extra powerful!",
		"Streitkolben aus Stahl\nDurch das hohe Gewicht von Stahl ist dieser Streitkolben besonders wirkungsvoll."
	],
	"weapon new_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon new_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon new_bow diamond": [
		"fe17b5f432b909f1aae0f01506d9a05977086c658ae0eb429e128036120a5bfc",
		"Crystal bow · Diamond\nAn arrow from this bow can pierce any chain mail clean through.",
		"Kristallbogen · Diamant\nEin Pfeil aus diesem Bogen kann jedes Kettenhemd glatt durchschlagen."
	],
	"weapon saber": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon saber ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon saber adamantium": [
		"ba4e149a3d2f100dd5c041eaf2faac4ec8a1050bc1af4041fe9abddfecf35e82",
		"Adamantite sabre\nYou could win a serious fight with this one!",
		"Säbel aus Adamant\nDamit gewinnt man jeden Kampf!"
	],
	"weapon saber bronze": [
		"86e37f2985b1a0d4bf6666fdf25506f1f9bb460d047e78f51271431a01094aca",
		"Bronze sabre\nDo not rely too much on a bronze blade, although it is a little better than stone.",
		"Säbel aus Bronze\nAllzu verlässlich sind Bronzewaffen nicht, aber immer noch besser als Stein."
	],
	"weapon saber iron": [
		"282d9d484156776aacb81d5c2d3cbb457f11a265167a9f55514d51b55321be7f",
		"Iron sabre\nNot bad, but nothing special.",
		"Säbel aus Eisen\nNicht wirklich schlecht, aber auch nichts Besonderes."
	],
	"weapon saber meteoric": [
		"44b953e68229122c3c9f5f833673a61cd3ac7cf398ef8ae13e050744315620dd",
		"Meteorite sabre\nThis blade will ensure at least a half victory.",
		"Säbel aus Meteorit-Eisen\nDiese Waffe ist schon der halbe Sieg!"
	],
	"weapon saber mithrill": [
		"8107ff0317d0c7408edf51703c321864a1e3a64c762910a3a9113eba09648e4d",
		"Mithrill sabre\nThis one is definitely not for beginners!",
		"Säbel aus Mithril\nKeine Waffe für Anfänger!"
	],
	"weapon saber steel": [
		"be1063f15a2596dd33729040f9d11b56a9e1ac5db99c657a038b0c760ad43d70",
		"Steel sabre\nA serious weapon in the hands of an experienced fighter... but it will not pierce every kind of armor!",
		"Säbel aus Stahl\nDieser Säbel ist eine gefährliche Waffe. Allerdings kann er es nicht unbedingt mit jeder Rüstung aufnehmen."
	],
	"weapon serp": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon serp steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon short_bow adamantium": [
		"6ff4af42a0a4fcf98d47f67ad7e0104a64d16f2d9e08b75340978aa217ca09a0",
		"Short adamantite bow\nThe springy adamantite makes this short bow an awesome weapon!",
		"Kurzbogen aus Adamant\nAuch für Bögen ist Adamant ein hervorragendes Material."
	],
	"weapon short_bow bronze": [
		"7fbd82c44d030c48416da6ca246d75089960f425c09f8880e5883055f73a061c",
		"Short bronze bow\nMetal gives bows additional properties - but bronze is not the most flexible of metals...",
		"Kurzbogen aus Bronze\nBronze ist für einen Kurzbogen denkbar ungeeignet."
	],
	"weapon short_bow iron": [
		"ff7ee5cd9312e094779d4a90a00dd7f79134c78f49d94f203e297e8816a154c4",
		"Short iron bow\nWave away an arrow shot from this bow, if you can!",
		"Kurzbogen aus Eisen\nVor diesem Bogen sollte der Gegner sich besser in Acht nehmen."
	],
	"weapon short_bow meteoric": [
		"fb8b3fb1684f42902fbc12b23e55778196c6d46a2620de0d3e1470b93c9ce5d7",
		"Short meteorite bow\nIf you see that your enemy has this bow, make a will.",
		"Kurzbogen aus Meteorit-Eisen\nWenn der Gegner einen solchen Bogen hat, sollte man lieber fliehen als kämpfen."
	],
	"weapon short_bow mithrill": [
		"367af7acd1c51338f406159d8a67259b76b8ca33c11bb5c483c3f2ab0f3ffcba",
		"Short mithrill bow\nEven a very well-protected opponent will have to take the owner of this one seriously.",
		"Kurzbogen aus Mithril\nAuch Gegner mit einer guten Rüstung werden einen mit diesem Bogen ausgerüsteten Schützen ernst nehmen."
	],
	"weapon short_bow steel": [
		"90df4a5c6614f7da8dcfb8b9181b636b25e9527b376340e74680ac394dd76970",
		"Short steel bow\nSteel makes arrows quicker and more precise.",
		"Kurzbogen aus Stahl\nStahlbögen sind sehr durchschlagskräftig und präzise!"
	],
	"weapon spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spear adamantium": [
		"29015a1d1f8642064c7476ba520e92faf06edbc1d67610e98bb9a72fea9f40fd",
		"Adamantite spear\nA very good weapon. And costs very good money.",
		"Speer aus Adamant\nEine sehr, sehr gute Waffe. Das spiegelt sich auch im Preis wider."
	],
	"weapon spear bronze": [
		"0adbc6f9b9f82243f9b00160b1005b4ec269992266630d278e4eca405c70dc22",
		"Bronze spear\nThe simplest metal spear. Not the worst weapon...",
		"Speer aus Bronze\nDer einfachste aller Metallspeere. Na ja..."
	],
	"weapon spear iron": [
		"5c0c1109356d3cdd572539dc273e1ebf02f7772718b3848eddbc2cd551600d22",
		"Iron spear\nNot the best weapon, but not the most expensive either.",
		"Speer aus Eisen\nNicht gerade der beste Speer, aber dafür auch nicht sehr teuer."
	],
	"weapon spear meteoric": [
		"d1e0a2d39880ec4082aeaabfad054a5b23421d0d9b5b3446bee8385a30e3bcb0",
		"Meteorite spear\nOnly meteorite armor could withstand this....and that's a big maybe...",
		"Speer aus Meteorit-Eisen\nNur eine Rüstung aus Meteorit-Eisen könnte diesen Speer vielleicht aufhalten."
	],
	"weapon spear mithrill": [
		"ae56b3483e0b990b25613ccbe65092a916e0e4fe005b21dc48e99a546c6dfb6f",
		"Mithrill spear\nThe material speaks for itself.",
		"Speer aus Mithril\nDas verwendete Material sagt eigentlich schon alles."
	],
	"weapon spear steel": [
		"bb25e7b41030df9dbdf1002d67f924365c405beb4755db1aecb0f294231f25ee",
		"Steel spear\nNow this is something efficient, and not too expensive.",
		"Speer aus Stahl\nEffizient und nicht zu teuer!"
	],
	"weapon spiked_club": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spiked_club ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spiked_club adamantium": [
		"3dc54f89b9d9978adc99a8a67c86ee1b33847214ad20ab0cfaf97fa66265e8bd",
		"Adamantite heavy spiked mace\nThis is capable of breaking any skull!",
		"Schwerer Streitkolben mit Dornen aus Adamant\nUnter diesem Streitkolben bricht absolut alles!"
	],
	"weapon spiked_club bronze": [
		"6a83418fa987d21b1be24225a317d5371e824e2cb62b1d676e8d327b8a53b424",
		"Heavy bronze spiked mace\nYou can't make a good spiked mace out of bronze...",
		"Schwerer Streitkolben mit Dornen aus Bronze\nBronze ist für einen solchen Streitkolben denkbar ungeeignet."
	],
	"weapon spiked_club iron": [
		"d5ad33bffc53dac6eab7c3010ea0abd0c6aaeb7b7a5dccc6fcbaaae3a89a4470",
		"Heavy iron spiked mace\nOf course iron is better than bronze but poorer than all the other metals...",
		"Schwerer Streitkolben mit Dornen aus Eisen\nEisen ist besser als Bronze, aber auch nicht viel besser."
	],
	"weapon spiked_club meteoric": [
		"1996468d5902eca9a5c83d2eb2e14c7f140564745cb9dcb862c2cbfa58b997d2",
		"Meteorite heavy spiked mace\nThe blacksmiths did all they could. Now it is the turn of the magicians.",
		"Schwerer Streitkolben mit Dornen aus Meteorit-Eisen\nFür den Schmied gibt es keine Möglichkeit, diese Waffe zu verbessern. Das schafft nur noch ein Magier!"
	],
	"weapon spiked_club mithrill": [
		"21e7988dc03dc6f93ae4820a5bbb8a1d7548eed6d97da334031fac4ca84982ac",
		"Mithrill heavy spiked mace\nWith an argument like this in your hands, you are well-placed to claim the right to go first...",
		"Schwerer Streitkolben mit Dornen aus Mithril\nMit dieser Waffe kann man sich jederzeit Respekt verschaffen."
	],
	"weapon spiked_club steel": [
		"2b153c76663718374c4f92c8b6dd979e06e501637811f1a1912db26186a70d46",
		"Steel heavy spiked mace\nA good weapon for one about to embark on a dangerous voyage.",
		"Schwerer Streitkolben mit Dornen aus Stahl\nEin guter Begleiter für gefährliche Reisen."
	],
	"weapon spiked_mace": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spiked_mace ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon spiked_mace adamantium": [
		"554a23f90fcb0ef099aa0cbd1c60356ccc2547d484288d11fc9bee00a8e84578",
		"Adamantite spiked mace\nGood things do not come cheap.",
		"Streitkolben mit Dornen aus Adamant\nGute Waffen haben ihren Preis."
	],
	"weapon spiked_mace bronze": [
		"c0657c2c2d37203add69acbcf4755432c2e09d30d13f4f4d1b64af02fd4db2dc",
		"Spiked mace · Bronze\nGood for splitting coconuts.",
		"Streitkolben mit Stacheln · Bronze\nGut zum Spalten von Kokosnüssen."
	],
	"weapon spiked_mace iron": [
		"2cdbd027075f627a5bb6d9ef202cc3eefe66367499c063fc6b785196b8e44331",
		"Heavy iron mace\nIron is not the best material for spikes, but this mace is heavier than a regular one.",
		"Schwerer Streitkolben aus Eisen\nEisen mag nicht gut sein für Dornen. Aber um Dinge schwer zu machen ist es ideal."
	],
	"weapon spiked_mace meteoric": [
		"088edce6cda0445a890782ab6e4ef7f701b07b2de2b7c97e6bcfe55dc4798c65",
		"Meteorite spiked mace\nAfter a blow from this mace, enemy armour is only fit to serve as a sieve...",
		"Streitkolben mit Dornen aus Meteorit-Eisen\nNach einem Schlag mit diesem Streitkolben taugt die feindliche Rüstung nur noch als Sieb ..."
	],
	"weapon spiked_mace mithrill": [
		"c943a8be46a1da9c0527021f2344bd5da562e3e4fe040c95431b683bc5b13a38",
		"Mithrill spiked mace\nEven steel armor will not resist mithrill spikes.",
		"Streitkolben mit Dornen aus Mithril\nSelbst eine Stahlrüstung gibt diesen Dornen nach!"
	],
	"weapon spiked_mace steel": [
		"0ea6b598d67d324abf76084f79f2dfa95ca75dee4d570587eb0811593a385f5b",
		"Heavy steel mace\nSteel doesn't make good spikes, but a mace is a formidable weapon anyway.",
		"Schwerer Streitkolben aus Stahl\nEine anständige und solide Waffe!"
	],
	"weapon stone_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_axe granite": [
		"9eeafeeae591be26a9a3e16ec8ccfdcc2053a3753d3fd8e0b1dd69521036d364",
		"Granite axe\nBetter than stone - you could even cut some wood... with difficulty.",
		"Granit-Axt\nBesser als einfacher Stein - man kann damit vielleicht sogar Holz hacken."
	],
	"weapon stone_axe malachite": [
		"63cf37adcfd839ba9669076c77afff34173ac3a22163e036bff9e17001dbf25f",
		"Obsidian axe\nYou might even cut yourself with this axe!",
		"Obsidian-Axt\nDiese Axt stellt durchaus eine brauchbare Waffe dar."
	],
	"weapon stone_axe rock": [
		"31fd9bbbd2d81be2567a33d6427b5d74c701aaf8cd73928dff1595edd9421dc0",
		"Stone axe\nThe simplest of axes. More of a club than an axe, really...",
		"Steinaxt\nEigentlich mehr ein Knüppel als eine ernst zu nehmende Axt."
	],
	"weapon stone_axe silicon": [
		"7b906c1bdcb091b506bf2f20fafcaecf9c8a3fd05de329ce8ccc21b212f97b36",
		"Silicon axe\nSilicon is a step forward - at least you can cut with it.",
		"Silizium-Axt\nSilizium eignet sich durchaus für eine Schneide."
	],
	"weapon stone_battle_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_axe granite": [
		"406ab7e9f2f8e34594f6e8847e3e7fb64b3d311a75dd7d25614cefb911e982b7",
		"Granite battle axe\nMore formidable than a stone battle axe, but sadly not by much.",
		"Streitaxt aus Granit\nGefährlicher als eine steinerne Streitaxt, aber leider nicht viel."
	],
	"weapon stone_battle_axe malachite": [
		"47ed3149d5d6a65980f39e4b13b884679756d0380901c6bd31712b5dcc8b91fb",
		"Obsidian battle axe\nThis axe will make your opponent respect you.",
		"Streitaxt aus Obsidian\nMit dieser Streitaxt verschafft man sich Respekt bei seinen Gegnern."
	],
	"weapon stone_battle_axe rock": [
		"dd66737ddbf57bb7cc51f8c53ef41c6b0af82f14436ae2536f0cb3b1d7541a0b",
		"Stone battle axe\nThis is not just a stone tied to a stick, but not far off it....",
		"Steinstreitaxt\nBesser als ein an einen Stock gebundener Stein, aber immer noch keine ernst zu nehmende Waffe."
	],
	"weapon stone_battle_axe silicon": [
		"b03ca93073de79febc89d22f928422305af41c5e09bdf5d579cbb4d4cd74d36c",
		"Silicon battle axe\nNow you can really rely on this one (provided your opponent is not too strong).",
		"Streitaxt aus Silizium\nAuf diese Waffe kann man sich bei nicht allzu starken Gegnern verlassen."
	],
	"weapon stone_battle_hammer": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_hammer ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_hammer granite": [
		"2cef777ba14c08d34c50868e434b48fff514b7b39a8bc73ed002097ee2e78f6d",
		"Heavy granite hammer\nLooks a bit better and is a little bit more efficient than a stone one - and only a little bit.....",
		"Schwerer Streithammer aus Granit\nEtwas besser als einfacher Stein. Aber das ist auch schon alles!"
	],
	"weapon stone_battle_hammer malachite": [
		"868ab32826fb6868485e39899105b42e001c84cfa7f492fce3c7673368d41861",
		"Heavy obsidian hammer\nThis is a heavy one! Only metal hammers are better.",
		"Schwerer Streithammer aus Obsidian\nNur Hämmer aus Metall sind besser."
	],
	"weapon stone_battle_hammer rock": [
		"963376c6ce8ba1e997b3bba43732264fd5548f91e67e8b595d6612506e5e6cdb",
		"Heavy stone hammer\nThe heavier the stone, the greater the damage...",
		"Schwerer Steinhammer\nJe schwerer der Stein, desto besser die Wirkung."
	],
	"weapon stone_battle_hammer silicon": [
		"f3ee75f50151952f6818410f11aee2fc564296968cae85e3e1dcf77641120a35",
		"Heavy silicon hammer\nThe sharp silicon edges cause additional damage to the enemy.",
		"Schwerer Streithammer aus Silizium\nDie scharfen Kanten sorgen für zusätzlichen Schaden."
	],
	"weapon stone_battle_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_battle_sword granite": [
		"374897b156a59d4ff44d167349c2373f7a375de86b0aa1c359abcf472e860566",
		"Stone battle sword · Granite\nThis weapon is effective against goblins.",
		"Steinkampfschwert · Granit\nMit dieser Waffe kann man erfolgreich gegen Goblins kämpfen."
	],
	"weapon stone_battle_sword malachite": [
		"523b59d0725690a77cc97098a6f948e48163d286c9c0e87287fb99f6c3030d7d",
		"Stone battle sword · Obsidian\nThe best sword on Gipath.",
		"Steinkampfschwert · Obsidian\nDas beste Schwert auf Gipath."
	],
	"weapon stone_battle_sword rock": [
		"0a0262697c8e4663d7307085b6ef953dac39cd8426a45bece68515591ad1877e",
		"Stone battle sword · Stone\nBetter than an ordinary sword, but the material is poorly chosen.",
		"Steinkampfschwert · Stein\nBesser als ein gewöhnliches Schwert, doch das Material ist schlecht gewählt."
	],
	"weapon stone_battle_sword silicon": [
		"b642fc77c63700895cc77c81f5d2964ae310fa3c610f8b91fe114b8212b7a74d",
		"Stone battle sword · Silicon\nA decent weapon at a matching price.",
		"Steinkampfschwert · Silizium\nEine ordentliche Waffe zu einem passenden Preis."
	],
	"weapon stone_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_dagger granite": [
		"4e7253810b5a3141de7f43a9267577582a247f75914eb4a5c752cb28f39afdea",
		"Granite dagger\nCould be useful at the start, but do not rely on it too much.",
		"Granit-Dolch\nAm Anfang vielleicht ganz nützlich, aber man sollte sich nicht zu sehr auf diesen Dolch verlassen."
	],
	"weapon stone_dagger malachite": [
		"c352aaecb92c0a416c327d139d8488b6c940fbfb2269d75b7456094ddee2d1b4",
		"Obsidian dagger\nA good piercing weapon - the best of stone daggers.",
		"Obsidian-Dolch\nDer beste Dolch, den man aus Stein herstellen kann."
	],
	"weapon stone_dagger rock": [
		"385a9bdeefcd4bd4c3f0bee73e6866cef1ac9cfaf78b340a89ace01ec90ec75a",
		"Stone dagger\nAlmost worthless, both in terms of price and efficiency.",
		"Steindolch\nPraktisch wertlos. In absolut jeder Hinsicht."
	],
	"weapon stone_dagger silicon": [
		"e06ac9607941b177884df4c10a96048c54126b3e91b210ffd193380ca29784a7",
		"Silicon dagger\nNot a bad piercing weapon - efficient and not too expensive.",
		"Silizium-Dolch\nKeine schlechte Stichwaffe! Effizient und nicht zu teuer."
	],
	"weapon stone_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_short_bow granite": [
		"2b84c4fe25d82f9a9e3778f734cfe5dbe0ad45389ca41f951aece470e5b2c467",
		"Bow (granite head arrows)\nThe shortcomings are many, but it is still better than nothing.",
		"Bogen (Pfeilspitzen aus Granit)\nDieser Bogen hat viele Nachteile, aber er ist immer noch besser als nichts."
	],
	"weapon stone_short_bow malachite": [
		"89be683aa97d6db459ea7e47909e2c18042a94eaa8aa0e6b51f9ac7dcdb1c256",
		"Bow (obsidian head arrows)\nCauses the maximum damage possible with this kind of weapon.",
		"Bogen (Pfeilspitzen aus Obsidian)\nDer beste aller Steinbögen!"
	],
	"weapon stone_short_bow rock": [
		"5cb9b9d4ce39d2824f184d270803d65b69b2139cfd3f12b07ab3bf0cea9becce",
		"Bow (stone head arrows)\nYour chances of hitting the target are not great, but this bow can still shoot arrows.",
		"Bogen (Steinpfeilspitzen)\nDieser Bogen verschießt Pfeile, aber ob man das Ziel auch trifft, ist eine andere Frage."
	],
	"weapon stone_short_bow silicon": [
		"4b860315ef3de369b2b24cbbe092f0763230d674772510f260e6ad1e4930f8ec",
		"Bow (silicon head arrows)\nNow you can risk going beyond the gates, and maybe you will even get back!",
		"Bogen (Pfeilspitzen aus Silizium)\nMit diesem Bogen kann man sich auch in die Wildnis wagen!"
	],
	"weapon stone_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_spear granite": [
		"ef6412c76d3f19511d70a98390d8e7a37d6b69478a900b1a8693aa7832420e17",
		"Granite head spear\nGranite is better than stone ... but worse than any other material.",
		"Speer mit Granitspitze\nGranit ist besser als einfacher Stein - aber mehr auch nicht!"
	],
	"weapon stone_spear malachite": [
		"1bf2c0ca2f25ed0bb64e26c6d3b62c3fbf9b436e2a69c4d2c6074c670c6acce3",
		"Obsidian head spear\nNow this does look like a real spear...",
		"Speer mit Obsidianspitze\nDen kann man schon als echten Speer bezeichnen."
	],
	"weapon stone_spear rock": [
		"03ff2ac9f85169ca1dce5c62ce9f822b8f71b81db5ddcc3f80b4e9fc78b4b110",
		"Stone head spear\nThe cheapest, most simple spear.",
		"Speer mit Steinspitze\nDer einfachste aller Speere!"
	],
	"weapon stone_spear silicon": [
		"097a9c97d66e9462b36c948b948fe6a82269253d4311105cf39b4afaeed71087",
		"Silicon head spear\nSilicon heads are much sharper than other stone ones...",
		"Speer mit Siliziumspitze\nSiliziumspitzen sind schärfer als andere Steinspitzen."
	],
	"weapon stone_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon stone_sword granite": [
		"e5cef472653b0fbdb9ed005d9b50e644803d5a2b65908c7fc683b98a644e2620",
		"Granite sword\nBetter than a stone sword, but not by much.",
		"Granit-Schwert\nBesser als ein Steinschwert, aber nicht viel."
	],
	"weapon stone_sword malachite": [
		"df6a5e55983bb168203d8200a2cec8a89abc67183d2d13f65eea2a117e8295f1",
		"Obsidian sword\nOnly metal swords are better than those made of obsidian.",
		"Obsidian-Schwert\nNur Schwerter aus Metall sind besser."
	],
	"weapon stone_sword rock": [
		"0bbb99e14ed005cbd391af8abea129a6c54accd594709cc1ef940900f987c04a",
		"Stone sword\nYou should try to trade it for something more serious.",
		"Steinschwert\nEs gibt deutlich bessere Waffen."
	],
	"weapon stone_sword silicon": [
		"61a8315d0ec137e5a09189641cdf2c7b1c8de928443389808f60543dbc0142bd",
		"Silicon sword\nYou can definitely do some damage with this sword.",
		"Silizium-Schwert\nDamit kann man wenigstens kämpfen!"
	],
	"weapon thief_axe": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe bronze": [
		"736a2952fc0e9ae4da2355e12269fbee02d297e1d722aabe54ba59775f55903b",
		"Scoundrel's axe\nA good axe to learn with, but not the best choice in battle.",
		"Schurkenaxt\nEine gute Axt zum Üben, aber nicht die beste Wahl im Kampf."
	],
	"weapon thief_axe iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_axe steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow bronze": [
		"6a9b5f2623ce11dd68fa6dfea9ffbf21336238c2a0e09e7042ca00c6e2c86ee6",
		"Thief's crossbow\nStrong enough to put a bolt through a troll's forehead.",
		"Diebesarmbrust\nStark genug, um einem Troll einen Bolzen in die Stirn zu schießen."
	],
	"weapon thief_crossbow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_crossbow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger bronze": [
		"e9c6ee8c2b2cbad27536490070f0f68cc0a9bc6c46bc3e154a562ee24eb672bd",
		"Thief's dagger\nIf money is tight, you will find no better knife.",
		"Diebesdolch\nBei knappem Geld findet man kein besseres Messer."
	],
	"weapon thief_dagger iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_dagger steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow bronze": [
		"3a1661871a89bce2f5869566ff1b5de856a21e505b35180511e1775951206560",
		"Thief's bow\nThe most experienced hunters use thieves' bows.",
		"Diebesbogen\nDie erfahrensten Jäger verwenden Diebesbögen."
	],
	"weapon thief_short_bow iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_short_bow steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear bronze": [
		"15ccaea1274b47ba46058e37ddcf324dca1fe350c5e7e9ff1ad0855a934975c1",
		"Thief's pike\nIt does little damage, but at least it does not hinder movement.",
		"Diebespike\nVerursacht wenig Schaden, behindert dafür aber nicht beim Gehen."
	],
	"weapon thief_spear iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_spear steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword bronze": [
		"0209271a0ce6c6eb22cf5c4b7a6bbac872e904aecdbe7c2bd204255c304558d0",
		"Thief's sword\nThis sword can teach a young ogre to be more selective about its meals.",
		"Diebesschwert\nMit diesem Schwert kann man einem jungen Oger beibringen, bei seinen Mahlzeiten wählerischer zu sein."
	],
	"weapon thief_sword iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon thief_sword steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_spear mithrill": [
		"2847a933bca7bc2bcfb594bae4dac2191fa2f4f806f6aca375572ce9b1654a88",
		"\"Lethal Lightning\" spear\nA unique weapon. Brother Blacksmith is not up to making anything comparable.",
		"Speer der tödlichen Blitze\nEine einzigartige Waffe. Bruder Schmied könnte nichts Vergleichbares herstellen!"
	],
	"weapon unique_spear steel": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword ": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword adamantium": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword bronze": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword iron": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword meteoric": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword mithrill": [
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"",
		""
	],
	"weapon unique_sword steel": [
		"b96831467496ed2a743e08b1ac1030cad97ab6f0337f60b81b92d2c9bed6abde",
		"Ancient sword\nThis sword is too old to disassemble, but its steel is still sharp.",
		"Antikes Schwert\nDieses Schwert ist zu alt zum Zerlegen, doch sein Stahl ist noch scharf."
	]
}
