# DESIGN — R75 zombie-clean keep-last-2 순번을 가드 앞에서 센다 (2026-10-10 · arch#26 · r1 = 사전 DA HOLD 1 반영)

★골 원문(복붙 3줄)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 어느 축: 개선요청 접수·협의(오빠 판정 807 직접 요청) + 업그레이드(전역 스킬 `~/.claude/skills/zombie-clean` 수정·설치).
근거 요청: 요청 원장 R75 · master#25 발주 seq 71274 · 오빠 「구 세션들은 리니지2(keep-last-2) 좀비 클린 프로세스가 닫는다 · 따르라」.

## 1. 결함 (코드 실측)

`~/.claude/skills/zombie-clean/scripts/zombie-clean.sh` `tmux_prune()` 의 멤버 루프(현행 431~466행)는 다음 순서로 돈다.

| 순서 | 행 | 동작 |
|---|---|---|
| 1 | 439–442 | `@zc_v65_active=1` ∧ idle < ABANDON → `continue` (preserve) |
| 2 | 446 | attached → `continue` |
| 3 | 447 | `idx=$((idx+1))` |
| 4 | 451–453 | `idx ≤ keep` → 보존 |

1·2 가 3 보다 앞이라 attached·preserve 좌석은 keep 슬롯을 쓰지 않는다. 그래서 실제로 남는 것은 «비-attached·비-preserve 중 최신 2개 + attached·preserve 전부»다. 정책 «lineage 당 최신 2개»보다 더 많이 남는다.

## 2. 변경 r0 (한 줄 이동) — ★r1 에서 §2-r1 의 B1·B2 가 더해진다 · 최종 변경 = §2 + §2-r1★

```diff
             idle=...                          # (기존: window_activity 반영까지 그대로)
+            idx=$((idx+1))   # 순번은 가드 앞에서 센다 — attached·preserve 도 «최신 순번»을 차지한다 (R75 · 판정 807)
             if [[ ... @zc_v65_active ... ]] && [[ "$idle" -lt ABANDON ]]; then
                 echo "  tmux preserve ..."; continue
             fi
             [[ "${att:-0}" -gt 0 ]] && continue
-            idx=$((idx+1))
             if [[ "$idx" -le "$keep" ]]; then
```

kill 을 막는 가드는 하나도 빼지 않는다. 바뀌는 것은 순번(idx) 계산 위치뿐이다.

| 가드 | 변경 후 |
|---|---|
| 유일 세대(`total ≤ keep`) | 그대로 · total 은 원래부터 attached 포함 |
| active V65 task preserve | 그대로 kill 0 · 다만 순번 1칸을 차지한다 |
| attached | 그대로 kill 0 · 다만 순번 1칸을 차지한다 |
| idle < idlemin | 그대로 |
| 라이브 서버 pane | 그대로 |
| RED + ABANDON 회수 | ★r1 에서 «최신 keep 세대 안» 회수는 없앤다 (§2-r1 B1)★ · keep 밖은 그대로 |
| kill-server · 브랜치 삭제 | 0 (원래 없음) |

사전 DA r1 = APPROVE (da-codex#1 · #71393 · 895ab137c1 기준 · 비차단 정정 = 시험 수 11건 · r0 설명 정합).

## 2-r1. 사전 DA HOLD 1 반영 (da-codex#1 · seq 71368)

**B1 보존 하한 — keep-last-2 는 어떤 티어·설정에서도 2 밑으로 내려가지 않는다.** 세 군데를 고친다.

```diff
     local keep="${ZC_TMUX_KEEP:-2}" idlemin=...
+    if ! [[ "$keep" =~ ^[0-9]+$ ]] || (( keep < 2 )); then echo "  keep 하한 2 적용 (요청 ZC_TMUX_KEEP=$keep)"; keep=2; fi
 ...
-        [[ "$total" -le "$keep" && "${ZC_TIER:-}" != "RED" ]] && continue
+        [[ "$total" -le "$keep" ]] && continue
 ...
-            if [[ "$idx" -le "$keep" ]]; then
-                [[ "${ZC_TIER:-}" == "RED" && "$idle" -ge "${ZC_TMUX_ABANDON_MIN:-360}" ]] || continue
-            fi
+            [[ "$idx" -le "$keep" ]] && continue          # 최신 keep 세대는 어떤 티어에서도 보존
```

- 하한을 올릴 때는 그 사실을 출력한다(소리 없이 바꾸지 않음 · #0 RULE).
- RED 의 회수력은 «keep 밖 세대 + RED idle 임계(10분)» 경로로만 남는다. 3번째 이후 세대는 RED 에서 더 빨리 정리된다.
- preserve 가드의 ABANDON(6시간 넘게 방치된 active 태그는 보호 해제)은 티어와 무관해서 그대로 둔다. 순번이 keep 안이면 B1 이 지키고, keep 밖이면 일반 정리 대상이다.

**B2 정렬 키 — 입력 시각(`session_activity`)이 아니라 세대 번호(`#N`)로 줄 세운다.**

```diff
-awk ... '{n=$1; sub(/#[0-9]+$/,"",n); if(n==b) print $2"|"$1"|"$3}' | sort -t'|' -k1 -rn)
+awk ... '{n=$1; sub(/#[0-9]+$/,"",n); g=0; if(match($1,/#[0-9]+$/)) g=substr($1,RSTART+1); if(n==b) print g"|"$2"|"$1"|"$3}' | sort -t'|' -k1,1rn -k2,2rn)
-        while IFS='|' read -r activity name att; do
+        while IFS='|' read -r gen activity name att; do
```

- 1순위는 `#N` 내림차순, 같은 번호(또는 번호 없음 = 0)끼리는 입력 시각 내림차순이다.
- 이유: 승계 계보에서 «최신»은 번호가 큰 쪽이다. 옛 세대에 질문을 보내면 입력 시각이 더 최근이 돼 최신 세대가 정리될 수 있었다(DA B2 실례: #3=100 · #2=200 · #1=300).

DA 판단 그대로 둔 것: §7-1 attached 가 순번을 차지하는 것은 허용 · §7-2 출력만 내는 좌석은 idle 가드가 막는다.

★문서 불일치 (master 에 전달)★: 전역 `~/.claude/CLAUDE.md` 「zombie-clean 자동 정리는 keep-last-1 (2026-09-11)」 문단과 `SKILL.md` 74행(기본 1)은 코드 주석(09-15 오빠 지시로 2 복귀)·plist(2)와 다르다. r1 은 하한을 코드로 2 에 고정한다. 문서 문구 정정은 전역 규칙 파일이라 master → planner 경로로 올린다.

스크래치 사본 `zc-r1.sh`: `bash -n` OK · `ZC_TMUX_KEEP=1` 로 실행하면 「keep 하한 2 적용 (요청 ZC_TMUX_KEEP=1)」을 출력한다.

## 3. 영향 — 지금 정리될 후보 (dry-run 실측 2026-10-10 · YELLOW · idle≥30분 · keep=2)

패치본은 스크래치 사본 `zc-patched.sh` 로 `tmux-prune --dry-run` 실행 (실 kill 0).

| 좌석 | 현행 | 패치 | 이유 |
|---|---|---|---|
| `byz-planner-master-claude#16` | 보존 | **정리** | #20·#19 가 attached 로 순번 1·2 를 차지 → #16 은 3번째 · idle 552분 |
| `byz-v65-tester-claude#30` | 보존 | **정리** | #32 가 preserve 로 순번 1 · #31 이 2 → #30 은 3번째 · idle 588분 |
| `byz-v65-arch-claude#194` | 정리 | 정리 | 원래부터 3번째(#196·#195 다음) |
| `byz-v65-tester-claude#32` | preserve | preserve | active V65 task 태그 |

신규 정리 대상은 2개다(r0 작성 시점). ★r1 시점 재실측(RED · keep=2): 현행·r0·r1 모두 0개★ — planner#16·v65-arch#194·v65-tester#30·#31 은 그 사이 이미 닫혔다(08:56 auto 1건 포함). 지금 lineage 에서 r1 정렬이 바꾸는 kill 은 없다. 오빠가 꼽은 loom#10·issues#9·v65 master#158·harness#24 는 «lineage 에서 두 번째 최신»이라 패치 뒤에도 보존된다. master 실측과 같다.

## 4. 되돌림

- 설치 전에 백업한다: `cp zombie-clean.sh zombie-clean.sh.pre-r75-order-20261010.bak`.
- 되돌릴 때: 백업을 `cp` 로 되돌린다. launchd 는 매 실행마다 스크립트를 새로 읽으므로 kickstart 는 필요 없다.
- 이미 정리된 좌석은 `zombie-clean.sh restore '<NAME>'` 로 복원한다(대장 `$ZC_RECLAIM` · kill 전 cwd·argv 기록 · 기존 경로).

## 5. 시험 (가짜 tmux fixture · 실 tmux 0)

`PATH` 앞에 스텁 `tmux` 를 둔다. 스텁은 fixture 표로 `list-sessions`·`show-options`·`list-windows`·`list-panes` 에 답하고, `kill-session` 은 파일에 기록만 한다. `pressure_tier` 는 `ZC_TIER=YELLOW ZC_TMUX_IDLE_MIN=30` 으로 고정한다.

| # | fixture (최신→오래된) | 기대 kill |
|---|---|---|
| T1 | A#3 att · A#2 att · A#1 idle 500 | A#1 (현행은 0) |
| T2 | B#3 preserve · B#2 idle 500 · B#1 idle 500 | B#1 만 |
| T3 | C#2 · C#1 (멤버 2 = keep) | 0 (유일 세대 보호) |
| T4 | D#3 att · D#2 att · D#1 idle 10 | 0 (idle 가드) |
| T5 | E#4 · E#3 · E#2 att · E#1 idle 500 | E#1 만 (현행·패치 같음 — attached 가 3번째면 원래도 E#1 이 3번째) |
| T6 | F#3 · F#2 · F#1 pane 에 uvicorn | 0 (라이브 서버 가드) |
| T7 | RED · G#2 · G#1 idle 400 (keep 안 · ABANDON 360) | ★0★ (r1 B1: 최신 2세대는 RED 에서도 보존 · 현행은 G#2·G#1 둘 다 kill — RED→GREEN) |
| T7b | RED · H#3 · H#2 · H#1 idle 400 | H#1 만 (keep 밖은 RED 회수 그대로) |
| T8 | I#3 활동 100 · I#2 활동 200 · I#1 활동 300 (전부 idle ≥ 500) | I#1 만 (r1 B2 세대 정렬 · 현행은 I#3 kill — RED→GREEN) |
| T9 | `ZC_TMUX_KEEP=1` · J#3 · J#2 · J#1 idle 500 | J#1 만 + 출력에 「keep 하한 2 적용」 (현행은 J#2·J#1 kill) |
| T10 | RED · K#2 · K#1 (멤버 2 · idle 500) | 0 (유일 세대 보호가 RED 에서도) |

T1·T2·T7·T8·T9·T10 은 현행 코드에서 FAIL, 패치에서 PASS 해야 한다(RED→GREEN). T3~T6·T7b 는 양쪽 다 PASS 해야 한다(회귀 0). 시험 파일 위치는 `~/.claude/skills/zombie-clean/tests/test_tmux_prune_order.sh` 다. 전역 스킬에는 tests/ 가 아직 없으니 새로 만든다.

## 6. 설치 절차 (전역 도구)

1. 나노가 리포 추적 사본에 패치 + 시험을 올린다. 추적 사본 경로는 나노 착수 때 `ft-harness-info.sh find zombie-clean` 으로 확인한다. 추적 사본이 없으면 스킬 디렉터리 시험만 돌린다.
2. 시험 11건(T1~T10 + T7b) PASS 와 `bash -n` 통과를 확인한다.
3. master 가 `.bak` 백업 → `cp` → `cmp` 로 설치하고, 바로 이어 `tmux-prune --dry-run` 을 1회 돌린다. §3 의 r1 재실측과 같은 목록이 나와야 한다(지금 실측 = 0개).
4. 다음 launchd auto 실행 로그(`~/.claude/logs/zombie-clean*.log` 의 `tmux 정책 정리:` 줄)를 보고 닫는다.

## 7. 사전 DA 에게 묻는 것 (반박 대상)

1. attached 좌석이 순번을 먹으면 «사람이 두 화면을 보고 있는 lineage» 에서 비-attached 직전 세대(물어볼 일이 잦은 구세션)가 정리된다. 판정 807 「keep-last-2 를 따르라」와 맞는가, 아니면 attached 를 «+α» 로 둬야 하는가.
2. 정렬 키가 `session_activity`(입력만 셈)다. idle 판정은 `window_activity`(출력) 까지 보는데, 정렬은 입력만 본다. 출력만 내는 작업 좌석이 «오래된 순번»으로 밀려 정리될 수 있는가(idle 가드가 막는지).

## 8. 범위 밖 관찰 (착수 0 · 기록만)

- launchd plist `com.yoonhwan.zombie-clean` 은 `ZC_TMUX_KEEP=2` 다. 전역 CLAUDE.md 는 「zombie-clean 자동 정리는 keep-last-1 (2026-09-11)」이라 적고, `SKILL.md` 74행 표도 기본 `1` 이다. 코드 주석(406행)은 09-15 에 2 로 복귀했다고 적는다. 문서 2곳이 stale 이다.
- 정렬 키 문제(§7-2)는 이번 변경과 별개로 남는다.
