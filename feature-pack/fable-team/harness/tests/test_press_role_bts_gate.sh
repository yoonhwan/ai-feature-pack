#!/usr/bin/env bash
# test_press_role_bts_gate.sh — R15 카드 H: press 게이트 ⑦ 좌석 역할 · ⑧ 직전 회차 BTS 표 · 허가 파일.
#   SELFTEST(⑥⑦⑧ 만 실제) + FT_PRESS_SEAT + mktemp 의 EVID·PERMIT_DIR 로만 돈다 — 리포 파일 쓰기 0 · 오디오·tmux 0(가짜 tmux 는 PATH 스텁).
#   전 케이스 «ft-press-gate.sh 최종 exit» 단언: SELFTEST 성공 = 3 · 막힘 = 1.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../../harness/bin/ft-press-gate.sh"
fail=0; n=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"

REAL_BEFORE="$(git -C "$HERE/../.." status --porcelain)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/worker" "$R/design/v65/baselines/ev" "$T/root/.fable-team" "$T/permits"
mkdir -p "$T/root/.fable-team/state"   # r626 DA⑥ r2: 상태 폴더 없음 = 전팀 정지 — 픽스처 루트에 빈 상태 폴더(원장·상태 파일 없음 = 꺼짐)
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$T/root/.fable-team/state"/all-stop.log   # r626 r4: 원장 없음 = 전팀 정지 — 설치가 남기는 init 줄(꺼짐)
echo '{}' > "$T/root/.fable-team/seats.json"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/worker/a.py"
printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/design/v65/baselines/FLAGS.md"
# r537: ⑥ 기준선 검사가 팀 명단(design/TEAMS.md · R383)으로 v65 폴더를 푼다 — 임시 리포에 최소 명단
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
git -C "$R" add -A && git -C "$R" commit -qm base
SHA="$(git -C "$R" rev-parse HEAD)"
printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"run-1","failed":true}\n' "$SHA" > "$R/design/v65/baselines/ev/RESULT-ok.json"
{ echo "set_sha: $SHA"; echo "control: lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=1"
  echo "side_lang: right=ko left=en"; echo "server_ready: 2026-10-07T03:00:00Z"; echo "visible_at_settle: yes"
  echo "evidence: design/v65/baselines/ev/RESULT-ok.json"; echo "run_id: run-1"; printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n'; } > "$R/design/v65/baselines/ok.md"
printf '# 카드 c-ok\n기준선: design/v65/baselines/ok.md\n실험: 없음\n' > "$R/card.md"
mkdir -p "$T/fakebin"   # 가짜 tmux: 세션명 = $FAKE_TMUX_SESSION
printf '#!/bin/sh\n[ -n "$FAKE_TMUX_SESSION" ] || exit 1\necho "$FAKE_TMUX_SESSION"\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"

gate() { # [env…] → 최종 exit · 출력 $OUT (FT_PRESS_SEAT·TMUX_PANE·HUMAN 은 기본 제거)
  OUT="$(env -u FT_PRESS_SEAT -u TMUX_PANE -u BYZ_PRESS_HUMAN -u FT_PRESS_EVID -u FT_PRESS_GATE_SELFTEST \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$T/root" FT_PRESS_CARD="$R/card.md" FT_PRESS_PERMIT_DIR="$T/permits" \
    FT_PRESS_GATE_SELFTEST=1 PATH="$T/fakebin:$PATH" "$@" bash "$GATE" 2>&1)"; }
expect() { # 기대exit 출력패턴 설명 [env…]
  local want="$1" pat="$2" desc="$3"; shift 3; n=$((n+1)); gate "$@"; local got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$OUT" | grep -q -- "$pat" && ! printf '%s' "$OUT" | grep -q '발화해도 된다'; then ok "$n. $desc (exit $got)"
  else bad "$n. $desc (exit $got want $want)"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}
ev() { echo "$T/ev-$1"; }

# ⑦ 좌석 역할
expect 3 '⑦ 역할 tester'  "역할 tester → 통과"   FT_PRESS_SEAT='byz-v65-tester-claude#0' FT_PRESS_EVID="$(ev a)"
expect 3 '⑦ 역할 checker' "역할 checker → 통과"  FT_PRESS_SEAT='byz-v65-checker-claude#2' FT_PRESS_EVID="$(ev b)"
expect 3 '⑦ 역할 tester'  "옛 형식 ft-v65-tester-… → 통과" FT_PRESS_SEAT='ft-v65-tester-claude#1' FT_PRESS_EVID="$(ev c)"
expect 1 '⑦ 역할 nano — press 는 tester·checker 만(R15)' "역할 nano → 막힘" FT_PRESS_SEAT='byz-harness-nano-r15-gate#0' FT_PRESS_EVID="$(ev d)"
expect 1 '⑦ 역할 temp'   "ft-v65-temp-x#0 → 막힘" FT_PRESS_SEAT='ft-v65-temp-x#0' FT_PRESS_EVID="$(ev e)"
expect 1 '⑦ 역할 master' "역할 master → 막힘" FT_PRESS_SEAT='byz-harness-master-claude#10' FT_PRESS_EVID="$(ev f)"
expect 1 '⑦ 역할 .* 이름 형식 불일치' "형식 불일치 → 막힘" FT_PRESS_SEAT='tester' FT_PRESS_EVID="$(ev g)"
expect 1 '⑦ 좌석 이름을 알 수 없다' "FT_PRESS_SEAT·TMUX_PANE 둘 다 없음 → 막힘(fail-closed)" FT_PRESS_EVID="$(ev h)"
expect 1 '⑦ 좌석 이름을 알 수 없다' "TMUX_PANE 있으나 tmux 조회 실패 → 막힘" TMUX_PANE=%1 FT_PRESS_EVID="$(ev i)"
expect 3 '⑦ 역할 tester' "TMUX_PANE 세션명 tester → 통과" TMUX_PANE=%1 FAKE_TMUX_SESSION='byz-v65-tester-claude#0' FT_PRESS_EVID="$(ev j)"
# FT_PRESS_SEAT 는 SELFTEST 전용 — 보통 모드에서는 읽지 않고 «있기만 해도» 막는다(① 이 서버 없이도 돌도록 판정은 문구 grep + exit≠0)
n=$((n+1))
OUT="$(env -u FT_PRESS_GATE_SELFTEST -u TMUX_PANE -u BYZ_PRESS_HUMAN FT_PRESS_WT="$R" FT_PRESS_ROOT="$T/root" FT_PRESS_CARD="$R/card.md" \
  FT_PRESS_PERMIT_DIR="$T/permits-normal" FT_PRESS_EVID="$(ev norm)" FT_PRESS_SEAT='byz-v65-tester-claude#0' PATH="$T/fakebin:$PATH" bash "$GATE" 2>&1)"; got=$?
[ "$got" -ne 0 ] && printf '%s' "$OUT" | grep -q '⑦ 시험 변수 상속' && ! printf '%s' "$OUT" | grep -q '발화해도 된다' && [ ! -e "$T/permits-normal" ] \
  && ok "$n. 보통 모드 + FT_PRESS_SEAT=tester 이름 → ⑦ 시험 변수 상속 막힘 · 허가 0 (exit $got)" || { bad "$n. 보통 모드 FT_PRESS_SEAT (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# SELFTEST 에서는 FT_PRESS_SEAT 를 계속 읽는다(위 ⑦ 전 사례가 그 증거 — 여기서는 상속 막힘 문구가 «없음» 을 한 번 더 단언)
n=$((n+1)); gate FT_PRESS_SEAT='byz-v65-tester-claude#0' FT_PRESS_EVID="$(ev selftest-ok)"; got=$?
[ "$got" -eq 3 ] && ! printf '%s' "$OUT" | grep -q '시험 변수 상속' && ok "$n. SELFTEST + FT_PRESS_SEAT → 통과(상속 막힘 문구 없음) (exit $got)" || { bad "$n. SELFTEST FT_PRESS_SEAT (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# 사람 직접 press
expect 3 'ERROR: BYZ_PRESS_HUMAN' "BYZ_PRESS_HUMAN=1 (좌석 아님) → 통과 + ERROR 배너" BYZ_PRESS_HUMAN=1 FT_PRESS_EVID="$(ev k)"
expect 1 '사람 행세' "BYZ_PRESS_HUMAN=1 + 좌석 세션(TMUX_PANE) → 막힘" BYZ_PRESS_HUMAN=1 TMUX_PANE=%1 FAKE_TMUX_SESSION='byz-harness-nano-x-claude#0' FT_PRESS_EVID="$(ev l)"
# ⑧ BTS 표
expect 1 '⑧ 증거 폴더 미지정' "FT_PRESS_EVID 없음 → 막힘" FT_PRESS_SEAT='byz-v65-tester-claude#0'
n=$((n+1)); rm -rf "$(ev first)"
gate FT_PRESS_SEAT='byz-v65-tester-claude#0' FT_PRESS_EVID="$(ev first)"; got=$?
[ "$got" -eq 3 ] && printf '%s' "$OUT" | grep -q '⑧ 첫 회차' && [ -f "$(ev first)/BTS.md" ] && grep -q '^| 화면 |' "$(ev first)/BTS.md" \
  && ok "$n. 직전 허가 없음 → 통과 + 골격 BTS.md 생성 (exit $got)" || { bad "$n. 첫 회차 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

SEATX='byz-v65-tester-claude#0'
prev() { # 이름 BTS본문 → 직전 허가(SEATX)가 그 증거 폴더를 가리키게
  mkdir -p "$(ev $1)"; printf '%s\n' "$2" > "$(ev $1)/BTS.md"
  printf '{"seat":"%s","role":"tester","evid":"%s"}\n' "$SEATX" "$(ev $1)" > "$T/permits/$SEATX.json"; }
HDR='| 축 | 사실 | 시간 |
|---|---|---|'
FULL="$HDR
| 아키텍처 문서 | PLAN ② 읽음 | 10:01 |
| 코드 | ft-press-gate.sh:31 | 10:02 |
| 로그 | worker finalized 12 | 10:03 |
| 화면 | poller 최종 스냅 | 10:04 |"
prev ok "$FULL"
expect 3 '⑧ 직전 회차 BTS 표 4행 완료' "직전 evid BTS 4행 다 참 → 통과" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur1)"
prev nofront "$HDR
| 아키텍처 문서 | PLAN ② | 10:01 |
| 코드 | gate.sh:31 | 10:02 |
| 로그 | finalized 12 | 10:03 |
| 화면 |  |  |"
expect 1 '모자란 칸: 화면' "화면 행 빈칸 → 막힘" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur2)"
prev dash "$HDR
| 아키텍처 문서 | PLAN ② | 10:01 |
| 코드 | gate.sh:31 | - |
| 로그 | finalized 12 | 10:03 |
| 화면 | poller | 10:04 |"
expect 1 '모자란 칸: 코드' "시간 칸 '-' → 막힘" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur3)"
prev norow "$HDR
| 아키텍처 문서 | PLAN ② | 10:01 |
| 코드 | gate.sh:31 | 10:02 |
| 화면 | poller | 10:04 |"
expect 1 '모자란 칸: 로그' "로그 행 없음 → 막힘" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur4)"
prev nohdr '| 아키텍처 문서 | a | 1 |
| 코드 | b | 2 |
| 로그 | c | 3 |
| 화면 | d | 4 |'
expect 1 '모자란 칸: 표머리' "표 머리 없음 → 막힘" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur5)"
printf '{"seat":"%s","role":"tester","evid":"%s"}\n' "$SEATX" "$T/gone" > "$T/permits/$SEATX.json"
expect 1 '⑧ 직전 회차 BTS.md 없음' "직전 허가의 BTS.md 파일 없음 → 막힘" FT_PRESS_SEAT="$SEATX" FT_PRESS_EVID="$(ev cur6)"

# 허가 파일: SELFTEST 에서는 쓰지 않는다(위 전 케이스를 돌린 뒤에도 새 파일 0 — 손으로 만든 SEATX.json 하나뿐)
n=$((n+1)); cnt="$(ls "$T/permits" | wc -l | tr -d ' ')"
[ "$cnt" = "1" ] && [ ! -e "$T/permits/permits.log" ] && ok "$n. SELFTEST 허가 파일 0개 발급(손으로 둔 것 1개뿐 · permits.log 없음)" || { bad "$n. SELFTEST 가 허가 파일을 썼다 (files=$cnt)"; ls "$T/permits"; }
n=$((n+1)); [ "$(git -C "$HERE/../.." status --porcelain)" = "$REAL_BEFORE" ] && ok "$n. 실제 리포 파일 쓰기 0(시험 전후 git status 동일)" || bad "$n. 실제 리포가 바뀌었다"

echo "cases=$n fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
