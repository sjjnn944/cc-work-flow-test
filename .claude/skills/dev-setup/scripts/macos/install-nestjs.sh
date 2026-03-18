#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: NestJS 개발 환경 설치 (macOS)

echo ""
echo "=== NestJS 개발 환경 설치 ==="
echo ""

ensure_homebrew

# --- Node.js 18+ ---
write_status "CHECK" "Node.js 확인 중..."
if command_exists node && check_min_version node "--version" "18.0"; then
    write_status "SKIP" "Node.js $(node --version) 이미 설치됨 (>= 18)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        # node@18이 존재하면 설치, 아니면 최신 node 설치
        if brew info node@18 &>/dev/null; then
            brew_install node@18 "Node.js 18"
            add_to_path "$(brew --prefix node@18)/bin"
            export PATH="$(brew --prefix node@18)/bin:$PATH"
        else
            brew_install node "Node.js"
        fi
    else
        write_status "INSTALL" "Node.js 18+ 설치 필요"
    fi
fi

# --- pnpm ---
write_status "CHECK" "pnpm 확인 중..."
if command_exists pnpm; then
    write_status "SKIP" "pnpm $(pnpm --version) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "pnpm 설치 중 (npm)..."
        npm install -g pnpm
        write_status "OK" "pnpm 설치 완료"
    else
        write_status "INSTALL" "pnpm 설치 필요"
    fi
fi

# --- @nestjs/cli ---
write_status "CHECK" "@nestjs/cli 확인 중..."
if command_exists nest; then
    write_status "SKIP" "@nestjs/cli $(nest --version 2>&1 | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "@nestjs/cli 설치 중 (npm)..."
        npm install -g @nestjs/cli
        write_status "OK" "@nestjs/cli 설치 완료"
    else
        write_status "INSTALL" "@nestjs/cli 설치 필요"
    fi
fi

# --- TypeScript ---
write_status "CHECK" "TypeScript 확인 중..."
if command_exists tsc; then
    write_status "SKIP" "TypeScript $(tsc --version) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "TypeScript 설치 중 (npm)..."
        npm install -g typescript
        write_status "OK" "TypeScript 설치 완료"
    else
        write_status "INSTALL" "TypeScript 설치 필요"
    fi
fi

# --- ts-node ---
write_status "CHECK" "ts-node 확인 중..."
if command_exists ts-node; then
    write_status "SKIP" "ts-node $(ts-node --version) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "ts-node 설치 중 (npm)..."
        npm install -g ts-node
        write_status "OK" "ts-node 설치 완료"
    else
        write_status "INSTALL" "ts-node 설치 필요"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
command_exists node  && write_status "OK" "node:    $(node --version)"
command_exists npm   && write_status "OK" "npm:     $(npm --version)"
command_exists pnpm  && write_status "OK" "pnpm:    $(pnpm --version)"
command_exists nest  && write_status "OK" "nest:    $(nest --version 2>&1 | head -1)"
command_exists tsc   && write_status "OK" "tsc:     $(tsc --version)"
command_exists ts-node && write_status "OK" "ts-node: $(ts-node --version)"
echo ""
