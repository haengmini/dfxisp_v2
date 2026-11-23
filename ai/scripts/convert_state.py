from pathlib import Path

import torch
from ultralytics import YOLO


AI = Path("/input")
WORK = Path("/work")

if __name__ == "__main__":
    model = YOLO(str(AI / "models/yolov8n.pt")).model.float().eval()
    state = {key: value.float() for key, value in model.state_dict().items()}
    names = [model.names[i] for i in range(len(model.names))]
    assert names == ["person", "car", "bicycle"], names
    assert len(state) == 355, len(state)
    assert any(isinstance(layer, torch.nn.SiLU) for layer in model.modules())
    identity_activations = [name for name, layer in model.named_modules()
                            if name.endswith(".act") and isinstance(layer, torch.nn.Identity)]
    torch.save({"state_dict": state, "names": model.names, "nc": len(names),
                "identity_activations": identity_activations},
               WORK / "yolov8n_state.pt")
    print(f"STATE_DONE keys={len(state)} names={names} identity_activations={identity_activations}")
