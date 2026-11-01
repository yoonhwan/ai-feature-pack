#!/usr/bin/env bash
# test_press_gate_step1_git_hoist_r1283.sh — r1283 press 게이트 ①: 기준 줄기 로그 1회 읽기 + 항상 거짓이던 조상 검사 삭제(1/2 · 훅 상한은 test_press_runner_gate_timeout_r1283.sh)
#   R1 나노 4 × 미랜딩 후보(같은 제목 cherry-pick · 본문 sha 인용 · 조상 병합 · 진짜 미랜딩) → 옛 판과 ① 출력 diff 0 · UNLANDED 같음
#   R2 선언 제외 · 선언 모순(커밋이 세트에 이미 있음) 꼴 → 옛 판과 출력 diff 0
#   R3 git 호출 수: 나노 4 일 때 «log FEAT --format=%s -400» 1회 · «-60» 1회(옛 판 4회씩) · merge-base 는 옛 판보다 줄어듦
#   R7 첫 실행이 ① 을 끝내면 캐시가 생기고 같은 키 둘째 실행은 ① git 호출 0(훅 안 게이트와 같은 경로 — 러너 훅이 부르는 꼴)
#   변이 1 = 옛 판(로그를 루프 안으로 되돌리고 ⒞ 복원) → R3 FAIL
#   옛 판은 새 판에서 «되돌리는 치환» 으로 만든다(치환이 안 먹으면 시험 FAIL · 먹은 결과가 옛 파일과 같은지는 나노 착수 때 git show 로 대조)
#   실 리포·실 tmux·실 Redis·네트워크 0 · 자기 재호출 0 · 고정 sleep 0
set -uo pipefail
[ -z "${FT_R1283_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1283_REENTRY=1
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"

mkold(){ # $1 = 새 게이트 → 옛 판 사본 경로(로그 2개를 루프 안으로 · ⒞ 복원) · 치환 하나라도 안 먹으면 rc1
  local out="$T/old-gate.sh"
  python3 -I - "$1" "$out" <<'PY' || return 1
import sys
s = open(sys.argv[1], encoding="utf-8").read()
subj = "FEAT_SUBJ=$(git log \"$FEAT\" --format='%s' -400)\n"
body = "FEAT_BODY=$(git log \"$FEAT\" --format='%H%n%B' -60)\n"
def rep(s, a, b):
    assert a in s, a
    return s.replace(a, b, 1)
s = rep(s, subj + body + "for W in $LIVE_WT; do", "for W in $LIVE_WT; do")
s = rep(s, "  P=0; IN_SET=0\n", "  P=0; IN_SET=0\n  " + subj + "  " + body)
anchor = "    printf '%s\\n' \"$FEAT_BODY\" | grep -q \"${h:0:9}\" && continue\n"
s = rep(s, anchor, anchor + "    git merge-base --is-ancestor \"$h\" \"$FEAT\" 2>/dev/null && continue\n")
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
  printf '%s' "$out"
}
cnt(){ grep -cE -- "$1" "$CASE/gitlog"; }   # git 래퍼 기록에서 한 꼴의 호출 수

mk4(){ # 나노 4(k·p·q·r) × 후보 꼴 4 → origin/main 에 p 제목·q 본문 인용·r 조상 반영
  mkcase "$1"
  local n sha
  for n in p q r; do
    g "$R" worktree add -q -b "nano/$n" "$R/.worktrees/v65-$n" main 2>/dev/null
  done
  printf '{"byz-v65-nano-k#0":{"role":"nano"},"byz-v65-nano-p#0":{"role":"nano"},"byz-v65-nano-q#0":{"role":"nano"},"byz-v65-nano-r#0":{"role":"nano"}}\n' > "$R/.fable-team/seats.json"
  printf 'byz-v65-nano-k#0\nbyz-v65-nano-p#0\nbyz-v65-nano-q#0\nbyz-v65-nano-r#0\n' > "$CASE/sessions"
  work 2                                                                        # k: 진짜 미랜딩 2
  cm "$R/.worktrees/v65-p" worker/p1.py "[fix] p-cherry"                        # p: main 에 같은 제목이 있다(⒜)
  cm "$R/.worktrees/v65-q" worker/q1.py "[fix] q-body"; sha="$(g "$R/.worktrees/v65-q" rev-parse HEAD)"   # q: main 커밋 본문이 sha 를 인용(⒝)
  cm "$R/.worktrees/v65-r" worker/r1.py "[fix] r-anc"                           # r: 이 커밋은 main 에 병합돼 조상(⒞ — 후보에 안 오른다)
  g "$R" merge -q --ff-only nano/r 2>/dev/null
  cm "$R/.worktrees/v65-r" worker/r2.py "[fix] r-new"                           # r: 진짜 미랜딩 1
  cm "$R" worker/p-main.py "[fix] p-cherry"
  g "$R" commit -q --allow-empty -m "[fix] q-relanded" -m "원본 ${sha:0:12} 재작성" 2>/dev/null
  g "$R" push -q origin main 2>/dev/null
}
GC="FT_PRESS_GATE_CACHE_SEC=0"

case_a1(){ # R1
  mk4 a1; local old new; old="$(mkprobe "$(mkold "$GATE")")" || return 1; new="$(mkprobe "$GATE")" || return 1
  GENV="$GC"; runbin "$old"; local o="$OUT"; runbin "$new"
  [ "$o" = "$OUT" ] && has "✗ 미랜딩 제품 커밋 2 — v65-k" && has "✗ 미랜딩 제품 커밋 1 — v65-r" \
    && ! has "미랜딩 후보: [fix] p-cherry" && ! has "미랜딩 후보: [fix] q-body" && ! has "미랜딩 후보: [fix] r-anc" \
    && ! has "✗ 미랜딩 제품 커밋 1 — v65-p" && ! has "✗ 미랜딩 제품 커밋 1 — v65-q" && has "S1STATE FAIL=1 UNLANDED=3"; }
case_a2(){ # R2
  mk4 a2; local old new; old="$(mkprobe "$(mkold "$GATE")")" || return 1; new="$(mkprobe "$GATE")" || return 1
  g "$R" worktree add -q --detach "$CASE/set" nano/k 2>/dev/null; GWT="$CASE/set"      # 세트 HEAD = k 끝 → k 커밋은 이미 세트에 있다
  printf '# card\n- press 제외 나노: v65-k, v65-r — 시험 제외\n' > "$CASE/card.md"
  GENV="$GC FT_PRESS_CARD=$CASE/card.md"; runbin "$old"; local o="$OUT"; runbin "$new"
  [ "$o" = "$OUT" ] && has "✗ 선언 모순 — v65-k" && has "⊘ 선언 제외(v65-r)" && has "S1STATE FAIL=1 UNLANDED=2"; }
case_a3(){ # R3 — $1 = 새 게이트(변이 1 이면 옛 판)
  mk4 a3; GENV="$GC"; runbin "$1"
  [ "$(cnt '^log origin/main --format=%s -400 $')" = "1" ] && [ "$(cnt '^log origin/main --format=%H%n%B -60 $')" = "1" ] || return 1
  local nm_new; nm_new="$(cnt 'merge-base --is-ancestor')"
  runbin "$(mkprobe "$(mkold "$GATE")")" || return 1                                    # 양성 대조: 옛 판은 나노마다 읽는다
  [ "$(cnt '^log origin/main --format=%s -400 $')" = "4" ] && [ "$(cnt '^log origin/main --format=%H%n%B -60 $')" = "4" ] \
    && [ "$(cnt 'merge-base --is-ancestor')" -gt "$nm_new" ]; }
case_a7(){ # R7 — 첫 실행이 상한 안에 ① 을 끝내면 캐시 1 · 둘째는 ① git 호출 0
  mk4 a7; GENV=""; runbin "$1"; local n1=$NG; [ "$n1" -gt 0 ] && [ "$(ncache)" = "1" ] || return 1
  runbin "$1"; hit && [ "$NG" = "0" ] && has "✗ 미랜딩 제품 커밋 2 — v65-k"; }

P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
run_cases "$P" a1 a2 a3 a7
[ -z "$BAD" ] && ok "R1·R2·R3·R7 통과" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -12 | sed 's/^/    /'; }
OLD="$(mkold "$GATE")" && M1="$(mkprobe "$OLD")" || { bad "변이 1 사본"; echo "FAILED $fail"; exit 1; }
run_cases "$M1" a3
case "$BAD" in *a3*) ok "변이 1(옛 판) → R3 FAIL" ;; *) bad "변이 1 이 R3 을 못 잡음" ;; esac
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
