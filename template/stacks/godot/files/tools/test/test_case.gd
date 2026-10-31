class_name TestCase
extends RefCounted
## The base of every test file under res://tests: assertions, and scene and input helpers.
##
## Each method whose name starts with test_ is one test, run on a fresh instance. It may
## await. before_each() and after_each() run around it. When it ends, pass or fail, every
## node add() put in the tree is freed and every press() is released.


## What one test has recorded. The runner creates it and reads it; tests use the helpers.
class Context:
	extends RefCounted
	var tree: SceneTree
	var failures: PackedStringArray = []
	var nodes: Array[Node] = []
	var pressed: Array[StringName] = []
	var expected_errors: PackedStringArray = []


## Every emission of one signal, oldest first: each entry holds that emission's arguments.
class SignalRecorder:
	extends RefCounted
	var emissions: Array[Array] = []


	func record(...args: Array) -> void:
		emissions.append(args)


const SELF_PATH := "res://tools/test/test_case.gd"

## Set by the runner before the test starts.
var context: Context


## Runs before each test of this file. Override it; it may await.
func before_each() -> void:
	pass


## Runs after each test of this file, even one that failed. Override it; it may await.
func after_each() -> void:
	pass


## The scene tree the tests run in.
func tree() -> SceneTree:
	return context.tree


## Adds [param node] under the tree's root for this test. It is freed when the test ends.
func add(node: Node) -> Node:
	context.tree.root.add_child(node)
	context.nodes.append(node)
	return node


## Instantiates [param scene] under the tree's root for this test.
func add_scene(scene: PackedScene) -> Node:
	return add(scene.instantiate())


## Waits until [param count] frames have been processed.
func frames(count: int = 1) -> void:
	for _i: int in count:
		await context.tree.process_frame


## Waits until [param count] physics ticks have run: 1/60 s of game time each.
func physics_frames(count: int = 1) -> void:
	for _i: int in count:
		await context.tree.physics_frame


## Holds [param action] down, as a player would, until release() or the end of the test.
func press(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)
	if not context.pressed.has(action):
		context.pressed.append(action)


## Lets go of [param action].
func release(action: StringName) -> void:
	Input.action_release(action)
	context.pressed.erase(action)


## Starts recording [param signal_name] on [param emitter] for the rest of the test.
func watch(emitter: Object, signal_name: StringName) -> SignalRecorder:
	var recorder := SignalRecorder.new()
	emitter.connect(signal_name, recorder.record)
	return recorder


## Expects an error whose message contains [param text] during this test. That error
## does not fail the test; the test fails if it never comes.
func expect_error(text: String) -> void:
	context.expected_errors.append(text)


## Fails the test with [param reason].
func fail(reason: String) -> void:
	_fail(reason, "")


func assert_true(condition: bool, note: String = "") -> bool:
	if condition:
		return true
	return _fail("expected true, got false", note)


func assert_false(condition: bool, note: String = "") -> bool:
	if not condition:
		return true
	return _fail("expected false, got true", note)


## Passes when both are the same value: equal and of the same type, except that an int
## equals the same float and a String the same StringName.
func assert_eq(actual: Variant, expected: Variant, note: String = "") -> bool:
	if same(actual, expected):
		return true
	return _fail("expected %s, got %s" % [show(expected), show(actual)], note)


func assert_ne(actual: Variant, unexpected: Variant, note: String = "") -> bool:
	if not same(actual, unexpected):
		return true
	return _fail("expected anything but %s" % show(unexpected), note)


## Passes when [param actual] is within [param tolerance] of [param expected]: two numbers,
## or two Vector2s or Vector3s (by distance).
func assert_almost_eq(
	actual: Variant,
	expected: Variant,
	tolerance: float = 0.00001,
	note: String = "",
) -> bool:
	var gap := INF
	if _is_number(typeof(actual)) and _is_number(typeof(expected)):
		var a: float = actual
		var e: float = expected
		gap = absf(a - e)
	elif typeof(actual) == TYPE_VECTOR2 and typeof(expected) == TYPE_VECTOR2:
		var a: Vector2 = actual
		var e: Vector2 = expected
		gap = a.distance_to(e)
	elif typeof(actual) == TYPE_VECTOR3 and typeof(expected) == TYPE_VECTOR3:
		var a: Vector3 = actual
		var e: Vector3 = expected
		gap = a.distance_to(e)
	if gap <= tolerance:
		return true
	return _fail(
		"expected %s within %s, got %s" % [show(expected), show(tolerance), show(actual)],
		note,
	)


## Passes for null, and for an object that has been freed.
func assert_null(value: Variant, note: String = "") -> bool:
	if _is_null(value):
		return true
	return _fail("expected null, got %s" % show(value), note)


func assert_not_null(value: Variant, note: String = "") -> bool:
	if not _is_null(value):
		return true
	return _fail("expected a value, got null", note)


## Passes when [param container] holds [param item]: an element of an Array or a
## PackedStringArray, a key of a Dictionary, or a substring of a String.
func assert_has(container: Variant, item: Variant, note: String = "") -> bool:
	var found := false
	match typeof(container):
		TYPE_ARRAY:
			var array: Array = container
			found = array.has(item)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = container
			found = typeof(item) in [TYPE_STRING, TYPE_STRING_NAME] and strings.has(str(item))
		TYPE_DICTIONARY:
			var dictionary: Dictionary = container
			found = dictionary.has(item)
		TYPE_STRING, TYPE_STRING_NAME:
			found = (
				typeof(item) in [TYPE_STRING, TYPE_STRING_NAME]
				and str(container).contains(str(item))
			)
		_:
			return _fail(
				"assert_has needs an Array, a Dictionary or a String, got %s" % show(container),
				note,
			)
	if found:
		return true
	return _fail("expected %s to hold %s" % [show(container), show(item)], note)


## True when [param a] and [param b] are the same value, as assert_eq() means it.
static func same(a: Variant, b: Variant) -> bool:
	var type_a := typeof(a)
	var type_b := typeof(b)
	if type_a == type_b:
		return a == b
	if _is_number(type_a) and _is_number(type_b):
		var number_a: float = a
		var number_b: float = b
		return number_a == number_b
	if type_a in [TYPE_STRING, TYPE_STRING_NAME] and type_b in [TYPE_STRING, TYPE_STRING_NAME]:
		return str(a) == str(b)
	return false


## How a failure message shows [param value]: as GDScript would write it.
static func show(value: Variant) -> String:
	if typeof(value) == TYPE_OBJECT:
		return str(value)
	return var_to_str(value)


static func _is_number(type: int) -> bool:
	return type == TYPE_INT or type == TYPE_FLOAT


static func _is_null(value: Variant) -> bool:
	if typeof(value) == TYPE_NIL:
		return true
	return typeof(value) == TYPE_OBJECT and not is_instance_valid(value)


func _fail(what: String, note: String) -> bool:
	var message := what if note.is_empty() else "%s: %s" % [note, what]
	context.failures.append("%s (%s)" % [message, _caller()])
	return false


## Where the failing assertion is: the first frame outside this file.
func _caller() -> String:
	for backtrace: ScriptBacktrace in Engine.capture_script_backtraces():
		for frame: int in backtrace.get_frame_count():
			var file := backtrace.get_frame_file(frame)
			if file != SELF_PATH:
				return "%s:%d" % [file.trim_prefix("res://"), backtrace.get_frame_line(frame)]
	return "line unknown"
