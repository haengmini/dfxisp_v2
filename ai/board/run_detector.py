#!/usr/bin/env python3
"""ZCU104 DPU inference for the dfxisp detectors (YOLOv8n / SSDLite-MobileNetV3).

Only the first DPU subgraph of the xmodel is executed on the DPU (vart.Runner).
Everything after it — YOLOv8 DFL + box decode + sigmoid, SSD box decode + softmax,
and NMS — is done here in numpy, so the CPU subgraphs / second DPU subgraph that
vai_c_xir emitted are never used.

Usage (on the board, as root):
  python3 run_detector.py --model yolov8n  --xmodel /home/root/models/yolov8n_dpu.xmodel \
                          --images /home/root/test_images --out dets_yolov8n.json
  python3 run_detector.py --model ssdlite  --xmodel /home/root/models/ssdlite_mbv3_dpu.xmodel \
                          --anchors /home/root/ssdlite_anchors.npy --norm unit \
                          --images /home/root/test_images --out dets_ssdlite.json
"""
import argparse
import json
import math
import os
import sys
import time

import numpy as np

# vart/xir only exist on the board; imported lazily so the postprocessing functions in this
# file can be reused on the host (eval_float_host.py).
try:
    import vart
    import xir
except ImportError:      # host
    vart = xir = None

CLASSES = ["person", "car", "bicycle"]
IMG_EXT = (".jpg", ".jpeg", ".png", ".bmp")


# ---------------------------------------------------------------- image I/O
def _have_cv2():
    try:
        import cv2  # noqa: F401
        return True
    except ImportError:
        return False


def load_rgb(path):
    """Returns HxWx3 uint8 RGB."""
    if _have_cv2():
        import cv2
        img = cv2.imread(path, cv2.IMREAD_COLOR)
        if img is None:
            raise IOError(f"cannot read {path}")
        return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGB"))


def resize_rgb(img, size):
    """Plain (non-letterbox) resize to size x size — same as the calibration script."""
    if _have_cv2():
        import cv2
        return cv2.resize(img, (size, size), interpolation=cv2.INTER_LINEAR)
    from PIL import Image
    return np.asarray(Image.fromarray(img).resize((size, size), Image.BILINEAR))


# ---------------------------------------------------------------- DPU runner
class DpuSubgraphRunner:
    """Runs the first DPU subgraph of an xmodel. Handles int8 quant/dequant."""

    def __init__(self, xmodel_path):
        # NOTE: the Graph (and the subgraph) must outlive the Runner — VART keeps a raw
        # pointer to the subgraph, so letting `graph` be garbage-collected segfaults on execute.
        self.graph = xir.Graph.deserialize(xmodel_path)
        dpu_sgs = [s for s in self.graph.get_root_subgraph().toposort_child_subgraph()
                   if s.has_attr("device") and s.get_attr("device").upper() == "DPU"]
        if not dpu_sgs:
            raise RuntimeError("no DPU subgraph in " + xmodel_path)
        self.subgraph = dpu_sgs[0]
        self.runner = vart.Runner.create_runner(self.subgraph, "run")
        self.in_t = self.runner.get_input_tensors()[0]
        self.out_ts = self.runner.get_output_tensors()
        self.in_dims = tuple(self.in_t.dims)           # (1, H, W, 3)
        self.in_scale = 2.0 ** self.in_t.get_attr("fix_point")
        self.out_scales = [2.0 ** (-t.get_attr("fix_point")) for t in self.out_ts]

    @property
    def input_size(self):
        return self.in_dims[1]

    def run(self, x):
        """x: (H, W, 3) float32 already in the range the model was calibrated with."""
        q = np.clip(np.round(x * self.in_scale), -128, 127).astype(np.int8)
        inp = np.ascontiguousarray(q.reshape(self.in_dims))
        outs = [np.empty(tuple(t.dims), dtype=np.int8, order="C") for t in self.out_ts]
        jid = self.runner.execute_async([inp], outs)
        self.runner.wait(jid)
        return {t.name: o.astype(np.float32) * s
                for t, o, s in zip(self.out_ts, outs, self.out_scales)}


# ---------------------------------------------------------------- NMS
def iou_xyxy(box, boxes):
    x1 = np.maximum(box[0], boxes[:, 0]); y1 = np.maximum(box[1], boxes[:, 1])
    x2 = np.minimum(box[2], boxes[:, 2]); y2 = np.minimum(box[3], boxes[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    a = (box[2] - box[0]) * (box[3] - box[1])
    b = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    return inter / (a + b - inter + 1e-9)


def nms(boxes, scores, iou_thr):
    order = scores.argsort()[::-1]
    keep = []
    while order.size:
        i = order[0]
        keep.append(i)
        if order.size == 1:
            break
        ious = iou_xyxy(boxes[i], boxes[order[1:]])
        order = order[1:][ious <= iou_thr]
    return np.array(keep, dtype=np.int64)


def multiclass_nms(boxes, scores, conf_thr, iou_thr, max_det=300, topk=300):
    """boxes (N,4) xyxy, scores (N,C). Per-class NMS. Returns list of (x1,y1,x2,y2,score,cls).
    Only the top-k candidates per class enter NMS (torchvision SSD: topk_candidates=300) —
    without this, --conf 0.001 lets thousands of boxes into the O(N^2) NMS loop."""
    dets = []
    for c in range(scores.shape[1]):
        m = scores[:, c] > conf_thr
        if not m.any():
            continue
        b, s = boxes[m], scores[m, c]
        if len(s) > topk:
            idx = np.argpartition(-s, topk)[:topk]
            b, s = b[idx], s[idx]
        for k in nms(b, s, iou_thr):
            dets.append((*b[k].tolist(), float(s[k]), c))
    dets.sort(key=lambda d: -d[4])
    return dets[:max_det]


# ---------------------------------------------------------------- YOLOv8n
def yolov8_postprocess(outs, img_size, nc, conf_thr, iou_thr):
    """outs: dequantized DPU outputs, NHWC. cv2 = box distribution (64ch), cv3 = class logits."""
    box_lv, cls_lv = {}, {}
    for name, arr in outs.items():
        a = arr[0]                      # (H, W, C)
        if "cv2" in name:
            box_lv[a.shape[0]] = a
        elif "cv3" in name:
            cls_lv[a.shape[0]] = a
    assert box_lv.keys() == cls_lv.keys(), (box_lv.keys(), cls_lv.keys())

    all_boxes, all_scores = [], []
    reg = np.arange(16, dtype=np.float32)
    for h in sorted(box_lv, reverse=True):          # 80, 40, 20
        stride = img_size / h
        # DFL: (H*W, 4, 16) -> softmax over 16 bins -> expectation
        b = box_lv[h].reshape(-1, 4, 16)
        b = b - b.max(-1, keepdims=True)
        p = np.exp(b)
        p /= p.sum(-1, keepdims=True)
        dist = (p * reg).sum(-1)                    # (N, 4) = l, t, r, b in grid units
        gy, gx = np.mgrid[0:h, 0:h]
        cx = gx.reshape(-1).astype(np.float32) + 0.5
        cy = gy.reshape(-1).astype(np.float32) + 0.5
        xyxy = np.stack([(cx - dist[:, 0]) * stride, (cy - dist[:, 1]) * stride,
                         (cx + dist[:, 2]) * stride, (cy + dist[:, 3]) * stride], 1)
        all_boxes.append(xyxy)
        logits = cls_lv[h].reshape(-1, nc)
        all_scores.append(1.0 / (1.0 + np.exp(-logits)))
    boxes = np.concatenate(all_boxes)
    scores = np.concatenate(all_scores)
    return multiclass_nms(boxes, scores, conf_thr, iou_thr)


# ---------------------------------------------------------------- SSDLite
BBOX_XFORM_CLIP = math.log(1000.0 / 16)   # torchvision BoxCoder default


def ssdlite_postprocess(outs, anchors, img_size, conf_thr, iou_thr):
    """anchors: (A,4) xyxy in img_size coords (from dump_ssdlite_anchors.py).
    Box decode = torchvision BoxCoder(weights=(10,10,5,5)); class 0 is background."""
    cls = reg = None
    for name, arr in outs.items():
        if "classification" in name:
            cls = arr[0]
        elif "regression" in name:
            reg = arr[0]
    assert cls is not None and reg is not None, list(outs)
    assert reg.shape[0] == anchors.shape[0], (reg.shape, anchors.shape)

    e = np.exp(cls - cls.max(1, keepdims=True))
    prob = e / e.sum(1, keepdims=True)
    scores = prob[:, 1:]                                     # drop background

    wa = anchors[:, 2] - anchors[:, 0]
    ha = anchors[:, 3] - anchors[:, 1]
    cxa = anchors[:, 0] + 0.5 * wa
    cya = anchors[:, 1] + 0.5 * ha
    dx, dy = reg[:, 0] / 10.0, reg[:, 1] / 10.0
    dw = np.minimum(reg[:, 2] / 5.0, BBOX_XFORM_CLIP)
    dh = np.minimum(reg[:, 3] / 5.0, BBOX_XFORM_CLIP)
    cx = dx * wa + cxa
    cy = dy * ha + cya
    w = np.exp(dw) * wa
    h = np.exp(dh) * ha
    boxes = np.stack([cx - 0.5 * w, cy - 0.5 * h, cx + 0.5 * w, cy + 0.5 * h], 1)
    boxes = np.clip(boxes, 0, img_size)
    return multiclass_nms(boxes, scores, conf_thr, iou_thr)


# ---------------------------------------------------------------- main
def preprocess(img, size, norm):
    x = resize_rgb(img, size).astype(np.float32) / 255.0
    if norm == "pm1":              # torchvision SSD default: mean=std=0.5 -> [-1, 1]
        x = (x - 0.5) / 0.5
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["yolov8n", "ssdlite"], required=True)
    ap.add_argument("--xmodel", required=True)
    ap.add_argument("--images", required=True, help="image file or directory")
    ap.add_argument("--out", default=None, help="write detections JSON here")
    ap.add_argument("--anchors", default=None, help="ssdlite_anchors.npy (ssdlite only)")
    ap.add_argument("--norm", choices=["unit", "pm1"], default="unit",
                    help="unit: x/255 (what the calibration script used); pm1: (x/255-0.5)/0.5")
    ap.add_argument("--conf", type=float, default=0.25)
    ap.add_argument("--iou", type=float, default=None,
                    help="NMS IoU (default 0.45 yolov8n / 0.55 ssdlite = framework defaults)")
    ap.add_argument("--warmup", type=int, default=3)
    args = ap.parse_args()

    if args.iou is None:
        args.iou = 0.45 if args.model == "yolov8n" else 0.55
    anchors = None
    if args.model == "ssdlite":
        if not args.anchors:
            sys.exit("--anchors is required for ssdlite")
        anchors = np.load(args.anchors).astype(np.float32)

    if os.path.isdir(args.images):
        files = sorted(os.path.join(args.images, f) for f in os.listdir(args.images)
                       if f.lower().endswith(IMG_EXT))
    else:
        files = [args.images]
    if not files:
        sys.exit("no images found")

    dpu = DpuSubgraphRunner(args.xmodel)
    size = dpu.input_size
    print(f"[info] DPU input {dpu.in_dims}, in_scale={dpu.in_scale}, "
          f"outputs={[tuple(t.dims) for t in dpu.out_ts]}", file=sys.stderr)

    # warm-up (first runs are slower)
    x0 = preprocess(load_rgb(files[0]), size, args.norm)
    for _ in range(args.warmup):
        dpu.run(x0)

    results = {}
    t_pre = t_dpu = t_post = 0.0
    for path in files:
        img = load_rgb(path)
        H, W = img.shape[:2]
        t0 = time.perf_counter()
        x = preprocess(img, size, args.norm)
        t1 = time.perf_counter()
        outs = dpu.run(x)
        t2 = time.perf_counter()
        if args.model == "yolov8n":
            dets = yolov8_postprocess(outs, size, len(CLASSES), args.conf, args.iou)
        else:
            dets = ssdlite_postprocess(outs, anchors, size, args.conf, args.iou)
        t3 = time.perf_counter()
        t_pre += t1 - t0; t_dpu += t2 - t1; t_post += t3 - t2

        sx, sy = W / size, H / size          # back to original image coords
        dets = [[d[0] * sx, d[1] * sy, d[2] * sx, d[3] * sy, d[4], d[5]] for d in dets]
        results[os.path.basename(path)] = {"width": W, "height": H, "detections": dets}
        top = ", ".join(f"{CLASSES[d[5]]}:{d[4]:.2f}" for d in dets[:5])
        print(f"{os.path.basename(path)}: {len(dets)} dets  [{top}]")

    n = len(files)
    total = (t_pre + t_dpu + t_post) / n
    timing = {"images": n, "pre_ms": t_pre / n * 1e3, "dpu_ms": t_dpu / n * 1e3,
              "post_ms": t_post / n * 1e3, "total_ms": total * 1e3, "fps": 1 / total}
    print(f"\n[timing over {n} images] pre {timing['pre_ms']:.1f} ms | DPU {timing['dpu_ms']:.1f} ms | "
          f"post {timing['post_ms']:.1f} ms | total {timing['total_ms']:.1f} ms = {timing['fps']:.1f} FPS "
          f"(excl. image load)", file=sys.stderr)

    if args.out:
        with open(args.out, "w") as f:
            json.dump({"model": args.model, "xmodel": args.xmodel, "norm": args.norm,
                       "conf": args.conf, "iou": args.iou, "classes": CLASSES,
                       "host": os.uname().nodename, "timing": timing,      # kept so results/ backups carry it
                       "images": results}, f)
        print(f"[info] wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
