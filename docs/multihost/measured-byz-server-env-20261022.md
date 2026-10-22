# BYZ 서버 최소 환경변수 «이름» 목록 (2026-10-22)

> 작성: `aifp-pi-master-pi#0` · 발주 #3134 ① · **읽기 전용**(값은 읽지도 쓰지도 않았다 · `.env` 파일은 열지 않음)
> 대상: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` (읽기만)
> 목표 시나리오: 러너 `tests/e2e/realtime_multi_e2e.py` 의 **«실시간 통역 1회차(마이크 → STT 최종본 1건)»**
> 근거 파일: `shared/config/settings.py` · `shared/config/payment_mode.py` · `gateway/infrastructure/middleware/auth.py` · `worker/graph/speech/pulse/v6/stt_config.py` · `gateway/routes/api/v1/stt_models.py` · `clients/web/next.config.*` · `.env.example`(이름만)

## 판정 범례
- **필수(부팅)** = 없으면 프로세스가 **raise** 하며 안 뜬다
- **필수(런타임)** = 떠는 뜨지만 이 시나리오가 그 지점에서 실패한다
- **조건부** = 고른 provider/모드에 따라 필요
- **기본값 있음** = 없어도 기본으로 돈다(단 이번엔 포트가 달라 **명시 필요**한 것 표시)

---

## A. 부팅 게이트 — 없으면 프로세스가 안 뜬다

| 이름 | 쓰는 곳(파일:줄) | 없으면 | 기본값 |
|---|---|---|---|
| `PAYMENT_MODE` | `shared/config/settings.py`(`payment_mode: str = ""`) · `shared/config/payment_mode.py` `validate_payment_mode()` (gateway 기동 시 호출: `gateway/domains/credit/services/credit_slot_repository_factory.py:33`) | **raise — 부팅 실패**. 주석 명시 «There is **no default** payment mode» (#0 RULE) | **없음** |
| `APP_ENV` | `shared/config/settings.py:23`(`get_env_file_path`) · `payment_mode.py:24`(허용 조합) | 부팅은 되지만 **PAYMENT_MODE 와의 조합**이 `(local_mock,local)`·`(toss_test,local|dev)`·`(toss_live,dev|prod)` 중 하나여야 한다. 미인식 값이면 **거부** | `local` |
| `V6_AUTHORITATIVE_STT_MODE` | `worker/.../v6/stt_config.py:94` | **raise** «required — 암묵 DEV_SINGLE default 금지(C5)» | **없음** |
| `V6_AUTHORITATIVE_STT_PROVIDER` | `stt_config.py:109-113` | 모드가 `dev_single` 이면 **raise**(PROVIDER_MISSING) | **없음** |
| `V6_AUTHORITATIVE_STT_LIVE_CANDIDATES` | `stt_config.py:117-121` | 모드가 `live_chain` 이면 **raise** · 또 `live_chain` 은 **APP_ENV≠production 이면 금지**(`validate_stt_runtime_env`) | **없음** |

★주의★ `live_chain` 은 `APP_ENV` 가 production 이 아니면 **정책상 금지**된다 → mini 시험은 **`dev_single` + provider 1개** 조합이 유일한 길.

## B. 런타임 필수 — 이 시나리오가 도는 데 반드시 필요

| 이름 | 쓰는 곳(파일:줄) | 없으면 | 기본값 |
|---|---|---|---|
| `REDIS_HOST` · `REDIS_PORT` | `shared/config/settings.py`(`redis_host="localhost"`, `redis_port=6379`) · `shared/redis/client.py:get_redis_client` | 기본값으로 **6379** 를 본다 → 우리는 383xx 의 Redis 를 쓰므로 **반드시 명시** | localhost:6379 |
| `BYZ_E2E_JWT_SECRET` | `gateway/infrastructure/middleware/auth.py:19-25·109-110`(E2E HS256 폴백) · 러너 `_load_e2e_jwt_secret()`(3697-3708) | E2E 폴백이 **꺼진다** → 러너가 만든 토큰이 거부되고 `/api/v1/credits/me` 등이 None → 크레딧 경로 시험 실패 | **없음**(빈 값 = 폴백 비활성) |
| STT provider 키 (**하나**) | `gateway/routes/api/v1/stt_models.py:27-36` 표가 «env_key» 로 나열 | 고른 provider 키가 없으면 그 provider 는 `is_active=false` → STT 호출 실패 | **없음** |

STT provider 별 키 이름(표 그대로 · **하나만 있으면 된다**):
`FIREWORKS_API_KEY`(whisper-v3 primary) · `GROQ_API_KEY`(3-tier fallback) · `DEEPGRAM_API_KEY` · `ELEVENLABS_API_KEY` · `SONIOX_API_KEY` · `RETURNZERO_ID`+`RETURNZERO_SECRET` · `CLOVA_API_SECRET`(+`CLOVA_GRPC_SECRET`) · `GOOGLE_API_KEY`

## C. 조건부 — 번역/TTS 까지 갈 때

| 이름 | 쓰는 곳 | 없으면 | 기본값 |
|---|---|---|---|
| `LLM_PROVIDER` | `worker/domains/chat/services/response_service.py:49` 주석(구 코드가 `os.getenv("LLM_PROVIDER","openai")`) · 실제 해석은 `shared/config/llm_models.py` `BRAIN_LLM_PROVIDER`(558 주석) | 번역 LLM 단계가 기본 provider 로 떨어지거나 실패 | `openai`(구 코드) |
| `BRAIN_LLM_PROVIDER`(+모델) | `shared/config/llm_models.py:558` · `worker/.../polish.py:1208·1250` | polish/번역 문맥이 기본 모델로 | 있음(내부 resolver) |
| `TTS_PROVIDER` | `worker/services/tts/service.py:58`(`os.getenv("TTS_PROVIDER")`) | 서버측 TTS 오디오가 안 나감(단 **러너는 로컬 say 로 발화**하므로 1회차엔 불필요할 수 있다) | 없음(빈 값) |
| TTS 키 | `stt_models.py:38-44` — `CARTESIA_API_KEY`·`TYPECAST_API_KEY`·`SUPERTONE_API_KEY`·`GOOGLE_API_KEY`·`OPENAI_API_KEY` | 서버 TTS 비활성 | 없음 |

## D. web(Next.js) — **빌드 시점**에 박히는 값

| 이름 | 쓰는 곳(`clients/web/next.config.*`) | 없으면 | 기본값 |
|---|---|---|---|
| `NEXT_PUBLIC_API_URL` | next.config:32·55 — 기본 `http://localhost:8080/api/v1` | 기본값이 **8080** → 우리 포트(383xx)와 어긋나 FE 가 엉뚱한 곳을 본다 → **명시 필수** | 8080 |
| `NEXT_PUBLIC_SSE_URL` | :56 — 기본 `http://localhost:8080/sse/v1` | 같음 | 8080 |
| `NEXT_PUBLIC_WS_URL` | :57 — 기본 `ws://localhost:8080/ws/v1` | 같음 | 8080 |
| `NEXT_PUBLIC_BASE_URL` | :58 — 기본 `http://localhost:3001` | 같음(우리 web 포트로) | 3001 |
| `NEXT_PUBLIC_BYZ_E2E_JWT_SECRET` | next.config:60-63 (**`|| process.env.BYZ_E2E_JWT_SECRET` 폴백**) | 브라우저 쪽 E2E 토큰 생성이 꺼진다 | 빈 값 |
| `NEXT_PUBLIC_DEV_MOCK_HOST` | `clients/web/middleware.ts:33-36` — `=== '1'` 이고 다른 조건 AND | mock host 경로가 안 열린다(러너 일부 시나리오가 mock fixture 전제) | 없음 |

★NEXT_PUBLIC_* 는 **빌드 타임 인라인**★ → 서버 기동 때 바꿔도 반영 안 된다. `npm run build` **전에** 환경을 정해야 한다(이번 h 는 빌드를 포함하므로 순서가 중요).

## E. 로그인 계정 — 필요한가?

- 러너의 host 는 **«로그인(token 無)»** 경로로 들어간다(파일 헤더 12: `host=로그인(token 無) / guest=?token=…`). 즉 **`BYZ_E2E_LOGIN_*` 같은 계정 자격은 1회차에 불필요**하다(`grep -c 'BYZ_E2E_LOGIN' realtime_multi_e2e.py` = 0).
- 대신 **`BYZ_E2E_JWT_SECRET`**(B) 이 있어야 크레딧/유저 경로가 열린다.

## 최소 세트 (한 줄 요약)

**부팅+1회차에 «반드시»**: `PAYMENT_MODE` · `APP_ENV` · `V6_AUTHORITATIVE_STT_MODE=dev_single` · `V6_AUTHORITATIVE_STT_PROVIDER` · `REDIS_HOST`/`REDIS_PORT` · `BYZ_E2E_JWT_SECRET` · STT provider 키 1개
**web 빌드 전**: `NEXT_PUBLIC_API_URL` · `NEXT_PUBLIC_SSE_URL` · `NEXT_PUBLIC_WS_URL` · `NEXT_PUBLIC_BASE_URL`(+ 선택 `NEXT_PUBLIC_BYZ_E2E_JWT_SECRET`, `NEXT_PUBLIC_DEV_MOCK_HOST=1`)
**조건부**: 번역까지 → `LLM_PROVIDER`/`BRAIN_LLM_PROVIDER` + 그 키 · 서버 TTS 까지 → `TTS_PROVIDER` + 그 키

## 이 문서가 하지 않은 것
- **값 0**: `.env` 파일을 열지 않았고, 어떤 키의 값도 읽거나 적지 않았다(이름·파일:줄 만).
- 원격 쓰기 0 · 코드 수정 0.
