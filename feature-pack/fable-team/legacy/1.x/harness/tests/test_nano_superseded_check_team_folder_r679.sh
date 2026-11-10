#!/usr/bin/env bash
# test_nano_superseded_check_team_folder_r679.sh — R679: ft-nano-superseded-check.sh 의 대체 카드 «경로 꼴» 이 옛 폴더 구조(design/<팀>/indices/)·옛 폴더 이름(완료)에 묶여 팀 폴더 카드(design/teams/<팀>/indices/)와 «완성» 폴더를 거절하던 결함
# 임시 리포 + 카드 파일만 쓴다 — 실 명부·실 좌석·tmux·원장은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓕ 키트 2곳 같은 바이트 · ⓐ 옛 꼴 통과 그대로 · ⓑ 팀 폴더 꼴·«완성» 폴더 통과 · ⓒ 거절 길 유지(실재·base 밖·..·모르는 폴더·자기 자신·사유·줄 꼴·경로 불일치) · ⓓ 키트 전체에 옛 꼴 잔존 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
SUT="$SRC/ft-nano-superseded-check.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }

echo "== ⓕ 키트 2곳(추적 짝·키트) 같은 바이트 + bash -n"
cmp -s "$HERE/../../harness/bin/ft-nano-superseded-check.sh" "$SUT" && ok "cmp ft-nano-superseded-check.sh (harness/bin == kit)" || bad "cmp 다름: harness/bin 과 kit"
bash -n "$SUT" && ok "bash -n ft-nano-superseded-check.sh" || bad "bash -n"

R="$T/repo"
mkdir -p "$R/design/teams/v65/indices/대기" "$R/design/teams/v65/indices/진행" "$R/design/teams/v65/indices/완성" \
         "$R/design/teams/v65/indices/기타" "$R/design/harness/indices/진행" "$R/design/harness/indices/완성" \
         "$R/design/harness/indices/완료" "$T/out"
for p in design/teams/v65/indices/대기/team-wait.md design/teams/v65/indices/진행/team-run.md \
         design/teams/v65/indices/완성/team-done.md design/teams/v65/indices/기타/team-etc.md \
         design/harness/indices/진행/old-run.md design/harness/indices/완성/new-done.md \
         design/harness/indices/완료/legacy-done.md; do
  printf '# 인덱스: %s\n## 상태\n- 진행\n' "$(basename "$p" .md)" > "$R/$p"
done
printf 'x\n' > "$T/out/outside.md"
CARD="$T/card.md"
card() { printf '## 상태\n대체됨: %s · 사유: %s\n' "$1" "폴더 꼴 시험" > "$CARD"; }
run() { bash "$SUT" "$CARD" --superseded-by "$1" --base "$R" 2>&1; }

echo "== ⓐ 옛 꼴 그대로 통과(회귀 0)"
card design/harness/indices/진행/old-run.md
out="$(run design/harness/indices/진행/old-run.md)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "OK 대체됨" "ⓐ design/harness/indices/진행/… → rc=0(옛 꼴 유지)" || bad "ⓐ 옛 꼴 rc=$rc ← ${out:0:300}"
card design/harness/indices/완료/legacy-done.md
out="$(run design/harness/indices/완료/legacy-done.md)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ 옛 폴더 이름 «완료» → rc=0(호환 유지)" || bad "ⓐ 완료 꼴 rc=$rc ← ${out:0:300}"

echo "== ⓑ 팀 폴더 꼴·«완성» 폴더 통과(R679 고침)"
for p in design/teams/v65/indices/대기/team-wait.md design/teams/v65/indices/진행/team-run.md \
         design/teams/v65/indices/완성/team-done.md design/harness/indices/완성/new-done.md; do
  card "$p"
  out="$(run "$p")"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "OK 대체됨" "ⓑ $p → rc=0" || bad "ⓑ $p rc=$rc ← ${out:0:300}"
done

echo "== ⓒ 거절 길 유지 — 팀 폴더 꼴이 열려도 «없는 파일·base 밖·..·모르는 폴더·자기 자신·사유·줄 꼴·경로 불일치» 는 그대로 REJECT"
card design/teams/v65/indices/진행/none.md
out="$(run design/teams/v65/indices/진행/none.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "대체 카드 파일이 없다" "ⓒ 팀 폴더 꼴인데 파일 없음 → rc=1" || bad "ⓒ 없는 파일 rc=$rc ← ${out:0:300}"
mkdir -p "$T/other/design/teams/v65/indices/진행" && printf 'x\n' > "$T/other/design/teams/v65/indices/진행/o.md"
card design/teams/v65/indices/진행/o.md
out="$(run design/teams/v65/indices/진행/o.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "대체 카드 파일이 없다" "ⓒ base 밖 팀 폴더 파일 → rc=1" || bad "ⓒ base 밖 rc=$rc ← ${out:0:300}"
card design/teams/v65/../v65/indices/진행/team-run.md
out="$(run design/teams/v65/../v65/indices/진행/team-run.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«..»" "ⓒ «..» 들어간 팀 폴더 경로 → rc=1" || bad "ⓒ .. rc=$rc ← ${out:0:300}"
card design/teams/v65/indices/기타/team-etc.md
out="$(run design/teams/v65/indices/기타/team-etc.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "여야 한다" "ⓒ 모르는 폴더(기타/) → rc=1" || bad "ⓒ 기타 rc=$rc ← ${out:0:300}"
printf '## 상태
대체됨: design/teams/v65/indices/진행/team-run.md · 사유: 자기 자신\n' > "$R/design/teams/v65/indices/진행/team-run.md"
out="$(bash "$SUT" "$R/design/teams/v65/indices/진행/team-run.md" --superseded-by design/teams/v65/indices/진행/team-run.md --base "$R" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "자신이다" "ⓒ 대체 카드 = 자기 자신 → rc=1" || bad "ⓒ 자기 자신 rc=$rc ← ${out:0:300}"
printf '# 인덱스: team-run\n## 상태\n- 진행\n' > "$R/design/teams/v65/indices/진행/team-run.md"
card design/teams/v65/indices/진행/team-run.md
printf '## 상태\n대체됨: design/teams/v65/indices/진행/team-run.md · 사유:   \n' > "$CARD"
out="$(run design/teams/v65/indices/진행/team-run.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "사유가 비어" "ⓒ 사유 빈칸 → rc=1" || bad "ⓒ 사유 빈칸 rc=$rc ← ${out:0:300}"
printf '## 상태\n- 2026-10-22 진행\n' > "$CARD"
out="$(run design/teams/v65/indices/진행/team-run.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "대체됨:» 줄이 아니다" "ⓒ «대체됨:» 줄 없음 → rc=1" || bad "ⓒ 줄 없음 rc=$rc ← ${out:0:300}"
card design/teams/v65/indices/진행/team-run.md
out="$(run design/teams/v65/indices/대기/team-wait.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "다르다" "ⓒ 줄의 경로 ≠ --superseded-by → rc=1" || bad "ⓒ 경로 불일치 rc=$rc ← ${out:0:300}"
ln -s "$T/out/outside.md" "$R/design/teams/v65/indices/진행/link.md"
card design/teams/v65/indices/진행/link.md
out="$(run design/teams/v65/indices/진행/link.md)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "실제 위치가 허용 범위 밖" "ⓒ 팀 폴더 꼴 이름의 심링크가 base 밖 → rc=1(우회 차단 유지)" || bad "ⓒ 심링크 rc=$rc ← ${out:0:300}"
rm -f "$R/design/teams/v65/indices/진행/link.md"

echo "== ⓓ 키트 전체에 옛 꼴 «indices/(대기|진행|완료)» 잔존 0 (같은 결함이 남은 곳 = 같이 고친다)"
for d in "$SRC" "$HERE/../../harness/bin"; do
  hit="$(grep -rn 'indices/(대기|진행|완료)' --include=*.sh "$d" 2>/dev/null)"
  [ -z "$hit" ] && ok "ⓓ $(basename "$d") 정규식 잔존 0" || bad "ⓓ 옛 꼴 정규식 잔존: $hit"
  hit="$(grep -rn 'indices/{대기,진행,완료}' --include=*.sh --include=*.py "$d" 2>/dev/null)"
  [ -z "$hit" ] && ok "ⓓ $(basename "$d") 문구 «{대기,진행,완료}» 잔존 0" || bad "ⓓ 옛 꼴 문구 잔존: $hit"
done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
