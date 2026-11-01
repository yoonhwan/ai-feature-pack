#!/usr/bin/env bash
# test_card_assign_paused_held_r1291.sh — r1291 배정 감시 «팀 정지 표식(PAUSED) = 정지 중» · «사람 보류 = 첫 1회만» 반례 R1~R12 + 변이 10 + bin·kit 같음.
# 임시 git 리포 · 임시 데이터 루트(state/card-assign · state/<팀>-tick/PAUSED · directive-roots.tsv) · FT_CARD_ASSIGN_NOW 고정 · FT_MBOX_SH 스텁(받은 쪽지 기록 · QUEUED 출력) · 네트워크 0 · 실 STATE·실 좌석·실 쪽지 0.
# 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_paused_held_r1291.sh
[ -z "${R1291_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1291_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1291_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
cut() {
  if [ "${1:-}" = "-d·" ] || { [ "${1:-}" = "-d" ] && [ "${2:-}" = "·" ]; }; then
    local fields
    if [ "${1:-}" = "-d·" ]; then fields="${2#-f}"; else fields="${3#-f}"; fi
    command python3 -c 'import sys; a=sys.argv[1]; lo,sep,hi=a.partition("-"); lo=int(lo); hi=int(hi) if sep and hi else lo; [print("·".join(line.rstrip("\n").split("·")[lo-1:hi])) for line in sys.stdin]' "$fields"
  elif [[ "${1:-}" == -c* ]]; then
    command python3 -c 'import sys; a=sys.argv[1][2:]; lo,sep,hi=a.partition("-"); lo=int(lo); hi=int(hi) if sep and hi else lo; [print(line.rstrip("\n")[lo-1:hi]) for line in sys.stdin]' "$1"
  else
    command cut "$@"
  fi
}
export -f cut
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"
PLANNER='byz-planner-master-claude#9'; KMASTER='byz-knowledge-master-claude#1'; HMASTER='byz-harness-master-claude#33'
NOW=$(date +%s); H=design/harness/indices; KD=design/teams/knowledge/indices
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state" "$R/$H/대기"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\nsent.log\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | design/harness/ | h | 현역 |\n| knowledge | design/teams/knowledge/ | k | 현역 |\n' > "$R/design/TEAMS.md"
  printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s"}\n' "$PLANNER" > "$R/.fable-team/seats-planner.json"; printf '{"_master":"%s"}\n' "$HMASTER" > "$R/.fable-team/seats-harness.json"
  printf '{"_master":"%s"}\n' "$KMASTER" > "$R/.fable-team/seats-knowledge.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/usr/bin/env bash\nprintf "%%s\\x1f%%s\\n" "$2" "$(printf "%%s" "$4" | tr "\\n" "|")" >> "$(dirname "$0")/sent.log"\n[ "$2" = "${FAKE_FAIL_TO:-}" ] && { echo "REJECT 가짜"; exit 3; }\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"; : > "$R/sent.log"
}
card() {  # <R> <상대경로> <커밋 epoch> <머리 줄...>
  local r="$1" p="$2" d="$3"; shift 3; mkdir -p "$(dirname "$r/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" "## 상태" "- 시험" > "$r/$p"; git -C "$r" add -A design; gc "$r" "$d +0900" "card $p"
}
led() { mkdir -p "$1/.fable-team/state/card-assign"; printf '%s\n' "$3" > "$1/.fable-team/state/card-assign/$2.json"; }
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
prep() { run prepare >/dev/null; }
sent() { grep -c "${1:-.}" "$R/sent.log" 2>/dev/null || true; }
hd() { printf '%s\n' "$OUT" | head -1; }
PZ() { mkdir -p "$R/.fable-team/state/$1-tick"; printf '%s\n' "$2" > "$R/.fable-team/state/$1-tick/PAUSED"; }
iso() { date -r "$1" +%Y-%m-%dT%H:%M:%S; }
STATE() { echo "$R/.fable-team/state/card-assign/$1"; }
# 지식 팀 대기 카드 5시간 초과(선행) 1장 + 시험용 환경 — 판정 3037 표식 = 시험 입력
k_env() {
  new_root; card "$R" "$KD/대기/k1.md" "$((NOW - 90000))" "- 상태: 대기"; led "$R" k1 '{"state":"waiting","reason":"선행","since":'$((NOW-18000))'}'; prep
}
GOOD="판정 3037 · $(iso $((NOW - 3600))) · 정지 레디 재개 대기"

# ⓐ R1 — knowledge PAUSED + 선행 5시간 → 정지 중 · [긴급] 0 · rc0 / R2 PAUSED 없음 → 초과 · 1통(지금 동작)
k_env; PZ knowledge "$GOOD"; run tick; a="$RC:$(hd | cut -d'·' -f2-3):$(sent)"
k_env; run tick; b="$RC:$(hd | cut -d'·' -f2-3):$(sent "^$PLANNER")"
[ "$a" = "0: 대기 초과 0 · 정지 중 1 :0" ] && [ "$b" = "1: 대기 초과 1(선행 1) · 정지 중 0 :1" ] && ok "R1 PAUSED 있음 = 정지 중 1 · 초과 0 · 쪽지 0 · rc0 / R2 없음 = 초과 1 · 쪽지 1 · rc1" || bad "R1·R2 a=$a b=$b"
lap R1R2
# ⓑ R3 — 풀림: team-resume(또는 손 삭제) 시각 T → T+1시간 0통 · T+4시간 1분 초과 1통 (tick 이 seen 표로 풀림 시각을 적는다)
r3() {  # <resume 방식 manual|cmd>
  k_env; PZ knowledge "$GOOD"; run tick
  if [ "$1" = cmd ]; then (cd "$R" && FT_ROOT="$R" python3 "$TOOL" team-resume knowledge >/dev/null); else rm -f "$R/.fable-team/state/knowledge-tick/PAUSED"; fi
  run tick; r3a="$(sent)"; FT_CARD_ASSIGN_NOW=$((NOW + 3600)) run tick; r3b="$(sent)"; FT_CARD_ASSIGN_NOW=$((NOW + 4*3600 + 60)) run tick; r3c="$(sent)"
  echo "$r3a$r3b$r3c:$(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(int(j.get("released_at",0))>=int(sys.argv[2]))' "$(STATE k1.json)" "$NOW")"
}
c1="$(r3 cmd)"; c2="$(r3 manual)"
[ "$c1" = "002:True" ] && [ "$c2" = "002:True" ] && ok "R3 team-resume·손 삭제 모두 → 풀린 직후·1시간 0통 · 4시간 1분 2통(planner+팀장) · released_at = 풀림 시각" || bad "R3 cmd=$c1 manual=$c2"
lap R3
# ⓒ R4 — 25시간 정지 → 정지 중 · planner [정지 24시간] 1통 · 같은 날 0통 · 다음 날 1통
k_env; PZ knowledge "판정 3037 · $(iso $((NOW - 25*3600))) · 정지 레디 재개 대기"; run tick; d1="$(sent "정지 24시간")"; run tick; d2="$(sent "정지 24시간")"
FT_CARD_ASSIGN_NOW=$((NOW + 86400)) run tick; d3="$(sent "정지 24시간")"
d3b="$(grep -c "정지 24시간" "$R/sent.log")"
[ "$d1:$d2" = "1:1" ] && [ "$d3b" = 2 ] && ok "R4 25시간 → 정지 중 · 1통 · 같은 날 다음 tick 0통 · 다음 날 tick 1통" || bad "R4 d=$d1:$d2:$d3b"
python3 - "$(STATE paused-notice.json)" <<'PY' || true
import json, sys
f = sys.argv[1]; j = json.load(open(f)); k = next(iter(j)); json.dump({"2000-01-01": ["knowledge"], k: j[k]}, open(f, "w"))
PY
run tick; d4="$(python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' "$(STATE paused-notice.json)" | grep -c 2000-01-01)"
[ "$d4" = 0 ] && ok "R4′ 옛 날짜 키 지움" || bad "R4′ 옛 날짜 키 남음"
lap R4
# ⓓ R5 — 빈 파일 / 판정 번호 없음 / 폴더 / 사유 짧음 → 판정 불가 Q · notes 1줄 · [긴급] 0 · 조용한 «정지 중» 아님
r5() { k_env; case "$1" in empty) PZ knowledge "";; nov) PZ knowledge "$(iso $NOW) · 정지 레디 재개 대기";; short) PZ knowledge "판정 3037 · $(iso $NOW) · 짧음";; dir) mkdir -p "$R/.fable-team/state/knowledge-tick/PAUSED";; esac; run tick; echo "$RC:$(hd | cut -d'·' -f3-4):$(printf '%s\n' "$OUT" | grep -c '^정지 표식 판정 불가 knowledge '):$(sent)"; }
e1="$(r5 empty)"; e2="$(r5 nov)"; e3="$(r5 short)"; e4="$(r5 dir)"; want="0: 정지 중 0 · 판정 불가 Q 1 :1:0"
[ "$e1" = "$want" ] && [ "$e2" = "$want" ] && [ "$e3" = "$want" ] && [ "$e4" = "$want" ] && ok "R5 빈 파일·판정 번호 없음·사유 짧음·폴더 = 판정 불가 Q 1 · notes 1줄 · 쪽지 0 · rc0" || bad "R5 $e1 | $e2 | $e3 | $e4"
lap R5
# ⓔ R6 — 사유 사람(verdict 3061) 4시간 1분 → 1통 · 61분 뒤 → 보류 중 · 0통 · 머리 줄 H
h_env() { new_root; card "$R" "$H/대기/p1.md" "$((NOW - 90000))" "- 상태: 대기"; (cd "$R" && FT_ROOT="$R" FT_CARD_ASSIGN_NOW=$((NOW - 4*3600 - 60)) python3 "$TOOL" record "$R/$H/대기/p1.md" waiting 사람 verdict 3061 >/dev/null) 2>/dev/null; prep; }
h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'
run tick; f1="$RC:$(sent)"; FT_CARD_ASSIGN_NOW=$((NOW + 3660)) run status; f2="$RC:$(hd | cut -d'·' -f2-4)"; FT_CARD_ASSIGN_NOW=$((NOW + 3660)) run tick; f3="$(sent)"
run status; f4="$RC:$(hd | cut -d'·' -f2-4)"; sb="$(sent)"; run tick; sa="$(sent)"
[ "$f1" = "1:2" ] && [ "$f2" = "0: 대기 초과 0 · 정지 중 0 · 보류 중 1 " ] && [ "$f3" = 2 ] && [ "$f4" = "0: 대기 초과 0 · 정지 중 0 · 보류 중 1 " ] && [ "$sb" = "$sa" ] && ok "R6 첫 초과 1회(planner+팀장 2통) 뒤 보류 중 H=1 · rc0 · 이후 tick 0통" || bad "R6 f1=$f1 f2=$f2 f3=$f3 f4=$f4"
lap R6
# ⓕ R7 — R6 뒤 사유가 «석» 으로 바뀜(since 유지) → 보류 중 아님 · 초과 1
led "$R" p1 '{"state":"waiting","reason":"석","since":'$((NOW-4*3600-60))'}'; run status; g="$RC:$(hd | cut -d'·' -f2)"
[ "$g" = "1: 대기 초과 1(석 1) " ] && ok "R7 사유가 바뀌면 키가 달라져 보류 중 아님 → 초과(석)" || bad "R7 $g"
lap R7
# ⓖ R8 — record 사람 판정 번호 없음 → REJECT rc2 · 원장 그대로
new_root; card "$R" "$H/대기/q1.md" "$NOW" "- 상태: 대기"; rr() { (cd "$R" && FT_ROOT="$R" python3 "$TOOL" record "$R/$H/대기/q1.md" "$@" 2>&1); }
o1="$(rr waiting 사람)"; r1=$?; o2="$(rr waiting 사람 verdict abc)"; r2=$?; o3="$(rr waiting 사람 verdict 3061)"; r3x=$?
verdict_ok="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("verdict"))' "$(STATE q1.json)" 2>/dev/null)"
case "$o1" in *"판정 번호 필수"*) m1=1;; *) m1=0;; esac
[ "$m1" = 1 ] && [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3x" = 0 ] && [ "$verdict_ok" = 3061 ] && ok "R8 사람 보류 판정 번호 없음·숫자 아님 → REJECT rc2 · 번호 있으면 원장에 verdict 3061" || bad "R8 r=$r1/$r2/$r3x v=$verdict_ok :: $o1"
lap R8
# ⓗ R9 — «사람» 카드가 완성으로 감 → held-once 키 지움 · 표 크기 ≤ 열린 사람 카드 수
h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'; run tick
n1="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$(STATE held-once.json)")"
mkdir -p "$R/$H/완성"; git -C "$R" mv "$H/대기/p1.md" "$H/완성/p1.md"; gc "$R" "$NOW +0900" done; run status
n2="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$(STATE held-once.json)")"
[ "$n1" = 1 ] && [ "$n2" = 0 ] && ok "R9 첫 경보 뒤 키 1 → 완성 이동 뒤 키 0 (원장도 삭제)" || bad "R9 n1=$n1 n2=$n2"
lap R9
# ⓘ R10 — H=0 머리 줄 = 옛 판(보류 중 칸 없음) / H=2 → «정지 중 P · 보류 중 2»
new_root; for c in a b; do card "$R" "$H/대기/$c.md" "$((NOW - 90000))" "- 상태: 대기"; led "$R" $c '{"state":"waiting","reason":"사람","verdict":"1","since":'$((NOW-18000))'}'; done; card "$R" "$H/대기/z.md" "$((NOW - 90000))" "- 상태: 대기"; led "$R" z '{"state":"waiting","reason":"선행","since":'$((NOW-18000))'}'; prep
run status; H0="$(hd | sed 's/판본.*//')"
run tick >/dev/null; run status; H2="$(hd | sed 's/판본.*//')"
case "$H0" in "배정 없는 카드 0 · 대기 초과 3(사람 2 · 선행 1) · 정지 중 0 · 카드 없는 발주 0 · ") z0=1;; *) z0=0;; esac
case "$H2" in "배정 없는 카드 0 · 대기 초과 1(선행 1) · 정지 중 0 · 보류 중 2 · 카드 없는 발주 0 · ") z2=1;; *) z2=0;; esac
[ "$z0" = 1 ] && [ "$z2" = 1 ] && ok "R10 보류 중 0 = 머리 줄에 칸 없음(옛 판 꼴) · 2 = «정지 중 0 · 보류 중 2 · 카드 없는 발주»" || bad "R10 H0=[$H0] H2=[$H2]"
lap R10
# ⓙ R11 — 긴급 카드(1시간) · 그 팀 PAUSED → 정지 중(정지 우선)
new_root; card "$R" "$KD/대기/u1.md" "$((NOW - 90000))" "- 상태: 대기" "- 긴급: 예"; led "$R" u1 '{"state":"waiting","reason":"선행","since":'$((NOW-7200))'}'; prep; PZ knowledge "$GOOD"; run tick; i1="$RC:$(hd | cut -d'·' -f2-3):$(sent)"
[ "$i1" = "0: 대기 초과 0 · 정지 중 1 :0" ] && ok "R11 긴급 카드(1시간 초과)도 팀 PAUSED = 정지 중 · 쪽지 0" || bad "R11 $i1"
lap R11
# ⓚ R12 — 첫 «사람» 경보 발신이 QUEUED 아님 → held-once 기록 0 · 다음 tick 다시 1통
h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'
# 모든 받는이 발신 실패를 주입한다(planner·팀장 둘 다 REJECT)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "$(dirname "$0")/sent.log"\necho "REJECT 가짜 전부"; exit 3\n' > "$R/mbox.sh"; rm -f "$(STATE held-once.json)" "$(STATE alarm.state)"; : > "$R/sent.log"
run tick >/dev/null; l1="$([ -f "$(STATE held-once.json)" ] && echo has || echo none)"; run tick >/dev/null; l2="$(sent)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "$(dirname "$0")/sent.log"\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"; run tick >/dev/null; l3="$(sent)"; l4="$([ -f "$(STATE held-once.json)" ] && echo has || echo none)"
[ "$l1" = none ] && [ "$l2" -ge 2 ] && [ "$l4" = has ] && ok "R12 모든 발신 REJECT → 기록 0 · 다음 tick 다시 발신 · QUEUED 가 나간 뒤에만 기록" || bad "R12 l1=$l1 l2=$l2 l3=$l3 l4=$l4"
lap R12

# ── 변이 10 (그 칸만 다시 돈다 — 변이마다 bin 사본 1개 · 해당 R 칸만)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
mcopy() { rm -rf "$T/m"; mkdir -p "$T/m"; cp "$BIN"/ft_*.py "$T/m/"; }
W="$BIN/ft_card_assign_watch.py"; P="$BIN/ft_card_assign_pause.py"; MW="$T/m/ft_card_assign_watch.py"; MP="$T/m/ft_card_assign_pause.py"
m1() { mcopy; mut "$W" "$MW" '        if tp[0] != "none":' '        if False:'; k_env; PZ knowledge "$GOOD"; TOOL_RUN="$MW" run tick; case "$(hd)" in *"대기 초과 1"*) echo ok;; esac; }
m2() { mcopy; mut "$W" "$MW" '            j["released_at"] = self.now
            save(d, stem, j)
            L.update(j)' '            save(d, stem, j)
            L.update(j)'; k_env; PZ knowledge "$GOOD"; TOOL_RUN="$MW" run tick; rm -f "$R/.fable-team/state/knowledge-tick/PAUSED"; TOOL_RUN="$MW" run tick; [ "$(sent)" -ge 2 ] && echo ok; }
m3() { mcopy; mut "$P" "$MP" '        if team in sent[day]:
            continue' '        if False:
            continue'; k_env; PZ knowledge "판정 3037 · $(iso $((NOW - 25*3600))) · 정지 레디 재개 대기"; TOOL_RUN="$MW" run tick; TOOL_RUN="$MW" run tick; [ "$(grep -c '정지 24시간' "$R/sent.log")" -ge 2 ] && echo ok; }
m4() { mcopy; mut "$P" "$MP" '        return "q", "표식 꼴 아님(판정 <N> · <시각> · <사유 10자+>)", 0.0, ""' '        return "on", "꼴 틀림 통과", time.time(), ""'; k_env; PZ knowledge ""; TOOL_RUN="$MW" run tick; case "$(hd)" in *"정지 중 1"*) echo ok;; esac; }
m5() { mcopy; mut "$P" "$MP" '    return hkey(stem, reason, since) in held' '    return False'; h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'; TOOL_RUN="$MW" run tick >/dev/null; FT_CARD_ASSIGN_NOW=$((NOW + 3660)) TOOL_RUN="$MW" run status; case "$(hd)" in *"대기 초과 1"*) echo ok;; esac; }
m6() { mcopy; mut "$W" "$MW" '"보류 중" if row["reason"] == "사람" and held_once' '"보류 중" if held_once'; mut "$P" "$MP" 'return stem not in gone and L.get("state") == "waiting" and L.get("reason") == reason and' 'return True or'; h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'; TOOL_RUN="$MW" run tick >/dev/null; led "$R" p1 '{"state":"waiting","reason":"석","since":'$((NOW-4*3600-60))'}'; TOOL_RUN="$MW" run status; case "$(hd)" in *"대기 초과 1(석 1)"*) ;; *) echo ok;; esac; }
m7() { mcopy; mut "$W" "$MW" 'if kind == "waiting" and arg == "사람" and not (verdict or "").isdigit():' 'if False:'; new_root; card "$R" "$H/대기/q1.md" "$NOW" "- 상태: 대기"; (cd "$R" && FT_ROOT="$R" python3 "$MW" record "$R/$H/대기/q1.md" waiting 사람 >/dev/null 2>&1); [ "$?" = 0 ] && echo ok; }
m9() { mcopy; mut "$W" "$MW" "if n['보류 중'] else ''" "if True else ''"; new_root; card "$R" "$H/대기/z.md" "$((NOW - 90000))" "- 상태: 대기"; led "$R" z '{"state":"waiting","reason":"선행","since":'$((NOW-18000))'}'; prep; TOOL_RUN="$MW" run status; case "$(hd)" in *"보류 중 0"*) echo ok;; esac; }
m10() { mcopy; mut "$W" "$MW" '        p = subprocess.run(["bash", mbox, "send", to, me, text], capture_output=True, text=True, timeout=7)' '        for x in grows:
            if x["reason"] == "사람":
                held_add(R, x["stem"], "사람", x["since"])
        p = subprocess.run(["bash", mbox, "send", to, me, text], capture_output=True, text=True, timeout=7)'; h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'; printf '#!/usr/bin/env bash\necho "REJECT 가짜 전부"; exit 3\n' > "$R/mbox.sh"; TOOL_RUN="$MW" run tick >/dev/null; [ -f "$(STATE held-once.json)" ] && echo ok; }
for i in 1 2 3 4 5 6 7 8 9 10; do
  case "$i" in
    1) why="PAUSED 갈래 제거 → R1";; 2) why="풀림 때 released_at 안 씀 → R3";; 3) why="24시간 알림 날짜 키 제거 → R4";; 4) why="꼴 틀림을 정지 중으로 → R5";; 5) why="held-once 제거 → R6";;
    6) why="사유 확인(가드·키 대조) 제거 → R7";; 7) why="판정 번호 검사 제거 → R8";; 8) why="완성 때 키 안 지움 → R9";; 9) why="«보류 중 0» 늘 표시 → R10";; 10) why="QUEUED 전 기록 → R12";;
  esac
  [ "$i" = 8 ] && continue
  res="$(m$i 2>&1 | tail -1)"; [ "$res" = ok ] && ok "변이$i($why) → 그 칸 빨강" || bad "변이$i($why) 이 안 잡힘 :: $res"
done
lap mutation
# 변이 8 — 완성 이동 때 키를 안 지우는 변이: held_prune 의 gone 검사 제거 + 원장 삭제 흉내(닫힌 카드는 status 가 원장을 지우므로 키가 «열린 카드 없음» 으로 남는지)
mcopy; mut "$P" "$MP" 'return stem not in gone and L.get("state") == "waiting"' 'return True or L.get("state") == "waiting"'
h_env; led "$R" p1 '{"state":"waiting","reason":"사람","verdict":"3061","since":'$((NOW-4*3600-60))'}'; TOOL_RUN="$MW" run tick >/dev/null
mkdir -p "$R/$H/완성"; git -C "$R" mv "$H/대기/p1.md" "$H/완성/p1.md"; gc "$R" "$NOW +0900" done; TOOL_RUN="$MW" run status >/dev/null
k8="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$(STATE held-once.json)")"; [ "$k8" = 1 ] && ok "변이8(완성 때 키 안 지움) → R9 빨강(키 1 남음)" || bad "변이8 이 안 잡힘 k=$k8"
lap m8

# ⓛ bin·kit 같음 · 문법 · 새 파일 모드 · 줄 수
for f in ft_card_assign_watch.py ft_card_assign_pause.py ft-card-assign-watch.sh; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용 3파일"
python3 -m py_compile "$BIN/ft_card_assign_pause.py" "$TOOL" 2>/dev/null && bash -n "$BIN/ft-card-assign-watch.sh" && ok "py_compile · bash -n" || bad "문법"
m="$(stat -f %Lp "$BIN/ft_card_assign_pause.py" "$KIT/ft_card_assign_pause.py" "$HERE/test_card_assign_paused_held_r1291.sh" | sort -u | tr '\n' ' ')"; [ "$m" = "644 " ] && ok "새 파일 모드 644" || bad "새 파일 모드 $m"
n="$(wc -l < "$BIN/ft_card_assign_pause.py" | tr -d ' ')"; [ "$n" -le 140 ] && ok "pause 모듈 ${n}줄" || bad "pause 모듈 줄 수 $n"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
