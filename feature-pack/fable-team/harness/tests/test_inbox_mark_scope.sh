#!/usr/bin/env bash
# test_inbox_mark_scope.sh — R326: ft-inbox.sh mark·report 는 «호출 좌석 큐» 하나만 고친다(남의 큐 줄 불변).
# 전부 mktemp 임시 FT_ROOT(가짜 큐 2개) · 실 인박스·실 mbox·Haiku 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INBOX="$REPO/scripts/fable-team-bin/ft-inbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
unset FT_SEAT TMUX_PANE
Q="$FT_ROOT/.fable-team/state/inbox"
A=seat-a; B=seat-b; AS="$A#3"; BS="$B#7"; GID=g-shared
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
sum() { md5 -q "$1"; }
field() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(json.dumps(x.get(sys.argv[3]) if sys.argv[3]!="mark" else (x["mark"] or {}).get("kind"), ensure_ascii=False))' "$@"; }

seed() {  # 큐 A: 701(group) 703(A 전용) · 큐 B: 702(group) 704(B 전용) — 전부 cls ③ · 미mark · 미report
  python3 - "$Q" "$FT_ROOT/.fable-team/comm/bodies" "$A" "$B" "$GID" <<'PY'
import json, sys
q, bd, a, b, gid = sys.argv[1:6]
def row(seq, grp):
    bp = f"{bd}/{seq}.txt"; open(bp, "w", encoding="utf-8").write(f"[x#1->y#1] 본문 {seq}\n")
    return {"seq": seq, "ts": "2026-10-17T20:00:00", "from": "x#1", "cls": "③", "prio": 1, "group": grp,
            "body_path": bp, "mark": None, "reported": False, "via": "rule"}
for name, rows in ((a, [row(701, gid), row(703, "g-a-only")]), (b, [row(702, gid), row(704, "g-b-only")])):
    with open(f"{q}/{name}.jsonl", "w", encoding="utf-8") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
PY
}

# ⓐ 같은 group 이 A·B 큐에 있을 때 A 로 mark → A 줄만 변경 · B 줄 불변
seed; B0="$(sum "$Q/$B.jsonl")"
bash "$INBOX" mark "$GID" 처리 "A 몫" --seat "$AS" >/dev/null 2>&1; rc=$?
eq "ⓐ mark --seat A rc" "$rc" "0"
eq "ⓐ A 큐 701 mark 처리" "$(field "$Q/$A.jsonl" 701 mark)" '"처리"'
eq "ⓐ B 큐 파일 불변" "$(sum "$Q/$B.jsonl")" "$B0"
# ⓐ' report 도 같은 범위
seed; B0="$(sum "$Q/$B.jsonl")"
bash "$INBOX" report "$GID" --seat "$AS" >/dev/null 2>&1; rc=$?
eq "ⓐ' report --seat A rc" "$rc" "0"
eq "ⓐ' A 큐 701 reported" "$(field "$Q/$A.jsonl" 701 reported)" "true"
eq "ⓐ' B 큐 파일 불변" "$(sum "$Q/$B.jsonl")" "$B0"

# ⓑ B 에만 있는 seq 를 A 로 mark/report → rc 1 · 두 큐 불변 · 안내에 B 계보 이름
seed; A0="$(sum "$Q/$A.jsonl")"; B0="$(sum "$Q/$B.jsonl")"
ERR="$(bash "$INBOX" mark 704 처리 "남의 줄" --seat "$AS" 2>&1 >/dev/null)"; rc=$?
eq "ⓑ 남의 seq mark rc" "$rc" "1"
echo "$ERR" | grep -q "$B" && ok "ⓑ 안내에 다른 계보($B) 표시" || bad "ⓑ 안내에 $B 없음 ($ERR)"
eq "ⓑ A 큐 불변" "$(sum "$Q/$A.jsonl")" "$A0"; eq "ⓑ B 큐 불변" "$(sum "$Q/$B.jsonl")" "$B0"
bash "$INBOX" report 704 --seat "$AS" >/dev/null 2>&1; rc=$?
eq "ⓑ 남의 seq report rc" "$rc" "1"
eq "ⓑ report 뒤 A 큐 불변" "$(sum "$Q/$A.jsonl")" "$A0"; eq "ⓑ report 뒤 B 큐 불변" "$(sum "$Q/$B.jsonl")" "$B0"
# ⓑ' 어느 큐에도 없는 대상은 기존대로 rc≠0
bash "$INBOX" mark 999999 처리 "없음" --seat "$AS" >/dev/null 2>&1; [ $? -ne 0 ] && ok "ⓑ' 없는 seq rc≠0" || bad "ⓑ' 없는 seq 통과"

# ⓒ 좌석 인자·FT_SEAT 모두 없음 → rc 2 · 쓰기 0
seed; A0="$(sum "$Q/$A.jsonl")"; B0="$(sum "$Q/$B.jsonl")"
bash "$INBOX" mark "$GID" 처리 "좌석 없음" >/dev/null 2>&1; rc=$?
eq "ⓒ mark 좌석 없음 rc" "$rc" "2"
bash "$INBOX" report "$GID" >/dev/null 2>&1; rc=$?
eq "ⓒ report 좌석 없음 rc" "$rc" "2"
eq "ⓒ A 큐 불변" "$(sum "$Q/$A.jsonl")" "$A0"; eq "ⓒ B 큐 불변" "$(sum "$Q/$B.jsonl")" "$B0"

# FT_SEAT 환경 대체 + --seat 우선
seed; B0="$(sum "$Q/$B.jsonl")"
FT_SEAT="$AS" bash "$INBOX" mark 703 처리 "env" >/dev/null 2>&1; rc=$?
eq "FT_SEAT mark rc" "$rc" "0"; eq "FT_SEAT A 큐 703 mark" "$(field "$Q/$A.jsonl" 703 mark)" '"처리"'
FT_SEAT="$BS" bash "$INBOX" mark 701 처리 "인자 우선" --seat "$AS" >/dev/null 2>&1
eq "--seat 이 FT_SEAT 보다 우선(A 701)" "$(field "$Q/$A.jsonl" 701 mark)" '"처리"'
eq "--seat 우선 시 B 큐 불변" "$(sum "$Q/$B.jsonl")" "$B0"

# tmux 안(TMUX_PANE) + FT_SEAT 없음 → 현재 tmux 세션 이름이 좌석(안내 명령 `mark <seq> 처리 "1줄"` 이 그대로 통한다)
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "$FAKE_TMUX_SESSION"\n' > "$T/bin/tmux"; chmod +x "$T/bin/tmux"
seed; B0="$(sum "$Q/$B.jsonl")"
TMUX_PANE=%1 FAKE_TMUX_SESSION="$AS" PATH="$T/bin:$PATH" bash "$INBOX" mark 703 처리 "tmux" >/dev/null 2>&1; rc=$?
eq "tmux 폴백 mark rc" "$rc" "0"; eq "tmux 폴백 A 큐 703 mark" "$(field "$Q/$A.jsonl" 703 mark)" '"처리"'
TMUX_PANE=%1 FAKE_TMUX_SESSION="$AS" PATH="$T/bin:$PATH" bash "$INBOX" report 703 >/dev/null 2>&1
eq "tmux 폴백 report A 큐 703" "$(field "$Q/$A.jsonl" 703 reported)" "true"
eq "tmux 폴백 B 큐 불변" "$(sum "$Q/$B.jsonl")" "$B0"
# tmux 가 이름을 못 주면(빈 출력) 추측 없이 rc 2
seed; A0="$(sum "$Q/$A.jsonl")"
TMUX_PANE=%1 FAKE_TMUX_SESSION="" PATH="$T/bin:$PATH" bash "$INBOX" mark 703 처리 "x" >/dev/null 2>&1; rc=$?
eq "tmux 이름 빈 값 → rc 2" "$rc" "2"; eq "tmux 이름 빈 값 → 큐 불변" "$(sum "$Q/$A.jsonl")" "$A0"

echo "FAILED=$fail"; [ "$fail" -eq 0 ]
