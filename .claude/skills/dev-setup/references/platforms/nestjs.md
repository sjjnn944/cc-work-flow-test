# NestJS 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| Node.js | 18 | JavaScript 런타임 | `node --version` |
| npm 또는 pnpm | npm 9+ / pnpm 8+ | 패키지 매니저 | `npm --version` / `pnpm --version` |
| @nestjs/cli | 10+ | NestJS CLI | `nest --version` |
| TypeScript | 5.0+ | 타입 시스템 | `tsc --version` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| ESLint | 린터 | 개발 환경 |
| Prettier | 포맷터 | 개발 환경 |
| Jest | 테스트 러너 | 기본 포함 |

## 패키지 매니저
- 기본: npm 또는 pnpm
- 초기화: `nest new {project}`

## OS별 특이사항
- Windows: winget으로 Node.js LTS 설치, 또는 nvm-windows
- Linux: nvm 또는 NodeSource 저장소
- macOS: `brew install node` 또는 nvm
