#!/usr/bin/env bash
set -euo pipefail
usage() {
    echo "Usage: $0 convert|calib|test|compile|structures|host|all"
}
case ${1:-} in
    -h|--help) usage; exit 0 ;;
    convert|calib|test|compile|structures|host|all) stage=$1 ;;
    *) usage >&2; exit 2 ;;
esac

ai=$(cd "$(dirname "$0")/.." && pwd)
work=$(cd "$ai/.." && pwd)/build/ai
dataset=${AI_DATASET:-$(cd "$ai/../../dfxisp_essen/dataset" && pwd)}
image=xilinx/vitis-ai-pytorch-cpu:latest
mkdir -p "$work"/{compiled,logs}
test -f "$work/wheels/ultralytics-8.3.0-py3-none-any.whl"
if [[ -n $(docker ps -q) ]]; then
    echo "An existing Docker container is running" >&2
    exit 1
fi

run() {
    local name=$1
    shift
    echo "RUN $name → $work/logs/$name.log"
    docker run --rm --network none --user "$(id -u):$(id -g)" \
        -e HOME=/tmp -e OMP_NUM_THREADS=6 -e PYTHONDONTWRITEBYTECODE=1 \
        -v "$ai:/input:ro" -v "$work:/work" -v "$dataset:/dataset:ro" \
        --entrypoint /bin/bash "$image" -lc '
            set -e
            source /opt/vitis_ai/conda/etc/profile.d/conda.sh
            conda activate vitis-ai-pytorch
            cd /work
            python -m pip install --quiet --no-index --no-deps --target /tmp/vendor /work/wheels/ultralytics-8.3.0-py3-none-any.whl
            export PYTHONPATH=/tmp/vendor
            python /input/scripts/measure.py "$@"
        ' bash "$@" > "$work/logs/$name.log" 2>&1
}

for step in convert calib test compile structures host; do
    [[ $stage == all || $step == "$stage" ]] || continue
    case $step in
        convert) run convert python /input/scripts/convert_state.py ;;
        calib) run calib python /input/scripts/quant.py calib ;;
        test) run test python /input/scripts/quant.py test ;;
        compile) run compile vai_c_xir -x /work/quant/RawHead_int.xmodel -a /input/arch/arch.json -o /work/compiled -n yolov8n_dpu_v2rebuild ;;
        structures) run structures python /input/scripts/check_xmodel.py ;;
        host) run host python /input/scripts/host_detect.py ;;
    esac
done
