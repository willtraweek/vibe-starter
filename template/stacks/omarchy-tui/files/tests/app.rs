//! The real event loop, driven by scripted key presses into a `TestBackend`.

use std::io;

use ::{{PACKAGE_NAME}}::app;
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Cell;
use ratatui::crossterm::event::{Event, KeyCode, KeyEvent};

/// One key press per character of `typed`.
fn keys(typed: &str) -> Vec<io::Result<Event>> {
    typed
        .chars()
        .map(|c| Ok(Event::Key(KeyEvent::from(KeyCode::Char(c)))))
        .collect()
}

fn terminal() -> Terminal<TestBackend> {
    Terminal::new(TestBackend::new(60, 12)).expect("terminal")
}

#[test]
fn keys_count_reset_and_quit() {
    let mut terminal = terminal();
    let model = app::run(&mut terminal, keys("  r q ")).expect("run");
    // The press after `q` is never read.
    assert_eq!(model.count(), 1);
    assert!(model.should_quit());
}

#[test]
fn the_screen_shows_the_latest_count() {
    let mut terminal = terminal();
    app::run(&mut terminal, keys("  ")).expect("run");
    let screen: String = terminal
        .backend()
        .buffer()
        .content
        .iter()
        .map(Cell::symbol)
        .collect();
    assert!(screen.contains("Pressed 2 times"), "screen: {screen:?}");
}

#[test]
fn other_events_and_unbound_keys_are_ignored() {
    let mut terminal = terminal();
    let mut events = vec![Ok(Event::FocusGained)];
    events.extend(keys("x "));
    let model = app::run(&mut terminal, events).expect("run");
    assert_eq!(model.count(), 1);
    assert!(!model.should_quit());
}

#[test]
fn a_resize_draws_again_without_waiting_for_a_key() {
    let mut terminal = terminal();
    let model = app::run(&mut terminal, vec![Ok(Event::Resize(80, 24))]).expect("run");
    assert_eq!(model.count(), 0);
    // Two frames: the first draw, and the resize's.
    assert_eq!(terminal.get_frame().count(), 2);
}

#[test]
fn a_read_error_ends_the_loop_with_that_error() {
    let mut terminal = terminal();
    let mut events = keys(" ");
    events.push(Err(io::Error::other("terminal went away")));
    let err = app::run(&mut terminal, events).expect_err("the error");
    assert_eq!(err.to_string(), "terminal went away");
}
