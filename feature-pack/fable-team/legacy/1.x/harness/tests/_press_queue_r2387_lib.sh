# _press_queue_r2387_lib.sh — r2387 공용(source 전용): r2381 픽스처(임시 origin · 가짜 git · 묶음 도우미) 위에 «gh pr list 대역» · PR 목록 JSON 도우미 · 음성 경로 세트/묶음 도우미 · queue 1회 실행
#   qreset = 목록·호출 기록 비움 · qm <번호> <가지> <승인ISO|""> <키=값…> = PR 1개 + 목록 1줄(파일 칸 = main 대비 git diff) · setof <head> [부모] = 그 PR 병합 세트
#   vbs <세트> <run> = 유효 묶음(임시 bare 에 push) · bks <40hex 꼴> <run> = 깨진 묶음(부모 없음) · qrun/qbase = queue 1회(rc·out) · tmn <분> = n분 전 ISO
#   기준판(QBB) = origin/main 판 도구(queue 갈래 0 → Red) · 실 gh·실 원격 0 · queue 는 읽기 전용(⑯)
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_pick_newest_r2381_lib.sh"

PLIST="$T/prs.json"; : > "$PLIST"; export PLIST
cat > "$T/gh-list" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "pr list") [ -z "${GH_SLEEP:-}" ] || { sleep "$GH_SLEEP"; exit 7; }; cat "$PLIST"; exit 0;;
  "pr view") [ -z "${GH_SLEEP:-}" ] || { sleep "$GH_SLEEP"; exit 7; }; cat "$STUB_JSON"; exit 0;;
esac
exit 0
EOF
chmod +x "$T/gh-list"; export FT_GH="$T/gh-list"

QBB="$T/qbase"; mkdir -p "$QBB"
for f in ft-press-evidence.sh press_evidence_verify.py press_evidence_land.py; do
  git -C "$PACKDIR" show "origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/$f" > "$QBB/$f" 2>/dev/null || { echo "FAIL 기준판(origin/main) $f 못 읽음"; exit 1; }
done
cp "$BIN/press_evidence_parts.py" "$QBB/"

tmn() { python3 -c 'import datetime,sys
print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
qreset() { : > "$PLIST"; : > "$STUB_LOG"; }
qgl() { grep -c 'pr list' "$STUB_LOG" 2>/dev/null || true; }   # pr list 부른 횟수(없으면 0)
prj() {  # prj <번호> <head> <승인ISO|""> <파일…> — 열린 PR 목록 JSON 에 1줄 더한다
  python3 - "$PLIST" "$@" <<'PY'
import json, os, sys
p, n, head, at = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
row = {"number": n, "title": "feat: PR %d" % n, "headRefOid": head,
       "files": [{"path": f} for f in sys.argv[5:]], "reviews": [], "comments": []}
if at.startswith("C:"):   # C:2026-… = 본문 «판정: APPROVE» 코멘트(승인 표식 둘째 길)
    row["comments"] = [{"createdAt": at[2:], "body": "판정: APPROVE — 막는 것 0"}]
elif at:
    row["reviews"] = [{"state": "APPROVED", "submittedAt": at}]
rows = json.load(open(p)) if os.path.getsize(p) else []
json.dump(rows + [row], open(p, "w"))
PY
}
qm() {  # qm <번호> <가지> <승인ISO|""> <키=값…> — PR 1개(가지는 지금 origin/main 에서) + 목록 1줄
  local n="$1" b="$2" at="$3" files; shift 3
  mkpr "$n" "$b" "$@"
  files="$(git -C "$REPO" diff --name-only --no-renames "$(sha "$REPO" origin/main)" "$PRSHA" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  prj "$n" "$PRSHA" "$at" $files
}
setof() {  # setof <head> [부모] — 그 PR 을 main 에 병합한 세트(부모 = main) · press 세트와 같은 꼴
  local h="$1" m="${2:-$(sha "$REPO" origin/main)}" t
  t="$(git -C "$REPO" merge-tree --write-tree "$m" "$h" | head -n1)"
  git -C "$REPO" commit-tree "$t" -p "$m" -m "set $h"
}
vbs() { vb "$1" "$2"; }   # 유효 묶음 — 세트 트리가 그 PR 의 병합 트리와 같다
qlst() {  # qlst <번호> <가지> <승인ISO> <더할 글롭> <키=값…> — 목록에 글롭 1줄 더한 PR(④ · 대상 판정 = 합집합)
  local n="$1" b="$2" at="$3" g="$4" kv files; shift 4
  git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B "$b" origin/main
  { cat "$REPO/docs/rules/press_voice_paths.md"; printf -- '- `%s`\n' "$g"; } > "$REPO/docs/rules/press_voice_paths.md.tmp"
  mv "$REPO/docs/rules/press_voice_paths.md.tmp" "$REPO/docs/rules/press_voice_paths.md"
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done
  cm "$REPO" "pr $n"; pushpr "$n" "$b"
  files="$(git -C "$REPO" diff --name-only --no-renames "$(sha "$REPO" origin/main)" "$PRSHA" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  prj "$n" "$PRSHA" "$at" $files
}
bks() { bk "$1" "$2"; }   # 깨진 묶음 — 부모 없음(rev-parse <커밋>^ 실패)
qrun() { : > "$STUB_LOG"; out="$(bash "$BIN/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
qbase() { : > "$STUB_LOG"; out="$(bash "$QBB/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
qline() { grep -n "^PR #$1 " <<<"$out" | cut -d: -f1; }   # 그 PR 줄의 순서(1부터 · 없으면 빈 값)
qnext() { sed -n 's/^NEXT //p' <<<"$out"; }   # 끝 NEXT 줄 값
