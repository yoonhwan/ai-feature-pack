#!/usr/bin/env bash
# test_team_upgrade.sh — ft-team-upgrade.sh: 팀 틀 버전 비교 + 일괄 패치(R368). 임시 git 리포 픽스처만 — 실제 design/·명부 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../scripts/fable-team-bin"
KIT="$HERE/../../scripts/harness-install/fable-team"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in "$SRCDIR/ft-team-upgrade.sh" "$KIT/bin/ft-team-upgrade.sh"; do bash -n "$f" 2>/dev/null && ok "bash -n ${f##*/}" || bad "bash -n $f"; done
cmp -s "$SRCDIR/ft-team-upgrade.sh" "$KIT/bin/ft-team-upgrade.sh" && ok "키트 사본 cmp0" || bad "키트 사본 cmp"
cmp -s "$SRCDIR/ft-team-scaffold.sh" "$KIT/bin/ft-team-scaffold.sh" && ok "scaffold 키트 사본 cmp0" || bad "scaffold 키트 사본 cmp"
[ "$(cat "$KIT/templates/team/VERSION" 2>/dev/null)" = "1.0.0" ] && ok "templates/team/VERSION = 1.0.0" || bad "templates/team/VERSION 없음·값 다름"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
TPL="$T/tpl"; cp -R "$KIT/templates/team" "$TPL"
REPO="$T/repo"; RDIR="$T/roster"; mkdir -p "$REPO/design" "$RDIR"
cat > "$REPO/design/TEAMS.md" <<'E'
# 팀 명단
| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| a | `design/a/` | a-master | 현역 |
| b | `design/b/` | b-master | 현역 |
| c | `design/c/` | c-master | 현역 |
| d | `design/d/` | d-master | 현역 |
| f | `design/f/` | f-master | 현역 |
E
cat > "$RDIR/seats-a.json" <<'E'
{
  "_version": "1.2.0",
  "_doc": "a 명부",
  "x": {"role": "nano"}
}
E
cat > "$RDIR/seats-b.json" <<'E'
{
  "_tree_version": "0.9.0",
  "_tree": "design/b/NEWS-TREE.md",
  "_doc": "b 명부"
}
E
cat > "$RDIR/seats-c.json" <<'E'
{
  "_tree_version": "1.0.0",
  "_doc": "c 명부"
}
E
printf '%s' '{"_name": "F", "_version": "1.0.0", "_doc": "한 줄 명부", "x": {"role": "nano"}}' > "$RDIR/seats-f.json"
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t && G add -A && G commit -qm base
UP() { (cd "$REPO" && FT_REPO_ROOT="$REPO" FT_ROSTER_DIR="$RDIR" FT_TEAM_TEMPLATE_DIR="$TPL" bash "$SRCDIR/ft-team-upgrade.sh" "$@" 2>&1); }
jget() { python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],"<없음>"))' "$RDIR/seats-$1.json" "$2"; }
rsum() { cat "$RDIR"/seats-*.json | shasum | cut -c1-12; }
echo 1.0.0 > "$TPL/VERSION"

# ⓐ --dry-run --all → 팀마다 TEAM 1줄 · 쓰기 0
r0="$(rsum)"; out="$(UP --dry-run --all)"; rc=$?
[ "$rc" = 0 ] && [ -z "$(G status --porcelain)" ] && [ "$r0" = "$(rsum)" ] \
  && echo "$out" | grep -qE '^TEAM a have=없음 want=1\.0\.0 missing=[1-9]' \
  && echo "$out" | grep -qE '^TEAM b have=0\.9\.0 want=1\.0\.0 missing=[1-9]' \
  && echo "$out" | grep -qE '^TEAM c have=1\.0\.0 want=1\.0\.0 ' \
  && echo "$out" | grep -qE '^TEAM d have=없음 want=1\.0\.0 ' \
  && ok "ⓐ dry-run --all TEAM 1줄씩 · 쓰기 0" || bad "ⓐ: rc=$rc $out"

# ⓑ 명부 없는 버전 → 틀 + _tree_version/_tree_version_note/_tree · 나머지 키 보존 · 2회째 멱등
out="$(UP a)"; rc=$?
v="$(jget a _tree_version)"; n="$(jget a _tree_version_note)"; tr="$(jget a _tree)"
[ "$rc" = 0 ] && [ "$v" = "1.0.0" ] && echo "$n" | grep -q '^tree 1.0.0 ' && echo "$n" | grep -q '없음→1.0.0' && [ "$tr" = "design/a/STATE.md" ] \
  && [ -f "$REPO/design/a/STATE.md" ] && [ -f "$REPO/design/a/GOAL-a.md" ] && [ "$(jget a _doc)" = "a 명부" ] && [ "$(jget a _version)" = "1.2.0" ] && grep -q '"role": "nano"' "$RDIR/seats-a.json" \
  && ok "ⓑ a 패치(틀+_tree_version+_tree_version_note+_tree · 키 보존)" || bad "ⓑ: rc=$rc v=$v n=$n tree=$tr $out"
sed -n '2p' "$RDIR/seats-a.json" | grep -q '^  "' && ok "ⓑ 들여쓰기 2칸 유지" || bad "ⓑ 들여쓰기: $(sed -n 2p "$RDIR/seats-a.json")"
r1="$(rsum)"; G add -A; G commit -qm up-a
out="$(UP a)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^SKIP a up-to-date' && [ "$r1" = "$(rsum)" ] && [ -z "$(G status --porcelain)" ] && ok "ⓑ 2회째 SKIP · 변경 0 (멱등)" || bad "ⓑ 멱등: rc=$rc $out"

# ⓑ'' 한 줄 JSON 명부(seats-kk 꼴) — 3키만 바뀌고 한 줄·나머지 원문 보존
out="$(UP f)"; rc=$?
[ "$rc" = 0 ] && [ "$(jget f _tree_version)" = "1.0.0" ] && [ "$(jget f _version)" = "1.0.0" ] && [ "$(jget f _tree)" = "design/f/STATE.md" ] \
  && [ "$(grep -c '' "$RDIR/seats-f.json")" = 1 ] && grep -q '"x": {"role": "nano"}' "$RDIR/seats-f.json" && grep -q '"_doc": "한 줄 명부"' "$RDIR/seats-f.json" \
  && ok "ⓑ'' 한 줄 JSON 명부 패치 · 한 줄 유지 · 원문 보존" || bad "ⓑ'': rc=$rc $out $(cat "$RDIR/seats-f.json")"
out="$(UP f)"; echo "$out" | grep -q '^SKIP f up-to-date' && ok "ⓑ'' 한 줄 명부 2회째 SKIP" || bad "ⓑ'' 멱등: $out"

# ⓑ' 낮은 버전 b → _tree 보존 · note 0.9.0→1.0.0
out="$(UP b)"; rc=$?
[ "$rc" = 0 ] && [ "$(jget b _tree_version)" = "1.0.0" ] && jget b _tree_version_note | grep -q '0.9.0→1.0.0' && [ "$(jget b _tree)" = "design/b/NEWS-TREE.md" ] && ok "ⓑ' b 낮은 버전 패치 · _tree 보존" || bad "ⓑ': rc=$rc $out"

# ⓒ 같은 버전 c → SKIP · 쓰기 0 (틀도 안 만든다)
r1="$(rsum)"; out="$(UP c)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^SKIP c up-to-date' && [ "$r1" = "$(rsum)" ] && [ ! -e "$REPO/design/c" ] && ok "ⓒ up-to-date SKIP · 쓰기 0" || bad "ⓒ: rc=$rc $out"

# ⓓ TEAMS.md 에 없는 팀 → REJECT · 폴더 링크 → REJECT · 명부 불변
out="$(UP ghost)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT' && [ ! -e "$REPO/design/ghost" ] && ok "ⓓ 명단 밖 팀 REJECT" || bad "ⓓ: rc=$rc $out"
echo '| e | `design/e/` | e-master | 현역 |' >> "$REPO/design/TEAMS.md"
echo '{ "_doc": "e" }' > "$RDIR/seats-e.json"; mkdir -p "$T/out"; ln -s "$T/out" "$REPO/design/e"
r1="$(rsum)"; out="$(UP e)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT.*링크' && [ "$r1" = "$(rsum)" ] && [ -z "$(ls -A "$T/out")" ] && ok "ⓓ 팀 폴더 링크 REJECT · 명부·밖 파일 0" || bad "ⓓ 링크: rc=$rc $out"
rm -f "$REPO/design/e" "$RDIR/seats-e.json"; sed -i.bak '/^| e |/d' "$REPO/design/TEAMS.md"; rm -f "$REPO/design/TEAMS.md.bak"

# ⓔ 명부 파일 없는 팀 d → 틀은 만들고 WARN · 명부 생성 0
out="$(UP d)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^WARN d 명부 없음' && [ -f "$REPO/design/d/STATE.md" ] && [ ! -e "$RDIR/seats-d.json" ] && ok "ⓔ 명부 없는 팀 틀 생성 · WARN · 명부 0" || bad "ⓔ: rc=$rc $out"

# ⓘ VERSION 올리면 up-to-date 였던 팀이 다시 대상 · 변이: 1.1.0
G add -A; G commit -qm up-rest
echo 1.1.0 > "$TPL/VERSION"
out="$(UP --dry-run --all)"
echo "$out" | grep -qE '^TEAM c have=1\.0\.0 want=1\.1\.0' && echo "$out" | grep -qE '^TEAM a have=1\.0\.0 want=1\.1\.0' && ok "ⓘ VERSION 1.1.0 → 전 팀 다시 대상" || bad "ⓘ dry: $out"
out="$(UP --all)"; rc=$?
[ "$rc" = 0 ] && [ "$(jget c _tree_version)" = "1.1.0" ] && jget c _tree_version_note | grep -q '1.0.0→1.1.0' && [ "$(jget a _tree_version)" = "1.1.0" ] && ok "ⓘ --all 패치 rc0 · c·a _tree_version 1.1.0" || bad "ⓘ: rc=$rc $out"
r1="$(rsum)"; out="$(UP --all)"; rc=$?
[ "$rc" = 0 ] && [ "$r1" = "$(rsum)" ] && ! echo "$out" | grep -q '^CREATE' && ok "ⓘ --all 재실행 변경 0 (멱등)" || bad "ⓘ 멱등: rc=$rc $out"

# 버전 비교는 숫자 — 1.10.0 > 1.9.0 (문자열 비교면 SKIP 오판)
echo 1.9.0 > "$TPL/VERSION"; python3 -I - "$RDIR/seats-b.json" <<'E'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["_tree_version"]="1.10.0"; json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
E
out="$(UP b)"; echo "$out" | grep -q '^SKIP b up-to-date' && ok "버전 숫자 비교(1.10.0 ≥ 1.9.0 SKIP)" || bad "숫자 비교: $out"

# ⓕ TEAMS.md ↔ TEAMSET.md 표 2 팀 집합 일치(추적 파일 · 실물) — 차이 = ERROR 1줄
out="$(cd "$HERE/../.." && FT_REPO_ROOT="$PWD" bash "$SRCDIR/ft-team-upgrade.sh" --check-teams 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^OK teams=' && ok "ⓕ 실물 TEAMS.md == TEAMSET 표 2" || bad "ⓕ 실물: rc=$rc $out"
mkdir -p "$T/f/design"; cp "$HERE/../../design/TEAMSET.md" "$T/f/design/"; grep -v '^| kk ' "$HERE/../../design/TEAMS.md" > "$T/f/design/TEAMS.md"
out="$(FT_REPO_ROOT="$T/f" bash "$SRCDIR/ft-team-upgrade.sh" --check-teams 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(echo "$out" | grep -c '^ERROR')" = 1 ] && echo "$out" | grep -q 'kk' && ok "ⓕ 변이: TEAMS.md 에서 kk 빼면 ERROR 1줄 rc1" || bad "ⓕ 변이: rc=$rc $out"

# usage
out="$(UP)"; rc=$?
[ "$rc" = 2 ] && ok "usage rc2" || bad "usage: rc=$rc $out"

echo "fail=$fail"; [ "$fail" = 0 ]
