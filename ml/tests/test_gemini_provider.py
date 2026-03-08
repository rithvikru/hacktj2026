from pathlib import Path

import open_vocab.grounding_dino.run_grounding as grounding_module
from open_vocab.gemini.run_gemini import _normalize_box, _parse_json_text


def test_parse_json_text_accepts_fenced_json():
    payload = """```json
    [{"label":"bottle","box_2d":[100,200,300,400]}]
    ```"""
    parsed = _parse_json_text(payload)
    assert isinstance(parsed, list)
    assert parsed[0]["label"] == "bottle"


def test_normalize_box_supports_gemini_0_to_1000_box_format():
    box = _normalize_box([100, 200, 300, 400])
    assert box == [0.2, 0.1, 0.4, 0.3]


def test_grounding_detect_dispatches_to_gemini(monkeypatch):
    monkeypatch.setenv("OPEN_VOCAB_DETECTOR_PROVIDER", "gemini")

    class FakeGeminiDetection:
        def __init__(self):
            self.image_path = "demo.jpg"
            self.bbox_xyxy_norm = [0.1, 0.2, 0.3, 0.4]
            self.confidence = 0.88
            self.label = "airpods case"

    def fake_detect(**kwargs):
        return [FakeGeminiDetection()]

    import open_vocab.gemini.run_gemini as gemini_module

    monkeypatch.setattr(gemini_module, "detect", fake_detect)

    detections = grounding_module.detect([Path("demo.jpg")], "airpods case")
    assert len(detections) == 1
    assert detections[0].label == "airpods case"
    assert detections[0].confidence == 0.88


def test_grounding_detect_does_not_fallback_when_gemini_is_selected(monkeypatch):
    monkeypatch.setenv("OPEN_VOCAB_DETECTOR_PROVIDER", "gemini")
    monkeypatch.delenv("OPEN_VOCAB_ALLOW_FALLBACK", raising=False)

    import open_vocab.gemini.run_gemini as gemini_module

    def fake_detect(**kwargs):
        raise TimeoutError("simulated timeout")

    monkeypatch.setattr(gemini_module, "detect", fake_detect)

    try:
        grounding_module.detect([Path("demo.jpg")], "airpods case")
    except TimeoutError as exc:
        assert "timeout" in str(exc)
    else:
        raise AssertionError("Gemini timeout should be raised when fallback is disabled")
