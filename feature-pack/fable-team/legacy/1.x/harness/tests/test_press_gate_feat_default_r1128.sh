#!/usr/bin/env bash
# test_press_gate_feat_default_r1128.sh — r1128: press 게이트 ① 의 기준 줄기(FEAT) 기본값 = origin/main.
#   R1 env 없음 · 나노 HEAD = main 에 들어간 커밋 → 미랜딩 0
#   R2 FT_NANO_FEAT=<옛 가지> → 그 가지 기준으로 센다(덮어쓰기 불변)
#   R3 env 없음 · origin/main 에 없는 worker 커밋 1 → 미랜딩 1
#   R4 FT_NANO_FEAT=없는 ref → «① 판정 불가» · 셈 0 · 막힘
#   R5 .worktree-info.json base=main(또는 origin/main) → «다른 줄기» 제외 0
#   변이 2: 기본값 되돌림 → R1 FAIL · ref 확인 삭제 → R4 FAIL
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

# 칸마다 새 루트: bare 원격 + main 2커밋(worker) 이 올라간 origin/main + 뒤처진 옛 feat 가지 + 나노 워크트리 v65-k
SEQ=0
mkcase(){ # $1 이름 → CASE · R · W (회차마다 새 폴더 — 앞 회차 상태가 새지 않는다)
  SEQ=$((SEQ+1)); CASE="$T/case-$SEQ-$1"; R="$CASE/root"; W="$R/.worktrees/v65-k"
  git init -q --bare "$CASE/origin.git"
  git init -q -b main "$R"
  mkdir -p "$R/.fable-team/state"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R/.fable-team/state/all-stop.log"
  printf '{"byz-v65-nano-k#0":{"role":"nano","agent":"claude","tick":null,"index":"x"}}\n' > "$R/.fable-team/seats.json"
  printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"
  cm "$R" worker/a.py base
  g "$R" branch -q feat/v6-realtime-live          # 옛 feat — 여기서 멈춘다
  cm "$R" worker/m1.py "main landed 1"
  cm "$R" worker/m2.py "main landed 2"
  g "$R" remote add origin "$CASE/origin.git" && g "$R" push -q origin main 2>/dev/null
}
nano(){ g "$R" worktree add -q -b nano/k "$W" "${1:-main}" 2>/dev/null; }
info(){ printf '{"base":"%s","base_sha":"%s"}\n' "$1" "$2" > "$W/.worktree-info.json"; }

gate(){ # SUT [env…] → OUT · RC
  local sut="$1"; shift
  OUT="$(cd "$R" && env -u FT_NANO_FEAT -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_CARD \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$R" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" TMUX_PANE=%1 \
    PATH="$FB:$PATH" "$@" timeout 60 bash "$sut" 2>&1)"; RC=$?
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }

case_r1(){ mkcase r1; nano; gate "$1"; has "✓ 미랜딩 제품 커밋 0" && ! has "✗ 미랜딩"; }
case_r2(){ mkcase r2; nano; gate "$1" FT_NANO_FEAT=feat/v6-realtime-live; has "✗ 미랜딩 제품 커밋 2 — v65-k"; }
case_r3(){ mkcase r3; nano; cm "$W" worker/own.py "[fix] own change"; gate "$1"
  has "✗ 미랜딩 제품 커밋 1 — v65-k" && has "미랜딩 후보: [fix] own change"; }
case_r4(){ mkcase r4; nano; gate "$1" FT_NANO_FEAT=no/such-ref
  [ "$RC" = 1 ] && has "✗ ① 판정 불가 — 기준 줄기 no/such-ref 를 못 풂" && ! has "미랜딩 제품 커밋" && has "PRESS-GATE BLOCK"; }
case_r5a(){ mkcase r5a; cm "$R" docs/local.md "local main ahead"; nano; info main "$(g "$R" rev-parse main)"; gate "$1"   # 로컬 main 이 origin/main 보다 앞섬
  ! has "다른 줄기" && has "✓ 미랜딩 제품 커밋 0"; }
case_r5b(){ mkcase r5b; nano; info origin/main "$(g "$R" rev-parse origin/main)"; gate "$1"; ! has "다른 줄기" && has "✓ 미랜딩 제품 커밋 0"; }
run_cases(){ # SUT 칸… → 실패 칸 이름은 BAD 에
  local sut="$1" c; shift; BAD=""
  for c in "$@"; do case_"$c" "$sut" >/dev/null 2>&1 && echo "  $c ok" || { BAD="$BAD $c"; LAST="$OUT"; }; done
}

# ⓐ~ⓓ 지금 게이트 — 반례 R1~R5 전부 통과
run_cases "$GATE" r1 r2 r3 r4 r5a r5b
[ -z "$BAD" ] && ok "R1~R5 지금 게이트 통과" || { bad "지금 게이트 실패 칸:$BAD"; printf '%s\n' "$LAST" | sed 's/^/    /'; }

# 변이 사본: bin 형제 파일은 심링크($HERE 로 부르는 스크립트) · 게이트만 바꾼다
mutant(){ # $1 이름 $2 sed 식 → MUT 경로
  local d="$T/mut-$1"; mkdir -p "$d"
  for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done
  rm "$d/ft-press-gate.sh"; sed "$2" "$GATE" > "$d/ft-press-gate.sh"
  cmp -s "$GATE" "$d/ft-press-gate.sh" && { bad "변이 $1 적용 안 됨"; return 1; }
  MUT="$d/ft-press-gate.sh"
}
mutant default 's|FT_NANO_FEAT:-origin/main}|FT_NANO_FEAT:-feat/v6-realtime-live}|' \
  && { run_cases "$MUT" r1; [ "$BAD" = " r1" ] && ok "변이① 기본값 되돌림 → R1 FAIL" || bad "변이① 못 잡음"; }
mutant refcheck '/rev-parse --verify -q "\$FEAT^{commit}"/,/^fi$/d' \
  && { run_cases "$MUT" r4; [ "$BAD" = " r4" ] && ok "변이② ref 확인 삭제 → R4 FAIL" || bad "변이② 못 잡음"; }

# ⓔ bin·kit 같은 내용
cmp -s "$GATE" "$KIT/ft-press-gate.sh" && ok "bin·kit cmp0" || bad "bin·kit 내용 다름"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
