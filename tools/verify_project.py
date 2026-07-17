from __future__ import annotations

import json
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(path: str) -> Path:
    target = ROOT / path
    assert target.exists(), f"missing: {path}"
    return target


def balanced_swift(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    pairs = {"{": "}", "(": ")", "[": "]"}
    for left, right in pairs.items():
        assert text.count(left) == text.count(right), (
            f"unbalanced {left}{right} in {path.relative_to(ROOT)}"
        )


def main() -> None:
    require("project.yml")
    require("Podfile")
    require(".github/workflows/build-ipa.yml")
    require("scripts/build-unsigned-ipa.sh")

    with require("MahjongAssistant/Supporting/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info["CFBundleDisplayName"] == "听牌助手"
    assert "NSCameraUsageDescription" in info
    assert "NSLocalNetworkUsageDescription" in info
    orientations = info["UISupportedInterfaceOrientations"]
    assert "UIInterfaceOrientationLandscapeLeft" in orientations
    assert "UIInterfaceOrientationLandscapeRight" in orientations

    with require(
        "MahjongAssistant/Assets.xcassets/AppIcon.appiconset/Contents.json"
    ).open(encoding="utf-8") as handle:
        icon_manifest = json.load(handle)
    assert icon_manifest["images"][0]["size"] == "1024x1024"
    require("MahjongAssistant/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    model = require("MahjongAssistant/Resources/weights.onnx")
    assert model.stat().st_size > 10_000_000, "offline model is unexpectedly small"
    labels = require("MahjongAssistant/Resources/MahjongLabels.txt")
    assert len(labels.read_text(encoding="utf-8").splitlines()) == 42
    require("MahjongAssistant/Supporting/BridgingHeader.h")

    swift_files = sorted((ROOT / "MahjongAssistant").rglob("*.swift"))
    assert len(swift_files) >= 10, "unexpectedly small Swift source tree"
    for swift_file in swift_files:
        balanced_swift(swift_file)

    rules = require("MahjongAssistant/Models/RuleSettings.swift").read_text(encoding="utf-8")
    for expected in (
        "allowChi: false",
        "allowPon: true",
        "allowKan: true",
        "winRequiresReady: true",
    ):
        assert expected in rules, f"default rule missing: {expected}"

    reference_markers = ("LYiHub", "fAres4s", "weights.onnx")
    shipped_text = "\n".join(path.read_text(encoding="utf-8") for path in swift_files)
    assert not any(marker in shipped_text for marker in reference_markers)

    podfile = require("Podfile").read_text(encoding="utf-8")
    assert "onnxruntime-objc" in podfile
    assert "1.22.0" in podfile

    print(
        f"OK: {len(swift_files)} Swift files, offline model, plist, assets, "
        "rules, and workflow validated"
    )


if __name__ == "__main__":
    main()
