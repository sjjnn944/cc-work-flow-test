---
name: project-scaffold
description: 시스템 아키텍처 설계서를 입력으로 프로젝트 폴더 구조(src/, doc/, test/)와
  핵심 문서(requirement.md, interface.md)를 자동 생성하는 스킬.
  프로젝트 초기화, 폴더 생성, 스캐폴딩, 설계서 기반 구조 생성 등을 요청할 때 사용.
---

<Purpose>
시스템 아키텍처 설계서를 입력으로 받아, `doc/base/folder-structure-guide.md` 규칙에 따라 프로젝트 폴더 구조와 핵심 문서를 자동 생성한다.

생성 범위:
- `src/` 폴더 트리 (include/entry 분리 원칙 적용)
- `doc/develop/` 미러링 + 필수 문서 파일 (requirement.md, interface.md, implementation.md, test.md)
- `doc/requirements/` 요구사항 통합 문서 3종
- `doc/architecture/` 아키텍처 문서 6종
- `test/` 미러링 (플랫폼별 규칙 적용)
</Purpose>

<Use_When>
- 시스템 아키텍처 설계서가 완성되어 프로젝트 폴더 구조를 생성해야 할 때
- "프로젝트 초기화", "폴더 구조 생성", "스캐폴딩" 등을 요청할 때
- 설계서 기반으로 src/, doc/, test/ 구조를 자동으로 만들고 싶을 때
- 새 프로젝트의 디렉토리 레이아웃을 설계서에서 도출해야 할 때
</Use_When>

<Do_Not_Use_When>
- 이미 존재하는 폴더 구조를 검증만 하고 싶을 때 (별도 검증 프롬프트 사용)
- 문서 내용을 상세하게 작성해야 할 때 (이 스킬은 템플릿+초안만 생성)
- 빌드 시스템 설정(CMakeLists.txt, build.gradle 등)을 생성해야 할 때
- 테스트 케이스/시나리오를 작성해야 할 때 (별도 작업)
</Do_Not_Use_When>

<Steps>

## 0. 입력 확인

1. **설계서 경로 확인**
   - 사용자가 설계서 경로를 제공한 경우 해당 파일을 사용
   - 제공하지 않은 경우 `doc/designs/*.md` 를 Glob으로 탐색하여 후보 목록 표시
   - 설계서가 없으면 중단하고 사용자에게 안내

2. **폴더 구조 가이드 확인**
   - `doc/base/folder-structure-guide.md` 존재 여부 확인
   - 없으면 중단하고 사용자에게 안내
   - **반드시 Read 도구로 가이드 전체를 읽어서 규칙을 파악**

3. **설계서 읽기**
   - 설계서 전체를 읽어서 다음 정보를 파악:
     - 독립운영시스템 목록 (시스템 코드, 명칭, 수)
     - 빌드 모듈 목록 (모듈코드, 유형, 빌드 산출물)
     - 모듈별 요구사항 (ID, 설명)
     - 모듈별 인터페이스 (Export/API/IPC/IOCTL)
     - 시스템 간 인터페이스 계약
     - 비기능 요구사항

## 1. 설계서 분석

설계서에서 다음 데이터를 구조화하여 추출한다.

### 1.1 독립운영시스템 목록

설계서의 "독립운영시스템 식별" 절에서 추출:

| 추출 항목 | 결정 사항 |
|----------|----------|
| 시스템 코드 목록 | 예: SVR, AGT → `svr/`, `agt/` 폴더 |
| CMN 존재 여부 | 전체 공통 모듈 유무 → `common/` 폴더 |
| 시스템 수 | 1개: 루트 배치 / N개: 시스템 폴더 분리 |

### 1.2 빌드 모듈 목록

설계서의 "빌드 모듈 구성" 절에서 각 모듈의 정보를 추출:
- 모듈코드 (예: SVR.POLCY, AGT.CORE, CMN.INSPT)
- 모듈명
- 유형 (EXE, DLL, SYS, JAR, npm 등)
- 빌드 산출물명
- 설명

### 1.3 프로토콜 소유권 매핑

설계서의 인터페이스 절에서 공유 프로토콜(IPC 메시지, 콜백 시그니처 등)의 주체↔소비자 관계를 추출한다.

| 추출 항목 | 설명 |
|----------|------|
| 프로토콜 명 | IPC 메시지, 콜백 등의 명칭 |
| 주체 모듈 | 프로토콜을 설계·구현하는 모듈 |
| 소비자 모듈 | 프로토콜을 사용만 하는 모듈 |

이 매핑은 Step 4 (interface.md 생성) 시 소비자 모듈의 "프로토콜 참조" 테이블에 반영한다.

### 1.4 모듈별 요구사항 및 인터페이스

설계서의 "모듈별 요구사항 + 인터페이스" 절에서 추출:
- 각 모듈의 요구사항 ID 목록과 설명
- 공개 인터페이스 (REST API, DLL Export, IPC, IOCTL 등)
- 의존 모듈 목록

### 1.5 비기능 요구사항

설계서의 "비기능 요구사항" 절에서 추출:
- 성능, 보안, 가용성 등 NFR 항목과 정량 기준

## 2. 모듈 분류

> **원문**: `folder-structure-guide.md` 4절 Step 2 — 모듈 분류

설계서의 "빌드 모듈 목록"에서 각 모듈의 모듈코드를 추출하고, 접두사로 분류한다.

| 모듈코드 접두사 | 분류 | src/ 경로 |
|---------------|------|----------|
| CMN.{CODE} | 전체 공통 | `src/common/{code}/` |
| {SYS}.{CODE} (공통성 모듈) | 시스템 내 공통 | `src/{sys}/common/{code}/` |
| {SYS}.{CODE} (도메인 모듈) | 도메인 모듈 | `src/{sys}/{domain}/{code}/` |

- **공통성 판단**: 모듈 설명에 "공통", "공유", "전체에서 사용" 등이 포함되면 `common/`에 배치
- **도메인 그룹핑**: 유사 기능의 모듈은 동일 도메인 폴더로 묶는다
- **경로 패턴**: 위 경로는 기본 구조(C++/CMake)의 예시이며, 프레임워크 사용 시 해당 참조 문서(2.3절)의 경로 패턴을 적용한다

**스킬 고유 판단 로직** (가이드에 없는 부분):
- 다른 모듈의 의존 대상으로만 사용되는 순수 라이브러리 → `common/`
- 도메인명은 영문 소문자 kebab-case 사용

## 3. src/ 폴더 트리 생성

> **원문**: `folder-structure-guide.md` 1절(시스템 루트 구조), 2.3절(플랫폼별 참조), 4절 Step 3(트리 생성)

### 3.1 시스템 루트 구조 결정

독립운영시스템 수에 따라 `src/` 루트 구조가 결정된다.

| 조건 | 루트 구조 | 시스템 폴더 |
|------|----------|------------|
| 독립운영시스템 1개 | `src/common/` + `src/{domain}/` | 없음 (프로젝트 루트에 바로 배치) |
| 독립운영시스템 N개 | `src/{시스템}/` + `src/common/` | 시스템 코드 → 소문자 폴더명 |

### 3.2 플랫폼별 참조

| 프레임워크/언어 | 참조 문서 | 주요 패턴 |
|---------------|----------|----------|
| C++/CMake | cpp.md | include/entry 구조, 2티어 |
| Spring Boot (Java/Kotlin) | springboot.md | Multi-module Gradle, 계층형 패키지 |
| Go (표준 레이아웃) | go.md | cmd/internal/pkg 패턴 |
| NestJS (Node.js/TypeScript) | nestjs.md | 모듈 기반, controller/service/provider |
| Django (Python) | django.md | App 기반, MTV 패턴 |
| ASP.NET Core (C#) | dotnet.md | Solution/Project, Clean Architecture |
| Rust (Cargo) | rust.md | Cargo workspace, crate 기반 |

### 3.3 트리 생성 순서

분류 결과에 따라 `src/` 트리를 생성한다. 상세 구조는 플랫폼별 참조 문서를 따른다.

1. 전체 공통: `src/common/` 하위에 플랫폼 규칙에 따라 생성
2. 시스템별 공통: `src/{sys}/common/` 하위에 생성
3. 도메인 모듈: `src/{sys}/{domain}/` 하위에 생성
4. 실행 모듈이 있는 경우: 플랫폼별 규칙에 따라 추가

**공통 원칙**: 모듈 경로(`src/{sys}/{domain}/{code}/`)까지는 플랫폼 무관. 그 내부 구조만 플랫폼별로 달라진다.

### 3.5 실행

- 위 구조에 따라 `mkdir -p` 명령으로 모든 폴더를 일괄 생성
- 생성 전 기존 폴더 존재 여부 확인 (이미 존재하면 건너뛰기)

## 4. doc/develop/ 미러링 + 문서 생성

> **참조**: `folder-structure-guide.md` 3.1절 — 개발 문서 미러링 규칙, 문서 파일 구성, 복수 파일 시 폴더 확장 규칙

### 4.1 폴더 미러링

> **원문**: `folder-structure-guide.md` 3.3절 — 프레임워크별 doc/develop 미러링

`src/` 구조를 `doc/develop/`에 그대로 복제한다. 프레임워크별 미러링 단위는 다음과 같다.

| 프레임워크 | 소스 경로 (미러링 단위) | doc/develop 경로 |
|-----------|----------------------|-----------------|
| C++/CMake | `src/{sys}/{domain}/{feature}/` | `doc/develop/{sys}/{domain}/{feature}/` |
| Spring Boot | `src/{sys}/{sys}-{domain}/` | `doc/develop/{sys}/{domain}/` |
| Go | `src/{sys}/internal/{domain}/` | `doc/develop/{sys}/{domain}/` |
| NestJS | `src/{sys}/src/{domain}/` | `doc/develop/{sys}/{domain}/` |
| Django | `src/{sys}/{domain}/` | `doc/develop/{sys}/{domain}/` |
| ASP.NET Core | `src/{sys}/src/{Sys}.Application/{Domain}/` | `doc/develop/{sys}/{domain}/` |
| Rust | `src/{sys}/{sys}-{domain}/` | `doc/develop/{sys}/{domain}/` |

- 소스 경로에서 프레임워크 특유의 접두사/경로를 제거하여 doc 경로를 도출
- doc/develop 하위 구조는 프레임워크와 무관하게 `{sys}/{domain}/` 형태로 통일
- 내부 계층 구조(controller/service/repository 등)는 구현 상세이므로 미러링하지 않음

### 4.2 문서 파일 생성

> **원문**: `folder-structure-guide.md` 3.1절 — 모듈별 문서 파일 구성

**폴더 유형별 requirement.md 내용:**

| 폴더 유형 | requirement.md 내용 |
|----------|---------------------|
| 상위 폴더 (하위 있음) | 하위 항목의 주요 내용 요약 |
| 말단 폴더 (하위 없음) | 해당 모듈의 상세 요구사항 |

**모듈별 문서 파일 구성 (말단 폴더):**

| 파일 | 용도 | 필수 |
|------|------|------|
| requirement.md | 요구사항 (FR, NFR, 제약사항) | O |
| interface.md | 인터페이스 선언 문서 | O |
| implementation.md | 내부 구현 가이드 | O |
| class-diagram.md | 클래스 다이어그램 | 선택 |
| sequence-diagram.md | 시퀀스 다이어그램 | 선택 |
| state-diagram.md | 상태 다이어그램 | 선택 |
| api-spec.md | API 명세 | 선택 |
| database-schema.md | DB 스키마 | 선택 |
| test.md | 테스트 케이스 | O |

**복수 파일 시 폴더 확장 규칙:**

동일 유형의 문서가 여러 개 필요한 경우, 파일명 대신 해당 유형의 폴더를 생성한다.

```
doc/develop/{시스템}/{경로}/{모듈코드}/
├── interface/             # 인터페이스가 여러 개인 경우
│   ├── scanner.md
│   └── worker.md
├── class-diagram/         # 다이어그램이 여러 개인 경우
│   ├── core.md
│   └── util.md
└── requirement.md
```

**스킬 생성 범위:** 이 스킬은 필수 문서(requirement.md, interface.md, implementation.md, test.md)만 생성한다. 선택 문서는 상세 설계 단계에서 별도 작성한다.

### 4.3 requirement.md 템플릿 (말단 폴더)

```markdown
# {모듈명} - 요구사항

> **모듈코드**: {SYS}.{CODE}
> **빌드 산출물**: {산출물명}
> **유형**: {유형}

## 기능 요구사항 (FR)

| ID | 설명 | 출처 |
|----|------|------|
| {요구사항 ID} | {설명} | {출처} |
(설계서에서 추출한 FR 목록)

## 비기능 요구사항 (NFR)

(해당 모듈에 적용되는 NFR이 있으면 기재)

## 의존 모듈

- {의존 모듈 목록}
```

### 4.4 interface.md 템플릿 (말단 폴더)

```markdown
# {모듈명} - 인터페이스

> **모듈코드**: {SYS}.{CODE}
> **인터페이스 유형**: {REST API / DLL Export / IPC / IOCTL / Library API 등}

## 프로토콜 참조

> 이 모듈이 소비하는 공유 프로토콜이 있으면 아래에 참조 경로를 기재한다.
> 주체 모듈인 경우 이 섹션은 "해당 없음"으로 기재한다.

| 프로토콜 | 주체 모듈 | 참조 경로 |
|----------|----------|----------|
| (없으면 "해당 없음") | | |

## 공개 인터페이스

(설계서에서 추출한 인터페이스 명세를 그대로 포함)

### 인터페이스 유형별 필수 포함 항목

인터페이스 유형에 따라 아래 항목을 반드시 포함한다. 설계서에 해당 정보가 없으면 placeholder(`/* 상세 설계 시 정의 */`)를 남긴다.

| 인터페이스 유형 | 필수 포함 항목 |
|---------------|--------------|
| DLL Export / Library API | 함수 시그니처 (반환 타입, 호출 규약, 파라미터 목록) |
| REST API | 엔드포인트, HTTP 메서드, 요청/응답 스키마 |
| IPC (Named Pipe, Shared Memory 등) | 메시지 코드, 헤더 구조체, **각 메시지별 payload 구조체** |
| IOCTL | IOCTL 코드, 입력/출력 버퍼 구조체 |
| 콜백 / 이벤트 | 콜백 함수 포인터 타입, 이벤트 코드, 이벤트 데이터 구조체 |

> **IPC/IOCTL 유형 주의**: 메시지 코드와 헤더만 정의하고 payload 구조체를 생략하면, 소비자 모듈이 상세 설계 시 wire format을 추론해야 한다. 프로토콜 주체 모듈의 interface.md에 payload 구조체를 반드시 포함한다.
```

### 4.5 implementation.md 템플릿 (말단 폴더)

```markdown
# {모듈명} - 구현 가이드

> **모듈코드**: {SYS}.{CODE}
> **상태**: 미작성

## 내부 구조

(상세 설계 시 작성)

## 클래스/컴포넌트 설계

(상세 설계 시 작성)
```

### 4.6 test.md 템플릿 (말단 폴더)

```markdown
# {모듈명} - 테스트 케이스

> **모듈코드**: {SYS}.{CODE}
> **상태**: 미작성

## 단위 테스트

(테스트 설계 시 작성)

## 통합 테스트

(테스트 설계 시 작성)
```

### 4.7 requirement.md 템플릿 (상위 폴더)

```markdown
# {폴더명} - 요약

## 하위 모듈

| 모듈코드 | 모듈명 | 설명 |
|----------|--------|------|
(하위 폴더에 포함된 모듈 목록)
```

## 5. doc/requirements/ 생성

설계서의 요구사항을 통합하여 3개 파일을 생성한다.

### 5.1 system-requirements.md

```markdown
# 시스템 요구사항 통합

## 개요
(설계서의 시스템 개요 요약)

## 시스템별 요구사항 요약

### {시스템코드} - {시스템명}
| 모듈코드 | 모듈명 | FR 수 | NFR 수 |
|----------|--------|-------|--------|
(설계서에서 집계한 모듈별 요구사항 수)
```

### 5.2 functional-requirements.md

```markdown
# 기능 요구사항 (FR)

## {시스템코드}.{모듈코드} - {모듈명}

| ID | 설명 | 출처 |
|----|------|------|
(설계서에서 추출한 모든 FR을 모듈별로 분류하여 나열)
```

### 5.3 non-functional-requirements.md

```markdown
# 비기능 요구사항 (NFR)

## 성능

| ID | 기준 수치 | 측정 방법 |
|----|----------|----------|

## 보안

...

## 가용성

...
(설계서의 NFR 절에서 추출하여 분류별로 나열)
```

## 6. doc/architecture/ 생성

설계서 내용을 기반으로 6개 아키텍처 문서를 생성한다.

### 생성 파일 목록

| 파일 | 내용 원천 |
|------|----------|
| `system-overview.md` | 설계서 1절(시스템 개요) + 독립운영시스템 식별 근거 |
| `component-diagram.md` | 설계서 3절(빌드 모듈 구성) 기반 컴포넌트 다이어그램 (mermaid) |
| `deployment-diagram.md` | 설계서 2절(기술 스택) + 1절 배포 환경 기반 배포 다이어그램 (mermaid) |
| `data-flow.md` | 설계서 3.3절(의존 관계도) + 4절(인터페이스) 기반 데이터 흐름도 |
| `interface-spec.md` | 설계서 5절(시스템 간 인터페이스 계약) 기반 인터페이스 명세 |
| `module-mapping.md` | Step 2(모듈 분류) + Step 3(src 트리) + Step 4(doc 미러링) + Step 7(test 미러링) 결과를 통합한 매핑 테이블 |

각 파일은 설계서 데이터를 기반으로 초안 수준으로 작성한다. mermaid 다이어그램이 가능한 경우 mermaid 코드 블록을 포함한다.

### 6.6 module-mapping.md

모든 스캐폴딩 단계의 결과를 통합하여 모듈별 경로 매핑 문서를 생성한다.

**생성 규칙:**

1. **매핑 테이블**: Step 2~7의 결과를 아래 컬럼으로 통합
2. **플랫폼 판별**: 모듈의 시스템 코드와 유형으로 플랫폼을 결정
   - `agt/` 하위 → C++/CMake
   - `svr/` 하위 → Spring Boot
   - 유형이 SYS → Windows Driver
   - 기타: 설계서의 기술 스택 절에서 판별
3. **정렬 순서**: 시스템(CMN → AGT → SVR) > 분류(common → domain) > 모듈코드 알파벳
4. **플랫폼별 참조 테이블**: 사용된 플랫폼에 대해서만 가이드 문서 경로를 기재

**템플릿:**

```markdown
# 모듈 폴더 매핑

> **생성**: project-scaffold 스킬에 의해 자동 생성
> **용도**: 구현 시 모듈별 소스/문서/테스트 경로 참조
> **설계서**: {설계서 경로}

## 매핑 테이블

| 모듈코드 | 모듈명 | 유형 | 플랫폼 | doc 경로 | src 경로 | test 경로 |
|----------|--------|------|--------|----------|----------|----------|
| {SYS}.{CODE} | {모듈명} | {EXE/DLL/SYS/JAR/...} | {플랫폼} | doc/develop/{...}/ | src/{...}/ | test/unit/{...}/ |

## 플랫폼별 참조

| 플랫폼 | 설계 패턴 | 폴더 구조 | 구현 가이드 |
|--------|----------|----------|------------|
| C++/CMake | doc/base/detailed-designs/cpp.md | doc/base/folder-structures/cpp.md | doc/base/implementation-guide.md |
| Spring Boot | doc/base/detailed-designs/springboot.md | doc/base/folder-structures/springboot.md | doc/base/implementation-guide.md |
| Windows Driver | doc/base/detailed-designs/driver.md | doc/base/folder-structures/cpp.md | doc/base/implementation-guide.md |
```

> **참고**: 플랫폼별 참조 테이블에는 프로젝트에서 실제 사용되는 플랫폼만 포함한다.

## 7. test/ 미러링

> **원문**: `folder-structure-guide.md` 4절 Step 6 — 플랫폼별 테스트 구조 규칙

테스트 구조는 플랫폼별 참조 문서의 test 구조 규칙을 따른다.

| 플랫폼 | 테스트 위치 | 비고 |
|--------|-----------|------|
| C++/CMake | `test/unit/`에 `src/`의 기능 모듈 경로를 미러링 | `entry/` 제외 (통합 테스트 대상) |
| Spring Boot, NestJS 등 | 모듈 내 `src/test/`에 위치 | 별도 `test/unit/` 미러링 불필요 |
| Go, Rust | 소스 파일과 동일 디렉토리 | `_test.go` / `#[cfg(test)]` 배치 |

- 빈 폴더만 생성 (테스트 코드 파일은 생성하지 않음)
- C++/CMake 외 플랫폼은 프레임워크 관례에 따라 테스트 위치가 결정되므로, 별도 폴더 생성이 불필요할 수 있음

## 8. 출력 및 검증

### 8.1 결과 출력

생성 완료 후 다음을 출력한다:
1. **전체 폴더 트리** (tree 명령 또는 텍스트 트리)
2. **생성 통계**: 폴더 수, 문서 파일 수
3. **모듈 매핑 표**: 모듈코드 → src 경로 → doc 경로 → test 경로 → `doc/architecture/module-mapping.md`에 저장됨

### 8.2 3중 미러링 일관성 검증

다음 검증을 자동 수행하고 결과를 보고한다:

| 검증 항목 | 방법 |
|----------|------|
| src ↔ doc/develop 일치 | src/ 하위 폴더가 doc/develop/에 모두 존재하는지 확인 |
| src ↔ test 일치 | 플랫폼별 규칙에 따라 테스트 폴더가 올바르게 생성되었는지 확인 |
| 말단 폴더 문서 존재 | doc/develop/ 말단 폴더에 requirement.md, interface.md가 존재하는지 확인 |
| 설계서 모듈 누락 | 설계서의 모든 빌드 모듈이 src/에 매핑되었는지 확인 |
| 프로토콜 참조 일관성 | 소비자 모듈의 프로토콜 참조 경로가 실제 주체 모듈의 interface.md를 가리키는지 확인 |
| module-mapping.md 일관성 | module-mapping.md의 모든 경로가 실제 생성된 폴더와 일치하는지 확인 |

</Steps>

<Scope_Exclusion>
- **문서 내용 상세 작성은 범위 외**: 템플릿 + 설계서 기반 초안만 생성. 상세 설계(클래스 다이어그램, 시퀀스 다이어그램 등)는 별도 작업.
- **테스트 케이스/시나리오**: 별도 작업으로 분리. test.md는 빈 템플릿만 생성.
- **빌드 시스템 설정**: CMakeLists.txt, build.gradle, package.json 등은 생성하지 않음.
- **CI/CD 파이프라인**: 생성하지 않음.
- **코딩 컨벤션 파일**: .editorconfig, .clang-format 등은 생성하지 않음.
</Scope_Exclusion>

<Tool_Usage>
- **Read 도구**: 설계서와 folder-structure-guide.md를 읽어서 규칙 및 데이터 추출
- **Glob 도구**: `doc/designs/*.md` 탐색, 기존 폴더 구조 확인
- **Bash 도구**: `mkdir -p` 로 폴더 일괄 생성, `tree` 로 결과 확인
- **Write 도구**: requirement.md, interface.md 등 문서 파일 생성
- **Grep 도구**: 설계서에서 특정 모듈 정보 검색 (대용량 설계서일 경우)
</Tool_Usage>

<Examples>

<Good>
설계서에서 모듈을 정확히 분류하여 폴더 생성:
```
설계서 모듈: CMN.INSPT (콘텐츠 검사 엔진, DLL)
→ 분류: 전체 공통 (CMN 접두사)
→ Executable: DLL이므로 독립 산출물 있음 → entry/ 포함
→ src/common/inspt/include/
→ src/common/inspt/entry/
→ doc/develop/common/inspt/requirement.md  (설계서의 CMN.INSPT 요구사항 포함)
→ doc/develop/common/inspt/interface.md    (설계서의 CMN.INSPT 인터페이스 포함)
→ test/unit/common/inspt/                  (entry/ 제외)
```
</Good>

<Good>
도메인 그룹핑을 적용한 폴더 생성:
```
설계서 모듈: AGT.DEVC (매체 제어), AGT.APPCT (앱 제어), AGT.PRINT (출력물 보안)
→ 분류: 각각 도메인 모듈
→ 도메인 그룹핑:
  - AGT.DEVC, AGT.APPCT → "control" 도메인 (매체/앱 제어)
  - AGT.PRINT → "print" 도메인 (출력물 보안)
→ src/agt/control/devc/include/ + entry/
→ src/agt/control/appct/include/ + entry/
→ src/agt/print/print/include/ + entry/
```
</Good>

<Good>
3중 미러링 검증 결과 보고:
```
=== 3중 미러링 검증 ===
[PASS] src ↔ doc/develop: 42/42 폴더 일치
[PASS] src ↔ test/unit: 25/25 경로 일치 (entry/ 제외)
[PASS] 말단 폴더 문서: 25/25 모듈에 requirement.md, interface.md 존재
[PASS] 설계서 모듈 누락: 0개 (25/25 모듈 매핑 완료)
```
</Good>

<Bad>
entry/를 test/unit/에 미러링:
```
test/unit/agt/core/core/entry/  (X)
```
entry/는 통합 테스트 대상이므로 test/unit/에 미러링하지 않는다.
</Bad>

<Bad>
설계서에 없는 모듈 폴더를 임의로 생성:
```
src/agt/utils/helper/   (설계서에 없는 모듈)
```
설계서의 빌드 모듈 목록에 있는 모듈만 폴더를 생성한다.
</Bad>

<Bad>
공통 모듈을 도메인에 배치:
```
SVR.CRYPT (서버 암호 라이브러리) → src/svr/crypto/crypt/  (X)
```
SVR.CRYPT은 서버 내 여러 모듈에서 공유하는 라이브러리이므로 `src/svr/common/crypt/`에 배치해야 한다.
</Bad>

</Examples>

<Test_Prompts>

### 테스트 1: DLP 프로젝트 스캐폴딩

```
/project-scaffold
설계서를 기반으로 프로젝트 폴더 구조를 생성해줘.

[입력]
- 폴더 구조 가이드: doc/base/folder-structure-guide.md
- 설계서: doc/designs/dlp-system-architecture.md

[범위]
- src/ 폴더 트리 생성 (25개 모듈 전체)
- doc/develop/ 미러링 + 필수 문서 파일 생성
- doc/requirements/ 3개 파일 생성
- doc/architecture/ 6개 파일 생성
- test/ 미러링 (플랫폼별 규칙 적용)
```

**기대 결과:**
- SVR 11개 모듈 + AGT 12개 모듈 + CMN 2개 모듈 = 25개 모듈의 폴더 생성
- 3중 미러링 일관성 검증 통과
- doc/requirements/ 3개 파일, doc/architecture/ 6개 파일 존재

### 테스트 2: 최소 입력 (설계서만 지정)

```
/project-scaffold
doc/designs/dlp-system-architecture.md 기반으로 프로젝트 구조 초기화해줘.
```

**기대 결과:**
- folder-structure-guide.md 자동 탐색
- 테스트 1과 동일한 결과

### 테스트 3: 특정 시스템만 스캐폴딩

```
/project-scaffold
doc/designs/dlp-system-architecture.md에서 AGT(에이전트) 시스템만 스캐폴딩해줘.
```

**기대 결과:**
- AGT 12개 모듈 + CMN 2개 모듈 폴더만 생성
- SVR 모듈은 생성하지 않음

</Test_Prompts>

<Final_Checklist>
- [ ] 설계서와 folder-structure-guide.md를 모두 읽었는가?
- [ ] 독립운영시스템 수에 따라 루트 구조가 결정되었는가? (1개: 루트 배치, N개: 시스템 폴더)
- [ ] 모든 빌드 모듈이 분류되었는가? (전체 공통 / 시스템 내 공통 / 도메인)
- [ ] Library-only vs Executable 구분이 정확한가? (entry/ 유무)
- [ ] 모듈코드가 소문자로 변환되어 폴더명으로 사용되었는가?
- [ ] src/ 폴더가 folder-structure-guide.md 2절 규칙대로 생성되었는가?
- [ ] doc/develop/ 가 src/ 와 동일 구조로 미러링되었는가?
- [ ] 말단 폴더에 requirement.md, interface.md, implementation.md, test.md가 생성되었는가?
- [ ] requirement.md에 설계서의 요구사항 데이터가 포함되었는가?
- [ ] interface.md에 설계서의 인터페이스 명세가 포함되었는가?
- [ ] doc/requirements/ 3개 파일이 생성되었는가?
- [ ] doc/architecture/ 6개 파일이 생성되었는가?
- [ ] test/ 구조가 플랫폼별 참조 문서의 규칙대로 생성되었는가?
- [ ] 3중 미러링 일관성 검증을 수행하고 결과를 보고했는가?
- [ ] 설계서의 모든 빌드 모듈이 누락 없이 매핑되었는가?
- [ ] doc/architecture/module-mapping.md가 생성되었는가?
- [ ] module-mapping.md의 모든 src/doc/test 경로가 실제 폴더와 일치하는가?
</Final_Checklist>
