# CALLTREE r897 r5 — 지우는 길(출구 게이트 delete_copy 포함) 함수의 외부 출력 받기(cap·gq) 전수 · 자동 생성(test ⓨ · 손 표 0)

| 함수 | 줄 | 코드 |
|---|---|---|
| delete_copy | 368 | `cap P phys_tmo "$p" \|\| { gfail G1 2 "물리 경로 못 읽음"; return; }` |
| delete_copy | 382 | `cap now date +%s && isnum "$now" \|\| { gfail G3 2 "시계 못 읽음"; return; }` |
| delete_copy | 386 | `gq RAW lsof -w -d cwd -Fpcn 2>/dev/null \|\| { gfail G4 2 "lsof 못 읽음"; return; }` |
| delete_copy | 388 | `cap ROWS cwd_parse "$RAW" \|\| { gfail G4 2 "lsof 해석 실패"; return; }` |
| delete_copy | 394 | `cap r remtmo; [ "$r" -gt 0 ] \|\| { gfail G6 2 "예산 소진"; return; }` |
| delete_copy | 395 | `cap S tmux_sessions_tmo "$r" \|\| { gfail G6 2 "tmux 못 읽음"; return; }` |
| delete_copy | 401 | `cap JUDGE_TMO remtmo; [ "$JUDGE_TMO" -gt 0 ] \|\| { JUDGE_TMO=7; gfail G6 2 "예산 소진"; return; }` |
| delete_copy | 407 | `gq T git -C "$P" rev-parse --show-toplevel 2>/dev/null \|\| { gfail G7 2 "toplevel 못 읽음"; return; }` |
| delete_copy | 408 | `cap TP phys_tmo "$T" \|\| { gfail G7 2 "toplevel 물리 경로 못 읽음"; return; }` |
| delete_copy | 410 | `gq G git -C "$P" rev-parse --path-format=absolute --git-dir 2>/dev/null \|\| { gfail G7 2 "git-dir 못 읽음"; return; }` |
| delete_copy | 411 | `gq C git -C "$P" rev-parse --path-format=absolute --git-common-dir 2>/dev/null \|\| { gfail G7 2 "git-common-dir 못 읽음"; return; }` |
| delete_copy | 412 | `cap GP phys_tmo "$G" \|\| { gfail G7 2 "git-dir 물리 경로 못 읽음"; return; }` |
| delete_copy | 413 | `cap CP phys_tmo "$C" \|\| { gfail G7 2 "git-common-dir 물리 경로 못 읽음"; return; }` |
| delete_copy | 415 | `cap r remtmo; [ "$r" -gt 0 ] \|\| { gfail G7 2 "예산 소진"; return; }` |
| delete_copy | 424 | `gq U stat -f %u "$P" \|\| { gfail G6 2 "소유자 못 읽음"; return; }` |
| delete_copy | 425 | `gq ME id -u \|\| { gfail G6 2 "내 uid 못 읽음"; return; }` |
| delete_copy | 427 | `gq M stat -f %m "$P" \|\| { gfail G6 2 "수정 시각 못 읽음"; return; }` |
| delete_copy | 432 | `gq DI stat -f %d:%i "$P" \|\| { gfail G8 2 "장치·inode 못 읽음"; return; }` |
| delete_copy | 436 | `gq T2 git -C "$P" rev-parse --show-toplevel 2>/dev/null && [ "$T2" = "$T" ] \|\| { gfail G8 2 "제거 직전 toplevel 다름·못 읽음"; return; }` |
| delete_copy | 437 | `gq G2 git -C "$P" rev-parse --path-format=absolute --git-dir 2>/dev/null && [ "$G2" = "$G" ] \|\| { gfail G8 2 "제거 직전 git-dir 다름·못 읽음"; return; }` |
| delete_copy | 438 | `gq DI2 stat -f %d:%i "$P" && [ "$DI2" = "$DI" ] \|\| { gfail G8 2 "제거 직전 장치·inode 다름·못 읽음"; return; }` |
| delete_copy | 450 | `gq DI2 stat -f %d:%i "$dest" && [ "$DI2" = "$DI" ] \|\| { mv -- "$dest" "$P" 2>/dev/null; gfail G8 2 "이동한 대상 장치·inode 다름 — 원위치 복원"; return; }` |
| gate_rows | 328 | `gq rows cat -- "$TSV" 2>/dev/null \|\| { gfail G5 2 "등록부 못 읽음"; return; }` |
| gate_rows | 334 | `cap pp phys_tmo "$c1" \|\| { gfail G5 2 "등록 줄 경로 못 읽음 $c1"; return; }` |
| gate_base | 353 | `cap B phys_tmo "$c" \|\| { gfail G1 2 "베이스 못 읽음 $c"; return; }` |
| past_deadline | 313 | `cap now date +%s && isnum "$now" \|\| return 0` |
| phys_tmo | 317 | `local t; cap t remtmo; [ "$t" -gt 0 ] \|\| return 124` |
| gq | 320 | `gq() { # <변수> <외부 명령…> → 남은 예산 상한으로 cap · 예산 0 = rc124(호출 0) · 셸 함수는 넘기지 않는다(gtimeout 이 못 부른다)` |
| gq | 321 | `local __gq_t; cap __gq_t remtmo; [ "$__gq_t" -gt 0 ] \|\| return 124` |
| gq | 323 | `cap "$__gq_v" bounded "$__gq_t" "$@"` |
| fast | 293 | `cap sha git -C "$p" rev-parse HEAD 2>/dev/null \|\| return 1   # ②HEAD 를 읽을 수 있고 이름 sha8 과 같다(만든 뒤 커밋 0)` |
| judged | 161 | `cap sha git -C "$1" rev-parse HEAD 2>/dev/null \|\| return 1; h8="${sha:0:8}"` |
| judged | 168 | `cap out bounded "$tmo" git -C "$ROOT" grep -F -l "$h8" "$m" -- design 2>/dev/null; rc=$?` |
| judged | 178 | `cap ct bounded "$tmo" git -C "$ROOT" log -1 --format=%ct "$m" -- "$f" 2>/dev/null; rc=$?` |
| judged | 188 | `cap now date +%s \|\| { echo "WARN ft-scratch-repo judged — 시계(date) 실패 · 판정 안 끝남 $1" >&2; return 1; }` |
| orphans | 236 | `cap now date +%s && isnum "$now" \|\| { READ_OK=0; echo "ERROR 시계(date +%s) 못 읽음 — 삭제 0" >&2; return 0; }` |
| orphans | 243 | `cap RAW $TMO lsof -w -d cwd -Fpcn 2>/dev/null \|\| LSOF_OK=0` |
| orphans | 246 | `[ "$LSOF_OK" = 0 ] \|\| cap CWDROWS cwd_parse "$RAW" \|\| LSOF_OK=0` |
| orphans | 250 | `if [ -e "$TSV" ]; then cap rows bounded 7 cat -- "$TSV" \|\| { READ_OK=0; echo "ERROR 등록부 못 읽음 — 삭제 0" >&2; return 0; }; fi` |
| orphans | 251 | `if cap SESS tmux_sessions; then` |
| orphans | 261 | `cap jnow date +%s && isnum "$jnow" \|\| { READ_OK=0; echo "ERROR 시계(date +%s) 못 읽음 — 삭제 0" >&2; return 0; }   # r5: 시계 못 읽음 = 이번 실행 전체 삭제 0(tmp 포함)` |
| orphans | 267 | `cap kbv kb "$p"; isnum "$kbv" \|\| kbv='?'   # 표시 전용(크기) — 결정 입력 0 · r5: 빈 칸 0(탭 IFS 가 빈 칸을 접어 열이 밀리던 길 · DA⑥ r4 반례 1b)` |
| orphans | 276 | `if cap me id -un && cap tdl find "$TD" -maxdepth 1 -type d -name 'tmp.*' -user "$me" -mmin +"$AGE" 2>/dev/null; then` |
| orphans | 280 | `cap kbv kb "$d"; isnum "$kbv" \|\| kbv='?'   # 표시 전용(크기)` |
| cwd_holder | 213 | `cap d phys "$1" && [ -n "$d" ] \|\| { HPID="?"; HCMD="경로 못 읽음"; return 0; }` |
| remtmo | 75 | `cap now date +%s && isnum "$now" \|\| { printf '0\n'; return 0; }` |
| sweep_run | 474 | `cap today date +%F   # 표시 전용(로그 날짜)` |
| sweep_run | 488 | `date +%s > "$ARMED"; cap g gib "$K"; cap l first_paths "$ORPH"   # 표시 전용` |
| sweep_run | 492 | `cap RSTART date +%s && isnum "$RSTART" \|\| { printf '%s ERROR 시계 못 읽음 — 삭제 0\n' "$today" >> "$SLOG"; echo "ERROR 시계(date) 못 읽음 — 임시 사본 정리 생략·삭제 0"; return 0; }` |
| sweep_run | 498 | `cap now date +%s && isnum "$now" \|\| { RSTOP=1; echo "WARN ft-scratch-repo — 시계 못 읽음 · 남은 항목 삭제 0" >&2; continue; }` |
| sweep_run | 516 | `cap g gib "$DK"   # 표시 전용` |
| done_run | 458 | `cap REG_OWN reg_owner "$P" 2>/dev/null \|\| die "등록부 못 읽음 — 삭제 0: $P" 4` |
| done_run | 461 | `[ -n "$ME" ] \|\| cap ME tmux display-message -p '#S' 2>/dev/null \|\| ME=-` |
