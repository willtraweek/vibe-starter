extends TestCase


func test_collecting_adds_a_point_and_says_so() -> void:
	var score := Score.new()
	var changes := watch(score, &"changed")
	score.collect()
	score.collect()
	assert_eq(score.points, 2)
	assert_eq(changes.emissions, [[1], [2]])


func test_reset_starts_the_round_over() -> void:
	var score := Score.new()
	score.collect()
	var changes := watch(score, &"changed")
	score.reset()
	assert_eq(score.points, 0)
	assert_eq(changes.emissions, [[0]])
