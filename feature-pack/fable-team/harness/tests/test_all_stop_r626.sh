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
printf '#!/usr/bin/env bash\ncase "$1" in has-session) t="${3#=}"; case " ${FAKE_ALIVE:-} " in *" $t "*) exit 0;; esac; echo "can'"'"'t find session: $t" >&2; exit 1;; display-message) echo "${FAKE_SEAT:-}";; *) exit 0;; esac\n' > "$FAKE/tmux"   # r2: has-session = FAKE_ALIVE 목록
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
# r688: STATE.md 자리 = 명단(origin/main:design/TEAMS.md) 칸 — 시험 팀 aa·bb 행 + 꼴3 harness 행을 명단에 싣고 origin/main 으로 고정
printf '| aa | `design/teams/aa/` | a | 현역 |\n| bb | `design/teams/bb/` | b | 현역 |\n' >> "$REPO/design/TEAMS.md"
sed -i '' 's#| harness | `design/harness/`#| harness | `$FT_HARNESS_ROOT/design/harness/`#' "$REPO/design/TEAMS.md"
git -C "$REPO" add design/TEAMS.md && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m teams && git -C "$REPO" update-ref refs/remotes/origin/main HEAD || bad "r688 명단 고정"
rc=0; out=""; o="$(cd "$REPO" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_all_stop as a; print(a.team_rel("m.bb"), a.team_rel("harness"))
try: a.team_rel("zz"); print("NO-RAISE")
except a.TeamPathError as e: print("RAISE", e)' "$BIN" 2>&1)"
[ "$(printf '%s\n' "$o" | head -1)" = "design/teams/bb/STATE.md design/harness/STATE.md" ] && printf '%s\n' "$o" | grep -q '^RAISE ERROR zz' && ok "r688 team_rel = 명단 칸(꼴2 · 꼴3 리포 안 자리) · 명단에 없는 팀 = TeamPathError" || bad "r688 team_rel ← $o"
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
# DA⑥ r1 Q2 — 실행 꼴·지우기·옮기기 (위협 모델 안 = 평범한 한 줄)
deny  "byz-aa-master-claude#1" "$(mkbash 'python3 /r/.fable-team/bin/ft_all_stop.py off')"; ck "Q2 python3 ft_all_stop.py off = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'sh /r/.fable-team/bin/ft-all-stop.sh on "x"')"; ck "Q2 sh ft-all-stop.sh on = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash '/r/.fable-team/bin/ft-all-stop.sh off')"; ck "Q2 직접 경로 off = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'cd /r && python3 .fable-team/bin/ft_all_stop.py on 점검')"; ck "Q2 python3 ft_all_stop.py on = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'rm -f /r/.fable-team/state/ALL_STOP.json')"; ck "Q2 rm ALL_STOP.json = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'mv /r/.fable-team/state /tmp/x')"; ck "Q2 mv .fable-team/state 폴더 = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash 'rm -rf .fable-team/state/')"; ck "Q2 rm -rf .fable-team/state/ = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash "python3 -c \"import os; os.remove('/r/.fable-team/state/ALL_STOP.json')\"")"; ck "Q2 python -c os.remove 문자열 = deny" $?
deny  "byz-aa-master-claude#1" "$(mkbash "python3 - <<'EOF'
from pathlib import Path
Path('/r/.fable-team/state/ALL_STOP.json').unlink()
EOF")"; ck "Q2 python heredoc unlink = deny" $?
deny  "byz-planner-master-claude#9" "$(mkbash "python3 -c \"import shutil; shutil.move('/r/.fable-team/state/ALL_STOP.json','/tmp/y')\"")"; ck "Q2 planner 도 python shutil 옮기기 = deny(도구로만)" $?
allow "byz-planner-master-claude#9" "$(mkbash 'python3 /r/.fable-team/bin/ft_all_stop.py off')"; ck "Q2 planner _master python 꼴 off = 통과" $?
allow "byz-aa-master-claude#1" "$(mkbash 'python3 /r/.fable-team/bin/ft_all_stop.py status')"; ck "Q2 좌석 python 꼴 status = 통과" $?
allow "byz-aa-master-claude#1" "$(mkbash 'mv /r/.fable-team/state/x.json /r/.fable-team/state/y.json')"; ck "Q2 상태 폴더 안 다른 파일 mv = 통과" $?
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

# ── DA⑥ r1 Q1 열기 길 · press 게이트 (정지 켜진 채) ──
printf 'g1\ng2\ng3\n본문\n' > "$TMP/body.txt"
succ() { out="$(cd "$REPO" && FT_SO_WAIT_MAX=1 FT_SO_POLL=0 bash "$BIN/ft-successor-open.sh" "$1" "$REPO" --name "$2" --agent claude --model m --body-file "$TMP/body.txt" 2>&1)"; rc=$?; }
succ "byz-aa-master-claude#1" "byz-aa-nano-x#0"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "Q1 successor-open 새 이름 = REJECT rc1" $?
succ "byz-aa-master-claude#1" "byz-aa-master-claude#3"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "Q1 successor-open 계보 건너뜀(#1→#3) = REJECT" $?
succ "byz-zz-master-claude#1" "byz-zz-master-claude#2"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "Q1 successor-open 구 좌석 세션 없음(계보 #N+1 이어도) = REJECT" $?
succ "byz-aa-master-claude#1" "byz-aa-master-claude#2"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "r2 닫힌(세션 없는) 구 좌석 계보 다음 번호 승계 = REJECT" $?
export FAKE_ALIVE="byz-aa-master-claude#1"
succ "byz-aa-master-claude#1" "byz-aa-master-claude#2"; ! echo "$out" | grep -q '^REJECT 전팀 정지' && echo "$out" | grep -q '진짜 승계'; ck "Q1 successor-open 진짜 승계(#1→#2 · 구 좌석 세션 살아 있음) = 통과" $?
succ "byz-aa-master-claude#1" "byz-aa-nano-x#0"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "r2 살아 있는 구 좌석이어도 새 이름 = REJECT" $?
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["byz-aa-master-claude#1"]["role"]="stop-ready";json.dump(d,open(p,"w"))' "$REPO/.fable-team/seats-aa.json"
succ "byz-aa-master-claude#1" "byz-aa-master-claude#2"; [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "r2 명부 행 role=stop-ready 면 승계 예외 0" $?
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["byz-aa-master-claude#1"]["role"]="master";json.dump(d,open(p,"w"))' "$REPO/.fable-team/seats-aa.json"
unset FAKE_ALIVE
out="$(cd "$REPO" && bash "$BIN/ft-tmux-spawn.sh" --root "$REPO" --name byz-aa-worker-claude#0 --role worker 2>&1)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중'; ck "Q1 tmux-spawn = REJECT rc1" $?
out="$(FT_PRESS_WT="$REPO" FT_PRESS_ROOT="$REPO" bash "$BIN/ft-press-gate.sh" 2>&1)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중'; ck "Q1 press-gate = 막힘 rc1(첫 검사)" $?
as off

# ── DA⑥ r1 Q3 깨진 상태 = 정지(읽기 이상) ──
for bad in 'null' '[]' '7' '' '{bad'; do
  printf '%s' "$bad" > "$AS"; as check
  [ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중(상태 파일 읽기 이상' && ! echo "$out" | grep -q Traceback; ck "Q3 상태 «${bad}» = check rc1 사유 1줄(traceback 0)" $?
done
as status; [ "$rc" = 0 ] && echo "$out" | grep -q '^all_stop=on(읽기 이상'; ck "Q3 깨진 상태 status = on(읽기 이상)" $?
as off; [ "$rc" = 0 ] && [ ! -e "$AS" ]; ck "Q3 깨진 상태도 off 로 치움" $?
mkdir "$AS"; nano; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중'; ck "Q3 상태 경로가 폴더 = nano-spawn REJECT" $?
role; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중'; ck "Q3 상태 경로가 폴더 = role-spawn REJECT" $?
rmdir "$AS"

# ── DA⑥ r1 Q4 통지 실패 = rc3 + notify_failed · 재실행 = 실패분만 ──
printf '#!/usr/bin/env bash\nprintf "%%s\\t" "$@" >> "%s"; echo >> "%s"\ncase "$2" in *bb-master*) [ -e "%s/bbfail" ] && exit 1;; esac\nexit 0\n' "$MAIL" "$MAIL" "$TMP" > "$TMP/mbox.sh"
: > "$TMP/bbfail"; : > "$MAIL"
as on "통지 시험"; [ "$rc" = 3 ] && echo "$out" | grep -q '상태 바뀜 · 통지 실패 1: byz-bb-master-claude#2' && [ -e "$AS" ]; ck "Q4 on 통지 실패 = rc3 · 상태는 켜짐" $?
python3 -c 'import json,sys;assert json.load(open(sys.argv[1]))["notify_failed"]==["byz-bb-master-claude#2"]' "$AS" 2>/dev/null; ck "Q4 notify_failed 기록" $?
rm -f "$TMP/bbfail"; : > "$MAIL"; cp "$AS" "$TMP/as1"
as on "통지 시험"; [ "$rc" = 0 ] && [ "$(grep -c . "$MAIL")" = 1 ] && grep -q 'byz-bb-master-claude#2' "$MAIL"; ck "Q4 재실행 on = 실패분만 재통지 rc0" $?
python3 -c 'import json,sys;a,b=(json.load(open(p)) for p in sys.argv[1:]);assert a["notify_failed"]==[] and a["since"]==b["since"]' "$AS" "$TMP/as1" 2>/dev/null; ck "Q4 재통지 뒤 notify_failed 비움 · since 그대로" $?
: > "$TMP/bbfail"; : > "$MAIL"
as off; [ "$rc" = 3 ] && echo "$out" | grep -q '통지 실패 1: byz-bb-master-claude#2' && [ ! -e "$AS" ]; ck "Q4 off 통지 실패 = rc3 · 상태는 꺼짐" $?
rm -f "$TMP/bbfail"; : > "$MAIL"
as off; [ "$rc" = 0 ] && [ "$(grep -c . "$MAIL")" = 1 ] && grep 'byz-bb-master-claude#2' "$MAIL" | grep -q '재개'; ck "Q4 재실행 off = 실패분만 «재개» 재통지" $?
: > "$MAIL"; as off; [ "$rc" = 0 ] && [ ! -s "$MAIL" ]; ck "Q4 실패분 없으면 off 재실행 통지 0" $?

# ── r688 H1: 명단(TEAMS.md) 밖 팀 1개가 통지 루프를 끊지 않는다 — 그 팀장 = 실패(rc3 · notify_failed · 재통지) · 뒤 팀(planner) 통지 O ──
echo '{"_label":"cc","_master":"byz-cc-master-claude#3","byz-cc-master-claude#3":{"role":"master"}}' > "$REPO/.fable-team/seats-cc.json"
: > "$MAIL"; as on "명단 밖 팀"
[ "$rc" = 3 ] && echo "$out" | grep -q '통지 실패 1: byz-cc-master-claude#3' && [ "$(grep -c . "$MAIL")" = 3 ] && grep -q 'byz-planner-master-claude#9' "$MAIL" && ! grep -q 'byz-cc-master' "$MAIL"; ck "r688 on: 명단 밖 팀 = 실패 1 rc3 · 나머지 3팀(뒤 planner 포함) 통지" $?
python3 -c 'import json,sys;assert json.load(open(sys.argv[1]))["notify_failed"]==["byz-cc-master-claude#3"]' "$AS" 2>/dev/null; ck "r688 on: notify_failed = 명단 밖 팀장" $?
as status; [ "$rc" = 0 ] && echo "$out" | grep -q 'team=cc state=X file=명단 못 풂' && echo "$out" | grep -q 'team=planner state='; ck "r688 status: 명단 밖 팀 줄 = 사유 · rc0 · 다른 팀 줄 계속" $?
: > "$MAIL"; as on "명단 밖 팀"; [ "$rc" = 3 ] && [ ! -s "$MAIL" ] && echo "$out" | grep -q '실패분 재통지 1'; ck "r688 재실행 on = 그 팀만 재시도(아직 명단 밖 → 다시 실패 rc3)" $?
: > "$MAIL"; as off; [ "$rc" = 3 ] && echo "$out" | grep -q '통지 실패 1: byz-cc-master-claude#3' && [ "$(grep -c . "$MAIL")" = 3 ] && grep 'byz-planner-master-claude#9' "$MAIL" | grep -q '재개'; ck "r688 off: 명단 밖 팀 = 실패 rc3 · 나머지 «재개» 통지" $?
printf '| cc | `design/teams/cc/` | c | 현역 |\n' >> "$REPO/design/TEAMS.md"; git -C "$REPO" add design/TEAMS.md && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m cc && git -C "$REPO" update-ref refs/remotes/origin/main HEAD
: > "$MAIL"; as off; [ "$rc" = 0 ] && [ "$(grep -c . "$MAIL")" = 1 ] && grep 'byz-cc-master-claude#3' "$MAIL" | grep -q '재개'; ck "r688 명단에 실린 뒤 off 재실행 = 그 팀만 «재개» rc0" $?
rm -f "$REPO/.fable-team/seats-cc.json"

# ── DA⑥ r2 재설계: «없음 = 꺼짐» 가정 제거 · 꺼짐 증거 = 원장(all-stop.log) 마지막 off 줄 ──
LOG="$ST/all-stop.log"
as on "r2"; tail -1 "$LOG" | awk -F'\t' '$2=="on"{f=1} END{exit !f}'; ck "r2 on = 원장 마지막 줄 on" $?
python3 -c "import os; os.rename('$AS', '$TMP/as.moved')"; as check
[ "$rc" = 1 ] && echo "$out" | grep -q '상태 파일 사라짐'; ck "r2 python os.rename 로 상태 파일만 옮김 → check rc1 «상태 파일 사라짐»" $?
nano; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중'; ck "r2 상태 파일 사라짐 → nano-spawn REJECT" $?
perm device-acquire mic; [ "$rc" = 1 ] && echo "$out" | grep -q '전팀 정지 중'; ck "r2 상태 파일 사라짐 → device-acquire REJECT" $?
(cd "$REPO/.fable-team" && mv state state.saved); as check
[ "$rc" = 1 ] && echo "$out" | grep -q '상태 폴더 없음'; ck "r2 mv state state.saved → check rc1 «상태 폴더 없음»" $?
role; [ "$rc" = 1 ] && echo "$out" | grep -q '상태 폴더 없음'; ck "r2 상태 폴더 없음 → role-spawn REJECT" $?
(cd "$REPO/.fable-team" && mv state.saved state)
as off; [ "$rc" = 0 ] && tail -1 "$LOG" | awk -F'\t' '$2=="off"{f=1} END{exit !f}'; ck "r2 상태 파일 없이 원장 on → off 로 끔 · 원장 마지막 off" $?
as check; ck "r2 원장 마지막 off → check rc0" "$rc"
cp "$LOG" "$TMP/log.ok"; printf 'garbage line\n' >> "$LOG"; as check
[ "$rc" = 1 ] && echo "$out" | grep -q '원장 읽기 이상'; ck "r2 원장 깨짐(마지막 줄 꼴 틀림) → check rc1" $?
cp "$TMP/log.ok" "$LOG"
mkdir "$AS"; as off; [ "$rc" = 1 ] && [ -d "$AS" ] && echo "$out" | grep -q '사람 확인'; ck "r2 상태 경로 폴더 + off → rc1 옮김 0 · 사람 확인" $?
rmdir "$AS"
: > "$TMP/bbfail"; as on "r2 통지"; as off; [ "$rc" = 3 ] && tail -1 "$LOG" | grep -q 'notify_failed=byz-bb-master-claude#2'; ck "r2 off 통지 실패 → 원장 off 줄 notify_failed" $?
rm -f "$TMP/bbfail"; rm -f "$ST"/ALL_STOP.released-*; : > "$MAIL"
as off; [ "$rc" = 0 ] && [ "$(grep -c . "$MAIL")" = 1 ] && grep 'byz-bb-master-claude#2' "$MAIL" | grep -q '재개' && tail -1 "$LOG" | awk -F'\t' '$2=="off"{f=1} END{exit !f}' && ! tail -1 "$LOG" | grep -q 'notify_failed=byz'; ck "r2 off 재실행 = 원장 기준 실패분만 재통지(released 파일 없어도)" $?
: > "$MAIL"; as off; [ "$rc" = 0 ] && [ ! -s "$MAIL" ] && echo "$out" | grep -q '이미 꺼짐'; ck "r2 실패분 없으면 off 재실행 통지 0" $?
IH2="$TMP/hooks"; export TMUX=fake
deny "byz-aa-master-claude#1" "$(mkbash "printf 'x\toff\n' >> /r/.fable-team/state/all-stop.log")"; ck "r2 가드: all-stop.log 덧붙이기 = deny" $?
deny "byz-aa-master-claude#1" "$(mkbash "python3 -c \"open('/r/.fable-team/state/all-stop.log','a').write('x')\"")"; ck "r2 가드: python 으로 all-stop.log 쓰기 = deny" $?
unset TMUX

# ── DA⑥ r3 → r4: «기록 없음» 추측 0 · 설치 init 줄 · 승계 = 명부 현역 행 ∧ 세션 생존 · 실제 판정기 연동 ──
as check; ck "r4 시작 = 원장 init(꺼짐) → check rc0" "$rc"
(cd "$REPO/.fable-team" && mv state state.r4 && mkdir state); as check
[ "$rc" = 1 ] && echo "$out" | grep -q '원장 없음'; ck "r4 DA 재현1 mv state x && mkdir state → check rc1 «원장 없음»" $?
nano; [ "$rc" = 1 ] && echo "$out" | grep -q '원장 없음'; ck "r4 빈 state 재생성 → nano-spawn REJECT" $?
perm device-acquire mic; [ "$rc" = 1 ] && echo "$out" | grep -q '원장 없음'; ck "r4 permit 이 빈 state 를 만들어도 device-acquire REJECT" $?
as init; [ "$rc" = 0 ] && tail -1 "$LOG" | awk -F'\t' '$2=="off" && $3=="install" && $4=="init"{f=1} END{exit !f}'; ck "r4 init = 원장 첫 줄 «off install init»" $?
as check; ck "r4 init 뒤 check rc0" "$rc"
cp "$LOG" "$TMP/log.init"; as init; [ "$rc" = 0 ] && cmp -s "$LOG" "$TMP/log.init" && echo "$out" | grep -q '그대로'; ck "r4 init 재실행 = 원장 그대로(멱등)" $?
(cd "$REPO/.fable-team" && mv state state.r4b && mkdir state); echo '{"since":1,"by":"x","reason":"r4"}' > "$AS"; as init
tail -1 "$LOG" | awk -F'\t' '$2=="on"{f=1} END{exit !f}'; ck "r4 상태 파일 있는데 원장 없음 → init 줄 on" $?
(cd "$REPO/.fable-team" && mv state state.r4c && mv state.r4 state); as check; ck "r4 원래 state 복원 → check rc0" "$rc"
as on "r4 승계"
export FAKE_ALIVE="r626-probe#0"
as check --succession 'r626-probe#0' 'r626-probe#1'; [ "$rc" = 1 ] && echo "$out" | grep -q '명부에도 현역 행으로 없음'; ck "r4 DA 재현2 명부 밖 tmux 이름 승계 = REJECT" $?
export FAKE_ALIVE="byz-aa-master-claude#1"
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#2'; ck "r4 명부 현역 행 ∧ 세션 생존 ∧ #N+1 = 통과" "$rc"
unset FAKE_ALIVE
# ── r1094: 재부팅 승계 — 부팅 시각이 정지 켠 시각보다 뒤면 «구 좌석 세션 없음» 이라도 통과 (정지 중 재부팅 뒤 100% 거절되던 길) ──
SEATA="$REPO/.fable-team/seats-aa.json"; OPEN_ROW='{"_label":"aa","_master":"byz-aa-master-claude#1","byz-aa-master-claude#1":{"role":"master"}}'
echo '{"since":1793000000,"by":"t","reason":"r1094"}' > "$AS"
export FT_BOOT_EPOCH=1793004000
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#2'
[ "$rc" = 0 ] && echo "$out" | grep -q '재부팅 승계'; ck "r1094 R1 재부팅 승계(부팅 > 정지 · 세션 없음 · 명부 현역 · #N+1) = 통과" $?
FT_BOOT_EPOCH=1792990000
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#2'
[ "$rc" = 1 ] && echo "$out" | grep -q '구 좌석 세션 없음'; ck "r1094 R2 재부팅 없음(부팅 < 정지 · 세션 없음) = REJECT «구 좌석 세션 없음»" $?
FT_BOOT_EPOCH=1793004000
echo '{"_label":"aa","_master":"byz-aa-master-claude#1","byz-aa-master-claude#1":{"role":"closed"}}' > "$SEATA"
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#2'
[ "$rc" = 1 ] && echo "$out" | grep -q '명부 행 닫힘 표시'; ck "r1094 R3 재부팅 꼴 + 명부 행 닫힘 = REJECT(지금과 같음)" $?
echo "$OPEN_ROW" > "$SEATA"
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#3'
[ "$rc" = 1 ] && echo "$out" | grep -q '#N+1 아님'; ck "r1094 R4 재부팅 꼴 + 새 이름 #N+2 = REJECT «#N+1 아님»" $?
export FAKE_ALIVE='byz-aa-master-claude#1'; unset FT_BOOT_EPOCH
as check --succession 'byz-aa-master-claude#1' 'byz-aa-master-claude#2'
[ "$rc" = 0 ] && echo "$out" | grep -q '구 좌석 세션 살아 있음'; ck "r1094 R5 세션 살아 있음 = 부팅 시각 없이 지금처럼 통과(생존 길 그대로)" $?
unset FAKE_ALIVE
CB="$TMP/copybin"; mkdir -p "$CB"; cp -R "$BIN"/. "$CB"/   # r686: 이름 골라 복사 0 — 새 lib(r672 swap·research) 가 생겨도 사본에 실재
. "$HERE/lib/bin_source_deps.sh"; out="$(missing_source_deps "$CB")"; rc=0; [ -z "$out" ]; ck "r686 사본 bin 의 같은 폴더 source 대상 전부 실재" $?
out="$(cd "$REPO" && bash "$CB/ft-nano-spawn.sh" "design/teams/aa/indices/대기/x.md" --dry-run 2>&1)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 전팀 정지 중(since'; ck "r4 연동: spawn 사본 bin + 진짜 ft-all-stop.sh · 켜짐 → REJECT" $?
as off
out="$(cd "$REPO" && bash "$CB/ft-nano-spawn.sh" "design/teams/aa/indices/대기/x.md" --dry-run 2>&1)"; rc=$?
! echo "$out" | grep -q '전팀 정지 중'; ck "r4 연동: 진짜 판정기 · 꺼짐 → 정지 거절 0" $?
export TMUX=fake
deny "byz-aa-master-claude#1" "$(mkbash 'bash /r/.fable-team/bin/ft-all-stop.sh init')"; ck "r4 가드: 좌석 init 직접 실행 = deny" $?
unset TMUX

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
