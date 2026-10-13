//! Drawing the model. Colours are the terminal's own: its 16 ANSI colours and
//! its default foreground and background, which Omarchy rewrites on every
//! `omarchy theme set`, so the app follows the theme with no code of its own.
//! `Color::Rgb` and `Color::Indexed` would stay put; `scripts/check.d` refuses
//! them.

use ratatui::Frame;
use ratatui::layout::{Constraint, Flex, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Paragraph};

use crate::model::Model;

/// The title on the box's top border.
pub const TITLE: &str = " {{PROJECT_NAME}} ";

/// Draws `model` centred in the frame.
pub fn render(model: Model, frame: &mut Frame) {
    // Wide enough for the title and the key hints; a narrow terminal cuts it.
    let width = u16::try_from(TITLE.chars().count() + 2).map_or(u16::MAX, |w| w.max(36));
    let [area] = Layout::vertical([Constraint::Length(5)])
        .flex(Flex::Center)
        .areas(frame.area());
    let [area] = Layout::horizontal([Constraint::Length(width)])
        .flex(Flex::Center)
        .areas(area);
    let accent = Style::new().fg(Color::Blue);
    let key = accent.add_modifier(Modifier::BOLD);
    let keys = Line::from(vec![
        Span::styled("space", key),
        Span::raw(" press  "),
        Span::styled("r", key),
        Span::raw(" reset  "),
        Span::styled("q", key),
        Span::raw(" quit"),
    ]);
    let block = Block::bordered().title(TITLE).border_style(accent);
    let text = vec![Line::from(model.label()), Line::default(), keys];
    frame.render_widget(Paragraph::new(text).block(block).centered(), area);
}
