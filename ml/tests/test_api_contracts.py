from serving.api.app import _build_open_vocab_request_from_payload

def test_open_vocab_request_builder_accepts_minimal_mobile_payload():
    request = _build_open_vocab_request_from_payload(
        room_id="room-1",
        payload={"query_text": "where is my wallet", "frame_refs": []},
    )

    assert request.room_id == "room-1"
    assert request.target_phrase == "wallet"
    assert request.normalized_query
