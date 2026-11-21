#!/usr/bin/env bash
# test_desk_head_post_r2390.sh — 머리 줄 1통(Slack 메인) · 열쇠 · 3시간 재발행 · 낡음 · 실패 (r2390 반례 ⑦~⑫ · 변이 M5~M9).
#   ⑦ 열쇠 = 지금 · 0 아닌 칸 0 → 발행 0 | 열쇠 다름 → 1통 | «N분 전» 만 다름 → 0
#   ⑧ 열쇠 같음 · 오빠 답 기다림 2 · 3시간 10분 전 → 1통(«그대로 3시간» 꼬리) | 2시간 전 → 0
#   ⑨ 1행 20분 낡음 → 발행 0 · stderr 1줄 · rc0 ⑩ 발행 실패 → head-last 안 씀 · desk [긴급] 1통(30분 창)
#   ⑪ 태그 = 오빠 답 기다림 ≥1 ∨ 스크립트 ≥1 일 때만 1개 ⑫ desk 틱 지침 «머리 먼저» 절 · 정본 1줄 그대로
# 전부 합성(임시 루트 · 가짜 발행 도구 · 가짜 mbox) · 네트워크 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/.."
Q="${FT_HEAD_POST_PY:-$H/bin/ft_desk_head_post.py}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NOW=1795000000
iso() { python3 -c 'import sys,time; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(int(sys.argv[1]))))' "$1"; }
L_HIT='자율 ON A19 풀자동 · 오빠 답 기다림 2(가장 오래 15시간) · 스크립트 2 · 막힌 팀 2 · planner [정리] 17:00(40분 전) · 원장 낡음 0 · 오빠 지시 멈춤 4 · 담당 없음 3'
L_ZERO='자율 OFF · 오빠 답 기다림 0(가장 오래 0시간) · 스크립트 0 · 막힌 팀 0 · planner [정리] 17:00(40분 전) · 원장 낡음 0 · 오빠 지시 멈춤 0 · 담당 없음 0'

cat > "$T/tp.py" <<'PY'
import json, os, sys
with open(os.environ["FAKE_TP_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"argv": sys.argv[1:], "text": open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read()}, ensure_ascii=False) + "\n")
sys.exit(int(os.environ.get("FAKE_POST_RC") or 0))
PY
printf '#!/usr/bin/env bash\necho "$*" >> "$FAKE_MBOX_LOG"\n' > "$T/mbox.sh"
export FT_THREAD_POST="$T/tp.py" FAKE_TP_LOG="$T/tp.log" FAKE_MBOX_LOG="$T/mbox.log" FT_MBOX="$T/mbox.sh"
export FT_BOARD_POST_ARGS="--channel C-MAIN" FT_OPPA_SLACK_UID="U0OPPA"
: > "$FAKE_TP_LOG"; : > "$FAKE_MBOX_LOG"

world() {  # world <이름> <1행> [head-last 의 at 오프셋 초]
  R="$T/$1"; mkdir -p "$R/.fable-team/state/planner-tick" "$R/.fable-team/state/board" "$R/.fable-team/comm"
  printf '%s\n설명: desk 틱 17:40 · 출처\n## 옛 기록\n바이트 그대로\t끝\n' "$2" > "$R/.fable-team/state/planner-tick/TEAM-STATUS.md"
  python3 -c 'import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' \
    "$R/.fable-team/state/planner-tick/TEAM-STATUS.md" "${3:-$((NOW-60))}"
  printf '{"_master":"byz-planner-master-pi#398","_desk":"byz-planner-desk-claude#121"}\n' > "$R/.fable-team/seats-planner.json"
  : > "$FAKE_TP_LOG"; : > "$FAKE_MBOX_LOG"
  ST="$R/.fable-team/state/planner-tick/TEAM-STATUS.md"; LAST="$R/.fable-team/state/board/head-last.json"
}
key_of() {  # 1행 → 열쇠 json («(N분 전)» 제거 · ft_desk_head_post.key_of 와 같은 꼴)
  python3 - "$1" <<'PY'
import json, re, sys
print(json.dumps([re.sub(r"\([0-9]+분 전\)", "", c).strip() for c in sys.argv[1].split(" · ")], ensure_ascii=False))
PY
}
last_with() {  # last_with <at epoch> <1행>
  printf '{"at": %s, "key": %s}\n' "$1" "$(key_of "$2")" > "$LAST"
}
run() { python3 "$Q" --root "$R" --now "$(iso "${1:-$NOW}")" 2>"$T/err"; }
posts() { wc -l < "$FAKE_TP_LOG" | tr -d ' '; }
[ -f "$Q" ] || { echo "FAIL ft_desk_head_post.py 없음(기준판 Red)"; echo "FAILED 1"; exit 1; }

# ⑦ 열쇠 같음 + 0 아닌 칸 0 → 0 | 열쇠 다름 → 1통 | «N분 전» 만 다름 → 0
world w7a "$L_ZERO"; last_with "$((NOW-60))" "$L_ZERO"
out="$(run)"; rc=$?
[ "$(posts)" = 0 ] && [ "$rc" -eq 0 ] && [ -f "$LAST" ] && ok "⑦ 열쇠 같음 · 0 칸 → 발행 0" || bad "⑦ rc=$rc 발행 $(posts) $out"
world w7b "$L_ZERO"; last_with "$((NOW-60))" "$L_HIT"
[ "$(run >/dev/null; posts)" = 1 ] && ok "⑦ 열쇠 다름 → 1통" || bad "⑦ 열쇠 다름 발행 $(posts)"
world w7c "$L_HIT"   # 같은 열쇠 · «40분 전» → «75분 전» 만 다름
last_with "$((NOW-60))" "$L_HIT"
printf '%s\n' "${L_HIT/(40분 전)/(75분 전)}" > "$ST"
[ "$(run >/dev/null; posts)" = 0 ] && ok "⑦ «N분 전» 만 다름 → 0" || bad "⑦ N분 전 발행 $(posts)"

# ⑧ 열쇠 같음 · 오빠 답 기다림 2 · 3시간 10분 전 → 1통(«그대로 3시간») | 2시간 전 → 0
world w8a "$L_HIT"; last_with "$((NOW-11400))" "$L_HIT"
run >/dev/null
[ "$(posts)" = 1 ] && grep -q '그대로 3시간' "$FAKE_TP_LOG" && ok "⑧ 3시간 10분 → 1통(«그대로 3시간»)" || bad "⑧ 3h10m 발행 $(posts)"
world w8b "$L_HIT"; last_with "$((NOW-7200))" "$L_HIT"
[ "$(run >/dev/null; posts)" = 0 ] && ok "⑧ 2시간 → 0" || bad "⑧ 2시간 발행 $(posts)"

# ⑨ 1행 20분 낡음 → 발행 0 · stderr «판정 불가 머리 줄 낡음» 1줄 · rc0
world w9 "$L_HIT" "$((NOW-1200))"
out="$(run)"; rc=$?
[ "$(posts)" = 0 ] && [ "$rc" -eq 0 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && grep -q '판정 불가 머리 줄 낡음' "$T/err" \
  && ok "⑨ 20분 낡음 → 발행 0 · stderr 1줄 · rc0" || bad "⑨ rc=$rc 발행 $(posts) err=$(cat "$T/err")"

# ⑩ 발행 실패 → head-last 안 씀 · desk [긴급] 1통 · 같은 판 다시 = 창 안이라 1통 그대로
world w10 "$L_HIT"
out="$(FAKE_POST_RC=3 run)"; rc=$?
[ "$(posts)" = 1 ] && [ ! -e "$LAST" ] && [ "$rc" -eq 0 ] && ok "⑩ 실패 → head-last 0 · rc0" || bad "⑩ rc=$rc head-last $( [ -e "$LAST" ] && echo 있음 || echo 없음 )"
grep -q 'send byz-planner-desk-claude#121 ft-desk-head \[긴급\] 머리 줄 발행 실패' "$FAKE_MBOX_LOG" && ok "⑩ desk [긴급] 1통" || bad "⑩ mbox $(cat "$FAKE_MBOX_LOG")"
last_with "$((NOW-60))" "$L_HIT"; rm -f "$R/.fable-team/state/board/head-fail-last.json"
FAKE_POST_RC=3 run >/dev/null; FAKE_POST_RC=3 run >/dev/null; FAKE_POST_RC=3 run >/dev/null
[ "$(wc -l < "$FAKE_MBOX_LOG" | tr -d ' ')" = 1 ] && ok "⑩ 30분 창 — 3회 실패 = 1통" || bad "⑩ 창 $(wc -l < "$FAKE_MBOX_LOG")통"

# ⑪ 태그 = 오빠 답 기다림 ≥1 ∨ 스크립트 ≥1 일 때만 1개
world w11a "$L_HIT"
run >/dev/null
grep -q '<@U0OPPA>' "$FAKE_TP_LOG" && grep -q -- '--keep-mention' "$FAKE_TP_LOG" && ok "⑪ 답 2 → 태그 1개" || bad "⑪ 태그 없음 $(head -c 200 "$FAKE_TP_LOG")"
world w11b "$L_ZERO"
run >/dev/null
grep -q '<@U0OPPA>' "$FAKE_TP_LOG" && bad "⑪ 답 0 · 스크립트 0 인데 태그" || ok "⑪ 답 0 · 스크립트 0 → 태그 0"
[ "$(grep -o '<@U0OPPA>' "$FAKE_TP_LOG" | wc -l | tr -d ' ')" -le 1 ] && ok "⑪ 태그 1개(2개 0)" || bad "⑪ 태그 여러 개"

# ⑫ desk 틱 지침 — «머리 먼저» 절 1개 · 틱 정본 1줄 그대로
D="$H/../skill/references/desk-tick-prompt.md"
[ "$(grep -c '머리 먼저' "$D")" -ge 1 ] && ok "⑫ «머리 먼저» 절 있음" || bad "⑫ 절 없음"
grep -qF 'bash <LIVE_BIN>/ft-desk-tick.sh <내 좌석>   # 1회. 마지막 줄 «결정 필요: 0» 이면 그 턴의 도구는 이것 하나(추가 0) · N≥1 이면 그 항목만 도구 1회 더' "$D" \
  && ok "⑫ 틱 정본 1줄 그대로" || bad "⑫ 정본 줄 바뀜"
grep -qF '1행 그대로' "$D" && ok "⑫ 1행 출처 적힘" || bad "⑫ 1행 출처 없음"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
