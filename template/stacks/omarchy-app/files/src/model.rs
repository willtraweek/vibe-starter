//! The window's state without GPUI: what each action does to it. Pure, so it
//! is held to the pure-logic tier (100% lines and regions).

/// How many times the main action ran.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counter {
    count: u32,
}

impl Counter {
    /// A counter that starts at `count`.
    #[must_use]
    pub const fn starting_at(count: u32) -> Self {
        Self { count }
    }

    /// The current count.
    #[must_use]
    pub const fn count(self) -> u32 {
        self.count
    }

    /// One more, stopping at `u32::MAX` instead of wrapping to zero.
    pub const fn increment(&mut self) {
        self.count = self.count.saturating_add(1);
    }

    /// Back to zero.
    pub const fn reset(&mut self) {
        self.count = 0;
    }

    /// What the window shows.
    #[must_use]
    pub fn label(self) -> String {
        match self.count {
            0 => "Not pressed yet".to_owned(),
            1 => "Pressed once".to_owned(),
            n => format!("Pressed {n} times"),
        }
    }
}
