//! CLI contract tests (TESTING.md tier 2: exit code and output of every
//! command), through the real binary. No arguments takes over the terminal, which
//! `tests/app.rs` covers instead.

use std::process::{Command, Output};

fn cli(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_{{PACKAGE_NAME}}"))
        .args(args)
        .output()
        .expect("the binary runs")
}

#[test]
fn version_flag_prints_the_version_file_and_exits_zero() {
    let version_file = concat!(env!("CARGO_MANIFEST_DIR"), "/VERSION");
    let version = std::fs::read_to_string(version_file).expect("VERSION exists");
    let out = cli(&["--version"]);
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("{{PACKAGE_NAME}} {}\n", version.trim_end())
    );
    assert!(out.stderr.is_empty());
}

#[test]
fn help_flag_prints_usage_and_exits_zero() {
    let out = cli(&["--help"]);
    assert!(out.status.success());
    assert_eq!(out.stdout, ::{{PACKAGE_NAME}}::cli::USAGE.as_bytes());
    assert!(out.stderr.is_empty());
}

#[test]
fn unknown_argument_exits_two_on_stderr() {
    let out = cli(&["--nope"]);
    assert_eq!(out.status.code(), Some(2));
    assert!(out.stdout.is_empty());
    assert_eq!(out.stderr, b"error: unexpected argument '--nope'\n");
}

#[test]
fn surplus_arguments_exit_two_on_stderr() {
    for args in [["--version", "x"], ["--help", "x"], ["--nope", "y"]] {
        let out = cli(&args);
        assert_eq!(out.status.code(), Some(2));
        assert!(out.stdout.is_empty());
        assert_eq!(out.stderr, b"error: expected at most one argument\n");
    }
}

#[test]
fn no_arguments_means_run_the_app() {
    // Asserted on the parser: the binary would take over this terminal.
    assert_eq!(::{{PACKAGE_NAME}}::cli::parse(&[]), Ok(::{{PACKAGE_NAME}}::cli::Command::Open));
}
