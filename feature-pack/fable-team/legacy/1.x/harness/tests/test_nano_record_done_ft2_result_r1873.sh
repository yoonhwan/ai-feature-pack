#!/usr/bin/env bash
# test_nano_record_done_ft2_result_r1873.sh — r1873 ft2 result 로 owner 를 반납한(null) 2.0 나노도 done 으로 세트·완료 줄을 쓴다: 반례 ①~⑦ + 변이 M1~M3(원본 대조) + 기준판 ① Red.
#   세계 = r1868 시험 세계 재사용(_nano_record_r1717_fixture.sh) + 가짜 FT2_HOME(CURRENT 판 core/cli.py = 정해진 project JSON · core/projection.py = 정해진 records)
#   실 명부·실 ft2 원장·실 우편함·실 tmux·네트워크 0 · sleep 0 · 사례 = 하위 셸 1개(사례마다 새 카드 stem)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
BASE_SHA=e48196031dacb39d8ec38d04738301155eacb7c2   # 기준판 = 이 카드 전 origin/main(r1868 판 — owner.holder 만 인정)
work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; WH="$(g "$PACK" rev-parse HEAD)"; }
fin() { rec done --seat "$1" --card "$2" --did "도구 추가" --test "$TST" --wt "$PACK" "${@:3}"; }
export FT2_HOME="$T/ft2" FT2_LOG="$T/ft2.log" FT2_OUT="$T/ft2.out" FT2_RECS="$T/ft2.recs"; C="$FT2_HOME/versions/9.9.9/core"; mkdir -p "$C"; echo 9.9.9 > "$FT2_HOME/CURRENT"
cat > "$C/cli.py" <<'PY'
import os, sys
open(os.environ["FT2_LOG"], "a", encoding="utf-8").write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(open(os.environ["FT2_OUT"], encoding="utf-8").read())
PY
cat > "$C/projection.py" <<'PY'
import json, os
record = "rec"
def runtime_path(root, team): return os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "runtime")
class Journal:
    def __init__(self, runtime, rec=None): self.runtime, self.rec = runtime, rec
    def records(self):
        open(os.environ["FT2_LOG"], "a", encoding="utf-8").write("records %s rec=%s\n" % (self.runtime, self.rec))
        if os.environ.get("FT2_RECS_RAISE"): raise ValueError("journal 판독 불가")
        return json.load(open(os.environ["FT2_RECS"], encoding="utf-8"))
class journal: Journal = Journal
PY
ft2() {  # ft2 "<work>|<holder 또는 ->|<done true|false>" "<kind>|<work>|<holder>|<gen>"… → 가짜 project(work gen 2 · holder - = owner null) + records
  python3 - "$FT2_OUT" "$FT2_RECS" "$@" <<'PY'
import json, sys
po, pr, w, recs = sys.argv[1], sys.argv[2], sys.argv[3].split("|"), sys.argv[4:]
own = None if w[1] == "-" else {"at": "t", "gen": 2, "holder": w[1]}
json.dump({"holders": {}, "pending": [], "reason": "", "remaining": 0, "result": "접수 성공", "revision": 7, "team": "harness",
           "works": {w[0]: {"deliveries": ["a1"], "done": w[2] == "true", "gen": 2, "owner": own, "uncertain": False}}}, open(po, "w", encoding="utf-8"), ensure_ascii=False)
json.dump([{"seq": i + 1, "kind": r.split("|")[0], "work": r.split("|")[1], "holder": r.split("|")[2], "gen": int(r.split("|")[3])} for i, r in enumerate(recs)], open(pr, "w", encoding="utf-8"))
PY
  : > "$FT2_LOG"
}
nowrite() { t "$1 카드 ref 커밋 0" [ "$(ncommit)" = "$2" ]; t "$1 세트 줄 0" [ "$(nline "$3" '^- 세트: ')" = 0 ]; t "$1 팀장 쪽지 0" [ "$(nto "$MASTER")" = 0 ]; }
rej() {  # rej <번호> <사례 꼬리> <ft2 인자…> → REJECT rc1 · 사유 holder · 쓰기 0
  local s="$2-card" n c0; n="$(NN "$2")"; fresh; card "$s"; seats; work "$s"; ft2 "${@:3}"; c0="$(ncommit)"
  fin "$n" "$s"; t "$1 REJECT rc1" [ "$RC ${OUT%% *}" = "1 REJECT" ]; t "$1 사유" inc "$OUT" "${WHY:-holder}"; nowrite "$1" "$c0" "$s"; return $E
}
step "사전: 짝 사본"
cmp -s "$SRC/ft_nano_record_ft2.py" "$KIT/ft_nano_record_ft2.py" && ok "짝 사본 bin·kit cmp0" || bad "짝 사본 다름"
world
c1() {  # ① owner null + 마지막 result holder = 좌석(뒤 dispatch·claim 0 · gen 같음) → 세트·완료 줄 rc0 · records 읽기 1회
  local w="c1$1" s="c1$1-card" n; n="$(NN "c1$1")"; fresh; card "$s"; seats; work "$s"
  ft2 "$w|-|false" "claim|$w|$n|2" "result|$w|$n|2" "claim|x$w|$(NN o)|2"; fin "$n" "$s" --pr 9; t "① DONE rc0" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "① 세트 줄" [ "$(nline "$s" "^- 세트: $WH · 시험: $TST · 이슈: 0$")" = 1 ]
  t "① 완료 줄" [ "$(nline "$s" "^- 완료: $n · 한 일: 도구 추가 · 산출: nano/$s@${WH:0:10} · 병합 상태: 착지 전(PR #9) · 남은 일: 없음$")" = 1 ]
  t "① 팀장 1통" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $n $s · ")" = 1 ]
  t "① ft2 = project 1회 + records 1회(같은 판 runtime · rec)" [ "$(cat "$FT2_LOG")" = "project --root $ROOT --team harness
records $ROOT/.fable-team/teams/harness/runtime rec=rec" ]; return $E
}
c2() { rej "②" "c2$1" "c2$1|-|false" "result|c2$1|$(NN "c2$1")|2" "dispatch|c2$1|$(NN o)|2"; }   # ② result 뒤 다른 좌석 dispatch → REJECT
c3() { rej "③" "c3$1" "c3$1|-|false" "result|c3$1|$(NN o)|2"; }                                # ③ 마지막 result holder 다름 → REJECT
c4() { WHY="반환" rej "④" "c4$1" "c4$1|-|true" "result|c4$1|$(NN "c4$1")|2"; }                 # ④ done true → REJECT
c5() { rej "⑤" "c5$1" "c5$1|-|false" "claim|c5$1|$(NN "c5$1")|2"; }                            # ⑤ result 줄 0 + owner null → REJECT
c7() { rej "⑦" "c7$1" "c7$1|-|false" "result|c7$1|$(NN "c7$1")|1"; }                           # ⑦ 옛 세대(gen 1) result → REJECT
c6() {  # ⑥ records 판독 예외 → 판정 불가 rc3 · 쓰기 0
  local w="c6$1" s="c6$1-card" n c0; n="$(NN "c6$1")"; fresh; card "$s"; seats; work "$s"; ft2 "$w|-|false" "result|$w|$n|2"; c0="$(ncommit)"
  FT2_RECS_RAISE=1 fin "$n" "$s"; t "⑥ 판정 불가 rc3" [ "$RC ${OUT%% *}" = "3 판정" ]; t "⑥ 사유" inc "$OUT" "ft2 journal"; nowrite "⑥" "$c0" "$s"; return $E
}
step "반례 ①~⑦"
run "① owner null + result holder = 좌석 → DONE" c1; run "② result 뒤 dispatch → REJECT" c2; run "③ result holder 다름 → REJECT" c3
run "④ done true → REJECT" c4; run "⑤ result 0 → REJECT" c5; run "⑥ records 예외 → 판정 불가" c6; run "⑦ 옛 세대 result → REJECT" c7
step "변이 M1~M3 (+원본 대조)"
if grep -q 'r1873-mut:after' "$SRC/ft_nano_record_ft2.py"; then
  mutbin m1 ft_nano_record_ft2.py 'return not any(' 'return True or not any('; mutcase M1 c2 1
  mutbin m2 ft_nano_record_ft2.py ' or r.get("holder") != seat' ''; mutcase M2 c3 2
  mutbin m3 ft_nano_record_ft2.py ' or r.get("gen") != gen' ''; mutcase M3 c7 3
else bad "변이 M1~M3 — 변이 자리 없음(고침 전)"; fi
step "기준판 ① (팩 $BASE_SHA — owner.holder 만)"
BASE="$T/base"; mkdir -p "$BASE"; cp "$SRC"/*.py "$SRC"/ft-nano-record.sh "$SRC"/ft-team-lib.sh "$SRC"/ft-nano-close-due.sh "$BASE/"
if git -C "$H" show "$BASE_SHA:./bin/ft_nano_record_ft2.py" > "$BASE/ft_nano_record_ft2.py" 2>/dev/null; then
  if o="$(BIN="$BASE"; TOOL="$BIN/ft-nano-record.sh"; c1 base)"; then bad "기준판에서 ① 이 통과함"; else ok "기준판 ① FAIL(기대 Red) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
else bad "기준판 꺼내기 실패"; fi
finish
