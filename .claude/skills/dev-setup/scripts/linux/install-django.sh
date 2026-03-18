#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# Django 개발 환경 설치 (Python 3.11+, pip, venv, poetry)

PYTHON_MIN="3.11"

check_sudo

# --- Python 3.11+ ---
write_status "CHECK" "Python 버전 확인 중..."
PYTHON_CMD=""
PYTHON_NEEDS_INSTALL=true

for cmd in python3.12 python3.11 python3; do
    if command_exists "$cmd"; then
        PY_VER=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)
        if printf '%s\n%s' "$PYTHON_MIN" "$PY_VER" | sort -V -C; then
            write_status "SKIP" "$cmd $PY_VER — 이미 설치됨 (>= $PYTHON_MIN)"
            PYTHON_CMD="$cmd"
            PYTHON_NEEDS_INSTALL=false
            break
        fi
    fi
done

if $PYTHON_NEEDS_INSTALL; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "Python >= $PYTHON_MIN 설치 필요"
    else
        PKG_MGR=$(detect_pkg_manager)
        case "$PKG_MGR" in
            apt)
                # deadsnakes PPA 사용 (Ubuntu)
                if command_exists add-apt-repository 2>/dev/null; then
                    sudo add-apt-repository -y ppa:deadsnakes/ppa
                    sudo apt-get update -qq
                fi
                pkg_install "Python 3.11" python3.11 python3.11-pip python3.11-venv python3-pip python3-venv
                PYTHON_CMD="python3.11"
                ;;
            dnf)    pkg_install "Python 3.11" python3.11 python3-pip; PYTHON_CMD="python3.11" ;;
            pacman) pkg_install "Python 3" python python-pip; PYTHON_CMD="python3" ;;
            *)      write_status "FAIL" "지원되지 않는 패키지 매니저"; exit 1 ;;
        esac
        write_status "OK" "Python 설치 완료"
    fi
fi

# pip 확인
write_status "CHECK" "pip 확인 중..."
if [[ -n "$PYTHON_CMD" ]] && "$PYTHON_CMD" -m pip --version &>/dev/null; then
    write_status "SKIP" "pip $("$PYTHON_CMD" -m pip --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨"
elif ! $CHECK_ONLY && [[ -n "$PYTHON_CMD" ]]; then
    PKG_MGR=$(detect_pkg_manager)
    case "$PKG_MGR" in
        apt)    pkg_install "pip" python3-pip ;;
        dnf)    pkg_install "pip" python3-pip ;;
        pacman) pkg_install "pip" python-pip ;;
    esac
fi

# python3-venv 확인
write_status "CHECK" "venv 모듈 확인 중..."
if [[ -n "$PYTHON_CMD" ]] && "$PYTHON_CMD" -m venv --help &>/dev/null 2>&1; then
    write_status "SKIP" "venv — 이미 사용 가능"
elif ! $CHECK_ONLY; then
    PKG_MGR=$(detect_pkg_manager)
    [[ "$PKG_MGR" == "apt" ]] && pkg_install "python3-venv" python3-venv
    write_status "OK" "venv 설치 완료"
fi

# --- poetry ---
write_status "CHECK" "poetry 확인 중..."
if command_exists poetry; then
    write_status "SKIP" "poetry $(poetry --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "poetry 설치 필요"
    elif [[ -n "$PYTHON_CMD" ]]; then
        write_status "INSTALL" "poetry 설치 중 (공식 설치 스크립트)..."
        curl -sSL https://install.python-poetry.org | "$PYTHON_CMD" -
        POETRY_BIN="$HOME/.local/bin"
        if [[ ":$PATH:" != *":$POETRY_BIN:"* ]]; then
            export PATH="$POETRY_BIN:$PATH"
            if ! grep -q 'poetry' "$HOME/.bashrc" 2>/dev/null; then
                echo "export PATH=\"$POETRY_BIN:\$PATH\"" >> "$HOME/.bashrc"
            fi
        fi
        write_status "OK" "poetry 설치 완료"
    fi
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
if [[ -n "$PYTHON_CMD" ]] && command_exists "$PYTHON_CMD"; then
    write_status "OK" "python3     $("$PYTHON_CMD" --version)"
else
    write_status "FAIL" "python3 없음"
fi
if [[ -n "$PYTHON_CMD" ]] && "$PYTHON_CMD" -m pip --version &>/dev/null 2>&1; then
    write_status "OK" "pip         $("$PYTHON_CMD" -m pip --version 2>&1)"
else
    write_status "FAIL" "pip 없음"
fi
command_exists poetry && write_status "OK" "poetry      $(poetry --version 2>&1)" || write_status "FAIL" "poetry 없음"
