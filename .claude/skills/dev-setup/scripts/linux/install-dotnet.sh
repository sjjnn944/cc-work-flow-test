#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# .NET 개발 환경 설치 (.NET SDK 8.0, dotnet-ef)

DOTNET_MIN="8.0"

check_sudo

# --- .NET SDK 8.0 ---
write_status "CHECK" ".NET SDK 버전 확인 중..."
DOTNET_NEEDS_INSTALL=true
if command_exists dotnet; then
    DOTNET_VER=$(dotnet --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)
    DOTNET_MAJOR=$(echo "$DOTNET_VER" | cut -d. -f1)
    if [[ "$DOTNET_MAJOR" -ge 8 ]]; then
        write_status "SKIP" "dotnet $DOTNET_VER — 이미 설치됨 (>= $DOTNET_MIN)"
        DOTNET_NEEDS_INSTALL=false
    else
        write_status "CHECK" "dotnet $DOTNET_VER — 8.0 이상 필요"
    fi
fi

if $DOTNET_NEEDS_INSTALL; then
    if $CHECK_ONLY; then
        write_status "INSTALL" ".NET SDK 8.0 설치 필요"
    else
        PKG_MGR=$(detect_pkg_manager)
        case "$PKG_MGR" in
            apt)
                write_status "INSTALL" "Microsoft 패키지 저장소 등록 중..."
                # Microsoft 패키지 저장소 GPG 키 및 sources 등록
                curl -fsSL https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb \
                    -o /tmp/packages-microsoft-prod.deb 2>/dev/null \
                    || {
                        # Ubuntu 버전 폴백: 직접 GPG 키 방식
                        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
                            | gpg --dearmor \
                            | sudo tee /usr/share/keyrings/microsoft-prod.gpg >/dev/null
                        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] \
https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" \
                            | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null
                        sudo apt-get update -qq
                        sudo apt-get install -y -qq dotnet-sdk-8.0
                    }
                if [[ -f /tmp/packages-microsoft-prod.deb ]]; then
                    sudo dpkg -i /tmp/packages-microsoft-prod.deb
                    rm -f /tmp/packages-microsoft-prod.deb
                    sudo apt-get update -qq
                    sudo apt-get install -y -qq dotnet-sdk-8.0
                fi
                ;;
            dnf)
                write_status "INSTALL" "Microsoft 저장소 등록 후 .NET 설치 중..."
                sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
                sudo dnf install -y https://packages.microsoft.com/config/fedora/$(rpm -E %fedora)/packages-microsoft-prod.rpm
                sudo dnf install -y dotnet-sdk-8.0
                ;;
            pacman)
                # Arch Linux: AUR 또는 community 저장소
                write_status "INSTALL" "dotnet-sdk 설치 중 (pacman)..."
                sudo pacman -S --noconfirm --needed dotnet-sdk
                ;;
            *)
                write_status "FAIL" "지원되지 않는 패키지 매니저"; exit 1 ;;
        esac
        write_status "OK" ".NET SDK 8.0 설치 완료"
    fi
fi

# --- dotnet-ef (Entity Framework Core CLI) ---
write_status "CHECK" "dotnet-ef 확인 중..."
EF_INSTALLED=false
if command_exists dotnet; then
    if dotnet tool list -g 2>/dev/null | grep -q "dotnet-ef"; then
        EF_VER=$(dotnet tool list -g 2>/dev/null | grep "dotnet-ef" | awk '{print $2}')
        write_status "SKIP" "dotnet-ef $EF_VER — 이미 설치됨"
        EF_INSTALLED=true
    fi
fi

if ! $EF_INSTALLED; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "dotnet-ef 설치 필요"
    elif command_exists dotnet; then
        write_status "INSTALL" "dotnet-ef global tool 설치 중..."
        dotnet tool install --global dotnet-ef
        # dotnet tools PATH 추가
        DOTNET_TOOLS="$HOME/.dotnet/tools"
        if [[ ":$PATH:" != *":$DOTNET_TOOLS:"* ]]; then
            export PATH="$DOTNET_TOOLS:$PATH"
            if ! grep -q '\.dotnet/tools' "$HOME/.bashrc" 2>/dev/null; then
                echo "export PATH=\"$DOTNET_TOOLS:\$PATH\"" >> "$HOME/.bashrc"
            fi
        fi
        write_status "OK" "dotnet-ef 설치 완료"
    else
        write_status "FAIL" "dotnet 없음 — dotnet-ef 설치 불가"
    fi
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
if command_exists dotnet; then
    write_status "OK" "dotnet      $(dotnet --version)"
else
    write_status "FAIL" "dotnet 없음"
fi
DOTNET_TOOLS_PATH="${HOME}/.dotnet/tools"
EF_BIN="$DOTNET_TOOLS_PATH/dotnet-ef"
if [[ -f "$EF_BIN" ]] || command_exists dotnet-ef; then
    EF_CMD="${EF_BIN}"
    command_exists dotnet-ef && EF_CMD="dotnet-ef"
    write_status "OK" "dotnet-ef   $("$EF_CMD" --version 2>&1 | head -1)"
else
    write_status "FAIL" "dotnet-ef 없음"
fi
