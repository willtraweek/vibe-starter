//! Named invariant: the launcher entry runs the installed binary in a floating
//! Omarchy terminal (`TUI.float` is the class Omarchy's window rules float) and
//! shares its name with the binary and the icon.

#[test]
fn the_desktop_entry_launches_the_binary_in_a_floating_terminal() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/packaging/app.desktop.in");
    let entry = std::fs::read_to_string(path).expect("packaging/app.desktop.in exists");
    let id = ::{{PACKAGE_NAME}}::APP_ID;
    for line in [
        format!("Exec=xdg-terminal-exec --app-id=TUI.float -e \"@BINDIR@/{id}\""),
        format!("Icon={id}"),
        "Terminal=false".to_owned(),
    ] {
        assert!(entry.lines().any(|l| l == line), "missing line: {line}");
    }
}
