---
name: parallel-test
description: 모듈 test.md를 병렬 배치로 자동 생성하는 스킬. "병렬 테스트", "test.md 일괄", "parallel test", "테스트 설계 일괄", "모듈 테스트 실행" 등을 요청할 때 사용. doc/develop 폴더에 requirement.md + interface.md + implementation.md가 준비된 상태에서 test.md를 생성하려 할 때 반드시 이 스킬을 사용할 것.
---

<Purpose>
doc/develop/ 내 모듈들을 탐색하고, 서브시스템(AGT/SVR)별로 배치를 구성하여 /team N:deep-executor로 test.md를 병렬 작성한다.

핵심 가치:
- 의존성 분석 불필요: 모든 입력 문서(requirement.md, interface.md, implementation.md)가 이미 존재
- 서브시스템별 배치: AGT/SVR로 분할하여 병렬 실행 (20-worker 제한 준수)
- 자족적 워커 프롬프트: 각 워커가 독립적으로 작업 가능하도록 모든 입력 경로를 명시
- Mock 금지 기본: 실제 환경 테스트 원칙 준수
</Purpose>

<Use_When>
- 전체 또는 특정 서브시스템(agt/svr)의 test.md를 일괄 작성할 때
- 병렬 에이전트로 테스트 설계 처리량을 최대화하고 싶을 때
- implementation.md가 모두 완성된 상태에서 test.md를 생성할 때
</Use_When>

<Do_Not_Use_When>
- 단일 모듈의 test.md만 작성할 때 (직접 test-design-guide.md 참조)
- implementation.md가 아직 작성되지 않았을 때 (먼저 /parallel-design 사용)
- 기존 test.md를 수정/업데이트할 때 (/parallel-test-review 사용)
</Do_Not_Use_When>

<Arguments>
인수 형식: `/parallel-test [subsystem] [--force] [--dry-run] [--workers N]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt` 또는 `svr` — 특정 서브시스템만 대상 |
| --force | false | 기존 test.md가 있어도 재작성 |
| --dry-run | false | .temp/ 파일만 생성하고 실행하지 않음 |
| --workers N | (배치 내 모듈 수) | 배치당 병렬 워커 수 제한 (최대 20) |
</Arguments>

<Steps>

## Step 0: 초기화

1. `doc/base/test-design-guide.md` 존재 확인 — 없으면 즉시 중단
2. `.temp/` 디렉토리 확인 — 없으면 `mkdir -p .temp`
3. `.temp/step-*-test-batch.md` 기존 파일이 있으면 사용자에게 덮어쓰기 여부 확인 (AskUserQuestion)

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

**Skip 판정:**
각 모듈 디렉토리에 `test.md`가 이미 존재하는지 확인.
- 존재하고 `--force`가 아니면 → 파일 내용을 Read하여 scaffold 템플릿 여부를 판별:
  - `상태: 미작성` 또는 `(테스트 설계 시 작성)` 문자열이 포함된 경우 → **scaffold 빈 템플릿**으로 간주, skip하지 않고 대상 목록에 추가
  - 그 외 (실질적 내용이 있는 경우) → skip 목록에 추가
- 존재하지 않으면 → 대상 목록에 추가
- `--force`이면 → 무조건 대상 목록에 추가

**필수 파일 검증:**
각 대상 모듈에 `requirement.md`와 `interface.md`가 존재하는지 확인.
- 어느 하나라도 없으면 → 경고 출력 후 해당 모듈 skip

## Step 2: 통합 테스트 교차 참조 식별 (정보용)

각 대상 모듈의 interface.md를 Read하여 외부 참조 관계를 파싱한다.
이 정보는 워커 프롬프트에 포함되어 통합 테스트 시나리오 도출에 활용된다.

**파싱 규칙:**

1. **소유권 판정**: `## 소유권` 절의 텍스트에서:
   - `주체(Owner)` 포함 → role = "owner"
   - `소비자(Consumer)` 포함 → role = "consumer"
   - 둘 다 포함 → role = "mixed" (주체이면서 소비자)

2. **참조 경로 추출**: `→` 로 시작하는 행에서 backtick 내 경로를 추출:
   ```
   → {설명} 참조: `{path}`
   ```
   backtick 사이의 경로가 참조 대상 모듈의 interface.md 경로이다.

3. **참조 대상 모듈 식별**: 추출한 경로에서 module_id를 역으로 파싱:
   ```
   doc/develop/agt/core/core/interface.md → AGT.CORE
   doc/develop/agt/driver/drvdev/interface.md → AGT.DRVDEV
   ```

**중요:** 이 단계는 블로킹이 아니다. 참조 정보가 없어도 워커는 독립적으로 test.md를 작성할 수 있다. 참조 정보는 통합 테스트 케이스의 "관련 컴포넌트" 열을 풍부하게 하기 위한 보조 입력이다.

## Step 3: 배치 계획

모듈을 서브시스템(AGT/SVR)별로 분할하여 배치를 구성한다.

**배치 구성 규칙:**
```
algorithm:
  agt_modules = [m for m in target_modules if m.path starts with "doc/develop/agt/"]
  svr_modules = [m for m in target_modules if m.path starts with "doc/develop/svr/"]

  batches = []
  if agt_modules:
    batches.append(("agt", agt_modules))
  if svr_modules:
    batches.append(("svr", svr_modules))
```

**워커 수 제한:**
- 각 배치의 워커 수 = `min(len(modules), args.workers or len(modules), 20)`
- 20-worker 제한 초과 시 배치를 분할: `step-01-test-batch-agt.md`, `step-02-test-batch-agt.md` 등

**결과를 사용자에게 요약 출력:**
```
=== 모듈 탐색 결과 ===
AGT: {N}개 모듈
SVR: {M}개 모듈

건너뛴 모듈: {K}개 (test.md 이미 존재)
필수 문서 누락: {L}개 (requirement.md 또는 interface.md 없음)
```

## Step 4: .temp/ 파일 생성

각 배치별로 `.temp/step-{NN}-test-batch.md` 파일을 생성한다.

**파일명**: `step-{NN}-test-batch.md` (NN = 01, 02, ...)

**각 파일의 구조:**

```markdown
# Step {NN} — 테스트 설계 배치

> 생성 시각: {timestamp}
> 대상 모듈 수: {count}
> 서브시스템: {AGT | SVR}

## 공통 입력

- 테스트 설계 가이드: `doc/base/test-design-guide.md`
- 플랫폼 참조 (C++/CMake): `doc/base/detailed-designs/cpp.md`
- 플랫폼 참조 (Spring Boot): `doc/base/detailed-designs/springboot.md`

## 테스트 설계 원칙 (워커 필수 준수)

1. **Mock 금지 기본**: 실제 환경에서 테스트. Mock 사용 시 반드시 사유와 승인 기재.
2. **에러 경로 TC 필수**: implementation.md의 에러 처리 전략 각 행에 대응하는 TC 작성.
3. **프로토콜 참조 원칙**: 소비자 모듈의 test.md에서 주체 모듈의 프로토콜 정의를 인라인 복사하지 않고 참조 경로만 기재.
4. **TC ID 체계**: `{MODULE}-TC-UT-NNN` (단위), `{MODULE}-TC-IT-NNN` (통합)

## 모듈 목록

### {N}. {MODULE_ID} — {모듈 설명}

- **역할**: 주체(Owner) | 소비자(Consumer) | 혼합(Mixed)
- **doc 경로**: `{doc_path}/`
- **requirement.md**: `{doc_path}/requirement.md`
- **interface.md**: `{doc_path}/interface.md`
- **implementation.md**: `{doc_path}/implementation.md`
- **플랫폼 참조**: `doc/base/detailed-designs/{cpp|springboot}.md`
- **교차 참조** (소비자인 경우):
  - → {OWNER_MODULE} interface.md: `{owner_interface_path}`
- **산출물**: `{doc_path}/test.md`

---
(다음 모듈 반복)
```

**플랫폼 선택 규칙:**
- 모듈이 `doc/develop/agt/` 하위 → `doc/base/detailed-designs/cpp.md`
- 모듈이 `doc/develop/svr/` 하위 → `doc/base/detailed-designs/springboot.md`

## Step 5: 사용자 확인

.temp/ 파일 생성 후, 사용자에게 실행 계획을 요약 보고한다:

```
=== parallel-test 실행 계획 ===

Step 01: {N}개 모듈 (AGT, 병렬 실행)
Step 02: {M}개 모듈 (SVR, 병렬 실행)

건너뛴 모듈: {K}개 (test.md 이미 존재)

.temp/ 생성 파일:
  - .temp/step-01-test-batch.md
  - .temp/step-02-test-batch.md

진행하시겠습니까?
```

`--dry-run` 인 경우 "실행하지 않음 (dry-run 모드)" 출력 후 종료한다.

## Step 6: 배치 실행

각 배치를 `/team N:deep-executor`로 병렬 실행한다. 배치 간에는 의존성이 없으므로 순차 실행하되, 동일 배치 내 모듈들은 병렬 실행한다.

### 6.1 워커 프롬프트 구성

각 deep-executor 워커에게 전달할 프롬프트를 다음 형식으로 구성한다:

```
다음 모듈의 test.md를 작성하라.

## 입력 문서

1. 테스트 설계 가이드 (필수 읽기): `doc/base/test-design-guide.md`
2. 플랫폼 참조 (필수 읽기): `doc/base/detailed-designs/{cpp|springboot}.md`
3. 요구사항: `{doc_path}/requirement.md`
4. 인터페이스: `{doc_path}/interface.md`
5. 구현 설계: `{doc_path}/implementation.md`
{소비자인 경우 추가:}
6. 참조 인터페이스 (주체 모듈): `{owner_interface_path}`

## 작업 범위

test-design-guide.md의 모든 필수 섹션을 포함하여 test.md를 작성:
- FR → TC 추적성 테이블 (requirement.md의 모든 FR이 최소 1개 TC에 매핑)
- 인터페이스 → TC 매핑 (interface.md의 모든 공개 함수가 최소 1개 TC에 매핑)
- 단위 테스트 케이스 표 (정상 + 비정상 + 경계값 + 에러 경로)
- 통합 테스트 케이스 표 (시나리오 기반, 관련 컴포넌트 명시)
- 테스트 환경 (실제 환경 기본, Mock 사용 시 사유 명시)
- 커버리지 검증 (tc-coverage-checklist 6단계 적용)

## TC ID 체계

- 단위 테스트: `{MODULE}-TC-UT-NNN` (예: AGT.CORE-TC-UT-001)
- 통합 테스트: `{MODULE}-TC-IT-NNN` (예: AGT.CORE-TC-IT-001)

## TC 도출 기법

1. **FR 기반 도출**: requirement.md의 각 FR에 대해 정상/비정상 시나리오
2. **경계값 분석**: 입력 파라미터의 경계값 (최솟값, 최댓값, NULL, 빈 값)
3. **에러 경로 커버리지**: implementation.md의 에러 처리 전략 각 행에 대응하는 TC

## 테스트 원칙 (필수 준수)

1. **Mock 금지 기본**: 실제 환경에서 테스트. Mock/stub은 기본적으로 사용하지 않는다.
   Mock이 반드시 필요한 경우 test.md에 사유와 범위를 명시해야 한다.
2. **프로토콜 참조 원칙**: 이 모듈이 소비자(Consumer)인 경우, 주체 모듈의 프로토콜 정의를
   test.md에 복사하지 말 것. 참조 경로만 기재하고 "단일 원천 원칙"을 준수할 것.
3. **에러 경로 TC 필수**: implementation.md의 에러 처리 전략 모든 항목에 대응하는 TC가 있어야 한다.

## 제외 사항

- requirement.md, interface.md, implementation.md 수정 금지
- 소스 코드 구현 금지

## 산출물

- `{doc_path}/test.md`
```

### 6.2 실행 순서

```
for batch_num, (subsystem, modules) in enumerate(batches, 1):
  worker_count = min(len(modules), args.workers or len(modules), 20)

  # /team 호출
  # 각 모듈별 워커 프롬프트를 구성하여 /team {worker_count}:deep-executor 에 전달
  invoke "/team {worker_count}:deep-executor" with:
    각 워커에게 모듈별 프롬프트 할당

  # 완료 대기 및 결과 검증
  for each module in modules:
    verify {doc_path}/test.md was created
    if missing: report failure, add to failed list

  # 실패율 확인
  if failed_count > len(modules) / 2:
    AskUserQuestion: "배치 {batch_num}에서 50% 이상 실패. 다음 배치 진행?"

  # 다음 배치로 진행
```

### 6.3 결과 보고

```
=== parallel-test 완료 ===

Step 01 (AGT): {success}/{total} 완료
Step 02 (SVR): {success}/{total} 완료

생성된 test.md: {total_success}개
실패: {total_failed}개
건너뛴 모듈: {total_skipped}개

{실패 목록이 있으면:}
실패 모듈:
  - {MODULE_ID}: {실패 사유}
```

</Steps>

<Escalation_And_Stop_Conditions>
- **테스트 설계 가이드 누락** (`doc/base/test-design-guide.md`): 즉시 중단
- **필수 문서 누락** (requirement.md, interface.md, implementation.md 중 하나라도 없음): 해당 모듈만 skip + 경고 (나머지 계속 진행)
- **배치 내 50% 이상 실패**: 다음 배치 진행 여부 사용자 확인
- **사용자 "중단" 요청**: 현재 배치 완료 후 중단 (진행 중인 워커는 완료까지 대기)
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
전체 모듈 병렬 테스트 설계:
```
사용자: /parallel-test
스킬: 24개 모듈 탐색 완료.
      Step 01: AGT 14개 모듈 (병렬 실행)
      Step 02: SVR 10개 모듈 (병렬 실행)
      .temp/step-01-test-batch.md, step-02-test-batch.md 생성 완료.
      진행하시겠습니까?
사용자: 진행
스킬: Step 01 실행 중... /team 14:deep-executor
      → 14/14 완료
      Step 02 실행 중... /team 10:deep-executor
      → 10/10 완료
      총 24개 test.md 생성 완료.
```
</Good>

<Good>
AGT만 선택:
```
사용자: /parallel-test agt
스킬: AGT 14개 모듈 탐색 완료.
      Step 01: 14개 모듈 (병렬 실행)
      .temp/ 파일 생성 완료. 진행하시겠습니까?
```
</Good>

<Good>
dry-run으로 계획만 확인:
```
사용자: /parallel-test --dry-run
스킬: .temp/ 파일 생성 완료. (실행하지 않음)
      .temp/step-01-test-batch.md (AGT 14개 모듈)
      .temp/step-02-test-batch.md (SVR 10개 모듈)
```
</Good>

<Good>
일부 모듈이 이미 테스트 설계된 경우:
```
사용자: /parallel-test agt
스킬: AGT 14개 모듈 탐색. 3개 이미 test.md 존재 (CORE, DRVDEV, CLIP).
      대상: 11개 모듈.
      Step 01: 11개 모듈 (병렬 실행)
      진행하시겠습니까?
```
</Good>

<Good>
워커 수 제한:
```
사용자: /parallel-test --workers 10
스킬: 24개 모듈 탐색 완료.
      Step 01: AGT 14개 모듈 (10 워커로 실행)
      Step 02: SVR 10개 모듈 (10 워커로 실행)
      진행하시겠습니까?
```
</Good>

<Bad>
implementation.md 없이 실행:
```
/parallel-test  # ← implementation.md가 없는 모듈은 에러 경로 TC를 도출할 수 없음
```
이유: test.md는 implementation.md의 에러 처리 전략을 입력으로 필요로 한다.
</Bad>

<Bad>
워커 프롬프트에 Mock 금지 원칙을 빠뜨림:
```
# 워커가 외부 의존성을 무분별하게 Mock 처리
@MockBean ServerClient serverClient;  # ← 실제 환경 테스트 원칙 위반
```
이유: Mock 사용은 사용자 승인이 필요하며, 사유를 test.md에 명시해야 한다.
</Bad>

</Examples>

<Tool_Usage>
- **Glob 도구**: `doc/develop/**/implementation.md` 탐색으로 모듈 목록 구축, `test.md` 존재 확인
- **Read 도구**: interface.md 파싱 (소유권, 참조 경로 추출), requirement.md/implementation.md 존재 확인
- **Bash 도구**: `.temp/` 디렉토리 생성 (`mkdir -p`)
- **Write 도구**: `.temp/step-{NN}-test-batch.md` 생성
- **AskUserQuestion**: 실행 확인, 덮어쓰기 확인, 실패 시 계속 진행 여부
- **Skill 도구**: `/team N:deep-executor` 호출로 배치 내 병렬 실행
- **Grep 도구**: 생성된 test.md에서 FR→TC 매핑 누락, Interface→TC 매핑 누락 검증
</Tool_Usage>

<Final_Checklist>
- [ ] `doc/base/test-design-guide.md` 존재를 확인했는가?
- [ ] 모든 대상 모듈의 requirement.md, interface.md, implementation.md 존재를 검증했는가?
- [ ] 모듈 skip 판정이 올바른가? (기존 test.md 존재 시 skip, --force 시 재작성)
- [ ] `.temp/step-{NN}-test-batch.md`에 테스트 설계 원칙(Mock 금지, 에러 경로, 프로토콜 참조)이 포함되었는가?
- [ ] 워커 프롬프트에 테스트 가이드, 플랫폼 참조, 입력 문서 경로(3개)가 모두 포함되었는가?
- [ ] 워커 프롬프트에 TC ID 체계(`{MODULE}-TC-UT-NNN`, `{MODULE}-TC-IT-NNN`)가 명시되었는가?
- [ ] 소비자 모듈의 워커 프롬프트에 참조 인터페이스 경로가 포함되었는가?
- [ ] `--dry-run` 시 실행 없이 .temp/ 파일만 생성하고 종료하는가?
- [ ] 20-worker 제한이 적용되었는가?
- [ ] 생성된 test.md에 FR→TC 추적성 테이블이 있는가?
- [ ] 생성된 test.md에 인터페이스→TC 매핑이 있는가?
- [ ] 결과 보고에 성공/실패/skip 수가 정확히 집계되었는가?
</Final_Checklist>
