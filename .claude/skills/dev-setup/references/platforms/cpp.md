# C++ 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| CMake | 3.20 | 빌드 시스템 | `cmake --version` |
| Ninja | 1.10 | 빌드 백엔드 | `ninja --version` |
| vcpkg | latest | 패키지 매니저 | `vcpkg version` |
| GCC/Clang/MSVC | GCC 11+ / Clang 14+ / MSVC 17+ | C++ 컴파일러 | `g++ --version` / `clang++ --version` / `cl` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| GTest | 단위 테스트 | 테스트 빌드 시 |
| Boost | 범용 라이브러리 | 설계서 의존성에 포함 시 |
| Doxygen | API 문서 생성 | 문서화 필요 시 |
| clang-tidy | 정적 분석 | CI 환경 |
| clang-format | 코드 포맷팅 | 개발 환경 |

## 패키지 매니저
- 기본: vcpkg
- 초기화: `vcpkg integrate install`

## 설치 경로
- vcpkg: `{project_root}/thirdparty/vcpkg/` (프로젝트별 격리)
- 기타 써드파티 라이브러리: `{project_root}/thirdparty/{library_name}/`

## OS별 특이사항
- Windows: MSVC (Visual Studio Build Tools 또는 VS 2022), winget으로 CMake/Ninja 설치, vcpkg는 git clone 후 bootstrap
- Linux: apt/dnf/pacman으로 gcc, cmake, ninja-build 설치. vcpkg는 git clone
- macOS: Homebrew로 cmake, ninja 설치. 컴파일러는 Xcode Command Line Tools (clang)
