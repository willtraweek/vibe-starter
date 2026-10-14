//! Command-line entry point: the machine contract (DOCTRINE.md §3).

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match {{PACKAGE_NAME}}::run(&args) {
        Ok(out) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
