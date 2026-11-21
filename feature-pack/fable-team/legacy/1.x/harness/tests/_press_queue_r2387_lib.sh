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

APD="$T/state/autonomy-merge-approved"   # 승인 표식 폴더 = ft-autonomy.sh state-dir(= 픽스처 FT_AUTONOMY_STATE_DIR) 아래
apm() {  # apm <head sha> <분 전> — 승인 표식 파일(이름 = 승인한 head · 시각 = mtime · DA#54 H3 계약)
  [ -n "${APM_BASE:-}" ] || APM_BASE="$(python3 -c 'import time;print(int(time.time()))')"   # 한 시험 안에서 «같은 분 전» = 같은 mtime(⑨)
  mkdir -p "$APD"; printf 'approve-merge %s A1 %s\n' "$1" "$APM_BASE" > "$APD/$1"
  python3 - "$APD/$1" "$APM_BASE" "$2" <<'PY'
import os, sys
t = int(sys.argv[2]) - int(sys.argv[3]) * 60
os.utime(sys.argv[1], (t, t))
PY
}
apn() { rm -f "$APD/$1"; }   # 표식 지우기(«승인 전» 사례)
sky() { git -C "$REPO" fetch -q origin '+refs/press/*:refs/press/*' '+refs/press-debt/*:refs/press-debt/*' 2>/dev/null || true; }   # r2387 H1: 묶음 ref 받기는 «부르는 쪽 몫»(queue 는 fetch 0)
qreset() { : > "$PLIST"; : > "$STUB_LOG"; }
qgl() { grep -c 'pr list' "$STUB_LOG" 2>/dev/null || true; }   # pr list 부른 횟수(없으면 0)
prj() {  # prj <번호> <head> — 열린 PR 목록 JSON 에 1줄 더한다(gh 칸 = 번호·head 만 · DA#54 H2)
  python3 - "$PLIST" "$@" <<'PY'
import json, os, sys
p, n, head = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [r for r in (json.load(open(p)) if os.path.getsize(p) else []) if r.get("number") != n]   # 같은 번호 = 새 줄로 바꾼다(head 갱신 사례)
json.dump(rows + [{"number": n, "headRefOid": head}], open(p, "w"))
PY
}
qm() {  # qm <번호> <가지> <분 전|""> <키=값…> — PR 1개(가지는 지금 origin/main 에서) + 목록 1줄 · 분 전 = 승인 표식(mtime)
  local n="$1" b="$2" at="$3"; shift 3
  mkpr "$n" "$b" "$@"
  [ -z "$at" ] || apm "$PRSHA" "$at"
  prj "$n" "$PRSHA"
}
setof() {  # setof <head> [부모] — 그 PR 을 main 에 병합한 세트(부모 = main) · press 세트와 같은 꼴
  local h="$1" m="${2:-$(sha "$REPO" origin/main)}" t
  t="$(git -C "$REPO" merge-tree --write-tree "$m" "$h" | head -n1)"
  git -C "$REPO" commit-tree "$t" -p "$m" -m "set $h"
}
vbs() { vb "$1" "$2"; sky; }   # 유효 묶음(원격 push + 로컬 ref 받기 = 부르는 쪽 몫) — 세트 트리가 그 PR 의 병합 트리와 같다
qlst() {  # qlst <번호> <가지> <분 전|""> <더할 글롭> <키=값…> — 목록에 글롭 1줄 더한 PR(④ · 대상 판정 = 합집합)
  local n="$1" b="$2" at="$3" g="$4" kv files; shift 4
  git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B "$b" origin/main
  { cat "$REPO/docs/rules/press_voice_paths.md"; printf -- '- `%s`\n' "$g"; } > "$REPO/docs/rules/press_voice_paths.md.tmp"
  mv "$REPO/docs/rules/press_voice_paths.md.tmp" "$REPO/docs/rules/press_voice_paths.md"
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done
  cm "$REPO" "pr $n"; pushpr "$n" "$b"
  [ -z "$at" ] || apm "$PRSHA" "$at"
  prj "$n" "$PRSHA"
}
bks() { bk "$1" "$2"; sky; }   # 깨진 묶음 — 부모 없음(rev-parse <커밋>^ 실패)
qrun() { : > "$STUB_LOG"; out="$(bash "$BIN/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
qbase() { : > "$STUB_LOG"; out="$(bash "$QBB/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
qline() { grep -n "^PR #$1 " <<<"$out" | cut -d: -f1; }   # 그 PR 줄의 순서(1부터 · 없으면 빈 값)
qnext() { sed -n 's/^NEXT //p' <<<"$out"; }   # 끝 NEXT 줄 값
