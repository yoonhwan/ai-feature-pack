#!/usr/bin/env bash
# test_inbox_waive.sh — ft-inbox.sh waive(판정 558 ④ 명시 면제) 시험. 전부 mktemp 임시 FT_ROOT(가짜 큐) · 라이브 .fable-team 접촉 0 · Haiku/mbox 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INBOX="$REPO/harness/bin/ft-inbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
Q="$FT_ROOT/.fable-team/state/inbox"
M=master-x; ME="$M#9"; CUT="2026-10-08T21:38"; WHY="판정 558 ④ — v423b 설치 전 백로그"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
sum() { md5 -q "$1"; }

seed() {  # <큐 이름> <seq:ts:cls:mark(1|0):group>…  — 줄마다 reported=false · 본문 1줄
  local name="$1"; shift
  python3 - "$Q/$name.jsonl" "$FT_ROOT/.fable-team/comm/bodies" "$@" <<'PY'
import json, sys
q, bd = sys.argv[1], sys.argv[2]
with open(q, "w", encoding="utf-8") as f:
    for spec in sys.argv[3:]:
        head, cls, mark, grp = spec.rsplit(":", 3)  # ts 에 ':' 가 있어 뒤에서부터 자른다
        seq, ts = head.split(":", 1)
        bp = f"{bd}/{seq}.txt"
        open(bp, "w", encoding="utf-8").write(f"[a#1->master-x#9] 본문 {seq}\n")
        row = {"seq": int(seq), "ts": ts, "from": "a#1", "cls": cls, "prio": 1, "group": grp, "body_path": bp,
               "mark": {"kind": "보류", "note": "n", "ts": ts} if mark == "1" else None, "reported": False, "via": "rule"}
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}
field() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(json.dumps(x.get(sys.argv[3]), ensure_ascii=False))' "$@"; }
show_has() { bash "$INBOX" show "$ME" | grep -q "seq=$1[ ,]" ; }

# 픽스처: 경계 전 mark 있는 ①·③·④ 3줄(601~603) · 경계 후 ① 1줄(604) · 경계 전 mark 없는 ① 1줄(605)
seed "$M" "601:2026-10-08T20:00:00:①:1:g601" "602:2026-10-08T21:00:00:③:1:g602" "603:2026-10-08T21:37:59:④:1:g603" \
          "604:2026-10-08T22:00:00:①:1:g604" "605:2026-10-08T20:30:00:①:0:g605"
seed other-x "701:2026-10-08T20:00:00:①:1:g701"
OTHER0="$(sum "$Q/other-x.jsonl")"

# ⓑ 사유에 판정 번호 없음 → rc=2 · 변경 0 (같은 줄에서 --before 형식 오류도 rc=2)
B0="$(sum "$Q/$M.jsonl")"
bash "$INBOX" waive "$ME" --before "$CUT" "그냥 정리" >/dev/null 2>&1; eq "ⓑ 판정 번호 없는 사유 → rc 2" "$?" "2"
eq "ⓑ 거부 뒤 큐 불변" "$(sum "$Q/$M.jsonl")" "$B0"
bash "$INBOX" waive "$ME" --before "어제쯤" "$WHY" >/dev/null 2>&1; eq "ⓑ --before 형식 오류 → rc 2" "$?" "2"
bash "$INBOX" waive "$ME" "$CUT" "$WHY" >/dev/null 2>&1; eq "ⓑ --before 누락 → rc 2" "$?" "2"
eq "ⓑ 오류 뒤 큐 불변" "$(sum "$Q/$M.jsonl")" "$B0"

# ⓐ waive → 앞 3줄 show 에서 사라짐 · 뒤 1줄 남음 · reported 전부 false 그대로
for s in 601 602 603 604; do show_has $s && ok "waive 전 show 에 $s" || bad "waive 전 show 에 $s 없음"; done
OUT="$(bash "$INBOX" waive "$ME" --before "$CUT" "$WHY")"; RC=$?
eq "ⓐ waive rc 0" "$RC" "0"
eq "ⓐ 출력 WAIVED 줄" "$(echo "$OUT" | sed -n 1p)" "WAIVED 3 seq=601,602,603"
for s in 601 602 603; do show_has $s && bad "waive 뒤 show 에 $s 남음" || ok "waive 뒤 show 에서 $s 사라짐"; done
show_has 604 && ok "경계 후 604 는 show 에 남음" || bad "경계 후 604 가 사라짐"
for s in 601 602 603 604 605; do eq "reported 불변 $s" "$(field "$Q/$M.jsonl" $s reported)" "false"; done
eq "waived.by 에 사유 원문" "$(python3 -c 'import json,sys
print([json.loads(l) for l in open(sys.argv[1])][0]["waived"]["by"])' "$Q/$M.jsonl")" "$WHY"
eq "경계 후 604 waived 없음" "$(field "$Q/$M.jsonl" 604 waived)" "null"

# ⓒ mark 없는 경계 전 줄(605) → 면제 0 · SKIPPED_NO_MARK 1
eq "ⓒ SKIPPED_NO_MARK 1" "$(echo "$OUT" | sed -n 2p)" "SKIPPED_NO_MARK 1"
eq "ⓒ 605 면제 안 붙음" "$(field "$Q/$M.jsonl" 605 waived)" "null"
show_has 605 && ok "ⓒ 605 는 show 에 남음" || bad "ⓒ 605 가 사라짐"
eq "ⓒ 재실행 멱등: WAIVED 0" "$(bash "$INBOX" waive "$ME" --before "$CUT" "$WHY" | sed -n 1p)" "WAIVED 0 seq="

# ⓓ 다른 좌석 큐 불변
eq "ⓓ 다른 좌석 큐 바이트 불변" "$(sum "$Q/other-x.jsonl")" "$OTHER0"

# ⓔ waive 뒤 archive → 면제 줄 이동(REFUSED 0) · 이동본에 waived·reported=false 보존
AO="$(bash "$INBOX" archive "$ME")"
eq "ⓔ ARCHIVED 3" "$(echo "$AO" | grep '^ARCHIVED')" "ARCHIVED 3 KEPT 2"
echo "$AO" | grep -Eq "REFUSED seq=(601|602|603) " && bad "ⓔ 면제 줄이 REFUSED" || ok "ⓔ 면제 줄 REFUSED 0"
AR="$(ls "$Q/archive/$M"-*.jsonl)"
eq "ⓔ 이동본 3줄" "$(wc -l < "$AR" | tr -d ' ')" "3"
eq "ⓔ 이동본 waived 보존·reported=false" "$(python3 -c 'import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
print(all(x["waived"]["by"]==sys.argv[2] and x["reported"] is False for x in r))' "$AR" "$WHY")" "True"

# ⓕ 면제 없는 줄: 술어가 옛 식과 전 조합 같음 + show·archive 출력이 옛 동작 골든과 바이트 같음
eq "ⓕ 술어 전 조합(mark×cls×reported×waived키 없음/None)이 옛 식과 같음" "$(python3 - "$REPO/harness/bin" <<'PY'
import itertools, sys
sys.path.insert(0, sys.argv[1])
from ft_inbox_core import CLS, MUST_REPORT, obligation_closed
bad = 0
for mark, cls, rep, kind in itertools.product([None, {"kind": "처리"}], CLS + ["미상"], [False, True], ["absent", "none"]):
    row = {"mark": mark, "cls": cls, "reported": rep}
    if kind == "none":
        row["waived"] = None
    old = mark is not None and (cls not in MUST_REPORT or rep is True)
    bad += obligation_closed(row) != old
print(bad)
PY
)" "0"
seed "$M" "801:2026-10-08T10:00:00:①:1:g801" "802:2026-10-08T10:01:00:⑥:1:g802" "803:2026-10-08T10:02:00:③:0:g803"
FS="$(bash "$INBOX" show "$ME")"
eq "ⓕ show 골든(801 열림·802 닫힘·803 mark 없음 열림)" "$FS" "[①] g801 seq=801 미닫힘=801 from=a#1 원문=$FT_ROOT/.fable-team/comm/bodies/801.txt | [a#1->master-x#9] 본문 801
[③] g803 seq=803 미닫힘=803 from=a#1 원문=$FT_ROOT/.fable-team/comm/bodies/803.txt | [a#1->master-x#9] 본문 803"
FA="$(bash "$INBOX" archive "$ME")"
eq "ⓕ archive 골든(옛 동작: ⑥ 이동 · ① mark만 REFUSED)" "$FA" "REFUSED seq=801 cls=① reported=false — 술어 거짓(이동 거부)
ARCHIVED 1 KEPT 2"

# ⓖ 묶음: 같은 group 에 경계 전 1줄 + 경계 후 1줄 → group_closed 거짓 유지
seed "$M" "901:2026-10-08T20:00:00:①:1:gG" "902:2026-10-08T22:00:00:①:1:gG"
eq "ⓖ 경계 전 1줄만 WAIVED" "$(bash "$INBOX" waive "$ME" --before "$CUT" "$WHY" | sed -n 1p)" "WAIVED 1 seq=901"
bash "$INBOX" show "$ME" | grep -q "gG seq=901,902 미닫힘=902" && ok "ⓖ 묶음 show 유지(미닫힘=902)" || bad "ⓖ 묶음이 닫힘"
bash "$INBOX" archive "$ME" | grep -q "ARCHIVED 0 KEPT 2" && ok "ⓖ 묶음 archive 0건 이동" || bad "ⓖ 묶음이 이동됨"

# 기존 시험 + 키트 사본 동기 + 구문
bash "$HERE/test_kit_bin_sync.sh" >/dev/null 2>&1 && ok "test_kit_bin_sync.sh PASS" || bad "test_kit_bin_sync.sh FAIL"
for f in ft_inbox_core.py ft-inbox.py; do
  cmp -s "$REPO/harness/bin/$f" "$REPO/harness/kit/fable-team/bin/$f" && ok "키트 사본 바이트 같음 $f" || bad "키트 사본 다름 $f"
  [ "$(wc -l < "$REPO/harness/bin/$f")" -le 200 ] && ok "$f 200줄 이하" || bad "$f 200줄 초과"
done

echo "RESULT fail=$fail"
[ "$fail" = 0 ]
