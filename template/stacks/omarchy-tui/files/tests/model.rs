//! Pure-logic tests (TESTING.md tier 1): the key map and every state change.

use ::{{PACKAGE_NAME}}::model::{Action, Model, action_for};
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

fn press(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

#[test]
fn the_key_map() {
    assert_eq!(
        action_for(press(KeyCode::Char(' '))),
        Some(Action::Increment)
    );
    assert_eq!(action_for(press(KeyCode::Char('r'))), Some(Action::Reset));
    assert_eq!(action_for(press(KeyCode::Char('q'))), Some(Action::Quit));
    assert_eq!(action_for(press(KeyCode::Esc)), Some(Action::Quit));
    let ctrl_c = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    assert_eq!(action_for(ctrl_c), Some(Action::Quit));
    assert_eq!(action_for(press(KeyCode::Char('c'))), None);
    assert_eq!(action_for(press(KeyCode::Enter)), None);
}

#[test]
fn key_releases_do_nothing() {
    let mut release = press(KeyCode::Char(' '));
    release.kind = KeyEventKind::Release;
    assert_eq!(action_for(release), None);
}

#[test]
fn increment_counts_and_the_label_follows() {
    let mut model = Model::default();
    assert_eq!(model.label(), "Not pressed yet");
    model.update(Action::Increment);
    assert_eq!(model.label(), "Pressed once");
    model.update(Action::Increment);
    assert_eq!(model.count(), 2);
    assert_eq!(model.label(), "Pressed 2 times");
}

#[test]
fn increment_saturates_instead_of_wrapping() {
    let mut model = Model::starting_at(u32::MAX);
    model.update(Action::Increment);
    assert_eq!(model.count(), u32::MAX);
}

#[test]
fn reset_goes_to_zero_and_quit_is_remembered() {
    let mut model = Model::starting_at(7);
    model.update(Action::Reset);
    assert_eq!(model.count(), 0);
    assert!(!model.should_quit());
    model.update(Action::Quit);
    assert!(model.should_quit());
}
