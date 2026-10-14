//! The main window through GPUI's test harness (TESTING.md tier 3): real
//! frames and real key presses, with no display or GPU.

use ::{{PACKAGE_NAME}}::app::{self, MainWindow};
use gpui_kit::{
    Entity, Focusable as _, KeyDownEvent, KeyUpEvent, Keystroke, Modifiers, TestAppContext,
    VisualTestContext,
};
use gpui_omarchy::Theme;

fn open(cx: &mut TestAppContext) -> (Entity<MainWindow>, &mut VisualTestContext) {
    cx.update(app::init);
    let (view, cx) = cx.add_window_view(|_, cx| MainWindow::new(cx));
    let focus = view.read_with(cx, gpui_kit::Focusable::focus_handle);
    cx.update(|window, cx| window.focus(&focus, cx));
    draw(cx);
    (view, cx)
}

fn draw(cx: &mut VisualTestContext) {
    cx.update(|window, cx| window.draw(cx).clear(cx));
}

fn count(view: &Entity<MainWindow>, cx: &mut VisualTestContext) -> u32 {
    view.read_with(cx, |view, _| view.counter().count())
}

/// Presses and releases `key` as the platform reports them: a focused button
/// clicks on the release, which `simulate_keystrokes` never sends.
fn press(cx: &mut VisualTestContext, key: &str) {
    let keystroke = Keystroke::parse(key).expect("a valid keystroke");
    cx.simulate_event(KeyDownEvent {
        keystroke: keystroke.clone(),
        is_held: false,
        prefer_character_input: false,
    });
    cx.simulate_event(KeyUpEvent { keystroke });
}

/// Whether the keyboard is still on the window's root, where `open` put it.
fn root_focused(view: &Entity<MainWindow>, cx: &mut VisualTestContext) -> bool {
    cx.update(|window, cx| view.read(cx).focus_handle(cx).is_focused(window))
}

#[gpui_kit::test]
fn space_counts_and_r_resets(cx: &mut TestAppContext) {
    let (view, cx) = open(cx);
    cx.simulate_keystrokes("space space");
    assert_eq!(count(&view, cx), 2);
    draw(cx);
    cx.simulate_keystrokes("r");
    assert_eq!(count(&view, cx), 0);
}

#[gpui_kit::test]
fn enter_runs_the_primary_action(cx: &mut TestAppContext) {
    // Regression test. Press is ButtonVariant::Primary, which DESIGN.md keeps for
    // what Enter does, yet Enter did nothing until Tab reached the button.
    let (view, cx) = open(cx);
    press(cx, "enter");
    assert_eq!(count(&view, cx), 1);
}

#[gpui_kit::test]
fn clicking_the_button_counts(cx: &mut TestAppContext) {
    let (view, cx) = open(cx);
    let bounds = cx.debug_bounds("press").expect("the press button is drawn");
    cx.simulate_click(bounds.center(), Modifiers::default());
    assert_eq!(count(&view, cx), 1);
}

#[gpui_kit::test]
fn tab_reaches_press_and_enter_presses_it_once(cx: &mut TestAppContext) {
    // Regression test. The focus scope sat inside the focused root, off the path
    // GPUI dispatches keys along, so Tab never left the root.
    let (view, cx) = open(cx);
    press(cx, "tab");
    assert!(!root_focused(&view, cx), "Tab moves the keyboard to Press");
    press(cx, "enter");
    assert_eq!(count(&view, cx), 1);
}

#[gpui_kit::test]
fn the_window_draws_in_dark_and_light_themes(cx: &mut TestAppContext) {
    let (_, cx) = open(cx);
    for theme in [Theme::tokyo_night(), Theme::flexoki_light()] {
        cx.update(|_, cx| theme.apply(cx));
        draw(cx);
        assert!(cx.debug_bounds("press").is_some());
    }
}

#[gpui_kit::test]
fn starting_opens_one_focused_window(cx: &mut TestAppContext) {
    cx.update(app::start);
    let windows = cx.windows();
    assert_eq!(windows.len(), 1);
    let window = windows[0]
        .downcast::<MainWindow>()
        .expect("the main window");
    let focused = window
        .update(cx, |view, window, cx| {
            view.focus_handle(cx).is_focused(window)
        })
        .expect("the window is open");
    assert!(focused);
}

#[test]
fn window_options_carry_the_app_id() {
    // Hyprland window rules and the desktop entry match this class. GPUI's test
    // window ignores the app id it is opened with, so this checks the options
    // `open_window` passes, not the window.
    assert_eq!(
        app::window_options().app_id.as_deref(),
        Some(::{{PACKAGE_NAME}}::APP_ID)
    );
}
