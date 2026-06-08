# 🗜️ headroom

> **AI 코딩 에이전트의 컨텍스트 비용을 LLM 도달 전에 깎는 로컬 프록시.** `ANTHROPIC_BASE_URL` 한 줄, 코드 변경 0.
>
> 언어 최적화는 착시(«1%). 캐시는 provider가 이미 10x 깎아 max. **남은 유일 레버는 carry/re-prefill되는 토큰 수를 줄이는 압축** — headroom이 그걸 한다.

---

## 🤔 왜 headroom?

**Claude Code / Codex / Cursor를 오래 쓰면 컨텍스트가 차고 토큰·한도가 녹습니다.** 직접 PoC로 검증한 "왜 비싼가 + 무엇이 진짜 레버인가"가 근거입니다.

스테이트리스 LLM은 턴 간 기억이 없어 **매 턴 누적 컨텍스트 전체를 다시 먹입니다**(풀 forward). 비용은 둘로 갈립니다:

- **carry** — 매 턴 쌓인 컨텍스트 재전송. 캐시 히트면 0.1배 요율이지만 **윈도우 전체 × 매 턴**.
- **re-prefill** — 캐시 만료 후 다음 턴이 풀 윈도우를 처음부터 재계산(cache_create). cache_read의 **12.5배** 중량.

한 17세션 샘플: 입력:출력 ≈ **327:1**, **비용의 절반이 cache_create(재워밍)**.

> 구독형 사용자에겐 돈보다 **rate-limit이 통화**. 캐시 만료 후 재prefill이 한도를 풀 중량으로 때립니다. **압축 = 재prefill 토큰↓ → 만료당 한도 소모↓ → 벽 치기 전 더 오래.**

---

## 🧠 핵심 멘탈모델

### ① 3-Zone — 압축은 중간띠에서만

```
[ ❄️ 동결 prefix ]   [ 🗜️ 압축 가능 중간띠 ]   [ 📤 recent N (풀) ]
 system+초기, 캐시키     오래된 tool 출력            최신 메시지(보호)
 ≥1024tok byte-동일      ← headroom 압축 대상 →       protect_recent(기본 4)
 = KV캐시 히트(0.1x)                                  크던작던 풀로 LLM행
```

- 앞쪽은 캐시 위해 **동결**(건드리면 캐시 전부 무효), recent는 fidelity 위해 **풀**.
- **신규 대화는 전부 prefix/recent → 압축 0.** 길어질수록 내용이 중간띠로 밀려 압축이 누적됩니다.

### ② 캐시 vs 압축 — 둘은 긴장 관계

압축하려면 내용을 고쳐써야 → prefix 캐시가 깨집니다. 그래서 모드가 갈립니다:

| 모드 | 동작 | 라이브 압축률 |
|---|---|---|
| `cache` | prefix 동결, 관찰만 | ~0% |
| `token` | 공격 압축 + 캐시 공존 | 재독 25~30% |

**손익분기 = 세션 길이 × 압축 후 재독 횟수.** 긴 세션만 net 이득.

> ✅ **증명됨**: `token` 모드에서 압축이 켜진 채로도 캐시가 생존합니다 — `cache_bust_count: 0`, `tokens_lost_to_cache_bust: 0`. CacheAligner가 압축 출력을 **결정론적**으로 안정화해 캐시 키를 유지하기 때문입니다. (이 결정론이 깨지면 매 요청 cache miss → 재앙. load-bearing 전제)

### ③ 프리필 타이밍 — keep-alive 루프 금지

TTL은 히트마다 갱신되니 핑으로 캐시 유지가 기술적으로 가능합니다. 그러나 **핑 1회 = 풀 윈도우 cache_read**. 12.5핑 ≈ 1시간 ≈ 재prefill 1회. 5분 내 자연 연타면 무료, 길게 비울 거면 만료 후 복귀 시 재prefill 1번이 쌉니다.

> **구독형은 idle 핑이 한도 자해.** 정답: 온디맨드 재prefill(보증금) > 루프(임대료). → 거의 항상 손해.

---

## ⚙️ 동작 — 요청 여정

API 경계 프록시(`ANTHROPIC_BASE_URL=localhost:PORT`):

1. **분류** — ContentRouter가 타입 판별 → JSON / 코드(AST) / 산문 차등 압축.
2. **가역 압축(CCR)** — 원본은 로컬 보관, 모델엔 압축본 + `headroom_retrieve` 통로. 컨텍스트 내 lossy, 필요 시 복원.
3. **캐시 정합(CacheAligner)** — 압축 출력을 결정론적으로 안정화해 prefix 캐시 키 유지.
4. **재prefill** — `[동결 prefix] + [압축 중간띠] + [recent 풀]` → **가장 비싼 cache_create를 작은 토큰 위에서** = 최대 페이오프.

---

## 📦 설치

```bash
python3.12 -m venv ~/.headroom-venv
~/.headroom-venv/bin/pip install "headroom-ai[all]"
~/.headroom-venv/bin/headroom --version       # 0.23.0
```

프록시 기동 (압축 + 캐시 공존 — 증명된 조합):

```bash
HEADROOM_MODE=token HEADROOM_COMPRESS_USER_MESSAGES=1 HEADROOM_CODE_AWARE_ENABLED=1 \
  ~/.headroom-venv/bin/python -m headroom.proxy.server \
  --port 8790 --compress-user-messages --exclude-tools Bash --code-aware
```

> click `headroom proxy`는 옵션이 제한적 → **`python -m headroom.proxy.server` 직접 실행**이 full 제어.

---

## 🚀 사용

### fail-open 래퍼 (SPOF 제거 — 핵심 안전장치)

프록시가 살아있을 때만 경유, 죽으면 직결되어 작업이 무중단됩니다:

```bash
#!/bin/zsh
if curl -sf -m1 http://localhost:8790/health >/dev/null 2>&1; then
  export ANTHROPIC_BASE_URL=http://localhost:8790
else
  unset ANTHROPIC_BASE_URL    # 프록시 다운 → 직결, 작업 무중단
fi
exec claude "$@"
```

`~/.zshrc`에 `alias claude-hr='~/.headroom/claude-hr.sh'` 추가 후 `claude-hr`로 실행.

### 관찰 (`/stats`)

```bash
curl -s localhost:8790/health        # status healthy
curl -s localhost:8790/stats         # 압축률 + cache_bust_count(0이어야 정상)
```

| 지표 | 의미 |
|---|---|
| `avg_compression_pct` | 압축 발동 정도 |
| **`cache_bust_count`** | **0 유지 필수** (>0 = 캐시 깨짐 = 손해 신호) |
| `cache_write_1h_tokens` | 1h extended 캐시 사용 확인 |
| `/api/oauth/usage` | 구독 rate-limit 소모 (압축 효과 실측) |

---

## 🎯 어디에 쓰면 효과가 큰가

압축은 **입력이 크고 + 여러 턴 재실리고 + 압축 여지가 있을 때** 발동합니다.

| | ✅ 강타깃 | ❌ 약타깃 |
|---|---|---|
| 입력 덩치 | 코딩 tool 출력 / 긴 전사(수천~수만 tok) | 짧은 요약 (~수백 tok) |
| 재실림 | 긴 미션 / 세션 누적 | 단발 독립 호출 |
| 압축 여지 | tool 출력 캐시 밖 벌키 | 시스템 프롬프트(이미 캐싱) |
| resume | 재개마다 cold prefill | — |

→ **multi-agent swarm · 긴 코딩 세션 · 긴 문서/전사 후처리 · 다중 청크 RAG** 에 강함. **단발 채팅 · 작은 입력 · 시스템 프롬프트**엔 무의미.

---

## ⚠️ 정직한 한계

PoC 실측을 그대로 공개합니다 (신뢰의 핵심):

| 경로 | 압축률 |
|---|---|
| 라이브러리 직접(`compress_user_messages=True`) | **83.7%** |
| 라이브 프록시 — 단발 read | **0%** (표준 도구 기본 제외 + recent 보호) |
| 라이브 프록시 — 재독/supersede | **25~30%** (best 30.7%) |

- **단발 0%는 버그가 아니라 설계.** `DEFAULT_EXCLUDE_TOOLS = {Read,Bash,Grep,Glob,Edit,Write}` + `protect_recent`(기본 4)가 표준 도구 결과와 최근 메시지를 보호합니다. 같은 파일을 **재독(supersede)** 할 때 옛 복사본이 보호 밖으로 밀려 압축이 발동합니다.
- **만능 아님**: 기본설정은 코딩 에이전트 도구 출력을 안 건드림. tool_result 압축은 베타(rtk).
- **디버깅 주의**: CCR은 컨텍스트 내 lossy. 모델이 복원 필요를 모르면 오판할 수 있으니, 디버깅 워크플로우에서는 `headroom_retrieve` 복원 정확도를 별도 점검하세요.
- 수치는 환경/버전(v0.23)에 따라 다를 수 있음.

---

## 📜 라이선스

MIT
