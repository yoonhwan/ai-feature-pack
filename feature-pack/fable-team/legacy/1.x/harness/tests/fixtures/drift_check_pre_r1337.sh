#!/usr/bin/env bash
# ft-live-bin-drift-check.sh --bin <폴더> [--repo <리포>] [--ref <ref>] [--path <트리 경로>]
#   라이브 도구 폴더(<FT_BIN>)가 git ref 의 main 키트 트리와 같은지 «읽기만» 검사한다 (카드 live-bin-drift-check · Issue 816 ②③).
#   기준 = `git ls-tree <ref> <path>/` 의 blob 행(모드·blob·이름). 워크트리 체크아웃이 아니다(로컬 main 은 뒤처질 수 있다).
#   --repo·--path 기본 = 하네스 코드 루트(ft-harness-root.sh)의 리포 · 그 리포 기준 kit/fable-team/bin (r385).
#   종료: 0 = OK · 1 = DRIFT(항목 줄 + HINT) · 2 = usage · 3 = ERROR(ref·repo 못 품 — 조용한 통과 금지 · #0 RULE).
#   fetch 하지 않는다 · 어긋남을 직접 cp 로 고치지 않는다(master 집행).
set -uo pipefail
usage() { echo "usage: $0 --bin <폴더> [--repo <리포>] [--ref <ref>] [--path <트리 경로>]" >&2; exit 2; }
err()   { echo "ERROR $*"; exit 3; }

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN=""; REPO=""; REF="${FT_DRIFT_REF:-origin/main}"; TPATH=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --bin) BIN="$2";; --repo) REPO="$2";; --ref) REF="$2";; --path) TPATH="$2";;
    *) usage;;
  esac
  shift 2
done
[ -n "$BIN" ] || usage
[ -d "$BIN" ] || err "bin 폴더 없음: $BIN"
BIN="$(cd -- "$BIN" && pwd)"

stale_copy() {  # r413: 프로젝트 .fable-team/bin 이 shim 아닌 옛 통째 사본(LIVE_BIN·shim·해석기 0 · 파일 ≥1)인가
  case "$BIN" in */.fable-team/bin) ;; *) return 1;; esac
  [ ! -f "$BIN/../LIVE_BIN" ] && [ ! -f "$BIN/ft-harness-root.sh" ] || return 1
  local f n=0
  for f in "$BIN"/*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    head -3 "$f" | grep -qF '# ft-root-bin-shim:' && return 1
    n=$((n + 1))
  done
  [ "$n" -ge 1 ]
}
if stale_copy; then  # 해석기 호출 «앞» — 옛 사본은 하네스 루트를 못 풀어 «main 키트와 다르다» 로 오인된다
  hr="${FT_HARNESS_ROOT:-}"; [ -n "$hr" ] || { [ -f "$HERE/../HARNESS_ROOT" ] && hr="$(head -1 "$HERE/../HARNESS_ROOT")"; }
  if [ -n "$hr" ]; then inst="$hr/install.sh"; else inst="<하네스>/harness/install.sh"; fi
  err "옛 설치 사본(shim 아님 · LIVE_BIN 없음): $BIN — bash $inst --apply --project ${BIN%/.fable-team/bin}"
fi

if [ -z "$REPO" ] || [ -z "$TPATH" ]; then  # 기본 = 하네스 코드 루트(팩)의 키트 bin 트리 (r385 · 리포 루트 전제 0)
  [ -f "$HERE/ft-harness-root.sh" ] || err "해석기 없음: $HERE/ft-harness-root.sh — --repo·--path 를 준다"; . "$HERE/ft-harness-root.sh"
  hr="$(ft_harness_root "$HERE")" || err "하네스 루트를 못 풂(FT_HARNESS_ROOT · ../HARNESS_ROOT 없음) — --repo·--path 를 준다"
  rk="$(ft_harness_kit "$hr")" || err "하네스 루트가 git 안이 아님: $hr — --repo·--path 를 준다"
  [ -n "$REPO" ] || REPO="${rk%%$'\t'*}"; [ -n "$TPATH" ] || TPATH="${rk#*$'\t'}"
fi
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || err "리포 아님: $REPO"
sha="$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}")" || err "ref 를 풀 수 없음: $REF (repo=$REPO)"
tree="$(git -C "$REPO" ls-tree "$sha" "${TPATH%/}/")" || err "ls-tree 실패: $REF:$TPATH"
[ -n "$tree" ] || err "ref 에 경로가 없음: $REF:$TPATH"

items=""; files=0; names=""
add() { items="$items$1"$'\n'; }
while IFS=$'\t' read -r meta path; do
  read -r mode type blob <<< "$meta"
  [ "$type" = blob ] || continue
  name="${path##*/}"; files=$((files + 1)); names="$names$name"$'\n'
  f="$BIN/$name"
  if [ ! -f "$f" ]; then add "MISSING $name"; continue; fi
  h="$(git -C "$REPO" hash-object --no-filters "$f")" || err "hash-object 실패: $f"
  [ "$h" = "$blob" ] || add "DIFF $name"
  if [ "$mode" = 100755 ]; then [ -x "$f" ] || add "MODE $name"; else [ ! -x "$f" ] || add "MODE $name"; fi
done <<< "$tree"

for f in "$BIN"/*; do
  [ -f "$f" ] || continue
  name="${f##*/}"
  case "$name" in *.bak*) continue;; esac
  grep -qxF -- "$name" <<< "$names" || add "EXTRA $name"
done

short="${sha:0:12}"
if [ -z "$items" ]; then echo "OK ref=$REF@$short bin=$BIN files=$files"; exit 0; fi
sorted="$(printf '%s' "$items" | sort)"
echo "DRIFT n=$(printf '%s\n' "$sorted" | grep -c .) ref=$REF@$short bin=$BIN"
printf '%s\n' "$sorted"
echo "HINT master 라이브 cp 필요 — 하네스 팀 폴더의 PLAN-release-0.4-and-816-20261007.md 집행 순서 2~4(tar 백업 → cp → diff 0줄)"
exit 1
