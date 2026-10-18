# factpack-code.md — v6 missing 트랙 코드 분석 (chk-dedup, 2026-07-08)

## ① demote_skip 가드 전체 흐름

**위치**: `pulse_consumer.py:1413~1429`

**발동 조건**: `sentence_splitter` 노드 실행 후 splitter_residual이 있고 `delta_sentences`(이번 라운드 이미 확정된 문장들)도 있을 때, `_seam_norm(splitter_residual)` vs `_seam_norm(각 delta_sentence)` 비교.

```python
if n_residual == n_ds or n_ds in n_residual:   # ← "포함" 조건
    _demote_is_dup = True
```

**동작**: `_demote_is_dup=True` → `residual = splitter_residual` 업데이트 스킵 → 이전 `residual` 값 유지. 정상 케이스에서는 `else: residual = splitter_residual` 실행.

**유효 문장을 죽이는 경우**: `n_ds in n_residual` 포함 조건이 문제.
예: delta에 `"We agreed"` (norm=`"we agreed"`), splitter_residual=`"We agreed that before shipping the fix"` → `"we agreed" in "we agreed that..."` = True → residual 전체 버림 → 후반부(`"that before shipping the fix"`)도 같이 소실.
→ **delta 문장이 residual의 접두사인 경우, residual 후미의 새 내용까지 통째로 드롭.**

## ② press_end residual 확정 정책

**경로 A — `_deterministic_split(is_final=True)`** (`assemble.py:216~219`):

```python
if is_final:
    segments = _SENTENCE_BOUNDARY_RE.split(combined)
    return {"sentences": segments or [combined], "residual": ""}  # ← 항상 residual=""
```

is_final=True chunk이면 splitter 투입 전 단계에서 이미 `residual=""`. combined 전체가 sentences로 분리됨.

**경로 B — `_empty_final_reconfirm`** (`assemble.py:342~388`): is_final=True + prev_residual 있음 + stt_text 없음(no_speech_tail) + sentences==[prev_residual] 일 때:

```python
elif len(_final_residual) < _FORCE_FINALIZE_CHARS(=20) and not _has_pending_carry:
    sentences = []; residual = ""          # SHORT(<20자) → DROP
else:
    # [pulse.guard] force_finalize residual_len=N   → sentences=[residual], residual=""
```

- **< 20자**: 드롭 (STT artifact 취급)
- **≥ 20자**: force_finalize → sentences에 승격, residual=""

**경로 C — EN short boundary deferred** (`assemble.py:252~258`): 라틴 텍스트 + combined < `_EN_SHORT_BOUNDARY_CHARS` → 전체를 residual로 유지(경계 보류). press_end_final 시 `_press_end_unconsumed_residual`의 주 공급원.

**5회전 82자 중 49자 확정·33자 탈락 실증 (chunk_seq=11, L5118)**:
- `prev_residual="Original race condition reliably."` (33자), no_speech_tail
- `_empty_final_reconfirm=True`, len=33 ≥ 20 → `force_finalize` → sentences=[33자], residual=""
- 이후 sentence_splitter → 완전 문장 → splitter_residual="" → D-2 `residual=""` → carry.tail 미동작
- **근본 원인: pending segment_id 소진** — `_PENDING_SEGMENT_IDS`가 비어 `issued_segment_id=False` → `segment_commit` 노드 미실행 → confirmed 미발행. 49자는 앞선 is_final=True chunk(seq=7)에서 ledger 확정된 것.

## ③ 꼬리 STT 소실 경로

**known hallucination 거부** (`stt_fallback.py:285~288`): `"No."` 같은 `_KNOWN_HALLUCINATIONS` 패턴 → provider reject. 전부 reject → `return None, last_rejected_text`.

**empty/unusable 거부** (`stt_fallback.py:310~318`): 빈 전사 → `saw_empty_transcription=True` → (`:319~`) `return None, _NO_SPEECH`.

**no_speech_tail suppressed** (`stt.py:386~399`): `_NO_SPEECH` sentinel → `stt_text=""` 반환(에러 아님) → assemble `stt_for_split=""` → combined=prev_residual only → is_final=True이면 `_deterministic_split` residual="" → ② 경로 진입.

**발동 조건 요약**: 꼬리 청크(짧은 오디오, 실제 무음 또는 "No." 환각) → 모든 provider reject → no_speech_tail = stt_text="" → residual 소실 경로 진입.

## ④ D-2 carry.tail이 구제 못하는 이유

**D-2 코드** (`pulse_consumer.py:1881~1887, 2267~2268`):
```python
if residual and residual.strip() and broadcast_mode != "release":
    _press_end_unconsumed_residual = residual.strip()
if _press_end_unconsumed_residual and press_end_final and _base_final:
    final_text = (_base_final + " " + _press_end_unconsumed_residual).strip()
```

**`residual=0`으로 도착하는 경로 (D-2 미동작 조건)**:

| 경로 | 원인 | residual 상태 |
|------|------|--------------|
| no_speech_tail | stt_text="" → _deterministic_split(is_final=True) | "" |
| force_finalize | sentences=[residual_content] → splitter 처리 후 | "" |
| demote_skip 후 is_final chunk | old_residual 유지됐어도 후속 is_final assemble이 덮어씀 | "" |

**구조적 이유**: `residual` 변수는 splitter 출력 `splitter_residual`로 업데이트됨. force_finalize/no_speech_tail 경로에서 splitter가 완전 문장을 소화하면 `splitter_residual=""` → D-2 조건 미충족. D-2는 **EN short boundary deferred 경로**에서만 동작.

## 설계 레버 후보

| 레버 | 위치 | 동작 |
|------|------|------|
| demote_skip `n_ds in n_residual` → 접두사 전용으로 좁히기 | `pulse_consumer.py:1418` | `n_residual.startswith(n_ds)` or len 비율 게이트 추가 |
| segment_commit을 `issued_segment_id=False`여도 pending 소진 후 발동 | `assemble.py:277~287 + segment_commit.py` | `final_boundary + sentences > 0`이면 새 segment_id 발급 |
| force_finalize 결과를 D-2 tail에 합류 (splitter 우회) | `pulse_consumer.py:1881` | force_finalize 결과를 `_press_end_unconsumed_residual`로 직접 주입 |
| `_FORCE_FINALIZE_CHARS` 하한 조정 | `assemble.py:28` | 현재 20자 — 짧은 tail 문장(≥8자?) 수용 |
