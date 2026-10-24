# NANO 결과 — mini worker env «이름» 차집합 (읽기 전용, 2026-10-25)

> 발주 #3295 · 워커 `aifp-multihost-nano-pi#0` · 상위 `aifp-multihost-master-claude#4`
> 목적: 이미 두 번 난 사고 클래스(**이 맥 `.env` 에는 있는데 서버 h 의 `KEYS` 화이트리스트에 이름이 없어 mini 로 안 넘어감** — `V5_BACKEND_ENABLED`·`DEV_GPU_STATUS_URL`)의 **잔여 후보를 «이름만»** 찾는다.
> **값 0 · `.env` 열람 0 · 원격 쓰기 0 · 서버 재시작 0 · Redis 쓰기 0** (mini 에서는 `rg`/`sed`/`cat` 읽기만)

## 0. 확인한 사실 (근거)

| 항목 | 확인 결과 |
|---|---|
| mini 코드 리비전 | `~/Project/BYZ-Agents/.h-installed` 1필드 = **`c34fc47f24c8…`** → 브리프의 BYZ main `c34fc47f` 와 일치(코드 열람이 유효). `.git` 은 없음(`git archive` 반입) |
| 넘어가는 «이름» = ① h 의 `KEYS` 화이트리스트(`h-mini-byz-server.sh:36-43`) ② `WORKER_ENV_SPEC` 고정값 채우기(`:200-207`) ③ `CORPUS_RETENTION_DAYS=30` 고정(`:189`) ④ dev DSN 2개(`:193-199`) ⑤ 스크립트가 직접 export 하는 `REDIS_HOST/REDIS_PORT/REDIS_URL`(`:235`) | 그 외 이름은 **`.env` 에 있어도 mini 로 가지 않는다**(`:179-185`) |
| 로컬 정본 worker 기동 세트 | `scripts/server/ready-check.sh:20` `WORKER_ENV_SPEC` (11항: `PORT`·`APP_ENV`·`GPU_STT_TTS_URL`·`GPU_STT_MODEL`·`V6_AUTHORITATIVE_STT_PROVIDER`·`V6_AUTHORITATIVE_STT_MODE`·`STT_PROVIDER`·`V6_LST_TRANSLATE`·`V6_STT_CHUNK_TEXT_LOG`·`V65_OWNER_BOOTSTRAP_ENABLED`·`LOOM_PG_TUNNEL_PORT`) → **`PORT` 빼고 전부 h 가 채운다**(`:202-206`) · `server.sh:262-274` 가 같은 배열을 읽어 export |
| `server.sh` 의 추가 필수 이름 | `server.sh:208` 검사 6개(`PAYMENT_MODE`·`APP_ENV`·`V6_AUTHORITATIVE_STT_MODE`·`V6_AUTHORITATIVE_STT_PROVIDER`·`BYZ_E2E_JWT_SECRET`·`V5_BACKEND_ENABLED`) = **전부 KEYS 에 있음** ✓ · `require_worker_env`(`:766-776`) 목록도 spec ∩ KEYS ✓ |
| 러너 측 env | `h-mini-e2e-round1-run.sh:104-108` = `BYZ_E2E_JWT_SECRET` **하나만** 넘긴다(그 이름은 KEYS 에 있음 ✓) |
| CORS | `gateway/infrastructure/middleware/cors_origins.py:8-26` — `APP_ENV=local` 이면 `localhost:3011-3499`·`3000-3499`·`38301-38399` 자동 허용 → **CORS env 불필요**(mini 의 38312/38314 커버) |

## 1. 확신도 정의 (섞지 않는다)

- **확정** = ⓐ 이름이 없을 때의 증상이 코드 한 줄로 닫히고 ⓑ **이 맥 `.env` 에 그 이름이 있다는 근거**(코드 주석·테스트·문서)가 있다.
- **추정** = ⓐ 또는 ⓑ 중 하나가 미확인. 표의 «미확인 지점» 칸에 무엇이 미확인인지 적었다.
- 즉 아래 **확정 1건 / 추정 9건**이며, 확정 1건은 **ko 1회차 경로를 깨지 않는다**(언어 축). 1회차를 깨는 후보는 전부 «추정» 이다 — 이 사실 자체가 보고 대상이다(이름 목록만으로는 «이 맥 값 존재» 를 확정할 수 없다: `.env` 열람 금지 제약).

## 2. 확정 (1건)

| 이름 | 코드 위치 | 없으면 생기는 증상 | 미확인 지점 |
|---|---|---|---|
| `GPU_EXCLUDED_LANGS` (및 `_TTS`·`_LLM`) | `shared/config/gpu_excluded_langs.py:39-43`(이름표)·`:74`(union) | mini 에는 이 이름이 안 가므로 제외 목록 = **코드 기본값만**. 이 맥은 `.env` 값 `uz,uk` 가 «추가» 되고 있었다(코드 주석 `:63-64` 원문: 「로컬 `.env`(`GPU_EXCLUDED_LANGS=uz,uk`)」 · 테스트 `tests/unit/shared/test_gpu_excluded_langs.py:40`) → **uz/uk 발화가 이 맥은 GPU 를 피하고 mini 는 GPU 로 간다**(provider 라우팅 갈림). **ko 회차엔 영향 0** | — (값 존재 근거 있음 · 증상도 코드 확인) |

## 3. 추정 (9건 · 위에서부터 유력)

| # | 이름 | 코드 위치 | 없으면 생기는 증상 (1줄) | 미확인 지점 |
|---|---|---|---|---|
| 1 | `V5_RMS_THRESHOLD` | `worker/services/stt/base.py:68` (기본 `200.0`) · 게이트 적용 조건 `:72-80` | L0 무음 게이트 임계가 기본 200 으로 돌아간다 — **ko 는 게이트 유지 대상**(`:79` `return not (ja|zh|vi)`) 이므로 mini BlackHole 캡처가 200 미만이면 `make_skip_response(text="")` → STT 빈 결과 → `host_empty`(6번째 실패와 «다른 입구, 같은 출구») | 이 맥 `.env` 에 이 이름이 있는지 (없으면 후보 아님) |
| 2 | `PULSE_STT_PROVIDER` | `worker/graph/speech/pulse/nodes/stt_core.py:233` | pulse STT 의 provider 강제가 사라져 `STT_PROVIDER`(=spec 고정 `fireworks`) 체인으로 떨어진다 → **원문 자체가 달라진다**(고유명사·첫 음절) → polished 문장도 달라져 `delta`/Nchars 판정이 흔들린다 | 이 맥 `.env` 값 존재·값(어느 provider 인지) |
| 3 | `V5_TRANSLATE_FINAL_CAP_S` | `worker/graph/speech/pulse/nodes/translate_raw.py:48` (기본 `7`) | 번역 final 캡이 7초로 고정 — mini(콜드 LLM·원격 DSN)에서 7초 초과 시 그 문장 번역 미완 → polished 누락/원문 유지 | 이 맥 `.env` 값(>7 로 올려 뒀는지) |
| 4 | `BYZ_DIFF_POOL_ENABLED` | `worker/graph/speech/pulse/nodes/polish.py:414` (기본 `false`) | polish 후처리(substring 보정, 최대 3회 치환)가 꺼진 채 돈다 → **같은 원문인데 polished 문자열·Nchars 가 이 맥과 다르다**(성공 줄의 `polished Nchars` 판정이 이 맥 값과 비교 불가) | 이 맥 `.env` 값(`true` 인지) |
| 5 | `V5_RETRANSLATE_PRESS_END_CAP_S` | `worker/graph/speech/pulse/nodes/retranslate_press_end.py:26` (기본 `4`) | press 종료 재번역 캡이 4초로 고정 → 꼬리 문장 재번역이 잘려 마지막 말풍선이 원문 잔존 | 이 맥 `.env` 값 |
| 6 | `CLOVA_CLIENT_ID`·`CLOVA_CLIENT_SECRET` · `RETURNZERO_CLIENT_ID`·`_SECRET` · `XAI_API_KEY`·`XAI_GROK_API_KEY` · `DASHSCOPE_API_KEY` | `worker/services/stt/clova.py`·`returnzero.py`·`xai.py`·`qwen.py:77,87` (provider 별 키 짝) | **KEYS 는 이 중 `CLOVA_API_SECRET`·`RETURNZERO_ID/SECRET` 만 넘긴다** → `.env` 의 `STT_PROVIDER` 가 clova·returnzero·xai·qwen 이면 mini 에서 그 provider 는 키 부재로 비활성/`RuntimeError` → STT 실패 | 이 맥 `STT_PROVIDER` 값(어느 provider 인지). `dev_single` 이면 이 축이 곧 STT 정본 |
| 7 | `ANTHROPIC_API_KEY` | `worker/services/llm/anthropic.py:47` · `worker/services/llm/service.py:301` | `LLM_PROVIDER`(KEYS 로 넘어감)가 `anthropic` 이면 **이름은 가고 키는 안 가서** provider 선택 후 생성 실패 → polish/translate 단계 결과 없음 | 이 맥 `LLM_PROVIDER`/`BRAIN_LLM_PROVIDER` 값 |
| 8 | `SPLITTER_LLM_TIMEOUT_S`(6.0) · `GPU_STT_RT_TIMEOUT_S`(6.5) · `DEV_GPU_STATUS_TTL_SEC`(10.0) · `GPU_POOL_MAX_CONNECTIONS`(10)/`MAX_KEEPALIVE`(5) | `nodes/sentence_splitter.py:29` · `nodes/stt_fallback.py:23` · `services/gpu/client.py:70,160-161` | 실패가 아니라 **기본값으로 돈다** — mini 가 더 느리면 splitter/RT 타임아웃이 이 맥보다 먼저 걸려 문장 분할·폴백이 달라진다 | 이 맥 `.env` 에서 조정했는지 |
| 9 | `BYZ_GUEST_JWT_ENABLED`·`BYZ_GUEST_JWT_SECRET` · `NEXT_PUBLIC_SUPABASE_URL` · `STRICT_AUTH` · `INTERNAL_SECRET` | `auth/guest_jwt.py:30,34` · `middleware/auth.py:21,144` · `auth/deps.py:41` | 인증 축 — 1회차 host 는 «token 無» 경로 + `BYZ_E2E_JWT_SECRET`(넘김)이라 **지금은 무영향**이지만, `?token=` guest 시나리오로 확장하면 guest 시크릿 부재로 게스트 토큰 거부 | 러너가 guest 시나리오를 언제 돌리는지(1회차 범위 밖) |

### 확인했지만 «후보 아님» 으로 닫은 것 (다음 좌석이 다시 안 뒤지도록)

- `V5_BACKEND_ENABLED`·`DEV_GPU_STATUS_URL` — **이미 KEYS 에 있다**(`:39`,`:40`) = 고친 2건.
- `REDIS_HOST/PORT/URL` — h 가 `:235` 에서 직접 export ✓ (spec 미등재지만 넘어감).
- `V65_OWNER_BOOTSTRAP_ENABLED`·`V6_LST_TRANSLATE`·`V6_STT_CHUNK_TEXT_LOG`·`GPU_STT_TTS_URL`·`V6_AUTHORITATIVE_STT_*` — spec 이 채움 ✓.
- `V65_UNSEALED_RAW_CONFIRM` — `owner_terminal.py:34-38` **미설정 = ON**(raise 아님) ✓.
- `V6_STT_ALLOW_NONPROD_CHAIN`·`V6_AUTHORITATIVE_STT_LIVE_CANDIDATES` — `live_chain` 전용인데 이 회차는 `dev_single` ✓.
- `SPIKE_V5_ENABLED`(`gateway/main.py:664`) — `/spike/v5` 에코 라우터 전용, `/v5` 본 라우터는 `v5_config.backend_enabled`(`:139`) ✓.
- `VERTEX_PROJECT`·`GOOGLE_TRANSLATE_API_KEY` — `GOOGLE_API_KEY` 폴백이 넘어간다(`stt/google.py:70`·`compat/misc.py:66`) ✓.
- `QDRANT_*` — glossary/검색(`compat/search.py:34-37`) 경로지 press→polished 경로 아님.
- `NEXT_PUBLIC_*` — 빌드 타임 인라인이고 h 가 `:153` `BUILD_ENV` 로 4개를 박는다 ✓.
- `V65_LLM_KEEPALIVE_SEC`·`TTS_CACHE_ENABLED`·`SUPERTONIC_TTS_ENABLED`·`CREDIT_METERING_BEST_EFFORT`·`TOPUP_ENABLED`·`USE_SEPARATED_TOKEN_PRICING`·`V65_CORPUS_FE_ENABLED`·`PTT_TRACE_LOG`/`LOG_DETAIL` — 기본값/계기용(실패 아님).

## 4. 가장 유력 1개 (상위 판단용)

**`V5_RMS_THRESHOLD`** — 유력도가 가장 높은 이유: ① 입구가 «마이크 오디오» 그 자체이고 mini 는 캡처 장치·경로가 이 맥과 다르다(BlackHole 루프백) ② ko 는 L0 게이트 대상이라 예외가 없다 ③ 없을 때의 출구가 `host_empty` 로 **이미 관측된 실패와 같은 모양**이다.
→ 다음 회차 전에 h 스크립트가 **이름만 확인**(값 아님)해서 `.env` 에 있으면 KEYS 에 추가하는 것으로 닫는 게 가장 싸다. 값이 0 이면 0 도 넘겨야 한다(= 미설정과 «명시적 0» 이 정반대로 동작하는 유일한 이름).

## 5. 이 문서가 하지 않은 것

- `.env` **열람·grep·cat 0**(값 0 · 이름은 코드·테스트·문서에서만 모았다) · 원격 쓰기 0 · 서버/Redis 재시작·쓰기 0 · `docs/multihost/h-plans/` 편집 0 · 커밋 0.
- 확정 판정에 필요한 «이 맥 `.env` 이름 목록» 은 **의도적으로 만들지 않았다**(금지 항목). 그래서 차집합의 «존재» 쪽 절반은 상위가 h 로 이름만 확인해야 닫힌다 — 이 문서는 **코드 쪽 절반(무엇이 없으면 무엇이 깨지는가)을 확정**했다.
