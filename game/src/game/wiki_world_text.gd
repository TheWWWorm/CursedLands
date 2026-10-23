class_name WikiWorldText
extends RefCounted
## Translations of original LiA reference text, used only when the installed
## text exactly matches the source. Localized archives and edited mod text win.
## Quest reference pages show the journal summary and objective titles.

static func text(key: String) -> String:
	var original := GameData.text(key)
	if GameData.campaign_id == CampaignProfile.ORIGINAL: return WikiQuestText.text(key, original)
	if GameData.campaign_id != CampaignProfile.ASTRAL or not TEXTS.has(key): return original
	var record: Dictionary = TEXTS[key]
	return String(record.get(RemakeText.lang, original)) if original == record.ru else original

const TEXTS := {
	"zone bz12g": {
		"en": "The healer's cave",
		"ru": "Пещера знахарки\n\n",
		"de": "Höhle der Heilerin"
	},
	"zone bz13g": {
		"en": "The Dragon's dwelling",
		"ru": "Жилище Дракона\n\n",
		"de": "Behausung des Drachen"
	},
	"zone bz14g": {
		"en": "The Great Mage's dungeon",
		"ru": "Подземелье Великого Мага\n\n",
		"de": "Verlies des Großen Magiers"
	},
	"zone bz21k": {
		"en": "City of Ingos",
		"ru": "Город Ингос\n\n",
		"de": "Stadt Ingos"
	},
	"zone bz23k": {
		"en": "The Green Clan's new home",
		"ru": "Новое жилище Зеленого клана\n\n",
		"de": "Neue Heimat des Grünen Clans"
	},
	"zone bz3h": {
		"en": "Last Shelter",
		"ru": "Последнее Укрытие\n\n",
		"de": "Letzte Zuflucht"
	},
	"zone gz11g": {
		"en": "Distant Mountains\nThe remotest region from the village. Few people venture here, and fewer return. Rumour says the master has found a way to reach a stone deposit in these mountains.",
		"ru": "Дальние Горы\nСамая дальняя от Поселка местность. Люди редко заходят сюда и еще реже возвращаются. Однако в Поселке ходят слухи, что мастер научился каким-то образом добираться до месторождения камня, которое находится там.\n",
		"de": "Ferne Berge\nDieses Gebiet liegt am weitesten vom Dorf entfernt. Nur wenige Menschen wagen sich hierher, und noch weniger kehren zurück. Gerüchten zufolge hat der Meister einen Weg zu einem hiesigen Steinvorkommen gefunden."
	},
	"zone gz12g": {
		"en": "Cave\nThis vast underground cavern has several exits to the surface. Even the hardy orcs have explored only part of it and avoid the depths, where creatures unknown above ground dwell.",
		"ru": "Пещера\nПодземелье больших размеров, имеющее несколько выходов на поверхность. Даже суровые орки освоили только часть пещеры и не рискуют заходить в глубины, где живут твари, не встречающиеся на поверхности.\n",
		"de": "Höhle\nDiese große unterirdische Höhle besitzt mehrere Ausgänge. Selbst die zähen Orks haben nur einen Teil erkundet. In die Tiefe wagen sie sich nicht, denn dort leben Wesen, die an der Oberfläche unbekannt sind."
	},
	"zone gz13g": {
		"en": "Road to the healer\nThe healer Estera quarrelled with the whole village and moved into a secluded cave. She protects the road with magical traps and the trolls that live nearby.",
		"ru": "Дорога к знахарке\nЗнахарка Эстера рассорилась со всем Поселком и переселилась в пещеру, подальше от людей. Чтобы ей не докучали любопытные, она установила на дороге к своему жилищу несколько магических ловушек. Также для охраны дороги к своему жилищу она использует обитающих в округе троллей.\n",
		"de": "Weg zur Heilerin\nDie Heilerin Estera zerstritt sich mit dem ganzen Dorf und zog in eine abgelegene Höhle. Magische Fallen und die dort lebenden Trolle bewachen den Weg zu ihr."
	},
	"zone gz2h": {
		"en": "Suslanger and its surroundings\nThe city stands beside a lake feeding irrigation canals. The people working its fields are unarmed, but must raise the alarm at the sight of strangers or face punishment themselves.",
		"ru": "Город Суслангер и его окрестности\nГород, давший название всей земле вокруг него, расположен на берегу озера, от которого тянутся оросительные каналы. Люди, работающие на полях, не вооружены, но готовы поднять тревогу при виде чужаков, иначе им самим грозит кара.\n",
		"de": "Suslanger und Umgebung\nDie Stadt liegt an einem See, der die Bewässerungskanäle speist. Die Feldarbeiter sind unbewaffnet, müssen aber beim Anblick Fremder Alarm schlagen, sonst droht ihnen selbst Strafe."
	},
	"zone gz3h": {
		"en": "Necromancers' desert\nThe necromancers built their homes and laboratories in the desert, far from prying eyes. Guard barracks protect these sites.",
		"ru": "Пустыня некромантов\nЖилища и лаборатории некромантов расположены в пустыне, подальше от лишних глаз. Здесь же находятся казармы стражи, которая осуществляет охрану этих объектов.\n",
		"de": "Wüste der Nekromanten\nDie Nekromanten errichteten ihre Wohnstätten und Labore in der Wüste, fern von neugierigen Blicken. Wachkasernen sichern diese Anlagen."
	},
	"zone gz5h": {
		"en": "Canyon of Death\nHadagan's army trains here. Soldiers seeking promotion hunt prisoners kept in a separate dungeon.",
		"ru": "Каньон Смерти\nЗдесь расположен тренировочный лагерь хадаганской армии. Воины, желающие получить повышение в чине, ведут охоту на пленников, которых содержат в отдельной темнице.\n",
		"de": "Schlucht des Todes\nHier liegt ein Ausbildungslager der hadaganischen Armee. Soldaten, die aufsteigen wollen, machen Jagd auf Gefangene aus einem eigenen Verlies."
	},
	"zone gz8g": {
		"en": "Sands\nA sandy desert stretches east from the Great Lake, bounded by mountains to the north. Several orc tribes live here, along with the main lizardman settlements. Both peoples constantly compete for water.",
		"ru": "Пески\nК востоку от Большого Озера тянется песчаная пустыня, которую с севера ограничивает гористая местность. На этих землях живут несколько племен орков, и здесь же находится главное место обитания ящеров. Орки и ящеры постоянно соперничают друг с другом из-за доступа к воде.\n",
		"de": "Sandland\nÖstlich des Großen Sees erstreckt sich eine Sandwüste, im Norden von Bergen begrenzt. Hier leben mehrere Orkstämme und die größten Siedlungen der Echsenmenschen. Beide Völker streiten ständig um Wasser."
	},
	"allod gipat2": {
		"en": "Gipath",
		"ru": "Гипат\nГипат — заброшенная земля, не принадлежащая ни одному из государств. Большая часть территории — дикие земли. Из разумных существ встречаются в основном гоблины, орки и ящеры, хотя есть и два небольших поселения людей в самой западной части аллода. Почти по всему Гипату разбросаны развалины зданий, возведеннных древней почти исчезнувшей расой джунов. По слухам именно этот аллод стал местом падения метеорита, на поиски которого была отправлена хадаганская экспедиция...\n",
		"de": "Gipath"
	},
	"allod ingos": {
		"en": "Ingos",
		"ru": "Ингос\nИнгос принадлежит Империи Кании, однако его население малочисленно, и поэтому здесь до сих пор обитают племена других рас — лесовиков и червелицых. Формально  аллодом управляет губернатор, назначенный в столице, но фактически его власть имеет силу только в пределах городской стены. Привыкшие рассчитывать только на себя жители Ингоса в ответ на стук в ворота вначале спускают собак, а потом спрашивают: «Кто там?».\n",
		"de": "Ingos"
	},
	"allod jigran": {
		"en": "Jigran",
		"ru": "Джигран\nДжигран — мир вечной осени, арена противостояния двух последних великих империй — Хадагана и Кании. На этой земле царит увядание и смерть — результат чудовищных по своей мощи заклятий безумного некроманта Фиреза. Из некогда цветущей земли злое чародейство вытянуло почти все силы: поля не родят, леса умирают, почти исчезло зверье. Население аллода в основном сосредоточено в укрепленных городах, в то время как пространство за пределами стен отдано на откуп различным тварям и нежити, которую можно встретить чаще, чем живые существа. Это закрытый мир, затерянный во времени и пространстве.",
		"de": "Jigran"
	},
	"allod suslanger": {
		"en": "Suslanger",
		"ru": "Суслангер\nСуслангер принадлежит Империи Хадаган. Размеры Суслангера невелики, а земли, пригодной для жизни и земледелия, совсем мало. Чтобы хоть как-то расширить обрабатываемые земли, людям приходится строить оросительные каналы и плотины. Власть в Хадагане сурова, безжалостна и насквозь коррумпирована. Стража и шпионы не в состоянии уследить за размножающимися преступными группировками, а шантаж и контрабанда уже воспринимаются в порядке вещей.\n",
		"de": "Suslanger"
	},
	"zone bz11g": {
		"en": "Free hunters",
		"ru": "Вольные охотники\n\n",
		"de": "Freie Jäger"
	},
	"zone bz1h": {
		"en": "Slave pen",
		"ru": "Загон с рабами\n\n",
		"de": "Sklavenpferch"
	},
	"zone bz1r": {
		"en": "Recruiter's camp",
		"ru": "Лагерь вербовщика\n\n",
		"de": "Lager des Anwerbers"
	},
	"zone bz22k": {
		"en": "Beastmasters",
		"ru": "Повелители зверей\n\n",
		"de": "Tiermeister"
	},
	"zone bz2h": {
		"en": "Rindeil's mansion",
		"ru": "Особняк Риндейла\n\n",
		"de": "Rindeils Anwesen"
	},
	"zone bz31j": {
		"en": "City of Dar-Leanos",
		"ru": "Город Дар-Леанос\n\n",
		"de": "Stadt Dar-Leanos"
	},
	"zone bz32j": {
		"en": "The spy",
		"ru": "Шпион\n\n",
		"de": "Der Spion"
	},
	"zone bz4h": {
		"en": "Wormface temple",
		"ru": "Храм червелицых\n\n",
		"de": "Tempel der Wurmgesichter"
	},
	"zone bz5h": {
		"en": "Black market",
		"ru": "Черный рынок\n\n",
		"de": "Schwarzmarkt"
	},
	"zone bz8g": {
		"en": "Orc fortress",
		"ru": "Крепость орков\n\n",
		"de": "Orkfestung"
	},
	"zone cz1h": {
		"en": "A breathing space",
		"ru": "Передышка\n\n",
		"de": "Eine Verschnaufpause"
	},
	"zone cz2h": {
		"en": "Catacomb exit",
		"ru": "Выход из катакомб\n\n",
		"de": "Ausgang der Katakomben"
	},
	"zone gz10g": {
		"en": "Foothills\nThe foothills border the settled lands and the wilderness. A settlement of free hunters stands here, but goblins and orcs are far more common than humans.",
		"ru": "Предгорья\nПредгорья — граница между освоенной людьми территорией и дикими землями. Здесь находится поселение «вольных охотников», однако гораздо чаще, чем людей, здесь можно встретить гоблинов и орков.\n",
		"de": "Vorgebirge\nDas Vorgebirge trennt die besiedelten Gebiete von der Wildnis. Hier liegt eine Siedlung freier Jäger, doch Goblins und Orks begegnet man wesentlich häufiger als Menschen."
	},
	"zone gz11d1": {
		"en": "Lizardmen's tomb\nThe lizardmen turned this abandoned underground palace of an ancient civilization into a tomb for their chieftains. No human has entered it for centuries.",
		"ru": "Гробница ящеров\nВ этом заброшенном подземном дворце древней цивилизации ящеры устроили гробницу для своих вождей. Ни одному человеку не удавалось побывать здесь уже многие века.\n",
		"de": "Grab der Echsenmenschen\nIn diesem verlassenen unterirdischen Palast einer alten Zivilisation bestatten die Echsenmenschen ihre Häuptlinge. Seit Jahrhunderten hat kein Mensch diesen Ort betreten."
	},
	"zone gz11d2": {
		"en": "Babur's mine\nMaster Babur once mined materials for his weapons here. Once everything valuable had been removed, the mine was abandoned and underground monsters moved in.",
		"ru": "Шахта Бабура\nСтарая шахта, в которой мастер Бабур добывал материал для изготовления оружия. После того, как все ценное было вынесено, шахта перестала использоваться, и в ней поселились подземные чудовища.",
		"de": "Baburs Mine\nMeister Babur gewann hier einst Material für seine Waffen. Nachdem alle wertvollen Vorkommen erschöpft waren, wurde die Mine verlassen und von unterirdischen Ungeheuern besiedelt."
	},
	"zone gz14g": {
		"en": "Tunnel\nLike Gipath's many ruins, this tunnel is a relic of antiquity. It was once the shortest and safest route through the mountains into the gorge, but much has changed since then.",
		"ru": "Тоннель\nТоннель — такой же след древности, как и многочисленные развалины на Гипате. Когда-то он был самой короткой и безопасной дорогой через горы в ущелье, но с тех пор очень многое изменилось.\n",
		"de": "Tunnel\nWie die zahlreichen Ruinen auf Gipath stammt auch dieser Tunnel aus uralter Zeit. Einst führte hier der kürzeste und sicherste Weg durch die Berge in die Schlucht, doch seither hat sich vieles verändert."
	},
	"zone gz15g": {
		"en": "Village and Ruins\nNamed for the remains of ancient buildings, this region is comparatively safe. Straying from the road can still lead a traveller into serious trouble.",
		"ru": "Поселок и Развалины\nЭта местность, получившая свое название от руин древних построек, сравнительно безопасна. Однако, сбившись с дороги, человек может попасть в очень неприятную ситуацию.\n",
		"de": "Dorf und Ruinen\nDiese Gegend ist nach den Überresten alter Bauwerke benannt und vergleichsweise sicher. Wer vom Weg abkommt, kann dennoch in große Schwierigkeiten geraten."
	},
	"zone gz16g": {
		"en": "River and Islands\nThe river from the Distant Mountains flows into the Great Lake, forming a delta with many islands. Large goblin and orc settlements, homes and shrines stand here. Free hunters also visit, but seldom linger.",
		"ru": "Река и острова\nРека, начинающаяся в Дальних горах, впадает в Большое Озеро, образуя дельту с многочисленными островами. Здесь находятся большие поселения гоблинов и орков, их дома и святилища. Также сюда заходят «вольные охотники», но они стараются не оставаться здесь надолго.\n",
		"de": "Fluss und Inseln\nDer Fluss aus den Fernen Bergen mündet mit einem weitläufigen Inseldelta in den Großen See. Hier stehen große Goblin- und Orksiedlungen mit Wohnhäusern und Heiligtümern. Auch freie Jäger kommen hierher, bleiben jedoch selten lange."
	},
	"zone gz1d1": {
		"en": "Rat farm\nRats are bred in this underground complex for their edible tails. The dungeon has two exits.",
		"ru": "Крысиная ферма\nВ этом подземелье разводят крыс ради их хвостов, которые можно употреблять в пищу. Подземелье имеет два выхода.\n",
		"de": "Rattenfarm\nIn diesem Verlies werden Ratten wegen ihrer essbaren Schwänze gezüchtet. Es gibt zwei Ausgänge."
	},
	"zone gz1d2": {
		"en": "Catacombs\nAbandoned catacombs provide a route out of the fortress surrounding the Portal.",
		"ru": "Катакомбы\nЗаброшенные катакомбы, через которые можно выйти из крепости, окружающей Портал.\n",
		"de": "Katakomben\nDurch die verlassenen Katakomben führt ein Weg aus der Festung, die das Portal umgibt."
	},
	"zone gz1g": {
		"en": "Western castle outskirts\nTo the east stands an impregnable castle, Jigran's stronghold. Its dungeons are the prison from which the hero escaped with such difficulty.",
		"ru": "Западные окрестности замка\nНа востоке отсюда находится непристунный замок — оплот аллода Джигран. Именно там находятся темницы, из которых с таким трудом удалось сбежать главному герою.\n",
		"de": "Westliches Schlossumland\nIm Osten steht ein uneinnehmbares Schloss, die Hochburg Jigrans. In seinen Kerkern war der Held gefangen, bevor ihm unter großen Mühen die Flucht gelang."
	},
	"zone gz1h": {
		"en": "Portal\nThe region is named after its ancient structure. It also contains the fortress guarding the Portal, much of Suslanger's city and several estates.",
		"ru": "Портал\nМестность взяла название древнего сооружения, но, помимо этого артефакта, тут находятся крепость, прикрывающая его, значительная часть города Суслангера и несколько поместий.\n",
		"de": "Portal\nDie Gegend trägt den Namen ihres uralten Bauwerks. Hier liegen auch die Festung zum Schutz des Portals, ein großer Teil der Stadt Suslanger und mehrere Landgüter."
	},
	"zone gz21k": {
		"en": "City outskirts\nThis province of Ingos has only one city, the seat of government. People in the surrounding villages resent the governor's ruinous orders. Woodland creatures known as foresters also live nearby.",
		"ru": "Окрестности города\nВ этой провинции Ингоса только один город, который является резиденцией власти. Население поселков вокруг настроено враждебно к городским жителям из-за разорительных приказов губернатора. Также в округе живут существа, которых называют лесовиками — по месту их обитания.\n",
		"de": "Stadtumland\nIn dieser Provinz von Ingos gibt es nur eine Stadt, den Sitz der Obrigkeit. Die Menschen in den umliegenden Dörfern hassen die verheerenden Befehle des Gouverneurs. In den nahen Wäldern leben außerdem die Waldmenschen."
	},
	"zone gz22d1": {
		"en": "Abandoned mines\nMining stopped when the workers broke into wormface dwellings. The masters of the underground do not welcome intruders.",
		"ru": "Заброшенные рудники\nНекогда здесь добывали руду, но, после того как рудокопы добрались до жилищ червелицых, разработку\nпришлось бросить — Повелители Подземелий не любят, когда их тревожат.\n",
		"de": "Verlassene Minen\nDer Erzabbau wurde aufgegeben, nachdem die Bergleute auf die Behausungen der Wurmgesichter stießen. Die Herren der Unterwelt lassen sich nicht gern stören."
	},
	"zone gz22k": {
		"en": "Mining district\nMining once flourished here. When monsters began appearing underground, the entrances were sealed and the surrounding district fell into decline.",
		"ru": "Зона рудников\nНазвание этой местности отражает ее недавнее прошлое — некогда в этой местности было развито горнорудное дело. Но, после того как в шахтах начали появляться монстры и чудовища, входы в них были закрыты — и окрестности пришли в упадок.\n",
		"de": "Bergbaugebiet\nFrüher blühte hier der Bergbau. Als in den Gruben Ungeheuer auftauchten, wurden die Eingänge verschlossen, und die Gegend verfiel."
	},
	"zone gz23k": {
		"en": "Karansul's domain\nKaransul's workshops stand here. His followers control almost the entire region, apart from the narrow valleys between the mountain spurs.",
		"ru": "Владения Карансула\nЗдесь находятся цехи и мастерские, принадлежащие Карансулу. Его подручные контролируют почти всю территорию, кроме узких долин между отрогами гор.\n",
		"de": "Karansuls Herrschaftsgebiet\nHier stehen Karansuls Werkstätten. Seine Gefolgsleute beherrschen fast die gesamte Gegend, mit Ausnahme der schmalen Täler zwischen den Bergausläufern."
	},
	"zone gz24k": {
		"en": "Mines\nAbout half the mines still produce gold and stone, the province's only source of income. They are closely guarded, and anyone without a pass should avoid the patrols. The other mines closed after workers disturbed underground creatures.",
		"ru": "Рудники\nПримерно в половине рудников ведется добыча золота и камней — единственного источника дохода провинции. По этой причине эта часть хорошо охраняется, и лучше не попадаться без пропуска на глаза страже. Вторая половина была закрыта, когда горняки потревожили жилища подземных тварей.\n",
		"de": "Minen\nEtwa die Hälfte der Minen liefert noch Gold und Gestein, die einzige Einnahmequelle der Provinz. Sie werden streng bewacht; ohne Pass sollte man der Wache aus dem Weg gehen. Die übrigen Gruben wurden geschlossen, nachdem Bergleute unterirdische Wesen aufgeschreckt hatten."
	},
	"zone gz25k": {
		"en": "Snowy wasteland\nHarsh conditions leave this region almost uninhabited. A small logging village in the west is its only safe haven. The northern lights can sometimes be seen here.",
		"ru": "Снежная пустошь\nХоть эта местность почти необитаема в силу плохих условий для проживания, на западе ее есть небольшой поселок лесорубов, и это единственное безопасное место в округе. Иногда здесь можно видеть северное сияние.\n",
		"de": "Schneewüste\nDie unwirtlichen Bedingungen machen diese Gegend fast unbewohnbar. Nur ein kleines Holzfällerdorf im Westen bietet Sicherheit. Manchmal sind hier Polarlichter zu sehen."
	},
	"zone gz26k": {
		"en": "Old portal\nThis cave contains a portal unused for so long that it has almost been forgotten.",
		"ru": "Старый портал\nВ этой пещере находится портал, который не использовался так давно, что о нем почти забыли.\n",
		"de": "Altes Portal\nIn dieser Höhle liegt ein Portal, das so lange nicht mehr benutzt wurde, dass es beinahe in Vergessenheit geraten ist."
	},
	"zone gz31j": {
		"en": "Dar-Leanos and its surroundings\nThese lands are almost all Kania has left, and even holding them is uncertain. Undead attack the city, pests infest the fields and bandits roam the woods. However high its walls, the city's fall seems only a matter of time.",
		"ru": "Город Дар-Леанос и окрестности\nЭто — все то немногое, что осталось у Кании, и даже удержание этих земель находится под вопросом. Город подвергается атакам нежити, на полях развелись паразиты, а в лесах — разбойники. И пусть стены высоки и неприступны, падение города — лишь вопрос времени.\n\n",
		"de": "Dar-Leanos und Umgebung\nDies ist fast alles, was Kania noch geblieben ist, und selbst diese Gebiete sind kaum zu halten. Untote greifen die Stadt an, Schädlinge befallen die Felder, und Räuber durchstreifen die Wälder. Trotz der hohen Mauern scheint der Fall der Stadt nur eine Frage der Zeit."
	},
	"zone gz32j": {
		"en": "Island of Death\nOnce a Kanian harbour, the island still has its old pier and abandoned warehouses. A powerful necromancer now lives here, and half the island has died. In the Dragon Mountains, a statue of a vampire-slaying hero stands as a symbol of freedom.",
		"ru": "Остров смерти\nОстров некогда использовался Канией как морской узел, старая пристань и заброшенные склады уцелели до нынешних времен. Сейчас здесь обосновался могущественный некромант, в силу чего половина острова стала мертвой. В драконовых горах символом свободы высится статуя героя — истребителя вампиров.\n\n",
		"de": "Insel des Todes\nDie Insel war einst ein Hafen Kanias; der alte Anleger und verlassene Lagerhäuser sind noch erhalten. Heute lebt hier ein mächtiger Nekromant, und die Hälfte der Insel ist tot. In den Drachenbergen steht als Freiheitssymbol die Statue eines Helden, der Vampire erschlug."
	},
	"zone gz33j": {
		"en": "Dar-Ulgorn fortress\nKania recently abandoned this fortress to Hadagan's soldiers, who laid waste to the surrounding lands. Necromancers turned every peasant into a zombie; these undead now work the fields to feed the garrison.",
		"ru": "Крепость Дар-Улгорн\nЭта крепость принадлежала Кании, но не так давно ее пришлось оставить. Крепость Дар-Улгорн заняли хадаганские воины, а окрестности разорили. На полях трудятся одни упыри, так как некроманты зомбировали всех крестьян. Эти упыри обеспечивают продовольствием гарнизон.\n",
		"de": "Festung Dar-Ulgorn\nKania musste diese Festung vor Kurzem aufgeben. Hadagans Soldaten besetzten sie und verwüsteten das Umland. Nekromanten verwandelten sämtliche Bauern in Zombies, die nun die Felder für die Garnison bestellen."
	},
	"zone gz34d1": {
		"en": "June cache\nThis ancient storehouse is the only trace of the Junes on Jigran. Powerful magic created and sealed it to keep their knowledge and artefacts from falling into the wrong hands.",
		"ru": "Тайник джунов\nДревнее хранилище джунов — единственный их след на аллоде Джигран. Оно было создано и запечатано могущественной магией, чтобы знания и артефакты древней расы не попали не в те руки.",
		"de": "Versteck der June\nDieses uralte Lager ist die einzige Spur der June auf Jigran. Mächtige Magie erschuf und versiegelte es, damit das Wissen und die Artefakte des alten Volkes nicht in falsche Hände geraten."
	},
	"zone gz34j": {
		"en": "Two Rivers\nTwo rivers give this region its name. War reduced the city between them to ruins and turned its inhabitants into undead. The strategic position now holds a large Hadagan camp.",
		"ru": "Две реки\nЭта местность получила свое название из-за двух рек, протекающих по ней. Раньше в междуречье был крупный город, но война превратила его в руины, а погибшие жители превратились в нежить. Место между этими реками имеет стратегический характер, поэтому в развалинах расположен мощный хадаганский лагерь.\n\n",
		"de": "Zwei Flüsse\nZwei Flüsse geben dieser Gegend ihren Namen. Der Krieg legte die Stadt dazwischen in Trümmer und verwandelte ihre Bewohner in Untote. Wegen der strategischen Lage steht in den Ruinen nun ein großes hadaganisches Lager."
	},
	"zone gz35j": {
		"en": "Sadrok and its surroundings\nSadrok is Hadagan's stronghold on Jigran. Living and dead troops fill the city, which contains Firez's castle, a working harbour, a military academy, the necromancers' guild and noble estates. A June prison lies high in the southern mountains.",
		"ru": "Город Садрок и окрестности\nГород Садрок и земли вокруг него — оплот империи Хадаган на аллоде. В городе собраны многочисленные войска живых и мертвых, находятся замок Фиреза, действующая пристань, военная академия, гильдия некромантов и дома знати. Высоко в горах на юге — тюрьма джунов.\n\n",
		"de": "Sadrok und Umgebung\nSadrok ist Hadagans Hochburg auf Jigran. Lebende und tote Truppen füllen die Stadt. Hier liegen Firez' Schloss, ein aktiver Hafen, eine Militärakademie, die Nekromantengilde und die Häuser des Adels. Hoch in den südlichen Bergen befindet sich ein Gefängnis der June."
	},
	"zone gz36j": {
		"en": "Throne room\nThe mad necromancer Firez uses this hall as both throne room and treasury. The final battle with him will decide Jigran's fate.",
		"ru": "Тронный зал\nТронный зал и сокровищница по совместительству безумного некроманта Фиреза. Здесь будет решаться судьба аллода Джигран. Здесь пройдет финальная битва с Фирезом.",
		"de": "Thronsaal\nDer wahnsinnige Nekromant Firez nutzt diesen Saal zugleich als Thronraum und Schatzkammer. Der letzte Kampf gegen ihn entscheidet über Jigrans Schicksal."
	},
	"zone gz3d1": {
		"en": "Prison\nThis underground complex belongs to the necromancers' guild. It contains prison cells, a torture chamber, a courtroom and an execution chamber.",
		"ru": "Тюрьма\nЭтот подземный комплекс принадлежит гильдии некромантов. В состав комплекса входят тюремные камеры, комната пыток, комната суда и камера смерти.\n",
		"de": "Gefängnis\nDieser unterirdische Komplex gehört der Nekromantengilde. Er umfasst Gefängniszellen, eine Folterkammer, einen Gerichtssaal und eine Hinrichtungskammer."
	},
	"zone gz4h": {
		"en": "Wormface cave\nDeep in this cave stands the temple of the magically gifted wormfaces. Rather than suffer heavy losses clearing it, Hadagan's soldiers guard its exits.",
		"ru": "Пещера червелицых\nГлубокая пещера, в которой находится Храм Червелицых — существ, обладающих большими  магическими способностями. Операция по очистке пещеры была чревата огромными потерями, и поэтому хадаганские воины ограничиваются тем, что охраняют выходы оттуда.\n",
		"de": "Höhle der Wurmgesichter\nTief in dieser Höhle liegt der Tempel der magisch begabten Wurmgesichter. Da eine Räumung hohe Verluste kosten würde, bewachen Hadagans Soldaten lediglich die Ausgänge."
	},
	"zone gz7d1": {
		"en": "Old mine\nThe people of a nearby town once worked this mine. When the town was deserted, the mine was abandoned as well.",
		"ru": "Старая шахта\nКогда-то давно эту шахту разрабатывали люди, жившие в городе неподалеку, но город был покинут, а шахта — заброшена.\n",
		"de": "Alte Mine\nFrüher wurde diese Mine von den Bewohnern der nahen Stadt betrieben. Als die Stadt verlassen wurde, gab man auch die Mine auf."
	},
	"zone gz7d2": {
		"en": "Goblin mine\nGoblins mine the materials for their weapons here.",
		"ru": "Шахта гоблинов\nВ этой шахте гоблины добывают материалы для изготовления оружия.\n",
		"de": "Goblinmine\nHier gewinnen Goblins das Material für ihre Waffen."
	},
	"zone gz7g": {
		"en": "Dead City\nTwo mountain ridges extend into a broad plain, enclosing the valley of the Dead City. Humans once lived there; now it is a nest of undead.",
		"ru": "Мертвый город\nНа широкую равнину выдаются два горных хребта, образующих долину. В этой долине расположен Мертвый город — когда-то он был населен людьми, а теперь в нем гнездится нежить.\n",
		"de": "Tote Stadt\nZwei Bergrücken ragen in eine weite Ebene und umschließen das Tal der Toten Stadt. Einst lebten dort Menschen; heute hausen hier Untote."
	},
	"zone gz9d1": {
		"en": "Goblin mine\nGoblins mine the materials for their weapons here.",
		"ru": "Шахта гоблинов\nВ этой шахте гоблины добывают материалы для изготовления оружия.\n",
		"de": "Goblinmine\nHier gewinnen Goblins das Material für ihre Waffen."
	},
	"zone gz9g": {
		"en": "Middle Mountains\nMountains occupy the northern half of this region; the southern plains are easier to cross. The lightly settled plains can be traversed without meeting an enemy, while people avoid the much more dangerous mountains.",
		"ru": "Средние горы\nГоры занимают северную половину этой области, а южная часть — гораздо более ровная и удобная для передвижения. Равнинная часть населена слабо, и осторожный путник сможет пересечь ее, не встретив ни одного врага. Горы гораздо более опасны, и люди стараются не заходить туда.\n",
		"de": "Mittlere Berge\nDie nördliche Hälfte ist gebirgig, während sich die südlichen Ebenen leichter durchqueren lassen. Die dünn besiedelte Ebene kann ein vorsichtiger Reisender ohne Feindkontakt durchqueren. Die wesentlich gefährlicheren Berge werden gemieden."
	},
	"quest fq10": {
		"ru": "Глоток свободы\nНепреклонный борец за свободу гоблинов Го-Го попал в заточение к островным оркам. Только его освобождение даст шанс гоблинам вдохнуть воздух свободы!\n#subobj 1\nМолодец\nАга!\n",
		"en": "A Taste of Freedom\nGo-Go, the determined fighter for goblin freedom, has been imprisoned by the island orcs. Freeing him is the goblins' only chance to breathe the air of freedom!\n#subobj 1\nWell done\n",
		"de": "Ein Hauch Freiheit\nGo-Go, der unerschütterliche Kämpfer für die Freiheit der Goblins, wurde von den Inselorks eingesperrt. Nur seine Befreiung gibt den Goblins eine Chance auf Freiheit!\n#subobj 1\nGut gemacht\n"
	},
	"quest fq11": {
		"ru": "Быстрые ноги\nОдин из разбойников, искавший клад в Золотой долине, разрубил оживший скелет опытного война на две части. Видимо, при жизни обладатель скелета был крепок «задним умом», поэтому нижняя часть скелета так и осталась живой...\n#subobj 1\nМолодец\nАга!\n",
		"en": "Fleet Feet\nA bandit searching for treasure in the Golden Valley cut an experienced warrior's animated skeleton in half. Its owner apparently had a remarkably clever backside in life: the lower half is still alive...\n#subobj 1\nWell done\n",
		"de": "Flinke Füße\nEin Bandit auf Schatzsuche im Goldenen Tal hieb das belebte Skelett eines erfahrenen Kriegers entzwei. Sein Besitzer war offenbar schon zu Lebzeiten ein besonders schlaues Hinterteil: Die untere Hälfte lebt noch immer...\n#subobj 1\nGut gemacht\n"
	},
	"quest fq12": {
		"ru": "Двойная порция\nОстровные орки тайно откармливают гигантского людоеда! Если его не кормить, то он рассвирепеет и станет смертельно опасен. Если кормить, то он станет еще больше! Остается только перекормить...\n#subobj 1\nМолодец\nАга!\n",
		"en": "A Double Portion\nThe island orcs are secretly fattening a giant ogre! Leave it hungry and it becomes furious and deadly; feed it and it grows even bigger. The only solution is to overfeed it...\n#subobj 1\nWell done\n",
		"de": "Eine doppelte Portion\nDie Inselorks mästen heimlich einen riesigen Oger! Ohne Futter wird er rasend und tödlich, mit Futter noch größer. Da hilft nur, ihn zu überfüttern...\n#subobj 1\nGut gemacht\n"
	},
	"quest fq13": {
		"ru": "Зал Великих\nНа верхнем ярусе гробницы ящеров располагается зал, в котором ящеры хоронили самых великих из своих вождей.\n#subobj 1\nМолодец\nАга!\n",
		"en": "Hall of the Great\nThe upper level of the lizard tomb contains the hall where the lizards buried their greatest chieftains.\n#subobj 1\nWell done\n",
		"de": "Halle der Großen\nAuf der oberen Ebene der Echsenkrypta liegt die Halle, in der die Echsen ihre größten Häuptlinge bestatteten.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq14": {
		"ru": "Найти чертеж секретного оружия\nОн должен находиться в лаборатории. \n#subobj 1\nНайти другой вход\nЭта дверь заблокирована изнутри, придется поискать другой вход.\n#subobj 2\nНайти ключ\nДверь в лабораторию закрыта, нужно найти ключ, он должен быть где-то поблизости.\n#subobj 3\nВойти в лабораторию\nНужно ключом разблокировать дверь и открыть ее.\n#subobj 4\nЗабрать чертеж\nОн находится где-то здесь.\n#subobj 5\nЗарядка големов\nЕсли бы зарядить одного да взять с собой, не страшен был бы любой враг!\n#subobj 6\nРазрядка големов\nТеперь они точно никогда не зарядятся.\n\n\n",
		"en": "Find the Secret Weapon Blueprint\nIt should be in the laboratory.\n#subobj 1\nFind another entrance\n\n#subobj 2\nFind the key\n\n#subobj 3\nEnter the laboratory\n\n#subobj 4\nCollect the blueprint\n\n#subobj 5\nCharge the golems\n\n#subobj 6\nDischarge the golems\n",
		"de": "Den Bauplan der Geheimwaffe finden\nEr müsste im Labor liegen.\n#subobj 1\nEinen anderen Eingang finden\n\n#subobj 2\nDen Schlüssel finden\n\n#subobj 3\nDas Labor betreten\n\n#subobj 4\nDen Bauplan holen\n\n#subobj 5\nDie Golems aufladen\n\n#subobj 6\nDie Golems entladen\n"
	},
	"quest fq15": {
		"ru": "Стая\nЖивотные не должны подвергаться заточению. Тот, кто освободит их, получит благодарность защитников животных.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Pack\nAnimals should not be imprisoned. Whoever frees them will earn the gratitude of their protectors.\n#subobj 1\nWell done\n",
		"de": "Das Rudel\nTiere sollten nicht eingesperrt werden. Wer sie befreit, verdient sich den Dank ihrer Beschützer.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq16": {
		"ru": "Преграда\nНе любые ворота можно открыть, не всякую преграду можно убрать с пути. Ждет награда того, кто найдет способ добраться до цели.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Barrier\nNot every gate can be opened, nor every obstacle removed. A reward awaits whoever finds a way to the goal.\n#subobj 1\nWell done\n",
		"de": "Die Sperre\nNicht jedes Tor lässt sich öffnen und nicht jedes Hindernis beseitigen. Wer einen Weg zum Ziel findet, wird belohnt.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq17": {
		"ru": "Дерево жизни\nОколо колодца в военном лагере стоит одинокое дерево. Кто польет его, по завету лесовиков вырастит небывалое растение.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Tree of Life\nA lone tree stands beside the well in the military camp. Watering it as the foresters advise will make an extraordinary plant grow.\n#subobj 1\nWell done\n",
		"de": "Der Baum des Lebens\nAm Brunnen im Militärlager steht ein einsamer Baum. Wer ihn nach dem Rat der Waldleute gießt, lässt eine außergewöhnliche Pflanze wachsen.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq18": {
		"ru": "Домик в деревне\nЛесовики хотят познакомиться со странными пятнистыми животными, дающими вкусное молоко. Одно такое животное есть в загоне в деревеньке на юге владений Карансула.\n#subobj 1\nМолодец\nАга!\n",
		"en": "A Cottage in the Village\nThe foresters want to meet the strange spotted animals that give delicious milk. One is kept in a pen in a small village in southern Karansul's domain.\n#subobj 1\nWell done\n",
		"de": "Ein Häuschen im Dorf\nDie Waldleute möchten die seltsamen gefleckten Tiere kennenlernen, die köstliche Milch geben. Eines steht in einem Pferch im Dorf im Süden von Karansuls Herrschaftsgebiet.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq19": {
		"ru": "Блуждание в потемках\nПоследовательность рычагов и ворот в пещере закрывает путь к сундуку. Только владелец особого ключа сможет разгадать загадку.\n#subobj 1\nМолодец\nАга!\n",
		"en": "Groping in the Dark\nA sequence of levers and gates blocks the way to a chest in the cave. Only someone with a special key can solve the puzzle.\n#subobj 1\nWell done\n",
		"de": "Im Dunkeln tappen\nEine Folge von Hebeln und Toren versperrt den Weg zu einer Truhe in der Höhle. Nur mit einem besonderen Schlüssel lässt sich das Rätsel lösen.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq2": {
		"ru": "Подземный ход\nПробраться на территорию особняка можно только через подземный ход. Путешествие стоит того.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Underground Passage\nThe manor can only be entered through an underground passage. The journey is worth it.\n#subobj 1\nWell done\n",
		"de": "Der unterirdische Gang\nDas Anwesen ist nur durch einen unterirdischen Gang erreichbar. Der Weg lohnt sich.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq3": {
		"ru": "Урожай\nВ корзине посреди плантаций собран почти весь урожай за несколько дней.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Harvest\nThe basket among the plantations holds almost the entire harvest of several days.\n#subobj 1\nWell done\n",
		"de": "Die Ernte\nIm Korb mitten auf den Plantagen liegt fast die gesamte Ernte mehrerer Tage.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq4": {
		"ru": "Сундук на горе\nНа горе стоит большой сундук. В такой сундук можно положить много денег...\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Chest on the Mountain\nA large chest stands on the mountain. A chest that size could hold a lot of money...\n#subobj 1\nWell done\n",
		"de": "Die Truhe auf dem Berg\nAuf dem Berg steht eine große Truhe. In eine solche Truhe passt eine Menge Geld...\n#subobj 1\nGut gemacht\n"
	},
	"quest fq5": {
		"ru": "Сундук мертвецов\nПо непонятной причине сундук открывается только в случае гибели всех зомби.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Chest of the Dead\nFor some unknown reason, the chest only opens once all the zombies are dead.\n#subobj 1\nWell done\n",
		"de": "Die Truhe der Toten\nAus unbekanntem Grund öffnet sich die Truhe erst, wenn alle Zombies tot sind.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq6": {
		"ru": "Загадка червелицых\nРычаги около храма червелицых заколдованы. Только хитрый и удачливый сможет разгадать тайну.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Wormfaces' Riddle\nThe levers near the wormface temple are enchanted. Only the clever and fortunate can unravel the mystery.\n#subobj 1\nWell done\n",
		"de": "Das Rätsel der Wurmgesichter\nDie Hebel am Tempel der Wurmgesichter sind verzaubert. Nur mit Geschick und Glück lässt sich ihr Geheimnis lösen.\n#subobj 1\nGut gemacht\n"
	},
	"quest fq8": {
		"ru": "Большой гриб\nНа полянке около лагеря гоблинов в Средних горах растут самые большие грибы на Гипате. Но съедобный только один...\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Giant Mushroom\nThe clearing near the goblin camp in the Middle Mountains has the largest mushrooms on Gipath. Only one is edible...\n#subobj 1\nWell done\n",
		"de": "Der Riesenpilz\nAuf der Lichtung beim Goblinlager im Mittleren Gebirge wachsen die größten Pilze auf Gipath. Doch nur einer ist essbar...\n#subobj 1\nGut gemacht\n"
	},
	"quest fq9": {
		"ru": "Сокровища экспедиции\nЗа решеткой в разоренном лагере хадаганской экспедиции лежит мешок с сокровищами.\n#subobj 1\nМолодец\nАга!\n",
		"en": "The Expedition's Treasure\nA bag of treasure lies behind a grate in the ruined Hadagan expedition camp.\n#subobj 1\nWell done\n",
		"de": "Der Schatz der Expedition\nHinter einem Gitter im verwüsteten Lager der hadaganischen Expedition liegt ein Schatzbeutel.\n#subobj 1\nGut gemacht\n"
	},
	"quest q02h": {
		"ru": "Побег\nВ загоне для рабов происходит что-то странное, и, пока стражники отвлеклись, можно попытаться сбежать.\n#subobj  1\nВыбраться из загона\nПохоже, одна из секций ограды не так прочна, как другие, — можно попытаться сломать ее.\n#subobj  2\nУбежать от монстра\nНеобходимо скрыться, пока чудовище отвлеклось на время от своей главной цели.\n#subobj  3\nЗаполучить план подземного хода\nПройти через главные ворота нет ни малейшего шанса. Но, по словам Кель, наружу есть и другой выход — через старый подземный ход. К сожалению, она не знает, как туда попасть, но план хода наверняка должен быть у одного из офицеров. \n#subobj  4\nПрийти к подземному ходу\nОказывается, потайной подземный ход спрятан под видом обычного дома на западе крепости. Самое время воспользоваться им!\n",
		"en": "Escape\nSomething strange is happening in the slave pen. With the guards distracted, this might be a chance to escape.\n#subobj 1\nEscape the pen\n\n#subobj 2\nEscape the monster\n\n#subobj 3\nObtain the underground passage plan\n\n#subobj 4\nGo to the underground passage\n",
		"de": "Flucht\nIm Sklavenpferch geht etwas Seltsames vor. Solange die Wachen abgelenkt sind, könnte eine Flucht gelingen.\n#subobj 1\nAus dem Pferch entkommen\n\n#subobj 2\nDem Monster entkommen\n\n#subobj 3\nDen Plan des unterirdischen Gangs beschaffen\n\n#subobj 4\nZum unterirdischen Gang gehen\n"
	},
	"quest q03h": {
		"ru": "Катакомбы\nПройти старые катакомбы — единственный подходящий способ выбраться из крепости. Эти ходы уже давно не используются, и тут могли завестись опасные существа!\n#subobj  1\nВоспользоваться лифтом\nЛифт раньше служил для переправки различных грузов из крепости наружу и обратно. Скорее всего он и сейчас работает.\n#subobj  2\nОбыскать сундук \nПохоже, что часть грузов отсюда забыли или не успели вывезти. Сейчас могут пригодиться даже старые вещи, которые тут сохранились.\n#subobj  3\nПокинуть катакомбы\nСтража крепости может догадаться проверить эту лазейку. Лучше не задерживаться здесь.\n",
		"en": "The Catacombs\nThe old catacombs are the only suitable way out of the fortress. These passages have long been unused and may now harbour dangerous creatures!\n#subobj 1\nUse the lift\n\n#subobj 2\nSearch the chest\n\n#subobj 3\nLeave the catacombs\n",
		"de": "Die Katakomben\nDie alten Katakomben sind der einzige geeignete Weg aus der Festung. Die lange ungenutzten Gänge könnten inzwischen gefährliche Kreaturen beherbergen!\n#subobj 1\nDen Aufzug benutzen\n\n#subobj 2\nDie Truhe durchsuchen\n\n#subobj 3\nDie Katakomben verlassen\n"
	},
	"quest q10g": {
		"ru": "Мир с ящерами\nЯщер-Отшельник просит установить Большую ракушку на алтарь ящеров в Дальних горах и тем самым помирить их с людьми, которые стали часто совершать набеги на владения ящеров. Взамен Отшельник обещал рассказать, как найти Избранного.\n#subobj 1\nПрийти к алтарю\nПоселение ящеров расположено на западе Дальних гор. Алтарь же находится в самом центре поселения и хорошо охраняется.\n#subobj 2\nУстановить ракушку\nПосле того как ракушка будет установлена на алтарь, в Дальних горах наступит мир.\n",
		"en": "Peace with the Lizards\nThe Lizard Hermit asks you to place the Great Shell on the lizard altar in the Distant Mountains. This should bring peace with the humans who have been raiding lizard lands. In return, the Hermit promises to explain how to find the Chosen One.\n#subobj 1\nGo to the altar\n\n#subobj 2\nPlace the shell\n",
		"de": "Frieden mit den Echsen\nDer Echsen-Eremit bittet dich, die Große Muschel auf den Echsenaltar im Fernen Gebirge zu legen. Das soll Frieden mit den Menschen stiften, die häufig das Echsenland überfallen. Dafür will er verraten, wie der Auserwählte zu finden ist.\n#subobj 1\nZum Altar gehen\n\n#subobj 2\nDie Muschel aufstellen\n"
	},
	"quest q10j": {
		"ru": "Рагу с грибами\nШтурм хадаганской крепости пройдет намного проще, если накормить вражеских солдат особой пищей, так чтобы им было не до сражений. Для приготовления «расслабляющего» рагу, дядюшке Раду нужны большая тыква и ядовитые грибы.\n#subobj 1\nНайти тыкву\nПодходящую тыкву можно найти на одном из полей не далеко от хадаганской крепости.\n#subobj 2\nЗабрать тыкву\nПодходящая для рагу тыква — единственная спелая на поле. Ее невозможно перепутать с другими.\n#subobj 3\nНайти грибы\nЯд в грибах не должен действовать мгновенно, иначе слишком мало стражников будет отравлено. Подходящие грибы растут только у реки южнее палатки Рада.\n#subobj 4\nСобрать грибы\nГрибы ядовиты только при употреблении внутрь, но собирать их не опасно.\n",
		"en": "Mushroom Stew\nStorming the Hadagan fortress will be much easier if the enemy soldiers eat something that leaves them unfit to fight. Uncle Radu needs a large pumpkin and poisonous mushrooms for his “relaxing” stew.\n#subobj 1\nFind the pumpkin\nA suitable pumpkin can be found in one of the fields near the Hadagan fortress.\n#subobj 2\nCollect the pumpkin\nThe pumpkin suitable for the stew is the only ripe one in the field. You cannot mistake it for the others.\n#subobj 3\nFind the mushrooms\nThe poison must not act immediately, or too few guards will be affected. Suitable mushrooms grow only by the river south of Radu's tent.\n#subobj 4\nGather the mushrooms\nThe mushrooms are poisonous only when eaten; gathering them is safe.\n",
		"de": "Pilzeintopf\nDer Sturm auf die hadaganische Festung wird viel leichter, wenn die feindlichen Soldaten etwas essen, das sie kampfunfähig macht. Onkel Radu braucht einen großen Kürbis und giftige Pilze für seinen „entspannenden“ Eintopf.\n#subobj 1\nDen Kürbis finden\nEin geeigneter Kürbis wächst auf einem der Felder nahe der hadaganischen Festung.\n#subobj 2\nDen Kürbis holen\nDer für den Eintopf geeignete Kürbis ist der einzige reife auf dem Feld. Er ist nicht mit den anderen zu verwechseln.\n#subobj 3\nDie Pilze finden\nDas Gift darf nicht sofort wirken, sonst werden zu wenige Wachen vergiftet. Geeignete Pilze wachsen nur am Fluss südlich von Radus Zelt.\n#subobj 4\nDie Pilze sammeln\nDie Pilze sind nur beim Verzehr giftig; sie zu sammeln ist ungefährlich.\n"
	},
	"quest q10k": {
		"ru": "Дары в столицу\nРазбойники готовы принять новых людей в своем лагере, но для этого нужно подтвердить свою верность — ограбить караван с дарами в столицу.\n#subobj 1\nПрийти к стоянке каравана\nКараван в столицу ненадолго остановился во владениях Карансула, там же, где обычно останавливаются скупщики мехов и дичи.\n#subobj 2\nУничтожить засаду\nНеподалеку спрятались вооруженные люди — кто-то еще заинтересовался этим караваном. Необходимо уничтожить засаду, не привлекая внимания охраны каравана.\n#subobj 3\nВыкрасть дары\nСамые ценные дары в столицу лежат в сундучке на одной из телег.\n",
		"en": "Gifts for the Capital\nThe bandits will welcome newcomers to their camp, but first demand proof of loyalty: rob the caravan carrying gifts to the capital.\n#subobj 1\nGo to the caravan camp\n\n#subobj 2\nDestroy the ambush\n\n#subobj 3\nSteal the gifts\n",
		"de": "Geschenke für die Hauptstadt\nDie Banditen nehmen neue Leute auf, verlangen aber einen Treuebeweis: Der Karawane mit Geschenken für die Hauptstadt sollen die Waren geraubt werden.\n#subobj 1\nZum Karawanenlager gehen\n\n#subobj 2\nZerschlage den Hinterhalt\n\n#subobj 3\nDie Geschenke stehlen\n"
	},
	"quest q11g": {
		"ru": "Великий Маг\nЯщер-Отшельник рассказал, что, перед тем как исчезнуть, Избранный направился к жилищу Великого мага Гипата. Избранный прошел туда по какому-то тоннелю, но сейчас можно пройти и по поверхности — через ущелье на востоке Дальних гор.\n#subobj 1\nПрийти к ущелью\nПуть к Великому магу пролегает через длинное извилистое ущелье в горах. Вход в ущелье находится на востоке Дальних гор.\n#subobj 2\nПройти ущелье\nДорога из ущелья выходит к озеру в центре Дальних гор. В горах на пути к выходу могут обитать опасные существа.\n#subobj 3\nВойти в жилище мага\nВход в пещеру, в которой живет Великий маг Гипата, находится к северу от озера.\n",
		"en": "The Great Mage\nThe Lizard Hermit says the Chosen One went to the Great Mage of Gipath before disappearing. The Chosen One used a tunnel, but a surface route now leads through the gorge in the eastern Distant Mountains.\n#subobj 1\nGo to the gorge\n\n#subobj 2\nGet through the gorge\n\n#subobj 3\nEnter the mage's home\n",
		"de": "Der Große Magier\nLaut dem Echsen-Eremiten suchte der Auserwählte vor seinem Verschwinden den Großen Magier von Gipath auf. Er nahm einen Tunnel; inzwischen führt auch ein Weg an der Oberfläche durch die Schlucht im Osten des Fernen Gebirges.\n#subobj 1\nZur Schlucht gehen\n\n#subobj 2\nDie Schlucht durchqueren\n\n#subobj 3\nDas Haus des Magiers betreten\n"
	},
	"quest q11h": {
		"ru": "Пропавшие товары\nКараван с товарами, которые должны были попасть в лавку тети Зары, по неизвестным причинам сильно задерживается в пути. На поиски каравана уже вышла городская стража, но, так как не все товары легальные, стражу необходимо опередить!\n#subobj  1\nНайти караван\nКараван должен был пройти с востока на запад южнее крепостных стен.\n#subobj  2\nУничтожить диких зверей\nВидимо, на караван напали дикие звери. Чтобы забрать уцелевшие вещи, необходимо убить всех зверей.\n#subobj  3\nОбыскать сундук\nВсе нелегальные товары лежат в большом сундуке. Если успеть их забрать, то стража ничего не заподозрит и вернет все остальное тете Заре в целости и сохранности.\n",
		"en": "Missing Goods\nAunt Zara's caravan is badly overdue for unknown reasons. The city guards have already gone looking, but some goods are illegal. Find the caravan before they do!\n#subobj 1\nFind the caravan\n\n#subobj 2\nKill the wild beasts\n\n#subobj 3\nSearch the coffer\n",
		"de": "Vermisste Waren\nTante Zaras Warenkarawane verspätet sich aus unbekannten Gründen erheblich. Die Stadtwache sucht bereits nach ihr. Da einige Waren illegal sind, musst du der Wache zuvorkommen!\n#subobj 1\nDie Karawane finden\n\n#subobj 2\nDie wilden Tiere töten\n\n#subobj 3\nDurchsuche die Truhe\n"
	},
	"quest q11j": {
		"ru": "Нездоровая пища\nПосле всего, что произошло около дома дядюшки Рада, ему нельзя показываться хадаганской страже. Поэтому накормить хадаганскую стражу отравленным рагу придется самостоятельно.\n#subobj 1\nПробраться в город\nВ стенах города есть только двое ворот — западные и восточные. Западные находятся дальше от столовой, а восточные лучше охраняются.\n#subobj 2\nДобраться до столовой\nСтоловая городской стражи находится в восточной части города и полна голодных и злых солдат. Лучше не попадаться им на глаза...\n#subobj 3\nПоставить котел\nКотелок с рагу нужно поставить на треножник в столовой.\n",
		"en": "Unhealthy Food\nAfter the events at Uncle Radu's house, he must avoid the Hadagan guards. You will have to deliver the poisoned stew yourself.\n#subobj 1\nGet into the city\n\n#subobj 2\nReach the mess hall\n\n#subobj 3\nPlace the cauldron\n",
		"de": "Ungesundes Essen\nNach den Ereignissen an Onkel Radus Haus darf er den hadaganischen Wachen nicht begegnen. Du musst ihnen den vergifteten Eintopf selbst bringen.\n#subobj 1\nIn die Stadt gelangen\n\n#subobj 2\nDen Speisesaal erreichen\n\n#subobj 3\nDen Kessel aufstellen\n"
	},
	"quest q11k": {
		"ru": "Элементали льда\nВ районе рудников, в заброшенной части, появились элементали льда. Нужно понять причину их появления, а для этого необходимы образцы самих элементалей.\n#subobj 1\nВойти в заброшенные рудники\nВход в заброшенные рудники находится в центре зоны рудников и прикрыт воротами.\n#subobj 2\nСобрать образцы\nДля того чтобы понять причину появления элементалей, необходимо уничтожить нескольких и взять их образцы.\n",
		"en": "Ice Elementals\nIce elementals have appeared in the abandoned part of the mining district. Samples of the elementals are needed to discover why.\n#subobj 1\nEnter the abandoned mines\nThe entrance to the abandoned mines is in the center of the mining district, behind a gate.\n#subobj 2\nGather the samples\nDestroy several elementals and collect samples to discover why they appeared.\n",
		"de": "Eiselementare\nIm verlassenen Teil des Bergbaugebiets sind Eiselementare aufgetaucht. Proben der Elementare sollen helfen, die Ursache zu ermitteln.\n#subobj 1\nDie verlassenen Minen betreten\nDer Eingang zu den verlassenen Minen liegt im Zentrum des Bergbaugebiets hinter einem Tor.\n#subobj 2\nDie Proben sammeln\nVernichte mehrere Elementare und sammle Proben, um die Ursache ihres Auftauchens zu ermitteln.\n"
	},
	"quest q12g": {
		"ru": "Разбойники\nРазбойники расположились в Предгорьях. Поиски магического шара лучше всего продолжить из их лагеря, тем более что они сами звали в гости.\n#subobj 1\nПрокрасться мимо Нового Поселка\nВся юго-восточная часть контролируется стражей Нового Поселка. Не стоит раньше времени устраивать драку с его жителями.\n#subobj 2\nДобраться до лагеря\nЛагерь «вольных охотников» расположен на севере этой местности. Пройти внутрь можно только по мосту.\n#subobj 3\nПеребить гоблинов\nЛюди оставили гоблинов для охраны выхода из лагеря. Необходимо расчистить дорогу.\n",
		"en": "The Bandits\nThe bandits camp in the Foothills. Their camp is the best place to continue searching for the magic orb, especially since they invited you.\n#subobj 1\nSneak past the New Village\n\n#subobj 2\nReach the camp\n\n#subobj 3\nKill the goblins\n",
		"de": "Die Banditen\nDie Banditen lagern im Vorgebirge. Von dort aus lässt sich die Suche nach der magischen Kugel am besten fortsetzen, zumal sie dich eingeladen haben.\n#subobj 1\nAm Neuen Dorf vorbeischleichen\n\n#subobj 2\nDas Lager erreichen\n\n#subobj 3\nDie Goblins töten\n"
	},
	"quest q12h": {
		"ru": "Логово шантажистов\nКак выяснилось из предсмертной записки, караван тети Зары был атакован не зверями, а шантажистами. Кроме того, шантажисты держат в плену одного из караванщиков и скорее всего захотят с его помощью еще сильнее надавить на тетю Зару. Банду шантажистов нужно уничтожить, а караванщика — спасти и привести к тете Заре.\n#subobj  1\nНайти дом шантажистов\nВ записке сказано, что караванщика вначале отведут в один из домов в городе. Нужно пробраться в дом и выяснить, где держат караванщика. Лучше действовать без шума.\n#subobj  2\nПодслушать разговор\nПодслушав разговор шантажистов, можно узнать, где держат караванщика. Главное — не попадаться на глаза.\n#subobj  3\nУбить помощника шантажистов\nНельзя отпускать живым ни одного вымогателя!\n#subobj  4\nОсвободить караванщика\nКараванщика держат где-то на юго-западе за пределами города и наверняка охраняют. Его необходимо освободить.\n#subobj  5\nПривести караванщика к тете Заре\nТеперь остается только довести караванщика до поместья Укрывателя и сдать тете Заре. При этом следует помнить о городских патрулях...\n",
		"en": "The Blackmailers' Lair\nA dying note reveals that blackmailers attacked Aunt Zara's caravan. They also hold a caravan driver prisoner and may use him to demand even more. Destroy the gang, rescue the driver and escort him to Aunt Zara.\n#subobj 1\nFind the blackmailers' house\n\n#subobj 2\nOverhear the conversation\n\n#subobj 3\nKill the blackmailers' accomplice\n\n#subobj 4\nFree the caravan driver\n\n#subobj 5\nEscort the caravan driver to Aunt Zara\n",
		"de": "Das Versteck der Erpresser\nEin Abschiedsbrief verrät, dass Erpresser Tante Zaras Karawane überfielen. Sie halten einen Karawanenführer gefangen und könnten mit ihm weitere Forderungen stellen. Vernichte die Bande, befreie ihn und bring ihn zu Tante Zara.\n#subobj 1\nDas Haus der Erpresser finden\n\n#subobj 2\nDas Gespräch belauschen\n\n#subobj 3\nDen Helfer der Erpresser töten\n\n#subobj 4\nDen Karawanenführer befreien\n\n#subobj 5\nDen Karawanenführer zu Tante Zara bringen\n"
	},
	"quest q12j": {
		"ru": "Штурм\nТеперь, когда большинство хадаганской стражи находится в небоеспособном состоянии, настало время штурма. Пора вернуть замок исконным владельцам!\n#subobj 1\nПрийти на место сбора\nОтряд барона собирается на востоке от крепости.\n#subobj 2\nЗахватить город\nНеобходимо очистить город от хадаганских солдат. Дар-Улгорн должен вернуться под контроль канийцев!\n",
		"en": "The Assault\nMost Hadagan guards are now unfit to fight. It is time to storm the castle and return it to its rightful owners!\n#subobj 1\nGo to the assembly point\n\n#subobj 2\nCapture the city\n",
		"de": "Der Sturmangriff\nDie meisten hadaganischen Wachen sind nun kampfunfähig. Es ist Zeit, die Burg zu stürmen und ihren rechtmäßigen Besitzern zurückzugeben!\n#subobj 1\nZum Sammelpunkt gehen\n\n#subobj 2\nDie Stadt erobern\n"
	},
	"quest q12k": {
		"ru": "Подарок губернатору\nГубернатор Вальрасиан намекнул, что неплохо бы преподнести ему в подарок стрелку мага лесовиков Синего клана. Необходимо раздобыть эту стрелку — немилость губернатора не приведет ни к чему хорошему.\n#subobj 1\nПрийти во владения Синего клана\nЛесовики Синего клана обитают на юго-западе зоны рудников.\n#subobj 2\nНайти лесовика-мага\nВ Синем клане много лесовиков-стрелков, но лесовик-маг, обладатель необходимой стрелки, всего один.\n#subobj 3\nЗабрать стрелку\nЛесовик-маг использует заклинания и не стреляет из трубки. Не стоит надеяться на то, что можно будет подобрать стрелку после выстрела или вытащить ее из доспеха. Ее можно только выкрасть или забрать с трупа.\n",
		"en": "A Gift for the Governor\nGovernor Valrasian has hinted that he would appreciate an arrow from a Blue Clan forester mage. Obtain one: the governor's displeasure would bring nothing good.\n#subobj 1\nGo to the Blue Clan's domain\n\n#subobj 2\nFind the forester mage\n\n#subobj 3\nCollect the arrow\n",
		"de": "Ein Geschenk für den Gouverneur\nGouverneur Valrasian hat angedeutet, dass er sich über einen Pfeil eines Waldmagiers des Blauen Klans freuen würde. Besorge ihn, denn sein Missfallen verheißt nichts Gutes.\n#subobj 1\nZum Gebiet des Blauen Klans gehen\n\n#subobj 2\nDen Waldmagier finden\n\n#subobj 3\nDen Pfeil holen\n"
	},
	"quest q13g": {
		"ru": "Неудачная охота\nПо словам атамана, люди из Нового поселка настолько плотно обложили лагерь разбойников, что у тех практически пропала возможность охотиться. В то же время сами посельчане охотятся даже в тех районах, которые всегда принадлежали разбойникам. Атаман просит отвадить людей от охотничьих мест разбойников.\n#subobj 1\nДобраться до западных Предгорий\nЛюди из нового поселка охотятся в западной части Предгорий.\n#subobj 2\nНайти лагерь охотников\nНаилучшее место для лагеря находится на северо-западе предгорий, у подножия гор.\n#subobj 3\nРазогнать охотников\nОхотники — не воины. Даже если некоторые из них окажут сопротивление, большинство скорее всего разбегутся.\n#subobj 4\nЗабрать добычу\nЕсли побитые охотники остануться еще и без добычи, в следующий раз они хорошо подумают, стоит ли охотиться в этих местах. Да и разбойникам добыча охотников не помешает.\n",
		"en": "An Unsuccessful Hunt\nThe bandit chief says the New Village's people have surrounded his camp so closely that hunting is almost impossible. Meanwhile, the villagers hunt even on traditional bandit grounds. He asks you to drive them away.\n#subobj 1\nReach the western Foothills\n\n#subobj 2\nFind the hunters' camp\n\n#subobj 3\nDrive away the hunters\n\n#subobj 4\nCollect the loot\n",
		"de": "Eine erfolglose Jagd\nLaut dem Banditenhauptmann umstellen die Leute aus dem Neuen Dorf sein Lager so eng, dass kaum noch eine Jagd möglich ist. Zugleich jagen sie sogar in den angestammten Revieren der Banditen. Er bittet dich, sie von dort zu vertreiben.\n#subobj 1\nDas westliche Vorgebirge erreichen\n\n#subobj 2\nDas Lager der Jäger finden\n\n#subobj 3\nDie Jäger vertreiben\n\n#subobj 4\nDie Beute holen\n"
	},
	"quest q13h": {
		"ru": "Пленница\nНевеста Фейруза Алия попалась на воровстве и сейчас сидит в застенках малой крепости в Пустыне некромантов. Вскоре ее должны перевести в общую тюрьму, которая охраняется во много раз лучше. Фейруз просит всех друзей помочь выручить его невесту, пока этого не случилось. Дельце предстоит жаркое...\n#subobj  1\nУбить часового\nВорота крепости охраняет часовой. Необходимо его острожно устранить. В противном случае он поднимет тревогу.\n#subobj  2\nОткрыть ворота\nОстальные участники предприятия ожидают открытия ворот, чтобы ворваться внутрь крепости.\n#subobj  3\nПрорваться в тюрьму\nВ крепости есть еще несколько охранников, так что придется пробиваться с боем. Вход в тюрьму открывается рычагом.\n#subobj  4\nСбежать\nПохоже, к стражникам подошло подкрепление. Самое время уносить ноги!\n",
		"en": "The Captive\nFairuz's fiancée Alia was caught stealing and is being held in the small fortress in the Necromancers' Desert. She will soon be moved to the main prison, which is much more heavily guarded. Fairuz asks his friends to help rescue her before that happens. This will be a dangerous undertaking...\n#subobj 1\nKill the sentry\nA sentry guards the fortress gate. Eliminate him carefully, or he will raise the alarm.\n#subobj 2\nOpen the gate\nThe others are waiting for the gate to open so they can storm the fortress.\n#subobj 3\nBreak into the prison\nSeveral more guards are inside the fortress, so you will have to fight your way through. A lever opens the prison entrance.\n#subobj 4\nEscape\nThe guards seem to have received reinforcements. It is time to get out!\n",
		"de": "Die Gefangene\nFairuz' Verlobte Alia wurde beim Stehlen erwischt und wird in der kleinen Festung in der Wüste der Nekromanten festgehalten. Bald soll sie in das wesentlich besser bewachte Hauptgefängnis verlegt werden. Fairuz bittet seine Freunde, sie vorher zu befreien. Das wird ein gefährliches Unternehmen...\n#subobj 1\nDen Wachposten töten\nEin Wachposten bewacht das Festungstor. Schalte ihn vorsichtig aus, sonst schlägt er Alarm.\n#subobj 2\nDas Tor öffnen\nDie anderen warten darauf, dass sich das Tor öffnet, damit sie die Festung stürmen können.\n#subobj 3\nZum Gefängnis durchbrechen\nIn der Festung stehen weitere Wachen, also musst du dir den Weg freikämpfen. Ein Hebel öffnet den Gefängniseingang.\n#subobj 4\nFliehen\nDie Wachen haben offenbar Verstärkung erhalten. Zeit, zu verschwinden!\n"
	},
	"quest q13j": {
		"ru": "Карта местности\nДля проведения дальнейшей военной кампании снова необходима развединформация. На этот раз ее можно получить только от самих хадаганцев — разгромив их штаб.\n#subobj 1\nНайти штаб\nВременный штаб хадаганских сил находится на юго-востоке местности «двух рек».\n#subobj 2\nЗабрать планы\nХадаганцы еще не знают о падении Дар-Улгорна и не ждут нападения.\n",
		"en": "A Map of the Region\nThe next stage of the military campaign needs fresh intelligence. This time it can only be obtained from the Hadagans themselves by destroying their headquarters.\n#subobj 1\nFind the headquarters\n\n#subobj 2\nCollect the plans\n",
		"de": "Eine Karte der Gegend\nFür den nächsten Feldzug werden neue Aufklärungsdaten gebraucht. Diesmal sind sie nur von den Hadaganern selbst zu beschaffen: Ihr Hauptquartier muss vernichtet werden.\n#subobj 1\nDas Hauptquartier finden\n\n#subobj 2\nDie Pläne holen\n"
	},
	"quest q13k": {
		"ru": "Предводительница\nЛовкач рассказал, что Геральдина подозрительно ведет себя последнее время — где-то пропадает подолгу, не отвечает на вопросы. Выяснить причины столь странного поведения можно, проследив за ней.\n#subobj 1\nПроследить за предводительницей\nГеральдина направляется куда-то на запад, лучше не терять ее из виду.\n#subobj 2\nОстаться незамеченными\nНе следует попадаться атаманше на глаза: она заподозрит предательство — и последний шанс найти магический артефакт будет потерян.\n",
		"en": "The Leader\nDodger says Geraldine has been acting suspiciously: disappearing for long periods and refusing to answer questions. Follow her to discover why.\n#subobj 1\nFollow the leader\n\n#subobj 2\nRemain undetected\n",
		"de": "Die Anführerin\nLaut dem Schlitzohr verhält sich Geraldine verdächtig: Sie verschwindet lange und beantwortet keine Fragen. Beschatte sie, um den Grund herauszufinden.\n#subobj 1\nDer Anführerin folgen\n\n#subobj 2\nUnentdeckt bleiben\n"
	},
	"quest q13oh": {
		"ru": "Тюрьма\nВ одной из камер этой тюрьмы сидит Алия, невеста Фейруза. Необходимо освободить ее и сбежать, пока друзья-воры сдерживают стражу наверху.\n#subobj  1\nПройти в комнату суда\nКомната суда находится между комнатой пыток и камерой смерти.\n#subobj  2\nЗабрать ключ\nКлюч от камер хранится в сундучке судьи, но сам судья, похоже, отошел.\n#subobj  3\nНайти Алию\nАлию посадили в одну из самых дальних камер. Камеру можно открыть только ключом судьи.\n#subobj  4\nПокинуть тюрьму\nБольше здесь делать нечего...\n#subobj  5\nОстаться незамеченным\nСтражники очень осторожны и поднимут тревогу, если заметят, что решетка хоть одной камеры не закрыта.\n\n",
		"en": "The Prison\nAliya, Feyruz's fiancée, is held in one of these cells. Free her and escape while your fellow thieves hold back the guards upstairs.\n#subobj 1\nEnter the judgement chamber\n\n#subobj 2\nTake the key\n\n#subobj 3\nFind Aliya\n\n#subobj 4\nLeave the prison\n\n#subobj 5\nRemain undetected\n",
		"de": "Das Gefängnis\nIn einer dieser Zellen sitzt Aliya, Feyruz' Verlobte. Befreie sie und fliehe, solange die befreundeten Diebe oben die Wachen aufhalten.\n#subobj 1\nDie Gerichtskammer betreten\n\n#subobj 2\nNimm den Schlüssel\n\n#subobj 3\nAliya finden\n\n#subobj 4\nDas Gefängnis verlassen\n\n#subobj 5\nUnentdeckt bleiben\n"
	},
	"quest q14g": {
		"ru": "Оружейный мастер\nМастер из Поселка Бабур должен многое знать о волшебных вещах. Возможно, что он слышал и о магическом шаре. Кроме того, разбойникам нужен новый мастер оружия, а то старый совсем плохой стал. Нужно уговорить или заставить мастера прийти к разбойникам.\n#subobj 1\nПробраться в Поселок\nПоселок — крупнейшее поселение людей, очень хорошо охраняется. Пройти «напролом» не получится, необходимо действовать тихо.\n#subobj 2\nПодбросить записку Бабуру\nЕсли подбросить Бабуру записку с условиями работы на разбойников, то он скорее всего польстится условиями и придет к ним в лагерь сам.\n#subobj 3\nПодбросить записку старосте\nЕсли подбросить старосте записку с условиями работы Бабура на разбойников, то будет скандал, Бабура выгонят из Поселка — и он придет к разбойникам.\n",
		"en": "The Weaponsmith\nBabur, the Village's craftsman, must know much about magical things. Perhaps he has heard of the magic orb. The bandits also need a new weaponsmith, as their old one is failing. Persuade or force Babur to join them.\n#subobj 1\nGet into the Village\n\n#subobj 2\nSlip Babur the note\n\n#subobj 3\nPlant the note for the elder\n",
		"de": "Der Waffenschmied\nBabur, der Handwerker aus dem Dorf, kennt sich mit magischen Dingen aus und könnte von der magischen Kugel gehört haben. Die Banditen brauchen auch einen neuen Waffenschmied, da ihr alter kaum noch kann. Überrede oder zwinge Babur, zu ihnen zu kommen.\n#subobj 1\nIns Dorf gelangen\n\n#subobj 2\nBabur die Nachricht zustecken\n\n#subobj 3\nDem Ältesten die Nachricht unterschieben\n"
	},
	"quest q14h": {
		"ru": "Месть\nУбийцы Фейруза, жениха Алии, живут в поместье на северо-западе окрестностей города. Алия просила помочь ей отомстить за Фейруза. Хоть в поместье и живут опытные воины, Алия надеется застать их врасплох.\n#subobj  1\nДобраться до места встречи\nМесто сбора всех «мстителей» находится у дороги по пути к особняку. Алия с остальными участниками уже будут ждать там.\n#subobj  2\nПодобратся к особняку\nНужно добраться до поместья как можно скорее — только так можно застать обитателей неподготовленными.\n#subobj  3\nУничтожить обитателей особняка\nПришел час расплаты! Никто из причастных к смерти Фейруза не должен спастись.\n#subobj  4\nЗабрать ценности\nПусть при расследовании подумают, что целью нападения была кража, а вовсе не месть. К тому же мертвым убийцам деньги все равно не нужны.\n#subobj  5\nАлия должна выжить\n",
		"en": "Revenge\nThe men who killed Aliya's fiancé Feyruz live in a manor northwest of the city outskirts. Aliya asks for help avenging him. Though they are experienced warriors, she hopes to catch them by surprise.\n#subobj 1\nReach the meeting place\n\n#subobj 2\nApproach the manor\n\n#subobj 3\nKill the manor's inhabitants\n\n#subobj 4\nCollect the valuables\n\n#subobj 5\nAliya must survive\n",
		"de": "Rache\nDie Mörder von Aliyas Verlobtem Feyruz leben im Anwesen im Nordwesten des Stadtumlands. Aliya bittet um Hilfe bei ihrer Rache. Obwohl es erfahrene Krieger sind, hofft sie, sie zu überraschen.\n#subobj 1\nDen Treffpunkt erreichen\n\n#subobj 2\nSich dem Anwesen nähern\n\n#subobj 3\nDie Bewohner des Anwesens töten\n\n#subobj 4\nDie Wertsachen holen\n\n#subobj 5\nAliya muss überleben\n"
	},
	"quest q14j": {
		"ru": "Опасные соседи\nДядюшка Рад рассказал, что в местности двух рек есть область с очень странными обитателями. По слухам эти существа охраняют что-то ценное.\n#subobj 1\nОбследовать странную область\nЗагадочное место находится западнее бывшего хадаганского штаба. В окрестностях обитают опасные существа, по пути следует проявить осторожность.\n",
		"en": "Dangerous Neighbours\nUncle Radu says a part of the Two Rivers region has very strange inhabitants. Rumour has it they guard something valuable.\n#subobj 1\nExplore the strange area\n",
		"de": "Gefährliche Nachbarn\nOnkel Radu erzählt von sehr seltsamen Bewohnern in einem Teil des Zweistromlands. Gerüchten zufolge bewachen sie etwas Wertvolles.\n#subobj 1\nDas seltsame Gebiet erkunden\n"
	},
	"quest q14k": {
		"ru": "Караульный\nЛовкач хочет помочь старому магу. Он знает, что есть караульный, который не раз пропускал мага в шахты. Необходимо встретиться с караульным, для этого нужно оставить ему записку около караульного помещения. \n#subobj 1\nПрийти к караулке\nКараульное помещение находится около ворот в шахты.\n#subobj 2\nОставить записку\nПисьмо караульному можно положить в ящик около караулки.\n",
		"en": "The Sentry\nDodger wants to help the old mage. He knows a sentry who has let the mage into the mines before. Leave the sentry a note by the guardroom to arrange a meeting.\n#subobj 1\nGo to the guardroom\n\n#subobj 2\nLeave the note\n",
		"de": "Der Wachposten\nDas Schlitzohr will dem alten Magier helfen. Es kennt einen Wachposten, der ihn schon öfter in die Minen ließ. Hinterlasse beim Wachraum eine Nachricht, um den Posten zu treffen.\n#subobj 1\nZum Wachraum gehen\n\n#subobj 2\nDie Nachricht hinterlassen\n"
	},
	"quest q15g": {
		"ru": "Засада\nРазбойники планируют проучить жителей Нового поселка — перехватить отряд, идущий к ним из Старого. Атаман просил поучаствовать в деле, ведь среди разбойников осталось очень мало достойных воинов.\n#subobj 1\nПрийти к мосту\nАтака на караван должа произойти в момент, когда отряд будет проходить по мосту и замыкающие воины не смогут помочь передовым.\n#subobj 2\nПеребить воинов\nОтряд должен быть уничтожен, иначе разбойники окажутся в безвыходном положении.\n",
		"en": "The Ambush\nThe bandits plan to teach the New Village a lesson by intercepting a detachment arriving from the Old Village. With few able warriors left in his band, the chief asks you to join the attack.\n#subobj 1\nGo to the bridge\n\n#subobj 2\nKill the warriors\n",
		"de": "Der Hinterhalt\nDie Banditen wollen dem Neuen Dorf eine Lektion erteilen und einen Trupp aus dem Alten Dorf abfangen. Da ihm nur noch wenige fähige Kämpfer bleiben, bittet der Hauptmann dich um Hilfe.\n#subobj 1\nZur Brücke gehen\n\n#subobj 2\nDie Krieger töten\n"
	},
	"quest q15h": {
		"ru": "Последнее Укрытие\nПосле нападения на особняк, в котором жили убийцы Фейруза, Риндейл отказал в своем покровительстве всем участникам. Теперь необходимо искать новое пристанище. Хорошо, что Алия знает одно вполне пригодное местечко.\n#subobj  1\nПроследовать за Алией\nАлия готова показать дорогу к укрытию, нужно лишь держаться поблизости от нее и не подпускать диких зверей.\n#subobj  2\nБр-р...\nГр-р...\n#subobj  3\nОбойти заставу\nЕдинственный путь в западную часть пустыни проходит недалеко от заставы хадаганцев. Нельзя попадаться им на глаза!\n#subobj  4\nНайти Последнее Укрытие\nНовое убежище находится где-то в пещерах, вход в которые — на самом западе пустыни. Алия покажет дорогу.\n#subobj  5\nАлия должна выжить\n",
		"en": "The Last Refuge\nAfter the attack on the manor of Feyruz's killers, Rindale withdrew his protection from everyone involved. A new shelter is needed. Fortunately, Aliya knows a suitable place.\n#subobj 1\nFollow Aliya\n\n#subobj 2\nBrr...\n\n#subobj 3\nBypass the outpost\n\n#subobj 4\nFind the Last Refuge\n\n#subobj 5\nAliya must survive\n",
		"de": "Die Letzte Zuflucht\nNach dem Angriff auf das Anwesen von Feyruz' Mördern entzog Rindale allen Beteiligten seinen Schutz. Eine neue Bleibe muss her. Zum Glück kennt Aliya einen geeigneten Ort.\n#subobj 1\nAliya folgen\n\n#subobj 2\nBrr...\n\n#subobj 3\nDen Vorposten umgehen\n\n#subobj 4\nDie Letzte Zuflucht finden\n\n#subobj 5\nAliya muss überleben\n"
	},
	"quest q15j": {
		"ru": "Переправа\nМестность двух рек имеет важнейшее стратегическое значение. Хадаганцы еще не успели перегруппироваться и восстановить силы после утраты Дар-Улгорна, так что можно попытаться развить успех — захватить переправу.\n#subobj 1\nДобраться до моста\nМесто сбора отряда, который должен захватить переправу, назначено восточнее южного моста.\n#subobj 2\nУстранить часового\nЕсли солдат, следящий за мостом, заметит врагов, он поднимет тревогу — и придется принять бой в неудобном месте.\n#subobj 3\nУничтожить охрану переправы\nПереправа только тогда будет под контролем канийских сил, когда все хадаганские защитники будут мертвы.\n",
		"en": "The Crossing\nThe Two Rivers region is strategically vital. The Hadagans have not yet recovered from losing Dar-Ulgorn. Seize the crossing to press the advantage.\n#subobj 1\nReach the bridge\n\n#subobj 2\nEliminate the sentry\n\n#subobj 3\nDestroy the crossing's guards\n",
		"de": "Der Übergang\nDas Zweistromland ist strategisch entscheidend. Die Hadaganer haben sich vom Verlust Dar-Ulgorns noch nicht erholt. Nutze den Vorteil und erobere den Übergang.\n#subobj 1\nDie Brücke erreichen\n\n#subobj 2\nDen Wachposten beseitigen\n\n#subobj 3\nDie Wachen des Übergangs vernichten\n"
	},
	"quest q15k": {
		"ru": "Пропуск в шахты\nВо время последнего посещения шахт старый маг потерал бумагу с подтверждением того, что он был там. Эта бумага могла бы послужить оправданием мага.\n#subobj 1\nЗабрать ключ\nВ пещере множество дверей, открыть которые можно только специальным ключом, который можно найти в комнате охраны на северо-западе рудников. По пути желательно не попадаться на глаза стражникам шахты — они атакуют всякого, у кого нет пропуска.\n#subobj 2\nПрийти на восточные разработки\nСкорее всего маг потерял бумагу, путешествуя по восточной части шахты, которая давно заброшена.\n#subobj 3\nПроникнуть в запретную часть\nПохоже, пропуск мага потерялся в самой опасной части пещеры.\n#subobj 4\nНайти бумагу\nВременный пропуск в шахты выпал из кармана мага недалеко от большой лужи в восточной части пещеры.\n\n",
		"en": "A Pass for the Mines\nDuring his last visit to the mines, the old mage lost a paper proving that he was there. It could serve as his alibi.\n#subobj 1\nTake the key\n\n#subobj 2\nGo to the eastern workings\n\n#subobj 3\nEnter the forbidden area\n\n#subobj 4\nFind the paper\n",
		"de": "Ein Passierschein für die Minen\nBei seinem letzten Minenbesuch verlor der alte Magier ein Papier, das seinen Aufenthalt belegt. Es könnte ihm als Alibi dienen.\n#subobj 1\nNimm den Schlüssel\n\n#subobj 2\nZu den östlichen Abbaustellen gehen\n\n#subobj 3\nDen verbotenen Bereich betreten\n\n#subobj 4\nDas Papier finden\n"
	},
	"quest q16ag": {
		"ru": "Волшебная игла\nДля того чтобы сделать новые качественные доспехи, Бабуру необходима волшебная игла. Человек, одетый в доспехи, изготовленные с ее помощью, практически неуязвим.\n#subobj 1\nПроникнуть в гробницу\nВход в гробницу находится в пересохшей части русла реки.\n#subobj 2\nЗабрать ключ\nЧтобы пройти в основные помещения, необходим ключ, который лежит в саркофаге на востоке подземелий.\n#subobj 3\nПройти в основные помещения\nДорога к нужному склепу пока недоступна, возможно, стоит исследовать основные помещения.\n#subobj 4\nЗатопить подземелье\nЕсли снять клапан с источника, то в подземелья поступит вода из подземных источников и затопит ловушки на пути к склепу с волшебной иглой.\n#subobj 5\nЗабрать иглу\nВолшебная игла лежит в одном из саркофагов в склепе на востоке подземелий.\n",
		"en": "The Magic Needle\nBabur needs a magic needle to make fine new armour. Anyone wearing armour made with it is almost invulnerable.\n#subobj 1\nEnter the tomb\n\n#subobj 2\nTake the key\n\n#subobj 3\nEnter the main chambers\n\n#subobj 4\nFlood the dungeon\n\n#subobj 5\nCollect the needle\n",
		"de": "Die magische Nadel\nBabur braucht eine magische Nadel, um hochwertige neue Rüstungen zu fertigen. Wer eine solche Rüstung trägt, ist fast unverwundbar.\n#subobj 1\nIn die Gruft eindringen\n\n#subobj 2\nNimm den Schlüssel\n\n#subobj 3\nDie Haupträume betreten\n\n#subobj 4\nDas Verlies fluten\n\n#subobj 5\nDie Nadel holen\n"
	},
	"quest q16g": {
		"ru": "Волшебная игла\nДля того чтобы сделать новые качественные доспехи, Бабуру необходима волшебная игла. Человек, одетый в доспехи, изготовленные с ее помощью, практически неуязвим.\n#subobj 1\nПроникнуть в гробницу\nВход в гробницу находится в пересохшей части русла реки.\n#subobj 2\nЗабрать ключ\nЧтобы пройти в основные помещения, необходим ключ, который лежит в саркофаге на востоке подземелий.\n#subobj 3\nПройти в основные помещения\nДорога к нужному склепу пока недоступна, возможно, стоит исследовать основные помещения.\n#subobj 4\nЗатопить подземелье\nЕсли снять клапан с источника, то в подземелья поступит вода из подземных источников — и затопит ловушки на пути к склепу с волшебной иглой.\n#subobj 5\nЗабрать иглу\nВолшебная игла лежит в одном из саркофагов в склепе на востоке подземелий.\n",
		"en": "The Magic Needle\nBabur needs a magic needle to make fine new armour. Anyone wearing armour made with it is almost invulnerable.\n#subobj 1\nEnter the tomb\n\n#subobj 2\nTake the key\n\n#subobj 3\nEnter the main chambers\n\n#subobj 4\nFlood the dungeon\n\n#subobj 5\nCollect the needle\n",
		"de": "Die magische Nadel\nBabur braucht eine magische Nadel, um hochwertige neue Rüstungen zu fertigen. Wer eine solche Rüstung trägt, ist fast unverwundbar.\n#subobj 1\nIn die Gruft eindringen\n\n#subobj 2\nNimm den Schlüssel\n\n#subobj 3\nDie Haupträume betreten\n\n#subobj 4\nDas Verlies fluten\n\n#subobj 5\nDie Nadel holen\n"
	},
	"quest q16h": {
		"ru": "Перстень Императора\nПодозрительные обитатели Последнего Укрытия, чтобы проверить лояльность, дали задание: принести императорский перстень-печать.\n#subobj  1\nОтыскать сундук с перстнем\nПо словам обитателей Последнего Укрытия, перстень лежит в сундуке, на северо-западе пустыни.\n#subobj  2\nБр-р...\nГр-р...\n#subobj  3\nПроследовать за похитителем\nКакой-то искатель сокровищ уже успел обыскать сундук и завладеть перстнем. Необходимо его догнать!\n#subobj  4\nЗабрать перстень\nПерстень оcтался на теле не слишком удачливого похитителя. Теперь он уже не будет возражать, если забрать у него эту вещицу.\n",
		"en": "The Emperor's Ring\nThe suspicious inhabitants of the Last Refuge demand the imperial signet ring as proof of loyalty.\n#subobj 1\nFind the chest with the ring\n\n#subobj 2\nBrr...\n\n#subobj 3\nFollow the kidnapper\n\n#subobj 4\nCollect the ring\n",
		"de": "Der Ring des Kaisers\nDie misstrauischen Bewohner der Letzten Zuflucht verlangen als Treuebeweis den kaiserlichen Siegelring.\n#subobj 1\nDie Truhe mit dem Ring finden\n\n#subobj 2\nBrr...\n\n#subobj 3\nDem Entführer folgen\n\n#subobj 4\nDen Ring holen\n"
	},
	"quest q16j": {
		"ru": "Древний амулет\nДартас рассказал, что видел вещицу, которая может помочь открыть вход в пещеру в долине двух рек. Это амулет, который нашел староста одной из деревень недалеко от Дар-Леаноса. Сейчас эту деревню заполонили гарпии, и причина скорее всего в амулете.\n#subobj 1\nПрийти в деревню\nРазрушенная деревня, в которой жил староста, нашедший древний амулет, находится западнее города.\n#subobj 2\nЗабрать амулет\nСкорее всего древний амулет и сейчас лежит в сундуке старосты.\n",
		"en": "The Ancient Amulet\nDartas saw an amulet that may open the cave in the Two Rivers valley. A village elder near Dar-Leanos found it. Harpies have since overrun the village, probably because of the amulet.\n#subobj 1\nGo to the village\n\n#subobj 2\nTake the amulet\n",
		"de": "Das alte Amulett\nDartas sah ein Amulett, das den Höhleneingang im Zweistromland öffnen könnte. Der Älteste eines Dorfes bei Dar-Leanos fand es. Inzwischen haben Harpyien das Dorf überrannt, vermutlich wegen des Amuletts.\n#subobj 1\nGehe ins Dorf\n\n#subobj 2\nNimm das Amulett\n"
	},
	"quest q16k": {
		"ru": "Место преступления\nДля того чтобы понять, как именно погиб Бриссен, необходимо изучить место преступления.\n#subobj 1\nНайти место преступления\nРыцарь Бриссен был убит недалеко от поселка лесорубов в окрестностях города Ингоса.\n#subobj 2\nСобрать улики\nНайденные улики могут помочь в расследовании.\n",
		"en": "The Crime Scene\nExamine the crime scene to discover exactly how Brissen died.\n#subobj 1\nFind the crime scene\n\n#subobj 2\nGather evidence\n",
		"de": "Der Tatort\nUntersuche den Tatort, um herauszufinden, wie Brissen ums Leben kam.\n#subobj 1\nDen Tatort finden\n\n#subobj 2\nBeweise sammeln\n"
	},
	"quest q17g": {
		"ru": "Путь к знахарке\nБабур говорит, что единственный известный ему человек, который разбирается в магических предметах на Гипате, — знахарка Эстера. Она наверняка сможет ответить на все вопросы, но для начала нужно пройти к ее жилищу, а путь к нему защищают ловушки! \n#subobj 1\nЗабрать магический ключ \nМагический ключ находится в самой северной части горы, которая разделяет долину на две части, но на пути к ключу расставлена огненная ловушка!\n#subobj 2\nОтключить западные ловушки \nДля того чтобы пройти к следующему алтарю, необходимо отключить западные ловушки. Алтарь, контролирующий их, находится совсем рядом!\n#subobj 3\nОтключить ловушку-молнию \nЛовушка-молния, находящаяся на юго-востоке этой местности, отключается при помощи западного алтаря.\n#subobj 4 \nОтключить восточные ловушки\nАлтарь находится на юго-востоке долины. Следует сохранять осторожность! \n#subobj 5 \nПрийти к знахарке \nТеперь ловушки в восточной части долины отключены — и можно пройти к знахарке. Разве что ее ручные тролли могут этому воспрепятствовать...\n",
		"en": "The Path to the Healer\nBabur says Estera is the only person he knows on Gipath who understands magical objects. She should have answers, but traps guard the path to her home!\n#subobj 1\nCollect the magic key\n\n#subobj 2\nDisable the western traps\n\n#subobj 3\nDisable the lightning trap\n\n#subobj 4\nDisable the eastern traps\n\n#subobj 5\nGo to the healer\n",
		"de": "Der Weg zur Heilerin\nLaut Babur kennt sich auf Gipath nur die Heilerin Estera mit magischen Gegenständen aus. Sie dürfte Antworten haben, doch Fallen sichern den Weg zu ihrem Haus!\n#subobj 1\nDen magischen Schlüssel holen\n\n#subobj 2\nDie westlichen Fallen entschärfen\n\n#subobj 3\nDie Blitzfalle entschärfen\n\n#subobj 4\nDie östlichen Fallen entschärfen\n\n#subobj 5\nZur Heilerin gehen\n"
	},
	"quest q17h": {
		"ru": "Пропавшая в пустыне\nПо словам Алии, в тюрьму она попала вместе со своей верной напарницей Сахилей. Но той удалось сбежать, и теперь она должна быть где-то в пустыне, раз не смогла добраться до Последнего Укрытия. Алия просит узнать, что случилось с ее лучшей подругой.\n#subobj  1\nНайти Сахилю\nЛучшая подруга Алии, которой удалось сбежать из тюрьмы, находится где-то на севере пустыни. По крайней мере на юге ее не нашли.\n#subobj  2\nОбследовать север пустыни\nНа севере есть небольшое достаточно безопасное ущелье. Не исключено, что Сахиля решила переждать некоторое время где-то в тех местах.\n#subobj  3\nОбследовать северо-восток пустыни\nНа северо-востоке пустыни живут несколько людоедов, и стража предпочитает обходить те места стороной. Возможно, Сахиля затаилась где-то там.\n#subobj  4\nДоставить Сахилю в Последнее Укрытие\nСахиля очень ослабла и не сможет добраться сама. Необходимо проводить ее до места.\n#subobj  5\nСахиля должна выжить\n",
		"en": "Lost in the Desert\nAliya was imprisoned with her trusted partner Sahilya, who managed to escape. Since she never reached the Last Refuge, she must still be in the desert. Aliya asks you to find out what happened to her best friend.\n#subobj 1\nFind Sahilya\n\n#subobj 2\nExplore the northern desert\n\n#subobj 3\nExplore the northeastern desert\n\n#subobj 4\nEscort Sahilya to the Last Refuge\n\n#subobj 5\nSahilya must survive\n",
		"de": "In der Wüste verschollen\nAliya kam mit ihrer treuen Gefährtin Sahilya ins Gefängnis. Sahilya konnte fliehen, erreichte aber nie die Letzte Zuflucht und muss noch in der Wüste sein. Aliya bittet dich herauszufinden, was ihrer besten Freundin zustieß.\n#subobj 1\nSahilya finden\n\n#subobj 2\nDen Norden der Wüste erkunden\n\n#subobj 3\nDen Nordosten der Wüste erkunden\n\n#subobj 4\nSahilya zur Letzten Zuflucht bringen\n\n#subobj 5\nSahilya muss überleben\n"
	},
	"quest q17j": {
		"ru": "Конец рабства\nФирез, опасаясь приближения канийцев, решил перевести своих пленников джунов из горной тюрьмы в свой замок. Перехватить конвой — реальный шанс освободить свою семью.\n#subobj 1\nПерехватить конвой\nКонвой будет двигаться от тюрьмы в горах к городу. Лучше всего перехватить его на перекрестке в центре местности.\n#subobj 2\nОсвободить пленников\nНеобходимо уничтожить всех охранников. Джуны безоружны и не смогут помочь своим спасителям.\n#subobj 3\nОтвести джунов в безопасное место\nМестность двух рек находится под контролем канийцев, туда и нужно отвести спасенных джунов.\n#subobj 4\nВсе джуны должны выжить\n",
		"en": "An End to Slavery\nFearing the approaching Kanians, Firez is moving his June prisoners from the mountain prison to his castle. Intercepting the convoy offers a real chance to free your family.\n#subobj 1\nIntercept the convoy\n\n#subobj 2\nFree the prisoners\n\n#subobj 3\nEscort the June to safety\n\n#subobj 4\nAll June must survive\n",
		"de": "Das Ende der Sklaverei\nAus Furcht vor den nahenden Kaniern verlegt Firez seine gefangenen June aus dem Berggefängnis in seine Burg. Den Transport abzufangen bietet eine echte Chance, deine Familie zu befreien.\n#subobj 1\nDen Gefangenentransport abfangen\n\n#subobj 2\nDie Gefangenen befreien\n\n#subobj 3\nDie June in Sicherheit bringen\n\n#subobj 4\nAlle June müssen überleben\n"
	},
	"quest q17k": {
		"ru": "Встреча с Хисом\nХис попросил встречи, для того чтобы предоставить доказательства своей невиновности. Он опасается за свою жизнь и говорит, что ему угрожали, поэтому место встречи назначено в лесу, за пределами города.\n#subobj 1\nПрийти на место встречи\nХис предложил встретиться на поляне к югу от города.\n#subobj 2\nУничтожить засаду\nЭто предательство! Кто-то устроил засаду!\n#subobj 3\nНайти Хиса\nНеобходимо выяснить, почему на месте встречи с Хисом оказалась засада.\n",
		"en": "A Meeting with His\nHis wants to present proof of his innocence. He says his life has been threatened, so he has arranged the meeting in the forest outside the city.\n#subobj 1\nGo to the meeting place\n\n#subobj 2\nDestroy the ambush\n\n#subobj 3\nFind His\n",
		"de": "Ein Treffen mit His\nHis möchte seine Unschuld beweisen. Da er um sein Leben fürchtet und bedroht wurde, soll das Treffen im Wald außerhalb der Stadt stattfinden.\n#subobj 1\nZum Treffpunkt gehen\n\n#subobj 2\nZerschlage den Hinterhalt\n\n#subobj 3\nHis finden\n"
	},
	"quest q17oh": {
		"ru": "Лечебные зелья\nВо время скитаний по пустыне Сахиля потеряла много сил, а раны, нанесенные ей дикими животными, долгое время оставались без внимания. Ей требуется немедленное лечение, и притом самыми действенными средствами.\n#subobj  1\nНайти склад\nСклад с зельями, травами и прочими медикаментами находится на востоке Пустыни Некромантов.\n#subobj  2\nРаздобыть ключ\nВход на склад заперт, но ключ должен быть у одного из стражников.\n#subobj  3\nЗабрать зелье\nЛечебное зелье — в одной из емкостей на складе, его необходимо забрать.\n",
		"en": "Healing Potions\nWandering the desert has exhausted Sahilya. Her wounds from wild animals have long gone untreated. She urgently needs the most effective healing available.\n#subobj 1\nFind the storehouse\n\n#subobj 2\nObtain the key\n\n#subobj 3\nCollect the potion\n",
		"de": "Heiltränke\nDie Wüste hat Sahilya entkräftet. Ihre von wilden Tieren verursachten Wunden blieben lange unbehandelt. Sie braucht dringend die wirksamsten Heilmittel.\n#subobj 1\nDas Lagerhaus finden\n\n#subobj 2\nDen Schlüssel beschaffen\n\n#subobj 3\nDen Trank holen\n"
	},
	"quest q18g": {
		"ru": "Подарок для Айри\nАйри, очаровательная внучка знахарки, мечтает примерить ожерелье, которое носит шаманка пещерных орков. Невозможно отказать себе в радости сделать ей этот подарок, нужно добыть ожерелье.\n#subobj 1\nПробраться в лагерь орков\nЕдинственный свободный тоннель в пещере ведет к жилищу орков.\n#subobj 2\nПолучить ожерелье\nУбить шаманку будет непросто. Намного спокойнее было бы украсть ожерелье.\n#subobj 3\nПокинуть пещеру\nШаманка вскоре обнаружит кражу и поднимет тревогу. Лучше всего убраться подальше к тому времени.\n",
		"en": "A Gift for Airi\nAiri, the healer's charming granddaughter, dreams of wearing the cave orc shamaness's necklace. Giving her this gift would be a delight. Obtain the necklace.\n#subobj 1\nGet into the Orc camp\n\n#subobj 2\nObtain the necklace\n\n#subobj 3\nLeave the cave\n",
		"de": "Ein Geschenk für Airi\nAiri, die bezaubernde Enkelin der Heilerin, träumt von der Halskette der Höhlenork-Schamanin. Es wäre eine Freude, sie ihr zu schenken. Beschaffe die Kette.\n#subobj 1\nGehe in das Lager der Orks\n\n#subobj 2\nDie Halskette beschaffen\n\n#subobj 3\nDie Höhle verlassen\n"
	},
	"quest q18h": {
		"ru": "Исследователи\nХадаганцы много раз уже пытались обследовать пещеры — и вот на этот раз хотят обследовать именно ту, в которой находится Последнее Укрытие, — один из исследователей только что был обнаружен около пещеры!\n#subobj  1\nДогнать разведчика\nНужно перехватить исследователя, пока он не рассказал о своей находке остальным!\n#subobj  2\nВернуться к пещере\nПохоже, разведчик уже успел передать основной группе о своей находке, и теперь к Последнему Укрытию двигается уже целая группа исследователей. С такой толпой лучше не связываться.\n#subobj  3\nУничтожить враждебный отряд\nИсследователи, направляясь в пещеры, ожидали встретить там в худшем случае гигантских крыс, но никак не боеспособный отряд жителей Последнего Укрытия.\n#subobj  4\nУбить разведчика\nХоть хадаганцы уже знают о пещере, разведчика следует проучить.\n",
		"en": "The Explorers\nThe Hadagans have explored caves many times. Now they are targeting the very cave that shelters the Last Refuge: an explorer has just been spotted nearby!\n#subobj 1\nCatch the scout\n\n#subobj 2\nReturn to the cave\n\n#subobj 3\nDestroy the hostile detachment\n\n#subobj 4\nKill the scout\n",
		"de": "Die Forscher\nDie Hadaganer haben schon viele Höhlen erkundet. Nun haben sie es ausgerechnet auf die Höhle der Letzten Zuflucht abgesehen: Ein Forscher wurde ganz in der Nähe entdeckt!\n#subobj 1\nDen Späher einholen\n\n#subobj 2\nZur Höhle zurückkehren\n\n#subobj 3\nDen feindlichen Trupp vernichten\n\n#subobj 4\nDen Späher töten\n"
	},
	"quest q18j": {
		"ru": "Доспехи джунов\nМудрый Туи-Лен смог раскрыть секрет пещеры в долине двух рек — в этом месте джуны спрятали доспехи одного из своих героев, а место заколдовали при помощи древнего амулета. Теперь заклинание снято — и можно забрать доспех.\n#subobj 1\nНайти ключ\nДверь в помещение со складами заперта. Необходимо отыскать ключ, при помощи которого можно открыть дверь.\n#subobj 2\nИспользовать ключ\nДля того чтобы открыть дверь, нужно включить алтарь в северо-западной комнате.\n#subobj 3\nЗабрать доспехи\nДоспехи лежат в саркофаге в комнате на востоке.\n",
		"en": "Joon Armor\nWise Tui-Len has uncovered the secret of the cave in the Valley of Two Rivers. The Joons hid one of their heroes' suits of armor there and enchanted the place using an ancient amulet. The spell has now been lifted, and the armor can be recovered.\n#subobj 1\nFind the key\nThe door to the storerooms is locked. Find the key that opens it.\n#subobj 2\nUse the key\nTo open the door, activate the altar in the northwestern room.\n#subobj 3\nRetrieve the armor\nThe armor lies in a sarcophagus in the eastern room.\n",
		"de": "Die Rüstung der Joon\nDer weise Tui-Len hat das Geheimnis der Höhle im Tal der zwei Flüsse gelüftet. Die Joon versteckten dort die Rüstung eines ihrer Helden und verzauberten den Ort mit einem alten Amulett. Der Zauber ist nun aufgehoben, und die Rüstung kann geborgen werden.\n#subobj 1\nDen Schlüssel finden\nDie Tür zu den Lagerräumen ist verschlossen. Finde den Schlüssel, der sie öffnet.\n#subobj 2\nDen Schlüssel benutzen\nUm die Tür zu öffnen, aktiviere den Altar im nordwestlichen Raum.\n#subobj 3\nDie Rüstung holen\nDie Rüstung liegt in einem Sarkophag im östlichen Raum.\n"
	},
	"quest q18k": {
		"ru": "Предатель\nВ лагере повелителей зверей есть предатель, в этом не может быть сомнений. Можно вычислить его, рассказав всем, что в лесу найден тайник с общей кассой. Тот, кто придет к тайнику, и есть предатель.\n#subobj 1\nВойти в ущелье\nВход в ущелье находится по пути к лагерю Зеленого клана.\n#subobj 2\nНайти тайник\nТайник предателя спрятан в конце ущелья на юго-западе владений Карансула.\n#subobj 3\nЗабрать кассу\nПовелители зверей будут очень благодарны тому, кто вернет их деньги!\n",
		"en": "The Traitor\nThere is certainly a traitor in the beastmasters' camp. Tell everyone that a cache containing the shared funds has been found in the forest. Whoever comes for it is the traitor.\n#subobj 1\nEnter the gorge\n\n#subobj 2\nFind the hiding place\n\n#subobj 3\nCollect the shared funds\n",
		"de": "Der Verräter\nIm Lager der Bestienmeister gibt es zweifellos einen Verräter. Erzähle allen von einem angeblich gefundenen Versteck mit der Gemeinschaftskasse im Wald. Wer dorthin kommt, ist der Verräter.\n#subobj 1\nDie Schlucht betreten\n\n#subobj 2\nFinde das Versteck\n\n#subobj 3\nDie Gemeinschaftskasse holen\n"
	},
	"quest q19g": {
		"ru": "Мертвый город\nЗнахарка Эстера, бабка Айри, отправилась в Мертвый город якобы в поисках говорящего дракона. Ее нужно найти, ведь только она может рассказать о магическом шаре.\n#subobj 1\nВойти в город\nНа страже ворот Мертвого города находится неусыпная стража нежити. Но есть и потайной ход через расщелину на юге гор, которую охраняет элементаль камня. Он медлительный, и его можно обмануть, выманив подальше от ущелья.\n#subobj 2\nПрийти к горе\nОдинокая гора посреди Мертвого города — наиболее примечательное место. Лучше всего начать поиски с нее.\n#subobj 3\nПодняться на гору\nДаже если знахарки нет на вершине горы, оттуда можно будет осмотреть окрестности.\n",
		"en": "The Dead City\nEstera, Airi's grandmother, went to the Dead City, supposedly looking for a talking dragon. Find her: only she can tell you about the magic orb.\n#subobj 1\nEnter the city\n\n#subobj 2\nGo to the mountain\n\n#subobj 3\nClimb the mountain\n",
		"de": "Die Tote Stadt\nEstera, Airis Großmutter, ging angeblich auf der Suche nach einem sprechenden Drachen in die Tote Stadt. Finde sie, denn nur sie weiß über die magische Kugel Bescheid.\n#subobj 1\nGehe in die Stadt\n\n#subobj 2\nZum Berg gehen\n\n#subobj 3\nDen Berg besteigen\n"
	},
	"quest q19h": {
		"ru": "Грязная работа\nХадаганцы знают о пещере, и они потеряли отряд, направлявшийся туда. Для разбирательства будет отправлен новый, намного более сильный отряд, если только не выяснится, что предыдущий отряд уничтожили червелицые.\n#subobj  1\nНайти червелицых\nДля получения тел червелицых, надо найти самих червелицых. Хадаганцы не зря боятся подземных обитателей: превратить «червелицего» в «труп червелицего» — очень непросто. Но, возможно, удастся найти уже мертвых.\n#subobj  2\nНайти тела червелицых\nТрупы червелицых должны быть там же, где их оставил убийца.\n#subobj  3\nЗабрать трупы\nРаботка не из самых приятных, но, если ее не выполнить, Последнее Укрытие будет обречено.\n",
		"en": "Dirty Work\nThe Hadagans know about the cave and have lost a detachment sent there. They will send a much stronger force to investigate, unless it appears that wormfaces destroyed the first one.\n#subobj 1\nFind the wormfaces\n\n#subobj 2\nFind the wormfaces' bodies\n\n#subobj 3\nCollect the bodies\n",
		"de": "Drecksarbeit\nDie Hadaganer kennen die Höhle und haben einen dorthin entsandten Trupp verloren. Zur Untersuchung werden sie eine viel stärkere Einheit schicken, sofern es nicht so aussieht, als hätten Wurmgesichter den ersten Trupp vernichtet.\n#subobj 1\nDie Wurmgesichter finden\n\n#subobj 2\nDie Leichen der Wurmgesichter finden\n\n#subobj 3\nDie Leichen holen\n"
	},
	"quest q19j": {
		"ru": "Безделушки\nТай-Илара просит принести ей ее вещи, которые остались в тюрьме. Невозможно отказать такой красотке...\n#subobj 1\nПробраться в тюрьму\nТюрьма находится высоко в горах на юге территории хадаганцев. Дорога завалена, но в тюрьму можно попасть через портал у подножия горы.\n#subobj 2\nЗабрать вещи\nБезделушки Тай-Илары спрятаны в сундуке недалеко от дома, в котором она находилась под стражей. \n",
		"en": "Trinkets\nTai-Ilara asks you to fetch the belongings she left in prison. How could anyone refuse such a beauty...\n#subobj 1\nGet into the prison\n\n#subobj 2\nCollect the belongings\n",
		"de": "Kleinigkeiten\nTai-Ilara bittet dich, ihre im Gefängnis zurückgebliebenen Sachen zu holen. Wer könnte einer solchen Schönheit etwas abschlagen...\n#subobj 1\nIns Gefängnis gelangen\n\n#subobj 2\nDie Sachen holen\n"
	},
	"quest q19k": {
		"ru": "Материал для ключа\nДля изготовления ключа Ловкачу необходим магический материал, который можно добыть только в самых отдаленных ущельях в горах.\n#subobj 1\nВойти в ущелье\nЧтобы попасть в ущелье, необходимо пройти через ворота на юго-востоке окрестностей города.\n#subobj 2\nПройти ущелье\nПодходящий материал можно найти только в самом конце ущелья.\n#subobj 3\nЗабрать материал\nЛовкач ошибся — материал не обладает магическими свойствами, но в качестве подтверждения образцы все равно нужно взять.\n",
		"en": "Material for the Key\nDodger needs magical material to make the key. It can only be found in the most remote mountain gorges.\n#subobj 1\nEnter the gorge\n\n#subobj 2\nGet through the gorge\n\n#subobj 3\nCollect the material\n",
		"de": "Material für den Schlüssel\nDas Schlitzohr braucht magisches Material für den Schlüssel. Es ist nur in den entlegensten Bergschluchten zu finden.\n#subobj 1\nDie Schlucht betreten\n\n#subobj 2\nDie Schlucht durchqueren\n\n#subobj 3\nDas Material holen\n"
	},
	"quest q1g": {
		"ru": "Стоянка\nЛагерь экспедиции, в который нужно получить донесение, расположен к северо-востоку от места телепортации, за перевалом, на котором располагается заброшенная канийская крепость.\n#subobj 1\nДобраться до моста\nМножество опасностей поджидает путника в этой дикой местности. Разрушенный первый лагерь экспедиции красноречиво напоминает об этом.\n#subobj 2\nПройти к перевалу\nЗа перевалом располагается местность, называемая «Дальние горы». Именно там должен находиться новый лагерь экспедиции.\n",
		"en": "The Expedition Camp\nThe expedition camp where the report must be collected lies northeast of the arrival point, beyond a pass occupied by an abandoned Kanian fortress.\n#subobj 1\nReach the bridge\n\n#subobj 2\nReach the pass\n",
		"de": "Das Expeditionslager\nDas Expeditionslager, in dem der Bericht abzuholen ist, liegt nordöstlich des Ankunftsorts. Der Weg führt über einen Pass mit einer verlassenen kanischen Festung.\n#subobj 1\nDie Brücke erreichen\n\n#subobj 2\nZum Pass gelangen\n"
	},
	"quest q1h": {
		"ru": "Тайное убежище\nВ незнакомом и опасном мире нельзя выжить, оставаясь в одиночестве. Необходимо найти поместье, о котором говорила Кель, в котором можно найти пристанище.\n#subobj  1\nПробраться в город\nБлижайший мост, ведущий в город, охраняется. К счастью, охранники не очень внимательны — и есть шанс проскользнуть незамеченными.\n#subobj  2\nИзбежать встречи с солдатами\nВ сторону портала движется группа воинов. Лучше не попадаться им на глаза.\n#subobj  3\nПрийти к Укрывателю\nОсобняк Укрывателя, как его назвала Кель, находится на севере городка. По дороге следует соблюдать осторожность.",
		"en": "The Secret Shelter\nYou cannot survive alone in this strange and dangerous world. Find the manor Kel mentioned, where you may take shelter.\n#subobj 1\nGet into the city\n\n#subobj 2\nAvoid the soldiers\n\n#subobj 3\nGo to the shelter keeper\n",
		"de": "Das geheime Versteck\nIn dieser fremden und gefährlichen Welt kannst du allein nicht überleben. Finde das Anwesen, das Kel erwähnte und das dir Schutz bieten kann.\n#subobj 1\nIn die Stadt gelangen\n\n#subobj 2\nDen Soldaten ausweichen\n\n#subobj 3\nZum Unterschlupfgeber gehen\n"
	},
	"quest q1j": {
		"ru": "Атака зомби\nКанийский город Дар-Леанос подвергся атаке нежити. Защитники города могут не справиться с угрозой, им необходима помощь.\n#subobj 1\nУничтожить войска нежити\nОжившие мертвецы ничего не боятся и не отступят. Необходимо уничтожить их всех до последнего.\n",
		"en": "The Zombie Attack\nThe Kanian city of Dar-Leanos is under attack by the undead. Its defenders may be overwhelmed and need help.\n#subobj 1\nDestroy the undead forces\n",
		"de": "Der Zombieangriff\nDie kanische Stadt Dar-Leanos wird von Untoten angegriffen. Ihre Verteidiger könnten unterliegen und brauchen Hilfe.\n#subobj 1\nDie Truppen der Untoten vernichten\n"
	},
	"quest q1k": {
		"ru": "Город Ингос\nПоскольку точное расположение магического артефакта неизвестно и его поиски могут затянуться, необходимо позаботиться о жилье и возможности пополнять и ремонтировать обмундирование и оружие. Лучше всего для этих целей подойдет город, который расположен неподалеку.\n#subobj 1\nДобраться до моста\nГород Ингос расположен на восточном берегу озера. Необходимо перебраться на противоположный берег реки, для того чтобы попасть в город.\n#subobj 2\nПрийти в город\nПохоже, провинция не очень хорошо контролируется властями. Дорога к городу может быть небезопасной!\n",
		"en": "The City of Ingos\nThe artifact's exact location is unknown, and the search may take time. You need lodging and somewhere to replenish and repair your equipment. The nearby city is the best place.\n#subobj 1\nReach the bridge\n\n#subobj 2\nCome to the city\n",
		"de": "Die Stadt Ingos\nDer genaue Fundort des magischen Artefakts ist unbekannt, und die Suche könnte dauern. Du brauchst eine Unterkunft und Möglichkeiten, Ausrüstung zu ergänzen und zu reparieren. Die nahe Stadt eignet sich am besten.\n#subobj 1\nDie Brücke erreichen\n\n#subobj 2\nGehe in die Stadt\n"
	},
	"quest q1r": {
		"ru": "Новая земля\nЕдинственный шанс спастись — покинуть эти земли, и как нельзя более кстати для этого появилась хорошая возможность! Нужно только добраться до тайного лагеря, а там уж помогут.\n#subobj 1\nПеребраться через реку\nНа пути к лагерю находится древнее кладбище, следует соблюдать осторожность.\n#subobj 2\nДобраться до лагеря\nЧто ж, помощь близка, осталось совсем немного!\n#subobj 3\nОткрыть сундук\nЛагерь подвергся нападению гарпии — все сожжено, и никого не осталось в живых. Тем не менее стоит попытаться обыскать то, что осталось. Главное при этом гарпии не попасться...\n#subobj 4\nВключить телепорт\nНевероятная находка — ключ от телепорта — поможет покинуть эти земли.\n#subobj 5\nЗайти в портал\nСейчас уже, наверное, стража повсюду ищет беглеца, так что лучше не медлить.\n",
		"en": "A New Land\nLeaving these lands is the only hope of escape, and a timely opportunity has appeared! Reach the secret camp; help will be waiting there.\n#subobj 1\nCross the river\n\n#subobj 2\nReach the camp\n\n#subobj 3\nOpen the coffer\n\n#subobj 4\nActivate the teleporter\n\n#subobj 5\nEnter the portal\n",
		"de": "Ein neues Land\nDiese Länder zu verlassen ist die einzige Rettung, und gerade bietet sich eine günstige Gelegenheit! Erreiche das geheime Lager; dort wird man dir helfen.\n#subobj 1\nDen Fluss überqueren\n\n#subobj 2\nDas Lager erreichen\n\n#subobj 3\nÖffne die Truhe\n\n#subobj 4\nDen Teleporter aktivieren\n\n#subobj 5\nDas Portal betreten\n"
	},
	"quest q20g": {
		"ru": "Болотный цветок\nЧтобы знахарка быстрее вернулась домой и смогла помочь в поисках магического шара, необходимо принести ей цветок с болот, обладающий волшебными свойствами.\n#subobj 1\nДобраться до центра болот\nЦветок, необходимый знахарке, может вырасти только в самых гиблых местах.\n#subobj 2\nСорвать цветок\nНе стоит забывать, что цветок обладает волшебными свойствами, так что могут быть сюрпризы...\n",
		"en": "The Marsh Flower\nBring the healer a magical marsh flower so she can return home sooner and help you search for the magic orb.\n#subobj 1\nReach the centre of the marsh\n\n#subobj 2\nPick the flower\n",
		"de": "Die Sumpfblume\nBringe der Heilerin eine magische Sumpfblume, damit sie bald heimkehren und bei der Suche nach der magischen Kugel helfen kann.\n#subobj 1\nDas Zentrum des Sumpfs erreichen\n\n#subobj 2\nDie Blume pflücken\n"
	},
	"quest q20h": {
		"ru": "Древний договор\nОдин из исследователей вторгся в пещеру и атаковал ее обитателей. Несколько червелицых уже убиты, и остальные просят отомстить некроманту.\n#subobj  1\nНайти некроманта\nНекромант-исследователь зашел в пещеру через западный вход.\n#subobj  2\nУбить некроманта\nНекромант должен быть убит.\n",
		"en": "The Ancient Pact\nAn explorer invaded the cave and attacked its inhabitants. Several wormfaces are dead; the survivors ask you to take revenge on the necromancer.\n#subobj 1\nFind the necromancer\n\n#subobj 2\nKill the necromancer\n",
		"de": "Der alte Pakt\nEin Forscher drang in die Höhle ein und griff ihre Bewohner an. Mehrere Wurmgesichter sind tot. Die Überlebenden bitten dich, sich am Nekromanten zu rächen.\n#subobj 1\nDen Nekromanten finden\n\n#subobj 2\nDen Nekromanten töten\n"
	},
	"quest q20j": {
		"ru": "Альянс\nАрмия Фиреза очень сильна, и идти на штурм его крепости, располагая только канийскими войсками, слишком рискованно. Туи-Лен знает способ подчинения диких существ. Если удастся получить себе в помощь нескольких сильных монстров, можно будет атаковать последний оплот врага.\n#subobj 1\nПодчинить циклопа\nУчастие циклопа в бою на стороне канийцев может решить исход сражения. Для того чтобы подчинить циклопа, достаточно приблизиться к нему с амулетом подчинения.\n#subobj 2\nПодчинить дракона\nДракон может внести неоценимый вклад в удачный исход битвы. Для того чтобы подчинить дракона, достаточно приблизиться к нему с амулетом подчинения.\n",
		"en": "The Alliance\nFirez's army is too strong to attack with Kanian troops alone. Tui-Len knows how to command wild creatures. Recruiting powerful monsters could make an assault on the enemy's last stronghold possible.\n#subobj 1\nSubjugate the cyclops\n\n#subobj 2\nSubjugate the dragon\n",
		"de": "Das Bündnis\nFirez' Armee ist zu stark für einen Angriff allein mit kanischen Truppen. Tui-Len weiß, wie man wilde Kreaturen unterwirft. Mit mächtigen Monstern als Verbündeten könnte der Angriff auf die letzte feindliche Bastion gelingen.\n#subobj 1\nDen Zyklopen unterwerfen\n\n#subobj 2\nDen Drachen unterwerfen\n"
	},
	"quest q20k": {
		"ru": "Тайные ворота\nМагический артефакт, о котором говорил Великий маг Тка-Рик, должен быть в пещере за Ледяной пустыней. По крайней мере в этом уверен Старый маг.\n#subobj 1\nПрийти ко входу в пещеру\nВход в пещеру находится на западе Ледяной пустыни.\n#subobj 2\nОткрыть вход!\nЧтобы открыть вход, нужно воспользоваться ключом, который сделал Ловкач.\n",
		"en": "The Secret Gates\nThe artifact mentioned by the Great Mage Tka-Rik should be in a cave beyond the Ice Desert. At least, the Old Mage is certain of it.\n#subobj 1\nGo to the cave entrance\n\n#subobj 2\nOpen the entrance!\n",
		"de": "Die geheimen Tore\nDas vom Großen Magier Tka-Rik erwähnte Artefakt müsste in einer Höhle hinter der Eiswüste liegen. Dessen ist sich zumindest der Alte Magier sicher.\n#subobj 1\nZum Höhleneingang gehen\n\n#subobj 2\nDen Eingang öffnen!\n"
	},
	"quest q21g": {
		"ru": "Возвращение знахарки\nХоть Эстера и отказывается от помощи, все же необходимо ее сопроводить хотя бы через территорию Мертвого города.\n#subobj 1\nПрийти к воротам\nВидимо старость дает себя знать — Эстера хочет идти напролом через главные ворота, несмотря на то что их охраняет самая сильная нежить.\n#subobj 2\nВыждать\nПохоже, что у Эстеры был заготовлен небольшой сюрприз... Нужно немного выждать.\n#subobj 3\nУничтожить всю охрану\nТеперь нужно только добить остатки охраны ворот — и можно идти дальше.\n#subobj 4\nПокинуть местность\nЗнахарку нужно сопроводить до окраины этой местности, остальной путь она пройдет сама.\n#subobj 5\nЭстера должна выжить\nБез знахарки поиски шара обречены на провал.\n",
		"en": "The Healer's Return\nAlthough Estera refuses help, escort her at least through the Dead City.\n#subobj 1\nGo to the gates\n\n#subobj 2\nWait\n\n#subobj 3\nEliminate all guards\n\n#subobj 4\nLeave the area\n\n#subobj 5\nEstera must survive\n",
		"de": "Die Rückkehr der Heilerin\nObwohl Estera Hilfe ablehnt, solltest du sie zumindest durch die Tote Stadt begleiten.\n#subobj 1\nZum Tor gehen\n\n#subobj 2\nAbwarten\n\n#subobj 3\nAlle Wachen beseitigen\n\n#subobj 4\nDas Gebiet verlassen\n\n#subobj 5\nEstera muss überleben\n"
	},
	"quest q21h": {
		"ru": "Старый некромант\nВ городе Суслагер живет некромант, который пытается подсидеть возлюбленного купчихи Зары в гильдии некромантов. Если испортить его опыты, можно рассчитывать на благодарность купчихи. Материальную, разумеется...\n#subobj  1\nНайти поместье некроманта\nДом старого некроманта расположен в северной части города.\n#subobj  2\nОживить зомби\nСвитком Зары можно оживить труп, над которым проводит опыты некромант. А поскольку в городе запрещены любые подобные испытания, некроманта ждет тяжелое наказание.\n",
		"en": "The Old Necromancer\nA necromancer in Suslanger is trying to undermine merchant Zara's lover in the necromancers' guild. Ruining his experiments should earn her gratitude, in material form, of course...\n#subobj 1\nFind the necromancer's manor\n\n#subobj 2\nRaise the zombies\n",
		"de": "Der alte Nekromant\nEin Nekromant in Suslanger versucht, den Geliebten der Händlerin Zara in der Nekromantengilde zu verdrängen. Wer seine Versuche vereitelt, darf auf ihre Dankbarkeit hoffen, natürlich in materieller Form...\n#subobj 1\nDas Anwesen des Nekromanten finden\n\n#subobj 2\nDie Zombies erwecken\n"
	},
	"quest q21j": {
		"ru": "Цитадель\nТеперь, когда канийская армия достаточно сильна, появилась возможность раз и навсегда установить мир и порядок на аллоде. Для этого нужно разгромить армию Фиреза и захватить его замок.\n#subobj 1\nУничтожить армию зла\nФирез превратил все население города в нежить и выставил ее на бой. Армия Фиреза должна быть уничтожена!\n#subobj 2\nПрорваться во дворец\nФирез укрылся в своем дворце! В городе еще много противников, прорваться будет непросто.\n",
		"en": "The Citadel\nThe Kanian army is now strong enough to secure lasting peace on the allod. Defeat Firez's army and capture his castle.\n#subobj 1\nDestroy the army of evil\n\n#subobj 2\nFight your way into the palace\n",
		"de": "Die Zitadelle\nDie kanische Armee ist nun stark genug, dauerhaft Frieden auf dem Allod zu schaffen. Schlage Firez' Armee und erobere seine Burg.\n#subobj 1\nDie Armee des Bösen vernichten\n\n#subobj 2\nIn den Palast vordringen\n"
	},
	"quest q21k": {
		"ru": "Портал\nОказывается, магический артефакт, который почувствовал Тка-Рик, — это Портал на другие земли. Нельзя возвращаться с пустыми руками, нужно хотя бы узнать, куда ведет этот портал.\n#subobj 1\nНайти ключ от ворот\nДля того чтобы пройти в комнаты портала, нужен ключ.\n#subobj 2\nЗабрать ключ телепорта\nКлюч телепорта должен быть в одной из комнат обслуживания портала. Без него не получится включить портал.\n#subobj 3\nВключить портал\nЭлемент управления порталом находится недалеко от самого портала.\n#subobj 4\nВойти в портал\nУзнать, что находится по другую сторону портала, можно, только войдя в него.\n",
		"en": "The Portal\nThe artifact Tka-Rik sensed is a portal to other lands. You cannot return empty-handed: at least discover where it leads.\n#subobj 1\nFind the gate key\n\n#subobj 2\nCollect the teleporter key\n\n#subobj 3\nActivate the portal\n\n#subobj 4\nEnter the portal\n",
		"de": "Das Portal\nDas von Tka-Rik gespürte Artefakt ist ein Portal in andere Länder. Kehre nicht mit leeren Händen zurück: Finde wenigstens heraus, wohin es führt.\n#subobj 1\nDen Torschlüssel finden\n\n#subobj 2\nDen Teleporterschlüssel holen\n\n#subobj 3\nDas Portal aktivieren\n\n#subobj 4\nGehe durch das Portal\n"
	},
	"quest q21oh": {
		"ru": "Тайник\nУслуга за услугу. Сахиля согласилась помочь достать хадаганские документы для вступления в армию, а взамен просит вернуть один из двух ее мешков с наворованным добром, которые она спрятала в пустыне.\n#subobj  1\nПрийти к ущелью\nОдно из хранилищ Сахили спрятано в ущелье на юго-западе...\n#subobj  2\nПопасть на островок\nВторое хранилище находится на небольшом островке на юге.\n#subobj  3\nУбить людоеда\nПроход в ущелье преградил людоед! Чтобы достать вещи Сахили, нужно его прикончить.\n#subobj  4\nУничтожить тролля\nПосреди островка расположился черный тролль. Обойти его не удастся, поэтому придется его убить.\n#subobj  5\nЗабрать вещи из тайника\nТайник в самом конце ущелья, осталось всего пара шагов!\n#subobj  6\nЗабрать вещи из хранилища\nХранилище находится в северной части островка, и путь к нему открыт!\n",
		"en": "The Cache\nA favour for a favour: Sahilya will help obtain Hadagan enlistment papers if you retrieve one of her two bags of stolen goods hidden in the desert.\n#subobj 1\nGo to the gorge\n\n#subobj 2\nReach the islet\n\n#subobj 3\nKill the ogre\n\n#subobj 4\nKill the troll\n\n#subobj 5\nCollect the goods from the cache\n\n#subobj 6\nCollect the goods from storage\n",
		"de": "Das Versteck\nEin Gefallen für einen Gefallen: Sahilya hilft dir, hadaganische Rekrutierungspapiere zu beschaffen. Dafür sollst du einen ihrer beiden in der Wüste versteckten Beutel mit Diebesgut zurückbringen.\n#subobj 1\nZur Schlucht gehen\n\n#subobj 2\nDie kleine Insel erreichen\n\n#subobj 3\nDen Oger töten\n\n#subobj 4\nDen Troll töten\n\n#subobj 5\nDie Sachen aus dem Versteck holen\n\n#subobj 6\nDie Sachen aus dem Lager holen\n"
	},
	"quest q22g": {
		"ru": "Магический шар\nВеликому магу Тка-Рику нужен магический шар, для того чтобы отыскать Джигран. Недавно шар был похищен островными орками у знахарки Эстеры, и теперь его можно добыть, только прорвавшись через их владения. Но, чтобы пробраться на острова, нужно опустить мосты, а сделать это можно только при помощи особой шестеренки.\n#subobj 1\nПрийти на гору Совета\nК счастью, островные орки иногда выходят на материк, на гору Совета, для принятия важных решений и обязательно берут с собой шестеренку от мостов.\n#subobj 2\nРаздобыть шестеренку\nБез шестеренки не получится пробраться на острова орков, а значит, и найти магический шар.\n#subobj 3\nНайти магический шар\nОрки поместили магический шар на его старый пьедестал на одном из южных островов.\n#subobj 4\nЗабрать магический шар\nАртефакт хорошо охраняется, забрать его по-тихому скорее всего не получится...\n",
		"en": "The Magic Orb\nThe Great Mage Tka-Rik needs the magic orb to locate Jigran. Island orcs recently stole it from Estera. Retrieving it means fighting through their lands. To reach the islands, lower the bridges using a special gear.\n#subobj 1\nGo to Council Mountain\n\n#subobj 2\nObtain the gear\n\n#subobj 3\nFind the magic orb\n\n#subobj 4\nCollect the magic orb\n",
		"de": "Die magische Kugel\nDer Große Magier Tka-Rik braucht die magische Kugel, um Jigran zu finden. Inselorks haben sie kürzlich Estera gestohlen. Um sie zurückzuholen, musst du durch ihr Gebiet. Für den Zugang zu den Inseln sind die Brücken mit einem besonderen Zahnrad zu senken.\n#subobj 1\nZum Ratsberg gehen\n\n#subobj 2\nDas Zahnrad beschaffen\n\n#subobj 3\nDie magische Kugel finden\n\n#subobj 4\nDie magische Kugel holen\n"
	},
	"quest q22h": {
		"ru": "Жрец Тишины\nВо время недавнего вторжения в пещеры червелицых хадаганцы пленили их жреца. Сейчас жрец сидит в одной из камер в крепости некромантов, где его будут пытать и проводить опыты над ним.\n#subobj  1\nНайти камеру червелицего\nВ крепости есть трое ворот, хуже всего охраняются восточные, но камера, в которой держат червелицего, дальше всего от них — около северо-западной стены города.\n#subobj  2\nОсвободить червелицего\nДля того чтобы поднять решетку камеры, не нужны ни ключи, ни отмычки.\n#subobj  3\nОтвести червелицего к пещерам\nЧервелицый, никогда ранее не выходивший на поверхность, не сможет найти вход в подземелья самостоятельно.\n#subobj  3\nЖрец червелицых должен выжить.\n",
		"en": "The Priest of Silence\nDuring their recent invasion of the wormface caves, the Hadagans captured a priest. He is imprisoned in the necromancers' fortress, awaiting torture and experiments.\n#subobj 1\nFind the wormface's cell\n\n#subobj 2\nFree the wormface\n\n#subobj 3\nEscort the wormface to the caves\n\n#subobj 3\nThe wormface priest must survive\n",
		"de": "Der Priester der Stille\nBeim jüngsten Einfall in die Höhlen der Wurmgesichter nahmen die Hadaganer einen Priester gefangen. Er sitzt in der Nekromantenfestung, wo ihm Folter und Experimente drohen.\n#subobj 1\nDie Zelle des Wurmgesichts finden\n\n#subobj 2\nDas Wurmgesicht befreien\n\n#subobj 3\nDas Wurmgesicht zu den Höhlen bringen\n\n#subobj 3\nDer Priester der Wurmgesichter muss überleben\n"
	},
	"quest q22j": {
		"ru": "Фирез\nФирез должен заплатить за все свои преступления! Но для начала нужно отключить ловушку, за которой он спрятался.\n#subobj 1\nОтключить первый управляющий элемент\n#subobj 2\nОтключить второй управляющий элемент\n#subobj 3\nОтключить третий управляющий элемент\n#subobj 4\nОтключить четвертый управляющий элемент\n#subobj 5\nУбить Фиреза\nЛовушка отключена! Теперь Фирез находится в пределах досягаемости, но он опасный противник. Возможно, телепортационные площадки по углам сокровищницы и магические статуи львов помогут с ним справиться...\n",
		"en": "Firez\nFirez must pay for his crimes! First, disable the trap behind which he is hiding.\n#subobj 1\nDisable the first control element\n\n#subobj 2\nDisable the second control element\n\n#subobj 3\nDisable the third control element\n\n#subobj 4\nDisable the fourth control element\n\n#subobj 5\nKill Firez\n",
		"de": "Firez\nFirez muss für seine Verbrechen bezahlen! Schalte zuerst die Falle aus, hinter der er sich versteckt.\n#subobj 1\nDas erste Steuerelement abschalten\n\n#subobj 2\nDas zweite Steuerelement abschalten\n\n#subobj 3\nDas dritte Steuerelement abschalten\n\n#subobj 4\nDas vierte Steuerelement abschalten\n\n#subobj 5\nFirez töten\n"
	},
	"quest q22oh": {
		"ru": "Донесение\nДля того чтобы узнать о событиях, произошедших в разгромленном поместье ученых, и разобраться, куда делся краснокожий юноша, необходимо раздобыть донесение некромантов.\n#subobj  1\nПробраться в цитадель\nЦитадель — самое защищенное место во всем городе некромантов, находится в самом центре поселения.\n#subobj  2\nДобыть донесение\nДонесение о нападении Ужаса на поместье ученых лежит в сундуке в самой северной части цитадели.\n",
		"en": "The Report\nObtain the necromancers' report to learn what happened at the ruined scholars' manor and discover where the red-skinned youth went.\n#subobj 1\nGet into the citadel\n\n#subobj 2\nObtain the report\n",
		"de": "Der Bericht\nBeschaffe den Bericht der Nekromanten, um die Ereignisse im verwüsteten Gelehrtenanwesen aufzuklären und herauszufinden, wohin der rothäutige Jüngling verschwunden ist.\n#subobj 1\nIn die Zitadelle gelangen\n\n#subobj 2\nDen Bericht beschaffen\n"
	},
	"quest q23g": {
		"ru": "Оружие Избранного\nСтароста и воевода Поселка отобрали у Бабура оружие Избранного — бронзовый кинжал. Этот предмет дорог Бабуру как память о единственном друге. Если вернуть ему кинжал, он изготовит ключ, при помощи которого можно будет открыть ворота в Средних горах.\n#subobj 1\nПробраться через мосты\nЕдинственный путь к священным местам, в которых появился Избранный, проходит севернее болотистой местности через два моста.\n#subobj 2\nПрийти в священные Развалины\nРазвалины находятся на высоком обрыве на западе этой местности. Подступы к этому месту хорошо охраняются.\n#subobj 3\nЗабрать кинжал\nКинжал Избранного вместе с другими предметами, принадлежавшими ему, хранится в сундуке в Священных Развалинах!\n",
		"en": "The Chosen One's Weapon\nThe Village elder and warlord confiscated the Chosen One's bronze dagger from Babur. It is a treasured reminder of his only friend. If you return it, Babur will make a key for the gates in the Middle Mountains.\n#subobj 1\nGet across the bridges\n\n#subobj 2\nGo to the sacred ruins\n\n#subobj 3\nCollect the dagger\n",
		"de": "Die Waffe des Auserwählten\nDer Dorfälteste und der Heerführer nahmen Babur den Bronzedolch des Auserwählten ab. Er erinnert ihn an seinen einzigen Freund. Bring ihn zurück, dann fertigt Babur einen Schlüssel für die Tore im Mittleren Gebirge.\n#subobj 1\nÜber die Brücken gelangen\n\n#subobj 2\nZu den heiligen Ruinen gehen\n\n#subobj 3\nDen Dolch holen\n"
	},
	"quest q23h": {
		"ru": "Северная крепость\nДля вступления в ряды хадаганской армии необходимо прийти в Северную крепость — место подбора и тренировки новобранцев.\n#subobj  1\nДобраться до Крепости\nДорога к крепости охраняется солдатами, но на людей с такими документами, какие сделала Сахиля, стража не обратит внимания.\n",
		"en": "The Northern Fortress\nTo join the Hadagan army, report to the Northern Fortress, where recruits are selected and trained.\n#subobj 1\nReach the fortress\n",
		"de": "Die Nordfestung\nMelde dich in der Nordfestung, um in die hadaganische Armee einzutreten. Dort werden Rekruten ausgewählt und ausgebildet.\n#subobj 1\nDie Festung erreichen\n"
	},
	"quest q24g": {
		"ru": "Завтрак людоеда\nОстровные орки, взявшие в плен Бабура во время дерзкого нападения на лагерь вольных охотников, решили преподнести его в подарок соседнему племени людоедов. Подобные подарки довольно быстро находят место в животах людоедов, а кроме Бабура, никто не сможет сделать ключ от ворот в Средних горах.\n#subobj 1\nПрийти в стойбище людоедов\nЛюдоеды обитают на полуострове на востоке местности.\n#subobj 2\nРаздобыть первый ключ\nЧтобы открыть решетку в яме, нужны два ключа. Один из ключей лежит в сундуке вождя людоедов, жилище которого расположено на самом высоком месте в стойбище.\n#subobj 3\nДостать второй ключ\nВторой ключ держит у себя старейшина людоедов который живет на севере полуострова.\n#subobj 4\nОсвободить мастера\nБабура вместе с другими потенциальными блюдами людоедов, держат в небольшой яме посреди лагеря.\n#subobj 5\nПроводить Бабура\nПо пути к лагерю может встретиться множество опасностей.\n#subobj 6\nБабур должен выжить\n",
		"en": "The Ogre's Breakfast\nThe island orcs who captured Babur in their raid on the free hunters' camp have given him to a neighbouring ogre tribe. Such gifts soon end up in ogres' stomachs, and only Babur can make the key to the gates in the Middle Mountains.\n#subobj 1\nGo to the ogres' camp\n\n#subobj 2\nObtain the first key\n\n#subobj 3\nObtain the second key\n\n#subobj 4\nFree the craftsman\n\n#subobj 5\nEscort Babur\n\n#subobj 6\nBabur must survive\n",
		"de": "Das Frühstück des Ogers\nDie Inselorks haben Babur beim Überfall auf das Lager der freien Jäger gefangen und wollen ihn den benachbarten Ogern schenken. Solche Geschenke landen schnell im Magen, und nur Babur kann den Schlüssel zu den Toren im Mittleren Gebirge anfertigen.\n#subobj 1\nZum Lager der Oger gehen\n\n#subobj 2\nDen ersten Schlüssel beschaffen\n\n#subobj 3\nDen zweiten Schlüssel beschaffen\n\n#subobj 4\nDen Handwerker befreien\n\n#subobj 5\nBabur begleiten\n\n#subobj 6\nBabur muss überleben\n"
	},
	"quest q24h": {
		"ru": "Каньон Смерти\nДля того чтобы доказать свою преданность Хадаганской Империи в лице сержанта Зайрака, необходимо обыскать три ущелья в каньоне и уничтожить всех, кого удастся там найти.\n#subobj  1\nОбыскать северное ущелье\nЭто ущелье — ближайшее по дороге из Северной крепости в Южную.\n#subobj  2\nУничтожить рабов\nРабы, спрятавшиеся в ущелье, — убийцы и воры. Их необходимо уничтожить.\n#subobj  3\nОбыскать южное ущелье\nЮжное ущелье — крупнейшее в каньоне. Отличное место для того, чтобы спрятаться...\n#subobj  4\nПеребить всех рабов\nНа счету тех, кто спрятался тут, многие жизни мирных людей.\n#subobj  5\nОбыскать западное ущелье\nЗападное ущелье расположено ближе всего к Южной крепости. Вряд ли там кто-нибудь прячется, но проверить надо.\n",
		"en": "Death Canyon\nProve your loyalty to the Hadagan Empire and Sergeant Zayrak: search the canyon's three gorges and destroy everyone you find.\n#subobj 1\nSearch the northern gorge\n\n#subobj 2\nKill the slaves\n\n#subobj 3\nSearch the southern gorge\n\n#subobj 4\nKill all the slaves\n\n#subobj 5\nSearch the western gorge\n",
		"de": "Die Todesschlucht\nBeweise Sergeant Zayrak deine Treue zum hadaganischen Imperium: Durchsuche die drei Schluchten des Canyons und vernichte alle, die du dort findest.\n#subobj 1\nDie nördliche Schlucht durchsuchen\n\n#subobj 2\nDie Sklaven töten\n\n#subobj 3\nDie südliche Schlucht durchsuchen\n\n#subobj 4\nAlle Sklaven töten\n\n#subobj 5\nDie westliche Schlucht durchsuchen\n"
	},
	"quest q25g": {
		"ru": "Судный День\nУ атамана появился новый план. Если все сделать как надо, люди поселка надолго покинут предгорья.\n#subobj 1\nПробраться в новый поселок\nВ новом поселке трое ворот. Пробиться можно через любые, но удобнее всего через западные.\n#subobj 2\nВключить пирамиду\nОрки, жившие в предгорьях, передали ключ от магической пирамиды. Если при помощи этого ключа настроить волшебный алтарь, магическая пирамида снова заработает, а нацелена она на людей!\n#subobj 3\nПокинуть зону действия пирамиды\nМагической пирамиде все равно, кого поджарить молнией — лишь бы человеком был. Кроме того, неизвестно, какой именно эффект она окажет на людей, ведь ее столько раз перенастраивали...\n#subobj 4\nВыждать\nПока магическая пирамида работает, лучше держаться от нее подальше.\n#subobj 5\nДобить охрану\nВозможно, кто-то из людей все еще выжил, а пирамида уже разрядилась. Объединенные силы орков и вольных охотников собрались около восточных ворот и вот-вот нанесут удар. Необходимо поддержать их!\n",
		"en": "Judgement Day\nThe bandit chief has a new plan. If it succeeds, the villagers will leave the Foothills for a long time.\n#subobj 1\nGet into the New Village\n\n#subobj 2\nActivate the pyramid\n\n#subobj 3\nLeave the pyramid's area of effect\n\n#subobj 4\nWait\n\n#subobj 5\nFinish off the guards\n",
		"de": "Der Tag des Gerichts\nDer Banditenhauptmann hat einen neuen Plan. Gelingt er, werden die Dorfbewohner das Vorgebirge für lange Zeit verlassen.\n#subobj 1\nIns Neue Dorf gelangen\n\n#subobj 2\nDie Pyramide aktivieren\n\n#subobj 3\nDen Wirkungsbereich der Pyramide verlassen\n\n#subobj 4\nAbwarten\n\n#subobj 5\nDie übrigen Wachen beseitigen\n"
	},
	"quest q26g": {
		"ru": "Заброшенная обсерватория\nДля того чтобы узнать, как починить магический шар, необходимо отыскать в заброшенной канийской обсерватории «книгу знаний».\n#subobj 1\nПробраться к ущелью\nПуть в долину, в которой находится обсерватория, проходит по ущелью, которое начинается севернее места обитания лесных ящеров.\n#subobj 2\nОткрыть первые ворота\nПри помощи ключа, который сделал Бабур, можно открыть ворота, закрывающие дорогу в горах.\n#subobj 3\nОткрыть вторые ворота\nВторые ворота находятся в конце ущелья. На пути к воротам могут встретиться мистические горные ящеры. Они намного опаснее своих лесных и озерных собратьев. Лучше избегать лишних столкновений с ними.\n#subobj 4\nПрийти в обсерваторию\nОбсерватория расположена на востоке долины.\n#subobj 5\nОбыскать обсерваторию\nВ сундуке в обсерватории должна быть книга, в которой рассказывается о восстановлении энергии в магических предметах.\n",
		"en": "The Abandoned Observatory\nFind the Book of Knowledge in the abandoned Kanian observatory to learn how to repair the magic orb.\n#subobj 1\nReach the gorge\n\n#subobj 2\nOpen the first gates\n\n#subobj 3\nOpen the second gates\n\n#subobj 4\nGo to the observatory\n\n#subobj 5\nSearch the observatory\n",
		"de": "Das verlassene Observatorium\nFinde das Buch des Wissens im verlassenen kanischen Observatorium, um zu erfahren, wie sich die magische Kugel reparieren lässt.\n#subobj 1\nZur Schlucht gelangen\n\n#subobj 2\nDas erste Tor öffnen\n\n#subobj 3\nDas zweite Tor öffnen\n\n#subobj 4\nZum Observatorium gehen\n\n#subobj 5\nDas Observatorium durchsuchen\n"
	},
	"quest q27g": {
		"ru": "Подземный источник\nВ книге, найденной в обсерватории, говорится, что один из способов восстановить энергию в магическом предмете — омыть его в подземных водах. Каналы, по которым проходят подземные воды, часто соприкасаются с залежами волшебных камней и магических металлов, что делает эти воды также напитанными магией.\n#subobj 1\nПройти в дальнюю часть пещеры\nПодземные воды протекают в дальней части пещеры, путь туда лежит через лагерь орков.\n#subobj 2\nОмыть шар в западном источнике\nВозможно, каналы этого источника проходят через залежи волшебных камней и воды его обладают магической силой.\n#subobj 3\nОмыть шар в центральном источнике\nВозможно, каналы этого источника проходят через залежи магических металлов и воды его обладают магической силой.\n#subobj 4\nОмыть шар в восточном источнике\nШар надо омыть во всех источниках, только так можно быть уверенным наверняка, что его сила восстановлена.\n",
		"en": "The Underground Spring\nThe observatory's book says that bathing a magical object in underground water can restore its energy. These waters often flow past magical stones and metals and absorb their power.\n#subobj 1\nReach the far end of the cave\n\n#subobj 2\nBathe the orb in the western spring\n\n#subobj 3\nBathe the orb in the central spring\n\n#subobj 4\nBathe the orb in the eastern spring\n",
		"de": "Die unterirdische Quelle\nLaut dem Buch aus dem Observatorium kann ein Bad im Grundwasser die Energie magischer Gegenstände erneuern. Solche Gewässer fließen oft an magischen Steinen und Metallen vorbei und nehmen deren Kraft auf.\n#subobj 1\nZum hinteren Teil der Höhle gelangen\n\n#subobj 2\nDie Kugel in der westlichen Quelle baden\n\n#subobj 3\nDie Kugel in der mittleren Quelle baden\n\n#subobj 4\nDie Kugel in der östlichen Quelle baden\n"
	},
	"quest q28g": {
		"ru": "Дорога под горой\nНет сомнений, что тоннель ведет к жилищу Великого Мага этих земель, но столь же хорошо известно, что этот проход охраняется безжалостными и бесстрашными убийцами — големами. Дорога будет опасна, но риск оправдан!\n#subobj 1 \nПройти пещеру\nГолемы перекрыли весь тоннель, но в одной из стен есть разлом с выходом в пещеру, появившийся, вероятно, в результате землетрясения. Можно попытаться обойти тоннель по пещере.\n#subobj 2 \nНайти ключ управления \nСудя по всему, в этом помещении велось обслуживание големов и осуществление контроля над ними. В комнатке к югу наверняка должно быть что-то, что может помочь.\n#subobj 3 \nИспользовать обелиск\nВ южной части большого зала, охраняемого големами, стоит обелиск, при помощи которого осуществляется частичный контроль над големами.\n#subobj 4 \nИспользвать алтарь\nГолемы, охраняющие алтарь на юго-востоке, получили новый приказ. Отличная возможность пройти к алтарю и при помощи ключа установить полный контроль над големами!\n#subobj 5\nВыйти!\nТеперь големы не опасны — путь свободен!\n",
		"en": "The Road Beneath the Mountain\nThe tunnel surely leads to the Great Mage's home, but ruthless, fearless golems guard it. The journey will be dangerous, yet the risk is worthwhile!\n#subobj 1\nGet through the cave\n\n#subobj 2\nFind the control key\n\n#subobj 3\nUse the obelisk\n\n#subobj 4\nUse the altar\n\n#subobj 5\nGet out!\n",
		"de": "Der Weg unter dem Berg\nDer Tunnel führt gewiss zum Haus des Großen Magiers, doch erbarmungslose und furchtlose Golems bewachen ihn. Der Weg ist gefährlich, aber das Risiko lohnt sich!\n#subobj 1\nDie Höhle durchqueren\n\n#subobj 2\nDen Steuerschlüssel finden\n\n#subobj 3\nDen Obelisken benutzen\n\n#subobj 4\nDen Altar benutzen\n\n#subobj 5\nHinaus!\n"
	},
	"quest q2g": {
		"ru": "Лагерь хадаганцев\nДля того чтобы сфабриковать донесение экспедиции, нужна гербовая бумага, на которой составляются подобные документы. Такая бумага должна быть в хадаганском лагере.\n#subobj 1\nНайти жилище людоеда\nЛюдоед, который забрал ключи от сундука с гербовой бумагой, живет к северу от крепости орков.\n#subobj 2\nЗабрать ключ\nСонный людоед хранит ключ при себе. Можно попытаться пошарить у него в карманах...\n#subobj 3\nПрийти в лагерь хадаганцев\nРазоренный лагерь экспедиции находится на востоке от жилища людоеда.\n#subobj 4\nДостать бумагу\nГербовая бумага лежит в сундуке около палатки в центре лагеря.\n",
		"en": "The Hadagan Camp\nForging the expedition's report requires the official stamped paper used for such documents. There should be some in the Hadagan camp.\n#subobj 1\nFind the ogre's home\n\n#subobj 2\nTake the key\n\n#subobj 3\nGo to the Hadagan camp\n\n#subobj 4\nObtain the paper\n",
		"de": "Das hadaganische Lager\nUm den Expeditionsbericht zu fälschen, brauchst du das amtliche Briefpapier für solche Dokumente. Im hadaganischen Lager müsste es welches geben.\n#subobj 1\nDie Behausung des Ogers finden\n\n#subobj 2\nNimm den Schlüssel\n\n#subobj 3\nZum hadaganischen Lager gehen\n\n#subobj 4\nDas Papier beschaffen\n"
	},
	"quest q2h": {
		"ru": "Списки рабов\nРиндейл не сможет дать приют человеку, находящемуся в розыске. Если выкрасть списки рабов, находящихся у портала во время нападения Ужаса, то это может усложнить задачу хадаганских ищеек.\n#subobj  1\nПробраться к особняку\nПока за дело не взялись следователи, списки рабов хранятся в особняке градоначальника.\n#subobj  2\nОбойти охрану особняка\nОсобняк хорошо охраняется, и лучше не попадаться стражникам.\n#subobj  3\nВыкрасть списки\nСписки рабов находятся на столе около чиновничьего дома.\n#subobj  4\nИзбавиться от свидетелей\nЧиновники заметили кражу! Необходимо избавиться от них.\n",
		"en": "The Slave Lists\nRindale cannot shelter someone who is wanted. Stealing the lists of slaves who were at the portal during the Horror's attack could make the Hadagan trackers' task harder.\n#subobj 1\nReach the manor\n\n#subobj 2\nBypass the manor guards\n\n#subobj 3\nSteal the lists\n\n#subobj 4\nEliminate the witnesses\n",
		"de": "Die Sklavenlisten\nRindale kann niemanden beherbergen, der gesucht wird. Der Diebstahl der Listen jener Sklaven, die beim Angriff des Schreckens am Portal waren, könnte die Suche der hadaganischen Häscher erschweren.\n#subobj 1\nZum Anwesen gelangen\n\n#subobj 2\nDie Wachen des Anwesens umgehen\n\n#subobj 3\nDie Listen stehlen\n\n#subobj 4\nDie Zeugen beseitigen\n"
	},
	"quest q2j": {
		"ru": "Смерть в деревне\nКак выяснилось, не только город подвергся атаке мертвецов — нежить заполонила все окрестности. В первую очередь необходимо очистить ближайшую деревню от порождений некромантии.\n#subobj 1\nПрийти в деревню\nДеревня, подвергшаяся атаке живых мертвецов, находится на востоке местности.\n#subobj 2\nОчистить деревню от нежити\nЖители боятся выходить на улицу, так что можно уничтожать любое встреченное создание.\n",
		"en": "Death in the Village\nThe undead have overrun the countryside as well as the city. First, clear the nearest village of these creatures of necromancy.\n#subobj 1\nGo to the village\n\n#subobj 2\nClear the village of undead\n",
		"de": "Tod im Dorf\nUntote haben nicht nur die Stadt, sondern auch das Umland überrannt. Befreie zunächst das nächste Dorf von diesen Geschöpfen der Nekromantie.\n#subobj 1\nGehe ins Dorf\n\n#subobj 2\nDas Dorf von Untoten befreien\n"
	},
	"quest q2k": {
		"ru": "Магическая лаборатория\nМаг, который мог бы ответить на вопросы об артефакте, — Хис — засел в своей лаборатории и уже давно не появлялся в городе. Можно попытаться наведаться в гости к магу, благо лаборатория находится недалеко от города.\n#subobj 1\nНайти вход в лабораторию\nМагическая лаборатория Хиса расположена восточнее города. По пути могут встретиться лишь дикие животные.\n#subobj 2\nОтключить ловушку\nПохоже, хозяин лаборатории не очень гостеприимен — на входе установлена магическая ловушка!\n#subobj 3\nУничтожить сторожевых тигров\nПомимо магической защиты, лабораторию охраняют еще и специально обученные тигры.\n#subobj 4\nПроникнуть в лабораторию\nПуть свободен! Пора получить ответы на вопросы.\n",
		"en": "The Magic Laboratory\nHis, the mage who might answer questions about the artifact, has shut himself in his laboratory and has not visited the city for a long time. His laboratory is nearby; try paying him a visit.\n#subobj 1\nFind the laboratory entrance\n\n#subobj 2\nSwitch off the trap\n\n#subobj 3\nKill the guard tigers\n\n#subobj 4\nInfiltrate the laboratory\n",
		"de": "Das magische Labor\nHis, der Magier, der über das Artefakt Auskunft geben könnte, hat sich in seinem Labor eingeschlossen und war lange nicht in der Stadt. Das Labor liegt in der Nähe; statte ihm einen Besuch ab.\n#subobj 1\nDen Laboreingang finden\n\n#subobj 2\nEntschärfe die Falle\n\n#subobj 3\nDie Wachtiger töten\n\n#subobj 4\nIns Labor eindringen\n"
	},
	"quest q3ag": {
		"ru": "Старая шахта\nПо традиции орк только тогда считается воином, когда получит топор из рук вождя. Материал для топора претендент должен добыть в шахтах Мертвого города...\n#subobj 1\nНайти вход в рудники\nРудниковая местность расположена на юго-востоке от крепости орков.\n#subobj 2\nПрийти к старой шахте\nСтарая шахта расположена на самом востоке рудников. Не следует забывать, что заброшенные рудники — место обитания нежити.\n#subobj 3\nПробраться в северный тоннель\nТолько в северном тоннеле можно добыть подходящий материал для оружия.\n#subobj 4\nЗабрать материалы\nРудокопы хорошо потрудились на этом участке — материал уже добыт, его нужно только унести.\n",
		"en": "The Old Mine\nTradition says an orc becomes a warrior only upon receiving an axe from the chief. The aspirant must obtain its material from the mines of the Dead City...\n#subobj 1\nFind the mine entrance\n\n#subobj 2\nGo to the old mine\n\n#subobj 3\nGet into the northern tunnel\n\n#subobj 4\nCollect the materials\n",
		"de": "Die alte Mine\nNach alter Sitte wird ein Ork erst zum Krieger, wenn er eine Axt vom Häuptling erhält. Das Material dafür muss der Anwärter aus den Minen der Toten Stadt holen...\n#subobj 1\nDen Mineneingang finden\n\n#subobj 2\nZur alten Mine gehen\n\n#subobj 3\nIn den nördlichen Tunnel gelangen\n\n#subobj 4\nDie Materialien holen\n"
	},
	"quest q3g": {
		"ru": "Старая шахта\nПо традиции орк только тогда считается воином, когда получит топор из рук вождя. Материал для топора претендент должен добыть в шахтах Мертвого города...\n#subobj 1\nНайти вход в рудники\nРудниковая местность расположена на юго-востоке от крепости орков.\n#subobj 2\nПрийти к старой шахте\nСтарая шахта расположена на самом востоке рудников. Не следует забывать, что заброшенные рудники — место обитания нежити.\n#subobj 3\nПробраться в северный тоннель\nТолько в северном тоннеле можно добыть подходящий материал для оружия.\n#subobj 4\nЗабрать материалы\nРудокопы хорошо потрудились на этом участке — материал уже добыт, его нужно только унести.\n",
		"en": "The Old Mine\nTradition says an orc becomes a warrior only upon receiving an axe from the chief. The aspirant must obtain its material from the mines of the Dead City...\n#subobj 1\nFind the mine entrance\n\n#subobj 2\nGo to the old mine\n\n#subobj 3\nGet into the northern tunnel\n\n#subobj 4\nCollect the materials\n",
		"de": "Die alte Mine\nNach alter Sitte wird ein Ork erst zum Krieger, wenn er eine Axt vom Häuptling erhält. Das Material dafür muss der Anwärter aus den Minen der Toten Stadt holen...\n#subobj 1\nDen Mineneingang finden\n\n#subobj 2\nZur alten Mine gehen\n\n#subobj 3\nIn den nördlichen Tunnel gelangen\n\n#subobj 4\nDie Materialien holen\n"
	},
	"quest q3h": {
		"ru": "Маскировка\nДля того чтобы получить разрешение Риндейла остаться в его поместье, необходимо скрыть свое лицо — стража не должна узнать, что Риндейл прикрывает беглого раба.\n#subobj  1\nПрийти к дому торговцев\nДом торговцев находится на самом юге города. Городская стража по-прежнему разыскивает беглецов, так что осторожность не помешает.\n#subobj  2\nДостать ключ\nДля того чтобы пробраться в дом, нужны ключи. Можно поискать их в карманах купца, пока Фейруз отвлекает его внимание.\n#subobj  3\nОтдать ключи Фейрузу\nТеперь нужно передать ключи Фейрузу — и можно приступать непосредственно к «делу».\n#subobj  4\nПодождать Фейруза\nПока Фейруз занимается своими делами в доме, необходимо прикрыть его снаружи. Никто не должен приблизиться к дому!\n#subobj  5\nВернуться в поместье\nДело сделано! Теперь лучше убраться подальше отсюда, пока не вернулись торговцы.\n",
		"en": "Disguise\nHide your face to gain Rindale's permission to stay at his manor. The guards must not learn that he is sheltering an escaped slave.\n#subobj 1\nGo to the merchants' house\n\n#subobj 2\nObtain the key\n\n#subobj 3\nGive Feyruz the keys\n\n#subobj 4\nWait for Feyruz\n\n#subobj 5\nReturn to the manor\n",
		"de": "Tarnung\nVerbirg dein Gesicht, um in Rindales Anwesen bleiben zu dürfen. Die Wache darf nicht erfahren, dass er einem entflohenen Sklaven Schutz bietet.\n#subobj 1\nZum Haus der Händler gehen\n\n#subobj 2\nDen Schlüssel beschaffen\n\n#subobj 3\nFeyruz die Schlüssel geben\n\n#subobj 4\nAuf Feyruz warten\n\n#subobj 5\nZum Anwesen zurückkehren\n"
	},
	"quest q3j": {
		"ru": "Торговец сладостями\nПо словам мастера Старка, у барона есть осведомитель, который мог бы рассказать о причинах такой активности нежити. Если удастся поговорить с осведомителем, возможно, удастся устранить эти причины.\n#subobj 1\nНайти шпиона\nКанийский шпион маскируется под продавца сладостей и живет севернее города.\n#subobj 2\nПеребить солдат\nНесколько хадаганских солдат решили полакомиться сладостями. Нужно угостить их хорошенько...\n",
		"en": "The Sweet Seller\nMaster Stark says the baron has an informant who may know why the undead are so active. Speaking to him could reveal how to stop them.\n#subobj 1\nFind the spy\n\n#subobj 2\nKill the soldiers\n",
		"de": "Der Süßwarenhändler\nLaut Meister Stark hat der Baron einen Informanten, der den Grund für die Unruhe der Untoten kennen könnte. Ein Gespräch könnte zeigen, wie man sie aufhält.\n#subobj 1\nDen Spion finden\n\n#subobj 2\nDie Soldaten töten\n"
	},
	"quest q3k": {
		"ru": "Священный цветок\nСерый Лист, предводитель Зеленого клана лесовиков, может помочь найти рыцаря Бриссена, но для этого нужно найти способ встретиться с ним. Если выкрасть у лесовиков Белого клана Священный цветок, то можно будет призвать Серого Листа на переговоры.\n#subobj 1\nПрийти к территории Белого клана\nЛесовики Белого клана живут на северо-западе окрестностей города Ингоса.\n#subobj 2\nДостать вечнозеленый лист\nЗона обитания лесовиков Белого клана находится под охраной магических ловушек. Ловушки сработают на всякого, кто не является лесовиком или не обладает вечнозеленым листом. Такой лист есть у одного из магов-лесовиков, находящихся за пределами охраняемой зоны.\n#subobj 3\nОтключить ловушку\nСвященный цветок защищают дополнительные ловушки, но их можно отключить на алтаре лесовиков при помощи вечнозеленого листа. Все остальные ловушки также отключатся.\n#subobj 4\nЗабрать цветок\nНа востоке владений лесовиков расположено священное место лесовиков Белого клана. Цветок находится именно там.\n",
		"en": "The Sacred Flower\nGrey Leaf, leader of the Green Clan, may help find the knight Brissen. Steal the Sacred Flower from the White Clan foresters to summon Grey Leaf for talks.\n#subobj 1\nGo to the White Clan's territory\n\n#subobj 2\nObtain an evergreen leaf\n\n#subobj 3\nSwitch off the trap\n\n#subobj 4\nCollect the flower\n",
		"de": "Die heilige Blume\nGraues Blatt, Anführer des Grünen Klans, könnte bei der Suche nach dem Ritter Brissen helfen. Stiehl die heilige Blume von den Waldleuten des Weißen Klans, um ihn zu Verhandlungen zu rufen.\n#subobj 1\nZum Gebiet des Weißen Klans gehen\n\n#subobj 2\nEin immergrünes Blatt beschaffen\n\n#subobj 3\nEntschärfe die Falle\n\n#subobj 4\nDie Blume holen\n"
	},
	"quest q4g": {
		"ru": "Образцы с Гипата\nВ пакете с приказами для экспедиции, говорилось о необходимости передать курьеру образцы пород из шахт Мертвого города. Если в этих породах обнаружатся признаки драгоценных камней, то на Гипат будет выслана новая экспедиция. Этого нельзя допустить, поэтому породы нужно добыть в другой шахте, где драгоценных камней быть не может.\n#subobj 1\nНайти шахту\nШахта, в которой можно взять образцы пород для отправки вместе с донесением, находится на западе Дальних гор.\n#subobj 2\nЗабрать образцы\nВ образцах пород из этой шахты не должно быть драгоценных камней.\n",
		"en": "Samples from Gipath\nThe expedition's orders request rock samples from the Dead City's mines. Signs of gemstones would prompt another expedition to Gipath. Prevent this by collecting samples from a different mine where no gems can be found.\n#subobj 1\nFind the mine\n\n#subobj 2\nCollect the samples\n",
		"de": "Proben aus Gipath\nDie Expeditionsbefehle verlangen Gesteinsproben aus den Minen der Toten Stadt. Hinweise auf Edelsteine würden eine neue Expedition nach Gipath auslösen. Verhindere das und hole Proben aus einer anderen Mine, in der es keine Edelsteine gibt.\n#subobj 1\nDie Mine finden\n\n#subobj 2\nDie Proben holen\n"
	},
	"quest q4h": {
		"ru": "Фруктовый сад\nВ этом саду растут кокосы и апельсины, а охраняют его всего несколько рабов и стражников.\n\n",
		"en": "The Orchard\nCoconuts and oranges grow in this orchard, guarded by only a few slaves and soldiers.",
		"de": "Der Obstgarten\nIn diesem Garten wachsen Kokosnüsse und Orangen. Nur wenige Sklaven und Wachen bewachen ihn."
	},
	"quest q4j": {
		"ru": "Одинокий некромант\nПричина активности нежити на канийской территории — старый некромант. Ему удалось сотворить очень мощное заклинание, которое не позволяет мертвецам спать спокойно в своих могилах.\n#subobj 1\nПопасть на остров Смерти\nНа остров можно попасть только по мосту на западе этой местности.\n#subobj 2\nПрийти к дому некроманта\nНекромант живет в своем поместье, окруженном мертвыми лесами. Он никогда не покидает своего укрытия.\n#subobj 3\nПоджечь поместье\nЧтобы выкурить и взять в плен некроманта, необходимо устроить пожар.\n#subobj 4\nОтконвоировать некроманта\nТолько при помощи некроманта можно устранить причину активности нежити.\n",
		"en": "The Lonely Necromancer\nAn old necromancer is responsible for the unrest in Kanian territory. His powerful spell prevents the dead from resting in their graves.\n#subobj 1\nReach Death Island\n\n#subobj 2\nGo to the necromancer's house\n\n#subobj 3\nSet fire to the manor\n\n#subobj 4\nEscort the necromancer\n",
		"de": "Der einsame Nekromant\nEin alter Nekromant verursacht die Unruhe im kanischen Gebiet. Sein mächtiger Zauber lässt die Toten nicht in ihren Gräbern ruhen.\n#subobj 1\nDie Todesinsel erreichen\n\n#subobj 2\nZum Haus des Nekromanten gehen\n\n#subobj 3\nDas Anwesen anzünden\n\n#subobj 4\nDen Nekromanten eskortieren\n"
	},
	"quest q4k": {
		"ru": "Тайник Свера\nСерый Лист поймет, что перед ним друг, и согласится помочь, если показать ему условленный предмет от Свера-Зайчатника. Свер спрятал такой предмет в одном из своих тайников.\n#subobj 1\nНайти тайник\nСвер спрятал предмет в полом бревне недалеко от армейского лагеря во владениях Карансула.\n#subobj 2\nЗабрать «предмет»\nТайник Свера никак не охраняется, нужно просто забрать его содержимое.\n",
		"en": "Sver's Cache\nGrey Leaf will recognise a friend and agree to help if shown a token from Sver the Hare-Catcher. Sver hid such a token in one of his caches.\n#subobj 1\nFind the hiding place\n\n#subobj 2\nCollect the “object”\n",
		"de": "Svers Versteck\nEin vereinbartes Zeichen von Sver dem Hasenfänger wird Graues Blatt überzeugen, dass du ein Freund bist. Sver hat ein solches Zeichen in einem seiner Verstecke verborgen.\n#subobj 1\nFinde das Versteck\n\n#subobj 2\nDen „Gegenstand“ holen\n"
	},
	"quest q5g": {
		"ru": "Курьер\nТеперь, когда есть и сфабрикованное донесение экспедиции, и фальшивые образы пород из Мертвого города, необходимо встретиться с курьером.\n#subobj 1\nПрийти к городской дороге\nБольшая часть пути к месту передачи материалов проходит вдоль дороги, ведущей из Мертвого города.\n#subobj 2\nНайти условленное место\nМесто передачи материалов — заброшенный домик на юго-западе этой местности.\n#subobj 3\nОставить материалы\nНеизвестно, когда прибудет курьер с Суслангера, поэтому лучше оставить все необходимое в сундуке в заброшенном доме.\n",
		"en": "The Courier\nWith the forged expedition report and false rock samples from the Dead City ready, it is time to meet the courier.\n#subobj 1\nGo to the city road\n\n#subobj 2\nFind the meeting place\n\n#subobj 3\nLeave the materials\n",
		"de": "Der Kurier\nDer gefälschte Expeditionsbericht und die falschen Gesteinsproben aus der Toten Stadt sind bereit. Nun musst du den Kurier treffen.\n#subobj 1\nZur Stadtstraße gehen\n\n#subobj 2\nFinde den Treffpunkt\n\n#subobj 3\nDie Materialien hinterlassen\n"
	},
	"quest q5h": {
		"ru": "Метеоритная лихорадка\nРиндейлу необходимо разузнать о том, где хранятся образцы метеорита с якобы «Бесполезных земель». Скорее всего об этом должен знать начальник городской стражи.\n#subobj  1\nНайти начальника стражи\nНачальник, как всегда, находится в комендатуре. Один из входов в комендатуру надежно охраняется, но все же есть шансы пробраться через второй.\n#subobj  2\nПодслушать разговор\nЭто рискованно, ведь вокруг полно стражи, но, возможно, во время разговора начальник стражи проболтается и о хранилище образцов метеорита.\n",
		"en": "Meteorite Fever\nRindale needs to know where meteorite samples from the supposedly Worthless Lands are kept. The captain of the city guard should know.\n#subobj 1\nFind the guard captain\n\n#subobj 2\nOverhear the conversation\n",
		"de": "Meteoritenfieber\nRindale will wissen, wo die Meteoritenproben aus den angeblich Wertlosen Landen lagern. Der Hauptmann der Stadtwache müsste es wissen.\n#subobj 1\nDen Hauptmann der Wache finden\n\n#subobj 2\nDas Gespräch belauschen\n"
	},
	"quest q5j": {
		"ru": "Чесночная настойка\nНекромант с острова Смерти рассказал, что заклинание, оживляющее мертвецов во всей округе, можно снять только при помощи специального зелья. Такое зелье должно быть на острове, в могиле одного героя древности.\n#subobj 1\nПопасть на восточную часть острова\nГробница героя, в которой спрятано зелье, находится на восточной части острова. Попасть на нее можно только через мостик в центральной части.\n#subobj 2\nПрийти к гробнице\nВеликий герой был захоронен высоко в горах. Сейчас это место заброшено, а горы облюбовали драконы.\n#subobj 3\nЗабрать зелье\nЗелье, уничтожающее нежить, было захоронено прямо в гробнице героя.\n#subobj 4\nУничтожить героя\nБутыль с зельем хорошо запечатана, и зелье не смогло уберечь своего бывшего хозяина от страшной участи. Теперь придется упокоить его навечно...\n",
		"en": "Garlic Tincture\nThe necromancer on Death Island says only a special potion can break the spell that raises the dead throughout the region. It should be buried on the island in an ancient hero's grave.\n#subobj 1\nReach the eastern part of the island\n\n#subobj 2\nGo to the tomb\n\n#subobj 3\nCollect the potion\n\n#subobj 4\nDestroy the hero\n",
		"de": "Knoblauchtinktur\nDer Nekromant auf der Todesinsel sagt, nur ein besonderer Trank könne den Zauber brechen, der überall die Toten erweckt. Er müsste auf der Insel im Grab eines alten Helden liegen.\n#subobj 1\nDen Ostteil der Insel erreichen\n\n#subobj 2\nZur Gruft gehen\n\n#subobj 3\nDen Trank holen\n\n#subobj 4\nDen Helden vernichten\n"
	},
	"quest q5k": {
		"ru": "Переговоры\nДля того чтобы встретиться с Серым листом — предводителем Зеленого клана, необходимо подать сигнал при помощи Священного цветка, который лесовики используют в случае необходимости проведения переговоров.\n#subobj 1\nДобраться до места встречи\nЛесовики всех кланов используют строго определенные места для проведения переговоров.\n#subobj 2\nПризвать лесовиков\nДля того чтобы подать сигнал, необходимо положить Священный цветок на старый пень лесовиков.\n",
		"en": "Negotiations\nUse the Sacred Flower, the foresters' signal for talks, to arrange a meeting with Grey Leaf, leader of the Green Clan.\n#subobj 1\nReach the meeting place\n\n#subobj 2\nSummon the foresters\n",
		"de": "Verhandlungen\nGib mit der heiligen Blume das Verhandlungssignal der Waldleute, um Graues Blatt, den Anführer des Grünen Klans, zu treffen.\n#subobj 1\nDen Treffpunkt erreichen\n\n#subobj 2\nDie Waldleute herbeirufen\n"
	},
	"quest q6g": {
		"ru": "Урк-Тар\nВождь орков с двумя молодыми воинами уже давно ушли на охоту и все еще не возвращаются. Необходимо отыскать их — скорее всего орки попали в неприятности.\n#subobj 1\nНайти отряд орков\nУрк-Тар должен был повести охотников на восток, в богатые дичью места.\n#subobj 2\nОтогнать гарпию\nПохоже, что гарпия, живущая в той местности, натравила на отряд стаю летучих мышей. Орки не смогут пробиться сами, им нужна помощь.\n#subobj 3\nПеребить летучих мышей\nПуть отряду преграждают летучие мыши, которых натравила гарпия. Дорога должна быть расчищена!\n#subobj 4\nПроводить вождя в крепость\nУрк-Тар ранен. Ему потребуется сопровождение, чтобы добраться до племени.\n#subobj 5\nУрк-Тар должен выжить\nСмерть вождя будет означать конец племени.\n",
		"en": "Urk-Tar\nThe orc chief and two young warriors left to hunt long ago and have not returned. Find them; they have probably run into trouble.\n#subobj 1\nFind the orc party\n\n#subobj 2\nDrive away the harpy\n\n#subobj 3\nKill the bats\n\n#subobj 4\nEscort the chief to the fortress\n\n#subobj 5\nUrk-Tar must survive\n",
		"de": "Urk-Tar\nDer Orkhäuptling und zwei junge Krieger gingen vor langer Zeit auf die Jagd und sind nicht zurück. Finde sie; vermutlich sind sie in Schwierigkeiten.\n#subobj 1\nDen Orktrupp finden\n\n#subobj 2\nDie Harpyie vertreiben\n\n#subobj 3\nDie Fledermäuse töten\n\n#subobj 4\nDen Häuptling zur Festung begleiten\n\n#subobj 5\nUrk-Tar muss überleben\n"
	},
	"quest q6h": {
		"ru": "Письмо шантажисту\nТетя Зара хочет договориться со своими шантажистами о выкупе за их молчание. Для этого необходимо отнести записку с ее предложением в условленное место севернее плантаций.\n#subobj  1\nПокинуть пределы города\nСейчас, когда шумиха про появление Ужаса около портала немного улеглась, стража сняла охрану с мостов, так что выход из города теперь вполне безопасен.\n#subobj  2\nДобраться до условленного места\nЗа пределами города обитает множество опасных диких зверей, а надсмотрщики на плантациях опасны вдвойне.\n#subobj  3\nИзбавиться от шпионов\nЗа местом передачи следят. Шпионы не должны выжить.\n#subobj  4\nПередать письмо\nПисьмо надо положить в урну. Шантажист заберет его позже.\n\n",
		"en": "A Letter to the Blackmailer\nAunt Zara wants to negotiate payment for her blackmailers' silence. Take her proposal to the agreed place north of the plantations.\n#subobj 1\nLeave the city limits\n\n#subobj 2\nReach the agreed place\n\n#subobj 3\nEliminate the spies\n\n#subobj 4\nDeliver the letter\n",
		"de": "Ein Brief an den Erpresser\nTante Zara will über den Preis für das Schweigen ihrer Erpresser verhandeln. Bringe ihre Nachricht zum vereinbarten Ort nördlich der Plantagen.\n#subobj 1\nDie Stadtgrenze überschreiten\n\n#subobj 2\nDen vereinbarten Ort erreichen\n\n#subobj 3\nDie Spione beseitigen\n\n#subobj 4\nDen Brief übergeben\n"
	},
	"quest q6j": {
		"ru": "Спокойные кладбища\nТеперь, с зельем, уничтожающим нежить, можно наконец избавиться от угрозы со стороны мертвецов. Для этого необходимо обрызгать кладбище зельем.\n#subobj 1\nПрийти на кладбище\nКладбище — источник нежити — находится в кольце гор, на юге местности. \n#subobj 2\nИспользовать зелье\nДля того чтобы упокоить кладбище, достаточно облить статую в центре. Дальше зелье распространится само.\n",
		"en": "Peaceful Graveyards\nThe potion that destroys the undead can finally end their threat. Sprinkle it over the graveyard.\n#subobj 1\nGo to the graveyard\n\n#subobj 2\nUse the potion\n",
		"de": "Ruhige Friedhöfe\nMit dem Trank gegen Untote lässt sich ihre Bedrohung endlich beenden. Besprenge den Friedhof damit.\n#subobj 1\nZum Friedhof gehen\n\n#subobj 2\nDen Trank benutzen\n"
	},
	"quest q6k": {
		"ru": "Зеленый клан\nСерый Лист рассказал о месте новой стоянки Зеленого клана и сказал, что готов будет ответить там на вопросы.\n#subobj 1\nОткрыть ворота\nДорога к Зеленому клану проходит по горному ущелью, вход в которое перекрыт воротами.\n#subobj 2\nПрийти в Зеленый клан\nСтоянка Зеленого клана расположена в конце ущелья.\n",
		"en": "The Green Clan\nGrey Leaf has revealed the Green Clan's new camp and will answer your questions there.\n#subobj 1\nOpen the gates\n\n#subobj 2\nCome to the Green Clan\n",
		"de": "Der Grüne Klan\nGraues Blatt hat den neuen Lagerplatz des Grünen Klans verraten und wird dort deine Fragen beantworten.\n#subobj 1\nÖffne die Tore\n\n#subobj 2\nGehe zum Grünen Clan\n"
	},
	"quest q7g": {
		"ru": "Предатели гоблины\nПока все воины были за пределами лагеря, произошел набег гоблинов, которые раньше всегда считались дружественными. Гоблины взяли в плен жену вождя. Урк-Тар ранен и не может спасти ее сам, но, если помочь ему, он должен быть благодарен.\n#subobj 1\nПрийти к лагерю гоблинов\nЛагерь гоблинов находится на востоке Средних гор. Это место окружено высокими холмами и хорошо охраняется...\n#subobj 2\nНайти жену вождя\nСкорее всего жена Урк-Тара содержится в самом центре лагеря.\n#subobj 3\nСпасти жену Урк-Тара\nНужно сопроводить жену вождя до Дальних гор. Остальная часть пути должна быть известна ей, и до крепости она доберется сама.\n#subobj 4\nЖена вождя должна выжить\nСкорее всего Урк-Тар не простит смерти своей жены.\n",
		"en": "The Goblins' Betrayal\nWhile the warriors were away, previously friendly goblins raided the camp and captured the chief's wife. Urk-Tar is wounded and cannot rescue her himself. He should be grateful for your help.\n#subobj 1\nGo to the goblin camp\n\n#subobj 2\nFind the chief's wife\n\n#subobj 3\nRescue Urk-Tar's wife\n\n#subobj 4\nThe chief's wife must survive\n",
		"de": "Der Verrat der Goblins\nWährend die Krieger fort waren, überfielen die bisher befreundeten Goblins das Lager und entführten die Frau des Häuptlings. Urk-Tar ist verwundet und kann sie nicht selbst retten. Für deine Hilfe dürfte er dankbar sein.\n#subobj 1\nZum Goblinlager gehen\n\n#subobj 2\nDie Frau des Häuptlings finden\n\n#subobj 3\nUrk-Tars Frau retten\n\n#subobj 4\nDie Frau des Häuptlings muss überleben\n"
	},
	"quest q7h": {
		"ru": "Черный рынок\nФейруз, который мог бы помочь в краже метеорита, перебрался на Черный рынок — тайное место торговли. Без его помощи достать образцы метеорита не удастся. Фейруза необходимо найти.\n#subobj  1\nПокинуть город\nЕдинственный выход из города, ведущий на северные плантации, почти не охраняется.\n#subobj  2\nПройти по северному мосту\nСеверный мост почти не охраняется, но дикие звери, живущие за ним, представляют серьезную угрозу.\n#subobj  3\nПройти по западному мосту\nЗападный мост охраняется с двух сторон — недалеко расположен военный лагерь хадаганцев.\n#subobj  4\nПрийти к Черному рынку\nНа пути к Черному рынку могут встретиться намного более взрослые и сильные звери, чем в области «Портала».\n",
		"en": "The Black Market\nFeyruz, who could help steal the meteorite, has moved to the secret Black Market. Find him: the samples cannot be obtained without his help.\n#subobj 1\nLeave the city\n\n#subobj 2\nCross the northern bridge\n\n#subobj 3\nCross the western bridge\n\n#subobj 4\nGo to the Black Market\n",
		"de": "Der Schwarzmarkt\nFeyruz, der beim Diebstahl des Meteoriten helfen könnte, ist zum geheimen Schwarzmarkt gezogen. Finde ihn, denn ohne seine Hilfe sind die Proben nicht zu beschaffen.\n#subobj 1\nDie Stadt verlassen\n\n#subobj 2\nDie nördliche Brücke überqueren\n\n#subobj 3\nDie westliche Brücke überqueren\n\n#subobj 4\nZum Schwarzmarkt gehen\n"
	},
	"quest q7j": {
		"ru": "Поединок\nДерзкий Дартас должен быть наказан, и поединок — единственный способ проучить его.\n#subobj 1\nПрийти на место поединка\nДуэли запрещены в военное время, так что место встречи находится в безлюдном месте, далеко от города.\n#subobj 2\nПроучить выскочку\nСына барона нельзя убивать, но хорошая взбучка явно пойдет ему на пользу.\n",
		"en": "The Duel\nThe insolent Dartas must be taught a lesson. A duel is the only way.\n#subobj 1\nGo to the duelling ground\n\n#subobj 2\nTeach the upstart a lesson\n",
		"de": "Das Duell\nDer freche Dartas muss eine Lektion erhalten. Das ist nur durch ein Duell möglich.\n#subobj 1\nZum Duellplatz gehen\n\n#subobj 2\nDem Emporkömmling eine Lektion erteilen\n"
	},
	"quest q7k": {
		"ru": "Отравленная вода\nОдна из мануфактур Карансула сбрасывает ядовитые отходы в соседний водоем, в результате чего лесные животные, обитающие недалеко от этого водоема, начали страдать различными болезнями. Необходимо прекратить загрязнение реки, иначе все животные погибнут.\n#subobj 1\nПрийти во владения Карансула\nЧтобы пробраться во владения Карансула, нужно миновать северный или южный пост охраны. Северный охраняется очень тщательно, так что лучше идти через южный.\n#subobj 2\nЗабрать порошок\nКарансул рассказал, что при горных работах используется специальный порошок, который может обрушить целую скалу. Раз может обрушить скалу, то и мануфактуру сможет.\n#subobj 3\nПодорвать мануфактуру\nДля того чтобы прекратить сброс отходов, необходимо предотвратить появление этих отходов, то есть вывести мануфактуру из строя.\n",
		"en": "Poisoned Water\nOne of Karansul's workshops discharges toxic waste into nearby water, making the forest animals ill. Stop the river pollution before all the animals die.\n#subobj 1\nGo to Karansul's domain\n\n#subobj 2\nCollect the powder\n\n#subobj 3\nBlow up the workshop\n",
		"de": "Vergiftetes Wasser\nEine von Karansuls Manufakturen leitet giftige Abfälle ins nahe Gewässer und macht die Waldtiere krank. Beende die Flussverschmutzung, bevor alle Tiere sterben.\n#subobj 1\nZu Karansuls Herrschaftsgebiet gehen\n\n#subobj 2\nDas Pulver holen\n\n#subobj 3\nDie Manufaktur sprengen\n"
	},
	"quest q8g": {
		"ru": "Ракушка ящеров\nПеред атакой на лагерь людей следует поссорить их с ящерами. Для этого нужно похитить Большую ракушку — символ мира людей и ящеров.\n#subobj 1\nПрийти к алтарю\nАлтарь, на котором установлена Большая ракушка, расположен в центре поселения лесных ящеров. Пока символ мира на месте, ящеры не опасны.\n#subobj 2\nУкрасть ракушку\nКак только символ мира пропадет с алтаря, ящеры станут враждебны людям.\n",
		"en": "The Lizards' Shell\nTurn the lizards against the humans before attacking the human camp. Steal the Great Shell, the symbol of peace between the two peoples.\n#subobj 1\nGo to the altar\n\n#subobj 2\nSteal the shell\n",
		"de": "Die Muschel der Echsen\nEntzweie Menschen und Echsen, bevor du das Menschenlager angreifst. Stiehl die Große Muschel, das Friedenssymbol beider Völker.\n#subobj 1\nZum Altar gehen\n\n#subobj 2\nDie Muschel stehlen\n"
	},
	"quest q8h": {
		"ru": "Небесное железо\nДля приобретения очередного редкого экземпляра гигантского хищного муравья Риндейлу потребовались образцы метеорита, которые сейчас находятся в расположении одного из лагерей хадаганской армии.\n#subobj  1\nПроникнуть за ворота\nНовые казармы находятся южнее Черного рынка. Хоть ворота почти не охраняются, следует сохранять бдительность.\n#subobj  2\nВзломать сундук\nОбразцы метеорита находятся в сундуке, однако заполучить их сможет только опытный вор...\n#subobj  3\nВернуться\nТеперь необходимо скрыться, пока кража не обнаружена и не начата погоня.\n",
		"en": "Heavenly Iron\nTo acquire another rare specimen of giant predatory ant, Rindale needs meteorite samples held in a Hadagan army camp.\n#subobj 1\nGet beyond the gates\n\n#subobj 2\nPick the chest's lock\n\n#subobj 3\nReturn\n",
		"de": "Himmlisches Eisen\nFür ein weiteres seltenes Exemplar der riesigen Raubameise braucht Rindale Meteoritenproben aus einem Lager der hadaganischen Armee.\n#subobj 1\nHinter das Tor gelangen\n\n#subobj 2\nDas Truhenschloss knacken\n\n#subobj 3\nZurückkehren\n"
	},
	"quest q8j": {
		"ru": "Новый сплав\nВ горах Джиграна есть металлы, которые могут дать новый сплав, обладающий отличными характеристиками.\n#subobj 1\nСобрать руду\nПодходящую руду можно найти в горах на западе, почти у самых городских стен.\n#subobj 2\nНайти кузницу\nКузница находится на западе местности за рекой. Путешествие к ней не должно вызвать сложности.\n#subobj 3\nВыплавить новый сплав\nКузница свободна, ее можно использовать для получения нового сплава.\n",
		"en": "A New Alloy\nThe mountains of Jigran contain metals that could produce an excellent new alloy.\n#subobj 1\nGather the ore\n\n#subobj 2\nFind the forge\n\n#subobj 3\nSmelt the new alloy\n",
		"de": "Eine neue Legierung\nDie Berge von Jigran enthalten Metalle, aus denen eine hervorragende neue Legierung entstehen könnte.\n#subobj 1\nDas Erz sammeln\n\n#subobj 2\nDie Schmiede finden\n\n#subobj 3\nDie neue Legierung schmelzen\n"
	},
	"quest q8k": {
		"ru": "Свободное поселение\nПо словам Серого листа маг, который может помочь в поисках артефакта, обосновался в поселении на западе зоны рудников. Маг очень редко покидает свое пристанище, поэтому придется идти к нему в лагерь.\n#subobj 1\nПрийти к вольным людям\nЧтобы попасть в поселение, нужно пройти по каньону в центре зоны рудников, а затем свернуть на запад.\n#subobj 2\nУничтожить тигров\nПоселение атакуют снежные тигры! Необходимо помочь жителям.\n",
		"en": "The Free Settlement\nGrey Leaf says a mage who may help locate the artifact lives in a settlement west of the mines. He rarely leaves his refuge, so you must visit his camp.\n#subobj 1\nGo to the free people\n\n#subobj 2\nKill the tigers\n",
		"de": "Die freie Siedlung\nLaut Graues Blatt lebt ein Magier, der das Artefakt finden helfen könnte, westlich des Bergbaugebiets. Er verlässt seine Zuflucht selten, also musst du sein Lager aufsuchen.\n#subobj 1\nZu den freien Leuten gehen\n\n#subobj 2\nDie Tiger töten\n"
	},
	"quest q9g": {
		"ru": "Внезапная атака\nПосле того как ящеры стали враждебны людям, между ними должна была произойти стычка. Нужно атаковать лагерь людей, пока они ослаблены.\n#subobj 1\nПрийти на место встречи\nВоины орков заняли позицию недалеко от лагеря людей. Вначале необходимо провести деверсию в лагере, уменьшив количество защитников. Атака в лоб скорее всего обернется неудачей — лагерь хорошо охраняется.\n#subobj 2\nВыбить людей из лагеря\nЭто стойбище отстроили орки, и оно должно принадлежать им!\n",
		"en": "The Sudden Attack\nThe lizards and humans should have clashed now that they are enemies. Strike the human camp while it is weakened.\n#subobj 1\nGo to the meeting place\n\n#subobj 2\nDrive the humans from the camp\n",
		"de": "Der Überraschungsangriff\nDie verfeindeten Echsen und Menschen dürften bereits aneinandergeraten sein. Greife das geschwächte Menschenlager an.\n#subobj 1\nZum Treffpunkt gehen\n\n#subobj 2\nDie Menschen aus dem Lager vertreiben\n"
	},
	"quest q9h": {
		"ru": "Шантажист\nЧеловек, шантажирующий тетю Зару, назначил место и время, в которые необходимо принести требуемую за его «покровительство» сумму.\n#subobj  1\nНайти назначенное место\nПлату за молчание шантажиста необходимо отнести к одной из пальм на плантациях севернее города.\n#subobj  2\nОставить записку\nВместо того чтобы оставлять деньги какому-то неизвестному человеку, можно присвоить их себе, а его заставить отказаться от шантажа...\n#subobj  3\nВыследить шантажиста\nТеперь необходимо подождать, пока шантажист придет к условленному месту.\n#subobj  4\nУбить шантажиста\nТеперь он никогда больше не будет заниматься вымогательством.\n",
		"en": "The Blackmailer\nAunt Zara's blackmailer has set a time and place for payment of the sum he demands for his “protection”.\n#subobj 1\nFind the designated place\n\n#subobj 2\nLeave the note\n\n#subobj 3\nTrack down the blackmailer\n\n#subobj 4\nKill the blackmailer\n",
		"de": "Der Erpresser\nTante Zaras Erpresser hat Ort und Zeit festgelegt, an denen das Geld für seinen „Schutz“ zu übergeben ist.\n#subobj 1\nDen vereinbarten Ort finden\n\n#subobj 2\nDie Nachricht hinterlassen\n\n#subobj 3\nDen Erpresser aufspüren\n\n#subobj 4\nDen Erpresser töten\n"
	},
	"quest q9j": {
		"ru": "Секретное донесение\nБарон просит доставить донесение о состоянии вражеских сил, которое  должен был подготовить шпион. За домом шпиона установлена слежка, поэтому донесение спрятано в другом месте.\n#subobj 1\nНайти донесение\nШпион боялся обыска и спрятал все документы там, где их точно никто не станет искать, — на кладбище в северной части местности.\n#subobj 2\nЗабрать донесение\nДонесение спрятано в кувшине на кладбище.\n#subobj 3\nУничтожить слежку\nХадаганские солдаты, устроившие засаду около дома шпиона, должны умереть.\n",
		"en": "The Secret Report\nThe baron asks you to deliver a spy's report on enemy strength. The spy's house is watched, so the report is hidden elsewhere.\n#subobj 1\nFind the report\n\n#subobj 2\nCollect the report\n\n#subobj 3\nEliminate the watchers\n",
		"de": "Der geheime Bericht\nDer Baron verlangt den Bericht eines Spions über die feindlichen Truppen. Da dessen Haus überwacht wird, liegt der Bericht an einem anderen Ort versteckt.\n#subobj 1\nDen Bericht finden\n\n#subobj 2\nDen Bericht holen\n\n#subobj 3\nDie Beobachter beseitigen\n"
	},
	"quest q9k": {
		"ru": "Магические ингридиенты\nХис просит принести кое-какие ингредиенты из его лаборатории, которые необходимы ему для составления заклинаний. Возможно, после этого он согласится помочь.\n#subobj 1\nПрийти в лабораторию\nНа этот раз проблем с лабораторией быть не должно — ловушки отключены и сторожевых тигров тоже нет.\n#subobj 2\nУничтожить «хвост»\nНеизвестные люди организовали слежку, необходимо избавиться от них.\n#subobj 3\nЗабрать ингредиенты\nВсе необходимое лежит в сундучке около лаборатории.\n",
		"en": "Magical Ingredients\nHis asks you to fetch ingredients from his laboratory for his spells. Perhaps he will agree to help afterwards.\n#subobj 1\nGo to the laboratory\n\n#subobj 2\nEliminate the pursuer\n\n#subobj 3\nCollect the ingredients\n",
		"de": "Magische Zutaten\nHis bittet dich, einige Zauberzutaten aus seinem Labor zu holen. Vielleicht wird er dir danach helfen.\n#subobj 1\nZum Labor gehen\n\n#subobj 2\nDen Verfolger beseitigen\n\n#subobj 3\nDie Zutaten holen\n"
	}
}
