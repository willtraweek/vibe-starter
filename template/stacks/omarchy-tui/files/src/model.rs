//! The app's state and what each key does to it, without a terminal. Pure, so
//! it is held to the pure-logic tier (100% lines and regions).

use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

/// Something the user asked for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    /// Count one more press.
    Increment,
    /// Start counting from zero again.
    Reset,
    /// Leave the app.
    Quit,
}

/// The key map. Key releases and keys that mean nothing give `None`.
#[must_use]
pub fn action_for(key: KeyEvent) -> Option<Action> {
    if key.kind != KeyEventKind::Press {
        return None;
    }
    let control = key.modifiers.contains(KeyModifiers::CONTROL);
    match key.code {
        KeyCode::Char('c') if control => Some(Action::Quit),
        KeyCode::Char(' ') => Some(Action::Increment),
        KeyCode::Char('r') => Some(Action::Reset),
        KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
        _ => None,
    }
}

/// The app's state.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Model {
    count: u32,
    quit: bool,
}

impl Model {
    /// A model whose count starts at `count`.
    #[must_use]
    pub const fn starting_at(count: u32) -> Self {
        Self { count, quit: false }
    }

    /// How many presses were counted.
    #[must_use]
    pub const fn count(self) -> u32 {
        self.count
    }

    /// Whether the user asked to leave.
    #[must_use]
    pub const fn should_quit(self) -> bool {
        self.quit
    }

    /// Applies `action`. Counting stops at `u32::MAX` instead of wrapping.
    pub const fn update(&mut self, action: Action) {
        match action {
            Action::Increment => self.count = self.count.saturating_add(1),
            Action::Reset => self.count = 0,
            Action::Quit => self.quit = true,
        }
    }

    /// What the screen shows.
    #[must_use]
    pub fn label(self) -> String {
        match self.count {
            0 => "Not pressed yet".to_owned(),
            1 => "Pressed once".to_owned(),
            n => format!("Pressed {n} times"),
        }
    }
}
