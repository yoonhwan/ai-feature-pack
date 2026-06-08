# Headroom / LLM 컨텍스트 비용 — SSOT 다이제스트 (퍼블릭)

> AI 코딩 에이전트의 컨텍스트 비용 구조와 headroom 압축 레버에 대한 실측·추론 정리.
> PoC 실측 기반. 수치는 환경/버전(v0.23)에 따라 다를 수 있음.

---

## 1. 근본 문제 — 왜 세션 이어가기가 비싼가

스테이트리스 LLM은 턴 간 기억이 없어 **매 턴 누적 컨텍스트 전체를 다시 먹인다**(풀 forward). 세션 비용은 두 가지로 분해:

- **carry 비용** — 매 턴 쌓인 컨텍스트를 재전송. 캐시 히트면 0.1배 요율이지만 **윈도우 전체 × 매 턴**.
- **re-prefill 비용** — 캐시 만료(TTL) 후 다음 턴이 풀 윈도우를 처음부터 재계산(cache_create). read의 **12.5배** 중량.

실측(트랜스크립트 약 17세션 샘플): 입력:출력 = **327:1**, 입력의 91%가 cache_read, **비용 51%가 cache_create(재워밍)**, 42%가 cache_read, 출력 7%.

## 2. 캐시 메커니즘 (Anthropic prompt caching)

- **prefix-exact + append-only**: 캐시는 처음부터 토큰-동일한 prefix에만 히트. 앞쪽 한 토큰만 바뀌어도 그 뒤 전부 무효.
- **최소 단위 ~1024 토큰** (Opus/Sonnet 1024, Haiku 2048).
- **TTL 5분, 히트할 때마다 갱신** (extended 1시간 옵션).
- **단가(Opus, /M tok):** 입력 $15 · cache_read $1.50(0.1x) · cache_write $18.75(1.25x = read의 12.5x) · 출력 $75.
- 구현상 prefix 블록을 해시해 매칭 → "앞쪽 해시로 캐시 키" 직관 맞음.

## 3. 3-Zone 모델 (핵심 기하)

```
[ ❄️ 동결 prefix ]   [ 🗜️ 압축 가능 중간띠 ]   [ 📤 recent N (풀) ]
 system+tools+초기       오래된 turn/tool 출력        최신 메시지
 ≥1024tok byte-동일       ← headroom 압축 대상 →        protect_recent(기본4)
 = KV캐시 히트(0.1x)                                    크던작던 풀로 LLM행
```
- 앞쪽: 건드리면 캐시 전부 무효 → 동결 사수(CacheAligner).
- recent N: fidelity 위해 풀 보존.
- **압축은 중간띠에서만.** 신규 대화는 전부 prefix/recent라 압축 0; 대화가 길어져 내용이 중간띠로 밀릴수록 압축 누적.

## 4. headroom 메커니즘 (요청 여정)

1. **가로채기** — `ANTHROPIC_BASE_URL=localhost:PORT`. 에이전트→headroom→실제 API. 코드 변경 0.
2. **분류** — ContentRouter가 타입 판별 → SmartCrusher(JSON)/CodeCompressor(AST)/Kompress(산문)로 차등 압축.
3. **가역성(CCR)** — 원본은 로컬 보관, 모델엔 압축본 + `headroom_retrieve` 통로. 컨텍스트 내 lossy, 요청 시 복원. (리스크: 모델이 복원 필요를 모르면 오판 — 디버깅 주의)
4. **캐시 정합(CacheAligner)** — 압축 출력을 **결정론적**으로 안정화해 prefix 캐시 키 유지. ⚠️ 결정론 깨지면 매 요청 cache miss → 영구 재prefill 재앙. **load-bearing 전제.**
5. 재생성 시: [동결 prefix] + [압축된 중간띠] + [recent 풀]로 재prefill → **작은 토큰 위에서 cache_create** = headroom 최대 페이오프(가장 비싼 12.5x 사건을 작게).

## 5. 두 레버 — 캐시는 max, 압축이 남은 유일 레버

| 레버 | 작용 | 상태 |
|---|---|---|
| 언어 영문화 | carry의 비영어 비중만, 소폭 | ❌ «1%, 레버 아님 |
| 캐시(요율) | 1x→0.1x | ✅ provider가 이미 10x, **max** |
| **압축(토큰 수)** | 윈도우 자체를 cW로 | ✅ **남은 유일 추가 레버 = headroom** |
| 프리필 타이밍 | 언제 풀 prefill 낼지 | bursty/온디맨드. **keep-alive 루프 금지** |

## 6. compress ↔ cache 트레이드오프 (근본 긴장)

압축하려면 내용을 고쳐써야 하나, 고쳐쓰면 prefix 캐시가 깨짐. 그래서 모드 2개:
- `token`: 공격 압축, 캐시 깸 우려 → 단 CacheAligner로 공존 증명(§8). (재독서 라이브 25~30%)
- `cache`: prefix 동결, 압축 ~0. (라이브 0%, observability only)
- 손익분기 = **세션 길이 × 압축 후 재독 횟수**. 긴 세션만 net 이득.

## 7. 트리거 조건 (out-of-box 0%의 이유)

- `DEFAULT_EXCLUDE_TOOLS = {Read,Bash,Grep,Glob,Edit,Write}` — 코딩 에이전트 표준 도구 결과 기본 제외.
- `protect_recent`(기본4) — 최근 메시지 보호.
- `compress_user_messages=False` 기본 (tool_result는 user 메시지).
- → 단발 read 0%. **같은 파일 재독(supersede) 시** 옛 복사본이 보호 밖으로 밀려 압축 발동.
- 강제법: `python -m headroom.proxy.server --compress-user-messages --exclude-tools Bash` (+ `HEADROOM_COMPRESS_USER_MESSAGES=1`). click `headroom proxy`는 옵션 제한적.

## 8. PoC 실측 결과

| 경로 | 압축률 | 조건 |
|---|---|---|
| 라이브러리 `compress(compress_user_messages=True)` | **83.7%** | 모든 eligible, aggressive |
| 라이브 프록시 단발 read | **0%** | recent 보호 + Read 제외 |
| 라이브 프록시 재독/supersede | **25~30%** (best 30.7%, 72K→50K) | 옛 복사본만 |

- 구독 OAuth 프록시 통과 ✅ · 작업 정확도 보존 ✅ · v0.23.0 · rtk(tool_result 가로채기) 베타.
- ✅ **증명 완료: 압축 켜진 상태에서 캐시 생존** (머신 검증):
  - `requests_compressed:2 avg 29.1% removed 33,300` + `cache_read 95,167` 동시
  - **`tokens_lost_to_cache_bust: 0`, `cache_bust_count: 0`** ← 압축이 캐시 안 깸. CacheAligner 결정론 입증
  - **보너스: cache_write 전부 1h(216,957 tok), 5m=0** — headroom이 1시간 extended cache 강제 → "5분 만료" 우려 자체 완화

## 9. keep-alive 루프 = 함정

TTL이 히트마다 갱신되니 4.5분 핑으로 유지는 기술적 가능. 그러나:
- 핑 1회 = 풀 윈도우 cache_read. **12.5핑 ≈ 56분 ≈ 재prefill 1회 비용.**
- 5분 내 자연 연타면 무료(핑 불필요). 1시간+ 비울 거면 만료시키고 복귀 시 재prefill 1번이 쌈.
- **구독형은 idle 중 핑이 rate-limit을 갉아먹어 자해.** → 거의 항상 손해.
- **정답: 온디맨드 재prefill (보증금) > 루프 (임대료).**

## 10. 구독 rate-limit 재프레임 (도입 명분)

구독형은 돈이 아니라 **rate-limit이 통화**. 캐시 만료 후 재prefill이 한도를 풀 중량으로 때림. 느린/텀 긴 사용 = 매 턴 풀 prefill = 한도 폭식.
- **headroom 가치 = 재prefill/carry 토큰 수↓ → 만료 1회당 한도 소모↓ → 벽 치기 전 더 오래 작업.**
- headroom에 **구독 사용량 폴러 내장**(`GET /api/oauth/usage`, `--subscription-poll-interval`) → 압축 on/off의 **한도 소모 속도를 실측 A/B 가능**.
- 확인 필요: warm cache_read가 한도에 0.1x로 카운트되는지 풀로인지(비공개). cache_create는 명백히 풀 중량.

## 11. 타깃 선정 기준 (손익분기)

| 조건 | 약타깃 (소형 위키/용어 enrich) | 강타깃 (코딩 swarm / 긴 전사) |
|---|---|---|
| 입력 덩치 | ❌ 요약 ~수백 tok | ✅ 코딩 tool출력/긴 전사(수천~수만) |
| 여러 턴 재실림(곱셈) | ❌ 항목당 1회 독립 | ✅ 긴 미션/세션 누적 |
| 압축 여지 | ❌ 시스템프롬프트 이미 캐싱 | ✅ tool출력 캐시밖 벌키 |
| resume cold prefill | ❌ | ✅ 재개마다 풀 prefill |

→ **소형 enrich 약함, 코딩 swarm/긴 전사 강함.**

## 12. 미해결/확인 액션

1. ✅ **캐시 생존 증명 완료** — bust 0 + 1h 캐시 (위 §8).
2. **swarm 세션 모델** — 멀티 에이전트 크루가 작업 단위 간 컨텍스트를 이어가나(=재prefill 폭식) vs fresh-per-task. (다음 확인)
3. **rate-limit A/B** — `/api/oauth/usage`로 압축 효과 실측. (PoC 2단계)
