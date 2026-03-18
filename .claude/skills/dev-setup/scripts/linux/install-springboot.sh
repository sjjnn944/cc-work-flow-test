#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_common.sh" "$@"

# Spring Boot 개발 환경 설치 (OpenJDK 17, JAVA_HOME 설정)

check_sudo

# --- OpenJDK 17 ---
write_status "CHECK" "Java 버전 확인 중..."
JAVA_OK=false
if command_exists java; then
    JAVA_VER=$(java -version 2>&1 | grep -oP '\d+' | head -1)
    if [[ "$JAVA_VER" -ge 17 ]]; then
        write_status "SKIP" "java $JAVA_VER — 이미 설치됨 (>= 17)"
        JAVA_OK=true
    else
        write_status "CHECK" "java $JAVA_VER 설치됨 — 17 이상 필요"
    fi
fi

if ! $JAVA_OK; then
    if $CHECK_ONLY; then
        write_status "INSTALL" "OpenJDK 17 설치 필요"
    else
        PKG_MGR=$(detect_pkg_manager)
        case "$PKG_MGR" in
            apt)    pkg_install "OpenJDK 17" openjdk-17-jdk ;;
            dnf)    pkg_install "OpenJDK 17" java-17-openjdk-devel ;;
            pacman) pkg_install "OpenJDK 17" jdk17-openjdk ;;
            *)      write_status "FAIL" "지원되지 않는 패키지 매니저"; exit 1 ;;
        esac
        write_status "OK" "OpenJDK 17 설치 완료"
    fi
fi

# --- JAVA_HOME 설정 ---
write_status "CHECK" "JAVA_HOME 확인 중..."
if [[ -n "${JAVA_HOME:-}" ]] && [[ -d "$JAVA_HOME" ]]; then
    write_status "SKIP" "JAVA_HOME=$JAVA_HOME — 이미 설정됨"
else
    if $CHECK_ONLY; then
        write_status "INSTALL" "JAVA_HOME 설정 필요"
    else
        # JAVA_HOME 자동 탐지
        DETECTED_JAVA_HOME=""
        if command_exists java; then
            JAVA_BIN=$(readlink -f "$(command -v java)" 2>/dev/null || true)
            if [[ -n "$JAVA_BIN" ]]; then
                DETECTED_JAVA_HOME=$(dirname "$(dirname "$JAVA_BIN")")
            fi
        fi
        # 공통 위치 폴백
        for candidate in /usr/lib/jvm/java-17-openjdk-amd64 \
                         /usr/lib/jvm/java-17-openjdk \
                         /usr/lib/jvm/temurin-17; do
            if [[ -d "$candidate" ]]; then
                DETECTED_JAVA_HOME="$candidate"
                break
            fi
        done

        if [[ -n "$DETECTED_JAVA_HOME" ]]; then
            export JAVA_HOME="$DETECTED_JAVA_HOME"
            if ! grep -q "JAVA_HOME" "$HOME/.bashrc" 2>/dev/null; then
                echo "export JAVA_HOME=\"$DETECTED_JAVA_HOME\"" >> "$HOME/.bashrc"
                echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> "$HOME/.bashrc"
            fi
            write_status "OK" "JAVA_HOME=$DETECTED_JAVA_HOME"
        else
            write_status "FAIL" "JAVA_HOME 자동 탐지 실패 — 수동 설정 필요"
        fi
    fi
fi

# --- javac 확인 ---
write_status "CHECK" "javac 확인 중..."
if command_exists javac; then
    JAVAC_VER=$(javac -version 2>&1 | grep -oP '\d+' | head -1)
    if [[ "$JAVAC_VER" -ge 17 ]]; then
        write_status "SKIP" "javac $JAVAC_VER — 이미 설치됨"
    else
        write_status "CHECK" "javac $JAVAC_VER — 17 이상 권장"
    fi
else
    write_status "FAIL" "javac 없음 — JDK(개발 도구) 설치 확인 필요"
fi

# --- Gradle wrapper 안내 ---
write_status "CHECK" "Gradle wrapper 안내"
write_status "OK" "Spring Boot 프로젝트는 gradlew(Gradle wrapper)를 내장합니다"
write_status "OK" "시스템 Gradle 설치 불필요 — ./gradlew 사용 권장"

# --- 최종 검증 ---
echo ""
write_status "CHECK" "=== 설치 검증 ==="
if command_exists java; then
    write_status "OK" "java        $(java -version 2>&1 | head -1)"
else
    write_status "FAIL" "java 없음"
fi
if command_exists javac; then
    write_status "OK" "javac       $(javac -version 2>&1)"
else
    write_status "FAIL" "javac 없음"
fi
write_status "OK" "JAVA_HOME   ${JAVA_HOME:-미설정}"
