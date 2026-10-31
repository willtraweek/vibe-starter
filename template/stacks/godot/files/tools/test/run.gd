extends SceneTree
## Runs the tests: each test_* method of each res://tests/**/test_*.gd, on a fresh instance.
##
## ./scripts/test.sh runs this headless at a fixed 60 frames a second. Arguments after --:
##   <filter>           run only the tests whose id (path::method) contains it
##   --check-only       load every script, scene and resource, and run no tests
##   --results <file>   write each test's id and outcome to <file> as JSON
##   --coverage <file>  write the coverage probes' counts to <file> (./scripts/coverage.sh)
##   --timeout <ms>     fail a test still running after <ms> milliseconds (30000)
## A test fails on a failed assertion, on any error Godot reports while it runs, on nodes
## it leaves behind, and when it runs for longer than the timeout. No test, no pass.

const ErrorLog := preload("res://tools/test/error_log.gd")
const Probe := preload("res://tools/coverage/probe.gd")
const TESTS_DIR := "res://tests"
const TEST_TIMEOUT_MS := 30000
const RESOURCE_EXTENSIONS: PackedStringArray = ["tscn", "scn", "tres", "res"]

var _log := ErrorLog.new()
var _filter := ""
var _check_only := false
var _results_path := ""
var _coverage_path := ""
var _timeout_ms := TEST_TIMEOUT_MS
var _results: Array[Dictionary] = []
var _last_progress_ms := 0
var _stopped := false


func _init() -> void:
	OS.add_logger(_log)
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--check-only":
				_check_only = true
			"--results":
				i += 1
				_results_path = args[i] if i < args.size() else ""
			"--coverage":
				i += 1
				_coverage_path = args[i] if i < args.size() else ""
			"--timeout":
				i += 1
				_timeout_ms = args[i].to_int() if i < args.size() else TEST_TIMEOUT_MS
			_:
				_filter = args[i]
		i += 1
	_last_progress_ms = Time.get_ticks_msec()
	_main.call_deferred()


## The watchdog: a test that never finishes, or a crash in this runner, can't hang the run.
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _last_progress_ms > _timeout_ms + 5000:
		printerr("tests: the run stopped making progress; giving up")
		quit(1)
	return false


func _main() -> void:
	await process_frame # Autoloads join the tree once the main loop runs.
	if _check_only:
		_finish(_check_everything())
		return
	var passed := 0
	var failed := 0
	for path: String in _find(TESTS_DIR, "test_", ".gd"):
		var script := load(path) as GDScript
		var load_errors := _log.take()
		if script == null or not load_errors.is_empty():
			load_errors.append("does not load")
			_report(path.trim_prefix("res://"), load_errors)
			failed += 1
			continue
		var methods := _test_methods(script)
		if methods.is_empty() and _filter.is_empty():
			_report(path.trim_prefix("res://"), ["has no test_* methods"])
			failed += 1
		for method: String in methods:
			var id := "%s::%s" % [path.trim_prefix("res://"), method]
			if not _filter.is_empty() and not id.contains(_filter):
				continue
			var problems: PackedStringArray = await _run_one(script, method, id)
			if _stopped:
				return
			_report(id, problems)
			if problems.is_empty():
				passed += 1
			else:
				failed += 1
	var summary := "tests: %d passed, %d failed" % [passed, failed]
	if not _filter.is_empty():
		summary += " (filter: %s)" % _filter
	print(summary)
	if passed + failed == 0:
		printerr("tests: no tests ran")
	_finish(failed == 0 and passed > 0)


## Runs one test and returns why it failed: empty when it passed.
func _run_one(script: GDScript, method: String, id: String) -> PackedStringArray:
	var instance: Variant = script.new()
	if not instance is TestCase:
		return ["%s does not extend TestCase" % script.resource_path]
	var case: TestCase = instance
	var context := TestCase.Context.new()
	context.tree = self
	case.context = context
	var orphans_before := _orphans()
	_log.take()
	_last_progress_ms = Time.get_ticks_msec()
	var state := { "done": false }
	var body := func() -> void:
		await case.call("before_each")
		await case.call(method)
		await case.call("after_each")
		state["done"] = true
	body.call()
	while not state["done"]:
		if Time.get_ticks_msec() - _last_progress_ms > _timeout_ms:
			var stuck := "still running after %d ms: awaiting a signal that never comes?"
			_report(id, [stuck % _timeout_ms])
			_finish(false)
			return []
		await process_frame
	for action: StringName in context.pressed:
		Input.action_release(action)
	for node: Node in context.nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	var problems := context.failures
	var errors := _log.take()
	for expected: String in context.expected_errors:
		var found := -1
		for i: int in errors.size():
			if errors[i].contains(expected):
				found = i
				break
		if found == -1:
			problems.append("expected an error containing \"%s\"; none came" % expected)
		else:
			errors.remove_at(found)
	for error: String in errors:
		problems.append("error: " + error)
	var leaked := _orphans() - orphans_before
	if leaked > 0:
		problems.append("left %d node(s) outside the tree: free them, or add() them" % leaked)
	_last_progress_ms = Time.get_ticks_msec()
	return problems


## Loads every script, scene and resource; true when all load without an error.
func _check_everything() -> bool:
	var problems: PackedStringArray = []
	var scripts := _find("res://", "", ".gd")
	for path: String in scripts:
		var script := load(path) as Script
		for error: String in _log.take():
			problems.append("%s: %s" % [path, error])
		if script == null or not (script.can_instantiate() or script.is_abstract()):
			problems.append("%s does not compile" % path)
	var resources := 0
	for extension: String in RESOURCE_EXTENSIONS:
		for path: String in _find("res://", "", "." + extension):
			resources += 1
			var resource := load(path)
			for error: String in _log.take():
				problems.append("%s: %s" % [path, error])
			if resource == null:
				problems.append("%s does not load" % path)
	for problem: String in problems:
		printerr("check: " + problem)
	print("check: %d scripts and %d scenes and resources load" % [scripts.size(), resources])
	return problems.is_empty()


func _test_methods(script: GDScript) -> PackedStringArray:
	var methods: PackedStringArray = []
	if script == null:
		return methods
	for method: Dictionary in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("test_") and not methods.has(name):
			methods.append(name)
	return methods


## Every file under [param dir] named <prefix>*<suffix>, sorted. Skips hidden folders and
## folders with a .gdignore, as the editor does.
func _find(dir: String, prefix: String, suffix: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var access := DirAccess.open(dir)
	if access == null or FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for file: String in access.get_files():
		if file.begins_with(prefix) and file.ends_with(suffix):
			found.append(dir.path_join(file))
	for sub: String in access.get_directories():
		found.append_array(_find(dir.path_join(sub), prefix, suffix))
	found.sort()
	return found


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _report(id: String, problems: PackedStringArray) -> void:
	_results.append({ "id": id, "passed": problems.is_empty() })
	if problems.is_empty():
		print("  ok   " + id)
		return
	print("  FAIL " + id)
	for problem: String in problems:
		print("       " + problem)


func _finish(ok: bool) -> void:
	_stopped = true
	if not _results_path.is_empty():
		var results := FileAccess.open(_results_path, FileAccess.WRITE)
		if results == null:
			printerr("tests: cannot write " + _results_path)
			ok = false
		else:
			results.store_string(JSON.stringify(_results, "  ") + "\n")
	if not _coverage_path.is_empty() and Probe.save(_coverage_path) != OK:
		printerr("tests: cannot write " + _coverage_path)
		ok = false
	OS.remove_logger(_log)
	quit(0 if ok else 1)
