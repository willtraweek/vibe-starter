extends RefCounted
## Rewrites one GDScript file so each statement counts its runs, keeping every line where it
## was: the probe call goes in front of the statement, on the statement's own line.
##
## A statement starts a logical line inside a function, a property accessor or a lambda.
## These are not statements: a line that continues a bracket, a string or a backslash; an
## elif or else line; a match pattern. An annotation on a line of its own applies to the
## statement after it, so that statement's probe goes in front of the annotation instead.
## Branches are the arms of each if chain and each match: an arm counts its first statement.
## A chain without else, and a match without a catch-all pattern, has one more arm: it ran
## whenever the if or match line ran and no arm did.

enum Kind {
	CLASS,
	CODE,
	ACCESSORS,
	PATTERNS,
}

## An arm whose first statement is still to come.
const PENDING := -2
## An arm, or an if or match line, that has no probe of its own.
const UNMEASURED := -1
const PROBE := "preload(\"res://tools/coverage/probe.gd\").hit(%d); "


## A block of lines: a class body, a function or arm body, accessors or match patterns.
class Block:
	extends RefCounted
	var kind: Kind
	var opener: int
	var indent := -1
	var chain: Chain = null
	var arm := -1
	var seen := false
	var last_if: Chain = null


	func _init(block_kind: Kind, opener_indent: int) -> void:
		kind = block_kind
		opener = opener_indent


## An if chain or a match: the probe on its line, and each arm's first probe.
class Chain:
	extends RefCounted
	var header := UNMEASURED
	var arms: Array[int] = []
	var implicit := true


## One logical line: where it starts and ends, its indentation and its code without
## comments or the text of its strings.
class Logical:
	extends RefCounted
	var first: int
	var indent: int
	var code := ""


static var _lambda := RegEx.create_from_string("(^|[^A-Za-z0-9_])func([^A-Za-z0-9_]|$)")


## Returns the rewritten source ("source"), the probe of each probed line ("lines": line
## number to probe id), the measurable branches ("branches": [if or match probe, [arm
## probes], has an implicit arm]), how many chains could not be measured ("unmeasured") and
## the next free probe id ("next_id"). Probe ids start at [param first_id].
func instrument(source: String, first_id: int) -> Dictionary:
	var lines := source.split("\n")
	var probes: Dictionary[int, int] = { }
	var reported: Dictionary[int, int] = { }
	var next_id := first_id
	var chains: Array[Chain] = []
	var stack: Array[Block] = [Block.new(Kind.CLASS, -1)]
	stack[0].indent = 0
	var pending := UNMEASURED
	for line: Logical in _logical_lines(lines):
		var top := _top(stack)
		if top.indent == -1:
			if line.indent > top.opener:
				top.indent = line.indent
			else:
				stack.pop_back()
		while stack.size() > 1 and line.indent < _top(stack).indent:
			stack.pop_back()
		top = _top(stack)
		var rest := _after_annotations(line.code)
		var word := _first_word(rest)
		var opens := rest.ends_with(":")
		match top.kind:
			Kind.CLASS:
				if opens:
					stack.append(Block.new(_class_member_body(rest, word), line.indent))
			Kind.ACCESSORS:
				if opens:
					stack.append(Block.new(Kind.CODE, line.indent))
			Kind.PATTERNS:
				var chain := top.chain
				if _catch_all(rest):
					chain.implicit = false
				if opens:
					chain.arms.append(PENDING)
					stack.append(_arm(Kind.CODE, line.indent, chain))
				else:
					chain.arms.append(UNMEASURED)
			Kind.CODE:
				var probe := UNMEASURED
				if line.code.begins_with("@") and rest.is_empty():
					if pending == UNMEASURED and _binds(line.code):
						pending = next_id
						next_id += 1
						probes[line.first] = pending
					probe = pending
				elif word == "elif" or word == "else":
					var chain := top.last_if
					if chain != null:
						if word == "else":
							chain.implicit = false
						if opens:
							chain.arms.append(PENDING)
							stack.append(_arm(Kind.CODE, line.indent, chain))
						else:
							chain.arms.append(UNMEASURED)
				else:
					top.last_if = null
					probe = pending
					pending = UNMEASURED
					if probe == UNMEASURED:
						probe = next_id
						next_id += 1
						probes[line.first] = probe
					reported[probe] = line.first + 1
					if opens and word == "if":
						var chain := Chain.new()
						chain.header = probe
						chain.arms.append(PENDING)
						chains.append(chain)
						top.last_if = chain
						stack.append(_arm(Kind.CODE, line.indent, chain))
					elif opens and word == "match":
						var chain := Chain.new()
						chain.header = probe
						chains.append(chain)
						var patterns := Block.new(Kind.PATTERNS, line.indent)
						patterns.chain = chain
						stack.append(patterns)
					elif opens:
						stack.append(Block.new(Kind.CODE, line.indent))
				if top.chain != null and not top.seen and probe != UNMEASURED:
					top.seen = true
					top.chain.arms[top.arm] = probe
	return _result(lines, probes, reported, chains, next_id)


## False for the region annotations, which apply up to their restore rather than to the
## statement after them.
func _binds(code: String) -> bool:
	var name := _first_word(code.substr(1))
	return name != "warning_ignore_start" and name != "warning_ignore_restore"


func _top(stack: Array[Block]) -> Block:
	return stack[stack.size() - 1]


## What a class-level line that ends with a colon opens: a function or a lambda's body, a
## property's accessors, or an inner class.
func _class_member_body(rest: String, word: String) -> Kind:
	var second := _first_word(rest.substr(word.length()).strip_edges())
	if word == "func" or (word == "static" and second == "func"):
		return Kind.CODE
	if (word == "var" or word == "static") and _lambda.search(rest) != null:
		return Kind.CODE
	if word == "var" or (word == "static" and second == "var"):
		return Kind.ACCESSORS
	return Kind.CLASS


func _arm(kind: Kind, opener: int, chain: Chain) -> Block:
	var block := Block.new(kind, opener)
	block.chain = chain
	block.arm = chain.arms.size() - 1
	return block


func _result(
	lines: PackedStringArray,
	probes: Dictionary[int, int],
	reported: Dictionary[int, int],
	chains: Array[Chain],
	next_id: int,
) -> Dictionary:
	var by_line := { }
	for index: int in probes:
		var text := lines[index]
		var indent := text.length() - text.strip_edges(true, false).length()
		lines[index] = text.substr(0, indent) + PROBE % probes[index] + text.substr(indent)
	for probe: int in reported:
		by_line[reported[probe]] = probe
	var branches: Array = []
	var unmeasured := 0
	for chain: Chain in chains:
		var measurable := chain.header >= 0 and not chain.arms.is_empty()
		for arm: int in chain.arms:
			measurable = measurable and arm >= 0
		if measurable:
			branches.append([chain.header, chain.arms, chain.implicit])
		else:
			unmeasured += 1
	return {
		"source": "\n".join(lines),
		"lines": by_line,
		"branches": branches,
		"unmeasured": unmeasured,
		"next_id": next_id,
	}


## Splits [param lines] into logical lines, skipping blank and comment-only ones.
func _logical_lines(lines: PackedStringArray) -> Array[Logical]:
	var found: Array[Logical] = []
	var current: Logical = null
	var quote := ""
	var depth := 0
	for index: int in lines.size():
		var text := lines[index].trim_suffix("\r")
		var code := ""
		var i := 0
		while i < text.length():
			var c := text[i]
			if not quote.is_empty():
				if c == "\\":
					i += 2
					continue
				if text.substr(i, quote.length()) == quote:
					code += "\""
					i += quote.length()
					quote = ""
					continue
				i += 1
				continue
			if c == "#":
				break
			if c == "\"" or c == "'":
				quote = c.repeat(3) if text.substr(i, 3) == c.repeat(3) else c
				code += "\""
				i += quote.length()
				continue
			if c in ["(", "[", "{"]:
				depth += 1
			elif c in [")", "]", "}"]:
				depth = maxi(depth - 1, 0)
			code += c
			i += 1
		if current == null:
			if code.strip_edges().is_empty():
				continue
			current = Logical.new()
			current.first = index
			current.indent = code.length() - code.strip_edges(true, false).length()
		current.code += " " + code.strip_edges()
		var joined := code.strip_edges(false, true).ends_with("\\")
		if depth == 0 and quote.is_empty() and not joined:
			current.code = current.code.strip_edges()
			found.append(current)
			current = null
	if current != null:
		current.code = current.code.strip_edges()
		found.append(current)
	return found


## [param code] without the annotations in front of it.
func _after_annotations(code: String) -> String:
	var rest := code
	while rest.begins_with("@"):
		var end := 1
		while end < rest.length() and _word_char(rest[end]):
			end += 1
		rest = rest.substr(end).strip_edges(true, false)
		if rest.begins_with("("):
			var depth := 0
			var close := 0
			while close < rest.length():
				if rest[close] == "(":
					depth += 1
				elif rest[close] == ")":
					depth -= 1
					if depth == 0:
						break
				close += 1
			rest = rest.substr(close + 1).strip_edges(true, false)
	return rest


func _first_word(code: String) -> String:
	var end := 0
	while end < code.length() and _word_char(code[end]):
		end += 1
	return code.substr(0, end)


func _word_char(c: String) -> bool:
	var point := c.unicode_at(0)
	return (
		point == 95 or (point >= 48 and point <= 57)
		or (point >= 65 and point <= 90) or (point >= 97 and point <= 122)
	)


## True for a match pattern that matches anything: _ or a bare var binding, without a guard.
func _catch_all(pattern: String) -> bool:
	var body := pattern.trim_suffix(":").strip_edges()
	if (" " + body + " ").contains(" when "):
		return false
	var depth := 0
	var start := 0
	var alternatives: PackedStringArray = []
	for i: int in body.length():
		var c := body[i]
		if c in ["(", "[", "{"]:
			depth += 1
		elif c in [")", "]", "}"]:
			depth -= 1
		elif c == "," and depth == 0:
			alternatives.append(body.substr(start, i - start))
			start = i + 1
	alternatives.append(body.substr(start))
	for alternative: String in alternatives:
		var option := alternative.strip_edges()
		if option == "_":
			return true
		if option.begins_with("var ") and option.substr(4).strip_edges().is_valid_identifier():
			return true
	return false
