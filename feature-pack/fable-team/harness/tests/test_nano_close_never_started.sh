#!/usr/bin/env bash
# test_nano_close_never_started.sh — r506: ft-nano-close.sh --never-started "<사유>" (발주를 한 번도 처리하지 못한 나노 닫기 · ①②⑥ 면제 · «한 일 0» 4값)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(projects 폴더) + 임시 우편함 + 실제 cherry 게이트만 쓴다 — 실제 리포·seats·tmux·opencode.db 는 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 4값 0 → CLOSED never-started · kill · 정리 계획 · 브랜치 보존 ⓑ assistant 턴 1 → REJECT ⓒ base 위 커밋 1 → REJECT ⓓ 미커밋 1(노이즈 제외) → REJECT
#    ⓔ 보낸 쪽지 1 → REJECT · base 못 정함 → REJECT(확인 못 함) · usage 2 · 인자 없으면 불변 · opencode/그 밖 agent · 600/300·외부 호출·GIT_* 0 · 키트 짝 cmp0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== 키트 2곳 같은 바이트 + bash -n"
for f in ft-nano-close.sh ft-nano-never-started-check.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

mkdir -p "$T/bin" "$T/fake" "$T/home"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "oc-reap $1 left=0 rc=0"\n' > "$T/bin/ft-opencode-reap.sh"   # r286 회수 = 스텁(opencode 좌석 닫기 · 실기계 프로세스 0)
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-never-started-check.sh" "$SRC/ft-landed-check.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$T/bin/"   # r842: 단계 판정(ft_card_stage_ref) = ft-team-lib.sh 필수(없으면 ERROR + REJECT)
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in *pane_current_path*)   # 검사기 후계 판정(r506 r2) — 실패 표식 · 경로 표 · 없으면 아래 공통
      [ ! -e "$FAKE_FAIL" ] || { echo "error connecting to /tmp/fake (Permission denied)"; exit 1; }
      [ ! -s "$FAKE_PATHS" ] || { cat "$FAKE_PATHS"; exit 0; };; esac
    if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git init -q --bare "$T/origin.git"; git -C "$REPO" remote add origin "$T/origin.git"; git -C "$REPO" push -q origin HEAD:main   # r842 픽스처: 원격 추적 ref 를 두면 닫기가 그 ref 하나만 fetch 한다(R22) — 원격도 실재해야 한다   # r842: 카드 단계 ref 실재(없으면 단계 판정 실패 = ERROR + REJECT) · ref 에 카드 없음 = ABSENT → 지금 규칙
BASE="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm"
SEAT='byz-planner-nano-ns#0'; BR='nano/ns'; NW="$REPO/.worktrees/v65-ns"
CARD_REL='design/planner/indices/진행/ns.md'; CARD="$REPO/$CARD_REL"; REASON='발주 처리 전 정본 범위 변경'
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
LEDGER="$T/ledger.md"; PROJ="$T/home/.claude/projects/$(printf '%s' "$NW" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"

run() { ( cd "$REPO" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_OPENCODE_DB="$T/oc.db" FT_OPENCODE_DB_TIMEOUT=1 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_PATHS="$T/panes-path" FAKE_FAIL="$T/tmux-fail" "$@" 2>&1 ); }
setup() {  # «한 일 0» 상태로 리셋: 세션 없음 · HEAD == base · 미커밋 0 · jsonl 0 · 좌석 발신 0 · 카드 base_sha
  git -C "$NW" reset -q --hard "$BASE"; git -C "$NW" clean -qfd; git -C "$REPO" branch -q -f "$BR" "$BASE" 2>/dev/null
  printf '{"%s":{"role":"nano","agent":"%s","index":"%s"}}\n' "$SEAT" "${1:-claude}" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  printf '{"branch":"%s","base":"origin/main","base_sha":"%s"}\n' "$BR" "${BASE:0:10}" > "$NW/.worktree-info.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -rf "$T/wtclean" "$PROJ" "$T/oc.db"
  printf '{"seq": 1, "from": "byz-planner-master-claude#1", "to": "%s", "body": "[발주]"}\n' "$SEAT" > "$T/comm/mailbox.log.jsonl"
  printf '# 인덱스: ns\n## 상태\n- base_sha: %s (spawn)\n- 2026-10-20 진행\n' "$BASE" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 FT_NEVER_MAIN_REF=main bash "$T/bin/ft-nano-close.sh" "$SEAT" "$@"; }
CHK() { run bash "$T/bin/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW" --branch "$BR" --comm "$T/comm" "$@"; }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
}
reject() {  # reject <이름> <기대 문구> — close --never-started 가 rc1 + 문구 + 변경 0
  local out rc; out="$(close --never-started "$REASON")"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "$2" "$1 → REJECT «$2»" || bad "$1 — rc=$rc ← ${out:0:600}"
  hasnt "$out" "CLOSED" "  └ CLOSED 0"; untouched "$1"
}
jsonl() {  # jsonl <model> — 좌석명 레코드 + assistant 1줄
  mkdir -p "$PROJ"
  printf '{"type":"agent-name","agentName":"%s"}\n{"type":"user","message":{"role":"user"}}\n{"type":"assistant","message":{"model":"%s","role":"assistant"}}\n' "$SEAT" "$1" > "$PROJ/s1.jsonl"
}

echo "== ⓐ 4값 0 · 세션 살아 있음 → CLOSED never-started «사유» · kill · 정리 계획 · 브랜치 보존"
setup; printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT never-started «${REASON}» (명부 삭제 · 원장 append)" "ⓐ rc=0 · CLOSED <좌석> never-started «<사유>»" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "NEVER-STARTED ok turns=0 commits=0 dirty=0 sent=0" "  └ ⑥ 자리 = 한 일 0 검사 통과 줄"
hasnt "$out" "①결과" "  └ ① 면제"; hasnt "$out" "②" "  └ ② 면제"; hasnt "$out" "증거 줄" "  └ ⑥ 증거 줄 면제"
has "$out" "KILLED $SEAT" "  └ 세션 kill(표준승인 경로)"
has "$(cat "$T/tlog")" "kill-session" "  └ tmux kill-session 호출"
[ -f "$T/wtclean/$SEAT.sh" ] && ok "  └ 워크트리 정리 계획 생성(기존 경로)" || bad "  └ 정리 계획 없음"
has "$(cat "$LEDGER")" "never-started «${REASON}»" "  └ 닫힘 원장 행 꼬리 never-started «<사유>»"
has "$(cat "$LEDGER")" "①결과 \`(never-started · 산출 0)\` ②회수 seq -" "  └ 원장 ①② 칸 = 면제 표기"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제" || bad "명부에 좌석 남음"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 실재(삭제 0)" || bad "브랜치 삭제됨"

echo "== ⓐ 세션 없음 → CLOSED-ABSENT never-started"
setup; out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT never-started «${REASON}»" "ⓐ 세션 없음 → CLOSED-ABSENT never-started" || bad "ⓐ' rc=$rc ← ${out:0:600}"

echo "== ⓑ 대화 기록에 assistant 턴 1 → REJECT · <synthetic> 만이면 턴 0"
setup; jsonl claude-opus-5-5; reject "ⓑ 턴 1" "never-started: 대화 기록에 턴 1"
setup; jsonl '<synthetic>'; out="$(CHK)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ <synthetic> assistant 만 → 턴 0 통과" || bad "ⓑ synthetic rc=$rc ← $out"
setup; mkdir -p "$PROJ"; printf '{"type":"agent-name","agentName":"byz-planner-nano-ns#1"}\n{"type":"assistant","message":{"model":"m"}}\n' > "$PROJ/other.jsonl"
out="$(CHK)"; rc=$?; [ "$rc" -eq 0 ] && ok "ⓑ 같은 워크트리의 다른 좌석(#1) jsonl 은 세지 않는다" || bad "ⓑ 다른 좌석 rc=$rc ← $out"

echo "== ⓒ base 위 커밋 1 → REJECT"
setup; echo x > "$NW/w.txt"; git -C "$NW" add w.txt; git -C "$NW" commit -q -m work
reject "ⓒ 커밋 1" "never-started: 커밋 1"

echo "== ⓓ 미커밋 파일 1 → REJECT · 노이즈 4종만이면 통과"
setup; echo x > "$NW/real.txt"; reject "ⓓ 미커밋 1" "never-started: 미커밋 1파일"
setup; mkdir -p "$NW/clients/web" "$NW/.serena"; echo '{}' > "$NW/tsconfig.json"; echo x > "$NW/clients/web/next-env.d.ts"; echo y > "$NW/.serena/project.yml"
out="$(CHK)"; rc=$?; [ "$rc" -eq 0 ] && ok "ⓓ 노이즈(.worktree-info.json·tsconfig.json·next-env.d.ts·.serena/project.yml)만 → 통과" || bad "ⓓ 노이즈 rc=$rc ← $out"

echo "== ⓔ 좌석이 보낸 쪽지 1 → REJECT (회전본 .1 포함)"
setup; printf '{"seq": 2, "from": "%s", "to": "m", "body": "[부팅 보고]"}\n' "$SEAT" >> "$T/comm/mailbox.log.jsonl"
reject "ⓔ 쪽지 1" "never-started: 보낸 쪽지 1"
setup; printf '{"seq": 2, "from": "%s", "to": "m", "body": "x"}\n' "$SEAT" > "$T/comm/mailbox.log.jsonl.1"
out="$(CHK)"; rc=$?; rm -f "$T/comm/mailbox.log.jsonl.1"
[ "$rc" -eq 1 ] && has "$out" "보낸 쪽지 1" "ⓔ 회전본 .1 의 발신도 센다" || bad "ⓔ .1 rc=$rc ← $out"

echo "== 셀 수 없음 → REJECT(확인 못 함)"
setup; rm -f "$NW/.worktree-info.json"; printf '# 인덱스: ns\n## 상태\n- 진행\n' > "$CARD"
reject "base 못 정함(카드 base_sha·info 둘 다 없음)" "확인 못 함 base"
setup; rm -f "$T/comm/mailbox.log.jsonl"; out="$(CHK)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 보낸 쪽지" "우편함 기록 없음 → 확인 못 함" || bad "우편함 없음 rc=$rc ← $out"
setup; out="$(CHK --base deadbeefdeadbeef)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 커밋" "없는 base sha → 확인 못 함" || bad "없는 base rc=$rc ← $out"
setup codex; reject "agent=codex(대화 기록 셀 길 없음)" "확인 못 함 대화 기록(agent=codex)"

echo "== opencode — opencode.db session.directory = 워크트리의 assistant 메시지 수"
setup; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 opencode.db" "ⓗ opencode.db 없음 → 확인 못 함" || bad "oc db 없음 rc=$rc ← $out"
mkoc() { python3 - "$T/oc.db" "$@" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table session(id text primary key, directory text not null, time_created integer not null)")
c.execute("create table message(id text primary key, session_id text not null, data text not null)")
c.execute("insert into session values('s1', ?, ?)", (sys.argv[2], int(sys.argv[4]) if len(sys.argv) > 4 else 4102444800000))
for i in range(int(sys.argv[3])): c.execute("insert into message values(?, 's1', '{\"role\":\"assistant\"}')", ("m%d" % i,))
c.execute("insert into message values('u1', 's1', '{\"role\":\"user\"}')"); c.commit()
PY
}
setup; mkoc "$NW" 0; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓕ opencode 세션 assistant 0(user 발주만) → 통과" || bad "oc 0 rc=$rc ← $out"
setup; mkoc "$NW/sub" 2; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "opencode 턴 2" "ⓖ opencode 세션(워크트리 아래) assistant 2 → REJECT «opencode 턴 2»" || bad "oc 2 rc=$rc ← $out"
setup; mkoc "${NW}-other" 3; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 0 ] && ok "opencode 다른 폴더(<wt>-other) 세션은 세지 않는다" || bad "oc 다른 폴더 rc=$rc ← $out"

setup; printf '{"branch":"%s","base_sha":"%s","created_at":"2026-10-20 02:04:43"}\n' "$BR" "${BASE:0:10}" > "$NW/.worktree-info.json"
mkoc "$NW" 2 1700000000000; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓕ 좌석 생성 시각(created_at) 전의 옛 opencode 세션은 세지 않는다" || bad "oc 시각 rc=$rc ← $out"
setup; mkoc "$NW" 0; python3 -c 'import sqlite3,sys,time;c=sqlite3.connect(sys.argv[1]);c.execute("begin exclusive");time.sleep(4)' "$T/oc.db" & LP=$!; sleep 0.5
out="$(CHK --agent opencode)"; rc=$?; wait "$LP"
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 opencode.db" "ⓗ opencode.db 잠김(상한 초과) → 확인 못 함" || bad "ⓗ 잠김 rc=$rc ← $out"
setup; python3 -c 'import sqlite3,sys;sqlite3.connect(sys.argv[1]).execute("create table other(x)")' "$T/oc.db"; out="$(CHK --agent opencode)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 opencode.db" "ⓗ 스키마 다름 → 확인 못 함" || bad "ⓗ 스키마 rc=$rc ← $out"
echo "== ⓕ close — opencode 좌석(명부 agent=opencode · claude jsonl 없음) + db assistant 0 → CLOSED never-started"
setup opencode; mkoc "$NW" 0; printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT never-started «${REASON}»" "ⓕ opencode 좌석 → CLOSED never-started" || bad "ⓕ close rc=$rc ← ${out:0:900}"
setup opencode; mkoc "$NW" 1; printf '%s|%%1\n' "$SEAT" > "$T/panes"; reject "ⓖ opencode 좌석 + assistant 1" "never-started: opencode 턴 1"

echo "== ⓘ~ⓚ 공유 워크트리 후계(같은 계보 #1 · tmux 생존 · pane toplevel == 워크트리)"
SUC='byz-planner-nano-ns#1'
shared() {  # shared <후계 명부 행 json> — #1 이 커밋 8 · 미커밋 2 · 발신 4 · #0 은 opencode 턴 0 · 발신 0
  setup opencode; mkoc "$NW" 0
  python3 - "$REPO/.fable-team/seats-planner.json" "$SUC" "${1:-{\"role\":\"nano\",\"agent\":\"claude\"}}" <<'PY'
import json, sys
p, s, row = sys.argv[1:4]; d = json.load(open(p)); d[s] = json.loads(row); json.dump(d, open(p, "w"))
PY
  for i in 1 2 3 4 5 6 7 8; do echo "$i" > "$NW/f$i.txt"; git -C "$NW" add "f$i.txt"; git -C "$NW" commit -q -m "s$i"; done
  echo x > "$NW/f1.txt"; echo y > "$NW/new.txt"
  for i in 1 2 3 4; do printf '{"seq": %d, "from": "%s", "to": "m", "body": "x"}\n' "$((10+i))" "$SUC" >> "$T/comm/mailbox.log.jsonl"; done
  printf '%s|%%1\n%s|%%2\n' "$SEAT" "$SUC" > "$T/panes"
}
shared; HEAD8="$(git -C "$NW" rev-parse HEAD)"; ST8="$(git -C "$NW" status --porcelain)"
printf '%s|%s\n%s|%s\n' "$SEAT" "$NW" "$SUC" "$NW/sub" > "$T/panes-path"; mkdir -p "$NW/sub"
out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT never-started (공유 워크트리 → 후계 $SUC · 워크트리 정리 0)" "ⓘ 후계 현역 → CLOSED never-started (공유 워크트리 → 후계 <이름> · 워크트리 정리 0)" || bad "ⓘ rc=$rc ← ${out:0:1200}"
has "$out" "SUCCESSOR $SUC" "  └ 검사기 SUCCESSOR <후계>"; has "$out" "commits=skip dirty=skip" "  └ 커밋·미커밋 검사 생략(후계 몫)"
has "$out" "KILLED $SEAT" "  └ #0 세션 kill"; hasnt "$(cat "$T/tlog")" "$SUC" "  └ 후계 세션 kill 0"
[ "$(git -C "$NW" rev-parse HEAD)" = "$HEAD8" ] && [ "$(git -C "$NW" status --porcelain)" = "$ST8" ] && ok "  └ 워크트리 HEAD·미커밋 그대로([wip] 0)" || bad "  └ 워크트리 바뀜"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 정리 계획 0" || bad "  └ 정리 계획 생김"
has "$(cat "$LEDGER")" "mode=never-started-shared successor=$SUC" "  └ 원장 행 = 공유 후계 표기"
jq -e --arg s "$SUC" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 후계 명부 행 그대로" || bad "  └ 후계 행 삭제"
shared; printf '%s|%s\n%s|%s\n' "$SEAT" "$NW" "$SUC" "$NW/sub" > "$T/panes-path"
printf '{"seq": 30, "from": "%s", "to": "m", "body": "[부팅 보고]"}\n' "$SEAT" >> "$T/comm/mailbox.log.jsonl"
reject "ⓙ 후계 있음 + #0 발신 1" "never-started: 보낸 쪽지 1"
shared; printf '%s|%s\n%s|%s\n' "$SEAT" "$NW" "$SUC" "$NW/sub" > "$T/panes-path"; : > "$T/tmux-fail"
out="$(close --never-started "$REASON")"; rc=$?; rm -f "$T/tmux-fail"
[ "$rc" -eq 1 ] && has "$out" "커밋 8" "ⓚ 후계 판정 못 함(tmux 조회 실패) → 4값 전부 · REJECT 커밋 8" || bad "ⓚ rc=$rc ← ${out:0:800}"
has "$out" "미커밋 2파일" "  └ 미커밋도 검사"
shared '{"role":"nano","agent":"claude","_replaced_by":["x#2"]}'; printf '%s|%s\n%s|%s\n' "$SEAT" "$NW" "$SUC" "$NW/sub" > "$T/panes-path"
reject "후계 행 _replaced_by 있음 → 후계 아님 · 4값" "never-started: 커밋 8"
shared; printf '%s|%s\n%s|%s\n' "$SEAT" "$NW" "$SUC" "$T" > "$T/panes-path"
reject "후계 pane toplevel ≠ 워크트리 → 후계 아님 · 4값" "never-started: 커밋 8"
rm -f "$T/panes-path"

echo "== ⓛ~ⓝ 착지 가지(규칙 2b · 개정 r3) — 후계 없음 · ft-landed-check rc0(ancestor·cherry·card) 이면 커밋 수 생략 · 미커밋·턴·발신은 그대로"
landed() {  # landed <근거> — 가지에 커밋 2 · main 에 같은 patch(cherry) 또는 키 메시지(grep)
  setup; for i in 1 2; do echo "$i" > "$NW/l$i.txt"; git -C "$NW" add "l$i.txt"; git -C "$NW" commit -q -m "l$i"; done
  git -C "$REPO" checkout -q --detach "$BASE"   # main 은 매번 base 에서 다시(앞 회차의 착지분이 남지 않게)
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main 다른 일"   # 부모를 갈라 같은 초 cherry-pick 이 같은 sha(=ancestor)가 되지 않게
  case "$1" in
    cherry) git -C "$REPO" -c user.email=t@t -c user.name=t cherry-pick "$BASE..$BR" >/dev/null;;
    grep) git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "[docs] ns 정리(키만 언급)";;
  esac
  git -C "$REPO" branch -q -f main HEAD; git -C "$REPO" checkout -q main 2>/dev/null || git -C "$REPO" symbolic-ref HEAD refs/heads/main
}
landed cherry; out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT never-started (착지 가지 cherry · 워크트리 정리 0)" "ⓛ cherry 착지 · 미커밋 0 → CLOSED never-started (착지 가지 cherry · 워크트리 정리 0)" || bad "ⓛ rc=$rc ← ${out:0:1200}"
has "$out" "LANDED cherry" "  └ 검사기 LANDED <근거>"; has "$out" "commits=skip(landed cherry)" "  └ 커밋 수 생략(착지 몫)"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 정리 계획 0" || bad "  └ 정리 계획 생김"
has "$(cat "$LEDGER")" "mode=never-started-landed landed=cherry" "  └ 원장 행 = 착지 가지 표기"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 실재(삭제 0)" || bad "  └ 브랜치 삭제됨"
landed cherry; printf '%s|%%1\n' "$SEAT" > "$T/panes"; out="$(close --never-started "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT never-started (착지 가지 cherry · 워크트리 정리 0)" "ⓛ 세션 생존 → CLOSED … (착지 가지 cherry …) + kill" || bad "ⓛ' rc=$rc ← ${out:0:800}"
has "$out" "KILLED $SEAT" "  └ 세션 kill"
landed grep; reject "ⓜ grep 근거(약한 증거) → 2b 적용 0 · 4값" "never-started: 커밋 2"
landed cherry; echo x > "$NW/dirty.txt"; reject "ⓝ 착지 + 미커밋 1 → REJECT" "never-started: 미커밋 1파일"
landed cherry; printf '{"seq": 40, "from": "%s", "to": "m", "body": "x"}\n' "$SEAT" >> "$T/comm/mailbox.log.jsonl"; reject "착지 + #0 발신 1 → REJECT" "never-started: 보낸 쪽지 1"
landed cherry; out="$(run FT_NEVER_MAIN_REF=no-such-ref bash "$T/bin/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW" --branch "$BR" --comm "$T/comm" --landed-auto)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "커밋 2" "착지 판정 실패(main ref 없음) → 2b 적용 0 · REJECT 커밋 2" || bad "판정 실패 rc=$rc ← $out"
setup

echo "== usage rc2 · 변경 0"
usage2() { local name="$1"; shift; setup; out="$(close "$@")"; rc=$?; [ "$rc" -eq 2 ] && ok "$name → usage rc=2" || bad "$name — rc=$rc ← ${out:0:300}"; untouched "$name"; }
usage2 "빈 사유" --never-started ""
usage2 "공백 사유" --never-started "   "
usage2 "값 누락" --never-started
usage2 "여러 줄 사유" --never-started $'한 줄\n두 줄'
usage2 "+ --suspended" --never-started "$REASON" --suspended "x"
usage2 "+ --superseded-by" --superseded-by design/planner/indices/진행/o.md --never-started "$REASON"
usage2 "+ --shared-wt" --never-started "$REASON" --shared-wt
setup; out="$(CHK)"; rc=$?; out2="$(run bash "$T/bin/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW")"; rc2=$?
[ "$rc" -eq 0 ] && [ "$rc2" -eq 2 ] && ok "검사 단독: 정상 rc0 · --branch 누락 usage 2" || bad "검사 단독 rc=$rc/$rc2 ← $out / $out2"

echo "== 인자 없으면 지금 동작 그대로 — ①② REJECT"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "①결과 경로 없음" "인자 없음 → ① REJECT 그대로" || bad "불변 rc=$rc ← ${out:0:400}"
has "$out" "②--recv <seq> 미지정" "  └ ② REJECT 그대로"; hasnt "$out" "NEVER-STARTED" "  └ 한 일 0 검사 안 돎"; untouched "불변"

echo "== 600/300 s · 외부 호출 · GIT_* env 0 (새 검사 스크립트 + close 의 r506 줄)"
# 줄 번호 없이 grep — 번호 600·300 줄이 아래 숫자 검사에 걸리는 오탐(r506 줄 이동 실측)
NEWL="$(cat "$SRC/ft-nano-never-started-check.sh"; grep 'r506\|NEVER\|_ns_' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "GIT_DIR env 0"; hasnt "$NEWL" "GIT_WORK_TREE=" "GIT_WORK_TREE env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
