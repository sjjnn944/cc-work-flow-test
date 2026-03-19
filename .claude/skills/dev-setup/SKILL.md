---
name: dev-setup
description: module-mapping.md와 설계서 기술 스택 절을 입력으로 개발 환경 설치(컴파일러/런타임/패키지 매니저)와
  플랫폼별 빌드 파일(CMakeLists.txt, build.gradle, Cargo.toml 등)을 자동 생성하는 스킬.
  "빌드 설정 생성", "CMakeLists 생성", "Gradle 설정", "개발 환경 구성", "dev-setup",
  "빌드 시스템 초기화", "개발 환경 설치", "환경 설정" 등을 요청할 때 사용.
---

<Purpose>
`doc/architecture/module-mapping.md`와 설계서 2절(기술 스택)을 입력으로 받아, 개발 환경 설치와 플랫폼별 빌드 파일 및 개발 환경 설정 파일을 생성한다.

지원 플랫폼 (8개):
- **C++/CMake**: CMakeLists.txt, vcpkg, MSVC/GCC/Clang
- **Spring Boot**: build.gradle, settings.gradle, JDK 17+
- **React/Vite**: package.json, vite.config.ts, Node.js + npm/pnpm
- **Go**: go.mod, Makefile, Go toolchain
- **Rust**: Cargo.toml, rustup + cargo
- **NestJS**: package.json, tsconfig.json, Node.js + pnpm
- **Django**: pyproject.toml, Python 3.x + poetry
- **ASP.NET Core**: .sln, .csproj, .NET SDK

생성 범위:
- **개발 환경 설치**: OS별 설치 스크립트 실행 (컴파일러, 런타임, 패키지 매니저)
- **빌드 파일**: 플랫폼별 빌드 시스템 파일 (루트 + 모듈별)
- **외부 라이브러리 의존성**: 플랫폼별 의존성 관리 블록
- **개발 도구 설정**: `.editorconfig`, `.clang-format`, `.gitignore` 등

이 스킬은 Step 2(project-scaffold) 완료 후, Step 4(parallel-design) 실행 전에 실행한다.
</Purpose>

<Use_When>
- project-scaffold 실행 완료 후 빌드 시스템을 구성해야 할 때
- `doc/architecture/module-mapping.md`와 `src/` 폴더 구조가 준비된 상태에서 빌드 파일을 생성할 때
- 새 개발자가 프로젝트에 참여하여 개발 환경을 설치해야 할 때
- "CMakeLists.txt 생성", "build.gradle 구성", "빌드 환경 초기화", "개발 환경 설치" 등을 요청할 때
- 기술 스택 절이 포함된 설계서를 기반으로 외부 의존성을 자동으로 설정하고 싶을 때
- `--install-only`로 환경 설치만 수행하거나 `--check`로 설치 상태만 확인할 때
</Use_When>

<Do_Not_Use_When>
- `--install-only` 또는 `--check` 모드가 아닌데 `doc/architecture/module-mapping.md`가 없는 경우 (먼저 /project-scaffold 사용)
- `--install-only` 또는 `--check` 모드가 아닌데 `src/` 폴더 구조가 없는 경우
- 기존 빌드 파일을 수정/업데이트하는 경우 (수동 편집 또는 별도 작업)
- CI/CD 파이프라인 설정이 필요한 경우 (범위 외)
</Do_Not_Use_When>

<Arguments>
인수 형식: `/dev-setup [subsystem] [--dry-run] [--install-only] [--build-only] [--check]`

| 인수 | 기본값 | 설명 |
|------|--------|------|
| subsystem | (전체) | `agt`, `svr` 또는 플랫폼명(`cpp`, `go`, `rust` 등) — 특정 대상만 |
| --dry-run | false | 생성할 파일 목록과 내용 미리보기만 출력하고 실제로 파일을 생성하지 않음 |
| --install-only | false | 개발 환경 설치만 실행, 빌드 파일 생성 skip |
| --build-only | false | 빌드 파일만 생성, 설치 skip (기존 동작 호환) |
| --check | false | 설치 필요 도구 확인만 (설치하지 않음) |

**모드 동작:**
- 인수 없음: 전체 실행 (설치 + 빌드 파일 + 개발 도구)
- `--install-only`: Step 0 → Step 1 → Step 2만 실행
- `--build-only`: Step 0 → Step 1 → Step 3~5만 실행 (기존 동작)
- `--check`: Step 0 → Step 1 → Step 2(check-only 모드)만 실행
</Arguments>

<Steps>

## Step 0: 초기화

1. **필수 파일 존재 확인**
   - `--install-only` 또는 `--check` 모드: `doc/architecture/module-mapping.md` 없어도 진행 가능 (subsystem 인수로 플랫폼 직접 지정)
   - 그 외: `doc/architecture/module-mapping.md` 존재 여부 확인 — 없으면 중단
   - `--build-only` 또는 기본 모드: `src/` 디렉토리 존재 여부 확인 — 없으면 중단
   - `doc/designs/*.md` Glob으로 설계서 탐색

2. **인수 처리**
   - `subsystem` 인수 확인: `agt`, `svr`, 플랫폼명, 또는 미지정(전체)
   - `--dry-run`, `--install-only`, `--build-only`, `--check` 플래그 확인

3. **플랫폼 참조 문서 경로 파악**
   - `doc/base/detailed-designs/{platform}.md` — 프로젝트 설계 컨벤션 참조
   - `.claude/skills/dev-setup/references/platforms/{platform}.md` — 설치 사양 참조

## Step 1: 입력 분석

### 1.1 module-mapping.md 읽기 (빌드 파일 생성 시)

`doc/architecture/module-mapping.md`를 Read하여 다음 정보를 추출한다.

| 추출 항목 | 용도 |
|----------|------|
| 모듈코드 | 빌드 target명 결정 |
| 유형 (EXE/DLL/SYS/JAR/BIN/...) | 빌드 명령 결정 |
| 플랫폼 | 8개 플랫폼 중 분기 |
| src 경로 | 빌드 파일 배치 위치 결정 |

**플랫폼 감지 (8개):**
- C++/CMake, Windows Driver → `cpp`
- Spring Boot → `springboot`
- React/Vite → `react`
- Go → `go`
- Rust → `rust`
- NestJS/Node.js → `nestjs`
- Django/Python → `django`
- ASP.NET Core/.NET → `dotnet`

### 1.2 설계서 기술 스택 절 읽기

`doc/designs/*.md`에서 **2절(기술 스택)** 을 찾아 Read하여 외부 라이브러리, 버전, 빌드 도구 요구사항을 추출한다.

### 1.3 플랫폼별 참조 문서 읽기

감지된 플랫폼에 대해:
- `doc/base/detailed-designs/{platform}.md` — 빌드 컨벤션
- `.claude/skills/dev-setup/references/platforms/{platform}.md` — 설치 도구/버전 사양

### 1.4 분석 결과 요약 출력

```
=== dev-setup 분석 결과 ===
대상 모듈: {N}개
  - C++/CMake: {N1}개
  - Spring Boot: {N2}개
  - Go: {N3}개  / Rust: {N4}개  / NestJS: {N5}개  / Django: {N6}개  / .NET: {N7}개

설치 필요 도구: {도구 목록} (--check/--install-only 시)
생성 예정 파일: {파일 목록} (--build-only/기본 시)
```

## Step 2: 개발 환경 설치

`--build-only` 지정 시 이 Step 전체를 건너뛴다.

### 2.1 OS 감지

실행 환경의 OS를 감지한다:
- Windows → `scripts/windows/` 스크립트 사용 (PowerShell)
- Linux → `scripts/linux/` 스크립트 사용 (bash)
- macOS → `scripts/macos/` 스크립트 사용 (bash)

스크립트 경로: `.claude/skills/dev-setup/scripts/{os}/`

### 2.2 설치 대상 결정

Step 1에서 감지된 플랫폼 목록에 따라 실행할 설치 스크립트를 결정한다.
`references/platforms/{platform}.md`에서 필수 도구와 최소 버전을 확인한다.

### 2.3 사전 검사

각 플랫폼 스크립트를 `--check-only` 모드로 실행하여 현재 설치 상태를 확인한다.

```
=== 설치 사전 검사 ===
[OK]    CMake 3.28.1 (>= 3.20)
[OK]    Ninja 1.11.1 (>= 1.10)
[INSTALL] vcpkg — 미설치
[OK]    JDK 17.0.9 (>= 17)
```

`--check` 모드이면 여기서 종료한다.

### 2.4 사용자 확인

설치할 도구 목록을 표시하고 진행 여부를 사용자에게 확인한다.
관리자 권한이 필요한 경우 경고를 표시한다.

### 2.5 스크립트 실행

OS별 공통 유틸리티를 소싱한 후 플랫폼별 스크립트를 순차 실행한다. 스크립트 실행 시 `--project-root {프로젝트루트}` 인수를 전달하여 써드파티 라이브러리가 `{프로젝트루트}/thirdparty/`에 설치되도록 한다:
- Windows: `powershell -ExecutionPolicy Bypass -File scripts/windows/install-{platform}.ps1 --project-root {프로젝트루트}`
- Linux/macOS: `bash scripts/{os}/install-{platform}.sh --project-root {프로젝트루트}`

**thirdparty 컨벤션:** vcpkg 등 써드파티 라이브러리는 프로젝트 루트의 `thirdparty/` 폴더에 설치한다. 이를 통해 프로젝트별 의존성 격리와 재현 가능한 빌드 환경을 보장한다.

### 2.6 설치 검증

각 도구의 검증 명령을 실행하여 설치 결과를 확인한 후, **빌드 샘플 검증**을 수행한다:
- 플랫폼별 최소 샘플 프로젝트(`assets/samples/{platform}/`)를 temp에 복사하여 실제 빌드 수행
- 빌드 성공 시 `[OK]`, 실패 시 `[FAIL]` + 에러 로그 출력
- `--check-only` 모드에서는 빌드 검증을 건너뜀

```
=== 설치 검증 ===
[OK] cmake --version → 3.28.1
[OK] vcpkg version → 2024.01.12
[FAIL] ninja --version → 실패 (PATH 확인 필요)
```

`--install-only` 모드이면 여기서 종료한다.

## Step 3: C++/CMake 빌드 파일 생성

C++/CMake 플랫폼 모듈이 존재하는 경우에만 실행한다. `--install-only` 시 건너뛴다.

### 3.1 루트 CMakeLists.txt

C++ 모듈이 속한 서브시스템 루트에 `CMakeLists.txt`를 생성한다.

**포함 항목:**
- `cmake_minimum_required(VERSION ...)` — 설계서에서 추출, 없으면 3.20
- `project(...)` — 프로젝트명과 언어(CXX)
- C++ 표준 설정 — 설계서에서 추출, 없으면 17
- vcpkg toolchain 설정: `set(CMAKE_TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/thirdparty/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")`
- 전역 컴파일 옵션, FetchContent 블록
- `add_subdirectory()` — 의존성 순서: 공통 → 시스템 공통 → 도메인

### 3.2 모듈별 빌드 파일

**C++ 일반 모듈 → CMakeLists.txt:**

| 모듈 유형 | CMake 명령 | 비고 |
|----------|-----------|------|
| EXE | `add_executable({target} ...)` | entry/ 소스 포함 |
| DLL | `add_library({target} SHARED ...)` | export 헤더 설정 |
| LIB | `add_library({target} STATIC ...)` | |

target명 규칙: 모듈코드 소문자 변환 (AGT.CORE → `agt_core`)

**드라이버 모듈(SYS) → vcxproj:**

WDK는 MSBuild 전용 `.targets`를 제공하며 CMake가 공식 지원하지 않으므로, SYS 유형 모듈은 CMakeLists.txt 대신 vcxproj를 생성한다.

생성 절차:
1. `assets/templates/driver.vcxproj` 템플릿을 로드
2. 다음 항목을 모듈에 맞게 치환:
   - `{{RootNamespace}}` → 모듈코드 PascalCase (AGT.DRVFS → `AgtDrvfs`)
   - `{{TargetName}}` → 모듈코드 소문자 (AGT.DRVFS → `agt_drvfs`)
   - `{{ProjectGuid}}` → 새 GUID 생성
   - `{{DriverType}}` → 설계서에서 추출 (WDM | KMDF | UMDF), 기본값 WDM
   - `{{SourceFiles}}` → src 경로 내 `*.c`, `*.cpp` 파일 목록으로 `<ClCompile Include="..." />` 생성
3. `{src_path}/{target_name}.vcxproj` 에 저장

루트 CMakeLists.txt의 `add_subdirectory()`에는 SYS 모듈을 포함하지 않는다 (빌드 체계가 분리됨).

### 3.3 중간 디렉토리 CMakeLists.txt

도메인 중간 디렉토리에 하위를 포함하는 최소 CMakeLists.txt를 생성한다.

## Step 4: Spring Boot 빌드 파일 생성

Spring Boot 플랫폼 모듈이 존재하는 경우에만 실행한다. `--install-only` 시 건너뛴다.

### 4.1 루트 settings.gradle + build.gradle

서브시스템 루트에 `settings.gradle`(include 목록)과 `build.gradle`(공통 플러그인/의존성)을 생성한다.

### 4.2 모듈별 build.gradle

| 모듈 유형 | 플러그인 | 비고 |
|----------|---------|------|
| JAR (실행) | `id 'org.springframework.boot'` | bootJar 설정 |
| JAR (라이브러리) | `id 'java-library'` | bootJar 비활성화 |

## Step 5: 추가 플랫폼 빌드 파일 생성

해당 플랫폼 모듈이 존재하는 경우에만 실행한다. `--install-only` 시 건너뛴다.

### 5.1 Go

| 생성 파일 | 내용 |
|----------|------|
| `go.mod` | 모듈 경로, Go 버전, 의존성 |
| `Makefile` | build, test, lint, clean 타겟 |
| `.golangci.yml` | golangci-lint 설정 |

### 5.2 Rust

| 생성 파일 | 내용 |
|----------|------|
| `Cargo.toml` (workspace) | workspace members, 공통 의존성 |
| `Cargo.toml` (per-crate) | 크레이트별 의존성 |
| `rustfmt.toml` | 포맷팅 설정 |
| `clippy.toml` | 린터 설정 |

### 5.3 React/Vite

| 생성 파일 | 내용 |
|----------|------|
| `package.json` | 의존성 (react, react-dom, vite, typescript), scripts (dev, build, preview, lint) |
| `vite.config.ts` | React 플러그인, 빌드 출력 경로, 프록시 설정 (API 서버 연동) |
| `tsconfig.json` | TypeScript 설정 (strict, JSX, path alias) |
| `tsconfig.node.json` | Vite 설정 파일용 TypeScript 설정 |
| `index.html` | SPA 진입점 (root div, script 태그) |
| `.eslintrc.cjs` | ESLint 설정 (react-hooks, react-refresh 플러그인) |

### 5.4 NestJS

| 생성 파일 | 내용 |
|----------|------|
| `package.json` | 의존성, scripts |
| `tsconfig.json` | TypeScript 설정 |
| `nest-cli.json` | NestJS CLI 설정 |
| `.eslintrc.js` | ESLint 설정 |

### 5.5 Django

| 생성 파일 | 내용 |
|----------|------|
| `pyproject.toml` | 프로젝트 메타데이터, 의존성, 도구 설정 |
| `manage.py` | Django 관리 스크립트 |
| settings 구조 | `settings/base.py`, `settings/local.py` |

### 5.6 ASP.NET Core

| 생성 파일 | 내용 |
|----------|------|
| `{SystemName}.sln` | 솔루션 파일 |
| `*.csproj` | 프로젝트별 설정 |
| `global.json` | SDK 버전 고정 |
| `nuget.config` | NuGet 소스 설정 |

## Step 5.5: 빌드 래퍼 스크립트 생성

Step 3~5 (플랫폼별 빌드 파일 생성) 완료 후, `tools/build.ps1` (Windows) / `tools/build.sh` (Linux/macOS)를 생성한다. `--install-only` 시 건너뛴다.

### 5.5.1 생성 조건

- `tools/build.ps1` 또는 `tools/build.sh`가 이미 존재하면 건너뜀 (기존 빌드 파일과 동일 정책)
- `module-mapping.md`에서 감지된 플랫폼 목록이 1개 이상 있어야 생성

### 5.5.2 `tools/build.ps1` (Windows)

**인터페이스:**
```powershell
tools/build.ps1 [-Module <MODULE_CODE>] [-Configuration <Release|Debug>] [-Clean]
# 예시:
#   tools/build.ps1 -Module AGT.CORE          # 단일 모듈 빌드
#   tools/build.ps1 -Module AGT.DRVFS         # 드라이버 모듈 빌드
#   tools/build.ps1 -Module SVR.API           # Spring Boot 모듈 빌드
#   tools/build.ps1                            # 전체 빌드
#   tools/build.ps1 -Clean                     # 전체 클린
```

**동작 흐름:**
1. `doc/architecture/module-mapping.md` 파싱 → 모듈코드/플랫폼/src경로/유형 테이블 구축
2. `-Module` 지정 시 해당 모듈만, 미지정 시 전체 모듈 순회
3. 플랫폼별 빌드 명령 분기:

| 플랫폼 | 빌드 명령 | 비고 |
|--------|----------|------|
| C++/CMake | `cmake --build build --target {target}` | 루트 CMakeLists.txt 기준, target = 모듈코드 소문자 (`agt_core`) |
| Windows Driver | vswhere → MSBuild.exe → vcxproj 빌드 | `_common.ps1`의 드라이버 빌드 로직 재활용 |
| Spring Boot | `gradlew :{module-name}:build` | settings.gradle 서브프로젝트명 기준 |
| React/Vite | `npm run build` (해당 src 디렉토리에서) | |
| Go | `go build ./...` (해당 src 디렉토리에서) | |
| Rust | `cargo build -p {crate-name}` | workspace 기준 |
| NestJS | `npm run build` (해당 src 디렉토리에서) | |
| Django | `python manage.py check` | 빌드 개념이 없으므로 check로 대체 |
| ASP.NET Core | `dotnet build {project}.csproj` | |

4. 빌드 결과 출력: `[OK] AGT.CORE 빌드 성공` 또는 `[FAIL] AGT.CORE 빌드 실패: {에러}`
5. 종료 코드: 성공 0, 실패 1

**핵심 설계 원칙:**
- `module-mapping.md`가 유일한 진실의 원천 (모듈 목록, 경로, 플랫폼 모두 여기서 파싱)
- 스크립트 자체는 빌드 도구 설치를 하지 않음 (dev-setup의 install 단계에서 이미 완료됨을 전제)
- 드라이버 빌드 로직은 `_common.ps1`에서 검증된 패턴(vswhere → MSBuild → WDK 감지)을 그대로 사용

### 5.5.3 `tools/build.sh` (Linux/macOS)

Windows Driver 빌드는 제외, 크로스플랫폼 빌드만 지원.
인터페이스: `tools/build.sh [--module MODULE_CODE] [--configuration Release|Debug] [--clean]`
동작 흐름은 `build.ps1`과 동일하되 Windows Driver 분기를 제외한다.

## Step 6: 개발 도구 설정 파일 생성

프로젝트 루트에 개발 환경 설정 파일을 생성한다. `--install-only` 시 건너뛴다.

### 6.1 .editorconfig

모듈이 하나라도 존재하는 경우 생성. 감지된 플랫폼별 파일 확장자 섹션을 포함한다.

### 6.2 .clang-format

C++/CMake 모듈 존재 시에만 생성. 설계서 코드 스타일 규정 적용, 없으면 Google 스타일 기반.

### 6.3 .gitignore

프로젝트 루트에 `.gitignore`가 없는 경우에만 생성.
감지된 플랫폼에 따라 `.claude/skills/dev-setup/assets/templates/.gitignore-fragments/{platform}.gitignore`에서 해당 패턴을 조합한다.

공통 패턴 추가: `.temp/`, `*.log`

## Step 7: 출력 및 검증

### 7.1 생성 결과 보고

```
=== dev-setup 완료 ===

설치된 도구: (Step 2 실행 시)
  [OK] CMake 3.28.1
  [OK] vcpkg 2024.01.12
  ...

생성된 파일:
  빌드 파일: {N}개
    - {파일 목록}
  개발 도구: {M}개
    - .editorconfig, .gitignore, ...

건너뛴 파일: {K}개 (이미 존재)
```

### 7.2 일관성 검증

| 검증 항목 | 방법 |
|----------|------|
| 빌드 파일 누락 | module-mapping.md의 모듈별 src 경로에 빌드 파일 존재 여부 확인 |
| 빌드 설정 일관성 | 루트 빌드 파일의 하위 모듈 참조가 실제 경로와 일치하는지 확인 |
| 설치 검증 (Step 2 실행 시) | 설치된 도구가 최소 버전 이상인지 재확인 |

검증 결과를 출력하고, 누락이 있으면 즉시 해당 파일을 추가 생성한다.

</Steps>

<Escalation_And_Stop_Conditions>
- **module-mapping.md 없음** (빌드 파일 모드): 즉시 중단. "/project-scaffold를 먼저 실행하세요" 안내
- **src/ 없음** (빌드 파일 모드): 즉시 중단
- **설계서 없음** (빌드 파일 모드): 경고 출력 후 기본 템플릿으로 진행
- **플랫폼 참조 문서 없음**: 경고만 출력하고 기본 템플릿으로 계속 진행
- **기존 빌드 파일 존재**: 덮어쓰지 않고 건너뜀 + 목록 보고. `--force` 없이는 덮어쓰기 금지
- **알 수 없는 플랫폼**: 해당 모듈에 대해 경고 출력 후 건너뜀
- **설치 실패**: `[FAIL]` 로그 출력, 나머지 도구 설치는 계속 진행, 최종 보고에 실패 항목 포함
- **관리자 권한 필요**: 사용자에게 권한 상승 안내 후 대기
</Escalation_And_Stop_Conditions>

<Examples>

<Good>
--install-only로 환경 설치만 실행:
```
사용자: /dev-setup cpp --install-only
스킬: OS 감지 (Windows) → scripts/windows/install-cpp.ps1 실행
      CMake, Ninja, vcpkg 설치 → 검증 완료
      빌드 파일 생성 skip
```
</Good>

<Good>
--check로 설치 상태 확인만:
```
사용자: /dev-setup --check
스킬: 감지된 플랫폼(cpp, springboot)에 대해 사전 검사 실행
      [OK] CMake 3.28.1, [OK] JDK 17.0.9, [INSTALL] vcpkg — 미설치
      실제 설치 수행하지 않음
```
</Good>

<Good>
--build-only로 기존 동작 호환:
```
사용자: /dev-setup agt --build-only
스킬: 설치 skip → CMakeLists.txt만 생성 (기존 동작과 동일)
```
</Good>

<Good>
module-mapping.md 기반으로 정확한 유형 판별:
```
모듈코드: AGT.CORE, 유형: DLL, src: src/agt/core/core/
→ add_library(agt_core SHARED ...)

모듈코드: AGT.TRAY, 유형: EXE, src: src/agt/ui/tray/
→ add_executable(agt_tray ...)
```
</Good>

<Good>
.gitignore를 플랫폼 조각에서 조합:
```
프로젝트에 cpp + springboot 모듈 존재
→ cpp.gitignore + springboot.gitignore 조각 병합
→ 공통 패턴(.temp/, *.log) 추가
→ .gitignore 생성
```
</Good>

<Bad>
설계서 없이 의존성 블록을 임의로 생성:
```cmake
# 설계서에 없는 라이브러리를 임의로 추가 (X)
FetchContent_Declare(boost ...)
```
의존성은 반드시 설계서 2절(기술 스택)에 명시된 항목만 포함한다.
</Bad>

<Bad>
모듈 유형을 무시하고 모두 동일한 빌드 명령 사용:
```cmake
add_library(agt_tray ...)  # ← EXE 유형이므로 add_executable이어야 함
```
</Bad>

<Bad>
플랫폼에 맞지 않는 빌드 파일 생성:
```
src/svr/api/CMakeLists.txt  (X) ← Spring Boot 모듈은 build.gradle만 생성
```
</Bad>

</Examples>

<Tool_Usage>
- **Read 도구**: `module-mapping.md`, 설계서, 플랫폼 참조 문서, `references/platforms/*.md` 읽기
- **Glob 도구**: `doc/designs/*.md` 탐색, 기존 빌드 파일 존재 확인
- **Write 도구**: 빌드 파일, 설정 파일 생성
- **Bash 도구**: `ls`로 src/ 구조 확인, 설치 스크립트 실행 (`scripts/{os}/install-{platform}`)
- **Grep 도구**: 설계서에서 기술 스택 절 탐색, 외부 라이브러리 추출
</Tool_Usage>

<Final_Checklist>
- [ ] `doc/architecture/module-mapping.md`를 읽어서 모든 모듈의 유형과 플랫폼을 파악했는가?
- [ ] 감지된 플랫폼이 7개 지원 플랫폼 중 어떤 것인지 정확히 분류했는가?
- [ ] 설계서 2절(기술 스택)에서 외부 라이브러리와 버전을 추출했는가?
- [ ] `--install-only`/`--build-only`/`--check` 모드에 따라 올바른 Step만 실행했는가?
- [ ] OS를 정확히 감지하고 올바른 스크립트 경로(windows/linux/macos)를 선택했는가?
- [ ] 설치 전 사전 검사를 실행하고 사용자 확인을 받았는가?
- [ ] 각 플랫폼별 빌드 파일이 모듈 유형에 맞게 생성되었는가?
- [ ] `.gitignore`를 플랫폼별 조각 파일에서 올바르게 조합했는가?
- [ ] 기존 빌드 파일을 덮어쓰지 않고 건너뛰었는가?
- [ ] `--dry-run` 시 실제 파일을 생성하지 않고 예정 목록만 출력했는가?
- [ ] 생성 완료 후 일관성 검증을 수행하고 결과를 보고했는가?
</Final_Checklist>
