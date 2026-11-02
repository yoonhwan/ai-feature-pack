#!/usr/bin/env bash
# test_card_assign_tick_race_r1325.sh — r1325 배정 감시 tick 표식 경합 반례 C1~C8 + 변이 W1~W6 + bin·kit 같음 + cwd 무관.
# 임시 git 리포(실 git) · 가짜 mbox 스텁(쪽지 1줄 + 본문 기록 · 겹침 표식 = race 파일이 있을 때만 상대를 최대 1.2초 기다린다 · 고정 대기는 이 한 곳) · 실 STATE·실 좌석·실 쪽지 0 · 네트워크 0.
# 자기 재호출 0(재진입 표지) · 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_tick_race_r1325.sh
[ -z "${R1325_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1325_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1325_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY FT_CARD_ASSIGN_NOW
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
TOOL="$BIN/ft_card_assign_watch.py"
cd / || exit 2   # 부르는 쪽 cwd 의존 0(r1310·r1311 반송 사유)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT   # & 자식(동시 tick·잠금 점유) 정리 — r1234
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
PLANNER='byz-planner-master-claude#9'; HMASTER='byz-harness-master-claude#33'
H=design/harness/indices
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 R = git 리포 + 카드 루트 표 + 명부(_master) + 가짜 mbox(겹침 표식·본문 기록)
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state" "$R/$H/대기"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\nsent.log\nres.log\nrace\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$(( $(date +%s) - 200000 )) +0900" init
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | design/harness/ | h | 현역 |\n' > "$R/design/TEAMS.md"
  printf 'harness\t.\tmain\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s"}\n' "$PLANNER" > "$R/.fable-team/seats-planner.json"; printf '{"_master":"%s"}\n' "$HMASTER" > "$R/.fable-team/seats-harness.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  cat > "$R/mbox.sh" <<'STUB'
#!/usr/bin/env bash
d="$(dirname "$0")"
printf '%s\x1f%s\n' "$2" "$(printf '%s' "$4" | tr '\n' '|')" >> "$d/sent.log"
if [ "$2" = "${FAKE_FAIL_TO:-}" ]; then printf '%s fail\n' "$2" >> "$d/res.log"; echo "REJECT 가짜"; exit 3; fi
printf '%s ok\n' "$2" >> "$d/res.log"
if [ -f "$d/race" ] && [ ! -f "$d/w.$$" ]; then  # 겹침 창 — 상대 프로세스가 들어오면 바로, 없으면 최대 1.2초만
  : > "$d/w.$$"; i=0
  while [ "$(cut -d' ' -f1 "$d/res.log" | sort -u | wc -l | tr -d ' ')" -lt 2 ] && [ "$i" -lt 24 ]; do sleep 0.05; i=$((i+1)); done
fi
echo "QUEUED seq=1 to=$2"
STUB
  : > "$R/sent.log"; : > "$R/res.log"
}
card() {  # <R> <상대경로> <커밋 epoch> <머리 줄...>
  local r="$1" p="$2" d="$3"; shift 3; mkdir -p "$(dirname "$r/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" "## 상태" "- 시험" > "$r/$p"; git -C "$r" add -A design; gc "$r" "$d +0900" "card $p"
}
led() { mkdir -p "$R/.fable-team/state/card-assign"; printf '%s\n' "$3" > "$1/.fable-team/state/card-assign/$2.json"; }
run() { OUT="$(cd "$R" && env -u FT_CARD_ASSIGN_NOW FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
prep() { run prepare >/dev/null; }
sent() { grep -c . "$R/sent.log" 2>/dev/null || true; }
res() { grep -c -- "^$1 ok" "$R/res.log" 2>/dev/null || true; }
hd() { printf '%s\n' "$OUT" | head -1; }
h_of() { python3 -c 'import hashlib,sys; print(hashlib.sha1(repr(sorted([(sys.argv[1], sys.argv[2], sys.argv[3])])).encode()).hexdigest()[:12])' "$1" "$2" "$3"; }
env1() {  # 대기 초과 카드 1장 + 준비(prepare) — 사유·나이 지정
  new_root; card "$R" "$H/대기/t1.md" "$(( $(date +%s) - 90000 ))" "- 상태: 대기"
  led "$R" t1 '{"state":"waiting","reason":"'"${1:-lint}"'","since":'$(( $(date +%s) - 18000 ))'}'; prep
}

# ── C1 동시 tick 2개 = 받는이마다 1통(합 2 · 기준판은 3~4) · C2 이어서 1개 더 = 0통
c1() {
  env1; : > "$R/race"
  ( cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" tick >/dev/null 2>&1 ) &
  ( cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" tick >/dev/null 2>&1 ) &
  wait; rm -f "$R/race"
  CZ="$(res "$PLANNER"):$(res "$HMASTER")"; echo "$CZ"
}
c2() { run tick; CZ="$(res "$PLANNER"):$(res "$HMASTER")"; echo "$CZ"; }
c1; c1v="$CZ"; c2; c2v="$CZ"   # 서브셸 금지 — c2 가 c1 이 만든 루트·표식을 그대로 본다
[ "$c1v" = "1:1" ] && [ "$c2v" = "1:1" ] && ok "C1 동시 tick 2개 = 받는이마다 1통(합 2) · C2 다음 tick 60분 억제 0통" || bad "C1·C2 c1=$c1v c2=$c2v :: $(cat "$R/sent.log")"
lap C1C2
# ── C3 스텁 발신 실패(planner) → planner 0통 · harness 1통 · 다음 tick 에 planner 1통(선점 되돌림)
c3() { env1; FAKE_FAIL_TO="$PLANNER" run tick; local a b; a="$(res "$PLANNER"):$(res "$HMASTER")"; run tick; b="$(res "$PLANNER")"; echo "$a:$b"; }
c3v="$(c3)"
[ "$c3v" = "0:1:1" ] && ok "C3 발신 실패 = planner 0통 · harness 1통 · 다음 tick planner 1통(선점 되돌림)" || bad "C3 $c3v :: $(cat "$R/sent.log")"
lap C3
# ── C4 죽은 선점 pending(t = 지금−61초) = 1통 / t = 지금−30초 = 0통
c4() {
  env1; local h; h="$(h_of t1 lint 초과)"
  printf '{"%s":{"h":"%s","t":%s,"pending":true}}\n' "$PLANNER" "$h" "$(( $(date +%s) - 61 ))" > "$R/.fable-team/state/card-assign/alarm.state"
  run tick; echo "$(res "$PLANNER")"
}
c4v="$(c4)"
env1; h="$(h_of t1 lint 초과)"; printf '{"%s":{"h":"%s","t":%s,"pending":true}}\n' "$PLANNER" "$h" "$(( $(date +%s) - 30 ))" > "$R/.fable-team/state/card-assign/alarm.state"
run tick
[ "$c4v" = "1" ] && [ "$(res "$PLANNER")" = "0" ] && ok "C4 죽은 선점 61초 = 1통(60분 막힘 0) · 30초 = 0통(발신 중)" || bad "C4 61초=$c4v 30초=$(res "$PLANNER")"
lap C4
# ── C5 다른 프로세스가 잠금 8초 쥠 → «표식 잠금 7초 넘김» 1줄 · 0통 · 판정 불가 rc3
c5() {
  env1
  python3 -c 'import fcntl,os,sys,time; f=open(sys.argv[1],"a+"); fcntl.flock(f,fcntl.LOCK_EX); time.sleep(8)' "$R/.fable-team/state/card-assign/lock" &
  local hp=$!; sleep 0.3; run tick; local o="$RC:$(sent)"
  kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
  case "$OUT" in *"tick 판정 불가 · 표식 잠금 7초 넘김"*) echo "$o:line";; *) echo "$o:noline";; esac
}
c5v="$(c5)"
[ "$c5v" = "3:0:line" ] && ok "C5 잠금 8초 점유 = «표식 잠금 7초 넘김» 1줄 · 쪽지 0 · rc3" || bad "C5 $c5v :: $OUT"
lap C5
# ── C6 집합이 바뀜(카드 1장 추가) → 새 해시 1통씩(설계 그대로)
c6() {
  new_root; local t; t=$(( $(date +%s) - 90000 ))
  card "$R" "$H/대기/t1.md" "$t" "- 상태: 대기"; led "$R" t1 '{"state":"waiting","reason":"lint","since":'$(( $(date +%s) - 18000 ))'}'; prep; run tick
  local a; a="$(res "$PLANNER")"
  card "$R" "$H/대기/t2.md" "$t" "- 상태: 대기"; led "$R" t2 '{"state":"waiting","reason":"lint","since":'$(( $(date +%s) - 18000 ))'}'; prep; run tick
  echo "$a:$(res "$PLANNER")"
}
c6v="$(c6)"
[ "$c6v" = "1:2" ] && ok "C6 집합 변화(카드 1장 추가) → 새 해시 1통 더(합 2)" || bad "C6 $c6v"
lap C6
# ── C7 (D4=2) 석·선행 = 경보·rc 밖 · 머리 «석·선행 대기 K» / 사람만 → 초과 1 · rc1 · 본문 = 사람 1장만
c7a() {
  new_root; local t; t=$(( $(date +%s) - 90000 )); local s=$(( $(date +%s) - 18000 ))
  card "$R" "$H/대기/k1.md" "$t" "- 상태: 대기"; card "$R" "$H/대기/k2.md" "$t" "- 상태: 대기"; card "$R" "$H/대기/k3.md" "$t" "- 상태: 대기"
  led "$R" k1 '{"state":"waiting","reason":"석","since":'$s'}'; led "$R" k2 '{"state":"waiting","reason":"선행","since":'$s'}'; led "$R" k3 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$s'}'; prep
  run tick; echo "$RC:$(hd | cut -d'·' -f2):$(printf '%s' "$OUT" | grep -c '석·선행 대기 2'):$(sent):$(grep -c 'k3' "$R/sent.log"):$(grep -c 'k1' "$R/sent.log")"
}
c7b() {
  new_root; local t; t=$(( $(date +%s) - 90000 )); local s=$(( $(date +%s) - 18000 ))
  card "$R" "$H/대기/k1.md" "$t" "- 상태: 대기"; card "$R" "$H/대기/k2.md" "$t" "- 상태: 대기"
  led "$R" k1 '{"state":"waiting","reason":"석","since":'$s'}'; led "$R" k2 '{"state":"waiting","reason":"선행","since":'$s'}'; prep
  run tick; echo "$RC:$(hd | cut -d'·' -f2):$(printf '%s' "$OUT" | grep -c '석·선행 대기 2'):$(sent)"
}
c7av="$(c7a)"; c7bv="$(c7b)"
[ "$c7av" = "1: 대기 초과 1(사람 1) :1:2:2:0" ] && [ "$c7bv" = "0: 대기 초과 0 :1:0" ] \
  && ok "C7 석·선행 5시간 = «석·선행 대기 2» 칸 · 초과 = 사람 1장만(본문 k3 1 · k1 0) · rc1 / 석·선행만 = 0통 · rc0" || bad "C7 a=$c7av b=$c7bv"
lap C7
# ── C8 석 카드가 사유 «사람» 으로 바뀜(since 유지) → 다음 tick 사람 1장 1통 · rc1
c8() {
  env1 석; run tick; local a="$RC:$(sent)"
  led "$R" t1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$(( $(date +%s) - 18000 ))'}'
  run tick; echo "$a:$RC:$(sent)"
}
c8v="$(c8)"
[ "$c8v" = "0:0:1:2" ] && ok "C8 석 5시간 = 0통 rc0 → 사유 사람(since 유지) → tick 1통(받는이 2) rc1" || bad "C8 $c8v"
lap C8

# ── 변이 (하나씩 독립 · 그 칸만 다시 돈다 · 변이마다 bin·kit cmp0)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
mcopy() { rm -rf "$T/m"; mkdir -p "$T/m"; cp "$BIN"/ft_*.py "$T/m/"; }
MW="$T/m/ft_card_assign_watch.py"
w() { mcopy; mut "$TOOL" "$MW" "$1" "$2" 2>/dev/null || { echo "MUTFAIL $1" >&2; return 1; }; cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" || { echo "bin·kit-diff" >&2; return 1; }; }
w1() { w '        marks[key] = {"h": h, "t": now, "pending": True}' '        pass  # 변이 W1 — 선점 없음(지금 꼴)' || return 1; TOOL_RUN="$MW" c1; }
w2() { w '                    marks.pop(key, None)' '                    pass  # 변이 W2 — 실패해도 선점 안 지움' || return 1; TOOL_RUN="$MW" c3; }
w3() { w '    return now - float(m.get("t", 0)) < (CLAIM_S if m.get("pending") else MUTE_S)' '    return now - float(m.get("t", 0)) < MUTE_S  # 변이 W3 — pending 60초 만료 삭제' || return 1; TOOL_RUN="$MW" c4; }
w4() { w '        raise Undecided("표식 잠금 7초 넘김") from None' '        return log  # 변이 W4 — 잠금 넘김을 조용히 0통' || return 1; TOOL_RUN="$MW" c5; }
w5() { w '        if self.now - start > WAIT_S and row["reason"] in WAIT_REASONS:' '        if False:  # 변이 W5 — 석·선행 제외 삭제' || return 1; TOOL_RUN="$MW" c7a; }
w6() { w ' · ref 미반영 팀 {ref_missing}" + wait' ' · ref 미반영 팀 {ref_missing}"  # 변이 W6 — 석·선행 칸 누락' || return 1; TOOL_RUN="$MW" c7b; }
v1="$(w1)"; [ -n "$v1" ] && [ "$v1" != "1:1" ] && ok "변이W1 선점 기록 제거 → C1 빨강($v1)" || bad "변이W1 이 C1 에 안 잡힘($v1)"
v2="$(w2)"; [ -n "$v2" ] && [ "$v2" != "0:1:1" ] && ok "변이W2 실패 때 선점 유지 → C3 빨강($v2)" || bad "변이W2 이 C3 에 안 잡힘($v2)"
v3="$(w3)"; [ -n "$v3" ] && [ "$v3" != "1" ] && ok "변이W3 pending 만료 삭제 → C4 빨강($v3)" || bad "변이W3 이 C4 에 안 잡힘($v3)"
v4="$(w4)"; [ -n "$v4" ] && [ "$v4" != "3:0:line" ] && ok "변이W4 잠금 넘김 조용히 → C5 빨강($v4)" || bad "변이W4 이 C5 에 안 잡힘($v4)"
v5="$(w5)"; [ -n "$v5" ] && [ "$v5" != "1: 대기 초과 1(사람 1) :1:2:2:0" ] && ok "변이W5 석·선행 제외 삭제 → C7 빨강($v5)" || bad "변이W5 가 C7 에 안 잡힘($v5)"
v6="$(w6)"; [ -n "$v6" ] && [ "$v6" != "0: 대기 초과 0 :1:0" ] && ok "변이W6 석·선행 칸 누락 → C7 빨강($v6)" || bad "변이W6 이 C7 에 안 잡힘($v6)"
lap mutation
# ── bin·kit 같음 · 문법 · 새 파일 모드
cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit 같은 내용" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" && bash -n "$HERE/test_card_assign_tick_race_r1325.sh" && ok "py_compile · bash -n" || bad "문법"
m="$(stat -f %Lp "$HERE/test_card_assign_tick_race_r1325.sh")"; [ "$m" = "644" ] && ok "새 시험 파일 모드 644(실행 비트 0)" || bad "새 시험 파일 모드 $m"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
