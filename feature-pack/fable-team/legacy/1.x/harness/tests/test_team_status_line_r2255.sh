#!/usr/bin/env bash
# test_team_status_line_r2255.sh — desk 틱이 TEAM-STATUS.md 1행(머리 카운터)을 새로 쓴다(r2255 · 반례 ①~⑦ ⑨).
#   ① 세 칸 셈 + 3행부터 바이트 같음 + status_head.head() = 1행 ② --hil ? → «스크립트 ?» · head() 그대로(경보 0)
#   ③ last.json 낡음·없음 → 막힌 팀 «?» ④ 장부 없음·깨진 줄 → 인터뷰 «?» ⑤ 파일 없음 → 2행 새로 · 폴더 없음 → rc≠0 · 파일 0
#   ⑥ 같은 입력 두 번 → 1행 · 3행부터 같음 ⑦ desk 틱 가짜 세계 «머리 …» 줄 ⑨ 열쇠 (kind, q_ts)
# 전부 합성(임시 루트 · 가짜 장부 · 가짜 last.json) · 네트워크 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/.."
P="$H/bin/ft_team_status_line.py"
KIT="$H/kit/slack-mirror"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NOW=1795000000
# r2390: 1행이 칸 8개로 넓어졌다 — 칸 출처 3(자율 · 지시 감시 · r2389 대기 세기 사본)을 스텁으로 고정한다(가짜 루트에서 진짜 도구 0)
mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\necho "[자율 ON A19 · 08:57~ · 끝 없음 · 대리 3 · 큐 1 · 레벨 풀자동 · 범위 S58]"\n' > "$T/fake/ft-autonomy.sh"
printf '#!/usr/bin/env bash\necho "담당 없는 오빠 지시 3 · 멈춘 오빠 지시 4 · 판본 x"\n' > "$T/fake/ft-directive-watch.sh"
export FT_DESK_HEAD_AUTONOMY="$T/fake/ft-autonomy.sh" FT_DESK_HEAD_DIRECTIVE="$T/fake/ft-directive-watch.sh"
export FT_BOARD_NEWS_WAIT_BIN="$HERE/fixtures/wait_r2390" FT_GOAL_PROGRESS_MD="$T/none.md"
exp() { printf '자율 ON A19 풀자동 · 오빠 답 기다림 %s · 스크립트 %s · 막힌 팀 %s · planner [정리] %s · 원장 낡음 %s · 오빠 지시 멈춤 4 · 담당 없음 3' "$1" "$2" "$3" "${4:-?}" "${5:-?}"; }
L1="$(exp '5(가장 오래 0시간)' 2 2)"

world() {  # world <이름> — 반례 ① 세계(장부 · 신선한 last.json · 옛 3행부터)
  R="$T/$1"; S="$R/.fable-team/state"; mkdir -p "$S/planner-tick"
  printf '%s\n' \
    '{"q_ts":"1.1","kind":"question","state":"open"}' '{"q_ts":"1.2","kind":"question","state":"notified"}' \
    '{"q_ts":"1.3","kind":"question","state":"closed"}' '{"q_ts":"1.4","kind":"question","state":"closed"}' \
    '{"q_ts":"1.5","kind":"question","state":"closed"}' '{"q_ts":"1.6","kind":"thread","state":"open"}' \
    '{"q_ts":"1.7","kind":"thread","state":"open"}' '{"q_ts":"1.8","h":"h1","state":"open"}' > "$S/desk-reply-wait.jsonl"
  printf '{"ts": %s, "c": 0, "teams": {"a": {"a":0,"b":0,"d":0,"f":1}, "b": {"a":0,"b":0,"d":0,"f":2}, "c": {"a":3,"b":1,"d":2,"f":0}, "x": {"diag": "_master 빔"}}}\n' \
    "$((NOW-60))" > "$S/stall-scan.last.json"
  printf '스크립트 0 · 인터뷰 0 · 막힌 팀 대기 0\n옛 설명\n## 옛 기록 1\n바이트 그대로\t끝\n' > "$S/planner-tick/TEAM-STATUS.md"
}
tool() { python3 "$P" --root "$R" --now "$NOW" "$@"; }
line() { sed -n "${2}p" "$1"; }
tail3() { tail -n +3 "$1" | shasum | cut -d' ' -f1; }
head_of() {  # status_head.head() — 가짜 루트(경보 표식 · mbox 0)
  ( cd "$KIT" && FT_ROOT="$R" FT_TEAM_STATUS_FILE="$1" python3 -c 'import status_head as s; print(s.head())' 2>/dev/null )
}
[ -f "$P" ] || { echo "FAIL ft_team_status_line.py 없음(기준판 Red)"; echo "FAILED 1"; exit 1; }

# ① 세 칸 · 3행부터 · head()
world w1; F="$S/planner-tick/TEAM-STATUS.md"; before="$(tail3 "$F")"
out="$(tool --hil 2)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$L1" ] && ok "① 출력 = 1행" || bad "① rc=$rc out=$out"
[ "$(line "$F" 1)" = "$L1" ] && ok "① 1행 «${L1}»" || bad "① 1행 $(line "$F" 1)"
line "$F" 2 | grep -qE '^설명: desk 틱 [0-9][0-9]:[0-9][0-9] · 자율 ft-autonomy.sh status [0-9][0-9]:[0-9][0-9] · .* · 담당 없음 ft-directive-watch.sh status [0-9][0-9]:[0-9][0-9]$' && ok "① 2행 설명" || bad "① 2행 $(line "$F" 2)"
[ "$(tail3 "$F")" = "$before" ] && ok "① 3행부터 바이트 같음" || bad "① 3행부터 바뀜"
[ "$(head_of "$F")" = "$L1" ] && ok "① head() = 1행" || bad "① head()=$(head_of "$F")"

# ② --hil ? → «스크립트 ?» · head() 그대로 · 경보 표식 0
world w2; F="$S/planner-tick/TEAM-STATUS.md"
tool --hil '?' >/dev/null
[ "$(line "$F" 1)" = "$(exp '5(가장 오래 0시간)' '?' 2)" ] && ok "② 1행 «스크립트 ?»" || bad "② 1행 $(line "$F" 1)"
[ "$(head_of "$F")" = "$(exp '5(가장 오래 0시간)' '?' 2)" ] && ok "② head() = 1행(형식 경보 0)" || bad "② head()=$(head_of "$F")"
[ -e "$R/.fable-team/state/status-head-alarm.txt" ] && bad "② 경보 표식 생김" || ok "② 경보 표식 0"

# ③ last.json 11분 전 · 없음 → 막힌 팀 «?»
world w3; F="$S/planner-tick/TEAM-STATUS.md"
printf '{"ts": %s, "teams": {"a": {"f": 1}}}\n' "$((NOW-660))" > "$S/stall-scan.last.json"
[ "$(tool --hil 2)" = "$(exp '5(가장 오래 0시간)' 2 '?')" ] && ok "③ 11분 낡음 → «?»" || bad "③ 낡음 $(line "$F" 1)"
rm -f "$S/stall-scan.last.json"
[ "$(tool --hil 2)" = "$(exp '5(가장 오래 0시간)' 2 '?')" ] && ok "③ 없음 → «?»" || bad "③ 없음 $(line "$F" 1)"

# ④ 장부 깨진 줄 → 오빠 답 기다림 «?» · 장부 없음 = 아직 등록 0(r2389 계약)
world w4
printf '{"q_ts":"1.1","kind":"question","state":"open"}\n{깨짐\n' > "$S/desk-reply-wait.jsonl"
[ "$(tool --hil 2)" = "$(exp '?' 2 2)" ] && ok "④ 깨진 줄 → «?»" || bad "④ 깨진 줄 $(line "$F" 1)"
rm -f "$S/desk-reply-wait.jsonl"
[ "$(tool --hil 2)" = "$(exp '0(가장 오래 0시간)' 2 2)" ] && ok "④ 없음 → 0(아직 등록 0)" || bad "④ 없음 $(line "$F" 1)"

# ⑤ 파일 없음 → 2행 새로 · 폴더 없음 → rc≠0 «판정 불가» 1줄 · 파일 0
world w5; F="$S/planner-tick/TEAM-STATUS.md"; rm -f "$F"
tool --hil 2 >/dev/null
[ "$(wc -l < "$F" | tr -d ' ')" = 2 ] && [ "$(line "$F" 1)" = "$L1" ] && ok "⑤ 새 파일 2행" || bad "⑤ 새 파일 $(wc -l < "$F")줄"
rm -rf "$S/planner-tick"
out="$(tool --hil 2)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$out" | grep -q '판정 불가' && ok "⑤ 폴더 없음 → rc=$rc «판정 불가» 1줄" || bad "⑤ 폴더 없음 rc=$rc out=$out"
[ -e "$S/planner-tick" ] && bad "⑤ 폴더 · 파일 생김" || ok "⑤ 파일 0"

# ⑥ 같은 입력 두 번 → 1행 · 3행부터 같음
world w6; F="$S/planner-tick/TEAM-STATUS.md"
tool --hil 2 >/dev/null; a1="$(line "$F" 1)"; a3="$(tail3 "$F")"
NOW=$((NOW+60)) tool --hil 2 >/dev/null
[ "$(line "$F" 1)" = "$a1" ] && [ "$(tail3 "$F")" = "$a3" ] && ok "⑥ 두 번 → 1행 · 3행부터 같음" || bad "⑥ 달라짐"

# ⑨ question open q_ts=X 뒤 thread open q_ts=X → 인터뷰 1
world w9
printf '%s\n' '{"q_ts":"9.9","kind":"question","state":"open"}' '{"q_ts":"9.9","kind":"thread","state":"open"}' > "$S/desk-reply-wait.jsonl"
[ "$(tool --hil 0)" = "$(exp '2(가장 오래 0시간)' 0 2)" ] && ok "⑨ 열쇠 (kind, q_ts) → 오빠 답 기다림 2(kind 전부 · r2390 K2)" || bad "⑨ $(line "$S/planner-tick/TEAM-STATUS.md" 1)"

# ⑦ desk 틱 가짜 세계(r1462 꼴 · 가짜 mbox · ft-hil · launchctl · ps · 원장 git)
world w7; F="$S/planner-tick/TEAM-STATUS.md"; FB="$T/fb"; mkdir -p "$FB" "$R/.fable-team/comm"
DESK='byz-planner-desk-claude#121'; PLANNER='byz-planner-master-claude#240'
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$R/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\ncase "$1" in send) echo QUEUED; exit 0;; peek) echo "pending=0 scanned=1 lineage=fake"; exit 0;; esac\nexit 2\n' > "$R/.fable-team/comm/mbox.sh"
printf '#!/usr/bin/env bash\n[ -n "${FAKE_HIL_RC:-}" ] && exit "$FAKE_HIL_RC"\nprintf "h1 3\\nh2 5\\n"\n' > "$FB/ft-hil.sh"
printf '#!/usr/bin/env bash\necho "$2"; echo "	state = running"; echo "	last exit code = 0"\n' > "$FB/launchctl"
printf '#!/usr/bin/env bash\necho "4242 python3 -u - %s/.fable-team/bin %s"\n' "$R" "$DESK" > "$FB/ps"
printf 'import sys\nprint("가짜 머리 실패")\nsys.exit(3)\n' > "$FB/head3.py"
chmod +x "$FB/launchctl" "$FB/ps"   # 시험 픽스처만 실행 비트(리포 파일 0)
printf 'ts=%s stall=0 a=0 b=0 c=0 d=0 seats=1\n' "$NOW" > "$T/stall.log"
: > "$R/.fable-team/comm/mailbox.log.jsonl"
( cd "$R" && git init -q && mkdir -p design/teams/planner && printf '## 골 진행\n\n| 1 | a |\n\n## 끝\n' > design/teams/planner/PLAN-oppa-ledger.md && git add design && git -c user.email=t@t -c user.name=t commit -qm t && git update-ref refs/remotes/origin/main HEAD && git update-ref refs/remotes/origin/ops/main-base HEAD )
tick7() {
  env FT_ROOT="$R" FT_HIL_DIR="$T" FT_DESK_TICK_MBOX="$R/.fable-team/comm/mbox.sh" FT_DESK_TICK_HIL="$FB/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$FB/launchctl" FT_DESK_TICK_PS="$FB/ps" FT_DESK_TICK_STALL_LOG="$T/stall.log" \
      FT_DESK_TICK_LOG="$R/.fable-team/comm/mailbox.log.jsonl" FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 \
      bash "$H/bin/ft-desk-tick.sh" "$DESK" 2>&1
}
out="$(tick7)"; rc=$?
printf '%s\n' "$out" | grep -qxF "머리 $L1" && ok "⑦ «머리 ${L1}» 1줄 (rc=$rc)" || bad "⑦ 머리 줄: $(printf '%s' "$out" | tr '\n' '/')"
[ "$(line "$F" 1)" = "$L1" ] && ok "⑦ TEAM-STATUS 1행 갱신" || bad "⑦ 1행 $(line "$F" 1)"
printf '%s\n' "$out" | tail -2 | head -1 | grep -q '^초:' && printf '%s\n' "$out" | tail -1 | grep -q '^결정 필요: ' && ok "⑦ 마지막 2줄 «초:» · «결정 필요»" || bad "⑦ 끝 2줄"
rc0=$rc; rm -rf "$S/planner-tick"
out="$(tick7)"; rc=$?
printf '%s\n' "$out" | grep -qx '머리 생략(폴더 없음)' && [ "$rc" -eq "$rc0" ] && [ ! -e "$S/planner-tick" ] && ok "⑦ 폴더 없음 → 생략 1줄 · rc=$rc 같음 · 파일 0" || bad "⑦ 폴더 없음 rc=$rc/$rc0"
mkdir -p "$S/planner-tick"
out="$(FT_DESK_TICK_HEAD="$FB/head3.py" tick7)"; rc=$?
printf '%s\n' "$out" | grep -qx '머리 판정 불가 rc=3' && [ "$rc" -eq 1 ] && ok "⑦ 머리 rc3 → «머리 판정 불가 rc=3» · 전체 rc1" || bad "⑦ rc3 세계 rc=$rc"
out="$(FAKE_HIL_RC=4 tick7)"; rc=$?
line "$F" 1 | grep -q ' · 스크립트 ? · ' && ok "⑦ ft-hil rc≠0 → «스크립트 ?»" || bad "⑦ hil 실패 1행 $(line "$F" 1)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
