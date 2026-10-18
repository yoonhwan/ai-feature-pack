# FACTS — 메인 오케 리스트 · 하위 트리 실측 (ft-harness-arch#0 요청 · ft-harness-nano#1 실행)

> 측정 시각 **2026-10-05 14:27 KST** · 읽기 전용 · Slack 0 · `gh` write 0.
> 원본 = `design/teams/harness/issue-improvement/facts-raw/T1-sessions.tsv` · `T1-roles.tsv` · `T2-seats-meta.txt` · `T2-other-seats.txt` · `T2-v65-masters.txt` · `T-measured.txt`.
> 표기 **[사실]** = 명령 출력 그대로 · **[추측]** = 해석. REQ = mbox #56947 · 커밋 0b9f624b18.

---

## T1. 오케 후보 전수 — 한 행 = 세션 1

**명령** `tmux list-panes -a -F '#{session_name}\t#{pane_pid}\t#{pane_current_command}\t#{session_created}\t#{pane_current_path}'` + `pgrep -P <pane_pid> -l` (전 세션 · **총 31**).

**[사실]** 에이전트 = claude 27 · codex(node) 2 · opencode 1 · shell 1. 워크트리 = `pane_current_path` 실측.

| 세션명 | 생성(KST) | 에이전트 | 워크트리 | 역할 추정 근거(접두) |
|---|---|---|---|---|
| FB_CCU#12 | 10-04 16:26 | claude(2.1.289) | BYZ-Agents / ccu-stress | CCU (접두 FB_CCU) |
| FB_CFO#52 | 10-03 22:18 | claude(2.1.288) | BYZ-Agents / c-level-planning | CFO |
| KakaoBot#14 | 10-02 15:39 | claude(2.1.287) | KakaoBot / bootstrap | kakao |
| KakaoBot#17 | 10-04 13:20 | claude(2.1.289) | KakaoBot / bootstrap | kakao |
| byz-planner-arch#1 | 10-04 12:19 | claude(2.1.289) | BYZ-Agents / v6-realtime-live | planner-arch |
| byz-planner-arch#3 | 10-04 16:48 | claude(2.1.289) | BYZ-Agents / v6-realtime-live | planner-arch (**HIL 라우트**) |
| ft-airag-helm-claude#4 | 10-03 13:44 | claude(2.1.288) | ai-feature-pack / rag-transplant | helm |
| ft-airag-helm-claude#5 | 10-04 12:21 | claude(2.1.289) | ai-feature-pack / rag-transplant | helm |
| ft-airag-master-claude#2 | 10-04 12:23 | claude(2.1.289) | ai-feature-pack / rag-transplant | **master** (airag) |
| ft-harness-arch#0 | 10-04 20:45 | claude(2.1.289) | BYZ-Agents / harness-ops | arch |
| ft-harness-da#1 | 10-05 12:10 | **codex(node)** | BYZ-Agents / harness-ops | da |
| ft-harness-nano#1 | 10-05 12:10 | **opencode** | BYZ-Agents / harness-ops | nano |
| ft-harness-ops#0 | 10-04 13:23 | claude(2.1.289) | BYZ-Agents / harness-ops | ops(master 축) |
| ft-harness-ops#1 | 10-04 17:09 | claude(2.1.289) | BYZ-Agents / harness-ops | ops(master 축) |
| ft-harness-ops#2 | 10-05 12:28 | claude(2.1.289) | BYZ-Agents / harness-ops | ops(master 축·현 `_master`) |
| ft-issue-manager#0 | 10-04 13:26 | claude(2.1.289) | BYZ-Agents / issue-manager | **issue-manager master** |
| ft-kakao-architect#27 | 10-04 14:02 | claude(2.1.289) | KakaoBot / bootstrap | arch |
| ft-kakao-architect#28 | 10-04 19:56 | claude(2.1.289) | KakaoBot / bootstrap | arch |
| ft-kakao-da#21 | 10-05 12:05 | **codex(node)** | KakaoBot / bootstrap | da |
| ft-kakao-nano-canary-inject#0 | 10-05 12:14 | claude(2.1.289) | KakaoBot / v65-canary-inject | nano |
| ft-kakao-nano-ops-005-notice-wire#0 | 10-04 14:30 | claude(2.1.289) | KakaoBot / v65-ops-005-notice-wire | nano |
| ft-kakao-nano-send-preview#0 | 10-04 17:28 | claude(2.1.289) | KakaoBot / v65-send-preview | nano |
| ft-kakao-nano-send-preview#1 | 10-04 19:15 | claude(2.1.289) | KakaoBot / bootstrap | nano |
| ft-v65-arch-claude#155 | 10-04 16:50 | claude(2.1.289) | BYZ-Agents / v65-732-redis-audio-ref | arch |
| ft-v65-master-claude#135 | 10-04 09:17 | claude(2.1.289) | BYZ-Agents / v6-realtime-live | **master** (v65) |
| ft-v65-master-claude#136 | 10-04 16:47 | claude(2.1.289) | BYZ-Agents / v6-realtime-live | **master** (v65) |
| ft-v65-temp-m7-p90-lang-update-gap-decomposition#0 | 10-04 18:06 | claude(2.1.289) | BYZ-Agents / v65-m7-p90-lang-update-gap-decomposition | nano(temp) |
| ft-v65-temp-m7-p90f-n06-n10-durable-four-of-five-rea#0 | 10-04 18:06 | claude(2.1.289) | BYZ-Agents / v65-m7-p90f-n06-n10-durable-four-of-five-rea | nano(temp) |
| ft-v65-tester-claude#13 | 10-04 17:19 | claude(2.1.289) | BYZ-Agents / v6-realtime-live | tester |
| repro-e2e#0 | 10-04 13:26 | claude(2.1.289) | BYZ-Agents / repro-main | tester(repro) |
| tmm | 10-04 13:01 | shell/none | /Users/yoonhwan | tmm(터미널) |

**[사실]** 세션은 **4개 프로젝트 루트**에 흩어져 있다: BYZ-Agents(19) · KakaoBot(9) · ai-feature-pack(3) · 홈(tmm 1).
**[추측]** 메인 오케 후보 = `ft-v65-master-claude#135/#136`(v65) · `ft-airag-master-claude#2`(airag) · `ft-issue-manager#0` · `ft-harness-ops#2` · `byz-planner-arch#3`(최상위) — 나머지는 위성/좌석.

---

## T2. 명부가 말하는 «오케»

**명령** `python3 (seats-*.json 의 _name/_version/_master/_hil_route)` · `find … -name seats*.json -path '*/.fable-team/*'`.

| file | _name | _version | _master | _hil_route | _master 세션 T1 생존 |
|---|---|---|---|---|---|
| seats.json (v65) | Seatbelt | 1.2.0 | **(없음)** | **(없음)** | — (아래 role:master 행) |
| seats-harness.json | Seatbelt-HARNESS | 1.0.0 | **ft-harness-ops#2** | byz-planner-arch#3 | **Y** |
| seats-issues.json | Seatbelt-ISSUES | 1.0.0 | **ft-issue-manager#0** | byz-planner-arch#3 | **Y** |
| seats-planner.json | Seatbelt-PLANNER | 1.0.0 | **byz-planner-arch#3** | 오빠 직접(최상위) — planner pane AskUserQuestion | **Y** |
| seats-kk.json | Seatbelt-KK | 1.0.0 | **(없음)** | **(없음)** | — |
| seats-cfo.json | Seatbelt-CFO | 1.0.0 | **(없음)** | **(없음)** | — |

**[사실] seats.json(v65)은 `_master` 필드가 없다** → `role:"master"` 이고 `_replaced_by` 없는 행 중 T1 에 있는 것: **`ft-v65-master-claude#136` (Y, role=master)**. **#135 는 role 필드가 빈 값(None)** 이지만 T1 에 master 세션으로 살아 있음 → **[추측]** 명부에 role 누락된 살아있는 오케.
**[사실] 다른 프로젝트 seats 파일**:
- **KakaoBot** = `KakaoBot/kakao-agent-bot-planning/.fable-team/seats.json` (리포 루트가 아니라 **중첩 서브디렉터리**) + 워크트리마다 `.worktrees/*/kakao-agent-bot-planning/.fable-team/seats.json` 사본 80여 개.
- **airag** = `ai-feature-pack/.worktrees/rag-transplant/.fable-team/seats.json`.
- **ccu** = **미발견**(`FB_CCU#12` 는 BYZ-Agents/.worktrees/ccu-stress 에서 도는데 seats 파일이 어디에도 없음) → 「6파일 밖 · 미발견」.
**[추측]** kakao 명부는 리포 루트 규약(`<root>/.fable-team/seats.json`)을 벗어나 중첩 경로에 있어, `_seats_json()`(루트 규약) 탐색으로는 안 잡힌다.

---

## T3. mbox 실측 (명령 5 + 도어벨 + 도달)

정본 = `.claude/fable-team/bin/mbox.sh` (226줄, `comm/mbox.sh` 심링크) · `mbox.py` (585줄).

| # | 항목 | 파일:줄 | 1줄 인용 |
|---|---|---|---|
| ① | usage | `mbox.sh:5` / `:225` | `Usage: mbox.sh {send <to> <from> <body...> [--urgent] \| recv <me> \| peek <me> \| ring <sess> [seq]}` |
| ② | send가 쓰는 파일 | `mbox.py:199` `:202` `:79` `:131` `:217` | 큐 `mailbox.jsonl` · 전문 `bodies/<seq>.txt` · 사본로그 `mailbox.log.jsonl` · seq `.mbox-seq` · 락 `mailbox.lock`(fcntl.flock `:313`) |
| ③ | 700자 초과 | `mbox.py:58` `:237` `:242` | `MAX_BODY=700` → `_clip`: `body[:MAX_BODY], "전문: %s (%d자)"` (전문은 `_stash_body` 로 `bodies/<seq>.txt` 에 **큐잉 전** 저장) |
| ④ | 도어벨 send-keys 한 줄 | `mbox.sh:105-112` | `msg="[발주 #$dbseq] bash $SELF recv $to — 실행하고 그 안의 지시를 즉시 착수하라"` → `tmux send-keys -t "$pane" -l "$msg"` (sleep 0.3) `Enter` |
| ④b | `--no-notify`/`--urgent` | `mbox.sh:175-181` | `--no-notify` = **무시+경고** · `--urgent` = `notify=1`(항상 울림) · 알림 여부는 `notify_policy`(seats.json `tick` 있으면 quiet) |
| ⑤ | recv consume / `--all` | `mbox.py:523` `:514` `:572` `:580` | `_consume` = `keep=[r for r … if seq not in seqs]` (**consume-on-read**) · LIFO `:530` · 기본 표시 5건(`RECV_LIMIT:65`), `--all` 이면 `limit=None` |
| ⑥ | ring | `mbox.sh:216-224` | 큐를 **건드리지 않고** doorbell만 `force=1`로 울림 — `db="$(doorbell_status "$sess" 1 "${2:-}")"` |
| ⑦ | relay 파일 경로 | `mbox.py:66` `:481-505` | `RELAY_DIR=/tmp/mbox` · `dest="%Y%m%dT%H%M%S-{from}-to-{to}-{name}"` 로 **복사**(원본 변경 무관) · 요약 비면 `EMPTY_SUMMARY` |
| ⑧ | ft-reach-check jsonl | `ft-reach-check.sh:63-70` `:80` | `printf '%s/.claude/projects/%s' "$HOME" "$enc"` (cwd 비영숫자→`-`) · `grep -lE "\"(agentName\|customTitle)\":\"<session>\"" "$dir"/*.jsonl` |

**[사실]** 도달 판정은 **pane capture 가 아니라 세션 jsonl 층**(`type=="user"` 레코드, `ft-reach-check.sh:9·22`)에서 한다.
**[추측]** ④의 도어벨 문자열은 «명령»이 아니라 «지시문» — `mbox.sh:86-92` 주석이 그 이유(도구 출력은 지시로 안 읽힘)를 적어 둔다.

---

## 회신 요약

- **못 한 항목**: **ccu 명부 파일 미발견**(6파일 밖 · find 전수에도 없음) — 그 외 T1~T3 전부 실행.
- **사실/추측**: [사실] 약 15항 / [추측] 4항 → **사실 ≈ 79% · 추측 ≈ 21%**.
- **두드러진 3**: ① 실재 31 세션 = **4개 프로젝트 루트**에 분산 · v65/airag/issues/harness/planner **5개 master** ② **kakao 명부는 중첩 경로**(루트 규약 밖) · **ccu 명부 없음** ③ v65 seats.json 은 **`_master` 필드 부재**(#135 role 빈 값).