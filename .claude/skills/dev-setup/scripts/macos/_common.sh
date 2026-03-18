#!/usr/bin/env bash
set -euo pipefail

# dev-setup: macOS 공통 유틸리티

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

write_status() {
    local status="$1" message="$2"
    case "$status" in
        OK)      echo -e "${GREEN}[OK]${NC} $message" ;;
        INSTALL) echo -e "${CYAN}[INSTALL]${NC} $message" ;;
        SKIP)    echo -e "${YELLOW}[SKIP]${NC} $message" ;;
        FAIL)    echo -e "${RED}[FAIL]${NC} $message" ;;
        CHECK)   echo -e "${GRAY}[CHECK]${NC} $message" ;;
    esac
}

command_exists() {
    command -v "$1" &>/dev/null
}

check_min_version() {
    local cmd="$1" version_arg="${2:---version}" min_version="$3"
    if ! command_exists "$cmd"; then return 1; fi
    local current
    current=$("$cmd" $version_arg 2>&1 | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) || return 1
    printf '%s\n%s' "$min_version" "$current" | sort -V -C
}

brew_install() {
    local formula="$1" display_name="${2:-$1}"
    if ! command_exists brew; then
        write_status "FAIL" "Homebrew가 설치되어 있지 않습니다"
        write_status "CHECK" "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" 로 설치하세요"
        return 1
    fi
    write_status "INSTALL" "$display_name 설치 중 (brew)..."
    brew install "$formula"
    write_status "OK" "$display_name 설치 완료"
}

brew_cask_install() {
    local cask="$1" display_name="${2:-$1}"
    if ! command_exists brew; then
        write_status "FAIL" "Homebrew가 설치되어 있지 않습니다"
        return 1
    fi
    write_status "INSTALL" "$display_name 설치 중 (brew cask)..."
    brew install --cask "$cask"
    write_status "OK" "$display_name 설치 완료"
}

add_to_path() {
    local path="$1"
    if [[ ":$PATH:" != *":$path:"* ]]; then
        export PATH="$path:$PATH"
        local shell_rc="$HOME/.zshrc"
        [[ -f "$HOME/.bash_profile" ]] && shell_rc="$HOME/.bash_profile"
        echo "export PATH=\"$path:\$PATH\"" >> "$shell_rc"
        write_status "OK" "PATH에 추가: $path"
    fi
}

ensure_homebrew() {
    if ! command_exists brew; then
        write_status "INSTALL" "Homebrew 설치 중..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        write_status "OK" "Homebrew 설치 완료"
    else
        write_status "OK" "Homebrew 이미 설치됨"
    fi
}

ensure_xcode_clt() {
    if ! xcode-select -p &>/dev/null; then
        write_status "INSTALL" "Xcode Command Line Tools 설치 중..."
        xcode-select --install
        write_status "CHECK" "설치 팝업을 확인하세요. 완료 후 스크립트를 다시 실행하세요."
        exit 0
    else
        write_status "OK" "Xcode Command Line Tools 이미 설치됨"
    fi
}

# 전체 인수 저장
SCRIPT_ARGS=("$@")

get_project_root() {
    # --project-root 인수가 있으면 사용, 없으면 git root, 없으면 PWD
    local i
    for ((i=0; i<${#SCRIPT_ARGS[@]}; i++)); do
        if [[ "${SCRIPT_ARGS[$i]}" == "--project-root" ]] && [[ $((i+1)) -lt ${#SCRIPT_ARGS[@]} ]]; then
            echo "${SCRIPT_ARGS[$((i+1))]}"; return
        fi
    done
    git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"
}

get_thirdparty_dir() {
    local root
    root=$(get_project_root)
    local dir="$root/thirdparty"
    mkdir -p "$dir"
    echo "$dir"
}

CHECK_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--check-only" ]] && CHECK_ONLY=true
done
