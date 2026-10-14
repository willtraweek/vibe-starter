//! Pure-logic tests (TESTING.md tier 1): every rule of the window's state.

use ::{{PACKAGE_NAME}}::model::Counter;

#[test]
fn a_new_counter_starts_at_zero() {
    assert_eq!(Counter::default().count(), 0);
    assert_eq!(Counter::default().label(), "Not pressed yet");
}

#[test]
fn increment_counts_and_the_label_follows() {
    let mut counter = Counter::default();
    counter.increment();
    assert_eq!(counter.label(), "Pressed once");
    counter.increment();
    assert_eq!(counter.count(), 2);
    assert_eq!(counter.label(), "Pressed 2 times");
}

#[test]
fn increment_saturates_instead_of_wrapping() {
    let mut counter = Counter::starting_at(u32::MAX);
    counter.increment();
    assert_eq!(counter.count(), u32::MAX);
}

#[test]
fn reset_goes_back_to_zero() {
    let mut counter = Counter::starting_at(7);
    counter.reset();
    assert_eq!(counter, Counter::default());
}
