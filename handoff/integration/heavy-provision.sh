#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
mkdir -p /opt/validation/bin /opt/validation/downloads
cd /opt/validation/downloads
curl -fsSLO https://static.rust-lang.org/rustup/archive/1.29.1/aarch64-unknown-linux-gnu/rustup-init
curl -fsSLO https://static.rust-lang.org/rustup/archive/1.29.1/aarch64-unknown-linux-gnu/rustup-init.sha256
sha256sum -c rustup-init.sha256
chmod +x rustup-init
./rustup-init -y --no-modify-path --profile minimal --default-toolchain none
export PATH="/opt/validation/bin:/root/.cargo/bin:$PATH"
rustup toolchain install 1.98.1 --profile minimal --component clippy,rustfmt,llvm-tools-preview
curl -fsSLO https://github.com/taiki-e/cargo-llvm-cov/releases/download/v0.9.1/cargo-llvm-cov-aarch64-unknown-linux-gnu.tar.gz
tar -xzf cargo-llvm-cov-aarch64-unknown-linux-gnu.tar.gz -C /opt/validation/bin cargo-llvm-cov
curl -fsSLO https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_arm64.tar.gz
curl -fsSLO https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt
grep 'gitleaks_8.30.1_linux_arm64.tar.gz$' gitleaks_8.30.1_checksums.txt | sha256sum -c -
tar -xzf gitleaks_8.30.1_linux_arm64.tar.gz -C /opt/validation/bin gitleaks
curl -fsSLO https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-arm64.tar.xz
curl -fsSLO https://nodejs.org/dist/v24.21.0/SHASUMS256.txt
grep 'node-v24.21.0-linux-arm64.tar.xz$' SHASUMS256.txt | sha256sum -c -
tar -xJf node-v24.21.0-linux-arm64.tar.xz -C /opt/validation --strip-components=1
npm install --prefix /opt/validation --global pnpm@12.6.0
node --version
pnpm --version
rustup run 1.98.1 rustc --version
rustup run 1.98.1 cargo llvm-cov --version
gitleaks version
ls -l /usr/lib/qt6/bin/qmltestrunner
pkg-config --modversion fontconfig xkbcommon-x11
