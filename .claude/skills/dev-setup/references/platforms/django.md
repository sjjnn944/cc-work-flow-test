# Django 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| Python | 3.11+ | 런타임 | `python3 --version` |
| pip | latest | 패키지 설치 | `pip --version` |
| poetry 또는 pipenv | poetry 1.7+ | 의존성 관리 | `poetry --version` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| Django | 프레임워크 | pip/poetry로 설치 |
| pytest | 테스트 러너 | 개발 환경 |
| black | 포맷터 | 개발 환경 |
| ruff | 린터 | 개발 환경 |
| mypy | 타입 체커 | CI 환경 |

## 패키지 매니저
- 기본: pip / poetry
- 초기화: `poetry init` 또는 `pip install django && django-admin startproject`

## OS별 특이사항
- Windows: winget 또는 python.org 설치, py launcher 사용
- Linux: apt `python3 python3-pip python3-venv` / dnf `python3 python3-pip`
- macOS: `brew install python@3.11`
