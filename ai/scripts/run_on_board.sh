#!/bin/sh
set -eu
cd "$(dirname "$0")"
sha256sum -c package.sha256
python3 - <<'PYBOARD'
from pathlib import Path
import re

stems = Path("demo_list.txt").read_text().splitlines()
if not stems or len(set(stems)) != len(stems) or any(
        not re.fullmatch(r"[A-Za-z0-9_-]+", stem) for stem in stems):
    raise SystemExit("Invalid demo_list.txt")
expected = {f"{stem}.jpg" for stem in stems}
if {p.name for p in Path("images").iterdir()} != expected:
    raise SystemExit("Image directory does not match demo_list.txt")
print(f"BOARD_IMAGES={len(stems)}", flush=True)
PYBOARD
mkdir results
failed=0
for name in rebuild reference v2_yolo_A_s0 v2_yolo_A_full_s1 v2_yolo_A_full_s2; do
    case $name in
        rebuild) model=yolov8n_dpu_v2rebuild.xmodel ;;
        reference) model=/home/root/exp/models/yolov8n_dpu.xmodel ;;
        *) model=/home/root/exp/v2live/$name.xmodel ;;
    esac
    if ! command -v fuser >/dev/null; then
        echo "fuser unavailable" >&2
        exit 2
    fi
    if fuser /dev/dpu; then
        echo "DPU busy" >&2
        exit 2
    fi
    mkdir "results/$name"
    printf '%s\n' "python3 run_detector.py --model yolov8n --xmodel $model --images images --out results/$name/detections.json --norm unit --conf 0.25 --iou 0.45 --warmup 3" > "results/$name/command.txt"
    if python3 -u - "$model" "results/$name/detections.json" > "results/$name/run.log" 2>&1 <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import time

start = time.monotonic()
result = subprocess.run(["python3", "run_detector.py", "--model", "yolov8n",
                         "--xmodel", sys.argv[1], "--images", "images",
                         "--out", sys.argv[2], "--norm", "unit", "--conf", "0.25",
                         "--iou", "0.45", "--warmup", "3"])
if result.returncode == 0:
    images = json.loads(Path(sys.argv[2]).read_text())["images"]
    stems = Path("demo_list.txt").read_text().splitlines()
    if set(images) != {f"{stem}.jpg" for stem in stems} or len(images) != len(stems):
        raise SystemExit("Result images do not match demo_list.txt")
print(f"BOARD_RUN exit={result.returncode} wall_s={time.monotonic()-start:.3f}", flush=True)
sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
PY
    then
        printf '%s PASS\n' "$name"
    else
        failed=1
        printf '%s FAIL\n' "$name"
    fi
done
(cd results && sha256sum */command.txt */run.log && for f in */detections.json; do
    [ ! -f "$f" ] || sha256sum "$f"
done) > results.sha256
exit "$failed"
