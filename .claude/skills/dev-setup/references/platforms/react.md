# React/Vite 개발 환경

## 필수 도구
| 도구 | 최소 버전 | 용도 | 검증 명령 |
|------|----------|------|----------|
| Node.js | 18 | JavaScript 런타임 | `node --version` |
| npm 또는 pnpm | npm 9+ / pnpm 8+ | 패키지 매니저 | `npm --version` / `pnpm --version` |
| TypeScript | 5.0+ | 타입 시스템 | `tsc --version` |

## 선택 도구
| 도구 | 용도 | 설치 조건 |
|------|------|----------|
| ESLint | 린터 | 개발 환경 |
| Prettier | 포맷터 | 개발 환경 |
| Vitest | 테스트 러너 | Vite 네이티브 테스트 |
| Playwright | E2E 테스트 | 통합 테스트 환경 |

## 패키지 매니저
- 기본: npm 또는 pnpm
- 초기화: `npm create vite@latest {project} -- --template react-ts`

## 주요 의존성
| 패키지 | 용도 |
|--------|------|
| react | UI 라이브러리 |
| react-dom | DOM 렌더링 |
| vite | 빌드 도구 |
| @vitejs/plugin-react | Vite React 플러그인 |
| typescript | 타입 시스템 |

## OS별 특이사항
- Windows: winget으로 Node.js LTS 설치, 또는 nvm-windows
- Linux: nvm 또는 NodeSource 저장소
- macOS: `brew install node` 또는 nvm
