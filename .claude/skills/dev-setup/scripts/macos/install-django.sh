#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: Django 개발 환경 설치 (macOS)

echo ""
echo "=== Django 개발 환경 설치 ==="
echo ""

ensure_homebrew

# --- Python 3.11+ ---
write_status "CHECK" "Python 3.11+ 확인 중..."
if command_exists python3 && check_min_version python3 "--version" "3.11"; then
    write_status "SKIP" "Python $(python3 --version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨 (>= 3.11)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install python@3.11 "Python 3.11"

        BREW_PYTHON="$(brew --prefix python@3.11)/bin"
        add_to_path "$BREW_PYTHON"
        export PATH="$BREW_PYTHON:$PATH"
    else
        write_status "INSTALL" "Python 3.11+ 설치 필요"
    fi
fi

# pip3 최신화
write_status "CHECK" "pip3 확인 중..."
if command_exists pip3; then
    write_status "SKIP" "pip3 $(pip3 --version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
    if [[ "$CHECK_ONLY" == "false" ]]; then
        python3 -m pip install --upgrade pip --quiet
        write_status "OK" "pip3 최신화 완료"
    fi
else
    write_status "FAIL" "pip3 찾을 수 없음"
fi

# --- poetry ---
write_status "CHECK" "poetry 확인 중..."
if command_exists poetry; then
    write_status "SKIP" "poetry $(poetry --version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "poetry 설치 중 (pip3)..."
        pip3 install --user poetry
        add_to_path "$HOME/.local/bin"
        export PATH="$HOME/.local/bin:$PATH"
        write_status "OK" "poetry 설치 완료"
    else
        write_status "INSTALL" "poetry 설치 필요"
    fi
fi

# --- virtualenv (선택) ---
write_status "CHECK" "virtualenv 확인 중..."
if command_exists virtualenv; then
    write_status "SKIP" "virtualenv 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "virtualenv 설치 중 (pip3)..."
        pip3 install --user virtualenv
        write_status "OK" "virtualenv 설치 완료"
    else
        write_status "INSTALL" "virtualenv 설치 필요 (optional)"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
if command_exists python3; then
    write_status "OK" "python3:    $(python3 --version)"
else
    write_status "FAIL" "python3: 찾을 수 없음"
fi

if command_exists pip3; then
    write_status "OK" "pip3:       $(pip3 --version | head -1)"
else
    write_status "FAIL" "pip3: 찾을 수 없음"
fi

if command_exists poetry; then
    write_status "OK" "poetry:     $(poetry --version)"
else
    write_status "FAIL" "poetry: 찾을 수 없음"
fi

command_exists virtualenv && write_status "OK" "virtualenv: $(virtualenv --version)"
echo ""
