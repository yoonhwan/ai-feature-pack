#!/usr/bin/env bash
# ft-root-bin-shim.sh --root <리포 루트> --live <라이브 bin> [--ref <ref>] [--repo <키트 리포>] [--path <키트 트리 경로>] [--dry-run]   (R201 · master 가 설치)
#   --repo·--path 기본 = 하네스 코드 루트(ft-harness-root.sh)의 리포 · 그 리포 기준 kit/fable-team/bin (r385 · --root 는 연결 파일을 둘 프로젝트 루트)
#   루트 `<루트>/.fable-team/bin` 의 옛 부분 사본을 «라이브 bin 으로 넘기는 연결 파일» 로 바꾼다.
#   ① `<루트>/.fable-team/LIVE_BIN` 에 라이브 경로 1줄 (+ R382: `<루트>/.fable-team/LIVE_ROOT` 데이터 루트 절대경로 1줄 — 없을 때만 만든다 · `--live-root <경로>` 없으면 라이브 bin/../.. 를 «설치 때 한 번» 풀어 적고 읽는 쪽은 유도 0 · 있으면 보존·다르면 NOTE)  ② 키트(--ref 의 --path 트리)의 *.sh·*.py 이름 중 라이브 bin 에 실재하는 것마다 연결 파일
#   ③ 연결 파일이 아닌 기존 항목(옛 사본·.bak-*·__pycache__·키트 밖 이름)은 `<루트>/.fable-team/bin.stale-<시각>/` 로 «옮긴다»(삭제 0 · 되돌리기 = 그 폴더를 bin 으로)
#   키트 밖 이름은 연결하지 않고 `UNKNOWN <이름>` 목록으로 보고. 멱등: 두 번째 실행 = 쓰기 0 · MOVED 0.
#   출력 끝줄 `SHIM n · MOVED m · UNKNOWN k` (--dry-run 은 쓰기 0 · 같은 숫자 · `PLAN …` 줄).  종료: 0 · 2 usage · 3 ERROR(조용한 통과 0)
#   r494 --init: 루트 bin 이 없을 때 루트가 «설치된 리포(공용 루트 .fable-team/LIVE_BIN 실재)의 git 워크트리 최상위» 면 bin 을 만들고 위 흐름 그대로
#     (LIVE_ROOT 기본 = 공용 루트 경로 그 자체 · 공용 루트 LIVE_ROOT 파일 값 복사 0) · 공용 루트 자체·git 밖·설치 안 된 리포 = ERROR rc3 + 사유
set -uo pipefail
usage() { echo "usage: $0 --root <리포 루트> --live <라이브 bin> [--live-root <데이터 루트>] [--ref <ref>] [--repo <키트 리포>] [--path <키트 경로>] [--init] [--dry-run]" >&2; exit 2; }
err()   { echo "ERROR $*"; exit 3; }
wt_common() {  # r494: $1 = 루트 → «설치된 리포의 git 워크트리 최상위» 면 공용 루트 물리 경로 · 아니면 사유 + rc1
  local rp top gd cp
  rp="$(cd -- "$1" 2>/dev/null && pwd -P)" || { echo "루트 폴더 없음: $1"; return 1; }
  top="$(git -C "$rp" rev-parse --show-toplevel 2>/dev/null)" || { echo "git 밖: $rp"; return 1; }
  [ "$(cd -- "$top" && pwd -P)" = "$rp" ] || { echo "워크트리 최상위가 아님: $rp (최상위 $top)"; return 1; }
  gd="$(git -C "$rp" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "git 공용 폴더를 못 풂: $rp"; return 1; }
  cp="$(cd -- "${gd%/.git}" 2>/dev/null && pwd -P)" || { echo "공용 루트 폴더 없음: ${gd%/.git}"; return 1; }
  [ "$cp" != "$rp" ] || { echo "공용 루트 자체다: $rp — 공용 루트 설치는 install.sh --apply --project $rp"; return 1; }
  [ -f "$cp/.fable-team/LIVE_BIN" ] || { echo "설치된 리포가 아님(공용 루트 LIVE_BIN 없음): $cp/.fable-team/LIVE_BIN"; return 1; }
  echo "$cp"
}

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT=""; LIVE=""; LROOT=""; REF="${FT_DRIFT_REF:-origin/main}"; REPO=""; TPATH=""; DRY=0; INIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift;;
    --init) INIT=1; shift;;
    --root|--live|--live-root|--ref|--repo|--path) [ $# -ge 2 ] || usage
      case "$1" in --root) ROOT="$2";; --live) LIVE="$2";; --live-root) LROOT="$2";; --ref) REF="$2";; --repo) REPO="$2";; --path) TPATH="$2";; esac; shift 2;;
    *) usage;;
  esac
done
[ -n "$ROOT" ] && [ -n "$LIVE" ] || usage
case "$LIVE" in /*) ;; *) err "--live 는 절대경로(/ 로 시작)여야 한다: $LIVE";; esac
NEWBIN=0; WTC=""   # r494: 새로 만들 bin · 워크트리의 공용 루트
if [ ! -d "$ROOT/.fable-team/bin" ]; then
  [ "$INIT" = 1 ] || err "루트 bin 없음: $ROOT/.fable-team/bin (새 워크트리면 --init)"
  WTC="$(wt_common "$ROOT")" || err "--init 불가 — $WTC"
  NEWBIN=1
elif [ "$INIT" = 1 ]; then WTC="$(wt_common "$ROOT")" || WTC=""; fi   # bin 있는 루트 = 지금 흐름 · LIVE_ROOT 기본값만 같은 규칙
[ -d "$LIVE" ] || err "라이브 bin 없음: $LIVE"
ROOT="$(cd -- "$ROOT" && pwd)"; LIVE="$(cd -- "$LIVE" && pwd)"
if [ -n "$LROOT" ]; then case "$LROOT" in /*) ;; *) err "--live-root 는 절대경로(/ 로 시작)여야 한다: $LROOT";; esac; [ -d "$LROOT" ] || err "--live-root 폴더 없음: $LROOT"; LROOT="$(cd -- "$LROOT" && pwd)"
elif [ -n "$WTC" ]; then LROOT="$WTC"
else LROOT="$(cd -- "$LIVE/../.." 2>/dev/null && pwd)" || err "LIVE_ROOT 를 라이브 bin/../.. 로 풀지 못했다: $LIVE (--live-root 로 지정)"; fi
RBIN="$ROOT/.fable-team/bin"
if [ -z "$REPO" ] || [ -z "$TPATH" ]; then  # 키트 트리 = 하네스 코드 루트(팩) 리포 · 프로젝트 루트(--root) 리포가 아니다 (r385)
  [ -f "$HERE/ft-harness-root.sh" ] || err "해석기 없음: $HERE/ft-harness-root.sh — --repo·--path 를 준다"; . "$HERE/ft-harness-root.sh"
  hr="$(ft_harness_root "$HERE")" || err "하네스 루트를 못 풂(FT_HARNESS_ROOT · ../HARNESS_ROOT 없음) — --repo·--path 를 준다"
  rk="$(ft_harness_kit "$hr")" || err "하네스 루트가 git 안이 아님: $hr — --repo·--path 를 준다"
  [ -n "$REPO" ] || REPO="${rk%%$'\t'*}"; [ -n "$TPATH" ] || TPATH="${rk#*$'\t'}"
fi
sha="$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}")" || err "ref 를 풀 수 없음: $REF (repo=$REPO)"
kit="$(git -C "$REPO" ls-tree --name-only "$sha" "${TPATH%/}/")" || err "ls-tree 실패: $REF:$TPATH"
[ -n "$kit" ] || err "ref 에 경로가 없음: $REF:$TPATH"
kitnames="$(printf '%s\n' "$kit" | sed 's|.*/||')"
if [ "$NEWBIN" = 1 ]; then  # r494: 모든 검사를 통과한 뒤에만 만든다(ERROR = 생성 0)
  if [ "$DRY" = 1 ]; then echo "PLAN init $RBIN (새 워크트리 · 공용 루트 $WTC)"
  else mkdir -p "$RBIN" || err "bin 못 만듦: $RBIN"; echo "INIT $RBIN (새 워크트리 · 공용 루트 $WTC)"; fi
fi

MARK="# ft-root-bin-shim:"
shim_body() {  # $1 = 도구 이름
  local name="$1" runner="bash"
  case "$name" in *.py) runner="python3";; esac
  cat <<EOF
#!/usr/bin/env bash
$MARK $name → LIVE_BIN (루트 옛 사본이 아니다 — ft-root-bin-shim.sh 생성 · 수정하지 말 것)
_h="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]:-\$0}")" && pwd)"
_f="\$_h/../LIVE_BIN"
_l=""; [ -f "\$_f" ] && _l="\$(sed -n '1p' "\$_f" | tr -d '\\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*\$//')"
[ -n "\$_l" ] || { echo "ERROR LIVE_BIN 이 없거나 비었다: \$_f"; exit 3; }
case "\$_l" in /*) ;; *) echo "ERROR LIVE_BIN 이 절대경로(/ 로 시작)가 아니다: \$_l (\$_f)"; exit 3;; esac
[ -f "\$_l/$name" ] || { echo "ERROR 라이브 도구 없음: \$_l/$name"; exit 3; }
exec $runner "\$_l/$name" "\$@"
EOF
}

nshim=0; nmoved=0; unknown=""; nunk=0; tomove=""
want=""  # 연결 대상 이름
while IFS= read -r n; do
  [ -n "$n" ] || continue
  case "$n" in *.sh|*.py) ;; *) continue;; esac
  [ -f "$LIVE/$n" ] || continue
  want="$want$n"$'\n'
done <<< "$kitnames"

# 기존 항목 분류: 연결 파일(그대로 두거나 갱신) / 옮길 것
shopt -s nullglob dotglob
for p in "$RBIN"/*; do
  n="${p##*/}"
  if [ -f "$p" ] && [ ! -L "$p" ] && head -3 "$p" | grep -qF "$MARK" && grep -qxF -- "$n" <<< "$want"; then continue; fi
  tomove="$tomove$n"$'\n'
  if ! grep -qxF -- "$n" <<< "$kitnames" && ! case "$n" in *.bak*|__pycache__) true;; *) false;; esac; then
    unknown="$unknown$n"$'\n'; nunk=$((nunk + 1))
  fi
done
shopt -u nullglob dotglob
nmoved=$(printf '%s' "$tomove" | grep -c .)

STALE="$ROOT/.fable-team/bin.stale-$(date +%Y%m%d-%H%M%S)"
if [ "$nmoved" -gt 0 ]; then
  while IFS= read -r n; do [ -n "$n" ] || continue
    if [ "$DRY" = 1 ]; then echo "PLAN move $n → ${STALE##*/}/"; else
      [ -d "$STALE" ] || mkdir -p "$STALE" || err "stale 폴더 못 만듦: $STALE"
      mv -- "$RBIN/$n" "$STALE/$n" || err "옮기기 실패: $n"
    fi
  done <<< "$tomove"
fi
[ -z "$unknown" ] || while IFS= read -r n; do [ -n "$n" ] && echo "UNKNOWN $n (키트 밖 — 연결 0 · stale 로 옮김)"; done <<< "$unknown"

lr_cur=""; [ -f "$ROOT/.fable-team/LIVE_ROOT" ] && lr_cur="$(sed -n '1p' "$ROOT/.fable-team/LIVE_ROOT")"
if [ "$DRY" = 1 ]; then echo "PLAN LIVE_BIN=$LIVE → $ROOT/.fable-team/LIVE_BIN"; [ -n "$lr_cur" ] && echo "PLAN LIVE_ROOT 보존 $lr_cur" || echo "PLAN LIVE_ROOT=$LROOT → $ROOT/.fable-team/LIVE_ROOT"
else
  cur=""; [ -f "$ROOT/.fable-team/LIVE_BIN" ] && cur="$(sed -n '1p' "$ROOT/.fable-team/LIVE_BIN")"
  [ "$cur" = "$LIVE" ] || printf '%s\n' "$LIVE" > "$ROOT/.fable-team/LIVE_BIN" || err "LIVE_BIN 쓰기 실패"
  if [ -z "$lr_cur" ]; then printf '%s\n' "$LROOT" > "$ROOT/.fable-team/LIVE_ROOT" || err "LIVE_ROOT 쓰기 실패"; echo "LIVE_ROOT $LROOT (새로 씀)"
  elif [ "$lr_cur" != "$LROOT" ]; then echo "NOTE LIVE_ROOT 보존 $lr_cur (이번 값 $LROOT 와 다름 — 바꾸려면 파일 1줄을 손으로 고친다)"; fi
fi
while IFS= read -r n; do [ -n "$n" ] || continue
  nshim=$((nshim + 1))
  [ "$DRY" = 1 ] && continue
  body="$(shim_body "$n")"
  if [ ! -f "$RBIN/$n" ] || [ "$(cat "$RBIN/$n")" != "$body" ]; then printf '%s\n' "$body" > "$RBIN/$n" || err "연결 파일 쓰기 실패: $n"; fi
  [ -x "$RBIN/$n" ] || chmod 755 "$RBIN/$n"
done <<< "$want"
[ "$DRY" = 1 ] && echo "PLAN shim n=$nshim"
echo "SHIM $nshim · MOVED $nmoved · UNKNOWN $nunk"
exit 0
