//! The command line: the machine contract (DOCTRINE.md §3). Parsing is pure,
//! and `tests/cli.rs` checks every answer through the real binary. With no
//! arguments the binary opens the window instead.

/// What the command line asked for.
#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    /// Open the main window.
    Open,
    /// Print this on stdout and exit 0.
    Print(String),
}

/// The `--help` text.
pub const USAGE: &str = "usage: {{PACKAGE_NAME}} [--help | --version]\n\
    With no arguments, opens the {{PROJECT_NAME}} window.\n";

/// Parses `args` (program name excluded).
///
/// # Errors
///
/// Returns the message to print on stderr when the arguments are invalid.
pub fn parse(args: &[String]) -> Result<Command, String> {
    if args.len() > 1 {
        return Err("error: expected at most one argument\n".to_owned());
    }
    match args.first().map(String::as_str) {
        None => Ok(Command::Open),
        // scripts/install.sh refuses a binary whose answer here isn't `APP_ID VERSION`.
        Some("--version") => Ok(Command::Print(format!(
            "{} {}\n",
            crate::APP_ID,
            crate::VERSION
        ))),
        Some("--help") => Ok(Command::Print(USAGE.to_owned())),
        Some(other) => Err(format!("error: unexpected argument '{other}'\n")),
    }
}
