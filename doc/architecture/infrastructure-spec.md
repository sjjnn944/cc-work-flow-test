# Infrastructure Specification

> 이 문서는 dev-setup 스킬이 설계서 기술스택에서 자동 생성합니다.
> docker-infra 스킬의 `provision` 명령으로 일괄 실행할 수 있습니다.

## 서비스 목록

| 서비스 | 이미지 | 호스트포트 | 카테고리 | 사용 모듈 | 상태 |
|--------|--------|-----------|----------|----------|------|
| postgresql | postgres:16-alpine | 5423 | Database | AUTH, POLICY | 등록됨 |
| redis | redis:7-alpine | 6370 | Cache | AUTH, CORE | 등록됨 |
| kafka | confluentinc/cp-kafka:7.6.0 | 9083 | MQ | CORE, LOG | 등록됨 |
| ... | ... | ... | ... | ... | ... |

## Compose 스택

- kafka-stack: zookeeper + kafka
- monitoring-stack: prometheus + grafana

## 시작 순서

1. Database (postgresql, mongodb)
2. Cache (redis)
3. Discovery (zookeeper)
4. MQ (kafka)
5. Monitoring (prometheus, grafana)
6. Auth (keycloak)
