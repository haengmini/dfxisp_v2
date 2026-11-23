# YOLOv8n 재구축 결과

2026-11-23 KST. CPU Docker Vitis AI 3.5 및 ZCU104. 4장 보드 재생은 정본 테스트 세트 PASCAL 5장과 LOD(RAW-NOD) 5장을 사용했다. 4장 결과는 정확도 평가가 아닌 DPU 동작 확인용이다. 모든 검출은 640×640 stretch, 입력 /255, conf 0.25, NMS IoU 0.45를 사용한다.

## 기존 모델의 PC 양자화·컴파일

| 단계 | 결과 | 실행 초 | 최대 RSS (KiB) |
| --- | --- | ---: | ---: |
| S0 환경 | Python 3.8.6, torch 1.13.1, Ultralytics 8.3.0, NNDCT 3.5.0, XIR 및 `vai_c_xir` 확인 | — | — |
| S1 체크포인트 변환 | 355키, 3클래스, SPPF Identity 활성화 보존 | 1.28 | 289,348 |
| S2 고정 목록 | LOD 64장, PASCAL 64장, 최초 데모 6장 제외 | — | — |
| S3 calib | `CALIB_DONE 128` | 215.54 | 582,164 |
| S3 test/export | `EXPORT_DONE batch=1`. `build/ai/quant/RawHead_int.xmodel` | 3.81 | 801,600 |
| S4 compile | `Compile done.` 및 XIR 지문 일치 | 8.67 | 556,772 |
| S5 구조 비교 | 5개 xmodel XIR 역직렬화 및 대조 | 0.15 | 34,544 |
| 4장 호스트 | 10장, 세 방식 검출. 원본과 복원한 SiLU FP32의 60개 head 텐서 최대 절대 차이 0 | 8.37 | 707,788 |
| 4장 패키지 | 해시 검증 PASS, 8,550,215 B | — | — |

첫 보정은 보드 전처리 확인 후 OpenCV에서 Pillow로 바꾸고 다시 실행했다. 체크포인트의 첫 재구성에서는 SPPF `model.9.cv1.act`의 Identity가 누락돼 원본 FP32와 최대 5.2379055 차이가 발생했다. Identity를 복원하고 같은 데이터·옵션으로 다시 실행했다. 경과 시간과 RSS는 각 컨테이너 내부 도구 프로세스 기준이다. 최종 모델은 4,327,213 B, SHA-256 `a81d5331a1d0403f5cf019bdc119919bb40b38307f9e768ce6e8d9e969abd858`. [환경](../build/ai/env.md) · [모델](models/rebuilt/yolov8n_dpu_v2rebuild.xmodel) · [기존 단계 로그](../build/ai/logs/) · [4장 패키지 해시](../build/ai/deploy10/package.sha256)

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

## 4장 호스트와 보드 검출

4장에서는 기존 보정 목록과 xmodel(`a81d5331…`)을 그대로 사용했다. 호스트 INT8은 기존 양자화 설정·bias의 복사본으로 test 모드 추론을 수행했다. 아래 두 이미지가 기존 보정 목록에도 포함되어 있다.

| JPG | 출처 | 보정 목록에도 포함 | 재구축 DPU 검출 / GT 대응 |
| --- | --- | --- | ---: |
| `2014_000888.jpg` | PASCAL | — | 1 / 1 |
| `2014_001610.jpg` | PASCAL | — | 4 / 4 |
| `2014_002785.jpg` | PASCAL | — | 2 / 2 |
| `2014_003044.jpg` | PASCAL | 예 | 3 / 2 |
| `2014_004106.jpg` | PASCAL | — | 2 / 2 |
| `DSC01845.jpg` | LOD | — | 9 / 6 |
| `DSC02077.jpg` | LOD | — | 13 / 11 |
| `DSC02790.jpg` | LOD | — | 3 / 3 |
| `DSC02903.jpg` | LOD | — | 16 / 9 |
| `DSC03927.jpg` | LOD | 예 | 7 / 5 |


호스트 검출 / GT 대응은 SiLU FP32 **44 / 40**, Hardswish FP32 **62 / 46**, Hardswish INT8 **60 / 45**였다. SiLU → Hardswish FP32의 대응은 44/44와 44/62, Hardswish FP32 → INT8의 대응은 57/62와 57/60이다. [10장 대조표](results/comparison.md) · [대조 JSON](results/comparison.json)

| 보드 모델 | 총 검출 / GT 대응 | DPU (ms/장) | 처리 (ms/장) | 10장 실행 (초) |
| --- | ---: | ---: | ---: | ---: |
| 재구축 | 60 / 45 | 66.1 | 208.8 | 4.688 |
| reference | 62 / 42 | 65.4 | 207.3 | 4.604 |
| v2live 시드 0 | 56 / 49 | 65.3 | 207.3 | 4.522 |
| v2live 시드 1 | 53 / 47 | 65.4 | 207.6 | 4.530 |
| v2live 시드 2 | 58 / 47 | 66.0 | 208.2 | 4.519 |

5개 모델 모두 종료 코드 0이었다. DPU 시간은 첫 서브그래프 호출과 입력 양자화·출력 역양자화를 포함한다. 처리 시간은 JPG 로드를 제외한다. 10장 실행 시간에는 Python 시작, warmup 3회, JPG 로드 및 JSON 기록이 포함된다.

재구축 DPU와 호스트 INT8은 보정 목록 포함 2장에서 **10/10건**, 나머지 8장에서 **50/50건**이 대응했다. 검출 순서와 클래스도 같았고, 최대 좌표·점수 절대 차이는 각각 0.0001221 px, 5.96×10⁻⁸이었다.

보드 사전 점검에서 기존 모델 4개의 해시와 DPU 지문을 확인했다. 새 패키지는 `/home/root/v2ai10/`의 해시 검사에서 통과했고, 회수한 파일 15개도 SHA-256이 일치했다. [10장 보드 JSON·로그](results/board/) · [기존 6장 보드 결과](results/board_6img/) · [실행과 회수 해시 로그](../build/ai/ch4/)
