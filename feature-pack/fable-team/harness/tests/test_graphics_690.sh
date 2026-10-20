#!/usr/bin/env bash
# test_graphics_690.sh — 그래픽스 팀장 체제 정본화(판정 690) 시험.
# 임시 git 저장소(가짜 .fable-team/seats-*.json) · 임시 ROOT 만 쓴다. 루트 .fable-team·홈 쓰기 0 · tmux 는 has-session/ls 읽기만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
W="$(cd "$HERE/../.." && pwd)"
GI="$W/harness/kit/graphics"
INFO_A="$W/harness/kit/fable-team/bin/ft-harness-info.sh"
INFO_B="$W/harness/bin/ft-harness-info.sh"
STG="$W/harness/design/harness/staged-690"
HOME_REF="$HOME/.claude/skills/fable-team/references"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }

# ① bash -n
for f in "$INFO_A" "$INFO_B" "$GI/install.sh" "$GI/graphics-env.sh"; do
  bash -n "$f" && ok "① bash -n ${f#$W/}" || bad "① bash -n ${f#$W/}"
done

# ② seats 팀 명부 절 — 정상 2 · 깨진 JSON 1
R="$T/r1"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
printf '{"_master":"m-a#0","_arch":"a-a#0","_hil_route":"h-a#1","t-a#0":{"role":"nano"}}\n' > "$R/.fable-team/seats-a.json"
printf '{"_master":"m-b#0","_arch":"","_hil_route":"h-b#1"}\n' > "$R/.fable-team/seats-b.json"
printf '{ broken' > "$R/.fable-team/seats-bad.json"
printf '{"_master":"stale"}\n' > "$R/.fable-team/seats-a.json.bak-1"
# r455a: 스텁 없음 = 임시 리포에 comm 0(판정 불가) → ⚠ 표시 0 · 명부 절은 그대로(외부 FT_ROOT·ALIVE 를 지워 그 경로를 강제)
out_a="$(cd "$R" && env -u FT_ROOT -u FT_AGENT_ALIVE_BIN bash "$INFO_A" seats 2>&1)"; out_b="$(cd "$R" && env -u FT_ROOT -u FT_AGENT_ALIVE_BIN bash "$INFO_B" seats 2>&1)"
printf '#!/usr/bin/env bash\necho ALIVE\n' > "$T/alive-stub"
out_s="$(cd "$R" && env -u FT_ROOT FT_AGENT_ALIVE_BIN="$T/alive-stub" bash "$INFO_A" seats 2>&1)"
has "② 스텁 ALIVE: 팀 명부 절 머리" "$out_s" "== 팀 명부"
has "② 스텁 ALIVE: seats-a 줄" "$out_s" "seats-a.json master=m-a#0 arch=a-a#0 hil=h-a#1 좌석=1 열림=0"
printf '%s' "$out_a" | grep -q 'ERROR' && bad "② 스텁 없음: ERROR 줄 0" || ok "② 스텁 없음: ERROR 줄 0(판정 불가 = 표시 0)"
has "② 팀 명부 절 머리" "$out_a" "== 팀 명부"
has "② seats-a 줄" "$out_a" "seats-a.json master=m-a#0 arch=a-a#0 hil=h-a#1 좌석=1 열림=0"
has "② seats-b 줄" "$out_a" "seats-b.json master=m-b#0 arch= hil=h-b#1 좌석=0 열림=0"
has "② 깨진 JSON ERR" "$out_a" "ERR seats-bad.json 파싱 실패"
printf '%s' "$out_a" | grep -q 'bak' && bad "② .bak 제외" || ok "② .bak 제외"
[ "$(printf '%s\n' "$out_a" | grep -c '^seats-.*master=')" = 2 ] && ok "② 정상 줄 2개" || bad "② 정상 줄 2개"
[ "$out_a" = "$out_b" ] && ok "② 두 사본 출력 동일" || bad "② 두 사본 출력 동일"
cmp -s "$INFO_A" "$INFO_B" && ok "② 두 사본 파일 동일" || bad "② 두 사본 파일 동일"

# ③ 기존 명부 보존
R2="$T/r2"; mkdir -p "$R2/.fable-team"
printf '{"_master":"live#9","seat#0":{"role":"nano"}}\n' > "$R2/.fable-team/seats-graphics.json"
cp "$R2/.fable-team/seats-graphics.json" "$T/live.before"
o3="$(bash "$GI/install.sh" "$R2" 2>&1)"; rc3=$?
has "③ SKIP 줄" "$o3" "SKIP seats-graphics.json (라이브 명부 보존 — _doc·_master 는 손으로)"
cmp -s "$T/live.before" "$R2/.fable-team/seats-graphics.json" && ok "③ 명부 바이트 그대로" || bad "③ 명부 바이트 그대로"
has "③ env CMP OK" "$o3" "CMP OK  bin-graphics/graphics-env.sh"
has "③ goal-lines CMP OK" "$o3" "CMP OK  bin-graphics/goal-lines-graphics.txt"
[ "$rc3" = 0 ] && ok "③ rc=0" || bad "③ rc=$rc3"

# ④ 루트가 비었으면 명부 복사
R3="$T/r3"; mkdir -p "$R3"
o4="$(bash "$GI/install.sh" "$R3" 2>&1)"; rc4=$?
has "④ 명부 CMP OK" "$o4" "CMP OK  seats-graphics.json"
cmp -s "$GI/seats-graphics.json" "$R3/.fable-team/seats-graphics.json" && ok "④ 명부 복사 일치" || bad "④ 명부 복사 일치"
[ "$rc4" = 0 ] && ok "④ rc=0" || bad "④ rc=$rc4"

# ⑤ 스테이징 명부
python3 -I - "$GI/seats-graphics.json" <<'PY' && ok "⑤ 명부 파싱 · _master · _doc" || bad "⑤ 명부 파싱 · _master · _doc"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["_master"] == "byz-graphics-master-claude#0", d["_master"]
assert "하네스 master 가 열기" not in d["_doc"]
PY

# ⑥ 649 문장 0
if grep -nE 'master 0|하네스 master 가 대행|열기·감시·닫기는 하네스 master|열기·감시·닫기 = 하네스 master|하네스 master 가 연다' \
  "$W/design/graphics/RUNBOOK-open-close.md" "$GI/graphics-env.sh" "$GI/seats-graphics.json" "$GI/install.sh"; then
  bad "⑥ 649 문장 잔존"
else ok "⑥ 649 문장 0"; fi

# ⑦ 스테이징 vs 홈 정본 diff (홈이 아직 옛 정본일 때만 수 검사 · 이미 설치됐으면 동일 확인)
sum16() { shasum -a 256 "$1" | cut -c1-16; }
chk_diff() { # <이름> <옛 sha16> <기대 줄수 grep 패턴> <기대값> <라벨>
  local home="$HOME_REF/$1" stg="$STG/$1" n
  if [ ! -f "$home" ]; then echo "SKIP ⑦ $5 (홈 정본 없음)"; return; fi
  if [ "$(sum16 "$home")" = "$2" ]; then
    n="$(diff "$home" "$stg" | grep -cE "$3")"
    [ "$n" = "$4" ] && ok "⑦ $5 diff=$n" || bad "⑦ $5 diff=$n (기대 $4)"
  elif cmp -s "$home" "$stg"; then echo "SKIP ⑦ $5 (이미 설치 — 홈 == 스테이징)"
  else bad "⑦ $5 홈 정본이 옛 sha 도 스테이징도 아님"; fi
}
chk_diff main-team-governance.md d16650b52a809ecf '^[0-9]' 4 "governance 변경 hunk(추가 1 · 바꿈 3 = 5곳)"
chk_diff main-team-governance.md d16650b52a809ecf '^>' 5 "governance 새 줄"
chk_diff harness-map.md 33065f92565e622f '^>' 1 "harness-map 새 줄"
chk_diff harness-map.md 33065f92565e622f '^<' 1 "harness-map 옛 줄"

echo "---"; [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit $((fail>0))
