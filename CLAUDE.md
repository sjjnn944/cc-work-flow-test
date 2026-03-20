# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Essential Context

> **매 대화 시작 시 반드시 읽을 파일:**
> - `doc/base/workflow/dev-workflow-8step.md` — 8단계 개발 워크플로우 가이드 (이 프로젝트의 핵심 참조 문서)
> - `.claude/skills/*/SKILL.md` — 프로젝트 스킬 파일들 (검토·수정·개선 대상)

## Project Overview

이 프로젝트는 실제 DLP 제품을 만들기 위한 것이 아니라, 개발 워크플로우와 스킬을 검토·개발하기 위한 테스트 프로젝트이다.

- **주요 목적**: `doc/base/workflow/dev-workflow-8step.md` 워크플로우 가이드 검증 및 개선
- **부가 목적**: `.claude/skills` 스킬 검토 및 개발
- DLP 관련 설계 문서와 코드는 워크플로우 테스트를 위한 샘플 데이터로만 활용

## Architecture

(Describe the system architecture after design phase)

## Directory Structure

```
src/           # Source code
doc/           # Documentation
tests/         # Test code
scripts/       # Build and utility scripts
```

## Build & Run

(Add build and run instructions here)

## Testing

(Add testing instructions here)

## Conventions

- Follow the coding conventions in `doc/base/`
- All modules use library-based development (implement in library/, wrap in module/)
- Test only public interfaces (no internal implementation testing)
