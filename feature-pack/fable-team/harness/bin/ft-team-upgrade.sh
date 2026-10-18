#!/usr/bin/env bash
# ft-team-upgrade.sh [--dry-run] (--all | <팀>)   (R368 · 팀 틀 버전 비교 + 일괄 패치)
#   design/TEAMS.md 팀마다 명부(.fable-team/seats-<팀>.json · v65 = seats.json)의 `_tree_version` 과 키트 templates/team/VERSION 을 비교해
#   낮거나 없으면 ft-team-scaffold.sh(없는 칸만)를 돌리고 `_tree_version`·`_tree_version_note`(·비었으면 `_tree`)만 갱신한다. 멱등 · 기존 파일 0 변경.
#   --dry-run = `TEAM <팀> have=… want=… missing=<칸 수>` 표만(쓰기 0).
#   --check-teams = TEAMS.md 팀 집합 == TEAMSET.md 표 2 팀 집합 (차이 = ERROR 1줄 rc1)
#   --stamp <팀> = 틀 생성 없이 명부 버전만 기록(ft-team-scaffold.sh 가 틀을 만든 직후 부른다)
#   env: FT_REPO_ROOT · FT_ROSTER_DIR(기본 git 공용 루트의 .fable-team) · FT_TEAM_TEMPLATE_DIR
#   exit 0 = 완료 · 1 = REJECT/ERROR · 2 = usage
set -uo pipefail
DRY=0; ALL=0; CHECK=0; STAMP=0; TEAM=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift;; --all) ALL=1; shift;; --check-teams) CHECK=1; shift;; --stamp) STAMP=1; shift;;
  -*) echo "unknown $1" >&2; exit 2;; *) [ -z "$TEAM" ] && TEAM="$1" || exit 2; shift;; esac; done
USAGE="usage: $0 [--dry-run] (--all | <팀>) | --check-teams | --stamp <팀>"
[ "$CHECK" = 1 ] || [ "$ALL" = 1 ] || [ -n "$TEAM" ] || { echo "$USAGE" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT/design" ] || { echo "REJECT 리포 루트(design/)를 못 찾았다" >&2; exit 1; }
TEAMS="$ROOT/design/TEAMS.md"
[ -f "$TEAMS" ] || { echo "REJECT design/TEAMS.md 없음 — 팀 명단이 먼저다"; exit 1; }
[ -f "$HERE/ft-team-lib.sh" ] || { echo "REJECT ft-team-lib.sh 없음: $HERE (팀 경로 단일 출처 · R382)"; exit 1; }
. "$HERE/ft-team-lib.sh"; export FT_REPO_ROOT="$ROOT" FT_TEAMS_MD="$TEAMS"   # 팀 이름·폴더는 ft_team_names/ft_team_rel 한 곳(3꼴)
teams_md() { ft_team_names "$TEAMS"; }

if [ "$CHECK" = 1 ]; then
  SET="$ROOT/design/TEAMSET.md"; [ -f "$SET" ] || { echo "ERROR design/TEAMSET.md 없음"; exit 1; }
  set_teams() { awk '/^## 표 2/{f=1;next} /^## /{f=0} f&&/^\|/{n=split($0,c,"|"); t=c[2]; gsub(/[[:space:]]/,"",t); if(t!=""&&t!="팀"&&t!~/^-+$/)print t}' "$SET"; }
  a="$(teams_md | LC_ALL=C sort -u)"; b="$(set_teams | LC_ALL=C sort -u)"
  onlya="$(comm -23 <(echo "$a") <(echo "$b") | tr '\n' ' ')"; onlyb="$(comm -13 <(echo "$a") <(echo "$b") | tr '\n' ' ')"
  [ -z "$onlya" ] && [ -z "$onlyb" ] && { echo "OK teams=$(echo "$a" | grep -c .)"; exit 0; }
  echo "ERROR TEAMS.md ≠ TEAMSET 표 2 — TEAMS.md 에만: ${onlya:-없음}· TEAMSET 에만: ${onlyb:-없음}"; exit 1
fi

TPL="${FT_TEAM_TEMPLATE_DIR:-}"
[ -n "$TPL" ] || for c in "$HERE/../templates/team" "$ROOT/scripts/harness-install/fable-team/templates/team"; do [ -d "$c" ] && { TPL="$c"; break; }; done
WANT="$(tr -d '[:space:]' < "$TPL/VERSION" 2>/dev/null)"
[ -n "$WANT" ] || { echo "REJECT 틀 버전 파일 없음: ${TPL:-<없음>}/VERSION"; exit 1; }
RDIR="${FT_ROSTER_DIR:-}"
[ -n "$RDIR" ] || { c="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; RDIR="${c%/.git}/.fable-team"; }
[ -d "$RDIR" ] || RDIR="$ROOT/.fable-team"

# 명부 JSON 은 «줄 단위로» 필요한 키만 고친다(전체 재직렬화 0 · 들여쓰기·인라인 객체 보존) · 결과는 파싱 대조 후에만 쓴다.
read -r -d '' PY <<'PYEND'
import json, re, sys
cmd, path = sys.argv[1], sys.argv[2]
def ver(s):
    try: return tuple(int(x) for x in s.split("."))
    except ValueError: print(f"ERROR 버전 형식 틀림: {s}"); sys.exit(1)
if cmd == "cmp":
    print((ver(sys.argv[3]) > ver(sys.argv[4])) - (ver(sys.argv[3]) < ver(sys.argv[4]))); sys.exit(0)
raw = open(path, encoding="utf-8").read()
try: d = json.loads(raw)
except ValueError as e: print(f"ERROR 명부 JSON 읽기 실패 {path}: {e}"); sys.exit(1)
if cmd == "get":
    v = d.get("_tree_version") if isinstance(d, dict) else None
    print(v if isinstance(v, str) and v else ""); sys.exit(0)
want, note, tree = sys.argv[3], sys.argv[4], sys.argv[5]
lines = raw.split("\n")
j = lambda v: json.dumps(v, ensure_ascii=False)
new = {"_tree_version": want, "_tree_version_note": note}
if not (isinstance(d.get("_tree"), str) and d["_tree"]): new["_tree"] = tree
if not isinstance(d, dict) or not d: print(f"ERROR 명부가 비었다·객체 아님: {path}"); sys.exit(1)
if sum(1 for l in lines if l.strip()) == 1 and raw.lstrip().startswith("{"):   # 한 줄 JSON(seats-kk 꼴): 키 3개만 정규식 치환·앞에 삽입
    out = raw; ins = []
    for k, v in new.items():
        pat = re.compile(rf'"{k}"\s*:\s*"(?:[^"\\]|\\.)*"')
        if pat.search(out): out = pat.sub(lambda m: f'"{k}": {j(v)}', out, count=1)
        else: ins.append(f'"{k}": {j(v)}, ')
    i = out.index("{") + 1
    out = out[:i] + "".join(ins) + out[i:]
else:
    if lines[0].strip() != "{": print(f"ERROR 명부 형식 미지원(여는 중괄호 줄 + 키 줄, 또는 한 줄 JSON): {path}"); sys.exit(1)
    ind = next((re.match(r"\s+", l).group(0) for l in lines[1:] if re.match(r'\s+"', l)), None)
    if ind is None: print(f"ERROR 명부 들여쓰기를 못 찾았다: {path}"); sys.exit(1)
    pos = None; missing = []
    for k, v in new.items():
        hit = next((i for i, l in enumerate(lines) if re.match(rf'{ind}"{k}"\s*:', l)), None)
        if hit is None: missing.append(k); continue
        comma = "," if lines[hit].rstrip().endswith(",") else ""
        lines[hit] = f'{ind}"{k}": {j(v)}{comma}'
        if k == "_tree_version": pos = hit
    at = (pos if pos is not None else 0) + 1
    lines[at:at] = [f'{ind}"{k}": {j(new[k])},' for k in missing]
    out = "\n".join(lines)
try: d2 = json.loads(out)
except ValueError as e: print(f"ERROR 패치 결과가 JSON 이 아니다(쓰기 0) {path}: {e}"); sys.exit(1)
keep = {k: v for k, v in d.items() if k not in new}
if {k: v for k, v in d2.items() if k not in new} != keep or any(d2.get(k) != v for k, v in new.items()):
    print(f"ERROR 패치가 키 3개 밖을 바꿨다(쓰기 0) {path}"); sys.exit(1)
open(path, "w", encoding="utf-8").write(out)
PYEND
roster_of() { [ "$1" = v65 ] && echo "$RDIR/seats.json" || echo "$RDIR/seats-$1.json"; }
py() { python3 -I -c "$PY" "$@"; }

stamp() {  # <팀> <have> — 명부 있으면 버전 기록, 없으면 WARN
  local t="$1" have="$2" r; r="$(roster_of "$t")"
  [ -f "$r" ] || { echo "WARN $t 명부 없음 — _tree_version 기록 0 — 명부를 만든 뒤 ft-team-upgrade.sh $t"; return 0; }
  py patch "$r" "$WANT" "tree $WANT $(date +%F) ${have:-없음}→$WANT" "$(ft_team_rel "$t")STATE.md" || return 1
  echo "STAMP $t ${have:-없음}→$WANT"
}
have_of() { local r; r="$(roster_of "$1")"; [ -f "$r" ] && py get "$r" || true; }
uptodate() { [ -n "$1" ] && [ "$(py cmp x "$1" "$WANT")" -ge 0 ]; }
SC() { FT_REPO_ROOT="$ROOT" FT_TEAM_TEMPLATE_DIR="$TPL" FT_TEAM_NO_STAMP=1 bash "$HERE/ft-team-scaffold.sh" "$@"; }

one() {
  local t="$1" have out rc; teams_md | grep -qx "$t" || { echo "REJECT $t 은 design/TEAMS.md 명단에 없는 팀이다"; return 1; }
  have="$(have_of "$t")" || return 1
  if uptodate "$have"; then
    [ "$DRY" = 1 ] && echo "TEAM $t have=$have want=$WANT missing=0" || echo "SKIP $t up-to-date ($have ≥ $WANT)"; return 0; fi
  if [ "$DRY" = 1 ]; then
    out="$(SC --dry-run "$t")"; rc=$?; [ "$rc" = 0 ] || { echo "$out"; return 1; }
    echo "TEAM $t have=${have:-없음} want=$WANT missing=$(echo "$out" | grep -c '^WOULD-CREATE')"; return 0; fi
  out="$(SC "$t")"; rc=$?; echo "$out"; [ "$rc" = 0 ] || return 1
  stamp "$t" "$have"
}

if [ "$STAMP" = 1 ]; then
  [ -n "$TEAM" ] || { echo "$USAGE" >&2; exit 2; }
  have="$(have_of "$TEAM")" || exit 1; uptodate "$have" && exit 0; stamp "$TEAM" "$have"; exit $?
fi
if [ "$ALL" = 1 ]; then rc=0; for t in $(teams_md); do one "$t" || rc=1; done; exit "$rc"; fi
one "$TEAM"
