# Spring Boot 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| JDK | 17 | Java 런타임/컴파일러 | `java -version` |
| Gradle | 8.0 | 빌드 도구 (wrapper 사용) | `./gradlew --version` |
| SpotBugs | latest | 정적 분석 (Gradle 플러그인) | `./gradlew spotbugsMain` |
| OWASP Dependency-Check | latest | 의존성 보안 취약점 분석 (Gradle 플러그인) | `./gradlew dependencyCheckAnalyze` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| IntelliJ IDEA | IDE | 권장 |
| Docker | 컨테이너 빌드 | 배포 환경 |
| Lombok | 보일러플레이트 제거 | 설계서 의존성에 포함 시 |

## 패키지 매니저
- 기본: Maven Central (Gradle)
- 초기화: `gradle init --type java-application`

## OS별 특이사항
- Windows: winget으로 Microsoft OpenJDK 17 설치, JAVA_HOME 설정 필요
- Linux: apt `openjdk-17-jdk` / dnf `java-17-openjdk-devel`
- macOS: `brew install openjdk@17`
