#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# Rust 개발 환경 설치 (rustup, clippy, rustfmt)

CARGO_ENV="$HOME/.cargo/env"

# --- rustup / rustc ---
write_status "CHECK" "Rust(rustup) 설치 여부 확인 중..."
RUST_NEEDS_INSTALL=true

# cargo env 소싱 (이미 설치된 경우 PATH에 없을 수 있음)
if [[ -f "$CARGO_ENV" ]]; then
    # shellcheck source=/dev/null
    source "$CARGO_ENV"
fi

if command_exists rustc && command_exists cargo; then
    write_status "SKIP" "rustc $(rustc --version) — 이미 설치됨"
    RUST_NEEDS_INSTALL=false
fi

if $RUST_NEEDS_INSTALL; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "rustup 설치 필요"
    else
        write_status "INSTALL" "rustup 설치 스크립트 실행 중..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        # shellcheck source=/dev/null
        source "$CARGO_ENV"
        write_status "OK" "rustup 설치 완료"
    fi
fi

# cargo env 재소싱 (방금 설치한 경우)
if [[ -f "$CARGO_ENV" ]]; then
    # shellcheck source=/dev/null
    source "$CARGO_ENV"
fi

# PATH에 cargo bin 추가 (.bashrc)
if ! grep -q '\.cargo/env' "$HOME/.bashrc" 2>/dev/null; then
    echo '. "$HOME/.cargo/env"' >> "$HOME/.bashrc"
    write_status "OK" ".bashrc에 cargo env 추가"
fi

# --- clippy ---
write_status "CHECK" "clippy 확인 중..."
if command_exists cargo && cargo clippy --version &>/dev/null 2>&1; then
    write_status "SKIP" "clippy — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "clippy 설치 필요"
    elif command_exists rustup; then
        write_status "INSTALL" "clippy 컴포넌트 추가 중..."
        rustup component add clippy
        write_status "OK" "clippy 설치 완료"
    fi
fi

# --- rustfmt ---
write_status "CHECK" "rustfmt 확인 중..."
if command_exists rustfmt; then
    write_status "SKIP" "rustfmt $(rustfmt --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "rustfmt 설치 필요"
    elif command_exists rustup; then
        write_status "INSTALL" "rustfmt 컴포넌트 추가 중..."
        rustup component add rustfmt
        write_status "OK" "rustfmt 설치 완료"
    fi
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
if command_exists rustc; then
    write_status "OK" "rustc       $(rustc --version)"
else
    write_status "FAIL" "rustc 없음"
fi
if command_exists cargo; then
    write_status "OK" "cargo       $(cargo --version)"
else
    write_status "FAIL" "cargo 없음"
fi
if command_exists rustfmt; then
    write_status "OK" "rustfmt     $(rustfmt --version 2>&1 | head -1)"
else
    write_status "FAIL" "rustfmt 없음"
fi
if cargo clippy --version &>/dev/null 2>&1; then
    write_status "OK" "clippy      $(cargo clippy --version 2>&1 | head -1)"
else
    write_status "FAIL" "clippy 없음"
fi
