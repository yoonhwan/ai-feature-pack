#!/usr/bin/env bash
# test_board_news_shorten_goal_r2184.sh — 다 접어도 3500B 를 넘는 자동 뉴스 본문 = 긴 골 상태 글부터 같은 상한 C 로 줄여 발행 (r2184 · 반례 ②~⑩).
#   ② 정확 3500B 불변 · ③ 3501B = 긴 줄 1개 «…» + 알림 «1개» · ④ 한글 경계(나머지 0·1·2) · ⑤ 실사건 꼴 7골 · ⑥ 동률 · 결정성
#   ⑦ 그대로 두는 줄 · ⑧ «변화 없음» 짧은 글 · ⑨ 바닥 30골 = 발행 0 · ⑩ 다음 틱 «변화 없음» (① = 기존 시험 8개 따로)
# 실 Slack · 실 수집기 · 실 df · 실 mbox 0 · sleep 0. R2184_BIN = 시험할 bin(기준판 · 변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2184_BIN:-$HERE/../bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ②~⑨ 본문 직접(body) — ⓓ 까지 접은 기준 글 = base() 로 따로 만든다
python3 - "$BIN" <<'PY' > "$T/direct.out" 2>&1
import sys
from datetime import datetime
sys.path.insert(0, sys.argv[1])
import ft_board_news_body as b
fails = 0
def chk(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name); fails += 0 if cond else 1
NOW, SHA, NOTE = datetime(2026, 11, 17, 18, 24), "1234567890", "길어서 줄였습니다, 전문은 골 진행 원장"
PRE = lambda i: f"골{i}: 3단계 중 1단계 끝남. "  # noqa: E731
def cur(st):
    return {"goals": [[str(i), f"골{i}", "1", "3", s, "—"] for i, s in enumerate(st, 1)], "h": 0, "carried": [], "cards": {}, "err": [], "sessions": {}}
def base(st, mark="", meas="", beat=""):  # ⓓ 까지 접은 글(막대 0 · 묶음 0 · 다음 한 수 없음)
    g = [PRE(i) + (f"{mark} " if mark else "") + s for i, s in enumerate(st, 1)]
    return "\n".join([*([beat] if beat else []), f"골 진행 알림: 열린 골 {len(st)}개, 닫힌 골 0개", "지금", *([meas] if meas else []), *g,
                      "다음", "정해진 다음 한 수 없음", "막힌 것, 오빠 할 일", "없음", f"근거: 발행 {NOW:%Y-%m-%d %H:%M}, 골 진행 원장 {SHA}"]) + "\n"
def fill(i, size, mark=""):  # 골 줄 전체가 size 바이트가 되는 상태 글(한글 + 끝 ASCII)
    room = size - len((PRE(i) + (f"{mark} " if mark else "")).encode())
    return "가" * (room // 3) + "x" * (room % 3)
def goals(o):
    return [ln for ln in o.splitlines() if ln.startswith("골") and not ln.startswith("골 진행 알림")]
def notes(o):
    return [ln for ln in o.splitlines() if ln.endswith(NOTE)]
def rest(o):  # 골 줄 · 알림 줄 밖 줄들
    return [ln for ln in o.splitlines() if ln not in goals(o) and not ln.endswith(NOTE)]
def size(o):
    return len(o.encode())

# ② 정확 3500B — 기준 글과 바이트 같음 · «…» 0 · 알림 0
st = ["가" * 100] * 8
st.append(fill(9, 3500 - size(base(st + [""])) + len(PRE(9).encode())))
o = b.body(cur(st), None, NOW, SHA)
chk(f"② ⓓ 3500B 입력({size(base(st))}B) → 기준 글과 바이트 같음 · «…» 0 · 알림 0", size(base(st)) == 3500 and o == base(st) and "…" not in o and not notes(o))
# ③ 3501B — 긴 골 1개만 «…» · 알림 «1개» · 3500B 안
st3 = st[:8] + [st[8] + "x"]
o3 = b.body(cur(st3), None, NOW, SHA)
cut = [g for g in goals(o3) if g.endswith("…")]
chk(f"③ ⓓ 3501B 입력({size(base(st3))}B) → {size(o3)}B ≤ 3500 · 골9 줄만 «…» · 알림 «상태 글 1개»",
    size(base(st3)) == 3501 and size(o3) <= 3500 and len(cut) == 1 and cut[0].startswith("골9: ") and notes(o3) == [f"상태 글 1개는 {NOTE}"])
chk("⑦ ③ 의 머리 · 다음 · 막힌 것 · 근거 = 기준 글 줄과 같음", rest(o3) == rest(base(st3)))
# ④ 한글 경계 — 자를 자리 나머지 0 · 1 · 2 (긴 줄 2개의 앞 ASCII 수를 달리 = 같은 C 에서 둘 중 하나는 글자 가운데)
for p in range(3):
    s4 = ["가" * 100] * 7 + ["x" * p + "가" * 400, "x" * ((p + 1) % 3) + "가" * 400]
    o = b.body(cur(s4), None, NOW, SHA)
    cut = [g for g in goals(o) if g.endswith("…")]
    chk(f"④ 앞 ASCII {p}자 · {(p + 1) % 3}자 → {size(o)}B ≤ 3500 · 잘린 줄 2개 = 온전한 «가» + «…» · 깨진 글자 0",
        size(base(s4)) > 3500 and size(o) <= 3500 and len(cut) == 2 and all(g.endswith("가…") for g in cut) and "\ufffd" not in o and o.encode().decode() == o)
# ⑤ 실사건 꼴 — 골 줄 137 · 167 · 374 · 465 · 562 · 725 · 761B · 원장 표지 · 실측 줄 · «변화 없음» 짧은 글
MARK, MEAS, BEAT = "(원장 17:28 기준)", "지금 실측(18:24): 디스크 여유 52Gi, 진행 카드 1, 대기 카드 2", "변화 없음, 지난 글 17:41"
s5 = [fill(i, n, MARK) for i, n in enumerate([137, 167, 374, 465, 562, 725, 761], 1)]
o5, b5 = b.body(cur(s5), None, NOW, SHA, meas=MEAS, mark=MARK, beat=BEAT), base(s5, MARK, MEAS, BEAT)
cut, keep = [g for g in goals(o5) if g.endswith("…")], [g for g in goals(o5) if not g.endswith("…")]
chk(f"⑤ 실사건 꼴 {size(b5)}B → {size(o5)}B ≤ 3500 · 골 이름 7개 · 표지 7개", size(b5) > 3500 and size(o5) <= 3500
    and [g.split(":")[0] for g in goals(o5)] == [f"골{i}" for i in range(1, 8)] and all(MARK in g for g in goals(o5)))
chk(f"⑤ C 보다 짧은 줄 {len(keep)}개 = 입력과 같음 · 줄인 줄 {len(cut)}개 = 알림 수 · 줄인 줄 ≥ 남은 줄",
    0 < len(cut) < 7 and all(g in goals(b5) for g in keep) and notes(o5) == [f"상태 글 {len(cut)}개는 {NOTE}"]
    and min(size(g) for g in cut) >= max(size(g) for g in keep) and max(size(g) for g in cut) - min(size(g) for g in cut) <= 2)
chk("⑦ ⑤ 의 머리 · 실측 · 다음 · 막힌 것 · 근거 = 기준 글 줄과 같음", rest(o5) == rest(b5) and MEAS in o5.splitlines())
# ⑥ 동률 긴 줄 2개 → 같은 길이 · 같은 입력 두 번 = 같은 바이트
s6 = ["가" * 100] * 7 + ["가" * 400, "가" * 400]
o6 = b.body(cur(s6), None, NOW, SHA)
cut = [g for g in goals(o6) if g.endswith("…")]
chk(f"⑥ 동률 2줄 → 둘 다 «…» · 같은 바이트 길이 · 두 번 같은 글 ({size(o6)}B)",
    size(o6) <= 3500 and len(cut) == 2 and size(cut[0]) == size(cut[1]) and o6 == b.body(cur(s6), None, NOW, SHA))
# ⑧ «변화 없음» 짧은 글이 넘는 입력 → ③ 과 같은 처리
o8 = b.body(cur(st3), None, NOW, SHA, beat=BEAT)
chk(f"⑧ 짧은 글 넘는 입력({size(base(st3, beat=BEAT))}B) → {size(o8)}B ≤ 3500 · 첫 줄 «변화 없음» · «…» 1 · 알림 «1개»",
    size(o8) <= 3500 and o8.splitlines()[0] == BEAT and len([g for g in goals(o8) if g.endswith("…")]) == 1 and len(notes(o8)) == 1)
# ⑨ 바닥 — 골 30개 모두 150B 넘음 → 넘는 글 그대로(발행 0 은 CLI 에서)
s9 = ["가" * 100] * 30
o9 = b.body(cur(s9), None, NOW, SHA)
chk(f"⑨ 30골 → 기준 글 그대로({size(o9)}B > 3500) · «…» 0", o9 == base(s9) and size(o9) > 3500 and "…" not in o9)
sys.exit(1 if fails else 0)
PY
cat "$T/direct.out"; fail=$((fail + $(grep -c '^FAIL' "$T/direct.out"))); grep -q '^PASS' "$T/direct.out" || bad "②~⑨ 본문 시험 못 돎"

# ③ ⑧ ⑨ ⑩ CLI — 임시 collect · 원장 · 가짜 df · 시각 주입
R="$T/root"; mkdir -p "$R/.fable-team/state/board" "$T/stub"
printf 'echo "Filesystem 1G-blocks Used Available Capacity iused ifree %%iused Mounted on"\necho "/dev/disk3s1s1 926 800 52 90%% 1 1 1%% /"\n' > "$T/stub/df.sh"
python3 - "$T/collect.json" <<'PY'
import json, sys
team = {"key": "harness", "label": "하네스", "states": {"r1": "진행"}, "counts": {"완성": 0, "진행": 1, "대기": 0},
        "progress": {}, "seats": {}, "oppa_todo": [], "axes": [], "goals": {}, "done_on": {}}
json.dump({"date": "2026-11-17", "verdicts": [], "issues": [], "teams": [team]}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
goal() { { printf '## 골 진행\n\n| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 |\n|---|---|---|---|---|---|\n'
  for r in "$@"; do echo "| $r | — |"; done; } > "$T/goal.md"; touch -t 202611171000 "$T/goal.md"; }
news() { rm -f "$T/body.txt"; RC=0
  env FT_ROOT="$R" FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="2026-11-17T$1:00" FT_BOARD_DF="bash $T/stub/df.sh" FT_OPPA_SLACK_UID=U1 \
    python3 "$BIN/ft_board_news.py" --collect "$T/collect.json" --last "$T/last.json" --body "$T/body.txt" --state "$T/state.json" > "$T/out" 2> "$T/err" || RC=$?
  [ "$(cat "$T/out")" = POST ] && cp "$T/state.json" "$T/last.json"; true; }
key_of() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["key"], ensure_ascii=False))' "$1"; }
G="$(python3 -c 'print("가"*100)')"; L="$(python3 -c 'print("가"*500)')"
rows=(); for i in 1 2 3 4 5 6 7 8; do rows+=("$i | 골$i | 1 | 3 | $G"); done
goal "${rows[@]}" "9 | 골9 | 1 | 3 | $L"; rm -f "$T/last.json"; news 10:00
chk "③ CLI 넘는 입력 → rc 0 · POST · 본문 ≤ 3500B · «…» 1줄 · 알림 «1개» · 실측 줄 있음" \
  '[ "$RC" = 0 ] && [ "$(cat "$T/out")" = POST ] && [ "$(wc -c < "$T/body.txt")" -le 3500 ] && [ "$(grep -c "…$" "$T/body.txt")" = 1 ] && grep -qxF "상태 글 1개는 길어서 줄였습니다, 전문은 골 진행 원장" "$T/body.txt" && grep -q "^지금 실측(10:00): 디스크 여유 52Gi" "$T/body.txt"'
K0="$(key_of "$T/last.json" 2>/dev/null)"
news 10:10
chk "⑩ 다음 틱 같은 입력 → «변화 없음 — 발행 0» · 본문 0 · key 그대로" 'grep -q "^변화 없음" "$T/out" && [ ! -e "$T/body.txt" ] && [ "$(key_of "$T/last.json")" = "$K0" ] && [ -n "$K0" ]'
news 10:31
chk "⑧ CLI 31분 뒤 짧은 글 → POST · 첫 줄 «변화 없음, 지난 글 10:00» · ≤ 3500B · 알림 1줄" \
  '[ "$(cat "$T/out")" = POST ] && head -n 1 "$T/body.txt" | grep -qxF "변화 없음, 지난 글 10:00" && [ "$(wc -c < "$T/body.txt")" -le 3500 ] && [ "$(grep -c "길어서 줄였습니다" "$T/body.txt")" = 1 ]'
rows=(); for i in $(seq 1 30); do rows+=("$i | 골$i | 1 | 3 | $G"); done
goal "${rows[@]}"; rm -f "$T/last.json"; news 11:00
chk "⑨ CLI 30골 → rc 1 · «> 3500B — 발행 0» · 본문 0" '[ "$RC" = 1 ] && grep -q "B > 3500B — 발행 0" "$T/err" && [ ! -e "$T/body.txt" ]'

[ -z "${R2184_BIN:-}" ] && chk "bin = kit 사본 cmp 0" '( for f in ft_board_news.py ft_board_news_body.py ft_board_news_name.py; do cmp -s "$BIN/$f" "$HERE/../kit/fable-team/bin/$f" || exit 1; done )'
echo "--- r2184: FAIL $fail"
[ "$fail" -eq 0 ]
