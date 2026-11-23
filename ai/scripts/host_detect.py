import argparse
import json
import time

import torch

from quant import AI, WORK, RawHead, detector, input_tensor, quantizer


def validate_silu_head(model):
    from ultralytics import YOLO

    checkpoint = YOLO(str(AI / "models/yolov8n.pt")).model.float().eval()
    detector_head = checkpoint.model[-1]
    captured = {}

    def capture(key):
        def save_output(_module, _inputs, output):
            captured[key] = output
        return save_output

    hooks = [branch[i].register_forward_hook(capture(2 * i + j))
             for j, branch in enumerate((detector_head.cv2, detector_head.cv3))
             for i in range(detector_head.nl)]
    maximum = 0.0
    paths = sorted((AI / "data/demo/images").glob("*.jpg"))
    with torch.no_grad():
        for path in paths:
            data = input_tensor(detector.load_rgb(str(path)))
            checkpoint(data)
            maximum = max(maximum, *(float((value - captured[i]).abs().max())
                                     for i, value in enumerate(model(data))))
    for hook in hooks:
        hook.remove()
    print(f"FP32_HEAD_EQ images={len(paths)} max_abs={maximum:.8g}")
    assert maximum <= 1e-5, maximum


def detect(model, name):
    directory = WORK / "host" / name
    directory.mkdir(parents=True, exist_ok=True)
    images = {}
    start = time.monotonic()
    with torch.no_grad():
        for path in sorted((AI / "data/demo/images").glob("*.jpg")):
            rgb = detector.load_rgb(str(path))
            height, width = rgb.shape[:2]
            raw = model(input_tensor(rgb))
            outs = {f"cv{2 + i % 2}_{i // 2}": x.numpy().transpose(0, 2, 3, 1)
                    for i, x in enumerate(raw)}
            boxes = detector.yolov8_postprocess(outs, 640, len(detector.CLASSES), 0.25, 0.45)
            images[path.name] = {"width": width, "height": height, "detections": [
                [float(x1 * width / 640), float(y1 * height / 640),
                 float(x2 * width / 640), float(y2 * height / 640), float(score), int(cls)]
                for x1, y1, x2, y2, score, cls in boxes]}
            print(name, path.name, len(boxes), flush=True)
    total = time.monotonic() - start
    path = directory / "detections.json"
    path.write_text(json.dumps({"classes": detector.CLASSES, "conf": 0.25, "iou": 0.45,
                                "timing": {"wall_s": total}, "images": images}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fp32-only", action="store_true")
    args = parser.parse_args()
    silu = RawHead(hardswish=False).eval()
    validate_silu_head(silu)
    detect(silu, "silu_fp32")
    detect(RawHead().eval(), "hardswish_fp32")
    if not args.fp32_only:
        detect(quantizer("test").quant_model.eval(), "hardswish_int8")
