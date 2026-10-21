# research-nano-2 — tmux / pgrep / ps / lsof 호출 전수 표

발주: [#3003] (aifp-multihost-master-claude#0 → aifp-multihost-nano-pi#1)
축: 설계 DA HOLD(H5) 해소용 **사실 수집**. 읽기 전용 · 원격 접속 0 · 설치 0 · 커밋 0.
범위: `feature-pack/tmuxc/core/bin/tmuxc`, `feature-pack/tmm/` 아래 스크립트. (`.worktrees` 미사용 · 두 폴더만)
조사 기준 트리: 워크트리 `multihost-plan` (= 현재 체크아웃 상태) · 비밀값 0.

---

## 0. 요약 — 서브명령별 건수

| 구역 | tmux | pgrep | ps | lsof | 합계 |
|---|---|---|---|---|---|
| `tmuxc/core/bin/tmuxc` | 47 | 7 | 3 | 0 | 57 |
| `tmm/core/bin/tmm` | 74 | 1 | 1 | 0 | 76 |
| `tmm/core/libexec/seat-scan.sh` | 3 | 0 | 0 | 0 | 3 |
| `tmm/core/libexec/tmm-dead-scan.py` | 0 | 0 | 1 | 1 | 2 |
| `tmm/core/libexec/tmm-models-sync.py` | 0 | 0 | 0 | 0 | 0 |
| `tmuxc/core/libexec/tmuxc-restore-scan.py` (인접) | 0 | 0 | 1 | 1 | 2 |
| `tmuxc/core/libexec/tmuxc-snapshot.py` (인접) | 0 | 0 | 0 | 0 | 0 |
| `tmm/install.sh`·`uninstall.sh`·`tmuxc/install.sh`·`uninstall.sh` | 0 | 0 | 0 | 0 | 0 (command -v 존재확인만) |
| `tmm/test/*.sh`·`tmuxc/test/*.sh` | 35 (격리 서버) | 0 | 0 | 0 | 35 |

**한 줄**: tmux 실행 호출 124건 중 `display-message·has-session·send-keys·capture-pane·list-sessions·list-panes·show-environment` 7종이 **88건(71%)**, 프로세스 조회는 전부 **로컬 `pgrep -P`(부모-자식 트리) + `ps`(argv) + `lsof`(열린 파일)** 3종뿐이다(원격 프로세스 테이블 조회 0).

### 서브명령 총계 (실행 호출만 · 문서/주석/출력문자열 제외)

| 서브명령 | tmuxc bin | tmm bin | seat-scan | 합계 |
|---|---|---|---|---|
| `display-message` / `display` | 9 | 9 | 0 | 18 |
| `has-session` | 7 | 11 | 0 | 18 |
| `send-keys` | 7 | 8 | 0 | 15 |
| `list-sessions` | 5 | 5 | 1 | 11 |
| `list-panes` | 6 | 2 | 0 | 8 |
| `capture-pane` | 5 | 6 | 2 | 13 |
| `show-environment` | 3 | 2 | 0 | 5 |
| `set` | 1 | 5 | 0 | 6 |
| `new-session` | 1 | 2 | 0 | 3 |
| `kill-session` | 1 | 3 | 0 | 4 |
| `switch-client` | 0 | 3 | 0 | 3 |
| `detach-client` | 0 | 2 | 0 | 2 |
| `list-clients` | 0 | 3 | 0 | 3 |
| `show` (`show-options` 축약) | 0 | 5 | 0 | 5 |
| `select-pane` | 0 | 2 (+1 fzf 액션 문자열) | 0 | 2 |
| `set-environment` | 1 | 0 | 0 | 1 |
| `attach` | 1 | 1 | 0 | 2 |
| `split-window` / `kill-pane` | 0 / 0 | 1 / 1 | 0 | 1 / 1 |
| `ls` (별칭) | 0 | 3 | 0 | 3 |
| **tmux 합계** | **47** | **74** | **3** | **124** |
| `pgrep` | 7 | 1 | 0 | 8 |
| `ps` | 3 | 1 | 0 | 4 |
| `lsof` | 0 | 0 | 0 | 0 (python 헬퍼에 1) |

---

## 1. `feature-pack/tmuxc/core/bin/tmuxc` (1871줄)

호출 47건 + pgrep 7 · ps 3. **lsof 0건.**
"어느 명령" 열 = `main()` 의 `case` 로 들어온 tmuxc 서브커맨드 (open|wt / fork / list / attach / send / submit / ask / model / probe / msg / kill / clean / save / restore).

| # | 파일:줄 | 명령 + 서브명령 | 인자 모양 | 어느 명령에서 |
|---|---|---|---|---|
| 1 | tmuxc:50 | `tmux set-environment -gu NO_COLOR` | 고정(플래그 2 + 키 1) | `prepare_color_environment` ← `create_tmux_session` ← open / fork / restore |
| 2 | tmuxc:62 | `tmux new-session -d -s <name> -c <root> -e FT_SEAT=<name> [-e K=V …]` | 가변(세션명·절대경로·env 반복 `-e`) | `create_tmux_session` ← open / fork / restore |
| 3 | tmuxc:65 | `tmux set -wu -t "=<name>:" window-size` | 고정 | `create_tmux_session` ← open / fork / restore |
| 4 | tmuxc:541 | `tmux has-session -t <sess>` | 고정 | `session_live_launch` ← model |
| 5 | tmuxc:543 | `tmux list-panes -t <sess> -F '#{pane_pid}'` | 고정 포맷 | `session_live_launch` ← model |
| 6 | tmuxc:546 | `pgrep -P <ppid>` | 고정 | `session_live_launch` ← model |
| 7 | tmuxc:546 | `pgrep -g <ppid>` (프로세스 그룹) | 고정 | `session_live_launch` ← model |
| 8 | tmuxc:548 | `ps -o command= -p <pid>` | 고정 포맷 | `session_live_launch` ← model |
| 9 | tmuxc:569 | `tmux send-keys -t <session> -l <message>` | **여러 줄 본문**(guide·run_cmd·prompt 자유문) | `inject_message` ← open / fork / restore / send / msg |
| 10 | tmuxc:571 | `tmux send-keys -t <session> Enter` | 고정 | `inject_message` |
| 11 | tmuxc:700 | `tmux has-session -t <name>` | 고정 | open (중복 세션 가드) |
| 12 | tmuxc:711·713·715·717 | `tmux display-message -p '#S'` | 고정 포맷 1개 | open (engine별 guide 접두 4분기) |
| 13 | tmuxc:730 | `tmux list-panes -t <name> -F '#{pane_pid}'` | 고정 | open (headroom 경유 검증) |
| 14 | tmuxc:731 | `pgrep -P <pane_pid>` | 고정 | open (headroom 경유 검증) |
| 15 | tmuxc:732 | `ps eww <pid>` (env 전문) | 고정 | open (headroom 경유 검증) |
| 16 | tmuxc:747 | `tmux has-session -t <from>` | 고정 | `resolve_fork_source_from_live` ← fork --from |
| 17 | tmuxc:758 | `tmux display-message -p -t <from> '#{session_path}'` | 고정 포맷 | `resolve_fork_source_from_live` ← fork --from |
| 18 | tmuxc:885 | `tmux has-session -t <name>` | 고정 | fork (중복 가드) |
| 19 | tmuxc:901·903·905·907 | `tmux display-message -p '#S'` | 고정 | fork (FORK guide 접두) |
| 20 | tmuxc:920 | `tmux list-sessions -F '#S\t#{session_path}\t#{session_attached}'` | 고정 포맷(탭 구분) | list |
| 21 | tmuxc:927 | `tmux has-session -t <name>` | 고정 | ask |
| 22 | tmuxc:928 | `tmux capture-pane -t <name> -p \| tail -n <lines>` | 가변(줄수) | ask |
| 23 | tmuxc:936 | `tmux has-session -t <name>` | 고정 | send |
| 24 | tmuxc:939 | `tmux capture-pane -t <name> -p \| tail -80 \| grep -qF <msg>` | **가변 본문**(메시지 원문 grep) | send (도달확인) |
| 25 | tmuxc:952 | `tmux list-panes -a -F '#S\t#{pane_current_command}'` | 고정 포맷 | clean |
| 26 | tmuxc:981 | `pgrep -P <cur>` (BFS, 최대 8 depth) | 고정 | `pane_descendant_pids` ← probe / save / fork |
| 27 | tmuxc:998·1000·1001 | `tmux show-environment -t <sess> TMUXC_PI_SESSION_ID / TMUXC_PI_MODEL / TMUXC_PI_THINKING` | 고정 키 3종 | `session_agent_probe` ← probe / model / save |
| 28 | tmuxc:1009 | `tmux list-panes -t <sess> -F '#{pane_pid}'` | 고정 | `session_agent_probe` |
| 29 | tmuxc:1013 | `ps -o command= -p <pid>` | 고정 | `session_agent_probe` |
| 30 | tmuxc:1147 | `tmux list-sessions` (>/dev/null 생존확인) | 고정 | save (preflight) |
| 31 | tmuxc:1163 | `tmux list-sessions -F '#S\t#{session_path}\t#{session_attached}\t#{pane_current_command}'` | 고정 포맷 | save (1단계 열거) |
| 32 | tmuxc:1406 | `tmux list-panes -t <name> -F '#{pane_pid}'` | 고정 | `restore_agent_live` ← restore |
| 33 | tmuxc:1417 | `pgrep -P <ppid> -f <pat>` | 가변 패턴(엔진별) | `restore_agent_live` |
| 34 | tmuxc:1419 | `pgrep -P <ppid> -f <pat>` | 가변 패턴 | `restore_agent_live` |
| 35 | tmuxc:1422 | `pgrep -P <ppid>` | 고정 | `restore_agent_live` (래퍼 폴백) |
| 36 | tmuxc:1430 | `tmux capture-pane -t <name> -p` | 고정 | `restore_pane_ready` ← restore |
| 37 | tmuxc:1535 | `tmux has-session -t <name>` | 고정 | `restore_one` ← restore |
| 38 | tmuxc:1620 | `tmux list-sessions` | 고정 | restore (preflight) |
| 39 | tmuxc:1622 | `tmux list-sessions \| wc -l` | 고정 | restore (세션 수 표시) |
| 40 | tmuxc:1712 | `tmux list-panes -a -F '#{session_name}\|#{pane_id}'` | 고정 포맷 | `pane_id_of` ← submit |
| 41 | tmuxc:1721 | `tmux capture-pane -t <pane> -p` | 고정 | `capture_input_line` ← submit |
| 42 | tmuxc:1741 | `tmux capture-pane -t <pane> -p` | 고정 | `transcript_has` ← submit |
| 43 | tmuxc:1755 | `tmux send-keys -t <pane> Enter` | 고정 | `submit_enter_loop` ← submit |
| 44 | tmuxc:1791 | `tmux send-keys -t <pane> -l "$PROBE_CHAR"` | 1글자(X) | submit (축1 버퍼 탐침) |
| 45 | tmuxc:1794 | `tmux send-keys -t <pane> BSpace` | 고정 키 이름 | submit |
| 46 | tmuxc:1816 | `tmux send-keys -t <pane> C-u` | 고정 키 이름 | submit --retype |
| 47 | tmuxc:1818 | `tmux send-keys -t <pane> -l <before>` | **가변 본문**(입력줄 원문) | submit --retype |
| 48 | tmuxc:1833 | `tmux attach -t <name>` | 고정 | main `attach` |
| 49 | tmuxc:1861 | `tmux kill-session -t <name>` | 고정 | main `kill` |

### 인자 모양 분류 (tmuxc bin)

| 모양 | 건수 | 해당 |
|---|---|---|
| 순수 고정(플래그·키이름만) | 26 | 50, 65, 541, 571, 700, 885, 1147, 1535, 1620, 1755, 1794, 1816, 1833, 1861 등 |
| 고정 포맷 + 세션명 1개 | 14 | 543, 730, 920, 952, 1009, 1406, 1712, 1163, 998~1001 … |
| 가변(경로·env·패턴·줄수) | 5 | 62, 928, 1417, 1419, 546 |
| **여러 줄/자유 본문** | **3** | 569(`-l <message>` guide·prompt·run_cmd), 939(grep 원문), 1818(`-l <before>`) |

### 출력 문자열에만 등장(실행 아님 · 오탐 방지용 명시)
`tmuxc:` 738, 915, 1516, 1576, 1582 (`attach=tmux attach -t …` printf), 6 (usage), 713/715/717/905 등 문장 속 "verified-send" — **호출 0**.

---

## 2. `feature-pack/tmm/core/bin/tmm` (1740줄)

tmux 74건 + pgrep 1 · ps 1. **lsof 0건.** (기본 실행 = fzf 피커 TUI)

| # | 파일:줄 | 명령 + 서브명령 | 인자 모양 | 어느 명령에서 |
|---|---|---|---|---|
| 1 | tmm:96 | `tmux display -p '#{socket_path}' \| cksum` | 고정 포맷 | `cache_init` ← list/tui/rows 전 경로 |
| 2 | tmm:135 | `tmux new-session -A -s <picker> "<TMM cmd>" ';' set -t =<picker>: @tmm_picker 1 ';' set … @tmm_ver … ';' set … prefix None [';' bind-key d run-shell "<self> dkey …"]` | **가변·다중 인자·인용 명령 + 명령 체인(`;`)** | `tui_wrap` (인자 없는 TUI 실행) |
| 3 | tmm:142 | `tmux list-clients -t "=<name>" -F x` | 고정 | `picker_free` ← `pick_picker_name` ← tui_wrap |
| 4 | tmm:147 | `tmux show -gqv "@tmm_home_<tty>"` | 가변(옵션명에 tty) | `picker_free` |
| 5 | tmm:148 | `tmux list-clients -F '#{client_tty}\t#{client_last_session}'` | 고정 포맷 | `picker_free` |
| 6 | tmm:157 | `tmux show -t "=<sess>:" -qv @tmm_ver` | 고정 | `picker_stale` ← `pick_picker_name` |
| 7 | tmm:163 | `tmux has-session -t "=<sess>"` | 고정 | `pick_picker_name` |
| 8 | tmm:166 | `tmux kill-session -t "=<sess>"` | 고정 | `pick_picker_name` (좀비 피커 정리) |
| 9 | tmm:210 | `tmux show -t "=<1>:" -qv @tmm_picker` | 고정 | `is_picker` ← cmd_dkey / cmd_attach / picker_free 계열 |
| 10 | tmm:218 | `tmux detach-client -t <tty>` | 가변(tty) | `cmd_dkey` (bind-key d) |
| 11 | tmm:219 | `tmux show -gqv "@tmm_home_<tty>"` | 가변 | `cmd_dkey` |
| 12 | tmm:220 | `tmux display -p -c <tty> '#{client_last_session}'` | 고정 포맷 | `cmd_dkey` |
| 13 | tmm:222 | `tmux has-session -t "=<p>"` | 고정 | `cmd_dkey` |
| 14 | tmm:223 | `tmux switch-client -c <tty> -t "=<p>"` | 가변 | `cmd_dkey` |
| 15 | tmm:225 | `tmux list-sessions -F '#{session_attached}\t#{session_name}' -f '#{@tmm_picker}'` | 고정 포맷 + 필터식 | `cmd_dkey` |
| 16 | tmm:226 | `tmux switch-client -c <tty> -t "=<p>"` | 가변 | `cmd_dkey` |
| 17 | tmm:226 | `tmux detach-client -t <tty>` | 가변 | `cmd_dkey` |
| 18 | tmm:257 | `tmux list-sessions -F '#{session_name}'` | 고정 | `cat_of` (분류 계산) |
| 19 | tmm:287 | `tmux list-sessions -F '#{session_name}'` | 고정 | `cat_prep` ← cmd_rows / cmd_dead_rows |
| 20 | tmm:326 | `tmux capture-pane -t "=<s>:" -p -S -300` | 가변(스크롤백 300) | `last_epoch` ← cmd_rows (좌석당 1회, xargs -P 8) |
| 21 | tmm:392 | `tmux show-environment -t "=<sess>" TMUXC_PI_THINKING` | 고정 키 | `live_effort_of` ← cmd_rows |
| 22 | tmm:406 | `tmux show-environment -t "=<sess>" TMUXC_PI_MODEL` | 고정 키 | `live_model_of` ← cmd_rows |
| 23 | tmm:407 | `tmux capture-pane -t "=<sess>:" -p` (pi 하단줄 파싱) | 고정 | `live_model_of` (폴백) |
| 24 | tmm:411 | `tmux capture-pane -t "=<sess>:" -p \| grep -oE '\bgpt-[0-9.]+-[a-z]+\b'` | 고정 | `live_model_of` (codex 폴백) |
| 25 | tmm:467 | `tmux list-panes -a -F '#{session_name}\t#{window_activity}\t#{pane_pid}'` | 고정 | cmd_rows |
| 26 | tmm:479 | `tmux list-sessions -F '#{session_name}' -f '#{@tmm_picker}'` | 고정 | cmd_rows |
| 27 | tmm:491 | `tmux list-panes -a -F '#{session_name}\t#{pane_current_command}\t#{window_activity}\t#{pane_current_path}'` | 고정 | cmd_rows |
| 28 | tmm:601 | `tmux display -p -t <pane> '#{window_width}'` | 고정 | `split_open` |
| 29 | tmm:603 | `tmux split-window -h -b -d -l <catw> -P -F '#{pane_id}' -t <pane> "<TMM_RUN=… TMM_NO_WRAP=1 <self> catpane>"` | **가변 + 셸 명령 인용** | `split_open` (분류 칸 pane) |
| 30 | tmm:606 | `tmux set -w -t <pane> pane-active-border-style 'fg=cyan'` | 고정 | `split_open` |
| 31 | tmm:606 | `tmux set -w -t <pane> pane-border-style 'fg=brightblack'` | 고정 | `split_open` |
| 32 | tmm:612 | `tmux kill-pane -t <pane>` | 가변 | `split_close` |
| 33 | tmm:674 | `tmux select-pane -t <main>` | 가변 | `cmd_catgo` |
| 34 | tmm:677 | `tmux select-pane -t <main>` | 가변 | `cmd_catfwd` |
| 35 | tmm:678 | `tmux send-keys -t <main> -H <hex바이트>` | 가변(hex) | `cmd_catfwd` |
| 36 | tmm:678 | `tmux send-keys -t <main> <키이름>` | 가변(키 이름) | `cmd_catfwd` |
| 37 | tmm:843 | `tmux ls -F '#S'` | 고정 | `dead_tsv` ← tmm dead / 종료뷰 |
| 38 | tmm:894 | `tmux display -p -t "=<s>:" '#{pane_pid}'` | 고정 | `live_agent_of` ← idx_row / dead 미리보기 |
| 39 | tmm:896 | `pgrep -P <ppid>` | 고정 | `live_agent_of` |
| 40 | tmm:897 | `ps -o args= -p <pid>` | 고정 | `live_agent_of` |
| 41 | tmm:906 | `tmux display -p -t "=<s>:" '#{pane_title}'` | 고정 | `live_agent_of` (cmd 판별 폴백) |
| 42 | tmm:916 | `tmux has-session -t "=<n>"` | 고정 | `idx_row` ← tmm idx / idxp |
| 43 | tmm:917 | `tmux display -p -t "=<n>:" '#{pane_current_path}'` | 고정 | `idx_row` |
| 44 | tmm:981 | `tmux has-session -t "=<n>"` (최대 50회 루프) | 고정 | `free_name` ← fork |
| 45 | tmm:992 | `tmux has-session -t "=<n>"` | 고정 | `src_model_effort` ← fork (모델 승계) |
| 46 | tmm:1062 | `tmux has-session -t "=<src>"` | 고정 | `cmd_fork` (--from 분기) |
| 47 | tmm:1154 | `tmux kill-session -t "=<name>"` | 고정 | `cmd_forkp` (사용자 취소 정리) |
| 48 | tmm:1210 | `tmux has-session -t "=<n>"` | 고정 | `cmd_restore_one` (이미 살아있으면 attach) |
| 49 | tmm:1223 | `tmux new-session -d -s <name> -c <cwd>` | 가변(경로) | `cmd_restore_one` |
| 50 | tmm:1227 | `tmux set -wu -t "=<name>:" window-size` | 고정 | `cmd_restore_one` |
| 51 | tmm:1228 | `tmux send-keys -t "=<name>:" -l <resume cmd>` | **가변 본문**(복구 명령 전문) | `cmd_restore_one` |
| 52 | tmm:1228 | `tmux send-keys -t "=<name>:" Enter` | 고정 | `cmd_restore_one` |
| 53 | tmm:1232 | `tmux capture-pane -t "=<name>:" -p \| grep -qE '<부팅 마커>'` | 고정 패턴 | `cmd_restore_one` (부팅 판정, 최대 20회×3초) |
| 54 | tmm:1233 | `tmux display -p -t "=<name>:" '#{pane_current_command}'` | 고정 | `cmd_restore_one` |
| 55 | tmm:1237 | `tmux send-keys -t "=<name>:" -l "[restore→<name>] …COMM-GUIDE-BOOT…"` | **고정 장문 본문**(1문장) | `cmd_restore_one` |
| 56 | tmm:1237 | `tmux send-keys -t "=<name>:" Enter` | 고정 | `cmd_restore_one` |
| 57 | tmm:1270 | `tmux has-session -t "=<n>"` | 고정 | `cmd_restore_all` (배치 병렬 결과 판정) |
| 58 | tmm:1365 | `tmux has-session -t "=<n>"` | 고정 | `cmd_attach` |
| 59 | tmm:1371 | `tmux set -wu -t "=<n>:" window-size` | 고정 | `cmd_attach` (attach 직전 window-size 해제) |
| 60 | tmm:1375 | `tmux display -p -t "${TMUX_PANE:-}" '#{session_name}'` | 고정 | `cmd_attach` (출발 피커 기록) |
| 61 | tmm:1377 | `tmux set -g "@tmm_home_<tty>" <me>` | 가변(옵션명·값) | `cmd_attach` |
| 62 | tmm:1378 | `tmux list-clients -t "=<me>" -F '#{client_tty}'` | 고정 | `cmd_attach` |
| 63 | tmm:1380 | `tmux switch-client -t "=<n>"` | 가변 | `cmd_attach` (TMUX 안) |
| 64 | tmm:1381 | `tmux attach -t "=<n>" [-f ignore-size]` | 가변(플래그 선택) | `cmd_attach` (TMUX 밖) |
| 65 | tmm:1386 | `tmux capture-pane -t "=<n>:" -p \| grep -v 빈줄 \| tail -n <k> \| cut -c1-$COLUMNS` | 가변(줄수·폭) | `cmd_peek` (tmm p / send 도달확인 / kill 미리보기) |
| 66 | tmm:1397 | `tmux capture-pane -t "=<n>:" -p -e -J -S -200` | 고정 | `cmd_preview` (fzf 미리보기) |
| 67 | tmm:1432 | `tmux display -p -t "=<1>:" '#{pane_current_command}'` | 고정 | `live_mark` ← `cmd_send` (HARD GATE) |
| 68 | tmm:1443 | `tmux send-keys -t "=<n>:" -l "[mobile→<n>] <msg>"` | **가변 본문** | `cmd_send` (tmuxc **없을 때** 폴백) |
| 69 | tmm:1443 | `tmux send-keys -t "=<n>:" Enter` | 고정 | `cmd_send` 폴백 |
| 70 | tmm:1463 | `tmux has-session -t "=<n>"` | 고정 | `cmd_kill` (전제 확인) |
| 71 | tmm:1470 | `tmux kill-session -t "=<n>"` | 고정 | `cmd_kill` (tmuxc **없을 때** 폴백) |
| 72 | tmm:1472 | `tmux has-session -t "=<n>"` | 고정 | `cmd_kill` (사후 확인) |
| 73 | tmm:1490 | `tmux ls >/dev/null` | 고정 | `cmd_doctor` |
| 74 | tmm:1490 | `tmux ls \| wc -l` | 고정 | `cmd_doctor` |
| 75 | tmm:1504 | `tmux show -t "=<psess>:" -qv @tmm_ver` | 고정 | `cmd_doctor` (좀비 피커 탐지) |
| 76 | tmm:1505 | `tmux list-sessions -F '#{session_name}' -f '#{@tmm_picker}'` | 고정 | `cmd_doctor` |

### 실행 아닌 문자열 / 특수
- tmm:596 `to_cat_action` = `printf 'execute-silent(tmux select-pane -t %s)'` — **fzf 액션 문자열**(실행 주체는 fzf). 호출 카운트에서 제외.
- tmm:1223 `echo "❌ tmux new-session 실패"` — 출력 문자열.
- tmm:1481 `for c in tmux fzf` + `command -v` — **존재 확인만**, 호출 아님.
- tmm:922·993·1035·1093·1441·1470 등은 `tmuxc` **자체 CLI 호출**(probe/model/send/kill) — tmux 바이너리 호출이 아님.
- tmm:1431 주석 "pgrep -P 는 zsh 플러그인 자식(gitstatusd 등)을 에이전트로 오판" — 실행 아님(설계 근거 기록).

### tmm 안에서 tmuxc 로 위임하는 지점 (tmux 직접 호출 아님 · H5 판단용 사실)
| 파일:줄 | 위임 대상 | 트리거 명령 |
|---|---|---|
| tmm:922 | `tmuxc probe <name>` | tmm idx (pi sid 조회) |
| tmm:993 | `tmuxc model <name>` | fork (모델 승계) |
| tmm:1061·1070 | `tmuxc fork` / `tmuxc open` | tmm fork (스폰 위임) |
| tmm:1441 | `tmuxc send <n> "[mobile→<n>] …"` | tmm send |
| tmm:1470 | `tmuxc kill <n>` | tmm kill |
| tmm:1735 | `tmuxc save` | tmm save |
| tmm:1674 | `tmuxc save` | 메뉴 7번 |

---

## 3. `feature-pack/tmm/core/libexec/`

| # | 파일:줄 | 명령 + 서브명령 | 인자 모양 | 어느 명령에서 |
|---|---|---|---|---|
| 1 | seat-scan.sh:17 | `tmux list-sessions -F '#S'` | 고정 | standalone (tmm `scan`/`human`/rows 가 bash 로 실행) |
| 2 | seat-scan.sh:23 | `tmux capture-pane -t <s> -p` (현재 화면) | 가변(세션명) | 〃 좌석당 1회 |
| 3 | seat-scan.sh:24 | `tmux capture-pane -t <s> -p -S -<LINES>` (스크롤백, 기본 150) | 가변(세션명·줄수) | 〃 좌석당 1회 |
| 4 | tmm-dead-scan.py:131 | `ps -eo args` (전 시스템 1회) | 고정 | `live_sids()` ← `scan`/`resolve` (tmm dead·restore 후보 필터) |
| 5 | tmm-dead-scan.py:139 | `lsof -Fn -c claude -c codex -c opencode -c cmd -c node` (전 시스템 1회) | **가변**(`-c` 반복 · 하드코딩 엔진 목록) | `live_sids()` |
| — | tmm-models-sync.py | tmux/pgrep/ps/lsof **0건** (opencode 모델 목록 생성 전용) | — | tmm models refresh |

---

## 4. `feature-pack/tmuxc/core/libexec/` (인접 — 발주 범위 밖이지만 tmuxc core 스크립트라 포함)

| # | 파일:줄 | 명령 + 서브명령 | 인자 모양 | 어느 명령에서 |
|---|---|---|---|---|
| 1 | tmuxc-restore-scan.py:275 | `lsof -t -- <jsonl path>` | 가변(절대경로) | `file_in_use()` ← `scan_claude`/`scan_codex` ← `tmuxc restore --scan` |
| 2 | tmuxc-restore-scan.py:281 | `ps -o command= -p <pid,pid,…>` | 가변(pid 목록 콤마) | `file_in_use()` (에이전트 프로세스만 인정) |
| — | tmuxc-snapshot.py | tmux/pgrep/ps/lsof **0건** (sid 해석·JSON 직렬화 전용) | — | `tmuxc save` |

---

## 5. 설치·삭제·시험 스크립트

| 파일 | tmux/pgrep/ps/lsof 실행 호출 | 비고 |
|---|---|---|
| `tmm/install.sh` | **0** | `for cmd in bash tmux fzf` + `command -v` 존재확인만 · `~/.tmuxc/current/core/VERSION` 읽기 |
| `tmm/uninstall.sh` | **0** | — |
| `tmuxc/install.sh` | **0** | `for cmd in bash git tmux` + `command -v` · 설치 후 `<bin>/tmuxc list` smoke |
| `tmuxc/uninstall.sh` | **0** | 심링크 검사만 |
| `tmm/test/capture.sh` | 1 (`kill-server`) | `tm()` = `env -u TMUX TMUX_TMPDIR=$SOCK tmux …` **격리 소켓** |
| `tmm/test/perf.sh` | 1 (`list-sessions`) | PATH 맨 앞에 **tmux 래퍼**를 심어 호출 수를 `$CALLS` 에 기록 · 격리 `TMUX_TMPDIR` |
| `tmm/test/verify.sh` | 4 (`kill-server`·`select-pane`×3) | `tm()` 래퍼 + 격리 소켓 · 생성 파이썬 스크립트 안에서 `subprocess.run(['tmux', …])` |
| `tmuxc/test/verify.sh` | 29 (`new-session`·`send-keys`·`kill-server`·`show-environment`·`display-message` 등) | 전부 `env -u TMUX TMUX_TMPDIR=<격리> …` · 실사용 서버 미접촉 |
| `tmuxc/test/test_tmuxc_opencode_model.sh` | 0 | `PATH` 앞에 **가짜 tmux 스크립트**(new-session 인자를 로그로) |
| `tmuxc/test/test_tmuxc_agent_seat_git_editor.sh` | 0 | 〃 가짜 tmux |

---

## 6. 사실 관찰 (설계 아님 · H5 판단용)

1. **모든 tmux 호출이 "현재 프로세스가 붙은 tmux 서버"를 암묵 대상으로 한다.** 소켓을 명시하는 호출은 0건 — 격리는 전부 `TMUX_TMPDIR` 환경변수(테스트 4개 파일)와 `#{socket_path}`(tmm:96 캐시 키)로만 이뤄진다.
2. **좌석 식별 = 로컬 프로세스 트리.** `pgrep -P`(부모→자식) + `ps -o args=/command=` + pane env(`TMUXC_PI_*`) 3종뿐. 원격 호스트의 프로세스 테이블을 조회하는 호출은 **0건**.
3. **파일 점유 판정 = 로컬 `lsof`.** `lsof`는 tmm-dead-scan(전 시스템 1회, `-c` 5개 엔진)과 tmuxc-restore-scan(경로 1개)에서만 쓰이고, 둘 다 로컬 프로세스 테이블 기준이다.
4. **경로 가정 = 로컬 홈.** `~/.tmuxc/{current,snapshots}`, `~/.pi/agent/sessions`, `~/.claude/...`, `$TMPDIR/tmm-scan-<uid>-<socket cksum>.cache` — 홈·TMPDIR 이 로컬이라는 전제가 코드에 직접 박혀 있다.
5. **자유 본문이 tmux 인자로 들어가는 지점은 8곳**(tmuxc:569·939·1818, tmm:1228·1237·1443, tmuxc:569 계열 가이드). 여러 줄 본문은 `send-keys -l` 1회로만 넣고 Enter 는 별도 호출이다(tmuxc:569/571, tmm:1228, tmm:1443).
6. **세션명에 `=` 접두를 쓰는 곳이 tmm 쪽에 집중**(`-t "=<name>"`, 22건) — `$`·`#` 접미 세션명 파싱 함정 회피용. tmuxc bin 은 `-t "$name"` 단순 형태(1563 계열 제외)이고, `#N` 파싱 함정은 `list-panes -a` + awk 정확매칭(tmuxc:1712)으로 우회한다.
7. **호출 밀도**: tmm `cmd_rows` 1회 = `list-sessions`(287/479) + `list-panes -a`×2(467/491) + 좌석당 `capture-pane` 1회(326, `xargs -P 8` 병렬) + pi/codex 좌석만 `show-environment`/`capture-pane` 추가. 65좌석 기준 주석상 약 2초(seat-scan 포함).
8. **`tmuxc restore` 1회 =** `list-sessions`(1620/1622) + 세션당 `has-session`(1535) + `new-session`/`set`/`send-keys`×2 + 판정용 `capture-pane`×N(1430, 최대 20회×3초) + `pgrep`×3(1417/1419/1422).
9. **tmm 은 tmuxc 로 위임하는 경로가 7곳**(send/kill/probe/model/fork/open/save) — tmux 직접 호출 경로는 위임 실패 시 폴백(tmm:1443, 1470)으로만 남아 있다.
10. **`ps eww <pid>`(tmuxc:732)는 프로세스 환경변수 전문을 읽는다** — headroom 프록시 경유 검증용. 원격 호스트에는 적용 불가한 로컬 전용 조회다.
