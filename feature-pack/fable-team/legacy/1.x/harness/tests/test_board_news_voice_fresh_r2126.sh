#!/usr/bin/env bash
# test_board_news_voice_fresh_r2126.sh — 자동 뉴스 글 존댓말 · 4칸 · 실측 신선도 · 무변화 30분 상태 글 · 실패 [긴급] (r2126 · 반례 ①~⑧).
#   ①~③ V1 바꿈표 · ④ V2 4칸(보통 글 · 상태 글) · ⑤ ⑥ F1 df 실측 · 원장 시각 표지 · ⑦ H1 29분 0 / 31분 1 · ⑧ H2 (단계, rc)별 30분 창
# 실 Slack · 실 우편함 · 실 launchd · 실 df 0 · sleep 0. R2126_HARNESS = 시험할 harness 폴더(기준판 · 변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HX="${R2126_HARNESS:-$HERE/..}"
BIN="$HX/bin"; NEWS="$BIN/ft_board_news.py"; PUB="$BIN/ft-board-publish.sh"
D0=2026-11-16
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/root"; FB="$R/.fable-team"; SD="$FB/state/board"
mkdir -p "$FB/comm" "$SD" "$T/stub"
# 가짜 df(rc = df_rc 파일 · 여유 = df_gi 파일) · collect dict(진행 1 · 대기 2)
cat > "$T/stub/df.sh" <<'EOF'
d="$(dirname "$0")"; rc="$(cat "$d/df_rc" 2>/dev/null || echo 0)"; [ "$rc" = 0 ] || exit "$rc"
echo "Filesystem 1G-blocks Used Available Capacity iused ifree %iused Mounted on"
echo "/dev/disk3s1s1 926 800 $(cat "$d/df_gi") 90% 1 1 1% /"
EOF
echo 52 > "$T/stub/df_gi"
python3 - "$T/collect.json" <<'PY'
import json, sys
team = {"key": "harness", "label": "하네스", "states": {"r1": "진행", "r2": "대기", "r3": "대기"}, "counts": {"완성": 0, "진행": 1, "대기": 2},
        "progress": {}, "seats": {}, "oppa_todo": [], "axes": [], "goals": {}, "done_on": {}}
json.dump({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": [team]}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
# goal <상태 칸> [다음 칸] — 원장 md 1골 · mtime = FT_BOARD_NOW − 5분(⑤ 만 따로 바꿈)
goal() { printf '## 골 진행\n\n| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 |\n|---|---|---|---|---|---|\n| 6 | 하네스 운영 정리 | 3 | 5 | %s | %s |\n' "$1" "${2:-—}" > "$T/goal.md"
  touch -t 202611162155 "$T/goal.md"; }
# news <시각 HH:MM> — ft_board_news.py 1회 · POST 면 state → last(발행 흉내) · out/err/body
news() { rm -f "$T/body.txt" "$T/state.json"; RC=0
  env FT_ROOT="$R" FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="${D0}T$1:00" FT_BOARD_DF="bash $T/stub/df.sh" FT_OPPA_SLACK_UID=U1 \
    python3 "$NEWS" --collect "$T/collect.json" --last "$T/last.json" --body "$T/body.txt" --state "$T/state.json" > "$T/out" 2> "$T/err" || RC=$?
  [ "$(cat "$T/out")" = POST ] && cp "$T/state.json" "$T/last.json"; true; }
key_of() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["key"], ensure_ascii=False))' "$1"; }
at_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["at"])' "$1"; }
# 반말 끝 = 문장 끝(마침표 · « · » · 줄 끝)의 «다» 중 «니다» 아닌 것
plain() { python3 -c 'import re,sys; t=open(sys.argv[1],encoding="utf-8").read(); print(len([s for s in re.split(r"\.(?=\s|$)| · |\n", t) if s.strip().endswith("다") and not s.strip().endswith("니다")]))' "$1"; }
order() { awk 'NR==1&&/^골 진행 알림:/{print "조건"} NR==2&&/^골 진행 알림:/{print "조건"} $0=="지금"{print "지금"} $0=="다음"{print "다음"} $0=="막힌 것, 오빠 할 일"{print "막힘"} /^근거:/{print "근거"}' "$1" | paste -sd/ -; }
four() { [ "$(order "$1")" = "조건/지금/다음/막힘/근거" ] && tail -n 1 "$1" | grep -q '^근거:' && ! grep -q '^|' "$1" && ! grep -qF '```' "$1" \
  && awk '$0=="지금"{getline; print; exit}' "$1" | grep -q '^지금 실측([0-9][0-9]:[0-9][0-9]): 디스크 여유 '; }

# ① V1 바꿈표 · 전체 문자열 · 반말 끝 0 · 두 회차 열쇠 같음(열쇠 = 원장 원문)
S1="첫 골로 다시 시작했다. 막힌 것은 2개다. 계정 값 회신을 기다린다."
W1="첫 골로 다시 시작했습니다. 막힌 것은 2개입니다. 계정 값 회신을 기다립니다."
goal "$S1"; rm -f "$T/last.json"; news 22:00; K1="$(key_of "$T/state.json")"; cp "$T/body.txt" "$T/body1.txt"
rm -f "$T/last.json"; news 22:40; K2="$(key_of "$T/state.json")"
chk "① 전체 문자열 «${W1}»" 'grep -qF "3/5. $W1" "$T/body1.txt"'
chk "① 본문 반말 끝 0" '[ "$(plain "$T/body1.txt")" = 0 ]'
chk "① 두 회차 열쇠 같음 · 열쇠 = 원장 원문" '[ "$K1" = "$K2" ] && printf "%s" "$K1" | grep -qF "회신을 기다린다."'

# ② 인용 · «함» 끝 그대로
goal "오빠 «닫아» 11-16 08:10 · 확인함"; rm -f "$T/last.json"; news 22:00
chk "② 인용 · 함 끝 그대로" 'grep -qF "3/5. 오빠 «닫아» 11-16 08:10, 확인함" "$T/body.txt" && ! grep -q "WARN 말투" "$T/err"'

# ③ 바꿀 수 없는 «다» = 그대로 + WARN 1줄
goal "ABC다."; rm -f "$T/last.json"; news 22:00
chk "③ 문장 그대로 · WARN «말투 바꿈 불가» 1줄" 'grep -qF "3/5. ABC다." "$T/body.txt" && [ "$(grep -c "^WARN 말투 바꿈 불가: 하네스 운영 정리 — ABC다" "$T/err")" = 1 ]'

# ④ V2 4칸 — 보통 글 · 무변화 상태 글 둘 다 · 표 줄 0 · 근거 맨 끝 · ② 칸 첫 줄 = 실측
goal "진행 중" "다음 카드를 연다"; rm -f "$T/last.json"; news 10:00; cp "$T/body.txt" "$T/b4a.txt"
news 10:31; cp "$T/body.txt" "$T/b4b.txt" 2>/dev/null || : > "$T/b4b.txt"
chk "④ 보통 글 4칸 순서 · 근거 맨 끝 · 표 0" 'four "$T/b4a.txt"'
chk "④ 상태 글도 4칸 · 첫 줄 «변화 없음, 지난 글»" 'four "$T/b4b.txt" && head -n 1 "$T/b4b.txt" | grep -q "^변화 없음, 지난 글 "'

# ⑤ F1 — 원장 시각 = 지금 − 45분 · 가짜 df 52Gi → 실측 줄 · 칸 앞 표지
goal "디스크 여유가 30Gi 아래라 실행을 멈췄다"; touch -t 202611162115 "$T/goal.md"; rm -f "$T/last.json"; news 22:00
chk "⑤ ② 첫 줄 «지금 실측(22:00): 디스크 여유 52Gi, 진행 카드 1, 대기 카드 2»" \
  '[ "$(awk "\$0==\"지금\"{getline; print; exit}" "$T/body.txt")" = "지금 실측(22:00): 디스크 여유 52Gi, 진행 카드 1, 대기 카드 2" ]'
chk "⑤ 칸 앞 «(원장 21:15 기준)»" 'grep -qF "3/5. (원장 21:15 기준) 디스크 여유가 30Gi 아래라 실행을 멈췄습니다" "$T/body.txt"'
goal "디스크 여유가 30Gi 아래라 실행을 멈췄다"; rm -f "$T/last.json"; news 22:00
chk "⑤ 원장 5분 전 = 표지 0" '! grep -qF "(원장 " "$T/body.txt"'

# ⑥ 가짜 df rc 1 → 판정 불가 줄 · 발행 계속
echo 1 > "$T/stub/df_rc"; rm -f "$T/last.json"; news 22:00
chk "⑥ «디스크 여유 판정 불가(rc=1)» · POST · 0Gi 0" 'grep -qF "디스크 여유 판정 불가(rc=1)" "$T/body.txt" && [ "$(cat "$T/out")" = POST ] && ! grep -q "디스크 여유 0Gi" "$T/body.txt"'
rm -f "$T/stub/df_rc"

# ⑦ H1 — 열쇠 같음 · 29분 = 발행 0 / 31분 = 상태 글 1 · key 그대로 · at 새로
goal "진행 중"; rm -f "$T/last.json"; news 10:00; KA="$(key_of "$T/last.json")"
news 10:29
chk "⑦ 29분 → 발행 0 «변화 없음»" 'grep -q "^변화 없음" "$T/out" && [ ! -f "$T/body.txt" ]'
news 10:31
chk "⑦ 31분 → 상태 글 1 · 첫 줄 «변화 없음, 지난 글 10:00» · 근거 맨 끝" \
  '[ "$(cat "$T/out")" = POST ] && head -n 1 "$T/body.txt" | grep -qxF "변화 없음, 지난 글 10:00" && tail -n 1 "$T/body.txt" | grep -q "^근거:"'
chk "⑦ news-last key 그대로 · at 새로" '[ "$(key_of "$T/last.json")" = "$KA" ] && [ "$(at_of "$T/last.json")" = "${D0}T10:31:00" ]'
news 10:45
chk "⑦ 상태 글 14분 뒤 → 발행 0" 'grep -q "^변화 없음" "$T/out"'

# ⑧ H2 — ft-board-publish --news 실패 = planner _desk [긴급] 1통 · (단계, rc)별 30분 · send 성공 뒤 표식 · 원 rc
printf '{"_desk":"desk#1","_master":"pm#1"}' > "$FB/seats-planner.json"
cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
d="$(dirname "$0")"; rc="$(cat "$d/collect_rc" 2>/dev/null || echo 0)"; [ "$rc" = 0 ] || exit "$rc"
cp "$d/../collect.json" "$3"
EOF
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
d = os.path.dirname(os.path.abspath(__file__))
sys.exit(int(open(f"{d}/tp_rc").read()) if os.path.exists(f"{d}/tp_rc") else 0)
EOF
cat > "$T/stub/mbox.sh" <<'EOF'
d="$(dirname "$0")"; printf '%s\n' "$*" >> "$d/sends.log"; exit "$(cat "$d/send_rc" 2>/dev/null || echo 0)"
EOF
chmod +x "$T/stub/board"; : > "$T/stub/sends.log"
pub() { RC=0; env FT_ROOT="$R" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" FT_GOAL_PROGRESS_MD="$T/goal.md" FT_OPPA_SLACK_UID=U1 \
  FT_BOARD_POST_ARGS="--channel C1" FT_BOARD_NOW="${D0}T$1:00" FT_BOARD_DF="bash $T/stub/df.sh" FT_MBOX="$T/stub/mbox.sh" \
  bash "$PUB" --news > "$T/out" 2> "$T/err" || RC=$?; }
sends() { wc -l < "$T/stub/sends.log" | tr -d ' '; }
goal "진행 중"; rm -f "$SD/news-last.json"; echo 1 > "$T/stub/tp_rc"
pub 10:00
chk "⑧ post rc 1 → send 1(desk · [긴급] · post rc=1) · rc 1" \
  '[ "$RC" = 1 ] && [ "$(sends)" = 1 ] && tail -n 1 "$T/stub/sends.log" | grep -q "^send desk#1 .*\[긴급\] 자동 뉴스 실패 — post rc=1"'
pub 10:10
chk "⑧ 10분 뒤 같은 실패 → send 0 · rc 1" '[ "$RC" = 1 ] && [ "$(sends)" = 1 ]'
pub 10:31
chk "⑧ 31분 뒤 → send 1" '[ "$RC" = 1 ] && [ "$(sends)" = 2 ]'
echo 2 > "$T/stub/collect_rc"; pub 10:33
chk "⑧ collect rc 2 → send 1 · rc 2" '[ "$RC" = 2 ] && [ "$(sends)" = 3 ] && tail -n 1 "$T/stub/sends.log" | grep -q "collect rc=2"'
rm -f "$T/stub/collect_rc"; pub 10:40
chk "⑧ post rc1 → collect rc2 → post rc1(10분 안) = post send 0" '[ "$RC" = 1 ] && [ "$(sends)" = 3 ]'
echo 3 > "$T/stub/tp_rc"; echo 1 > "$T/stub/send_rc"; pub 10:41
chk "⑧ send 실패 → stderr «판정 불가 — desk 알림 실패» · 표식 0 · rc 3" \
  '[ "$RC" = 3 ] && [ "$(sends)" = 4 ] && grep -qF "판정 불가 — desk 알림 실패" "$T/err" && ! grep -qF "post rc=3" "$SD/news-fail-last.json" 2>/dev/null'
rm -f "$T/stub/send_rc"; pub 10:42
chk "⑧ 다음 회차 → send 1" '[ "$RC" = 3 ] && [ "$(sends)" = 5 ]'
rm -f "$T/stub/tp_rc"; pub 10:43
chk "⑧ 성공 → send 0 · rc 0 · 글 1통" '[ "$RC" = 0 ] && [ "$(sends)" = 5 ] && grep -q "글 1통 발행" "$T/out"'

echo "--- r2126: FAIL $fail"
[ "$fail" -eq 0 ]
