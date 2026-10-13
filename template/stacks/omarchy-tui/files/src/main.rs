//! Command-line entry point: prints what `cli::parse` returns, or runs the app
//! in this terminal. Everything testable lives in the library.

use std::process::ExitCode;

use ::{{PACKAGE_NAME}}::cli::{self, Command};
use ratatui::crossterm::event;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match cli::parse(&args) {
        Ok(Command::Print(out)) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Ok(Command::Open) => {
            // The one path no test runs: the real terminal and its real keys.
            let events = std::iter::repeat_with(event::read);
            match ratatui::run(|terminal| ::{{PACKAGE_NAME}}::app::run(terminal, events)) {
                Ok(_) => ExitCode::SUCCESS,
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::FAILURE
                }
            }
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
