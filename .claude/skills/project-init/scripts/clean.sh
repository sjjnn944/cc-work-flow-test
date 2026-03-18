#!/bin/bash
# 프로젝트 초기화 스크립트
# scaffold/설계 워크플로우로 생성된 산출물을 삭제한다.
# doc/base/, .claude/skills/ 등 가이드·스킬은 보존한다.

set -euo pipefail

PROJECT_ROOT="${1:-.}"

TARGETS=(
  "doc/architecture"
  "doc/develop"
  "doc/requirements"
  "src"
  "test"
)

deleted_count=0

for target in "${TARGETS[@]}"; do
  target_path="$PROJECT_ROOT/$target"
  if [ -d "$target_path" ]; then
    # 디렉토리 내부 파일/폴더만 삭제 (디렉토리 자체는 유지)
    find "$target_path" -mindepth 1 -delete 2>/dev/null || true
    echo "[CLEANED] $target/"
    ((deleted_count++))
  else
    echo "[SKIP]    $target/ (not found)"
  fi
done

echo ""
echo "초기화 완료: ${deleted_count}개 디렉토리 정리됨"
