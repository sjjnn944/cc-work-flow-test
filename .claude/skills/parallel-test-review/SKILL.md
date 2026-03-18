---
name: parallel-test-review
description: 구현 완료된 소스 코드 기반으로 기존 test.md의 TC를 재검토하고, 추가 TC의 테스트 코드를 구현하는 스킬. 분기 조건 분석, TEST/REVIEW 검증 방법 분류, 누락 TC 추가, 추가 TC 테스트 코드 생성을 병렬로 수행한다. "테스트 리뷰", "TC 재검토", "분기 커버리지", "test.md 업데이트", "검증 방법 분류", "TEST REVIEW 마킹", "추가 TC 구현" 등을 요청할 때 사용. src/ 폴더에 소스 코드가 존재하고 doc/develop/ 에 test.md가 이미 있는 상태에서 반드시 이 스킬을 사용할 것.
---

<Purpose>
구현 완료 후 소스 코드의 분기 조건을 분석하여 기존 test.md를 재검토한다.

핵심 가치:
- 분기 커버리지 검증: 소스 코드의 if/switch/삼항 분기가 TC로 커버되는지 확인
- TEST/REVIEW 분류: test-design-guide.md 6.1절 기준으로 각 TC의 검증 방법을 마킹
- 누락 TC 보충: 커버되지 않은 분기에 대한 TC를 추가
- 추가 TC 구현: 신규 추가된 TC의 테스트 코드를 test/ 디렉토리에 생성
- 병렬 실행: 서브시스템별 배치로 /team N:deep-executor 활용
</Purpose>

<Use_When>
- 구현 완료 후 기존 test.md를 소스 코드 기준으로 재검토할 때
- TC에 TEST/REVIEW 검증 방법을 일괄 분류할 때
- 소스 코드 분기 조건 대비 TC 누락을 확인할 때
- src/ 폴더에 소스 코드가 존재하는 상태일 때
</Use_When>

<Do_Not_Use_When>
- test.md가 아직 없을 때 (먼저 /parallel-test 사용)
- 소스 코드가 아직 구현되지 않았을 때 (src/ 미존재)
- 단일 모듈의 test.md만 검토할 때 (직접 수동 검토)
</Do_Not_Use_When>

<Arguments>
인수 형식: `/parallel-test-review [subsystem] [--dry-run] [--workers N] [--impl]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt` 또는 `svr` — 특정 서브시스템만 대상 |
| --dry-run | false | .temp/ 파일만 생성하고 실행하지 않음 |
| --workers N | (배치 내 모듈 수) | 배치당 병렬 워커 수 제한 (최대 20) |
| --impl | false | 추가 TC에 대한 테스트 코드를 test/ 디렉토리에 생성 |
</Arguments>

<Steps>

## Step 0: 초기화

1. `doc/base/test-design-guide.md` 존재 확인 — 없으면 즉시 중단
2. `src/` 디렉토리 존재 확인 — 없으면 "소스 코드가 없습니다. 구현 완료 후 실행하세요." 출력 후 중단
3. `.temp/` 디렉토리 확인 — 없으면 `mkdir -p .temp`
4. `.temp/step-*-test-review-batch.md` 기존 파일이 있으면 사용자에게 덮어쓰기 여부 확인

## Step 1: 모듈 탐색 (Discovery)

기존 test.md와 대응하는 소스 코드를 모두 찾는다.

**탐색:**
```
test_files = Glob("doc/develop/**/test.md")  # 또는 서브시스템 한정
```

**모듈별 소스 경로 매핑 규칙:**
```
doc/develop/agt/{category}/{module}/test.md
  → src/agt/{category}/{module}/

doc/develop/agt/{module}/test.md  (flat 구조)
  → src/agt/{module}/

doc/develop/svr/{module}/test.md
  → src/svr/{module}/
```

**Skip 판정:**
- test.md가 없으면 → skip ("test.md 미존재, 먼저 /parallel-test 실행")
- 대응하는 src/ 디렉토리가 없으면 → skip ("소스 코드 미존재")
- src/ 디렉토리에 소스 파일(*.cpp, *.h, *.java, *.kt)이 없으면 → skip

**소스 파일 수집:**
```
AGT 모듈: Glob("src/agt/{...}/{module}/**/*.cpp") + Glob("src/agt/{...}/{module}/**/*.h")
SVR 모듈: Glob("src/svr/{module}/**/*.java") + Glob("src/svr/{module}/**/*.kt")
```

## Step 2: 배치 계획

/parallel-test와 동일한 배치 분할 로직 적용 (AGT/SVR 분할, 20-worker 제한).

**결과를 사용자에게 요약 출력:**
```
=== 모듈 탐색 결과 ===
AGT: {N}개 모듈 (소스 파일 {X}개)
SVR: {M}개 모듈 (소스 파일 {Y}개)

건너뛴 모듈: {K}개 (소스 코드 미존재)
```

## Step 3: .temp/ 파일 생성

각 배치별로 `.temp/step-{NN}-test-review-batch.md` 파일을 생성한다.

**각 파일의 구조:**

```markdown
# Step {NN} — 테스트 리뷰 배치

> 생성 시각: {timestamp}
> 대상 모듈 수: {count}
> 서브시스템: {AGT | SVR}

## 공통 입력

- 테스트 설계 가이드: `doc/base/test-design-guide.md` (특히 6.1절 검증 방법 분류)
- 플랫폼 참조 (C++/CMake): `doc/base/detailed-designs/cpp.md`
- 플랫폼 참조 (Spring Boot): `doc/base/detailed-designs/springboot.md`
- 모듈 매핑: `doc/architecture/module-mapping.md` (test 경로 참조, `--impl` 시 필수)

## 리뷰 원칙 (워커 필수 준수)

1. **검증 방법 분류 (6.1절)**: 모든 TC에 TEST 또는 REVIEW를 마킹한다.
   - TEST: 테스트 코드로 실행하여 자동 검증 가능한 시나리오 (기본값)
   - REVIEW: 일반 테스트 환경에서 재현 불가, 코드 리뷰로 검증하는 시나리오
2. **REVIEW 판정 기준**: 메모리 할당 실패, 커널 풀 할당 실패, 스레드/핸들 생성 실패, OS API 내부 오류
3. **REVIEW가 아닌 것**: 입력 검증, 외부 자원 부재, 프로토콜 오류, 경계값 → 반드시 TEST
4. **분기 커버리지**: 소스 코드의 공개 함수 내 if/switch/삼항 분기를 분석하여 TC 누락 확인
5. **기존 TC 보존**: 기존 TC의 ID/시나리오/기대결과는 변경하지 않음. 검증 방법 컬럼만 추가.

## 모듈 목록

### {N}. {MODULE_ID}

- **doc 경로**: `{doc_path}/`
- **src 경로**: `{src_path}/`
- **소스 파일**: {파일 목록}
- **기존 test.md**: `{doc_path}/test.md`
- **implementation.md**: `{doc_path}/implementation.md`
- **interface.md**: `{doc_path}/interface.md`

---
(다음 모듈 반복)
```

## Step 4: 사용자 확인

```
=== parallel-test-review 실행 계획 ===

Step 01: {N}개 모듈 (AGT, 병렬 실행)
Step 02: {M}개 모듈 (SVR, 병렬 실행)

건너뛴 모듈: {K}개 (소스 코드 미존재)

.temp/ 생성 파일:
  - .temp/step-01-test-review-batch.md
  - .temp/step-02-test-review-batch.md

진행하시겠습니까?
```

`--dry-run` 인 경우 종료.

## Step 5: 배치 실행

각 배치를 `/team N:deep-executor`로 실행한다.

### 5.1 워커 프롬프트 구성

```
다음 모듈의 test.md를 소스 코드 기준으로 재검토하라.

## 입력 문서

1. 테스트 설계 가이드 (필수 읽기): `doc/base/test-design-guide.md` (6.1절 검증 방법 분류 숙지)
2. 플랫폼 참조 (필수 읽기): `doc/base/detailed-designs/{cpp|springboot}.md`
3. 기존 테스트: `{doc_path}/test.md`
4. 인터페이스: `{doc_path}/interface.md`
5. 구현 설계: `{doc_path}/implementation.md`
6. 소스 코드: `{src_path}/` 하위 전체

## 작업 순서

### A. 소스 코드 분기 분석

1. interface.md의 공개 함수 목록을 확인한다.
2. 각 공개 함수의 소스 코드 구현을 읽는다.
3. if/switch/삼항 분기를 추출하여 분기 조건 목록을 구축한다.
   - 각 분기에 대해: 함수명, 조건식, 분기 유형(정상/에러/경계값) 기록
4. 에러 처리 분기에서 재현 가능 여부를 판정한다:
   - 재현 가능 → TEST 분류
   - 재현 불가 → REVIEW 분류 (6.1절 기준 적용)

### B. 기존 TC 대조

1. 기존 test.md의 모든 TC를 읽는다.
2. 각 TC가 어떤 분기를 커버하는지 매핑한다.
3. 커버되지 않은 분기를 누락 목록으로 정리한다.

### C. test.md 업데이트

1. **기존 TC 표에 검증 방법 컬럼 추가**:
   - 단위 테스트 표: `| TC ID | 대상 함수 | 시나리오 | 입력 | 기대 결과 | 검증 방법 | FR 매핑 |`
   - 통합 테스트 표: `| TC ID | 시나리오 | ... | 기대 결과 | 검증 방법 | FR 매핑 |`
   - 대부분의 TC는 TEST. REVIEW는 6.1절 기준에 해당하는 것만.
2. **누락 분기에 대한 TC 추가**:
   - 기존 TC 번호 체계를 이어서 번호 부여
   - 추가된 TC에도 TEST/REVIEW 마킹
3. **리뷰 요약 섹션 추가** (test.md 맨 아래):
   ```markdown
   ## 코드 리뷰 검증 대상

   소스 코드 분기 분석 결과, 아래 TC는 일반 테스트 환경에서 재현 불가하여
   코드 리뷰로 검증한다 (test-design-guide.md 6.1절).

   | TC ID | 시나리오 | REVIEW 사유 | 리뷰 결과 |
   |-------|---------|------------|----------|
   | TC-UT-XXX | 메모리 할당 실패 | E_OUTOFMEMORY 재현 불가 | (구현 후 기입) |
   ```

### D. 추가 TC 테스트 코드 구현 (`--impl` 플래그 사용 시)

`--impl` 플래그가 활성화된 경우에만 수행한다.

1. **신규 추가된 TC 중 TEST 분류된 것**만 대상으로 테스트 코드를 작성한다.
2. **테스트 코드 위치**: `doc/architecture/module-mapping.md`의 test 경로 참조
   - C++/CMake: `test/unit/{sys}/{category}/{module}/` 하위에 테스트 파일 생성
   - Spring Boot: 모듈 내 `src/test/` 디렉토리에 생성
3. **테스트 코드 작성 원칙**:
   - 기존 테스트 파일이 있으면 해당 파일에 추가 (파일 말미에 append)
   - 기존 테스트 파일이 없으면 새 파일 생성
   - test-design-guide.md의 테스트 코드 컨벤션 준수
   - Mock 금지 기본 원칙 준수 (실제 환경 테스트)
4. **테스트 코드 검증**: 작성 후 빌드 가능 여부 확인 (컴파일 에러 없는지)

## 변경 범위 제한

- test.md 수정: 검증 방법 컬럼 추가 + 누락 TC 추가 + 리뷰 요약 섹션
- `--impl` 시 추가: test/ 디렉토리에 테스트 코드 생성
- 기존 TC의 ID, 시나리오, 입력, 기대 결과, FR 매핑은 변경하지 않는다.
- requirement.md, interface.md, implementation.md는 수정하지 않는다.
- src/ 소스 코드는 수정하지 않는다 (읽기 전용 참조).

## 산출물

- `{doc_path}/test.md` (업데이트)
- `--impl` 시 추가: `{test_path}/` 하위 테스트 코드 파일
```

### 5.2 실행 순서

/parallel-test와 동일 (배치 순차, 배치 내 병렬, 50% 실패 시 사용자 확인).

### 5.3 결과 보고

```
=== parallel-test-review 완료 ===

Step 01 (AGT): {success}/{total} 완료
Step 02 (SVR): {success}/{total} 완료

모듈별 요약:
  {MODULE_ID}: TC {total}개 (TEST {n}, REVIEW {m}), 신규 추가 {k}개
  ...

전체:
  TC 총계: {total} (TEST {n}, REVIEW {m})
  신규 추가: {k}개
  REVIEW 대상: {m}개

{--impl 사용 시 추가:}
테스트 코드 생성:
  생성된 테스트 파일: {file_count}개
  구현된 TC: {impl_count}개 (신규 추가 TC 중 TEST 분류)
```

</Steps>

<Escalation_And_Stop_Conditions>
- **소스 코드 미존재** (`src/` 디렉토리 없음): 즉시 중단, 구현 완료 후 재실행 안내
- **test.md 미존재**: 해당 모듈만 skip + "/parallel-test로 먼저 생성" 안내
- **대응 소스 파일 없음**: 해당 모듈만 skip + 경고
- **배치 내 50% 이상 실패**: 다음 배치 진행 여부 사용자 확인
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
전체 모듈 TC 리뷰:
```
사용자: /parallel-test-review
스킬: 24개 모듈 탐색. src/ 매핑 완료.
      Step 01: AGT 15개 모듈 (병렬 실행)
      Step 02: SVR 9개 모듈 (병렬 실행)
      진행하시겠습니까?
사용자: 진행
스킬: Step 01 완료... 15/15
      Step 02 완료... 9/9
      TC 총계: 1058 (TEST 1040, REVIEW 18), 신규 추가 12개
```
</Good>

<Good>
AGT만 리뷰:
```
사용자: /parallel-test-review agt
스킬: AGT 15개 모듈 탐색. src/ 매핑 완료.
      Step 01: 15개 모듈 (병렬 실행)
      진행하시겠습니까?
```
</Good>

<Good>
TC 리뷰 + 추가 TC 구현:
```
사용자: /parallel-test-review --impl
스킬: 24개 모듈 탐색. src/ 매핑 완료.
      Step 01: AGT 15개 모듈 (병렬 실행)
      Step 02: SVR 9개 모듈 (병렬 실행)
      --impl 활성: 추가 TC의 테스트 코드를 test/에 생성합니다.
      진행하시겠습니까?
사용자: 진행
스킬: Step 01 완료... 15/15
      Step 02 완료... 9/9
      TC 총계: 1058 (TEST 1040, REVIEW 18), 신규 추가 12개
      테스트 코드 생성: 10개 파일, 12개 TC 구현
```
</Good>

<Bad>
소스 코드 없이 실행:
```
사용자: /parallel-test-review
스킬: src/ 디렉토리가 존재하지 않습니다.
      구현 완료 후 실행하세요. 중단합니다.
```
</Bad>

<Bad>
test.md 없이 실행:
```
# test.md가 없는 모듈은 skip 처리
# "먼저 /parallel-test로 test.md를 생성하세요" 안내
```
</Bad>

</Examples>

<Tool_Usage>
- **Glob 도구**: `doc/develop/**/test.md` 탐색, `src/**/*.cpp`, `src/**/*.java` 소스 파일 수집
- **Read 도구**: interface.md (공개 함수 목록), 소스 코드 (분기 분석), 기존 test.md
- **Bash 도구**: `.temp/` 디렉토리 생성
- **Write 도구**: `.temp/step-{NN}-test-review-batch.md` 생성
- **Edit 도구**: 워커가 기존 test.md에 검증 방법 컬럼 추가 시
- **AskUserQuestion**: 실행 확인, 덮어쓰기 확인
- **Skill 도구**: `/team N:deep-executor` 호출로 배치 내 병렬 실행
</Tool_Usage>

<Final_Checklist>
- [ ] `src/` 디렉토리 존재를 확인했는가?
- [ ] 각 모듈의 doc → src 경로 매핑이 올바른가?
- [ ] 워커 프롬프트에 test-design-guide.md 6.1절 기준이 포함되었는가?
- [ ] 워커 프롬프트에 소스 파일 경로가 포함되었는가?
- [ ] 기존 TC의 ID/시나리오/기대결과를 변경하지 않았는가?
- [ ] 검증 방법 컬럼(TEST/REVIEW)이 모든 TC에 마킹되었는가?
- [ ] REVIEW 대상이 6.1절 기준에 부합하는가? (재현 불가 시나리오만)
- [ ] 누락 분기에 대한 TC가 기존 번호 체계를 이어서 추가되었는가?
- [ ] "코드 리뷰 검증 대상" 요약 섹션이 test.md에 추가되었는가?
- [ ] 결과 보고에 TEST/REVIEW/신규 추가 수가 집계되었는가?
- [ ] `--impl` 시: 신규 TC 중 TEST 분류된 것에 대한 테스트 코드가 생성되었는가?
- [ ] `--impl` 시: 테스트 코드 위치가 module-mapping.md의 test 경로와 일치하는가?
- [ ] `--impl` 시: 생성된 테스트 코드가 Mock 금지 원칙을 준수하는가?
</Final_Checklist>
