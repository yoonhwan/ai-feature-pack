#!/usr/bin/env bash
# test_goal_table_gate.sh — R362 골 표(A6) 상시 게재 문: 렌더(ⓐⓑ) · 판정기 check(ⓗ) · 쪽지 가드 문 ③(ⓔⓕⓘⓙ).
# 가짜 정본·상태 파일 + 임시 폴더의 정본 mbox*.py·mbox*.sh 사본 + 격리 큐(FT_MBOX_DIR) — 실 큐·실 doorbell(tmux 스텁)·루트 .fable-team/ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="$REPO/scripts/fable-team-bin/ft-goal-table.sh"; SRC="$REPO/tools/comm-canonical"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
CANON="$T/AUTONOMY-GOAL-A6.md"; STATE="$T/GOAL-A6-STATE.md"
cat > "$CANON" <<'EOF'
# 자율 골 A6 (시험 픽스처 — 실 정본 표 6행 복사)

## 골 → 팀 → 닫는 증거

| 골(원문) | 담당 팀 | 닫는 증거 |
|---|---|---|
| v65 마이크 넘기기 완성 | v65 (byz-v65-master) | main 착지 sha(r3 841838491b) + 라이브 확인(기존 러너 --mic-pass) |
| m.room 멀티 사용자 v65 마이그레이션 + 게스트 대화 사용성 3명 이상 | room (byz-room-master) · 설계 v65 arch | main 착지 sha + 3명 겹쳐 말하기 --overlap 4자 표(+turbopack 칸) |
| m.lecture 멀티 사용자 v65 마이그레이션 + 게스트채팅 PiP · 번역 PiP 전부 | lecture (byz-lecture-master) | main 착지 sha(N5c #1854 · N6) + 강의방 라이브 확인 |
| 하네스팀 랜딩부터 | harness (byz-harness-master) | 남은 하네스 카드 main 착지 + 라이브 설치 cmp0(ft-live-install-check OK) |
| 전팀 지침과 프로젝트 폴더 기준 재기동 | harness(지침 파일 배치) · planner(팀별 확인) | 12팀 cwd 에서 ft-teamset-check ERROR 0 + 팀별 확인 1줄 |
| 메모리 세션 제한으로 안 멈춰 있게 완성 | harness(장치) · 각 팀장(끝난 좌석 닫기) | 정지 좌석 = 승인·차례 대기만(사유 1줄) · 자원 문지기 REJECT 로 멈춘 팀 0 |
EOF
SHA="$(shasum -a 256 "$CANON" | cut -c1-10)"
mkstate() {  # <sha10> — 상태 파일(행마다 | 행번호 | 지금 상태 | 남은 것 |)
  python3 - "$CANON" "$1" > "$STATE" <<'PY'
import sys
rows = [l.split("|")[1].strip() for l in open(sys.argv[1], encoding="utf-8") if l.startswith("| ") and not l.startswith("| 골(") ]
print("# 골 표 상태\n정본 sha10: " + sys.argv[2] + "\n갱신: 2026-10-18 10:30")
for i, r in enumerate(rows, 1): print(f"| {i} | 상태{i} 진행 | 남은{i} |")
PY
}
render() { FT_GOAL_A6_MD="${CANON_OVERRIDE:-$CANON}" FT_GOAL_A6_STATE="${STATE_OVERRIDE:-$STATE}" bash "$TOOL" "$@"; }
# check_body <본문> → RC·OUT
check_body() { OUT="$(printf '%s' "$1" | render check - 2>&1)"; RC=$?; }

# ── ⓐ 렌더: 머리·6행·꼬리·900B·상태 칸
mkstate "$SHA"; BLOCK="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "ⓐ 렌더 rc0" || bad "ⓐ 렌더 rc=$RC :: $BLOCK"
printf '%s\n' "$BLOCK" | head -1 | grep -qE "^★골 표 A6 \($SHA · 상태 10:30\)★$" && ok "ⓐ 머리 마커 줄" || bad "ⓐ 머리 :: $(printf '%s' "$BLOCK" | head -1)"
printf '%s\n' "$BLOCK" | tail -1 | grep -qx '★/골 표★' && ok "ⓐ 꼬리 마커 줄" || bad "ⓐ 꼬리"
[ "$(printf '%s\n' "$BLOCK" | grep -c '^| .* | .* | .* | .* |$')" = 7 ] && ok "ⓐ 표 7줄(제목 1 + 골 6)" || bad "ⓐ 표 행 수"
printf '%s' "$BLOCK" | grep -q '상태3 진행' && ok "ⓐ 상태 칸 값 반영" || bad "ⓐ 상태 칸 값 없음"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$BLOCK" | wc -c)" -gt 100 ] && [ "$(printf '%s\n' "$BLOCK" | wc -c)" -le 1600 ] && ok "ⓐ ≤1600B" || bad "ⓐ $(printf '%s\n' "$BLOCK" | wc -c)B"
OUT="$(STATE_OVERRIDE="$T/없는상태.md" render 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | grep -o '상태 없음' | wc -l)" -ge 6 ] && ok "ⓐ 상태 파일 없음 = «상태 없음» 6칸(빈 칸 0)" || bad "ⓐ 상태 없음 rc=$RC :: $OUT"

# ── ⓑ 정본 이상 = ERROR rc1 (조용한 빈 표 0)
OUT="$(CANON_OVERRIDE="$T/없는정본.md" render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ok "ⓑ 정본 없음 ERROR rc1" || bad "ⓑ 정본 없음 rc=$RC :: $OUT"
grep -v 'harness(장치)' "$CANON" > "$T/canon5.md"
OUT="$(CANON_OVERRIDE="$T/canon5.md" render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ok "ⓑ 표 5행 ERROR rc1" || bad "ⓑ 5행 rc=$RC :: $OUT"

# ── ⓕ 상태 낡음 (상태의 sha ≠ 정본 sha)
mkstate "0000000000"; OUT="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | head -1 | grep -q '상태 낡음' && ok "ⓕ sha 불일치 머리에 «상태 낡음»" || bad "ⓕ 낡음 rc=$RC :: $(printf '%s' "$OUT" | head -1)"
mkstate "$SHA"

# ── ⓗ check 단독
GOOD="$BLOCK"$'\n골좌표: 3 — m.lecture 멀티'
check_body "$GOOD";                                    [ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK n=3'*) true;; *) false;; esac && ok "ⓗ 블록+좌표 → GOAL-OK n=3" || bad "ⓗ 정상 rc=$RC :: $OUT"
check_body "$BLOCK";                                   [ "$RC" = 3 ] && case "$OUT" in *'REJECT 골 없음'*) true;; *) false;; esac && ok "ⓗ 블록만 → REJECT" || bad "ⓗ 블록만 rc=$RC :: $OUT"
check_body $'골좌표: 3 — m.lecture 멀티';               [ "$RC" = 3 ] && ok "ⓗ 좌표만(블록 없음) → REJECT" || bad "ⓗ 좌표만 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 7 — m.lecture 멀티';     [ "$RC" = 3 ] && ok "ⓗ 번호 7(범위 밖) → REJECT" || bad "ⓗ 번호 7 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 3 — 하네스팀 랜딩부터';   [ "$RC" = 3 ] && ok "ⓗ 번호와 원문 불일치 → REJECT" || bad "ⓗ 불일치 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 3';                      [ "$RC" = 3 ] && ok "ⓗ 번호만(원문 없음) → REJECT" || bad "ⓗ 번호만 rc=$RC :: $OUT"
check_body $'★골 표 A6 (abcdef0123 · 상태 10:30)★\n| 골 | 팀 | 지금 상태 | 닫는 증거 |\n| a | b | c | d |\n★/골 표★\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓗ 블록 안 행 6 아님 → REJECT" || bad "ⓗ 행 수 rc=$RC :: $OUT"
check_body $'★/골 표★\n골좌표: 3 — m.lecture 멀티'; [ "$RC" = 3 ] && ok "ⓕ 꼬리 마커만 → REJECT" || bad "ⓕ 꼬리만 rc=$RC :: $OUT"

# ── 쪽지 가드 문 ③ — 격리 루트
new_env() {
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state" "$ENVROOT/.fable-team/bin" "$ENVROOT/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENVROOT/.fable-team/comm/"; cp "$TOOL" "$(dirname "$TOOL")/ft_goal_table.py" "$ENVROOT/.fable-team/bin/" 2>/dev/null; git -C "$ENVROOT" init -q
  echo '{"_master":"byz-planner-master-claude#9","_desk":"byz-planner-desk-claude#3","_arch":"byz-planner-arch-claude#4"}' > "$ENVROOT/seats/seats-planner.json"
  echo '{"_master":"byz-harness-master-claude#64","_arch":"byz-harness-arch-claude#81","byz-harness-nano-x#0":{"role":"nano"}}' > "$ENVROOT/seats/seats-harness.json"
  echo '{}' > "$ENVROOT/seats/seats.json"; [ "${UNARMED:-0}" = 1 ] || : > "$ENVROOT/.fable-team/state/goal-gate.armed"
}
send_from() {  # <from> <body> → RC·OUT (수신자 = 명부에 없는 나노 → 수신자 문·planner 머리 문 둘 다 비켜 간다)
  OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_STATE="$STATE" \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" send 'byz-zz-nano-q#0' "$1" "$2" 2>&1)"; RC=$?
}
queued() { local n; n="$(grep -c '"to": *"byz-zz-nano-q#0"' "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
PM='byz-planner-master-claude#9'; HM='byz-harness-master-claude#64'; HN='byz-harness-nano-x#0'
WITH="$BLOCK"$'\n골좌표: 4 — 하네스팀 랜딩부터'

# ⓔ planner 팀 발주 머리 4종 — 블록 없으면 REJECT·큐 0, 블록+좌표면 통과
for h in '[발주 #1]' '[팀 발주]' '[착지 차례]' '[A6 점검]'; do
  new_env; send_from "$PM" "$h 해라"$'\n본문'
  [ "$RC" = 3 ] && case "$OUT" in *'골 없음'*'ft-goal-table.sh'*) true;; *) false;; esac && [ "$(queued)" = 0 ] && ok "ⓔ $h 블록 없음 → REJECT·큐 0" || bad "ⓔ $h rc=$RC q=$(queued) :: $OUT"
  new_env; send_from "$PM" "$h 해라"$'\n'"$WITH"
  [ "$RC" = 0 ] && [ "$(queued)" = 1 ] && ok "ⓔ $h 블록+좌표 → 통과" || bad "ⓔ $h 통과 rc=$RC :: $OUT"
done
# ⓔ 안전 보고는 검사 밖
for h in '[HIL] 막힘' '[긴급] 중단' '[반송 · 골] 다시'; do
  new_env; send_from "$PM" "$h"$'\n본문'
  [ "$RC" = 0 ] && ok "ⓙ $h 블록 없음 → 통과(안전 보고 우선)" || bad "ⓙ $h rc=$RC :: $OUT"
done

# ⓘ 다른 팀 master — 틱·부팅도 검사 · 나노 발신은 검사 0
for h in '[틱]' '[부팅 보고]' '[완료·휴식]'; do
  new_env; send_from "$HM" "$h 보고"$'\n세션=x'
  [ "$RC" = 3 ] && case "$OUT" in *'골 없음'*) true;; *) false;; esac && ok "ⓘ harness master $h 블록 없음 → REJECT" || bad "ⓘ master $h rc=$RC :: $OUT"
done
new_env; send_from "$HN" $'[틱] 보고\n본문'
[ "$RC" = 0 ] && ok "ⓘ 나노 발신 [틱] 블록 없음 → 통과(검사 0)" || bad "ⓘ 나노 rc=$RC :: $OUT"
new_env; send_from 'byz-planner-desk-claude#3' $'[발주] x\n본문'
[ "$RC" = 3 ] && ok "ⓘ planner desk 도 대상" || bad "ⓘ desk rc=$RC :: $OUT"
new_env; send_from "$PM" "[발주 #1] 골좌표 줄 없음"$'\n'"$BLOCK"
[ "$RC" = 3 ] && ok "ⓔ 블록만(좌표 줄 없음) 발주 → REJECT" || bad "ⓔ 블록만 rc=$RC :: $OUT"

# ⓚ 실물 정본(1274B 표) — 골 원문 전문 보존 + ≤1600B
REAL="$REPO/tests/fixtures/goal_table/AUTONOMY-GOAL-A6-20261018.md"
OUT="$(CANON_OVERRIDE="$REAL" STATE_OVERRIDE="$T/없음.md" render 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | wc -c)" -le 1600 ] && ok "ⓚ 실물 정본 ≤1600B" || bad "ⓚ rc=$RC $(printf '%s\n' "$OUT" | wc -c)B :: $OUT"
full=0; while IFS= read -r g; do printf '%s' "$OUT" | grep -qF "$g" || full=1; done < <(python3 -c 'import sys;[print(l.split("|")[1].strip()) for l in open(sys.argv[1],encoding="utf-8") if l.startswith("| ") and not l.startswith("| 골(")]' "$REAL")
[ "$full" = 0 ] && ok "ⓚ 골 원문 6칸 전문 보존(절단 0)" || bad "ⓚ 골 원문 절단"

# ⓛ 비무장 = WOULD-REJECT 로그 + 통과 · 무장 = REJECT 로그
UNARMED=1 new_env; send_from "$PM" $'[발주 #1] 블록 없음\n본문'
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && grep -q 'WOULD-REJECT' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓛ 비무장: 큐 적재 + WOULD-REJECT 로그" || bad "ⓛ 비무장 rc=$RC :: $OUT"
new_env; send_from "$PM" $'[발주 #1] 블록 없음\n본문'
grep -q '^[^ ]* REJECT from=' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓛ 무장: REJECT 로그 1줄" || bad "ⓛ 무장 로그 없음"

# ⓝ relay — 첨부 사본을 검사하고 그 사본이 그대로 relay 된다
relay_from() {  # <from> <첨부 파일> <요약> → RC·OUT
  OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_STATE="$STATE" \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" relay 'byz-zz-nano-q#0' "$1" "$2" "$3" 2>&1)"; RC=$?
}
printf '%s\n본문\n' "$BLOCK" > "$T/attach-ok.md"; printf '본문만\n' > "$T/attach-no.md"
SUM=$'[발주 #2] 긴 발주\n골좌표: 4 — 하네스팀 랜딩부터'
new_env; relay_from "$PM" "$T/attach-ok.md" "$SUM"
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && ok "ⓝ relay 첨부에 블록 + 요약에 좌표 → 통과" || bad "ⓝ relay 통과 rc=$RC :: $OUT"
new_env; relay_from "$PM" "$T/attach-no.md" "$SUM"
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && ok "ⓝ relay 첨부에 블록 없음 → REJECT·큐 0" || bad "ⓝ relay 거절 rc=$RC :: $OUT"
ls "$ENVROOT/.fable-team/state/" | grep -q '^goal-relay' && bad "ⓝ relay 검사 사본 폴더 잔존" || ok "ⓝ relay 검사 사본 폴더 정리"

# ⓞ 머리 [회신·착지·정지] = 대상 밖(집행 회신·안전 보고)
for h in '[회신] 확인' '[착지] 끝' '[정지] 멈춤'; do
  new_env; send_from "$PM" "$h"$'\n본문'
  [ "$RC" = 0 ] && ok "ⓞ $h 블록 없음 → 통과" || bad "ⓞ $h rc=$RC :: $OUT"
done

# ⓟ 마커 sha10 ≠ 본문 6행 · 모르는 sha10 → REJECT
check_body "$(printf '%s' "$BLOCK" | sed 's/^| v65 마이크 넘기기 완성/| 바꾼 골 원문/')"$'\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓟ 정본과 다른 6행 + 진짜 마커 → REJECT" || bad "ⓟ 변조 rc=$RC :: $OUT"
check_body "$(printf '%s' "$BLOCK" | sed "1s/($SHA/(ffffffffff/")"$'\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓟ 모르는 마커 sha10 → REJECT" || bad "ⓟ sha rc=$RC :: $OUT"

# ⓠ H1① 문 본체 파일 없음 — 무장 = REJECT · 비무장 = WOULD-REJECT 로그 + 통과 · 비대상(나노·안전 보고)은 통과
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[발주 #1] 본문 파일 없음\n본문'
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && case "$OUT" in *'문 파일 없음'*) true;; *) false;; esac && ok "ⓠ 무장 + 문 본체 없음 → REJECT" || bad "ⓠ 무장 rc=$RC :: $OUT"
UNARMED=1 new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[발주 #1] 본문 파일 없음\n본문'
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && grep -q 'WOULD-REJECT' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓠ 비무장 + 문 본체 없음 → WOULD-REJECT 로그 + 통과" || bad "ⓠ 비무장 rc=$RC :: $OUT"
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$HN" $'[틱] 나노\n본문'
[ "$RC" = 0 ] && ok "ⓠ 문 본체 없음 + 나노 발신 → 통과(대상 아님)" || bad "ⓠ 나노 rc=$RC :: $OUT"
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[HIL] 막힘\n본문'
[ "$RC" = 0 ] && ok "ⓠ 문 본체 없음 + [HIL] → 통과(안전 보고)" || bad "ⓠ HIL rc=$RC :: $OUT"

# ⓡ H1② 명부 읽기 실패 — «대상 아님» 과 분리: 무장 = REJECT(판정 불가) · 비무장 = WOULD-REJECT · 다른 명부에서 역할이 확인되면 정상 판정
new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$HM" $'[틱] 보고\n본문'
[ "$RC" = 3 ] && case "$OUT" in *'판정 불가'*) true;; *) false;; esac && ok "ⓡ 무장 + 명부 깨짐 + 역할 미확인 → REJECT(판정 불가)" || bad "ⓡ 무장 rc=$RC :: $OUT"
UNARMED=1 new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$HM" $'[틱] 보고\n본문'
[ "$RC" = 0 ] && grep -q 'WOULD-REJECT.*판정 불가' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓡ 비무장 + 명부 깨짐 → WOULD-REJECT 로그 + 통과" || bad "ⓡ 비무장 rc=$RC :: $OUT"
new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$PM" "[발주 #1] 정상"$'\n'"$WITH"
[ "$RC" = 0 ] && ok "ⓡ 다른 명부가 깨져도 발신자 역할이 확인되면 정상 판정" || bad "ⓡ 정상 rc=$RC :: $OUT"

# ⓢ H2 relay 사본 — 복사 실패 = REJECT · 검사 뒤 원본 변경 = 사본 전달 · 요약에 골좌표 없음 = REJECT(첨부 안 좌표는 요약 대신이 아니다)
printf '%s\n본문\n' "$BLOCK" > "$T/att-unreadable.md"; chmod 000 "$T/att-unreadable.md"
new_env; relay_from "$PM" "$T/att-unreadable.md" "$SUM"
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && case "$OUT" in *'사본 생성·읽기 실패'*) true;; *) false;; esac && ok "ⓢ 첨부 사본 복사 실패 → REJECT(원본 후퇴 0)" || bad "ⓢ 복사 실패 rc=$RC :: $OUT"
chmod 644 "$T/att-unreadable.md"
printf '%s\n본문\n' "$BLOCK" > "$T/att-tamper.md"
new_env; printf '#!/usr/bin/env bash\n[ "$1" = check ] && echo TAMPER >> "%s"\nexec bash "%s" "$@"\n' "$T/att-tamper.md" "$TOOL" > "$ENVROOT/.fable-team/bin/ft-goal-table.sh"
relay_from "$PM" "$T/att-tamper.md" "$SUM"
SNAP="$(python3 -c 'import json,re,sys;l=[json.loads(x) for x in open(sys.argv[1],encoding="utf-8") if x.strip()][-1];print(re.search(r"상세\(전문\): (\S+)",l["body"]).group(1))' "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"
[ "$RC" = 0 ] && grep -q TAMPER "$T/att-tamper.md" && [ -n "$SNAP" ] && ! grep -q TAMPER "$SNAP" && ok "ⓢ 검사 뒤 원본이 바뀌어도 전달본 = 검사한 사본" || bad "ⓢ 사본 전달 rc=$RC snap=$SNAP :: $OUT"
printf '%s\n골좌표: 4 — 하네스팀 랜딩부터\n본문\n' "$BLOCK" > "$T/att-coord.md"
new_env; relay_from "$PM" "$T/att-coord.md" $'[발주 #3] 요약만 — 좌표 줄 없음'
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && ok "ⓢ 요약에 골좌표 없음(첨부 안에만 있음) → REJECT" || bad "ⓢ 요약 좌표 rc=$RC :: $OUT"

echo "fail=$fail"; [ "$fail" = 0 ]
