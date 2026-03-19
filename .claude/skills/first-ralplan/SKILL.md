---
name: first-ralplan
description: Improved consensus planning with dedicated design phase — Analyst, Architect, Planner, Critic pipeline with differentiated iteration targets
---

<Purpose>
my-ralplan은 ralplan(plan --consensus)의 구조적 문제를 해결한 개선 버전이다. 핵심 개선: 설계 단계를 Architect에게 분리하여 Planner 과부하를 해소하고, Critic 판정을 3단계(APPROVE/ITERATE/REJECT)로 세분화하여 문제 유형별 최적 복귀 지점을 제공한다.

워크플로우: Analyst(요구사항) → Architect(설계) → Planner(실행계획) → Critic(검증)
</Purpose>

<Use_When>
- 고위험/대규모 프로젝트에서 설계와 계획을 분리하고 싶을 때
- 아키텍처 결정이 중요하여 Architect의 전문적 설계가 필요할 때
- 기존 ralplan에서 Planner 산출물이 너무 비대해지는 문제를 겪었을 때
- 요구사항/설계/계획 각각의 독립 산출물이 필요할 때
- `--interactive` 플래그로 각 단계 사이에 사용자 확인을 받고 싶을 때
</Use_When>

<Do_Not_Use_When>
- 단순하거나 명확한 태스크 — 바로 `/ralph` 또는 executor로 실행
- 빠른 계획만 필요할 때 — `/plan --direct` 사용
- 코드 리뷰나 기존 계획 검토만 필요할 때 — `/review` 사용
- 설계 없이 간단한 실행 계획만 필요할 때 — `/plan --consensus` (기존 ralplan) 사용
</Do_Not_Use_When>

<Why_This_Exists>
기존 ralplan에서 Planner가 요구사항 분석 + 아키텍처 설계 + 실행 계획을 모두 수행하여 과부하가 발생했다. Architect는 READ-ONLY 제약으로 설계를 생성할 수 없어 사후 리뷰만 수행했다. 이 구조에서는:

1. Planner가 본래 역할(3-6 step 계획)을 넘어 1700줄짜리 문서를 생성
2. Architect의 아키텍처 전문성이 설계 단계에서 활용되지 못함
3. Critic REJECT 시 문제 유형에 관계없이 Planner가 모든 것을 재처리

my-ralplan은 설계 단계를 Architect에게 분리하고, Critic 판정을 세분화하여 이 문제들을 해결한다.
</Why_This_Exists>

<Execution_Policy>
- Consensus 루프 최대 5회 반복 (5회 초과 시 최선 버전을 사용자에게 제시)
- 각 에이전트는 본래 역할만 수행 (Analyst=요구사항, Architect=설계, Planner=계획, Critic=검증)
- Architect가 설계 결과를 `doc/designs/`에 직접 저장 (Write 권한 부여)
- `doc/base/system-design-guide.md`가 존재하면 Architect에게 설계 원칙으로 전달 (모듈 분리, 인터페이스 유형, 프로토콜 소유권, 요구사항 ID 체계 등)
- `--interactive` 플래그 사용 시 각 단계 후 사용자 확인 (기본값: 비대화식)
- `--security-requirements` 지정 시 `doc/base/security-requirements/README.md`에 참조된 보안요구사항을 설계 입력에 포함하고 `doc/architecture/security-requirements.conf`에 활성화 기록
- `doc/architecture/security-requirements.conf` 존재 시 자동으로 보안요구사항 포함 (--no-security-requirements로 해제 가능)
- 최종 APPROVE 후 반드시 Plan Mode 진입하여 사용자 승인 획득
</Execution_Policy>

<Steps>

## 0. 초기화

1. 사용자 입력에서 태스크 이름(`{name}`) 추출 (kebab-case 변환)
2. `doc/designs/` 및 `.omc/plans/` 디렉토리 존재 확인 및 생성
3. `--interactive` 플래그 확인
4. `--security-requirements` 또는 자동 로드 확인:
   a. `--no-security-requirements` 지정 시: 보안요구사항 검증 생략 (자동 로드 무시)
   b. `--security-requirements` 지정 시: `doc/architecture/security-requirements.conf`에 `enabled` 기록
   c. 미지정 시: `doc/architecture/security-requirements.conf` 존재 확인 → 존재하면 자동 활성화
   d. 활성화 시: `doc/base/security-requirements/README.md`를 읽어 문서 목록을 `security_docs` 변수에 로드
   e. 자동 로드된 경우 사용자에게 알림: "보안요구사항 자동 로드 (해제: --no-security-requirements)"
5. 설계 가이드 탐색: `doc/base/system-design-guide.md` 존재 여부 확인
   - 존재하면 `design_guide_path` 변수에 경로 저장 (Architect에게 전달)
6. 반복 카운터 초기화: `iteration = 0`, `max_iterations = 5`

## 1. Analyst 단계 (요구사항 분석)

**에이전트**: `oh-my-claudecode:analyst` (Opus, READ-ONLY)

**프롬프트 구성**:
```
다음 태스크에 대한 요구사항 분석을 수행하라:

## 사용자 요청
{user_request}

## 지시사항
1. 요구사항 갭 분석 수행
2. 숨은 요구사항 발굴
3. 엣지케이스, 리스크, 가드레일 도출
4. 결과를 텍스트로 출력하라 (파일 저장하지 말 것)

{--security-requirements 활성화 시 추가:}
## 보안요구사항
`doc/base/security-requirements/README.md`를 읽고, 참조된 보안요구사항 문서를 모두 읽어 분석에 반영하라.

5. 보안요구사항의 모듈 매핑 커버리지를 검증하라
6. 보안요구사항 중 기능 요구사항에 반영되지 않은 항목을 식별하라

{이전 REJECT 피드백이 있으면 포함}
```

**오케스트레이터 처리**:
- Analyst의 텍스트 출력을 `analyst_report` 변수에 저장
- `--interactive` 모드면 `AskUserQuestion`으로 사용자 확인:
  - "Analyst 분석 결과를 확인하세요. 진행할까요?"
  - 옵션: "진행" / "피드백 추가" / "중단"

## 2. Architect 단계 (시스템 설계)

**에이전트**: `system-designer` (Opus, Write 권한 있음)

**핵심 메커니즘**: Architect가 설계 결과를 `doc/designs/{name}.md`에 직접 저장한다. 출력이 클 경우 텍스트 전달 시 짤리는 문제를 방지한다.

**프롬프트 구성**:
```
다음 요구사항 분석 결과를 바탕으로 시스템 설계를 수행하라:

## 사용자 요청
{user_request}

## Analyst 분석 결과
{analyst_report}

{design_guide_path가 존재하면:}
## 설계 가이드
다음 설계 가이드를 먼저 읽고, 그 원칙에 따라 설계하라: {design_guide_path}

준수해야 할 핵심 원칙:
- **모듈 분리**: 독립운영시스템 식별(1절) → 빌드 모듈 분리(2절) 순서로 진행
- **Shell/Core 분리**: 실행 파일은 Shell(OS 인터페이스)과 Core(비즈니스 로직)를 별도 모듈로 분리 (2.1.1절)
- **인터페이스 유형별 정의**: 2.2절 유형표에 따라 인터페이스별 필수 정의 항목을 빠짐없이 기술
- **프로토콜 소유권**: 공유 프로토콜은 주체 모듈에만 정의, 소비자는 참조로 가리킴 (2.3절)
- **요구사항 ID 체계**: {시스템}.{모듈코드}-{유형}-{번호} 형식 (3.2절)
- **설계서 템플릿**: 5절 구조(시스템 개요 → 기술 스택 → 모듈 구성 → 모듈별 요구사항+인터페이스 → 시스템 간 계약 → Data Flow → NFR)를 따름

## 지시사항
1. 컴포넌트 구조 설계 (설계 가이드의 모듈 분리 원칙 적용)
2. 인터페이스 정의 (설계 가이드 2.2절 유형별 필수 항목 포함)
3. 의존성 및 데이터 흐름 설계
4. 기술적 결정 사항과 trade-off 문서화
5. 코드베이스의 기존 패턴을 조사하여 일관성 유지
6. 결과를 `doc/designs/{name}.md`에 Write 도구로 직접 저장하라

{--security-requirements 활성화 시 추가:}
## 보안요구사항
`doc/base/security-requirements/README.md`를 읽고, 참조된 보안요구사항 문서를 모두 읽어 설계에 반영하라.

7. 각 보안요구사항이 어느 모듈에서 구현되는지 추적 매트릭스를 설계서에 포함하라
8. NFR 절에 보안 비기능 요구사항(암호화, 인증, 감사기록 등)을 정량 기준과 함께 명시하라

{이전 ITERATE 피드백이 있으면 포함}
```

**오케스트레이터 처리**:
- Architect가 `doc/designs/{name}.md`에 직접 저장 (Write 권한 있음)
- 오케스트레이터는 파일 존재 여부만 확인
- `--interactive` 모드면 `AskUserQuestion`으로 사용자 확인:
  - "Architect 설계 결과를 확인하세요. 진행할까요?"
  - 옵션: "진행" / "피드백 추가" / "중단"

## 3. Planner 단계 (실행 계획)

**에이전트**: `oh-my-claudecode:planner` (Opus, READ+WRITE)

**프롬프트 구성**:
```
다음 설계 문서를 기반으로 실행 계획을 수립하라:

## 사용자 요청
{user_request}

## 설계 문서
{doc/designs/{name}.md 내용 또는 경로}

## Analyst 분석 결과
{analyst_report}

## 지시사항
1. 설계 문서에 정의된 구조를 그대로 따르라 (재설계 금지)
2. 3-6 step 실행 계획 수립
3. 각 step에 명확한 acceptance criteria 포함
4. 순서, 의존성, 검증 방법 명시
5. 계획을 `.omc/plans/{name}.md`에 저장

중요: 아키텍처 설계는 이미 완료되었다.
설계를 변경하지 말고, 설계를 실행 가능한 단계로 분해하는 것에 집중하라.
```

**오케스트레이터 처리**:
- Planner가 `.omc/plans/{name}.md`에 직접 저장 (Write 권한 있음)
- `--interactive` 모드면 `AskUserQuestion`으로 사용자 확인

## 4. Critic 단계 (설계 + 계획 검증)

**에이전트**: `oh-my-claudecode:critic` (Opus, READ-ONLY)

**프롬프트 구성**:
```
다음 설계와 실행 계획의 정합성을 검증하라:

## 설계 문서
{doc/designs/{name}.md 경로}

## 실행 계획
{.omc/plans/{name}.md 경로}

## Analyst 분석 결과
{analyst_report}

## 검증 기준
1. **Clarity**: 실행자가 추측 없이 진행 가능한가? (80%+ 주장이 file:line 참조)
2. **Verification**: 각 태스크에 검증 가능한 acceptance criteria가 있는가? (90%+ 구체적)
3. **Completeness**: 필요한 컨텍스트의 90%+ 가 제공되는가?
4. **Big Picture**: 실행자가 태스크 간 연관성과 이유를 이해하는가?
5. **Design-Plan Coherence**: 계획이 설계를 정확히 반영하는가? 설계에 없는 것을 추가하거나, 설계에 있는 것을 누락하지 않았는가?
6. **Design Guide Compliance** (설계 가이드 존재 시): 설계가 system-design-guide.md 원칙을 준수하는가? (Shell/Core 분리, 인터페이스 유형별 정의 항목, 프로토콜 소유권, 요구사항 ID 체계)

{--security-requirements 활성화 시 추가:}
7. **Security Coverage**: 보안요구사항이 빠짐없이 모듈에 매핑되었는가? 추적 매트릭스에 누락 항목이 없는가?

## 판정 기준
- **APPROVE**: 설계-계획 정합성이 높고, 4가지 기준 모두 충족
- **ITERATE**: 설계 수정이 필요한 문제 발견 (Architect로 복귀)
  - 설계-계획 불일치, 아키텍처 결함, 인터페이스 누락 등
- **REJECT**: 요구사항 수준의 문제 발견 (Analyst로 복귀)
  - 요구사항 누락, 스코프 불명확, 근본적 방향 오류 등

판정과 함께 구체적 피드백을 제공하라.
```

**오케스트레이터 처리**:

판정에 따른 분기:

```
APPROVE:
  → Plan Mode 진입
  → 사용자에게 설계 + 계획 요약 표시
  → 사용자 승인/수정/거부 선택

ITERATE:
  → iteration += 1
  → iteration > max_iterations이면 최선 버전으로 APPROVE 처리
  → Critic 피드백을 Architect에게 전달하여 2단계(Architect)로 복귀
  → Architect 설계 수정 → Planner 계획 갱신 → Critic 재검증

REJECT:
  → iteration += 1
  → iteration > max_iterations이면 최선 버전으로 APPROVE 처리
  → Critic 피드백을 Analyst에게 전달하여 1단계(Analyst)로 복귀
  → 전체 파이프라인 재실행
```

</Steps>

<Tool_Usage>
- **Task 도구**: 각 에이전트를 `subagent_type` 파라미터로 호출
  - `subagent_type="oh-my-claudecode:analyst"` — 1단계
  - `subagent_type="system-designer"` — 2단계
  - `subagent_type="oh-my-claudecode:planner"` — 3단계
  - `subagent_type="oh-my-claudecode:critic"` — 4단계
- **Write 도구**: Architect가 `doc/designs/{name}.md`에 직접 저장 (Architect에 Write 권한 부여됨)
- **Read 도구**: 이전 단계 산출물 읽기 (설계 문서, 계획 문서)
- **AskUserQuestion**: `--interactive` 모드에서 각 단계 후 사용자 확인
- **EnterPlanMode**: 최종 APPROVE 후 사용자 승인 흐름 진입
</Tool_Usage>

<Examples>

<Good>
설계와 계획이 분리된 워크플로우:
```
[1단계] Analyst: "사용자 삭제 기능에 soft/hard delete 구분이 없고,
         cascade 정책이 미정의입니다. 3개 gap 발견."

[2단계] Architect: "soft delete 방식 채택. users 테이블에 deleted_at 컬럼 추가.
         관련 posts는 orphan 처리. 인터페이스: deleteUser(id, soft=true)"
         → doc/designs/user-deletion.md에 직접 저장

[3단계] Planner: "Step 1: DB 마이그레이션 (deleted_at 컬럼 추가)
         Step 2: deleteUser API 구현 (설계 문서 인터페이스 참조)
         Step 3: cascade 처리 구현 ... 총 4단계"
         → .omc/plans/user-deletion.md에 저장

[4단계] Critic: "APPROVE — 설계-계획 정합성 확인. 모든 인터페이스가
         계획에 반영됨. Acceptance criteria 구체적."
```
Planner가 설계를 하지 않고 실행 계획에만 집중. 산출물이 분리되어 참조 용이.
</Good>

<Good>
ITERATE로 설계 수정:
```
[4단계] Critic: "ITERATE — 설계에서 deleteUser의 에러 핸들링이 미정의.
         404 Not Found와 409 Conflict 케이스 추가 필요."
         → Architect로 복귀

[2단계 재실행] Architect: 에러 핸들링 추가한 설계 수정본
         → doc/designs/user-deletion.md에 직접 갱신

[3단계 재실행] Planner: 수정된 설계 반영하여 계획 갱신

[4단계 재실행] Critic: "APPROVE"
```
설계 문제는 Architect가 수정. Planner는 계획만 갱신. 효율적 반복.
</Good>

<Bad>
Planner가 설계까지 수행:
```
[3단계] Planner: "Step 1: 컴포넌트 구조 설계..."
```
설계는 Architect의 역할이다. Planner는 이미 완성된 설계를 실행 단계로 분해해야 한다. 설계 문서에 없는 구조를 계획에 추가하지 말 것.
</Bad>

<Bad>
ITERATE인데 Analyst로 복귀:
```
[4단계] Critic: "ITERATE — 인터페이스 정의 부족"
         → Analyst로 복귀 (잘못됨!)
```
인터페이스 문제는 설계(Architect) 문제이므로 Architect로 복귀해야 한다. REJECT(요구사항 문제)만 Analyst로 복귀.
</Bad>

</Examples>

<Escalation_And_Stop_Conditions>
- 5회 반복 후에도 APPROVE되지 않으면, 최선 버전을 사용자에게 제시하고 수동 결정 요청
- 사용자가 "중단", "취소"를 말하면 즉시 중단
- 사용자가 "건너뛰기"를 말하면 해당 단계를 최소 실행으로 진행
- `--interactive` 모드에서 사용자가 특정 단계를 반복 거부하면 해당 단계 결과를 수용하고 진행
</Escalation_And_Stop_Conditions>

<Final_Checklist>
- [ ] Analyst가 독립 1단계로 실행되었는가?
- [ ] Architect가 설계 문서를 `doc/designs/`에 직접 저장했는가?
- [ ] `doc/base/system-design-guide.md` 존재 시, Architect가 설계 원칙(모듈 분리, Shell/Core, 인터페이스 유형, 프로토콜 소유권)을 준수했는가?
- [ ] Planner가 설계를 변경하지 않고 실행 계획만 수립했는가?
- [ ] 실행 계획이 3-6 step이며 각 step에 acceptance criteria가 있는가?
- [ ] Critic이 설계-계획 정합성을 검증했는가?
- [ ] ITERATE 시 Architect로, REJECT 시 Analyst로 복귀하는가?
- [ ] 최대 5회 반복 제한이 적용되는가?
- [ ] 최종 APPROVE 후 사용자 승인을 받았는가?
- [ ] 산출물이 `doc/designs/{name}.md`와 `.omc/plans/{name}.md`에 저장되었는가?
- [ ] (`--security-requirements` 시) 보안요구사항 추적 매트릭스가 설계서에 포함되었는가?
- [ ] (`--security-requirements` 시) 보안 NFR이 정량 기준과 함께 명시되었는가?
- [ ] (`--security-requirements` 지정 시) `doc/architecture/security-requirements.conf`에 활성화가 기록되었는가?
</Final_Checklist>
