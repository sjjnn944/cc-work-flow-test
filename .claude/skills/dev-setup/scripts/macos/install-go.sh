#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: Go 개발 환경 설치 (macOS)

echo ""
echo "=== Go 개발 환경 설치 ==="
echo ""

ensure_homebrew

# --- Go ---
write_status "CHECK" "Go 확인 중..."
if command_exists go && check_min_version go "version" "1.21"; then
    write_status "SKIP" "Go $(go version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨 (>= 1.21)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install go Go
    else
        write_status "INSTALL" "Go 설치 필요 (>= 1.21)"
    fi
fi

# --- GOPATH 설정 ---
write_status "CHECK" "GOPATH 확인 중..."
DEFAULT_GOPATH="$HOME/go"
if [[ -n "${GOPATH:-}" ]]; then
    write_status "SKIP" "GOPATH 이미 설정됨: $GOPATH"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        export GOPATH="$DEFAULT_GOPATH"
        mkdir -p "$GOPATH/bin" "$GOPATH/src" "$GOPATH/pkg"

        local shell_rc="$HOME/.zshrc"
        [[ -f "$HOME/.bash_profile" ]] && shell_rc="$HOME/.bash_profile"

        if ! grep -q "GOPATH" "$shell_rc" 2>/dev/null; then
            echo "export GOPATH=\"$DEFAULT_GOPATH\"" >> "$shell_rc"
            echo "export PATH=\"\$GOPATH/bin:\$PATH\"" >> "$shell_rc"
            write_status "OK" "GOPATH 설정: $DEFAULT_GOPATH"
        fi

        add_to_path "$GOPATH/bin"
    else
        write_status "INSTALL" "GOPATH 설정 필요 ($DEFAULT_GOPATH)"
    fi
fi

# PATH에 GOPATH/bin 추가
export PATH="${GOPATH:-$DEFAULT_GOPATH}/bin:$PATH"

# --- golangci-lint ---
write_status "CHECK" "golangci-lint 확인 중..."
if command_exists golangci-lint; then
    write_status "SKIP" "golangci-lint $(golangci-lint --version 2>&1 | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install golangci-lint golangci-lint
    else
        write_status "INSTALL" "golangci-lint 설치 필요"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
if command_exists go; then
    write_status "OK" "go:            $(go version)"
else
    write_status "FAIL" "go: 찾을 수 없음"
fi

if command_exists golangci-lint; then
    write_status "OK" "golangci-lint: $(golangci-lint --version 2>&1 | head -1)"
else
    write_status "FAIL" "golangci-lint: 찾을 수 없음"
fi

write_status "OK" "GOPATH:        ${GOPATH:-$DEFAULT_GOPATH}"
echo ""
