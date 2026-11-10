#!/usr/bin/env bash
# test_team_upgrade_note.sh — ft-team-upgrade.sh 도장 줄 문구(R376): note 는 틀 VERSION 값 기반 · 명부 없는 팀 WARN 은 다음 한 수 안내.
# 임시 git 리포 픽스처만 — 실제 design/·명부 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
TPL="$T/tpl"; cp -R "$KIT/templates/team" "$TPL"
REPO="$T/repo"; RDIR="$T/roster"; mkdir -p "$REPO/design" "$RDIR"
cat > "$REPO/design/TEAMS.md" <<'E'
# 팀 명단
| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| a | `design/a/` | a-master | 현역 |
| c | `design/c/` | c-master | 현역 |
| d | `design/d/` | d-master | 현역 |
E
printf '{\n  "_doc": "a 명부"\n}\n' > "$RDIR/seats-a.json"
printf '{\n  "_tree_version": "1.0.0",\n  "_tree_version_note": "r368 2026-10-18 없음→1.0.0",\n  "_doc": "c 명부"\n}\n' > "$RDIR/seats-c.json"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t \
  && git -C "$REPO" add -A && git -C "$REPO" commit -qm base
UP() { (cd "$REPO" && FT_REPO_ROOT="$REPO" FT_ROSTER_DIR="$RDIR" FT_TEAM_TEMPLATE_DIR="$TPL" bash "$SRCDIR/ft-team-upgrade.sh" "$@" 2>&1); }
jget() { python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],"<없음>"))' "$RDIR/seats-$1.json" "$2"; }
echo 1.0.0 > "$TPL/VERSION"
TODAY="$(date +%F)"

# ⓐ 새 명부(_tree_version 없음) → note = tree <VERSION> <오늘> 없음→<VERSION> · r368 고정 문구 0
out="$(UP a)"; rc=$?; n="$(jget a _tree_version_note)"
[ "$rc" = 0 ] && [ "$n" = "tree 1.0.0 $TODAY 없음→1.0.0" ] && ok "ⓐ 새 명부 note = '$n'" || bad "ⓐ: rc=$rc note=$n $out"

# ⓑ 명부 없는 팀 → WARN 에 다음 한 수(명부를 만든 뒤 ft-team-upgrade.sh <팀>) · rc0 · 명부 생성 0
out="$(UP d)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^WARN d 명부 없음 — _tree_version 기록 0 — 명부를 만든 뒤 ft-team-upgrade.sh d$' && [ ! -e "$RDIR/seats-d.json" ] \
  && ok "ⓑ WARN 이 다음 한 수 안내" || bad "ⓑ: rc=$rc $out"

# ⓒ 이미 도장된 명부(c) → SKIP · note 문자열 불변
before="$(cat "$RDIR/seats-c.json")"; out="$(UP c)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^SKIP c up-to-date' && [ "$before" = "$(cat "$RDIR/seats-c.json")" ] \
  && ok "ⓒ 기존 note 불변 (SKIP)" || bad "ⓒ: rc=$rc $out"

# ⓓ 변이: 틀 1.1.0 → 낮은 쪽 명부 c 의 note = tree 1.1.0 <오늘> 1.0.0→1.1.0
echo 1.1.0 > "$TPL/VERSION"
out="$(UP c)"; rc=$?; n="$(jget c _tree_version_note)"
[ "$rc" = 0 ] && [ "$n" = "tree 1.1.0 $TODAY 1.0.0→1.1.0" ] && ok "ⓓ 1.1.0 개정 note = '$n'" || bad "ⓓ: rc=$rc note=$n $out"

echo "fail=$fail"; [ "$fail" = 0 ]
