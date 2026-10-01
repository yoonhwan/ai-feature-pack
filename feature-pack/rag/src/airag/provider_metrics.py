"""Request timing and numeric token counters, without prompts, responses or credentials."""
from contextlib import contextmanager
from contextvars import ContextVar
from functools import wraps
import time

_calls = ContextVar('airag_provider_metrics', default=None)


@contextmanager
def capture():
    calls = []
    token = _calls.set(calls)
    try:
        yield calls
    finally:
        _calls.reset(token)


def timed_request(function):
    @wraps(function)
    def wrapper(*args, **kwargs):
        recorder = _calls.get()
        if recorder is None:
            return function(*args, **kwargs)
        start = time.monotonic()
        response = None
        succeeded = False
        try:
            response = function(*args, **kwargs)
            succeeded = True
            return response
        finally:
            path = args[1] if len(args) > 1 else kwargs.get('path')
            usage = response.get('usage') if isinstance(response, dict) else None
            usage = usage if isinstance(usage, dict) else {}
            details = usage.get('prompt_tokens_details')
            details = details if isinstance(details, dict) else {}
            def number(value):
                return value if type(value) is int and value >= 0 else 0
            recorder.append({'path': path if path in ('/tokenize','/chat/completions') else 'other',
                'seconds': round(time.monotonic()-start, 6), 'succeeded': succeeded,
                'prompt_tokens': number(usage.get('prompt_tokens')),
                'completion_tokens': number(usage.get('completion_tokens')),
                'cached_prompt_tokens': number(details.get('cached_tokens'))})
    return wrapper
