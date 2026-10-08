#!/usr/bin/env bash
# ft-index-move-canon.sh <카드> <워크트리> <landed:""|S|T..S>   (stdin = 판정문 §N 절 본문)
#   ft-index-move.sh 진행→완성의 정본 게이트 + 랜딩 commit 사실 검사 (판정 440 설계 r2 §6-1 · 판정 444).
#   출력 한 줄: `OK<TAB>정본 <경로> §<절>[ · 정본 …]` 또는 `OK<TAB>정본 영향 없음: <이유>` 또는 `REJECT<TAB><사유>` · 항상 exit 0.
#   랜딩 브랜치 ref = env FT_LAND_REF(기본 origin/main) · 검사 전 fetch 하지 않는다 · 검사를 끄는 값 없음.
set -uo pipefail
CARD="${1:-}"; WT="${2:-}"; LANDED="${3:-}"
BODY="$(cat)"
rej() { printf 'REJECT\t%s\n' "$1"; exit 0; }

# ① 카드 줄 검사 — 「정본 갱신:」 줄 «전부» 파일·절 실재 · 없으면 「정본 영향 없음」 · 출력 UPD 줄들 + 마지막 OK/REJECT
RES="$(python3 - "$CARD" "$WT" <<'PY'
import re, sys, os
card = open(sys.argv[1], encoding="utf-8").read().splitlines()
wt = sys.argv[2]
pre = r'^[\s>*\-]*'
upd = [m for m in (re.match(pre + r'정본 갱신(?: 줄)?\s*:\s*(\S+?)\s*§\s*(.+?)\s*$', l) for l in card) if m]
non = [m for m in (re.match(pre + r'정본 영향 없음\s*:\s*(.*?)\s*$', l) for l in card) if m]
def reject(why):
    print("REJECT\t" + why); sys.exit(0)
notes = []
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
if upd:
    print("OK\t" + " · ".join(notes)); sys.exit(0)
for m in non:
    why = re.sub(r'^이유\s*=\s*', '', m.group(1)).strip()
    if len(why) >= 10:
        print("OK\t정본 영향 없음: " + why); sys.exit(0)
    reject("「정본 영향 없음」 이유가 10자 미만이다")
reject("카드에 「정본 갱신: docs/architect/….md §<절>」 또는 「정본 영향 없음: <이유 ≥10자>」 줄이 없다")
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
g() { git -C "$WT" "$@"; }
SFULL="$(g rev-parse --verify -q "${S}^{commit}" 2>/dev/null)" || rej "S 없음 — git fetch 후 다시: $S"
g rev-parse --verify -q "${REF}^{commit}" >/dev/null 2>&1 || rej "랜딩 브랜치 ref 없음: $REF"
g merge-base --is-ancestor "$SFULL" "$REF" 2>/dev/null || rej "랜딩 안 됨 — $S 가 $REF 의 조상이 아니다"
if [ -z "$UPDS" ]; then printf '%s\n' "$LAST"; exit 0; fi
if [ -n "$T" ]; then
  TFULL="$(g rev-parse --verify -q "${T}^{commit}" 2>/dev/null)" || rej "T 없음 — git fetch 후 다시: $T"
  RANGE="$TFULL..$SFULL"
else
  g rev-parse --verify -q "${SFULL}^1" >/dev/null 2>&1 || rej "S 에 첫 부모가 없다: $S"
  RANGE="${SFULL}^1..$SFULL"
fi
CHANGED="$(g diff --name-only "$RANGE" 2>/dev/null)"
while IFS= read -r X; do
  [ -n "$X" ] || continue
  printf '%s\n' "$CHANGED" | grep -Fxq -- "$X" || rej "랜딩 commit 에 정본 $X 없음 — 로컬에만 고친 것($RANGE)"
  xre="$(printf '%s' "$X" | sed 's/[][\.*^$/]/\\&/g')"
  CS="$(printf '%s\n' "$BODY" | grep -oE "정본 diff 확인:[[:space:]]*${xre}[[:space:]]+§[^@]*@[0-9a-fA-F]{7,40}" | sed 's/.*@//')"
  [ -n "$CS" ] || rej "판정문 절에 「정본 diff 확인: $X §Y @<sha>」 줄 없음 — arch 검토 기록 필요"
  SB="$(g rev-parse -q --verify "$SFULL:$X" 2>/dev/null)" || rej "S 에 $X 없음"
  while IFS= read -r C; do
    CB="$(g rev-parse -q --verify "$C:$X" 2>/dev/null)" || rej "정본 diff 확인 줄의 @$C 에서 $X 를 읽을 수 없음 — 재검토"
    [ "$CB" = "$SB" ] || rej "검토 뒤 정본이 바뀜 — 재검토($X @$C ≠ S)"
  done <<<"$CS"
done <<<"$UPDS"
printf '%s\n' "$LAST"
