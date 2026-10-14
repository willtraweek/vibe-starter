//! A keyboard-driven terminal app for Omarchy, built with ratatui.

pub mod app;
pub mod cli;
pub mod model;
pub mod view;

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// The installed binary's name, which the desktop entry and the icon share
/// (`packaging/app.desktop.in`, `scripts/install.sh`).
pub const APP_ID: &str = "{{PACKAGE_NAME}}";
