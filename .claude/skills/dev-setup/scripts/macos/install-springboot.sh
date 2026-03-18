#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# dev-setup: Spring Boot 개발 환경 설치 (macOS)

echo ""
echo "=== Spring Boot 개발 환경 설치 ==="
echo ""

ensure_homebrew

# --- OpenJDK 17 ---
write_status "CHECK" "Java 17 확인 중..."
if command_exists java && java -version 2>&1 | grep -q 'version "17'; then
    write_status "SKIP" "OpenJDK 17 이미 설치됨"
else
    if [[ "$CHECK_ONLY" == "false" ]]; then
        brew_install openjdk@17 "OpenJDK 17"

        # JAVA_HOME 설정
        JAVA_HOME_PATH="$(brew --prefix openjdk@17)"
        write_status "INSTALL" "JAVA_HOME 설정 중..."

        local shell_rc="$HOME/.zshrc"
        [[ -f "$HOME/.bash_profile" ]] && shell_rc="$HOME/.bash_profile"

        if ! grep -q "JAVA_HOME.*openjdk@17" "$shell_rc" 2>/dev/null; then
            echo "export JAVA_HOME=\"$JAVA_HOME_PATH\"" >> "$shell_rc"
            echo "export PATH=\"\$JAVA_HOME/bin:\$PATH\"" >> "$shell_rc"
            write_status "OK" "JAVA_HOME 추가: $JAVA_HOME_PATH"
        fi

        export JAVA_HOME="$JAVA_HOME_PATH"
        export PATH="$JAVA_HOME/bin:$PATH"

        # 시스템 Java 심볼릭 링크
        JAVA_SYS_LINK="/usr/local/bin/java"
        if [[ ! -L "$JAVA_SYS_LINK" ]]; then
            write_status "INSTALL" "시스템 Java 심볼릭 링크 생성 중..."
            sudo ln -sfn "$JAVA_HOME_PATH/bin/java" "$JAVA_SYS_LINK" || \
                write_status "CHECK" "심볼릭 링크 생성 실패 — sudo 권한이 필요할 수 있습니다"
        fi

        write_status "OK" "OpenJDK 17 설치 완료"
    else
        write_status "INSTALL" "OpenJDK 17 설치 필요"
    fi
fi

# JAVA_HOME이 아직 미설정이면 brew prefix로 설정
if [[ -z "${JAVA_HOME:-}" ]] && command_exists brew; then
    BREW_JAVA="$(brew --prefix openjdk@17 2>/dev/null || true)"
    if [[ -n "$BREW_JAVA" && -d "$BREW_JAVA" ]]; then
        export JAVA_HOME="$BREW_JAVA"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
fi

# --- 검증 요약 ---
echo ""
echo "=== 검증 요약 ==="
if command_exists java; then
    write_status "OK" "java:    $(java -version 2>&1 | head -1)"
else
    write_status "FAIL" "java: 찾을 수 없음"
fi

if command_exists javac; then
    write_status "OK" "javac:   $(javac -version 2>&1)"
else
    write_status "FAIL" "javac: 찾을 수 없음"
fi

[[ -n "${JAVA_HOME:-}" ]] && write_status "OK" "JAVA_HOME: $JAVA_HOME"
echo ""
