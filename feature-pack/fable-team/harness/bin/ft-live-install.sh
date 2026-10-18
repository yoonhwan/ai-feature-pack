#!/usr/bin/env bash
# ft-live-install.sh --bin <라이브 bin> --ref <sha|ref> [--repo <리포>] [--path <트리 경로>] [--dry-run]
# ft-live-install.sh --restore <manifest>
#   main 에 병합된 키트(ref)를 라이브 bin 에 «추적된 도구 한 번 실행» 으로 설치한다 (R215 · master 가 cp/mv 손 설치 대신 `bash` 한 줄).
#   ref 는 origin/main 조상만 · 일치하면 쓰기 0 · DIFF·MISSING·MODE 를 «파일 이름 고유 집합» 으로 설치 · EXTRA 는 KEEP-EXTRA 줄만 · 설치 전 tar 백업(실패면 쓰기 0)
#   git blob → tmp(.<이름>.tmp-li.<pid>) → 검사 «전부» 통과 뒤에만 mv · mv 전 <bak>.manifest · 오류·TERM·INT 는 manifest 로 원복 · 끝나면 manifest.done · 미완 manifest 면 다음 실행 REJECT
#   쓰는 실행(설치·--restore)은 bin 단위 mkdir 잠금 <bin>/../state/live-install/lock.d 안에서만(pid+시각 · 죽은 pid·60초 초과는 회수 · 5초 못 얻으면 REJECT) · 끝에 drift-check 재검사 OK 여야 INSTALLED
#   종료: 0 = 설치·일치·dry-run·복원 · 1 = REJECT·재검사 DRIFT·RESTORE-FAIL · 2 = usage · 3 = ERROR(조용한 통과 금지 · #0 RULE). --restore = manifest 수동 원복(RESTORED n / RESTORE-FAIL).
set -uo pipefail
usage() { echo "usage: $0 --bin <폴더> --ref <sha|ref> [--repo <리포>] [--path <트리 경로>] [--dry-run] | --restore <manifest>" >&2; exit 2; }
err()   { echo "ERROR $*" >&2; exit 3; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CHK="$HERE/ft-live-bin-drift-check.sh"
BIN=""; SD=""; ACTIVE=0; MAN=""; HELD=0; LOCKD=""

cleanup_tmp() { [ -z "$BIN" ] || rm -f "$BIN"/.*.tmp-li."$$"; }   # 내 tmp 만 — 남의 실행 tmp 는 건드리지 않는다
on_exit() {
  local rc=$?; cleanup_tmp
  if [ "$ACTIVE" = 1 ]; then ACTIVE=0; restore_from "$MAN" || rc=3; fi
  if [ "$HELD" = 1 ]; then rm -f "$LOCKD/owner"; rmdir "$LOCKD" 2>/dev/null; fi
  exit "$rc"
}
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
lock_acquire() {   # lock_acquire <state 폴더> — 못 얻으면 REJECT rc 1(쓰기 0)
  local d="$1/lock.d" n=0 p ts
  mkdir -p "$1" 2>/dev/null || err "상태 폴더를 못 만듦: $1 — 쓰기 0"
  until mkdir "$d" 2>/dev/null; do
    p="$(sed -n 1p "$d/owner" 2>/dev/null)"; ts="$(sed -n 2p "$d/owner" 2>/dev/null)"; [ -n "$ts" ] || ts="$(mtime "$d")"
    if { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } || [ $(( $(date +%s) - ${ts:-0} )) -gt 60 ]; then
      if mv "$d" "$d.stale.$$" 2>/dev/null; then   # 회수는 mv 한 번(한 실행만 성공)
        [ -z "$p" ] || rm -f "$BIN"/.*.tmp-li."$p"
        rm -f "$d.stale.$$/owner"; rmdir "$d.stale.$$" 2>/dev/null
      fi
      continue
    fi
    n=$((n + 1)); [ "$n" -lt 5 ] || { echo "ERROR REJECT 다른 설치 진행 중 pid=${p:-?} (쓰기 0)" >&2; exit 1; }
    sleep 1
  done
  HELD=1; LOCKD="$d"; printf '%s\n%s\n' "$$" "$(date +%s)" > "$d/owner" || err "잠금 owner 쓰기 실패: $d"
}
restore_from() {   # restore_from <manifest> — 원복 뒤 하나씩 검증한 것만 센다(되돌렸다고 단정하지 않는다)
  local m="$1" tarf="${1%.manifest}" rb rn ex md nm=0 bad=""
  rb="$(sed -n 's/^bin=//p' "$m")"; [ -d "$rb" ] || { echo "RESTORE-FAIL bin 폴더 없음: $rb manifest=$m"; return 1; }
  rm -f "$rb"/.*.tmp-li*   # 호출자는 잠금을 쥐고 있어 남은 tmp 는 전부 고아다
  while read -r rn ex md; do
    case "$rn" in ref=*|bin=*) continue;; esac
    if [ "$ex" = 0 ]; then rm -f "$rb/$rn"; [ ! -e "$rb/$rn" ] || bad="$bad $rn(삭제 실패)"
    else { tar -xf "$tarf" -C "$rb" "$rn" 2>/dev/null && chmod "$md" "$rb/$rn" 2>/dev/null; } || bad="$bad $rn(복원 실패)"; fi
    nm=$((nm + 1))
  done < "$m"
  if [ -n "$bad" ]; then echo "RESTORE-FAIL$bad — 백업 $tarf manifest=$m (원복 단정 불가 · 상태 확인 필요)"; return 1; fi
  : > "$m.done"; echo "RESTORED n=$nm bin=$rb manifest=$m"
}
pending_check() {   # 강제 종료(KILL)로 못 닫힌 설치가 있으면 그 위에 덮어쓰지 않는다
  local m; for m in "$SD"/*.manifest; do [ -f "$m" ] && [ ! -e "$m.done" ] && { echo "ERROR REJECT 이전 설치 미완 — --restore $m (쓰기 0)" >&2; exit 1; }; done; return 0
}
analyze() {   # → dout drc want (같은 파일의 DIFF+MODE 는 한 줄 «DIFF+MODE a.sh» — 이후 모든 단계가 이 고유 집합을 쓴다)
  dout="$(bash "$CHK" --bin "$BIN" --repo "$REPO" --ref "$sha" --path "$TPATH")"; drc=$?
  case "$drc" in 0|1) ;; *) printf '%s\n' "$dout" >&2; err "drift-check rc=$drc";; esac
  want="$(printf '%s\n' "$dout" | awk '/^(DIFF|MISSING|MODE) /{r[$2]=(r[$2]=="" ? $1 : r[$2] "+" $1)} END{for(n in r) print r[n], n}' | sort -k2)"
  nwant="$(printf '%s\n' "$want" | grep -c .)"
}
settle() {   # analyze 결과만으로 끝낼 수 있으면(일치·EXTRA 만·dry-run) 쓰기 0 으로 끝낸다
  [ "$drc" != 0 ] || { echo "OK 이미 일치 ref=$short bin=$BIN"; exit 0; }
  if [ -z "$want" ] || [ "$DRY" = 1 ]; then
    printf '%s\n' "$dout" | sed -n 's/^EXTRA /KEEP-EXTRA /p'
    [ -n "$want" ] || { echo "OK 설치 대상 없음(EXTRA 만) ref=$short"; exit 0; }
    printf '%s\n' "$want" | sed 's/^/WOULD /'; echo "DRY-RUN n=$nwant ref=$short 쓰기 0"; exit 0
  fi
}
REPO=""; REF=""; TPATH="scripts/harness-install/fable-team/bin"; DRY=0; RESTORE=""
while [ $# -gt 0 ]; do
  if [ "$1" = --dry-run ]; then DRY=1; shift; continue; fi
  [ $# -ge 2 ] || usage
  case "$1" in --bin) BIN="$2";; --repo) REPO="$2";; --ref) REF="$2";; --path) TPATH="$2";; --restore) RESTORE="$2";; *) usage;; esac
  shift 2
done
trap on_exit EXIT; trap 'exit 143' TERM; trap 'exit 130' INT
if [ -n "$RESTORE" ]; then
  [ -f "$RESTORE" ] || err "manifest 없음: $RESTORE"
  BIN="$(sed -n 's/^bin=//p' "$RESTORE")"; SD="$(cd -- "$(dirname -- "$RESTORE")" && pwd)"
  lock_acquire "$SD"; restore_from "$RESTORE"; exit $?
fi
[ -n "$BIN" ] && [ -n "$REF" ] || usage
[ -d "$BIN" ] || err "bin 폴더 없음: $BIN"
[ -f "$CHK" ] || err "drift-check 없음: $CHK"
BIN="$(cd -- "$BIN" && pwd)"; SD="$BIN/../state/live-install"
pending_check
if [ -z "$REPO" ]; then
  gc="$(git -C "$BIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || err "bin 이 git 안이 아니라 리포를 못 풂 — --repo 를 준다: $BIN"
  REPO="${gc%/.git}"
fi
sha="$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}")" || err "ref 를 풀 수 없음: $REF (repo=$REPO)"
main="$(git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}')" || err "origin/main 을 풀 수 없음 (repo=$REPO)"
git -C "$REPO" merge-base --is-ancestor "$sha" "$main"; arc=$?
if [ "$arc" = 1 ]; then echo "ERROR REJECT $REF 는 origin/main 의 조상이 아님 — 병합된 sha 만 설치한다 (쓰기 0)" >&2; exit 1; fi
[ "$arc" = 0 ] || err "merge-base 실패 rc=$arc (repo=$REPO)"
short="${sha:0:12}"

analyze; settle                       # 읽기만: 일치·dry-run 은 잠금 없이 끝난다
lock_acquire "$SD"                    # 여기부터 쓰기 — 잠금 안에서 «다시» 미완 검사·분석한다(기다리는 사이 상태가 바뀐다)
pending_check; analyze; settle
printf '%s\n' "$dout" | sed -n 's/^EXTRA /KEEP-EXTRA /p'
# ④ 백업 — MISSING 은 기존 파일이 없다. 백업이 틀리면 아무것도 쓰지 않는다.
bak="$SD/bak-$short-$(date +%Y%m%dT%H%M%S).tar"; [ ! -e "$bak" ] || bak="${bak%.tar}-$$.tar"
have="$(printf '%s\n' "$want" | grep -v '^MISSING ' | sed 's/^[^ ]* //')"
if [ -n "$have" ]; then printf '%s\n' "$have" | tar -cf "$bak" -C "$BIN" -T - 2>/dev/null; else tar -cf "$bak" -T /dev/null 2>/dev/null; fi || err "tar 백업 실패: $bak — 쓰기 0"
nhave="$(printf '%s\n' "$have" | grep -c .)"
[ "$(tar -tf "$bak" 2>/dev/null | wc -l | tr -d ' ')" = "$nhave" ] || err "백업 검증 실패(파일 수 ≠ $nhave): $bak — 쓰기 0"
# ⑤ 스테이징 — 전부 검사를 통과해야 mv 한다(한 파일이라도 틀리면 라이브 bin 은 그대로).
while read -r k n; do
  [ -n "$n" ] || continue
  entry="$(git -C "$REPO" ls-tree "$sha" "${TPATH%/}/$n" | cut -f1)"; read -r mode type blob <<< "$entry"
  [ "$type" = blob ] || err "키트에서 blob 을 못 찾음: $n — 쓰기 0 (백업 $bak)"
  t="$BIN/.$n.tmp-li.$$"
  git -C "$REPO" cat-file blob "$blob" > "$t" || err "blob 읽기 실패: $n — 쓰기 0"
  if [ "$mode" = 100755 ]; then chmod 755 "$t"; else chmod 644 "$t"; fi
  [ "$(git -C "$REPO" hash-object --no-filters "$t")" = "$blob" ] || err "tmp 해시 불일치: $n — 쓰기 0"
  case "$n" in
    *.sh) bash -n "$t" 2>/dev/null || err "bash -n 실패: $n — 라이브 bin 그대로(백업 $bak)";;
    *.py) python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$t" 2>/dev/null || err "py 문법 실패: $n — 라이브 bin 그대로(백업 $bak)";;
  esac
done <<< "$want"
# ⑥ mv 전에 원복 정보(manifest)를 남기고, 이후의 오류·신호는 EXIT 트랩이 그 manifest 로 되돌린다.
MAN="$bak.manifest"
{
  echo "ref=$sha"; echo "bin=$BIN"
  while read -r k n; do
    [ -n "$n" ] || continue
    ex=1; md=-; case "$k" in MISSING) ex=0;; esac
    if [ "$ex" = 1 ]; then md="$(stat -f %Lp "$BIN/$n" 2>/dev/null || stat -c %a "$BIN/$n")"; fi
    echo "$n $ex $md"
  done <<< "$want"
} > "$MAN" || err "manifest 쓰기 실패: $MAN — 쓰기 0"
ACTIVE=1
while read -r k n; do
  [ -n "$n" ] || continue
  mv -f "$BIN/.$n.tmp-li.$$" "$BIN/$n" || err "mv 실패: $n — 백업($bak)·manifest 로 원복 시도"
done <<< "$want"
: > "$MAN.done" || err "manifest.done 쓰기 실패: $MAN"
ACTIVE=0
# ⑦ 재검사 — EXTRA 는 보존하기로 했으니 남아도 실패가 아니다.
rout="$(bash "$CHK" --bin "$BIN" --repo "$REPO" --ref "$sha" --path "$TPATH")"; rrc=$?
left="$(printf '%s\n' "$rout" | grep -E '^(DIFF|MISSING|MODE) ')"
if [ "$rrc" = 0 ] || { [ "$rrc" = 1 ] && [ -z "$left" ]; }; then echo "INSTALLED n=$nwant ref=$short bak=$bak"; exit 0; fi
printf '%s\n' "$rout"
echo "ERROR 설치 뒤 재검사 rc=$rrc — 백업 $bak" >&2
exit 1
