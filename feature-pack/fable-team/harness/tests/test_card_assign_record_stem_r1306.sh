#!/usr/bin/env bash
# test_card_assign_record_stem_r1306.sh — r1306 record 가 이름(stem)으로도 카드를 풀어 원장을 쓴다 · 못 찾거나 이름이 겹치면 REJECT rc1 ·
#   디스크에 없고 tip 에만 있으면 원장만 + NOTE 1줄(거울 0). 반례 R1~R6·R4b + 변이 4(실파일 치환 → 그 칸만 실행 → 복구).
# 임시 git 리포(카드 = tip 객체 + 디스크) · 실 STATE·실 좌석·실 쪽지 0 · 네트워크 0 · tmux 0 · 고정 sleep 0 · 자기 재호출 = 재진입 표지 + R1306_CHECK 칸 한정.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_record_stem_r1306.sh
[ -z "${R1306_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1306_TEST_ACTIVE 가 이미 켜져 있다(R1306_CHECK 칸만 자식 허용)"; exit 3; }; export R1306_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY FT_CARD_ASSIGN_NOW
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; SAVE=""; trap '[ -n "$SAVE" ] && cp "$SAVE" "$TOOL"; rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="${TOOL_RUN:-$BIN/ft_card_assign_watch.py}"; NOW=$(date +%s); H=design/harness/indices; CHECK="${R1306_CHECK:-all}"
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t.com commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 R = git 리포(main) + 카드 루트 표 + 명부 · 원장 = R/.fable-team/state/card-assign
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state" "$R/$H/대기" "$R/design"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | design/harness/ | h | 현역 |\n| room | design/teams/room/ | r | 현역 |\n' > "$R/design/TEAMS.md"
  printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-harness-master-claude#149"}\n' > "$R/.fable-team/seats-harness.json"
  printf '{"_master":"byz-room-master-claude#1"}\n' > "$R/.fable-team/seats-room.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  git -C "$R" add -A design; gc "$R" "$((NOW - 200000)) +0900" teams
}
card() {  # <R> <상대경로> <커밋 epoch> <머리 줄...>
  local r="$1" p="$2" d="$3"; shift 3; mkdir -p "$(dirname "$r/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" "## 상태" "- 시험" > "$r/$p"; git -C "$r" add -A design; gc "$r" "$d +0900" "card $p"
}
run() { OUT="$(cd "$R" && env FT_ROOT="$R" python3 "$TOOL" "$@" 2>&1)"; RC=$?; }
rec() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_CARD_ASSIGN_NOW="$NOW" python3 "$TOOL" record "$@" 2>&1)"; RC=$?; }
prep() { run prepare >/dev/null; }
ledger() { [ -f "$R/.fable-team/state/card-assign/$1.json" ]; }
jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$R/.fable-team/state/card-assign/$1.json" "$2" 2>/dev/null; }
one() { [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = "$2" ]; }
MIRROR='^- 배정: 대기(정지 · [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9])$'
DUP="REJECT 배정 원장 — 이름 중복 dup (design/harness/indices/대기/dup.md, design/teams/room/indices/대기/dup.md) · 원장 키가 이름이라 기록 불가 · 카드 이름을 바꿔라"

r1() {  # 이름 인자 = 경로 인자와 같은 원장·같은 카드 바이트·같은 출력
  new_root; card "$R" "$H/대기/s1.md" "$((NOW - 9000))" "- 상태: 대기"; rec s1 waiting 정지
  local a="$RC|$OUT|$(cat "$R/.fable-team/state/card-assign/s1.json")|$(cat "$R/$H/대기/s1.md")"
  new_root; card "$R" "$H/대기/s1.md" "$((NOW - 9000))" "- 상태: 대기"; rec "$R/$H/대기/s1.md" waiting 정지
  local b="$RC|$OUT|$(cat "$R/.fable-team/state/card-assign/s1.json")|$(cat "$R/$H/대기/s1.md")"
  [ "$a" = "$b" ] && case "$a" in 0\|"배정 원장 s1 → waiting 정지"\|*'"reason": "정지"'*) true;; *) false;; esac \
    && printf '%s\n' "$(cat "$R/$H/대기/s1.md")" | grep -q "$MIRROR" \
    && ok "R1 이름 = 경로(원장 json·카드 바이트·출력 같음 · 거울 1줄) · rc0" || bad "R1 a=$a b=$b"
}
r2() {  # 디스크 없음 · tip 에만 → 원장 + NOTE · 디스크 쓰기 0 · urgent 는 tip 본문
  new_root; card "$R" "$H/대기/s2.md" "$((NOW - 9000))" "- 상태: 대기" "- 긴급: 예"; rm "$R/$H/대기/s2.md"; rec s2 waiting 부하
  [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^NOTE 거울 줄 0 — 디스크에 카드 없음(tip 에만 · .*:design/harness/indices/대기/s2.md)$' \
    && printf '%s\n' "$OUT" | grep -qx '배정 원장 s2 → waiting 부하' && one "$OUT" 2 \
    && [ "$(jget s2 state)" = waiting ] && [ "$(jget s2 reason)" = 부하 ] && [ "$(jget s2 urgent)" = True ] && [ ! -e "$R/$H/대기/s2.md" ] \
    && ok "R2 tip 에만 있음 = 원장 + NOTE 1줄 · 디스크 쓰기 0 · urgent = tip 본문 · rc0" || bad "R2 rc=$RC :: $OUT"
}
r3() {  # 어디에도 없음 = REJECT rc1 · 원장 0
  new_root; card "$R" "$H/대기/s3.md" "$((NOW - 9000))" "- 상태: 대기"; rec no-such-card waiting 정지
  [ "$RC" = 1 ] && one "$OUT" 1 && printf '%s\n' "$OUT" | grep -qx 'REJECT 배정 원장 — 카드 없음 no-such-card(tip·디스크)' && ! ledger no-such-card \
    && ok "R3 어디에도 없음 = REJECT 1줄 rc1 · 원장 0(옛 WARN rc0 = 조용한 통과 0)" || bad "R3 rc=$RC :: $OUT"
}
dup_root() { new_root; card "$R" "$H/대기/dup.md" "$((NOW - 9000))" "- 상태: 대기"; card "$R" "design/teams/room/indices/대기/dup.md" "$((NOW - 9000))" "- 상태: 대기"; }
r4() {  # 같은 이름 두 팀 = REJECT · 원장 0
  dup_root; rec dup waiting 정지
  [ "$RC" = 1 ] && [ "$OUT" = "$DUP" ] && ! ledger dup && ok "R4 이름 중복 = REJECT(두 경로 · 이름을 바꿔라) rc1 · 원장 0" || bad "R4 rc=$RC :: $OUT"
}
r4b() {  # 경로 인자도 같은 중복 거절(DA① 반례 1) · 다른 팀 status 줄 그대로
  dup_root; prep; run status; local before; before="$(printf '%s\n' "$OUT" | grep '^없음 room dup · 원장 없음')"
  rec "$R/$H/대기/dup.md" waiting 정지; local a="$RC|$OUT"; prep; run status; local after; after="$(printf '%s\n' "$OUT" | grep '^없음 room dup · 원장 없음')"
  [ "$a" = "1|$DUP" ] && ! ledger dup && [ -n "$before" ] && [ "$before" = "$after" ] \
    && ok "R4b 경로 인자도 같은 중복 REJECT rc1 · 원장 0 · room status 줄 그대로" || bad "R4b a=$a :: before=$before after=$after"
}
r5() {  # 경로 인자 = 지금 그대로(디스크 있음) · 디스크 없으면 REJECT rc1(옛 WARN rc0)
  new_root; card "$R" "$H/대기/s5.md" "$((NOW - 9000))" "- 상태: 대기"; rec "$R/$H/대기/s5.md" waiting 정지
  local a="$RC|$(jget s5 state)|$(grep -c -- "$MIRROR" "$R/$H/대기/s5.md")"
  new_root; card "$R" "$H/대기/s5.md" "$((NOW - 9000))" "- 상태: 대기"; rm "$R/$H/대기/s5.md"; rec "$R/$H/대기/s5.md" waiting 정지
  local b="$RC|$OUT"
  [ "$a" = "0|waiting|1" ] && [ "$b" = "1|REJECT 배정 원장 — 카드 없음 $R/$H/대기/s5.md" ] && ! ledger s5 \
    && ok "R5 경로·디스크 있음 = 지금 그대로(원장+거울 rc0) · 디스크 없음 = REJECT rc1 · 원장 0" || bad "R5 a=$a b=$b"
}
r6() {  # status 가 «원장 없음» 으로 보인 카드에 이름으로 record → 그 줄 0 · 원장 waiting/정지
  new_root; card "$R" "$H/대기/s6.md" "$((NOW - 9000))" "- 상태: 대기"; prep; run status
  local before; before="$(printf '%s\n' "$OUT" | grep ' s6 ')"
  rec s6 waiting 정지; local rc="$RC|$(jget s6 state)|$(jget s6 reason)"; prep; run status
  local after; after="$(printf '%s\n' "$OUT" | grep -c ' s6 ')"
  case "$before" in "없음 harness s6 · 원장 없음 · since "*) true;; *) false;; esac \
    && [ "$rc" = "0|waiting|정지" ] && [ "$after" = 0 ] \
    && ok "R6 «원장 없음» 카드에 이름으로 record → 원장 waiting·정지 · 다음 status 그 줄 0 · rc0" || bad "R6 before=$before rc=$rc after=$after"
}

if [ "$CHECK" != all ]; then
  case "$CHECK" in r1) r1;; r2) r2;; r3) r3;; r4) r4;; r4b) r4b;; r5) r5;; r6) r6;; *) echo "알 수 없는 칸 $CHECK"; exit 2;; esac
  [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

r1; lap R1
r2; lap R2
r3; lap R3
r4; lap R4
r4b; lap R4b
r5; lap R5
r6; lap R6

# ── 변이 4 — 실파일 치환 → 그 칸만 실행 → 복구
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
sha0="$(shasum "$TOOL" | cut -d' ' -f1)"; SAVE="$T/save.py"; cp "$TOOL" "$SAVE"
mutate() {  # <이름> <바꿀 문자열> <바꿀 값> <칸>
  mut "$SAVE" "$T/mut.py" "$2" "$3" && cp "$T/mut.py" "$TOOL" || { cp "$SAVE" "$TOOL"; bad "변이 $1 치환 실패"; return; }
  ( cd "$REPO" && env -u R1306_TEST_ACTIVE R1306_CHECK="$4" bash "$SELF" >"$T/mut-$1.out" 2>&1 ); local mrc=$?
  cp "$SAVE" "$TOOL"
  [ "$mrc" -ne 0 ] && ok "변이 $1 → $4 빨강(rc=$mrc)" || bad "변이 $1 이 $4 에 안 잡힘 :: $(cat "$T/mut-$1.out")"
}
mutate 1 '    print(f"NOTE 거울 줄 0 — 디스크에 카드 없음(tip 에만 · {hits[0][0]}:{hits[0][2]})")
    return path, git(hits[0][0], "show", f"{hits[0][1]}:{hits[0][2]}")' '    raise Rejected(f"REJECT 배정 원장 — 카드 없음 {stem}(tip·디스크)")' r2
mutate 2 '            return 1' '            return 0' r3
mutate 3 '    if len(hits) > 1:' '    if len(hits) > 1 and ispath:' r4
mutate 4 '    if len(hits) > 1:' '    if len(hits) > 1 and not ispath:' r4b
SAVE=""
[ "$(shasum "$TOOL" | cut -d' ' -f1)" = "$sha0" ] && ok "변이 복구 — 실파일 sha 같음(잔여 변이 0)" || bad "변이 복구 실패(실파일이 바뀌었다)"
lap 변이

# ── bin·kit 같음 · 문법 · 모드 · 줄 수
cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit 같은 내용(ft_card_assign_watch.py)" || bad "bin·kit 다름"
python3 -m py_compile "$BIN/ft_card_assign_watch.py" && bash -n "$BIN/ft-card-assign-watch.sh" && ok "py_compile · bash -n" || bad "문법"
m="$(stat -f %Lp "$HERE/test_card_assign_record_stem_r1306.sh")"; [ "$m" = 644 ] && ok "새 시험 모드 644" || bad "새 시험 모드 $m"
n="$(wc -l < "$BIN/ft_card_assign_watch.py" | tr -d ' ')"; [ "$n" -le 700 ] && ok "ft_card_assign_watch.py ${n}줄 ≤700(이미 200 초과 · 알려진 한계 · r1306 +$((n - 667))줄)" || bad "줄 수 $n"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
