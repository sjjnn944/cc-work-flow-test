---
name: parallel-impl
description: 모듈 의존성 분석 후 병렬 배치로 소스 코드 구현 및 Phase A 검증을 자동 실행하는 스킬. "병렬 구현", "전체 모듈 구현", "소스 코드 일괄 작성", "parallel impl", "구현 일괄", "모듈 구현 실행", "코드 구현 실행" 등을 요청할 때 사용. implementation.md와 interface.md가 준비된 상태에서 실제 소스 코드를 생성하고 빌드/테스트까지 수행하려 할 때 반드시 이 스킬을 사용할 것.
---

<Purpose>
doc/develop/ 내 모듈들을 탐색하고, interface.md의 소유권/참조 관계를 분석하여 의존성 그래프를 구축한 뒤, 위상 정렬(topological sort)로 병렬 실행 가능한 배치(step)를 생성한다. 각 배치를 /team N:deep-executor로 실행하여 소스 코드 구현과 Phase A 검증(빌드 + 정적 분석 + 단위 테스트)을 병렬로 수행한다.

핵심 가치:
- 의존성 순서 보장: Owner 모듈이 먼저 구현되어야 Consumer 모듈이 헤더를 참조할 수 있다
- 즉시 검증: 각 모듈 구현 직후 빌드 + 단위 테스트를 수행하여 조기에 문제를 발견한다
- 프로토콜 참조 원칙 강제: 소비자가 주체의 프로토콜 정의를 인라인 복사하는 것을 방지
- 자족적 워커 프롬프트: 각 워커가 독립적으로 작업 가능하도록 모든 입력 경로와 플랫폼 정보를 명시
</Purpose>

<Use_When>
- 전체 또는 특정 서브시스템(agt/svr)의 소스 코드를 일괄 구현할 때
- implementation.md 설계가 완료된 모듈들을 실제 코드로 변환할 때
- 모듈 간 의존성을 고려한 구현 순서가 필요할 때
- 구현 직후 빌드 + 단위 테스트(Phase A)까지 자동으로 수행하고 싶을 때
- 병렬 에이전트로 구현 처리량을 최대화하고 싶을 때
</Use_When>

<Do_Not_Use_When>
- 단일 모듈만 구현할 때 (직접 implementation.md와 implementation-guide.md 참조)
- implementation.md가 아직 작성되지 않았을 때 (먼저 /parallel-design 사용)
- interface.md가 없을 때 (먼저 /project-scaffold 사용)
- 기존 소스 코드를 수정/리팩토링할 때
- 빌드 환경(dev-setup)이 준비되지 않았을 때
</Do_Not_Use_When>

<Arguments>
인수 형식: `/parallel-impl [subsystem] [--force] [--dry-run] [--workers N] [--skip-verify]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt` 또는 `svr` — 특정 서브시스템만 대상 |
| --force | false | src/ 내 소스 파일이 이미 존재해도 재구현 |
| --dry-run | false | .temp/ 파일만 생성하고 실행하지 않음 |
| --workers N | (배치 내 모듈 수) | 배치당 병렬 워커 수 제한 |
| --skip-verify | false | Phase A 검증(빌드 + 정적 분석 + 단위 테스트) 생략 |
</Arguments>

<Steps>

## Step 0: 초기화

1. `doc/base/implementation-guide.md` 존재 확인 — 없으면 중단
2. `doc/architecture/module-mapping.md` 존재 확인 — 없으면 중단 (src 경로 해석 불가)
3. `.temp/` 디렉토리 확인 — 없으면 `mkdir -p .temp`
4. `.temp/impl-results/` 디렉토리 확인 — 없으면 `mkdir -p .temp/impl-results`
5. `.temp/step-*-impl-batch.md` 기존 파일이 있으면 자동으로 덮어쓴다 (별도 확인 없이 진행)
6. `.temp/impl-results/*.result.md`, `step-*-summary.md`, `execution-report.md` 기존 파일이 있으면 덮어쓴다

## Step 1: 모듈 탐색 (Discovery)

Glob으로 모든 implementation.md를 찾아 모듈 목록을 구축한다.

**탐색 범위:**
- subsystem 미지정: `Glob("doc/develop/**/implementation.md")`
- `agt` 지정: `Glob("doc/develop/agt/**/implementation.md")`
- `svr` 지정: `Glob("doc/develop/svr/**/implementation.md")`

**모듈 식별자 추출 규칙:**

경로 패턴별 파싱:
```
doc/develop/{sys}/{category}/{module}/implementation.md
  → module_id: {SYS}.{MODULE}  (대문자)
  → 예: doc/develop/agt/core/core/implementation.md → AGT.CORE

doc/develop/{sys}/{module}/implementation.md  (category 없는 flat 구조)
  → module_id: {SYS}.{MODULE}
  → 예: doc/develop/svr/api/implementation.md → SVR.API
        doc/develop/agt/update/implementation.md → AGT.UPDATE
```

**src 경로 해석:**

`doc/architecture/module-mapping.md`를 Read하여 각 module_id에 대응하는 src 경로와 플랫폼 정보를 추출한다.

```
mapping 예시:
  AGT.CORE → src/agt/core/core/   (platform: cpp)
  SVR.API  → src/svr/api/         (platform: springboot)
```

**Skip 판정:**

각 모듈의 src 디렉토리에 소스 파일이 이미 존재하는지 확인:
- C++ 모듈: `*.cpp`, `*.h`, `*.hpp` 파일 존재 여부 (Glob 사용)
- Java/Spring 모듈: `*.java` 파일 존재 여부 (Glob 사용)
- 존재하고 `--force`가 아니면 → skip 목록에 추가
- 존재하지 않으면 → 대상 목록에 추가
- `--force`이면 → 무조건 대상 목록에 추가

**필수 파일 검증:**

각 대상 모듈에 다음 파일이 모두 존재하는지 확인:
- `interface.md` — 없으면 경고 출력 후 해당 모듈 skip
- `test.md` — 없으면 경고 출력 (skip 없이, --skip-verify 없어도 단위 테스트만 생략)

## Step 2: 의존성 분석 (Dependency Analysis)

각 대상 모듈의 interface.md를 Read하여 의존 관계를 파싱한다.

**파싱 규칙:**

1. **소유권 판정**: `## 소유권` 절의 텍스트에서:
   - `주체(Owner)` 포함 → role = "owner"
   - `소비자(Consumer)` 포함 → role = "consumer"
   - 둘 다 포함 → role = "mixed" (주체이면서 소비자)

2. **참조 경로 추출**: `→` 로 시작하는 행에서 backtick 내 경로를 추출:
   ```
   → {설명} 참조: `{path}`
   ```
   backtick 사이의 경로가 의존 대상 모듈의 interface.md 경로이다.

3. **의존 대상 모듈 식별**: 추출한 경로에서 module_id를 역으로 파싱:
   ```
   doc/develop/agt/core/core/interface.md → AGT.CORE
   doc/develop/agt/driver/drvdev/interface.md → AGT.DRVDEV
   ```

4. **의존 그래프 구축**:
   ```
   dependencies = {}
   for each module in target_modules:
     refs = parse_references(module.interface_md)
     if refs:
       dependencies[module.id] = [resolve_module_id(ref) for ref in refs]
   ```

**교차 서브시스템 참조 처리:**

subsystem 필터가 적용된 경우, 참조 대상이 필터 밖에 있으면:
- 대상 owner의 src가 이미 구현 완료된 것으로 간주
- 의존성은 "이미 충족"으로 처리 → consumer를 step-01에 배치 가능

## Step 3: 위상 정렬 (Topological Sort)

Kahn's algorithm으로 모듈을 병렬 배치(step)로 그룹화한다.

```
algorithm:
  in_degree = { m: len(dependencies[m]) for m in target_modules }
  step_num = 1
  result_steps = []

  while unprocessed modules exist:
    batch = [m for m in unprocessed if in_degree[m] == 0]
    if batch is empty:
      ERROR: "순환 의존성 감지" → 관련 모듈 목록 출력 후 중단
    result_steps.append((step_num, batch))
    for each m in batch:
      for each dependent of m:
        in_degree[dependent] -= 1
    mark batch as processed
    step_num += 1
```

**결과를 사용자에게 요약 출력:**
```
=== 의존성 분석 결과 ===
Step 01: {N}개 모듈 (독립, 병렬 실행 가능)
  - AGT: CORE, CRYPTO, DRVDEV, ...
  - SVR: API, AUTH, ...

Step 02: {M}개 모듈 (Step 01 완료 후 실행)
  - AGT: TRAY(→CORE), DEVCTL(→DRVDEV), ...
  - SVR: CONSOLE(→API)

건너뛴 모듈: {K}개
```

## Step 4: .temp/ 파일 생성

각 step별로 `.temp/step-{NN}-impl-batch.md` 파일을 생성한다.

**파일명**: `step-{NN}-impl-batch.md` (NN = 01, 02, ...)

**각 파일의 구조:**

```markdown
# Step {NN} — 구현 배치

> 생성 시각: {timestamp}
> 대상 모듈 수: {count}
> 선행 조건: {Step {NN-1} 완료 필요 | 없음 (독립 배치)}

## 공통 입력

- 구현 가이드: `doc/base/implementation-guide.md`
- 검증 가이드: `doc/base/verification-guide.md`
- 모듈 매핑: `doc/architecture/module-mapping.md`
- 플랫폼 참조 (C++/CMake): `doc/base/detailed-designs/cpp.md`
- 플랫폼 참조 (Spring Boot): `doc/base/detailed-designs/springboot.md`
- 코딩 컨벤션: `doc/base/coding-convention/README.md`

## 프로토콜 참조 원칙 (워커 필수 준수)

공유 프로토콜(IPC 메시지, IOCTL 코드, 콜백 시그니처 등)은 주체(Owner) 모듈의 헤더에만 정의된다.
소비자(Consumer) 모듈의 소스 코드에서는 **절대 정의를 복사하지 않고** Owner의 헤더를 `#include`하거나 import한다.

**금지 패턴 (C++):**
```c
// 금지: Consumer 모듈 소스에 Owner의 struct/define 인라인 복사
typedef struct _DLP_IPC_HEADER { ... }  // ← Owner 모듈 헤더에서 복사 금지
#define IPC_MSG_USER_NOTIFICATION 0x0001 // ← Owner 모듈 헤더에서 복사 금지
```

**올바른 패턴 (C++):**
```c
// 올바름: Owner 모듈의 공유 헤더를 include
#include "agt/core/core/include/ipc_protocol.h"
// 이후 IPC_MSG_*, DLP_IPC_HEADER 등을 그대로 사용
```

## 모듈 목록

### {N}. {MODULE_ID} — {모듈 설명}

- **역할**: 주체(Owner) | 소비자(Consumer) | 혼합(Mixed)
- **doc 경로**: `{doc_path}/`
- **implementation.md**: `{doc_path}/implementation.md`
- **interface.md**: `{doc_path}/interface.md`
- **test.md**: `{doc_path}/test.md` (존재 여부: 있음 | 없음)
- **src 경로**: `{src_path}/`
- **플랫폼**: cpp | springboot
- **플랫폼 참조**: `doc/base/detailed-designs/{cpp|springboot}.md`
- **참조 인터페이스** (소비자인 경우):
  - → {OWNER_MODULE} 공유 헤더: `{src_path}/include/{header}.h`
  - → {OWNER_MODULE} interface.md: `{owner_interface_path}`

---
(다음 모듈 반복)
```

**플랫폼 선택 규칙:**
- 모듈이 `doc/develop/agt/` 하위 → `doc/base/detailed-designs/cpp.md`
- 모듈이 `doc/develop/svr/` 하위 → `doc/base/detailed-designs/springboot.md`

## Step 5: 실행 계획 요약

.temp/ 파일 생성 후, 실행 계획을 요약 출력한다.

```
=== parallel-impl 실행 계획 ===

Step 01: {N}개 모듈 (독립, 병렬 실행)
Step 02: {M}개 모듈 (Step 01 완료 후 실행)

건너뛴 모듈: {K}개 (src/ 내 소스 파일 이미 존재)

각 모듈 작업 내용:
  1. 소스 코드 구현 (implementation.md 설계 기반)
  2. 빌드 검증
  3. 정적 분석
  4. 단위 테스트 실행 (test.md 기반)

.temp/ 생성 파일:
  - .temp/step-01-impl-batch.md
  - .temp/step-02-impl-batch.md
```

**조건부 승인:**
- 건너뛴 모듈이 **0개** → 요약 출력 후 자동으로 Step 6 진행
- 건너뛴 모듈이 **1개 이상** → skip 목록 + 사유를 표시하고 AskUserQuestion으로 진행 여부 확인

`--dry-run` 인 경우 "실행하지 않음 (dry-run 모드)" 출력 후 종료한다.
`--skip-verify` 인 경우 요약에 "Phase A 검증 생략" 표시.

## Step 6: Phase 0 — 공통 상수 헤더 생성

모듈별 워커가 병렬로 구현을 시작하기 **전에**, 공유 상수 헤더를 먼저 생성한다. 이 단계가 없으면 각 워커가 상수를 자체 정의하여 중복·불일치가 발생한다.

### 6.1 상수 수집

Step 2에서 파싱한 각 모듈의 implementation.md를 Read하여 "상수 식별" 절(detailed-design-guide.md 2.14절)의 테이블을 수집한다.

```
constants = { "shared": [], "common": [] }

for each module in all_modules:  # skip된 모듈 포함 (이미 구현된 모듈도 상수는 필요)
  impl_md = read("{doc_path}/implementation.md")
  owned = parse_owned_constants(impl_md)  # "이 모듈이 소유하는 상수" 테이블
  for const in owned:
    constants[const.classification].append({
      name: const.name,
      value: const.value,
      owner: module.id,
      consumers: const.consumer_modules
    })
```

**implementation.md에 "상수 식별" 절이 없는 경우:**
- 경고 출력: `"WARN: {MODULE_ID}의 implementation.md에 상수 식별 절 없음 — 하드코딩 위험"`
- 해당 모듈은 상수 헤더 생성에서 제외 (워커가 자체 판단하게 됨)
- 전체 모듈 중 50% 이상 누락 시 AskUserQuestion으로 계속 진행 여부 확인

### 6.2 중복·충돌 검증

```
for each classification in ["shared", "common"]:
  names = [c.name for c in constants[classification]]
  duplicates = find_duplicates(names)
  if duplicates:
    ERROR: "상수 이름 충돌: {duplicates} — 소유 모듈을 확인하세요"
    → AskUserQuestion으로 해결 방법 확인 후 진행
```

### 6.3 헤더 파일 생성

**shared 헤더** (`src/shared/include/dlp_product_names.h`):

```c
// Auto-generated by parallel-impl Phase 0
// DO NOT EDIT — 수정 시 doc/develop/*/implementation.md의 "상수 식별" 절을 변경 후 재생성
#pragma once

// === {OWNER_MODULE} 소유 ===
#define {CONST_NAME}    {CONST_VALUE}
// ... (소유 모듈별로 그룹화)
```

**common 헤더** (`src/common/include/dlp_service_constants.h`):

```c
// Auto-generated by parallel-impl Phase 0
// DO NOT EDIT — 수정 시 doc/develop/*/implementation.md의 "상수 식별" 절을 변경 후 재생성
#pragma once

#include "dlp_product_names.h"  // shared 상수 재활용 (shared 상수가 있는 경우)

// === {OWNER_MODULE} 소유 ===
#define {CONST_NAME}    {CONST_VALUE}
// ...
```

**생성 규칙:**
- shared 헤더는 `#define`과 `typedef`만 사용 (커널 호환)
- common 헤더는 shared 헤더를 `#include`하여 유저모드에서 단일 include로 모든 상수 접근 가능
- 소유 모듈별로 `// === {MODULE_ID} 소유 ===` 주석 구분
- `src/shared/include/`, `src/common/include/` 디렉토리가 없으면 자동 생성

### 6.4 빌드 검증

생성된 헤더의 문법 오류를 확인한다:

```
# 헤더만 컴파일 테스트 (C/C++ 모드)
cl /c /W4 /WX /Zs src/shared/include/dlp_product_names.h
cl /c /W4 /WX /Zs src/common/include/dlp_service_constants.h
```

실패 시 에러 출력 후 AskUserQuestion으로 에스컬레이션.

### 6.5 요약 출력

```
=== Phase 0: 공통 상수 헤더 생성 완료 ===

shared 상수: {N}개 (src/shared/include/dlp_product_names.h)
common 상수: {M}개 (src/common/include/dlp_service_constants.h)
소유 모듈: {K}개
상수 식별 절 누락 모듈: {L}개

빌드 검증: 성공 | 실패
```

## Step 7: 배치 실행

각 step을 순차적으로 실행한다. 동일 step 내 모듈들은 `/team N:deep-executor`로 병렬 실행한다.

### 7.1 워커 프롬프트 구성

각 deep-executor 워커에게 전달할 프롬프트를 다음 형식으로 구성한다:

```
다음 모듈의 소스 코드를 구현하고 Phase A 검증을 수행하라.

## 입력 문서

1. 구현 가이드 (필수 읽기): `doc/base/implementation-guide.md`
2. 검증 가이드 (Phase A 섹션 읽기): `doc/base/verification-guide.md`
3. 플랫폼 참조 (필수 읽기): `doc/base/detailed-designs/{cpp|springboot}.md`
4. 코딩 컨벤션 (존재 시 필수 읽기): `doc/base/coding-convention/README.md`
5. 설계서: `{doc_path}/implementation.md`
6. 인터페이스: `{doc_path}/interface.md`
7. 테스트 케이스: `{doc_path}/test.md`  (없으면 생략)
{소비자인 경우 추가:}
8. 참조 인터페이스 (주체 모듈): `{owner_interface_path}`
   → 주체 모듈 공유 헤더 경로: `{owner_src_path}/include/`

## 작업 범위

### Phase 1: 소스 코드 구현

implementation-guide.md의 모든 원칙을 준수하여 소스 코드를 작성한다:

- **라이브러리 기반 개발**: 핵심 로직은 `library/` 하위에 구현, `module/` 또는 `entry/` 에서 래핑
- **로깅 필수**: 모든 에러 경로에 로그 출력 (implementation-guide.md의 로깅 규칙 준수)
- **공통 코드 분리**: 2개 이상 모듈에서 사용하는 코드는 공통 라이브러리로 분리
- **API 래핑**: 외부 API는 직접 호출하지 않고 래퍼 레이어를 통해 호출
- **Mock 금지**: 실제 환경 기반 구현을 원칙으로 함. Mock 사용 시 반드시 주석으로 사유 명시
- **상수 하드코딩 금지**: 제품 식별 상수(서비스명, DLL명, 파이프명 등)는 cpp/c 파일에 직접 쓰지 않고, Phase 0에서 생성된 공유 헤더를 `#include`하여 사용한다
  - 커널+유저 공유: `src/shared/include/dlp_product_names.h`
  - 유저모드 전용: `src/common/include/dlp_service_constants.h`
  - 설정 값(서버 URL, 간격, 경로 등)은 설정 파일에서 런타임 로드
- **반환값 검증 필수**: 모든 API/시스템 호출(CreateFile, WriteFile, RegOpenKeyEx 등)의 반환값을 검증한다. 반환값을 의도적으로 무시하는 경우 `(void)` 캐스트 + 사유 주석을 명시한다
- **핸들/리소스 해제**: CreateEvent, CreateFile, CreateMutex 등으로 생성한 핸들은 모든 경로(정상+에러+조기 반환)에서 CloseHandle로 해제한다. RAII 래퍼(unique_handle 등) 사용을 권장한다
- **잠금 보호 데이터 접근**: 락으로 보호되는 자료구조에서 획득한 포인터는 락 보유 중에만 역참조한다. 락 해제 후 사용이 필요하면 락 보유 중에 로컬 변수로 deep copy한 후 락을 해제한다

src 경로: `{src_path}/`
플랫폼: {cpp | springboot}

### Phase 2: Phase A 검증 (--skip-verify 미지정 시)

구현 완료 후 verification-guide.md 섹션 1-4를 기준으로 검증 수행:

1. **빌드 검증**: `tools/build.ps1 -Module {MODULE_ID}` 실행 → 컴파일 에러 0건 확인
   - Linux/macOS: `tools/build.sh --module {MODULE_ID}`
   - tools/build.ps1이 없으면 플랫폼별 직접 빌드 (fallback)
2. **정적 분석**: 도구 실행 + 아래 패턴을 코드 리뷰로 추가 확인
   - 반환값을 변수에 저장했으나 if/switch로 검증하지 않는 코드
   - 에러 경로(if FAILED, catch 등)에서 로그 출력 없이 반환하는 코드
   - 핸들 생성 후 조기 return/break 경로에서 CloseHandle 누락
   - 잠금 해제 후 잠금 내에서 획득한 포인터를 역참조하는 코드
3. **단위 테스트**: test.md의 테스트 케이스 기반 단위 테스트 실행 (test.md가 있는 경우)
4. **커버리지 확인**: 핵심 경로 커버리지 기준 충족 여부 확인

## 프로토콜 참조 원칙 (필수 준수)

이 모듈이 소비자(Consumer)인 경우:
- 주체 모듈의 헤더를 `#include`하거나 import하여 사용할 것
- 주체 모듈의 struct, define, enum, 메시지 코드를 소스에 인라인 복사 금지
- 단일 원천 원칙(Single Source of Truth): 정의는 주체 모듈에만 존재해야 한다

## 결과 보고

워커는 작업 완료 후 반드시 결과 파일을 `.temp/impl-results/{MODULE_ID}.result.md`에 생성한다.
(예: AGT.CORE → `.temp/impl-results/AGT.CORE.result.md`)
`.temp/impl-results/` 디렉토리가 없으면 먼저 생성한다.

파일 형식:
```markdown
---
module: {MODULE_ID}
status: SUCCESS | PARTIAL | FAILED
build: PASS | FAIL
test: {통과}/{전체} PASS | SKIP
static_analysis: {N} warnings
timestamp: {ISO 8601}
---

## 빌드 결과
(빌드 로그 요약 — 성공 시 1줄, 실패 시 에러 메시지 전문)

## 테스트 결과
(테스트 실행 결과 요약)

## 정적 분석
(경고 목록)

## 실패 사유 (실패 시만)
(구체적 실패 원인 + 관련 파일/라인)
```

추가로 콘솔에도 다음 항목을 보고한다:
- 구현 완료 파일 목록 (경로 포함)
- 빌드 결과: 성공 | 실패 (에러 메시지 포함)
- 정적 분석 경고 수 및 주요 항목
- 단위 테스트: {통과}/{전체} 케이스
- 실패 항목이 있으면 원인 요약
```

### 7.2 실행 순서

```
for step_num, modules in result_steps:
  worker_count = min(len(modules), args.workers or len(modules), 20)

  # /team 호출
  # 각 모듈별 워커 프롬프트를 구성하여 /team {worker_count}:deep-executor 에 전달
  invoke "/team {worker_count}:deep-executor" with:
    각 워커에게 모듈별 프롬프트 할당

  # 완료 대기 및 결과 검증 (Result File Parsing)
  for each module in modules:
    result_file = ".temp/impl-results/{MODULE_ID}.result.md"
    if not exists(result_file):
      module.status = "NO_REPORT"  # 워커가 결과 파일을 생성하지 않음
      module.build = "UNKNOWN"
      module.test = "UNKNOWN"
      module.static_analysis = "UNKNOWN"
      add to failed list with reason "워커 결과 파일 미생성"
    else:
      parse frontmatter → extract status, build, test, static_analysis
      module.status = parsed.status
      module.build = parsed.build
      module.test = parsed.test
      module.static_analysis = parsed.static_analysis
      if module.status in ["FAILED", "PARTIAL"]:
        add to failed list with reason from "## 실패 사유" section

    # src 파일 존재도 추가 검증
    verify src files exist in {src_path}/
    if missing and module.status != "FAILED":
      module.status = "NO_SRC"
      add to failed list with reason "src 파일 미생성"

  # Step 요약 파일 생성
  Write ".temp/impl-results/step-{NN}-summary.md":
    ```markdown
    # Step {step_num} 실행 결과

    > 실행 시각: {timestamp}
    > 대상 모듈: {total}개

    | 모듈 | 상태 | 빌드 | 테스트 | 정적분석 | 비고 |
    |------|------|------|--------|---------|------|
    | {MODULE_ID} | {status} | {build} | {test} | {static_analysis} | {failure_reason or ""} |
    ...

    성공: {success_count}/{total}, 실패: {failed_count}/{total}
    ```

  # 실패 확인
  if failed_count > 0:
    AskUserQuestion: "Step {step_num}에서 {failed_count}건 실패. 실패 목록 + 사유를 표시. 다음 step 진행?"

  # 다음 step으로 진행
```

### 7.3 결과 보고

모든 Step 완료 후 `.temp/impl-results/execution-report.md`를 생성한다:

```markdown
# parallel-impl 실행 보고서

## 실행 개요
- 실행 일시: {timestamp}
- 총 모듈: {total}개 ({success} 성공 / {failed} 실패 / {skipped} 건너뜀)
- 총 Step: {step_count}개

## Step별 결과

| Step | 성공 | 실패 | 상세 |
|------|------|------|------|
| Step 01 | {success}/{total} | {failed} | [step-01-summary.md](step-01-summary.md) |
| Step 02 | {success}/{total} | {failed} | [step-02-summary.md](step-02-summary.md) |

## Phase A 검증 집계
- 빌드: {build_pass}/{build_total} 성공
- 테스트: {test_pass}/{test_total} 통과
- 정적 분석 경고: {warn_total}건

## 실패 모듈 상세

| 모듈 | 상태 | 실패 사유 | 의존 영향 |
|------|------|----------|-----------|
| {MODULE_ID} | {status} | {failure_reason} | {이 모듈에 의존하는 모듈 목록} |

## full-verify 전달 사항
(Step 8에서 추가 확인이 필요한 항목 — PARTIAL 모듈, 높은 경고 수 모듈 등)
```

생성 후 콘솔에도 요약을 출력한다:

```
=== parallel-impl 완료 ===

Step 01: {success}/{total} 구현 완료
Step 02: {success}/{total} 구현 완료

구현 완료 모듈: {total_success}개
실패: {total_failed}개
건너뛴 모듈: {total_skipped}개

Phase A 검증 요약:
  빌드 성공: {build_success}개 / {build_total}개
  단위 테스트: {test_pass}개 통과 / {test_total}개 실행
  정적 분석 경고: {warn_count}건

{실패 목록이 있으면:}
실패 모듈:
  - {MODULE_ID}: {실패 사유} (빌드 실패 | 테스트 실패 | 구현 미완)

{정적 분석 경고가 있으면:}
정적 분석 경고 주요 항목:
  - {MODULE_ID}: {경고 내용} ({건수}건)

상세 보고서: .temp/impl-results/execution-report.md
```

</Steps>

<Escalation_And_Stop_Conditions>
- **순환 의존성 감지**: 관련 모듈 목록 출력 후 즉시 중단
- **implementation.md/interface.md 누락**: 해당 모듈만 skip + 경고 (나머지 계속 진행)
- **module-mapping.md 누락**: 즉시 중단 (src 경로 해석 불가)
- **implementation-guide.md 누락**: 즉시 중단 (구현 원칙 없이 진행 불가)
- **빌드 환경 미준비**: 빌드 스크립트 실행 실패 시 워커가 보고 → 사용자에게 에스컬레이션
- **step 내 1건 이상 실패**: 실패 목록 + 사유를 표시하고 다음 step 진행 여부 사용자 확인
- **NO_REPORT (워커 결과 파일 미생성)**: 워커가 `.temp/impl-results/{MODULE_ID}.result.md`를 생성하지 않은 경우 — 해당 모듈을 FAILED(NO_REPORT)로 기록하고, step-summary에 "워커 결과 파일 미생성" 사유를 명시. src 파일 존재 여부를 추가 확인하여 실제 구현은 완료되었으나 보고만 누락된 경우(PARTIAL)와 구현 자체가 실패한 경우(FAILED)를 구분한다
- **사용자 "중단" 요청**: 현재 step 완료 후 중단 (진행 중인 워커는 완료까지 대기)
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
전체 모듈 병렬 구현 (skip 없음 → 자동 진행):
```
사용자: /parallel-impl
스킬: 24개 모듈 탐색 완료. 6개 의존성 발견.
      Step 01: 18개 모듈 (독립), Step 02: 6개 모듈 (소비자)
      건너뛴 모듈: 0개
      .temp/step-01-impl-batch.md, step-02-impl-batch.md 생성 완료.
      자동 진행합니다.
      Step 01 실행 중... /team 18:deep-executor
      → 18/18 구현 완료, 빌드 18/18 성공, 테스트 142/145 통과
      Step 02 실행 중... /team 6:deep-executor
      → 6/6 구현 완료, 빌드 6/6 성공, 테스트 38/38 통과
      총 24개 모듈 구현 완료. 정적 분석 경고 3건.
```
</Good>

<Good>
AGT만 선택, 워커 수 제한 (skip 없음 → 자동 진행):
```
사용자: /parallel-impl agt --workers 5
스킬: AGT 14개 모듈 탐색 완료. 5개 의존성 발견.
      Step 01: 9개 모듈 (워커 5개로 제한), Step 02: 5개 모듈 (워커 5개)
      건너뛴 모듈: 0개
      .temp/ 파일 생성 완료. 자동 진행합니다.
```
</Good>

<Good>
dry-run으로 계획만 확인:
```
사용자: /parallel-impl --dry-run
스킬: .temp/ 파일 생성 완료. (실행하지 않음)
      .temp/step-01-impl-batch.md (18개 모듈)
      .temp/step-02-impl-batch.md (6개 모듈)
```
</Good>

<Good>
일부 모듈이 이미 구현된 경우 (skip 있음 → 승인 요청):
```
사용자: /parallel-impl agt
스킬: AGT 14개 모듈 탐색. 3개 이미 구현 완료 (CORE: src/*.cpp 존재, DRVDEV, CLIP).
      대상: 11개 모듈. 의존성 재분석...
      Step 01: 6개 모듈, Step 02: 5개 모듈

      건너뛴 모듈: 3개
        - AGT.CORE: src/*.cpp 이미 존재
        - AGT.DRVDEV: src/*.cpp 이미 존재
        - AGT.CLIP: src/*.cpp 이미 존재

      진행하시겠습니까?
사용자: 진행
```
</Good>

<Good>
검증 생략 모드 (skip 없음 → 자동 진행):
```
사용자: /parallel-impl --skip-verify
스킬: 24개 모듈 탐색 완료. Phase A 검증 생략 모드.
      Step 01: 18개 모듈, Step 02: 6개 모듈
      건너뛴 모듈: 0개
      자동 진행합니다. (빌드/테스트 미실행)
```
</Good>

<Bad>
의존성을 무시하고 모든 모듈을 한 배치에서 실행:
```
/team 24:deep-executor  # ← TRAY가 CORE보다 먼저 실행될 수 있음 → 헤더 참조 실패
```
이유: 소비자 모듈은 주체 모듈의 헤더가 src/에 존재한 후 컴파일해야 한다.
</Bad>

<Bad>
워커 프롬프트에 프로토콜 참조 원칙을 빠뜨림:
```c
// 워커가 CORE의 IPC struct를 TRAY 소스 코드에 인라인 복사
typedef struct _DLP_IPC_HEADER { ... }  // ← Owner 헤더에서 복사, 단일 원천 원칙 위반
```
이유: 주체 모듈 헤더가 변경될 때 복사본이 자동으로 갱신되지 않아 불일치가 발생한다.
</Bad>

<Bad>
Phase A 검증 없이 완료 보고:
```
스킬: 24개 구현 완료.  # ← 빌드/테스트 실행 결과 없이 완료 선언
```
이유: 구현 직후 검증이 이 스킬의 핵심 가치이다. 검증 결과를 반드시 보고해야 한다.
</Bad>

</Examples>

<Tool_Usage>
- **Glob 도구**: `doc/develop/**/implementation.md` 탐색으로 모듈 목록 구축, src/ 내 소스 파일 존재 확인
- **Read 도구**: implementation.md, interface.md, module-mapping.md 파싱 (소유권, 참조 경로, src 경로 추출)
- **Bash 도구**: `.temp/` 디렉토리 생성 (`mkdir -p`), 빌드 스크립트 실행, 정적 분석 도구 실행
- **Write 도구**: `.temp/step-{NN}-impl-batch.md` 생성
- **AskUserQuestion**: skip 발생 시 진행 확인, 실패 발생 시 계속 진행 여부
- **Skill 도구**: `/team N:deep-executor` 호출로 배치 내 병렬 실행
- **Grep 도구**: 생성된 소스 파일에서 프로토콜 인라인 복사 여부 검증 (패턴: `typedef struct _DLP_IPC`)
</Tool_Usage>

<Final_Checklist>
- [ ] `doc/base/implementation-guide.md` 존재를 확인했는가?
- [ ] `doc/architecture/module-mapping.md` 존재를 확인했는가?
- [ ] 모든 대상 모듈의 implementation.md와 interface.md 존재를 검증했는가?
- [ ] module-mapping.md에서 각 모듈의 src 경로와 플랫폼 정보를 추출했는가?
- [ ] Skip 판정에서 src/ 내 실제 소스 파일 존재 여부를 Glob으로 확인했는가?
- [ ] 의존성 그래프에서 순환 참조가 없는지 확인했는가?
- [ ] 위상 정렬 결과가 올바른가? (owner → consumer 순서 보장)
- [ ] `.temp/step-{NN}-impl-batch.md`에 프로토콜 참조 원칙이 포함되었는가?
- [ ] 워커 프롬프트에 implementation-guide.md, verification-guide.md, 플랫폼 참조, src 경로가 모두 포함되었는가?
- [ ] 소비자 모듈의 워커 프롬프트에 주체 모듈 헤더 경로가 포함되었는가?
- [ ] 워커 프롬프트에 Phase A 검증 지시(빌드 + 정적 분석 + 단위 테스트)가 포함되었는가?
- [ ] `--skip-verify` 시 Phase A 검증 생략이 워커 프롬프트에 반영되었는가?
- [ ] `--dry-run` 시 실행 없이 .temp/ 파일만 생성하고 종료하는가?
- [ ] Phase 0에서 공통 상수 헤더가 생성되었는가? (Step 6)
- [ ] implementation.md에 "상수 식별" 절이 없는 모듈에 대해 경고가 출력되었는가?
- [ ] 워커 프롬프트에 공유 헤더 경로(shared/, common/)와 하드코딩 금지 지시가 포함되었는가?
- [ ] step 간 순차 실행이 보장되는가? (step 01 완료 후 step 02 실행)
- [ ] 결과 보고에 빌드 성공/실패, 테스트 통과/전체, 정적 분석 경고 수가 집계되었는가?
- [ ] 결과 보고에 성공/실패/skip 수가 정확히 집계되었는가?
- [ ] 워커 프롬프트에 `.temp/impl-results/{MODULE_ID}.result.md` 생성 지시가 포함되었는가?
- [ ] 각 Step 완료 후 `.temp/impl-results/step-{NN}-summary.md`가 생성되었는가?
- [ ] 모든 Step 완료 후 `.temp/impl-results/execution-report.md`가 생성되었는가?
- [ ] NO_REPORT(워커 결과 파일 미생성) 상태가 올바르게 FAILED로 기록되었는가?
</Final_Checklist>
