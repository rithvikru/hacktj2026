from pathlib import Path

from open_vocab.grounding_dino.run_grounding import Detection, _limit_tiles, deduplicate_detections
from hacktj2026_ml.query_contracts import OpenVocabSearchRequest
from hacktj2026_ml.toolkit import (
    _next_open_vocab_mode,
    _open_vocab_runtime_settings,
    _select_room_image_paths,
    _select_open_vocab_candidates,
    _should_escalate_open_vocab_search,
)


def test_open_vocab_runtime_settings_use_interactive_limits_for_live_priority():
    settings = _open_vocab_runtime_settings(
        OpenVocabSearchRequest(
            query_text="where is my phone",
            normalized_query="where is my phone",
            target_phrase="phone",
            room_id="room-1",
            frame_selection_mode="live_priority",
        )
    )

    assert settings["frame_limit"] == 4
    assert settings["max_prompt_variants"] == 2
    assert settings["sam2_top_k"] == 4


def test_limit_tiles_keeps_first_and_last_tile():
    tiles = [(index, 0, index + 10, 10) for index in range(10)]

    limited = _limit_tiles(tiles, 4)

    assert len(limited) == 4
    assert limited[0] == tiles[0]
    assert limited[-1] == tiles[-1]


def test_deduplicate_detections_collapses_synonym_labels_on_same_box():
    detections = [
        Detection("frame.jpg", [0.10, 0.10, 0.20, 0.20], 0.91, "phone"),
        Detection("frame.jpg", [0.11, 0.11, 0.21, 0.21], 0.88, "mobile phone"),
        Detection("frame.jpg", [0.55, 0.55, 0.65, 0.65], 0.70, "phone"),
    ]

    deduped = deduplicate_detections(detections)

    assert len(deduped) == 2
    assert deduped[0].confidence == 0.91


class _Reranked:
    def __init__(self, detection_idx: int):
        self.detection_idx = detection_idx


def test_select_open_vocab_candidates_prefers_reranked_indices():
    detections = [
        Detection("a.jpg", [0.0, 0.0, 0.1, 0.1], 0.2, "phone"),
        Detection("b.jpg", [0.0, 0.0, 0.1, 0.1], 0.3, "phone"),
        Detection("c.jpg", [0.0, 0.0, 0.1, 0.1], 0.4, "phone"),
    ]

    selected = _select_open_vocab_candidates(
        detections=detections,
        reranked=[_Reranked(2), _Reranked(1)],
        sam2_top_k=1,
        fallback_top_k=2,
    )

    assert selected.original_indices == [2]
    assert selected.detections[0].image_path == "c.jpg"


def test_live_priority_frame_selection_uses_most_recent_frames(tmp_path):
    image_dir = tmp_path / "images"
    image_dir.mkdir()

    frames = []
    for index in range(6):
        image_path = image_dir / f"frame_{index}.jpg"
        image_path.write_bytes(b"fake")
        frames.append({"image_path": str(image_path)})

    selected = _select_room_image_paths(
        room_frame_dir=tmp_path,
        frames=frames,
        frame_selection_mode="live_priority",
        frame_refs=[],
        frame_limit=3,
    )

    assert [Path(path).name for path in selected] == [
        "frame_3.jpg",
        "frame_4.jpg",
        "frame_5.jpg",
    ]


def test_live_priority_prefers_geometry_and_depth_ready_frames(tmp_path):
    image_dir = tmp_path / "images"
    image_dir.mkdir()

    frames = []
    for index in range(6):
        image_path = image_dir / f"frame_{index}.jpg"
        image_path.write_bytes(b"fake")
        frame = {
            "image_path": str(image_path),
            "timestamp": f"2026-03-07T00:00:0{index}Z",
        }
        if index >= 2:
            frame["intrinsics9"] = [1.0] * 9
            frame["camera_transform16"] = [1.0] * 16
        if index >= 4:
            frame["depth_path"] = "depth.png"
        frames.append(frame)

    selected = _select_room_image_paths(
        room_frame_dir=tmp_path,
        frames=frames,
        frame_selection_mode="live_priority",
        frame_refs=[],
        frame_limit=2,
    )

    assert [Path(path).name for path in selected] == [
        "frame_4.jpg",
        "frame_5.jpg",
    ]


def test_saved_scan_search_escalates_after_live_priority_miss():
    request = OpenVocabSearchRequest(
        query_text="where is my phone",
        normalized_query="where is my phone",
        target_phrase="phone",
        room_id="room-1",
        frame_selection_mode="live_priority",
    )
    room = type(
        "RoomStub",
        (),
        {
            "reconstruction_status": "complete",
            "frames": [{}] * 20,
        },
    )()

    assert _should_escalate_open_vocab_search(
        request=request,
        room=room,
        candidates=[],
    )
    assert _next_open_vocab_mode("live_priority") == "saved_priority"
