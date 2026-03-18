# Go 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| Go | 1.21 | Go 툴체인 | `go version` |
| golangci-lint | 1.55 | 린터 | `golangci-lint --version` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| delve | 디버거 | 개발 환경 |
| gopls | LSP 서버 | IDE 연동 |
| mockgen | 목 생성기 | 테스트 시 |

## 패키지 매니저
- 기본: go modules
- 초기화: `go mod init {module}`

## OS별 특이사항
- Windows: winget 또는 공식 MSI 설치, GOPATH 설정
- Linux: 공식 tarball 또는 snap install go
- macOS: `brew install go`
