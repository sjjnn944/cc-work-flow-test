#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# NestJS 개발 환경 설치 (Node.js 18+, pnpm, @nestjs/cli, TypeScript)

NODE_MIN="18"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# nvm 소싱 (이미 설치된 경우)
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
fi

check_sudo

# --- Node.js ---
write_status "CHECK" "Node.js 버전 확인 중..."
NODE_NEEDS_INSTALL=true
if command_exists node; then
    NODE_VER=$(node --version 2>&1 | grep -oP '\d+' | head -1)
    if [[ "$NODE_VER" -ge "$NODE_MIN" ]]; then
        write_status "SKIP" "node v$NODE_VER — 이미 설치됨 (>= $NODE_MIN)"
        NODE_NEEDS_INSTALL=false
    else
        write_status "CHECK" "node v$NODE_VER — $NODE_MIN 이상 필요"
    fi
fi

if $NODE_NEEDS_INSTALL; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "Node.js >= $NODE_MIN 설치 필요"
    else
        PKG_MGR=$(detect_pkg_manager)
        if [[ "$PKG_MGR" == "apt" ]]; then
            write_status "INSTALL" "NodeSource 저장소 등록 후 Node.js 설치 중..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y -qq nodejs
        elif [[ "$PKG_MGR" == "dnf" ]]; then
            write_status "INSTALL" "NodeSource 저장소 등록 후 Node.js 설치 중..."
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            sudo dnf install -y nodejs
        elif [[ "$PKG_MGR" == "pacman" ]]; then
            pkg_install "Node.js" nodejs npm
        else
            # nvm 폴백
            write_status "INSTALL" "nvm을 통해 Node.js 설치 중..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            # shellcheck source=/dev/null
            source "$NVM_DIR/nvm.sh"
            nvm install 20
            nvm use 20
            nvm alias default 20
        fi
        write_status "OK" "Node.js 설치 완료"
    fi
fi

# --- pnpm ---
write_status "CHECK" "pnpm 확인 중..."
if command_exists pnpm; then
    write_status "SKIP" "pnpm $(pnpm --version 2>&1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "pnpm 설치 필요"
    elif command_exists npm; then
        write_status "INSTALL" "pnpm 설치 중..."
        npm install -g pnpm
        write_status "OK" "pnpm 설치 완료"
    else
        write_status "FAIL" "npm 없음 — pnpm 설치 불가"
    fi
fi

# --- @nestjs/cli ---
write_status "CHECK" "@nestjs/cli 확인 중..."
if command_exists nest; then
    write_status "SKIP" "nest $(nest --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "@nestjs/cli 설치 필요"
    elif command_exists pnpm; then
        write_status "INSTALL" "@nestjs/cli 설치 중..."
        pnpm add -g @nestjs/cli
        write_status "OK" "@nestjs/cli 설치 완료"
    elif command_exists npm; then
        write_status "INSTALL" "@nestjs/cli 설치 중 (npm)..."
        npm install -g @nestjs/cli
        write_status "OK" "@nestjs/cli 설치 완료"
    fi
fi

# --- TypeScript ---
write_status "CHECK" "TypeScript 확인 중..."
if command_exists tsc; then
    write_status "SKIP" "tsc $(tsc --version 2>&1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "TypeScript 설치 필요"
    elif command_exists pnpm; then
        write_status "INSTALL" "TypeScript 설치 중..."
        pnpm add -g typescript ts-node
        write_status "OK" "TypeScript 설치 완료"
    elif command_exists npm; then
        npm install -g typescript ts-node
        write_status "OK" "TypeScript 설치 완료"
    fi
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
command_exists node  && write_status "OK" "node        $(node --version)" || write_status "FAIL" "node 없음"
command_exists npm   && write_status "OK" "npm         $(npm --version)" || write_status "FAIL" "npm 없음"
command_exists pnpm  && write_status "OK" "pnpm        $(pnpm --version)" || write_status "FAIL" "pnpm 없음"
command_exists nest  && write_status "OK" "nest        $(nest --version 2>&1 | head -1)" || write_status "FAIL" "nest 없음"
command_exists tsc   && write_status "OK" "tsc         $(tsc --version)" || write_status "FAIL" "tsc 없음"
