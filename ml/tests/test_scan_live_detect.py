import base64

from fastapi.testclient import TestClient

from serving.api.app import app


def test_live_scan_detect_endpoint_returns_detections(monkeypatch):
    from open_vocab.grounding_dino.run_grounding import Detection
    import open_vocab.grounding_dino.run_grounding as grounding_module
    import open_vocab.sam2.run_segmentation as segmentation_module

    def fake_detect(*args, **kwargs):
        return [
            Detection(
                image_path="scan.jpg",
                bbox_xyxy_norm=[0.1, 0.2, 0.3, 0.4],
                confidence=0.91,
                label="phone",
            )
        ]

    class FakeMask:
        def __init__(self):
            self.mask = [[True]]

    def fake_segment(*args, **kwargs):
        return [FakeMask()]

    monkeypatch.setattr(grounding_module, "detect", fake_detect)
    monkeypatch.setattr(segmentation_module, "segment", fake_segment)

    client = TestClient(app)
    image_bytes = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8B2s8AAAAASUVORK5CYII="
    )
    response = client.post(
        "/scan/live-detect",
        files={"file": ("scan.png", image_bytes, "image/png")},
        data={"labels": "phone,airpods case", "maxCandidates": "4"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["labels"] == ["phone", "airpods case"]
    assert len(payload["detections"]) == 1
    assert payload["detections"][0]["label"] == "phone"
    assert payload["detections"][0]["maskAvailable"] is True
