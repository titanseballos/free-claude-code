"""Tests for Cerebras provider."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from providers.base import ProviderConfig
from providers.cerebras import CerebrasProvider
from providers.cerebras.request import CEREBRAS_DEFAULT_MAX_TOKENS


class MockMessage:
    def __init__(self, role, content):
        self.role = role
        self.content = content


class MockRequest:
    def __init__(self, **kwargs):
        self.model = "llama3.3-70b"
        self.messages = [MockMessage("user", "Hello")]
        self.max_tokens = 100
        self.temperature = 0.5
        self.top_p = 0.9
        self.system = "System prompt"
        self.stop_sequences = None
        self.tools = []
        self.extra_body = {}
        self.thinking = MagicMock()
        self.thinking.enabled = False
        for k, v in kwargs.items():
            setattr(self, k, v)


@pytest.fixture
def cerebras_config():
    return ProviderConfig(
        api_key="test_cerebras_key",
        base_url="https://api.cerebras.ai/v1",
        rate_limit=10,
        rate_window=60,
    )


@pytest.fixture(autouse=True)
def mock_rate_limiter():
    """Mock the global rate limiter to prevent waiting."""
    with patch("providers.openai_compat.GlobalRateLimiter") as mock:
        instance = mock.get_instance.return_value
        instance.wait_if_blocked = AsyncMock(return_value=False)

        async def _passthrough(fn, *args, **kwargs):
            return await fn(*args, **kwargs)

        instance.execute_with_retry = AsyncMock(side_effect=_passthrough)
        yield instance


@pytest.fixture
def cerebras_provider(cerebras_config):
    return CerebrasProvider(cerebras_config)


def test_init(cerebras_config):
    """Test provider initialization."""
    with patch("providers.openai_compat.AsyncOpenAI"):
        provider = CerebrasProvider(cerebras_config)
        assert provider._api_key == "test_cerebras_key"
        assert provider._base_url == "https://api.cerebras.ai/v1"
        assert provider._provider_name == "CEREBRAS"


def test_init_uses_configurable_timeouts():
    """Provider passes configurable read/write/connect timeouts to the HTTP client."""
    config = ProviderConfig(
        api_key="test_cerebras_key",
        base_url="https://api.cerebras.ai/v1",
        http_read_timeout=600.0,
        http_write_timeout=15.0,
        http_connect_timeout=5.0,
    )
    with patch("providers.openai_compat.AsyncOpenAI") as mock_openai:
        CerebrasProvider(config)
        call_kwargs = mock_openai.call_args[1]
        timeout = call_kwargs["timeout"]
        assert timeout.read == 600.0
        assert timeout.write == 15.0
        assert timeout.connect == 5.0


def test_init_strips_trailing_slash():
    """base_url trailing slash is stripped."""
    config = ProviderConfig(
        api_key="test_cerebras_key",
        base_url="https://api.cerebras.ai/v1/",
    )
    with patch("providers.openai_compat.AsyncOpenAI"):
        provider = CerebrasProvider(config)
        assert provider._base_url == "https://api.cerebras.ai/v1"


def test_build_request_body_defaults(cerebras_provider):
    """build_request_body returns model and falls back to CEREBRAS_DEFAULT_MAX_TOKENS."""
    req = MockRequest(max_tokens=None)
    body = cerebras_provider._build_request_body(req)
    assert body["model"] == "llama3.3-70b"
    assert body["max_tokens"] == CEREBRAS_DEFAULT_MAX_TOKENS


def test_build_request_body_respects_max_tokens(cerebras_provider):
    """build_request_body passes through the requested max_tokens."""
    req = MockRequest(max_tokens=512)
    body = cerebras_provider._build_request_body(req)
    assert body["max_tokens"] == 512


@pytest.mark.asyncio
async def test_stream_response_text(cerebras_provider):
    """stream_response yields SSE events for a normal text completion."""
    req = MockRequest()

    mock_chunk = MagicMock()
    mock_chunk.usage = None
    mock_chunk.choices = [MagicMock()]
    mock_chunk.choices[0].finish_reason = None
    mock_chunk.choices[0].delta = MagicMock()
    mock_chunk.choices[0].delta.content = "Hello"
    mock_chunk.choices[0].delta.tool_calls = None
    mock_chunk.choices[0].delta.reasoning_content = None

    finish_chunk = MagicMock()
    finish_chunk.usage = MagicMock()
    finish_chunk.usage.completion_tokens = 1
    finish_chunk.usage.prompt_tokens = 10
    finish_chunk.choices = [MagicMock()]
    finish_chunk.choices[0].finish_reason = "stop"
    finish_chunk.choices[0].delta = MagicMock()
    finish_chunk.choices[0].delta.content = None
    finish_chunk.choices[0].delta.tool_calls = None
    finish_chunk.choices[0].delta.reasoning_content = None

    async def mock_stream():
        yield mock_chunk
        yield finish_chunk

    mock_stream_ctx = MagicMock()
    mock_stream_ctx.__aiter__ = lambda s: mock_stream().__aiter__()

    with patch.object(
        cerebras_provider._client.chat.completions,
        "create",
        new_callable=AsyncMock,
        return_value=mock_stream_ctx,
    ):
        events = [e async for e in cerebras_provider.stream_response(req)]

    assert any("message_start" in e for e in events)
    assert any("Hello" in e for e in events)
    assert any("message_stop" in e for e in events)


@pytest.mark.asyncio
async def test_stream_response_error(cerebras_provider):
    """Network errors are caught and yielded as SSE error events."""
    req = MockRequest()

    import httpx

    with patch.object(
        cerebras_provider._client.chat.completions,
        "create",
        new_callable=AsyncMock,
        side_effect=httpx.ConnectError("Connection refused"),
    ):
        events = [
            e async for e in cerebras_provider.stream_response(req, request_id="CBS1")
        ]

    assert any("Connection refused" in e for e in events)
    assert any("message_stop" in e for e in events)
    assert any("CBS1" in e for e in events)
