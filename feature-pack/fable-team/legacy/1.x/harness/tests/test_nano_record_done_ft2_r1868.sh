#!/usr/bin/env bash
# test_nano_record_done_ft2_r1868.sh — r1868 명부 행 없는 2.0 나노(ft2 원장의 그 일 현재 holder)도 done 으로 세트·완료 줄을 쓴다: 반례 ①~⑦ + 변이 M1~M3(변이마다 원본 대조) + 기준판 ① Red.
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote 2 · 사본 리포 2 · 가짜 명부·mbox·tmux) + 가짜 ft2(FT2_HOME 임시 폴더 · CURRENT 판 core/cli.py 가 정해진 JSON 출력)
#   실 명부·실 ft2 원장·실 우편함·실 tmux·네트워크 0 · sleep 0 · 사례 = 하위 셸 1개(사례마다 새 카드 stem)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
BASE_SHA=2595d3e6d563a4e88d289206fb7604ebb7033b90   # 기준판 = 이 카드 전 origin/main
work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; WH="$(g "$PACK" rev-parse HEAD)"; }
fin() { rec done --seat "$1" --card "$2" --did "도구 추가" --test "$TST" --wt "$PACK" "${@:3}"; }
export FT2_HOME="$T/ft2" FT2_LOG="$T/ft2.log" FT2_OUT="$T/ft2.out"; mkdir -p "$FT2_HOME/versions/9.9.9/core"; echo 9.9.9 > "$FT2_HOME/CURRENT"
cat > "$FT2_HOME/versions/9.9.9/core/cli.py" <<'PY'
import os, sys
open(os.environ["FT2_LOG"], "a", encoding="utf-8").write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(open(os.environ["FT2_OUT"], encoding="utf-8").read())
sys.exit(int(os.environ.get("FT2_RC") or 0))
PY
ft2out() {  # ft2out <결과> "<work>|<holder>|<done true|false>"… → 가짜 project 출력(실측 2.0.23 꼴 · works = work 키 dict)
  python3 - "$FT2_OUT" "$@" <<'PY'
import json, sys
p, res, rows = sys.argv[1], sys.argv[2], sys.argv[3:]
w = {r.split("|")[0]: {"deliveries": ["a1"], "done": r.split("|")[2] == "true", "gen": 2, "owner": {"at": "t", "gen": 2, "holder": r.split("|")[1]}, "uncertain": False} for r in rows}
json.dump({"holders": {}, "pending": [], "reason": "", "remaining": [], "result": res, "revision": 7, "team": "harness", "works": w}, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  : > "$FT2_LOG"
}
nowrite() { t "$1 카드 ref 커밋 0" [ "$(ncommit)" = "$2" ]; t "$1 세트 줄 0" [ "$(nline "$3" '^- 세트: ')" = 0 ]; t "$1 팀장 쪽지 0" [ "$(nto "$MASTER")" = 0 ]; }
step "사전: 짝 사본 · 줄 수"
for f in ft_nano_record_done.py ft_nano_record_ft2.py; do cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"; done
[ "$({ wc -l < "$SRC/ft_nano_record_ft2.py"; } 2>/dev/null || echo 999)" -le 50 ] && ok "새 파일 ≤50줄" || bad "새 파일 50줄 넘음(또는 없음)"
world

c1() {  # ① 명부 행 0 + 원장 holder = 좌석 → 세트·완료 줄 rc0 · 팀장 1통 · ft2 는 project 읽기 1회
  local w="c1$1" s="c1$1-card" n; n="$(NN "c1$1")"; fresh; card "$s"; seats; work "$s"; ft2out "접수 성공" "$w|$n|false" "x$w|$n|false"
  fin "$n" "$s" --pr 9; t "① DONE rc0" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "① 세트 줄" [ "$(nline "$s" "^- 세트: $WH · 시험: $TST · 이슈: 0$")" = 1 ]
  t "① 완료 줄" [ "$(nline "$s" "^- 완료: $n · 한 일: 도구 추가 · 산출: nano/$s@${WH:0:10} · 병합 상태: 착지 전(PR #9) · 남은 일: 없음$")" = 1 ]
  t "① 팀장 «[완료·닫기 요청]» 1통" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $n $s · ")" = 1 ]
  t "① ft2 = project 읽기 1회(루트·팀)" [ "$(cat "$FT2_LOG")" = "project --root $ROOT --team harness" ]; return $E
}
c2() {  # ② holder 다름 → REJECT · 쓰기 0
  local w="c2$1" s="c2$1-card" n c0; n="$(NN "c2$1")"; fresh; card "$s"; seats; work "$s"; ft2out "접수 성공" "$w|$(NN other)|false"; c0="$(ncommit)"
  fin "$n" "$s"; t "② REJECT rc1" [ "$RC ${OUT%% *}" = "1 REJECT" ]; t "② 사유 holder" inc "$OUT" "holder"; nowrite "②" "$c0" "$s"; return $E
}
c3() {  # ③ done: true(반환됨) → REJECT · 쓰기 0
  local w="c3$1" s="c3$1-card" n c0; n="$(NN "c3$1")"; fresh; card "$s"; seats; work "$s"; ft2out "접수 성공" "$w|$n|true"; c0="$(ncommit)"
  fin "$n" "$s"; t "③ REJECT rc1" [ "$RC ${OUT%% *}" = "1 REJECT" ]; t "③ 사유 반환" inc "$OUT" "반환"; nowrite "③" "$c0" "$s"; return $E
}
c4() {  # ④ 가짜 cli rc2 → 판정 불가 rc3 · 쓰기 0
  local w="c4$1" s="c4$1-card" n c0; n="$(NN "c4$1")"; fresh; card "$s"; seats; work "$s"; ft2out "접수 성공" "$w|$n|false"; c0="$(ncommit)"
  FT2_RC=2 fin "$n" "$s"; t "④ 판정 불가 rc3" [ "$RC ${OUT%% *}" = "3 판정" ]; t "④ 사유 rc=2" inc "$OUT" "ft2 project rc=2"; nowrite "④" "$c0" "$s"; return $E
}
c5() {  # ⑤ result = 복구 필요 → 판정 불가 rc3 · 쓰기 0
  local w="c5$1" s="c5$1-card" n c0; n="$(NN "c5$1")"; fresh; card "$s"; seats; work "$s"; ft2out "복구 필요" "$w|$n|false"; c0="$(ncommit)"
  fin "$n" "$s"; t "⑤ 판정 불가 rc3" [ "$RC ${OUT%% *}" = "3 판정" ]; t "⑤ 사유" inc "$OUT" "복구 필요"; nowrite "⑤" "$c0" "$s"; return $E
}
c6() {  # ⑥ --card 에 맞는 work 2개(<work> 와 <work>-card) → REJECT · 쓰기 0
  local w="c6$1" s="c6$1-card" n c0; n="$(NN "c6$1")"; fresh; card "$s"; seats; work "$s"; ft2out "접수 성공" "$w|$n|false" "$s|$n|false"; c0="$(ncommit)"
  fin "$n" "$s"; t "⑥ REJECT rc1" [ "$RC ${OUT%% *}" = "1 REJECT" ]; t "⑥ 사유 2개" inc "$OUT" "2개"; nowrite "⑥" "$c0" "$s"; return $E
}
c7() {  # ⑦ 명부 role=arch 행 있음 + 원장 holder = 좌석 → 지금처럼 REJECT(명부 우선 · ft2 호출 0)
  local w="c7$1" s="c7$1-card" n c0; n="$(NN "c7$1")"; fresh; card "$s"; seats "$n|arch|$s"; work "$s"; ft2out "접수 성공" "$w|$n|false"; c0="$(ncommit)"
  fin "$n" "$s"; t "⑦ REJECT rc1" [ "$RC" = 1 ]; t "⑦ 사유 = 명부 role" inc "$OUT" "REJECT done 은 명부 role=nano 좌석만 — $n"
  t "⑦ ft2 호출 0" [ ! -s "$FT2_LOG" ]; nowrite "⑦" "$c0" "$s"; return $E
}
step "반례 ①~⑦"
run "① 명부 행 0 + holder = 좌석 → DONE" c1; run "② holder 다름 → REJECT" c2; run "③ 반환됨 → REJECT" c3; run "④ cli rc2 → 판정 불가" c4
run "⑤ 복구 필요 → 판정 불가" c5; run "⑥ work 2개 → REJECT" c6; run "⑦ 명부 우선 → REJECT" c7
step "변이 M1~M3 (+원본 대조)"
if [ -f "$SRC/ft_nano_record_ft2.py" ]; then
  mutbin m1 ft_nano_record_ft2.py '"holder") != seat:   # r1868-mut:holder' '"holder") != seat and False:'; mutcase M1 c2 1
  mutbin m2 ft_nano_record_ft2.py 'w.get("done") is not False:   # r1868-mut:done' 'False:'; mutcase M2 c3 2
  mutbin m3 ft_nano_record_done.py 'if a.seat not in doc:   # r1868-mut:order' 'if True:'; mutcase M3 c7 3
else bad "변이 M1~M3 — 새 파일 없음"; fi
step "기준판 ① (팩 $BASE_SHA — 명부 role=nano 만)"
BASE="$T/base"; mkdir -p "$BASE"; cp "$SRC"/*.py "$SRC"/ft-nano-record.sh "$SRC"/ft-team-lib.sh "$SRC"/ft-nano-close-due.sh "$BASE/"
if git -C "$H" show "$BASE_SHA:./bin/ft_nano_record_done.py" > "$BASE/ft_nano_record_done.py" 2>/dev/null; then
  if o="$(BIN="$BASE"; TOOL="$BIN/ft-nano-record.sh"; c1 base)"; then bad "기준판에서 ① 이 통과함"; else ok "기준판 ① FAIL(기대 Red) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
