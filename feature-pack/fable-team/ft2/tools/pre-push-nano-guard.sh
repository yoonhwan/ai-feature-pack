#!/bin/sh
# r1900 pre-push 나노 가드 — 나노 좌석(env FT2_HOLDER·FT_SEAT_NAME 에 -nano-)의 main·ops/main-base push 를 거부한다.
# r2383 — 나노 가지도 본다: 바뀐 파일에 feature-pack/fable-team/ft2/ 가 있으면 그 로컬 sha 의 ft2 를 풀어
#   tools/legacy_guard.py 를 1회(7초 · 재시도 1) 돌린다. rc 1 = PUSH_DENIED · 판정 불가 = PUSH_DENIED · ft2 안 바뀜 = 검사 0.
# stdin(ref 줄)만 읽는다 · 저장·재생은 부르는 훅 몫 · 착지 = master · --no-verify 는 건너뜀(실수 방지 장치 · 권한 통제 아님).
seat=""
for s in "${FT2_HOLDER:-}" "${FT_SEAT_NAME:-}"; do
  case "$s" in *-nano-*) seat="$s"; break ;; esac
done
[ -n "$seat" ] || { cat >/dev/null; exit 0; }
ZERO="0000000000000000000000000000000000000000"
FT2_DIR="feature-pack/fable-team/ft2"
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; TMP=""; }   # r2383 K5: 임시 폴더는 어떤 길로 끝나도 지운다
trap cleanup EXIT INT TERM HUP
card_only() {   # r1999: ops/main-base 면제 = 커밋 1개(부모 = remote_sha) · 파일 1개 */indices/*.md · 지운 줄 0 → 0 · 아니면 1 · git 실패 = 2
  case "$1 $2" in *0000000000000000000000000000000000000000*) return 1 ;; esac
  p=$(git rev-parse "$1^@" </dev/null 2>/dev/null) || return 2
  [ "$p" = "$2" ] || return 1   # r1999-mut:parent
  n=$(git -c core.quotePath=false diff --no-renames --numstat "$2" "$1" </dev/null 2>/dev/null) || return 2
  IFS="$(printf '\t')" read -r a d f x <<EOF
$n
EOF
  case "$a" in ''|*[!0-9]*) return 1 ;; esac
  [ "$d" = 0 ] || return 1   # r1999-mut:del
  [ -z "$x" ] && [ "$(printf '%s\n' "$n" | wc -l)" -eq 1 ] && case "$f" in */indices/*.md) return 0 ;; esac; return 1
}
need_guard() {   # r2383 K4: $1 = local_sha · $2 = remote_sha → 0 = ft2 바뀜 · 1 = 안 바뀜 · 2 = 판정 불가
  base=$2
  case "$2" in "$ZERO") base=$(git merge-base "$1" origin/main </dev/null 2>/dev/null) || return 2 ;; esac
  [ -n "$base" ] || return 2
  files=$(git -c core.quotePath=false diff --no-renames --name-only "$base" "$1" </dev/null 2>/dev/null) || return 2
  case "$files" in *"$FT2_DIR"*) return 0 ;; esac
  return 1
}
guard_rc() {   # $1 = local_sha → $TMP/g.<sha>.out 에 위반 줄 · 표준출력 = rc(0·1·2 · 124 시간 · 125 archive · 127 python)
  sha=$1; dir="$TMP/g.$sha"; out="$TMP/g.$sha.out"
  if [ ! -d "$dir" ]; then   # r2383 K4: 풀기는 sha 마다 1회(재시도는 같은 나무를 다시 쓴다) · 지우기는 trap
    mkdir -p "$dir" 2>/dev/null || { echo 125; return; }
    git archive "$sha" "$FT2_DIR" 2>/dev/null | tar -x -C "$dir" 2>/dev/null
  fi
  [ -f "$dir/$FT2_DIR/tools/legacy_guard.py" ] || { echo 125; return; }
  : > "$out"
  python3 "$dir/$FT2_DIR/tools/legacy_guard.py" "$dir/$FT2_DIR" >"$out" 2>/dev/null &
  pid=$!
  ( sleep 7; kill -9 "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 & wd=$!
  wait "$pid"; rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  case "$rc" in 124|137|143) echo 124 ;; *) echo "$rc" ;; esac
}
guard_once() {   # r2383 K4·F2: 같은 local_sha 는 guard 1회(결과를 $TMP/cache.<sha> 에 둔다) · 7초 넘김만 1회 더
  cache="$TMP/cache.$1"
  if [ -f "$cache" ]; then cat "$cache"; return; fi
  rc=$(guard_rc "$1")
  case "$rc" in
    124|126|127)
      rc=$(guard_rc "$1") ;;
  esac
  printf '%s\n' "$rc" > "$cache"
  printf '%s\n' "$rc"
}
rc=0
while read -r local_ref local_sha remote_ref remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/ops/main-base)
      if [ "$remote_ref" = refs/heads/ops/main-base ]; then card_only "$local_sha" "$remote_sha"; k=$?; else k=1; fi
      [ "$k" = 0 ] && continue
      [ "$k" = 2 ] && echo "판정 불가 나노 가드 git rev-parse·diff 실패($remote_ref) rc=1" >&2
      echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — 착지 = master" >&2
      rc=1 ;;
    *)
      case "$local_sha" in "$ZERO") continue ;; esac   # r2383 F1: 가지 지우는 push = 검사 0
      need_guard "$local_sha" "$remote_sha"; k=$?
      [ "$k" = 1 ] && continue   # ft2 안 바뀜 = guard 0회
      if [ "$k" = 2 ]; then
        echo "판정 불가 나노 가드 legacy_guard merge-base rc=1" >&2
        echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — legacy_guard 판정 불가" >&2
        rc=1; continue
      fi
      [ -n "$TMP" ] || { TMP=$(mktemp -d 2>/dev/null) || TMP="$(mktemp -d -t nanoguard 2>/dev/null)"; }
      if [ -z "$TMP" ]; then
        echo "판정 불가 나노 가드 legacy_guard 임시폴더 rc=1" >&2
        echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — legacy_guard 판정 불가" >&2
        rc=1; continue
      fi
      g=$(guard_once "$local_sha")
      case "$g" in
        0) continue ;;
        1) n=$(grep -c . "$TMP/g.$local_sha.out" 2>/dev/null)
           first=$(grep -m 1 . "$TMP/g.$local_sha.out" 2>/dev/null)
           echo "PUSH_DENIED legacy_guard 위반 ${n}건 — 첫 줄: $first" >&2
           rc=1 ;;
        *) stage=실행
           [ "$g" = 124 ] && stage=시간
           [ "$g" = 127 ] && stage=python
           [ "$g" = 125 ] && stage=archive
           echo "판정 불가 나노 가드 legacy_guard $stage rc=$g" >&2
           echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — legacy_guard 판정 불가" >&2
           rc=1 ;;
      esac ;;
  esac
done
exit $rc
