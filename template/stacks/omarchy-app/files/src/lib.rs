//! An Omarchy desktop app built with GPUI and gpui-omarchy.

pub mod app;
pub mod cli;
pub mod model;

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// The Wayland app id, which Hyprland reports as the window class: window rules
/// match it, and so do the desktop entry's `StartupWMClass`, the installed
/// binary and the icon (`packaging/app.desktop.in`, `scripts/install.sh`).
pub const APP_ID: &str = "{{PACKAGE_NAME}}";
