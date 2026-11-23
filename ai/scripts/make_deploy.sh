#!/usr/bin/env bash
set -euo pipefail
ai=$(cd "$(dirname "$0")/.." && pwd)
work=$(cd "$ai/.." && pwd)/build/ai
deploy=$work/deploy10
demo=$ai/data/demo
model=yolov8n_dpu_v2rebuild.xmodel
mkdir -p "$deploy/images"
mapfile -t stems < "$demo/demo_list.txt"
(( ${#stems[@]} > 0 ))
declare -A seen=()
images=()
for stem in "${stems[@]}"; do
    [[ $stem =~ ^[A-Za-z0-9_-]+$ && ! ${seen[$stem]+listed} ]]
    seen[$stem]=1
    file=images/$stem.jpg
    cp "$demo/$file" "$deploy/$file"
    images+=("$file")
done
cp "$ai/models/rebuilt/$model" "$deploy/"
cp "$demo/demo_list.txt" "$ai/board/run_detector.py" "$ai/scripts/run_on_board.sh" "$deploy/"
cd "$deploy"
sha256sum "${images[@]}" demo_list.txt run_detector.py run_on_board.sh "$model" > package.sha256
sha256sum -c package.sha256
size=$(find . -type f -printf '%s\n' | awk '{n += $1} END {print n}')
((size <= 20000000))
printf 'PACKAGE_BYTES %s\n' "$size"
