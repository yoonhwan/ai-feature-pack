#!/usr/bin/env bash
# test_press_baseline_check.sh — #834 press 기준선 게이트 ⑥ (설계 DESIGN-834-baseline-gate-arch165.md §7 C2 + «C2 잔여 2»).
#   고정 입력 임시 git 저장소만 사용 · 실제 press·오디오 0. 전 케이스를 «ft-press-gate.sh 최종 exit» 로 단언:
#   SELFTEST 성공 = 3 · 막힘 = 1 · 보통 모드에 SELFTEST 상속 = 1 · SELFTEST 출력에 «발화해도 된다» 0건.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
fin=0; T=""   # r2249 O2: 끝 표지 — 중간에 죽거나 exit 0 해도 EXIT trap 이 rc 1 로 바꾼다(bash 3.2 연관 배열 죽음 = rc 0)
trap 'rc=$?; [ -n "$T" ] && rm -rf "$T"; [ "$fin" = 1 ] || { echo "FAIL 끝 줄 없음 — 시험이 끝까지 돌지 않음(rc=$rc)"; exit 1; }; exit $rc' EXIT
WANT_CASES=30   # r2249 O2: 기대 사례 수(expect 칸을 더하면 같이 고친다)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
GATE="$BIN/ft-press-gate.sh"
fail=0; n=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
bash -n "$BIN/ft-press-baseline-check.sh" && ok "bash -n baseline-check" || bad "bash -n baseline-check"

T="$(mktemp -d)"
R="$T/repo"; mkdir -p "$R/worker" "$R/design/v65/baselines/ev" "$R/cards" "$T/root/.fable-team"
mkdir -p "$T/root/.fable-team/state"   # r626 DA⑥ r2: 상태 폴더 없음 = 전팀 정지 — 픽스처 루트에 빈 상태 폴더(원장·상태 파일 없음 = 꺼짐)
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$T/root/.fable-team/state"/all-stop.log   # r626 r4: 원장 없음 = 전팀 정지 — 설치가 남기는 init 줄(꺼짐)
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"   # R382b: v65 폴더는 TEAMS.md 칸으로 풀린다
echo '{}' > "$T/root/.fable-team/seats.json"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/worker/a.py"
cat > "$R/design/v65/baselines/FLAGS.md" <<'EOF'
| key | 기본값 | OFF 값 | 읽는 자리 |
|---|---|---|---|
| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |
| `V65_TOGGLE_B` | `off` | `off` | worker/a.py:1 |
EOF
git -C "$R" add -A && git -C "$R" commit -qm base
SHA="$(git -C "$R" rev-parse HEAD)"
OKFLAGS="V65_TOGGLE_A=1,V65_TOGGLE_B=off"

result() { # 파일 set_sha session_id → 러너 RESULT json
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"%s","failed":true}\n' "$2" "$3" > "$1"; }
result "$R/design/v65/baselines/ev/RESULT-ok.json" "$SHA" run-1
result "$R/design/v65/baselines/ev/RESULT-other.json" "$(printf 'a%.0s' {1..40})" run-1

base() { # 이름 [키 값]… → 기준선 파일(기본 머리줄 · 값 __DROP__ = 그 줄 빼기) · r2249: 연관 배열 대신 v_<키> 변수(bash 3.2)
  local f="$R/design/v65/baselines/$1.md"; shift
  local v_set_sha="$SHA" v_control="lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=$OKFLAGS" \
    v_side_lang="right=ko left=en" v_server_ready="2026-10-07T03:00:00Z" v_visible_at_settle="yes" \
    v_evidence="design/v65/baselines/ev/RESULT-ok.json" v_run_id="run-1" v_profile="__DROP__" k vn
  while [ $# -gt 0 ]; do printf -v "v_$1" '%s' "$2"; shift 2; done
  : > "$f"
  for k in profile set_sha control side_lang server_ready visible_at_settle evidence run_id; do
    vn="v_$k"; [ "${!vn}" = "__DROP__" ] || echo "$k: ${!vn}" >> "$f"
  done
  printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n' >> "$f"
}
card() { # 이름 머리줄… → 카드 경로
  local f="$R/cards/$1.md"; shift
  { echo "# 카드 $1"; printf '%s\n' "$@"; } > "$f"; echo "$f"; }

gate() { # FT_PRESS_CARD(빈 값 = 미지정) [env…] → 최종 exit · 출력은 $OUT
  local c="$1"; shift
  OUT="$(env -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_CARD FT_PRESS_WT="$R" FT_PRESS_ROOT="$T/root" \
    FT_PRESS_SEAT='byz-v65-tester-claude#0' FT_PRESS_EVID="$T/evid" FT_PRESS_PERMIT_DIR="$T/permits" \
    ${c:+FT_PRESS_CARD="$c"} "$@" bash "$GATE" 2>&1)"; }
expect() { # 기대exit 출력패턴(막힌 칸·통과 줄) 설명 카드 [env…]
  local want="$1" pat="$2" desc="$3"; shift 3; n=$((n+1))
  gate "$@"; local got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$OUT" | grep -q -- "$pat" && ! printf '%s' "$OUT" | grep -q '발화해도 된다'; then ok "$n. $desc (exit $got)"
  else bad "$n. $desc (exit $got want $want)"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}
ST="FT_PRESS_GATE_SELFTEST=1"
P="design/v65/baselines"

base ok
base nohdr visible_at_settle __DROP__
base badsha set_sha "$(printf 'b%.0s' {1..40})"
base unknown visible_at_settle unknown
base flagsoff control "lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=0,V65_TOGGLE_B=off"
base noev evidence "$P/ev/RESULT-missing.json"
base evother evidence "$P/ev/RESULT-other.json"
echo '[]' > "$R/$P/ev/RESULT-array.json"; base evarr evidence "$P/ev/RESULT-array.json"
# 검사기 비정상 종료 재현: BLOCK 줄 없이 비0 으로 죽는 python3 를 PATH 앞에 둔다(DA⑥ r1 — 줄 부재를 통과로 읽으면 안 된다)
mkdir -p "$T/fakebin" && printf '#!/bin/sh\ncase "$1" in *ft_all_stop.py) exec %s "$@";; esac\nexit 9\n' "$(command -v python3)" > "$T/fakebin/python3" && chmod +x "$T/fakebin/python3"   # r626: ⓪ 전팀 정지 판정기(ft_all_stop.py)만 진짜 python — 이 시험은 기준선 검사기의 비정상 종료를 본다

expect 1 '⑥ 카드 미지정' "카드 미지정 → 막힘" "" "$ST"
expect 1 'BLOCK 카드 기준선: 없음' "카드 기준선: 없음 → 막힘" "$(card none '기준선: 없음' '실험: 없음')" "$ST"
expect 1 'BLOCK 기준선 파일: 없음' "기준선 파일 없음 → 막힘" "$(card nofile "기준선: $P/BASELINE-nope.md" '실험: 없음')" "$ST"
expect 1 'BLOCK 기준선 머리줄 빠짐: visible_at_settle' "머리줄 빠짐(visible_at_settle) → 막힘" "$(card c-nohdr "기준선: $P/nohdr.md" '실험: 없음')" "$ST"
expect 1 'BLOCK set_sha:' "set_sha 불량(이 저장소에 없음) → 막힘" "$(card c-badsha "기준선: $P/badsha.md" '실험: 없음')" "$ST"
expect 1 'BLOCK visible_at_settle: unknown' "visible_at_settle: unknown → 막힘" "$(card c-unknown "기준선: $P/unknown.md" '실험: 없음')" "$ST"
expect 1 'BLOCK side_lang:' "side_lang 불일치(카드 비교 언어 right=en) → 막힘" "$(card c-lang "기준선: $P/ok.md" '실험: 없음' '비교 언어: right=en,left=ko')" "$ST"
expect 1 'BLOCK self: 종류' "보통 카드(종류: 측정 · 회차: 12) self → 막힘" "$(card self-normal '기준선: self' '종류: 측정' '회차: 12' '실험: 없음' '프로필: default-3bubble')" "$ST"
expect 1 'BLOCK self: 프로필' "프로필 ≠ default-3bubble self → 막힘" "$(card self-prof '기준선: self' '종류: 기준선' '회차: 1' '실험: 없음' '프로필: long-3m')" "$ST"
expect 1 'BLOCK control flags: V65_TOGGLE_A=0' "flags 비기본(V65_TOGGLE_A=0) → 막힘" "$(card c-flags "기준선: $P/flagsoff.md" '실험: 없음')" "$ST"
expect 1 'BLOCK evidence: 증거 없음' "evidence 부재(머리줄 정상) → 막힘" "$(card c-noev "기준선: $P/noev.md" '실험: 없음')" "$ST"
expect 1 'BLOCK evidence: 증거 불일치 — RESULT set_sha' "evidence set_sha 불일치 → 막힘" "$(card c-evother "기준선: $P/evother.md" '실험: 없음')" "$ST"
OKCARD="$(card c-ok "기준선: $P/ok.md" '실험: V65_TOGGLE_B=on')"
expect 3 'diff 0 = 커밋 소스 동일' "정상 경로(실험 key ⊂ FLAGS.md · 측정 실패 회차도 유효) → SELFTEST 성공 3" "$OKCARD" "$ST"
SELFCARD="$(card self-ok '기준선: self' '종류: 기준선' '회차: 1' '실험: 없음' '프로필: default-3bubble')"
expect 3 '기준선 self — 이 회차가 기준선이다' "제한된 self(종류 기준선·회차 1·실험 없음·default-3bubble) → SELFTEST 성공 3" "$SELFCARD" "$ST"
expect 1 '시험 모드 상속 — 발사 금지' "보통 모드에 SELFTEST 상속(FT_PRESS_GATE_SELFTEST=0) → 막힘" "$OKCARD" FT_PRESS_GATE_SELFTEST=0
expect 1 'BLOCK evidence: 증거 없음 — 형식' "evidence JSON 배열 [] → 막힘" "$(card c-evarr "기준선: $P/evarr.md" '실험: 없음')" "$ST"
expect 1 'BLOCK 검사기: python 비정상 종료(rc=9)' "검사기 비정상 종료(BLOCK 줄 0 · rc 9) → 막힘" "$OKCARD" "$ST" PATH="$T/fakebin:$PATH"
echo 'x = 2' > "$R/worker/a.py"; git -C "$R" commit -qam change
expect 1 'BLOCK 세트 변경' "세트 경로 변경 뒤 → 막힘" "$OKCARD" "$ST"
n=$((n+1)); gate "$SELFCARD" "$ST"; got=$?
[ "$got" -eq 3 ] && printf '%s' "$OUT" | grep -q '^PRESS-GATE SELFTEST PASS$' && ! printf '%s' "$OUT" | grep -q '발화해도 된다' \
  && ok "$n. SELFTEST 성공 출력에 «발화해도 된다» 0건 · 마지막 판정 = SELFTEST PASS" || bad "$n. SELFTEST 출력 (exit $got)"

# r2245: 기준선 머리줄 «profile: room»(방 러너 기준선) — 카드 머리 «프로필: default-3bubble» 과 다른 칸 · 새 저장소(위 세트 변경과 분리)
R="$T/repo2"; mkdir -p "$R/worker" "$R/$P/ev" "$R/cards" && cp "$T/repo/design/TEAMS.md" "$R/design/TEAMS.md"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/worker/a.py"
RK="PRESS_LST:1 PRESS_POLISH_DIFF:0 PRESS_DOMAIN_QS:dental PRESS_VAD_AUTO:unset PRESS_VAD_SHAPE:unset PRESS_VAD_P:unset PRESS_CHUNK_MS:unset PRESS_SILENCE_MS:unset PRESS_LST_INTERVAL_MS:unset PRESS_OWNER_CAP_MS:unset PRESS_TTS_RIGHT:unset PRESS_LST_TOGGLE_MID_PRESS_MS:0 V6_LST:1 V65_TOGGLE_A:1"
{ printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n'; for kv in $RK; do printf '| `%s` | `%s` | `0` | x |\n' "${kv%%:*}" "${kv#*:}"; done; } > "$R/$P/FLAGS.md"
git -C "$R" add -A && git -C "$R" commit -qm base
SHA="$(git -C "$R" rev-parse HEAD)"
roomflags() { # [key=값 바꿈 | key=__DROP__]… → FLAGS.md 기본값 기준 flags= 값
  local kv k v o out=""; for kv in $RK; do k="${kv%%:*}"; v="${kv#*:}"
    for o in "$@"; do [ "${o%%=*}" = "$k" ] && v="${o#*=}"; done
    [ "$v" = "__DROP__" ] || out="$out${out:+,}$k=$v"; done; printf '%s' "$out"; }
OKFLAGS="$(roomflags)"
rctl() { echo "lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=$1 flags=${2:-$OKFLAGS}"; }
roomres() { # 파일 control-json [scenario_id 칸] → 방 러너 RESULT json(가짜 · 네트워크 0)
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"run-1","control":%s%s}\n' "$SHA" "$2" "${3-,\"scenario_id\":\"room-s1\"}" > "$R/$P/ev/$1"; }
roomres RESULT-room.json '{"click":null,"click_reason":"방 러너는 PRESS_SIDE_LANG_CLICK 을 안 읽음"}'
roomres RESULT-room-click.json '{"click":"PRESS_SIDE_LANG_CLICK:1","click_reason":null}'
roomres RESULT-room-ctlstr.json '"click=room-keyboard"'
RE="$P/ev/RESULT-room.json"
base r-ok profile room control "$(rctl room-keyboard)" evidence "$RE"
base r-solo control "$(rctl room-keyboard)" evidence "$RE"
base r-click1 profile room control "$(rctl PRESS_SIDE_LANG_CLICK:1)" evidence "$RE"
base r-resclick profile room control "$(rctl room-keyboard)" evidence "$P/ev/RESULT-room-click.json"
base r-ctlstr profile room control "$(rctl room-keyboard)" evidence "$P/ev/RESULT-room-ctlstr.json"
base r-press profile room control "$(rctl room-keyboard "$(roomflags PRESS_LST=unset PRESS_DOMAIN_QS=__DROP__)")" evidence "$RE"
base r-v6 profile room control "$(rctl room-keyboard "$(roomflags V6_LST=0)")" evidence "$RE"
base r-roomx profile roomx control "$(rctl room-keyboard)" evidence "$RE"
base r-noev profile room control "$(rctl room-keyboard)" evidence ""
base r-mid profile room control "$(rctl room-keyboard "$(roomflags PRESS_LST_TOGGLE_MID_PRESS_MS=500)")" evidence "$RE"
base s-noev control "$(rctl PRESS_SIDE_LANG_CLICK:1)" evidence ""   # r2249 ④: solo · evidence 키 있음 ∧ 값 빈
rc_() { card "$1" "기준선: $P/$1.md" '실험: 없음'; }
expect 3 'diff 0 = 커밋 소스 동일' "① 머리줄 profile: room(≠ 카드 머리 프로필) · click=room-keyboard · RESULT click null+사유 · scenario_id → 통과" "$(rc_ r-ok)" "$ST"
expect 1 'BLOCK control click: room-keyboard — 기준선 프로필은 PRESS_SIDE_LANG_CLICK:1 고정' "② profile 없음(solo) · click=room-keyboard → 막힘" "$(rc_ r-solo)" "$ST"
expect 1 'BLOCK control click: PRESS_SIDE_LANG_CLICK:1 — profile room 은 room-keyboard 만' "③ profile room · click=PRESS_SIDE_LANG_CLICK:1 → 막힘" "$(rc_ r-click1)" "$ST"
expect 1 'BLOCK profile room ↔ RESULT 불일치' "④ profile room · RESULT control.click 값 있음 → 막힘" "$(rc_ r-resclick)" "$ST"
expect 1 'BLOCK profile room ↔ RESULT 불일치 — control dict 아님' "④-2 profile room · RESULT control 이 dict 아님 → 막힘" "$(rc_ r-ctlstr)" "$ST"
notes1() { [ "$(printf '%s\n' "$OUT" | grep -c 'NOTE room: PRESS_\* 11개 대조 제외(방 러너가 읽지 않음)')" -eq 1 ] && ok "$n-b. NOTE 1줄(11개)" || bad "$n-b. NOTE 수"; }
expect 3 'NOTE room: PRESS_\* 11개 대조 제외' "⑤ profile room · PRESS_LST=unset · PRESS_DOMAIN_QS 누락 → 통과 + NOTE" "$(rc_ r-press)" "$ST"; notes1
expect 1 'BLOCK control flags: V6_LST=0 ≠ 기본값 1' "⑥ profile room · V6_LST=0(worker key) → 막힘" "$(rc_ r-v6)" "$ST"
expect 1 'BLOCK profile: roomx — profile: room 만' "⑦ profile: roomx → 막힘" "$(rc_ r-roomx)" "$ST"
expect 1 'BLOCK control flags: PRESS_LST_TOGGLE_MID_PRESS_MS=500 ≠ 기본값 0' "⑨ profile room · PRESS_LST_TOGGLE_MID_PRESS_MS=500(방 러너가 읽음) → 막힘" "$(rc_ r-mid)" "$ST"; notes1
EVE='BLOCK evidence: 빈 값 — RESULT json 경로 필수'
evempty1() { [ "$(printf '%s\n' "$OUT" | grep -c '^[[:space:]]*BLOCK evidence: 빈 값')" -eq 1 ] && ! printf '%s' "$OUT" | grep -q 'RESULT 없음' && ok "$n-b. 빈 evidence BLOCK 1줄 · 겹침 0" || bad "$n-b. 빈 evidence BLOCK 수"; }
expect 1 "$EVE" "⑩ profile room · evidence: 빈 값 → 막힘(RESULT 대조 건너뜀 0)" "$(rc_ r-noev)" "$ST"; evempty1
expect 1 "$EVE" "⑪ solo · evidence: 빈 값 → 막힘(profile 상관없음 · r2249)" "$(rc_ s-noev)" "$ST"; evempty1

[ "$n" -eq "$WANT_CASES" ] || bad "사례 수 $n ≠ 기대 $WANT_CASES"
echo "cases=$n fail=$fail"; fin=1; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
