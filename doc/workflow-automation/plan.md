# Workflow 자동화 — 스텝별 독립 세션 + 라이브 포인터 + DB 동기화

## Context

`doc/base/workflow/dev-workflow-8step.md` 의 8단계 워크플로우는 연속 실행 시 컨텍스트 폭발 위험이 있어, **스텝 하나 = claude-code 명령 하나 = 세션 하나** 로 독립 실행한다. 상태는 두 곳에 기록하되 역할이 다르다:

- `sessions.json` = **현재 진행 중인 스텝 하나**만 담는 라이브 포인터(빠른 조회).
- `workflow.db` (SQLite) = **히스토리·병렬 태스크**의 단일 원천(외부 가시성, 쿼리 가능).

두 파일은 같은 트랜잭션에서 동기화한다.

## 핵심 설계

- **세션 ID 선지정**: 스크립트가 UUID 를 생성 → `claude --session-id <uuid>` 로 주입. 세션 시작 후 ID 를 긁어오는 경로 불필요.
- **PID 직접 획득**: `subprocess.Popen().pid` 로 스크립트가 즉시 획득.
- **`running` 마킹**: 스크립트가 spawn 시점에 DB/sessions.json 에 직접 기록.
- **완료 시그널**: `Stop` hook 이 파일 시그널 생성 → 오케스트레이터가 감지하고 자식 SIGTERM.
- **rate limit/에러**: `StopFailure` hook + matcher 로 정확히 구분.

## 워크플로우 식별 키

- **키 이름**: `run_id`
- **포맷**: `YYYY-MM-DD-NN` (같은 날 N번째 run). `--name foo` 지정 시 `YYYY-MM-DD-foo` 접미.
- **전파**:
  - DB: `workflow_runs.run_id` (PK), `steps.run_id`, `tasks.run_id` FK
  - sessions.json: `"run_id"` 필드
  - env var: `WORKFLOW_RUN_ID`, `WORKFLOW_STEP_NO` (자식 claude-code 프로세스에 주입)
  - hook: stdin JSON 에는 session_id 만 오므로, hook 핸들러는 env var 로 run/step 식별
- **활성 판정**: sessions.json 존재 유무 = 활성 여부. 동시 다중 run 미지원(필요 시 `sessions.d/{run_id}.json` 확장).

## 상태 파일

### 1. `.workflow-state/sessions.json` — 현재 스텝 포인터

```json
{
  "run_id": "2026-04-15-01",
  "step_no": 2,
  "skill": "project-scaffold",
  "status": "running",
  "session_id": "def45678-90ab-cdef-1234-567890abcdef",
  "pid": 23456,
  "started_at": "2026-04-15T10:42:00+09:00"
}
```

- 배열/히스토리 없음. 단일 활성 스텝 정보만.
- 스텝 완료 시 다음 스텝 값으로 덮어쓰기.
- `status`: `running | waiting | done | failed | rate_limited`.

### 2. `.workflow-state/workflow.db` (SQLite)

```sql
CREATE TABLE workflow_runs (
  run_id       TEXT PRIMARY KEY,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL,
  status       TEXT NOT NULL,      -- init|running|done|failed|abandoned
  note         TEXT
);

CREATE TABLE steps (
  run_id       TEXT NOT NULL REFERENCES workflow_runs(run_id),
  step_no      INTEGER NOT NULL,
  skill        TEXT NOT NULL,
  status       TEXT NOT NULL,      -- pending|running|done|failed|rate_limited
  session_id   TEXT,               -- UUID, 스크립트가 선지정
  pid          INTEGER,
  started_at   TEXT,
  ended_at     TEXT,
  PRIMARY KEY (run_id, step_no)
);

-- 병렬 태스크 (Step 4~8 모듈 단위)
CREATE TABLE tasks (
  id            INTEGER PRIMARY KEY,
  run_id        TEXT NOT NULL,
  step_no       INTEGER NOT NULL,
  key           TEXT NOT NULL,
  status        TEXT NOT NULL,       -- pending|running|done|failed
  worker_label  TEXT,
  started_at    TEXT,
  ended_at      TEXT,
  artifact_path TEXT,
  UNIQUE (run_id, step_no, key)
);

CREATE TABLE task_deps (
  task_id    INTEGER NOT NULL REFERENCES tasks(id),
  depends_on INTEGER NOT NULL REFERENCES tasks(id),
  PRIMARY KEY (task_id, depends_on)
);

CREATE TABLE events (
  id       INTEGER PRIMARY KEY,
  run_id   TEXT,
  step_no  INTEGER,
  task_id  INTEGER,
  ts       TEXT NOT NULL,
  level    TEXT,
  message  TEXT
);
```

### 동기화 규칙

| 액션 | 주체 | sessions.json | workflow.db |
|---|---|---|---|
| `workflow start` | 스크립트 | 삭제 | `workflow_runs` insert, `steps` 9개 `pending` |
| `workflow run --step N` spawn | 스크립트 | UUID 생성, 전체 오브젝트 덮어쓰기 | `UPDATE steps SET status='running', session_id=?, pid=?, started_at=?` |
| 스텝 완료 (스킬 내부) | 스킬 | (변경 없음) | `UPDATE steps SET status='done', ended_at=?` |
| Stop hook | hook | `status=done` 반영 | signal 파일 생성 |
| StopFailure hook | hook | `status=failed` / `rate_limited` | `events` insert + signal 파일 `.failed.{matcher}` |
| SessionEnd hook | hook | 정리 또는 유지 | `events` insert (종료 사유) |
| 자식 PID 종료 | 오케스트레이터 | (변경 없음) | `events` insert ("killed") |
| PID 사망 감지 (watch) | 스크립트 | `status=failed` | UPDATE + `events` |

## 스텝 실행 흐름

```
사용자: workflow.py run --step 2
  │
  ▼
[workflow.py = 오케스트레이터]
  1) DB steps 조회 → step 2 상태 확인
  2) 분기:
     - status=done                  → "이미 완료" 출력 종료
     - status=running
         · pid 살아있음             → "진행 중" 차단
         · pid 죽음                 → resume 분기
     - status=pending/failed        → 새 세션 분기
     - status=rate_limited          → 사용자 의도적 재시도 → resume 분기
  3) 새 세션 분기:
     - uuid.uuid4() 로 session_id 생성
     - subprocess.Popen([
         "claude", "--session-id", str(sid),
         "--prompt", "<스킬 호출 프롬프트>",
         ...
       ], env={WORKFLOW_RUN_ID, WORKFLOW_STEP_NO, ...})
     - child.pid 획득 즉시 sessions.json + DB UPDATE (status=running)
  4) resume 분기:
     - subprocess.Popen(["claude", "--resume", <session_id>, "--prompt", "계속 진행"])
  5) 대기 루프:
     - 시그널 파일 감지 → 자식 SIGTERM → .wait() → 다음 스텝 안내
     - 시그널 없이 자식 자연 종료 → events 에 unexpected_exit
```

## Hook 계층 (공식 hook 26종 중 사용)

| 이벤트 | Hook | matcher | 동작 |
|---|---|---|---|
| 정상 턴 종료 | `Stop` | — | 스킬이 DB `status=done` 선마킹한 경우에만 signal 파일 `{run_id}-{step_no}.done` 생성 |
| API 에러 (rate limit 포함) | **`StopFailure`** | `rate_limit`, `authentication_failed`, `billing_error`, `server_error`, `max_output_tokens` 등 | matcher 값을 `events.message` 기록 + signal 파일 `.failed.{matcher}`. `rate_limit` 은 `steps.status=rate_limited` |
| 세션 종료 | `SessionEnd` | `prompt_input_exit`, `logout`, `other` 등 | sessions.json 정리, DB 종료 사유 기록 |
| idle 감지 | `Notification` | `idle_prompt`, `permission_prompt` | events 에 `waiting` 기록 |
| 서브에이전트 완료 (옵션) | `SubagentStop` | agent_type | Step 4~8 의 tasks 자동 마킹 |
| 세션 시작 검증 (옵션) | `SessionStart` | `startup`, `resume` | UUID/PID 일치 검증용. 기록은 이미 스크립트가 완료 |

### `.claude/settings.json` 추가

```json
{
  "hooks": {
    "Stop":          [{"hooks":[{"type":"command","command":"python tools/workflow.py hook stop"}]}],
    "StopFailure":   [{"hooks":[{"type":"command","command":"python tools/workflow.py hook stop-failure"}]}],
    "SessionEnd":    [{"hooks":[{"type":"command","command":"python tools/workflow.py hook session-end"}]}],
    "Notification":  [{"hooks":[{"type":"command","command":"python tools/workflow.py hook notify"}]}],
    "SubagentStop":  [{"hooks":[{"type":"command","command":"python tools/workflow.py hook subagent-stop"}]}]
  }
}
```

## CLI (`tools/workflow.py`)

| 명령 | 동작 |
|---|---|
| `workflow start [--name foo]` | 새 run_id 생성, DB 초기화, sessions.json 삭제 |
| `workflow run --step N` | UUID 생성 → claude-code spawn(`--session-id`) → 시그널 대기 → SIGTERM → 다음 스텝 안내 |
| `workflow status` | DB 스텝 표 + 현재 sessions.json 포인터 출력 |
| `workflow watch` | PID 폴링, 죽은 running 스텝을 `failed` 마킹 |
| `workflow hook {stop\|stop-failure\|session-end\|notify\|subagent-stop}` | hook 엔드포인트 |

## 폴더/파일

- 신규 `doc/workflow-automation/README.md` — 사용자 가이드
- 신규 `doc/workflow-automation/state-spec.md` — 필드 명세, 상태 전이도
- 신규 `doc/workflow-automation/schema.sql`
- 신규 `doc/workflow-automation/hook-poc-findings.md` (Phase 0 산출물)
- 신규 `tools/workflow.py`
- 신규 `tools/hook_probe.py` (Phase 0)
- 수정 `.claude/settings.json`
- 수정 `.gitignore` — `.workflow-state/`

## 구현 순서

### Phase 0 — Hook PoC (**본 구현 전 필수**)

공식 문서 기반 설계를 실제 동작으로 검증. 문서-실동작 불일치 시 설계 수정 비용 조기 흡수.

1. `tools/hook_probe.py` — stdin JSON + env var 를 타임스탬프와 함께 `.workflow-state/hook-probe.log` 에 append.
2. `.claude/settings.json` 에 5개 hook(`Stop`, `StopFailure`, `SessionEnd`, `Notification`, `SubagentStop`) 을 probe 로 연결.
3. 검증 시나리오:
   - 정상 세션: claude-code 1회 대화 → `Stop` 로그 (stdin JSON 스키마 현행화).
   - `--session-id <uuid>` 플래그로 지정한 UUID 가 stdin JSON `session_id` 와 일치하는지.
   - `/exit` / 입력 종료 → `SessionEnd` 가 `prompt_input_exit` matcher 로 찍히는지.
   - 서브에이전트 호출 → `SubagentStop` 이 `agent_type` 과 함께 찍히는지.
   - 장시간 입력 대기 → `Notification` 이 `idle_prompt` 로 찍히는지.
   - StopFailure: `authentication_failed` 를 가짜 키로 유도해 matcher/스키마 확인(rate_limit 은 재현 어려움).
4. env var `WORKFLOW_RUN_ID` / `WORKFLOW_STEP_NO` 가 hook 프로세스에 제대로 전파되는지 확인.
5. 결과를 `hook-poc-findings.md` 로 정리. 설계와 차이 나는 부분 반영.

→ PoC 통과 후 Phase 1.

### Phase 1 — 본 구현

- `schema.sql` / DB 초기화
- `tools/workflow.py` (start / run / status / watch / hook subcommands)
- `.claude/settings.json` 정식 등록
- `.gitignore` 업데이트

### Phase 2 — 스킬 연계

- 각 스킬(`first-ralplan` ~ `full-verify`) 종료 시점에 DB `status=done` 마킹 규약 명시 (`doc/base/detailed-design-guide.md` 혹은 각 SKILL.md).
- Step 4~8 team worker 의 tasks 테이블 insert/update 규약.

## 검증

1. (Phase 0) `hook_probe.py` 로그로 5개 hook 동작/스키마 확인.
2. `workflow start "test"` → DB/sessions.json 초기화.
3. `workflow run --step 1` → UUID/PID 기록, DB step 1 running.
4. 스킬 `status=done` 마킹 + Stop hook 이 `.workflow-state/signals/2026-04-15-01-1.done` 생성.
5. 오케스트레이터 시그널 감지 → 자식 SIGTERM → 프로세스 종료.
6. `workflow run --step 2` → sessions.json 덮어쓰기, DB step 1 보존 확인.
7. step 2 강제 kill → `workflow watch` 감지 → `workflow run --step 2` 재실행 시 resume 경로.
8. rate limit 시뮬레이션(가짜 키 등) → StopFailure hook 이 `.failed.*` signal 파일 생성, DB 상태 전이 확인.
9. 동일 스텝 이중 실행 차단 확인 (PID 생존 시).

## 보류

- 자식 SIGTERM 후 안 죽을 때 SIGKILL 타임아웃 값 (기본 5s 제안).
- sessions.json ↔ DB 불일치 복구용 `workflow sync` 보조 명령.
- rate_limited 복구 시 자동 재시도 딜레이 옵션 (`workflow run --wait-until <ts>`).
- Stop hook 이 "스텝 완료 vs 일반 턴 종료" 를 구분하는 규약(스킬의 DB 선마킹)을 `doc/base/detailed-design-guide.md` 에 어떻게 명시할지.

## 해결된 항목 (공식 hook 문서 확인)

- 세션 ID 획득 → `--session-id` CLI 플래그로 스크립트가 선지정.
- PID 획득 → `subprocess.Popen().pid`.
- rate limit 감지 → `StopFailure` hook + matcher `rate_limit`.
- 비정상 종료 감지 → `SessionEnd` hook + matcher.
- 완료 시그널 → Stop hook + 파일 시그널.
