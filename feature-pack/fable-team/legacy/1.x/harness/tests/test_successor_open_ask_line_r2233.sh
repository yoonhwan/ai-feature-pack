#!/usr/bin/env bash
# test_successor_open_ask_line_r2233.sh — r2233: desk 승계 본문 첫 10줄에 planner 안내서 «- **desk 묻는 기준**» 줄 뒤 글이 없으면 열지 않는다.
# 실 파일만 읽는다(쓰기 0): 안내서 = BYZ 리포 <ref>:design/teams/planner/GUIDE-planner.md · 템플릿 = state SUCC-BODY-desk-TEMPLATE.txt · 사건 본문 = bodies/332594.txt
# 반례 ①~⑤ + 변이 M1~M3(사본에서만 · 변이마다 원본으로 같은 사례 1회 더). FT_SO_PATH = 기준판(Red) 판을 줄 때.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO0="${FT_SO_PATH:-$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh}"; SO="$SO0"
BYZ="${FT_R2233_BYZ:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"
GREF="${FT_R2233_GUIDE_REF:-origin/main}"
TPL="${FT_R2233_TEMPLATE:-$BYZ/.fable-team/state/team-main/planner/SUCC-BODY-desk-TEMPLATE.txt}"
B594="${FT_R2233_BODY:-$BYZ/.fable-team/comm/bodies/332594.txt}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
MK='- **desk 묻는 기준**'

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REAL_GUIDE="$TMP/real-guide.md"
git -C "$BYZ" show "$GREF:design/teams/planner/GUIDE-planner.md" > "$REAL_GUIDE" 2>/dev/null
ASK_LINE="$(grep -F -- "$MK" "$REAL_GUIDE" | head -1)"
{ [ -f "$SO" ] && bash -n "$SO" && [ -n "$ASK_LINE" ] && [ -s "$TPL" ] && [ -s "$B594" ]; } \
  || { echo "FAIL 준비: SO=$SO · 안내서 $GREF 묻는 기준 줄=${ASK_LINE:+있음} · TPL=$TPL · BODY=$B594"; echo "FAILED 1"; exit 1; }

REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; OPENED="$TMP/opened"
mkdir -p "$REPO/design/teams/planner" "$FAKE"; git -C "$REPO" init -q
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'if [ "$1" = boot-enter ]; then exit 0; fi; echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox 'exit 0'; : > "$FAKE/mbox_doorbell.sh"; mkstub reach 'exit 0'
mkstub ps 'case "$1 $2 $3" in "-o lstart= -p") echo "Thu Jan  1 09:00:00 2026"; exit 0;; esac; exec /bin/ps "$@"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
mkdir -p "$RES/design" "$REPO/.fable-team" "$TMP/live"
printf '# TEAMS\n\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | byz-t-master-claude | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{"byz-t-master-claude":{"role":"master","model":"m"},"byz-t-tool-claude#1":{"role":"master","model":"m"},"byz-t-repro-claude#2":{"role":"master","model":"m"}}\n' > "$RES/.fable-team/seats-t.json"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-claude | — |\n' > "$TMP/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n<!-- S11-DESK-BEGIN -->\n6. desk 틱마다 직접 잰다.\n<!-- S11-DESK-END -->\n' > "$TMP/gov.md"
printf '%s\n' "$TMP/live" > "$REPO/.fable-team/LIVE_ROOT"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/teams/planner/` | p | 현역 |\n' > "$REPO/design/TEAMS.md"
guide_set() { cp "$1" "$REPO/design/teams/planner/GUIDE-planner.md"; git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m guide --allow-empty; git -C "$REPO" update-ref refs/remotes/origin/main HEAD; }
OLD='byz-planner-desk-claude#38'; NEW='byz-planner-desk-claude#39'
run() { # run <본문> — 출력 $TMP/out · rc $RC · 로그 초기화
  rm -f "$LOG" "$OPENED"; rm -rf "$REPO/.fable-team/state/successor"; : > "$LOG"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" OPENED="$OPENED" SENSORS="$SENSORS" FT_RES_ROOT="$RES" \
      FT_TEAMSET_MD="$TMP/teamset.md" FT_GOV_MD="$TMP/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=3 \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$1" > "$TMP/out" 2>&1
  RC=$?
}
sends() { grep -c '^send' "$LOG"; }
rejected() { [ "$RC" -ne 0 ] && grep -q REJECT "$TMP/out" && [ "$(sends)" = 0 ] && ! grep -q '^tmuxc' "$LOG"; }
passed() { [ "$RC" -eq 0 ] && [ "$(sends)" = 1 ]; }

# 픽스처(본문·안내서 판) — 실 파일에서만 만든다
ASK_CORE="$(printf '%s' "${ASK_LINE#"$MK"}" | sed 's/^[:[:space:]]*//')"
{ head -4 "$TPL"; echo '열린 칸 감시: 없음'; } > "$TMP/body_tpl.txt"   # 앞 단계 문(열린 칸 감시 1줄)을 지나려면 있어야 한다
{ sed -n 2p "$TPL"; for i in 1 2 3 4 5 6 7 8; do echo "채움 $i 줄"; done; echo '열린 칸 감시: 없음'; printf '%s\n' "$ASK_CORE"; } > "$TMP/body_11.txt"
sed 's/^- \*\*desk 묻는 기준\*\* /- **desk 묻는 기준**: /' "$REAL_GUIDE" > "$TMP/guide_colon.md"
grep -vF -- "$MK" "$REAL_GUIDE" > "$TMP/guide_0.md"
awk -v mk="$MK" '{print} index($0, mk) == 1 {print}' "$REAL_GUIDE" > "$TMP/guide_2.md"
R2235='- desk 의 오빠 질문은 byz_thread_post.py ask 로만 올린다 · 팀이 붙인 «자율 범위 밖» 은 근거가 아니다 · 선택지마다 D2 3문을 다시 묻고 «예» 인 선택지만 --d2 · --why · --default 로 묻는다 · 3문이 모두 «아니오» 면 그 턴에 고른다(D3) · 임시 게시 스크립트로 질문 0'
awk -v mk="$MK" -v add="$R2235" '{print} index($0, mk) == 1 {print add}' "$REAL_GUIDE" > "$TMP/guide_2235.md"

# ① 사건 본문(#332594) + 새 안내서 = REJECT · 묻는 기준 줄 원문 출력 · 송신 0
guide_set "$REAL_GUIDE"; run "$B594"
rejected && grep -q '묻는 기준 줄이 없다' "$TMP/out" && grep -qF -- "${ASK_CORE:0:60}" "$TMP/out" \
  && ok "① #332594 본문 → REJECT · 원문 출력 · open·송신 0" || bad "① rc=$RC" "$(cat "$TMP/out")"
# ② 실 템플릿 1~4행 + 실 안내서 줄 = 통과 · «:» 붙인 판도 통과
run "$TMP/body_tpl.txt"; passed && ok "② 실 템플릿 1~4행 + 실 안내서 → 통과 · 송신 1" || bad "② rc=$RC" "$(cat "$TMP/out")"
guide_set "$TMP/guide_colon.md"; run "$TMP/body_tpl.txt"
passed && ok "② 안내서 «**:» 판 → 통과 · 송신 1" || bad "② 콜론 rc=$RC" "$(cat "$TMP/out")"
# ③ 묻는 기준 줄이 11번째 줄 = REJECT
guide_set "$REAL_GUIDE"; run "$TMP/body_11.txt"
rejected && grep -q '묻는 기준 줄이 없다' "$TMP/out" && ok "③ 11번째 줄 → REJECT" || bad "③ rc=$RC" "$(cat "$TMP/out")"
# ④ 안내서 표식 0줄 · 2줄 = 판정 불가 REJECT(0줄 글에 fetch 1구)
guide_set "$TMP/guide_0.md"; run "$TMP/body_tpl.txt"
rejected && grep -q '사람이 확인' "$TMP/out" && grep -q 'git fetch origin 뒤 다시' "$TMP/out" \
  && ok "④ 표식 0줄 → REJECT 판정 불가 · fetch 1구" || bad "④0 rc=$RC" "$(cat "$TMP/out")"
guide_set "$TMP/guide_2.md"; run "$TMP/body_tpl.txt"
rejected && grep -q '줄이 여러 줄' "$TMP/out" && grep -q '사람이 확인' "$TMP/out" \
  && ok "④ 표식 2줄 → REJECT 판정 불가" || bad "④2 rc=$RC" "$(cat "$TMP/out")"
# ⑤ 불변: desk 아닌 이름 + #332594 본문 = 이 검사 출력 0 · r2233+r2235 두 줄 판에서 «desk 는 … N통)» 매치 1줄 · 템플릿 본문 통과
guide_set "$REAL_GUIDE"; OLD='byz-t-tool-claude#1'; NEW='byz-t-repro-claude#2'; run "$B594"
passed && ! grep -q '묻는 기준' "$TMP/out" && ok "⑤ desk 아닌 승계 → 이 검사 출력 0 · 송신 1" || bad "⑤ 비desk rc=$RC" "$(cat "$TMP/out")"
OLD='byz-planner-desk-claude#38'; NEW='byz-planner-desk-claude#39'
n="$(python3 -c 'import re,sys; print(sum(1 for g in open(sys.argv[1],encoding="utf-8").read().splitlines() if re.search(r"desk 는 .*?\d+통\)", g)))' "$TMP/guide_2235.md")"
guide_set "$TMP/guide_2235.md"; run "$TMP/body_tpl.txt"
[ "$n" = 1 ] && passed && ok "⑤ r2233·r2235 두 줄 판 → «N통)» 매치 1줄 · 템플릿 본문 통과" || bad "⑤ 두 줄 n=$n rc=$RC" "$(cat "$TMP/out")"

# 변이 M1~M3 — 사본에서만 · 변이 판 = 통과(빨강이어야 할 것이 초록) · 원본 = REJECT
mutate() { # mutate <이름> <sed 식> <grep 확인> → $MUT
  local d="$TMP/mut-$1"; mkdir -p "$d"; cp -R "$(dirname -- "$SO0")/." "$d/"; MUT="$d/$(basename -- "$SO0")"
  sed "$2" "$SO0" > "$MUT.tmp" && mv "$MUT.tmp" "$MUT" && grep -qF -- "$3" "$MUT"
}
mcase() { # mcase <이름> <안내서> <본문>
  guide_set "$2"; SO="$MUT"; run "$3"; local mrc=$RC mpass=0; passed && mpass=1
  SO="$SO0"; run "$3"
  [ "$mpass" = 1 ] && rejected && ok "$1 변이 = 통과 · 원본 = REJECT" || bad "$1 변이 rc=$mrc pass=$mpass · 원본 rc=$RC" "$(cat "$TMP/out")"
}
mutate M1 's/^if ask not in /if False and ask not in /' 'if False and ask not in ' && mcase "M1 검사 뺌 ①" "$REAL_GUIDE" "$B594" || bad "M1 적용 실패" ""
mutate M2 '/^if ask not in /s/lines\[:10\]/lines/' 'if ask not in " ".join(" ".join(lines).split())' && mcase "M2 첫 10줄→전체 ③" "$REAL_GUIDE" "$TMP/body_11.txt" || bad "M2 적용 실패" ""
mutate M3 's/^if len(asks) != 1:/if len(asks) < 1:/' 'if len(asks) < 1:' && mcase "M3 ==1→>=1 ④2줄" "$TMP/guide_2.md" "$TMP/body_tpl.txt" || bad "M3 적용 실패" ""

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
