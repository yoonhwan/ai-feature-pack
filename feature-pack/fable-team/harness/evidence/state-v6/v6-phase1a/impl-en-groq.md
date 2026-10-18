# impl-en-groq — EN STT chain groq 추가

## 변경 4파일

1. **shared/config/stt_models.py** — `ENGLISH_STT_FALLBACK_CHAIN: list[str] = ["groq", "fireworks"]` 상수 추가 (VIETNAMESE 아래, GPU_EXCLUDED_LANGS 위).
2. **worker/graph/speech/pulse/nodes/stt.py** — import에 ENGLISH_STT_FALLBACK_CHAIN 추가 + lang 분기에 `elif not env_provider and lang_lower.startswith("en")` 분기 1개 추가 (vi 뒤, else 앞).
3. **worker/services/stt/service.py** — import + lang 분기에 `elif is_english: chain = ENGLISH_STT_FALLBACK_CHAIN` 추가 (서비스 레벨도 pulse 노드와 동일 chain 적용).
4. **docs/rules/stt_provider_policy.md** — §5 EN chain 정책 1줄 추가.

## 테스트

- `tests/unit/worker/services/test_stt_routing_v5.py` — EN 섹션 3개 테스트로 교체: groq 1순위 / groq fail→fireworks fallback / 상수 검증.
- ruff: All checks passed
- pytest: **19 passed** in 0.27s (기존 16 + EN 신규 3)
