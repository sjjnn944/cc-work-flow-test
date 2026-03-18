#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: .NET 개발 환경 설치 (macOS)

echo ""
echo "=== .NET 개발 환경 설치 ==="
echo ""

ensure_homebrew

# --- .NET SDK 8.0 ---
write_status "CHECK" ".NET SDK 확인 중..."
if command_exists dotnet && check_min_version dotnet "--version" "8.0"; then
    write_status "SKIP" ".NET SDK $(dotnet --version) 이미 설치됨 (>= 8.0)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        # brew cask로 dotnet 설치 시도, 없으면 formula 시도
        if brew info --cask dotnet &>/dev/null 2>&1; then
            brew_cask_install dotnet ".NET SDK"
        else
            brew_install dotnet-sdk ".NET SDK"
        fi

        # PATH 설정 (brew 설치 경로가 다를 수 있음)
        DOTNET_PATH="/usr/local/share/dotnet"
        [[ -d "$DOTNET_PATH" ]] && add_to_path "$DOTNET_PATH"
        export PATH="$DOTNET_PATH:$PATH"
    else
        write_status "INSTALL" ".NET SDK 8.0 설치 필요"
    fi
fi

# --- dotnet-ef (Entity Framework CLI) ---
write_status "CHECK" "dotnet-ef 확인 중..."
if command_exists dotnet && dotnet tool list -g 2>/dev/null | grep -q "dotnet-ef"; then
    EF_VERSION=$(dotnet tool list -g | grep dotnet-ef | awk '{print $2}')
    write_status "SKIP" "dotnet-ef $EF_VERSION 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        if command_exists dotnet; then
            write_status "INSTALL" "dotnet-ef 설치 중..."
            dotnet tool install --global dotnet-ef
            write_status "OK" "dotnet-ef 설치 완료"

            # dotnet tools PATH
            DOTNET_TOOLS="$HOME/.dotnet/tools"
            add_to_path "$DOTNET_TOOLS"
            export PATH="$DOTNET_TOOLS:$PATH"
        else
            write_status "FAIL" "dotnet이 설치되지 않아 dotnet-ef를 설치할 수 없습니다"
        fi
    else
        write_status "INSTALL" "dotnet-ef 설치 필요"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
if command_exists dotnet; then
    write_status "OK" "dotnet:    $(dotnet --version)"
    write_status "OK" "SDK 목록:"
    dotnet --list-sdks 2>/dev/null | while read -r line; do
        write_status "OK" "  $line"
    done
else
    write_status "FAIL" "dotnet: 찾을 수 없음"
fi

DOTNET_EF_PATH="${HOME}/.dotnet/tools/dotnet-ef"
if [[ -f "$DOTNET_EF_PATH" ]] || command_exists dotnet-ef; then
    EF_VER=$(dotnet ef --version 2>/dev/null | head -1 || echo "설치됨")
    write_status "OK" "dotnet-ef: $EF_VER"
else
    write_status "FAIL" "dotnet-ef: 찾을 수 없음"
fi
echo ""
