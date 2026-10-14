# Heavy integration validation

Status: COMPLETE — 7 passed, 0 failed, 0 skipped; process exit 0.

Environment: isolated Docker container `vibe-palembang-heavy`, Ubuntu 24.04 Linux ARM64 (hosted CI uses Ubuntu 24.04 x64). Docker Desktop has 8 GB RAM; `CARGO_BUILD_JOBS=2` caps build parallelism without changing test logic.

Installed toolchain: Rust 1.98.1 with clippy/rustfmt/llvm-tools-preview, cargo-llvm-cov 0.9.1, Node 24.21.0, pnpm 12.6.0, gitleaks 8.30.1, GPUI development libraries, desktop-file-validate, Qt6 qmltestrunner and declared QML modules. Dependencies are isolated in the container; no host package upgrades or tracked-source changes.

Logs:
- `heavy-env/system-deps.log`
- `heavy-env/provision.log`
- `heavy-env/playwright.log`

All seven heavy tests completed successfully against the frozen candidate below. This Linux ARM64 run supplements, and does not replace, hosted Ubuntu x64 CI.

## Launch receipt

All seven heavy tests launched against the frozen combined source after root confirmed source freeze. They run in alphabetical order; Foldkit guard-failure coverage already passed.

- Root freeze ID: `147805b14f4b6b30e65255f935ad5e9300bcca44`
- Snapshot: `heavy-source/` (187 files), immutable source copied into `/opt/validation/source` in the container.
- Manifest: `heavy-source-manifest.json`, SHA256 `ed5ce5ca0a0d624d74fa58874f6ff5073c5595117ac16b8ba2e3c7963cdc23f9`.
- Command: `CI=true SELFTEST_RUST_TOOLCHAIN=1.98.1 SELFTEST_CARGO_TARGET_DIR=/opt/validation/target CARGO_BUILD_JOBS=2 TMPDIR=/opt/validation/tmp ./scripts/template-selftest.sh test_heavy_`
- Container runner PID/process group: `5659`; harness PID `5665`.
- Host persistent exec session: `7449` (its exit may be polled using `write_stdin`).
- Full output: `heavy-tests.log`.
- Exit code file: `heavy-tests.exit` (created only on completion or timeout).
- A detached watchdog terminates the runner process group after the remaining 44 minutes, bounding the run to the CI's approximately 45-minute budget. Timeout is exit 124, not a passing or skipped test.

Poll from workspace:

```sh
tail -35 .context/integration/heavy-tests.log
cat .context/integration/heavy-tests.exit 2>/dev/null || true
docker exec vibe-palembang-heavy ps -o pid,pgid,sid,args -p 5659,5665
```

Build progress while a test is active:

```sh
docker exec vibe-palembang-heavy sh -c 'find /opt/validation/tmp -maxdepth 4 -name "*.gate.out" -exec tail -6 {} \;'
```

Final result verified by parent from heavy-tests.log and heavy-tests.exit: `selftest: 7 passed, 0 failed, 0 skipped`, exit `0`. All Foldkit, GPUI app, Qt plugin and TUI heavy cases passed. No live Omarchy desktop session was tested.
