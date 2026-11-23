# YOLOv8n 재구축 결과

2026-11-23 KST. CPU Docker Vitis AI 3.5 및 ZCU104. PASCAL 3장과 LOD(RAW-NOD) 3장을 선택 순서로 고정했다. 모든 검출은 640×640 stretch, 입력 /255, conf 0.25, NMS IoU 0.45를 사용한다.

## PC 양자화·컴파일

| 단계 | 결과 | 실행 초 | 최대 RSS (KiB) |
| --- | --- | ---: | ---: |
| S0 환경 | Python 3.8.6, torch 1.13.1, Ultralytics 8.3.0, NNDCT 3.5.0, XIR 및 `vai_c_xir` 확인 | — | — |
| S1 체크포인트 변환 | 355키, 3클래스, SPPF Identity 활성화 보존 | 1.28 | 289,348 |
| S2 고정 목록 | LOD 64장, PASCAL 64장, 데모 6장 제외 | — | — |
| S3 calib | `CALIB_DONE 128` | 215.54 | 582,164 |
| S3 test/export | `EXPORT_DONE batch=1`. `build/ai/quant/RawHead_int.xmodel` | 3.81 | 801,600 |
| S4 compile | `Compile done.` 및 XIR 지문 일치 | 8.67 | 556,772 |
| S5 구조 비교 | 5개 xmodel XIR 역직렬화 및 대조 | 0.15 | 34,544 |
| S6 호스트 | 고정 데모 6장, 세 방식 검출. 원본과 복원한 SiLU FP32의 36개 head 텐서 최대 절대 차이 0 | 6.24 | 713,920 |
| S7 패키지 | 해시 검증 PASS, 6,946,133 B | — | — |

첫 보정은 보드 전처리 확인 후 OpenCV에서 Pillow로 바꾸고 다시 실행했다. 체크포인트의 첫 재구성에서는 SPPF `model.9.cv1.act`의 Identity가 누락돼 원본 FP32와 최대 5.2379055 차이가 발생했다. Identity를 복원하고 같은 데이터·옵션으로 다시 실행했다. 경과 시간과 RSS는 각 컨테이너 내부 도구 프로세스 기준이다. 최종 모델은 4,327,213 B, SHA-256 `a81d5331a1d0403f5cf019bdc119919bb40b38307f9e768ce6e8d9e969abd858`. [환경](../build/ai/env.md) · [모델](../build/ai/compiled/yolov8n_dpu_v2rebuild.xmodel) · [단계 로그](../build/ai/logs/) · [패키지 해시](../build/ai/deploy/package.sha256)

## XIR 구조

모든 DPU 서브그래프의 지문은 `0x101000056010407`이다. 첫 DPU의 입출력은 모두 `xint8`이다. 입력 `[1,640,640,3]`과 스케일 80/40/20의 box 64채널·class 3채널 NHWC 출력 6개가 동일하다. 위치·정확한 tensor name·dtype·fix_point는 JSON에 저장했다. [XIR 전체 구조](results/xmodel_structures.json)

| 모델 | DPU / CPU / USER | 첫 DPU 활성화 경로 | CPU 쪽 연산 |
| --- | --- | --- | --- |
| 재구축 | 1 / 6 / 1 | `Hardswish` 이름, `hard-sigmoid-fix → eltwise-fix(mul)` 56곳 | `fix2float` 6개 |
| reference | 2 / 10 / 1 | `Hardswish` 이름, 같은 패턴 56곳 | transpose, concat, reshape, softmax, sigmoid, slice, eltwise, 정수·실수 변환 |
| `v2_yolo_A_s0` | 1 / 6 / 1 | 같은 패턴 57곳 | `fix2float` 6개 |
| `v2_yolo_A_full_s1` | 1 / 6 / 1 | 같은 패턴 57곳 | `fix2float` 6개 |
| `v2_yolo_A_full_s2` | 1 / 6 / 1 | 같은 패턴 57곳 | `fix2float` 6개 |

이름과 연결 구조에 따르면 기존 reference도 DPU 백본에서 Hardswish 형태로 컴파일된 것으로 해석된다. reference의 끝에 있는 CPU sigmoid는 클래스 점수 후처리 그래프에 있다. 두 번째 DPU는 `[1,4,8400,16]` → `[1,4,8400]`이고, 보드 앱은 첫 DPU 결과에 numpy DFL·디코드·NMS를 적용한다. 재구축의 class fix_point는 80/40/20에서 2/1/1, reference와 v2live는 2/2/2다.

## 호스트와 보드 검출

호스트 검출 총수 / GT 대응 수는 SiLU FP32 **25 / 24**, Hardswish FP32 **34 / 28**, Hardswish INT8 **32 / 27**이다. 검출 간 대응은 SiLU → Hardswish FP32 25/25와 25/34, Hardswish FP32 → INT8은 30/34와 30/32였다. 전자의 평균 점수 차이 B−A는 +0.1050, 후자는 −0.0262다. Hardswish FP32로 바꾸며 LOD 3장 중 2장의 검출 수가 늘었고 PASCAL 3장의 검출 수는 같았다. 이 수치는 고정된 6장에 한한다. [이미지별 검출·GT 및 모델 간 대조](results/comparison.md) · [대조 JSON](results/comparison.json) · [호스트 JSON·주석 이미지](results/host/)

보드 사전 점검에서 `xdputil query`의 300 MHz·1코어·지문, `/dev/dpu`, VART/XIR import, DPU 미사용 상태 및 4개 보관 모델의 백업 SHA-256 일치를 확인했다. 루트 파일시스템 여유 281 MB, 메모리 1,951,576 KiB였다. 첫 SCP는 소스 디렉터리 이름 `.`을 거부했다. 승인 후 항목별 경로를 지정해 6,946,133 B를 전송했다. 보드에서 패키지 해시를 확인했고 회수한 결과 15개도 SHA-256이 일치했다. [사전 점검](../build/ai/board_preflight.log) · [실행 명령](../build/ai/progress.md) · [회수 해시 검증](../build/ai/board_results_verified.log)

| 보드 모델 | PASCAL 3장 검출 | LOD 3장 검출 | 총 검출 / GT 대응 | DPU (ms/장) | 처리 (ms/장) | 6장 실행 (s) |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 재구축 | 1 / 4 / 2 | 9 / 13 / 3 | 32 / 27 | 65.4 | 208.3 | 4.000 |
| reference | 1 / 4 / 2 | 9 / 15 / 3 | 34 / 27 | 66.4 | 208.2 | 3.647 |
| `v2_yolo_A_s0` | 1 / 4 / 2 | 7 / 12 / 3 | 29 / 29 | 65.6 | 208.0 | 3.589 |
| `v2_yolo_A_full_s1` | 1 / 4 / 2 | 6 / 12 / 3 | 28 / 28 | 66.1 | 208.4 | 3.537 |
| `v2_yolo_A_full_s2` | 1 / 4 / 2 | 7 / 12 / 3 | 29 / 27 | 64.6 | 206.8 | 3.531 |

모든 모델의 종료 코드는 0이었다. DPU 열은 앱의 첫 서브그래프 호출 구간이며 입력 양자화와 출력 역양자화를 포함한다. 처리 열은 전처리·DPU 호출·후처리 합계로 JPG 로드를 제외한다. 6장 실행 시간은 Python 프로세스 시작부터 warmup 3회, JPG 로드, JSON 쓰기까지 포함한다. [모델별 명령·로그·JSON·주석 이미지 30장](results/board/)

재구축 DPU와 호스트 INT8은 32/32건이 대응했다. 검출 순서와 클래스가 같았으며 최대 좌표 절대 차이는 0.0001221 px, 최대 점수 절대 차이는 5.96×10⁻⁸이다. 재구축 DPU 대비 reference는 32/32 대 32/34건, v2live 세 모델은 각각 26/32 대 26/29·26/28·26/29건이 대응했다. [이미지별·모델 간 대응 및 점수 차이](results/comparison.md)
