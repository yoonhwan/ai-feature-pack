import pytest

from airag_consumer.events import AccessScope


@pytest.fixture
def scope():
    return AccessScope("synthetic", "airag-contract", "synthetic-airag-01")


@pytest.fixture
def payload():
    return {
        "schema_version": 1,
        "event_id": "e001",
        "stream_id": "synthetic-airag-01",
        "message_id": "m001",
        "producer_epoch": "synthetic-1",
        "source_version": 1,
        "source_ordinal": 1,
        "event_type": "create",
        "occurred_at": "2026-09-27T00:00:00Z",
        "ingested_at": "2026-09-27T00:00:01Z",
        "role": "user",
        "content": "설정 오류를 확인해 주세요.",
        "access_scope": {"tenant_id": "synthetic", "project_id": "airag-contract"},
    }
