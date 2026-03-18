#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: Rust 개발 환경 설치 (macOS)

echo ""
echo "=== Rust 개발 환경 설치 ==="
echo ""

ensure_homebrew

# cargo env 소싱 (rustup 설치 후를 위해)
CARGO_ENV="$HOME/.cargo/env"

# --- rustup / Rust toolchain ---
write_status "CHECK" "rustup 확인 중..."
if command_exists rustup; then
    write_status "SKIP" "rustup 이미 설치됨"
    # cargo env 소싱
    [[ -f "$CARGO_ENV" ]] && source "$CARGO_ENV"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "rustup 설치 중 (curl installer)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        write_status "OK" "rustup 설치 완료"

        # cargo env 소싱
        if [[ -f "$CARGO_ENV" ]]; then
            source "$CARGO_ENV"
            write_status "OK" "cargo 환경 로드: $CARGO_ENV"
        fi
    else
        write_status "INSTALL" "rustup 설치 필요"
    fi
fi

# PATH에 cargo/bin 추가
add_to_path "$HOME/.cargo/bin"
export PATH="$HOME/.cargo/bin:$PATH"

# --- rustc 확인 ---
write_status "CHECK" "rustc 확인 중..."
if command_exists rustc; then
    write_status "SKIP" "rustc $(rustc --version) 이미 설치됨"
else
    write_status "FAIL" "rustc 찾을 수 없음 — rustup 설치를 확인하세요"
fi

# --- clippy ---
write_status "CHECK" "clippy 확인 중..."
if rustup component list --installed 2>/dev/null | grep -q "clippy"; then
    write_status "SKIP" "clippy 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "clippy 컴포넌트 추가 중..."
        rustup component add clippy
        write_status "OK" "clippy 설치 완료"
    else
        write_status "INSTALL" "clippy 설치 필요"
    fi
fi

# --- rustfmt ---
write_status "CHECK" "rustfmt 확인 중..."
if rustup component list --installed 2>/dev/null | grep -q "rustfmt"; then
    write_status "SKIP" "rustfmt 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "rustfmt 컴포넌트 추가 중..."
        rustup component add rustfmt
        write_status "OK" "rustfmt 설치 완료"
    else
        write_status "INSTALL" "rustfmt 설치 필요"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
if command_exists rustc; then
    write_status "OK" "rustc:   $(rustc --version)"
else
    write_status "FAIL" "rustc: 찾을 수 없음"
fi

if command_exists cargo; then
    write_status "OK" "cargo:   $(cargo --version)"
else
    write_status "FAIL" "cargo: 찾을 수 없음"
fi

if command_exists rustup; then
    write_status "OK" "rustup:  $(rustup --version 2>&1 | head -1)"
fi

command_exists cargo && cargo clippy --version &>/dev/null && \
    write_status "OK" "clippy:  설치됨"
command_exists rustfmt && \
    write_status "OK" "rustfmt: $(rustfmt --version)"
echo ""
