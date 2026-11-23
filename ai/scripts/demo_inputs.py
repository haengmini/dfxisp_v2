import re


def demo_images(directory):
    stems = (directory / "demo_list.txt").read_text().splitlines()
    if (not stems or len(set(stems)) != len(stems)
            or any(not re.fullmatch(r"[A-Za-z0-9_-]+", stem) for stem in stems)):
        raise ValueError("demo_list.txt must contain unique image stems, one per line")
    paths = [directory / "images" / f"{stem}.jpg" for stem in stems]
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
    return paths
