# workflow.py CLI 명세

> **버전**: 0.1 (2026-04-16)
> **파일**: `tools/workflow.py`
> **목적**: 9단계 워크플로우를 스텝 단위 독립 세션으로 실행·관리

---

## 1. 개요

`workflow.py` 는 9단계 워크플로우의 오케스트레이터다. 각 스텝을 별도 `claude-code` 세션으로 실행하고, 상태를 두 곳에 기록한다.

| 저장소 | 역할 |
|---|---|
| `.workflow-state/sessions.json` | 현재 진행 중인 스텝의 라이브 포인터 |
| `.workflow-state/workflow.db` | 히스토리·병렬 태스크의 단일 원천 |

Git 브랜치를 run 단위로 관리하여 `reset` 시 이전 상태로 복원할 수 있다.

**분리 파일**
- `tools/workflow_hook.py` — hook 엔드포인트 (Stop / StopFailure / SessionEnd / Notification / SubagentStop)
- `tools/workflow_watch.py` — PID 폴링, 죽은 running 스텝 → `failed` 마킹

---

## 2. 명령 레퍼런스

### `workflow init [--name foo]`

새 워크플로우 run 을 초기화한다.

- `run_id` 생성: `YYYY-MM-DD-NN` (당일 N번째). `--name foo` 지정 시 `YYYY-MM-DD-foo`
- DB `workflow_runs` insert, `steps` 9개 `pending` 상태로 insert
- `sessions.json` 삭제 (이전 포인터 초기화)
- Git 브랜치 생성: `git checkout -b workflow/{run_id}`

```
$ python workflow.py init
Created run: 2026-04-16-01
Branch: workflow/2026-04-16-01
```

---

### `workflow run`

마지막 스텝 상태를 확인하고 분기 처리한다.

```
DB 조회 → 마지막 실행 스텝 확인
  ├─ 진행 중(running) + pid 생존  → 상태 출력 후 종료
  ├─ 진행 중(running) + pid 없음  → claude --resume <session_id> --prompt "계속 진행"
  ├─ 마지막 스텝 done             → 다음 스텝 새 세션 시작
  └─ 스텝 없음 / pending          → Step 1 새 세션 시작
```

세션 시작 시:
1. `uuid.uuid4()` 로 session_id 생성
2. `subprocess.Popen(["claude", "--session-id", str(sid), "--prompt", "<스킬 프롬프트>"], env={WORKFLOW_RUN_ID, WORKFLOW_STEP_NO, ...})`
3. `child.pid` 획득 즉시 `sessions.json` + DB UPDATE (`status=running`)
4. 즉시 종료 — 대기는 Claude 루프 대기 모드(ScheduleWakeup)가 담당

---

### `workflow run --restart`

현재 스텝을 세션 로드 없이 처음부터 강제 재시작한다.

- 진행 중 세션이 있어도 무시
- 현재 스텝 `status → pending` 초기화 후 새 세션 시작

```
$ python workflow.py run --restart
Step 3 reset → starting fresh session ...
```

---

### `workflow reset --step N`

Step N 이전 상태로 복원한다.

1. DB에서 Step N-1 의 `git_commit` 조회
2. 새 브랜치 체크아웃: `git checkout -b workflow/{run_id}-reset-{N} <commit>`
3. DB에서 Step N 이상 `status → pending`, `session_id` / `pid` / `started_at` / `ended_at` / `git_commit` 초기화

```
$ python workflow.py reset --step 3
Resetting to Step 2 (commit: abc1234)
Branch: workflow/2026-04-16-01-reset-3
Steps 3~9 set to pending.
```

---

### `workflow auto`

현재 스텝부터 전체 완료까지 자동 연속 실행한다 (Claude 루프 대기 모드 진입점).

Claude 가 이 명령을 사용할 때의 흐름:
```
Bash("python workflow.py run", run_in_background=True)
ScheduleWakeup(60s, prompt="workflow-loop: run_id=<X> step=<N> 완료 확인")

  깨어남 → workflow status --json 확인
    running       → ScheduleWakeup(60s) 재등록 (루프 계속)
    done          → 다음 스텝 자동 시작 (루프 재귀)
    failed        → 루프 종료, 실패 원인 보고
    rate_limited  → 루프 종료, 대기 후 재시도 안내
```

ScheduleWakeup 을 재등록하지 않으면 루프가 자연 종료된다.

---

### `workflow status [--json]`

현재 진행 중인 스텝의 상태를 출력한다.

기본 출력:
```
Run:  2026-04-16-01  (branch: workflow/2026-04-16-01)
Step: 3 / 9  parallel-design  [running]
PID:  23456   Session: def45678-...
```

`--json` 출력 (Claude 파싱용):
```json
{
  "run_id": "2026-04-16-01",
  "step_no": 3,
  "skill": "parallel-design",
  "status": "running",
  "session_id": "def45678-90ab-cdef-1234-567890abcdef",
  "pid": 23456,
  "started_at": "2026-04-16T10:42:00+09:00"
}
```

---

### `workflow status --update`

`sessions.json` 에 기록된 상태를 DB 에 반영한다.

**사용 목적**: 스킬(claude-code 세션)이 완료 시점에 스스로 상태를 갱신하는 경로.  
스킬은 DB 에 직접 접근하지 않고 `sessions.json` 만 수정 후 이 명령을 호출한다.

**스킬 내부 호출 흐름**:
```
1. 스킬 종료 직전:
   sessions.json 의 status 필드를 완료 상태로 수정
   예) "status": "done"  또는  "status": "failed"

2. python workflow.py status --update 호출

3. workflow.py 처리:
   a. sessions.json 읽기
   b. DB UPDATE:
        UPDATE steps
        SET status=?, ended_at=?, git_commit=?
        WHERE run_id=? AND step_no=?
   c. status=done 시:
        git add -A
        git commit -m "workflow: step {N} ({skill}) done"
        커밋 해시 → steps.git_commit 저장
        signal 파일 생성: .workflow-state/signals/{run_id}-{step_no}.done
   d. status=failed 시:
        signal 파일 생성: .workflow-state/signals/{run_id}-{step_no}.failed
```

**sessions.json 수정 예시** (스킬이 완료 전 기록):
```json
{
  "run_id": "2026-04-16-01",
  "step_no": 2,
  "skill": "project-scaffold",
  "status": "done",
  "session_id": "def45678-90ab-cdef-1234-567890abcdef",
  "pid": 23456,
  "started_at": "2026-04-16T10:42:00+09:00"
}
```

> **설계 의의**: 이 명령이 plan.md 의 "Stop hook 이 스텝 완료 vs 일반 턴 종료를 구분하는 규약" 문제를 해소한다.
> 스킬이 명시적으로 `status --update` 를 호출해야만 signal 파일이 생성되므로, Stop hook 은 단순 로깅 역할로 축소된다.

---

## 3. Git 연동

| 시점 | 동작 |
|---|---|
| `init` | `git checkout -b workflow/{run_id}` + `workflow_runs.git_branch` 저장 |
| 스텝 완료(done) | `git add -A && git commit -m "workflow: step {N} ({skill}) done"` + 커밋 해시 `steps.git_commit` 저장 |
| `reset --step N` | Step N-1 커밋 기준 `git checkout -b workflow/{run_id}-reset-{N} <commit>` |

---

## 4. 상태 전이

```
steps.status:

  pending ──► running ──► done
                      ├──► failed
                      └──► rate_limited
```

`workflow_runs.status`:
```
  init ──► running ──► done
                   ├──► failed
                   └──► abandoned
```

---

## 5. 환경 변수 (자식 프로세스에 주입)

| 변수 | 값 |
|---|---|
| `WORKFLOW_RUN_ID` | 현재 run_id |
| `WORKFLOW_STEP_NO` | 현재 스텝 번호 |

hook 핸들러는 stdin JSON 에 session_id 만 있으므로 이 env var 로 run/step 을 식별한다.

---

## 6. 스텝 → 스킬 매핑

| step_no | skill |
|---|---|
| 1 | first-ralplan |
| 2 | project-scaffold |
| 3 | dev-setup |
| 4 | parallel-design |
| 5 | parallel-test |
| 6 | parallel-impl |
| 7 | impl-fixup |
| 8 | parallel-test-review |
| 9 | full-verify |
