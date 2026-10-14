//! The screen (TESTING.md tier 3), drawn into ratatui's `TestBackend`.

use ::{{PACKAGE_NAME}}::model::{Action, Model};
use ::{{PACKAGE_NAME}}::view;
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::style::Color;

fn draw(model: Model, width: u16, height: u16) -> Buffer {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|frame| view::render(model, frame))
        .expect("draw");
    terminal.backend().buffer().clone()
}

fn text(buffer: &Buffer) -> String {
    let area = buffer.area;
    (area.top()..area.bottom())
        .map(|y| {
            (area.left()..area.right())
                .map(|x| buffer[(x, y)].symbol())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn the_screen_shows_the_title_the_count_and_the_keys() {
    let mut model = Model::default();
    model.update(Action::Increment);
    let screen = text(&draw(model, 160, 12));
    for expected in [view::TITLE.trim(), "Pressed once", "space press", "r reset", "q quit"] {
        assert!(screen.contains(expected), "missing {expected:?} in\n{screen}");
    }
}

/// Named invariant: every cell uses the terminal's own colours (the 16 ANSI
/// colours or its default), which Omarchy rewrites on `omarchy theme set`.
#[test]
fn every_cell_uses_theme_colours() {
    let buffer = draw(Model::default(), 160, 12);
    for cell in &buffer.content {
        for colour in [cell.fg, cell.bg] {
            assert!(
                !matches!(colour, Color::Rgb(..) | Color::Indexed(_)),
                "{colour:?} ignores the Omarchy theme"
            );
        }
    }
}

#[test]
fn a_tiny_terminal_still_draws() {
    let buffer = draw(Model::default(), 8, 2);
    assert_eq!(buffer.area.width, 8);
}
