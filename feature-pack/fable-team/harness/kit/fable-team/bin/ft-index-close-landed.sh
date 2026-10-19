#!/usr/bin/env bash
# ft-index-close-landed.sh <판정문> [--team <팀>] [--dry-run]   (r456 · 판정 2349)
#   «이미 main 에 착지한» 카드를 DA 닫힘 판정문 1장으로 N장 닫는다 — 재설계 해제 쪽지 불요.
#   판정문 행 꼴: `## §N …` 절 안 «닫힘 — <카드 stem> — main `<40hex>` / PR …»
#   행마다: 팀 폴더(ft_team_root · 글자 조립 0) 대기/·진행/ 에서 카드 실재 → sha 가 origin/main 조상 →
#     (실행) 카드 «## 상태» 끝에 `- 착지: <sha> (DA 닫힘 <판정문>#§N · <날짜>)` 1줄(없을 때만) → ft-index-move <카드> 완성 --da <판정문>#§N --landed <sha>
#     (--dry-run) 쓰기 0 · 표만 «§N · 카드 · 위치 · 조상 · 착지 줄 · 예상(판정기 --closing 첫 줄)»
#   결과 1줄/카드: MOVED · REJECT <원문 첫 줄> · SKIP 카드 없음|이미 완성 · 끝 집계 1줄. 카드 없는 행·조상 아닌 sha 는 쓰기 0.
#   rc 0 = REJECT 0 · 1 = REJECT ≥1 · 2 = usage/팀 폴더 못 풂
set -uo pipefail
DAF=""; TEAM=""; DRY=0
while [ $# -gt 0 ]; do case "$1" in --team) TEAM="${2:-}"; shift 2;; --dry-run) DRY=1; shift;; -*) echo "unknown $1" >&2; exit 2;; *) DAF="$1"; shift;; esac; done
[ -f "$DAF" ] || { echo "usage: $0 <판정문> [--team <팀>] [--dry-run] — 판정문 없음: ${DAF:-(빈 값)}" >&2; exit 2; }
DAF="$(cd -- "$(dirname -- "$DAF")" && pwd)/$(basename -- "$DAF")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(git -C "$(dirname "$DAF")" rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR 판정문이 git 리포 밖: $DAF" >&2; exit 2; }
if [ -n "$TEAM" ]; then
  . "$HERE/ft-team-lib.sh" || { echo "ERROR ft-team-lib.sh 를 못 읽었다: $HERE" >&2; exit 2; }
  TROOT="$(FT_REPO_ROOT="$REPO" ft_team_root "$TEAM")" || { echo "ERROR 팀 폴더를 못 풀었다: $TEAM (design/TEAMS.md)" >&2; exit 2; }
else
  TROOT="$(dirname "$DAF")"   # 팀 미지정 = 판정문이 놓인 팀 폴더
fi
[ -d "$TROOT/indices" ] || { echo "ERROR 팀 폴더에 indices/ 없음: $TROOT (--team <팀>)" >&2; exit 2; }
ROWS="$(python3 -I - "$DAF" <<'PY'
import re, sys
sec = ""
for ln in open(sys.argv[1], encoding="utf-8", errors="replace"):
    h = re.match(r"^## .*?(§\d+)(?!\d)", ln)
    if ln.startswith("## "):
        sec = h.group(1) if h else ""
    m = re.search(r"닫힘\s*—\s*(\S+)\s*—\s*main\s*`?([0-9a-f]{40})\b", ln)
    if m and sec:
        print(f"{sec}\t{m.group(1)}\t{m.group(2)}")
PY
)"
[ -n "$ROWS" ] || { echo "ERROR 판정문에 «닫힘 — <카드> — main \`<40hex>\`» 행 0: $DAF" >&2; exit 2; }
n=0; mv=0; rj=0; sk=0; today="$(date '+%Y-%m-%d')"
[ "$DRY" = 1 ] && printf '%s\n' "| § | 카드 | 위치 | 조상 | 착지 줄 | 예상 |" "|---|---|---|---|---|---|"
while IFS=$'\t' read -r sec stem sha; do n=$((n+1))
  card=""; where=없음
  for d in 진행 대기; do [ -f "$TROOT/indices/$d/$stem.md" ] && { card="$TROOT/indices/$d/$stem.md"; where="$d"; break; }; done
  [ -z "$card" ] && [ -f "$TROOT/indices/완성/$stem.md" ] && where=완성
  anc=no; git -C "$REPO" merge-base --is-ancestor "$sha" origin/main 2>/dev/null && anc=ok
  has=무; [ -n "$card" ] && grep -qE "^- 착지:[[:space:]]*\`?$sha" "$card" && has=유
  if [ "$DRY" = 1 ]; then
    if [ "$where" = 완성 ]; then exp="SKIP 이미 완성"; elif [ -z "$card" ]; then exp="SKIP 카드 없음"; elif [ "$anc" != ok ]; then exp="REJECT LANDED-INVALID not-ancestor"
    else exp="$(python3 "$HERE/ft_da_hold_gate.py" "$card" --closing --da "$DAF#$sec" --landed "$sha" 2>&1 | head -1)"; fi
    printf '| %s | %s | %s | %s | %s | %s |\n' "$sec" "$stem" "$where" "$anc" "$has" "$exp"; continue
  fi
  if [ "$where" = 완성 ]; then echo "SKIP $stem 이미 완성"; sk=$((sk+1)); continue; fi
  if [ -z "$card" ]; then echo "SKIP $stem 카드 없음"; sk=$((sk+1)); continue; fi
  if [ "$anc" != ok ]; then echo "REJECT $stem LANDED-INVALID not-ancestor $sha (쓰기 0)"; rj=$((rj+1)); continue; fi
  if [ "$has" = 무 ]; then
    python3 -I - "$card" "- 착지: $sha (DA 닫힘 $(basename "$DAF")#$sec · $today)" <<'PY' || { echo "REJECT $stem 착지 줄 쓰기 실패"; rj=$((rj+1)); continue; }
import re, sys
p, line = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
m = re.search(r"^##\s*상태[^\n]*\n(.*?)(?=^##\s|\Z)", t, re.S | re.M)
if not m:
    sys.exit(1)
e = m.end(1)
rest = t[e:]
open(p, "w", encoding="utf-8").write(t[:e].rstrip("\n") + "\n" + line + "\n" + ("\n" + rest.lstrip("\n") if rest.strip() else ""))
PY
  fi
  out="$(bash "$HERE/ft-index-move.sh" "$card" 완성 --da "$DAF#$sec" --landed "$sha" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then echo "MOVED $stem"; mv=$((mv+1)); else echo "REJECT $stem $(printf '%s\n' "$out" | grep -m1 '^REJECT' || printf '%s' "${out%%$'\n'*}") rc=$rc"; rj=$((rj+1)); fi
done <<< "$ROWS"
[ "$DRY" = 1 ] && { echo "DRY rows=$n (쓰기 0)"; exit 0; }
echo "TOTAL rows=$n MOVED=$mv REJECT=$rj SKIP=$sk"
[ "$rj" = 0 ]
