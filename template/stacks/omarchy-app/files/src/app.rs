//! The main window: a panel that counts presses, in the active Omarchy theme.
//!
//! Colours, type and spacing come from gpui-omarchy (`cx.omarchy()` and its
//! components), which follows `omarchy theme set` live. Never hardcode them.

use gpui_kit::{
    App, AppContext as _, Context, FocusHandle, Focusable, InteractiveElement as _, IntoElement,
    KeyBinding, ParentElement as _, Render, Styled as _, TitlebarOptions, Window, WindowHandle,
    WindowOptions, actions, div, rems,
};
use gpui_omarchy::{ActiveTheme as _, ButtonVariant, button, focus_scope, keycap, panel};

use crate::model::Counter;

/// The key context the window's bindings are scoped to.
const KEY_CONTEXT: &str = "MainWindow";

actions!(
    {{PACKAGE_NAME}},
    [
        /// Count one more press.
        Increment,
        /// Start counting from zero again.
        Reset,
        /// Quit the application.
        Quit,
    ]
);

/// Registers the Omarchy theme, the key bindings and quit-on-close. Call it
/// once at startup, before opening a window.
pub fn init(cx: &mut App) {
    gpui_omarchy::init(cx);
    cx.bind_keys([
        KeyBinding::new("space", Increment, Some(KEY_CONTEXT)),
        KeyBinding::new("r", Reset, Some(KEY_CONTEXT)),
        KeyBinding::new("q", Quit, Some(KEY_CONTEXT)),
        KeyBinding::new("ctrl-q", Quit, None),
    ]);
    cx.on_action(|_: &Quit, cx| cx.quit());
    // One window is the whole app: closing it (super+w on Omarchy) quits.
    cx.on_window_closed(|cx, _| {
        if cx.windows().is_empty() {
            cx.quit();
        }
    })
    .detach();
}

/// Starts the app inside a running GPUI application: the theme, the key
/// bindings and the main window, focused. `main` hands this to
/// `gpui_kit::application().run`; tests call it on a test application.
pub fn start(cx: &mut App) {
    init(cx);
    open_window(cx);
    cx.activate(true);
}

/// The main window's options. `app_id` is the class Hyprland window rules match.
#[must_use]
pub fn window_options() -> WindowOptions {
    WindowOptions {
        titlebar: Some(TitlebarOptions {
            title: Some("{{PROJECT_NAME}}".into()),
            ..TitlebarOptions::default()
        }),
        app_id: Some(crate::APP_ID.to_owned()),
        ..WindowOptions::default()
    }
}

/// Opens the main window with the keyboard on its root.
///
/// # Panics
///
/// When the platform cannot open a window.
pub fn open_window(cx: &mut App) -> WindowHandle<MainWindow> {
    let window = cx
        .open_window(window_options(), |_, cx| cx.new(MainWindow::new))
        .expect("open the main window");
    window
        .update(cx, |view, window, cx| window.focus(&view.focus, cx))
        .expect("focus the main window");
    window
}

/// The main window's root view.
pub struct MainWindow {
    counter: Counter,
    focus: FocusHandle,
}

impl MainWindow {
    /// A fresh window state.
    pub fn new(cx: &mut Context<Self>) -> Self {
        Self {
            counter: Counter::default(),
            focus: cx.focus_handle(),
        }
    }

    /// What the window is counting.
    #[must_use]
    pub const fn counter(&self) -> Counter {
        self.counter
    }

    fn increment(&mut self, cx: &mut Context<Self>) {
        self.counter.increment();
        cx.notify();
    }

    fn reset(&mut self, cx: &mut Context<Self>) {
        self.counter.reset();
        cx.notify();
    }
}

impl Focusable for MainWindow {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for MainWindow {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let background = cx.omarchy().background;
        // GPUI dispatches a key along the path from the window's root to the
        // focused element, so the focus scope (Tab and Shift+Tab) must enclose
        // the root the window focuses, not sit inside it.
        focus_scope("main-window").size_full().child(
            div()
                .track_focus(&self.focus)
                .key_context(KEY_CONTEXT)
                .on_action(cx.listener(|this, _: &Increment, _, cx| this.increment(cx)))
                .on_action(cx.listener(|this, _: &Reset, _, cx| this.reset(cx)))
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .bg(background)
                .child(
                    panel("{{PROJECT_NAME}}", cx)
                        .child(self.counter.label())
                        .child(
                            div().debug_selector(|| "press".into()).child(
                                button("press", "Press", ButtonVariant::Primary, cx)
                                    .on_click(cx.listener(|this, _, _, cx| this.increment(cx))),
                            ),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(rems(0.5))
                                .child(keycap("space", cx))
                                .child("press")
                                .child(keycap("r", cx))
                                .child("reset")
                                .child(keycap("q", cx))
                                .child("quit"),
                        ),
                ),
        )
    }
}
