---
name: full-verify
description: 전체 프로젝트를 대상으로 verification-guide.md 7단계 검증을 수행하는 스킬. "전체 검증", "최종 검증", "full verify", "빌드 검증", "배포 검증", "보안 검증", "문서 정합성", "검증 보고서" 등을 요청할 때 사용. src/, test/, doc/base/verification-guide.md가 존재하는 상태에서 반드시 이 스킬을 사용할 것.
---

<Purpose>
개발 워크플로우의 최종 단계(Step 8)로, 전체 프로젝트에 대해 verification-guide.md에 정의된 7단계 검증을 수행하고 종합 검증 보고서를 생성한다.

핵심 가치:
- 완전성: parallel-impl(Phase A)에서 모듈별로 부분 수행한 단계를 포함하여 전체 프로젝트 범위에서 재수행
- 추적성: requirement.md → interface.md → implementation.md → test.md 4-문서 정합성 확인
- 실행 증거: 빌드 결과, 테스트 실행 결과, 커버리지 수치 등 실제 증거 기반 보고
- 병렬화: 정적 분석 등 병렬 가능 단계는 /team N:deep-executor 활용
</Purpose>

<Use_When>
- parallel-test-review(Step 7) 완료 후 최종 검증이 필요할 때
- 전체 프로젝트 빌드 + 테스트 + 배포 + 보안 + 문서 정합성을 일괄 검증할 때
- 공식 검증 보고서(verification-report.md)가 필요할 때
- CI/CD 파이프라인의 게이트 체크로 활용할 때
</Use_When>

<Do_Not_Use_When>
- src/ 또는 플랫폼별 테스트 경로가 아직 없을 때 (구현 완료 후 실행)
- doc/base/verification-guide.md가 없을 때 (가이드 부재 시 중단)
- 단일 모듈만 검증할 때 (수동으로 verification-guide.md 참조)
- 빠른 빌드 확인만 필요할 때 (full-verify는 전체 7단계 수행)
</Do_Not_Use_When>

<Arguments>
인수 형식: `/full-verify [subsystem] [--skip-deploy] [--skip-security] [--report-path PATH]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt` 또는 `svr` — 특정 서브시스템만 대상 |
| --skip-deploy | false | 배포 검증(Step 6) 생략 — 개발 환경에서 VM 배포 불가 시 |
| --skip-security | false | 보안 검증(Step 7) 생략 |
| --security-requirements | (자동 로드) | 보안요구사항 활성화 — conf 파일이 없을 때 수동 활성화. 활성화 시 `doc/base/security-requirements/README.md` 참조 문서로 Step 7 추적성 검증 추가 |
| --no-security-requirements | false | 보안요구사항 자동 로드 해제 |
| --report-path PATH | `.temp/verification-report.md` | 검증 보고서 출력 경로 |
</Arguments>

<Steps>

## Step 0: 초기화

1. 필수 디렉토리/파일 존재 확인:
   - `src/` 디렉토리 — 없으면 "소스 코드가 없습니다. 구현 완료 후 실행하세요." 출력 후 중단
   - **플랫폼별 테스트 경로** 존재 확인:
     - C++: `test/` 디렉토리
     - Spring Boot: `src/test/` 디렉토리
     - Go/Rust: 소스 파일과 동일 디렉토리 내 `*_test.go` / `*_test.rs` 파일
     - 위 경로 중 하나라도 존재하면 통과. **모두 없으면** "테스트 코드가 없습니다. 구현 완료 후 실행하세요." 출력 후 중단
   - `doc/base/verification-guide.md` — 없으면 즉시 중단 ("검증 가이드가 없습니다.")
2. `.temp/` 디렉토리 확인 — 없으면 `mkdir -p .temp`
3. 기존 보고서 파일(`--report-path` 대상)이 있으면 사용자에게 덮어쓰기 여부 확인
4. 인수 파싱: subsystem, --skip-deploy, --skip-security, --report-path 확인
5. `--security-requirements` 또는 자동 로드 확인:
   a. `--no-security-requirements` 지정 시: 보안요구사항 추적성 검증 생략 (자동 로드 무시)
   b. `--security-requirements` 지정 시: 수동 활성화 (conf 파일 갱신하지 않음)
   c. 미지정 시: `doc/architecture/security-requirements.conf` 존재 확인 → 존재하면 자동 활성화
   d. 활성화 시: `doc/base/security-requirements/README.md`를 읽어 문서 목록을 `security_req_path` 변수에 로드
   e. 자동 로드된 경우 사용자에게 알림: "보안요구사항 자동 로드 (해제: --no-security-requirements)"

## Step 1: 검증 계획 수립

1. `doc/base/verification-guide.md`를 읽어 플랫폼별 검증 절차와 단계별 체크리스트를 파악한다.
2. `doc/base/verification-designs/` 디렉토리가 존재하면 플랫폼별 검증 문서를 탐색한다:
   ```
   Glob("doc/base/verification-designs/*.md")
   ```
   - AGT 대상: `cpp.md` 또는 `c-cpp.md` 등 C++ 관련 검증 문서
   - SVR 대상: `springboot.md` 또는 `java.md` 등 Spring Boot 관련 검증 문서
3. 모듈 목록 구축: `Glob("doc/develop/**/requirement.md")`로 모든 모듈 식별
   - subsystem 인수 지정 시 해당 서브시스템만 탐색
4. 각 모듈의 4개 문서 존재 여부 사전 확인:
   - `requirement.md`, `interface.md`, `implementation.md`, `test.md`
   - 누락 문서가 있는 모듈은 경고 목록에 추가
5. 검증 계획 요약 출력:
   ```
   === full-verify 검증 계획 ===

   대상: {subsystem 또는 전체}
   모듈 수: {N}개 (AGT: {n}개, SVR: {m}개)
   문서 누락 경고: {K}개 모듈

   수행 단계:
     [1] 정적 분석    — verification-guide.md 2절
     [2] 코드 리뷰    — verification-guide.md 3절 (REVIEW TC 포함)
     [3] 빌드 검증    — verification-guide.md 4절
     [4] 테스트 실행  — verification-guide.md 5절 (TEST TC 실행)
     [5] 배포 검증    — verification-guide.md 6절 {--skip-deploy 시: [SKIP]}
     [6] 보안 검증    — verification-guide.md 7절 {--skip-security 시: [SKIP]} {security_req_path 존재 시: [+보안요구사항 추적성: {security_req_path}]}
     [7] 문서 정합성  — verification-guide.md 8절

   보고서 출력 경로: {--report-path}

   진행하시겠습니까?
   ```

## Step 2: 정적 분석 (verification-guide.md 2절)

verification-guide.md 2절(정적 분석) 기준으로 전체 소스 코드를 분석한다.

**병렬화 가능**: 모듈별로 독립적이므로 `/team N:deep-executor` 활용

### 2.1 AGT (C++/CMake) 정적 분석

워커 프롬프트 구성:
```
다음 모듈의 소스 코드에 대해 정적 분석을 수행하라.

## 분석 기준
- 검증 가이드: `doc/base/verification-guide.md` (2절 정적 분석)
- 플랫폼 참조: `doc/base/verification-designs/{cpp 관련 문서}`
- 소스 경로: `src/agt/{category}/{module}/`

## 분석 항목
1. 컴파일러 경고 (warning level 최대, -Wall -Wextra)
2. 정적 분석 도구 결과 (verification-guide.md 2절 지정 도구 기준)
3. 코딩 규칙 위반 (doc/base/detailed-designs/cpp.md 기준)
4. 헤더 가드, include 순서, 네임스페이스 규칙

## 산출물
모듈별 정적 분석 결과:
- PASS: 위반 사항 없음
- FAIL: 위반 사항 목록 (파일:라인, 규칙, 설명)
```

### 2.2 SVR (Spring Boot/Java) 정적 분석

워커 프롬프트 구성 (AGT와 동일 구조, 플랫폼 도구 상이):
- CheckStyle, SpotBugs, PMD 등 verification-guide.md 2절 지정 도구 기준
- `src/svr/{module}/` 소스 대상

### 2.3 결과 집계

```
=== Step 2: 정적 분석 결과 ===
PASS: {N}개 모듈
FAIL: {M}개 모듈
  - {MODULE_ID}: {위반 건수}건 — {대표 위반 사항}
  ...
```

FAIL 모듈이 있어도 다음 단계로 진행한다 (보고서에 기록).

## Step 3: 코드 리뷰 (verification-guide.md 3절)

test.md의 REVIEW TC 항목을 코드 리뷰 방식으로 검증한다.

**병렬화 가능**: 모듈별로 독립적이므로 `/team N:deep-executor` 활용

### 3.1 REVIEW TC 수집

각 모듈의 `test.md`에서 REVIEW 마킹된 TC를 수집한다:
```
Grep pattern: "REVIEW" in "doc/develop/**/test.md"
```

### 3.2 워커 프롬프트 구성

```
다음 모듈의 REVIEW TC를 코드 리뷰 방식으로 검증하라.

## 입력
- 검증 가이드: `doc/base/verification-guide.md` (3절 코드 리뷰)
- 인터페이스: `{doc_path}/interface.md`
- 구현 설계: `{doc_path}/implementation.md`
- 테스트: `{doc_path}/test.md` (REVIEW TC 목록)
- 소스 코드: `src/{...}/{module}/`

## 검증 방법
각 REVIEW TC에 대해:
1. 해당 시나리오를 처리하는 소스 코드 블록을 식별한다.
2. 에러 처리 로직이 올바르게 구현되었는지 코드 리뷰로 확인한다.
3. verification-guide.md 3절의 체크리스트 항목을 적용한다.
4. 결과를 PASS/FAIL로 판정하고 근거를 기재한다.

## 산출물
REVIEW TC별 코드 리뷰 결과:
| TC ID | 시나리오 | 검토 코드 위치 | 판정 | 근거 |
|-------|---------|--------------|------|------|
```

### 3.3 결과 집계

```
=== Step 3: 코드 리뷰 결과 ===
REVIEW TC 총계: {N}개
PASS: {N}개
FAIL: {M}개
  - {TC_ID}: {실패 사유}
  ...
```

## Step 4: 빌드 검증 (verification-guide.md 4절)

클린 빌드를 수행하여 빌드 성공 여부를 확인한다.

**순차 실행 필수**: 빌드는 테스트 실행 전에 완료되어야 한다.

### 4.1 AGT 빌드 (CMake)

```bash
# verification-guide.md 4절 빌드 명령 기준으로 실행
# 예시 (실제 명령은 verification-guide.md 참조):
cd build && cmake --fresh .. && cmake --build . --config Release 2>&1
```

빌드 결과 확인:
- 빌드 성공: 경고 수, 에러 수 기록
- 빌드 실패: 에러 메시지 전체 기록 → 보고서에 포함, 다음 단계(테스트 실행) 건너뜀

### 4.2 SVR 빌드 (Gradle/Maven)

```bash
# verification-guide.md 4절 기준 빌드 명령
# 예시: ./gradlew clean build -x test 2>&1
```

### 4.3 결과 집계

```
=== Step 4: 빌드 검증 결과 ===
AGT 빌드: PASS (경고 {N}건) / FAIL (에러 {M}건)
SVR 빌드: PASS (경고 {N}건) / FAIL (에러 {M}건)
```

## Step 5: 테스트 실행 (verification-guide.md 5절)

test.md의 TEST TC를 실행하고 커버리지를 측정한다.

**선행 조건**: Step 4 빌드 성공한 서브시스템만 실행. 빌드 실패 서브시스템은 건너뜀.

### 5.1 AGT 테스트 실행

```bash
# verification-guide.md 5절 테스트 실행 명령 기준
# 예시: ctest --output-on-failure --test-dir build 2>&1
```

커버리지 측정:
```bash
# verification-guide.md 5절 커버리지 도구 기준 (gcov/lcov 등)
```

### 5.2 SVR 테스트 실행

```bash
# 예시: ./gradlew test jacocoTestReport 2>&1
```

### 5.3 TC 실행 결과 대조

각 모듈의 `test.md`에 있는 TEST TC 목록과 실제 실행 결과를 대조한다:
- TEST TC 총 N개 중 실행된 TC 수, PASS 수, FAIL 수 집계
- 커버리지: 라인/브랜치 커버리지 수치

### 5.4 결과 집계

```
=== Step 5: 테스트 실행 결과 ===
AGT: TEST TC {N}개 실행 — PASS {P}개, FAIL {F}개
     라인 커버리지: {L}%, 브랜치 커버리지: {B}%
SVR: TEST TC {M}개 실행 — PASS {P}개, FAIL {F}개
     라인 커버리지: {L}%, 브랜치 커버리지: {B}%
```

## Step 6: 배포 검증 (verification-guide.md 6절)

`--skip-deploy` 인수가 지정된 경우 이 단계를 건너뛴다.

실제 배포 환경(VM 등)에 배포하여 동작을 검증한다.

### 6.1 배포 준비

- verification-guide.md 6절의 배포 절차 확인
- 배포 환경 접근 가능 여부 확인 (VM, 테스트 서버 등)
- 배포 환경에 접근 불가능하면: "배포 환경에 접근할 수 없습니다. --skip-deploy 사용을 권장합니다." 출력 후 사용자에게 계속 진행 여부 확인

### 6.2 배포 실행 및 검증

verification-guide.md 6절 기준으로:
1. 빌드 아티팩트를 배포 환경에 배포
2. 서비스 기동 확인 (프로세스, 포트, 헬스체크)
3. 기본 연결 테스트 (통신 경로, 프로토콜 연결)
4. 배포 전/후 상태 비교

### 6.3 결과 집계

```
=== Step 6: 배포 검증 결과 ===
배포: PASS / FAIL / SKIP (--skip-deploy)
서비스 기동: PASS / FAIL
연결 테스트: PASS / FAIL
```

## Step 7: 보안 검증 (verification-guide.md 7절)

`--skip-security` 인수가 지정된 경우 이 단계를 건너뛴다.

### 7.1 소스 코드 보안 스캔

verification-guide.md 7절 지정 도구 기준으로 실행:
- 하드코딩된 시크릿/패스워드 스캔
- 알려진 취약점 패턴 (버퍼 오버플로우, 인젝션 등) 탐지
- 의존성 취약점 (CVE) 스캔

**병렬화 가능**: AGT/SVR 동시 실행

### 7.2 결과 집계

```
=== Step 7: 보안 검증 결과 ===
Critical: {N}건
High:     {M}건
Medium:   {K}건
Low:      {L}건
PASS 기준 (verification-guide.md 7절): Critical 0건, High 0건
판정: PASS / FAIL
```

### 7.3 보안요구사항 추적성 검증

`security_req_path`가 설정된 경우에만 수행한다. 미설정 시 이 하위 단계를 건너뛴다.

1. 보안요구사항 문서(`security_req_path`)를 읽어 모든 요구사항 ID를 추출한다
2. 각 보안요구사항 → 모듈 요구사항 ID 매핑을 확인한다
3. 매핑된 모듈의 `requirement.md`에 해당 ID가 존재하는지 확인한다
4. 매핑된 모듈의 `test.md`에 대응 TC가 존재하는지 확인한다

### 7.4 보안요구사항 결과 집계

```
=== Step 7 추가: 보안요구사항 추적성 ===
보안요구사항: {N}개 중 매핑 완료 {M}개, 누락 {K}개
TC 커버리지: 매핑된 {M}개 중 TC 존재 {P}개, TC 누락 {Q}개
```

## Step 8: 문서 정합성 (verification-guide.md 8절)

4개 문서(requirement.md, interface.md, implementation.md, test.md) 간 추적성과 정합성을 검증한다.

**병렬화 가능**: 모듈별로 독립적이므로 `/team N:deep-executor` 활용

### 8.1 워커 프롬프트 구성

```
다음 모듈의 4개 문서 간 정합성을 검증하라.

## 입력
- 검증 가이드: `doc/base/verification-guide.md` (8절 문서 정합성)
- requirement.md: `{doc_path}/requirement.md`
- interface.md:   `{doc_path}/interface.md`
- implementation.md: `{doc_path}/implementation.md`
- test.md:        `{doc_path}/test.md`

## 검증 항목 (4-문서 추적성)

1. **FR → TC 추적성**: requirement.md의 모든 FR이 test.md에서 최소 1개 TC에 매핑되는가?
2. **Interface → Implementation 정합성**: interface.md의 모든 공개 함수 시그니처가 implementation.md에 구현 상세가 기술되어 있는가?
3. **Implementation → Test 정합성**: implementation.md의 에러 처리 전략 모든 항목에 대응 TC가 있는가?
4. **Interface → Test 정합성**: interface.md의 모든 공개 함수가 test.md에서 최소 1개 단위 TC에 매핑되는가?
5. **단일 원천 원칙**: test.md 또는 implementation.md에서 타 모듈의 프로토콜 정의를 인라인 복사하지 않고 참조 경로를 사용하는가?

## 산출물

각 항목별 PASS/FAIL 판정 및 위반 목록:
| 항목 | 판정 | 위반 내용 |
|------|------|---------|
| FR → TC 추적성 | PASS/FAIL | FR-003에 대응 TC 없음 |
| ... | ... | ... |
```

### 8.2 결과 집계

```
=== Step 8: 문서 정합성 결과 ===
PASS: {N}개 모듈 (전체 정합)
FAIL: {M}개 모듈
  - {MODULE_ID}: FR→TC {K}건 누락, Interface→Test {L}건 누락
  ...
```

## Step 9: 검증 보고서 생성

모든 단계의 결과를 종합하여 검증 보고서를 생성한다.

보고서 경로: `--report-path` 인수 값 (기본: `.temp/verification-report.md`)

### 9.1 보고서 작성

```markdown
# 검증 보고서

> 생성: {YYYY-MM-DD HH:MM}
> 대상: {subsystem 또는 전체}
> 검증 기준: `doc/base/verification-guide.md`

## 요약

| 단계 | 결과 | 상세 |
|------|------|------|
| 1. 정적 분석 | PASS/FAIL | {N}개 모듈 FAIL, {M}건 위반 |
| 2. 코드 리뷰 | PASS/FAIL | REVIEW TC {N}개 중 {M}개 FAIL |
| 3. 빌드 검증 | PASS/FAIL | AGT {결과}, SVR {결과} |
| 4. 테스트 실행 | PASS/FAIL | TEST TC {N}개 — PASS {P}, FAIL {F} / 커버리지 {L}% |
| 5. 배포 검증 | PASS/FAIL/SKIP | {배포 환경 결과 또는 SKIP 사유} |
| 6. 보안 검증 | PASS/FAIL/SKIP | Critical {N}건, High {M}건 |
| 7. 문서 정합성 | PASS/FAIL | {N}개 모듈 FAIL |

**종합 판정**: PASS / FAIL / CONDITIONAL PASS

> CONDITIONAL PASS: 필수 단계(빌드, 테스트) PASS + 선택 단계 SKIP인 경우

## 상세 결과

### 1. 정적 분석

{Step 2에서 수집한 모듈별 위반 목록}

FAIL 모듈:
| 모듈 | 위반 건수 | 대표 위반 사항 |
|------|---------|--------------|
| {MODULE_ID} | {N}건 | {파일:라인 — 위반 내용} |

### 2. 코드 리뷰 (REVIEW TC)

{Step 3에서 수집한 REVIEW TC 검토 결과}

| TC ID | 모듈 | 시나리오 | 판정 | 근거 |
|-------|------|---------|------|------|
| {TC_ID} | {MODULE_ID} | {시나리오} | PASS/FAIL | {근거} |

### 3. 빌드 검증

**AGT 빌드**
- 결과: PASS/FAIL
- 경고: {N}건
- 에러: {M}건
{빌드 실패 시 에러 메시지}

**SVR 빌드**
{동일 구조}

### 4. 테스트 실행

**AGT 테스트**
- 실행: {N}개 TC
- PASS: {P}개
- FAIL: {F}개
- 라인 커버리지: {L}%
- 브랜치 커버리지: {B}%

FAIL TC 목록:
| TC ID | 모듈 | 실패 사유 |
|-------|------|---------|

**SVR 테스트**
{동일 구조}

### 5. 배포 검증

{SKIP인 경우: "생략됨 (--skip-deploy)"}
{수행한 경우: 배포 결과 상세}

### 6. 보안 검증

{SKIP인 경우: "생략됨 (--skip-security)"}
{수행한 경우:}
| 심각도 | 건수 | 대표 항목 |
|--------|------|---------|
| Critical | {N} | {설명} |
| High | {M} | {설명} |
| Medium | {K} | {설명} |
| Low | {L} | {설명} |

#### 보안요구사항 추적성

{security_req_path 미설정 시: "보안요구사항 추적성 검증 생략 (비활성화 상태)"}
{수행한 경우:}
| 요구사항 ID | 내용 | 구현 모듈 | requirement.md | test.md TC | 판정 |
|------------|------|---------|---------------|-----------|------|
| {SEC_ID} | {내용} | {MODULE_ID} | PASS/FAIL | PASS/FAIL | PASS/FAIL |

보안요구사항: {N}개 중 매핑 완료 {M}개, 누락 {K}개
TC 커버리지: 매핑된 {M}개 중 TC 존재 {P}개, TC 누락 {Q}개

### 7. 문서 정합성

| 모듈 | FR→TC | Interface→Impl | Impl→Test | Interface→Test | 단일원천 | 종합 |
|------|-------|---------------|-----------|---------------|---------|------|
| {MODULE_ID} | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL |

FAIL 상세:
{모듈별 위반 항목 목록}

## 조치 필요 항목

{종합 판정이 FAIL인 경우, 필수 조치 항목 목록}

| 우선순위 | 단계 | 모듈 | 조치 내용 |
|---------|------|------|---------|
| HIGH | 빌드 검증 | {MODULE} | {에러 메시지} |
| MEDIUM | 테스트 실행 | {MODULE} | {실패 TC 수정} |
| LOW | 정적 분석 | {MODULE} | {경고 해소} |
```

### 9.2 완료 출력

```
=== full-verify 완료 ===

보고서: {report_path}

단계별 요약:
  1. 정적 분석:  PASS/FAIL ({N}건 위반)
  2. 코드 리뷰:  PASS/FAIL ({M}개 REVIEW TC 중 {K}개 FAIL)
  3. 빌드 검증:  PASS/FAIL
  4. 테스트 실행: PASS/FAIL (PASS {P}/{N}, 커버리지 {L}%)
  5. 배포 검증:  PASS/FAIL/SKIP
  6. 보안 검증:  PASS/FAIL/SKIP
  7. 문서 정합성: PASS/FAIL ({M}개 모듈 정합성 위반)

종합 판정: PASS / FAIL / CONDITIONAL PASS
```

</Steps>

<Escalation_And_Stop_Conditions>
- **src/ 미존재**: 즉시 중단, 구현 완료 후 재실행 안내
- **플랫폼별 테스트 경로 전무**: 즉시 중단, 구현 완료 후 재실행 안내 (C++: `test/`, Spring Boot: `src/test/`, Go/Rust: 소스 동일 디렉토리)
- **verification-guide.md 미존재**: 즉시 중단
- **빌드 실패**: 해당 서브시스템의 테스트 실행(Step 5), 배포 검증(Step 6)을 건너뜀. 보고서에 FAIL 기록 후 나머지 단계 계속 진행.
- **배포 환경 접근 불가**: 사용자에게 --skip-deploy 권장 후 계속 진행 여부 확인
- **배치 내 50% 이상 워커 실패**: 다음 배치 진행 여부 사용자 확인
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
전체 프로젝트 검증:
```
사용자: /full-verify
스킬: src/, test/, verification-guide.md 확인 완료.
      모듈 24개 (AGT: 15개, SVR: 9개)
      7단계 검증 수행. 진행하시겠습니까?
사용자: 진행
스킬: Step 2 정적 분석 실행 중... /team 15:deep-executor (AGT) + /team 9:deep-executor (SVR)
      → 정적 분석: PASS 22개, FAIL 2개 (CORE: 3건, API: 1건)
      Step 3 코드 리뷰... REVIEW TC 18개 중 PASS 18개
      Step 4 빌드 검증... AGT PASS, SVR PASS
      Step 5 테스트 실행... TEST TC 1058개 — PASS 1055, FAIL 3 / 커버리지 87%
      Step 6 배포 검증... PASS
      Step 7 보안 검증... Critical 0건, High 0건
      Step 8 문서 정합성... PASS 23개, FAIL 1개
      보고서 생성: .temp/verification-report.md
      종합 판정: CONDITIONAL PASS
```
</Good>

<Good>
개발 환경 (배포/보안 생략):
```
사용자: /full-verify agt --skip-deploy --skip-security
스킬: AGT 15개 모듈 대상. 배포/보안 검증 생략.
      5단계 수행 (정적분석, 코드리뷰, 빌드, 테스트, 문서정합성).
      진행하시겠습니까?
```
</Good>

<Good>
보고서 경로 지정:
```
사용자: /full-verify --report-path doc/release/v1.0-verification.md
스킬: ... 검증 완료.
      보고서: doc/release/v1.0-verification.md
```
</Good>

<Bad>
소스 코드 없이 실행:
```
사용자: /full-verify
스킬: src/ 디렉토리가 존재하지 않습니다.
      구현 완료 후 실행하세요. 중단합니다.
```
</Bad>

<Bad>
verification-guide.md 없이 실행:
```
사용자: /full-verify
스킬: doc/base/verification-guide.md가 없습니다.
      검증 가이드를 먼저 준비하세요. 중단합니다.
```
</Bad>

<Bad>
빌드 실패 시 테스트를 강제 실행:
```
# AGT 빌드가 실패했는데 AGT 테스트를 실행하려는 시도
# → 빌드 실패 서브시스템은 테스트를 건너뛰고 보고서에 FAIL 기록
```
</Bad>

</Examples>

<Tool_Usage>
- **Glob 도구**: `doc/develop/**/requirement.md` 모듈 탐색, `doc/base/verification-designs/*.md` 플랫폼 검증 문서 탐색
- **Read 도구**: `doc/base/verification-guide.md` 단계별 기준 파악, 각 모듈의 4개 문서 읽기
- **Grep 도구**: test.md에서 REVIEW TC 항목 수집, FR/Interface→TC 매핑 누락 탐지
- **Bash 도구**: `.temp/` 디렉토리 생성, 빌드/테스트/커버리지 명령 실행
- **Write 도구**: 검증 보고서(`--report-path`) 생성
- **AskUserQuestion**: 실행 확인, 보고서 덮어쓰기 확인, 배포 환경 접근 불가 시 계속 진행 여부
- **Skill 도구**: `/team N:deep-executor` 호출로 정적 분석(Step 2), 코드 리뷰(Step 3), 문서 정합성(Step 8) 병렬 실행
</Tool_Usage>

<Final_Checklist>
- [ ] `src/`, `test/`, `doc/base/verification-guide.md` 세 가지 모두 존재를 확인했는가?
- [ ] verification-guide.md를 읽어 플랫폼별 도구/명령/기준을 파악했는가?
- [ ] 정적 분석(Step 2)에 병렬 실행을 활용했는가?
- [ ] 코드 리뷰(Step 3)가 test.md의 REVIEW TC를 빠짐없이 검증했는가?
- [ ] 빌드 실패 서브시스템의 테스트 실행을 건너뛰었는가?
- [ ] 테스트 실행(Step 5)에 커버리지 수치가 포함되었는가?
- [ ] --skip-deploy 시 Step 6을 건너뛰었는가?
- [ ] --skip-security 시 Step 7을 건너뛰었는가?
- [ ] 문서 정합성(Step 8)이 4-문서 추적성 5개 항목을 모두 검증했는가?
- [ ] 보고서에 단계별 PASS/FAIL 판정과 상세 위반 목록이 포함되었는가?
- [ ] 종합 판정(PASS/FAIL/CONDITIONAL PASS)이 보고서와 완료 출력 모두에 포함되었는가?
- [ ] 조치 필요 항목이 우선순위별로 정리되었는가?
- [ ] (`--security-requirements` 시) 보안요구사항 전체가 모듈 요구사항에 매핑되었는가?
- [ ] (`--security-requirements` 시) 매핑된 요구사항에 대응 TC가 존재하는가?
</Final_Checklist>
