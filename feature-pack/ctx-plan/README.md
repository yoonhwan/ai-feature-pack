# Feature Pack: ctx-plan

감당량 축. **계정 구성 → 정원·피크 세션·골 처리량**을 계산하고, 0순위 고정상수(구독 장수·주간 리밋)를
점검하고, 목표 규모에서 **필요 구독 장수**를 역산한다.

짝 도구는 `ctx-burn` 이다. `ctx-burn` = «쓴 양» 측정 · `ctx-plan` = «감당량» 시뮬.
둘은 **JSON 계약 하나(`ctx.v1`)로만** 붙는다. `ctx-plan` 은 세션 로그도, 실 HOME 도 읽지 않는다.

## Quick start

```bash
cd ai-feature-pack/feature-pack/ctx-plan
bash install.sh                 # ~/.local/bin/ctx-plan

cp accounts.env.example /tmp/accounts.env      # 상수 파일 자리는 하네스/사람이 정한다 · 값은 머신마다 채운다
ctx-burn --hours 168 --json > /tmp/burn.json

CTX_PLAN_CAP_FILE=/tmp/accounts.env ctx-plan --from /tmp/burn.json --inventory   # 0순위 상수 점검 + 크리티컬
ctx-plan --from /tmp/burn.json --inv-file /tmp/accounts.env --capacity --accounts 5x:5,ultra:5
ctx-plan --from /tmp/burn.json --inv-file /tmp/accounts.env --need concurrent:40
```

`ctx-sim` alias 는 **폐기**했다(오빠 #278951 — alias 는 `ctx-waste` → `ctx-burn` 하나만).

## Modes

| mode | 무엇을 내나 |
|---|---|
| (없음) | 머리 3줄 — 계약·축 정의·상수 파일 경로 + pool 한 줄 |
| `--inventory` | 0순위 상수 13키 점검 · «0순위 문제 N건» · 크리티컬 2행(낮은·높은 용량 가정) |
| `--capacity` | pool 표(pool 있는 것만) · 시뮬 4행 · 골 모형 2행 |
| `--need K:N` | `concurrent:N` · `sessions:N` · `teams:N` · `goals:N` → 필요 Ultra/5x 장수 |
| `--scales 1.0,0.9,…` | 낭비 감소 배율 목록(기본 4값 = 실측·-10%·-20%·-30%) |

## Options

| option | default | meaning |
|---|---|---|
| `--from FILE\|-` | stdin | `ctx-burn --json` 출력 |
| `--inv-file FILE` | (아래 순서) | 고정상수 파일 |
| `--accounts 5x:N,ultra:N` | 없음 | `--capacity` 정원·피크 계산용 계정 구성 |
| `--wk-5x N` / `--wk-ultra N` | 630 / 2520 | 주간 리밋 앵커(가중 M) — 파일 값이 있으면 파일이 이긴다 |
| `--c5h-5x N` | 60 | 5x 5시간창 앵커 |
| `--target-util F` | 0.85 | 주간 목표 사용률(운영정책) |
| `--seats-per-team N` | 4 | 팀 하나 = 세션 몇 석 |
| `--hours-per-week N` | 40 | 세션 하나의 주당 시간 |
| `--teams-per-goal N` | 3 | 한 골에 동시 투입되는 팀 수 |
| `--team-hours-per-goal N` | 8 | 골 하나에서 팀 하나가 붙어 있는 시간 |

## 축 정의 (출력 머리에 매번 찍는다)

```
메인 골 = 전역 직렬(동시 1) · 한 골 = 팀 3 동시 × 8시간(24 팀-시간) · 남는 팀은 후순위 골
```

`동시골` 값은 **용량상 가능 수**다. 운영 규칙 «메인 3골 직렬» 의 실제 값과 구별해서 읽어라.
`팀-시간/주` 는 중간 단위이므로 성과 판정에 쓰지 않는다.

## 상수 파일 (0순위) — 이 패키지는 자리를 정하지 않는다

**해석 순서 = 두 개뿐** (느슨한 연결 · 수용 기준 #2):

1. `--inv-file FILE`
2. `$CTX_PLAN_CAP_FILE`

상위 폴더를 뒤지거나 홈의 특정 경로를 가정하지 않는다. **자리는 하네스가 정하고 env 로 주입한다.**
파일이 없으면 `ctx-plan` 은 아무 표도 내지 않고 **rc3 + 1줄**로 끝난다(수용 기준 #6):

```
ctx-plan: 상수 파일 없음 — --inv-file 또는 CTX_PLAN_CAP_FILE (install.sh 참고)
```

출력 머리에 **읽은 경로 1줄**을 찍는다. 키 13개 — 구독 5 · 주간 리밋 4(상한·하한) · 모형 4.
값이 비면 «0순위 문제» 이고 **기본값으로 대체하지 않는다**(수용 기준 #7 — 계산이 필요한 표는 «산정 불가»).
계약 키가 아닌 두 손잡이(`FT_CAP_C5H_5X` · `FT_CAP_HOURS_PER_WEEK`)만 기본값을 쓰고, 화면에 «기본값(계약 키 아님)» 이라고 적는다.

견본: [`accounts.env.example`](accounts.env.example) (값은 비어 있다).

## 지켜지는 규칙

- **하한은 한 곳에서만** — `FT_CAP_WK_5X_LOW` · `FT_CAP_WK_ULTRA_LOW`. «상한 ÷ 3» 같은 대체 계산을 하지 않는다.
  비어 있으면 계산하지 않고 «산정 불가» 라고 쓴다(`docs/rules/no_silent_fallback.md`).
- **라벨은 «낮은 용량 가정 · 높은 용량 가정»** — «낙관·보수» 를 쓰지 않는다(작은 용량이 보수라는 보장이 없다).
- **앵커에는 상태가 붙는다** — `미검증·추정` · `추정(5x×4)·실측 필요` · `실측 주장·출처 미확인` · `운영정책`.
  상태 표기가 지워지기 전에는 이 숫자로 계정 결정을 내리지 않는다.
- **느슨한 연결** — `ctx-burn` 을 실행하지 않고(subprocess 0), 하네스 폴더 이름·홈 경로를 모른다.
  입력은 계약 JSON 하나와 상수 파일 하나뿐이다(수용 기준 #1·#3).
- **계약 검사** — `plan_input.schema != ctx.v1` 이면 계산하지 않고 **rc2** + 사유 1줄로 멈춘다(경고 후 진행 0).
- **모형 상수는 한 함수에서만 해석** — `params()` 하나가 `CLI 명시 > 상수 파일` 을 정하고, 계약 키는
  둘 다 없으면 **None(산정 불가)** 이다(기본값 대체 0 · 수용 기준 #7). 머리(header)·capacity·inventory·need
  가 같은 값을 본다(R2 · DA #278950). 출처(`CLI`/`파일`/`없음`/`기본값(계약 키 아님)`)를 머리에 찍는다.
- **골 모형은 «참고»** — 고정 기본값(팀 3 · 8h)을 운영 규칙으로 읽지 않게 «참고 — 운영 규칙 아님» 라벨을 붙인다
  (오빠 #278942). 규칙이 아니라 계산 예시다.
- **표본 0 = 미산정** — 0 으로 채우지 않는다. rc 는 0.

## 입력 계약 (ctx.v1)

`ctx-burn --json` 의 `plan_input`:

```json
{"schema": "ctx.v1", "window_hours": 168,
 "units": {"rate_claude": "weighted_tokens_per_session_hour",
           "w_per_session_hour": "weighted_tokens_per_session_hour",
           "w_total": "weighted_tokens", "ctx_per_req": "tokens"},
 "pools": {"claude": {"req": 0, "usage0": 0, "ctx_per_req": 0.0, "active_hours": 0,
                      "cache_reuse": 0.0, "cache_reuse_of_input": 0.0,
                      "w_per_session_hour": null, "samples": 0, "sessions": 0, "w_total": 0}},
 "rate_claude": null}
```

**단위 (R1 · DA #278950):** 계약의 `rate_claude` 는 **가중 토큰 / 세션-시간**이다.
계산 예산(M = 백만 가중 토큰)과 섞으면 100만 배가 어긋나므로, 이 도구는 `main()` 의
`rate_tok / TOKENS_PER_M` **한 줄에서만** 단위를 바꾼다. `--once` 없음 · `units` 필드는 계약이
스스로 단위를 말하게 하는 표식이다.

`rate_claude` = claude pool 의 **세션-시간당 W 중앙값**(가중 토큰). 표본 조건 = 요청 20건 이상 세션.
`usage0` = 가중 0 레코드(API 오류)로, 요청률 분모에서 빠진다. `unknown` pool = 모델 미상 —
다른 pool 에 밀어 넣지 않는다.

## Safety

- 읽는 것: `--from` JSON 하나 · 상수 파일 하나. 그 밖 0.
- 쓰기 0 · 네트워크 0 · 세션 로그 직접 읽기 0.
- 상수 파일은 **읽기만** 한다(`--set` 없음). 값은 사람이 채운다.

## Requirements

- python3 (3.8+), 표준 라이브러리만
- macOS · Linux
