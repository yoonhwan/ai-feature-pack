#!/usr/bin/env bash
# test_board_seat_cell.sh — ft-board 좌석 칸 = jsonl turn 실측 · stalled · ⓪ 열 · 완료 선언 꼬리 (판정 511·514 · DESIGN-511 §4-r2·§4-r3 시험 ①~㉒).
# 전부 mktemp 임시 FT_ROOT(가짜 명부 3 · 가짜 mailbox 3파일 · 임시 git 리포 커밋 1) + 스텁 env(FT_BOARD_SEAT_STATUS·TMUX·GH·INBOX) + FT_BOARD_NOW.
# 실제 tmux·jsonl·gh 호출 0 · 라이브 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

export FT_ROOT="$T/root" FT_BOARD_NOW="2026-10-09T10:00:00" FT_BOARD_GH_TTL=0 SEAT_CALLS="$T/seat.calls" TURN_DIR="$T/turn"
export FT_VERDICT_BIN="$BIN/ft-verdict.sh"
export FT_BOARD_TMUX="bash $T/tmux.sh" FT_BOARD_GH="cat $T/gh.json" FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS="$T/seat.sh"
FB="$FT_ROOT/.fable-team"; mkdir -p "$FB/comm" "$FB/state" "$T/turn" "$FT_ROOT/t/진행"
git -C "$FT_ROOT" init -q && git -C "$FT_ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
export FAKE_SHA="$(git -C "$FT_ROOT" rev-parse HEAD)"
board() { python3 "$BIN/ft-board.py" "$@"; }
: > "$FB/state/verdicts.jsonl"; echo '[]' > "$T/gh.json"; printf '#!/bin/sh\necho EMPTY\n' > "$T/inbox.sh"
printf '#!/bin/sh\ncat %s/alive.txt\n' "$T" > "$T/tmux.sh"
printf '# 인덱스: 진행카드\n본문\n' > "$FT_ROOT/t/진행/c-prog.md"
cat > "$T/seat.sh" <<'EOF'
#!/bin/sh
echo "$2" >> "$SEAT_CALLS"
[ -f "$TURN_DIR/$2.rc" ] && exit "$(cat "$TURN_DIR/$2.rc")"
cat "$TURN_DIR/$2.out"
EOF

python3 - "$T" <<'PY'
import datetime as dt, json, os, sys
from pathlib import Path
T = Path(sys.argv[1]); R = T / "root"; FB = R / ".fable-team"; SHA = os.environ["FAKE_SHA"]
NOW = dt.datetime(2026, 10, 9, 10, 0, 0)
ago = lambda m: (NOW - dt.timedelta(minutes=m)).isoformat()
S = lambda i: f"s-{i}#0"
def turn(seat, state, te, src="jsonl"):
    (T / "turn" / f"{seat}.out").write_text(json.dumps({"state": state, "turn_end": te, "duration_ms": 1000, "reported": "no", "source": src}), encoding="utf-8")
IDLE = {"i2": 2, "i5": 5, "pend": 10, "d-ok": 5, "d-noev": 5, "d-badsha": 5, "d-replied": 5, "d-keep": 5, "d-other": 5, "d-ok12": 5, "d-plain": 5, "d-k999": 5}
for i, m in IDLE.items(): turn(S(i), "PENDING" if i == "pend" else "IDLE", ago(m))
utc = (NOW.astimezone() - dt.timedelta(minutes=5)).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
turn(S("i-utc"), "IDLE", utc); turn(S("i-null"), "IDLE", None); turn(S("i-bad"), "IDLE", "not-a-time"); turn(S("i-future"), "IDLE", ago(-30))
turn(S("d-null"), "IDLE", None); turn(S("i-pane"), "IDLE", None, "pane")
for i in ("w-jsonl", "w-noreply", "w-reply", "w-succ", "w-rot", "w-nosend", "w-hil", "d-work"): turn(S(i), "WORKING", ago(20))
turn(S("w-pane"), "WORKING", None, "pane"); turn(S("unk-first"), "UNKNOWN", None); turn(S("unk-none"), "UNKNOWN", None, "pane")
turn("t-master#1", "WORKING", None); turn("u-master#1", "WORKING", None); turn(S("u-stuck"), "IDLE", ago(9)); turn("w-master#1", "WORKING", None)
(T / "turn" / f"{S('fail')}.rc").write_text("1"); (T / "turn" / f"{S('garbage')}.out").write_text("oops")
# 우편 기록 — seq 순서 = 생성 순서
files = {"mailbox.log.jsonl.1": [], "mailbox.log.jsonl": [], "mailbox.jsonl": []}; seq = [1000]
def rec(frm, to, body, when, f="mailbox.jsonl"):
    seq[0] += 1; r = {"seq": seq[0], "ts": when, "to": to, "from": frm, "body": f"[{frm}->{to}] {body}"}
    files[f].append(r); return seq[0]
rec("x#1", "y#1", "기록 시작", ago(300), "mailbox.log.jsonl.1")
M = "t-master#1"; EV = f"세트: {SHA} · 시험: bash tests/x.sh rc=0 · 이슈: 0"; BADEV = "세트: " + "0" * 40 + " · 시험: bash tests/x.sh rc=0 · 이슈: 0"
facts = {}
facts["rot"] = rec(S("w-rot"), "t-arch#1", "회전본 발신", ago(100), "mailbox.log.jsonl.1")
files["mailbox.log.jsonl"].append(files["mailbox.log.jsonl.1"][-1])  # 같은 seq 두 파일 → 중복 제거
facts["noreply"] = rec(S("w-noreply"), "t-arch#1", "질문", ago(30))
facts["reply0"] = rec(S("w-reply"), "t-arch#1", "질문", ago(40)); facts["reply1"] = rec("t-arch#1", S("w-reply"), "답", ago(35))
facts["succ0"] = rec(S("w-succ"), "t-arch#1", "질문", ago(40)); facts["succ1"] = rec("t-arch#2", S("w-succ"), "승계 답", ago(35))
facts["hil"] = rec(S("w-hil"), "t-planner#1", "[HIL] 막힘", ago(20))
for i, body in (("d-ok", f"[완료·휴식] 끝 {EV}"), ("d-noev", "[완료·휴식] 끝"), ("d-badsha", f"[완료·휴식] 끝 {BADEV}"), ("d-work", f"[완료·휴식] 끝 {EV}"),
                ("d-null", f"[완료·휴식] 끝 {EV}"), ("d-plain", f"완료했습니다 {EV}"), ("d-k999", "[완료·휴식 유지 #999]")):
    facts[i] = rec(S(i), M, body, ago(5))
facts["d-replied"] = rec(S("d-replied"), M, f"[완료·휴식] 끝 {EV}", ago(8)); rec(M, S("d-replied"), "다음 일", ago(7))
facts["d-other"] = rec(S("d-other"), M, f"[완료·휴식] 끝 {EV}", ago(8)); rec(S("d-other"), M, "[보고] 다른 머리", ago(6))
facts["d-ok12"] = rec(S("d-ok12"), M, f"[완료·휴식] 끝 {EV}", ago(12))
facts["d-keep"] = rec(S("d-keep"), M, f"[완료·휴식] 끝 {EV}", ago(12))
for m in (9, 6, 3): rec(S("d-keep"), M, f"[완료·휴식 유지 #{facts['d-keep']}]", ago(m))
for f, rows in files.items(): (FB / "comm" / f).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
# 명부
roster = {"_label": "시험팀", "_master": M, "_cards": "t", M: {"role": "master"}, "s-dead#0": {"role": "nano"},
          S("ready"): {"role": "stop-ready"}, S("closed"): {"role": "stopped"}, S("old"): {"role": "nano", "_replaced_by": S("i5")}}
alive = [M, S("ready"), S("closed"), S("old")]
for i in list(IDLE) + ["i-utc", "i-null", "i-bad", "i-future", "d-null", "i-pane", "w-jsonl", "w-noreply", "w-reply", "w-succ", "w-rot", "w-nosend", "w-hil",
                       "d-work", "w-pane", "unk-first", "unk-none", "fail", "garbage"]:
    roster[S(i)] = {"role": "nano", **({"index": "t/진행/c-prog.md"} if i in ("i5", "d-ok", "d-work") else {})}; alive.append(S(i))
(FB / "seats-t.json").write_text(json.dumps(roster, ensure_ascii=False), encoding="utf-8")
(FB / "seats-u.json").write_text(json.dumps({"_label": "유팀", "_master": "u-master#1", "u-master#1": {"role": "master"}, S("u-stuck"): {"role": "nano"}}), encoding="utf-8")
(FB / "seats-w.json").write_text(json.dumps({"_label": "무사고팀", "_master": "w-master#1", "w-master#1": {"role": "master"}}), encoding="utf-8")
(T / "alive.txt").write_text("\n".join(alive + ["u-master#1", S("u-stuck"), "w-master#1"]) + "\n", encoding="utf-8")
(T / "facts.json").write_text(json.dumps(facts), encoding="utf-8")
PY

rm -f "$SEAT_CALLS"; board collect > "$T/dict.json"; eq "collect rc" "$?" 0
CALLS_COLLECT="$(wc -l < "$SEAT_CALLS" | tr -d ' ')"
# 호출 대상 = 현역(비 stop-ready·stopped·_replaced_by)이면서 tmux 에 산 좌석 — 명부 t 의 s-* 41개가 아니라 집계로 대조
EXPECT_CALLS="$(python3 - "$FB" "$T/alive.txt" <<'PY'
import json, sys
alive = set(open(sys.argv[2], encoding="utf-8").read().split())
n = 0
for f in ("seats-t.json", "seats-u.json", "seats-w.json"):
    for k, v in json.load(open(f"{sys.argv[1]}/{f}", encoding="utf-8")).items():
        if not k.startswith("_") and isinstance(v, dict) and not v.get("_replaced_by") and v.get("role") not in ("stop-ready", "stopped") and k in alive: n += 1
print(n)
PY
)"
eq "⑧ turn 스텁 호출 수 = 현역 좌석 수(collect 1회)" "$CALLS_COLLECT" "$EXPECT_CALLS"
eq "⑧ 좌석당 1회(중복 호출 0)" "$(sort "$SEAT_CALLS" | uniq -d | wc -l | tr -d ' ')" 0
python3 - "$BIN" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from ft_board_collect import collect
from ft_board_render import render
d = collect(); render(d, "term"); render(d, "slack"); render(d, "term", True)
PY
eq "⑧ 같은 프로세스 collect 1회 + render 3회 = 호출 수 2×(collect 1회분)" "$(wc -l < "$SEAT_CALLS" | tr -d ' ')" "$((CALLS_COLLECT * 2))"

python3 - "$T" <<'PY' | tee "$T/py.out"
import json, sys
from pathlib import Path
T = Path(sys.argv[1]); d = json.load(open(T / "dict.json", encoding="utf-8")); F = json.load(open(T / "facts.json"))
team = lambda k: next(t for t in d["teams"] if t["key"] == k)
t = team("t"); S = lambda i: f"s-{i}#0"; cells = t["seats"]; M = "t-master#1"
def chk(name, got, want): print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f" (기대 {want!r} 실제 {got!r})"))
txt = lambda i: cells[S(i)]["text"]
print("--- 좌석 칸 픽스처 렌더(8행 표 + §4-r3 ⑩~㉑) ---")
for n, c in cells.items():
    if n.startswith("s-"): print(f"CELL {n} => {c['text']}")
# 8행 표
chk("① WORKING jsonl", txt("w-jsonl"), "작업중"); chk("① WORKING pane", txt("w-pane"), "작업중(pane)")
chk("② IDLE 2분 = 정지 2분 · ⚠ 0", txt("i2"), "정지 2분(턴 끝 09:58)"); chk("② IDLE 5분 = ⚠정지 5분", txt("i5"), "⚠정지 5분(턴 끝 09:55)")
chk("② UTC(Z) turn_end 도 지역 시각으로 5분", txt("i-utc"), "⚠정지 5분(턴 끝 09:55)")
chk("③ null turn_end → 분 0 · 사유", txt("i-null"), "대기(분 확인 불가: turn_end 없음)"); chk("③ 깨진 ISO", txt("i-bad"), "대기(분 확인 불가: turn_end 해석 실패)")
chk("③ 미래 시각", txt("i-future"), "대기(분 확인 불가: 미래 시각)")
chk("③ null/깨짐/미래 = stalled 0", [cells[S(i)]["stalled"] for i in ("i-null", "i-bad", "i-future")], [None, None, None])
chk("④ PENDING = 대기열 있음 · 정지로 안 셈", (txt("pend"), cells[S("pend")]["stalled"]), ("대기열 있음(턴 끝 09:50)", None))
chk("⑤ IDLE pane = 분 미상", txt("i-pane"), "대기(분 미상 · pane)")
chk("⑥ UNKNOWN 첫 턴 전 / 좌석 없음", (txt("unk-first"), txt("unk-none")), ("확인 불가(첫 턴 전)", "확인 불가(좌석 없음)"))
chk("⑦ rc≠0 / 출력 해석 실패", (txt("fail"), txt("garbage")), ("확인 불가(turn 조회 실패 rc=1)", "확인 불가(출력 해석 실패)"))
chk("⑧ stop-ready / stopped 칸", (txt("ready"), txt("closed")), ("정지레디", "닫힘"))
chk("⑨ 옛 좌석(_replaced_by)·세션 없는 좌석은 현역 칸에 없음", [n for n in cells if n in (S("old"), "s-dead#0")], [])
chk("stalled 대상 = ⚠ 행 하나뿐(IDLE∧jsonl∧N≥3)", sorted(n for n, c in cells.items() if c["stalled"] and n.startswith("s-") and not n.startswith("s-d-")), sorted([S("i5"), S("i-utc")]))
# 기다림 6종
W = lambda i: cells[S(i)]["wait"]
chk("기다림 ① 회신 없음", W("w-noreply"), f"추정: t-arch#1 에 마지막 발신 #{F['noreply']}(09:30) · 기록상 이후 t-arch#1 회신 없음")
chk("기다림 ② 회신 있음", W("w-reply"), f"추정: t-arch#1 에 마지막 발신 #{F['reply0']}(09:20) · 기록상 회신 있음 #{F['reply1']}")
chk("기다림 ③ 승계(#2) 회신 인정", W("w-succ"), f"추정: t-arch#1 에 마지막 발신 #{F['succ0']}(09:20) · 기록상 회신 있음 #{F['succ1']}")
chk("기다림 ④ 회전본에만 있는 발신(중복 seq 1건)", W("w-rot"), f"추정: t-arch#1 에 마지막 발신 #{F['rot']}(08:20) · 기록상 이후 t-arch#1 회신 없음")
chk("기다림 ⑤ 기록 시작 이전/없음 → 기록상 발신 없음", W("w-nosend"), "추정: 기록(05:00 이후)상 발신 없음")
chk("기다림 ⑥ [HIL] 발신", W("w-hil"), f"추정: HIL 대기 #{F['hil']}(t-planner#1)")
# §4-r3 ⑩~㉒
tail = lambda i, ev="증거 있음", hm="09:55": f" · 완료 선언 #{F[i]}({hm} · {ev})"
chk("⑩ 증거 있음 → 꼬리 · ⚠ 0 · stalled 0", (txt("d-ok"), cells[S("d-ok")]["stalled"]), ("정지 5분(턴 끝 09:55)" + tail("d-ok"), None))
chk("⑪ 증거 줄 없음 → ⚠ 그대로", (txt("d-noev"), cells[S("d-noev")]["stalled"]), ("⚠정지 5분(턴 끝 09:55)" + tail("d-noev", "증거 없음"), 5))
chk("⑫ sha 미실재 → ⑪ 과 같음", (txt("d-badsha"), cells[S("d-badsha")]["stalled"]), ("⚠정지 5분(턴 끝 09:55)" + tail("d-badsha", "증거 없음"), 5))
chk("⑬ 받는 좌석이 뒤에 발신 → 꼬리 없음", txt("d-replied"), "⚠정지 5분(턴 끝 09:55)")
chk("⑭ 완료 뒤 WORKING → ⚠완료 뒤 작업 + stalled 행", txt("d-work"), "작업중" + tail("d-work") + " · ⚠완료 뒤 작업")
chk("⑭ stalled 완료 뒤 작업 행", ["완료 뒤 작업", S("d-work"), f"#{F['d-work']}", "09:40"] in t["stalled"], True)
chk("⑮ 유지 3회 → 꼬리 HH:MM = 원 쪽지", txt("d-keep"), "정지 5분(턴 끝 09:55)" + tail("d-keep", hm="09:48"))
chk("⑮ 미처리 N = 지금 − 원 ts = 12 (응답으로 안 줄어듦)", ["완료 선언 미처리", M, f"{S('d-keep')} #{F['d-keep']}", "12분"] in t["stalled"], True)
chk("⑯ 다른 머리 쪽지가 뒤에 → 꼬리 없음", txt("d-other"), "⚠정지 5분(턴 끝 09:55)")
chk("⑰ 12분 → 완료 선언 미처리 1행(받는 좌석)", ["완료 선언 미처리", M, f"{S('d-ok12')} #{F['d-ok12']}", "12분"] in t["stalled"], True)
chk("⑰ 보낸 좌석 stalled 0 · 5분짜리는 미처리 행 없음", [r for r in t["stalled"] if r[0] == "완료 선언 미처리"], [r for r in t["stalled"] if r[0] == "완료 선언 미처리" and r[2].split(" ")[0] in (S("d-keep"), S("d-ok12"))])
chk("⑰ 미처리 행 정확히 2(d-keep · d-ok12)", len([r for r in t["stalled"] if r[0] == "완료 선언 미처리"]), 2)
chk("⑲ null turn_end + 꼬리 → 대기(분 확인 불가) + 꼬리 · ⚠ 0", (txt("d-null"), cells[S("d-null")]["stalled"]), ("대기(분 확인 불가: turn_end 없음)" + tail("d-null"), None))
chk("⑳ [완료·휴식] 이 아닌 「완료했습니다」 → 꼬리 없음", txt("d-plain"), "⚠정지 5분(턴 끝 09:55)")
chk("㉑ 원 쪽지 없는 유지 #999 → 꼬리 없음", txt("d-k999"), "⚠정지 5분(턴 끝 09:55)")
chk("㉒ 기다리는 것에 결론 문구 0", [w for w in (c["wait"] for c in cells.values()) if "다음 일 대기" in w or "처리 없음" in w or "발주 필요" in w], [])
chk("㉒ 모든 기다림 줄 = 추정: 로 시작", [w for w in (c["wait"] for c in cells.values()) if not w.startswith("추정:")], [])
chk("d-keep 기다림 = 완료 선언 추정(승계 문구)", cells[S("d-keep")]["wait"], f"추정: {M} 에 완료 선언 #{F['d-keep']}(09:48) · 기록(05:00 이후)상 이후 {M} → 이 좌석 발신 없음")
# 팀 단위 수
stall_rows = [r for r in t["stalled"] if r[0].endswith("분") and r[0][:-1].isdigit()]
chk("stalled ⚠ 행 수 = 칸 stalled 좌석 수", len(stall_rows), len([c for c in cells.values() if c["stalled"]]))
chk("declared(증거 있음 꼬리) = d-keep·d-null·d-ok·d-ok12·d-work", sorted(x["seat"] for x in t["declared"]), sorted(S(i) for i in ("d-keep", "d-null", "d-ok", "d-ok12", "d-work")))
chk("beta 격 무사고팀 stalled 0", team("w")["stalled"], [])
chk("유팀 stalled 1(9분)", [r[:3] for r in team("u")["stalled"]], [["9분", S("u-stuck"), "09:51"]])
PY
fail=$((fail + $(grep -c '^FAIL' "$T/py.out")))

# 렌더: ⓪ 열 · 좌석 칸 · stalled 출력
TERM="$(board render --term)"; SLACK="$(board render --slack)"
LINE_T="$(printf '%s\n' "$TERM" | grep '^- 시험팀 ')"
has "⓪ term: 정지(3분+) 열 = ⚠ 좌석 수(8) + 첫 좌석" "$LINE_T" "정지(3분+) 8(s-d-badsha#0)"
has "⓪ term: 완료 선언 열 = 증거 있음 꼬리 5 + 첫 좌석·원 쪽지 뒤 N분" "$LINE_T" "완료 선언 5(s-d-keep#0 · 원 쪽지 뒤 12분)"
has "⓪ slack 에도 두 열" "$(printf '%s\n' "$SLACK" | grep '^- 시험팀 ')" "정지(3분+) 8(s-d-badsha#0) | 완료 선언 5(s-d-keep#0"
has "⓪ 무사고팀 = 0 · 0" "$(printf '%s\n' "$TERM" | grep '^- 무사고팀 ')" "정지(3분+) 0 | 완료 선언 0"
has "렌더 ⑩ 좌석 칸(진행 카드 줄)" "$TERM" "s-d-ok#0 정지 5분(턴 끝 09:55) · 완료 선언 #"
has "렌더 ⑪ 정지 5분 ⚠ 가 카드 줄에" "$TERM" "s-i5#0 ⚠정지 5분(턴 끝 09:55)"
has "렌더 ⑭ ⚠완료 뒤 작업" "$TERM" "s-d-work#0 작업중 · 완료 선언 #"
has "슬랙에도 좌석 칸 그대로(금지어 치환 0)" "$SLACK" "s-i5#0 ⚠정지 5분(턴 끝 09:55)"
echo "--- stalled (--min 3) ---"; ST="$(board stalled)"; printf '%s\n' "$ST"
eq "stalled 행 수 = ⚠ 8 + 완료 뒤 작업 1 + 미처리 2 + 유팀 1" "$(printf '%s\n' "$ST" | wc -l | tr -d ' ')" 12
has "stalled ⑪ 행 형식 N분|좌석|턴 끝|기다림" "$ST" "5분|s-i5#0|09:55|추정: 기록(05:00 이후)상 발신 없음"
has "stalled ⑰ 완료 선언 미처리|받는 좌석|보낸 좌석 #seq|N분" "$ST" "완료 선언 미처리|t-master#1|s-d-ok12#0 #"
has "stalled ⑭ 완료 뒤 작업|좌석|#seq|HH:MM" "$ST" "완료 뒤 작업|s-d-work#0|#"
lacks "stalled: ⑩ 증거 있음 좌석(d-ok) 자기 행 0" "$ST" "|s-d-ok#0|"
lacks "stalled: 옛 좌석·정지레디·닫힘 0" "$ST" "s-ready#0"
eq "stalled --team seats-t.json: 명부 밖(유팀) 0" "$(board stalled --team "$FB/seats-t.json" | grep -c 's-u-stuck')" 0
eq "stalled --team seats-u.json = 유팀 1행만" "$(board stalled --team "$FB/seats-u.json" | wc -l | tr -d ' ')" 1
eq "stalled --team seats-w.json = 출력 0(빈 출력)" "$(board stalled --team "$FB/seats-w.json" | wc -c | tr -d ' ')" 0
eq "stalled --min 6: 5분 행 사라지고 9분(유팀)·완료 행은 남음" "$(board stalled --min 6 | grep -c '^5분|')" 0
has "stalled --min 6: 유팀 9분 남음" "$(board stalled --min 6)" "9분|s-u-stuck#0"
board stalled --min x >/dev/null 2>&1; eq "stalled 잘못된 인자 rc=2" "$?" 2
for w in "발주 필요" "다음 일 대기" "처리 없음"; do lacks "출력에 결론 문구 '$w' 0" "$TERM$SLACK$ST" "$w"; done
# 로그 JSON 깨짐 → 기다림 확인 불가 · 꼬리 없음(⚠ 는 그대로 — 가리지 않는다)
echo '{깨진' >> "$FB/comm/mailbox.log.jsonl"
BROKEN="$(board stalled)"
has "로그 JSON 깨짐 → 기다림 확인 불가(사유)" "$BROKEN" "5분|s-i5#0|09:55|기다림 확인 불가(mailbox.log.jsonl "
lacks "로그 깨짐이면 꼬리·미처리 행 0" "$BROKEN" "완료 선언 미처리"
python3 "$BIN/ft-board.py" render --term | grep -q 's-d-ok#0 ⚠정지 5분' && ok "로그 깨짐이면 d-ok 도 ⚠정지로(꼬리 없이)" || bad "로그 깨짐 시 d-ok 칸"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
