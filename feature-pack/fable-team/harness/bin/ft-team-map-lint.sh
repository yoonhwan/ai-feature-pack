#!/usr/bin/env bash
# ft-team-map-lint.sh <팀>   (R318a · 파일 지도 검사)
#   design/<팀>/README.md «파일 지도» 표의 첫 칸 경로 ↔ 실제 파일 대조.
#     지도에 있는데 없음 = ERR(rc1) · 지도에 없는 «바닥 파일» = WARN(정리 후보 · rc0).
#   지도 경로 꼴: `{a,b}` 중괄호 전개 · `*` 글롭 · `<이름>` 자리표시(=*) · 끝 `/` = 폴더. 글롭은 0건이어도 ERR 아님.
#   현역 원장은 지도 표에 한 줄 등록하면 정리 후보에서 빠진다(등록 = 지도에 있음).
#   env: FT_REPO_ROOT(기본 git 루트). exit 0 = ERR 없음 · 1 = ERR · 2 = usage
set -uo pipefail
TEAM="${1:-}"; [ -n "$TEAM" ] && [ $# = 1 ] || { echo "usage: $0 <팀>" >&2; exit 2; }
ROOT="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || { echo "ERR 리포 루트를 못 찾았다(FT_REPO_ROOT 또는 git 안에서 실행)"; exit 1; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft-team-lib.sh" ] || { echo "ERR ft-team-lib.sh 없음: $HERE (팀 경로 단일 출처 · R382)"; exit 1; }
. "$HERE/ft-team-lib.sh"; export FT_REPO_ROOT="$ROOT"
D="$(ft_team_root "$TEAM" 2>&1)" || { echo "ERR $TEAM 폴더를 못 풀었다 — ${D#ERROR }"; exit 1; }; REL="$(ft_team_rel "$TEAM")"   # REL = 명단 칸 원문(끝 /)
[ -d "$D" ] || { echo "ERR ${REL} 폴더 없음"; exit 1; }
[ -f "$D/README.md" ] || { echo "ERR ${REL}README.md 없음 — ft-team-scaffold.sh $TEAM"; exit 1; }
python3 - "$D" "$REL" <<'PY'
import glob, os, re, sys
d, rel = sys.argv[1], sys.argv[2]
def expand(p):
    m = re.search(r'\{([^{}]*)\}', p)
    if not m: return [p]
    return [x for o in m.group(1).split(",") for x in expand(p[:m.start()] + o + p[m.end():])]
pats, in_map = [], False
for line in open(os.path.join(d, "README.md"), encoding="utf-8"):
    if line.startswith("#"): in_map = "파일 지도" in line; continue
    if not in_map or not line.startswith("|"): continue
    cell = line.split("|")[1] if line.count("|") >= 2 else ""
    for tok in re.findall(r'`([^`]+)`', cell):
        if re.fullmatch(r'[^\s]+', tok) and re.search(r'[./*<{]', tok): pats += expand(re.sub(r'<[^>]*>', '*', tok))
errs, warns, covered = 0, 0, set()
for p in pats:
    full = os.path.join(d, p)
    hits = glob.glob(full)
    if "*" not in p and not hits:
        print("ERR %s%s — 지도에 있으나 실재하지 않는다" % (rel, p)); errs += 1
    for h in hits: covered.add(os.path.relpath(h, d).split(os.sep)[0] if os.path.isdir(h) else os.path.relpath(h, d))
for f in sorted(os.listdir(d)):
    if f == ".DS_Store" or os.path.isdir(os.path.join(d, f)) or f in covered or f == "README.md": continue
    print("WARN %s%s — 지도 밖 바닥 파일(정리 후보)" % (rel, f)); warns += 1
print("%s errs=%d warns=%d" % ("ERR" if errs else "OK", errs, warns))
sys.exit(1 if errs else 0)
PY
