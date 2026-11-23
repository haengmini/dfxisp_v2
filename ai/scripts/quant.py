import argparse
from pathlib import Path
import sys

import torch
from torch import nn

AI = Path("/input")
WORK = Path("/work")
sys.path.insert(0, str(AI / "board"))
import run_detector as detector

# Pillow matches the deployed board's image path.
detector._have_cv2 = lambda: False


class RawHead(nn.Module):
    """Return the three box/class head pairs before DFL and decoding."""

    def __init__(self, hardswish=True):
        super().__init__()
        from ultralytics.nn.tasks import DetectionModel
        from ultralytics.nn.modules.conv import Conv

        checkpoint = torch.load(WORK / "yolov8n_state.pt", map_location="cpu")
        state = checkpoint["state_dict"]
        net = DetectionModel("yolov8n.yaml", nc=checkpoint["nc"], verbose=False)
        head = net.model[-1]
        prefix = f"model.{head.i}.cv3"
        channels = [state[f"{prefix}.{i}.0.conv.weight"].shape[1] for i in range(head.nl)]
        hidden = state[f"{prefix}.0.0.conv.weight"].shape[0]
        head.cv3 = nn.ModuleList(
            nn.Sequential(Conv(c, hidden, 3), Conv(hidden, hidden, 3),
                          nn.Conv2d(hidden, head.nc, 1)) for c in channels
        )
        for path in checkpoint["identity_activations"]:
            parent, _, name = path.rpartition(".")
            setattr(net.get_submodule(parent), name, nn.Identity())
        for layer in net.modules():
            if isinstance(layer, nn.BatchNorm2d):
                layer.eps, layer.momentum = 1e-3, 0.03
            if hardswish:
                for name, child in layer.named_children():
                    if isinstance(child, nn.SiLU):
                        setattr(layer, name, nn.Hardswish(inplace=False))
        net.load_state_dict(state, strict=True)
        self.net = net.eval()
        head.export = True

    def forward(self, x):
        saved = []
        for layer in self.net.model[:-1]:
            if isinstance(layer.f, list):
                x = [x if index == -1 else saved[index] for index in layer.f]
            elif layer.f != -1:
                x = saved[layer.f]
            x = layer(x)
            saved.append(x if layer.i in self.net.save else None)
        head = self.net.model[-1]
        return tuple(value for i, index in enumerate(head.f)
                     for value in (head.cv2[i](saved[index]), head.cv3[i](saved[index])))


def input_tensor(rgb):
    return torch.from_numpy(detector.preprocess(rgb, 640, "unit")).permute(2, 0, 1)[None].contiguous()


def quantizer(mode):
    from pytorch_nndct.apis import torch_quantizer

    model = RawHead().eval()
    return torch_quantizer(mode, model, (torch.zeros((1, 3, 640, 640)),),
                           output_dir=str(WORK / "quant"), device=torch.device("cpu"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("calib", "test"))
    args = parser.parse_args()
    q = quantizer(args.stage)
    model = q.quant_model.eval()
    with torch.no_grad():
        if args.stage == "calib":
            entries = (AI / "data/calib_list.txt").read_text().splitlines()
            assert len(entries) == len(set(entries)) == 128
            for index, entry in enumerate(entries, start=1):
                model(input_tensor(detector.load_rgb(str(Path("/dataset") / entry))))
                if index % 16 == 0:
                    print(f"CALIB {index}/{len(entries)}", flush=True)
            q.export_quant_config()
            print(f"CALIB_DONE {len(entries)}")
        else:
            first = sorted((AI / "data/demo/images").glob("*.jpg"))[0]
            model(input_tensor(detector.load_rgb(str(first))))
            q.export_xmodel(output_dir=str(WORK / "quant"), deploy_check=False)
            print("EXPORT_DONE batch=1")


if __name__ == "__main__":
    main()
