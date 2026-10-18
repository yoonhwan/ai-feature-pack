#!/usr/bin/env bash
# test_resource_reclaim.sh — R198(판정 1767) ft-resource-reclaim.sh: DA⑥ 축 ⓐ~ⓕ + 호출처 + 변이 2.
# 전부 mktemp 안 — 임시 HOME(재개 기록) · 임시 명부·카드 · 가짜 tmux/pgrep/ps/nano-close/seat-status/mbox/문지기(PATH·env) · 진짜 tmux 세션 kill 0.
# 변이: 승인 표 판정 제거(resume_ok 항상 통과) → 범위 밖 좌석 kill 단언 FAIL · 잠금 제거 → 동시 2호출 중복 kill FAIL.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
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

. "$HERE/lib/fake_reclaim_world.sh"

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

  # ── ⓕ --team (r-teamset-standard · DA r1 ⑤): 그 팀 나노만 후보(이름 접두 ∧ 팀 명부 행) — 직전 세대·역할 좌석·다른 팀 표 행 0 · 닫기 직전 소속 재확인 ──
  setup; cp "$ST/seats.json" "$ST/seats-t.json"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 1 --team t)"; rc=$?
  eq "$rc" 0 "ⓕ --team rc0"
  eq "$(awk '{print $1}' "$ST/nc.log")" "byz-t-nano-a#0" "ⓕ 그 팀 가장 오래 쉰 나노 1개만 닫음"
  eq "$(wc -l < "$ST/kill.log" | tr -d ' ')" 0 "ⓕ 접두 밖 직전 세대 kill 0 (재개 기록 있는 role#1 도 후보 아님)"
  hasnt "$out" "byz-t-role-claude" "ⓕ 접두 밖 좌석은 표 행도 0"
  hasnt "$out" "byz-t-da-codex" "ⓕ 접두 밖 codex DA 는 «승인 범위 밖» 행도 0"
  setup; cp "$ST/seats.json" "$ST/seats-zz.json"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 1 --team zz)"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "ⓕ 다른 팀(zz) 지정 = byz-t-* 닫기 0"
  has "$out" "RECLAIMED 0" "ⓕ 접두 불일치 = RECLAIMED 0"
  # 소속 재확인: 후보로 뽑힌 뒤 그 팀 명부에서 행이 빠지면(승계·정리) 닫기 직전 fresh_ok 가 거절 — 팀 명부에 a 행이 없는 세계
  setup; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[d.pop(k) for k in list(d) if k.startswith("byz-t-nano-a")];json.dump(d,open(sys.argv[2],"w"))' "$ST/seats.json" "$ST/seats-t.json"
  out="$(run "$S" --caller byz-t-master-claude#1 --need 1 --team t)"
  hasnt "$(cat "$ST/nc.log")" "byz-t-nano-a#0" "ⓕ 팀 명부에 행 없는 나노는 닫지 않음(소속 확인)"
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
