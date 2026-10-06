# FACTS — tmux 세션명 현황 · tmuxc/tmm 이름 처리 · 이름에 기대는 스크립트 실측 (ft-harness-arch#1 요청 · ft-harness-nano#1 실행 · 조각 P6)

> 측정 시각 **2026-10-05 15:45 KST** · 읽기 전용 · 이름 변경·kill 0 · Slack 0.
> 산출 위치 = `design/harness/issue-improvement/`. 원본 = `design/harness/issue-improvement/facts-raw/N*.txt`.
> 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #57005 · ORDER = ORDER-session-naming(#57004).

---

## N1. tmux 세션 전수 — 이름 패턴 분류

**명령** `tmux list-sessions -F '#{session_name}\t#{session_created}\t#{session_attached}'` → **총 32 세션**.

| 패턴 | 건수 | 예 |
|---|---|---|
| `ft-<팀>-<역할>#N` | **15** | `ft-harness-arch#0` · `ft-harness-da#1` · `ft-harness-ops#2` · `ft-issue-manager#0` |
| `ft-<팀>-nano-<slug>#N` | **4** | `ft-kakao-nano-canary-inject#0` · `ft-kakao-nano-send-preview#1` |
| `ft-airag-<역할>#N` | **3** | `ft-airag-master-claude#2` · `ft-airag-helm-claude#4/#5` |
| `FB_<팀>#N` | **2** | `FB_CCU#12` · `FB_CFO#52` |
| `KakaoBot#N` | **2** | `KakaoBot#14` · `KakaoBot#17` |
| `byz-<팀>-<역할>#N` | **2** | `byz-planner-arch#1` · `byz-planner-arch#3` |
| `ft-<팀>-temp-<slug>#N` | **2** | `ft-v65-temp-m7-p90-lang-update-gap-decomposition#0` |
| `repro-*` | **1** | `repro-e2e#0` |
| `tmm` | **1** | `tmm` |

**[사실] 같은 팀인데 두 문법**: **v65** = `ft-v65-{master,arch,tester}-claude#N` + `ft-v65-temp-*#N` · **cfo** = `FB_CFO#52`(역할 없음 · `CFO_*` 문법은 좌석에만 있고 라이브 아님) · **kakao** = `KakaoBot#N`(접두 없음) **+** `ft-kakao-*#N`(둘 다 라이브).
**[사실] user option 태그** — `@zc_v65_active` **9** 세션(v65 5 + kakao 3 + KakaoBot 2 … v65/kakao 계보 전부) · `@tmm_picker` **1**(tmm). 그 외 `@*` 태그 없음.
**[추측]** 「팀」은 이름 접두로만 알 수 있고(`ft-<팀>-`·`FB_<팀>`·`KakaoBot`), **역할**은 `ft-<팀>-<역할>#N` 에만 박혀 있다 — cfo(`FB_CFO`)·kakao(`KakaoBot`)는 이름에 역할이 없다.

---

## N2. tmuxc 가 이름을 만드는 방식

정본 = `~/.local/bin/tmuxc` → **`~/.tmuxc/current/core/bin/tmuxc`** (0.4.0 · 1900+행).

| 항목 | 파일:줄 + 인용 | 사실/추측 |
|---|---|---|
| `--name` 처리 | `:447` `local name=""` · `:460` `--name) name="${2:-}"` | [사실] |
| 자동명 규칙 | `:481-483` `if [[ -z "$name" ]]; then name="$(basename "$root")"; fi` — **`#N` 자동 증가 없음** | [사실] |
| 이름 유효문자 | `:58-63` `sanitize_name`: `raw="${raw// /-}"; raw="${raw//:/-}"; raw="${raw//./-}"; tr -cd 'A-Za-z0-9_#-'` | [사실] |
| 중복 시 | `:526` `tmux has-session -t "$name" 2>/dev/null && die "session already exists: $name"` (증가 없이 **거부**) | [사실] |
| `#` target 충돌 | `:52-55` `tmux new-session -d -s "$name"` 뒤 `tmux set -wu -t "=$name:"` — **`=` 접두 exact-match** 로 `#` 파싱 회피 | [사실] |
| `--like` | `:505-515` claude 전용 — 지정 라이브 세션의 `model`/`effort` 상속(명시 `--model` 우선) | [사실] |

**[추측]** **`#N` 계보 이름은 tmuxc 가 만들지 않는다** — tmuxc 기본명은 `basename(root)` 뿐이고, `#N` 은 fable-team 스폰 스크립트(`ft-role-spawn.sh` · `ft-nano-spawn.sh`)가 붙인다(N4 참조).

---

## N3. tmm 이 이름을 읽는 방식

정본 = `which tmm` → **`~/.tmm/current/core/bin/tmm`** (1375행 · bash TUI).

| 항목 | 파일:줄 + 인용 | 사실/추측 |
|---|---|---|
| 카테고리 규칙 | `:46` 「TMM_CATEGORIES 카테고리 규칙 파일(기본 ~/.tmm/categories) — `glob<TAB>라벨` 한 줄씩, 위에서부터 첫 매치」 | [사실] |
| 이름→라벨 | `:184-190` `local n="${1%%#*}"` (**`#N` 떼고**) → `case "$n" in $glob) printf '%s' "${label,,}"` | [사실] |
| 기본 접두 제거 | `~/.tmm/categories:4` 「규칙에 안 걸리면 «역할 접두»(`FB_`·`ft-`)를 떼고 첫 토큰(-/_ 앞 5자)이 라벨: `FB_CCU#0→CCU` `ft-v65-master-claude#86→v65` `ft-airag-arch-astra→airag`」 | [사실] |
| 카테고리 예 | `~/.tmm/categories` = `KakaoBot→kakao` · `cfo_*→CFO` · `loom_*→LOOM` · `DATA_PG→LOOM` (4규칙) | [사실] |
| HUMAN/BLOCK 판정 | `:225-235` `last_epoch`: **pane 텍스트** `tmux capture-pane … | tr -s` → `[[ "$txt" =~ done\ +(오전\|오후)\ +([0-9]{1,2}):([0-9]{2}) ]]` (**이름 아님**) | [사실] |
| picker 판별 | `:161-162` 「세션 옵션 `@tmm_picker` 로 한다(이름은 `tmm-2 …` 로 늘어나므로 이름 비교는 못 쓴다)」 | [사실] |
| live 표시 | `:348` `case "$pcmd" in zsh\|bash\|sh\|fish…) live="○";; *) live="●";;` (pane_current_command) | [사실] |
| `tmm h` | `:347` `[ "$only" = "h" ] && ! [[ "$st" =~ ^(HUMAN\|BLOCK\|STUCK)$ ]] && continue` | [사실] |
| `tmm ls` | `:1028` `cmd_ls` = `cmd_rows time | cut -f1 | grep -i` | [사실] |

**[추측]** tmm 은 이름을 **카테고리 라벨**에만 쓰고(접두 제거 + 첫 토큰), 상태(HUMAN/BLOCK/STUCK)는 **pane 내용·jsonl freshness** 로 판정한다 — 이름과 상태가 분리돼 있다.

---

## N4. 이름에 기대는 스크립트·규칙

| # | 종류 | 파일:줄 + 인용 |
|---|---|---|
| ① | 리터럴 접두 | `ft-role-spawn.sh:35` `BASE_NAME="ft-v65-$ROLE-$AGENT"` · `ft-nano-spawn.sh:92` `BASE_NAME="${FT_NANO_PREFIX:-ft-v65-temp-}$SLUG"` · `ft-nano-close.sh:23` `NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"` |
| ① | 팀 리터럴 | `ft-context-monitor.sh:13-14` `SESSION_PREFIX="${FT_CTX_SESSION_PREFIX:-ft-v65-}"` + EXCLUDE 17개 `ft-v65-*` · `ft-goal-tick.sh:21` `TARGET="${FT_GOAL_TICK_TARGET:-ft-v65-master#39}"` · `ft-master-tick.sh:20` `TARGET_SESSION="${FT_MASTER_TICK_TARGET:-ft-v65-master#4}"` |
| ② | `#N` 계보 | `ft-role-spawn.sh:34-38` 「`ft-v65-<role>-<agent>#<N+1>` — N = tmux 세션 + seats.json 키 중 같은 베이스의 최댓값」 · `zombie-clean.sh:398` 「lineage(베이스명 `#N` 계열)당 최근 KEEP개 보존」 · `ft-role-spawn.sh:8` `_replaced_by` / `_replaces` |
| ③ | 역할 추출 | `ft-role-spawn.sh:45` `v.get("role") == sys.argv[2] and not v.get("_replaced_by")` (seats `role` 로 · **이름 문자열 파싱 아님**) · `ft-news-tick-cfo.sh:13` `grep -E '^FB_CFO#[0-9]+$'` |
| ④ | `@zc_*` 태그 | `ft-nano-spawn.sh:164` `tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1` · 팀별 `FT_ACTIVE_TAG` = `@zc_harness_active`(harness-env.sh:5) · `@zc_issues_active`(issues-env.sh:5) · `@zc_kk_active`(kk-env.sh:5) · `@zc_planner_active`(planner-env.sh:5) |
| ④ | 해제 | `ft-nano-close.sh:378` `tmux set-option -t "$PANE" -u @zc_v65_active` (하드코딩 · `FT_ACTIVE_TAG` 미사용) |
| — | mbox 이름 검증 | `.claude/fable-team/bin/mbox.sh:15-19` `_check_name`: `case "$1" in ''|*[!A-Za-z0-9._#-]*) echo BAD_SESSION_NAME; return 1;; esac` |

**[사실] 서로 어긋나는 가정**:
- **① tmuxc vs fable-team**: tmuxc 자동명 = `basename(root)`(N2) vs 스폰 스크립트 = `ft-v65-…-claude#N` — **같은 도구로 열어도 이름 규칙이 다르다**.
- **② `ft-role-spawn` 은 v65 전용**: `BASE_NAME="ft-v65-$ROLE-$AGENT"` 하드코딩 → harness/issues 는 `ft-harness-*`·`ft-issue-manager#0`(role-agent-#N 아님)이라 이 스폰으로 안 만들어졌다.
- **③ prefix 불일치**: `ft-nano-close.sh` 는 `FT_NANO_PREFIX`(기본 `ft-v65-temp-`)로만 닫고, harness 는 `FT_NANO_PREFIX=ft-harness-temp-`(harness-env.sh) — **env 없이 close 부르면 harness 나노는 REJECT**.
- **④ 태그 해제 하드코딩**: spawn 은 `FT_ACTIVE_TAG`(팀별) 를 세팅하나 close 는 `@zc_v65_active` 를 하드코딩 해제 → harness/issues 나노 태그가 안 풀린다.
- **⑤ tmm 접두 가정**: tmm 은 `FB_`·`ft-` 만 벗긴다 → `byz-planner-arch#3` 은 첫 토큰 `byz` 로 분류(팀 `planner` 아님).
- **⑥ stale 리터럴 기본값**: context-monitor/goal-tick/master-tick 의 기본 대상이 `ft-v65-master#39`·`#4`·`#10` 등 **현재 없는 좌석**.

---

## 회신 요약

- **못 한 항목**: 없음 — N1~N4 전부 실행.
- **사실/추측**: [사실] 약 22항 / [추측] 3항 → **사실 ≈ 88% · 추측 ≈ 12%**.
- **두드러진 3**: ① 세션명 문법 **9종 혼재**(팀당 2문법: v65/kakao) · 역할은 `ft-<팀>-<역할>` 에만 ② **tmuxc 는 `#N` 이름을 안 만든다**(기본명=basename) — `#N` 계보는 fable-team 스폰 스크립트 ③ 이름 의존 스크립트가 **v65 리터럴 하드코딩 + 팀별 태그 불일치**(close 가 `@zc_v65_active` 하드코딩).