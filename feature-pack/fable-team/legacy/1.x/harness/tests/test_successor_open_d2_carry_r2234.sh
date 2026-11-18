#!/usr/bin/env bash
# test_successor_open_d2_carry_r2234.sh — r2234: planner master · desk 승계 개설 ⓐ-4 «--d2-carry»(ft-carry-check.py)
#   오빠 질문(Slack ts 키) 이월 줄 · «오빠 답» 절 줄 = ts 1개 + «D2 n번 — <왜 사람>» · 앞·새 인계서 줄 필수 · 열린 칸 절 없음 = WARN.
#   반례 ①~⑪(실 글 사본 4 = fixtures/r2234) · 짝 사본 cmp 0 · 변이 M1~M7(사본에서만 · 변이마다 원본 같은 사례 1회 더)
#   기준판 Red = FT_KIT_DIR=<r2229 착지 kit 사본> → ① 이 WARN 통과 = FAIL
#   ⑪ 의 r2229 시험(test_successor_open_open_cell_r2229.sh) 결과 수 대조는 따로 돌린다(시험 1개 70초 상한 · 중첩 0)
# 격리: r2229 시험과 같은 가짜 tmux·tmuxc·pgrep·send·mbox·reach + 임시 리포 · 실 세션·실 mbox 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1; unset FT_CARRY_WARN_ONLY FT_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; FX="$HERE/fixtures/r2234"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
step() { echo "STEP $1 ${SECONDS}s"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
KIT="$REPO/harness/kit/fable-team/bin"; KD="${FT_KIT_DIR:-$KIT}"   # FT_KIT_DIR = 기준판(Red)
F="$T/fakebin"; lg="$T/calls.log"; R="$T/repo"
DESK0="byz-planner-desk-pi#204"; DESK="byz-planner-desk-pi#205"; MAS0="byz-planner-master-pi#363"; MAS="byz-planner-master-pi#364"
ARC0="byz-planner-arch-pi#57"; ARC="byz-planner-arch-pi#58"
mkdir -p "$F" "$R/design/p"; git -C "$R" init -q; mkdir -p "$R/design/teams/planner"; ASK='선택지마다 D2 3문 · «예» 가 하나라도 있으면 오빠께'
printf -- '- **desk 좌석**: desk 는 인터뷰·응대·요청 정리만(코드·커밋 0 · 팀 직접 발주 0 · 정리한 요청은 master 에 1통)\n- **desk 묻는 기준** %s\n' "$ASK" > "$R/design/teams/planner/GUIDE-planner.md"   # desk 안내서 단계 = 실 #332594 2줄 구절 · r2233 묻는 기준 줄
git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m r0; mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$F/$1"; chmod +x "$F/$1"; }
mkstub tmux 'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $* CW=${FT_CARRY_WARN_ONLY-unset}" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; printf "%s" "$2" > "$SENT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox 'exit 0'; : > "$F/mbox_doorbell.sh"; mkstub reach 'exit 0'; . "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"; SENSORS="$T/sensors/fake-sensors"
mkdir -p "$RES/design" "$R/.fable-team" "$T/live"
printf '# TEAMS\n\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/teams/planner/` | byz-planner-master-pi | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{"%s":{"role":"desk","model":"m"},"%s":{"role":"desk","model":"m"},"%s":{"role":"master","model":"m"},"%s":{"role":"master","model":"m"},"%s":{"role":"arch","model":"m"},"%s":{"role":"arch","model":"m"}}\n' \
  "$DESK0" "$DESK" "$MAS0" "$MAS" "$ARC0" "$ARC" > "$RES/.fable-team/seats-planner.json"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| planner | byz-planner-master-pi | — |\n' > "$T/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n<!-- S11-DESK-BEGIN -->\ndesk 는 정리만.\n<!-- S11-DESK-END -->\n' > "$T/gov.md"
printf '%s\n' "$T/live" > "$R/.fable-team/LIVE_ROOT"; SOENV=(HOME="$T/home" PANE_CWD="$T/pane" PATH="$F:$PATH" LOG="$lg" OPENED="$T/opened" SENT="$T/sent.txt" SENSORS="$SENSORS" FT_RES_ROOT="$RES"
  FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=3 FT_SEND_VERIFIED="$F/send" FT_MBOX_SH="$F/mbox" FT_REACH_CHECK="$F/reach" FT_SO_MAIN_REF=HEAD FT_GUIDE_REF=HEAD FT_GUIDE_PATH=design/teams/planner/GUIDE-planner.md)   # r756 desk·planner 자리 검사 = 시험 리포 HEAD
# 실 글 사본(ROOT=$R 기준 상대경로): H363 = HANDOVER-362-to-363 · D204 = handover-desk203-to-204-open · ask6 = H363 36~44 «## 오빠 답 대기» 표 6행
cp "$FX/HANDOVER-362-to-363-20261118.md" "$R/design/p/H363.md"; cp "$FX/handover-desk203-to-204-open.md" "$R/design/p/D204.md"
sed -n 36,44p "$FX/HANDOVER-362-to-363-20261118.md" > "$R/design/p/ask6.md"; sed -n 18p "$FX/HANDOVER-362-stop-20261118.md" > "$R/design/p/stop18.md"
printf '# 새 인계서\n\n## 재개 중\n- 연세 선택지 h desk 실행 #332550\n' > "$R/design/p/N0.md"
B1="$FX/body-332594.txt"; P363='앞 인계서: design/p/H363.md'
b1() { cat "$B1"; echo; echo "desk 묻는 기준: $ASK"; [ $# -gt 0 ] && printf '%s\n' "$@"; return 0; }   # 실 #332594 본문(9줄 · 끝 줄바꿈 0) + 10줄 r2233 묻는 기준 + 덧줄
so_run() {  # so_run <kit 폴더> <구> <후계> [env…] — 본문 = $T/b.txt · cwd = $T(ROOT 밖)
  local d="$1" o="$2" n="$3"; shift 3; rm -f "$lg" "$T/opened" "$T/sent.txt"; rm -rf "$R/.fable-team/state"; : > "$lg"
  (cd "$T" && export "${SOENV[@]}" "$@" && bash "$d/ft-successor-open.sh" "$o" "$R" --name "$n" --agent pi --model m --body-file "$T/b.txt") > "$T/out" 2>&1; RC=$?
}
rej_so() {  # rej_so <이름> <REJECT 글> <구> <후계> [kit] — 열기·send 0
  so_run "${5:-$KD}" "$3" "$4"; { [ "$RC" = 1 ] && grep -qF -- "$2" "$T/out" && ! grep -q '^tmuxc' "$lg" && ! grep -q '^send' "$lg"; } \
    && ok "$1 REJECT rc1 «$2» · 열기·send 0" || bad "$1" "rc=$RC out=$(cat "$T/out")"
}
pass_so() {  # pass_so <이름> <WARN 글> <구> <후계> [kit] [env…] — 열기·send · ⓐ-4 줄 1개
  local n="$1" w="$2" o="$3" s="$4" d="${5:-$KD}"; shift 5 2>/dev/null || shift $#; so_run "$d" "$o" "$s" "$@"
  { [ "$RC" = 0 ] && grep -qF -- "$w" "$T/out" && grep -q '^tmuxc open' "$lg" && grep -q '^send' "$lg"; } \
    && ok "$n 통과 rc0 «${w}» · 열기·send" || bad "$n" "rc=$RC out=$(cat "$T/out")"
}
cc() {  # cc <kit 폴더> <새 인계서 파일 이름> — 본문 = 앞(H363) · 새 줄 → ft-carry-check.py --d2-carry 직접
  printf '골 1\n%s\n새 인계서: design/p/%s\n' "$P363" "$2" > "$T/cb.txt"
  CO="$(python3 "$1/ft-carry-check.py" "$T/cb.txt" --root "$R" --d2-carry 2>&1)"; CR=$?
}
rej_cc() { cc "${4:-$KD}" "$2"; { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -qF -- "$3"; } && ok "$1 REJECT «$3»" || bad "$1" "rc=$CR $CO"; }
pass_cc() { cc "${3:-$KD}" "$2"; [ "$CR" = 0 ] && ok "$1 통과 rc0" || bad "$1" "rc=$CR $CO"; }
nf() { printf '%s\n' "${@:2}" > "$R/design/p/$1"; }
step 준비
# ── ① 실 #332594 + desk 후계 = REJECT(기준판 = WARN 통과 → FAIL = Red)
c1() { b1 > "$T/b.txt"; rej_so "① 실 #332594 desk" '앞 인계서 줄 없음 — planner master' "$DESK0" "$DESK" "${1:-}"; }; c1
# ── ② 새 줄 없음 · 못 읽음
b1 "$P363" > "$T/b.txt"; rej_so "② 새 줄 없음" 'REJECT 새 인계서 줄 없음' "$DESK0" "$DESK"
b1 "$P363" '새 인계서: design/p/없음.md' > "$T/b.txt"; rej_so "② 새 못 읽음" 'REJECT 새 인계서 판정 불가 경로 못 읽음' "$DESK0" "$DESK"
# ── ③ 앞 = 실 362-to-363 · 실 desk203-to-204-open(둘 다 «## 열린 칸» 절 0) · 새 = ts 키 줄 0 · 절 0 = WARN rc0(master 후계 · 옵션 넘김)
c3() { b1 "$P363" '새 인계서: design/p/N0.md' > "$T/b.txt"; pass_so "③ 앞 362-to-363 master" 'WARN 열린 칸 절 없음 — 대조 0칸' "$MAS0" "$MAS" "${1:-$KD}"; }; c3
b1 '앞 인계서: design/p/D204.md' '새 인계서: design/p/N0.md' > "$T/b.txt"; pass_so "③ 앞 desk203-to-204-open master" 'WARN 열린 칸 절 없음 — 대조 0칸' "$MAS0" "$MAS"
step e2e
# ── ④~⑩ 판정 도구 직접(--d2-carry)
c4() { rej_cc "④ 새 = 실 desk203-to-204-open" D204.md 'REJECT ts 키는 한 줄에 하나(13)' "${1:-}"; }; c4
c5() { rej_cc "⑤ 새 «## 오빠 답 대기» = 실 362-to-363 표 6행" ask6.md 'D2 재분류 없는 오빠 질문 6(1794933737.222419 ' "${1:-}"; }; c5
c6() { rej_cc "⑥ 실 362-stop 18줄(키 자리 ts 1 · 사유 링크 ts 1)" stop18.md 'D2 재분류 없는 오빠 질문 1(1794924929.802389)' "${1:-}"; }; c6
grep -q '한 줄에 하나' <<<"$CO" && bad "⑥ 한 줄에 하나 거짓" "$CO" || ok "⑥ «한 줄에 하나» 0"
nf c7.md '- 1794933737.222419: 이월(오빠 «네» 대기)'
c7() { rej_cc "⑦ D2 칸 없음" c7.md 'D2 재분류 없는 오빠 질문 1(1794933737.222419)' "${1:-}"; }; c7
nf c8a.md '- room 1794933737.222419: 이월(D2 1번 — worktree 25곳 삭제 · 비가역)'; pass_cc "⑧ D2 1번" c8a.md
nf c8b.md '- v65 1794951124.303049: 이월(D2 off — 자율 OFF 라 오빠께 묻기)'; pass_cc "⑧ D2 off" c8b.md
nf c8c.md '## 오빠 답 대기' '| 키 | 일 | 분류 |' '|---|---|---|' '| 1794965055.660189 | GPU 2대 | D2 2번 — 새 비용 · 승인 골 밖 |'; pass_cc "⑧ 표 행 D2 2번" c8c.md
nf c9a.md '- 1794933737.222419: 이월(D2 1번 — 가나다라마바사아자)'
c9() { rej_cc "⑨ 왜 사람 9자" c9a.md 'D2 재분류 없는 오빠 질문 1(1794933737.222419)' "${1:-}"; }; c9
nf c9b.md '- 1794933737.222419: 이월(D2 1번 — 가나다라마바사아자차)'; pass_cc "⑨ 왜 사람 10자 경계" c9b.md
nf c9c.md '- 1794933737.222419: 이월(D2 4번 — worktree 25곳 삭제 · 비가역)'; rej_cc "⑨ D2 4번" c9c.md 'D2 재분류 없는 오빠 질문 1(1794933737.222419)'
nf c10.md '- 닫음: 1794933737.222419 — desk 고름 D3 1단 #332674' '## 오빠 답 대기' '| 키 | 일 | 다음 손 |' '|---|---|---|' '| 1794933737.222419 | room 러너 카드 2장 «네» | room#60 GO |'
pass_cc "⑩ 닫음 + 같은 ts 오빠 답 표 행 남음" c10.md
step 직접
# ── ⑪ 불변: planner arch = r2229 WARN 그대로 · 자동 길 desk = WARN 1줄 진행 · r2229 시험 결과 수 기준판과 같음(PASS 29)
b1 > "$T/b.txt"; pass_so "⑪ arch + ① 본문 = r2229 WARN" 'WARN 앞 인계서 줄 없음 · 열린 칸 대조 0' "$ARC0" "$ARC"
grep -q 'D2\|새 인계서' "$T/out" && bad "⑪ arch 에 d2 판정" "$(cat "$T/out")" || ok "⑪ arch d2 판정 0"
so_run "$KD" "$DESK0" "$DESK" FT_CARRY_WARN_ONLY=1
{ [ "$RC" = 0 ] && grep -c 'WARN 자동 길(FT_CARRY_WARN_ONLY=1) 진행 — 앞 인계서 줄 없음' "$T/out" | grep -qx 1 && grep -q '^tmuxc open' "$lg" && grep -q '^send' "$lg"; } \
  && ok "⑪ WARN_ONLY=1 + ① desk = WARN 1줄 진행 rc0 · 열기·send" || bad "⑪ WARN_ONLY" "rc=$RC out=$(cat "$T/out")"
grep -q '^D2C="".*\*-planner-master-\*|\*-planner-desk-\*) D2C="--d2-carry"' "$KIT/ft-successor-open.sh" && ok "⑪ 옵션 넘김 1줄(planner master · desk 만)" || bad "⑪ 옵션 넘김 줄"
step 불변
# ── 짝 사본
for f in ft-successor-open.sh ft-carry-check.py; do cmp -s "$KIT/$f" "$REPO/harness/bin/$f" && ok "짝 사본 $f cmp 0" || bad "짝 사본 $f 다름"; done
# ── 변이 M1~M7 (사본에서만 · 변이마다 원본 같은 사례 1회 더)
mut() {  # mut <이름> <old> <new> → $MX = kit 사본(ft-carry-check.py 1곳 치환)
  MX="$T/mx-$1"; mkdir -p "$MX"; cp -R "$KIT/." "$MX/"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); assert s.count(sys.argv[2]) == 1, sys.argv[2]; p.write_text(s.replace(sys.argv[2], sys.argv[3]))' "$MX/ft-carry-check.py" "$2" "$3" || bad "$1 치환 자리 없음" "$2"
}
expect_fail() {  # expect_fail <이름> <사례 함수> — 변이 사본 = FAIL · 원본 = PASS
  local before=$fail; "$2" "$MX" > "$T/mout"
  if [ "$fail" -gt "$before" ]; then fail=$before; "$2" > "$T/oout"; [ "$fail" = "$before" ] && ok "$1 잡힘($(grep -m1 -o '^FAIL [^ ]*' "$T/mout")) · 원본 같은 사례 PASS" || bad "$1 원본 대조 실패" "$(cat "$T/oout")"
  else bad "$1 안 잡힘" "$(cat "$T/mout")"; fi
}
WHY='if not (m and len(m.group(1).strip()) >= MIN_WHY):'
mut M1 'if not m and d2:' 'if False:'; expect_fail M1 c1
mut M2 'if not sec and d2:' 'if False:'; expect_fail M2 c3
mut M3 'ask = "오빠 답" in line' 'ask = False'; expect_fail M3 c5
mut M4 'if len(ts) > 1:' 'if False:'; expect_fail M4 c4
mut M5 'ts = TS.findall(key)' 'ts = TS.findall(key + rest)'; expect_fail M5 c6
mut M6 "$WHY" 'if False:'; expect_fail M6 c7
mut M7 "$WHY" 'if not m:'; expect_fail M7 c9
step 변이
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
