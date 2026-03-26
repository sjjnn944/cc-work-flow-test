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
| --workers N | (배치 내 모듈 수, 최대 8) | 배치당 병렬 워커 수 제한 (최대 8개 — rate limit 방지) |
| --skip-verify | false | Phase A 검증(빌드 + 정적 분석 + 단위 테스트) 생략 |
| --max-retries N | 3 | Phase 2 빌드/테스트 실패 시 자동 수정 재시도 최대 횟수 |
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
- `test.md` — 없으면 경고 출력 (해당 모듈 Phase 2-C SKIP. 테스트 코드 작성 의무 없음)

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

**빌드 파일 의존성 보조 감지:**

interface.md 기반 의존성 분석 이후, 빌드 파일에서 추가 의존성을 추출하여 그래프에 병합한다.

```
for each module in target_modules:
  if module.platform == "springboot":
    build_file = "{src_path}/build.gradle.kts"
    if exists(build_file):
      content = read(build_file)
      # implementation(project(":모듈명")) 패턴 파싱
      build_deps = regex_findall(r'implementation\(project\(":(\w+)"\)\)', content)
      for dep in build_deps:
        dep_id = resolve_module_id(dep)
        if dep_id and dep_id not in dependencies[module.id]:
          WARN: "{module.id}: 빌드 파일에 의존성 {dep_id} 발견 (interface.md에 없음)"
          dependencies[module.id].append(dep_id)

  elif module.platform == "cpp":
    cmake_file = "{src_path}/CMakeLists.txt"
    if exists(cmake_file):
      content = read(cmake_file)
      # target_link_libraries(... 모듈명) 패턴 파싱
      build_deps = regex_findall(r'target_link_libraries\([^)]*\b(\w+)\b', content)
      for dep in build_deps:
        dep_id = resolve_module_id(dep)
        if dep_id and dep_id not in dependencies[module.id]:
          WARN: "{module.id}: 빌드 파일에 의존성 {dep_id} 발견 (interface.md에 없음)"
          dependencies[module.id].append(dep_id)
```

interface.md에 없지만 빌드 파일에 있는 의존성은 경고를 출력하고 의존성 그래프에 추가한다. 이를 통해 실제 빌드 의존 모듈이 같은 Step에 배치되는 것을 방지한다.

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
7. 테스트 케이스: `{doc_path}/test.md`  (필수 — 단위 테스트 코드 작성 기준. 없으면 Phase 2-C SKIP)
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

## 파일 소유권 원칙

이 워커는 자기 모듈의 src 경로(`{src_path}/`)에만 파일을 생성/수정한다. 다른 모듈의 소스 파일을 절대 수정하지 않는다.

## 인터페이스 갭 보고 원칙

의존 모듈의 인터페이스가 부족하여 구현이 불가능한 경우:

1. 의존 모듈의 소스를 수정하지 **않는다**
2. 빌드가 실패하더라도 **첫 번째 갭에서 멈추지 않는다** — 소스 코드 전체를 작성 완료한 후, 모든 인터페이스 갭을 식별한다
3. result.md에 `## 인터페이스 갭` 절을 추가하여 다음 정보를 **갭별로** 기록한다:

| # | 의존 모듈 | 필요 인터페이스 | 필요 기능 설명 | 호출 위치 (파일:라인) | 빌드 영향 |
|---|----------|---------------|--------------|---------------------|----------|
| 1 | {DEP_MODULE} | {메서드/함수 시그니처 (파라미터 타입, 반환 타입 포함)} | {왜 이 인터페이스가 필요한지 — 비즈니스 로직 관점} | {파일:라인} | {컴파일 에러 / 링크 에러 / 런타임 에러} |

4. 각 갭에 대해:
   - **필요 인터페이스**: 메서드/함수 시그니처 (파라미터 타입, 반환 타입 포함)
   - **필요 기능 설명**: 왜 이 인터페이스가 필요한지 (비즈니스 로직 관점)
   - **호출 위치**: 이 모듈의 어떤 파일, 어떤 라인에서 호출하는지
   - **빌드 영향**: 이 갭으로 인해 발생하는 에러 유형 (컴파일/링크/런타임)
5. 빌드 결과는 `build: FAIL (INTERFACE_GAP)` 으로 기록 — 일반 FAIL과 구분

### Phase 2-A: 빌드 검증 재시도 루프 (--skip-verify 미지정 시)

구현 완료 후 verification-guide.md 섹션 1-4를 기준으로 검증 수행한다.

```
build_attempt = 1

while build_attempt <= max_retries + 1:
  1. `python tools/build.py --module {MODULE_ID}` 실행
     - 빌드 도구 미설치/build.py 미존재 → FAIL (재시도 불가, 즉시 탈출)

  2. 성공 → build: PASS, break

  3. 실패 (컴파일 에러):
     if build_attempt > max_retries → build: FAIL, break
     if 이전 시도와 동일 에러 → build: FAIL, break (동일 에러 반복 방지)

     a. 에러 메시지에서 파일명, 라인, 에러 코드 추출
     b. 에러 유형별 수정:
        - include 경로 오류 → 경로 수정
        - 미선언 심볼 → 선언 추가 / 타입 수정
        - 링크 에러 → 누락 함수 구현
        - 기타 → implementation.md 참조하여 수정
     c. 수정 내용 기록
     build_attempt += 1
```

**재시도 불가 조건 (즉시 FAIL):**
- 빌드 도구 미설치 / build.py 미존재
- 동일 에러 2회 연속 반복 (수정 무효)

### Phase 2-B: 정적 분석

도구 실행 + 아래 패턴을 코드 리뷰로 추가 확인 (재시도 대상 아님):
- 반환값을 변수에 저장했으나 if/switch로 검증하지 않는 코드
- 에러 경로(if FAILED, catch 등)에서 로그 출력 없이 반환하는 코드
- 핸들 생성 후 조기 return/break 경로에서 CloseHandle 누락
- 잠금 해제 후 잠금 내에서 획득한 포인터를 역참조하는 코드

### Phase 2-C: 단위 테스트 작성 및 실행 재시도 루프

```
test_attempt = 1

while test_attempt <= max_retries + 1:
  1. test.md 없으면 → test: SKIP (재시도 없음)

  2. test.md의 TC를 구현하는 테스트 코드를 작성한다:
     - test.md의 TC ID, 입력, 기대 결과를 기반으로 테스트 코드 파일 생성
     - 테스트 코드 경로: module-mapping.md의 test_path 또는 test/ 하위
     - 환경 제약으로 실행 불가한 TC는 코드는 작성하되, SKIP 마킹하고 사유를 기록
       (예: // SKIP: VM 배포 필요 — fltmc load DlpMinifilter 환경에서 실행)

  3. 테스트 빌드 + 실행
     - 실행 가능한 TC만 실행, 환경 제약 TC는 빌드 검증만

  4. 전체 통과 → test: PASS, break
     환경 제약으로 실행 불가 → test: SKIP (사유 + 실행 불가 TC 목록 기록)
     실행 가능 TC 중 실패 → 아래 재시도 로직 적용

  5. 실패 재시도:
     if test_attempt > max_retries → test: FAIL, break
     if 이전 시도와 동일 실패 TC → test: FAIL, break

     a. 실패 TC의 에러 메시지/스택 추출
     b. 구현 로직 오류 → 소스 수정 (implementation.md 참조)
        테스트 환경 문제 → FAIL (재시도 불가, 즉시 탈출)
     c. 코드 수정했으므로 빌드 재실행 → 빌드 실패 시 test: FAIL
     d. 수정 내용 기록
     test_attempt += 1
```

**재시도 불가 조건 (즉시 FAIL):**
- 테스트 프레임워크 미설치
- 동일 실패 TC 2회 연속 반복 (수정 무효)

4. **커버리지 확인**: 핵심 경로 커버리지 기준 충족 여부 확인

**빌드 검증 필수 원칙:**
- 빌드 도구 실행이 실패하면 반드시 build: FAIL로 보고한다
- 코드 리뷰, 문법 검토, 수동 검사 등으로 빌드 검증을 대체할 수 없다
- "빌드 환경 미설치"는 FAIL 사유이며, PASS나 SKIP이 아니다
- result.md의 build 필드는 실제 컴파일러/빌드 도구 실행 결과만 반영한다

## 프로토콜 참조 원칙 (필수 준수)

이 모듈이 소비자(Consumer)인 경우:
- 주체 모듈의 헤더를 `#include`하거나 import하여 사용할 것
- 주체 모듈의 struct, define, enum, 메시지 코드를 소스에 인라인 복사 금지
- 단일 원천 원칙(Single Source of Truth): 정의는 주체 모듈에만 존재해야 한다

## 결과 보고

워커는 작업 완료 후 반드시 결과 파일을 `.temp/impl-results/{MODULE_ID}.result.md`에 생성한다.
(예: AGT.CORE → `.temp/impl-results/AGT.CORE.result.md`)
`.temp/impl-results/` 디렉토리가 없으면 먼저 생성한다.

**result.md 시작은 반드시 다음 YAML frontmatter로 시작한다 (누락 시 검증 실패):**

파일 형식:
```markdown
---
module: {MODULE_ID}
status: SUCCESS | PARTIAL | FAILED
build: PASS | FAIL | FAIL (INTERFACE_GAP)
build_attempts: {N}
interface_gaps: {0 | N}
interface_gap_targets: [{의존 모듈 ID 목록}]
test: {통과}/{전체} PASS | SKIP | NOT_IMPL
test_attempts: {N}
static_analysis: {N} warnings
timestamp: {ISO 8601}
---

## 빌드 결과
(빌드 로그 요약 — 성공 시 1줄, 실패 시 에러 메시지 전문)

## 테스트 결과
(테스트 실행 결과 요약)

## 정적 분석
(경고 목록)

## 재시도 이력 (재시도 발생 시만)

### 빌드 재시도
| 시도 | 에러 요약 | 수정 내용 | 결과 |
|------|----------|----------|------|
| 1 | {에러 1줄} | (첫 시도) | FAIL |
| 2 | {에러 1줄} | {파일:라인 수정 요약} | PASS |

### 테스트 재시도
| 시도 | 실패 TC | 수정 내용 | 결과 |
|------|--------|----------|------|
| 1 | {TC명} | (첫 시도) | FAIL |
| 2 | {TC명} | {파일:라인 수정 요약} | PASS |

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
  worker_count = min(len(modules), args.workers or len(modules), 8)  # 최대 8개 (rate limit 방지)

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
      parse frontmatter → extract status, build, build_attempts, test, test_attempts, static_analysis
      module.status = parsed.status
      module.build = parsed.build
      module.build_attempts = parsed.build_attempts or 1
      module.test = parsed.test
      module.test_attempts = parsed.test_attempts or 1
      module.static_analysis = parsed.static_analysis
      if module.test == "SKIP":
        module.skip_reason = extract from "Phase 2-C" or "Unit Test" section of result.md
        # 환경 제약 SKIP vs 미구현 SKIP 교차 검증
        if test.md exists for this module:
          if module.skip_reason is empty or contains "별도 작업":
            module.test = "NOT_IMPL"  # 미구현으로 재분류
            add to failed list with reason "test.md 존재하나 테스트 코드 미작성 (Phase 2-C 미수행)"
      if module.build contains "리뷰" or "review":
        module.build = "FAIL"
        add to failed list with reason "빌드 검증이 코드 리뷰로 대체됨 — 실제 빌드 필요"
      if module.status in ["FAILED", "PARTIAL"]:
        add to failed list with reason from "## 실패 사유" section

    # src 파일 존재도 추가 검증
    verify src files exist in {src_path}/
    if missing and module.status != "FAILED":
      module.status = "NO_SRC"
      add to failed list with reason "src 파일 미생성"

  # Post-step 통합 빌드 검증
  # 각 워커의 개별 빌드가 완료된 후, Step 전체 모듈의 통합 빌드를 실행한다.
  # 이를 통해 워커 재시도 중 파일 덮어쓰기로 인한 크로스모듈 불일치를 탐지한다.
  integration_failures = []
  for module in modules:
    if module.status == "FAILED":
      continue  # 이미 실패한 모듈은 통합 빌드 대상에서 제외
    result = run "python tools/build.py --module {MODULE_ID}"
    if result.failed:
      integration_failures.append({
        module: module.id,
        error: result.error_message
      })
      # 에러 메시지에서 인터페이스 불일치 여부 확인
      if "unresolved" in result.error or "undefined reference" in result.error:
        module.integration_note = "크로스모듈 인터페이스 불일치 의심"

  if integration_failures:
    WARN: "Step {step_num} 통합 빌드 실패: {[f.module for f in integration_failures]}"
    for f in integration_failures:
      add to failed list with reason "통합 빌드 실패: {f.error} ({f.module.integration_note or ''})"

  # Step 요약 파일 생성
  Write ".temp/impl-results/step-{NN}-summary.md":
    ```markdown
    # Step {step_num} 실행 결과

    > 실행 시각: {timestamp}
    > 대상 모듈: {total}개

    | 모듈 | 상태 | 빌드 | 시도 | 테스트 | 시도 | 정적분석 | 비고 |
    |------|------|------|------|--------|------|---------|------|
    | {MODULE_ID} | {status} | {build} | {build_attempts} | {test} | {test_attempts} | {static_analysis} | {failure_reason or ""} |
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

## 재시도 통계
- 빌드 재시도 발생: {N}/{total}개 모듈
- 테스트 재시도 발생: {M}/{total}개 모듈
- 재시도 후 성공: {K}개 모듈
- 재시도 소진 실패: {module_list}

## 실패 모듈 상세

| 모듈 | 상태 | 실패 사유 | 의존 영향 |
|------|------|----------|-----------|
| {MODULE_ID} | {status} | {failure_reason} | {이 모듈에 의존하는 모듈 목록} |

## 인터페이스 갭 통합

모든 워커의 result.md에서 `## 인터페이스 갭` 절과 frontmatter의 `interface_gaps`, `interface_gap_targets` 필드를 수집하여 통합 테이블을 생성한다.

| 제공 모듈 | 부족 인터페이스 | 요청 모듈 | 기능 설명 | 호출 위치 | 빌드 영향 |
|-----------|---------------|-----------|----------|----------|----------|
| {DEP_MODULE} | {필요 인터페이스 시그니처} | {요청 MODULE_ID} | {필요 기능 설명} | {파일:라인} | {에러 유형} |

### 조치 필요 사항

갭이 존재하는 경우, 제공 모듈별로 필요한 조치를 요약한다:
- {제공 모듈}: {부족 인터페이스 목록} 추가 필요
- 추가 후 {요청 모듈} 재빌드로 갭 해소 확인

> 수집 방법: 각 result.md에서 `build: FAIL (INTERFACE_GAP)` 인 모듈의 `## 인터페이스 갭` 테이블을
> 파싱하여, 동일 제공 모듈의 갭을 하나의 그룹으로 병합한다.

## 통합 빌드 검증 결과

각 Step의 post-step 통합 빌드 결과를 집계한다.

| Step | 통합 빌드 | 실패 모듈 | 실패 원인 |
|------|----------|----------|----------|
| Step {NN} | PASS / FAIL | {실패 모듈 목록 또는 "-"} | {크로스모듈 불일치 등} |

## 테스트 SKIP 원인 통합

### 환경 제약 SKIP (정당한 사유)

각 워커의 result.md에서 test: SKIP 사유를 수집하여 공통 원인별로 그룹화한다.

| SKIP 원인 | 해당 모듈 | TC 수 | 해소 조건 |
|-----------|----------|-------|----------|
| {reason_category} | {MODULE_ID, ...} | {total_tc_count} | {환경/조건 설명} |

> 수집 방법: 각 result.md의 "Phase 2-C: 단위 테스트" 절에서 SKIP 사유를 추출하고,
> 동일 사유를 가진 모듈을 하나의 행으로 병합한다.
> TC 수는 test.md에 정의된 전체 TC 수를 기재한다 (실행 불가 TC 포함).

### 미구현 (test.md 존재, 워커 미수행)

Step 7.2에서 NOT_IMPL로 재분류된 모듈을 별도 표시한다.

| 모듈 | TC 수 | 비고 |
|------|-------|------|
| {MODULE_ID} | {tc_count} | test.md 존재 — 재실행 필요 |

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

{테스트 SKIP이 있으면:}
테스트 SKIP 원인 (환경 제약):
  - VM 배포 필요: {MODULE_LIST} ({N}개 TC)
  - 관리자 권한 필요: {MODULE_LIST} ({N}개 TC)
  - 의존 모듈 미배포: {MODULE_LIST} ({N}개 TC)

{인터페이스 갭이 있으면:}
인터페이스 갭:
  - {제공 모듈}: {부족 인터페이스 목록} (요청: {요청 모듈 목록})

{통합 빌드 실패가 있으면:}
통합 빌드 실패:
  - Step {NN}: {실패 모듈 목록} (크로스모듈 인터페이스 불일치)

{테스트 NOT_IMPL이 있으면:}
테스트 미구현 (test.md 존재, 워커 미수행):
  - {MODULE_LIST} — 재실행 필요

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
- **재시도 소진 (RETRY_EXHAUSTED)**: 최대 재시도 후에도 빌드/테스트 실패 — FAILED(RETRY_EXHAUSTED)로 기록. 재시도 이력(각 시도의 에러 + 수정 내용) 전체를 결과 파일에 포함하여 수동 진단 가능하게 한다
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
- [ ] 워커 프롬프트에 빌드/테스트 재시도 루프와 최대 재시도 횟수가 포함되었는가?
- [ ] 동일 에러 반복 시 즉시 탈출하는 가드가 포함되었는가?
- [ ] Phase 2-C에서 test.md 기반 테스트 코드 작성 단계가 실행 전에 수행되는가?
- [ ] Step 7.2에서 test.md 존재 + SKIP인 모듈이 NOT_IMPL로 재분류되는가?
- [ ] execution-report에서 환경 제약 SKIP과 미구현 NOT_IMPL이 별도 테이블로 구분되는가?
- [ ] Step 2에서 빌드 파일(build.gradle.kts, CMakeLists.txt) 의존성 보조 감지가 수행되는가?
- [ ] 빌드 파일에만 존재하는 의존성이 경고 출력 + 그래프 병합되는가?
- [ ] 워커 프롬프트에 파일 소유권 원칙(자기 모듈 src 경로만 수정)이 포함되었는가?
- [ ] 워커 프롬프트에 인터페이스 갭 보고 원칙(갭 테이블 + FAIL(INTERFACE_GAP))이 포함되었는가?
- [ ] result.md frontmatter에 `interface_gaps`, `interface_gap_targets` 필드가 포함되었는가?
- [ ] 각 Step 완료 후 post-step 통합 빌드가 실행되는가?
- [ ] 통합 빌드 실패 시 크로스모듈 인터페이스 불일치 여부가 확인되는가?
- [ ] execution-report에 "인터페이스 갭 통합" 절이 생성되는가?
- [ ] execution-report에 "통합 빌드 검증 결과" 절이 생성되는가?
</Final_Checklist>
