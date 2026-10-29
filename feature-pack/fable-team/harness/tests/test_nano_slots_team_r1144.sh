#!/usr/bin/env bash
# test_nano_slots_team_r1144.sh — r1144: ft-nano-slots.sh 팀 풀기 = 정본 ft_teamset.py team-of 경유(손 규칙 두 벌 0) · 키트 안 옛 접두 글자 = 정본·틱 문구 밖 0.
#   R1 byz-harness-nano- → 팀 harness · R2 옛 접두(ft-v65-temp-) → v65 · R3 xyz- → ERROR 1줄 rc1 · R4 키트 옛 글자 정본 밖 0 · ⓒ bin·kit 같은 내용
#   팀 관측 = 카드 명단 ref 를 일부러 없는 ref 로 줘서 나오는 «ERROR <팀> 팀 폴더를 못 풀었다» 줄(실 명단·실 좌석·실 tmux 0).
#   변이 = R1144_SUT_KIT 로 옛 손 규칙 판 사본을 주면 R4 가 FAIL 해야 한다(시험 파일은 자기를 다시 부르지 않는다).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="${R1144_SUT_KIT:-$REPO/harness/kit/fable-team/bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

git init -q "$T/repo"
slots() { # <접두> → 표준오류 파일 $T/err · rc 반환
  (cd "$T/repo" && FT_NANO_PREFIX="$1" FT_TEAMS_REF=refs/heads/r1144-none FT_SEATS_JSON="$T/none.json" bash "$KIT/ft-nano-slots.sh" >/dev/null 2>"$T/err")
}

# ── ⓐ R1·R2·R3 팀 풀기
slots byz-harness-nano-; rc=$?
{ [ "$rc" = 1 ] && grep -q '^ERROR harness 팀 폴더를 못 풀었다' "$T/err"; } && ok "ⓐ R1 byz-harness-nano- → 팀 harness" || bad "ⓐ R1 rc=$rc «$(head -1 "$T/err")»"
slots ft-v65-temp-; rc=$?
{ [ "$rc" = 1 ] && grep -q '^ERROR v65 팀 폴더를 못 풀었다' "$T/err"; } && ok "ⓐ R2 옛 접두 → 팀 v65(호환)" || bad "ⓐ R2 rc=$rc «$(head -1 "$T/err")»"
slots xyz-; rc=$?
{ [ "$rc" = 1 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && grep -q '^ERROR FT_NANO_PREFIX 에서 팀을 못 풀었다: xyz-' "$T/err"; } \
  && ok "ⓐ R3 규칙 밖 접두 → ERROR 1줄 rc1" || bad "ⓐ R3 rc=$rc «$(head -2 "$T/err" | tr '\n' ' ')»"
grep -q 'ft_teamset.py" team-of' "$KIT/ft-nano-slots.sh" && ok "ⓐ 팀 풀기가 정본 team-of 를 부른다" || bad "ⓐ team-of 호출 없음"

# ── ⓑ R4 키트 안 옛 접두 글자 = 정본(ft_teamset.py)·틱 문구(ft-tick-team.sh·ft-pm-tick.sh) 밖 0 (r655 ⓖ 와 같은 셈)
hits="$(grep -n 'ft-v65-temp-' "$KIT"/* 2>/dev/null | grep -v 'ft_teamset.py:' | grep -v 'ft-tick-team.sh:' | grep -v 'ft-pm-tick.sh:' | grep -v '\.pyc')"
[ -z "$hits" ] && ok "ⓑ R4 옛 접두 글자 정본 밖 0" || bad "ⓑ R4 남은 곳: $(printf '%s' "$hits" | head -3 | cut -d: -f1-2 | tr '\n' ' ')"

# ── ⓒ bin·kit 같은 내용 (변이 사본 판정 때는 건너뜀)
if [ -z "${R1144_SUT_KIT:-}" ]; then
  for f in ft-nano-spawn.sh ft-nano-slots.sh ft_teamset.py; do
    cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓒ bin·kit 같음 $f" || bad "ⓒ bin·kit 다름 $f"
  done
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
