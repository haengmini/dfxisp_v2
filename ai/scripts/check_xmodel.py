from collections import Counter
import json
from pathlib import Path

import xir

AI = Path("/input")
WORK = Path("/work")


def describe_tensor(tensor):
    return {"name": tensor.name, "shape": list(tensor.dims), "dtype": str(tensor.dtype),
            "fix_point": tensor.get_attr("fix_point") if tensor.has_attr("fix_point") else None}


def op_kind(op):
    kind = op.get_type().lower()
    return kind[:-4] if kind.endswith("-fix") else kind


def activations(ops):
    counts = Counter()
    evidence = {}
    for op in ops:
        kind = op_kind(op)
        name = op.get_name()
        for tag in ("silu", "hardswish"):
            if tag in name.lower():
                counts[tag + " in op name"] += 1
                evidence.setdefault(tag + " in op name", name)
        fused = [str(op.get_attr(key)).lower() for key in
                 ("nonlinear", "activation", "activation_type") if op.has_attr(key)]
        for tag in ("silu", "swish", "sigmoid", "hard-sigmoid", "hard-swish", "hardswish"):
            if tag == kind or tag in fused:
                counts[tag] += 1
                evidence.setdefault(tag, name)
        if kind in ("mul", "eltwise") and (kind == "mul" or "mul" in str(
                op.get_attr("type") if op.has_attr("type") else "").lower()):
            types = set()
            for src in op.get_input_ops().values():
                for producer in src:
                    current = producer
                    while current.get_type() in ("fix", "identity"):
                        parents = [branch for items in current.get_input_ops().values()
                                   for branch in items]
                        if len(parents) != 1:
                            break
                        current = parents[0]
                    types.add(op_kind(current))
            for tag in ("sigmoid", "hard-sigmoid"):
                if tag in types:
                    counts[tag + "+mul"] += 1
                    evidence.setdefault(tag + "+mul", name)
    return {"counts": dict(counts), "examples": evidence}


def inspect(path):
    graph = xir.Graph.deserialize(str(path))
    children = graph.get_root_subgraph().toposort_child_subgraph()
    results = []
    for subgraph in children:
        device = subgraph.get_attr("device") if subgraph.has_attr("device") else None
        fp = subgraph.get_attr("dpu_fingerprint") if subgraph.has_attr("dpu_fingerprint") else None
        ops = list(subgraph.get_ops())
        results.append({"name": subgraph.get_name(), "device": device,
                        "fingerprint": hex(fp) if isinstance(fp, int) else fp,
                        "inputs": sorted(map(describe_tensor, subgraph.get_input_tensors()),
                                         key=lambda t: t["name"]),
                        "outputs": sorted(map(describe_tensor, subgraph.get_output_tensors()),
                                          key=lambda t: t["name"]),
                        "op_types": dict(sorted(Counter(op.get_type() for op in ops).items())),
                        "activations": activations(ops)})
    return results


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-only", action="store_true")
    args = parser.parse_args()
    paths = sorted((AI / "models/reference").rglob("*.xmodel"))
    if not args.reference_only:
        paths.insert(0, WORK / "compiled/yolov8n_dpu_v2rebuild.xmodel")
    result = {p.stem: inspect(p) for p in paths}
    (WORK / "xmodel_structures.json").write_text(json.dumps(result, indent=2) + "\n")
    expected = json.loads((AI / "arch/arch.json").read_text())["fingerprint"]
    for name, subgraphs in result.items():
        dpus = [sg for sg in subgraphs if sg["device"] == "DPU"]
        print(name, "DPU", len(dpus), "fingerprints", [sg["fingerprint"] for sg in dpus],
              "activations", [sg["activations"]["counts"] for sg in dpus])
        if name == "yolov8n_dpu_v2rebuild":
            assert dpus and all(sg["fingerprint"] == expected for sg in dpus)
