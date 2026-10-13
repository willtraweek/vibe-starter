//! Command-line entry point: prints what `cli::parse` returns, or opens the
//! window. Everything testable lives in the library; this only wires it up.

use std::process::ExitCode;

use ::{{PACKAGE_NAME}}::cli::{self, Command};
use gpui_kit::assets::Assets;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match cli::parse(&args) {
        Ok(Command::Print(out)) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Ok(Command::Open) => {
            // The one line no test can run: it hands the process to the
            // platform's event loop until the window closes.
            gpui_kit::application()
                .with_assets(Assets)
                .run(::{{PACKAGE_NAME}}::app::start);
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
