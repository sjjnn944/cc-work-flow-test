#!/usr/bin/env bash
set -euo pipefail

# dev-setup: Linux 공통 유틸리티

# 색상 코드
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
    current=$("$cmd" $version_arg 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) || return 1
    printf '%s\n%s' "$min_version" "$current" | sort -V -C
}

# 패키지 매니저 감지
detect_pkg_manager() {
    if command_exists apt-get; then echo "apt"
    elif command_exists dnf; then echo "dnf"
    elif command_exists pacman; then echo "pacman"
    else echo "unknown"; fi
}

pkg_install() {
    local pkg_manager display_name="$1"; shift
    pkg_manager=$(detect_pkg_manager)
    write_status "INSTALL" "$display_name 설치 중 ($pkg_manager)..."
    case "$pkg_manager" in
        apt)    sudo apt-get update -qq && sudo apt-get install -y -qq "$@" ;;
        dnf)    sudo dnf install -y -q "$@" ;;
        pacman) sudo pacman -S --noconfirm --needed "$@" ;;
        *)      write_status "FAIL" "지원되지 않는 패키지 매니저"; return 1 ;;
    esac
}

add_to_path() {
    local path="$1"
    if [[ ":$PATH:" != *":$path:"* ]]; then
        export PATH="$path:$PATH"
        echo "export PATH=\"$path:\$PATH\"" >> "$HOME/.bashrc"
        write_status "OK" "PATH에 추가: $path"
    fi
}

check_sudo() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        write_status "CHECK" "sudo 권한이 필요합니다"
        sudo -v
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

# --check-only 인수 처리
CHECK_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--check-only" ]] && CHECK_ONLY=true
done
