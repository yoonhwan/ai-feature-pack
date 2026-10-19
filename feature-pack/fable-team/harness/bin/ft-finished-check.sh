#!/usr/bin/env bash
# ft-finished-check.sh <폴더|브랜치> [--repo <리포>] — 끝난 것 판정기 하나(r444 · planner 설계 §2 E0~E3). 정리 도구는 전부 이것만 본다. 삭제·이동 0.
#   출력 1행 = `FINISHED|EMPTY|ACTIVE|ORPHAN <대상>` · 2행부터 근거 `E0~E3 ok|no …` · `branch=… sha=… card=…`. rc 0 = 판정함 · 2 = 판정 불가(ERROR — 호출자는 «안 끝남» 으로 다룬다).
#   E0 폴더 porcelain 0(폴더 없으면 참) · E1 카드 `- 착지: <sha>` 가 기준(main) 조상 · E2 카드가 indices/완성/ · E3 좌석 없음(tmux 세션·명부 seats*.json 키·폴더 cwd 프로세스 0)
#   순서: E0·E3 하나라도 거짓 = ACTIVE(살아 있는 것 먼저) → 가지가 기준 대비 커밋 0 = EMPTY → 카드 0·2+ = ORPHAN → E1·E2 거짓 = ACTIVE → FINISHED.
#   카드 = 가지 이름 nano/<slug>[-rN] 의 slug 와 «카드 파일 이름 slug»(ft-nano-spawn 과 같은 규칙) 가 같은 것 — 팀 폴더는 ft_team_cands_ref(명단 = ref · 폴더 = 리포)만.
#   env: FT_FINISHED_MAIN(기준 ref · 기본 origin/main 있으면 그것 없으면 main) · FT_TEAMS_REF · FT_TMUX_BIN · FT_TMUX_SOCKET · FT_SEATS_DIR(기본 <리포>/.fable-team)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="${1:-}"; shift 2>/dev/null; R=""
while [ $# -gt 0 ]; do case "$1" in --repo) R="${2:-}"; shift 2;; *) echo "usage: $0 <폴더|브랜치> [--repo <리포>]" >&2; exit 2;; esac; done
[ -n "$T" ] || { echo "usage: $0 <폴더|브랜치> [--repo <리포>]" >&2; exit 2; }
err() { echo "ERROR $1"; exit 2; }
[ -f "$HERE/ft-team-lib.sh" ] || err "ft-team-lib.sh 없음: $HERE"
. "$HERE/ft-team-lib.sh"
DIR=""; BR=""
if [ -d "$T" ]; then DIR="$(cd "$T" && pwd -P)"; [ -n "$R" ] || R="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  BR="$(git -C "$DIR" symbolic-ref -q --short HEAD 2>/dev/null)"
else BR="${T#refs/heads/}"; fi
[ -n "$R" ] || R="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$R" ] && [ -d "$R" ] || err "리포를 못 찾음(--repo 필요): ${R:-<없음>}"
M="${FT_FINISHED_MAIN:-}"; [ -n "$M" ] || { git -C "$R" rev-parse -q --verify origin/main >/dev/null && M=origin/main || M=main; }
git -C "$R" rev-parse -q --verify "$M^{commit}" >/dev/null || err "기준 ref 없음: $M"
if [ -n "$BR" ]; then SHA="$(git -C "$R" rev-parse -q --verify "refs/heads/$BR^{commit}")" || err "가지 없음: $BR"
  [ -n "$DIR" ] || DIR="$(git -C "$R" worktree list --porcelain | awk -v b="branch refs/heads/$BR" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')"
else SHA="$(git -C "$DIR" rev-parse -q --verify HEAD)" || err "폴더 HEAD 없음: $DIR"; fi
SLUG="${BR#nano/}"; [ "$SLUG" != "$BR" ] || SLUG=""; SLUG="$(printf '%s' "$SLUG" | sed -E 's/-r[0-9]+$//')"
# 카드 찾기 — 팀 명단(ref) × 폴더(리포) 후보의 indices/{대기,진행,완성}/*.md 중 파일 이름 slug 가 같은 것
CARDS=()
if [ -n "$SLUG" ]; then
  MD="$(mktemp)" || err "mktemp 실패"; trap 'rm -f "$MD"' EXIT
  git -C "$R" show "${FT_TEAMS_REF:-origin/main}:design/TEAMS.md" > "$MD" 2>/dev/null || err "팀 명단(${FT_TEAMS_REF:-origin/main}:design/TEAMS.md)을 못 읽음: $R"
  # 카드 루트 = FT_FINISHED_CARD_ROOTS(: 구분) → 원장 워크트리(FT_NANO_LEDGER_WT · 기본 <리포>/.worktrees/v6-realtime-live) → 리포 — 카드가 나온 «첫 루트» 만 쓴다(미커밋 이동이 루트마다 다르다)
  IFS=: read -r -a BASES <<< "${FT_FINISHED_CARD_ROOTS:-${FT_NANO_LEDGER_WT:-$R/.worktrees/v6-realtime-live}}"; BASES+=("$R")
  for b in "${BASES[@]}"; do [ -d "$b" ] && [ "${#CARDS[@]}" = 0 ] || continue
    for t in $(ft_team_names "$MD"); do
      while IFS= read -r c; do [ -n "$c" ] || continue
        for f in "$c"/indices/대기/*.md "$c"/indices/진행/*.md "$c"/indices/완성/*.md; do [ -f "$f" ] || continue
          s="$(basename "$f" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"; [ "$s" = "$SLUG" ] && CARDS+=("$f")
        done
      done < <(ft_team_cands_ref "$b" "$t" "${FT_TEAMS_REF:-origin/main}" 2>/dev/null)
    done
  done
fi
CARD=""; [ "${#CARDS[@]}" = 1 ] && CARD="${CARDS[0]}"
# E0 — 폴더 porcelain 0
E0=1; E0W="폴더 없음"; if [ -n "$DIR" ] && [ -d "$DIR" ]; then E0W="$DIR"; [ -z "$(git -C "$DIR" status --porcelain 2>/dev/null)" ] || { E0=0; E0W="미커밋 있음 $DIR"; }; fi
# E3 — 좌석 없음. tmux 목록을 못 읽으면 «없음» 으로 세지 않는다(ACTIVE · #0 RULE)
E3=1; E3W=""; TB="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
for _t in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do [ -n "$TB" ] || { [ -x "$_t" ] && TB="$_t"; }; done
if [ -n "$SLUG" ]; then
  if S="$("${TB:-false}" ${FT_TMUX_SOCKET:+-S "$FT_TMUX_SOCKET"} list-sessions -F '#{session_name}' 2>/dev/null)"; then
    hit="$(printf '%s\n' "$S" | grep -F -- "$SLUG#" | head -1)"; [ -z "$hit" ] || { E3=0; E3W="tmux $hit"; }
  else E3=0; E3W="tmux 목록 못 읽음(tmux=${TB:-없음})"; fi
  if [ "$E3" = 1 ]; then hit="$(python3 - "$SLUG#" "${FT_SEATS_DIR:-$R/.fable-team}" <<'PY'
import glob, json, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[2], "seats*.json"))):
    try: d = json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError): continue
    for k, v in d.items():
        if sys.argv[1] in k and isinstance(v, dict) and not v.get("_replaced_by"): print(os.path.basename(f) + ":" + k); sys.exit(0)
PY
)"; [ -z "$hit" ] || { E3=0; E3W="명부 $hit"; }; fi
fi
if [ "$E3" = 1 ] && [ -n "$DIR" ] && [ -d "$DIR" ]; then
  hit="$(lsof -w -d cwd -Fpn 2>/dev/null | awk -v d="$DIR" '/^p/{p=substr($0,2)} /^n/{n=substr($0,2); if (n==d || index(n, d "/")==1) {print "pid " p; exit}}')"
  [ -z "$hit" ] || { E3=0; E3W="cwd $hit"; }
fi
[ -n "$E3W" ] || E3W="좌석 0"
# E1·E2 — 카드
E1=0; E1W="카드 없음"; E2=0; E2W="카드 없음"
if [ -n "$CARD" ]; then
  L="$(sed -nE 's/^[[:space:]]*-[[:space:]]*착지:[[:space:]]*([0-9a-f]{7,40}).*/\1/p' "$CARD" | tail -1)"
  if [ -z "$L" ]; then E1W="착지 줄 없음"
  elif git -C "$R" merge-base --is-ancestor "$L" "$M" 2>/dev/null; then E1=1; E1W="착지 $L ⊂ $M"
  else E1W="착지 $L 가 $M 조상 아님"; fi
  case "$CARD" in */indices/완성/*) E2=1; E2W="완성/";; *) E2W="$(basename "$(dirname "$CARD")")/";; esac
fi
AHEAD="$(git -C "$R" rev-list --count "$M..$SHA" 2>/dev/null)" || err "rev-list 실패: $M..$SHA"
if [ "$E0" = 0 ] || [ "$E3" = 0 ]; then V=ACTIVE
elif [ "$AHEAD" = 0 ]; then V=EMPTY
elif [ -z "$CARD" ]; then V=ORPHAN
elif [ "$E1" = 0 ] || [ "$E2" = 0 ]; then V=ACTIVE
else V=FINISHED; fi
echo "$V $T"
echo "E0 $([ "$E0" = 1 ] && echo ok || echo no) $E0W"
echo "E1 $([ "$E1" = 1 ] && echo ok || echo no) $E1W"
echo "E2 $([ "$E2" = 1 ] && echo ok || echo no) $E2W"
echo "E3 $([ "$E3" = 1 ] && echo ok || echo no) $E3W"
echo "branch=${BR:-<detached>} sha=$SHA ahead=$AHEAD main=$M card=${CARD:-<${#CARDS[@]}개>} dir=${DIR:-<없음>}"
