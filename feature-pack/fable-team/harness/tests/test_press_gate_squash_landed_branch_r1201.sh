#!/usr/bin/env bash
# test_press_gate_squash_landed_branch_r1201.sh — r1201: press 게이트 ① 이 ft-merge-land squash 로 착지된 나노 가지를 «미랜딩» 으로 세지 않는다.
#   R1 FEAT 끝줄 «PR #7 (head X)» · 나노 HEAD ⊂ X(X = HEAD + main 병합) · 제품 커밋 3 → 셈 0 · «⊘ 착지됨» 줄
#   R2 같은 꼴 · 나노 HEAD = X → 셈 0
#   R3 X ⊂ 나노 HEAD · X..HEAD 에 병합 아닌 제품 커밋 1 → ✗ 미랜딩 1(착지 뒤 새 작업)
#   R3b X ⊂ 나노 HEAD · HEAD = 미착지 옆 가지(제품 커밋 1 · FEAT 에 없음) 병합 → ✗ 미랜딩 2(옆 가지 커밋 + 병합 커밋 — 병합 커밋 셈은 기존 커밋 단위 규칙 그대로)
#   R4 FEAT 끝줄 «PR #7 (head Y)» · Y 는 나노와 계보 무관 → 지금처럼 센다(기준판과 같은 ✗ 줄)
#   R5 끝 2줄 «PR #7 (head X)» + «main 자동 병합(문서 전용 · 겹침 0) C=<40hex>» · HEAD ⊂ X → 셈 0(꼬리 1줄 건너뜀)
#   R6 X 가 로컬에 없음 → 지금처럼 센다(기준판과 같은 ✗ 줄)
#   변이 1: 가지 판정 호출 삭제(= 기준판 동작) → R1 FAIL · 같은 변이로 R3·R4·R6 의 ✗ 줄이 기준판과 같음을 대조
#   임시 bare 원격 + 임시 리포만 · 가짜 tmux·sysctl·lsof·curl · 실 리포·실 tmux 0 · 자기 재호출 0 · 고정 sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
KIT="$HERE/../kit/fable-team/bin"
GATE="$BIN/ft-press-gate.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'TMUX'
#!/bin/sh
case "$1" in
  display-message) echo 'byz-v65-tester-claude#0' ;;
  list-sessions) printf '%s\n' 'byz-v65-nano-k#0' ;;
esac
TMUX
printf '#!/bin/sh\nprintf "{ 0.50 0.50 0.50 }\\n"\n' > "$FB/sysctl"
printf '#!/bin/sh\nexit 1\n' > "$FB/lsof"
printf '#!/bin/sh\nprintf 000\nexit 7\n' > "$FB/curl"
chmod +x "$FB"/*

g(){ git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
cm(){ mkdir -p "$1/$(dirname "$2")"; echo "$3" > "$1/$2"; g "$1" add -A >/dev/null && g "$1" commit -qm "$3"; }

SEQ=0
mkcase(){ # $1 이름 → CASE · R · W (칸마다 새 폴더) · main 1커밋 + 나노 워크트리 v65-k(main 에서)
  SEQ=$((SEQ+1)); CASE="$T/case-$SEQ-$1"; R="$CASE/root"; W="$R/.worktrees/v65-k"
  git init -q --bare "$CASE/origin.git"
  git init -q -b main "$R"
  mkdir -p "$R/.fable-team/state"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R/.fable-team/state/all-stop.log"
  printf '{"byz-v65-nano-k#0":{"role":"nano","agent":"claude","tick":null,"index":"x"}}\n' > "$R/.fable-team/seats.json"
  printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"
  cm "$R" worker/a.py base
  g "$R" remote add origin "$CASE/origin.git"
  g "$R" worktree add -q -b nano/k "$W" main 2>/dev/null
}
work(){ local i; for i in $(seq 1 "$1"); do cm "$W" "worker/k$i.py" "[fix] k$i"; done; }
squash(){ # $1 = 끝줄 head X · $2 = 꼬리 줄(선택) → main 에 squash 커밋(나노 가지 내용) + push
  local x="$1" tail="${2:-}"
  g "$R" merge -q --squash nano/k >/dev/null 2>&1
  printf '[feature] K5 착지\n\n본문\n\nPR #7 (head %s)\n%s' "$x" "$tail" > "$CASE/msg"
  g "$R" commit -q -F "$CASE/msg"
  g "$R" push -q origin main 2>/dev/null
}
side_merge(){ # main 에 커밋 1 → 나노 가지 끝에서 main 을 병합한 X 를 별도 가지(pr)로 만든다(나노 HEAD 는 그대로) → X
  cm "$R" docs/m1.md "main side"
  g "$R" branch -q pr nano/k
  g "$R" checkout -q pr && g "$R" merge -q --no-edit main >/dev/null && g "$R" checkout -q main
  g "$R" rev-parse pr
}

gate(){ # SUT → OUT · RC
  OUT="$(cd "$R" && env -u FT_NANO_FEAT -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_CARD \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$R" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" TMUX_PANE=%1 \
    PATH="$FB:$PATH" timeout 60 bash "$1" 2>&1)"; RC=$?
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }
xline(){ printf '%s\n' "$OUT" | grep -F '✗ 미랜딩 제품 커밋' ; }

case_r1(){ mkcase r1; work 3; local x; x="$(side_merge)"; squash "$x"; gate "$1"
  has "⊘ 착지됨(v65-k · PR #7 squash" && has "✓ 미랜딩 제품 커밋 0" && ! has "✗ 미랜딩"; }
case_r2(){ mkcase r2; work 3; squash "$(g "$W" rev-parse HEAD)"; gate "$1"
  has "⊘ 착지됨(v65-k · PR #7 squash" && has "✓ 미랜딩 제품 커밋 0"; }
case_r3(){ mkcase r3; work 1; squash "$(g "$W" rev-parse HEAD)"; cm "$W" worker/new.py "[fix] after land"; gate "$1"
  has "✗ 미랜딩 제품 커밋 1 — v65-k" && has "미랜딩 후보: [fix] after land" && ! has "착지됨"; }
case_r3b(){ mkcase r3b; work 1; squash "$(g "$W" rev-parse HEAD)"   # X ⊂ HEAD · HEAD = 미착지 옆 가지(제품 커밋 1) 병합
  g "$R" checkout -q -b side main~1 && cm "$R" worker/side.py "[fix] side unlanded" && g "$R" checkout -q main
  g "$W" merge -q --no-edit side >/dev/null; gate "$1"
  has "✗ 미랜딩 제품 커밋 2 — v65-k" && has "미랜딩 후보: [fix] side unlanded" && ! has "착지됨"; }
case_r4(){ mkcase r4; work 3; g "$R" branch -q other main; cm "$R" worker/o.py other-base
  local y; y="$(g "$R" rev-parse HEAD)"; g "$R" reset -q --hard HEAD~1
  squash "$y"; gate "$1"; has "✗ 미랜딩 제품 커밋 3 — v65-k" && ! has "착지됨"; }
case_r5(){ mkcase r5; work 3; local x; x="$(side_merge)"
  squash "$x" "main 자동 병합(문서 전용 · 겹침 0) C=$(g "$R" rev-parse main)"; gate "$1"
  has "⊘ 착지됨(v65-k · PR #7 squash" && has "✓ 미랜딩 제품 커밋 0"; }
case_r6(){ mkcase r6; work 3; squash 0123456789abcdef0123456789abcdef01234567; gate "$1"
  has "✗ 미랜딩 제품 커밋 3 — v65-k" && ! has "착지됨"; }
run_cases(){ # SUT 칸… → 실패 칸 이름은 BAD · 칸별 ✗ 줄은 XL_<칸>
  local sut="$1" c; shift; BAD=""
  for c in "$@"; do
    if case_"$c" "$sut" >/dev/null 2>&1; then echo "  $c ok"; else BAD="$BAD $c"; LAST="$OUT"; fi
    eval "XL_$c=\$(xline)"
  done
}

# ⓐⓑⓒ 지금 게이트 — R1~R6 전부 통과
run_cases "$GATE" r1 r2 r3 r3b r4 r5 r6
[ -z "$BAD" ] && ok "R1~R6·R3b 지금 게이트 통과" || { bad "지금 게이트 실패 칸:$BAD"; printf '%s\n' "$LAST" | sed 's/^/    /'; }
NEW_R3="$XL_r3"; NEW_R3B="$XL_r3b"; NEW_R4="$XL_r4"; NEW_R6="$XL_r6"

# 변이: 가지 판정 호출 삭제 = 기준판 ① 동작 · bin 형제는 심링크
d="$T/mut-call"; mkdir -p "$d"
for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done
rm "$d/ft-press-gate.sh"; sed '/_squash_landed "\$W" && continue/d' "$GATE" > "$d/ft-press-gate.sh"
if cmp -s "$GATE" "$d/ft-press-gate.sh"; then bad "변이 적용 안 됨"
else
  run_cases "$d/ft-press-gate.sh" r1
  [ "$BAD" = " r1" ] && ok "변이(가지 판정 호출 삭제) → R1 FAIL" || bad "변이 못 잡음"
  run_cases "$d/ft-press-gate.sh" r3 r3b r4 r6
  # ⓒ 착지 뒤 새 작업·무관·못 풂 = 기준판(변이)과 같은 ✗ 줄
  [ -n "$NEW_R3" ] && [ "$NEW_R3" = "$XL_r3" ] && [ "$NEW_R3B" = "$XL_r3b" ] && [ "$NEW_R4" = "$XL_r4" ] && [ "$NEW_R6" = "$XL_r6" ] \
    && ok "R3·R3b·R4·R6 ✗ 줄 기준판과 같음" || bad "R3·R3b·R4·R6 ✗ 줄 기준판과 다름"
fi

# ⓓ bin·kit 같은 내용
cmp -s "$GATE" "$KIT/ft-press-gate.sh" && ok "bin·kit cmp0" || bad "bin·kit 내용 다름"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
