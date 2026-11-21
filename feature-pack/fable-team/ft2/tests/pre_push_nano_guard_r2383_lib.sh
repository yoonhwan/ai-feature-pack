#!/bin/sh
# r2383 pre-push 나노 가드 시험 공통 대역 — 시험 3파일이 source 해서 쓴다.
# 임시 bare 리포(실 원격 0) · 실 좌석 0(env 만) · 가짜 python3 로 guard 호출 세기 · 변이는 훅 사본에서만.
# 시험 1개 70초 상한 때문에 사례를 칸으로 나눴다(⑪~⑰㉑㉓㉔ / ⑱ / ⑲) — sleep 은 ⑱ 칸에만.
FT2=$(cd "$(dirname "$0")/.." && pwd) || exit 1
HOOK="$FT2/tools/pre-push-nano-guard.sh"
NANO="byz-harness-nano-x#1"
PY=$(command -v python3) || { echo "FAIL python3 없음"; exit 1; }
REAL_GIT=$(command -v git)
REAL_TAR=$(command -v tar)
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
pushof() {   # $1 = d · $2 = FT2_HOLDER 값 · 나머지 = refspec → $1/push.out · rc · EXECP 있으면 GIT_EXEC_PATH 로 넘긴다(㉓)
  d=$1; holder=$2; shift 2
  ( cd "$d/c" && env FT2_HOLDER="$holder" FT_SEAT_NAME= TMPDIR="$d/tmp" PATH="$d/bin:$PATH" ${EXECP:+GIT_EXEC_PATH=$EXECP} git push origin "$@" ) >"$d/push.out" 2>&1
}
wrap_git() {   # ㉓ 대역 — archive 만 바이트는 정상으로 내고 rc 를 $2 로.
  # 훅 안에서는 git 이 exec-path 를 PATH 앞에 붙이므로, 사본을 exec-path 자리에 두고 그 자리를 넘긴다(c23 이 EXECP 를 세운다).
  mkdir -p "$1/exec"
  printf '#!/bin/sh\nunset GIT_EXEC_PATH\nif [ "$1" = archive ]; then "%s" "$@"; rc=$?; [ "$rc" = 0 ] && exit %s; exit "$rc"; fi\nexec "%s" "$@"\n' "$REAL_GIT" "$2" "$REAL_GIT" > "$1/exec/git"
  chmod +x "$1/exec/git"
}
wrap_tar() {   # ㉔ 대역 — 풀기는 정상으로 하고 rc 를 $2 로
  printf '#!/bin/sh\n"%s" "$@"; rc=$?; [ "$rc" = 0 ] && exit %s; exit "$rc"\n' "$REAL_TAR" "$2" > "$1/bin/tar"
  chmod +x "$1/bin/tar"
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

run_case() {   # $1 = 이름 · $2 = 사례 함수 → 사례는 (훅 경로, 이름 꼬리) 를 받는다
  if out=$("$2" "$HOOK" ""); then pass "$1"; else fail "$1" "$(printf '%s' "$out" | paste -sd' ' -)"; fi
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
lib_done() {   # $1 = 이 칸 설명
  if [ "$FAILS" = 0 ]; then echo "PASS $1"; exit 0; fi
  echo "FAILS=$FAILS"; exit 1
}
