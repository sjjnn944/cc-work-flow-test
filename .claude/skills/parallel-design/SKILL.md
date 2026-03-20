---
name: parallel-design
description: 모듈 의존성 분석 후 병렬 배치로 상세 설계(implementation.md)를 자동 실행하는 스킬. "병렬 설계", "전체 모듈 설계", "implementation.md 일괄 작성", "parallel design", "상세 설계 일괄", "모듈 설계 실행" 등을 요청할 때 사용. doc/develop 폴더에 interface.md와 requirement.md가 준비된 상태에서 implementation.md를 생성하려 할 때 반드시 이 스킬을 사용할 것.
---

<Purpose>
doc/develop/ 내 모듈들을 탐색하고, interface.md의 소유권/참조 관계를 분석하여 의존성 그래프를 구축한 뒤, 위상 정렬(topological sort)로 병렬 실행 가능한 배치(step)를 생성한다. 각 배치를 /team N:deep-executor로 실행하여 implementation.md를 병렬 작성한다.

핵심 가치:
- 의존성 순서 보장: Owner 모듈이 먼저 설계되어야 Consumer 모듈이 참조할 수 있다
- 프로토콜 참조 원칙 강제: 소비자가 주체의 프로토콜 정의를 인라인 복사하는 것을 방지
- 자족적 워커 프롬프트: 각 워커가 독립적으로 작업 가능하도록 모든 입력 경로를 명시
</Purpose>

<Use_When>
- 전체 또는 특정 서브시스템(agt/svr)의 implementation.md를 일괄 작성할 때
- 모듈 간 의존성을 고려한 순서가 필요할 때
- 병렬 에이전트로 설계 처리량을 최대화하고 싶을 때
</Use_When>

<Do_Not_Use_When>
- 단일 모듈의 implementation.md만 작성할 때 (직접 detailed-design-guide.md 참조)
- interface.md나 requirement.md가 아직 작성되지 않았을 때 (먼저 /project-scaffold 사용)
- 기존 implementation.md를 수정/업데이트할 때
</Do_Not_Use_When>

<Arguments>
인수 형식: `/parallel-design [subsystem] [--force] [--dry-run] [--workers N]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt` 또는 `svr` — 특정 서브시스템만 대상 |
| --force | false | 기존 implementation.md가 있어도 재작성 |
| --dry-run | false | .temp/ 파일만 생성하고 실행하지 않음 |
| --workers N | (배치 내 모듈 수) | 배치당 병렬 워커 수 제한 |
| --no-split | false | 대형 모듈 자동 분할 비활성화 |
| --split-threshold N | 15 | FR 기준 분할 임계값 |
</Arguments>

<Steps>

## Step 0: 초기화

1. `doc/base/detailed-design-guide.md` 존재 확인 — 없으면 중단
2. `.temp/` 디렉토리 확인 — 없으면 `mkdir -p .temp`
3. `.temp/step-*.md` 기존 파일이 있으면 자동으로 덮어쓴다 (별도 확인 없이 진행)

## Step 1: 모듈 탐색 (Discovery)

Glob으로 모든 interface.md를 찾아 모듈 목록을 구축한다.

**탐색 범위:**
- subsystem 미지정: `Glob("doc/develop/**/interface.md")`
- `agt` 지정: `Glob("doc/develop/agt/**/interface.md")`
- `svr` 지정: `Glob("doc/develop/svr/**/interface.md")`

**모듈 식별자 추출 규칙:**

경로 패턴별 파싱:
```
doc/develop/{sys}/{category}/{module}/interface.md
  → module_id: {SYS}.{MODULE}  (대문자)
  → 예: doc/develop/agt/core/core/interface.md → AGT.CORE

doc/develop/{sys}/{module}/interface.md  (category 없는 flat 구조)
  → module_id: {SYS}.{MODULE}
  → 예: doc/develop/svr/api/interface.md → SVR.API
        doc/develop/agt/update/interface.md → AGT.UPDATE
```

**Skip 판정:**
각 모듈 디렉토리에 `implementation.md`가 이미 존재하는지 확인.
- 존재하고 `--force`가 아니면 → 파일 내용을 Read하여 scaffold 템플릿 여부를 판별:
  - `상태: 미작성` 또는 `(상세 설계 시 작성)` 문자열이 포함된 경우 → **scaffold 빈 템플릿**으로 간주, skip하지 않고 대상 목록에 추가
  - 그 외 (실질적 내용이 있는 경우) → skip 목록에 추가
- 존재하지 않으면 → 대상 목록에 추가
- `--force`이면 → 무조건 대상 목록에 추가

**필수 파일 검증:**
각 대상 모듈에 `requirement.md`가 존재하는지 확인.
- 없으면 → 경고 출력 후 해당 모듈 skip

## Step 1.5: 모듈 크기 분석 (Large Module Detection)

`--no-split`이 아닌 경우, 각 대상 모듈의 requirement.md와 interface.md를 분석하여 대형 모듈을 감지하고 도메인별 분할 계획을 수립한다.

**감지 기준** (requirement.md + interface.md에서 측정):
- FR 행 수 >= `--split-threshold` (기본 15) → 분할 대상
- FR 행 수 >= 10 AND REST endpoint 수 >= 10 → 분할 대상
- 그 외 → 단일 모듈 유지

**FR 행 수 측정:**
```
Grep 패턴: /^[\s]*FR-\d+/ 또는 /^\|[\s]*FR-\d+/
대상: 각 모듈의 requirement.md
```

**REST endpoint 수 측정:**
```
Grep 패턴: /^\|[\s]*(GET|POST|PUT|DELETE|PATCH)/
대상: 각 모듈의 interface.md
```

**도메인 클러스터링 알고리즘:**

1. requirement.md의 FR 설명에서 키워드 매칭으로 도메인 분류:
   ```
   auth: 인증, 패스워드, 세션, 로그인, MFA, RBAC, 접속, IP 제한
   policy: 정책, 배포
   agent: 에이전트, 등록, 식별
   audit: 감사, 로그, 감사기록, 사고
   security: 암호화, 무결성, 자체시험, 업데이트, 서명, 롤백
   approval: 승인, 반출, 결재
   report: 보고서, 통계
   ```
2. 매칭 안 되는 FR → "core" 도메인에 할당
3. FR 3개 미만인 도메인 → 가장 관련 높은 도메인에 병합
4. 목표: 도메인당 5~12 FR
5. 12 FR 초과 도메인 → 하위 키워드로 재분할

**분할 계획 출력:**
```
=== 대형 모듈 분할 계획 ===
SVR.SVCCORE (31 FR, 18 REST endpoints) → 6개 서브태스크:
  - core (FR-001, FR-025): 부트스트랩 및 수명 주기
  - auth (FR-002~010, FR-026~027): 인증 및 세션 관리
  - policy-agent (FR-011~014, FR-028): 정책 CRUD/배포, 에이전트 관리
  - audit (FR-015~019, FR-029): 감사 로그, 사고 자동생성
  - security (FR-020~024): 암호화, 무결성, 업데이트
  - approval-report (FR-030~031): 승인 워크플로우, 보고서
```

각 모듈 객체에 `split_plan` 속성을 추가:
- 분할 대상 아님 → `split_plan = null`
- 분할 대상 → `split_plan = { subtasks: [{ domain, fr_list, output_path }] }`

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
- 대상 owner의 interface.md는 이미 존재하므로 (scaffold 완료 상태)
- 의존성은 "이미 충족"으로 간주 → consumer를 step-01에 배치 가능

## Step 2.5: 입력 완성도 검증 게이트

Step 2에서 파싱한 각 대상 모듈의 interface.md에 대해 플레이스홀더 잔존 여부를 검사한다.

**검색 패턴:**
```
Grep 패턴: /\*\s*상세\s*설계\s*시\s*(확정|정의)|（미정）|\(미정\)|TBD|TODO.*설계/
대상: 각 모듈의 interface.md
```

**발견 시 처리 절차:**

1. **자동 확정 시도**: 설계서(scratch.md, `doc/architecture/` 내 문서)를 참조하여 플레이스홀더를 구체적 정의로 확정
   - 설계서에 충분한 정보가 있으면 → interface.md에 확정된 정의를 반영
   - 설계서에도 정보가 부족하면 → 2단계로 진행

2. **사용자 결정 요청**: 자동 확정이 불가능한 경우 AskUserQuestion으로 사용자에게 구체적 선택지를 제시
   ```
   {MODULE_ID}의 interface.md에 미확정 플레이스홀더가 있습니다:
   - 위치: line {N}
   - 내용: {플레이스홀더 텍스트}

   제안 선택지:
   1. {선택지 A} (설계서 기반 추천)
   2. {선택지 B}
   3. 직접 입력

   어떤 방식으로 확정하시겠습니까?
   ```

3. **확정 반영**: 사용자 결정에 따라 interface.md를 수정한 후 다음 단계로 진행

**검증 결과 출력:**
```
=== 입력 완성도 검증 ===
✓ AGT.CORE: interface.md 완전
✓ AGT.DRVDEV: interface.md 완전
✗ AGT.FSDRV: interface.md 플레이스홀더 1건 (line 41) → 확정 완료
✗ AGT.NETDRV: interface.md 플레이스홀더 1건 (line 41) → 사용자 확정 대기
```

**중요:** 플레이스홀더가 미확정인 모듈은 implementation.md 작성 대상에서 제외하거나, 확정 후에만 진행한다.

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

각 step별로 `.temp/step-{NN}-design-batch.md` 파일을 생성한다.

**파일명**: `step-{NN}-design-batch.md` (NN = 01, 02, ...)

**각 파일의 구조:**

```markdown
# Step {NN} — 상세 설계 배치

> 생성 시각: {timestamp}
> 대상 모듈 수: {count}
> 선행 조건: {Step {NN-1} 완료 필요 | 없음 (독립 배치)}

## 공통 입력

- 상세 설계 가이드: `doc/base/detailed-design-guide.md`
- 플랫폼 참조 (C++/CMake): `doc/base/detailed-designs/cpp.md`
- 플랫폼 참조 (Spring Boot): `doc/base/detailed-designs/springboot.md`
- 코딩 컨벤션: `doc/base/coding-convention/README.md`

## 프로토콜 참조 원칙 (워커 필수 준수)

공유 프로토콜(IPC 메시지, IOCTL 코드, 콜백 시그니처 등)은 주체(Owner) 모듈의 interface.md에만 정의된다.
소비자(Consumer) 모듈의 implementation.md에서는 **절대 정의를 복사하지 않고** 참조 경로만 기재한다.

**금지 패턴:**
소비자 모듈의 implementation.md에 주체 모듈의 struct/define을 인라인 복사
```c
// 금지: 이런 식으로 복사하면 안 됨
typedef struct _DLP_IPC_HEADER { ... }  // ← 주체 모듈에서 복사 금지
#define IPC_MSG_USER_NOTIFICATION 0x0001 // ← 주체 모듈에서 복사 금지
```

**올바른 패턴:**
```markdown
AGT.CORE interface.md (`doc/develop/agt/core/core/interface.md`)에서 정의한
DLP_IPC_HEADER 및 IPC_MSG_* 코드를 공유 헤더로 참조한다.
공유 헤더: `src/agt/core/core/include/ipc_protocol.h`
이 모듈은 해당 정의를 참조하며, 복제하지 않는다.
```

## 모듈 목록

### {N}. {MODULE_ID} — {모듈 설명}

- **역할**: 주체(Owner) | 소비자(Consumer) | 혼합(Mixed)
- **doc 경로**: `{doc_path}/`
- **requirement.md**: `{doc_path}/requirement.md`
- **interface.md**: `{doc_path}/interface.md`
- **플랫폼 참조**: `doc/base/detailed-designs/{cpp|springboot}.md`
- **참조 인터페이스** (소비자인 경우):
  - → {OWNER_MODULE} interface.md: `{owner_interface_path}`
- **산출물**: `{doc_path}/implementation.md`

---
(다음 모듈 반복)
```

**분할 대상 모듈의 기재 형식:**

분할 대상 모듈은 기존 단일 항목 대신 서브태스크 목록으로 기재한다:

```markdown
### {N}. {MODULE_ID} — {모듈 설명} [분할: {K}개 서브태스크]

- **역할**: 주체(Owner) | 소비자(Consumer) | 혼합(Mixed)
- **doc 경로**: `{doc_path}/`
- **requirement.md**: `{doc_path}/requirement.md`
- **interface.md**: `{doc_path}/interface.md`
- **플랫폼 참조**: `doc/base/detailed-designs/{cpp|springboot}.md`

#### {N}.1 {MODULE_ID}/{domain} — {도메인 설명}
- **담당 FR**: {fr_list}
- **산출물**: `{doc_path}/implementation/{domain}.md`

#### {N}.2 {MODULE_ID}/{domain} — {도메인 설명}
- **담당 FR**: {fr_list}
- **산출물**: `{doc_path}/implementation/{domain}.md`

...(서브태스크 반복)

---
```

**플랫폼 선택 규칙:**
- 모듈이 `doc/develop/agt/` 하위 → `doc/base/detailed-designs/cpp.md`
- 모듈이 `doc/develop/svr/` 하위 → `doc/base/detailed-designs/springboot.md`

## Step 5: 실행 계획 요약

.temp/ 파일 생성 후, 실행 계획을 요약 출력한다.

```
=== parallel-design 실행 계획 ===

Step 01: {N}개 모듈 (독립, 병렬 실행)
Step 02: {M}개 모듈 (Step 01 완료 후 실행)

{분할 대상 모듈이 있는 경우:}
분할 대상: {K}개 모듈 → {S}개 서브태스크로 확장
  - {MODULE_ID}: {subtask_count}개 서브태스크 ({fr_count} FR)

건너뛴 모듈: {K}개 (implementation.md 이미 존재)

.temp/ 생성 파일:
  - .temp/step-01-design-batch.md
  - .temp/step-02-design-batch.md
```

**조건부 승인:**
- 건너뛴 모듈이 **0개** → 요약 출력 후 자동으로 Step 6 진행
- 건너뛴 모듈이 **1개 이상** → skip 목록 + 사유를 표시하고 AskUserQuestion으로 진행 여부 확인

`--dry-run` 인 경우 "실행하지 않음 (dry-run 모드)" 출력 후 종료한다.

## Step 6: 배치 실행

각 step을 순차적으로 실행한다. 동일 step 내 모듈들은 `/team N:deep-executor`로 병렬 실행한다.

### 6.1 워커 프롬프트 구성

각 deep-executor 워커에게 전달할 프롬프트를 다음 형식으로 구성한다:

```
다음 모듈의 implementation.md를 작성하라.

## 입력 문서

1. 상세 설계 가이드 (필수 읽기): `doc/base/detailed-design-guide.md`
2. 플랫폼 참조 (필수 읽기): `doc/base/detailed-designs/{cpp|springboot}.md`
3. 코딩 컨벤션 (존재 시 읽기): `doc/base/coding-convention/README.md`
4. 요구사항: `{doc_path}/requirement.md`
5. 인터페이스: `{doc_path}/interface.md`
{소비자인 경우 추가:}
6. 참조 인터페이스 (주체 모듈): `{owner_interface_path}`

## 작업 범위

detailed-design-guide.md의 모든 필수 섹션을 포함하여 implementation.md를 작성:
- 파생 요구사항(DFR) 도출
- 아키텍처 개요 (Mermaid graph TB)
- FR + DFR → 컴포넌트 추적성 테이블
- 내부 클래스/컴포넌트 설계 (Mermaid classDiagram)
- 핵심 시퀀스 (주요 FR별 정상 + 오류 경로)
- 에러 처리 전략
- 데이터 구조
- 의존 상세
- 설계 원칙 체크리스트

조건부 섹션: 상태 관리(상태 전이가 있는 경우), 스레드 모델(멀티스레딩 있는 경우)

## 플레이스홀더 처리 (필수 준수)

interface.md에 `/* 상세 설계 시 확정 */`, `(미정)`, `TBD` 등의 플레이스홀더가 남아 있으면
implementation.md 작성 **전에** 반드시 확정하라.

- 설계서(scratch.md, `doc/architecture/`)와 상위 모듈의 interface.md를 참조하여 구체적 정의를 도출
- 확정 불가 시 작업을 중단하고 보고 (임의로 결정하지 않음)
- 확정된 내용을 interface.md에 반영한 후 implementation.md 작성 진행

## 프로토콜 참조 원칙 (필수 준수)

이 모듈이 소비자(Consumer)인 경우, 주체 모듈의 프로토콜 정의(struct, define, 메시지 코드 등)를
implementation.md에 복사하지 말 것. 참조 경로만 기재하고 "단일 원천 원칙"을 준수할 것.

## 작업 범위 (분할 서브태스크) — 분할 대상 모듈에만 추가

이 모듈은 크기가 커서 도메인별로 분할 설계합니다.

- **도메인**: {domain_name}
- **담당 FR**: {fr_list}
- **산출물**: `{doc_path}/implementation/{domain}.md`

### 분할 작성 규칙

1. 아키텍처 개요: 전체 모듈 다이어그램 포함, 본 도메인 컴포넌트 강조
2. FR→컴포넌트 매핑: 담당 FR만 매핑
3. 내부 클래스 설계: 본 도메인 클래스만 상세 (다른 도메인은 외부 의존 표시)
4. 핵심 시퀀스: 담당 FR의 정상+오류 경로만 작성
5. 교차 도메인 참조: "→ {domain}.md 참조" 형태로 경로만 기재 (정의 복사 금지)

> 핵심: 모든 서브태스크에 전체 requirement.md + interface.md를 전달 (교차 참조 컨텍스트 유지), 단 **작성 범위만 제한**.

## 제외 사항

- test.md 작성하지 않음
- 소스 코드 구현하지 않음

## 산출물

- 일반 모듈: `{doc_path}/implementation.md`
- 분할 서브태스크: `{doc_path}/implementation/{domain}.md`
```

### 6.2 실행 순서

```
for step_num, modules in result_steps:
  # 분할 대상 모듈을 서브태스크로 확장
  tasks = []
  for module in modules:
    if module.split_plan:
      tasks.extend(module.subtasks)  # 6개 서브태스크 → 6개 워커
    else:
      tasks.append(module)           # 일반 모듈 → 1개 워커

  worker_count = min(len(tasks), args.workers or len(tasks), 20)

  # /team 호출
  # 각 태스크별 워커 프롬프트를 구성하여 /team {worker_count}:deep-executor 에 전달
  # 분할 서브태스크는 분할 작성 규칙이 포함된 프롬프트 사용
  invoke "/team {worker_count}:deep-executor" with:
    각 워커에게 태스크별 프롬프트 할당

  # 완료 대기 및 결과 검증
  for each task in tasks:
    if task.is_subtask:
      verify {doc_path}/implementation/{domain}.md was created
    else:
      verify {doc_path}/implementation.md was created
    if missing: report failure, add to failed list

  # 분할 모듈 추가 검증
  for each module in modules:
    if module.split_plan:
      # FR 합집합 == requirement.md 전체 FR (누락 검사)
      all_fr = union(subtask.fr_list for subtask in module.subtasks)
      missing_fr = requirement_fr - all_fr
      if missing_fr: report "FR 누락: {missing_fr}"

      # FR 교집합 == 공집합 (중복 검사)
      for each pair (s1, s2) in module.subtasks:
        overlap = s1.fr_list & s2.fr_list
        if overlap: report "FR 중복: {overlap} in {s1.domain} & {s2.domain}"

  # 실패 확인
  if failed_count > 0:
    AskUserQuestion: "Step {step_num}에서 {failed_count}건 실패. 실패 목록 + 사유를 표시. 다음 step 진행?"

  # 다음 step으로 진행
```

동일 모듈의 서브태스크들은 **상호 독립** (FR 영역이 다름) → 병렬 실행 가능.

### 6.3 결과 보고

```
=== parallel-design 완료 ===

Step 01: {success}/{total} 완료
Step 02: {success}/{total} 완료

생성된 implementation.md: {total_success}개
실패: {total_failed}개
건너뛴 모듈: {total_skipped}개

{실패 목록이 있으면:}
실패 모듈:
  - {MODULE_ID}: {실패 사유}
```

</Steps>

<Escalation_And_Stop_Conditions>
- **순환 의존성 감지**: 관련 모듈 목록 출력 후 즉시 중단
- **interface.md/requirement.md 누락**: 해당 모듈만 skip + 경고 (나머지 계속 진행)
- **step 내 1건 이상 실패**: 실패 목록 + 사유를 표시하고 다음 step 진행 여부 사용자 확인
- **설계 가이드 누락** (`doc/base/detailed-design-guide.md`): 즉시 중단
- **사용자 "중단" 요청**: 현재 step 완료 후 중단 (진행 중인 워커는 완료까지 대기)
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
전체 모듈 병렬 설계:
```
사용자: /parallel-design
스킬: 24개 모듈 탐색 완료. 6개 의존성 발견.
      Step 01: 18개 모듈 (독립), Step 02: 6개 모듈 (소비자)
      .temp/step-01-design-batch.md, step-02-design-batch.md 생성 완료.
      진행하시겠습니까?
사용자: 진행
스킬: Step 01 실행 중... /team 18:deep-executor
      → 18/18 완료
      Step 02 실행 중... /team 6:deep-executor
      → 6/6 완료
      총 24개 implementation.md 생성 완료.
```
</Good>

<Good>
AGT만 선택:
```
사용자: /parallel-design agt
스킬: AGT 14개 모듈 탐색 완료. 5개 의존성 발견.
      Step 01: 9개 모듈, Step 02: 5개 모듈
      .temp/ 파일 생성 완료. 진행하시겠습니까?
```
</Good>

<Good>
dry-run으로 계획만 확인:
```
사용자: /parallel-design --dry-run
스킬: .temp/ 파일 생성 완료. (실행하지 않음)
      .temp/step-01-design-batch.md (18개 모듈)
      .temp/step-02-design-batch.md (6개 모듈)
```
</Good>

<Good>
일부 모듈이 이미 설계된 경우:
```
사용자: /parallel-design agt
스킬: AGT 14개 모듈 탐색. 3개 이미 설계 완료 (CORE, DRVDEV, CLIP).
      대상: 11개 모듈. 의존성 재분석...
      Step 01: 6개 모듈, Step 02: 5개 모듈
      진행하시겠습니까?
```
</Good>

<Good>
대형 모듈 자동 분할:
```
사용자: /parallel-design svr
스킬: SVR 10개 모듈 탐색 완료.
      대형 모듈 감지: SVR.SVCCORE (31 FR, 18 REST endpoints)
        → 6개 서브태스크로 분할: core, auth, policy-agent, audit, security, approval-report
      Step 01: 10개 모듈 (4개 일반 + 6개 서브태스크)
      .temp/ 파일 생성 완료. 진행하시겠습니까?
사용자: 진행
스킬: Step 01 실행 중... /team 10:deep-executor
      → 10/10 완료 (SVR.SVCCORE: implementation/core.md~approval-report.md 6개 생성)
```
</Good>

<Good>
분할 비활성화:
```
사용자: /parallel-design svr --no-split
스킬: SVR 10개 모듈 탐색 완료. (대형 모듈 분할 비활성화)
      Step 01: 10개 모듈
```
</Good>

<Bad>
의존성을 무시하고 모든 모듈을 한 배치에서 실행:
```
/team 24:deep-executor  # ← TRAY가 CORE보다 먼저 실행될 수 있음 → 참조 불완전
```
이유: 소비자 모듈은 주체 모듈의 implementation.md가 완료된 후 실행해야 한다.
</Bad>

<Bad>
워커 프롬프트에 프로토콜 참조 원칙을 빠뜨림:
```
# 워커가 CORE의 IPC struct를 TRAY implementation.md에 인라인 복사
typedef struct _DLP_IPC_HEADER { ... }  # ← 단일 원천 원칙 위반
```
이유: 프로토콜 정의가 여러 곳에 복제되면 불일치가 발생한다.
</Bad>

</Examples>

<Tool_Usage>
- **Glob 도구**: `doc/develop/**/interface.md` 탐색으로 모듈 목록 구축
- **Read 도구**: interface.md 파싱 (소유권, 참조 경로 추출), requirement.md 존재 확인
- **Bash 도구**: `.temp/` 디렉토리 생성 (`mkdir -p`)
- **Write 도구**: `.temp/step-{NN}-design-batch.md` 생성
- **AskUserQuestion**: 실행 확인, 덮어쓰기 확인, 실패 시 계속 진행 여부
- **Skill 도구**: `/team N:deep-executor` 호출로 배치 내 병렬 실행
- **Grep 도구**: 생성된 implementation.md에서 프로토콜 인라인 복사 여부 검증
</Tool_Usage>

<Final_Checklist>
- [ ] `doc/base/detailed-design-guide.md` 존재를 확인했는가?
- [ ] 모든 대상 모듈의 interface.md와 requirement.md 존재를 검증했는가?
- [ ] 의존성 그래프에서 순환 참조가 없는지 확인했는가?
- [ ] 위상 정렬 결과가 올바른가? (owner → consumer 순서 보장)
- [ ] `.temp/step-{NN}-design-batch.md`에 프로토콜 참조 원칙이 포함되었는가?
- [ ] 워커 프롬프트에 설계 가이드, 플랫폼 참조, 입력 문서 경로가 모두 포함되었는가?
- [ ] 소비자 모듈의 워커 프롬프트에 참조 인터페이스 경로가 포함되었는가?
- [ ] `--dry-run` 시 실행 없이 .temp/ 파일만 생성하고 종료하는가?
- [ ] step 간 순차 실행이 보장되는가? (step 01 완료 후 step 02 실행)
- [ ] 생성된 implementation.md에 프로토콜 정의 인라인 복사가 없는가?
- [ ] 결과 보고에 성공/실패/skip 수가 정확히 집계되었는가?
- [ ] 각 implementation.md에 detailed-design-guide.md 필수 섹션이 모두 포함되었는가? (파생 요구사항, 아키텍처 개요, 추적성 테이블, 컴포넌트 설계, 핵심 시퀀스, 에러 처리 전략, 데이터 구조, 의존 상세)
- [ ] 각 implementation.md의 핵심 시퀀스가 정상 경로와 오류 경로를 모두 포함하는가?
- [ ] 소비자 모듈의 implementation.md가 참조하는 주체 모듈 인터페이스의 함수 시그니처/메시지 코드를 빠짐없이 사용하고 있는가?
- [ ] FR >= split-threshold인 모듈이 분할 대상으로 식별되었는가?
- [ ] 분할된 서브태스크의 FR 합집합 == requirement.md 전체 FR?
- [ ] 분할된 서브태스크 간 FR 중복이 없는가?
- [ ] 각 서브태스크 산출물이 `implementation/` 폴더 확장 규칙을 따르는가?
</Final_Checklist>
