#!/bin/bash
# ft-version.sh — «깔린 fable-team 이 무엇인가» 를 한 줄로 (하네스 0.4 단위 2 · GOAL-harness-v2 축 C).
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT.★
#
# 버전의 출처는 manifest.json 한 곳이다. 스크립트 헤더의 「Seatbelt x.y」는 «기능 세대» 표기이지 버전이 아니다.
#
# 사용:
#   ft-version.sh                → 한 줄:  ft=<manifest.version> bin#<실행본 지문 8> src=<팩 sha7|nogit>[+dirty] bin=<ok|drift N,missing M,local L> boot=<ok|missing> guide=<sha16|missing>
#     ★bin# 이 «실행본» 좌표다★ — 실행 폴더($HERE)의 *.sh (이름, sha256) 정렬 목록의 sha256 앞 8자. 한 파일 한 글자만 바뀌어도 달라진다.
#     src= 는 «소스 checkout» 상태(팩 git). 실행본과 무관하게 바뀐다 — 둘을 섞어 읽지 않는다(DA-unit2 r1 발견 1).
#     bin= 의 missing 은 «전체 팩 대비» 표기다 — 의도적 미배포(tmux 계열·ft-lib 등)가 상수로 섞이니 경보로 읽지 않는다. 경보는 deps 모드.
#   ft-version.sh short          → ft=<ver> bin#<지문> src=<sha7>[+dirty] 만 (spawn 래퍼 발주문 머리용 — 700자 mbox 절단 대비).
#   ft-version.sh check [--root <워크트리>] [--strict]
#                                → 같은 줄 + 파일별 상세(stderr). exit 0 = ok/drift/local, exit 1 = missing>0 (--strict 일 때만), exit 2 = 팩 자체를 못 찾음.
#   ft-version.sh json           → 같은 값 JSON.
#   ft-version.sh deps <script>  → 그 스크립트가 «실제로 실행하는» 의존만 검사. dangling 0 이면 exit 0, 아니면 목록 + exit 1.
#                                  spawn 래퍼 첫 줄 게이트가 이것을 쓴다 (journey#1 판정 2026-09-23: 전체 missing 이 아니라 실행 의존만 막는다).
#                                  규칙: ①주석 줄(#)의 이름은 의존이 아니다 ②경로는 스크립트가 푸는 방식대로 — $HERE/x.sh 는 같은 폴더,
#                                        $HERE/../comm/mbox.sh 는 comm 폴더. 맨 이름만 나온 문자열(echo·usage)은 세지 않는다.
#
# 대조 = 팩 skill/scripts/*.sh 의 sha256 vs <워크트리>/.fable-team/bin/*.sh 의 sha256.
#   drift   = 양쪽에 있는데 해시가 다름(로컬 패치 — 의도된 경우가 있어 REJECT 사유가 아니다)
#   missing = 팩에는 있는데 워크트리에 없음
#   local   = 워크트리에만 있음(팩 밖 스크립트 — REJECT 사유 아님)
# boot  = ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md 존재 (단위 5 — tmuxc 재설치로 원복되면 여기서 잡힌다)
# guide = COMM-GUIDE.md sha256 앞16 — BOOT 헤더의 값과 다르면 BOOT 매핑표 줄 번호가 낡은 것(DA-unit5 발견 10)
set -uo pipefail
MODE="${1:-}"; case "$MODE" in ""|line|short|check|json|deps) [ $# -gt 0 ] && shift;; --*) MODE="line";; *) echo "usage: ft-version.sh [line|short|check|json|deps <script>] [--root <wt>] [--strict]" >&2; exit 2;; esac

# ── deps 모드: 실행 의존만 ─────────────────────────────────────────
if [ "$MODE" = deps ]; then
  T="${1:-}"; [ -f "$T" ] || { echo "usage: ft-version.sh deps <script>" >&2; exit 2; }
  D="$(cd -- "$(dirname -- "$T")" && pwd)"
  MISS=(); SEEN=""
  # 코드 줄만(앞이 # 인 줄 제외) · $HERE/… $BINDIR/… $(dirname "$0")/… 형태의 «경로로 부르는» 스크립트만
  while IFS= read -r ref; do
    case "$ref" in
      '$HERE/../comm/'*|'$BINDIR/../comm/'*) p="$D/../comm/${ref##*/}" ;;
      *) p="$D/${ref##*/}" ;;
    esac
    case " $SEEN " in *" $ref "*) continue;; esac; SEEN="$SEEN $ref"
    [ -f "$p" ] || MISS+=("$ref -> $p")
  done < <(grep -vE '^\s*#' "$T" | grep -oE '\$(HERE|BINDIR)/(\.\./comm/)?[A-Za-z0-9_.-]+\.sh|\$\(dirname "\$0"\)/[A-Za-z0-9_.-]+\.sh' | sed 's|\$(dirname "\$0")|$HERE|' | sort -u)
  if [ ${#MISS[@]} -eq 0 ]; then echo "deps=ok $(basename "$T")"; exit 0; fi
  echo "deps=DANGLING ${#MISS[@]} $(basename "$T")"; for m in "${MISS[@]}"; do echo "  $m"; done; exit 1
fi

ROOT=""; STRICT=0
while [ $# -gt 0 ]; do case "$1" in
  --root) ROOT="$2"; shift 2;; --strict) STRICT=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 팩 루트: 이 파일이 팩 안(skill/scripts)에 있으면 그 위, 런타임 사본이면 심링크 ~/.claude/skills/fable-team 을 따라간다.
PACK=""
if [ -f "$HERE/../../manifest.json" ]; then PACK="$(cd "$HERE/../.." && pwd)"
elif [ -L "$HOME/.claude/skills/fable-team" ]; then PACK="$(cd "$(readlink "$HOME/.claude/skills/fable-team")/.." && pwd)"
elif [ -d "$HOME/.claude/skills/fable-team" ]; then PACK="$(cd "$HOME/.claude/skills/fable-team/.." && pwd)"; fi
[ -n "$PACK" ] && [ -f "$PACK/manifest.json" ] || { echo "ft=unknown (팩 manifest.json 을 찾지 못함: HERE=$HERE)" >&2; exit 2; }

VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version","?"))' "$PACK/manifest.json" 2>/dev/null || echo '?')"
SHA7="$(git -C "$PACK" rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"
DIRTY=""; [ "$SHA7" != nogit ] && [ -n "$(git -C "$PACK" status --porcelain -- "$PACK/skill/scripts" 2>/dev/null)" ] && DIRTY="+dirty"

# ROOT(대조할 워크트리) — 실행 폴더가 <wt>/.fable-team/bin 이면 그 wt(호출 cwd 에 안 갈린다 · DA-unit2 r1 발견 2). --root 가 우선.
if [ -z "$ROOT" ]; then
  case "$HERE" in */.fable-team/bin) ROOT="$(cd "$HERE/../.." && pwd)";; *) ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)";; esac
fi
BIN="$ROOT/.fable-team/bin"
SCR="$PACK/skill/scripts"
# 실행본 지문 = $HERE 의 *.sh (이름, sha256) 정렬 목록의 sha256 앞 8 — 실행 폴더가 곧 실행본
FP="$( (cd "$HERE" && for f in *.sh; do [ -f "$f" ] && printf '%s %s\n' "$f" "$(shasum -a 256 "$f" | cut -c1-64)"; done) | sort | shasum -a 256 | cut -c1-8 )"
[ -n "$FP" ] || FP="none"

h() { shasum -a 256 "$1" 2>/dev/null | cut -c1-16; }
DRIFT=(); MISSING=(); LOCAL=(); OK=0
for f in "$SCR"/*.sh; do
  b="$(basename "$f")"
  if [ -f "$BIN/$b" ]; then
    if [ "$(h "$f")" = "$(h "$BIN/$b")" ]; then OK=$((OK+1)); else DRIFT+=("$b"); fi
  else MISSING+=("$b"); fi
done
if [ -d "$BIN" ]; then for f in "$BIN"/*.sh; do [ -f "$f" ] || continue; b="$(basename "$f")"; [ -f "$SCR/$b" ] || LOCAL+=("$b"); done; fi

BOOT="$HOME/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md"
GUIDE="$HOME/.claude/skills/tmuxc/COMM-GUIDE.md"
BOOT_ST="missing"; [ -f "$BOOT" ] && BOOT_ST="ok"
GUIDE_SHA="missing"; [ -f "$GUIDE" ] && GUIDE_SHA="$(h "$GUIDE")"
BOOT_GUIDE_SHA=""; [ -f "$BOOT" ] && BOOT_GUIDE_SHA="$(grep -oE 'sha256 앞16 = `[0-9a-f]{16}`' "$BOOT" | grep -oE '[0-9a-f]{16}' | head -1)"
GUIDE_ST="$GUIDE_SHA"; [ -n "$BOOT_GUIDE_SHA" ] && [ "$BOOT_GUIDE_SHA" != "$GUIDE_SHA" ] && GUIDE_ST="$GUIDE_SHA(BOOT 표는 $BOOT_GUIDE_SHA — 낡음)"

if [ ${#DRIFT[@]} -eq 0 ] && [ ${#MISSING[@]} -eq 0 ]; then BIN_ST="ok"; else BIN_ST="drift ${#DRIFT[@]},missing ${#MISSING[@]}"; fi
[ ${#LOCAL[@]} -gt 0 ] && BIN_ST="$BIN_ST,local ${#LOCAL[@]}"
[ -d "$BIN" ] || BIN_ST="absent"
[ -z "$BOOT_GUIDE_SHA" ] && [ -f "$BOOT" ] && GUIDE_ST="$GUIDE_SHA(BOOT 표 해시 없음 — 대조 불가)"
LINE="ft=${VER} bin#${FP} src=${SHA7}${DIRTY} bin=${BIN_ST} boot=${BOOT_ST} guide=${GUIDE_ST}"

case "$MODE" in
  ""|line) echo "$LINE" ;;
  short) echo "ft=${VER} bin#${FP} src=${SHA7}${DIRTY}" ;;
  check)
    echo "$LINE"
    { echo "pack=$PACK"; echo "bin=$BIN"; echo "same=$OK"
      for x in "${DRIFT[@]}";   do echo "DRIFT   $x"; done
      for x in "${MISSING[@]}"; do echo "MISSING $x"; done
      for x in "${LOCAL[@]}";   do echo "local   $x"; done; } >&2
    if [ "$STRICT" = 1 ] && [ ${#MISSING[@]} -gt 0 ]; then exit 1; fi ;;
  json)
    python3 - "$VER" "$SHA7$DIRTY" "$OK" "$BOOT_ST" "$GUIDE_SHA" "$BOOT_GUIDE_SHA" "${DRIFT[*]:-}" "${MISSING[*]:-}" "${LOCAL[*]:-}" "$FP" "$HERE" "$BIN" "$([ -d "$BIN" ] && echo 1 || echo 0)" <<'PY'
import json,sys
a=sys.argv[1:]
print(json.dumps({"version":a[0],"bin_fingerprint":a[9],"exec_dir":a[10],"src_sha":a[1],"same":int(a[2]),"boot":a[3],"guide_sha16":a[4],"boot_table_sha16":a[5],
  "bin_dir":a[11],"bin_present":a[12]=="1","drift":a[6].split(),"missing":a[7].split(),"local":a[8].split()},ensure_ascii=False))
PY
    ;;
  *) echo "usage: ft-version.sh [line|short|check|json] [--root <wt>] [--strict]" >&2; exit 2 ;;
esac
