#!/usr/bin/env bash
# test_headline_seats_r1290.sh — r1290 팀 헤드라인 좌석 칸 초안(ft_headline_seats · ft-stall-scan 이 처리 끝에 덮어씀).
#   본문 = tests/scripts/test_stall_scan_headline_seats_r1290.py (R1~R11 · 판정 = 이번 scan 의 좌석 캐시뿐 · 화면 읽기 0)
#   + 재작업 W1~W7(쓰는 꼴 = 읽는 꼴 · 변이 ⑩~⑬) + 회귀(초록 stall 시험 4종 · 빨간 24건은 r1289 착지본 그대로 = 목록 보고) + 변이 9종
# 격리: 합성 jsonl·턴 스텁 · 가짜 명부·tmux·mbox·seat-status(임시 폴더 · FT_ROOT 임시 루트) — 실 좌석 발신 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_py() { (cd "$SC" && R1290_BIN="$1" pytest -q -p no:cacheprovider $2 >"$T/py.log" 2>&1); }

run_py "$KIT" test_stall_scan_headline_seats_r1290.py; ck "R1~R11 · W1~W7 $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?

# ⓕ — 회귀: 지금 초록인 stall 시험(원장 「stall_ 목록」 은 아래 echo). 빨간 24건은 r1289 착지본에서 이미 빨강(내 변경 전후 동일 실측).
for t in test_ft_stall_scan_off_roster.py test_ft_stall_scan_wake_r638.py test_ft_penalty.py test_stall_heartbeat_promoted_r1154.py; do
  run_py "$KIT" "$t"; ck "ⓕ 회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
done
echo "stall_ 시험 목록: $(cd "$SC" && ls test_*stall_*.py | tr '\n' ' ')"
echo "착지본 빨강(내 변경 전후 동일 · r1289 «m.» 팀 이름과 TEAMS 폴더 꼴이 어긋남): test_ft_stall_scan.py 3 · test_stall_scan_headline_age.py 18 · test_stall_scan_heartbeat_desk_r1143.py 3"

# 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_headline_seats.py" "$TRK/ft_stall_detect.py" "$TRK/ft_stall_seats.py" "$TRK/ft_stall_scan.py" "$TRK/ft_team_main_inputs.py" | awk '{print $1}' | tr '\n' ' ')"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 시험 노드
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" "test_stall_scan_headline_seats_r1290.py::$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "API 오류 표식 제거" ft_stall_detect.py '"err": _error_at(turn[-1]) if turn else None' '"err": None' test_r3_api_error_turn_is_error_cell
mutate "오류 뒤 정상 턴도 오류로" ft_stall_detect.py '"err": _error_at(turn[-1]) if turn else None' '"err": next((_error_at(r) for r in recs if is_error(r)), None)' test_r4_normal_turn_after_error_is_idle
mutate "UTC 시각 그대로" ft_headline_seats.py 'at, today = time.localtime(stamp), time.localtime(now)' 'at, today = time.gmtime(stamp), time.localtime(now)' test_r1_idle_turn_end_is_local_clock
mutate "IDLE 을 «작업 중»" ft_headline_seats.py '        return UNDECIDED if info.get("end") is None else f"{MARK} {clock(info.get('"'"'end'"'"'), now)}"' '        return "작업 중"' test_r6_screen_ghost_text_is_not_used
mutate "jsonl 없음을 «✻ —»" ft_headline_seats.py '        return UNDECIDED  # jsonl 없는 좌석' '        return f"{MARK} -"  # jsonl 없는 좌석' test_r7_seat_without_jsonl_is_undecided
mutate "_closed 행 포함" ft_stall_detect.py 'and v.get("role") not in OFF_ROLES and not v.get("_replaced_by") and not v.get("_closed")}' 'and v.get("role") not in OFF_ROLES and not v.get("_replaced_by")}' test_r8_closed_and_stop_ready_are_not_cells
mutate "덮어쓰기 대신 append" ft_headline_seats.py '        _ = temporary.write_text(text + "\n", encoding="utf-8")
        os.replace(temporary, folder_path / "HEADLINE-seats.txt")' '        with open(folder_path / "HEADLINE-seats.txt", "a", encoding="utf-8") as handle:
            _ = handle.write(text + "\n")' test_r9_only_a_processing_run_rewrites_the_draft
mutate "묶음 접기 제거" ft_headline_seats.py '    items = list(cells_list)
    if len(" · ".join(items)) <= limit:
        return items' '    items = list(cells_list)
    return items' test_r10_many_idle_seats_are_folded
mutate "팀 이름 낱말 떼기 제거" ft_headline_seats.py '        if words and words[0] == match.group("team"):' '        if False:' test_r11_short_names
# ── 재작업 W(판정 3240 — 쓰는 꼴 1줄 vs 읽는 쪽 TAB 꼴) ──
mutate "파싱을 옛 TAB 분리로 되돌림" ft_team_main_inputs.py '    cells, folded = headline.parse(_text(path))' '    cells, folded = ({p[0].strip(): p[1].strip() for p in (x.split("\t") for x in _read(path)) if len(p) >= 2 and p[0].strip()}, False)' test_w1_draft_line_parses_into_card_cells
mutate "풀린 칸 0 판정 불가 제거" ft_team_main_inputs.py '"why": None if cells else "초안 꼴 다름"}' '"why": None}' test_w2_garbage_line_is_form_unknown
mutate "조회 키를 카드 stem 전체로" ft_team_main_inputs.py 'key = str(stem).split("-", 1)[0]' 'key = str(stem)' test_w1_draft_line_parses_into_card_cells
mutate "칸 정규식을 첫 «)» 에서 끊음" ft_headline_seats.py '^(?P<name>[^=()]+)=\?\((?P<cell>.*)\)$' '^(?P<name>[^=()]+)=\?\((?P<cell>[^)]*)\).*$' test_w1_draft_line_parses_into_card_cells
sha_after="$(shasum "$TRK/ft_headline_seats.py" "$TRK/ft_stall_detect.py" "$TRK/ft_stall_seats.py" "$TRK/ft_stall_scan.py" "$TRK/ft_team_main_inputs.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?

# 짝 사본(bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 100644
for n in ft_headline_seats.py ft_stall_detect.py ft_stall_seats.py ft_stall_scan.py ft_team_main_inputs.py ft_team_main.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
grep -q 'ft_headline_seats' "$KIT/ft_stall_scan.py"; ck "scan 이 초안을 부른다" $?
[ "$(stat -f %Lp "$HERE/test_headline_seats_r1290.sh")" = 644 ]; ck "새 시험 모드 644" $?
[ "$(stat -f %Lp "$SC/test_stall_scan_headline_seats_r1290.py")" = 644 ]; ck "새 시험 본문 모드 644" $?
echo "ft_headline_seats.py $(wc -l <"$KIT/ft_headline_seats.py")줄(신설) · ft_stall_scan.py $(wc -l <"$KIT/ft_stall_scan.py")줄(origin/main 378 · +3)"
echo "FAIL=$fail"; [ "$fail" = 0 ]
