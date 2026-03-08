from open_vocab.grounding_dino.run_grounding import Detection, _limit_tiles, deduplicate_detections
from hacktj2026_ml.query_contracts import OpenVocabSearchRequest
from hacktj2026_ml.toolkit import (
    _open_vocab_runtime_settings,
    _select_open_vocab_candidates,
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

    assert settings["frame_limit"] == 8
    assert settings["max_prompt_variants"] == 2
    assert settings["sam2_top_k"] == 6


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
