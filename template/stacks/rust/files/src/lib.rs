//! The command line's logic; `main.rs` only runs it.

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// Runs the command line with `args` (program name excluded) and returns what to
/// print on stdout.
///
/// # Errors
///
/// Returns the message to print on stderr when the arguments are invalid.
pub fn run(args: &[String]) -> Result<String, String> {
    if args.len() > 1 {
        return Err("error: expected at most one argument\n".to_owned());
    }
    match args.first().map(String::as_str) {
        Some("--version") => Ok(format!("{{PACKAGE_NAME}} {VERSION}\n")),
        Some("--help") | None => Ok("usage: {{PACKAGE_NAME}} [--help | --version]\n".to_owned()),
        Some(other) => Err(format!("error: unexpected argument '{other}'\n")),
    }
}
