#!/usr/bin/env bash
# ft-index-move-canon.sh <카드> <워크트리> <landed:""|S|T..S>   (stdin = 판정문 §N 절 본문)
#   ft-index-move.sh 진행→완성의 정본 게이트 + 랜딩 commit 사실 검사 (판정 440 설계 r2 §6-1 · 판정 444).
#   출력 한 줄: `OK<TAB>정본 <경로> §<절>[ · 정본 …]` 또는 `OK<TAB>정본 영향 없음: <이유>` 또는 `REJECT<TAB><사유>` · 항상 exit 0.
#   랜딩 브랜치 ref = env FT_LAND_REF(기본 origin/main) · 검사 전 fetch 하지 않는다 · 검사를 끄는 값 없음.
#   r937: 착지 리포 판정 = ft_landed_repo(ft-team-lib.sh) — sha 가 실제로 있는 리포(카드 리포·팩 리포)와 그 리포의 ref 를 쓴다.
#     표식 = 판정문 §절의 «닫힘 — <카드> — main|main(팩) `<sha>`» 줄(main(팩) = 팩 리포 · main = 카드 리포).
set -uo pipefail
CARD="${1:-}"; WT="${2:-}"; LANDED="${3:-}"
BODY="$(cat)"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
rej() { printf 'REJECT\t%s\n' "$1"; exit 0; }
. "$HERE/ft-team-lib.sh" 2>/dev/null || rej "ft-team-lib.sh 를 못 읽었다: $HERE (착지 리포를 못 정한다)"

# ① 카드 줄 검사 — 「정본 갱신:」 줄 «전부» 파일·절 실재 · 없으면 「정본 영향 없음」 · 출력 UPD 줄들 + 마지막 OK/REJECT
RES="$(python3 - "$CARD" "$WT" <<'PY'
import re, sys, os
card = open(sys.argv[1], encoding="utf-8").read().splitlines()
wt = sys.argv[2]
pre = r'^[\s>*\-]*'
upd = [m for m in (re.match(pre + r'정본 갱신(?: 줄)?\s*:\s*(\S+?)\s*§\s*(.+?)\s*$', l) for l in card) if m]
non = [m for m in (re.match(pre + r'정본 영향 없음\s*:\s*(.*?)\s*$', l) for l in card) if m]
can = [m for m in (re.match(pre + r'정본화\s*:\s*(.+?)\s*$', l) for l in card) if m]
def reject(why):
    print("REJECT\t" + why); sys.exit(0)
notes = []
# 정본화 줄(R318a) — 허용 뿌리: docs/architect/ · docs/rules/ · design/<TEAMS.md 팀>/GUIDE-*.md · design/<팀>/README.md · 실재 .md 파일만(.. · 심볼릭 탈출 REJECT)
teams = set()   # 팀 폴더 접두(design/<팀> · design/teams/<팀> — TEAMS.md 폴더 칸 꼴1·꼴2 · R382)
try:
    for l in open(os.path.join(wt, "design/TEAMS.md"), encoding="utf-8"):
        t = re.search(r'\|\s*`?(design/(?:teams/)?[A-Za-z0-9_-]+)/`?\s*\|', l)
        if t: teams.add(t.group(1))
except OSError:
    pass
def canon_root(p):
    parts = p.split("/")
    if len(parts) > 2 and parts[0] == "docs" and parts[1] in ("architect", "rules"):
        return os.path.join(wt, "docs", parts[1])
    if len(parts) >= 3 and "/".join(parts[:-1]) in teams and (parts[-1] == "README.md" or re.fullmatch(r'GUIDE-.+\.md', parts[-1])):
        return os.path.join(wt, *parts[:-1])
    return None
for m in can:
    for p in [x.strip() for x in m.group(1).split(",")]:
        if p.startswith("/") or ".." in p.split("/"):
            reject("정본화 줄의 경로가 허용 뿌리 밖이다(절대경로 또는 ..): " + p)
        root = canon_root(p)
        if root is None or not p.endswith(".md"):
            reject("정본화 줄의 경로가 허용 뿌리 밖이다 — docs/architect/ · docs/rules/ · design/<팀>/GUIDE-*.md · design/<팀>/README.md(팀 = design/TEAMS.md): " + p)
        real = os.path.realpath(os.path.join(wt, p)); rroot = os.path.realpath(root); rwt = os.path.realpath(wt)
        if os.path.commonpath([rwt, rroot]) != rwt:
            reject("정본화 줄의 허용 뿌리 자체가 워크트리 밖 심볼릭 링크다: " + p)
        if os.path.commonpath([rroot, real]) != rroot:
            reject("정본화 줄의 경로가 허용 뿌리 밖으로 나간다(심볼릭 링크): " + p)
        if not os.path.isfile(os.path.join(wt, p)):
            reject("정본화 줄의 파일이 없다: " + p)
        notes.append("정본화 " + p)
for m in upd:
    path, sec = m.group(1), m.group(2)
    if not path.startswith("docs/architect/") or not path.endswith(".md"):
        reject("정본 갱신 줄의 경로는 docs/architect/….md 여야 한다: " + path)
    full = os.path.join(wt, path)
    root = os.path.realpath(os.path.join(wt, "docs/architect"))
    real = os.path.realpath(full)
    if ".." in path.split("/") or os.path.commonpath([root, real]) != root:
        reject("정본 갱신 줄의 경로가 docs/architect/ 밖으로 나간다(.. 또는 심볼릭 링크): " + path)
    if not os.path.isfile(full):
        reject("정본 갱신 줄의 파일이 없다: " + path)
    heads = [l for l in open(full, encoding="utf-8", errors="ignore").read().splitlines() if l.startswith("#")]
    tok = sec.split()[0]
    if not any(sec in h or tok in h for h in heads):
        reject("정본 문서에 그 절 제목이 없다: " + path + " §" + sec)
    print("UPD\t" + path + "\t" + sec)
    notes.append("정본 " + path + " §" + sec)
if upd or can:
    print("OK\t" + " · ".join(notes)); sys.exit(0)
for m in non:
    why = re.sub(r'^이유\s*=\s*', '', m.group(1)).strip()
    if len(why) >= 10:
        print("OK\t정본 영향 없음: " + why); sys.exit(0)
    reject("「정본 영향 없음」 이유가 10자 미만이다")
reject("카드에 「정본 갱신: docs/architect/….md §<절>」 · 「정본화: <경로>[, <경로>…]」 · 「정본 영향 없음: <이유 ≥10자>」 중 한 줄이 없다")
PY
)" || { printf 'REJECT\t정본 게이트 검사 실행 실패(python3)\n'; exit 0; }
LAST="$(printf '%s\n' "$RES" | tail -1)"
case "${LAST%%$'\t'*}" in OK|REJECT) ;; *) rej "정본 게이트 검사 실행 실패(python3)";; esac
[ "${LAST%%$'\t'*}" = REJECT ] && { printf '%s\n' "$LAST"; exit 0; }
UPDS="$(printf '%s\n' "$RES" | grep '^UPD' | cut -f2)"

# ② 랜딩 commit 사실 검사 — 갱신 카드는 --landed 필수 · 영향 없음 카드는 있을 때 (가)만
if [ -z "$LANDED" ]; then
  [ -z "$UPDS" ] || rej "정본 갱신 카드는 --landed <랜딩 commit> 필수"
  printf '%s\n' "$LAST"; exit 0
fi
case "$LANDED" in *..*) T="${LANDED%%..*}"; S="${LANDED##*..}";; *) T=""; S="$LANDED";; esac
REF="${FT_LAND_REF:-origin/main}"
# r937: 착지 리포 = sha 가 실제로 있는 리포(ft_landed_repo) — 표식 줄 = 이 카드의 «닫힘 — <카드> — main…» 줄(§절 본문에서)
STEM="$(basename "$CARD" .md)"
MARKER="$(printf '%s\n' "$BODY" | awk -v s="$STEM" 'BEGIN{p="(닫힘|CLOSE)[[:space:]]*—[[:space:]]*" s "[[:space:]]*—[[:space:]]*main"} $0 ~ p{print;exit}')"   # r959: «닫힘 — <카드> — main…» 정확한 모양만 — 절 헤더 오인 금지
PACK=""; [ -f "$HERE/ft-harness-root.sh" ] && PACK="$(. "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE" 2>/dev/null)"
# r937 r3: 루트 조회도 ft_git_capped — 한 후보의 루트 조회가 실패(rc≠0 · 시간 초과 포함)면 그 후보를 빈 값으로 넘기지 않고 REJECT
if [ -n "$PACK" ]; then PACK_H="$PACK"; PACK="$(ft_git_capped 7 "$PACK_H" rev-parse --show-toplevel)" || rej "팩 리포($PACK_H) 루트 조회 실패(rc=$?) — 통과 0"; fi
# r959: «표식 오기(팩 착지)» 보정은 ft_landed_repo 의 기본 동작 — 부르는 쪽마다 붙이지 않는다(네 호출이 같은 판정)
LR="$(ft_landed_repo "$S" "$WT" "$PACK" "$MARKER")" || rej "${LR#REJECT }"
REPO_LANDED="${LR%%$'\t'*}"; SFULL="${LR##*$'\t'}"
# r937 r2 (T1·T2): 모든 git 조회 = ft_git_capped(7초 · 재시도 1) · 허용 rc 를 넘은 값(124 시간 초과 · 128 실행 실패)은 «조회 실패» = REJECT(«없음» 으로 읽지 않는다)
#   gq <허용 rc> <사유> <git 인자…> → GQ_OUT = 출력 · rc 그대로. 허용 rc 초과 = «조회 실패» = REJECT (rej 는 이 셸에서 돌아야 하므로 $( ) 안에서 부르지 않는다)
gq() { local max="$1" why="$2"; shift 2
  GQ_OUT="$(ft_git_capped 7 "$REPO_LANDED" "$@")"; GQ_RC=$?
  [ "$GQ_RC" -le "$max" ] || rej "$why — $REPO_LANDED 조회 실패(rc=$GQ_RC · 시간 초과 포함) 통과 0"
  return "$GQ_RC"; }
gq 1 "랜딩 브랜치 ref($REF)" rev-parse --verify -q "${REF}^{commit}" \
  || rej "랜딩 브랜치 ref 없음: $REF ($REPO_LANDED)"
gq 1 "조상 검사($REF)" merge-base --is-ancestor "$SFULL" "$REF" || {
  # r978 고침 2 — 카드가 «설치: 없음» 이고 문서 가지(FT_DOC_LAND_REF · 기본 origin/ops/main-base) 조상이며 바꾼 경로가 전부 design/**.md 면 문서 가지 착지 인정(판정 = ft_doc_card_landed 한 곳)
  _dc=""; _dc="$(ft_doc_card_landed "$REPO_LANDED" "$SFULL" "$CARD")"; _drc=$?   # r978-mut:imc
  [ "$_drc" -eq 0 ] || rej "랜딩 안 됨 — $S 가 $REF 의 조상이 아니다 ($REPO_LANDED) · 문서 카드 인정 0(${_dc:-사유 없음})"
  printf '착지 인정 = %s(문서 카드)\n' "$_dc" >&2   # r1018: stdout 은 «OK<TAB>…»/«REJECT<TAB>…» 한 줄 계약 — 안내 줄은 stderr
}
if [ -z "$UPDS" ]; then printf '%s\n' "$LAST"; exit 0; fi
if [ -n "$T" ]; then
  gq 1 "T($T)" rev-parse --verify -q "${T}^{commit}" || rej "T 없음 — git fetch 후 다시: $T"
  TFULL="$GQ_OUT"
  RANGE="$TFULL..$SFULL"
else
  gq 1 "S 첫 부모($S)" rev-parse --verify -q "${SFULL}^1" || rej "S 에 첫 부모가 없다: $S"
  RANGE="${SFULL}^1..$SFULL"
fi
gq 0 "랜딩 구간 변경 목록($RANGE)" diff --name-only "$RANGE" || rej "랜딩 구간 변경 목록을 못 읽었다($RANGE)"
CHANGED="$GQ_OUT"
while IFS= read -r X; do
  [ -n "$X" ] || continue
  grep -Fxq -- "$X" <<<"$CHANGED" || rej "랜딩 commit 에 정본 $X 없음 — 로컬에만 고친 것($RANGE)"
  xre="$(printf '%s' "$X" | sed 's/[][\.*^$/]/\\&/g')"
  CS="$(printf '%s\n' "$BODY" | grep -oE "정본 diff 확인:[[:space:]]*${xre}[[:space:]]+§[^@]*@[0-9a-fA-F]{7,40}" | sed 's/.*@//')"
  [ -n "$CS" ] || rej "판정문 절에 「정본 diff 확인: $X §Y @<sha>」 줄 없음 — arch 검토 기록 필요"
  gq 1 "$X @$S" rev-parse -q --verify "$SFULL:$X" || rej "S 에 $X 없음"
  SB="$GQ_OUT"
  while IFS= read -r C; do
    gq 1 "$X @$C" rev-parse -q --verify "$C:$X" || rej "정본 diff 확인 줄의 @$C 에서 $X 를 읽을 수 없음 — 재검토"
    CB="$GQ_OUT"
    [ "$CB" = "$SB" ] || rej "검토 뒤 정본이 바뀜 — 재검토($X @$C ≠ S)"
  done <<<"$CS"
done <<<"$UPDS"
printf '%s\n' "$LAST"
