class_name WikiSearch
extends RefCounted
## Ranked token search, shared in behavior with web/wiki/search.mjs.

static func normalize(value: String) -> String:
	var out := value.to_lower()
	for pair: Array in [["ё","е"],["ä","a"],["ö","o"],["ü","u"],["ß","ss"],["é","e"],["–"," "],["-"," "]]: out = out.replace(pair[0],pair[1])
	return RegEx.create_from_string("\\s+").sub(out," ",true)

static func distance(a: String, b: String) -> int:
	if absi(a.length()-b.length()) > 2: return 99
	var rows: Array = []
	for i in a.length()+1:
		var row: Array[int] = []
		for j in b.length()+1: row.append(j if i==0 else i if j==0 else 0)
		rows.append(row)
	for i in range(1,a.length()+1):
		for j in range(1,b.length()+1):
			rows[i][j] = mini(mini(rows[i-1][j]+1,rows[i][j-1]+1),rows[i-1][j-1]+(0 if a[i-1]==b[j-1] else 1))
			if i>1 and j>1 and a[i-1]==b[j-2] and a[i-2]==b[j-1]: rows[i][j]=mini(rows[i][j],rows[i-2][j-2]+1)
	return rows[a.length()][b.length()]

static func score(query: String, title: String, text: String) -> int:
	query=normalize(query).strip_edges()
	if query.is_empty(): return 0
	title=normalize(title)
	text=normalize(title+" "+text)
	if query==title: return 1000
	var score_value := 800 if title.begins_with(query) else 600 if query in title else 100
	var words := RegEx.create_from_string("[^a-zа-я0-9]+").sub(text," ",true).split(" ",false)
	for word: String in query.split(" ",false):
		if word in text: continue
		if word.length()<4: return -1
		var closest := 99
		for candidate: String in words: closest=mini(closest,distance(word,candidate))
		if closest > (1 if word.length()<8 else 2): return -1
		score_value -= closest*30
	return score_value
