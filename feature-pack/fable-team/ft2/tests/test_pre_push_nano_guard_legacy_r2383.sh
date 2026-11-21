#!/bin/sh
# r2383 pre-push 나노 가드 ft2 갈래 시험 — 반례 ⑪~⑲ · ㉑ · 변이 M4~M8.
# 전부 임시 bare 리포(실 원격 0) · 실 좌석 0(env 만) · sleep 은 ⑱(시간)에만 · 변이는 훅 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
# 실행: sh tests/test_pre_push_nano_guard_legacy_r2383.sh    rc 0 = 전부 통과 · 지는 사례는 «FAIL <번호> — <사유>».
FT2=$(cd "$(dirname "$0")/.." && pwd) || exit 1
HOOK="$FT2/tools/pre-push-nano-guard.sh"
NANO="byz-harness-nano-x#1"
PY=$(command -v python3) || { echo "FAIL python3 없음"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
FAILS=0
MK_HOOK="$HOOK"
g() { git -c user.name=t -c user.email=t@t "$@"; }
pass() { echo "OK   $1"; }
fail() { echo "FAIL $1 — $2"; FAILS=$((FAILS + 1)); }
why() { tail -2 "$1/push.out" 2>/dev/null | paste -sd' ' -; }
calls() { wc -l < "$1/calls" | tr -d ' '; }

mk() {   # $1 = 이름 → <T>/<이름> 에 remote.git·c·hooks·bin·tmp · stdout = 리포 폴더
  d="$T/$1"; rm -rf "$d"; mkdir -p "$d/hooks" "$d/bin" "$d/tmp"
  git init -q --bare -b main "$d/remote.git" || return 1
  git clone -q "$d/remote.git" "$d/c" 2>/dev/null || return 1
  mkdir -p "$d/c/feature-pack/fable-team/ft2/tools" "$d/c/design/harness"
  printf 'import sys\nsys.exit(0)\n' > "$d/c/feature-pack/fable-team/ft2/tools/legacy_guard.py"
  printf 'base\n' > "$d/c/design/harness/note.md"
  ( cd "$d/c" && g add -A && g commit -q -m base && g push -q origin HEAD:main ) >/dev/null 2>&1 || return 1
  g -C "$d/c" config core.hooksPath "$d/hooks"
  cp "$MK_HOOK" "$d/hooks/pre-push" || return 1
  chmod +x "$d/hooks/pre-push" || return 1
  : > "$d/calls"
  printf '#!/bin/sh\necho call >> "%s/calls"\nexec "%s" "$@"\n' "$d" "$PY" > "$d/bin/python3"
  printf '#!/bin/sh\necho call >> "%s/calls"\nsleep 8\nexit 2\n' "$d" > "$d/bin/slow"
  chmod +x "$d/bin/python3" "$d/bin/slow"
  echo "$d"
}

setguard() {   # $1 = d · $2 = ok|viol|bad → 그 리포 ft2 의 guard 대역(진짜 python 파일)
  case "$2" in
    ok) printf 'import sys\nsys.exit(0)\n' > "$1/c/feature-pack/fable-team/ft2/tools/legacy_guard.py" ;;
    viol) printf 'import sys\nprint("core/x.py:1: probe")\nsys.exit(1)\n' > "$1/c/feature-pack/fable-team/ft2/tools/legacy_guard.py" ;;
    bad) printf 'import sys\nsys.exit(2)\n' > "$1/c/feature-pack/fable-team/ft2/tools/legacy_guard.py" ;;
  esac
}
mkc() { ( cd "$1/c" && g add -A && g commit -q -m "$2" ) >/dev/null 2>&1; }
pushof() {   # $1 = d · $2 = FT2_HOLDER 값 · 나머지 = refspec → $1/push.out · rc
  d=$1; holder=$2; shift 2
  ( cd "$d/c" && FT2_HOLDER="$holder" FT_SEAT_NAME= TMPDIR="$d/tmp" PATH="$d/bin:$PATH" git push origin "$@" ) >"$d/push.out" 2>&1
}

c11() {   # ⑪ ft2 바뀜 · 위반 0 → rc 0 · guard 1회
  MK_HOOK=$1; d=$(mk "c11$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 1 ] || { echo "  guard $(calls "$d")회(기대 1)"; return 1; }
}
c12() {   # ⑫ 위반 1 → PUSH_DENIED legacy_guard 위반 1건 · rc 1
  MK_HOOK=$1; d=$(mk "c12$2") || return 1
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "PUSH_DENIED legacy_guard 위반 1건 — 첫 줄: core/x.py:1: probe" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 1 ] || { echo "  guard $(calls "$d")회(기대 1)"; return 1; }
}
c13() {   # ⑬ ft2 밖만 바뀜 → guard 0회 · rc 0
  MK_HOOK=$1; d=$(mk "c13$2") || return 1
  printf 'x\n' >> "$d/c/design/harness/note.md"; mkc "$d" "문서만" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c14() {   # ⑭ 나노 아닌 좌석 → rc 0 · guard 0회
  MK_HOOK=$1; d=$(mk "c14$2") || return 1
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c15() {   # ⑮ 새 가지 · origin/main 없음 → 판정 불가 + PUSH_DENIED
  MK_HOOK=$1; d=$(mk "c15$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  g -C "$d/c" update-ref -d refs/remotes/origin/main >/dev/null 2>&1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard merge-base rc=1" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c16() {   # ⑯ 가지 지우는 push(local_sha 0×40) → guard 0회 · rc 0 (DA#54 F1)
  MK_HOOK=$1; d=$(mk "c16$2") || return 1
  pushof "$d" "" HEAD:refs/heads/nano/x || { echo "  준비 실패 $(why "$d")"; return 1; }
  : > "$d/calls"
  pushof "$d" "$NANO" --delete refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c17() {   # ⑰ 한 push ref 3줄(같은 sha 2 · 다른 sha 1) → guard 2회 (DA#54 F2)
  MK_HOOK=$1; d=$(mk "c17$2") || return 1
  setguard "$d" ok
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 1" || return 1
  printf 'b = 1\n' > "$d/c/feature-pack/fable-team/ft2/b.py"; mkc "$d" "ft2 2" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/a HEAD:refs/heads/nano/b HEAD~1:refs/heads/nano/c; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 2 ] || { echo "  guard $(calls "$d")회(기대 2)"; return 1; }
}
c18() {   # ⑱ 가짜 python 8초 멈춤 → 시간 판정 불가 + PUSH_DENIED · 호출 2회 · 15초 안
  MK_HOOK=$1; d=$(mk "c18$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  cp "$d/bin/slow" "$d/bin/python3"
  s=$(date +%s); pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?; e=$(date +%s)
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard 시간 rc=124" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 2 ] || { echo "  guard $(calls "$d")회(기대 2)"; return 1; }
  [ $((e - s)) -le 15 ] || { echo "  $((e - s))초(기대 15 이하)"; return 1; }
}
c19() {   # ⑲ guard rc 2 → 판정 불가 + PUSH_DENIED · 임시 폴더 남음 0
  MK_HOOK=$1; d=$(mk "c19$2") || return 1
  setguard "$d" bad; mkc "$d" "ft2 rc2" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard 실행 rc=2" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ -z "$(ls -A "$d/tmp")" ] || { echo "  임시 폴더 남음: $(ls -A "$d/tmp")"; return 1; }
}
c21() {   # ㉑ 나노 좌석 main·ops/main-base — r1900·r1999 출력 그대로 · guard 0회
  MK_HOOK=$1; d=$(mk "c21$2") || return 1
  pushof "$d" "" HEAD:refs/heads/ops/main-base || { echo "  준비 실패 $(why "$d")"; return 1; }
  mkdir -p "$d/c/design/harness/indices"; printf 'x\n' > "$d/c/design/harness/indices/r1.md"; mkc "$d" "카드" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/ops/main-base; rc=$?
  [ "$rc" = 0 ] || { echo "  ops/main-base rc=$rc(카드 전용 면제 깨짐) $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/main; rc=$?
  [ "$rc" != 0 ] || { echo "  main push rc=0"; return 1; }
  grep -qF "PUSH_DENIED 나노 좌석 $NANO 의 refs/heads/main push — 착지 = master" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}

mut() {   # $1 = 사본 경로 · 나머지 = old▸new — 훅 원본에서 1회씩 치환(글자 1회 확인)
  dest=$1; shift
  python3 - "$HOOK" "$dest" "$@" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
for pair in sys.argv[3:]:
    old, new = pair.split("▸")
    if src.count(old) != 1:
        raise SystemExit("치환 %d회: %r" % (src.count(old), old))
    src = src.replace(old, new)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
}
mtest() {   # $1 = 변이 이름 · $2 = 사례 번호 · 나머지 = 치환 쌍 → 사본은 지고 원본은 이겨야 통과
  name=$1; num=$2; shift 2
  mfile="$T/mut_$name.sh"
  if ! mut "$mfile" "$@"; then fail "$name" "치환 실패"; return; fi
  if "c$num" "$mfile" "_m"; then fail "$name" "사본이 안 잡힘"; return; fi
  if "c$num" "$HOOK" "_o"; then pass "$name"; else fail "$name" "원본 대조 실패"; fi
}

for n in 11 12 13 14 15 16 17 18 19 21; do
  if out=$("c$n" "$HOOK" ""); then pass "$n"; else fail "$n" "$(printf '%s' "$out" | tr '\n' ' ')"; fi
done

mtest M4 12 '      g=$(guard_once "$local_sha")▸      g=0'
mtest M5 18 '  case "$rc" in 124|137|143) echo 124 ;; *) echo "$rc" ;; esac▸  case "$rc" in 124|137|143) echo 0 ;; *) echo "$rc" ;; esac'
mtest M6 13 '      [ "$k" = 1 ] && continue   # ft2 안 바뀜 = guard 0회▸      :   # 변이 M6 — ft2 안 바뀜도 검사'
mtest M7 18 '    124|126|127)▸    1000)'
mtest M8 17 '  if [ -f "$cache" ]; then cat "$cache"; return; fi▸  if false; then cat "$cache"; return; fi'

if [ "$FAILS" = 0 ]; then echo "PASS 반례 ⑪~⑲ · ㉑ · 변이 M4~M8"; exit 0; fi
echo "FAILS=$FAILS"; exit 1
