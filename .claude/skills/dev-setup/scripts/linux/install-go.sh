#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# Go 개발 환경 설치 (Go 1.21+, golangci-lint)

GO_MIN="1.21"
GO_INSTALL_DIR="/usr/local/go"
GO_TARBALL_BASE="https://go.dev/dl"

check_sudo

# --- Go ---
write_status "CHECK" "Go 버전 확인 중..."
GO_NEEDS_INSTALL=true
if command_exists go; then
    if check_min_version "go" "version" "$GO_MIN"; then
        write_status "SKIP" "go $(go version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨 (>= $GO_MIN)"
        GO_NEEDS_INSTALL=false
    else
        write_status "CHECK" "go 버전 미달 — $GO_MIN 이상 설치 필요"
    fi
fi

if $GO_NEEDS_INSTALL; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "Go >= $GO_MIN 설치 필요"
    else
        # 최신 안정 버전 조회
        write_status "INSTALL" "Go 최신 버전 조회 중..."
        LATEST=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  GOARCH="amd64" ;;
            aarch64) GOARCH="arm64" ;;
            *)       GOARCH="$ARCH" ;;
        esac
        TARBALL="${LATEST}.linux-${GOARCH}.tar.gz"
        URL="${GO_TARBALL_BASE}/${TARBALL}"

        write_status "INSTALL" "$TARBALL 다운로드 중..."
        curl -fsSL "$URL" -o "/tmp/$TARBALL"
        sudo rm -rf "$GO_INSTALL_DIR"
        sudo tar -C /usr/local -xzf "/tmp/$TARBALL"
        rm -f "/tmp/$TARBALL"

        if ! grep -q "/usr/local/go/bin" "$HOME/.bashrc" 2>/dev/null; then
            echo 'export PATH="/usr/local/go/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        export PATH="/usr/local/go/bin:$PATH"
        write_status "OK" "Go ${LATEST} 설치 완료"
    fi
fi

# --- GOPATH 설정 ---
write_status "CHECK" "GOPATH 확인 중..."
GOPATH_DIR="${GOPATH:-$HOME/go}"
if [[ -n "${GOPATH:-}" ]]; then
    write_status "SKIP" "GOPATH=$GOPATH — 이미 설정됨"
else
    if ! $CHECK_ONLY; then
        export GOPATH="$GOPATH_DIR"
        if ! grep -q "GOPATH" "$HOME/.bashrc" 2>/dev/null; then
            echo "export GOPATH=\"$GOPATH_DIR\"" >> "$HOME/.bashrc"
            echo 'export PATH="$GOPATH/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        export PATH="$GOPATH_DIR/bin:$PATH"
        write_status "OK" "GOPATH=$GOPATH_DIR"
    fi
fi

# --- golangci-lint ---
write_status "CHECK" "golangci-lint 확인 중..."
if command_exists golangci-lint; then
    write_status "SKIP" "golangci-lint $(golangci-lint --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "golangci-lint 설치 필요"
    else
        write_status "INSTALL" "golangci-lint curl 설치 스크립트 실행 중..."
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
            | sh -s -- -b "$(go env GOPATH)/bin"
        write_status "OK" "golangci-lint 설치 완료"
    fi
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
if command_exists go; then
    write_status "OK" "go              $(go version)"
else
    write_status "FAIL" "go 없음"
fi
if command_exists golangci-lint; then
    write_status "OK" "golangci-lint   $(golangci-lint --version 2>&1 | head -1)"
else
    write_status "FAIL" "golangci-lint 없음"
fi
write_status "OK" "GOPATH          ${GOPATH:-$HOME/go}"
