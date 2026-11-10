# CALLTREE r897 r10.5 — 지우는 길 함수의 외부 출력 받기(cap) 전수 · 자동 생성(test ⓨ · 손 표 0)

| 함수 | 줄 | 코드 |
|---|---|---|
| fast | 292 | `cap sha git -C "$p" rev-parse HEAD 2>/dev/null \|\| return 1   # ②HEAD 를 읽을 수 있고 이름 sha8 과 같다(만든 뒤 커밋 0)` |
| judged | 164 | `cap sha git -C "$1" rev-parse HEAD 2>/dev/null \|\| return 1; h8="${sha:0:8}"` |
| judged | 171 | `cap out bounded "$tmo" git -C "$ROOT" grep -F -l "$h8" "$m" -- design 2>/dev/null; rc=$?` |
| judged | 181 | `cap ct bounded "$tmo" git -C "$ROOT" log -1 --format=%ct "$m" -- "$f" 2>/dev/null; rc=$?` |
| judged | 191 | `cap now date +%s \|\| { echo "WARN ft-scratch-repo judged — 시계(date) 실패 · 판정 안 끝남 $1" >&2; return 1; }` |
| orphans | 239 | `cap now date +%s && isnum "$now" \|\| { READ_OK=0; echo "ERROR 시계(date +%s) 못 읽음 — 삭제 0" >&2; return 0; }` |
| orphans | 246 | `cap RAW $TMO lsof -w -d cwd -Fpcn 2>/dev/null \|\| LSOF_OK=0` |
| orphans | 249 | `[ "$LSOF_OK" = 0 ] \|\| cap CWDROWS cwd_parse "$RAW" \|\| LSOF_OK=0` |
| orphans | 252 | `if cap SESS tmux_sessions; then` |
| orphans | 262 | `cap jnow date +%s && isnum "$jnow" \|\| { jover=1; echo "WARN ft-scratch-repo — 판정 예산 시계 못 읽음 · 남은 사본은 즉시 삭제 후보 아님" >&2; continue; }` |
| orphans | 268 | `cap kbv kb "$p"   # 표시 전용(크기) — 결정에 안 쓴다(add 는 숫자 아닌 크기를 0 으로 센다)` |
| orphans | 275 | `if cap me id -un && cap tdl find "$TD" -maxdepth 1 -type d -name 'tmp.*' -user "$me" -mmin +"$AGE" 2>/dev/null; then` |
| orphans | 279 | `cap kbv kb "$d"   # 표시 전용(크기)` |
| cwd_holder | 216 | `cap d phys "$1" && [ -n "$d" ] \|\| { HPID="?"; HCMD="경로 못 읽음"; return 0; }` |
| recheck | 302 | `cap t remtmo; [ "$t" -gt 0 ] \|\| { echo "WARN ft-scratch-repo — 재확인 예산 소진 · 남은 항목 삭제 0" >&2; return 2; }` |
| recheck | 304 | `cap S tmux_sessions_tmo "$t" \|\| return 2` |
| recheck | 308 | `cap t remtmo; [ "$t" -gt 0 ] \|\| { echo "WARN ft-scratch-repo — 재확인 예산 소진 · 남은 항목 삭제 0" >&2; return 2; }` |
| recheck | 309 | `cap RAW bounded "$t" lsof -w -d cwd -Fpcn 2>/dev/null \|\| return 2` |
| recheck | 311 | `cap CWDROWS cwd_parse "$RAW" \|\| return 2   # r10.5: 해석 실패 = 못 읽음` |
| remtmo | 71 | `cap now date +%s && isnum "$now" \|\| { printf '0\n'; return 0; }` |
| overbudget | 80 | `cap now date +%s && isnum "$now" \|\| return 0` |
| sweep_run | 334 | `cap today date +%F   # 표시 전용(로그 날짜)` |
| sweep_run | 348 | `date +%s > "$ARMED"; cap g gib "$K"; cap l first_paths "$ORPH"   # 표시 전용` |
| sweep_run | 352 | `cap RSTART date +%s && isnum "$RSTART" \|\| { printf '%s ERROR 시계 못 읽음 — 삭제 0\n' "$today" >> "$SLOG"; echo "ERROR 시계(date) 못 읽음 — 임시 사본 정리 생략·삭제 0"; return 0; }` |
| sweep_run | 358 | `cap now date +%s && isnum "$now" \|\| { RSTOP=1; echo "WARN ft-scratch-repo — 시계 못 읽음 · 남은 항목 삭제 0" >&2; continue; }` |
| sweep_run | 374 | `cap g gib "$DK"   # 표시 전용` |
| done_run | 321 | `cap REG_OWN reg_owner "$P" 2>/dev/null \|\| die "등록부 못 읽음 — 삭제 0: $P" 4` |
| done_run | 324 | `[ -n "$ME" ] \|\| cap ME tmux display-message -p '#S' 2>/dev/null \|\| ME=-` |
| done_run | 326 | `cap RAW $TMO lsof -w -d cwd -Fpcn 2>/dev/null \|\| die "lsof 실패 — 삭제 0: $P" 4` |
| done_run | 328 | `cap CWDROWS cwd_parse "$RAW" \|\| die "lsof 해석 실패 — 삭제 0: $P" 4` |
