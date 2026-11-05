#!/usr/bin/env bash
# test_press_gate_step1_cache_moving_main_r1411.sh — r1411 press 게이트 ① 캐시 «TTL 스냅숏»(planner 판정 4127 · 카드 3판 T1~T7)
#   T1 판정 OK 캐시 → 기준 줄기 문서 커밋 1개 앞으로 → 같은 입력 재실행 = «① 캐시 재사용» · 줄에 «기준 줄기 a → b»(묵은 정도가 보인다)
#   T2 나노 2석 선언 base = main(로컬 ref) 1 · origin/main 1 · 두 ref 다 앞으로 → 재사용
#   T3 판정 UNLANDED 캐시 → 기준 줄기 앞으로 → 재사용(막힘 유지)
#   T4 나노 HEAD 커밋 1개 → 다시 돈다 · T5 선언 base = 다른 줄기(feat/x) 그 줄기 앞으로 → 다시 돈다
#   T6 hook 끝까지: 손 게이트(가짜 ① 지연 2초 주입) PASS → 기준 줄기 앞으로 → press-runner-gate.sh 경유 = allow(캐시 재사용 · ① git 호출 0 · 게이트 로그에 «① 캐시 재사용 … 기준 줄기 a → b»)
#   T7 TTL 지남(FT_PRESS_GATE_CACHE_SEC=2 · 3초 뒤) → 다시 돈다
#   변이 1 same-trunk 치환 삭제 → T2·T6 FAIL · 변이 2 feat 를 키에 되돌림 → T1·T3 FAIL · 변이 3 재사용 줄의 기준 줄기 표시 삭제 → T1 FAIL
#   실 리포·실 tmux·실 Redis·네트워크 0 · 자기 재호출 0 · 칸별 timeout 60(하드 룰 22) · 지연·TTL 3초 말고 고정 sleep 0
set -uo pipefail
[ -z "${FT_R1411_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1411_REENTRY=1
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
HOOK="$LIBDIR/../kit/fable-team/templates/hooks/press-runner-gate.sh"
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
bash -n "$HOOK" && ok "bash -n hook" || bad "bash -n hook"

infow(){ printf '{"base":"%s","base_sha":"%s"}\n' "$2" "$3" > "$1/.worktree-info.json"; }
ngstep1(){ grep -cE ' (log|diff|cat-file) ' "$CASE/gitlog" | tr -d ' '; }   # ① 본문이 부르는 git 꼴(키 셈용 merge-base 는 빼고 센다)
mksplit(){ # $1 = 칸 이름 · $2·$3 = 나노 두 석의 선언 base — 러너는 «detached»(기준 줄기 ref 가 움직여도 러너 HEAD 는 그대로)
  mkcase "$1" || return 1
  g "$R" worktree add -q -b nano/j "$R/.worktrees/v65-j" main 2>/dev/null || return 1
  printf '{"byz-v65-nano-k#0":{"role":"nano"},"byz-v65-nano-j#0":{"role":"nano"}}\n' > "$R/.fable-team/seats.json"
  printf 'byz-v65-nano-k#0\nbyz-v65-nano-j#0\n' > "$CASE/sessions"
  local sha; sha="$(g "$R" rev-parse main)"
  infow "$R/.worktrees/v65-k" "$2" "$sha"
  infow "$R/.worktrees/v65-j" "$3" "$sha"
  g "$R" worktree add -q --detach "$CASE/run" main 2>/dev/null || return 1
  GWT="$CASE/run"
}
detach_runner(){ g "$R" worktree add -q --detach "$CASE/run" main 2>/dev/null || return 1; GWT="$CASE/run"; }
seats2(){ printf '{"byz-v65-nano-k#0":{"role":"nano"},"byz-v65-nano-j#0":{"role":"nano"}}\n' > "$R/.fable-team/seats.json"
  printf 'byz-v65-nano-k#0\nbyz-v65-nano-j#0\n' > "$CASE/sessions"; }
advance_trunk(){ # origin/main 문서 커밋 1개 push + fetch + 로컬 main ref 를 같은 값으로(러너 HEAD 는 detached 라 안 흔들린다)
  git clone -q -b main "$CASE/origin.git" "$CASE/other" 2>/dev/null || return 1
  cm "$CASE/other" docs/o.md o || return 1
  g "$CASE/other" push -q origin main 2>/dev/null || return 1
  g "$R" fetch -q origin || return 1
  g "$R" update-ref refs/heads/main "$(g "$R" rev-parse origin/main)"
}
slowgate(){ # $1 = 이름 · $2 = 기준 게이트(진짜 또는 변이 사본) → ① 본문에 3초 지연을 넣은 사본(형제 스크립트는 심링크 · 진짜 게이트와 같은 자리 꼴) · ① 끝에서 멈춘다(② 이후는 이 카드 범위 밖)
  local d base="$2"; d="$(mktemp -d "$T/slow-$1-XXXXXX")" || return 1
  ln -s "$BIN"/* "$d"/ && rm -f "$d/ft-press-gate.sh" || return 1
  sed -e 's/^_step1_run(){.*/&\n  sleep 2/' "$base" > "$d/ft-press-gate.sh" || return 1
  if ! grep -q 'S1STATE' "$d/ft-press-gate.sh"; then   # 변이 사본(이미 ① 끝 정지 주입됨)은 sleep 만 더한다
    sed 's/^_tick B$/_tick B; echo "S1STATE FAIL=$FAIL UNLANDED=$UNLANDED"; exit 0/' "$d/ft-press-gate.sh" > "$d/g.tmp" && mv "$d/g.tmp" "$d/ft-press-gate.sh" || return 1
  fi
  grep -q '^  sleep 2$' "$d/ft-press-gate.sh" && grep -q 'S1STATE' "$d/ft-press-gate.sh" || { echo "주입 안 됨" >&2; return 1; }
  chmod +x "$d/ft-press-gate.sh"
  printf '%s' "$d/ft-press-gate.sh"
}
wrapgate(){ # $1 = 이름 · $2 = 게이트 · $3 = 로그 → 게이트 출력을 파일로 남기는 얇은 껍데기(훅은 rc 만 본다)
  local w="$T/wrap-$1.sh"
  printf '%s\n' '#!/usr/bin/env bash' "bash \"$2\" > \"$3\" 2>&1" > "$w" && chmod +x "$w" && printf '%s' "$w"
}
hookrun(){ # $@ = 훅 env 추가 대입 → 훅 출력(훅이 게이트를 부른다 · 입력 = T6 이 만든 JSON)
  printf '%s' "$T6JSON" | env "$@" FT_PRESS_RUNNER_GATE_TIMEOUT=10 FT_PRESS_RUNNER_GATE_LOG="$CASE/hook.log" FT_PRESS_GATE_BIN="$T6BIN" \
    FT_PRESS_WT="$CASE/run" FT_PRESS_ROOT="$R" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" TMUX_PANE=%1 \
    SESS_FILE="$CASE/sessions" GITLOG="$CASE/gitlog" REALGIT="$REALGIT" CURL_CODE=000 PATH="$FB:$PATH" bash "$HOOK" 2>&1
}

case_t1(){ # 판정 OK 재사용 + 묵은 정도가 출력에 보인다
  mksplit t1 main origin/main || return 1
  runbin "$1"; [ "$(ncache)" = "1" ] || return 1; local n1; n1="$(ngstep1)"; [ "$n1" -gt 0 ] || return 1
  advance_trunk || return 1
  runbin "$1"; hit && [ "$(ngstep1)" = "0" ] && has "기준 줄기 " && has " → " && has "S1STATE FAIL=0 UNLANDED=0"; }
case_t2(){ # 두 ref(로컬 main · origin/main) 다 앞으로 → 재사용(same-trunk)
  case_t1 "$1"; }
case_t3(){ # 판정 UNLANDED 캐시도 기준 줄기 움직임에 흔들리지 않는다(막힘 유지)
  mksplit t3 main origin/main || return 1
  work 1 || return 1
  runbin "$1"; has "S1STATE FAIL=1 UNLANDED=1" || return 1
  advance_trunk || return 1
  runbin "$1"; hit && has "✗ 미랜딩 제품 커밋 1 — v65-k" && has "S1STATE FAIL=1 UNLANDED=1"; }
case_t4(){ # 나노 HEAD 커밋 → 다시 돈다
  mksplit t4 main origin/main || return 1
  runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  work 1 || return 1
  runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_t5(){ # 다른 줄기(feat/x) 선언 · 그 줄기가 앞으로 → 다시 돈다
  mkcase t5 || return 1
  g "$R" worktree add -q -b feat/x "$R/.worktrees/v65-j" main 2>/dev/null || return 1
  seats2; detach_runner || return 1
  infow "$R/.worktrees/v65-j" feat/x "$(g "$R" rev-parse main)"
  runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  cm "$R/.worktrees/v65-j" worker/x1.py "[fix] x" || return 1
  runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_t6(){ # hook 경유 — 손 게이트가 남긴 ① 을 상한 10초 안에 다시 쓴다(allow)
  mksplit t6 main origin/main || return 1
  T6GATE="$(slowgate t6 "$1")" || return 1
  T6LOG="$CASE/gate.log"; T6BIN="$(wrapgate t6 "$T6GATE" "$T6LOG")" || return 1
  T6JSON="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 tests/e2e/realtime_multi_e2e.py\"},\"cwd\":\"$R\"}"
  runbin "$T6GATE"; [ "$(ncache)" = "1" ] || return 1        # 손 게이트(① 3초 지연) PASS → 캐시 1
  advance_trunk || return 1
  : > "$CASE/gitlog"; : > "$T6LOG"; OUT="$(hookrun)"
  [ -z "$OUT" ] && [ "$(ngstep1)" = "0" ] || { echo "hook allow 아님: ${OUT:0:300}" >&2; return 1; }
  grep -qF '① 캐시 재사용' "$T6LOG" && grep -qF '기준 줄기 ' "$T6LOG" && grep -qF ' → ' "$T6LOG"; }
case_t7(){ # TTL 지남 → 다시 돈다(FT_PRESS_GATE_CACHE_SEC=2 · 3초)
  mkcase t7 || return 1; detach_runner || return 1
  GENV="FT_PRESS_GATE_CACHE_SEC=2"; runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  sleep 3
  runbin "$1"; ! hit && [ "$(ncache)" = "1" ] && [ "$(ngstep1)" -gt 0 ]; }

P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
run_cases "$P" t1 t2 t3 t4 t5 t7
[ -z "$BAD" ] && ok "T1·T2·T3·T4·T5·T7 통과" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -12 | sed 's/^/    /'; }
run_cases "$GATE" t6
[ -z "$BAD" ] && ok "T6 통과(손 게이트 → 기준 줄기 이동 → hook allow · 게이트 로그에 캐시 재사용 줄)" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -14 | sed 's/^/    /'; }
MUT1='s/bres="same-trunk" ;;/bres="$(git -C "$w" rev-parse --verify -q "$decl^{commit}")" ;;/'
MUT2='s/^  p="trunk=\$FEAT|/  p="trunk=$FEAT,$S1_FEAT_NOW|/'
MUT3='s/ · \$_fmsg)/)/'
mut(){ # 이름 · sed식 · 칸 · [대조 기준판=P] → 변이 사본이 그 칸을 FAIL 해야 통과 · 대조판=none 이면 대조 생략(위에서 같은 입력으로 이미 통과한 경우)
  local name="$1" re="$2" c="$3" subj="${4:-$P}"
  if [ "$subj" != "none" ]; then
    run_cases "$subj" "$c"; [ -z "$BAD" ] || { bad "$name 대조 실패:$BAD"; printf '%s\n' "${LAST:-}" | tail -8 | sed 's/^/    /'; return; }
  fi
  local m; m="$(mkprobe "$GATE" "$re")" || { bad "$name 사본"; return; }
  run_cases "$m" "$c"
  [ "$BAD" = " $c" ] && ok "$name → $c FAIL" || bad "$name 이 $c 를 못 잡음(${BAD:- 통과})"
}
mut "변이 1(same-trunk 치환 삭제)" "$MUT1" t2 "none"   # 대조 = 위 run_cases "$P" t2
mut "변이 1(same-trunk 치환 삭제)" "$MUT1" t6 "none"   # 대조 = 위 run_cases "$GATE" t6
mut "변이 2(feat 를 키에 되돌림)" "$MUT2" t1 "none"      # 대조 = 위 T1
mut "변이 2(feat 를 키에 되돌림)" "$MUT2" t3 "none"      # 대조 = 위 T3
mut "변이 3(재사용 줄의 기준 줄기 표시 삭제)" "$MUT3" t1 "none"   # 대조 = 위 T1
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
