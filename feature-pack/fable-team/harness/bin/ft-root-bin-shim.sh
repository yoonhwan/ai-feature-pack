#!/usr/bin/env bash
# ft-root-bin-shim.sh --root <리포 루트> --live <라이브 bin> [--ref <ref>] [--path <키트 트리 경로>] [--dry-run]   (R201 · master 가 설치)
#   루트 `<루트>/.fable-team/bin` 의 옛 부분 사본을 «라이브 bin 으로 넘기는 연결 파일» 로 바꾼다.
#   ① `<루트>/.fable-team/LIVE_BIN` 에 라이브 경로 1줄  ② 키트(--ref 의 --path 트리)의 *.sh·*.py 이름 중 라이브 bin 에 실재하는 것마다 연결 파일
#   ③ 연결 파일이 아닌 기존 항목(옛 사본·.bak-*·__pycache__·키트 밖 이름)은 `<루트>/.fable-team/bin.stale-<시각>/` 로 «옮긴다»(삭제 0 · 되돌리기 = 그 폴더를 bin 으로)
#   키트 밖 이름은 연결하지 않고 `UNKNOWN <이름>` 목록으로 보고. 멱등: 두 번째 실행 = 쓰기 0 · MOVED 0.
#   출력 끝줄 `SHIM n · MOVED m · UNKNOWN k` (--dry-run 은 쓰기 0 · 같은 숫자 · `PLAN …` 줄).  종료: 0 · 2 usage · 3 ERROR(조용한 통과 0)
set -uo pipefail
usage() { echo "usage: $0 --root <리포 루트> --live <라이브 bin> [--ref <ref>] [--path <키트 경로>] [--dry-run]" >&2; exit 2; }
err()   { echo "ERROR $*"; exit 3; }

ROOT=""; LIVE=""; REF="${FT_DRIFT_REF:-origin/main}"; TPATH="scripts/harness-install/fable-team/bin"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift;;
    --root|--live|--ref|--path) [ $# -ge 2 ] || usage
      case "$1" in --root) ROOT="$2";; --live) LIVE="$2";; --ref) REF="$2";; --path) TPATH="$2";; esac; shift 2;;
    *) usage;;
  esac
done
[ -n "$ROOT" ] && [ -n "$LIVE" ] || usage
case "$LIVE" in /*) ;; *) err "--live 는 절대경로(/ 로 시작)여야 한다: $LIVE";; esac
[ -d "$ROOT/.fable-team/bin" ] || err "루트 bin 없음: $ROOT/.fable-team/bin"
[ -d "$LIVE" ] || err "라이브 bin 없음: $LIVE"
ROOT="$(cd -- "$ROOT" && pwd)"; LIVE="$(cd -- "$LIVE" && pwd)"
RBIN="$ROOT/.fable-team/bin"
sha="$(git -C "$ROOT" rev-parse --verify -q "$REF^{commit}")" || err "ref 를 풀 수 없음: $REF (repo=$ROOT)"
kit="$(git -C "$ROOT" ls-tree --name-only "$sha" "${TPATH%/}/")" || err "ls-tree 실패: $REF:$TPATH"
[ -n "$kit" ] || err "ref 에 경로가 없음: $REF:$TPATH"
kitnames="$(printf '%s\n' "$kit" | sed 's|.*/||')"

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

if [ "$DRY" = 1 ]; then echo "PLAN LIVE_BIN=$LIVE → $ROOT/.fable-team/LIVE_BIN"
else
  cur=""; [ -f "$ROOT/.fable-team/LIVE_BIN" ] && cur="$(sed -n '1p' "$ROOT/.fable-team/LIVE_BIN")"
  [ "$cur" = "$LIVE" ] || printf '%s\n' "$LIVE" > "$ROOT/.fable-team/LIVE_BIN" || err "LIVE_BIN 쓰기 실패"
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
