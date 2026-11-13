#!/usr/bin/env bash
# test_nano_close_landed_pr_renamed_branch_r1417.sh — r1417: ft-nano-close.sh --landed-pr(--wt 없음)가 «표준 경로에서 가지만 바꾼» 살아 있는 나노 좌석을 닫는다.
#   기준값: 표준 경로 + 가지 nano/<키>-fix + 세션 살아 있음 + --landed-pr → ③ REJECT «후보 0»(닫을 길 0).
# 반례 N1~N11 · 변이 M1~M7 · 기준판(BASE_SHA) N1 Red · 설비 = _landed_ref_wt_r1737_fixture.sh(임시 리포·가짜 tmux·가짜 gh · 실 좌석·실 명부 0).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_landed_ref_wt_r1737_fixture.sh"
BASE_1417=96465897   # r1417 기준판 = 이 카드의 팩 base(고치기 전)
git -C "$HERE" show "$BASE_1417:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh" || bad "기준판 못 읽음"

SW="$ROOT/.worktrees/v65-refwt"; SW2="$ROOT/.worktrees/v65-refwt-r2"; SW3="$ROOT/.worktrees/v65-refwt-r3"   # 표준 경로(<접두><키>[-rN])
echo .worktree-info.json >> "$ROOT/.git/info/exclude"
mkwt() {  # mkwt <경로> <가지> <info 가지> [기준 커밋] — 표준 경로 워크트리 1개(가지·info 따로)
  git -C "$ROOT" worktree remove --force "$1" >/dev/null 2>&1; rm -rf "$1"; git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -D "$2" >/dev/null 2>&1
  git -C "$ROOT" worktree add -q -b "$2" "$1" "${4:-$SET}"
  printf '{"branch":"%s","created_at":"2026-11-14"}\n' "$3" > "$1/.worktree-info.json"
  find "$1" -type f -not -path '*/.git/*' -exec touch -t 202001010101 {} + 2>/dev/null
}
clean_std() { local w; for w in "$SW" "$SW2" "$SW3"; do git -C "$ROOT" worktree remove --force "$w" >/dev/null 2>&1; rm -rf "$w"; done; git -C "$ROOT" worktree prune; }
fresh() { setup; clean_std; land_main; }   # 착지 PR(#363 head=세트) · 표준 워크트리 0
alive_at() { printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$1" > "$T/cwd"; }
untouched_sw() { untouched "$1"; [ -d "$SW" ] && ok "  └ 워크트리 그대로" || bad "$1: 워크트리 사라짐"; }
cbase() { CLOSE_BIN="$T/basebin/ft-nano-close.sh" close "$@"; }

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

echo "== N1 표준 경로 + 가지 nano/refwt-fix(info = 원래 nano/refwt) + 세션 살아 있음 + --landed-pr → 인정 · CLOSED rc0"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "N1 rc=0" || bad "N1 rc=$rc ← ${out:0:2000}"
has "$out" "INFO 좌석 워크트리 ← pane cwd (표준 경로 · branch=nano/refwt-fix" "  └ INFO 좌석 워크트리 ← pane cwd"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 착지 판정 통과"
closed_ok "N1"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(cbase --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "후보도 0개" "  └ 기준판 Red: 같은 입력 REJECT(«후보 0») = N1 이 고치는 자리" || bad "기준판 Red 아님 rc=$rc ← ${out:0:600}"

echo "== N1b info == 체크아웃 가지(nano/refwt-fix · r599 꼴) → 인정"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt-fix; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "N1b rc=0" || bad "N1b rc=$rc ← ${out:0:1500}"

echo "== N1c HEAD ≠ PR head 이지만 트리 같음(메시지만 고친 커밋 · squash 꼴) → 인정"
fresh; c="$(git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$SET^{tree}" -p "$SET" -m reword)"
mkwt "$SW" nano/refwt-fix nano/refwt "$c"; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "N1c rc=0(트리 같음)" || bad "N1c rc=$rc ← ${out:0:1500}"

echo "== N2 N1 + HEAD 에 미착지 코드 커밋 1개(세트·PR head 는 옛 커밋) → REJECT «미착지 커밋» · 부작용 0"
n2() { fresh; mkwt "$SW" nano/refwt-fix nano/refwt; echo y > "$SW/web/b.txt"; git -C "$SW" add web/b.txt; git -C "$SW" -c user.email=t@t -c user.name=t commit -q -m "미착지"; touch -t 202001010101 "$SW/web/b.txt"; alive_at "$SW"; }
n2; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "미착지 커밋 1개" "N2 미착지 → REJECT" || bad "N2 rc=$rc ← ${out:0:900}"
untouched_sw "N2"

echo "== N3a pane cwd 가 표준 경로 밖(v65-refwt-cfg · nano/*) · 표준 경로엔 가지 바꾼 워크트리 → REJECT(cwd ≠ 후보)"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$NW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "pane cwd 최상위" "N3a 경로 밖 cwd → REJECT" || bad "N3a rc=$rc ← ${out:0:900}"
untouched_sw "N3a"
echo "== N3b 경로 밖 cwd + 따로 표준 후보(nano/refwt-r3) → 지금 resolver 동작(② 후퇴)과 같음"
fresh; mkwt "$SW3" nano/refwt-r3 nano/refwt-r3; alive_at "$NW"; out="$(close --landed-pr 363)"; rc=$?
fresh; mkwt "$SW3" nano/refwt-r3 nano/refwt-r3; alive_at "$NW"; bout="$(cbase --landed-pr 363)"; brc=$?
[ "$rc" -eq "$brc" ] && ok "N3b rc=$rc == 기준판 rc" || bad "N3b rc=$rc ≠ 기준판 $brc ← ${out:0:600}"

echo "== N4 표준 경로 + 가지 nano/zzz · 살아 있는 같은 팀 좌석 byz-ops-nano-zzz#0 → REJECT"
fresh; mkwt "$SW" nano/zzz nano/zzz; alive_at "$SW"; echo 'byz-ops-nano-zzz#0' > "$T/sessions"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "살아 있는 좌석 byz-ops-nano-zzz#0" "N4 남의 좌석 → REJECT" || bad "N4 rc=$rc ← ${out:0:900}"
untouched_sw "N4"

echo "== N5 info 가지(nano/other) ≠ 체크아웃 가지(nano/refwt-fix) · 좌석 가지도 아님 → REJECT"
fresh; mkwt "$SW" nano/refwt-fix nano/other; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "후보 0개" "N5 info 불일치 → REJECT" || bad "N5 rc=$rc ← ${out:0:900}"
untouched_sw "N5"

echo "== N6 --landed-pr + --wt + --branch → usage 2(지금 그대로)"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(close --landed-pr 363 --wt "$SW" --branch nano/refwt-fix)"; rc=$?
[ "$rc" -eq 2 ] && ok "N6 usage 2" || bad "N6 rc=$rc ← ${out:0:400}"

echo "== N7 가지 nano/B · 살아 있는 다른 팀 좌석 byz-ccu-nano-B#0 → REJECT(팀 접두 무관)"
fresh; mkwt "$SW" nano/B nano/B; alive_at "$SW"; echo 'byz-ccu-nano-B#0' > "$T/sessions"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "byz-ccu-nano-B#0" "N7 다른 팀 좌석 → REJECT" || bad "N7 rc=$rc ← ${out:0:900}"
untouched_sw "N7"

echo "== N8 가지 nano/B-r2-fix · 살아 있는 byz-ops-nano-B-r2-fix#0 → REJECT(키를 B 로 자르지 않음)"
n8() { fresh; mkwt "$SW" nano/B-r2-fix nano/B-r2-fix; alive_at "$SW"; echo 'byz-ops-nano-B-r2-fix#0' > "$T/sessions"; }
n8; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "byz-ops-nano-B-r2-fix#0" "N8 꼬리 붙은 키 → REJECT" || bad "N8 rc=$rc ← ${out:0:900}"
untouched_sw "N8"
echo "== N8b 가지 nano/refwt-r3(주인 = 닫는 좌석 자신) → 인정"
fresh; mkwt "$SW3" nano/refwt-r3 nano/refwt-r3; alive_at "$SW3"; echo "$SEAT" > "$T/sessions"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "N8b rc=0" || bad "N8b rc=$rc ← ${out:0:1200}"

echo "== N9 표준 경로 후보 2개(v65-refwt · v65-refwt-r2 둘 다 가지 바꿈) → REJECT(모호)"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; mkwt "$SW2" nano/refwt-alt nano/refwt-alt; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "후보 2개" "N9 모호 → REJECT" || bad "N9 rc=$rc ← ${out:0:900}"
untouched_sw "N9"

echo "== N10a --landed-pr 없는 일반 close(가지 바꾼 표준 워크트리 · 세션 살아 있음) → 기준판과 같은 REJECT «후보 0»"
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(close)"; rc=$?
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; bout="$(cbase)"; brc=$?
[ "$rc" -eq "$brc" ] && has "$out" "후보도 0개" "N10a 일반 close = 기준판(rc=$rc)" || bad "N10a rc=$rc 기준판 $brc ← ${out:0:600}"
echo "== N10b 기존 --landed-pr --wt 힌트 호출(r1737 꼴) → 기준판과 같은 결과"
fresh; alive; out="$(close --landed-pr 363 --wt "$NW")"; rc=$?
fresh; alive; bout="$(cbase --landed-pr 363 --wt "$NW")"; brc=$?
[ "$rc" -eq "$brc" ] && [ "$rc" -eq 0 ] && ok "N10b rc=$rc == 기준판" || bad "N10b rc=$rc 기준판 $brc ← ${out:0:600}"

echo "== N11 체크아웃 feat/x(nano/ 밖) · info = nano/refwt(좌석 자신) → 인정(r1486 보강)"
fresh; mkwt "$SW" feat/x nano/refwt; alive_at "$SW"; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "N11 rc=0" || bad "N11 rc=$rc ← ${out:0:1200}"

echo "== 변이 M1 «설계 1 삭제» → N1 이 잡는다"
mutant 'then _resolve_landed_cwd; fi   # r1417-mut:cwd' 'then :; fi'
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -ne 0 ] && ok "M1 FAIL(REJECT) = N1 이 잡는다" || bad "M1 안 먹음"
echo "== 변이 M2 «HEAD 착지 검사 삭제» → N2 가 잡는다"
mutant 'if [ "$_lp_cwd_seat" = 1 ]; then _lp_cwd_head_gate || bad+=("$_lp_cwd_head_err"); fi' ':'
n2; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "M2 FAIL(닫힘) = N2 가 잡는다" || bad "M2 안 먹음 rc=$rc ← ${out:0:1500}"
echo "== 변이 M3 «소유 검사를 닫는 팀 접두로 좁힘» → N7 이 잡는다"
mutant '    i = seat_info(s)' '    i = None'
fresh; mkwt "$SW" nano/B nano/B; alive_at "$SW"; echo 'byz-ccu-nano-B#0' > "$T/sessions"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "M3 FAIL(닫힘) = N7 이 잡는다" || bad "M3 안 먹음 rc=$rc"
echo "== 변이 M4 «키를 \${key%-r[0-9]*} 로 자름» → N8 이 잡는다"
mutant 'okey="${br#nano/}"; keys="$okey"; [[ "$okey" =~ ^(.*)-r[0-9]+$ ]] && keys="$keys ${BASH_REMATCH[1]}"' 'okey="${br#nano/}"; okey="${okey%-r[0-9]*}"; keys="$okey"'
n8; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "M4 FAIL(닫힘) = N8 이 잡는다" || bad "M4 안 먹음 rc=$rc"
echo "== 변이 M5 «info 대조 삭제» → N5 가 잡는다"
mutant 'nano/?*) [ "$txt" = "$br" ] || continue;;' 'nano/?*) ;;'
fresh; mkwt "$SW" nano/refwt-fix nano/other; alive_at "$SW"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "M5 FAIL(닫힘) = N5 가 잡는다" || bad "M5 안 먹음 rc=$rc"
echo "== 변이 M6 «설계 1 을 공용 resolver 에(--landed-pr 조건 삭제)» → N10a 가 잡는다"
mutant '[ "$HAVE_LPR" -eq 1 ] && [ "$HAVE_NWT" -eq 0 ]; then _resolve_landed_cwd' '[ "$HAVE_NWT" -eq 0 ]; then _resolve_landed_cwd'
fresh; mkwt "$SW" nano/refwt-fix nano/refwt; alive_at "$SW"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close)"; rc=$?
case "$out" in *"후보도 0개"*) bad "M6 안 먹음";; *) ok "M6 FAIL(«후보 0» 사라짐 rc=$rc) = N10a 가 잡는다";; esac
echo "== 변이 M7 «REJECT 판정을 kill 뒤로» → N2(부작용) 가 잡는다"
mutant '_lp_cwd_head_gate || bad+=("$_lp_cwd_head_err")' '_lp_cwd_head_gate || _m7="$_lp_cwd_head_err"' \
  'tmux kill-session -t "$PANE" || { echo "FAIL $SEAT — kill-session 실패(세션 잔존 · 태그는 해제됨)"; exit 1; }' 'tmux kill-session -t "$PANE" || exit 1; [ -z "${_m7:-}" ] || { echo "REJECT $SEAT"; exit 1; }'
n2; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ -n "$(cat "$T/tlog")" ] && ok "M7 FAIL(REJECT 인데 kill 흔적 rc=$rc) = N2 부작용 검사가 잡는다" || bad "M7 안 먹음 rc=$rc"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
