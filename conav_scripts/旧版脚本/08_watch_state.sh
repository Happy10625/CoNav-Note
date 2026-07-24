#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "[监控] Co-Nav2 状态：SEARCHING → TARGET_CONFIRMED → APPROACHING → SUCCEEDED"
exec ros2 topic echo /semantic_explorer/state
