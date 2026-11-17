#!/usr/bin/env bash
# test_wt_sweep_replan_no_wt_none_r2179.sh — 카드 r2179: 옛 판 계획을 다시 만들 때 워크트리 폴더가 이미 없으면 «정리할 것 없음» 으로 닫는다.
#   ①생성기 --replan(WT 없음) → `NONE --replan: WT 없음(` 1줄 · rc 0 · 새 계획 0 ②sweep → 원장 그 좌석 행 wt=none · 다른 행 바이트 불변
#   ③원장 파일 없음 · ③-b 그 좌석 닫힘 행 없음 → 그래도 none · .done 끝줄 «원장 표식 못 함» ④sweep 출력 OK wt=none · .done(# none(replan):) · .stale/.replanned 0 · rc 0
#   ⑤가짜 mbox 호출 0 · critical-pending 0 ⑥한 pass 옛 계획 3개(WT 없음 2 + 있음 1) → none 2 · REPLAN 1 · cleaned/none 3 · stale 0 · 크리티컬 0
#   ⑦WT 없음 + 좌석 불일치 → STALE «좌석 불일치» · 원장 불변 ⑦-b WT 없음 + NAMED_BR → STALE «사람 경로»
#   변이 M1~M6(사본에서만 · 변이마다 원본으로 같은 사례 1회 더). 기준판 대조 = WT_TEST_BASE_SRC=<고치기 전 bin>(① ② ③ ③-b ④ ⑤ ⑥ FAIL · ⑦ ⑦-b PASS).
# 임시 git 리포 + 임시 워크트리 + 가짜 tmux·lsof·du·baton·mbox 만 — 실 리포·워크트리·mbox·tmux 0 · 외부 호출 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CRITICAL_OFF FT_ROOT FT_MBOX_DIR
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../kit/fable-team/bin}"; BASE="${WT_TEST_BASE_SRC:-}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T_START=$SECONDS; STEPS=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
step() { STEPS="$STEPS $1=$((SECONDS - ${_S0:-$T_START}))s"; _S0=$SECONDS; }
eqn() { [ "$1" = "$2" ] || { echo "    $3 got=[${1:0:300}] want=[${2:0:300}]" >&2; return 1; }; }
inc() { case "$1" in *"$2"*) return 0;; esac; echo "    $3 없음: «$2» ← ${1:0:300}" >&2; return 1; }
exc() { case "$1" in *"$2"*) echo "    $3 있으면 안 됨: «$2»" >&2; return 1;; esac; return 0; }
isf() { [ -f "$1" ] && echo yes || echo no; }

mkbin() { mkdir -p "$2"; for f in ft-nano-close.sh ft-wt-sweep.sh ft-hil.sh ft_teamset.py ft_team_lib.py ft-critical-notify.sh ft-harness-root.sh ft-block-lib.sh; do cp "$1/$f" "$2/"; done; }
mkbin "$SRC" "$T/bin"; [ -z "$BASE" ] || mkbin "$BASE" "$T/base"
bash -n "$T/bin/ft-wt-sweep.sh" && bash -n "$T/bin/ft-nano-close.sh" && ok "bash -n 2종" || bad "bash -n"
mkdir -p "$T/fake"; : > "$T/sessions"
printf '#!/usr/bin/env bash\ncase "$1" in ls) if [ -s "$FAKE_SESSIONS" ]; then cat "$FAKE_SESSIONS"; else echo "no server running on /tmp/fake"; exit 1; fi;; *) exit 1;; esac\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fake/lsof"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" 12 "$2"\n' > "$T/fake/du"
# 가짜 mbox — 호출마다 MCALLS 1줄(발신 시도 수)
printf '#!/usr/bin/env bash\necho x >> "$MCALLS"\necho "QUEUED seq=1 to=$2"\n' > "$T/mbox.sh"
REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
printf '.worktree-info.json\n' > "$REPO/.gitignore"
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
GIT add .gitignore && GIT commit -q -m init
printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"
chmod +x "$T/fake/"* "$T/mbox.sh"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/comm"; PEND="$ROOT/.fable-team/state/critical-pending.jsonl"
printf '{"_master":"byz-harness-master#1","_desk":"byz-planner-desk-pi#9"}\n' > "$ROOT/.fable-team/seats-planner.json"

K=0; D=""; LEDGER=""
fresh() { K=$((K+1)); D="$T/c$K/wt-clean"; LEDGER="$T/c$K/ledger.md"; mkdir -p "$D"; : > "$T/mcalls"; rm -rf "$ROOT/.fable-team/state"; }
# oldplan <좌석(파일 이름)> <키> <WT> [굽힌 SEAT] [NAMED_BR] — 옛 판(plan-ver 0000) 계획
oldplan() {
  { printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 2026-11-12 17:00 에 생성. (옛 판)\n# plan-ver: %s\n' 0000000000000000000000000000000000000000
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q; LEDGER=%q; PLAN=%q; FT_NANO_WIP=%q; NAMED_BR=%q; SWEEPER=%q; GEN=%q; PLANVER=%q; PLAN_ONLY=%q; LANDCHK=%q; MAINREF=%q; ROOTR=%q\n' \
      "${4:-$1}" "$2" "$3" byz-harness-nano- "$LEDGER" "$D/$1.sh" 0 "${5:-}" /old/ft-wt-sweep.sh /old/ft-nano-close.sh 0000 0 /old/ft-landed-check.sh '' "$REPO"
    printf 'echo "OLD BODY RAN"; echo cleaned\n'; } > "$D/$1.sh"
}
mkwt() { GIT worktree add -q "$REPO/.worktrees/$1" -b "$2"; printf '{"branch":"%s"}\n' "$2" > "$REPO/.worktrees/$1/.worktree-info.json"; }
envs() { echo HOME="$HOME" PATH="$T/fake:$PATH" BATON_BIN="$T/fake/baton" FT_WT_CLEAN_DIR="$D" FT_WT_PLAN_TIMEOUT=20 FT_WT_RESUME_GRACE=0 \
  FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" FAKE_SESSIONS="$T/sessions" HIL_DIR="$T/hil" HIL_CLIP=0 \
  FT_MBOX="$T/mbox.sh" FT_MBOX_DIR="$ROOT/.fable-team/comm" MCALLS="$T/mcalls" FT_ALLOW_TRACKED_BIN=1; }
OUT=""; RC=0
swp() { OUT="$(cd "$REPO" && env -i $(envs) bash "$1/ft-wt-sweep.sh" 2>&1)"; RC=$?; }
ncall() { grep -c . "$T/mcalls"; }
npend() { local n; n="$(grep -c . "$PEND" 2>/dev/null)"; echo "${n:-0}"; }
S='byz-harness-nano-a1#0'; NOWT="$T/gone/v65-a1"
L_A='- `byz-harness-nano-a1#0` 닫힘(ft-nano-close) · wt=skipped:cwd 보유 프로세스 3개 — tee,tail'
L_B='- `byz-harness-nano-zz#0` 닫힘(ft-nano-close) · wt=planned'
L_A1='- `byz-harness-nano-a1#0` 닫힘(ft-nano-close) · wt=planned (앞 행)'

c1() { fresh; oldplan "$S" a1 "$NOWT"; local o rc
  o="$(cd "$T" && env -i $(envs) bash "$1/ft-nano-close.sh" "$S" --replan "$D/$S.sh" 2>/dev/null)"; rc=$?
  eqn "$(printf '%s\n' "$o" | grep -c '^NONE --replan: WT 없음(')" 1 "① NONE 1줄" || return 1
  eqn "$rc" 0 "① rc" && eqn "$(ls "$D" | tr '\n' ' ')" "$S.sh " "① 계획 폴더 새 파일 0"; }
c2() { fresh; printf '%s\n%s\n%s\n' "$L_A1" "$L_B" "$L_A" > "$LEDGER"; oldplan "$S" a1 "$NOWT"; swp "$1"
  eqn "$(cat "$LEDGER")" "$L_A1"$'\n'"$L_B"$'\n''- `byz-harness-nano-a1#0` 닫힘(ft-nano-close) · wt=none' "② 원장(마지막 그 좌석 행만 none · 다른 행 바이트 불변)"; }
c3() { fresh; oldplan "$S" a1 "$NOWT"; swp "$1"
  inc "$OUT" "OK   $S wt=none" "③ OK none" && eqn "$(ncall)" 0 "③ 발신" && inc "$(tail -1 "$D/$S.sh.done" 2>/dev/null)" "원장 표식 못 함" "③ .done 끝줄"; }
c3b() { fresh; printf '%s\n' "$L_B" > "$LEDGER"; oldplan "$S" a1 "$NOWT"; swp "$1"
  inc "$OUT" "OK   $S wt=none" "③-b OK none" && eqn "$(ncall)" 0 "③-b 발신" && inc "$(tail -1 "$D/$S.sh.done" 2>/dev/null)" "원장 표식 못 함" "③-b .done 끝줄" \
    && eqn "$(cat "$LEDGER")" "$L_B" "③-b 원장 불변"; }
# ③-c(DA HOLD1 R1) 긴 정상 WT 경로(구성요소 100자 미만 · 전체 300자 넘게) + 그 좌석 닫힘 행 없음 → .done 끝줄에 NONE 줄 전체(«원장 표식 못 함» 까지)
LONGWT="$T/gone/projects-$(printf 'a%.0s' $(seq 80))/nested-$(printf 'b%.0s' $(seq 80))/.worktrees-$(printf 'c%.0s' $(seq 80))/nano-review"
c3c() { fresh; printf '%s\n' "$L_B" > "$LEDGER"; oldplan "$S" a1 "$LONGWT"; swp "$1"
  inc "$OUT" "OK   $S wt=none" "③-c OK none" && inc "$(tail -1 "$D/$S.sh.done" 2>/dev/null)" "WT 없음($LONGWT) — 정리할 것 없음 (원장 표식 못 함: $S 닫힘 행 없음)" "③-c .done 끝줄 = NONE 줄 전체"; }
c4() { fresh; printf '%s\n' "$L_A" > "$LEDGER"; oldplan "$S" a1 "$NOWT"; swp "$1"
  inc "$OUT" "OK   $S wt=none — 옛 판 계획 · WT 없음" "④ OK 줄" && exc "$OUT" "STALE" "④ STALE 줄" && eqn "$RC" 0 "④ sweep rc" \
    && inc "$(tail -1 "$D/$S.sh.done" 2>/dev/null)" "# none(replan): NONE --replan:" "④ .done 끝줄" \
    && eqn "$(isf "$D/$S.sh.stale")$(isf "$D/$S.sh.replanned")$(isf "$D/$S.sh")" nonono "④ .stale·.replanned·.sh 남김 0"; }
# ⑤ + V5 «rc 0 = 해결 길» — 그 좌석의 앞 열쇠(예전 거절로 나간 미해결 1줄)를 심어 두고 닫히는지 본다(M6 rc 1 은 발신 0 이어도 열쇠가 남는다)
c5() { fresh; printf '%s\n' "$L_A" > "$LEDGER"; oldplan "$S" a1 "$NOWT"; mkdir -p "$ROOT/.fable-team/state"
  printf '{"tool":"ft-nano-close","target":"%s","event":"x:1","ts":1,"seq":1,"n":1,"first":1}\n' "$S" > "$ROOT/.fable-team/state/critical-sent.jsonl"; swp "$1"
  eqn "$(ncall)/$(npend)" 0/0 "⑤ mbox 호출/pending" && eqn "$(grep -c '"resolved"' "$ROOT/.fable-team/state/critical-sent.jsonl")" 1 "⑤ 앞 열쇠 닫힘(rc 0 해결 길)"; }
c6() { fresh; local w="v65-m$K"; mkwt "$w" "nano/m$K"
  printf '%s\n%s\n%s\n' "$L_A" '- `byz-harness-nano-a2#0` 닫힘(ft-nano-close) · wt=planned' "- \`byz-harness-nano-m$K#0\` 닫힘(ft-nano-close) · wt=planned" > "$LEDGER"
  oldplan "$S" a1 "$NOWT"; oldplan 'byz-harness-nano-a2#0' a2 "$T/gone/v65-a2"; oldplan "byz-harness-nano-m$K#0" "m$K" "$REPO/.worktrees/$w"; swp "$1"
  eqn "$(printf '%s\n' "$OUT" | grep -c '^OK   .* wt=none — 옛 판 계획')" 2 "⑥ none 2" && inc "$OUT" "REPLAN byz-harness-nano-m$K#0" "⑥ REPLAN 1" \
    && inc "$OUT" "OK   byz-harness-nano-m$K#0 wt=cleaned" "⑥ 뒤이어 정리" && inc "$OUT" "cleaned/none 3" "⑥ 요약" && exc "$OUT" "STALE" "⑥ stale" \
    && eqn "$(ls "$D" | grep -c '\.stale$')/$(ncall)" 0/0 "⑥ .stale/발신"; }
c7() { fresh; printf '%s\n' "$L_A" > "$LEDGER"; oldplan 'byz-harness-nano-other#0' a1 "$NOWT" "$S"; swp "$1"
  inc "$OUT" "STALE byz-harness-nano-other#0" "⑦ STALE" && inc "$OUT" "좌석 불일치" "⑦ 사유" && eqn "$(isf "$D/byz-harness-nano-other#0.sh.stale")" yes "⑦ .stale" \
    && eqn "$(cat "$LEDGER")" "$L_A" "⑦ 원장 불변"; }
c7b() { fresh; printf '%s\n' "$L_A" > "$LEDGER"; oldplan "$S" a1 "$NOWT" "" feat/x; swp "$1"
  inc "$OUT" "STALE $S" "⑦-b STALE" && inc "$OUT" "사람 경로" "⑦-b 사유" && eqn "$(cat "$LEDGER")" "$L_A" "⑦-b 원장 불변"; }

tc() { if "$2" "$T/bin"; then ok "$1"; else bad "$1"; fi; }
basefail() { [ -n "$BASE" ] || { echo "SKIP $1 기준판 대조(WT_TEST_BASE_SRC 없음)"; return 0; }
  if "$2" "$T/base" >/dev/null 2>&1; then bad "$1 — 기준판에서 PASS(못 가름)"; else ok "$1 기준판 FAIL(정상 Red)"; fi; }
basepass() { [ -n "$BASE" ] || return 0; if "$2" "$T/base" >/dev/null 2>&1; then ok "$1 기준판 PASS(불변)"; else bad "$1 — 기준판에서 FAIL"; fi; }
tc "① 생성기 --replan WT 없음 → NONE rc 0 · 새 계획 0" c1; basefail ① c1
tc "② 원장 그 좌석 마지막 행 wt=none · 다른 행 불변" c2; basefail ② c2
tc "③ 원장 파일 없음 → none · .done 끝줄 «원장 표식 못 함» · 발신 0" c3; basefail ③ c3
tc "③-b 그 좌석 닫힘 행 없음 → 같은 결과" c3b; basefail ③-b c3b
tc "③-c 긴 WT 경로 + 행 없음 → .done 끝줄에 NONE 줄 전체(자름 0)" c3c; basefail ③-c c3c
tc "④ sweep OK wt=none · .done(# none(replan):) · .stale·.replanned 0 · rc 0" c4; basefail ④ c4
tc "⑤ mbox 호출 0 · critical-pending 0" c5; basefail ⑤ c5; step ①~⑤
tc "⑥ 혼합 pass → none 2 · REPLAN 1 · cleaned/none 3 · stale 0 · 크리티컬 0" c6; basefail ⑥ c6; step ⑥
tc "⑦ WT 없음 + 좌석 불일치 → STALE · 원장 불변" c7; basepass ⑦ c7
tc "⑦-b WT 없음 + --wt/--branch 계획 → STALE «사람 경로»" c7b; basepass ⑦-b c7b; step ⑦

# 변이 — 사본 MB 의 파일 하나만 바꾼다(옛 글은 정확히 1곳) · 변이에서 FAIL + 원본에서 PASS
MB="$T/mbin"
mut() { rm -rf "$MB"; cp -R "$T/bin" "$MB"; local f="$1"; shift
  python3 - "$MB/$f" "$@" <<'PY' || { bad "변이 패턴 없음($f)"; return 1; }
import io, sys
p, pairs = sys.argv[1], sys.argv[2:]; s = io.open(p, encoding="utf-8").read()
for a, b in zip(pairs[0::2], pairs[1::2]):
    if s.count(a) != 1: sys.exit(3)
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8").write(s)
PY
}
killed() { local name="$1"; shift; local fn
  for fn in "$@"; do if "$fn" "$MB" >/dev/null 2>&1; then bad "$name — 변이가 살아남음($fn)"; return; fi; done
  for fn in "$@"; do "$fn" "$T/bin" >/dev/null 2>&1 || { bad "$name — 원본 대조 FAIL($fn)"; return; }; done
  ok "$name → $* FAIL · 원본 대조 PASS"; }
NG='[ -d "$WT" ] || { _rp_none; exit 0; }'
mut ft-nano-close.sh "$NG" '[ -d "$WT" ] || { echo "REJECT --replan: WT 없음($WT)"; exit 1; }' && killed "M1 NONE → REJECT rc 1" c1 c4 c5 c6
mut ft-wt-sweep.sh "grep -m1 '^NONE --replan:'" "grep -m1 '^NONE-X --replan:'" && killed "M2 sweep 이 NONE 을 안 읽음" c4 c6
mut ft-nano-close.sh "$NG" '' '  [ "$SEAT" = "$_rs" ] ||' "  $NG"$'\n''  [ "$SEAT" = "$_rs" ] ||' && killed "M3 WT 검사를 좌석 검사 앞으로" c7
mut ft-nano-close.sh 'if [ ! -f "$LEDGER" ]; then why=' 'if true; then why=' && killed "M4 원장 표식 지움" c2
mut ft-nano-close.sh 'echo "NONE --replan: WT 없음' '[ -z "$why" ] || { echo "REJECT --replan: 원장 표식 못 함: $why"; exit 1; }; echo "NONE --replan: WT 없음' && killed "M5 표식 실패 → REJECT" c3 c3b
mut ft-nano-close.sh "$NG" '[ -d "$WT" ] || { _rp_none; exit 1; }' && killed "M6 NONE 을 rc 1 로" c5
step 변이
echo "단계별 초: 전체=$((SECONDS - T_START))s ·$STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
