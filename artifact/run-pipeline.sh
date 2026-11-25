#!/usr/bin/env bash
# 一键跑完整流水线（Linux / macOS / Git Bash）
# 用法:
#   ./run-pipeline.sh                 # 用默认 BGI_HOME
#   BGI_HOME=/path/to/BetterGI ./run-pipeline.sh
#   PYTHON=python3 ./run-pipeline.sh --latest
set -euo pipefail

PYTHON="${PYTHON:-python3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LATEST=""
[[ "${1:-}" == "--latest" ]] && LATEST="--latest"

run() {
  echo ""
  echo "=== $1 ==="
  shift
  "$@"
}

if [[ -n "$LATEST" ]]; then
  run "解析扫描日志" "$PYTHON" "$HERE/parse_artifact_log.py" --latest
else
  run "解析扫描日志" "$PYTHON" "$HERE/parse_artifact_log.py"
fi
run "规则评分"  "$PYTHON" "$HERE/evaluate.py"
run "角色画像"  "$PYTHON" "$HERE/build_characters.py" --force
run "角色分配"  "$PYTHON" "$HERE/assign.py"
run "最终清单"  "$PYTHON" "$HERE/make_final_lists.py"
run "四星滚动"  "$PYTHON" "$HERE/four_star_rolling.py"

echo ""
echo "完成。产物："
echo "  $HERE/output/report.md"
echo "  $HERE/final/SUMMARY.md"
echo "  $HERE/final/lock_scheme.md"
