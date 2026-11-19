#!/usr/bin/env bash
# test_nano_record_due_ownerless_no_fetch_r2202.sh — r2202 «주인 없음» 줄만 열린 장부는 fetch 판을 열지 않는다(F1) · due 단계 표식 due-1 · fetch · due-2(F2)
#   사례 ②~⑥ (+⑥b due 손 실행 = STEP 파일 바이트 그대로) + 변이 M1·M2(변이마다 원본 대조) + 기준판 ②·⑤ Red · ① = 기존 tests/test_nano_record_*.sh 따로 재실행
#   인자 = 부분(cases 기본 | mut | base) — 시험 1개 70초 상한(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh + PATH 앞 git 감싸개(인자를 GITLOG 에 1줄 · GW_KILL_FETCH=1 이면 fetch 자리에서 부모 도구를 kill = stall-scan 상한 kill 흉내)
#   표식 순서 = python 감싸개가 Budget.mark 를 이름 1줄씩 MARKLOG 에 덧쓴다 · 실 장부·실 우편함·실 원격·네트워크 0 · sleep 0
PART="${1:-cases}"; case "$PART" in cases|mut|base) ;; *) echo "usage: $0 [cases|mut|base]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=41512ebdb2d4c7f62372f967dd0a248fd505ffdf   # 기준판 = 이 카드 전 팩 origin/main
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
REALGIT="$(command -v git)"; GW="$T/gw"; GITLOG="$T/git.log"; MARKLOG="$T/marks.log"; SF="$STATE/land-record-notify-step.txt"; mkdir -p "$GW"; export REALGIT GITLOG MARKLOG
cat > "$GW/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GITLOG"
case " $* " in *" fetch "*) [ "${GW_KILL_FETCH:-0}" != 1 ] || { kill -KILL "$PPID"; exit 137; };; esac
exec "$REALGIT" "$@"
EOF
chmod +x "$GW/git"
gx() { : > "$GITLOG"; OUT="$(cd "$T" && PATH="$GW:$PATH" timeout 7 bash "$TOOL" "$@" 2>&1)"; RC=$?; }   # gx <동사…> → OUT·RC·GITLOG (7초 상한)
mx() {  # mx <notify 인자…> — notify 1회 · 표식 이름을 MARKLOG 에 차례로(감싸개 = 시험만 · 도구 0 변경)
  : > "$GITLOG"; : > "$MARKLOG"
  OUT="$(cd "$T" && PATH="$GW:$PATH" timeout 7 python3 - "$BIN" "$@" 2>&1 <<'PY'
import os, runpy, sys
b = sys.argv[1]; sys.path.insert(0, b)
import ft_nano_record_budget as M
old = M.Budget.mark
def mark(self, step, target="-"):
    open(os.environ["MARKLOG"], "a", encoding="utf-8").write(step + "\n")
    return old(self, step, target)
M.Budget.mark = mark
sys.argv = [f"{b}/ft_nano_record_notify.py", "notify"] + sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
)"; RC=$?
}
nfetch() { grep -c ' fetch ' "$GITLOG" || true; }
dmarks() { grep -xE 'due|due-1|fetch|due-2|끝' "$MARKLOG" | tr '\n' ' ' | sed 's/ $//'; }   # due 단계 표식만(send·ring = 줄 발신 몫)
laststep() { awk 'NR==1{print $2}' "$SF" 2>/dev/null; }
cerr() {  # cerr <pr> — 착지 때 카드 ref 를 못 읽은 장부 줄(cards_err · 카드 0 · r2138 꼴)
  python3 -c 'import json,sys;n=int(sys.argv[1]);print(json.dumps({"pr":n,"repo":"p","target":"main","landed":"%040x"%n,"pr_head":"0"*40,"by":"byz-x-fix3","cards":[],"cards_err":"카드 토큰 fix3 풀이 실패","ts":"t"},ensure_ascii=False))' "$1" >> "$STATE/land-record-turn.jsonl"
}
own1() {  # own1 <stem> <PR> [<차례 stem>] — 주인 없음 카드 1(좌석 죽음) [+ 차례 카드 1(좌석 살아 있음)] · 장부 1줄
  local o="$1" pr="$2" c="${3:-}"; fresh; land "$pr"; cardf "$o"; [ -z "$c" ] || cardf "$c"; cpush
  if [ -n "$c" ]; then seats "$(NN "$o")|nano|$o" "$(NN "$c")|nano|$c"; else seats "$(NN "$o")|nano|$o"; fi
  dead "$(NN "$o")"; turn "$pr" "$o" ${c:+"$c"}
}

step "사전: 기준판 · 짝 사본 · 줄 수 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
for f in ft_nano_record_due.py ft_nano_record_budget.py ft_nano_record_fmt.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world

c2() {  # ② (F1) 주인 없음 1줄만 → due fetch 0 · 출력·rc = --no-fetch 판과 같은 바이트
  local s="c2$1" o r; own1 "$s" 21
  gx due --no-fetch; o="$OUT"; r="$RC"; t "② 주인 없음 줄" inc "$o" "주인 없음 $s "
  gx due; t "② fetch 0" [ "$(nfetch)" = 0 ]; t "② 출력 = --no-fetch" [ "$OUT" = "$o" ]; t "② rc = --no-fetch($r)" [ "$RC" = "$r" ]
  return $E
}
c3() {  # ③ (F1·F3) 주인 없음 1 + 차례 1 → fetch 1 · 두 줄 다
  local s="c3$1"; own1 "$s" 22 "${s}t"
  gx due; t "③ fetch 1" [ "$(nfetch)" = 1 ]; t "③ 주인 없음 줄" inc "$OUT" "주인 없음 $s "; t "③ 차례 줄" inc "$OUT" "차례 $(NN "${s}t") "; t "③ rc0" [ "$RC" = 0 ]
  return $E
}
c4() {  # ④ (F1) 주인 없음 1 + 카드ref불가 1 → fetch 0 · rc3
  local s="c4$1"; own1 "$s" 23; cerr 24
  gx due; t "④ fetch 0" [ "$(nfetch)" = 0 ]; t "④ 주인 없음 줄" inc "$OUT" "주인 없음 $s "; t "④ 카드 ref 줄" inc "$OUT" "판정 불가 카드 ref "; t "④ rc3" [ "$RC" = 3 ]
  return $E
}
c5() {  # ⑤ (F2) notify 를 fetch 자리에서 멈춤(부모 kill) → STEP 파일 마지막 단계 = fetch
  local s="c5$1"; own1 "$s" 25 "${s}t"; rm -f "$SF"
  GW_KILL_FETCH=1 gx notify; t "⑤ fetch 자리 도달 1" [ "$(nfetch)" = 1 ]; t "⑤ 도구 멈춤(rc≠0)" [ "$RC" != 0 ]; t "⑤ 마지막 단계 = fetch ($(laststep))" [ "$(laststep)" = fetch ]
  return $E
}
c6() {  # ⑥ (F2) 표식 순서 — fetch 0 판 = due → due-1 → 끝 · fetch 판 = due → due-1 → fetch → due-2 → 끝
  local s="c6$1"; own1 "$s" 26
  mx; t "⑥ fetch 0 판 fetch 0" [ "$(nfetch)" = 0 ]; t "⑥ fetch 0 판 순서 «$(dmarks)»" [ "$(dmarks)" = "due due-1 끝" ]
  own1 "${s}b" 27 "${s}t"
  mx; t "⑥ fetch 판 fetch 1" [ "$(nfetch)" = 1 ]; t "⑥ fetch 판 순서 «$(dmarks)»" [ "$(dmarks)" = "due due-1 fetch fetch due-2 끝" ]   # r2250 O3: URL 마다 «fetch <원격>» 표식 1줄 더(여기 URL 1)
  return $E
}
c6b() {  # ⑥b (발주 글 ②) due 손 실행(옵션 없음 · --no-fetch 둘 다) 뒤 STEP 파일 바이트 = 실행 전 그대로
  local s="c6b$1" a; own1 "$s" 28 "${s}t"; printf '1.000000 send x 경과=1 보냄=0 남음=0\n' > "$SF"; a="$(cksum < "$SF")"
  gx due; t "⑥b fetch 판이 돎(fetch 1)" [ "$(nfetch)" = 1 ]; t "⑥b 옵션 없음 뒤 STEP 그대로" [ "$(cksum < "$SF")" = "$a" ]
  gx due --no-fetch; t "⑥b --no-fetch 뒤 STEP 그대로" [ "$(cksum < "$SF")" = "$a" ]
  return $E
}
echo "부분 = $PART (세 부분 = cases · mut · base)"
if [ "$PART" = cases ]; then step "사례 ②~⑥b"
run "② 주인 없음만 fetch 0" c2; run "③ 주인 없음+차례 fetch 1" c3; run "④ 주인 없음+카드ref불가 fetch 0" c4
run "⑤ fetch 자리 멈춤 = 표식 fetch" c5; run "⑥ 표식 순서" c6; run "⑥b due 손 실행 STEP 그대로" c6b; fi
if [ "$PART" = mut ]; then step "변이 M1·M2 (+원본 대조)"
mutbin m1 ft_nano_record_due.py 'out = [r for r in out if r["k"] != "주인없음"]' 'out = [r for r in out]'; mutcase M1 c2 1
mutbin m2 ft_nano_record_due.py '        step(ctx, "fetch")
' '' ft_nano_record_batch.py '                bud.mark("fetch", name)' '                pass'; mutcase M2 c5 2; fi   # r2250 O3: fetch 자리 표식 = 단계 1 + URL 마다 1 → 둘 다 지움
if [ "$PART" = base ]; then step "기준판 ②·⑤ Red (팩 $BASE_SHA)"
for c in c2 c5; do o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; printf '%s\n' "$o" | grep '^  x ' | head -3; done; fi
finish
