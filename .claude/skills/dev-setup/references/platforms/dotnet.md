# .NET 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| .NET SDK | 8.0 | 빌드/런타임 | `dotnet --version` |
| dotnet CLI | SDK 포함 | 프로젝트 관리 | `dotnet --info` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| Visual Studio / Rider | IDE | 권장 |
| dotnet-ef | EF Core CLI | DB 마이그레이션 시 |
| dotnet-format | 포맷터 | 개발 환경 |

## 패키지 매니저
- 기본: NuGet (dotnet CLI)
- 초기화: `dotnet new webapi -n {project}`

## OS별 특이사항
- Windows: winget `Microsoft.DotNet.SDK.8`
- Linux: Microsoft 패키지 저장소 등록 후 apt/dnf
- macOS: `brew install dotnet-sdk`
