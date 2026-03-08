from open_vocab.grounding_dino.run_grounding import (
    Detection,
    _iter_tiles,
    _prompt_profile,
    deduplicate_detections,
)

def test_prompt_profile_expands_small_object_queries():
    profile = _prompt_profile("where is my coke can")

    assert profile["force_tiles"] is True
    assert "coke can" in profile["prompt_variants"]
    assert "soda can" in profile["prompt_variants"]
    assert profile["tile_box_threshold"] < profile["full_box_threshold"]

def test_iter_tiles_covers_large_image_with_overlap():
    tiles = _iter_tiles(width=1600, height=1200, tile_size=768, overlap=0.35)

    assert len(tiles) > 1
    assert tiles[0] == (0, 0, 768, 768)
    assert any(tile[0] > 0 for tile in tiles)
    assert any(tile[1] > 0 for tile in tiles)
    assert max(tile[2] for tile in tiles) == 1600
    assert max(tile[3] for tile in tiles) == 1200

def test_deduplicate_detections_keeps_best_overlapping_box():
    detections = [
        Detection("frame.jpg", [0.10, 0.10, 0.20, 0.20], 0.91, "phone"),
        Detection("frame.jpg", [0.11, 0.11, 0.21, 0.21], 0.74, "phone"),
        Detection("frame.jpg", [0.55, 0.55, 0.65, 0.65], 0.70, "phone"),
    ]

    deduped = deduplicate_detections(detections)

    assert len(deduped) == 2
    assert deduped[0].confidence == 0.91
