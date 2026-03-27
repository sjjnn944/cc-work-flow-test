---
name: docker-infra
description: Docker 컨테이너 인프라 관리 — 외부 서비스 시작/중지/상태/로그 관리 및 미등록 서비스 자동 등록. "docker", "컨테이너", "서비스 시작", "redis 시작", "kafka 올려", "인프라", "서비스 중지", "컨테이너 상태" 등을 요청할 때 사용.
---

# docker-infra 스킬

Docker 컨테이너 기반 외부 서비스 라이프사이클 관리 스킬.
`container-registry.json`에 등록된 서비스를 docker-mcp 도구로 관리하며,
미등록 서비스는 WebSearch로 이미지를 찾아 자동 등록한다.

## 명령어

| 명령 | 설명 |
|------|------|
| `start <service>` | 단일 서비스 시작 (의존성 자동 해소) |
| `stop <service>` | 단일 서비스 중지 |
| `status` | test- 접두사 컨테이너 상태 조회 |
| `logs <service>` | 컨테이너 로그 조회 |
| `up <services...>` | 여러 서비스 일괄 시작 |
| `down` | 모든 test- 컨테이너 중지 |
| `list` | 레지스트리 등록 서비스 목록 |
| `add <service>` | 수동 등록 |
| `provision [--file <path>]` | infrastructure-spec.md 기반 전체 인프라 일괄 시작 |

## 파일 참조

- **레지스트리**: `.claude/skills/docker-infra/references/container-registry.json`
- **Compose 템플릿**: `.claude/skills/docker-infra/references/compose-templates/`

## 워크플로우

### 1. `start <service>`

```
1. Read로 container-registry.json 로드
2. 서비스 키로 조회
   - 미등록 → [자동 등록 워크플로우] 실행
3. depends_on 확인 → 의존 서비스가 미실행이면 재귀적으로 먼저 시작
4. compose_template 유무 판단:
   - 있음 → mcp__docker-mcp__deploy-compose 로 스택 배포
     - content: compose-templates/{template} 파일 내용을 Read로 읽어서 전달
     - project_name: "test"
   - 없음 → mcp__docker-mcp__create-container 로 단일 컨테이너 생성
     - name: "test-{service}"
     - image: registry의 image
     - ports: registry의 ports (호스트:컨테이너 형식 배열)
     - environment: registry의 env (KEY=VALUE 형식 배열)
5. 접속 정보 출력:
   - 서비스명, 호스트포트, 카테고리
   - 예: "redis started → localhost:6370"
```

### 2. `stop <service>`

```
1. Bash로 docker stop test-{service} && docker rm test-{service} 실행
   (docker-mcp에 stop/rm API가 없으므로 Bash 사용)
2. compose_template이 있는 서비스의 경우:
   - Bash로 docker compose -p test -f <template-path> down 실행
```

### 3. `status`

```
1. mcp__docker-mcp__list-containers 호출
2. 결과에서 test- 접두사 컨테이너만 필터링
3. 테이블 형식으로 출력:
   | 컨테이너 | 이미지 | 상태 | 포트 |
```

### 4. `logs <service>`

```
1. mcp__docker-mcp__get-logs 호출
   - container_name: "test-{service}"
   - tail: 50 (기본값)
2. 로그 출력
```

### 5. `up <services...>`

```
1. 각 서비스에 대해 start 워크플로우 순차 실행
2. 의존성 그래프를 고려하여 중복 시작 방지
3. 전체 결과 요약 출력
```

### 6. `down`

```
1. mcp__docker-mcp__list-containers 호출
2. test- 접두사 컨테이너 목록 추출
3. 의존성 역순으로 정렬 (depends_on 참조)
4. 각 컨테이너에 대해 Bash로 docker stop && docker rm 실행
5. 결과 요약 출력
```

### 7. `list`

```
1. Read로 container-registry.json 로드
2. 카테고리별 그룹핑하여 테이블 출력:
   | 서비스 | 이미지 | 포트 | 카테고리 |
```

### 8. `add <service>`

```
1. 사용자에게 다음 정보 요청:
   - image (필수)
   - ports (필수)
   - env (선택)
   - category (필수)
   - depends_on (선택)
2. container-registry.json에 항목 추가 (Write)
3. 등록 확인 메시지 출력
```

### 9. `provision [--file <path>]`

infrastructure-spec.md를 읽어서 모든 서비스를 의존성 순서대로 일괄 시작한다.

```
1. Read로 doc/architecture/infrastructure-spec.md 로드 (또는 --file로 지정된 경로)
2. "서비스 목록" 테이블 파싱 → 서비스 키 목록 추출
3. container-registry.json과 대조:
   - "미등록" 서비스 → 자동 등록 워크플로우 실행
4. "시작 순서" 절 기반으로 의존성 순서 결정
5. 각 서비스를 순서대로 start (compose_template 있으면 스택 배포)
6. 전체 결과 요약 (성공/실패/스킵)
```

**예시:**
```
사용자: /docker-infra provision
스킬:
  1. doc/architecture/infrastructure-spec.md 로드
  2. 서비스 6개 추출: postgresql, redis, zookeeper, kafka, prometheus, grafana
  3. registry 대조: 등록됨 4개, 미등록 2개
  4. 미등록 서비스 자동 등록 실행
  5. 시작 순서대로 실행:
     [1/6] postgresql → localhost:5423 [OK]
     [2/6] redis → localhost:6370 [OK]
     [3/6] zookeeper + kafka (kafka-stack) → localhost:9083 [OK]
     [4/6] prometheus + grafana (monitoring-stack) [OK]
  6. 결과: 성공 6개 / 실패 0개 / 스킵 0개
```

## 자동 등록 워크플로우

미등록 서비스 요청 시 실행:

```
1. WebSearch로 "{service} docker official image" 검색
2. Docker Hub 공식/인기 이미지 후보 3개 제시
3. 사용자가 선택 (또는 직접 입력)
4. 기본 포트 매핑 추정 (WebSearch 결과 기반)
   - port_offset(-9) 적용하여 호스트 포트 계산
5. 사용자 확인 후 container-registry.json에 추가 (Write)
6. start 워크플로우로 이어서 실행
```

## 도구 매핑

| 동작 | 도구 |
|------|------|
| 단일 컨테이너 생성 | `mcp__docker-mcp__create-container` |
| 멀티 컨테이너 스택 배포 | `mcp__docker-mcp__deploy-compose` |
| 컨테이너 목록 조회 | `mcp__docker-mcp__list-containers` |
| 컨테이너 로그 조회 | `mcp__docker-mcp__get-logs` |
| 컨테이너 중지/삭제 | `Bash` (docker stop/rm) |
| 이미지 검색 (자동 등록) | `WebSearch` |
| 레지스트리 읽기 | `Read` |
| 레지스트리 업데이트 | `Write` |

## 컨테이너 네이밍 규칙

- 모든 컨테이너에 `test-` 접두사 적용
- 단일: `test-{service}` (예: `test-redis`, `test-postgresql`)
- 스택 내: compose 파일의 container_name 사용 (예: `test-kafka`, `test-zookeeper`)
- auth-stack처럼 동일 서비스가 다른 용도로 사용되면: `test-auth-{service}` (예: `test-auth-postgresql`)

## 포트 관리

- `port_offset: -9` — 기본 포트에서 9를 빼서 호스트 포트 산출 (충돌 방지)
- 자동 등록 시에도 동일 규칙 적용
- 포트 충돌 시 사용자에게 대체 포트 제안

## 주의사항

- compose_template이 있는 서비스는 반드시 deploy-compose로 배포 (단일 create-container 금지)
- depends_on 서비스가 이미 실행 중이면 재시작하지 않음
- down 시 의존성 역순 중지 필수 (kafka → zookeeper 순)
- 환경변수에 민감정보가 있으면 사용자에게 경고 (기본값은 테스트용)
