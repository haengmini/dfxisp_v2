import argparse
import random
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    args = parser.parse_args()
    ai = Path(__file__).resolve().parents[1]
    excluded = {p.stem for p in (ai / "data/demo/images").glob("*.jpg")}
    rng = random.Random(20261014)
    selected = []
    for name in ("LOD_test", "PASCAL_test"):
        candidates = sorted(p for p in (args.dataset / name / "images").glob("*.jpg")
                            if p.stem not in excluded and p.is_file())
        chosen = rng.sample(candidates, 64)
        selected.extend(p.relative_to(args.dataset).as_posix() for p in chosen)
        print(f"{name}: {len(chosen)} / {len(candidates)}")
    assert len(set(selected)) == 128
    (ai / "data/calib_list.txt").write_text("\n".join(selected) + "\n")


if __name__ == "__main__":
    main()
