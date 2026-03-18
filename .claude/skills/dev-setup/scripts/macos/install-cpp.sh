#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: C++ 개발 환경 설치 (macOS)

echo ""
echo "=== C++ 개발 환경 설치 ==="
echo ""

ensure_homebrew
ensure_xcode_clt

# --- clang (Xcode CLT 포함) ---
write_status "CHECK" "clang 확인 중..."
if command_exists clang && check_min_version clang "--version" "14.0"; then
    write_status "SKIP" "clang $(clang --version 2>&1 | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
else
    write_status "FAIL" "clang를 찾을 수 없습니다. Xcode CLT 재설치를 시도하세요."
fi

# --- CMake ---
write_status "CHECK" "CMake 확인 중..."
if command_exists cmake && check_min_version cmake "--version" "3.20"; then
    write_status "SKIP" "CMake $(cmake --version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨 (>= 3.20)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install cmake CMake
    else
        write_status "INSTALL" "CMake 설치 필요"
    fi
fi

# --- Ninja ---
write_status "CHECK" "Ninja 확인 중..."
if command_exists ninja; then
    write_status "SKIP" "Ninja $(ninja --version) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install ninja Ninja
    else
        write_status "INSTALL" "Ninja 설치 필요"
    fi
fi

# --- vcpkg ---
write_status "CHECK" "vcpkg 확인 중..."
VCPKG_DIR="$(get_thirdparty_dir)/vcpkg"
if [[ -f "$VCPKG_DIR/vcpkg" ]]; then
    write_status "SKIP" "vcpkg 이미 설치됨 ($VCPKG_DIR)"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        write_status "INSTALL" "vcpkg 설치 중..."
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
        "$VCPKG_DIR/bootstrap-vcpkg.sh" -disableMetrics
        add_to_path "$VCPKG_DIR"
        write_status "OK" "vcpkg 설치 완료 ($VCPKG_DIR)"
    else
        write_status "INSTALL" "vcpkg 설치 필요 ($VCPKG_DIR)"
    fi
fi

# --- clang-format (optional) ---
write_status "CHECK" "clang-format 확인 중..."
if command_exists clang-format; then
    write_status "SKIP" "clang-format $(clang-format --version | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1) 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install clang-format clang-format
    else
        write_status "INSTALL" "clang-format 설치 필요 (optional)"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
command_exists clang      && write_status "OK" "clang:        $(clang --version 2>&1 | head -1)"
command_exists cmake      && write_status "OK" "cmake:        $(cmake --version | head -1)"
command_exists ninja      && write_status "OK" "ninja:        $(ninja --version)"
[[ -f "$VCPKG_DIR/vcpkg" ]] && write_status "OK" "vcpkg:        $VCPKG_DIR/vcpkg"
command_exists clang-format && write_status "OK" "clang-format: $(clang-format --version)"
echo ""
