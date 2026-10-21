#!/usr/bin/env bash
# test_all_stop_r626.sh — 전팀 정지 스위치(r626 · 오빠 «자율 상태와 별개로 전팀 정지 상태»): ft-all-stop.sh on|off|status|check + 막기 3곳 + 가드 훅.
# 격리: 임시 git 루트(FT_ROOT) + 임시 명부 2팀(+planner) + 가짜 mbox(FT_MBOX_SH · 받은 인자만 적는다) + 가짜 tmux/tmuxc + 가짜 자원 센서 — 실 mbox·명부·tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -u   # pipefail 쓰지 않는다 — `cmd | grep -q` 가 SIGPIPE(141)로 거짓 FAIL 을 낸다
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/kit/fable-team/bin"; HK="$HERE/../../harness/kit/fable-team/templates/hooks"
fail=0; out=""; rc=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; mkdir -p "$REPO" "$FAKE"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; display-message) echo "${FAKE_SEAT:-}";; *) exit 0;; esac\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmuxc"; chmod +x "$FAKE/tmux" "$FAKE/tmuxc"
fake_comm_root "$REPO" || bad "fake_comm_root"   # git init + .fable-team/comm · FT_ROOT=REPO
MAIL="$TMP/mail.log"; printf '#!/usr/bin/env bash\nprintf "%%s\\t" "$@" >> "%s"; echo >> "%s"\n' "$MAIL" "$MAIL" > "$TMP/mbox.sh"
export FT_MBOX_SH="$TMP/mbox.sh" PATH="$FAKE:$PATH"
mkdir -p "$REPO/.fable-team/state" "$REPO/design/v65/indices/inbox/master" "$REPO/design/teams/aa"; : > "$REPO/design/v65/SEATBELT-README.md"
echo '{"_label":"aa","_master":"byz-aa-master-claude#1","byz-aa-master-claude#1":{"role":"master"}}' > "$REPO/.fable-team/seats-aa.json"
echo '{"_label":"m.bb","_master":"byz-bb-master-claude#2","byz-bb-master-claude#2":{"role":"master"}}' > "$REPO/.fable-team/seats-bb.json"
echo '{"_label":"planner","_master":"byz-planner-master-claude#9","byz-planner-master-claude#9":{"role":"master"}}' > "$REPO/.fable-team/seats-planner.json"
echo '{}' > "$REPO/.fable-team/seats.json"
printf '# aa 상태\n' > "$REPO/design/teams/aa/STATE.md"
ST="$REPO/.fable-team/state"; AS="$ST/ALL_STOP.json"
as()   { out="$(cd "$REPO" && bash "$BIN/ft-all-stop.sh" "$@" 2>&1)"; rc=$?; }
nano() { out="$(cd "$REPO" && bash "$BIN/ft-nano-spawn.sh" "design/teams/aa/indices/대기/x.md" --dry-run 2>&1)"; rc=$?; }
role() { out="$(cd "$REPO" && env -u FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM=aa bash "$BIN/ft-role-spawn.sh" master --dry-run 2>&1)"; rc=$?; }
perm() { out="$(cd "$REPO" && FT_PERMIT_DIR="$TMP/permits" bash "$BIN/ft-press-permit.sh" "$@" 2>&1)"; rc=$?; }

# ── 꺼진 상태: 막기 0 ──
as check; ck "ⓕ 꺼짐 check rc0" "$rc"
nano; echo "$out" | grep -q '전팀 정지' ; [ $? != 0 ]; ck "ⓑ0 꺼짐 nano 정지 거절 0" $?
role; echo "$out" | grep -q '^PLAN '; ck "ⓑ0 꺼짐 role PLAN" $?
perm set-acquire s1 ops >/dev/null; perm join s1 mic; perm device-acquire mic; ck "ⓒ0 꺼짐 device-acquire OK" "$rc"

# ── ⓐ 켜기 ──
echo '{"since":1,"reason":"벌칙","order":["aa"],"resumed":[]}' > "$ST/PENALTY_STOP"; PEN0="$(cat "$ST/PENALTY_STOP")"
as on "오빠 점검"; ck "ⓐ on rc0" "$rc"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert {"since","by","reason"}<=set(d) and d["reason"]=="오빠 점검"' "$AS" 2>/dev/null; ck "ⓐ ALL_STOP.json {since,by,reason}" $?
[ "$(grep -c 'byz-aa-master-claude#1' "$MAIL")" = 1 ] && [ "$(grep -c 'byz-bb-master-claude#2' "$MAIL")" = 1 ]; ck "ⓐ 두 팀 _master 통지 1통씩" $?
grep 'byz-aa-master-claude#1' "$MAIL" | grep -q '오빠·planner 요청에만 답·간단 작업' && grep 'byz-aa-master-claude#1' "$MAIL" | grep -q '새 골·이슈·spawn·press 0' \
  && grep 'byz-aa-master-claude#1' "$MAIL" | grep -q 'design/teams/aa/STATE.md «정지 직전» 절'; ck "ⓐ 통지 본문(답만·spawn·press 0·STATE.md 정지 직전)" $?
grep 'byz-bb-master-claude#2' "$MAIL" | grep -q 'design/teams/bb/STATE.md' && grep 'byz-bb-master-claude#2' "$MAIL" | grep -q 'templates/team/STATE.md 틀로 만들기'; ck "ⓐ STATE.md 없는 팀 = 틀로 만들기 구절 (m.bb → bb)" $?
grep 'byz-aa-master-claude#1' "$MAIL" | grep -q '틀로 만들기'; [ $? != 0 ]; ck "ⓐ STATE.md 있는 팀 = 틀 구절 0" $?

# ── ⓗ 이미 켜짐 · PENALTY 무변경 ──
cp "$AS" "$TMP/as0"; : > "$MAIL"
as on "다시"; [ "$rc" = 0 ] && echo "$out" | grep -q '이미 켜짐' && cmp -s "$AS" "$TMP/as0" && [ ! -s "$MAIL" ]; ck "ⓗ 이미 켜짐 on = rc0 변경 0 통지 0" $?
[ "$(cat "$ST/PENALTY_STOP")" = "$PEN0" ]; ck "ⓗ on 이 PENALTY_STOP 무변경" $?

# ── ⓕ ⓑ ⓒ 켜진 동안 ──
as check; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중(since' && echo "$out" | grep -q '오빠 점검'; ck "ⓕ 켜짐 check rc1 사유 1줄" $?
rm -f "$ST/PENALTY_STOP"   # 막기 시험은 PENALTY 와 섞지 않는다
nano; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중(since .*) — 끄기 전 spawn'; ck "ⓑ 켜짐 nano-spawn REJECT rc1" $?
role; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중(since .*) — 끄기 전 spawn'; ck "ⓑ 켜짐 role-spawn REJECT rc1" $?
perm device-release mic; ck "ⓒ 켜짐 device-release 통과" "$rc"
perm device-acquire mic; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중(since'; ck "ⓒ 켜짐 device-acquire REJECT rc1" $?
perm status; ck "ⓒ 켜짐 status 통과" "$rc"
perm leave s1 mic; ck "ⓒ 켜짐 leave 통과" "$rc"

# ── ⓓ status ──
as status; [ "$rc" = 0 ] && echo "$out" | grep -q '^all_stop=on since=' && echo "$out" | grep -q 'team=aa state=X' && echo "$out" | grep -q 'team=m.bb state=X'; ck "ⓓ status on · 두 팀 X" $?
printf '# aa 상태\n\n## 정지 직전\n- 하던 일: r1\n' > "$REPO/design/teams/aa/STATE.md"; touch "$REPO/design/teams/aa/STATE.md"
as status; echo "$out" | grep -q 'team=aa state=O' && echo "$out" | grep -q 'team=m.bb state=X'; ck "ⓓ STATE.md «정지 직전» 적은 팀 O" $?

# ── ⓔ 끄기 ──
echo '{"since":1,"reason":"벌칙","order":["aa"],"resumed":[]}' > "$ST/PENALTY_STOP"; PEN0="$(cat "$ST/PENALTY_STOP")"; : > "$MAIL"
as off; [ "$rc" = 0 ] && [ ! -e "$AS" ] && ls "$ST"/ALL_STOP.released-* >/dev/null 2>&1; ck "ⓔ off = ALL_STOP.released-<시각> 로 옮김" $?
[ "$(grep -c 'byz-aa-master-claude#1' "$MAIL")" = 1 ] && grep 'byz-aa-master-claude#1' "$MAIL" | grep -q '재개 — design/teams/aa/STATE.md «정지 직전» 절 읽고 이어감 → 끝났으면 다음 카드(대기/ 맨 위) 착수' \
  && [ "$(grep -c 'byz-bb-master-claude#2' "$MAIL")" = 1 ]; ck "ⓔ 두 팀장 «재개» 통지" $?
[ "$(cat "$ST/PENALTY_STOP")" = "$PEN0" ]; ck "ⓗ off 가 PENALTY_STOP 무변경" $?
rm -f "$ST/PENALTY_STOP"
as check; ck "ⓕ 끈 뒤 check rc0" "$rc"
as off; [ "$rc" = 0 ] && echo "$out" | grep -q '이미 꺼짐'; ck "ⓔ 꺼진 데 off = 이미 꺼짐 rc0" $?
as bogus; [ "$rc" = 2 ]; ck "usage rc2" $?

# ── ⓖ 가드 훅 ──
IH="$TMP/hooks"; mkdir -p "$IH"; cp "$HK/autonomy-state-guard.sh" "$HK/../../../hooks/merge_cmd.py" "$IH"/
export FT_AUTONOMY_HOOK_LOG="$TMP/hook.log" TMUX=fake
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$REPO"; }
mkwrite() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","cwd":sys.argv[2],"tool_input":{"file_path":sys.argv[1],"content":"{}"}},ensure_ascii=False))' "$1" "$REPO"; }
guard() { out="$(FAKE_SEAT="$1" bash "$IH/autonomy-state-guard.sh" <<<"$2" 2>&1)"; rc=$?; }
deny()  { guard "$1" "$2"; echo "$out" | grep -q '"permissionDecision": "deny"' && echo "$out" | grep -q '전팀 정지'; }
allow() { guard "$1" "$2"; [ "$rc" = 0 ] && ! echo "$out" | grep -q deny; }
deny  "byz-aa-master-claude#1" "$(mkbash 'bash .fable-team/bin/ft-all-stop.sh on "x"')"; ck "ⓖ 좌석 on 직접 = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'FT_X=1 bash /r/.fable-team/bin/ft-all-stop.sh off')"; ck "ⓖ 좌석 off 직접 = deny" $?
deny  "" "$(mkbash 'ft-all-stop.sh on "x"')"; ck "ⓖ 좌석 이름 못 읽음 on = deny" $?
allow "byz-planner-master-claude#9" "$(mkbash 'bash .fable-team/bin/ft-all-stop.sh on "오빠 요청"')"; ck "ⓖ planner _master on = 통과" $?
allow "byz-aa-master-claude#1" "$(mkbash 'bash .fable-team/bin/ft-all-stop.sh status; ft-all-stop.sh check')"; ck "ⓖ 좌석 status·check = 통과" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'echo {} > .fable-team/state/ALL_STOP.json')"; ck "ⓖ 좌석 ALL_STOP.json 쓰기 = deny" $?
deny  "byz-planner-master-claude#9" "$(mkwrite "$AS")"; ck "ⓖ planner 도 ALL_STOP.json 직접 Write = deny(도구로만)" $?
allow "byz-aa-master-claude#1" "$(mkbash 'cat .fable-team/state/ALL_STOP.json')"; ck "ⓖ 읽기 = 통과" $?
H="$TMP/h7"; printf 'bash /r/.fable-team/bin/ft-all-stop.sh on "점검"\n' > "$H"
deny  "byz-aa-master-claude#1" "$(mkbash "bash $H")"; ck "ⓖ 좌석이 bash /tmp/hN(정지 켜기) 실행 = deny" $?
allow "byz-planner-master-claude#9" "$(mkbash "bash $H")"; ck "ⓖ planner _master 가 hN 실행 = 통과" $?
guard "byz-aa-master-claude#1" "$(mkbash 'bash .fable-team/bin/ft-autonomy.sh on')"; echo "$out" | grep -q '자율 모드 상태 파일'; ck "ⓖ 기존 자율 막기 문구 그대로" $?
unset TMUX

# ── 변이: 막기 3곳 검사 줄을 하나씩 지우면 빨강 ──
as on "변이"
for f in ft-nano-spawn.sh ft-role-spawn.sh ft-press-permit.sh; do
  M="$TMP/mut-$f/.fable-team/bin"; mkdir -p "$M"; cp -R "$BIN"/. "$M"/
  grep -v 'ft-all-stop.sh" check' "$BIN/$f" > "$M/$f"
  case "$f" in   # 검사 줄이 빠지면 게이트 «뒤» 단계까지 간다(문법 오류로 거짓 통과 0) — pass = 그 뒤 단계 표지
    ft-nano-spawn.sh)  pass='팀 env 없음'; out="$(cd "$REPO" && bash "$M/$f" "design/teams/aa/indices/대기/x.md" --dry-run 2>&1)";;
    ft-role-spawn.sh)  pass='^PLAN '; out="$(cd "$REPO" && env -u FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM=aa bash "$M/$f" master --dry-run 2>&1)";;
    ft-press-permit.sh) pass='^OK device-acquire mic'; out="$(cd "$REPO" && FT_PERMIT_DIR="$TMP/permits" bash "$M/$f" join s1 mic >/dev/null; cd "$REPO" && FT_PERMIT_DIR="$TMP/permits" bash "$M/$f" device-acquire mic 2>&1)";;
  esac
  ! cmp -s "$BIN/$f" "$M/$f" && ! echo "$out" | grep -q '전팀 정지 중' && echo "$out" | grep -q "$pass"; ck "변이 $f 검사 줄 제거 → 막기 0 · 뒤 단계 도달(시험이 잡는다)" $?
done
as off

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
