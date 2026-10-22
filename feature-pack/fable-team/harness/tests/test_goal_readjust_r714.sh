#!/usr/bin/env bash
# test_goal_readjust_r714.sh — 골 «하루 두 번 재조정» 회차 수집기(r714a · 설계 DESIGN-goal-daily-readjust-20261022 r3 §1~§9) 시험.
#   ⓐ 빨강(장치 없는 판 = 머리에 «재조정» 0) ⓑ 첫 회차(baseline null · 전 행 «기준» · 쪽지 0) ⓒ 행별 움직임(카드 1 · 다른 절 수정은 원장 행 변화 0)
#   ⓓ 마감 문법 «✅ 시작»·오탐 2종·쓰기 0(git status·refs/heads 불변) ⓔ 24시간 미만 무변화(`변화 0(7시간)`) ⓕ 닫힘 후보·[결정] 1통·mbox_guard reject 통과·claimed 선점이 송신 «전»
#   ⓖ 정본 밖 골 파일 2(제안 ID 0) ⓗ 송신 뒤 중단·timeout → 재실행 송신 0 + «송신 상태 모름» ⓘ 같은 run 재실행 = 측정값 동일·첫 파일 불변 ⓙ 실패 보존·머리(ERROR 뒤에도 ok= 보존 · [긴급] 1통 · 30시간 «재조정 없음»)
#   ⓚ 골 교체 3회차(전문 해시로 잡음 · r702 미착지 = «대응 유지 모름» · 표식 픽스처 = «확인 불가») ⓛ 수집·표시 사이 정본 교체 = `모름(판 다름)` ⓜ 저장소별 commit·디스크 삭제 무관
#   ⓝ 하네스 ref 미정 = harness 행만 «모름» ⓞ 모름 글자 4종 구분 ⓟ 동시 2건 = busy SKIP 1 ⓠ 뉴스 3파일 diff 0 ⓡ r668 회귀·kit↔harness/bin cmp0·예산 ⓢ 변이 6 ⓣ 첫 공지 보존
#   ★오빠 10-22 정정(슬랙 1792637646 «하루 두번인데 내가 요청할때. 안할때는 그냥 넘어감»)★ ⓤ 자동 시계 0(launchd·install.sh --launchd-new 없음 · 요청 없는 날 회차 0) · 하루 최대 2회 상한(3번째 요청 = REJECT rc2)
#   ★DA⑥ r1 HOLD 14건(arch 122 · evidence/r714a-da6)★ ⓥ H1 회차 불변(보고서만 쓴 회차 재실행) · H2 모름 지속 · H3 26시간 뒤 ok= 보존 · H4 기준 행 정본 대조 · H5 하네스 하위 폴더+fetch · H6 입력 commit 고정 · H7 손상·빈 표식/r714c·r701 모름 · H8 송신 실패 rc3+머리 · H9 골좌표 절 정규식·측정 예외=ERROR · H10 측정 중 예산 · H11 bin 쓰기 0(python3 -B) · H12 request 칸 · H13 무효 LIVE_ROOT=ERROR · H14 = ⓢ②·ⓢ④·ⓣ 갱신
#   ★DA⑥ r2 HOLD 작은 고침 5개(arch 122 · evidence/r714a-da6/PACKET-r714a-after-2hold.md)★ ⓦ1 H7 손상 표식 렌더(접두 판별) · ⓦ2 H10 느린 git 도 회차 예산에서 끊김 · ⓦ3·ⓦ4 H13 LIVE_ROOT 빈 값·상대경로 = ERROR · ⓦ5 회귀 H6 원장 상대경로 = 리포 기준 · ⓦ6 회귀 H2 이월 «송신 모름» 이 _need() 앞
# 픽스처 = mktemp 임시 git 리포(+bare origin)·임시 루트·가짜 mbox(인자 기록만) — 실 리포·실 좌석·실 /tmp/h·실 launchd 0 (install 은 FT_LAUNCHCTL 스텁).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
KITBIN="$REPO/harness/bin"; KIT="$REPO/harness/kit"; INST="$REPO/harness/install.sh"
HR_ROOT="$(cd "$(git -C "$REPO/harness" rev-parse --show-toplevel)" && pwd -P)"
KPATH="$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$KITBIN" "$HR_ROOT")"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = 0 ]; then ok "$1"; else bad "$1 :: rc=$RC out=${out:0:2000}"; fi; }
has() { [[ "$out" == *"$1"* ]]; }
J() { python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(eval(sys.argv[2], {"d": d, "json": json}))
PY
}
PYBIN="$KITBIN"

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
GTEAM=(); GGOAL=(); LSTATE=(); STAMP_TXT="2026-10-23 07:00"
init_goals() {
  GTEAM=(planner issues desk room planner issues); GGOAL=(); LSTATE=()
  local i; for i in 1 2 3 4 5 6; do GGOAL+=("goal-$i-test"); LSTATE+=("상태$i 진행"); done
}
teams_md() {
  printf '# 팀 명단\n\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'
  printf '| planner | `design/planner/` | p | 현역 |\n| issues | `design/issues/` | i | 현역 |\n'
  printf '| desk | `design/desk/` | d | 현역 |\n| room | `design/room/` | r | 현역 |\n'
  printf '| harness | `$FT_HARNESS_ROOT/design/harness/` | h | 현역 |\n'
}
canon() {
  { printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
    local i; for i in "${!GGOAL[@]}"; do printf '| %s | %s | 착지 sha |\n' "${GGOAL[$i]}" "${GTEAM[$i]}"; done; }
}
ledger() {
  { printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 %s줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$STAMP_TXT" "${#GGOAL[@]}"
    local i; for i in "${!GGOAL[@]}"; do printf '| 원장 글자 %s | %s | 남은%s |\n' "$((i + 1))" "${LSTATE[$i]}" "$((i + 1))"; done; }
}
goalfiles() {
  local t i
  for t in planner issues desk room; do
    mkdir -p "$R/design/$t/indices/완성" "$R/design/$t/indices/진행" "$R/design/$t/indices/대기"
    printf '' > "$R/design/$t/indices/완성/.gitkeep"; : > "$R/design/$t/indices/진행/.gitkeep"; : > "$R/design/$t/indices/대기/.gitkeep"
    { printf '# 골 — %s\n\n' "$t"
      for i in "${!GGOAL[@]}"; do [ "${GTEAM[$i]}" = "$t" ] && printf '골좌표: %s — %s\n' "$((i + 1))" "${GGOAL[$i]}"; done; } > "$R/design/$t/GOAL-$t.md"
  done
}
new_fx() {  # <이름>
  FX="$T/$1"; R="$FX/repo"; rm -rf "$FX"; mkdir -p "$FX" "$R" "$R/design/planner" "$R/design/issues" "$R/design/desk" "$R/design/room"
  git init -q --bare "$FX/origin.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$FX/origin.git"
  printf '.fable-team/\n' > "$R/.gitignore"
  teams_md > "$R/design/TEAMS.md"
  cat > "$FX/mbox.sh" <<'SH'
#!/usr/bin/env bash
# 시험용 쪽지함 — 실제 송신 0 · 인자와 «송신 시점의 회차 파일 상태»만 기록
{ printf 'SEND to=%s from=%s\n' "${2:-}" "${3:-}"; printf '%s\n' "${4:-}"; echo '---END---'; } >> "${MBOX_LOG:?}"
f="$(ls -1 "${CLAIM_DIR:?}"/*.json 2>/dev/null | grep -v 'sent.json' | grep -v 'send-failed.json' | sort | tail -1)"
if [ -n "$f" ] && grep -q '"state": "claimed"' "$f"; then echo "CLAIMED-AT-SEND=yes" >> "$MBOX_LOG"; else echo "CLAIMED-AT-SEND=no" >> "$MBOX_LOG"; fi
case "${MBOX_HANG:-0}" in 1) sleep 30 ;; esac
echo "QUEUED seq=777 to=${2:-}"
SH
  chmod +x "$FX/mbox.sh"
  mkdir -p "$R/.fable-team/comm"; printf '{"_master":"byz-planner-claude#9"}\n' > "$R/.fable-team/seats-planner.json"
  init_goals; write_all
  : > "$FX/mbox.log"
  envfx
}
write_all() { canon > "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"; ledger > "$R/design/planner/PLAN-oppa-ledger.md"; goalfiles; }
commit() {  # <메시지> [커밋시각]
  git -C "$R" add -A
  GIT_COMMITTER_DATE="${2:-2026-10-22 07:00}" GIT_AUTHOR_DATE="${2:-2026-10-22 07:00}" \
    git -C "$R" -c user.name=t -c user.email=t@t commit -q -m "$1" && git -C "$R" push -q origin main
}
envfx() {
  export FT_ROOT="$R" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=origin/main
  export FT_MBOX="$FX/mbox.sh" MBOX_LOG="$FX/mbox.log" CLAIM_DIR="$R/.fable-team/state/goal-readjust/rounds"
  unset FT_HARNESS_ROOT FT_HARNESS_REF FT_GOAL_A6_MD FT_GOAL_A6_LEDGER FT_GOAL_READJUST_MAX_H FT_GOAL_STALL_H MBOX_HANG FT_NOW
}
RD() { echo "$R/.fable-team/state/goal-readjust"; }
rounds() { ls -1 "$(RD)/rounds"/*.json 2>/dev/null | grep -v 'sent.json' | grep -v 'send-failed.json' | sort; }
lastround() { rounds | tail -1; }
REQ="시험 요청(오빠 슬랙 1792637646)"
rrun() {  # <FT_NOW>  — ★--request 필수★(DA H12)
  out="$(FT_NOW="$1" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
}
render() { out="$(FT_NOW="${1:-2026-10-23 07:35}" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?; }
nmsg() { grep -c '^SEND to=' "$FX/mbox.log" 2>/dev/null || true; }
body() { awk '/^SEND to=/{f=1;next} /^---END---$/{f=0} f' "$FX/mbox.log"; }
rounds_for() { ls -1 "$(RD)/rounds/$1"*.json 2>/dev/null | grep -v 'sent.json' | grep -v 'send-failed.json' | wc -l | tr -d ' '; }

# ⓐ 빨강 — 장치 없는 판(팩 origin/main 의 ft_goal_table.py)은 머리에 «재조정» 이 없다
HB="$(git -C "$HR_ROOT" rev-parse origin/main)"
new_fx a; commit init
mkdir -p "$T/basebin"; cp "$KITBIN/ft_goal_ledger.py" "$KITBIN/ft_team_lib.py" "$T/basebin/"
git -C "$HR_ROOT" show "$HB:$KPATH/ft_goal_table.py" > "$T/basebin/ft_goal_table.py"
out="$(FT_NOW="2026-10-23 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1; FT_NOW="2026-10-23 07:35" python3 "$T/basebin/ft_goal_table.py" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && ! has "재조정"; }; chk "ⓐ 장치 없는 판(origin/main ft_goal_table) = 머리에 «재조정» 0(빨강 기준선)" $?
out="$(FT_NOW="2026-10-23 07:35" python3 "$KITBIN/ft_goal_table.py" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "재조정"; }; chk "ⓐ2 지금 판 = 머리에 «재조정» 1칸 + 행 «재조정» 칸" $?

# ⓑ 첫 회차 — baseline null · rows 6 전부 «기준» · log 1줄 · 쪽지 0 · 머리 `재조정: ok=20261023-am` · 행 칸 «기준»
new_fx b; commit init
: > "$FX/mbox.log"; rrun "2026-10-23 07:35"
F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(basename "$F")" = "20261023-1-01.json" ] && [ "$(J "$F" 'd["baseline"]')" = None ] && [ "$(J "$F" 'd["baseline_reason"]')" = "첫 회차" ] \
  && [ "$(J "$F" '[r["label"] for r in d["rows"]]')" = "['기준', '기준', '기준', '기준', '기준', '기준']" ]; }; chk "ⓑ 회차 파일 20261023-1-01.json · baseline null · rows 6 전부 «기준»" $?
{ [ -f "$(RD)/rounds/20261023-1-01.md" ] && [ "$(grep -c . "$(RD)/goal-readjust.log")" = 1 ] && [ "$(nmsg)" = 0 ]; }; chk "ⓑ2 보고서 .md 있음 · log 1줄 · 쪽지 0(알릴 사실 없음)" $?
render "2026-10-23 07:35"
{ has "재조정: ok=20261023-1 07:35" && has "| 기준 |"; }; chk "ⓑ3 머리 «재조정: ok=20261023-1 07:35 · 최근=…» + 행 칸 «기준»" $?

# ⓒ 행별 움직임 — 다른 팀 완성 카드 1(골 5 묶임) + 원장 «오빠 할 일» 절만 수정 → 5행 «움직임·카드1» · 나머지 «변화 0(…)» · 원장 행 변화 0
printf '# 카드\n\n골좌표: 5 — goal-5-test\n' > "$R/design/issues/indices/완성/card-x.md"
printf '\n## 오빠 할 일\n\n- (추가)\n' >> "$R/design/planner/PLAN-oppa-ledger.md"
commit card "2026-10-23 19:00"; rrun "2026-10-23 19:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["rows"][4]["label"]')" = "움직임" ] && [ "$(J "$F" 'd["rows"][4]["cards_added"]')" = 1 ] \
  && [ "$(J "$F" 'all(r["ledger_row_changed"] == False for r in d["rows"])')" = True ] \
  && [ "$(J "$F" '[r["label"].startswith("변화 0(") for r in d["rows"] if r["n"] != 5]')" = "[True, True, True, True, True]" ]; }; chk "ⓒ 골 5 «움직임·카드1» · 다른 5행 «변화 0(N시간)» · 원장 행 변화 0(다른 절 수정)" $?
render "2026-10-23 19:35"; has "움직임·카드1"; chk "ⓒ2 골 표 칸에 «움직임·카드1»(r702 미착지라 «·대응 모름» 접미)" $?

# ⓓ 마감 문법 «✅ 시작» · 오탐 2종 · 쓰기 0 — 4·5행은 «닫힘/끝» 글자가 있어도 마감 아님 · 연결 끊김 경보 0 · git status 0 · refs/heads·HEAD 불변
new_fx d; commit init; rrun "2026-10-22 07:35"
LSTATE[0]="✅ 10-22 닫힘(판정 …)"; LSTATE[1]="✅ 10-20 20:5x 닫힘 — …"; LSTATE[2]="✅ 10-20 마감(→ 새 골로 교체 대기)"
LSTATE[3]="1.1.178 설치 끝 · …"; LSTATE[4]="10-20 01:4x: … main 착지 끝 · 휴식"
STAMP_TXT="2026-10-22 08:00"; write_all; commit states
BEFORE_R="$(git -C "$R" show-ref | grep 'refs/heads/')"; BEFORE_H="$(git -C "$R" rev-parse HEAD)"; BEFORE_S="$(git -C "$R" status --porcelain)"
rrun "2026-10-22 08:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["run"]')" = "20261022-2" ] && [ "$(J "$F" '[r["label"] for r in d["rows"][:3]]')" = "['마감', '마감', '마감']" ] \
  && [ "$(J "$F" '[r["label"] != "마감" for r in d["rows"][3:5]]')" = "[True, True]" ]; }; chk "ⓓ 1~3행 «마감»(✅ 시작 3꼴) · 4·5행(닫힘·끝 글자) «마감 아님»" $?
{ [ "$(J "$F" 'd["facts"]["broken_links"]')" = "[]" ] && ! grep -q '연결 끊김' "$F"; }; chk "ⓓ2 마감 행 면제 · 연결 끊김 경보 0" $?
{ [ "$(git -C "$R" status --porcelain)" = "$BEFORE_S" ] && [ "$(git -C "$R" show-ref | grep 'refs/heads/')" = "$BEFORE_R" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$BEFORE_H" ]; }; chk "ⓓ3 쓰기 허용 목록 밖 쓰기 0 — git status·refs/heads·HEAD 전후 동일" $?

# ⓔ 24시간 미만 무변화 — 둘째 회차 · 변화 0 · blame 7시간 전 → `변화 0(7시간)` · 경보 0 · 빈 라벨 0
new_fx e; commit init "2026-10-22 12:35"; rrun "2026-10-22 12:40"
STAMP_TXT="2026-10-22 19:00"; write_all; commit ledger "2026-10-22 12:35"; rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["rows"][0]["label"]')" = "변화 0(7시간)" ] && [ "$(J "$F" 'd["alarms"]')" = "[]" ] \
  && [ "$(J "$F" 'all(r["label"] for r in d["rows"])')" = True ]; }; chk "ⓔ 둘째 회차 7시간 무변화 = «변화 0(7시간)» · 경보 0 · 빈 라벨 0" $?

# ⓕ 닫힘 후보 · [결정] 1통 · mbox_guard reject 통과 · claimed 가 송신 «전» 에 쓰임
new_fx f; GGOAL[1]="goal-2-test"; commit init
mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
LSTATE[1]="진행"; STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
: > "$FX/mbox.log"; rrun "2026-10-23 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["facts"]["close_candidates"]')" = "[2]" ] && [ "$(nmsg)" = 1 ] && [ "$(J "$F" 'd["send"]["state"]')" = "claimed" ]; }; chk "ⓕ 닫힘 후보 [2] · 쪽지 1통 · 회차 파일 send.state=claimed" $?
BODY="$(body)"
{ [ "${#BODY}" -le 700 ] && [[ "$BODY" == *"GR-20261023-1"* ]] && [[ "$BODY" == *"비가역:"*"선례:"*"선택지:"* ]] && [ "$(grep -c 'CLAIMED-AT-SEND=yes' "$FX/mbox.log")" = 1 ] \
  && [ "$(( $(stat -f %m "$F") ))" -le "$(( $(stat -f %m "$FX/mbox.log") ))" ]; }; chk "ⓕ2 본문 ≤700B · GR-<run> · [결정] 3줄 · claimed 가 송신 전(파일 mtime < 송신 로그) " $?
G="$T/guard"; rm -rf "$G"; mkdir -p "$G/.fable-team/comm"
cp "$REPO/harness/comm"/mbox*.sh "$REPO/harness/comm"/mbox*.py "$G/.fable-team/comm/" 2>/dev/null
cp "$REPO"/harness/comm/*_lib.sh "$G/.fable-team/comm/" 2>/dev/null || true
printf '{"_master":"byz-planner-claude#9","byz-planner-claude#9":{"role":"master","agent":"claude"}}\n' > "$G/.fable-team/seats-planner.json"
out="$(cd "$G" && FT_PLANNER_HEAD_MODE=reject GIT_CONFIG_GLOBAL=/dev/null bash .fable-team/comm/mbox.sh send byz-planner-claude#9 ft-goal-readjust "$BODY" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && ! has "REJECT"; }; chk "ⓕ3 실제 comm/mbox_guard.sh reject 모드 통과([결정] 3줄 고정)" $?

# ⓖ 새 골 후보 2 — planner 폴더 GOAL-x/y-<날짜>.md 정본 밖 → 2 · 제안 ID 0 · 쪽지 «정본 밖 골 파일 2»
new_fx g; commit init
printf '# 골 — x\n\n골좌표: 7 — 새 골 x\n' > "$R/design/planner/GOAL-x-20261023.md"
printf '# 골 — y\n\n' > "$R/design/planner/GOAL-y-20261023.md"
commit newgoals; : > "$FX/mbox.log"; rrun "2026-10-23 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["facts"]["goal_files_outside_canon"]')" = "['GOAL-x-20261023.md', 'GOAL-y-20261023.md']" ] \
  && [ "$(J "$F" '[k for k in d if "id" in k.lower() or "proposal" in k.lower()]')" = "[]" ] && grep -q '정본 밖 골 파일 2' "$FX/mbox.log"; }; chk "ⓖ 정본 밖 골 파일 2 · 제안 ID 0 · 쪽지에 «정본 밖 골 파일 2»" $?

# ⓗ 송신 뒤 중단(.sent.json 없음) → 재실행 송신 0 + «송신 상태 모름» · 첫 파일 불변 / 송신 timeout → 재실행 송신 0
new_fx h; commit init
mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
: > "$FX/mbox.log"; rrun "2026-10-23 07:35"
F1="$(lastround)"; SUM1="$(cksum "$F1")"; rm -f "$(RD)/rounds/20261023-1-01.sent.json"
rrun "2026-10-23 07:35"; F2="$(rounds | tail -1)"
{ [ "$RC" = 3 ] && [ "$(basename "$F2")" = "20261023-1-02.json" ] && [ "$(J "$F2" 'd["send"]["state"]')" = "unknown" ] \
  && [ "$(nmsg)" = 1 ] && [ "$(cksum "$F1")" = "$SUM1" ] && grep -q '송신 상태 모름 GR-20261023-1' "$F2"; }; chk "ⓗ 송신 뒤 중단 → 재실행 송신 0 · 새 attempt send.state=unknown · 경보 «송신 상태 모름» · 첫 파일 바이트 불변" $?
new_fx h2; commit init
mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
: > "$FX/mbox.log"; T0=$SECONDS
MBOX_HANG=1 out="$(FT_NOW="2026-10-23 07:35" MBOX_HANG=1 bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
EL=$((SECONDS - T0))
{ [ "$RC" = 3 ] && [ "$EL" -lt 20 ] && [ -f "$(RD)/rounds/20261023-1-01.send-failed.json" ] && has "송신 failed"; }; chk "ⓗ2 송신 상한 7초 — 멈춘 mbox 에도 회차는 끝남(경과 ${EL}s) · .send-failed.json · ★rc3(조용한 rc0 0)★" $?
out="$(FT_NOW="2026-10-23 07:35" bash "$KITBIN/ft-goal-readjust.sh" --retry --request "$REQ" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(nmsg)" = 1 ] && [ "$(J "$(rounds | tail -1)" 'd["send"]["reason"]')" = "run 상한" ]; }; chk "ⓗ3 timeout 뒤 재실행(--retry) = 송신 0(run 상한 — 재시도 0 · 상대가 받았는데 또 보내는 길 0)" $?

# ⓘ 같은 run 재실행 — 2개 파일 · rows 측정값 동일 · baseline 같은 파일 · 쪽지 상한
new_fx i; commit init; rrun "2026-10-23 07:35"
out="$(FT_NOW="2026-10-23 07:35" bash "$KITBIN/ft-goal-readjust.sh" --retry --request "$REQ" 2>&1)"; RC=$?
{ [ "$(rounds_for 20261023-1)" = 2 ] && [ "$(J "$(rounds | tail -1)" 'd["attempt"]')" = 2 ] && [ "$(J "$(rounds | head -1)" 'd["baseline"]')" = "$(J "$(rounds | tail -1)" 'd["baseline"]')" ] \
  && python3 - "$(RD)/rounds/20261023-1-01.json" "$(RD)/rounds/20261023-1-02.json" <<'PY'
import json, sys
a, b = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3])
keys = ("n", "goal_hash", "label", "cards_added", "evidence", "ledger_row_hash", "ledger_row_changed")
sys.exit(0 if [tuple(r[k] for k in keys) for r in a["rows"]] == [tuple(r[k] for k in keys) for r in b["rows"]] and a["run"] == b["run"] else 1)
PY
}; chk "ⓘ --retry 같은 run 재실행 = <run>-01·<run>-02 두 파일 · rows 측정값 동일 · 같은 기준(null) · 쪽지 상한" $?

# ⓙ 실패 보존 · 머리 — am OK 뒤 pm ERROR(원장 못 읽음) · 30시간 뒤 «재조정 없음 30시간»
new_fx j; commit init; rrun "2026-10-22 07:35"
AM="$(RD)/rounds/20261022-1-01.json"; SUMA="$(cksum "$AM")"
git -C "$R" rm -q design/planner/PLAN-oppa-ledger.md; commit noledger
: > "$FX/mbox.log"; rrun "2026-10-22 19:35"; PM="$(rounds | tail -1)"
{ [ "$RC" = 1 ] && [ "$(J "$PM" 'd["status"]')" = "ERROR" ] && [ "$(cksum "$AM")" = "$SUMA" ] && [ "$(nmsg)" = 1 ] && grep -q '\[긴급\]' "$FX/mbox.log"; }; chk "ⓙ pm ERROR(원장 못 읽음) · OK 파일 불변 · [긴급] 1통" $?
rrun "2026-10-22 19:35"
{ [ "$(nmsg)" = 1 ] && [ "$(rounds_for 20261022-2)" = 2 ]; }; chk "ⓙ2 같은 run 재시도 ERROR = 0통(쪽지 상한)" $?
out="$(FT_NOW="2026-10-23 01:35" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "ok=20261022-1" && has "최근=20261022-2-02 ERROR"; }; chk "ⓙ3 머리에 마지막 성공(ok=)과 최근 시도(최근=… ERROR)를 둘 다" $?
out="$(FT_NOW="2026-10-23 13:35" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "재조정 없음 30시간"; }; chk "ⓙ4 30시간 뒤 = «재조정 없음 30시간 · 최근=…»" $?

# ⓚ 골 교체 3회차 — 전문 해시로 잡음 · r702 미착지 = 라벨 ⑤ + «대응 유지 모름» · 표식 픽스처 = «확인 불가»
new_fx k; commit init; rrun "2026-10-22 07:35"
GGOAL[2]="goal-3-test-완전히-다른-골"; write_all; commit swap "2026-10-22 18:00"
rrun "2026-10-22 19:35"; F1="$(rounds | tail -1)"
STAMP_TXT="2026-10-22 19:40"; write_all; commit nostamp "2026-10-22 19:45"
rrun "2026-10-23 07:35"; F2="$(rounds | tail -1)"
{ [ "$(J "$F1" 'd["rows"][2]["label"]')" = "확인 불가" ] && [ "$(J "$F2" 'd["rows"][2]["label"].startswith("변화 0(")')" = True ] \
  && [ "$(J "$F2" '"대응 유지 모름(r702 미착지)" in d["rows"][2]["unknown"]')" = True ]; }; chk "ⓚ 회차 1 «확인 불가»(앞 12자 같아도 전문 해시로 잡음) · 회차 2 라벨 ⑤ + «대응 유지 모름(r702 미착지)»" $?
mkdir -p "$(RD)"; printf '{"stale_rows":[3]}\n' > "$(RD)/goal-row-swap.json"
STAMP_TXT="2026-10-23 07:40"; write_all; commit stamp "2026-10-23 07:45"
rrun "2026-10-23 19:35"; F3="$(rounds | tail -1)"
{ [ "$(J "$F3" 'd["rows"][2]["label"]')" = "확인 불가" ]; }; chk "ⓚ2 r702 표식 픽스처 추가 → «확인 불가»(유지 조건은 r702 몫)" $?

# ⓛ 수집·표시 사이 변경 — 회차 뒤 정본 2행 전문 교체 → 2행 «모름(판 다름)» · 다른 행 라벨 유지 + «·정본 바뀜»
GGOAL[1]="goal-2-test-바뀐-골"; canon > "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"; commit canononly "2026-10-23 19:45"
out="$(FT_NOW="2026-10-23 19:50" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "| 모름(판 다름) |" && has "·정본 바뀜" && [ "$(printf '%s\n' "$out" | grep -c '모름(판 다름)')" = 1 ] ; }; chk "ⓛ 2행 «모름(판 다름)» · 다른 행은 라벨 유지 + «·정본 바뀜»" $?

# ⓜ 저장소별 commit · 디스크 삭제 무관 · 수집 중 origin 전진
new_fx m; commit init
HN="$FX/hrepo"; mkdir -p "$HN"; git init -q -b main "$HN"; git -C "$HN" remote add origin "$FX/hrepo-origin.git"; git init -q --bare "$FX/hrepo-origin.git"
mkdir -p "$HN/design/harness/indices/완성" "$HN/design/harness/indices/진행" "$HN/design/harness/indices/대기"
: > "$HN/design/harness/indices/완성/.gitkeep"; : > "$HN/design/harness/GOAL-harness.md"
printf '골좌표: 4 — goal-4-test\n' > "$HN/design/harness/GOAL-harness.md"
git -C "$HN" add -A && GIT_COMMITTER_DATE="2026-10-22 07:00" git -C "$HN" -c user.name=t -c user.email=t@t commit -q -m h0 && git -C "$HN" push -q origin main
export FT_HARNESS_ROOT="$HN"
rrun "2026-10-22 07:35"; F1="$(rounds | tail -1)"
C1="$(J "$F1" 'd["inputs"]["repos"]["byz"]["commit"]')"; H1="$(J "$F1" 'd["inputs"]["repos"]["harness"]["commit"]')"
rm -rf "$R/design/desk"
printf '\n## 오빠 할 일\n\n- (추가)\n' >> "$R/design/planner/PLAN-oppa-ledger.md"; commit advance "2026-10-23 18:00"
rrun "2026-10-23 19:35"; F2="$(rounds | tail -1)"
C2="$(J "$F2" 'd["inputs"]["repos"]["byz"]["commit"]')"
{ [ -n "$C1" ] && [ -n "$H1" ] && [ "$C1" != "$C2" ] && [ "$RC" = 0 ] && [ "$(J "$F2" 'd["status"]')" = "OK" ] \
  && [ "$(J "$F2" 'd["rows"][2]["label"]')" != "" ]; }; chk "ⓜ BYZ·하네스 commit 따로 기록 · 팀 폴더를 디스크에서 지워도 commit 트리로 측정(ERROR 0)" $?
git -C "$R" checkout -q -- .

# ⓝ 하네스 ref 미정 — FT_HARNESS_ROOT 없음 → harness 행만 «하네스 카드 모름(리포/ref 미정)» · 다른 행 정상
new_fx n; GTEAM[3]="harness"; write_all; commit init
unset FT_HARNESS_ROOT; rrun "2026-10-22 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'any("하네스 카드 모름(리포/ref 미정)" in u for u in d["rows"][3]["unknown"])')" = True ] \
  && [ "$(J "$F" 'd["rows"][0]["label"]')" = "기준" ] && [ "$(J "$F" 'd["inputs"]["repos"]["harness"]')" = None ]; }; chk "ⓝ FT_HARNESS_ROOT 없음 = harness 행 «하네스 카드 모름(리포/ref 미정)» · 다른 행 정상 · repos.harness=null" $?

# ⓞ 모름 글자 4종 구분 — r693 없음 / 판별 미설정 / r664 없음 / r708 없음
new_fx o; commit init; rrun "2026-10-22 07:35"; F="$(lastround)"
V1="$(J "$F" 'd["rows"][0]["evidence"]')"
mkdir -p "$(RD)"; printf '{"rows":{"1":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
rrun "2026-10-22 19:35"; F2="$(rounds | tail -1)"; V2="$(J "$F2" 'd["rows"][1]["evidence"]')"
V3="$(J "$F2" 'd["rows"][1]["unknown"][-2]')"; V4="$(J "$F2" 'd["rows"][1]["unknown"][-1]')"
{ [ "$V1" = "모름(r693 미착지)" ] && [ "$V2" = "모름(r693 판별 미설정)" ] && [ "$V3" = "착지 모름(r664 미착지)" ] && [ "$V4" = "라이브 판 모름(r708 미착지)" ]; }; chk "ⓞ 모름 4종 구분 — r693 미착지 / r693 판별 미설정 / r664 미착지 / r708 미착지" $?

# ⓟ 동시 2건 — busy SKIP 1 · 회차 파일 1개
new_fx p; mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-22 06:00"; write_all; commit init; : > "$FX/mbox.log"
MBOX_HANG=1 FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" > "$T/p1.log" 2>&1 &
sleep 0.4
MBOX_HANG=1 FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" > "$T/p2.log" 2>&1
wait
{ [ "$(rounds_for 20261022-1)" = 1 ] && grep -q 'SKIP busy' "$(RD)/goal-readjust.log"; }; chk "ⓟ 동시 2건 = busy SKIP 1줄 · 회차 파일 1개(잠금)" $?

# ⓠ 뉴스 무변경 — kit 뉴스 3파일이 base(origin/main) 와 diff 0
n=0
for f in ft_news_html.py ft_news_html_render.py ft_news_ledger.py; do
  git -C "$HR_ROOT" show "$HB:$KPATH/$f" > "$T/$f.base" 2>/dev/null && cmp -s "$T/$f.base" "$KITBIN/$f" && n=$((n + 1))
done
{ [ "$n" = 3 ]; }; chk "ⓠ 뉴스 3파일(ft_news_html·render·ledger) base 대비 diff 0" $?

# ⓡ 회귀·합본 — r668 시험 rc0 · kit ↔ harness/bin cmp0 · 예산 1600B(넘치면 ERROR)
out="$(bash "$HERE/test_goal_count_follows_canon_r668.sh" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "fail=0"; }; chk "ⓡ r668 골 개수 시험 전부 통과(fail=0)" $?
n=0
for f in ft_goal_readjust.py ft_goal_readjust_measure.py ft_goal_readjust_state.py ft-goal-readjust.sh ft_goal_table.py; do cmp -s "$KIT/fable-team/bin/$f" "$KITBIN/$f" && n=$((n + 1)); done
{ [ "$n" = 5 ]; }; chk "ⓡ2 kit ↔ harness/bin cmp0 (새 4 + ft_goal_table)" $?
new_fx r; commit init; rrun "2026-10-22 07:35"
out="$(FT_NOW="2026-10-22 07:40" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(printf '%s' "$out" | wc -c)" -le 1600 ] && has "재조정"; }; chk "ⓡ3 표 ≤1600B + «재조정» 칸 포함(6행)" $?
python3 - "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); lines = p.read_text(encoding="utf-8").splitlines()
lines = [l.replace("goal-", "goal-" + "아주긴골이름" * 40 + "-", 1) if l.startswith("| goal-") else l for l in lines]
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
commit longcanon "2026-10-22 07:45"
out="$(FT_NOW="2026-10-22 07:50" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 1 ] && has "예산 초과"; }; chk "ⓡ4 골 원문이 길어 1600B 넘침 = «ERROR 골 표 예산 초과» rc1(조용한 절단 0)" $?

# ⓢ 변이 6 — 각 변이가 그 칸의 시험을 FAIL 시킨다
mut() {  # <이름> <파일> <치환 전> <치환 후> → $T/mut/$1 에 사본
  local n="$1"; rm -rf "$T/mut/$n"; mkdir -p "$T/mut/$n"
  cp "$KITBIN"/ft_goal_readjust.py "$KITBIN"/ft_goal_readjust_measure.py "$KITBIN"/ft_goal_readjust_state.py "$KITBIN"/ft_goal_table.py "$KITBIN"/ft_goal_ledger.py \
     "$KITBIN"/ft_team_lib.py "$KITBIN"/ft-goal-readjust.sh "$KITBIN"/ft-goal-table.sh "$T/mut/$n/"
  python3 - "$T/mut/$n/$2" "$3" "$4" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
assert sys.argv[2] in s, "치환 대상 없음: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
}
mut ① ft_goal_readjust_measure.py '    _fetch(repo, ref)
    return repo, ref, _git(repo, "rev-parse", "--verify", ref).strip()' '    _fetch(repo, ref)
    (repo / "MUTANT-canon.txt").write_text("1줄 쓰기\n", encoding="utf-8")
    return repo, ref, _git(repo, "rev-parse", "--verify", ref).strip()'
new_fx s1; commit init; FT_NOW="2026-10-22 07:35" bash "$T/mut/①/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1
{ [ -n "$(git -C "$R" status --porcelain)" ]; }; chk "ⓢ① 정본 작업 파일 1줄 쓰기 변이 → ⓓ(git status 0) 가 FAIL 한다" $?
mut ② ft_goal_readjust.py '    attempt = _attempts(d, run) + 1' '    attempt = 1'
new_fx s2; commit init
rrun "2026-10-22 07:35"
out="$(FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --retry --request "$REQ" 2>&1)"
N_ORIG="$(rounds_for 20261022-1)"
new_fx s2b; commit init
FT_NOW="2026-10-22 07:35" bash "$T/mut/②/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1
FT_NOW="2026-10-22 07:35" bash "$T/mut/②/ft-goal-readjust.sh" --retry --request "$REQ" >/dev/null 2>&1
N_MUT="$(rounds_for 20261022-1)"
{ [ "$N_ORIG" = 2 ] && [ "$N_MUT" = 1 ]; }; chk "ⓢ② attempt 고정 변이 — 원본은 2파일(ⓘ PASS) · 변이는 덮어쓰기 금지로 1파일(FAIL) = ${N_ORIG}/${N_MUT}" $?
mut ③ ft_goal_readjust.py '    _write(stem.with_suffix(".json"), json.dumps(rec, ensure_ascii=False, indent=1) + "\n", fresh=True)   # ← 이 파일 존재 = 회차 완료' '    pass  # 변이 ③: 회차 파일을 송신 «뒤» 로 미룬다'
new_fx s3; commit init
mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-22 06:00"; write_all; commit ev
python3 - "$T/mut/③/ft_goal_readjust.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
s = s.replace('        rec["send"] = {**plan, **out}', '        rec["send"] = {**plan, **out}\n        _write(stem.with_suffix(".json"), json.dumps(rec, ensure_ascii=False, indent=1) + "\\n", fresh=True)', 1)
p.write_text(s, encoding="utf-8")
PY
: > "$FX/mbox.log"; FT_NOW="2026-10-22 07:35" bash "$T/mut/③/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1
{ [ "$(grep -c 'CLAIMED-AT-SEND=yes' "$FX/mbox.log")" != 1 ]; }; chk "ⓢ③ claimed 를 송신 뒤로 옮긴 변이 → ⓕ(claimed 가 송신 전) 가 FAIL 한다" $?
mut ④ ft_goal_readjust_state.py '    if row is None or not goal_hash or row.get("goal_hash") != goal_hash:' '    if row is None or not goal_hash:'
new_fx s4; commit init; rrun "2026-10-22 07:35"
GGOAL[1]="goal-2-test-바뀐-골"; canon > "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"; commit canononly "2026-10-22 07:40"
MUT4="$(FT_NOW="2026-10-22 07:40" bash "$T/mut/④/ft-goal-table.sh" render 2>&1)"
out="$(FT_NOW="2026-10-22 07:40" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "모름(판 다름)" && [[ "$MUT4" != *"모름(판 다름)"* ]]; }; chk "ⓢ④ goal_hash 대조 삭제 변이 — 원본은 «모름(판 다름)»(ⓛ PASS) · 변이는 없음(FAIL)" $?
mut ⑤ ft_goal_readjust_measure.py '    return f"변화 0({int(row['"'"'row_age_h'"'"'])}시간)" if row["row_age_h"] is not None else "변화 0(시간 모름)"' '    return ""'
new_fx s5; commit init "2026-10-22 12:35"; rrun "2026-10-22 12:40"
STAMP_TXT="2026-10-22 19:00"; write_all; commit ledger "2026-10-22 12:35"
FT_NOW="2026-10-22 19:35" bash "$T/mut/⑤/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1
{ [ "$(J "$(lastround)" 'any(r["label"] == "" for r in d["rows"])')" = True ]; }; chk "ⓢ⑤ 라벨 ⑤ 기본값 삭제 변이 → ⓔ(빈 라벨 0) 가 FAIL 한다" $?
mut ⑥ ft_goal_readjust_measure.py '            "ledger_closed": _flat(state_cell).startswith("✅"),' '            "ledger_closed": any(k in _flat(state_cell) for k in ("✅", "닫힘", "마감", "끝")),'
new_fx s6; commit init; rrun "2026-10-22 07:35"
LSTATE[3]="1.1.178 설치 끝 · …"; LSTATE[4]="10-20 01:4x: … main 착지 끝 · 휴식"
STAMP_TXT="2026-10-22 08:00"; write_all; commit states
FT_NOW="2026-10-22 08:35" bash "$T/mut/⑥/ft-goal-readjust.sh" --request "$REQ" >/dev/null 2>&1
{ [ "$(J "$(lastround)" '"마감" in [r["label"] for r in d["rows"][3:5]]')" = True ] && [ "$(J "$(lastround)" 'd["run"]')" = "20261022-2" ]; }; chk "ⓢ⑥ 마감을 «닫힘 글자 포함» 으로 바꾼 변이 → ⓓ(4·5행 마감 아님) 가 FAIL 한다" $?

# ⓣ 첫 공지 보존 — 장치 선실행 뒤 렌더에도 «[골 번호 바뀜]» 1통 그대로(r668 공지 보존 · ★표식 없음 · 정본 5행★)
new_fx t; GTEAM=(planner issues desk room planner); GGOAL=(goal-1-test goal-2-test goal-3-test goal-4-test goal-5-test); LSTATE=(상태1 진행 상태2 진행 상태3 진행 상태4 진행 상태5 진행)
write_all; commit init
printf '{"_master":"master-a#1","master-a#1":{"role":"master"}}\n' > "$R/.fable-team/seats-harness.json"
rrun "2026-10-22 07:35"
: > "$FX/mbox.log"; out="$(FT_NOW="2026-10-22 07:40" FT_MBOX="$FX/mbox.sh" MBOX_LOG="$FX/mbox.log" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && grep -q '\[골 번호 바뀜\]' "$FX/mbox.log" && grep -q '5줄' "$FX/mbox.log"; }; chk "ⓣ 표식 없음·5행 정본 — 장치 선실행 뒤 첫 렌더에도 «[골 번호 바뀜]» 1통(5줄)" $?

# ⓤ ★오빠 10-22 정정★ 자동 시계 0 + 수동 진입점 1개 + 하루 최대 2회 상한
{ [ ! -f "$KIT/launchd/com.byz.ft-goal-readjust.plist.template" ] && ! grep -q 'launchd-new' "$INST" \
  && [ -f "$KIT/fable-team/bin/ft-goal-readjust.sh" ] && ! python3 "$KIT/fable-team/bin/ft_plist_env.py" bin-list "$KIT" | grep -q 'ft-goal-readjust'; }; chk "ⓤ 자동 시계 0 — launchd 템플릿·install.sh --launchd-new 없음 · 수동 진입점 = ft-goal-readjust.sh 하나(등록 데몬 0)" $?
new_fx u; commit init; : > "$FX/mbox.log"
{ [ ! -d "$(RD)/rounds" ] || [ -z "$(rounds)" ]; }; chk "ⓤ2 요청 없는 날 = 회차 파일 0(부르지 않으면 아무것도 안 돈다)" $?
rrun "2026-10-22 07:35"; rrun "2026-10-22 19:35"; N2="$(rounds | wc -l | tr -d ' ')"; M2="$(nmsg)"
rrun "2026-10-22 21:00"
{ [ "$N2" = 2 ] && [ "$(rounds | wc -l | tr -d ' ')" = 2 ] && [ "$(nmsg)" = "$M2" ] && [ "$RC" = 2 ] && has "REJECT 오늘 2회 다 씀" && grep -q 'REJECT 오늘 2회 다 씀' "$(RD)/goal-readjust.log"; }; chk "ⓤ3 하루 최대 2회 — 3번째 요청 = REJECT rc2 · 회차 파일 0 · 쪽지 0(요청 없는 날 건너뜀과 다른 조건)" $?
rrun "2026-10-23 07:35"
{ [ "$RC" = 0 ] && [ "$(rounds | wc -l | tr -d ' ')" = 3 ] && [ "$(J "$(lastround)" 'd["run"]')" = "20261023-1" ]; }; chk "ⓤ4 다음 날 요청 = 새 회차(20261023-1) 하나 더 — 상한은 «날» 단위" $?
out="$(FT_NOW="2026-10-23 19:35" bash "$KITBIN/ft-goal-readjust.sh" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && has "usage" && [ "$(rounds | wc -l | tr -d ' ')" = 3 ]; }; chk "ⓤ5 --request 없음 = usage rc2 · 회차 파일 0(출처 없이 안 돈다)" $?
out="$(FT_NOW="2026-10-23 19:35" bash "$KITBIN/ft-goal-readjust.sh" --request "" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && has "usage"; }; chk "ⓤ6 --request 빈 값 = usage rc2(빈 출처 0)" $?


# ⓥ ★DA⑥ r1 HOLD 처방 H1~H13 재시험★ — 아래 13칸이 처방 하나씩을 잡는다(H14 = 위 ⓢ②·ⓢ④·ⓣ 갱신)
# ⓥ1 H1 회차 불변 — 보고서(.md)만 쓰고 끊긴 회차를 재실행해도 «같은 .md 덮어쓰기 0»(번호 02 · -01.md 바이트 불변)
new_fx v1; commit init; rrun "2026-10-22 07:35"
MD1="$(RD)/rounds/20261022-1-01.md"; SUM_MD="$(cksum "$MD1")"; rm -f "$(RD)/rounds/20261022-1-01.json"
rrun "2026-10-22 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(basename "$F")" = "20261022-1-02.json" ] && [ "$(cksum "$MD1")" = "$SUM_MD" ]; }; chk "ⓥ1 H1 보고서만 있던 회차 재실행 = -02 로 쓰고 -01.md 덮어쓰기 0(바이트 불변)" $?

# ⓥ2 H2 «송신 상태 모름» 은 영수증이 생길 때까지 이어진다 — 두 번째·세 번째 attempt 모두 unknown + 경보
new_fx v2; mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
: > "$FX/mbox.log"; rrun "2026-10-23 07:35"; rm -f "$(RD)/rounds/20261023-1-01.sent.json"
rrun "2026-10-23 07:35"; F2="$(rounds | tail -1)"
out="$(FT_NOW="2026-10-23 07:35" bash "$KITBIN/ft-goal-readjust.sh" --retry --request "$REQ" 2>&1)"; RC=$?; F3="$(rounds | tail -1)"
{ [ "$(J "$F2" 'd["send"]["state"]')" = "unknown" ] && [ "$(J "$F3" 'd["send"]["state"]')" = "unknown" ] \
  && [ "$(J "$F3" '"송신 상태 모름 GR-20261023-1" in d["alarms"]')" = True ] && [ "$(nmsg)" = 1 ]; }; chk "ⓥ2 H2 모름이 사라지지 않는다 — 2·3번째 attempt 모두 unknown · 경보 유지 · 쪽지는 1통 그대로" $?

# ⓥ3 H3 26시간 뒤에도 마지막 성공(run)을 머리에 남긴다 — «재조정 없음 30시간 · ok=… · 최근=…»
new_fx v3; commit init; rrun "2026-10-22 07:35"
out="$(FT_NOW="2026-10-23 13:35" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "재조정 없음 30시간" && has "ok=20261022-1 07:35"; }; chk "ⓥ3 H3 30시간 뒤 머리에도 ok=<run> 과 최근= 를 둘 다(마지막 성공 생략 0)" $?

# ⓥ4 H4 «기준» 라벨 행도 정본 대조 — 첫 회차 뒤 정본만 바뀌면 «기준·정본 바뀜»
new_fx v4; commit init; rrun "2026-10-22 07:35"
printf '\n' >> "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"; commit canon2 "2026-10-22 08:00"
out="$(FT_NOW="2026-10-22 08:35" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "기준·정본 바뀜"; }; chk "ⓥ4 H4 «기준» 행도 «·정본 바뀜» 을 붙인다(조기 반환 0)" $?

# ⓥ5 H5 하네스 리포 «하위 폴더»(FT_HARNESS_ROOT=리포/sub) · 하네스도 fetch — 하네스 카드 1 이 4행에 묶인다
new_fx v5; GTEAM[3]="harness"; write_all; commit init
HN="$FX/hrepo5"; mkdir -p "$HN/sub/design/harness/indices/완성" "$HN/sub/design/harness/indices/진행" "$HN/sub/design/harness/indices/대기"
git init -q -b main "$HN"; git -C "$HN" remote add origin "$FX/hrepo5-origin.git"; git init -q --bare "$FX/hrepo5-origin.git"
: > "$HN/sub/design/harness/indices/완성/.gitkeep"; : > "$HN/sub/design/harness/indices/진행/.gitkeep"; : > "$HN/sub/design/harness/indices/대기/.gitkeep"
printf '골좌표: 4 — goal-4-test\n' > "$HN/sub/design/harness/GOAL-harness.md"
git -C "$HN" add -A && GIT_COMMITTER_DATE="2026-10-22 07:00" git -C "$HN" -c user.name=t -c user.email=t@t commit -q -m h0 && git -C "$HN" push -q origin main
export FT_HARNESS_ROOT="$HN/sub"
rrun "2026-10-22 07:35"
printf '# 카드 h5\n\n골좌표: 4 — goal-4-test\n' > "$HN/sub/design/harness/indices/완성/card-h5.md"
git -C "$HN" add -A && GIT_COMMITTER_DATE="2026-10-22 19:00" git -C "$HN" -c user.name=t -c user.email=t@t commit -q -m h1 && git -C "$HN" push -q origin main
rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["rows"][3]["cards_added"]')" = 1 ] && [ "$(J "$F" 'd["rows"][3]["label"]')" = "움직임" ]; }; chk "ⓥ5 H5 하네스 하위 폴더 prefix + fetch — 하네스 완성 카드 1 이 4행 «움직임·카드1»" $?

# ⓥ6 H6 입력은 «기록한 commit 트리» 에서 — 작업 파일만 고치고 커밋 안 하면 측정이 안 흔들린다(파일 출처도 같다)
new_fx v6; commit init
rrun "2026-10-22 07:35"
export FT_GOAL_A6_MD="$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"
GGOAL[1]="goal-2-test-작업만-바뀐-골"; canon > "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"
rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" '[r["label"] for r in d["rows"]][1]')" != "확인 불가" ] && [ "$(J "$F" 'd["rows"][1]["goal_hash"] == d["rows"][1]["goal_hash"]')" = True ]; }; chk "ⓥ6 H6 커밋 안 한 작업 파일 변경 = 측정에 반영 0(«확인 불가» 0 · 고정 commit 판)" $?
unset FT_GOAL_A6_MD

# ⓥ7 H7 «모름» 계약 — 손상 표식 / 빈 파일 / 넘긴 3개(r714c·r701) 글자
new_fx v7; commit init
mkdir -p "$(RD)"; printf '{broken\n' > "$(RD)/goal-row-swap.json"; printf '{}' > "$(RD)/goal-landed.json"
rrun "2026-10-22 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" '"대응 유지 모름(표식 손상)" in d["rows"][0]["unknown"]')" = True ] \
  && [ "$(J "$F" '"착지 모름(r664 표식 손상)" in d["rows"][0]["unknown"]')" = True ] \
  && [ "$(J "$F" '"모름(r714c 미착지)" in d["facts"]["unknown"]')" = True ] && [ "$(J "$F" '"모름(r701 미착지)" in d["facts"]["unknown"]')" = True ]; }; chk "ⓥ7 H7 손상 표식·빈 파일도 «모름» · 넘긴 r714c·r701 «미착지» 글자(0 으로 합치지 않음)" $?
printf '{"stale_rows":[]}\n' > "$(RD)/goal-row-swap.json"; printf '{"n":1}\n' > "$(RD)/goal-landed.json"
rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$(J "$F" 'any("r702" in u for u in d["rows"][0]["unknown"])')" = False ] && [ "$(J "$F" 'any("r664" in u for u in d["rows"][0]["unknown"])')" = False ]; }; chk "ⓥ7b H7 «빈 배열 표식»·정상 표식은 «모름» 아님(손상과 구분 · 거짓 모름 0)" $?

# ⓥ8 H8 조용한 OK 0 — 송신 실패(mbox 없음)·planner 자리 없음은 rc3 + 머리 «송신 실패»
new_fx v8; mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
out="$(FT_NOW="2026-10-23 07:35" FT_MBOX="$FX/no-such-mbox.sh" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
{ [ "$RC" = 3 ] && has "송신"; }; chk "ⓥ8 H8 mbox 없음 = rc3(«OK … rc0» 0)" $?
out="$(FT_NOW="2026-10-23 07:35" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "송신 실패"; }; chk "ⓥ8b H8 머리가 영수증을 읽어 «송신 실패» 를 보인다" $?
new_fx v8c; mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev; rm -f "$R/.fable-team/seats-planner.json"
out="$(FT_NOW="2026-10-23 07:35" FT_MBOX="$FX/mbox.sh" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
F="$(lastround)"
{ [ "$RC" = 3 ] && [ "$(J "$F" 'd["send"]["state"]')" = "failed" ]; }; chk "ⓥ8c H8 planner 명부 없음 = send.state=failed · rc3(«보낼 수 없음» 을 조용히 0 으로 안 넘긴다)" $?

# ⓥ9 H9 골좌표 정규식 — `## 골좌표` 절 카드가 «골 n»+goal12 로 묶이고 ValueError 0 · 측정 예외 = ERROR 회차 파일
new_fx v9; commit init; rrun "2026-10-22 07:35"
printf '# 카드\n\n## 골좌표\n\n골 5 goal-5-test\n' > "$R/design/issues/indices/완성/card-sec.md"
commit cardsec "2026-10-22 19:00"; rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["rows"][4]["cards_added"]')" = 1 ]; }; chk "ⓥ9 H9 «## 골좌표» 절 카드 = 5행에 묶임(정규식 ValueError 0)" $?
new_fx v9b; commit init
printf '\xff\xfe binary\n' > "$R/design/planner/PLAN-oppa-ledger.md"; commit bin "2026-10-22 19:00"
rrun "2026-10-22 19:35"; F="$(lastround)"
{ [ "$RC" = 1 ] && [ "$(J "$F" 'd["status"]')" = "ERROR" ]; }; chk "ⓥ9b H9 측정 예외(디코드 실패) = ERROR 회차 파일(status=ERROR · rc1)" $?

# ⓥ10 H10 예산 — 측정 «중» 예산 초과도 ERROR 회차로 남는다(«ERROR 파일 0» 0)
new_fx v10; commit init
out="$(FT_NOW="2026-10-22 07:35" FT_GOAL_READJUST_BUDGET=0 bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
F="$(lastround)"
{ [ "$RC" = 1 ] && [ -n "$F" ] && [ "$(J "$F" 'd["status"]')" = "ERROR" ] && has "시간 초과"; }; chk "ⓥ10 H10 예산 초과 = ERROR 회차 파일 + rc1(래퍼 문구와 사실 일치)" $?

# ⓥ11 H11 쓰기 허용 목록 — 실행이 설치 사본 bin 아래에 파일을 만들지 않는다(python3 -B)
new_fx v11; commit init
BEFORE="$(ls -1 "$KITBIN")"; rrun "2026-10-22 07:35"; AFTER="$(ls -1 "$KITBIN")"
{ [ "$RC" = 0 ] && [ "$BEFORE" = "$AFTER" ]; }; chk "ⓥ11 H11 bin 파일 목록 전후 동일(__pycache__ 새로 생김 0)" $?

# ⓥ12 H12 요청 출처가 회차 파일에 남는다(--request 값 그대로)
new_fx v12; commit init; rrun "2026-10-22 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["request"]')" = "$REQ" ]; }; chk "ⓥ12 H12 회차 파일 request 칸 = --request 값 그대로" $?

# ⓥ13 H13 무효 LIVE_ROOT = ERROR(조용한 FT_ROOT 대체 0) · 렌더는 죽지 않는다
new_fx v13; commit init
mkdir -p "$R/.fable-team"; printf '/no/such/live/root\n' > "$R/.fable-team/LIVE_ROOT"
out="$(FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
{ [ "$RC" = 1 ] && has "LIVE_ROOT 무효" && [ -z "$(rounds)" ]; }; chk "ⓥ13 H13 무효 LIVE_ROOT = ERROR rc1 · 회차 파일 0(FT_ROOT 로 조용히 안 간다)" $?
out="$(FT_NOW="2026-10-22 07:40" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "재조정 기록 없음"; }; chk "ⓥ13b H13 무효 LIVE_ROOT 라도 렌더는 rc0(«재조정 기록 없음»)" $?

# ⓦ ★DA⑥ r2 HOLD 작은 고침 5개 재시험★ — 뒷판 PASS · r2 판 FAIL 로 갈리는 칸
# ⓦ1 H7 손상 표식 — «r702» 글자가 없는 «대응 유지 모름(표식 손상)» 도 렌더가 «·대응 모름» 으로 본다(접두 판별)
new_fx w1; commit init; rrun "2026-10-22 07:35"
mkdir -p "$(RD)"; printf '{broken\n' > "$(RD)/goal-row-swap.json"
STAMP_TXT="2026-10-22 19:00"; write_all; commit st; rrun "2026-10-22 19:35"; F="$(lastround)"
render "2026-10-22 19:35"
{ [ "$RC" = 0 ] && [ "$(J "$F" '"대응 유지 모름(표식 손상)" in d["rows"][0]["unknown"]')" = True ] && [[ "$out" == *"·대응 모름"* ]]; }; chk "ⓦ1 H7 손상 표식(«r702» 글자 없음) 둘째 회차 → render 행에 «·대응 모름»" $?

# ⓦ2 H10 총 마감 — 호출당은 7초 미만인데 합계가 예산을 넘기는 느린 git 도 «측정 중»에 끊긴다(카드·행 반복 안 마감)
REALGIT="$(command -v git)"; mkdir -p "$T/slowgit"; : > "$T/slowgit/calls"
cat > "$T/slowgit/git" <<SH
#!/usr/bin/env bash
sleep 5
"$REALGIT" "\$@"; rc=\$?
printf 'x\n' >> "$T/slowgit/calls"
exit \$rc
SH
chmod +x "$T/slowgit/git"
new_fx w2; commit init
T0=$SECONDS
out="$(PATH="$T/slowgit:$PATH" FT_NOW="2026-10-22 07:35" FT_GOAL_READJUST_BUDGET=7 bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
EL=$((SECONDS - T0)); F="$(lastround)"
{ [ "$RC" = 1 ] && [ -n "$F" ] && [ "$(J "$F" 'd["status"]')" = "ERROR" ] && has "시간 초과" \
  && [ "$(grep -c . "$T/slowgit/calls")" = 1 ] && [ "$EL" -le 9 ]; }; chk "ⓦ2 H10 느린 git(호출당 5초) 도 예산 7초에서 끊김 — 완료 호출 1 · ERROR 회차 파일 · 경과 ${EL}s(70초 kill 전)" $?

# ⓦ3·ⓦ4 H13 LIVE_ROOT «빈 값»·«상대경로» = ERROR rc1(FT_ROOT 로 조용한 대체 0)
new_fx w3; commit init
mkdir -p "$R/.fable-team"; printf '\n' > "$R/.fable-team/LIVE_ROOT"
out="$(FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
{ [ "$RC" = 1 ] && has "LIVE_ROOT" && [ -z "$(rounds)" ]; }; chk "ⓦ3 H13 LIVE_ROOT 빈 값 = ERROR rc1 · 회차 파일 0" $?
out="$(FT_NOW="2026-10-22 07:40" bash "$KITBIN/ft-goal-table.sh" render 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "재조정 기록 없음"; }; chk "ⓦ3b H13 빈 값이라도 렌더는 rc0(«재조정 기록 없음» — 사람이 «재조정 없음» 을 본다)" $?
new_fx w4; commit init
mkdir -p "$R/.fable-team"; printf '.\n' > "$R/.fable-team/LIVE_ROOT"
out="$(FT_NOW="2026-10-22 07:35" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
{ [ "$RC" = 1 ] && has "상대경로" && [ -z "$(rounds)" ]; }; chk "ⓦ4 H13 LIVE_ROOT 상대경로(.) = ERROR rc1 · 회차 파일 0(cwd 따라 흔들리는 루트 0)" $?

# ⓦ5 회귀 H6 — FT_LEDGER_PATH 상대 경로는 «리포 기준» (옛 ft_goal_ledger.ledger_spec 과 같은 규칙 · cwd 기준이면 리포 밖에서 ERROR)
new_fx w5; commit init; mkdir -p "$T/outside"
out="$(cd "$T/outside" && FT_NOW="2026-10-22 07:35" FT_LEDGER_PATH="design/planner/PLAN-oppa-ledger.md" bash "$KITBIN/ft-goal-readjust.sh" --request "$REQ" 2>&1)"; RC=$?
F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["status"]')" = "OK" ]; }; chk "ⓦ5 회귀 H6 FT_LEDGER_PATH 상대경로 = 리포 기준(리포 밖 cwd 에서도 OK · «입력이 리포 밖» 0)" $?

# ⓦ6 회귀 H2 — 이월 «송신 모름» 경보를 _need() «앞» 에 — 이번 회차 자체 경보 0 이어도 쪽지 1통(조용한 rc0 0)
new_fx w6; GGOAL[1]="goal-2-test"; commit init
mkdir -p "$(RD)"; printf '{"rows":{"2":"✅ 전부"}}\n' > "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-23 06:00"; write_all; commit ev
: > "$FX/mbox.log"; rrun "2026-10-23 07:35"
rm -f "$(RD)/rounds/20261023-1-01.sent.json"; rm -f "$(RD)/goal-evidence.json"
STAMP_TXT="2026-10-24 06:00"; write_all; commit nx "2026-10-24 06:00"
rrun "2026-10-24 07:35"; F="$(lastround)"
{ [ "$RC" = 0 ] && [ "$(J "$F" 'd["facts"]["close_candidates"]')" = "[]" ] && [ "$(nmsg)" = 2 ] \
  && [ "$(J "$F" 'any("송신 상태 모름" in a for a in d["alarms"])')" = True ]; }; chk "ⓦ6 회귀 H2 이월 «송신 모름» 이 _need() 앞 — 후보 해소된 다음 날에도 쪽지 1통(조용한 rc0 0)" $?

echo "== test_goal_readjust_r714: fail=$fail"
[ "$fail" = 0 ]
