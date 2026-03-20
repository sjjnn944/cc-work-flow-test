#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# C++ 개발 환경 설치 (GCC, CMake, Ninja, vcpkg)

check_sudo

# --- GCC (g++) ---
write_status "CHECK" "GCC 버전 확인 중..."
if check_min_version "g++" "--version" "11.0"; then
    write_status "SKIP" "g++ $(g++ --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨 (>= 11)"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "g++ 설치 필요 (>= 11)"
    else
        PKG_MGR=$(detect_pkg_manager)
        case "$PKG_MGR" in
            apt)    pkg_install "GCC/g++" build-essential ;;
            dnf)    pkg_install "GCC/g++" gcc-c++ make ;;
            pacman) pkg_install "GCC/g++" base-devel ;;
        esac
        write_status "OK" "g++ 설치 완료"
    fi
fi

# --- CMake ---
write_status "CHECK" "CMake 버전 확인 중..."
if check_min_version "cmake" "--version" "3.20"; then
    write_status "SKIP" "cmake $(cmake --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1) — 이미 설치됨 (>= 3.20)"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "cmake 설치 필요 (>= 3.20)"
    else
        PKG_MGR=$(detect_pkg_manager)
        if [[ "$PKG_MGR" == "apt" ]]; then
            # Kitware APT 저장소 등록 후 최신 CMake 설치
            write_status "INSTALL" "Kitware APT 저장소 등록 중..."
            sudo apt-get install -y -qq gpg curl ca-certificates
            curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc \
                | gpg --dearmor - \
                | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
                | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y -qq cmake
        else
            pkg_install "CMake" cmake
        fi
        write_status "OK" "cmake 설치 완료"
    fi
fi

# --- Ninja ---
write_status "CHECK" "Ninja 확인 중..."
if command_exists ninja; then
    write_status "SKIP" "ninja $(ninja --version 2>/dev/null) — 이미 설치됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "ninja 설치 필요"
    else
        PKG_MGR=$(detect_pkg_manager)
        case "$PKG_MGR" in
            apt)    pkg_install "Ninja" ninja-build ;;
            dnf)    pkg_install "Ninja" ninja-build ;;
            pacman) pkg_install "Ninja" ninja ;;
        esac
        write_status "OK" "ninja 설치 완료"
    fi
fi

# --- vcpkg ---
write_status "CHECK" "vcpkg 확인 중..."
VCPKG_DIR="$(get_thirdparty_dir)/vcpkg"
if [[ -x "$VCPKG_DIR/vcpkg" ]]; then
    write_status "SKIP" "vcpkg — 이미 설치됨 ($VCPKG_DIR)"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "vcpkg 설치 필요 ($VCPKG_DIR)"
    else
        write_status "INSTALL" "vcpkg 클론 및 부트스트랩 중..."
        pkg_install "git" git
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
        "$VCPKG_DIR/bootstrap-vcpkg.sh" -disableMetrics
        if ! grep -q "VCPKG_ROOT" "$HOME/.bashrc" 2>/dev/null; then
            echo "export VCPKG_ROOT=\"$VCPKG_DIR\"" >> "$HOME/.bashrc"
            echo "export PATH=\"\$VCPKG_ROOT:\$PATH\"" >> "$HOME/.bashrc"
        fi
        export VCPKG_ROOT="$VCPKG_DIR"
        export PATH="$VCPKG_DIR:$PATH"
        write_status "OK" "vcpkg 설치 완료 (VCPKG_ROOT=$VCPKG_DIR)"
    fi
fi

# --- Optional: clang-format, clang-tidy ---
write_status "CHECK" "clang-format / clang-tidy 확인 중..."
if command_exists clang-format && command_exists clang-tidy; then
    write_status "SKIP" "clang-format, clang-tidy — 이미 설치됨"
elif ! $CHECK_ONLY; then
    PKG_MGR=$(detect_pkg_manager)
    case "$PKG_MGR" in
        apt)    pkg_install "clang tools" clang-format clang-tidy ;;
        dnf)    pkg_install "clang tools" clang-tools-extra ;;
        pacman) pkg_install "clang tools" clang ;;
    esac
    write_status "OK" "clang-format / clang-tidy 설치 완료"
fi

# --- cppcheck ---
write_status "CHECK" "cppcheck 확인 중..."
if command_exists cppcheck; then
    write_status "SKIP" "cppcheck $(cppcheck --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*') — 이미 설치됨"
elif ! $CHECK_ONLY; then
    PKG_MGR=$(detect_pkg_manager)
    case "$PKG_MGR" in
        apt)    pkg_install "cppcheck" cppcheck ;;
        dnf)    pkg_install "cppcheck" cppcheck ;;
        pacman) pkg_install "cppcheck" cppcheck ;;
    esac
    write_status "OK" "cppcheck 설치 완료"
fi

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
command_exists g++        && write_status "OK" "g++         $(g++ --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)" || write_status "FAIL" "g++ 없음"
command_exists cmake      && write_status "OK" "cmake       $(cmake --version 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)" || write_status "FAIL" "cmake 없음"
command_exists ninja      && write_status "OK" "ninja       $(ninja --version 2>/dev/null)" || write_status "FAIL" "ninja 없음"
[[ -x "$VCPKG_DIR/vcpkg" ]] && write_status "OK" "vcpkg       $VCPKG_DIR" || write_status "FAIL" "vcpkg 없음"
