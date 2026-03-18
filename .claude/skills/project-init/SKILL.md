---
name: project-init
description: 프로젝트 초기화 — scaffold/설계 워크플로우로 생성된 산출물(doc/architecture, doc/develop, doc/requirements, src, test)을 일괄 삭제한다. "프로젝트 초기화", "산출물 정리", "클린 리셋", "scaffold 결과 삭제" 등을 요청할 때 사용.
---

# 프로젝트 초기화

워크플로우 테스트 후 생성된 산출물을 삭제하여 프로젝트를 초기 상태로 되돌린다.

## 삭제 대상

| 디렉토리 | 내용 | 생성 주체 |
|----------|------|----------|
| `doc/architecture/*` | 아키텍처 문서 5종 | project-scaffold |
| `doc/develop/*` | 모듈별 설계 문서 (requirement, interface, implementation, test) | project-scaffold + detailed-design |
| `doc/requirements/*` | 요구사항 통합 문서 3종 | project-scaffold |
| `src/*` | 소스 폴더 트리 | project-scaffold |
| `test/*` | 테스트 폴더 트리 | project-scaffold |

## 보존 대상 (삭제하지 않음)

- `doc/base/*` — 가이드 문서
- `doc/designs/*` — 설계서 원본
- `.claude/skills/*` — 스킬 정의
- `CLAUDE.md` — 프로젝트 설정

## 실행

```bash
bash .claude/skills/project-init/scripts/clean.sh "$(pwd)"
```

실행 전 사용자에게 삭제 대상을 보여주고 확인을 받는다.
