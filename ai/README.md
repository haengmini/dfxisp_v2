# YOLOv8n 양자화·컴파일·보드 DPU 재생

객체 검출기는 ISP·DFX 연구의 평가 도구다. 저장된 3클래스 YOLOv8n(`person`, `car`, `bicycle`)을 640×640 RGB 입력으로 재양자화·컴파일하고 JPG 6장으로 보드 DPU 출력을 확인한다. [DPU 설정](DPU_CONFIG.md) · [보드 명령](BOARD_RUN.md) · [측정 결과](RESULTS.md)

## 환경

Vitis AI 3.5 CPU Docker `xilinx/vitis-ai-pytorch-cpu:latest` (`baf43fd9d6e1`), Python 3.8.6, PyTorch 1.13.1, Ultralytics 8.3.0, NNDCT 3.5.0, XIR 및 `vai_c_xir`. 기본 이미지에 Ultralytics가 없어 아래 wheel을 검증한 뒤 컨테이너 안 `/tmp/vendor`에 오프라인으로 설치한다. 컨테이너는 `--network none`, CPU 및 스레드 6개로 한 개씩 실행한다. [실행 환경 기록](../build/ai/env.md)

```bash
mkdir -p build/ai/wheels && curl -fsSL https://files.pythonhosted.org/packages/ef/67/78eac779c488f10d4977b0a7ff9bb4ecc91acecf6c37455e2ce34b1b335e/ultralytics-8.3.0-py3-none-any.whl -o build/ai/wheels/ultralytics-8.3.0-py3-none-any.whl && printf '%s  %s\n' 3137c4921c18c8ddf610f64f1badc2dad2a9fd182e10218c2bbb29caee308b9e build/ai/wheels/ultralytics-8.3.0-py3-none-any.whl | sha256sum -c -
```

## 재구축 절차

저장소 루트에서 실행한다. 보정 목록 파일은 이미 정해 두었다. 목록을 재생성할 때는 `python3 ai/scripts/select_calibration.py ../dfxisp_essen/dataset`를 실행한다.

```bash
ai/scripts/run_quant.sh all && ai/scripts/make_deploy.sh
```

1. 보관 `.pt`를 `state_dict` 355키로 변환한다. 8.3.0의 기본 분류 head 대신 체크포인트와 같은 Conv–Conv–Conv2d head를 구성하고 BN 설정을 맞춘다. 원래 SPPF의 `model.9.cv1.act`는 Identity로 복원한다. 가중치는 strict load하고 호스트에서 원본 SiLU head와 6장×6텐서를 대조한다.
2. 데모 6장을 제외하고 `LOD_test/images`, `PASCAL_test/images` 각각 97개 JPG 중 64개씩 시드 `20261014`로 고정했다. [보정 목록](data/calib_list.txt)
3. 이번 보정은 학습 데이터 부재로 test split의 참조 JPG를 사용한다. 10월 절차는 학습 분할의 ISP 출력 PNG 128장(야간 Normal 40, Lowlight 40, 주간 48)을 사용했다. 이번에는 보드 영상 경로와 같은 Pillow bilinear 640×640 stretch(패딩 없음), RGB / 255를 사용한다. 데모는 quantizer test 모드의 batch 1 export 호출 및 추론 비교에만 사용한다.
4. 보관 모델의 SiLU를 Hardswish로 치환한 head를 양자화한다. `vai_c_xir -x /work/quant/RawHead_int.xmodel -a /input/arch/arch.json -o /work/compiled -n yolov8n_dpu_v2rebuild`로 컴파일한다. DFL·디코드·NMS는 보드 앱의 numpy 경로고, 그 앞의 6개 head 텐서를 사용한다.
5. XIR로 서브그래프, 텐서, 활성화 구조, 지문을 비교한다. 호스트에서 SiLU FP32, Hardswish FP32, Hardswish INT8을 추론한다. 보드 추론에는 동일한 conf 0.25, NMS IoU 0.45를 쓴다. [보드 전송·재생·회수](BOARD_RUN.md)

V2 스크립트는 정본 `2026-10-v2-board/scripts/audit/{quant_v2,export_seed,host_int8_test,eval_v2}.py`와 `quant_seeds.sh`에서 절차를 확인해 새로 작성했다. 보드 앱의 SSD 경로는 이번에 사용하지 않는다.

## 학습(이번 재구축에서 생략)

10월에는 보관 `yolov8n.pt`를 BASE로 불러와 학습 전에 SiLU를 Hardswish로 바꿨다. 야간의 같은 프레임에서 Normal·Lowlight(BLC16) 두 뷰와 주간 replay를 사용하고, `data.yaml`에 `person/car/bicycle`을 지정했다. `A_full`은 전체 파라미터, `B_freeze10`은 백본 0–9층을 고정한 시험군이다. 기본 30 epoch, SGD `lr0=0.002`, 입력 640, 배치 16, 인자로 받은 시드와 deterministic 설정을 사용했다. 근거는 `dfxisp_essen/2026-10-v2-board/scripts/audit/train_v2.py:1–25,27–56`이다. 보관된 `v2live` xmodel은 이 연구에서 학습한 A_full의 시드 0·1·2 컴파일본이다. 근거는 `notes/2026-10-14-v2-balanced-model-board-replay.md:9–18,100–102`와 아래 해시다. 이 PC에는 당시 작업 폴더와 학습 데이터가 없어 학습을 재현할 수 없다.

## 이관 파일

`cmp`로 출처와 모두 대조했다. 기존 배포 xmodel과 보드 앱은 백업본에도 바이트 단위로 일치했다. LOD 3장은 `DSC01845`, `DSC02077`, `DSC02790`, PASCAL 3장은 `2014_000888`, `2014_001610`, `2014_002785`이다. 선택 순서는 정본 `dataset/test`의 데이터셋별 파일명 오름차순이다.

| 파일 | 출처 | 크기 (B) | SHA-256 |
| --- | --- | ---: | --- |
| `arch/arch.json` | 정본 hw/NormalISP_DPU/arch.json | 36 | `6feb79ba36f1f030f7827d94cdd8b43ff03faec72dad8e4a4e4d72704ed8490e` |
| `board/run_detector.py` | 정본 experiment_v2/app/run_detector.py | 12641 | `5b228c310ee6bed2e4affe090caee3e205521e8703be0027c59d01df3fb3d756` |
| `data/demo/images/2014_000888.jpg` | 정본 dataset/test/images/2014_000888.jpg | 186728 | `60d6f8cdd9c20d168bf5c9057fbc5098ad2291b2adc275f8ea11e24d7c5b3a85` |
| `data/demo/images/2014_001610.jpg` | 정본 dataset/test/images/2014_001610.jpg | 264399 | `3cc15bb07ef8c0ef0104a5655443b149291161a8b849cb913b32ae8880f69971` |
| `data/demo/images/2014_002785.jpg` | 정본 dataset/test/images/2014_002785.jpg | 197247 | `7d1d367b2930811eac23676866b5ff87ac586a32e907e1b2433fcc4b7b226dea` |
| `data/demo/images/DSC01845.jpg` | 정본 dataset/test/images/DSC01845.jpg | 452500 | `bb31d0c969857e6fe84c4a9e8300918b400fe3f77fdd391d71ae2d8107008cf3` |
| `data/demo/images/DSC02077.jpg` | 정본 dataset/test/images/DSC02077.jpg | 766088 | `5cfaa11c0618be4f14f980cbe8bc1c93cc917af98cadebcf9d1af54ccd4460ee` |
| `data/demo/images/DSC02790.jpg` | 정본 dataset/test/images/DSC02790.jpg | 736833 | `f3512b1b383cee8799a9a6b2c2bf7548c7cf9a39fe3ec2f68df1655a249af11f` |
| `data/demo/labels/2014_000888.txt` | 정본 dataset/test/labels/2014_000888.txt | 37 | `13a23325e52d7f95026c27314b9b3470c36f5731cc38b4cb53b9243b4afeee86` |
| `data/demo/labels/2014_001610.txt` | 정본 dataset/test/labels/2014_001610.txt | 151 | `e7fa07abbed94a688286cea753fd2a452d80a43f73b6d14c4eb8bdf1c0db1760` |
| `data/demo/labels/2014_002785.txt` | 정본 dataset/test/labels/2014_002785.txt | 113 | `f94e841bbe7f1df0fd653111ae802b8504621818582001173aca429ddde311a4` |
| `data/demo/labels/DSC01845.txt` | 정본 dataset/test/labels/DSC01845.txt | 341 | `69f610de4fa97ca8ebf3fb4b87e03a257f25864c616d29f4c10e78206bf087b4` |
| `data/demo/labels/DSC02077.txt` | 정본 dataset/test/labels/DSC02077.txt | 721 | `c6a4d339a4575072ba33cbd8576a4ba9c093375e48842331d8ba4dee562bd493` |
| `data/demo/labels/DSC02790.txt` | 정본 dataset/test/labels/DSC02790.txt | 151 | `da18a39bc92b9032639c19275747272e26deb299e111a21b94aa0886689c8753` |
| `models/reference/v2live/v2_yolo_A_full_s1.xmodel` | 보드 SD /home/root/exp/v2live (백업본) | 4314429 | `b747014257ac6924287b92cd34ed9fff417a279ef6435c6221b3c1e864ff55b0` |
| `models/reference/v2live/v2_yolo_A_full_s2.xmodel` | 보드 SD /home/root/exp/v2live (백업본) | 4316189 | `ca8dd8181a77f1f138367ef425b450c89718369a32bcf5a586dc02b450e3588c` |
| `models/reference/v2live/v2_yolo_A_s0.xmodel` | 보드 SD /home/root/exp/v2live (백업본) | 4325149 | `4565206dc2dbd03a8fcc312a558e5b4bd1763dbf87b26e8ec1f4b7952f202357` |
| `models/reference/yolov8n_dpu.xmodel` | 정본 hw/ai/models/yolov8n/ | 4481264 | `6713fbad2065a6b15e627b334633912c24cf691748455b9c7b82f8f269698817` |
| `models/yolov8n.pt` | 정본 hw/ai/models/yolov8n/ | 6243178 | `5d32e97ce3fafe16381e2e18c6da78e8c5019035d91291b5b90f50d26c63f848` |
| `models/rebuilt/yolov8n_dpu_v2rebuild.xmodel` | S4 컴파일 산출물 | 4327213 | `a81d5331a1d0403f5cf019bdc119919bb40b38307f9e768ce6e8d9e969abd858` |
