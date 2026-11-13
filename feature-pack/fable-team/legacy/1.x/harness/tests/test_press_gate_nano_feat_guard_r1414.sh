#!/usr/bin/env bash
# test_press_gate_nano_feat_guard_r1414.sh — r1414: press 게이트 ① 기준 줄기 env FT_NANO_FEAT 꾸밈 막기.
#   F1 env 없음 → 지금과 같음(미랜딩 1 을 센다)
#   F2 FT_NANO_FEAT=<미랜딩 나노 HEAD 40hex> → «① 판정 불가 … origin/main 의 조상 아님» 막힘
#   F3 <나노 HEAD>^{commit} · 축약 sha → 같은 막힘(꼴이 아니라 풀린 커밋으로 판정)
#   F4 FT_NANO_FEAT=<origin/main 조상 A> · 나노 base_sha=B(A 뒤) → 막힘(«다른 줄기» 로 빼는 길 0)
#   F5 FT_NANO_FEAT=<origin/main tip sha> → 지금과 같음(착지 나노 = 통과 · 미랜딩 1 = 셈)
#   F6 FT_NANO_FEAT=<현역 나노 가지 이름> → 막힘(알려진 줄기 ref 이름이 아니다)
#   변이 4: 조상 검사 삭제 → F2 · 40hex 꼴만 검사 → F3 · base 후손 검사 삭제 → F4 · 나노 가지 검사 삭제 → F6
#   임시 bare 원격 + 임시 리포만 · 가짜 tmux·sysctl·lsof·curl · 실 리포·실 허가 파일 0 · 고정 sleep 0 · 칸별 timeout 60
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
KIT="$HERE/../kit/fable-team/bin"
GATE="${R1414_GATE:-$BIN/ft-press-gate.sh}"
fail=0; T0=$(date +%s)
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

# 칸마다 새 루트: bare 원격 + origin/main(base → m1 → m2) + main tip 에서 뜬 나노 워크트리 v65-k(base=main · base_sha=tip)
SEQ=0
mkcase(){ # $1 이름 [$2 = own → 나노 미랜딩 worker 커밋 1] → CASE · R · W · A(base) · B(tip) · N(나노 HEAD)
  SEQ=$((SEQ+1)); CASE="$T/case-$SEQ-$1"; R="$CASE/root"; W="$R/.worktrees/v65-k"
  git init -q --bare "$CASE/origin.git"
  git init -q -b main "$R"
  mkdir -p "$R/.fable-team/state"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R/.fable-team/state/all-stop.log"
  printf '{"byz-v65-nano-k#0":{"role":"nano","agent":"claude","tick":null,"index":"x"}}\n' > "$R/.fable-team/seats.json"
  printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"
  cm "$R" worker/a.py base; A="$(g "$R" rev-parse HEAD)"
  cm "$R" worker/m1.py "main landed 1"
  cm "$R" worker/m2.py "main landed 2"; B="$(g "$R" rev-parse HEAD)"
  g "$R" remote add origin "$CASE/origin.git" && g "$R" push -q origin main 2>/dev/null
  g "$R" worktree add -q -b nano/k "$W" main 2>/dev/null
  printf '{"base":"main","base_sha":"%s"}\n' "$B" > "$W/.worktree-info.json"
  [ "${2:-}" = own ] && cm "$W" worker/own.py "[fix] own change"
  N="$(g "$W" rev-parse HEAD)"
}
gate(){ # SUT [env…] → OUT · RC
  local sut="$1"; shift
  OUT="$(cd "$R" && env -u FT_NANO_FEAT -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_CARD \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$R" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" FT_PRESS_GATE_CACHE_SEC=0 TMUX_PANE=%1 \
    PATH="$FB:$PATH" "$@" timeout 60 bash "$sut" 2>&1)"; RC=$?
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }
blocked(){ [ "$RC" = 1 ] && has "✗ ① 판정 불가 — $1" && ! has "미랜딩 제품 커밋" && has "PRESS-GATE BLOCK"; }
NOT_ANC="은 origin/main 의 조상 아님"

case_f1(){ mkcase f1 own; gate "$1"; has "✗ 미랜딩 제품 커밋 1 — v65-k" && ! has "① 판정 불가"; }
case_f2(){ mkcase f2 own; gate "$1" FT_NANO_FEAT="$N"; blocked "FT_NANO_FEAT=$N $NOT_ANC"; }
case_f3a(){ mkcase f3a own; gate "$1" "FT_NANO_FEAT=$N^{commit}"; blocked "FT_NANO_FEAT=$N^{commit} $NOT_ANC"; }
case_f3b(){ mkcase f3b own; gate "$1" FT_NANO_FEAT="${N:0:9}"; blocked "FT_NANO_FEAT=${N:0:9} $NOT_ANC"; }
case_f4(){ mkcase f4 own; gate "$1" FT_NANO_FEAT="$A"; blocked "FT_NANO_FEAT=$A 는 현역 나노(v65-k) base ${B:0:10} 보다 앞선 값" && ! has "다른 줄기"; }
case_f5a(){ mkcase f5a; gate "$1" FT_NANO_FEAT="$B"; has "✓ 미랜딩 제품 커밋 0" && ! has "① 판정 불가"; }
case_f5b(){ mkcase f5b own; gate "$1" FT_NANO_FEAT="$B"; has "✗ 미랜딩 제품 커밋 1 — v65-k" && ! has "① 판정 불가"; }
case_f6(){ mkcase f6 own; gate "$1" FT_NANO_FEAT=nano/k; blocked "기준 줄기 nano/k 는 현역 나노(v65-k)의 가지"; }
ALL="f1 f2 f3a f3b f4 f5a f5b f6"
run_cases(){ # SUT 칸… → 실패 칸 이름은 BAD 에
  local sut="$1" c; shift; BAD=""
  for c in "$@"; do case_"$c" "$sut" >/dev/null 2>&1 && echo "  $c ok" || { BAD="$BAD $c"; LAST="$OUT"; }; done
}

# ⓐ 지금 게이트 — F1~F6 전부 통과
run_cases "$GATE" $ALL
[ -z "$BAD" ] && ok "F1~F6 게이트 통과" || { bad "게이트 실패 칸:$BAD"; printf '%s\n' "$LAST" | sed 's/^/    /'; }
[ -n "${R1414_GATE:-}" ] && { echo "기준판 실행(R1414_GATE) — 변이·kit 생략"; [ "$fail" = 0 ] && exit 0 || exit 1; }

# ⓑ 변이 사본: bin 형제 파일은 심링크($HERE 로 부르는 스크립트) · 게이트만 perl 로 바꾼다
mutant(){ # $1 이름 $2 perl 식 → MUT 경로
  local d="$T/mut-$1"; mkdir -p "$d"
  for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done
  rm "$d/ft-press-gate.sh"; perl -pe "$2" "$GATE" > "$d/ft-press-gate.sh"
  cmp -s "$GATE" "$d/ft-press-gate.sh" && { bad "변이 $1 적용 안 됨"; return 1; }
  MUT="$d/ft-press-gate.sh"
}
mut_check(){ # 이름 기대실패칸 perl식
  mutant "$1" "$3" || return
  run_cases "$MUT" $2
  [ "$BAD" = " $2" ] && ok "변이 $1 → $2 FAIL" || bad "변이 $1 못 잡음(실패 칸:${BAD:- 없음})"
}
mut_check anc f2 's/^(\s*)(git merge-base --is-ancestor "\$fs" "\$ms").*$/$1:/'
mut_check hex40 "f3a f3b" 's/^(\s*)(fs="\$\(git rev-parse -q --verify)/$1\[\[ "\$FEAT" =~ ^[0-9a-f]{40}\$ \]\] || return 0; $2/'
mut_check desc f4 's/^.*보다 앞선 값.*$/    :/'
mut_check nanobr f6 's/^.*의 가지.*$/      :/'

# ⓒ bin·kit 같은 내용
cmp -s "$GATE" "$KIT/ft-press-gate.sh" && ok "bin·kit cmp0" || bad "bin·kit 내용 다름"

echo "단계 초: 전체 $(( $(date +%s) - T0 ))s"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
