# 보드 DPU 재생

명령은 저장소 루트에서 실행한다. `BOARD`에는 키 인증이 준비된 SSH 대상을 로컬 환경 변수로 지정한다. PetaLinux 2024.1의 `xdputil query`에서 `DPUCZDX8G_ISA1_B4096`, 300 MHz, 1코어, 지문 `0x101000056010407`, `is_vivado_flow=true`를 확인했다. 커널은 6.6.10 aarch64, Python 3.10.6, numpy 1.23.3, Pillow 9.4.0, VART 4.0.0, Vitis AI Library 3.5.0이다. `vart`·`xir` import, `/dev/dpu`, UIO 9개를 확인했다. 호스트 경과 시간을 재며 보드의 날짜는 사용하지 않는다.

1. DPU·스토리지·사용 중 프로세스를 확인한다. `ssh -o BatchMode=yes -o ConnectTimeout=5 "$BOARD" 'xdputil query; ls -l /dev/dpu; df -h /; python3 -c "import vart,xir,numpy,PIL; print(numpy.__version__,PIL.__version__)"; fuser /dev/dpu; ps -ef'`
2. 이미 있는 네 모델의 해시를 확인한다. `ssh -o BatchMode=yes -o ConnectTimeout=5 "$BOARD" 'sha256sum /home/root/exp/models/yolov8n_dpu.xmodel /home/root/exp/v2live/v2_yolo_A_s0.xmodel /home/root/exp/v2live/v2_yolo_A_full_s1.xmodel /home/root/exp/v2live/v2_yolo_A_full_s2.xmodel'`
3. 패키지를 구성하고 새 디렉터리를 만든다. 기존 경로가 있으면 `mkdir`에서 멈춘다. `ai/scripts/make_deploy.sh && ssh -o BatchMode=yes -o ConnectTimeout=5 "$BOARD" 'mkdir /home/root/v2ai10'`
4. 패키지 항목을 개별 경로로 전송한다. `scp -r -o BatchMode=yes -o ConnectTimeout=5 build/ai/deploy10/{images,demo_list.txt,package.sha256,run_detector.py,run_on_board.sh,yolov8n_dpu_v2rebuild.xmodel} "$BOARD:/home/root/v2ai10/"`
5. 모델 다섯 개를 순서대로 실행한다. 각 모델은 `demo_list.txt`가 지정한 정본 테스트 JPG 10장에 대해 `--norm unit --conf 0.25 --iou 0.45 --warmup 3`을 사용한다. `ssh -o BatchMode=yes -o ConnectTimeout=5 "$BOARD" 'cd /home/root/v2ai10 && sh run_on_board.sh'`
6. 분리된 로컬 경로로 회수하고 대조한다. `out=$(mktemp -d build/ai/received10.XXXXXX) && scp -r -o BatchMode=yes -o ConnectTimeout=5 "$BOARD:/home/root/v2ai10/results/*" "$out/" && scp -o BatchMode=yes -o ConnectTimeout=5 "$BOARD:/home/root/v2ai10/results.sha256" "$out/" && (cd "$out" && sha256sum -c results.sha256)`
7. 검증이 끝난 결과를 `ai/results/board`에 반영한다. 기존 최초 6장 결과는 `ai/results/board_6img`에 보존했다. 호스트 10장 결과도 준비한 뒤 `python3 ai/scripts/compare_results.py`로 대조표와 JSON을 생성한다.

5단계 스크립트는 업로드 해시를 먼저 확인하고 각 추론 직전에 `fuser /dev/dpu`로 점검한다. 개별 종료 코드·벽시계 시간·정확한 명령은 모델별 디렉터리에 남긴다. `/home/root/exp/`의 기존 모델은 원래 경로에서 읽는다. `/home/root/v2ai10/`에는 재구축 모델, 데모 JPG, 실행 스크립트 및 이 실행의 결과가 남는다. 2026-11-23 실행에서 모델 5개가 각각 10장을 처리했고, 회수한 15개 파일의 해시를 검증했다. [실행 결과](RESULTS.md)
