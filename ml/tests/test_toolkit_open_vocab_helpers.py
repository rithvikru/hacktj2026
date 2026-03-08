from hacktj2026_ml.toolkit import _select_room_image_paths

def test_select_room_image_paths_samples_large_rooms(tmp_path):
    images_dir = tmp_path / "images"
    images_dir.mkdir()
    frames = []
    for index in range(40):
        image_name = f"frame-{index:02d}.jpg"
        (images_dir / image_name).write_bytes(b"jpg")
        frames.append({"image_path": f"images/{image_name}"})

    selected = _select_room_image_paths(
        room_frame_dir=tmp_path,
        frames=frames,
        frame_refs=[],
        frame_limit=24,
    )

    assert len(selected) == 24
    assert selected[0] == images_dir / "frame-00.jpg"
    assert selected[-1] == images_dir / "frame-39.jpg"

def test_select_room_image_paths_keeps_requested_refs(tmp_path):
    image_a = tmp_path / "images" / "frame-a.jpg"
    image_b = tmp_path / "images" / "frame-b.jpg"
    image_a.parent.mkdir()
    image_a.write_bytes(b"a")
    image_b.write_bytes(b"b")

    selected = _select_room_image_paths(
        room_frame_dir=tmp_path,
        frames=[],
        frame_refs=["images/frame-b.jpg", "images/frame-a.jpg", "images/frame-b.jpg"],
        frame_limit=24,
    )

    assert selected == [image_b, image_a]
