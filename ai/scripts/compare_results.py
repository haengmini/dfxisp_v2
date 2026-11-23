from itertools import combinations
import json
from pathlib import Path
from statistics import mean

from PIL import Image, ImageDraw, ImageFont

AI = Path(__file__).resolve().parents[1]
RESULTS = AI / "results"
DEMO = AI / "data/demo"
CLASSES = ("person", "car", "bicycle")
HOSTS = ("silu_fp32", "hardswish_fp32", "hardswish_int8")
BOARDS = ("rebuild", "reference", "v2_yolo_A_s0", "v2_yolo_A_full_s1", "v2_yolo_A_full_s2")


def iou(a, b):
    x = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    y = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = x * y
    union = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter
    return inter / union if union > 0 else 0.0


def matches(a, b):
    candidates = []
    for i, first in enumerate(a):
        for j, second in enumerate(b):
            if first[5] == second[5]:
                overlap = iou(first, second)
                if overlap >= 0.5:
                    candidates.append((-overlap, i, j))
    used_a, used_b = set(), set()
    selected = []
    for overlap, i, j in sorted(candidates):
        if i not in used_a and j not in used_b:
            used_a.add(i)
            used_b.add(j)
            selected.append({"iou": -overlap, "score_delta": b[j][4] - a[i][4]})
    return selected


def ground_truth(path, width, height):
    boxes = []
    for row in path.read_text().splitlines():
        cls, x, y, w, h = map(float, row.split())
        boxes.append([(x-w/2)*width, (y-h/2)*height, (x+w/2)*width, (y+h/2)*height,
                      0.0, int(cls)])
    return boxes


def annotate(path, out, boxes):
    with Image.open(path) as source:
        image = source.convert("RGB")
    old_width, old_height = image.size
    image.thumbnail((1024, 1024), getattr(Image, "Resampling", Image).LANCZOS)
    sx, sy = image.width / old_width, image.height / old_height
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("DejaVuSans.ttf", 14)
    colors = ("#25e5b8", "#ffd166", "#ef7598")
    scaled = [((x1*sx, y1*sy, x2*sx, y2*sy), score, cls)
              for x1, y1, x2, y2, score, cls in boxes]
    for box, _, cls in scaled:
        draw.rectangle(box, outline=colors[cls], width=2)

    labels = []
    for box, score, cls in scaled:
        label = f"{CLASSES[cls]} {score:.2f}"
        x0, y0, x1, y1 = draw.textbbox((0, 0), label, font=font)
        width, height = x1 - x0 + 6, y1 - y0 + 6
        left = max(0, min(int(box[0]), image.width - width))
        preferred = max(0, min(int(box[1]) - height, image.height - height))
        top = preferred
        for offset in (0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5):
            candidate = preferred + offset * (height + 2)
            if 0 <= candidate <= image.height - height and all(
                    left + width < a or left > c or candidate + height < b or candidate > d
                    for a, b, c, d in labels):
                top = candidate
                break
        label_box = (left, top, left + width, top + height)
        labels.append(label_box)
        if abs(top - preferred) > 2:
            draw.line((left, top + height, box[0], box[1]), fill=colors[cls])
        draw.rectangle(label_box, fill="#16191d")
        draw.text((left + 3 - x0, top + 3 - y0), label, fill=colors[cls], font=font)
    out.mkdir(parents=True, exist_ok=True)
    image.save(out / path.name, quality=85, optimize=True)


def summarize(items, n_a, n_b):
    deltas = [x["score_delta"] for x in items]
    return {"matches": len(items), "n_a": n_a, "n_b": n_b,
            "match_rate_a": len(items)/n_a if n_a else None,
            "match_rate_b": len(items)/n_b if n_b else None,
            "mean_score_delta_b_minus_a": mean(deltas) if deltas else None,
            "mean_abs_score_delta": mean(map(abs, deltas)) if deltas else None,
            "max_abs_score_delta": max(map(abs, deltas)) if deltas else None}


def main():
    files = sorted((DEMO / "images").glob("*.jpg"))
    names = [p.name for p in files]
    sets = {}
    for group, models in (("host", HOSTS), ("board", BOARDS)):
        for model in models:
            directory = RESULTS / group / model
            record = directory / "detections.json"
            if not record.exists():
                print("MISSING", group, model)
                continue
            payload = json.loads(record.read_text())
            assert sorted(payload["images"]) == names
            assert payload["classes"] == list(CLASSES) and payload["conf"] == 0.25 and payload["iou"] == 0.45
            sets[model] = payload["images"]
            for path in files:
                annotate(path, directory / "annotated", sets[model][path.name]["detections"])

    counts = {}
    for name in names:
        with Image.open(DEMO / "images" / name) as img:
            gt = ground_truth(DEMO / "labels" / (Path(name).stem + ".txt"), *img.size)
        row = {"gt": len(gt)}
        for model, images in sets.items():
            boxes = images[name]["detections"]
            row[model] = {"count": len(boxes), "gt_matches": len(matches(boxes, gt))}
        counts[name] = row
    pairs = []
    for a, b in combinations(sets, 2):
        by_image, all_matches = {}, []
        for name in names:
            sa, sb = sets[a][name]["detections"], sets[b][name]["detections"]
            matched = matches(sa, sb)
            by_image[name] = summarize(matched, len(sa), len(sb))
            all_matches.extend(matched)
        pairs.append({"a": a, "b": b, "images": by_image, "overall":
                      summarize(all_matches, sum(x["n_a"] for x in by_image.values()),
                                sum(x["n_b"] for x in by_image.values()))})
    (RESULTS / "comparison.json").write_text(json.dumps(
        {"images": counts, "pairs": pairs}, indent=2) + "\n")
    columns = ["파일", "GT", *sets]
    rows = [columns, ["---"] * len(columns)]
    for name, values in counts.items():
        rows.append([name, str(values["gt"]), *(
            f"{values[m]['count']} / {values[m]['gt_matches']}" for m in sets)])
    header = "각 셀은 검출 수 / 같은 클래스·IoU ≥ 0.5로 대응된 GT 수다.\n\n"
    output = header + "\n".join("| " + " | ".join(row) + " |" for row in rows) + "\n"
    output += "\n같은 클래스에서 IoU가 높은 순으로 한 번씩 대응했다. 빈 분모와 대응 없는 점수 차이는 —로 표시했다.\n\n"
    rows = [["A", "B", "A 대응/전체", "B 대응/전체", "평균 점수 차이 B−A", "평균·최대 절대 차이"],
            ["---"] * 6]
    for pair in pairs:
        m = pair["overall"]
        fmt = lambda key: f"{m[key]:.4f}" if m[key] is not None else "—"
        rows.append([pair["a"], pair["b"], f"{m['matches']}/{m['n_a']}",
                     f"{m['matches']}/{m['n_b']}", fmt("mean_score_delta_b_minus_a"),
                     f"{fmt('mean_abs_score_delta')} / {fmt('max_abs_score_delta')}"])
    output += "\n".join("| " + " | ".join(row) + " |" for row in rows) + "\n"
    (RESULTS / "comparison.md").write_text(output)
    print(f"COMPARE_DONE models={len(sets)} images={len(names)} pairs={len(pairs)}")


if __name__ == "__main__":
    main()
