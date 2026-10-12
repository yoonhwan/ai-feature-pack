#!/usr/bin/env bash
# test_ft_wt_sweep_route_timeout.sh — ft-wt-sweep.sh 상한 처리(rc 124 정직 · 삭제 단계 초과=WAIT · pass 당 1건 · [HIL] seat=) +
#   ft-tick.sh sweep_wt 팀 라우팅([HIL] 좌석 접두 → seats-<팀>.json 의 _master · 못 찾으면 «[라우팅 실패 <팀>]» 머리).
# 모든 쓰기는 mktemp scratch 안 — 실 계획 디렉터리·실 mbox·실 baton·라이브 좌석표 0 (스텁 계획 .sh · 스텁 mbox · 스텁 seats-*.json).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
SWEEP="$ROOT/scripts/fable-team-bin/ft-wt-sweep.sh"
TICK="$ROOT/scripts/fable-team-bin/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1 (없음: $3)"; fi; }
cnt() { grep -cF -- "$2" "$1" 2>/dev/null || true; }
nfiles() { ls "$1"/$2 2>/dev/null | wc -l | tr -d ' '; }

BATON_HDR='🗄️  워크트리 정리 — Archive 자동 보관'
# sweep <디렉터리> <출력> [env...] — 격리 디렉터리의 계획만 실행(cwd 도 scratch)
#   R83: [HIL] 안내는 ft-hil.sh 가 만드는 짧은 링크 — 시험은 HIL_DIR 을 scratch 로, 클립보드 0 (실 /tmp/h<N>·pbcopy 건드리지 않는다)
mkdir -p "$TMP/hil"
sweep() { local d="$1" o="$2"; shift 2; ( cd "$TMP" && env FT_WT_CLEAN_DIR="$d" FT_WT_PLAN_TIMEOUT=1 HIL_DIR="$TMP/hil" HIL_CLIP=0 "$@" bash "$SWEEP" > "$o" 2>&1 ); }
plan() { mkdir -p "$1"; printf '%s\n' "$3" > "$1/$2.sh"; }

bash -n "$SWEEP" && ok "ft-wt-sweep bash -n" || bad "ft-wt-sweep bash -n"
bash -n "$TICK" && ok "ft-tick bash -n" || bad "ft-tick bash -n"

# ⓐ 상한 1초 + sleep 5 (baton 머리줄 없음) → skipped:timeout (rc 124 정직) · 로그에 Terminated 0 · [HIL] 줄에 seat=
D="$TMP/a"; plan "$D" 'sa#0' 'sleep 5'; sweep "$D" "$TMP/a.out"
has "ⓐ timeout → [HIL] seat=sa#0 timeout 1s" "$TMP/a.out" '[HIL] seat=sa#0 timeout 1s'
chk "ⓐ '실행 실패' 0" "$(cnt "$TMP/a.out" '실행 실패')" 0
chk "ⓐ 계획 .hil 로 이동" "$([ -f "$D/sa#0.sh.hil" ] && echo yes || echo no)" yes
chk "ⓐ 로그 Terminated 0" "$(cnt "$D/sa#0.sh.log" 'Terminated')" 0

# ⓑ baton 머리줄 뒤 상한 초과 → WAIT(.sh 제자리 · .tmo 1) · 3회 연속 → .hil + [HIL] seat= · .tmo 삭제
D="$TMP/b"; plan "$D" 'sb#0' "echo '$BATON_HDR'; sleep 5"
sweep "$D" "$TMP/b1.out"
has "ⓑ 1회 WAIT" "$TMP/b1.out" 'WAIT sb#0'
chk "ⓑ 1회 계획 제자리" "$([ -f "$D/sb#0.sh" ] && echo yes || echo no)" yes
chk "ⓑ 1회 .tmo=1" "$(cat "$D/sb#0.sh.tmo" 2>/dev/null)" 1
chk "ⓑ 1회 [HIL] 0" "$(cnt "$TMP/b1.out" '[HIL]')" 0
sweep "$D" "$TMP/b2.out"
chk "ⓑ 2회 .tmo=2" "$(cat "$D/sb#0.sh.tmo" 2>/dev/null)" 2
sweep "$D" "$TMP/b3.out"
has "ⓑ 3회 연속 → [HIL] seat=sb#0" "$TMP/b3.out" '[HIL] seat=sb#0'
chk "ⓑ 3회 .hil 이동" "$([ -f "$D/sb#0.sh.hil" ] && echo yes || echo no)" yes
chk "ⓑ 3회 .tmo 삭제" "$([ -e "$D/sb#0.sh.tmo" ] && echo yes || echo no)" no
# 초과 뒤 성공하면 .tmo 삭제
D="$TMP/b2d"; plan "$D" 'sc#0' "echo '$BATON_HDR'; sleep 5"; sweep "$D" "$TMP/c0.out"
chk "ⓑ' 초과 1회 .tmo=1" "$(cat "$D/sc#0.sh.tmo" 2>/dev/null)" 1
printf '%s\n' 'echo cleaned' > "$D/sc#0.sh"; sweep "$D" "$TMP/c1.out"
chk "ⓑ' 성공 → .done" "$([ -f "$D/sc#0.sh.done" ] && echo yes || echo no)" yes
chk "ⓑ' 성공 → .tmo 삭제" "$([ -e "$D/sc#0.sh.tmo" ] && echo yes || echo no)" no

# ⓒ 계획 3건 → pass 1회에 1건만 실행 · FT_WT_SWEEP_MAX=5 면 전부 · 좌석 WAIT 는 예산을 쓰지 않는다
D="$TMP/c"; for s in c1 c2 c3; do plan "$D" "$s#0" 'echo cleaned'; done
sweep "$D" "$TMP/p1.out"; chk "ⓒ pass1 .done=1" "$(nfiles "$D" '*.sh.done')" 1; chk "ⓒ pass1 남은 .sh=2" "$(nfiles "$D" '*.sh')" 2
sweep "$D" "$TMP/p2.out"; chk "ⓒ pass2 .done=2" "$(nfiles "$D" '*.sh.done')" 2
sweep "$D" "$TMP/p3.out" FT_WT_SWEEP_MAX=5; chk "ⓒ MAX=5 → .done=3" "$(nfiles "$D" '*.sh.done')" 3
D="$TMP/cw"; plan "$D" 'w1#0' 'echo "skipped:좌석 살아있음"'; plan "$D" 'z1#0' 'echo cleaned'
sweep "$D" "$TMP/w.out"
chk "ⓒ WAIT 는 예산 0 → z1 실행" "$([ -f "$D/z1#0.sh.done" ] && echo yes || echo no)" yes
chk "ⓒ w1 제자리" "$([ -f "$D/w1#0.sh" ] && echo yes || echo no)" yes

# ⓓ 기존 결과 분류 불변: none → done · 다른 skipped → [HIL] seat=
D="$TMP/d"; plan "$D" 'n1#0' 'echo none'; plan "$D" 'k1#0' 'echo "skipped:미커밋 변경"'
sweep "$D" "$TMP/d1.out" FT_WT_SWEEP_MAX=5
chk "ⓓ none → .done" "$([ -f "$D/n1#0.sh.done" ] && echo yes || echo no)" yes
has "ⓓ skipped → [HIL] seat=k1#0 미커밋 변경" "$TMP/d1.out" '[HIL] seat=k1#0 미커밋 변경'
has "ⓓ R83 짧은 링크 유지(! bash …/h<N>)" "$TMP/d1.out" "! bash $TMP/hil/h"

# ⓔ sweep_wt 팀 라우팅 — ft-tick.sh 에서 master_seat · sweep_wt 만 뽑아 스텁 좌석표·스텁 mbox·스텁 sweep 으로 실행
FN="$(sed -n '/^master_seat() {/,/^}/p;/^sweep_wt() {/,/^}/p' "$TICK")"
X="$TMP/x"; mkdir -p "$X"
mk() { printf '{"_master": "%s", "%s": {"role": "master", "tick": "ft-master-tick"}}' "$2" "$2" > "$X/$1"; }
mk seats.json 'byz-v65-master-claude#1'; mk seats-harness.json 'byz-harness-master-claude#2'
printf '{"_master": "byz-loom-master-claude#9"}' > "$X/seats-loom.json"   # 현역 master 행 없음
cat > "$X/mbox.sh" <<'STUB'
#!/bin/bash
printf 'to=%s body=%s\n' "$2" "$4" >> "$MBOX_LOG"
STUB
cat > "$X/sweep.sh" <<'STUB'
#!/bin/bash
cat "$SWEEP_OUT"
STUB
chmod +x "$X/sweep.sh"   # sweep_wt 는 [ -x ] 로 존재를 본다
route() { # <케이스> <[HIL] 줄들> → $X/<케이스>.log (mbox 호출) · $X/<케이스>.err
  printf '%s\n' "$2" > "$X/$1.in"; : > "$X/$1.log"
  SEATS="$X/seats.json" MBOX="$X/mbox.sh" WT_SWEEP="$X/sweep.sh" WT_SWEEP_ENABLED=1 DRY=0 MBOX_LOG="$X/$1.log" SWEEP_OUT="$X/$1.in" \
    bash -c "log() { :; }"$'\n'"$FN"$'\n''sweep_wt' > /dev/null 2> "$X/$1.err"
}
route h '[HIL] seat=byz-harness-nano-x#0 timeout 120s · 스크립트 /p/a.sh.hil'
has "ⓔ harness 좌석 → harness master" "$X/h.log" 'to=byz-harness-master-claude#2 '
chk "ⓔ harness 머리 없음" "$(cnt "$X/h.log" '라우팅 실패')" 0
route v '[HIL] seat=byz-v65-nano-y#0 미커밋 · 스크립트 /p/b.sh.hil
[HIL] seat=ft-v65-temp-z#0 미커밋 · 스크립트 /p/c.sh.hil'
chk "ⓔ v65 두 줄 → 1통" "$(wc -l < "$X/v.log" | tr -d ' ')" 1
has "ⓔ v65 → 자기 master" "$X/v.log" 'to=byz-v65-master-claude#1 '
route l '[HIL] seat=byz-loom-nano-q#0 미커밋 · 스크립트 /p/d.sh.hil'
has "ⓔ 현역 master 없음 → 자기 master" "$X/l.log" 'to=byz-v65-master-claude#1 '
has "ⓔ 라우팅 실패 머리(loom)" "$X/l.log" '[라우팅 실패 loom]'
chk "ⓔ 라우팅 실패 stderr 1줄" "$(grep -c 'loom' "$X/l.err")" 1
route c '[HIL] seat=byz-cfo-nano-r#0 미커밋 · 스크립트 /p/e.sh.hil'
has "ⓔ 팀 파일 없음(cfo) → 라우팅 실패 머리" "$X/c.log" '[라우팅 실패 cfo]'
route m '[HIL] seat=byz-harness-nano-x#0 a
[HIL] seat=byz-v65-nano-y#0 b'
chk "ⓔ 팀 2개 → 2통" "$(wc -l < "$X/m.log" | tr -d ' ')" 2

# ⓕ DA⑥ HOLD: planner 앞 머리 검사(FT_PLANNER_HEAD_MODE=reject)는 본문이 «[HIL]» 로 시작해야 통과 — 라우팅 실패 표식은 [HIL] «뒤».
body="$(sed 's/^to=[^ ]* body=//' "$X/l.log")"
case "$body" in '[HIL] [라우팅 실패 loom] 워크트리 정리'*) ok "ⓕ 본문 = [HIL] [라우팅 실패 loom] 워크트리 정리 …";; *) bad "ⓕ 본문 머리 순서 :: ${body:0:60}";; esac
G="$TMP/g"; mkdir -p "$G/.fable-team/comm" "$G/.fable-team/state" "$G/seats" "$G/stub"
cp "$ROOT"/tools/comm-canonical/mbox*.py "$ROOT"/tools/comm-canonical/mbox*.sh "$ROOT"/tools/comm-canonical/bang_command_check.py "$G/.fable-team/comm/"
git -C "$G" init -q; cp "$ROOT"/tests/fixtures/mbox_guard/ok/seats*.json "$G/seats/"
printf '#!/bin/sh\nexit 1\n' > "$G/stub/tmux"; chmod +x "$G/stub/tmux"
guard() { ( cd "$G" && env PATH="$G/stub:$PATH" FT_SEATS_JSON="$G/seats/seats.json" FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$G/.fable-team/comm" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 bash "$G/.fable-team/comm/mbox.sh" send "$1" "me#1" "$2" 2>&1 ); }
gout="$(guard 'byz-planner-master-claude#9' "$body")"; grc=$?
chk "ⓕ 라우팅 실패 본문 → planner 머리 검사(reject) 통과 rc" "$grc" 0
chk "ⓕ 대조: 머리 순서 뒤집으면 가드 rc3" "$(guard 'byz-planner-master-claude#9' "[라우팅 실패 loom] $body" >/dev/null; echo $?)" 3

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
