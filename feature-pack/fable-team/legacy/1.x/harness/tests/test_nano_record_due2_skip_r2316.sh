#!/usr/bin/env bash
# test_nano_record_due2_skip_r2316.sh — r2316 notify 가 fetch 를 건너뛴 판에서 due-2 판독 0(R1) · 예산 넘김 = fetch 갈래 진입 0(R2) · 표식 단계 초·느린 호출 칸(R3) · 그 밖 불변(R4)
#   반례 ①~⑨ + 변이 M1~M7(변이마다 원본 대조) + 기준판 Red(① ② ④ ⑤ ⑨) + ⑦ 회귀(reg1~reg3 = r2175·r2202·r2250 실패 이름 diff 0) — 시험 1개 70초 상한(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh + 주입 시계(FT_LAND_RECORD_CLOCK) + 가짜 ft_card_ref(부를 때 시계를 민다) + PATH 앞 git 감싸개(GITLOG · GW_FAIL_SUB/GW_FAIL_RC)
#     가짜 ft_card_ref = bin 사본($FB)의 ft-team-lib.sh 꼬리에 덧붙인 갈래(R2316_CLK·R2316_ON·R2316_ADD — 그 회차만 시계 +초 · sleep 0) · 표식·장부·쪽지 = 가짜(실 우편함·실 tmux·네트워크 0)
PART="${1:-cases}"; case "$PART" in cases|mut|base|reg1|reg2|reg3) ;; *) echo "usage: $0 [cases|mut|base|reg1|reg2|reg3]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=ada04488b4a55335ec2f75db4b9f86ede90b3210   # 기준판 = 이 카드 전 팩 origin/main
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
REALGIT="$(command -v git)"; GW="$T/gw"; GITLOG="$T/git.log"; MARKLOG="$T/marks.log"; ROWLOG="$T/rows.log"; DUELOG="$T/due.log"
SF="$STATE/land-record-notify-step.txt"; CLKF="$T/clock"; N="$T/cardref.n"; fb=0
mkdir -p "$GW"; export REALGIT GITLOG MARKLOG ROWLOG DUELOG STEPF="$SF"
cat > "$GW/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GITLOG"
case " $* " in
  *"cat-file --batch"*) tee -a "$GITLOG.in" | "$REALGIT" "$@"; exit "${PIPESTATUS[1]}";;
  *" fetch "*)
    if [ -n "${GW_FAIL_FIRST:-}" ] && [ ! -e "$GITLOG.first" ]; then : > "$GITLOG.first"; exit "${GW_FAIL_RC:-1}"; fi
    case "$*" in *"${GW_FAIL_SUB:-__none__}"*) exit "${GW_FAIL_RC:-1}";; esac;;
esac
exec "$REALGIT" "$@"
EOF
chmod +x "$GW/git"
fakelib() {  # fakelib <bin 사본> — ft_card_ref 를 감싸 그 회차에 주입 시계를 민다(R2316_ON 번째 호출 · R2316_ADD 초)
  cat >> "$1/ft-team-lib.sh" <<'EOF'

# r2316 시험 대역 — ft_card_ref 부를 때 주입 시계(FT_LAND_RECORD_CLOCK)를 민다 = 가짜 느린 호출
eval "$(declare -f ft_card_ref | sed '1s/^ft_card_ref/__r2316_orig_card_ref/')"
ft_card_ref() {
  local n; n=$(( $(cat "${N:?}" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$N"
  if [ -n "${R2316_CLK:-}" ] && [ "$n" = "${R2316_ON:-1}" ]; then
    awk -v a="$(cat "$R2316_CLK" 2>/dev/null || echo 0)" -v b="${R2316_ADD:-0}" 'BEGIN{printf "%.3f\n", a + b}' > "$R2316_CLK.n" && mv "$R2316_CLK.n" "$R2316_CLK"
  fi
  __r2316_orig_card_ref "$@"
}
EOF
}
FB="$T/fb"; mkdir -p "$FB"; cp "$SRC"/*.py "$SRC"/ft-nano-record.sh "$SRC"/ft-team-lib.sh "$SRC"/ft-nano-close-due.sh "$FB/"; fakelib "$FB"
MUTSRC="$FB"   # 변이 사본 = 가짜 ft_card_ref 판에서 시작(같은 대역)
pin() { [ "$BIN" = "$SRC" ] && { BIN="$FB"; TOOL="$BIN/ft-nano-record.sh"; }; return 0; }   # 사례 머리 — 변이·기준판 판은 그대로 둔다
clk() { echo "$1" > "$CLKF"; rm -f "$N"; export FT_LAND_RECORD_CLOCK="$CLKF" R2316_CLK="$CLKF" N="$T/cardref.n"; }
nobump() { unset FT_LAND_RECORD_CLOCK R2316_CLK R2316_ON R2316_ADD; rm -f "$N"; }
mp() {  # mp <동사> [인자…] — 도구를 python 으로 1회(25초 = stall-scan 상한 대역) · rows 셈(DUELOG) · 표식 줄(MARKLOG) · 판 결과(ROWLOG) · KILL_MARK = 그 단계 표식 뒤 예외
  local verb="$1"; shift
  : > "$GITLOG"; : > "$GITLOG.in"; : > "$MARKLOG"; : > "$ROWLOG"; : > "$DUELOG"; rm -f "$GITLOG.first"
  OUT="$(cd "$T" && PATH="$GW:$PATH" timeout 25 python3 - "$BIN" "$verb" "$@" 2>&1 <<'PY'
import os, runpy, sys
b, verb = sys.argv[1], sys.argv[2]; sys.path.insert(0, b)
import ft_nano_record_budget as M, ft_nano_record_due as D
from ft_nano_record_fmt import fmt
old, judge_rows = M.Budget.mark, D.rows
def mark(self, step, target="-"):
    old(self, step, target)
    line = open(os.environ["STEPF"], encoding="utf-8").read().strip() if os.path.exists(os.environ["STEPF"]) else ""
    open(os.environ["MARKLOG"], "a", encoding="utf-8").write(f"{step}|{target}\t{line}\n")
    if os.environ.get("KILL_MARK") and step == os.environ["KILL_MARK"]:
        raise SystemExit(9)   # 25초 kill 흉내 — 표식 뒤 예외
def rows(*a, **k):
    out = judge_rows(*a, **k)
    open(os.environ["DUELOG"], "a", encoding="utf-8").write("due\n")
    open(os.environ["ROWLOG"], "w", encoding="utf-8").write("".join(fmt(r) + "\n" for r in out))
    return out
M.Budget.mark, D.rows = mark, rows
if verb == "due":   # due 는 제 main 을 부른다(rows 감싸개가 그 모듈 것이라 runpy 로 다시 읽으면 감싸개 밖이 된다)
    sys.exit(D.main([verb] + sys.argv[3:]))
sys.argv = [f"{b}/ft_nano_record_{verb}.py", verb] + sys.argv[3:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
)"; RC=$?
}
mx() { mp notify "$@"; }
gx() { mp due "$@"; }   # 손 실행(due) — 같은 감싸개(rows 셈 · Budget 없음 = 표식 0)
steps() { cut -f1 "$MARKLOG" | tr '\n' ' ' | sed 's/ $//'; }
nrows() { wc -l < "$DUELOG" | tr -d ' '; }
nfetch() { grep -c ' fetch ' "$GITLOG" || true; }
nfetchx() { grep ' fetch ' "$GITLOG" | grep -c -- "$1" || true; }
ntip() { grep -c ' rev-parse --verify ' "$GITLOG" || true; }
ncat() { grep -c 'cat-file --batch' "$GITLOG" || true; }
trace() { ( cd "$T" && PYTHONPATH="$BIN" python3 -c 'import sys;from ft_nano_record_budget import stop_trace;print(stop_trace(sys.argv[1], "0"))' "$ROOT" ); }
nslow() { local v; v="$(sed -E 's/.*느린=//' <<<"$1")"; [ "$v" = "-" ] && { echo 0; return; }; tr ',' '\n' <<<"$v" | grep -c .; }
fresh2() { fresh; rm -f "$STATE/land-record-notify-step.txt" "$STATE/land-record-fin.json" "$COMM/mailbox.drops.log"; }
open1() { local s="$1" pr="$2"; fresh2; land "$pr"; cardf "$s"; }   # open1 <차례 stem> <PR> — 사례 머리 · 차례 카드 파일
lt() {  # lt <PR> <doc_only 0|1> <idx>:<stem>… — 장부 1줄(카드 = $ROOT/<idx>/진행/<stem>.md)
  python3 -c 'import json,sys;a=sys.argv;d={"pr":int(a[1]),"repo":a[3],"target":"main","landed":a[4],"pr_head":a[5],"by":"","cards":[a[6]+"/"+c.split(":")[0]+"/진행/"+c.split(":")[1]+".md" for c in a[7:]],"ts":"t"}
if a[2]=="1": d["doc_only"]=True
print(json.dumps(d,ensure_ascii=False))' "$1" "$2" "$PACK" "$Q" "$PH" "$ROOT" "${@:3}" >> "$STATE/land-record-turn.jsonl"
}
xworld() {  # 둘째 카드 리포(외부) — 카드 ref ops/base · 제 카드 루트 표
  XR="$T/xrepo"; XREM="$T/xcard.git"; git init -q --bare -b main "$XREM"; git clone -q "$XREM" "$XR" 2>/dev/null; g "$XR" checkout -q -b ops/base 2>/dev/null
  mkdir -p "$XR/.fable-team/state"; printf 'harness\t.\torigin/ops/base\t%s\n' "$IDX" > "$XR/.fable-team/state/directive-roots.tsv"
  echo x > "$XR/x"; g "$XR" add -A; g "$XR" commit -qm x; g "$XR" push -q -u origin ops/base
}
xcard() { local s="$1"; mkdir -p "$XR/$IDX/진행"; printf '# 인덱스: %s\n\n## 상태\n- 대기\n' "$s" > "$XR/$IDX/진행/$s.md"; g "$XR" add -A; g "$XR" commit -qm "x $s"; g "$XR" push -q origin ops/base; }
ltx() {  # ltx <PR> <카드 절대경로> — 장부 1줄(외부 리포 카드)
  python3 -c 'import json,sys;a=sys.argv;print(json.dumps({"pr":int(a[1]),"repo":a[2],"target":"main","landed":a[3],"pr_head":a[4],"by":"","cards":[a[5]],"ts":"t"},ensure_ascii=False))' "$1" "$PACK" "$Q" "$PH" "$2" >> "$STATE/land-record-turn.jsonl"
}

c1() {  # ① B 12 · due-1 끝 22초(첫 ft_card_ref 가 시계 +22) → R2 = fetch 진입 0 · rows 1회 · tip() 재계산 0 · 결과 = due-1 결과
  local s="c1$1" n; n="$(NN "$s")"; pin; nobump; open1 "$s" 51; cpush; seats "$n|nano|$s"; lt 51 0 "$IDX:$s"
  clk 0; export R2316_ON=1 R2316_ADD=22; mx
  t "① rc0" [ "$RC" = 0 ]; t "① rows 1회" [ "$(nrows)" = 1 ]; t "① tip() 재계산 0($(ntip)회)" [ "$(ntip)" = 1 ]; t "① fetch 0" [ "$(nfetch)" = 0 ]
  t "① 표식 «$(steps)»" inc "$(steps)" "fetch 예산 넘김|-"; t "① due-2 표식 0" exc "$(steps)" "due-2"; t "① 차례 줄 = due-1 판" inc "$(cat "$ROWLOG")" "차례 $n "
  return $E
}
c2() {  # ② B 12 · due-1 끝 5.5초(fetch_cap = min(7, 0.5) < 1) → 같은 갈래(R2) · rows 1회 · tip 재계산 0
  local s="c2$1" n; n="$(NN "$s")"; pin; nobump; open1 "$s" 52; cpush; seats "$n|nano|$s"; lt 52 0 "$IDX:$s"
  clk 0; export R2316_ON=1 R2316_ADD=5.5; mx
  t "② rc0" [ "$RC" = 0 ]; t "② rows 1회" [ "$(nrows)" = 1 ]; t "② tip() 재계산 0($(ntip)회)" [ "$(ntip)" = 1 ]; t "② fetch 0" [ "$(nfetch)" = 0 ]
  t "② 표식 «$(steps)»" inc "$(steps)" "fetch 예산 넘김|-"; t "② 차례 줄" inc "$(cat "$ROWLOG")" "차례 $n "
  return $E
}
c3() {  # ③ 시계 1초 · 가짜 fetch 성공 → due-2 판독 1회 그대로 · 결과 = 원격 끝 판(옛 remote-tracking 판에는 카드 없음)
  local s="c3$1" n old; n="$(NN "$s")"; pin; nobump; open1 "$s" 53; seats "$n|nano|$s"; lt 53 0 "$IDX:$s"
  old="$(g "$ROOT" rev-parse origin/ops/base)"; cpush; g "$ROOT" update-ref refs/remotes/origin/ops/base "$old"
  clk 1; mx
  t "③ rc0" [ "$RC" = 0 ]; t "③ rows 2회($(nrows))" [ "$(nrows)" = 2 ]; t "③ fetch 1회($(nfetch))" [ "$(nfetch)" = 1 ]
  t "③ 표식 «$(steps)»" inc "$(steps)" "due-2|-"; t "③ 생략 0" exc "$(steps)" "생략"
  t "③ 결과 = fetch 판(차례 $n)" inc "$(cat "$ROWLOG")" "차례 $n "; t "③ 판정 불가 0" exc "$OUT$(cat "$ROWLOG")" "판정 불가"
  return $E
}
c4() {  # ④ 가짜 fetch rc1(실패) · 시간 남음 → R1 = due-2 생략 · 표식 «시도=1 받음=0» · 실패 줄 그대로
  local s="c4$1" n; n="$(NN "$s")"; pin; nobump; open1 "$s" 54; cpush; seats "$n|nano|$s"; lt 54 0 "$IDX:$s"
  clk 0; GW_FAIL_SUB="$CREM" GW_FAIL_RC=1 mx
  t "④ rc0" [ "$RC" = 0 ]; t "④ rows 1회($(nrows))" [ "$(nrows)" = 1 ]; t "④ 표식 «$(steps)»" inc "$(steps)" "due-2 생략 묶음=1 시도=1 받음=0|-"
  t "④ due-2 표식 0" exc "$(steps)" "|due-2"; t "④ 실패 1줄 그대로" [ "$(grep -c 'fetch origin 실패 rc=1 — remote-tracking 판' <<<"$OUT")" = 1 ]
  t "④ 결과 = due-1 판(차례 $n)" inc "$(cat "$ROWLOG")" "차례 $n "
  return $E
}
c5() {  # ⑤ 끝·중간 표식마다 «단계=»·«느린=» 칸 · 느린 3개 이하 · 최악 폭(경과 999.5 · 남음 99)에서 stop_trace 120자 안에 단계 칸 전부
  local s="c5$1" n o; n="$(NN "$s")"; pin; nobump; open1 "$s" 55; cpush; seats "$n|nano|$s"; lt 55 0 "$IDX:$s"
  clk 0; mx
  t "⑤ 표식 3개 이상($(steps))" awk -v n="$(wc -l < "$MARKLOG")" 'BEGIN{exit !(n >= 4)}'
  t "⑤ 모든 표식에 단계= 칸" [ "$(grep -c ' 단계=' "$MARKLOG")" = "$(wc -l < "$MARKLOG" | tr -d ' ')" ]
  t "⑤ 모든 표식에 느린= 칸" [ "$(grep -c ' 느린=' "$MARKLOG")" = "$(wc -l < "$MARKLOG" | tr -d ' ')" ]
  o="$(tail -n 1 "$MARKLOG" | cut -f2)"
  t "⑤ 끝 표식 단계 = d1·f·d2" [ "$(sed -E 's/.*단계=([^ ]*).*/\1/' <<<"$o" | tr ',' '\n' | sed -E 's/:.*//' | tr '\n' ',')" = "d1,f,d2," ]
  t "⑤ 느린 3개 이하($(nslow "$o"))" awk -v n="$(nslow "$o")" 'BEGIN{exit !(n <= 3)}'
  o="$( cd "$T" && PYTHONPATH="$BIN" python3 - "$ROOT" "$CLKF" <<'PY'
import os, sys
from pathlib import Path
import ft_nano_record_call as C
from ft_nano_record_budget import Budget, stop_trace
C.CALLS[:] = [("ft_card_ref", 9.5), ("git merge-base", 7.25), ("git rev-parse", 3.5), ("mbox.sh", 1.0)]
Path(sys.argv[2]).write_text("999.5\n", encoding="utf-8")
os.environ["FT_LAND_RECORD_CLOCK"] = sys.argv[2]
b = Budget(sys.argv[1]); b.left = 99
for nm in ("due-1", "fetch", "due-2"):
    b.stage(nm)
b.mark("due-2 생략 묶음=905 시도=905 받음=0")
print(stop_trace(sys.argv[1], "0"))
PY
)"
  t "⑤ 최악 폭 120자 안에 단계 칸(${#o}자)" inc "$o" "단계=d1:999.5,f:999.5,d2:999.5"; t "⑤ 최악 폭 느린 첫 칸" inc "$o" "느린=ft_card_ref:9.5"
  return $E
}
c6() {  # ⑥ due 손 실행(Budget 없음 · 열린 줄 1 · 묶음 fetch 만 실패 = 받은 것 0) → 판독 2회 그대로 · 표식 파일 쓰기 0
  local s="c6$1" n; n="$(NN "$s")"; pin; nobump; open1 "$s" 56; cpush; seats "$n|nano|$s"; lt 56 0 "$IDX:$s"
  rm -f "$SF"; GW_FAIL_FIRST=1 GW_FAIL_RC=1 gx
  t "⑥ rc0" [ "$RC" = 0 ]; t "⑥ 판독(rows) 2회($(nrows))" [ "$(nrows)" = 2 ]; t "⑥ 묶음 1 + 팀마다 1 = fetch 2회($(nfetch))" [ "$(nfetch)" = 2 ]
  t "⑥ 표식 파일 0" [ ! -e "$SF" ]; t "⑥ 차례 줄" [ "$(grep -c "차례 $n " <<<"$OUT")" = 1 ]; t "⑥ 생략 줄 0" exc "$OUT" "생략"
  return $E
}
c8() {  # ⑧ 외부 리포 카드 → R1 적용 0(외부 sub tip fetch 그대로) / 같은 입력 due-1 22초 → R2 = 외부 fetch 0
  local s="c8$1" n; n="$(NN "$s")"; pin; nobump; fresh2; land 58; xworld; xcard "$s"
  export FT_SEATS_JSON="$ROOT/.fable-team/seats-harness.json"
  seats "$n|nano|$s"; ltx 58 "$XR/$IDX/진행/$s.md"
  clk 0; GW_FAIL_SUB="$CREM" GW_FAIL_RC=1 mx
  t "⑧a rc0" [ "$RC" = 0 ]; t "⑧a rows 2회($(nrows))" [ "$(nrows)" = 2 ]; t "⑧a due-2 표식 «$(steps)»" inc "$(steps)" "due-2|-"
  t "⑧a 생략 0" exc "$(steps)" "생략"; t "⑧a 외부 fetch 1회($(nfetchx xcard.git))" [ "$(nfetchx xcard.git)" = 1 ]
  clk 0; export R2316_ON=1 R2316_ADD=22; GW_FAIL_SUB="$CREM" GW_FAIL_RC=1 mx
  t "⑧b 표식 «$(steps)»" inc "$(steps)" "fetch 예산 넘김|-"; t "⑧b rows 1회($(nrows))" [ "$(nrows)" = 1 ]
  t "⑧b fetch 0(외부 0 · $(nfetch))" [ "$(nfetch)" = 0 ]
  unset FT_SEATS_JSON
  return $E
}
c9() {  # ⑨ 가짜 느린 호출(due-2 의 ft_card_ref 가 시계 +9) 뒤 due-2 표식에서 kill → stop_trace 줄에 «단계=d1:»·«느린=ft_card_ref:9»
  local s="c9$1" n o; n="$(NN "$s")"; pin; nobump; open1 "$s" 59; cpush; seats "$n|nano|$s"; lt 59 0 "$IDX:$s"
  clk 0; export FT_LAND_RECORD_BUDGET_S=30 R2316_ON=2 R2316_ADD=9 KILL_MARK="due-2"; mx
  t "⑨ 도구 멈춤(rc=9)" [ "$RC" = 9 ]; t "⑨ 마지막 표식 = due-2($(steps))" [ "$(tr ' ' '\n' <<<"$(steps)" | tail -n 1)" = "due-2|-" ]; o="$(trace)"
  t "⑨ 표식 줄에 단계=d1: ($o)" inc "$o" "단계=d1:"; t "⑨ 표식 줄에 느린=ft_card_ref:9" inc "$o" "느린=ft_card_ref:9"
  return $E
}

step "사전: 기준판 · 짝 사본 · 줄 수 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
BFB="$T/base/fb"; mkdir -p "$BFB"; cp "$BB"/* "$BFB"/ 2>/dev/null; fakelib "$BFB"
for f in ft_nano_record_due.py ft_nano_record_batch.py ft_nano_record_budget.py ft_nano_record.py ft_nano_record_call.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world
echo "부분 = $PART"
if [ "$PART" = cases ]; then step "사례 ①~⑥·⑧·⑨"
run "① 22초 = fetch 진입 0" c1; run "② 5.5초 = fetch 진입 0" c2; run "③ fetch 성공 = due-2 그대로" c3; step "①②③"
run "④ fetch 실패 = due-2 생략" c4; run "⑤ 표식 단계·느린 칸" c5; run "⑥ due 손 실행 불변" c6; step "④⑤⑥"
run "⑧ 외부 리포 카드 = R1 0" c8; run "⑨ due-2 표식 뒤 kill" c9; fi
if [ "$PART" = mut ]; then step "변이 M1~M7 (+원본 대조)"
mutbin m1 ft_nano_record_due.py 'if bud and ctx._fetchn[2] == 0 and not shared(ctx)["ext"]:' 'if False:'; mutcase M1 c4 1; step "M1"
mutbin m2 ft_nano_record_due.py 'if bud and fetch_cap(bud) < 1:' 'if bud and bud.elapsed() >= bud.b:'; mutcase M2 c2 2; step "M2"
mutbin m3 ft_nano_record_due.py 'if bud and ctx._fetchn[2] == 0 and not shared(ctx)["ext"]:' 'if bud:'; mutcase M3 c3 3; step "M3"
mutbin m4 ft_nano_record_budget.py '단계={cells} 느린={slow()}' '단계=- 느린=-'; mutcase M4 c5 4; step "M4"
mutbin m5 ft_nano_record_due.py 'if bud and ctx._fetchn[2] == 0 and not shared(ctx)["ext"]:' 'if ctx._fetchn[2] == 0 and not shared(ctx)["ext"]:'; mutcase M5 c6 5; step "M5"
mutbin m6 ft_nano_record_budget.py 'f"단계={cells} 느린={slow()}\n"' "f\"단계={cells if step == '끝' else '-'} 느린={slow()}\\n\""; mutcase M6 c9 6; step "M6"
mutbin m7 ft_nano_record_due.py ' and not shared(ctx)["ext"]:' ':'; mutcase M7 c8 7; fi
if [ "$PART" = base ]; then step "기준판 ①·②·④·⑤·⑨ Red (팩 $BASE_SHA)"
for c in c1 c2 c4 c5 c9; do o="$( ( BIN="$BFB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; printf '%s\n' "$o" | grep '^  x ' | head -2; step "$c"; done; fi
if [ "$PART" = reg1 ] || [ "$PART" = reg2 ] || [ "$PART" = reg3 ]; then
  case "$PART" in reg1) f=test_nano_record_budget_r2175.sh;; reg2) f=test_nano_record_due_ownerless_no_fetch_r2202.sh;; reg3) f=test_nano_record_fetch_budget_fin_r2250.sh;; esac
  step "⑦ 회귀 $f — 이 판 vs 기준판 실패 이름"
  names() { grep '^FAIL ' | sed 's/ ::.*//' | sort; }
  now="$( ( cd "$HERE" && R2175_NO_MUT=1 R1717_BIN="$SRC" timeout 70 bash "$f" cases 2>&1 ) | names )"
  bas="$( ( cd "$HERE" && R2175_NO_MUT=1 R1717_BIN="$BB" timeout 70 bash "$f" cases 2>&1 ) | names )"
  [ "$now" = "$bas" ] && ok "⑦ $f 실패 이름 diff 0(이 판 $(grep -c . <<<"$now" || true)건)" || bad "⑦ $f 실패 이름 다름" "$(diff <(printf '%s\n' "$bas") <(printf '%s\n' "$now"))"
fi
finish
