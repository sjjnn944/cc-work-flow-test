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
  git_branch   TEXT,               -- workflow/{run_id}, init 시 생성
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
  git_commit   TEXT,               -- 스텝 완료(done) 시 커밋 해시 저장
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
| `workflow init` | 스크립트 | 삭제 | `workflow_runs` insert(`git_branch` 포함), `steps` 9개 `pending`; `git checkout -b workflow/{run_id}` |
| `workflow run --step N` spawn | 스크립트 | UUID 생성, 전체 오브젝트 덮어쓰기 | `UPDATE steps SET status='running', session_id=?, pid=?, started_at=?` |
| 스텝 완료 (스킬 내부) | 스킬 | (변경 없음) | `UPDATE steps SET status='done', ended_at=?, git_commit=?`; `git add -A && git commit -m "workflow: step {N} done"` |
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
  5) 즉시 종료 — 대기는 Claude 루프 대기 모드(ScheduleWakeup)가 담당
```

### `workflow run` 분기 로직

```
workflow run 진입 시:
  1) DB 조회 → 마지막 실행 스텝 확인
  2) 분기:
     - 진행 중(running) + pid 생존  → 상태 출력 후 종료
     - 진행 중(running) + pid 없음  → claude --resume <session_id> --prompt "계속 진행"
     - 마지막 스텝 done             → 다음 스텝 새 세션 시작
     - 스텝 없음 / pending          → Step 1 새 세션 시작
  3) --restart 플래그 시: 현재 스텝 pending 초기화 → 새 session_id → 처음부터 재시작
```

## Claude 루프 대기 모드

`workflow.py run --step N`은 백그라운드 실행 후 Claude가 `/loop`(ScheduleWakeup) 로 완료를 감지한다.

### 동작 흐름

```
Claude:
  1) Bash("python workflow.py run --step N", run_in_background=True)
       → workflow.py 내부: claude-code spawn + sessions.json/DB 기록 후 즉시 종료
  2) ScheduleWakeup(60s, prompt="run_id=<X> step=<N> 완료 확인")

--- 60초 후 자동 깨어남 ---

  3) Bash("python workflow.py status --json")
     ├─ status=running   → ScheduleWakeup(60s) 재등록 (루프 계속)
     ├─ status=done      → 재등록 없음 (루프 자연 종료)
     │                      --auto 모드: 다음 스텝 자동 실행
     │                      기본 모드:   사용자에게 "다음 스텝 실행할까요?" 확인
     ├─ status=failed    → 루프 종료, 실패 원인 보고
     └─ status=rate_limited → 루프 종료, 대기 후 재시도 안내
```

### 실행 모드

| 모드 | 호출 | 동작 |
|---|---|---|
| **기본** | `workflow run --step N` | 완료 시 사용자 확인 후 다음 스텝 |
| **자동** | `workflow auto [--from N]` | done 감지 즉시 다음 스텝 자동 실행, 전 스텝 완료까지 반복 |

### ScheduleWakeup 컨텍스트 전달

루프가 깨어난 후 어떤 run/step을 확인할지 알아야 하므로 prompt에 포함:

```
prompt="workflow-loop: run_id=2026-04-16-01 step=2 완료 확인 후 계속"
```

### 제약

- 완료 감지 지연: 최대 60초 (ScheduleWakeup 최소 간격)
- 캐시 효율: 270초 이내 재등록 시 캐시 유지. 스텝이 5분 이상 걸릴 것으로 예상되면 폴링 주기를 270s로 늘려 캐시 미스 방지
- workflow.py는 spawn 후 **즉시 종료** — 내부 폴링 루프 없음. 상태 확인은 Claude가 담당

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
| `workflow init [--name foo]` | run_id 생성(`YYYY-MM-DD-NN`) + DB 초기화 + `workflow/{run_id}` 브랜치 생성 |
| `workflow run` | 마지막 스텝 상태 확인 → 분기 처리 (스텝 실행 흐름 참조) |
| `workflow run --restart` | 현재 스텝을 세션 로드 없이 처음부터 강제 재시작 |
| `workflow reset --step N` | Step N 이전 커밋 기준 새 브랜치 체크아웃 + DB Step N 이상 pending 초기화 |
| `workflow auto` | 현재 스텝부터 전체 자동 연속 실행 (Claude 루프 대기 모드 진입점) |
| `workflow status [--json]` | 현재 진행 중인 스텝 상태 출력. `--json` 시 Claude 파싱용 JSON |

> `hook`, `watch` 는 별도 파일로 분리 → `tools/workflow_hook.py`, `tools/workflow_watch.py`

## 폴더/파일

- 신규 `doc/workflow-automation/README.md` — 사용자 가이드
- 신규 `doc/workflow-automation/workflow-cli-spec.md` — CLI 명세 (명령·흐름·git 연동)
- 신규 `doc/workflow-automation/state-spec.md` — 필드 명세, 상태 전이도
- 신규 `doc/workflow-automation/schema.sql`
- 신규 `doc/workflow-automation/hook-poc-findings.md` (Phase 0 산출물)
- 신규 `tools/workflow.py` (init / run / reset / auto / status)
- 신규 `tools/workflow_hook.py` (hook 엔드포인트)
- 신규 `tools/workflow_watch.py` (PID 폴링)
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

- `schema.sql` / DB 초기화 (`git_branch`, `git_commit` 컬럼 포함)
- `tools/workflow.py` (`init` / `run` / `run --restart` / `reset` / `auto` / `status` subcommands)
- `tools/workflow_hook.py` (hook 전용: stop / stop-failure / session-end / notify / subagent-stop)
- `tools/workflow_watch.py` (PID 폴링 전용)
- `.claude/settings.json` 정식 등록
- `.gitignore` 업데이트

### Phase 2 — 스킬 연계

- 각 스킬(`first-ralplan` ~ `full-verify`) 종료 시점에 DB `status=done` 마킹 규약 명시 (`doc/base/detailed-design-guide.md` 혹은 각 SKILL.md).
- Step 4~8 team worker 의 tasks 테이블 insert/update 규약.

## 검증

1. (Phase 0) `hook_probe.py` 로그로 5개 hook 동작/스키마 확인.
2. `workflow init "test"` → DB/sessions.json 초기화 + `workflow/YYYY-MM-DD-01` 브랜치 생성 확인.
3. `workflow run` → UUID/PID 기록, DB step 1 running.
4. 스킬 `status=done` 마킹 + Stop hook 이 `.workflow-state/signals/2026-04-15-01-1.done` 생성.
5. Claude 루프 대기: ScheduleWakeup 60s 후 `workflow status --json` 확인 → done 시 루프 종료.
6. 스텝 완료 후 자동 커밋 생성 + `steps.git_commit` 저장 확인.
7. `workflow run` (done 상태) → 다음 스텝 자동 시작, sessions.json 덮어쓰기, DB step 1 보존 확인.
8. step 강제 kill → `workflow run` 재실행 시 pid 없음 감지 → resume 경로 확인.
9. rate limit 시뮬레이션(가짜 키 등) → StopFailure hook 이 `{run_id}-{step_no}.failed.rate_limit` signal 파일 생성, DB 상태 전이 확인.
10. `workflow run` (running + pid 생존) → 상태 출력 후 종료, 이중 실행 차단 확인.
11. `workflow run --restart` → 진행 중 스텝 무시, 새 세션으로 재시작 확인.
12. `workflow reset --step 3` → Step 3 이상 pending 초기화, 새 브랜치 체크아웃, `workflow run` 으로 Step 3 재시작 확인.
13. `workflow auto` → done 감지 후 다음 스텝 자동 진행 확인.

## 보류

- 자식 SIGTERM 후 안 죽을 때 SIGKILL 타임아웃 값 (기본 5s 제안).
- sessions.json ↔ DB 불일치 복구용 `workflow sync` 보조 명령.
- rate_limited 복구 시 자동 재시도 딜레이 옵션 (`workflow run --wait-until <ts>`).
- ~~Stop hook 이 "스텝 완료 vs 일반 턴 종료" 를 구분하는 규약~~ → **해소**: 스킬이 `workflow status --update` 를 명시적 호출 → signal 파일 생성. Stop hook 은 단순 로깅으로 축소.

## 해결된 항목 (공식 hook 문서 확인)

- 세션 ID 획득 → `--session-id` CLI 플래그로 스크립트가 선지정.
- PID 획득 → `subprocess.Popen().pid`.
- rate limit 감지 → `StopFailure` hook + matcher `rate_limit`.
- 비정상 종료 감지 → `SessionEnd` hook + matcher.
- 완료 시그널 → Stop hook + 파일 시그널.
- 대기 루프 폴링 주기 → ScheduleWakeup 최소 60s (Claude 루프 대기 모드).
