#!/usr/bin/env bash
# test_successor_open_open_cell_r2229.sh — r2229: 승계 개설 ⓐ-4 «앞 인계서:» 열린 칸 대조(ft-carry-check.py) + 자동 길 WARN(FT_CARRY_WARN_ONLY).
#   ① 앞 줄 없음 WARN 통과 · 못 읽음 · 절 없음 REJECT rc1 · 상대경로 = ROOT ② 353→354 꼴 #326195 사라짐 REJECT(기준판 = 통과 · Red)
#   ③ 닫음 «—» «-» · 열린 칸 이월 · 곁 키 · «DA r3» 키 0 · «: 이월» 줄 통과 · 빈 근거 REJECT ④ 실 인계서 354→355 «## 열린 칸» 사본 = 칸 5
#   ⑤ 자동 길 WARN 진행 · tmuxc 새 좌석 env 에 키 0 · team-boot B2 계속 · 부르는 줄에만(export 0) ⑥ 짝 사본(bin ↔ kit) cmp 0
#   변이 M1~M5(사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
# 격리: r1957 시험과 같은 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 앞 스텁) + 임시 리포 · 실 세션·실 mbox 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1; unset FT_CARRY_WARN_ONLY FT_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
KIT="$REPO/harness/kit/fable-team/bin"; SO="${FT_SO_PATH:-$KIT/ft-successor-open.sh}"   # FT_SO_PATH = 기준판(Red)
F="$T/fakebin"; lg="$T/calls.log"; R="$T/repo"; OLD="byz-t-tool-claude#1"; NEW="byz-t-repro-claude#2"
mkdir -p "$F" "$R/design/p"; git -C "$R" init -q; mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$F/$1"; chmod +x "$F/$1"; }
mkstub tmux 'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $* CW=${FT_CARRY_WARN_ONLY-unset}" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; printf "%s" "$2" > "$SENT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox 'exit 0'; : > "$F/mbox_doorbell.sh"; mkstub reach 'exit 0'; . "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"; SENSORS="$T/sensors/fake-sensors"
mkdir -p "$RES/design" "$R/.fable-team" "$T/live"
printf '# TEAMS\n\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | byz-t-master-claude | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{"%s":{"role":"master","model":"m"},"%s":{"role":"master","model":"m"}}\n' "$OLD" "$NEW" > "$RES/.fable-team/seats-t.json"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-claude | — |\n' > "$T/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n' > "$T/gov.md"
printf '%s\n' "$T/live" > "$R/.fable-team/LIVE_ROOT"; SOENV=(HOME="$T/home" PANE_CWD="$T/pane" PATH="$F:$PATH" LOG="$lg" OPENED="$T/opened" SENT="$T/sent.txt" SENSORS="$SENSORS" FT_RES_ROOT="$RES"
  FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=3 FT_SEND_VERIFIED="$F/send" FT_MBOX_SH="$F/mbox" FT_REACH_CHECK="$F/reach")
# 앞 인계서 픽스처(ROOT=$R 기준 상대경로) — 353 꼴: #326195 줄 · 곁 키 줄 · 키 없는 줄 · «DA r3» 만 있는 줄
printf '# 353\n\n## 열린 칸\n- 승계 진행: desk #326867 · 첫 일 = 지시 걷기 #326791\n- 연세라인 선택지 h = DA r3 HOLD → 내 결정 #326195 작은 고침 · knowledge arch PR 기다림\n  → 오면 착지\n- 선택지 DA r3 HOLD 만 남음\n- room: tester 자가 개설 기다림\n\n## 원장\n- 원장 #111111\n' > "$R/design/p/H353.md"
printf '# 352\n\n## 착지\n- 없음\n' > "$R/design/p/H352.md"
body() { printf '골 1\n골 2\n골 3\n본문 4행\n열린 칸 감시: 없음\n'; [ $# -gt 0 ] && printf '%s\n' "$@"; printf '본문 끝\n'; }
P='앞 인계서: design/p/H353.md'; KEEP='## 열린 칸'$'\n''- 승계 진행 desk #326867'$'\n''## 기타'   # 새 «## 열린 칸» 절은 «## 기타» 에서 끝(닫음 줄이 절 안에 섞이지 않게)
so_run() {  # so_run <개설도구> [env…] — 본문 = $T/b.txt · cwd = $T(ROOT 밖)
  local s="$1"; shift; rm -f "$lg" "$T/opened" "$T/sent.txt"; rm -rf "$R/.fable-team/state"; : > "$lg"
  (cd "$T" && export "${SOENV[@]}" "$@" && bash "$s" "$OLD" "$R" --name "$NEW" --agent claude --model m --body-file "$T/b.txt") > "$T/out" 2>&1; RC=$?
}
pass_c() {  # pass_c <이름> [도구] — 본문 = $T/b.txt
  so_run "${2:-$SO}"; { [ "$RC" = 0 ] && grep -q '^tmuxc open' "$lg" && grep -q '^send' "$lg"; } && ok "$1 통과 rc0 · 열기·send" || bad "$1" "rc=$RC out=$(cat "$T/out")"
}
rej_c() {  # rej_c <이름> <REJECT 글> [도구]
  so_run "${3:-$SO}"; { [ "$RC" = 1 ] && grep -qF -- "$2" "$T/out" && ! grep -q '^tmuxc' "$lg" && ! grep -q '^send' "$lg"; } \
    && ok "$1 REJECT rc1 «$2» · 열기·send 0" || bad "$1" "rc=$RC log=$(tr '\n' ' ' < "$lg") out=$(cat "$T/out")"
}
# ── ①
body > "$T/b.txt"; pass_c "① 앞 줄 없음"; grep -q 'WARN 앞 인계서 줄 없음 · 열린 칸 대조 0' "$T/out" && ok "① WARN 1줄" || bad "① WARN" "$(cat "$T/out")"
body '앞 인계서: design/p/없음.md' > "$T/b.txt"; rej_c "① 못 읽음" '앞 인계서 판정 불가 경로 못 읽음'
body '앞 인계서: design/p/H352.md' > "$T/b.txt"; rej_c "① 절 없음" '앞 인계서 판정 불가 «## 열린 칸» 절 없음'
# ── ② (기준판 = 통과 → FAIL = Red)
c2() { body "$P" "$KEEP" > "$T/b.txt"; rej_c "② 353→354 꼴" '열린 칸 말없이 사라짐 1(#326195)' "${1:-$SO}"; }; c2
# ── ③
c3a() { body "$P" "$KEEP" '닫음: #326195 — knowledge PR 착지 9xxx' > "$T/b.txt"; pass_c "③a 닫음 «—» · 상대경로 ROOT · 곁 키(#326791 안 옮김) · DA r3 키 0" "${1:-$SO}"; }; c3a
grep -q 'OK 열린 칸 대조 칸 2 · 사라짐 0' "$T/out" && ok "③ 키 있는 칸 = 2(DA r3 · 글 줄 = 대조 밖)" || bad "③ 칸 수" "$(cat "$T/out")"
body "$P" "$KEEP" '- 닫음: #326195 - knowledge PR 착지 9xxx' > "$T/b.txt"; pass_c "③b 닫음 «-»"
body "$P" '## 열린 칸' '- 승계 진행 desk #326867' '- 연세라인 #326195 이월' '## 기타' > "$T/b.txt"; pass_c "③c 새 «## 열린 칸» 에 키 다시"
c3f() { body "$P" '## 앞 인계서 열린 칸 이월·닫음' '- 승계 #326867 #326195: 이월(정지 중)' > "$T/b.txt"; pass_c "③f «: 이월» 줄(362-stop 꼴)" "${1:-$SO}"; }; c3f
c3g() { body "$P" "$KEEP" '닫음: #326195 —' > "$T/b.txt"; rej_c "③g 빈 근거" '열린 칸 말없이 사라짐 1(#326195)' "${1:-$SO}"; }; c3g
# ── ④ 실 인계서 사본 = state/team-main/planner HANDOVER-353-to-354 · 354-to-355 의 «## 열린 칸» 절 그대로(355 전문에 «닫음:» · «: 이월» 줄 0 · 11-18 grep)
cat > "$R/design/p/R353.md" <<'EOF'
## 열린 칸
- 승계 진행: planner arch #40 → #41(desk #326867 · 첫 일 = AGENTS.md 은퇴 도구 지시 걷기 #326791 · 닫는 값 AGENTS.md 만 · CLAUDE.md :195 금지문 유지 · 판정 4399) · v65 master #299 → #300(desk #326885)
- 연세라인 선택지 h = DA r3 HOLD → 내 결정 #326195 작은 고침 · knowledge arch PR 기다림 → 오면 착지
- v65 골 6: ⑥ 닫힘 · ⑦ r2 ll 통과 · rr 재회차 발주(코드 0) · 새 결함 후보 2(백엔드)는 rr 재현 때만 카드(#326857)
- ops: 나노 4석(colima · loom-node-r2 · tour-clinic · disk-300g 읽기만 · 지우기 HIL) · PR 9022 상태 줄 DA#15 뒤 [합치기] 예정 · 1.x 카드 이동 = card_stage --da 길(harness #326733)
- harness: arch #437(한 명령 부팅 시범 OK · 요청 7 · 창 44683) · 인계서 5KB 카드 · r2174 게이트 거짓 양성 · record-notify rc=99 · 아카이브 동사 · keeper choose 무음·거짓 완성 카드감
- room: tester #29 → #30 자가 개설 기다림(10분 넘으면 desk 경유)
- aifp #24: 사용량 포커싱 완성(숫자 목표 밖 · 조율 86%)

## 원장
EOF
cat > "$T/r355.md" <<'EOF'
앞 인계서: design/p/R353.md
## 열린 칸
- v65: K2 T9 두 기기 press r2 → tester#30 진행 중(세트 a0434c804b) · RESULT 오면 착지 → planner arch#42 판정 · v65 DA 칸 빔(4404 로 닫음)
- ops: 카드 아카이브 실사건(ops-worktrees-stale-close 대체 카드 PR → DA 닫힘 절 → card_archive --to) · 9025·9029 오빠 대기 · 다음 지우기 카드 반례 2(lsof 오류 rc · 남은 범위 줄 결과 PR 안)
- harness: master #319 · arch #442 · 거짓 완성 카드 → 보드 뉴스 본문 상한(3509B > 3500B) 카드 · analyst 나노 = 1회성 미등록 → 닫기는 desk 수동
- desk #327627: chatbot 팀장 빔 → 대기 카드 수 답 오면 개설 판단
- 원장 «골 진행» 표 고칠 때 «메인 골» 표 상태 칸도 같은 PR(ft-goal-table 은 메인 골 표만 읽음)

## 원장
EOF
o4="$(python3 "$(dirname -- "$SO")/ft-carry-check.py" "$T/r355.md" --root "$R" 2>&1)"; r4=$?
{ [ "$r4" = 1 ] && printf '%s' "$o4" | grep -qF '열린 칸 말없이 사라짐 5(#326867 #326195 #326857 PR 9022 r2174)'; } && ok "④ 실 354→355 = 칸 5(carry2 수와 같음)" || bad "④" "rc=$r4 $o4"
# ── ⑤ 자동 길
c5() { body "$P" "$KEEP" > "$T/b.txt"; so_run "${1:-$SO}" FT_CARRY_WARN_ONLY=1
  { [ "$RC" = 0 ] && grep -q 'WARN 자동 길(FT_CARRY_WARN_ONLY=1) 진행 — 열린 칸 말없이 사라짐 1(#326195)' "$T/out" && grep -q '^tmuxc open .* CW=unset$' "$lg"; } \
    && ok "⑤ WARN_ONLY=1 + ② 픽스처 = WARN 진행 rc0 · 새 좌석 env 키 0(env -u)" || bad "⑤" "rc=$RC log=$(tr '\n' ' ' < "$lg") out=$(cat "$T/out")"; }; c5
body "$P" "$KEEP" > "$T/b.txt"; rej_c "⑤ env 없는 사람 길 = REJECT" '열린 칸 말없이 사라짐 1(#326195)'
# team-boot B2: 감싸개 = 실제 개설 도구(WSO) · 받은 본문 + «앞 인계서:» 줄 · 사라진 칸 1(#326195)
{ echo '#!/usr/bin/env bash'; printf 'cd %q; rm -rf %q %q %q\n' "$T" "$T/opened" "$T/sent.txt" "$R/.fable-team/state"
  printf 'while [ $# -gt 0 ]; do [ "$1" = --body-file ] && { cat "$2"; printf "%%s\\n" %q %q; } > %q; shift; done\n' "$P" "$KEEP" "$T/b.txt"
  printf 'echo "WRAP CW=${FT_CARRY_WARN_ONLY-unset}" > %q\nenv' "$T/wrap.env"; printf ' %q' "${SOENV[@]}"; printf ' bash "$WSO" %q %q --name %q --agent claude --model m --body-file %q > %q 2>&1; rc=$?; cat %q; exit $rc\n' "$OLD" "$R" "$NEW" "$T/b.txt" "$T/wrap.out" "$T/wrap.out"; } > "$T/so_wrap.sh"
B="$T/boot"; mkdir -p "$B/design/teams/t1/indices/진행" "$B/.fable-team/comm" "$B/.worktrees/wtt1" "$T/la"; git -C "$B" init -q -b main
printf '{"_master":"byz-t1-master-claude#4","_cards":"design/teams/t1/indices","_cards_wt":"wtt1","byz-t1-master-claude#4":{"role":"master","agent":"claude","model":"m"}}\n' > "$B/.fable-team/seats-t1.json"
echo '{"_master":"byz-planner-master-pi#245"}' > "$B/.fable-team/seats-planner.json"; mkstub ok0 'exit 0'; mkstub tls '[ "$1" = ls ] || exit 0'
printf '# CLOSEOUT\n\n## 골 원문\n\n골 1\n골 2\n골 3\n\n' > "$B/design/teams/t1/CLOSEOUT-t1-20261114.md"
git -C "$B" add -A; git -C "$B" -c user.name=t -c user.email=t@t commit -qm c; git -C "$B" update-ref refs/remotes/origin/main HEAD
boot() {  # boot <개설도구> — B2 1회
  rm -rf "$B/.fable-team/state" "$T/wrap.out"; : > "$lg"
  BOUT="$(cd "$B" && WSO="$1" FT_REPO_ROOT="$B" FT_SUCCESSOR_OPEN="$T/so_wrap.sh" FT_MBOX_SH="$F/ok0" FT_NANO_SPAWN="$F/ok0" FT_ALL_STOP="$F/ok0" FT_TMUX="$F/tls" \
    FT_LAUNCHAGENTS="$T/la" FT_BOOT_ME='byz-t1-nano-boot#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245' bash "$REPO/harness/bin/ft-team-boot.sh" t1 2>&1)"; BRC=$?
}
c5b() { boot "${1:-$SO}"
  { printf '%s' "$BOUT" | grep -q 'B2 .* rc=0' && ! printf '%s' "$BOUT" | grep -q '팀장 미도달' && grep -q 'WARN 자동 길' "$T/wrap.out" && grep -qx 'WRAP CW=1' "$T/wrap.env" && grep -q '^tmuxc open .* CW=unset$' "$lg"; } \
    && ok "⑤ team-boot B2 = 대조 실패 WARN 뒤 부팅 계속 · 부르는 줄 env=1 · 새 좌석 env 키 0" || bad "⑤ B2" "brc=$BRC wrap=$(cat "$T/wrap.out" 2>/dev/null) out=$BOUT"; }; c5b
for f in ft-team-boot.sh ft_model_swap.py ft-successor-open.sh; do ! grep -qE 'export FT_CARRY_WARN_ONLY|os\.environ\["FT_CARRY_WARN_ONLY"\] *=' "$KIT/$f" && ok "⑤ $f export 0" || bad "⑤ $f export 있음"; done
grep -q 'FT_CARRY_WARN_ONLY=1 bash "$SO" "${so_args\[@\]}"' "$KIT/ft-team-boot.sh" && ok "⑤ team-boot B2 부르는 줄에만 env" || bad "⑤ team-boot 부르는 줄"
grep -q '"--body-file", str(bf)\], env={\*\*os.environ, "FT_CARRY_WARN_ONLY": "1"}' "$KIT/ft_model_swap.py" && ok "⑤ model_swap 부르는 줄에만 env" || bad "⑤ model_swap 부르는 줄"
# ── ⑥ 짝 사본
for f in ft-successor-open.sh ft-team-boot.sh ft_model_swap.py ft-carry-check.py; do cmp -s "$KIT/$f" "$REPO/harness/bin/$f" && ok "⑥ 짝 사본 $f cmp 0" || bad "⑥ 짝 사본 $f 다름"; done
# ── 변이 M1~M5 (사본에서만 · 변이마다 원본 같은 사례 1회 더)
mut() {  # mut <이름> <파일> <old> <new> → $MX/ft-successor-open.sh
  MX="$T/mx-$1"; mkdir -p "$MX"; cp -R "$KIT/." "$MX/"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); assert sys.argv[2] in s, sys.argv[2]; p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))' "$MX/$2" "$3" "$4" || bad "$1 치환 자리 없음" "$3"
}
expect_fail() {  # expect_fail <이름> <사례 함수> — 변이 사본 = FAIL · 원본 = PASS
  local before=$fail; "$2" "$MX/ft-successor-open.sh" > "$T/mout"
  if [ "$fail" -gt "$before" ]; then fail=$before; "$2" > "$T/oout"; [ "$fail" = "$before" ] && ok "$1 잡힘($(grep -m1 -o '^FAIL [^ ]*' "$T/mout")) · 원본 같은 사례 PASS" || bad "$1 원본 대조 실패" "$(cat "$T/oout")"
  else bad "$1 안 잡힘" "$(cat "$T/mout")"; fi
}
GATE='if m and len(m.group(2).strip()) >= MIN_WHY:'
mut M1 ft-carry-check.py "$GATE" 'if False:'; expect_fail M1 c3a
mut M2 ft-carry-check.py 'r"#(\d{6})|' 'r"(?!)(\d{6})|'; expect_fail M2 c2
mut M3 ft-carry-check.py "$GATE" 'if m:'; expect_fail M3 c3g
mut M4 ft-successor-open.sh '[ "${FT_CARRY_WARN_ONLY:-}" = 1 ] || { printf' '{ printf'; expect_fail M4 c5b
mut M5 ft-carry-check.py 'm = CARRY.search(line)' 'm = None'; expect_fail M5 c3f
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
