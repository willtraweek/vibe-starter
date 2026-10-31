extends RefCounted
## Counts how often each coverage probe ran. Only the copies ./scripts/coverage.sh
## instruments call hit(); the test runner saves the counts when the run ends.

static var counts: Dictionary[int, int] = { }


static func hit(id: int) -> void:
	if counts.has(id):
		counts[id] += 1
	else:
		counts[id] = 1


## Writes the counts to [param path] as JSON, keyed by probe id.
static func save(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var by_id := { }
	for id: int in counts:
		by_id[str(id)] = counts[id]
	file.store_string(JSON.stringify(by_id) + "\n")
	return OK
