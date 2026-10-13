//! Named invariant: the desktop entry, the installed binary and icon, and the
//! window class Hyprland sees all use one name, `APP_ID`. If they drift, the
//! launcher loses the window and window rules stop matching.

fn entry() -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/packaging/app.desktop.in");
    std::fs::read_to_string(path).expect("packaging/app.desktop.in exists")
}

#[test]
fn the_desktop_entry_names_the_app_id_everywhere() {
    let entry = entry();
    let id = ::{{PACKAGE_NAME}}::APP_ID;
    for line in [
        format!("Exec=\"@BINDIR@/{id}\""),
        format!("Icon={id}"),
        format!("StartupWMClass={id}"),
    ] {
        assert!(entry.lines().any(|l| l == line), "missing line: {line}");
    }
}
