#!/usr/bin/env bash
# test_succession_ready_retire_r1319.sh — r1319: 승계에서 retire 를 빠뜨리면 [레디]·부팅 보고 어느 쪽에서든 기계가 REJECT 한다.
#   [레디] 관문(C1·C2) + 부팅 보고 lint 머리 판정(C3·C4) + 닫기 관문(C7) + 남은 `_*` 칸 검사(C0) + 명부 고르기(C0b) + 승계 판정(C0c) + rc4 문구(C5).
# 격리 큐(FT_MBOX_DIR) + 정본 사본 + 임시 명부 — 실 우편함·실 명부·실 doorbell(tmux 스텁)·실 재개 기록 0 · 고정 sleep 0 · push 0.
# 새 파일 = 100644(실행 비트 0 · bash 로 부른다) · 시험 1개 단독 70초 안.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub" "$T/home"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"

M_OLD='byz-harness-master-claude#32'; M_NEW='byz-harness-master-claude#33'
A_OLD='byz-harness-arch-claude#203'; A_NEW='byz-harness-arch-claude#204'
PM='byz-harness-pm-claude#1'

new_env() {   # 정본 사본 + 빈 명부 + 변이 훅(«new_env mut 3»)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$SRC"/ft-boot-report-lint.py "$C/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; : > "$Q"
  [ $# -eq 0 ] || "$@"
}
put() { cat > "$ENVROOT/seats/$1"; }   # put <파일> <<JSON … JSON
subst() { python3 - "$C/${4:-mbox_retire_check.py}" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert a in s, "변이 대상 문자열 없음: " + a
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
sh_() { OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
xenv() { env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" \
  FT_SUCCESSOR_DIR="$ENVROOT/.fable-team/state/successor" HOME="$T/home" "$@"; }
row() { printf '{"seq": %s, "ts": "2026-11-02T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
queued() { local n; n="$(grep -c . "$Q" 2>/dev/null)"; echo "${n:-0}"; }
mail() { OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" send "$1" "$2" "$3" 2>&1)"; RC=$?; }   # mail <to> <from> <본문>

# 명부 두 벌 — before = retire 전(구 행 _replaced_by 없음) · after = retire 뒤 꼴
roster_before() {
  put seats-harness.json <<JSON
{ "$M_OLD": {"role": "master"}, "$M_NEW": {"role": "master", "_replaces": ["$M_OLD"]},
  "$A_OLD": {"role": "arch"}, "$A_NEW": {"role": "arch", "_replaces": ["$A_OLD"]},
  "$PM": {"role": "pm"}, "_master": "$M_OLD" }
JSON
}
roster_after() {
  put seats-harness.json <<JSON
{ "$M_OLD": {"role": "stop-ready", "_retired_role": "master", "_replaced_by": "$M_NEW"},
  "$M_NEW": {"role": "master", "_replaces": ["$M_OLD"]},
  "$A_OLD": {"role": "stop-ready", "_retired_role": "arch", "_replaced_by": "$A_NEW"},
  "$A_NEW": {"role": "arch", "_replaces": ["$A_OLD"]},
  "$PM": {"role": "pm"}, "_master": "$M_NEW" }
JSON
}
hand_over() {   # hand_over <구> <후계> — 실제 [인계] 를 보내고 후계가 recv 한다([레디] 관문 앞 단계)
  row $((900 + RANDOM % 90)) "$1" "[HIL] 시험 질문"; sh_ recv "$1"
  sh_ handover "$1" "$2"; sh_ recv "$2"
}
ready_rc() { sh_ ready "$2" "$1"; }   # ready_rc <구> <후계>

# ── K1 retire 전 [레디] → REJECT rc3 · [레디] 쪽지 0
k1() { new_env "$@"; roster_before; hand_over "$M_OLD" "$M_NEW"; local n; n="$(queued)"
  ready_rc "$M_OLD" "$M_NEW"
  [ "$RC" = 3 ] && case "$OUT" in *'retire 먼저'*"$M_OLD"*) true;; *) false;; esac && [ "$(queued)" = "$n" ]; }
k1 && ok "K1 retire 전 [레디] → REJECT rc3 «retire 먼저» · 쪽지 0" || bad "K1 rc=$RC :: $OUT"

# ── K2 retire 뒤 [레디] → QUEUED (지금처럼)
k2() { new_env "$@"; roster_after; hand_over "$M_OLD" "$M_NEW"; local n; n="$(queued)"
  ready_rc "$M_OLD" "$M_NEW"
  [ "$RC" = 0 ] && [ "$(queued)" = "$((n + 1))" ]; }
k2 && ok "K2 retire 뒤 [레디] → QUEUED 1통" || bad "K2 rc=$RC :: $OUT"

# ── K3 새 좌석(승계 아님 · #11 _closed · _replaces []) → 부팅 lint 승계 검사 0
k3() { new_env "$@"; local P='byz-ops-tester'
  put seats-ops.json <<JSON
{ "byz-ops-tester-claude#11": {"role": "tester", "_closed": "2026-11-01T00:00:00Z"},
  "byz-ops-tester-claude#12": {"role": "tester", "_replaces": []}, "$PM": {"role": "pm"} }
JSON
  mail "$PM" "$P#12" "[부팅] $P#12 시작 — 부팅 보고 아님(칸 없음)"; [ "$RC" = 0 ]; }
k3 && ok "K3 새 좌석(#11 _closed · _replaces []) 부팅 보고 → 승계 검사 0 · 전송" || bad "K3 rc=$RC :: $OUT"

# ── K4 첫 줄 «[HIL] 부팅 끝: <내 이름> …» retire 칸 없음 → lint REJECT (desk#97 실사고 꼴)
k4() { new_env "$@"; roster_after
  mail "$PM" "$A_NEW" "[HIL] 부팅 끝: $A_NEW 진행 중 — retire 칸 없음"; [ "$RC" = 3 ]; }
k4 && ok "K4 «[HIL] 부팅 끝: <내 이름>» retire 칸 없음 → REJECT rc3" || bad "K4 rc=$RC :: $OUT"

# ── K5 둘째 줄 «[부팅] <내 이름>» (첫 줄 = 골좌표) → 앞 3줄 조각 판정으로 lint 실행
k5() { new_env "$@"; roster_after
  mail "$PM" "$A_NEW" "골좌표: 5 — 세션 생명주기
[부팅] $A_NEW 시작 · retire 칸 없음"; [ "$RC" = 3 ]; }
k5 && ok "K5 «골좌표» + 둘째 줄 «[부팅] <내 이름>» → REJECT rc3" || bad "K5 rc=$RC :: $OUT"

# ── K6 «부팅» 글자가 넷째 줄 뒤에만 → lint 0 · 전송 (앞 3줄 제한)
k6() { new_env "$@"; roster_after
  mail "$PM" "$A_NEW" "일반 쪽지 1
일반 쪽지 2
일반 쪽지 3
[부팅 보고] $A_NEW 는 본문 아래 · retire 없음"; [ "$RC" = 0 ]; }
k6 && ok "K6 넷째 줄 뒤 «부팅» → lint 0 · 전송" || bad "K6 rc=$RC :: $OUT"

# ── K7 다른 명부 `_hil_route`(문자열)에 구 이름이 남음 → [레디] REJECT + 부팅 lint REJECT
k7() { new_env "$@"; roster_after
  put seats-planner.json <<JSON
{ "_hil_route": "$A_OLD", "_master": "byz-planner-master-claude#9" }
JSON
  hand_over "$A_OLD" "$A_NEW"; ready_rc "$A_OLD" "$A_NEW"
  [ "$RC" = 3 ] && case "$OUT" in *"seats-planner.json:_hil_route"*) true;; *) false;; esac || return 1
  mail "$PM" "$A_NEW" "[부팅 보고] $A_NEW retire=$A_OLD->$A_NEW rc=0 cron=c0ffee00 남은 칸 시험"
  [ "$RC" = 3 ] && case "$OUT" in *'남음'*'_hil_route'*) true;; *) false;; esac; }
k7 && ok "K7 다른 명부 `_hil_route` 에 구 이름 → [레디]·lint 둘 다 REJECT(파일:칸)" || bad "K7 rc=$RC :: $OUT"

# ── K8 ft-seat-retire rc4 문구 = 후계 pane 에서 handover && retire 한 줄 (C5)
k8() { new_env "$@"; roster_before
  row 1 "$M_OLD" "[HIL] 미표시 질문"; sh_ recv "$M_OLD"   # 영수 미표시 → close-check --no-ready rc3 → rc4
  OUT="$(cd "$ENVROOT" && xenv bash "$BIN/ft-seat-retire.sh" "$M_OLD" "$M_NEW" --seats "$ENVROOT/seats/seats-harness.json" 2>&1)"; RC=$?
  [ "$RC" = 4 ] && case "$OUT" in *"bash mbox.sh handover $M_OLD $M_NEW && bash ft-seat-retire.sh $M_OLD $M_NEW"*) true;; *) false;; esac; }
k8 && ok "K8 retire rc4 문구에 C5 한 줄 명령(handover && retire)" || bad "K8 rc=$RC :: $OUT"

# ── K9 명부 읽기 실패 = 판정 불가 rc≠0 · 부팅 보고 REJECT (하드 룰 20 · fail-closed · 받는 쪽 명부는 멀쩡)
k9() { new_env "$@"; roster_after; printf '{"broken": ' > "$ENVROOT/seats/seats-knowledge.json"
  mail "$PM" 'byz-knowledge-master-claude#77' "[부팅 보고] byz-knowledge-master-claude#77 시작"
  [ "$RC" = 3 ] && case "$OUT" in *'판정 불가'*'하드 룰 20'*) true;; *) false;; esac; }
k9 && ok "K9 발신 좌석 명부 읽기 실패 → 판정 불가 rc3 · 부팅 보고 REJECT" || bad "K9 rc=$RC :: $OUT"

# ── K10 1행 «골좌표: 5 — … · [부팅 보고] arch#204 / …» → 조각 판정으로 lint 실행 (#225848 꼴)
k10() { new_env "$@"; roster_after
  mail "$PM" "$A_NEW" "골좌표: 5 — 세션 생명주기 · [부팅 보고] $A_NEW / retire 칸 없음 · 항목 3"; [ "$RC" = 3 ]; }
k10 && ok "K10 1행 «골좌표 · [부팅 보고] arch#204» → REJECT rc3" || bad "K10 rc=$RC :: $OUT"

# ── K11 «[정리] 골좌표 … · 부팅 완료: <내 이름> …» → 조각 머리 «부팅 완료» 로 lint 실행
k11() { new_env "$@"; roster_after
  mail "$PM" "$A_NEW" "[정리] 골좌표 5 — 세션 · 부팅 완료: $A_NEW (retire 칸 없음)"; [ "$RC" = 3 ]; }
k11 && ok "K11 «[정리] … · 부팅 완료: <내 이름>» → REJECT rc3" || bad "K11 rc=$RC :: $OUT"

# ── K12 [인계] 보낸 구 · 후계 행 있음 · retire 0 · close-check(면제 없이) → REJECT «retire 먼저» · --verdict = 면제
k12() { new_env "$@"; roster_before; hand_over "$M_OLD" "$M_NEW"
  py close-check "$M_OLD"; [ "$RC" = 3 ] && case "$OUT" in *'retire 먼저'*) true;; *) false;; esac || return 1
  py close-check "$M_OLD" --verdict; [ "$RC" = 0 ] && case "$OUT" in *'retire 먼저'*) false;; *) true;; esac; }
k12 && ok "K12 close-check = retire 먼저 REJECT · --verdict = C7 면제" || bad "K12 rc=$RC :: $OUT"

# ── K13 이름 바꾼 팀 좌석(seats-chatbot.json · _renamed_from) 행 고르기 = C0b (조용한 WARN 통과 0)
k13() { new_env "$@"; local S='byz-concierge-da-codex#1'
  put seats-chatbot.json <<JSON
{ "_renamed_from": "concierge", "_da": "$S", "$S": {"role": "da", "_replaces": ["byz-concierge-da-codex#0"]},
  "$PM": {"role": "pm"} }
JSON
  mail "$PM" "$S" "[부팅 보고] $S 시작"; [ "$RC" = 3 ] && case "$OUT" in *'retire 칸 없음'*) true;; *) false;; esac; }
k13 && ok "K13 이름 바꾼 팀 좌석 → C0b 로 seats-chatbot.json 선택(승계 판정됨 · 칸 없음 REJECT)" || bad "K13 rc=$RC :: $OUT"

# ── K14 메모 칸에 «부분 문자열» 로 남은 자기 이름(…#97 vs …#98) → 정확히 같음이라 REJECT 0
k14() { new_env "$@"; local D='byz-planner-desk-claude#97' N='byz-planner-desk-claude#98'
  put seats-planner.json <<JSON
{ "_hil_route": "$N", "_memo": "$D 은퇴 완료(칸 글자)",
  "$D": {"role": "stop-ready", "_retired_role": "desk", "_replaced_by": "$N"},
  "$N": {"role": "desk", "_replaces": ["$D"]} }
JSON
  hand_over "$D" "$N"; ready_rc "$D" "$N"; [ "$RC" = 0 ]; }
k14 && ok "K14 메모 칸 «…#97» 글자 = 정확히 같음 아님 → REJECT 0 · QUEUED" || bad "K14 rc=$RC :: $OUT"

# ── K15 남의 부팅 보고를 언급한 쪽지(실데이터 꼴 3건) → lint 0 · 전송
k15() { new_env "$@"; roster_after
  local b
  for b in "[정리] #226731 회신 · 부팅 보고 받음" \
           "[정리] 부팅 보고에 retire rc 칸 부탁 · $PM 몫" \
           "[정리] 부팅 보고에 cron=<job id> 를 적는 규칙(BOOT 16) 안내"; do
    mail "$PM" "$A_NEW" "$b"; [ "$RC" = 0 ] || return 1
  done; }
k15 && ok "K15 남의 부팅 보고를 언급한 쪽지 3건 → lint 0 · 전송" || bad "K15 rc=$RC :: $OUT"

# ── K16 새로 연 좌석의 [부팅] (#219823 ops-tester#12 · #219578 chatbot-tester#10) → 승계 아님 · 전송
k16() { new_env "$@"
  put seats-harness.json <<JSON
{ "$PM": {"role": "pm"} }
JSON
  put seats-ops.json <<JSON
{ "byz-ops-tester-claude#11": {"role": "tester", "_closed": "2026-11-01T00:00:00Z"},
  "byz-ops-tester-claude#12": {"role": "tester", "_replaces": []} }
JSON
  put seats-chatbot.json <<JSON
{ "byz-chatbot-tester-claude#9": {"role": "tester"}, "byz-chatbot-tester-claude#10": {"role": "tester", "_replaces": []} }
JSON
  mail "$PM" 'byz-ops-tester-claude#12' "[부팅] byz-ops-tester-claude#12 시작"; [ "$RC" = 0 ] || return 1
  mail "$PM" 'byz-chatbot-tester-claude#10' "[부팅] byz-chatbot-tester-claude#10 시작"; [ "$RC" = 0 ]; }
k16 && ok "K16 새 좌석 [부팅] 2건 → 승계 아님 · retire 검사 0 · 전송" || bad "K16 rc=$RC :: $OUT"

# ── K17 후계 개설 실패(후계 행 없음) = C7 면제 · 후계 행 있고 retire 0 = --verdict 로만 닫힘(ft-seat-close 가 플래그를 넘긴다)
k17() { new_env "$@"; roster_before
  hand_over "$M_OLD" 'byz-harness-master-claude#90'   # 후계 행 없음
  py close-check "$M_OLD"; [ "$RC" = 0 ] || return 1
  hand_over "$M_OLD" "$M_NEW"; py close-check "$M_OLD"
  [ "$RC" = 3 ] && case "$OUT" in *'retire 먼저'*) true;; *) false;; esac || return 1
  OUT="$(cd "$ENVROOT" && xenv bash "$BIN/ft-seat-close.sh" "$M_OLD" --reason "시험" --verdict 3220 --seats "$ENVROOT/seats/seats-harness.json" 2>&1)"; RC=$?
  case "$OUT" in *'retire 먼저'*) false;; *) true;; esac; }
k17 && ok "K17 후계 행 없음 = C7 면제(닫힘) · retire 0 = REJECT · --verdict 닫기 = 면제 · ft-seat-close 가 플래그를 넘긴다" || bad "K17 rc=$RC :: $OUT"

# ── K18 좌석 행이 teamfile 아닌 파일(byz-v65-tester-claude#34 → seats-knowledge.json) · retire 끝 → [레디] QUEUED · 닫기 C7 오판 0
k18() { new_env "$@"; local O='byz-v65-tester-claude#34' N='byz-v65-tester-claude#35'
  put seats-knowledge.json <<JSON
{ "$O": {"role": "stop-ready", "_retired_role": "tester", "_replaced_by": "$N"},
  "$N": {"role": "tester", "_replaces": ["$O"]}, "$PM": {"role": "pm"} }
JSON
  hand_over "$O" "$N"; ready_rc "$O" "$N"; [ "$RC" = 0 ] || return 1
  py close-check "$O"; [ "$RC" = 0 ] && case "$OUT" in *'retire 먼저'*) false;; *) true;; esac; }
k18 && ok "K18 teamfile 아닌 명부(seats-knowledge.json) 좌석 → [레디] QUEUED · 닫기 C7 오판 0" || bad "K18 rc=$RC :: $OUT"

# ── K19 arch·master 승계 [부팅] 에 지시·배정 칸 없음 → lint REJECT (BOOT 발주 계약 · 의도한 범위)
k19() { new_env "$@"; roster_after
  mkdir -p "$ENVROOT/seats/state/directive-watch" "$ENVROOT/seats/state/card-assign"
  printf '%s\t0\t0\n' "$(date +%s)-0000abcd" > "$ENVROOT/seats/state/directive-watch/stamps.tsv"
  printf '%s\t0\t0\t0\tabcd\n' "$(date +%s)-0000abcd" > "$ENVROOT/seats/state/card-assign/stamps.tsv"
  mail "$PM" "$A_NEW" "[부팅 보고] $A_NEW retire=$A_OLD->$A_NEW rc=0 cron=c0ffee00"; [ "$RC" = 3 ] && case "$OUT" in *'지시 칸'*|*'배정'*) true;; *) false;; esac; }
k19 && ok "K19 arch 승계 부팅 보고에 지시·배정 칸 없음 → REJECT rc3" || bad "K19 rc=$RC :: $OUT"

# ── check-drift 감시 목록 — 새 모듈이 빠지면 한쪽만 깔려도 아무도 모른다(전 좌석 send·recv ImportError 가 무증상)
D="$T/drift"; mkdir -p "$D/tools/comm-canonical" "$D/.fable-team/comm"
cp "$SRC/check-drift.sh" "$SRC/mbox_retire_check.py" "$D/tools/comm-canonical/"; cp "$SRC/mbox_retire_check.py" "$D/.fable-team/comm/"
drift_row() { bash "$D/tools/comm-canonical/check-drift.sh" 2>&1 | grep -E ' mbox_retire_check\.py( |$)'; }
case "$(drift_row)" in SAME*) ok "check-drift 감시: mbox_retire_check.py SAME";; *) bad "check-drift 감시 행 없음/불일치 :: $(drift_row)";; esac
printf '#\n' >> "$D/.fable-team/comm/mbox_retire_check.py"
case "$(drift_row)" in DRIFT*) ok "check-drift 감시: 1바이트 변경 = DRIFT";; *) bad "check-drift DRIFT 아님 :: $(drift_row)";; esac
cp "$SRC/mbox_retire_check.py" "$D/.fable-team/comm/mbox_retire_check.py"
case "$(drift_row)" in SAME*) ok "check-drift 감시: 원복 = SAME";; *) bad "check-drift 원복 후 SAME 아님 :: $(drift_row)";; esac

# ── 변이 11종 — 각각 그 반례 하나를 빨강으로 만들어야 한다(변이는 사본에만 · 원본 무변경 · 대상 문자열 없으면 실패로 보인다)
mut() { case "$1" in
  1) subst 1 'if row.get("_replaced_by") != new:' 'if False:';;                                  # C1 ready retire 검사 제거 → K1
  2) subst 1 '    if left:' '    if False:';;                                                     # C0 남은 칸 검사 제거 → K7
  3) subst 1 'def is_boot_report(body, me):   # C3' 'def is_boot_report(body, me):   # C3 (변이: 옛 첫 줄 판정)'; \
     subst 1 '    return any(_head_ok(LEAD.sub("", p.strip()).strip(), me) for ln in lines for p in ln.split(" · "))' \
               '    return (first.startswith("[") and first.endswith("]") and "부팅 보고" in first) or first.startswith("부팅 보고")';;   # C3 조각 판정 제거 → K4·K5·K10
  4) subst 1 'lines = (body or "").split("\n")[:3]' 'lines = (body or "").split("\n")';;           # 앞 3줄 제한 제거 → K6
  5) subst 1 'g = None if verdict else mbox_retire_check.close_gate(seat)' 'g = None' mbox_handover.py;;            # C7 제거 → K12
  6) subst 1 'isinstance(val, str) and val == old' 'isinstance(val, str) and old in val';;        # 정확히 같음 → 부분 문자열 → K14
  7) subst 1 '    *) echo "REJECT 부팅 보고 판정 불가 rc=$rc — ${res#REJECT } (하드 룰 20 — 확인 못 하면 통과가 아니다)" >&2; return 3;;   # r1319 C4·C6 fail-closed' \
               '    *) echo "WARN 판정 불가 — 검사 없이 전송" >&2; return 0;;' mbox_guard.sh;;                   # rc≠0 REJECT 를 WARN 전송으로 → K9
  8) subst 1 '            if (me and me in tail) or (num and num in tail):' '            if True:';;                 # 40자 안 이름 조건 제거 → K15
  9) subst 1 '    if isinstance(row, dict) and row.get("_replaces"):' \
               '    m0 = re.match(r"^(.+)#(\d+)$", seat or "")
    if m0 and isinstance(doc.get(m0.group(1) + "#" + str(int(m0.group(2)) - 1)), dict):
        return True, ""
    if isinstance(row, dict) and row.get("_replaces"):';;                                     # 승계 판정을 «X#N-1 행 있음» 으로 → K16
  10) subst 1 'g = None if verdict else mbox_retire_check.close_gate(seat)' 'g = mbox_retire_check.close_gate(seat)' mbox_handover.py;;   # C7 면제 제거 → K17
  11) subst 1 '    if cand:' '    if False:';;                                                    # 구 행 고르기를 teamfile 만 → K18
  *) echo "unknown mut $1" >&2; return 1;;
  esac; }
mtest() { if "$2" mut "$1" >/dev/null 2>&1; then bad "변이 $1 → $3 가 안 잡힘(초록)"; else ok "변이 $1 → $3 빨강 확인"; fi; }
mtest 1 k1 K1; mtest 2 k7 K7; mtest 3 k4 K4; mtest 3 k5 K5; mtest 3 k10 K10; mtest 4 k6 K6
mtest 5 k12 K12; mtest 6 k14 K14; mtest 7 k9 K9; mtest 8 k15 K15; mtest 9 k16 K16
mtest 10 k17 K17; mtest 11 k18 K18

# ── 문법·크기·새 시험 파일 모드
bash -n "$SRC/mbox_guard.sh" && ok "bash -n mbox_guard.sh" || bad "bash -n mbox_guard.sh"
for f in "$SRC/mbox_retire_check.py" "$SRC/mbox_handover.py" "$SRC/mbox.py" "$SRC/ft-boot-report-lint.py"; do
  python3 -m py_compile "$f" 2>/dev/null && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")"
done
for f in mbox_retire_check.py mbox_handover.py ft-boot-report-lint.py; do
  n="$(wc -l < "$SRC/$f")"; [ "$n" -le 200 ] && ok "$f ≤200줄($n)" || bad "$f 줄수 $n"
done
[ "$(git -C "$REPO" ls-files -s -- "harness/tests/test_succession_ready_retire_r1319.sh" | cut -d' ' -f1)" = 100644 ] \
  && ok "새 시험 파일 모드 100644" || bad "새 시험 파일 모드(100644 아님 또는 미추가)"
[ -x "$HERE/test_succession_ready_retire_r1319.sh" ] && bad "새 시험에 실행 비트가 붙었다" || ok "새 시험 실행 비트 0"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
