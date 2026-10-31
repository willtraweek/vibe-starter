extends SceneTree
## The coverage gate (TESTING.md), run by ./scripts/coverage.sh. Arguments after --:
##   --validate             check coverage-tiers.json on its own, before any test runs
##   --ratchet <base.json>  check coverage-tiers.json against the base branch's copy: no tier,
##                          minimum or target lowered or removed, and no member dropped unless
##                          its old path is in the tier's retired list
##   --map <file> --hits <file> --results <file> [--lcov <file>]
##                          the gate: at least 90% of lines and of branches overall, each tier
##                          at its minimum, and every named journey run and passed

const CONFIG := "res://coverage-tiers.json"
const GLOBAL_MINIMUM := 90.0
const TIER_KEYS: PackedStringArray = [
	"title",
	"minimum",
	"target",
	"include",
	"allow_empty",
	"retired",
]
const JOURNEY_PREFIX := "tests/journeys/"

var _options: Dictionary[String, String] = { }


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i].begins_with("--"):
			var has_value := i + 1 < args.size() and not args[i + 1].begins_with("--")
			_options[args[i].trim_prefix("--")] = args[i + 1] if has_value else ""
	var config: Variant = _read_json(CONFIG)
	var problems := validate(config)
	if problems.is_empty():
		var checked: Dictionary = config
		if _options.has("ratchet"):
			problems = ratchet(checked, _read_json(_options["ratchet"]))
		elif not _options.has("validate"):
			problems = _gate(checked)
	for problem: String in problems:
		printerr("coverage: " + problem)
	if problems.is_empty():
		print("coverage: ok")
	quit(0 if problems.is_empty() else 1)


## What is wrong with the tier config [param config]: empty when nothing is. Without
## [param check_files] (the base branch's copy), paths need not exist here.
func validate(config: Variant, check_files: bool = true) -> PackedStringArray:
	var problems: PackedStringArray = []
	if typeof(config) != TYPE_DICTIONARY:
		return ["coverage-tiers.json must hold a JSON object"]
	var top: Dictionary = config
	for key: Variant in top:
		if not key in ["tiers", "journeys"]:
			problems.append("unknown key %s in coverage-tiers.json" % JSON.stringify(key))
	var tiers: Variant = top.get("tiers")
	if typeof(tiers) != TYPE_DICTIONARY or (tiers == { }):
		problems.append("tiers must be a nonempty object")
		tiers = { }
	var owners := { }
	var by_name: Dictionary = tiers
	for name: Variant in by_name:
		problems.append_array(_validate_tier(str(name), by_name[name], owners, check_files))
	var journeys: Variant = top.get("journeys", [])
	if typeof(journeys) != TYPE_ARRAY:
		problems.append("journeys must be an array")
		journeys = []
	var seen := { }
	var listed: Array = journeys
	for journey: Variant in listed:
		var id := str(journey)
		var file := id.get_slice("::", 0)
		if (
			typeof(journey) != TYPE_STRING or not id.begins_with(JOURNEY_PREFIX)
			or not id.contains("::test_")
		):
			problems.append(
				"journey %s must be tests/journeys/<file>.gd::test_<name>" % JSON.stringify(journey)
			)
		elif seen.has(id):
			problems.append("journey %s is listed twice" % id)
		elif check_files and not FileAccess.file_exists("res://" + file):
			problems.append("journey %s: %s does not exist" % [id, file])
		seen[id] = true
	return problems


func _validate_tier(
	name: String,
	tier: Variant,
	owners: Dictionary,
	check_files: bool,
) -> PackedStringArray:
	var problems: PackedStringArray = []
	if typeof(tier) != TYPE_DICTIONARY:
		return ["%s: a tier must be an object" % name]
	var fields: Dictionary = tier
	for key: Variant in fields:
		if not str(key) in TIER_KEYS:
			problems.append("%s: unknown key %s" % [name, JSON.stringify(key)])
	if (
		typeof(fields.get("title")) != TYPE_STRING
		or str(fields.get("title")).strip_edges().is_empty()
	):
		problems.append("%s: title must be a nonempty string" % name)
	var minimum: Variant = fields.get("minimum")
	var target: Variant = fields.get("target")
	if not _is_percent(minimum) or not _is_percent(target):
		problems.append("%s: minimum and target must be numbers from 0 to 100" % name)
	else:
		var low: float = minimum
		var high: float = target
		if low > high:
			problems.append("%s: minimum must not exceed target" % name)
	if typeof(fields.get("allow_empty", false)) != TYPE_BOOL:
		problems.append("%s: allow_empty must be true or false" % name)
	var include: Variant = fields.get("include")
	var retired: Variant = fields.get("retired", [])
	if typeof(include) != TYPE_ARRAY or typeof(retired) != TYPE_ARRAY:
		problems.append("%s: include and retired must be arrays of src/**.gd paths" % name)
		return problems
	var members: Array = include
	var old: Array = retired
	if members.is_empty() and fields.get("allow_empty", false) != true:
		problems.append("%s: an empty include needs \"allow_empty\": true" % name)
	for path: Variant in members + old:
		if not _is_source_path(path):
			problems.append("%s: %s is not a src/**.gd path" % [name, JSON.stringify(path)])
		elif owners.has(path):
			problems.append("%s: %s is listed twice (also in %s)" % [name, path, owners[path]])
		else:
			owners[path] = name
	for path: Variant in members:
		if (
			check_files and _is_source_path(path)
			and not FileAccess.file_exists("res://" + str(path))
		):
			problems.append(
				"%s: %s does not exist (renamed? list the old path in retired)" % [name, path]
			)
	return problems


## What [param config] loosens compared with the base branch's [param base]: empty when nothing.
func ratchet(config: Dictionary, base: Variant) -> PackedStringArray:
	# ./scripts/coverage.sh passes over a base without the file; a broken one still fails.
	var problems: PackedStringArray = []
	for problem: String in validate(base, false):
		problems.append("base config: " + problem)
	if not problems.is_empty():
		return problems
	var base_root: Dictionary = base
	var base_tiers: Dictionary = base_root["tiers"]
	var tiers: Dictionary = config["tiers"]
	for name: Variant in base_tiers:
		var before: Dictionary = base_tiers[name]
		if not tiers.has(name):
			problems.append("tier %s was removed" % name)
			continue
		var after: Dictionary = tiers[name]
		for key: String in ["minimum", "target"]:
			var was_percent: float = before[key]
			var now_percent: float = after[key]
			if now_percent < was_percent:
				problems.append(
					"%s: %s fell from %s to %s"
					% [name, key, _number(was_percent), _number(now_percent)]
				)
		var kept: Array = after["include"] + after.get("retired", [])
		var was: Array = before["include"]
		for path: Variant in was:
			if not kept.has(path):
				problems.append(
					"%s: %s left the tier; list it in retired if it was renamed or deleted"
					% [name, path]
				)
	return problems


func _gate(config: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var map: Variant = _read_json(_option("map"))
	var hits: Variant = _read_json(_option("hits"))
	var results: Variant = _read_json(_option("results"))
	if (
		typeof(map) != TYPE_DICTIONARY or typeof(hits) != TYPE_DICTIONARY
		or typeof(results) != TYPE_ARRAY
	):
		return ["the gate needs --map, --hits and --results from an instrumented run"]
	var map_root: Dictionary = map
	var files: Dictionary = map_root.get("files", { })
	var counts: Dictionary = hits
	var stats := { }
	var lcov := ""
	for path: String in files:
		var entry: Dictionary = files[path]
		stats[path] = _file_stats(entry, counts)
		lcov += _lcov(path, entry, counts)
		var unmeasured: int = entry["unmeasured"]
		if unmeasured > 0:
			var why := "%s: %d if or match chain(s) cannot be measured: run ./scripts/format.sh"
			problems.append(why % [path, unmeasured])
	var all := _sum(stats, files.keys())
	print("coverage: %s overall (floor %d%%)" % [_show(all), int(GLOBAL_MINIMUM)])
	problems.append_array(_floor("overall", all, GLOBAL_MINIMUM))
	if all["lines"] == 0:
		problems.append("no measured lines under src/")
	var tiers: Dictionary = config["tiers"]
	for name: String in tiers:
		var tier: Dictionary = tiers[name]
		var minimum: float = tier["minimum"]
		var include: Array = tier["include"]
		for member: Variant in include:
			if not files.has(member):
				problems.append(
					"%s: %s is not measured (in a folder with a .gdignore?)" % [name, member]
				)
		var sum := _sum(stats, include)
		print("  %-16s %s (minimum %s%%)" % [name, _show(sum), _number(minimum)])
		problems.append_array(_floor(name, sum, minimum))
	for path: String in stats:
		var missed: PackedStringArray = stats[path]["missed"]
		if not missed.is_empty():
			print("  not run in %s: %s" % [path, ", ".join(missed)])
	var journeys: Array = config.get("journeys", [])
	var outcomes: Array = results
	problems.append_array(_journeys(journeys, outcomes))
	if _options.has("lcov") and not _write(_option("lcov"), lcov):
		problems.append("cannot write " + _option("lcov"))
	return problems


## Lines and branches of one file: how many there are, how many ran, and which did not.
func _file_stats(entry: Dictionary, counts: Dictionary) -> Dictionary:
	var lines: Dictionary = entry["lines"]
	var stats := { "lines": lines.size(), "covered_lines": 0, "branches": 0, "covered_branches": 0 }
	var missed: PackedStringArray = []
	var by_id := { }
	for line: String in lines:
		by_id[_key(lines[line])] = line
		if _count(counts, lines[line]) > 0:
			stats["covered_lines"] += 1
		else:
			missed.append(line)
	for branch: Array in entry["branches"]:
		var arms: Array = branch[1]
		var taken_total := 0
		for arm: Variant in arms:
			var taken := _count(counts, arm)
			taken_total += taken
			stats["branches"] += 1
			if taken > 0:
				stats["covered_branches"] += 1
			else:
				missed.append("branch at %s" % by_id.get(_key(arm), "?"))
		if branch[2]:
			stats["branches"] += 1
			if _count(counts, branch[0]) - taken_total > 0:
				stats["covered_branches"] += 1
			else:
				missed.append("no-arm branch at %s" % by_id.get(_key(branch[0]), "?"))
	stats["missed"] = missed
	return stats


func _lcov(path: String, entry: Dictionary, counts: Dictionary) -> String:
	var out := "SF:%s\n" % path
	var lines: Dictionary = entry["lines"]
	var by_id := { }
	var hit_lines := 0
	for line: String in lines:
		by_id[_key(lines[line])] = line
		out += "DA:%s,%d\n" % [line, _count(counts, lines[line])]
		hit_lines += 1 if _count(counts, lines[line]) > 0 else 0
	var found := 0
	var hit := 0
	var branches: Array = entry["branches"]
	for chain: int in branches.size():
		var branch: Array = branches[chain]
		var header_line: String = by_id.get(_key(branch[0]), "0")
		var arms: Array = branch[1]
		var taken_total := 0
		var takes: Array[int] = []
		for arm: Variant in arms:
			takes.append(_count(counts, arm))
			taken_total += takes.back()
		if branch[2]:
			takes.append(_count(counts, branch[0]) - taken_total)
		for arm: int in takes.size():
			found += 1
			hit += 1 if takes[arm] > 0 else 0
			out += "BRDA:%s,%d,%d,%d\n" % [header_line, chain, arm, takes[arm]]
	out += "BRF:%d\nBRH:%d\nLF:%d\nLH:%d\nend_of_record\n" % [found, hit, lines.size(), hit_lines]
	return out


func _journeys(journeys: Array, results: Array) -> PackedStringArray:
	var problems: PackedStringArray = []
	var outcome := { }
	for result: Dictionary in results:
		outcome[result["id"]] = result["passed"]
	for journey: Variant in journeys:
		if not outcome.has(journey):
			problems.append("journey %s did not run" % journey)
		elif outcome[journey] != true:
			problems.append("journey %s failed" % journey)
	for id: Variant in outcome:
		if str(id).begins_with(JOURNEY_PREFIX) and not journeys.has(id):
			problems.append("%s is a journey test missing from coverage-tiers.json" % id)
	return problems


func _sum(stats: Dictionary, paths: Array) -> Dictionary:
	var total := { "lines": 0, "covered_lines": 0, "branches": 0, "covered_branches": 0 }
	for path: Variant in paths:
		var entry: Dictionary = stats.get(path, { })
		for key: String in total:
			var value: int = entry.get(key, 0)
			total[key] += value
	return total


func _floor(name: String, sum: Dictionary, minimum: float) -> PackedStringArray:
	var problems: PackedStringArray = []
	for kind: String in ["lines", "branches"]:
		var total: int = sum[kind]
		var covered: int = sum["covered_" + kind]
		if total > 0 and 100.0 * covered / total < minimum:
			problems.append("%s: %s below %s%%" % [name, kind, _number(minimum)])
	return problems


func _show(sum: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kind: String in ["lines", "branches"]:
		var total: int = sum[kind]
		var covered: int = sum["covered_" + kind]
		if total == 0:
			parts.append("%s n/a" % kind)
		else:
			parts.append("%s %.1f%% (%d/%d)" % [kind, 100.0 * covered / total, covered, total])
	return ", ".join(parts)


## [param value] as a person writes it: 90, or 92.5.
func _number(value: float) -> String:
	return str(int(value)) if value == floorf(value) else str(value)


func _count(counts: Dictionary, id: Variant) -> int:
	var count: float = counts.get(_key(id), 0)
	return int(count)


## The JSON key of probe [param id]: JSON reads every number back as a float.
func _key(id: Variant) -> String:
	var number: float = id
	return str(int(number))


func _option(name: String) -> String:
	return _options[name] if _options.has(name) else ""


func _is_percent(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and number >= 0.0 and number <= 100.0


func _is_source_path(path: Variant) -> bool:
	if typeof(path) != TYPE_STRING:
		return false
	var text := str(path)
	if not text.begins_with("src/") or not text.ends_with(".gd") or text.contains("\\"):
		return false
	for part: String in text.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true


func _read_json(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true
