extends SceneTree
## Writes an instrumented copy of every script under res://src into a mirror of the project,
## and the map of its probes. ./scripts/coverage.sh runs it, then the tests in the mirror.
##
## Arguments after --: the mirror's directory, then the file for the map (JSON: each script's
## probed lines, its branches, and how many of its chains could not be measured).

const Instrumenter := preload("res://tools/coverage/instrumenter.gd")
const SOURCE_DIR := "res://src"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("instrument: usage: -- <mirror dir> <map.json>")
		quit(2)
		return
	var instrumenter := Instrumenter.new()
	var files := { }
	var next_id := 0
	var ok := true
	for path: String in _scripts(SOURCE_DIR):
		var relative := path.trim_prefix("res://")
		var result := instrumenter.instrument(FileAccess.get_file_as_string(path), next_id)
		var source: String = result["source"]
		next_id = result["next_id"]
		var copy := FileAccess.open(args[0].path_join(relative), FileAccess.WRITE)
		if copy == null:
			printerr("instrument: cannot write the copy of %s" % relative)
			ok = false
			continue
		copy.store_string(source)
		files[relative] = {
			"lines": result["lines"],
			"branches": result["branches"],
			"unmeasured": result["unmeasured"],
		}
	var map := FileAccess.open(args[1], FileAccess.WRITE)
	if map == null:
		printerr("instrument: cannot write " + args[1])
		ok = false
	else:
		map.store_string(JSON.stringify({ "files": files }, "  ") + "\n")
	quit(0 if ok else 1)


func _scripts(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var access := DirAccess.open(dir)
	if access == null or FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for file: String in access.get_files():
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub: String in access.get_directories():
		found.append_array(_scripts(dir.path_join(sub)))
	found.sort()
	return found
