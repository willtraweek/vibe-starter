//! The main window through GPUI's test harness (TESTING.md tier 3): real
//! frames and real key presses, with no display or GPU.

use ::{{PACKAGE_NAME}}::app::{self, MainWindow};
use gpui_kit::{Entity, Modifiers, TestAppContext, VisualTestContext};
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
fn clicking_the_button_counts(cx: &mut TestAppContext) {
    let (view, cx) = open(cx);
    let bounds = cx.debug_bounds("press").expect("the press button is drawn");
    cx.simulate_click(bounds.center(), Modifiers::default());
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
fn starting_opens_one_focused_window_under_the_app_id(cx: &mut TestAppContext) {
    cx.update(app::start);
    let windows = cx.windows();
    assert_eq!(windows.len(), 1);
    let window = windows[0]
        .downcast::<MainWindow>()
        .expect("the main window");
    let focused = window
        .update(cx, |view, window, cx| {
            gpui_kit::Focusable::focus_handle(view, cx).is_focused(window)
        })
        .expect("the window is open");
    assert!(focused);
    // Hyprland window rules and the desktop entry match this class.
    assert_eq!(
        app::window_options().app_id.as_deref(),
        Some(::{{PACKAGE_NAME}}::APP_ID)
    );
}
