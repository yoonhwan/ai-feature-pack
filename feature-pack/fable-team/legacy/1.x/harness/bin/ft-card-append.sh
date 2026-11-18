#!/usr/bin/env bash
# ft-card-append.sh — r2244 O2·O3: 가지 끝 카드의 «## 상태» 끝에 원고 파일 줄을 그대로 덧붙여 커밋 1개 push.
# 쓰는 법: ft-card-append.sh <가지> <카드 경로> <원고 파일> "<커밋 글>"   (현재 폴더의 git 리포 · origin)
#   작업 트리·현재 index 손 0(임시 index) · fetch 는 --refmap= 으로 받아 묵은 refs/remotes/*.lock 을 피한다.
#   덧붙인 뒤 확인 = ft-card-tail.sh <카드 경로> --ref <PUSHED sha>
# 출력 ≤ 3줄: «PUSHED <sha40> base=<sha40>» · stat 1줄 · push stderr 가 있으면 «경고 <첫 줄 200B> (+<n>줄)» 1줄
# rc: 0 = push 됨 · 2 = 카드가 가지 끝에 없음 · «## 상태» 없음 · «## 상태» 가 마지막 절 아님 (push 0)
#     3 = «판정 불가 <단계> rc=<n>» (fetch·push 실패 · 재시도 1) · 4 = 원고 거절(UTF-8 아님 · 빈 원고 · «- » 로 시작 안 하는 줄) · 64 = 인자 틀림
set -uo pipefail
[ $# -eq 4 ] || { echo "쓰는 법: ft-card-append.sh <가지> <카드 경로> <원고 파일> \"<커밋 글>\"" >&2; exit 64; }
BR="$1"; CARD="$2"; DRAFT="$3"; MSG="$4"
[ -f "$DRAFT" ] || { echo "원고 없음: $DRAFT" >&2; exit 64; }
python3 - "$DRAFT" <<'PY' || exit 4
import sys
b = open(sys.argv[1], "rb").read()
try:
    t = b.decode("utf-8")
except UnicodeDecodeError:
    print("원고 거절: UTF-8 아님 — push 0"); sys.exit(4)
ls = t[:-1].split("\n") if t.endswith("\n") else t.split("\n")
if not t.strip():
    print("원고 거절: 빈 원고 — push 0"); sys.exit(4)
bad = [i + 1 for i, l in enumerate(ls) if not l.startswith("- ")]
if bad:
    print("원고 거절: «- » 로 시작 안 하는 줄 %s — push 0" % ",".join(map(str, bad[:5]))); sys.exit(4)
PY
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 25"
TMP="$(mktemp -d)"; PREF="refs/ft-card-append/$$/$BR"
trap 'git update-ref -d "$PREF" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
step() {  # step <단계> <명령…> — 1회 + 재시도 1 · stderr 는 $TMP/<단계>.err
  local name="$1" rc=0; shift
  "$@" 2>"$TMP/$name.err" && return 0
  "$@" 2>"$TMP/$name.err" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  echo "판정 불가 $name rc=$rc"; exit 3
}
step fetch $TO git fetch -q --no-tags --refmap= origin "+refs/heads/$BR:$PREF"
BASE="$(git rev-parse --verify -q "$PREF^{commit}")" || { echo "판정 불가 fetch rc=1"; exit 3; }
ENTRY="$(git ls-tree "$BASE" -- "$CARD")"
case "$ENTRY" in *" blob "*) ;; *) echo "카드가 가지 끝에 없음: $BR:$CARD — push 0"; exit 2 ;; esac
git cat-file blob "$BASE:$CARD" > "$TMP/card"
python3 - "$TMP/card" "$DRAFT" <<'PY' || exit $?
import sys
card = open(sys.argv[1], "rb").read()
ls = card.split(b"\n")
st = [i for i, l in enumerate(ls) if l.rstrip() == "## 상태".encode()]
if not st:
    print("«## 상태» 절 없음 — push 0"); sys.exit(2)
after = [l[3:].strip().decode("utf-8", "replace") for l in ls[st[-1] + 1:] if l.startswith(b"## ")]
if after:
    print("«## 상태» 뒤에 ## 절 있음: %s — push 0" % " · ".join(after)); sys.exit(2)
d = open(sys.argv[2], "rb").read()
out = card + (b"" if card.endswith(b"\n") or not card else b"\n") + d + (b"" if d.endswith(b"\n") else b"\n")
open(sys.argv[1], "wb").write(out)
PY
MODE="${ENTRY%% *}"
BLOB="$(git hash-object -w "$TMP/card")"
export GIT_INDEX_FILE="$TMP/index"
git read-tree "$BASE" && git update-index --cacheinfo "$MODE,$BLOB,$CARD" \
  && TREE="$(git write-tree)" && C="$(git commit-tree "$TREE" -p "$BASE" -m "$MSG")" \
  || { echo "판정 불가 commit rc=1"; exit 3; }
unset GIT_INDEX_FILE
step push $TO git push -q origin "$C:refs/heads/$BR"
echo "PUSHED $C base=$BASE"
git diff --shortstat "$BASE" "$C" | sed 's/^ *//'
if [ -s "$TMP/push.err" ]; then
  python3 -c 'import sys; ls = open(sys.argv[1], "rb").read().splitlines() or [b""]
print("경고 %s (+%d줄)" % (ls[0][:200].decode("utf-8", "ignore"), len(ls) - 1))' "$TMP/push.err"
fi
exit 0
