# Rust 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| rustup | latest | Rust 툴체인 관리자 | `rustup --version` |
| cargo | latest (rustup과 함께) | 빌드/패키지 매니저 | `cargo --version` |
| rustc | 1.75+ | Rust 컴파일러 | `rustc --version` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| clippy | 린터 | `rustup component add clippy` |
| rustfmt | 포맷터 | `rustup component add rustfmt` |
| cargo-watch | 자동 리빌드 | 개발 편의 |
| cargo-audit | 보안 감사 | CI 환경 |

## 패키지 매니저
- 기본: crates.io (cargo)
- 초기화: `cargo init`

## OS별 특이사항
- Windows: rustup-init.exe 실행, MSVC Build Tools 필요 (링커)
- Linux: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- macOS: 동일한 rustup 설치, Xcode CLT 필요
