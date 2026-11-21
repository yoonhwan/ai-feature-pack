#!/usr/bin/env bash
# test_board_news_wait_r2389.sh — 오빠 대기 실측 3곳 · 기다림 줄 · 원장 낡음 · 접기 0 · 수집 실패 골 칸 (r2389 K1~K6 · 반례 ①~⑬).
#   ① 장부 열린 줄 1 = 오빠 할 일 1줄 ② 팀장 [HIL] 쪽지 1줄 + «(질문 장부 등록 0)» ③ ②+① = 중복 0 ④ 마지막 1통만
#   ⑤ 장부 깨짐 = «판정 불가» 1줄 ⑥ 셋 다 0 = «없음» ⑦ 줄 꼴·태그 1개 ⑧ 원장 «기다림» 칸·단계 글 ⑨ 골 줄 대조
#   ⑩ 시각만 바뀐 두 판 = 열쇠 그대로 ⑪ 원장 12시간 낡음 = 머리 줄 + planner 1통(같은 sha 두 번 0) ⑫ 접기 0 · 넘으면 발행 0
#   ⑬ 수집 실패 팀 = 그 골 기다림 줄 끝 · 모르면 todo 꼬리 줄만 · 변이 M1~M9
# 실 Slack · 실 mbox · 실 df 0 (FT_MBOX_SH·FT_BOARD_DF 스텁) · sleep 0. R2389_BIN = 시험할 bin(기준판 · 변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2389_BIN:-$HERE/../bin}"
NOW="2026-11-21T16:03"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SENT="$T/stub/sent.log"
mkdir -p "$T/ft/.fable-team/state" "$T/ft/.fable-team/comm" "$T/stub"
: > "$SENT"
printf '#!/usr/bin/env bash\necho "$2|$4" >> "%s"\n' "$SENT" > "$T/stub/mbox.sh"
printf '#!/usr/bin/env bash\nprintf "Filesystem 1G-blocks Used Available Capacity\\ndev 100 1 52 3%%%%\\n"\n' > "$T/stub/df.sh"
chmod +x "$T/stub/mbox.sh" "$T/stub/df.sh"

# ── 명부 · 장부 · 우편함 (K1 세 출처)
printf '{"_label": "planner", "_master": "byz-planner-master-pi#368", "_desk": "byz-planner-desk-pi#127"}\n' > "$T/ft/.fable-team/seats-planner.json"
printf '{"_label": "cfo", "_master": "byz-cfo-master-pi#1"}\n' > "$T/ft/.fable-team/seats-cfo.json"
led() {  # led <json 줄들...> — 장부(state/desk-reply-wait.jsonl) 새로 쓰기
  : > "$T/ft/.fable-team/state/desk-reply-wait.jsonl"
  local l; for l in "$@"; do printf '%s\n' "$l" >> "$T/ft/.fable-team/state/desk-reply-wait.jsonl"; done; }
: > "$T/ft/.fable-team/state/desk-reply-wait.jsonl"
mail() {  # mail <json 줄들...> — 우편 기록 새로 쓰기 (seq · ts · from · to · body)
  : > "$T/ft/.fable-team/comm/mailbox.jsonl"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$T/ft/.fable-team/comm/mailbox.jsonl"; done; }
: > "$T/ft/.fable-team/comm/mailbox.jsonl"
EPOCH="$(python3 -c 'import datetime;print(int(datetime.datetime.fromisoformat("'"$NOW"'").timestamp()))')"
at() { python3 -c 'import sys;print(int(sys.argv[1])-int(float(sys.argv[2])*3600))' "$EPOCH" "$1"; }  # at <시간 전>
QTS="1795244606.826379"
# K1 — waits() 한 번 (실 자료 · 게시판과 같은 함수)
waits() { python3 - "$BIN" "$T/ft" "$EPOCH" <<'PY'
import json, pathlib, sys
sys.path.insert(0, sys.argv[1])
import ft_board_mail as m
import ft_board_news_wait as w
root = pathlib.Path(sys.argv[2])
print(json.dumps(w.waits(root, [], m.Mail(root), float(sys.argv[3])), ensure_ascii=False))
PY
}
W() { waits | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
HIL_BODY=$'[HIL] 카드 대기 2 · 오빠 승인 필요 · 다음 수: 10249 오빠 approve-merge 대기\n골좌표: 1 — B2B 토스 결제 시험'
hil() { python3 -c 'import json,sys;print(json.dumps({"seq":int(sys.argv[1]),"ts":sys.argv[2],"from":sys.argv[3],"to":sys.argv[4],"body":sys.argv[5]}, ensure_ascii=False))' "$1" "$2" "$3" "$4" "$5"; }
goal7() {  # goal7 <행...> — «기다림» 칸이 있는 7 column 원장
  { printf '## 골 진행\n\n| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 | 기다림 |\n|---|---|---|---|---|---|---|\n'
    local r; for r in "$@"; do printf '| %s |\n' "$r"; done; } > "$T/goal.md"; }
goal6() {  # goal6 <행...> — «기다림» 칸 없는 6 column 원장
  { printf '## 골 진행\n\n| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 |\n|---|---|---|---|---|---|\n'
    local r; for r in "$@"; do printf '| %s |\n' "$r"; done; } > "$T/goal.md"; }
collect() {  # collect <h> <err쉼표> <waits json> [card_goals json] — collect.json 한 장
  python3 - "$T/collect.json" "$1" "$2" "$3" "${4:-{}}" <<'PY'
import json, sys
out, h, err, waits, cg = sys.argv[1], int(sys.argv[2]), sys.argv[3], json.loads(sys.argv[4] or "{}"), json.loads(sys.argv[5])
team = {"key": "harness", "label": "하네스", "states": {}, "counts": {"완성": 0, "진행": 0, "대기": 0, "중복": 0}, "progress": {}, "seats": {},
        "oppa_todo": list(range(h)), "axes": [], "goals": {}, "done_on": {}}
teams = [team] + [{"key": t, "label": t, "error": "깨짐"} for t in err.split(",") if t]
cg = {**cg, "하네스": {}}
for t in teams:
    if t["key"] in cg:
        t["goals"] = cg[t["key"]]
json.dump({"date": "2026-11-21", "verdicts": [], "issues": [], "teams": teams, "waits": waits}, open(out, "w"), ensure_ascii=False)
PY
}
news() {  # news <HH:MM> [장부 시각] — 게시판 1판
  RC=0; rm -f "$T/body.txt"
  env FT_ROOT="$T/ft" FT_MBOX_SH="$T/stub/mbox.sh" FT_OPPA_SLACK_UID=U1 FT_BOARD_DF="bash $T/stub/df.sh" \
      FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="2026-11-21T$1" \
      python3 "$BIN/ft_board_news.py" --collect "$T/collect.json" --last "$T/last.json" --body "$T/body.txt" --state "$T/state.json" > "$T/out" 2> "$T/err" || RC=$?
  [ "$(cat "$T/out" 2>/dev/null)" = POST ] && cp "$T/state.json" "$T/last.json"; true; }
todo() { awk '/^막힌 것, 오빠 할 일$/{f=1;next} /^근거:/{f=0} f' "$T/body.txt"; }
keyof() { python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["key"],ensure_ascii=False))' "$T/state.json" 2>/dev/null; }
lastsnap() {  # lastsnap <카드 골좌표 json> — 직전 snap(news-last.json) 한 장
python3 - "$T/last.json" "$1" <<'PY'
import json, sys
cg = json.loads(sys.argv[2])
snap = {"goals": [], "cards": {t: {c: "진행" for c in v} for t, v in cg.items()}, "counts": {t: [0, 1, 0] for t in cg},
        "sessions": {}, "h_by": {}, "err": [], "carried": [], "masterless": [], "card_goals": cg,
        "done_on": {t: {} for t in cg}, "h": 0, "waits": {"a": [], "b": [], "c": [], "bad": []}}
json.dump({"at": "2026-11-21T15:50:00", "key": ["옛 판"], "snap": snap}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
want() { [ -z "${R2389_ONLY:-}" ] || [[ " ${R2389_ONLY:-} " == *" $1 "* ]]; }  # 사례 번호 하나만 돌리기
reset() { rm -rf "$T/ft/.fable-team/state/board" "$T/last.json" "$T/body.txt" "$T/state.json" "$T/out" "$T/err"; : > "$SENT"; }

if want ①; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ① 장부 열린 줄 1 = «오빠 할 일» 1줄 (기준판 = «없음» → Red)
reset; led "{\"q_ts\": \"$QTS\", \"kind\": \"thread\", \"key\": \"pr10249-approve\", \"at\": $(at 15), \"deadline\": $(at -9), \"state\": \"open\"}"; mail
collect 0 "" "$(waits)"
goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기"
chk "① K1 ⓑ = 열린 줄 1 (pr10249-approve · 15시간 전)" '[ "$(W "len(d[\"b\"])")" = 1 ] && [ "$(W "d[\"b\"][0][\"key\"]")" = pr10249-approve ]'
news 16:03
if [ -n "${DBG:-}" ]; then echo "--BODY--" >&2; cat "$T/body.txt" >&2; echo "--OUT--" >&2; cat "$T/out" "$T/err" >&2; fi
chk "① «오빠 할 일» = 그 1줄(«없음» 0) · 태그 1개" '[ "$(todo | grep -c "^<@U1> pr10249-approve 질문 — desk 기다림 · 01:03(15시간)$")" = 1 ] && [ "$(grep -c "<@" "$T/body.txt")" = 1 ]'
chk "① 기준판 글 «없음» 0" '! todo | grep -qx "없음"'

fi
if want ②; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ② 팀장 [HIL] 쪽지 = 1줄 + «(질문 장부 등록 0)»
reset; led; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")"
collect 0 "" "$(waits)"
if [ -n "${DBG:-}" ]; then echo "--W--" >&2; waits >&2; echo "--MB--" >&2; cat "$T/ft/.fable-team/comm/mailbox.jsonl" >&2; fi
news 16:03
chk "② ⓒ = cfo · «다음 수» 글 · 골좌표" '[ "$(W "len(d[\"c\"])")" = 1 ] && [ "$(W "d[\"c\"][0][\"team\"]")" = cfo ] && [ "$(W "d[\"c\"][0][\"next\"]")" = "10249 오빠 approve-merge 대기" ]'
chk "② «오빠 할 일» 1줄 · 끝 «(질문 장부 등록 0)»" '[ "$(todo | grep -c "^<@U1> 10249 오빠 approve-merge 대기 — cfo 기다림 · 15:25(0시간) (질문 장부 등록 0)$")" = 1 ]'

fi
if want ③; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ③ ② + 장부 같은 PR = 중복 0
reset; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")"
led "{\"q_ts\": \"$QTS\", \"kind\": \"thread\", \"key\": \"pr10249-approve\", \"at\": $(at 15), \"deadline\": $(at -9), \"state\": \"open\"}"
collect 0 "" "$(waits)"; news 16:03
chk "③ ⓒ 0(같은 PR 번호가 장부에 있음) · «오빠 할 일» 1줄" '[ "$(W "len(d[\"c\"])")" = 0 ] && [ "$(todo | grep -c "기다림")" = 1 ]'

fi
if want ④; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ④ 팀장 마지막 1통이 [정리] = ⓒ 0
reset; led; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")" \
            "$(hil 9 "2026-11-21T15:40:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 '[정리] 골 진행 원장 낡음 3시간')"
collect 0 "" "$(waits)"; news 16:03
chk "④ ⓒ 0(마지막 1통만) · «없음»" '[ "$(W "len(d[\"c\"])")" = 0 ] && todo | grep -qx "없음"'

fi
if want ⑤; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑤ 장부 한 줄 깨짐 = «판정 불가» 1줄 · «없음» 0
reset; printf '{"q_ts": "%s", "state": "open"}\n{깨진 줄\n' "$QTS" > "$T/ft/.fable-team/state/desk-reply-wait.jsonl"; mail
collect 0 "" "$(waits)"; news 16:03
chk "⑤ «오빠 질문 장부 판정 불가» 1줄 · «없음» 0" '[ "$(todo | grep -cxF "오빠 질문 장부 판정 불가")" = 1 ] && ! todo | grep -qx "없음"'

fi
if want ⑥; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑥ 셋 다 0 · 판정 불가 0 = «없음»
reset; led; mail; collect 0 "" "$(waits)"; news 16:03
chk "⑥ «없음» 1줄 · 태그 0" 'todo | grep -qx "없음" && [ ! -s "$SENT" ]'

fi
if want ⑦; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑦ ①+② 한 판 = 줄 꼴 · 태그 첫 줄 1개
reset; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")"
led "{\"q_ts\": \"$QTS\", \"kind\": \"question\", \"key\": \"ops-live-token\", \"at\": $(at 7), \"deadline\": $(at -17), \"state\": \"open\"}"
collect 0 "" "$(waits)"; news 16:03
chk "⑦ 두 줄 · 첫 줄만 태그 · «HH:MM(N시간)» 꼴" '[ "$(todo | wc -l | tr -d " ")" = 2 ] && [ "$(grep -c "<@" "$T/body.txt")" = 1 ] && todo | head -1 | grep -q "^<@U1> ops-live-token 질문 — desk 기다림 · 09:03(7시간)$" && todo | tail -1 | grep -qxF "10249 오빠 approve-merge 대기 — cfo 기다림 · 15:25(0시간) (질문 장부 등록 0)"'

fi
if want ⑧; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑧ 원장 «기다림» 칸 = 그 글 · 없으면 «둘 다 없음» · 단계 글
reset; led; mail; collect 0 "" "$(waits)"
goal7 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기 | planner 가 원장 고치는 중" "2 | 세션 생명주기 | — | — | 대기 | 없음 |"
news 16:03
chk "⑧ 칸 글 = 기다림 줄 · 숫자 = «지금 3/5단계»" '[ "$(grep -cF "지금 3/5단계 · 기다림: planner 가 원장 고치는 중" "$T/body.txt")" = 1 ]'
chk "⑧ 빈 칸 = «둘 다 없음» · «—» = «단계 수 원장에 없음»" '[ "$(grep -cF "단계 수 원장에 없음 · 기다림: 원장·오빠 대기 실측 둘 다 없음" "$T/body.txt")" = 1 ]'

fi
if want ⑨; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑨ ② 판 = B2B 골 줄에만 «기다림: cfo · …»
reset; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")"
collect 0 "" "$(waits)"
goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기" "2 | 세션 생명주기 | 1 | 4 | 진행 중 | 다음 손"
news 16:03
chk "⑨ B2B 골 줄 = «기다림: cfo · 10249 오빠 approve-merge 대기 · 15:25»" '[ "$(grep -cF "지금 3/5단계 · 기다림: cfo · 10249 오빠 approve-merge 대기 · 15:25" "$T/body.txt")" = 1 ]'
chk "⑨ 다른 골 줄엔 기다림 줄 0" '[ "$(grep -c "기다림:" "$T/body.txt")" = 1 ]'

fi
if want ⑩; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑩ 기다림 줄 시각만 바뀐 두 판 = 열쇠 그대로 (30분 짧은 글)
reset; mail "$(hil 7 "2026-11-21T15:25:00" byz-cfo-master-pi#1 byz-planner-master-pi#368 "$HIL_BODY")"
collect 0 "" "$(waits)"
goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기"; news 16:03
K1V="$(keyof)"; news 16:40
chk "⑩ 열쇠 같음 · 30분 짧은 글(«변화 없음, 지난 글 16:03»)" '[ -n "$K1V" ] && [ "$(keyof)" = "$K1V" ] && head -1 "$T/body.txt" | grep -qxF "변화 없음, 지난 글 16:03"'

fi
if want ⑪; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑪ 원장 12시간 낡음 = 머리 줄 + planner 1통 · 같은 sha 두 번 0 · 1시간 전 = 0
reset; led; mail; collect 1 "" "$(waits)"
goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기"; touch -t 202611210403 "$T/goal.md"
news 16:03
chk "⑪ 머리 줄 «원장 낡음 12시간(04:03 판)» = 2번째 줄" '[ "$(sed -n 2p "$T/body.txt")" = "원장 낡음 12시간(04:03 판) — 골 상태 글은 그때 값" ]'
chk "⑪ planner _master 1통 «[정리 요청] … 원장 sha»" '[ "$(grep -c "^byz-planner-master-pi#368|\[정리 요청\] 골 진행 원장 낡음 12시간" "$SENT")" = 1 ]'
collect 2 "" "$(waits)"; news 16:10
chk "⑪ 같은 원장 sha 다시 발행 = 1통 더 0" '[ "$(wc -l < "$SENT" | tr -d " ")" = 1 ]'
reset; led; mail; collect 0 "" "$(waits)"; goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기"; touch -t 202611211503 "$T/goal.md"; news 16:03
chk "⑪ 1시간 전 = 머리 줄 0 · 쪽지 0" '! grep -qF "원장 낡음" "$T/body.txt" && [ ! -s "$SENT" ]'
chk "⑪ 시각 모름 = «원장 시각 판정 불가»" '[ "$(cd "$BIN" && python3 -c "import ft_board_news_wait as w; from datetime import datetime; print(w.stale_head(None, datetime(2026,11,21,16,3)).startswith(\"원장 시각 판정 불가\"))")" = True ]'

fi
if want ⑫; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑫ 접기 0 — 골 12개 + 긴 «다음» 글 = 다 싣고 줄임 · 30골 = 발행 0
reset; led; mail; collect 0 "" "$(waits)"
V="$(python3 -c 'print("나"*400)')"; rows=(); for i in $(seq 1 12); do rows+=("$i | 넘침 골 $i | 3 | 5 | 진행 중 | $V"); done
goal6 "${rows[@]}"; news 16:03
chk "⑫ «그 밖의 골 N개» 0 · «다음» 12줄 50자로 줄임 · ≤3500B" '! grep -qE "그 밖의 골 [0-9]+개" "$T/body.txt" && [ "$(grep -cE "^넘침 골 [0-9]+: 나{50}$" "$T/body.txt")" = 12 ] && [ "$(wc -c < "$T/body.txt")" -le 3500 ]'
rows=(); for i in $(seq 1 30); do rows+=("$i | 넘침 골 $i | 3 | 5 | 진행 중 | $V"); done
reset; goal6 "${rows[@]}"; news 16:03
chk "⑫ 30골 = rc 1 «> 3500B — 발행 0» · 본문 0" '[ "$RC" = 1 ] && grep -q "B > 3500B — 발행 0" "$T/err" && [ ! -e "$T/body.txt" ]'

fi
if want ⑬; then  # R2389_ONLY 로 한 사례만 돌린다(변이 사본 = 그 사례 1회)
# ── ⑬ 수집 실패 팀 = 그 골 기다림 줄 끝 «· 수집 실패: graphics»
reset; led; mail; lastsnap '{"graphics": {"c1": "3 — 세션 생명주기"}}'; collect 0 "graphics" "$(waits)"
goal6 "1 | B2B 토스 | 3 | 5 | 진행 중 | 시험 붙이기" "2 | 세션 생명주기 | 1 | 4 | 진행 중 | 다음 손"; news 16:03
chk "⑬ 세션 생명주기 골 줄 끝 «· 수집 실패: graphics»" '[ "$(grep -c "기다림: 원장·오빠 대기 실측 둘 다 없음 · 수집 실패: graphics$" "$T/body.txt")" = 1 ] && [ "$(grep -c "· 수집 실패" "$T/body.txt")" = 1 ]'
reset; led; mail; lastsnap '{}'; collect 0 "graphics" "$(waits)"; news 16:03
chk "⑬ 직전 snap 에도 없으면(어느 골인지 모름) 골 칸 표시 0" '[ "$(grep -c "· 수집 실패" "$T/body.txt")" = 0 ]'

fi
# ── 변이 M1~M9 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
mut() {  # mut <이름> <파일> <바꿀 글> <새 글>
  rm -rf "$T/mut"; cp -R "$BIN" "$T/mut"
  python3 - "$T/mut/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 자리 없음: " + old[:40]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
runmut() {  # runmut <이름> <파일> <바꿀 글> <새 글> <기대 FAIL> <사례 번호> — 사본으로 이 시험을 다시 돌려 그 사례가 FAIL 인지
  mut "$1" "$2" "$3" "$4" || { bad "변이 $1 적용 실패"; return; }
  local out; out="$(R2389_ONLY="$6" R2389_BIN="$T/mut" bash "${BASH_SOURCE[0]:-$0}" 2>&1)"; local rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "^FAIL $5"; then ok "변이 $1 → «$5» FAIL(시험이 잡는다)"; else bad "변이 $1 → «$5» 안 잡힘(rc=$rc)"; fi; }
if [ -z "${R2389_BIN:-}" ]; then
  runmut M1 ft_board_news_wait.py '    out = [f"{x['"'"'key'"'"']} 질문 — desk 기다림{t(x)}" for x in w.get("b") or []]' '    out = []' "① «오빠 할 일»" ①
  runmut M2 ft_board_news_wait.py '    c = [x for x in c if not (set(x["pr"]) & bpr) and x["next"] not in keys and not (pr_nums(x["next"]) & bpr)]' '    c = c' "③ ⓒ 0" ③
  runmut M3 ft_board_news_wait.py '        last = max(mine, key=lambda r: r["seq"])' '        last = mine[0]' "④ ⓒ 0" ④
  runmut M4 ft_board_news_wait.py '        return None, "오빠 질문 장부 판정 불가"' '        return [], ""' "⑤ «오빠 질문 장부 판정 불가»" ⑤
  runmut M5 ft_board_news_wait.py '(질문 장부 등록 0)" for x in w.get("c") or []]' '" for x in w.get("c") or []]' "② «오빠 할 일»" ②
  runmut M6 ft_board_news_wait.py '    w, out = cur.get("waits") or {}, []' '    return []' "⑧ 칸 글" ⑧
  runmut M7 ft_board_news.py '    return standing(s) + ["다음", *next_key(s), "완성", *done]' '    return standing(s) + goal_waits(s) + ["다음", *next_key(s), "완성", *done]' "⑩ 열쇠 같음" ⑩
  runmut M8 ft_board_news.py 'beat=beat, stale=stale_head(ledger_at, now))' 'beat=beat, stale="")' "⑪ 머리 줄" ⑪
  runmut M9 ft_board_news_body.py '        out = clip_next(out)' '        for k in range(len(steps), -1, -1):
            nxt2 = steps[:k] + ([f"그 밖의 골 {len(steps) - k}개"] if k < len(steps) else []) if steps else [NO_NEXT]
            if len((o2 := text(st, [], nxt2)).encode()) <= MAX_BYTES:
                out = o2' "⑫ «그 밖의 골 N개» 0" ⑫
fi
echo "--- r2389 wait: FAIL $fail"
[ "$fail" -eq 0 ]
