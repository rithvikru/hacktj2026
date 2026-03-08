import base64
from datetime import UTC, datetime
from uuid import uuid4

from serving.api.app import (
    WearableFrameBatchRequest,
    WearableFrameEventRequest,
    WearableObservedObjectRequest,
    WearableSessionCreateRequest,
    create_wearable_session,
    get_wearable_session,
    ingest_wearable_frames,
    list_wearable_sessions,
)
from serving.storage.home_store import HomeStore
from serving.storage.wearable_store import WearableStore

def _iso_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")

def _frame_event(
    *,
    label: str,
    confidence: float,
    place_hint: str,
    image_payload: str | None = None,
):
    return WearableFrameEventRequest(
        frame_id=str(uuid4()),
        timestamp=_iso_now(),
        sample_reason="wearable_stream",
        place_hint=place_hint,
        observed_objects=[WearableObservedObjectRequest(label=label, confidence=confidence)],
        image_jpeg_base64=image_payload,
        image_width=320 if image_payload else None,
        image_height=240 if image_payload else None,
        metadata={"capture_source": "rayban_meta"},
    )

def setup_function():
    HomeStore.reset()
    WearableStore.reset()

def test_wearable_session_frame_ingest_and_inspection(monkeypatch, tmp_path):
    monkeypatch.setenv("HACKTJ_WEARABLES_DIR", str(tmp_path / "wearables"))
    HomeStore.reset()
    WearableStore.reset()

    home = HomeStore().create("House")
    create_response = create_wearable_session(
        WearableSessionCreateRequest(
            home_id=home.home_id,
            device_name="Ray-Ban Meta",
            source="rayban_meta",
            sampling_fps=1.0,
        )
    )
    session_id = create_response["sessionID"]

    image_payload = base64.b64encode(b"fake-jpeg").decode("utf-8")
    frame = _frame_event(
        label="wallet",
        confidence=0.93,
        place_hint="Kitchen",
        image_payload=image_payload,
    )
    ingest_response = ingest_wearable_frames(
        session_id,
        WearableFrameBatchRequest(events=[frame]),
    )
    assert ingest_response["newFrames"] == 1
    assert ingest_response["frameCount"] == 1

    duplicate_response = ingest_wearable_frames(
        session_id,
        WearableFrameBatchRequest(
            events=[
                WearableFrameEventRequest(
                    frame_id=frame.frame_id,
                    timestamp=_iso_now(),
                    sample_reason="wearable_stream",
                    place_hint="Kitchen",
                )
            ]
        ),
    )
    assert duplicate_response["newFrames"] == 0
    assert duplicate_response["duplicateFrames"] == 1
    assert duplicate_response["frameCount"] == 1

    inspect_body = get_wearable_session(session_id)
    assert inspect_body["status"] == "streaming"
    assert inspect_body["frameCount"] == 1
    assert inspect_body["lastFrameID"] == frame.frame_id

    state_path = tmp_path / "wearables" / session_id / "session.json"
    frame_path = tmp_path / "wearables" / session_id / "frames" / f"{frame.frame_id}.jpg"
    assert state_path.exists()
    assert frame_path.exists()

def test_wearable_sessions_reload_from_disk(monkeypatch, tmp_path):
    monkeypatch.setenv("HACKTJ_WEARABLES_DIR", str(tmp_path / "wearables"))
    HomeStore.reset()
    WearableStore.reset()

    home = HomeStore().create("Apartment")
    create_response = create_wearable_session(
        WearableSessionCreateRequest(
            home_id=home.home_id,
            device_name="Ray-Ban Meta",
            source="rayban_meta",
            sampling_fps=2.0,
        )
    )
    session_id = create_response["sessionID"]
    frame = _frame_event(label="keys", confidence=0.81, place_hint="Office")
    ingest_wearable_frames(
        session_id,
        WearableFrameBatchRequest(events=[frame]),
    )

    WearableStore.reset()

    inspect_response = get_wearable_session(session_id)
    assert inspect_response["frameCount"] == 1

    list_response = list_wearable_sessions(home_id=home.home_id)
    assert list_response["sessions"][0]["sessionID"] == session_id
    assert list_response["sessions"][0]["frameCount"] == 1
