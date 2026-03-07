from hacktj2026_ml.chat_contracts import ChatMessageDTO, ChatRequestDTO
from hacktj2026_ml.chat_service import ChatService
from hacktj2026_ml.query_engine import QueryEngine
from hacktj2026_ml.toolkit import DefaultQueryToolkit


def test_chat_service_returns_query_context():
    service = ChatService(query_engine=QueryEngine(toolkit=DefaultQueryToolkit()))
    response = service.chat(
        ChatRequestDTO(
            room_id="room-1",
            query_text="where is my wallet",
            messages=[],
        )
    )

    assert response.room_id == "room-1"
    assert response.reply.role == "assistant"
    assert response.query_response is not None
    assert response.planner_summary is not None


def test_chat_service_preserves_history():
    service = ChatService(query_engine=QueryEngine(toolkit=DefaultQueryToolkit()))
    response = service.chat(
        ChatRequestDTO(
            room_id="room-1",
            query_text="what about the charger",
            messages=[
                ChatMessageDTO(role="user", content="where is my wallet"),
                ChatMessageDTO(role="assistant", content="I found a last seen wallet result."),
            ],
        )
    )

    assert "charger" in response.reply.content.lower()
