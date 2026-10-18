#!/usr/bin/env bash
# test_press_permit.sh — C7 허가 2종 순차 시나리오 5개 (mktemp 디렉터리만 사용 · 실제 마이크·오디오 실행 없음).
#   ①mic 1바퀴 ②api 1바퀴 ③멤버 있는 동안 2번째 가입 REJECT ④멤버 남은 채 세트 해제 REJECT ⑤장치 허가 중 두 번째 장치 요청 REJECT
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../../scripts/fable-team-bin/ft-press-permit.sh"
LIVE="$HERE/../../.fable-team/state/permits"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

LIVE_BEFORE="$(ls -la "$LIVE" 2>&1)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_PERMIT_DIR="$T"
run() { bash "$TOOL" "$@" 2>&1; }
# exp <rc> <출력 패턴> <설명> <명령…>
exp() { local rc="$1" pat="$2" desc="$3"; shift 3; local out; out="$(run "$@")"; local got=$?
  [ "$got" -eq "$rc" ] && echo "$out" | grep -q -- "$pat" && ok "$desc" || bad "$desc (rc=$got want=$rc): $out"; }

exp 0 '^OK set-acquire s1' "세트 획득" set-acquire s1 ops

# ① mic 멤버 1바퀴: 가입→장치 획득→해제→탈퇴
exp 0 '^OK join s1 mic' "① mic 가입" join s1 mic
exp 0 '^OK device-acquire mic' "① mic 장치 획득" device-acquire mic
exp 0 '^OK device-release mic' "① mic 장치 해제" device-release mic
exp 0 '^OK leave s1 mic' "① mic 탈퇴" leave s1 mic

# ② 이어서 api 멤버 1바퀴
exp 0 '^OK join s1 api' "② api 가입" join s1 api
exp 0 '^OK device-acquire api' "② api 장치 획득" device-acquire api
exp 0 '^OK device-release api' "② api 장치 해제" device-release api
exp 0 '^OK leave s1 api' "② api 탈퇴" leave s1 api

# ③ 멤버가 있는 동안 2번째 가입 REJECT (상한 1)
exp 0 '^OK join s1 mic' "③ 첫 멤버 가입" join s1 mic
exp 1 '^REJECT 세트 s1 멤버 상한 1' "③ 2번째 가입 REJECT" join s1 api
[ "$(jq '.members|length' "$T/set-s1.json")" -eq 1 ] && ok "③ 거부 뒤 멤버 1명 유지" || bad "③ 멤버 수"

# ④ 멤버가 남은 채 세트 해제 REJECT
exp 1 '^REJECT 세트 s1 에 멤버 1명 남음' "④ 멤버 남은 채 set-release REJECT" set-release s1
[ -e "$T/set-s1.json" ] && ok "④ 거부 뒤 세트 파일 유지" || bad "④ 세트 파일 사라짐"

# ⑤ 장치 허가 중 두 번째 장치 요청 REJECT (api 는 별도 세트 s2 에서)
exp 0 '^OK set-acquire s2' "⑤ 세트 s2 획득" set-acquire s2 ops
exp 0 '^OK join s2 api' "⑤ s2 api 가입" join s2 api
exp 0 '^OK device-acquire mic' "⑤ mic 장치 획득" device-acquire mic
exp 1 '^REJECT 장치 허가 이미 held (member=mic)' "⑤ 두 번째 장치 요청 REJECT" device-acquire api
exp 1 '^REJECT 장치 허가는 mic 가 쥠' "⑤ 남이 장치 해제 REJECT" device-release api
exp 1 '^REJECT 멤버 mic 이 장치 허가를 쥔 채 탈퇴 불가' "⑤ 장치 쥔 채 탈퇴 REJECT" leave s1 mic

# 정리 순서 + 상태
exp 0 '^OK device-release mic' "정리 device-release" device-release mic
exp 0 '^OK leave s1 mic' "정리 leave s1" leave s1 mic
exp 0 '^OK leave s2 api' "정리 leave s2" leave s2 api
exp 0 '^OK set-release s1' "정리 set-release s1" set-release s1
exp 0 '^OK set-release s2' "정리 set-release s2" set-release s2
out="$(run status)"; echo "$out" | grep -q '^device free' && ! echo "$out" | grep -q '^set ' && ok "status 빈 상태" || bad "status: $out"

# 보조: 멤버 아닌 장치 요청·미획득 세트 가입·usage
exp 1 '^REJECT 멤버 ghost 은 어느 세트에도' "비멤버 device-acquire REJECT" device-acquire ghost
exp 1 '^REJECT 세트 nope 허가 없음' "없는 세트 join REJECT" join nope x
run bogus >/dev/null; [ $? -eq 2 ] && ok "usage exit 2" || bad "usage exit"

# 상한 2 로 올리면 2번째 가입 통과(상한은 값)
export FT_PERMIT_MAX_MEMBERS=2
exp 0 '^OK set-acquire s3' "상한2 세트 획득" set-acquire s3 ops
exp 0 'members=1/2' "상한2 첫 가입" join s3 a
exp 0 'members=2/2' "상한2 둘째 가입 통과" join s3 b
exp 1 '^REJECT 세트 s3 멤버 상한 2' "상한2 셋째 가입 REJECT" join s3 c
unset FT_PERMIT_MAX_MEMBERS

# 라이브 상태 디렉터리 전후 비교
LIVE_AFTER="$(ls -la "$LIVE" 2>&1)"
[ "$LIVE_BEFORE" = "$LIVE_AFTER" ] && ok "라이브 permits 디렉터리 전후 무변경" || bad "라이브 permits 변경됨"

echo "fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
