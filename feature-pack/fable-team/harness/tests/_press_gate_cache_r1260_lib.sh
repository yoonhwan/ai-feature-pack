# _press_gate_cache_r1260_lib.sh — r1260 시험 공용(source 전용): 임시 리포 + 가짜 tmux·sysctl·lsof·curl·git 기록기 + 칸 함수
#   게이트 ① 판정 캐시를 «실제 게이트 코드»로 시험한다. 빠른 칸은 probe 판(게이트 사본 · ① 끝(_tick B)에서 FAIL·UNLANDED 를 찍고 멈춤 · ②~⑧ 생략),
#   ② 이후가 캐시와 무관함을 보는 칸(R8)만 실제 게이트 전체를 돈다. 변이는 probe 사본에 sed 로 건다.
#   실 리포·실 tmux·실 Redis·네트워크 0 · 자기 재호출 0 · 고정 sleep 0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
LIBDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$LIBDIR/../bin"; KIT="$LIBDIR/../kit/fable-team/bin"; GATE="$BIN/ft-press-gate.sh"
REALGIT="$(command -v git)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'TMUX'
#!/bin/sh
case "$1" in
  display-message) echo 'byz-v65-tester-claude#0' ;;
  list-sessions) cat "$SESS_FILE" ;;
esac
TMUX
printf '#!/bin/sh\nprintf "{ 0.50 0.50 0.50 }\\n"\n' > "$FB/sysctl"
printf '#!/bin/sh\nexit 1\n' > "$FB/lsof"
printf '#!/bin/sh\nprintf "%%s" "${CURL_CODE:-000}"\n[ "${CURL_CODE:-000}" = 200 ] && exit 0\nexit 7\n' > "$FB/curl"
printf '#!/bin/sh\nprintf "%%s \\n" "$*" >> "$GITLOG"\nexec "$REALGIT" "$@"\n' > "$FB/git"
chmod +x "$FB"/*

g(){ git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
cm(){ mkdir -p "$1/$(dirname "$2")"; echo "$3" > "$1/$2"; g "$1" add -A >/dev/null && g "$1" commit -qm "$3"; }

SEQ=0; GENV=""; GWT=""; RCWD=""; CURL_CODE=000
mkcase(){ # 이름 → CASE · R(러너·루트) · W(나노 워크트리 v65-k) · main 1커밋 push 완료 · seats·세션 목록
  SEQ=$((SEQ+1)); CASE="$T/case-$SEQ-$1"; R="$CASE/root"; W="$R/.worktrees/v65-k"; GENV=""; GWT=""; RCWD=""
  git init -q --bare -b main "$CASE/origin.git"
  git init -q -b main "$R"
  mkdir -p "$R/.fable-team/state"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R/.fable-team/state/all-stop.log"
  printf '{"byz-v65-nano-k#0":{"role":"nano","agent":"claude","tick":null,"index":"x"}}\n' > "$R/.fable-team/seats.json"
  printf 'byz-v65-nano-k#0\n' > "$CASE/sessions"
  printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"
  cm "$R" worker/a.py base
  g "$R" remote add origin "$CASE/origin.git"
  g "$R" push -q origin main 2>/dev/null
  g "$R" worktree add -q -b nano/k "$W" main 2>/dev/null
}
work(){ local i; for i in $(seq 1 "$1"); do cm "$W" "worker/k$i.py" "[fix] k$i"; done; }
ncache(){ find "$CASE/press-gate-cache" -name 'step1-*.json' 2>/dev/null | wc -l | tr -d ' '; }

runbin(){ # $1 = 게이트 → OUT · RC · NG(① 이 부르는 git 하위 명령 log·diff·merge-base·cat-file 호출 수)
  : > "$CASE/gitlog"
  OUT="$(cd "${RCWD:-$R}" && env -u FT_NANO_FEAT -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_CARD -u FT_PRESS_GATE_CACHE_SEC \
    FT_PRESS_WT="${GWT:-$R}" FT_PRESS_ROOT="$R" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" TMUX_PANE=%1 \
    SESS_FILE="$CASE/sessions" GITLOG="$CASE/gitlog" REALGIT="$REALGIT" CURL_CODE="$CURL_CODE" PATH="$FB:$PATH" $GENV timeout 60 bash "$1" 2>&1)"; RC=$?
  NG=$(grep -cE ' (log|diff|merge-base|cat-file) ' "$CASE/gitlog")
}
mkprobe(){ # $1 = 게이트 · $2 = 변이 sed 식(선택) → 사본 경로 · ① 끝에서 상태를 찍고 멈춘다
  local d; d="$(mktemp -d "$T/probe-XXXXXX")"   # $(...) 안에서 불리므로 카운터 대신 mktemp
  ln -s "$BIN"/* "$d"/; rm "$d/ft-press-gate.sh"
  sed -e 's/^_tick B$/_tick B; echo "S1STATE FAIL=$FAIL UNLANDED=$UNLANDED"; exit 0/' ${2:+-e "$2"} "$1" > "$d/ft-press-gate.sh"
  grep -q 'S1STATE' "$d/ft-press-gate.sh" || { echo "probe 적용 안 됨" >&2; return 1; }
  [ -z "${2:-}" ] || ! cmp -s "$d/ft-press-gate.sh" <(sed -e 's/^_tick B$/_tick B; echo "S1STATE FAIL=$FAIL UNLANDED=$UNLANDED"; exit 0/' "$1") || { echo "변이 적용 안 됨" >&2; return 1; }
  printf '%s' "$d/ft-press-gate.sh"
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }
hit(){ has "① 캐시 재사용(키"; }
s1(){ printf '%s\n' "$OUT" | grep -E '미랜딩|세트 밖|세트 포함|착지됨|다른 줄기|선언|S1STATE'; }
info(){ printf '{"base":"%s","base_sha":"%s"}\n' "$1" "$2" > "$W/.worktree-info.json"; }

# ── 칸 함수: $1 = 게이트(probe 또는 변이 사본) · rc0 = 기대대로 ──
case_r1(){ mkcase r1; runbin "$1"; local n1=$NG a b; a="$(s1)"; ! hit || return 1
  runbin "$1"; hit || return 1; b="$(s1)"
  [ "$a" = "$b" ] && [ "$n1" -gt 0 ] && [ "$NG" = "0" ] && [ "$(ncache)" = "1" ] && has "S1STATE FAIL=0 UNLANDED=0"; }
case_r2(){ mkcase r2; runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  cm "$W" worker/new.py "[fix] new"; runbin "$1"; ! hit && has "S1STATE FAIL=1 UNLANDED=1" && has "✗ 미랜딩 제품 커밋 1 — v65-k" && [ "$(ncache)" = "2" ]; }
case_r3(){ mkcase r3; runbin "$1"
  git clone -q -b main "$CASE/origin.git" "$CASE/other" 2>/dev/null; cm "$CASE/other" docs/o.md o; g "$CASE/other" push -q origin main 2>/dev/null; g "$R" fetch -q origin
  runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r4a(){ mkcase r4a; runbin "$1"; cm "$R" docs/r.md r; runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r4b(){ mkcase r4b; runbin "$1"; g "$R" worktree add -q --detach "$CASE/wt2" main 2>/dev/null; GWT="$CASE/wt2"; runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r5a(){ mkcase r5a; runbin "$1"
  g "$R" worktree add -q -b nano/z "$R/.worktrees/v65-z" main 2>/dev/null
  printf '{"byz-v65-nano-k#0":{"role":"nano"},"byz-v65-nano-z#0":{"role":"nano"}}\n' > "$R/.fable-team/seats.json"; printf 'byz-v65-nano-k#0\nbyz-v65-nano-z#0\n' > "$CASE/sessions"
  runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r5a2(){ mkcase r5a2; info main "$(g "$R" rev-parse main)"; runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  info main 0123456789abcdef0123456789abcdef01234567; runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r5b(){ mkcase r5b; work 1; g "$R" branch topic main; info topic "$(g "$R" rev-parse main)"; runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  g "$R" branch -f topic nano/k; runbin "$1"; ! hit && [ "$(ncache)" = "2" ]; }
case_r5b2(){ mkcase r5b2; info nosuchref "$(g "$R" rev-parse main)"; runbin "$1"; ! hit && [ "$(ncache)" = "0" ] && [ "$NG" -gt 0 ] || return 1
  runbin "$1"; ! hit && [ "$(ncache)" = "0" ] && [ "$NG" -gt 0 ]; }
case_r5c(){ mkcase r5c; work 1; printf '# card\n- press 제외 나노: v65-k — 시험 제외\n' > "$CASE/cardA.md"; printf '# card\n' > "$CASE/cardB.md"
  GENV="FT_PRESS_CARD=$CASE/cardA.md"; runbin "$1"; has "⊘ 선언 제외(v65-k)" && has "S1STATE FAIL=0 UNLANDED=0" || return 1
  GENV="FT_PRESS_CARD=$CASE/cardB.md"; runbin "$1"; ! hit && has "✗ 미랜딩 제품 커밋 1 — v65-k" && has "S1STATE FAIL=1 UNLANDED=1"; }
case_r5c2(){ mkcase r5c2; work 1; printf '# card\n- press 제외 나노: v65-k — 시험 제외\n' > "$CASE/cardA.md"
  GENV="FT_PRESS_CARD=$CASE/cardA.md"; runbin "$1"; has "⊘ 선언 제외(v65-k)" || return 1
  printf '# card\n' > "$CASE/cardA.md"; runbin "$1"; ! hit && has "✗ 미랜딩 제품 커밋 1 — v65-k"; }
case_r6(){ mkcase r6; GENV="FT_PRESS_GATE_CACHE_SEC=0"; runbin "$1"; [ "$(ncache)" = "0" ] || return 1; runbin "$1"; ! hit && [ "$NG" -gt 0 ] || return 1
  GENV=""; runbin "$1"; [ "$(ncache)" = "1" ] || return 1
  python3 - "$CASE/press-gate-cache" <<'PY' || return 1
import glob,json,sys
for p in glob.glob(sys.argv[1]+"/step1-*.json"):
    d=json.load(open(p)); d["ts"]-=400; json.dump(d,open(p,"w"))
PY
  runbin "$1"; ! hit && [ "$NG" -gt 0 ] || return 1
  GENV="FT_PRESS_GATE_CACHE_SEC=abc"; runbin "$1"; has "✗ FT_PRESS_GATE_CACHE_SEC=abc" && has "S1STATE FAIL=1"; }
case_r7(){ mkcase r7; work 2; runbin "$1"; has "S1STATE FAIL=1 UNLANDED=2" && has "✗ 미랜딩 제품 커밋 2 — v65-k" || return 1
  runbin "$1"; hit && has "S1STATE FAIL=1 UNLANDED=2" && has "✗ 미랜딩 제품 커밋 2 — v65-k" || return 1
  mkcase r7b; work 1; GENV="FT_NANO_FEAT=origin/nope"; runbin "$1"; has "① 판정 불가" && [ "$(ncache)" = "0" ] || return 1
  runbin "$1"; ! hit && has "① 판정 불가" && [ "$(ncache)" = "0" ] && has "S1STATE FAIL=1"; }
case_r9(){ mkcase r9; GENV="FT_PRESS_SEAT=byz-v65-tester-claude#0"; runbin "$1"; runbin "$1"; ! hit && [ "$(ncache)" = "0" ] || return 1
  GENV="FT_PRESS_GATE_SELFTEST=1"; runbin "$1"; ! has "S1STATE" && [ "$(ncache)" = "0" ]; }
rel(){ python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$1" "$2"; }
case_r10(){ # 상대 경로 호출 · 호출 위치 ≠ FT_PRESS_WT — 다른 문구 게이트 둘이 같은 캐시를 쓰지 않는다(착지 DA ① 반례 1)
  local p1="$1" p2; p2="$(mkprobe "$1" 's/^FAIL=0$/FAIL=0  # alt/')" || return 1   # 변이 사본($1)을 그대로 쓴다
  mkcase r10; RCWD="$CASE"; GWT="$R"
  runbin "$(rel "$p1" "$CASE")"; ! hit && [ "$(ncache)" = "1" ] || return 1
  runbin "$(rel "$p1" "$CASE")"; hit || return 1
  runbin "$(rel "$p2" "$CASE")"; ! hit && [ "$(ncache)" = "2" ]; }
run_cases(){ # 게이트 칸… → 실패 칸은 BAD · 마지막 실패 출력은 LAST
  local sut="$1" c; shift; BAD=""
  for c in "$@"; do
    if case_"$c" "$sut" >/dev/null 2>&1; then echo "  $c ok"; else BAD="$BAD $c"; LAST="$OUT"; fi
  done
}
