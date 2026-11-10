# FACTS — v65 「시험 묶음」 실제 방식 실측 (ft-harness-arch#2 요청 · ft-harness-nano#1 실행 · P7 r6 정정)

> 측정 시각 **2026-10-05 16:53 KST** · 읽기 전용 · 수정·커밋 0.
> E1~E3(`FACTS-team-essentials-20261005.md`)은 재측정 안 함. 산출 위치 = `design/teams/harness/issue-improvement/`. 원본 = `design/teams/harness/issue-improvement/facts-raw/G*.txt`.
> 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #57039 · 발주 = ops#2 ORDER-essentials-bundle(#57036). 오빠 원문: 「tester+checker(bts,poller) 하나의 구성으로 v65 에서 단순화하고 빠르게 수집 보고 아키텍트에게 올린 이게 유효함」.

---

## G1. 묶음의 구성원 — v65 에서 tester 와 checker 는 한 좌석이었나

**[사실] `seats.json` `role=tester` = 12행** — 전부 `ft-v65-tester-claude#N`(N=1..6, 8..13 · **#7 결번**), `agent=claude`, `model=claude-sonnet-5-5[1m]`, **`created`/`closed` 필드 없음**.

| 항목 | 값 | 사실/추측 |
|---|---|---|
| 이름에 `checker` 든 키 | `ft-v65-tester-checker-ds#19` · `ft-v65-tester-checker-ds#20` — **이름 자체가 `tester-checker`** | [사실] |
| `#19` | `role=stop-ready` · `agent=claude` · `model=deepseek-v4.1-flash` · `_replaced_by=…ds#20` · `_session=killed` | [사실] |
| `#20` | `role=stop-ready` · `agent=opencode` · `model=openrouter/deepseek/deepseek-v4.1-flash` | [사실] |
| to=`ft-v65-tester*` 발주 22행 중 키워드 | 「4축」 **2** · 「poller」 **1** · 「checker」 **0** · 「BTS」 **0** · 「4자」 **0** | [사실] |

**[추측]** **한 좌석이 tester+checker 를 겸했다** — 좌석명이 `ft-v65-tester-checker-ds#N`(ds=deepseek)이고 role 은 나중에 `stop-ready` 로 덮였다. 단 **일반 tester 좌석 12행(`ft-v65-tester-claude#N`)은 이름에 checker 가 없다** → 겸임은 **별도 이름(`tester-checker-ds`)의 특수 좌석**에서 일어났고, 최근 표준 tester 좌석은 이름상 겸임 흔적이 없다.

---

## G2. 누가 press 를 돌리고 누가 4축을 모았나

**[사실] 최근 v65 press 산출 2건** (`.worktrees/v6-realtime-live/design/v65/20261003/`):

| 폴더 | 파일 목록 | runner/시작 |
|---|---|---|
| `evid-tester9-press-seq-001/` | `checkpoint.json` · `checkpoint.md` · `offsets-seq.txt` · `runner-seq.log`(157 KB) | runner = **tcc8**(`[tcc8]` 로그) · 시작 `07:04:34` |
| `evid-tester10-k4-002/` | `checkpoint.json/md` · `dec.json/py` · `dup.py` · `final_dom.png` · `poller_capture_end.json` · `pre.txt` · `runner-k4-002-attempt7.log` · `worker_log_span.txt` · `worker_log_span_late.txt` | runner = k4-002 attempt7 |

**[사실] `runner-seq.log` 머리 10줄**: `[tcc8] 07:04:34 ★E-4 채록★ {services:{fe/gateway/worker pid·started_utc}}` · `[tcc8] 07:04:34 opening fresh tab …` · `★poller_dom★ 기동 pid=65850 -> …/scratchpad/tcc8-completion-press/…/poller_dom.jsonl` · `★FE-CONSOLE★ Runtime.consoleAPICalled …` · `pump start (poller live capture) budget=220.0s`.
**[사실] 4축 파일 대응**(이 회차들 기준): ① FE 콘솔 = `runner-seq.log`(`★FE-CONSOLE★`) ② poller/DOM = `poller_capture_end.json` + `final_dom.png`(poller_dom.jsonl 은 scratchpad) ③ worker 로그 = `worker_log_span.txt` ④ 저장소(Redis) = **전용 파일 없음**(로그 안 durable 라인). → **넷 중 ④ 는 별 파일 없음**.
**[사실] checker 좌석 따로 썼나**: 두 폴더 발신 좌석 = `tester`(`evid-tester9`/`evid-tester10`) → **tester 단독**(별도 checker 발신 파일·mbox 행 0).

---

## G3. 어떤 형식으로 architect 에 올렸나

| 항목 | 값 | 사실/추측 |
|---|---|---|
| `from=ft-v65-tester*` → arch | **19행** — 전부 **옛 것**(최대 seq **14851** · `to=ft-v65-arch-fable#45` 계열, 09-xx) | [사실] |
| `from=ft-v65-tester*` → master | **11행** — **최근분이 여기**(seq 56751·56814·56871·56899 · 10-04) | [사실] |
| 최근 3건(tester→master) | 56751 `[n01 완료·#732 첫 회차] m7p90f-n01 exit0·VALID(…)` · 56814 `[70 완료] 유효 12/14…` · 56899 `[크론 0 · Monitor 0]…` | [사실] |
| 4자 대조표 정본 | `READ-tester11-s5-3bubble-press.md:18-24` 「## 3. **4자 표 (시간 열 + 분모)**」 — 열 = `축 \| 사실 \| 시간`, 행 = `아키텍처 문서 \| 코드 \| 로그(worker) \| 화면(poller)` | [사실] |

**[추측]** **최근 tester 보고는 arch 가 아니라 master 로 간다**(arch 행은 전부 옛 seq) — 「architect 에게 올린다」는 오빠 원문과 현재 라우팅이 다르다(현행 = tester→master→(master 가 relay)).

---

## G4. 묶음을 누가 언제 열고 닫았나(배분 사건)

| 항목 | 원문(파일:줄 / seq) | 사실/추측 |
|---|---|---|
| 열린 계기 | seq **56728** (2026-10-04 17:20:34) `ft-v65-master-claude#136 → ft-v65-tester-claude#13` 「**[Seatbelt 역할 교체] 너는 tester 후계 좌석(ft-v65-tester-claude#13)**」 · 직후 seq 56727 tester 부팅 3항(17:20:20) | [사실] |
| 좌석 생성 시각 기록 | `seats.json` 12행에 **`created` 필드 0** → 명부상 생성 시각 없음(세션 `session_created` 로만) | [사실] |
| 닫힌 계기 | seq **56818** (2026-10-04 18:02:06) `ft-v65-master-claude#136 → ft-issue-manager#0` 「**press 창 종료(tester#13 70 완료, 유효 12/14)**」 | [사실] |
| 「tester 닫음/kill」 문구 | **없음** — 닫는 사건 기록 0(「press 창 종료」만) | [사실] |
| 살아있는 `ft-v65-tester-claude#13` 마지막 발주 | seq **56899** (2026-10-04 18:36:25) `[크론 0 · Monitor 0] … 이후 발신 0` → **유휴 ≈ 22시간**(측정 16:53 기준) | [사실] |

**[추측]** tester 좌석은 **master 의 「Seatbelt 역할 교체」** 로 열리고(별도 「tester 열어」 발주 0), 닫기는 **press 창 종료 통보**로만 이뤄져 **명시적 close/kill 기록이 없다**.

---

## 회신 요약

- **못 한 항목**: 없음 — G1~G4 전부 실행. (단 「tester 열어」 문구의 mbox 행은 **0** 이라 열린 계기는 「Seatbelt 역할 교체」 행으로 대체.)
- **사실/추측**: [사실] 약 20항 / [추측] 4항 → **사실 ≈ 83% · 추측 ≈ 17%**.
- **두드러진 3**: ① **겸임은 `ft-v65-tester-checker-ds#N`(이름이 tester-checker · deepseek-flash) 특수 좌석에서** — 일반 `ft-v65-tester-claude#N` 12행은 겸임 흔적 0 ② 최근 tester 보고는 **arch 가 아니라 master** 로 감(tester→arch 19행 전부 옛 seq) ③ 4축 표 = `축|사실|시간`(아키텍처문서·코드·worker로그·화면poller) — **Redis 축은 별 파일 없음**, checker 는 **tester 단독**(별 발신 0).