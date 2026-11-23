#!/usr/bin/env bash
set -euo pipefail
ai=$(cd "$(dirname "$0")/.." && pwd)
work=$(cd "$ai/.." && pwd)/build/ai
deploy=$work/deploy
mkdir -p "$deploy/images"
cp "$work/compiled/yolov8n_dpu_v2rebuild.xmodel" "$deploy/"
cp "$ai"/data/demo/images/*.jpg "$deploy/images/"
cp "$ai"/board/run_detector.py "$ai"/scripts/run_on_board.sh "$deploy/"
cd "$deploy"
sha256sum images/*.jpg run_detector.py run_on_board.sh yolov8n_dpu_v2rebuild.xmodel > package.sha256
sha256sum -c package.sha256
size=$(find . -type f -printf '%s\n' | awk '{n += $1} END {print n}')
((size <= 20000000))
printf 'PACKAGE_BYTES %s\n' "$size"
