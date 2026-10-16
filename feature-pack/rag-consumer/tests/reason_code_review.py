"""Hand classification of literal occurrences the AST rules cannot place (tuple/assignment/ternary/f-string).

Key: (package-relative path, line, value). Value: (class, one-line reason).
  reason    -> the value is reported as an error/reason code, so it enters the registry
  reference -> the value points at an already declared code (it never widens the registry)
  data      -> not a reported code (env name, identifier, SQL, dynamic-code prefix, ...)
Entries are per occurrence; ``test_reason_codes`` fails on an unplaced literal, a stale entry, or an entry
for an occurrence the rules already classify. Line numbers move with the source: re-run
``python tests/_regen_reason_codes.py`` and fix the keys it reports.
"""

REVIEW: dict[tuple[str, int, str], tuple[str, str]] = {
    ("airag/api.py", 79, "DB_BUSY"): ("reason", "value of the response's \"code\" key through a ternary"),
    ("airag/api.py", 79, "DB_OPERATIONAL_ERROR"): ("reason", "value of the response's \"code\" key through a ternary"),
    ("airag/db/connect.py", 48, "SCHEMA_VERSION"): ("data", "name in __all__, an identifier"),
    ("airag/diagnostics.py", 39, "RUNTIME_PROBE_FAILED"): ("reason", "stored as the probe's error_code"),
    ("airag/embeddings.py", 280, "PROVIDER_RATE_LIMITED"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag/embeddings.py", 282, "PROVIDER_SERVER_ERROR"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag/embeddings.py", 287, "PROVIDER_REQUEST_ERROR"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag/llm_enrichment.py", 173, "PROVIDER_RATE_LIMITED"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag/llm_enrichment.py", 175, "PROVIDER_SERVER_ERROR"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag/llm_enrichment.py", 176, "PROVIDER_REQUEST_ERROR"): ("reason", "returned classification code raised/reported by the caller"),
    ("airag_consumer/_result.py", 57, "RUNTIME_FAILED"): ("reference", "fallback code; declared by the pass child and the tick"),
    ("airag_consumer/_result.py", 64, "RUNTIME_FAILED"): ("reference", "fallback code; declared by the pass child and the tick"),
    ("airag_consumer/_result.py", 84, "RUNTIME_FAILED"): ("reference", "frame code set member; declared by the pass child and the tick"),
    ("airag_consumer/_result.py", 84, "RUNTIME_OUTPUT_INVALID"): ("reference", "frame code set member; declared by the tick's TickError"),
    ("airag_consumer/_result.py", 87, "CORE_PUBLICATION_FAILED"): ("reference", "fallback code for an unrecognized publish failure; declared by the bridge"),
    ("airag_consumer/bridge.py", 42, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/bridge.py", 221, "CORE_PUBLICATION_FAILED"): ("reason", "assigned and reported as the publication error_code"),
    ("airag_consumer/cli.py", 149, "INTERNAL_ERROR"): ("reason", "assigned and emitted as the error code"),
    ("airag_consumer/collector.py", 451, "EXCLUDED_NON_MESSAGE_RESPONSE"): ("reason", "skip reason carried in the classification"),
    ("airag_consumer/collector.py", 451, "EXCLUDED_REASONING"): ("reason", "skip reason carried in the classification"),
    ("airag_consumer/events.py", 17, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/events.py", 21, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/events.py", 28, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/lifecycle.py", 482, "INVALID_EVENT_LIMIT"): ("reason", "tuple partner passed to _error(code) in the loop"),
    ("airag_consumer/lifecycle.py", 483, "INVALID_TOKEN_LIMIT"): ("reason", "tuple partner passed to _error(code) in the loop"),
    ("airag_consumer/lifecycle.py", 484, "INVALID_OPEN_TAIL_SECONDS"): ("reason", "tuple partner passed to _error(code) in the loop"),
    ("airag_consumer/lifecycle.py", 485, "INVALID_RETENTION_DAYS"): ("reason", "tuple partner passed to _error(code) in the loop"),
    ("airag_consumer/lifecycle.py", 486, "INVALID_ACTIVE_WINDOW_COUNT"): ("reason", "tuple partner passed to _error(code) in the loop"),
    ("airag_consumer/memory.py", 399, "PROVIDER_TIMEOUT"): ("reason", "assigned then passed to MemoryProviderError as its code"),
    ("airag_consumer/memory.py", 399, "PROVIDER_UNAVAILABLE"): ("reason", "assigned then passed to MemoryProviderError as its code"),
    ("airag_consumer/memory.py", 496, "COMMIT"): ("data", "SQL statement text"),
    ("airag_consumer/memory.py", 700, "NULL"): ("data", "SQL fragment"),
    ("airag_consumer/memory.py", 911, "UNRESOLVED_MEMORY_CONFLICT"): ("reason", "stored as the candidate's reason code"),
    ("airag_consumer/memory.py", 913, "EXPLICIT_USER_CONFIRMATION_REQUIRED"): ("reason", "stored as the candidate's reason code"),
    ("airag_consumer/memory.py", 915, "VERIFICATION_EVIDENCE_REQUIRED"): ("reason", "stored as the candidate's reason code"),
    ("airag_consumer/memory.py", 960, "VERIFICATION_EVIDENCE_REQUIRED"): ("reason", "VerificationDecision reason_code through a ternary"),
    ("airag_consumer/memory.py", 960, "VERIFIER_CONFIRMED"): ("reason", "VerificationDecision reason_code through a ternary"),
    ("airag_consumer/memory.py", 1247, "PROVIDER_FAILURE"): ("reason", "assigned and stored as the extraction failure reason"),
    ("airag_consumer/reference.py", 48, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/reference.py", 54, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/runtime.py", 236, "INVALID_"): ("data", "prefix of a dynamic code family, not a whole code (design 5.4)"),
    ("airag_consumer/runtime.py", 57, "AIRAG_PROFILE_SOURCE_KEY_HEX"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 32, "AIRAG_ARCHIVE_KEY_HEX"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 32, "AIRAG_CONSUMER_KEY_HEX"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 32, "AIRAG_PROJECTION_KEY_HEX"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "HOME"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "LANG"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "LC_ALL"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "LC_CTYPE"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "LOGNAME"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "PATH"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "TMPDIR"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 44, "USER"): ("data", "environment variable name"),
    ("airag_consumer/tick.py", 466, "RUNTIME_FAILED"): ("reference", "fallback code passed on to TickError; declared by the pass child"),
}
