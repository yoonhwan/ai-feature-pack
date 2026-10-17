#!/usr/bin/env bash
# test_resource_reclaim.sh — R198(판정 1767) ft-resource-reclaim.sh: DA⑥ 축 ⓐ~ⓕ + 호출처 + 변이 2.
# 전부 mktemp 안 — 임시 HOME(재개 기록) · 임시 명부·카드 · 가짜 tmux/pgrep/ps/nano-close/seat-status/mbox/문지기(PATH·env) · 진짜 tmux 세션 kill 0.
# 변이: 승인 표 판정 제거(resume_ok 항상 통과) → 범위 밖 좌석 kill 단언 FAIL · 잠금 제거 → 동시 2호출 중복 kill FAIL.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
SCRIPT_NAME=ft-resource-reclaim.sh
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
cnt()  { local n; n="$(grep -c -F -- "$2" "$1" 2>/dev/null)"; echo "${n:-0}"; }

bash -n "$BIN/$SCRIPT_NAME" && ok "bash -n $SCRIPT_NAME" || bad "bash -n $SCRIPT_NAME"
for f in ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
for f in $SCRIPT_NAME ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
[ -x "$BIN/$SCRIPT_NAME" ] && ok "실행 권한 $SCRIPT_NAME" || bad "실행 권한 없음 $SCRIPT_NAME"

# ── 가짜 도구 (한 번만 만들고 상태 파일만 시험마다 바꾼다) ──
F="$T/fake"; H="$T/home"; ST="$T/st"; mkdir -p "$F" "$H/.claude/state/seat-resume" "$T/cards"
cat > "$F/tmux" <<EOF
#!/bin/bash
S="$ST/sessions"
case "\$1" in
  list-sessions) case "\$3" in *session_activity*) awk '{print \$1"|"\$2"|"\$3}' "\$S";; *) awk '{print \$1"|"\$3}' "\$S";; esac;;
  list-panes) if [ "\$2" = -a ]; then awk '{print \$1" "\$4}' "\$S"; else n="\${3#=}"; awk -v n="\$n" '\$1==n{print \$4}' "\$S"; fi;;
  show-options) n="\${@: -2:1}"; n="\${n#=}"; n="\${n%:}"; [ -f "$ST/active.\${n//#/_}" ] && echo 1;;
  kill-session) n="\${3#=}"; echo "\$n" >> "$ST/kill.log"; [ -f "$ST/kill.slow" ] && sleep 1; grep -v "^\$n " "\$S" > "\$S.new"; mv "\$S.new" "\$S";;
  *) exit 0;;
esac
EOF
cat > "$F/pgrep" <<EOF
#!/bin/bash
[ "\$1" = -P ] && awk -v p="\$2" '\$1==p{print \$2; f=1}END{exit !f}' "$ST/kids"
EOF
cat > "$F/ps" <<EOF
#!/bin/bash
case "\$*" in *ppid=*) exec /bin/ps "\$@";; *) k="\${@: -1}"; awk -v p="\$k" '\$1==p{sub(/^[0-9]+ /,""); print}' "$ST/cmds";; esac
EOF
printf '#!/bin/bash\necho called >> "%s/mktemp.calls"\nexec /usr/bin/mktemp "$@"\n' "$ST" > "$F/mktemp"
cat > "$F/seat-status.sh" <<EOF
#!/bin/bash
k="\${2//#/_}"
if [ -f "$ST/protectflip.req" ] && [ "\$2" = 'byz-t-role-claude#1' ] && [ ! -f "$ST/protect-flip" ]; then
  pc=\$(cat "$ST/protectc" 2>/dev/null || echo 0); echo \$((pc+1)) > "$ST/protectc"
fi
if [ -f "$ST/protectflip.req" ] && [ "\$2" = 'byz-t-role-claude#1' ] && [ ! -f "$ST/protect-flip" ] && [ "\$(cat "$ST/protectc")" -ge 2 ]; then
  python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["_master"]="byz-t-role-claude#1";json.dump(d,open(p,"w"))' "$ST/seats.json"; touch "$ST/protect-flip"
fi
if [ -f "$ST/flip.\$k" ]; then c=\$(cat "$ST/flipc.\$k" 2>/dev/null || echo 0); echo \$((c+1)) > "$ST/flipc.\$k"; [ "\$c" -ge "\$(cat "$ST/flip.\$k")" ] && { echo "WORKING - - - jsonl"; exit 0; }; fi
[ -f "$ST/turn.\$k" ] && cat "$ST/turn.\$k" || echo "IDLE 2026-10-15T00:00:00Z 1 1 jsonl"
EOF
cat > "$F/nano-close.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$ST/nc.log"
k="\${1//#/_}"
if [ -f "$ST/nc.reject.\$k" ]; then echo "REJECT \$1"; echo "  - ⑤cherry 미반입"; exit 1; fi
grep -v "^\$1 " "$ST/sessions" > "$ST/sessions.new"; mv "$ST/sessions.new" "$ST/sessions"; echo "CLOSED \$1"
EOF
cat > "$F/mbox.sh" <<EOF
#!/bin/bash
case "\$1" in
  send) echo "\$*" >> "$ST/mbox.log"; echo "QUEUED";;
  peek) k="\${2//#/_}"
    if [ -f "$ST/pendflip.\$k" ]; then c=\$(cat "$ST/pendflipc.\$k" 2>/dev/null || echo 0); echo \$((c+1)) > "$ST/pendflipc.\$k"; [ "\$c" -ge 1 ] && { echo "pending=1 scanned=1"; exit 0; }; fi
    echo "pending=\$( [ -f "$ST/pend.\$k" ] && cat "$ST/pend.\$k" || echo 0 ) scanned=1";;
esac
EOF
cat > "$F/gate.sh" <<EOF
#!/bin/bash
[ -f "$ST/disk.mode" ] && { echo "REJECT resource disk=1GiB limit=30GiB"; exit 3; }
n=\$(grep -c . "$ST/sessions"); l=\${FT_TEST_LIMIT:-6}
[ "\$n" -gt "\$l" ] && { echo "REJECT resource agents=\$n limit=\$l"; exit 3; }
echo "OK disk=99GiB agents=\$n"
EOF
chmod +x "$F"/*

NOW=$(date +%s)
mkseat() { # 이름 idle분 attached pane_pid
  printf '%s %s %s %s\n' "$1" "$((NOW - $2*60))" "$3" "$4" >> "$ST/sessions"; }
mkrecord() { # 이름 pane_pid child_pid
  local u="uuid-$RANDOM$RANDOM" d="$T/cwd"; mkdir -p "$d"; : > "$T/$u.jsonl"
  python3 -c 'import json,sys;json.dump({"name":sys.argv[1],"engine":"claude","uuid":sys.argv[2],"jsonl":sys.argv[3],"cwd":sys.argv[4],"model":"claude-sonnet-5-5[1m]","pid":sys.argv[5]},open(sys.argv[6],"w"))' \
    "$1" "$u" "$T/$u.jsonl" "$d" "$3" "$H/.claude/state/seat-resume/$1.json"
  echo "$2 $3" >> "$ST/kids"; }

setup() {   # 시험마다 새 세계
  rm -rf "$ST" "$T/root"; mkdir -p "$ST" "$T/root/.fable-team/state"; rm -f "$H/.claude/state/seat-resume/"*.json
  : > "$ST/sessions"; : > "$ST/kids"; : > "$ST/cmds"; cp /dev/null "$F/mailbox.jsonl"
  local c
  for c in a b c d e; do echo "card $c" > "$T/cards/$c.md"; done
  # 나노 5 (a: 가장 오래 쉼·닫힘 후보 / b: attached / c: WORKING / d: pending / e: 닫을 수 있으나 need 밖)
  mkseat "byz-t-nano-a#0" 120 0 90001; mkseat "byz-t-nano-b#0" 110 1 90002; mkseat "byz-t-nano-c#0" 105 0 90003
  mkseat "byz-t-nano-d#0" 100 0 90004; mkseat "byz-t-nano-e#0" 60 0 90005
  echo "WORKING - - - jsonl" > "$ST/turn.byz-t-nano-c_0"; echo 2 > "$ST/pend.byz-t-nano-d_0"
  # 직전 세대: role(기록 O·닫힘 후보) · erole(기록 없음) · vrole(V65 active) · srole(라이브 서버)
  mkseat "byz-t-role-claude#1" 100 0 91001; mkseat "byz-t-role-claude#2" 3 0 91002; mkrecord "byz-t-role-claude#1" 91001 4101
  mkseat "byz-t-erole-claude#1" 99 0 91003; mkseat "byz-t-erole-claude#2" 3 0 91004
  mkseat "byz-t-vrole-claude#1" 98 0 91005; mkseat "byz-t-vrole-claude#2" 3 0 91006; mkrecord "byz-t-vrole-claude#1" 91005 4102; touch "$ST/active.byz-t-vrole-claude_1"
  mkseat "byz-t-srole-claude#1" 97 0 91007; mkseat "byz-t-srole-claude#2" 3 0 91008; mkrecord "byz-t-srole-claude#1" 91007 4103; echo "4103 uvicorn app:main --port 38301" >> "$ST/cmds"
  # 명부 밖(다른 프로젝트) 직전 세대 — 재개 기록은 유효하나 BYZ 명부에 행이 없다 (DA⑥ H1)
  mkseat "other-proj-claude#1" 150 0 93001; mkseat "other-proj-claude#2" 3 0 93002; mkrecord "other-proj-claude#1" 93001 4104
  # 범위 밖: codex DA · 상위 오케(master·planner)
  mkseat "byz-t-da-codex#0" 300 0 92001; mkseat "byz-t-master-claude#1" 200 0 92002; mkseat "byz-t-planner-claude#1" 200 0 92003
  python3 - "$ST/seats.json" "$T/cards" <<'PY'
import json, sys
d = {"_master": "byz-t-master-claude#1", "_hil_route": "byz-t-planner-claude#1"}
for k in "abcde": d[f"byz-t-nano-{k}#0"] = {"role": "nano", "agent": "claude", "index": f"{sys.argv[2]}/{k}.md"}
d["byz-t-da-codex#0"] = {"role": "da", "agent": "codex"}
for b in ("role", "erole", "vrole", "srole"):
    for g in (1, 2): d[f"byz-t-{b}-claude#{g}"] = {"role": b, "agent": "claude"}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
  for c in a b c d e; do echo "{\"seq\": $((10000+$(printf %d "'$c"))), \"from\": \"byz-t-nano-$c#0\", \"to\": \"x\", \"body\": \"완료\"}" >> "$F/mailbox.jsonl"; done
  : > "$ST/kill.log"; : > "$ST/nc.log"; : > "$ST/mbox.log"
}

run() {   # run <스크립트> [도구 인자…] — 가짜를 env/PATH 로 주입(추가 env 는 `VAR=값 run …` 으로)
  local s="$1"; shift
  PATH="$F:$PATH" HOME="$H" TOKEN_SENTINEL=sk-ant-SECRET-xyz FT_RES_ROOT="$T/root" FT_SEATS_JSON="$ST/seats.json" FT_SEAT_STATUS="$F/seat-status.sh" FT_NANO_CLOSE="$F/nano-close.sh" \
    FT_MBOX_SH="$F/mbox.sh" ZC_RESUME_DIR="$H/.claude/state/seat-resume" FT_PRESS_PERMIT_DIR="$T/permits" FT_RECLAIM_LOCK_TRIES=10 bash "$s" "$@" 2>&1
}

suite() {   # $1=시험할 스크립트 경로 — 한 묶음 단언 (실물이면 fail=0 이어야 하고, 변이면 fail>0 이어야 한다)
  local S="$1" out rc

  # ── ⓐⓑⓒ need=2 : 오래 쉰 순으로 정확히 2개, 행 밖 kill 0, 제외 가드 전부 ──
  setup
  out="$(run "$S" --caller byz-t-master-claude#1 --need 2)"; rc=$?
  eq "$rc" 0 "need=2 rc0"
  eq "$(cat "$ST/kill.log")" "byz-t-role-claude#1" "ⓐ kill-session = 재개 기록 있는 직전 세대 1개뿐(행 밖 0 · codex/기록없음/active/서버/현역 0)"
  eq "$(cat "$ST/nc.log" | awk '{print $1}')" "byz-t-nano-a#0" "ⓐ nano-close = 가장 오래 쉰 병합 끝 나노 1개뿐"
  has "$(cat "$ST/nc.log")" "--result $T/cards/a.md --recv 10097" "ⓐ nano-close 인자 = 카드 경로 + 그 나노의 마지막 보고 seq"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 2 "ⓒ 필요 수(need=2)만 닫음 — 그 이상 0 (나노 e 도 닫을 수 있었지만 안 닫음)"
  has "$out" "RECLAIMED 2" "표 끝 RECLAIMED 2"
  has "$out" "byz-t-nano-b#0 | 병합 끝 나노 | - | SKIP attached" "ⓑ attached 후보 제외"
  has "$out" "byz-t-nano-c#0 | 병합 끝 나노 | - | SKIP jsonl WORKING" "ⓑ jsonl WORKING 후보 제외"
  has "$out" "byz-t-nano-d#0 | 병합 끝 나노 | - | SKIP mbox pending=2" "ⓑ mbox pending>0 후보 제외"
  has "$out" "byz-t-vrole-claude#1 | 직전 세대 좌석 | - | SKIP V65 active" "ⓑ V65 active 제외"
  has "$out" "byz-t-srole-claude#1 | 직전 세대 좌석 | - | SKIP 라이브 서버" "ⓑ 라이브 서버 보유 제외"
  has "$out" "byz-t-erole-claude#1 | 직전 세대 좌석 | - | HIL(승인 범위 밖: 재개 기록 없음" "재개 기록 없는 직전 세대 = 승인 범위 밖(HIL)"
  has "$out" "byz-t-da-codex#0 | 현역 역할/기타 | - | HIL(승인 범위 밖" "codex DA = 승인 범위 밖(HIL)"
  has "$out" "other-proj-claude#1 | 직전 세대 좌석 | - | HIL(승인 범위 밖: 다른 프로젝트" "회귀 H1: 명부 밖 직전 세대(재개 기록 유효) = 승인 범위 밖 표 행"
  hasnt "$(cat "$ST/kill.log")" "other-proj" "회귀 H1: 명부 밖 좌석 kill 0"
  hasnt "$out" "byz-t-master-claude#1 |" "ⓑ 부르는 쪽(master) 표에도 안 올림"
  hasnt "$out" "byz-t-planner-claude#1 |" "ⓑ 상위 오케(_hil_route) 표에도 안 올림"
  has "$(cat "$T/root/.fable-team/state/reclaim.log")" "RECLAIMED 2" "로그 = 표 그대로 append"
  hasnt "$(cat "$T/root/.fable-team/state/reclaim.log")$out" "SECRET" "ⓕ 표·로그에 비밀 0"

  # ── nano-close 가 거절하면 후보 탈락(HIL) — 미병합 나노는 닫지 않는다 ──
  setup; touch "$ST/nc.reject.byz-t-nano-a_0"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 1)"
  has "$out" "byz-t-nano-a#0 | 병합 끝 나노 | 나노 세션 정리 2026-10-02 | HIL(승인 범위 밖: nano-close 거절" "ⓐ nano-close REJECT = 후보 탈락 + HIL"
  eq "$(cat "$ST/kill.log" | wc -l | tr -d ' ')" 1 "거절된 나노 다음 후보로 넘어감(직전 세대 1개 kill)"

  # ── dry-run ──
  setup
  out="$(run "$S" --dry-run --caller byz-t-master-claude#1 --need 2)"
  has "$out" "WOULD-CLOSE(nano-close)" "dry-run 나노 표시"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "dry-run = 실제 kill·close 0"
  [ ! -e "$T/root/.fable-team/state/reclaim.log" ] && ok "회귀 H3: dry-run 은 reclaim.log 쓰기 0" || bad "회귀 H3: dry-run 이 reclaim.log 를 썼다"

  # ── 회귀 H3: dry-run + 문지기 REJECT 에서도 [HIL] 발신·로그·sig 0 ──
  setup
  out="$(FT_TEST_LIMIT=3 run "$S" --dry-run --on-reject "REJECT resource agents=17 limit=3" --gate "$F/gate.sh")"; rc=$?
  eq "$(grep -c '^send ' "$ST/mbox.log")" 0 "회귀 H3: dry-run REJECT 에서 [HIL] mbox 발신 0"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "회귀 H3: dry-run REJECT 에서 kill·close 0"
  [ ! -e "$T/root/.fable-team/state/reclaim.log" ] && [ ! -e "$T/root/.fable-team/state/reclaim-hil.sig" ] && ok "회귀 H3: dry-run REJECT 로그·sig 0" || bad "회귀 H3: dry-run REJECT 가 상태 파일을 썼다"
  has "$out" "REJECT resource agents=17 limit=3" "dry-run REJECT 원문 통과"
  eq "$rc" 3 "dry-run REJECT rc3"

  # ── 회귀 r3: 첫 판정 «뒤»(두 번째 조회에서) 명부 _master 가 후보로 바뀌면(승계) kill 0 — 시작 시 만든 보호 문자열이 아니라 «지금» 명부를 다시 읽는다 ──
  setup; touch "$ST/protectflip.req"
  out="$(run "$S" --caller byz-t-nano-a#0 --need 1)"
  [ -f "$ST/protect-flip" ] && ok "회귀 r3: 시험 전제 — 명부가 첫 판정 중 바뀜" || bad "회귀 r3: 시험 전제 불성립(명부가 안 바뀜)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-role-claude#1" "회귀 r3: 보호 전이(현역 master) 후 kill 0"
  has "$out" "byz-t-role-claude#1 | 직전 세대 좌석 | - | SKIP(재확인 거절) 부르는 쪽·상위 오케" "회귀 r3: 재확인 거절 표 행"

  # ── 회귀 r3: dry-run (direct · on-reject) 은 mktemp «호출» 0 (끝 상태 snapshot 이 아니라 호출 기록) · 정상 실행도 0 ──
  setup; rm -f "$ST/mktemp.calls"
  run "$S" --dry-run --caller byz-t-master-claude#1 --need 1 >/dev/null
  [ ! -s "$ST/mktemp.calls" ] && ok "회귀 r3: dry-run direct mktemp 호출 0" || bad "회귀 r3: dry-run direct 가 mktemp 를 불렀다"
  FT_TEST_LIMIT=3 run "$S" --dry-run --on-reject "REJECT resource agents=17 limit=3" --gate "$F/gate.sh" >/dev/null
  [ ! -s "$ST/mktemp.calls" ] && ok "회귀 r3: dry-run on-reject mktemp 호출 0" || bad "회귀 r3: dry-run on-reject 가 mktemp 를 불렀다"
  run "$S" --caller byz-t-master-claude#1 --need 1 >/dev/null
  [ ! -s "$ST/mktemp.calls" ] && ok "회귀 r3: 실행 분기도 정렬용 임시 파일 0" || bad "회귀 r3: 실행 분기가 mktemp 를 불렀다"

  # ── 회귀 H2: 첫 판정 뒤 jsonl 이 WORKING 으로 바뀌면 kill 0 ──
  setup; echo 1 > "$ST/flip.byz-t-role-claude_1"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 2)"
  eq "$(cat "$ST/kill.log")" "" "회귀 H2: 재확인에서 WORKING 으로 바뀐 직전 세대 kill 0"
  has "$out" "byz-t-role-claude#1 | 직전 세대 좌석 | - | SKIP(재확인 거절) jsonl WORKING" "회귀 H2: SKIP(재확인 거절) 표 행"
  # ── 회귀 H2: 첫 판정 뒤 mbox pending 이 생기면 nano-close 0 ──
  setup; touch "$ST/pendflip.byz-t-nano-a_0"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 1)"
  has "$out" "byz-t-nano-a#0 | 병합 끝 나노 | - | SKIP(재확인 거절) mbox pending=1" "회귀 H2: 나노 pending 변화 SKIP(재확인 거절)"
  hasnt "$(awk '{print $1}' "$ST/nc.log")" "byz-t-nano-a#0" "회귀 H2: 바뀐 나노 nano-close 호출 0"

  # ── ⓓ 호출처 모드: 정리 뒤 문지기 재검 OK → rc0 ──
  setup   # 세션 17 · 한도 15 → need=3 (직전 세대 role#1 · 나노 a · 나노 e)
  out="$(FT_TEST_LIMIT=15 run "$S" --on-reject "REJECT resource agents=17 limit=15" --gate "$F/gate.sh")"; rc=$?
  eq "$rc" 0 "ⓓ 정리 뒤 문지기 OK → rc0"
  has "$out" "RECLAIM ok need=3" "need = agents − limit + 1 = 3"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 3 "ⓒ need=3 만큼만 닫음"
  hasnt "$(cat "$ST/kill.log")" "erole" "ⓐ 재개 기록 없는 직전 세대 kill 0"

  # ── ⓓ 모자라면 원래 REJECT + 표 + HIL 1통, 같은 날 같은 묶음 재발신 0 ──
  setup
  out="$(FT_TEST_LIMIT=3 run "$S" --on-reject "REJECT resource agents=17 limit=3" --gate "$F/gate.sh")"; rc=$?
  eq "$rc" 3 "ⓓ 여전히 REJECT → rc3"
  has "$out" "REJECT resource agents=17 limit=3" "ⓓ 원래 REJECT 문구 그대로"
  has "$out" "후보 | 종류 | 승인 근거 | 결과" "ⓓ 후보 표 동반"
  eq "$(cat "$ST/mbox.log" | grep -c '^send byz-t-planner-claude#1 ')" 1 "ⓓ [HIL] 1통 → _hil_route"
  has "$(cat "$ST/mbox.log")" "[HIL] 자원 — 승인 범위 밖 후보" "HIL 머리"
  : > "$ST/mbox.log"   # 같은 날 같은 후보 묶음으로 한 번 더(setup 없이)
  out="$(FT_TEST_LIMIT=3 run "$S" --on-reject "REJECT resource agents=17 limit=3" --gate "$F/gate.sh")"
  eq "$(cat "$ST/mbox.log" | grep -c '^send ')" 0 "ⓓ 같은 날 같은 후보 묶음 = HIL 재발신 0"
  has "$out" "HIL 재발신 0" "재발신 0 안내"

  # ── ⓔ 디스크 등 다른 사유는 정리 0 ──
  setup; touch "$ST/disk.mode"
  out="$(run "$S" --on-reject "REJECT resource disk=1GiB limit=30GiB" --gate "$F/gate.sh")"; rc=$?
  eq "$rc" 3 "ⓔ 디스크 REJECT = rc3 그대로"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "ⓔ 디스크 사유엔 정리 0"
  has "$out" "REJECT resource disk=1GiB limit=30GiB" "ⓔ 원문 통과"

  # ── ⓔ 동시 2호출: 같은 좌석 두 번 닫기 0 (잠금) ──
  setup; touch "$ST/kill.slow"
  ( run "$S" --caller byz-t-master-claude#1 --need 1 >/dev/null & run "$S" --caller byz-t-master-claude#1 --need 1 >/dev/null & wait )
  # 각 호출 need=1 → 총 2개 닫힘 가능하나, 같은 좌석을 두 번 닫으면 안 된다
  eq "$(sort "$ST/kill.log" "$ST/nc.log" | awk '{print $1}' | sort | uniq -d | wc -l | tr -d ' ')" 0 "ⓔ 동시 2호출 = 같은 좌석 중복 kill/close 0"
}

# ── 실물 ──
suite "$BIN/$SCRIPT_NAME"
[ "$fail" -eq 0 ] && ok "실물 묶음 전부 통과" || bad "실물 묶음 실패 ${fail}건"
real_fail=$fail

# ── 호출처: FT_RECLAIM=0 이면 정리 도구를 부르지 않는다 / 기본이면 1번 ──
CB="$T/callbin"; mkdir -p "$CB"; cp "$BIN/ft-nano-spawn.sh" "$CB/"
printf '#!/bin/bash\necho "REJECT resource agents=41 limit=40"; exit 3\n' > "$CB/ft-resource-gate.sh"
printf '#!/bin/bash\necho "$*" >> "%s"; printf "%%s\\n" "$2"; exit 3\n' "$T/reclaim.calls" > "$CB/ft-resource-reclaim.sh"
: > "$T/reclaim.calls"
o0="$(FT_RECLAIM=0 bash "$CB/ft-nano-spawn.sh" x.md 2>&1)"; r0=$?
eq "$(wc -l < "$T/reclaim.calls" | tr -d ' ')" 0 "FT_RECLAIM=0 → 정리 도구 호출 0"
has "$o0" "REJECT resource agents=41 limit=40" "FT_RECLAIM=0 → 원래 REJECT"
o1="$(bash "$CB/ft-nano-spawn.sh" x.md 2>&1)"; r1=$?
eq "$(wc -l < "$T/reclaim.calls" | tr -d ' ')" 1 "기본 → 문지기 REJECT 때만 정리 도구 1번"
has "$(cat "$T/reclaim.calls")" "--on-reject REJECT resource agents=41 limit=40" "문지기 출력 그대로 전달"
eq "$r1" 3 "정리 실패 → 기존 REJECT rc 유지"

# ── R320: swap·메모리·압력·속도 사유도 정리한다 (병합 끝 나노 idle 문턱 5분 · 모자라면 [HIL] + 재부팅 계획 1줄) ──
printf '#!/bin/bash\n[ -f "%s/rej.hard" ] && { cat "%s/rej.text"; exit 3; }\n[ -f "%s/rej.once" ] && [ ! -s "%s/kill.log" ] && [ ! -s "%s/nc.log" ] && { cat "%s/rej.text"; exit 3; }\necho "OK disk=99GiB"\n' "$ST" "$ST" "$ST" "$ST" "$ST" "$ST" > "$F/gate-res.sh"
printf '#!/bin/bash\necho "! bash /tmp/h777"\n' > "$F/hil.sh"; chmod +x "$F/gate-res.sh" "$F/hil.sh"
addnano() {   # 이름 idle분 카드경로 — 명부 행·보고 seq·카드 파일·세션을 한 번에 (setup 직후에 부른다)
  mkdir -p "$(dirname "$3")"; echo "card" > "$3"; mkseat "$1" "$2" 0 "9${RANDOM}"
  python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d[sys.argv[2]]={"role":"nano","agent":"claude","index":sys.argv[3]};json.dump(d,open(p,"w"),ensure_ascii=False)' "$ST/seats.json" "$1" "$3"
  echo "{\"seq\": $((20000+RANDOM)), \"from\": \"$1\", \"to\": \"x\", \"body\": \"완료\"}" >> "$F/mailbox.jsonl"
}
swapworld() { setup
  addnano "byz-t-nano-f#0" 6 "$T/cards2/indices/완성/f.md"; addnano "byz-t-nano-g#0" 3 "$T/cards2/indices/완성/g.md"; addnano "byz-t-nano-h#0" 6 "$T/cards2/indices/진행/h.md"
  : > "$ST/rej.text"; }
SWAP_REJ="REJECT resource swap=13000MiB limit=12288MiB"
swapworld; echo "$SWAP_REJ" > "$ST/rej.text"; touch "$ST/rej.once"
out="$(run "$BIN/$SCRIPT_NAME" --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh")"; rc=$?
eq "$rc" 0 "R320 swap REJECT → 정리 뒤 문지기 OK rc0"
has "$out" "RECLAIM ok" "R320 swap 사유 회수 표"
eq "$(awk '{print $1}' "$ST/nc.log" | sort | tr '\n' ' ')" "byz-t-nano-a#0 byz-t-nano-e#0 byz-t-nano-f#0 " "R320 닫는 나노 = 후보 전부(a·e 30분↑ · f 완성 카드 5분↑) · b attached·c WORKING·d pending·g 3분·h 미완성 6분 0"
eq "$(cat "$ST/kill.log")" "byz-t-role-claude#1" "R320 kill-session = 재개 기록 있는 직전 세대뿐(역할 현역·codex DA·기록 없음·명부 밖 0)"
# idle 분은 시험이 도는 동안 1~2분 흐를 수 있어 «문턱 문구»만 단언한다
has "$(printf '%s\n' "$out" | grep 'byz-t-nano-g#0 |')" "분 < 5분" "R320 완성 카드 나노 5분 문턱"
has "$(printf '%s\n' "$out" | grep 'byz-t-nano-h#0 |')" "분 < 30분" "R320 완성 카드 아닌 나노 30분 문턱"
has "$(cat "$T/root/.fable-team/state/reclaim.log")" "why=swap=13000MiB" "R320 reclaim.log 헤더에 swap 사유"
for rej in "REJECT resource memfree=9% limit=15%" "REJECT resource level=4 limit=2" "REJECT resource rate=900MiB/min limit=512MiB/min"; do
  swapworld; echo "$rej" > "$ST/rej.text"; touch "$ST/rej.once"
  out="$(run "$BIN/$SCRIPT_NAME" --on-reject "$rej" --gate "$F/gate-res.sh")"; rc=$?
  eq "$rc" 0 "R320 ${rej#REJECT resource } → 정리 뒤 rc0"; eq "$(wc -l < "$ST/nc.log" | tr -d ' ')" 3 "R320 ${rej#REJECT resource } → 나노 3석 닫기"
done
swapworld; echo "$SWAP_REJ" > "$ST/rej.text"; touch "$ST/rej.hard"
out="$(FT_HIL_SH="$F/hil.sh" run "$BIN/$SCRIPT_NAME" --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh")"; rc=$?
eq "$rc" 3 "R320 정리 뒤에도 REJECT → rc3"; has "$out" "$SWAP_REJ" "R320 원래 REJECT 문구"
eq "$(grep -c '^send byz-t-planner-claude#1 ' "$ST/mbox.log")" 1 "R320 [HIL] 1통 → _hil_route"
has "$(cat "$ST/mbox.log")" "! bash /tmp/h777" "R320 [HIL] 에 재부팅 계획 1줄(ft-hil 이 돌려준 ! bash /tmp/h<N>)"
ls "$T/root/.fable-team/state"/reboot-plan-*.sh.hil >/dev/null 2>&1 && ok "R320 재부팅 계획 파일 작성" || bad "R320 재부팅 계획 파일 없음"
hasnt "$(cat "$T/root/.fable-team/state"/reboot-plan-*.sh.hil)" "reboot" "R320 계획 내용 = 안내만(실행 명령 0)"
: > "$ST/mbox.log"; run "$BIN/$SCRIPT_NAME" --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh" >/dev/null
eq "$(grep -c '^send ' "$ST/mbox.log")" 0 "R320 같은 날 같은 묶음 [HIL] 재발신 0"
swapworld; touch "$ST/rej.hard"; echo "$SWAP_REJ" > "$ST/rej.text"
out="$(run "$BIN/$SCRIPT_NAME" --dry-run --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh")"
has "$out" "WOULD-CLOSE(nano-close)" "R320 dry-run 표시"; eq "$(cat "$ST/kill.log" "$ST/nc.log" "$ST/mbox.log" | wc -l | tr -d ' ')" 0 "R320 dry-run kill·close·mbox 0"
swapworld; out="$(run "$BIN/$SCRIPT_NAME" --on-reject "ERROR resource measure swap rc≠0" --gate "$F/gate-res.sh")"; rc=$?
eq "$rc" 4 "R320 측정 실패 ERROR rc4 유지"; eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "R320 측정 실패엔 정리 0"
swapworld; out="$(run "$BIN/$SCRIPT_NAME" --on-reject "REJECT resource freeze=FREEZE x limit=0" --gate "$F/gate-res.sh")"; rc=$?
eq "$rc" 3 "R320 동결 REJECT rc3 유지"; eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "R320 동결엔 정리 0"
swapworld; echo "$SWAP_REJ" > "$ST/rej.text"; touch "$ST/rej.once"
out="$(FT_RECLAIM_DONE_IDLE_MIN=2 run "$BIN/$SCRIPT_NAME" --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh")"
has "$(awk '{print $1}' "$ST/nc.log")" "byz-t-nano-g#0" "R320 FT_RECLAIM_DONE_IDLE_MIN=2 → 3분 쉰 완성 나노도 닫음"

# ── 변이 ──
MUT="$T/mut"; mkdir -p "$MUT"
sed 's/^resume_ok() {/resume_ok() { return 0;/' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # 승인 표 판정(재개 기록 검증) 제거
saved=$fail; fail=0; suite "$MUT/$SCRIPT_NAME" >"$T/mut1.out"; m1=$fail; fail=$saved
[ "$m1" -gt 0 ] && ok "변이1(승인 표 판정 제거) → 단언 FAIL ${m1}건" || bad "변이1 이 잡히지 않음(시험이 약하다)"
sed 's/^acquire_lock || /true || /; s/^  acquire_lock || /  true || /' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # 잠금 제거
saved=$fail; fail=0; suite "$MUT/$SCRIPT_NAME" >"$T/mut2.out"; m2=$fail; fail=$saved
[ "$m2" -gt 0 ] && ok "변이2(잠금 제거) → 단언 FAIL ${m2}건" || bad "변이2 가 잡히지 않음(시험이 약하다)"

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare 이상"
echo "---- fail=$fail"
[ "$fail" -eq 0 ]
