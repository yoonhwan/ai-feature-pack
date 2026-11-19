#!/usr/bin/env bash
# test_nano_record_fetch_budget_fin_r2250.sh — r2250 notify fetch 예산(O1) · 묶음 실패 다시 받기 0(O2) · fetch 표식 원격 이름(O3) · 닫힌 줄 기억(O4·O5) · due 손 실행 불변(O6)
#   사례 ①~⑧ + 변이 M1~M3(변이마다 원본 대조) + 기준판 ①·②·④ Red · 인자 = 부분(cases 기본 | mut | base) — 시험 1개 70초 상한(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh(r2202 세계) + 팀 t2·t3(같은 카드 원격) + 팀 ops(둘째 원격 up) + PATH 앞 git 감싸개
#     감싸개: 인자 1줄 → GITLOG · cat-file --batch 입력 → GITLOG.in · GW_FETCH_RC(fetch 즉시 rc) · GW_SLEEP_CARD·GW_SLEEP_OPS(그 URL fetch 앞 sleep = fetch 대역 안만) · GW_KILL_ON(그 글이 든 git 자리에서 부모 kill)
#   표식 = python 감싸개가 Budget.mark 를 «<단조초> <단계> <대상>» 1줄씩 MARKLOG 에 · due 줄 = due_rows 결과 fmt 를 ROWLOG 에 · 실 장부·실 우편함·네트워크 0
PART="${1:-cases}"; case "$PART" in cases|mut|base) ;; *) echo "usage: $0 [cases|mut|base]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=c3d56acb1ffbc82cb3711ca8bfbea26b6167d7a6   # 기준판 = 이 카드 전 팩 origin/main
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
REALGIT="$(command -v git)"; GW="$T/gw"; GITLOG="$T/git.log"; MARKLOG="$T/marks.log"; ROWLOG="$T/rows.log"; SF="$STATE/land-record-notify-step.txt"; FIN="$STATE/land-record-fin.json"
mkdir -p "$GW"; export REALGIT GITLOG MARKLOG ROWLOG
cat > "$GW/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GITLOG"
[ -z "${GW_KILL_ON:-}" ] || case " $* " in *" $GW_KILL_ON "*) kill -KILL "$PPID"; exit 137;; esac
case " $* " in
  *" fetch "*) [ -z "${GW_FETCH_RC:-}" ] || exit "$GW_FETCH_RC"
    case "$*" in *card.git*) s="${GW_SLEEP_CARD:-}";; *ops.git*) s="${GW_SLEEP_OPS:-}";; *) s="";; esac
    [ -z "$s" ] || sleep "$s";;
  *" cat-file --batch "*) tee -a "$GITLOG.in" | "$REALGIT" "$@"; exit "${PIPESTATUS[1]}";;
esac
exec "$REALGIT" "$@"
EOF
chmod +x "$GW/git"
now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
gx() { : > "$GITLOG"; : > "$GITLOG.in"; OUT="$(cd "$T" && PATH="$GW:$PATH" timeout 25 bash "$TOOL" "$@" 2>&1)"; RC=$?; }   # due 손 실행 1회
mx() {  # mx [notify 인자…] — notify 1회(25초 = stall-scan 상한 대역) · MARKLOG·ROWLOG·GITLOG · SECS = 경과
  : > "$GITLOG"; : > "$GITLOG.in"; : > "$MARKLOG"; : > "$ROWLOG"; local a; a="$(now)"
  OUT="$(cd "$T" && PATH="$GW:$PATH" timeout 25 python3 - "$BIN" "$@" 2>&1 <<'PY'
import os, runpy, sys, time
b = sys.argv[1]; sys.path.insert(0, b)
import ft_nano_record_budget as M, ft_nano_record_due as D
from ft_nano_record_fmt import fmt
old, rows = M.Budget.mark, D.due_rows
def mark(self, step, target="-"):
    open(os.environ["MARKLOG"], "a", encoding="utf-8").write(f"{time.monotonic():.3f} {step} {target}\n")
    return old(self, step, target)
def due_rows(*a, **k):
    out = rows(*a, **k)
    open(os.environ["ROWLOG"], "w", encoding="utf-8").write("".join(fmt(r) + "\n" for r in out))
    return out
M.Budget.mark, D.due_rows = mark, due_rows
sys.argv = [f"{b}/ft_nano_record_notify.py", "notify"] + sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
)"; RC=$?; SECS="$(awk -v a="$a" -v b="$(now)" 'BEGIN{printf "%.2f", b - a}')"
}
nfetch() { grep -c ' fetch ' "$GITLOG" || true; }
dmarks() { awk '$2 ~ /^(due|due-1|fetch|due-2|끝)$/ {print ($2 == "fetch" && $3 != "-") ? $2 ":" $3 : $2}' "$MARKLOG" | tr '\n' ' ' | sed 's/ $//'; }
seg() { awk -v a="$1" -v b="$2" '($2 " " $3) == a {s=$1} $2 == b && s != "" {printf "%.2f", $1 - s; exit}' "$MARKLOG"; }   # seg "<단계> <대상>" <다음 단계> → 두 표식 사이 초
laststep() { awk 'NR==1{print $2}' "$SF" 2>/dev/null; }
lt() {  # lt <PR> <doc_only 0|1> <idx>:<stem>… — 장부 1줄(카드 경로 = $ROOT/<idx>/진행/<stem>.md · Q·PH = 직전 land 값)
  python3 -c 'import json,sys;a=sys.argv;d={"pr":int(a[1]),"repo":a[3],"target":"main","landed":a[4],"pr_head":a[5],"by":"","cards":[a[6]+"/"+c.split(":")[0]+"/진행/"+c.split(":")[1]+".md" for c in a[7:]],"ts":"t"}
if a[2]=="1": d["doc_only"]=True
print(json.dumps(d,ensure_ascii=False))' "$1" "$2" "$PACK" "$Q" "$PH" "$ROOT" "${@:3}" >> "$STATE/land-record-turn.jsonl"
}
cardx() { local i="$1" s="$2"; shift 2; mkdir -p "$OPS/$i/진행"; { printf '# 인덱스: %s\n\n## 상태\n- 2026-11-18 대기\n' "$s"; [ $# = 0 ] || printf '%s\n' "$@"; } > "$OPS/$i/진행/$s.md"; }   # 카드 원격(ops/base) 팀 카드 1장(올리기 = cpush)
OI="design/ops/indices"; T2="design/t2/indices"; T3="design/t3/indices"
cardo() { local s="$1"; shift; mkdir -p "$OW/$OI/진행"; { printf '# 인덱스: %s\n\n## 상태\n- 2026-11-18 대기\n' "$s"; printf '%s\n' "$@"; } > "$OW/$OI/진행/$s.md"; g "$OW" add -A; g "$OW" commit -qm c; g "$OW" push -q origin ops/base; g "$ROOT" fetch -q up; }   # 둘째 원격 카드 1장(+ ROOT remote-tracking 갱신)
rec2() { ctext "$1" > "$T/rec.md"; PYTHONPATH="$BIN" python3 -c 'import sys;from ft_nano_record import marks,rec_of,section;l,s,e=section(open(sys.argv[1],encoding="utf-8").read());print(rec_of(marks(l[s+1:e],sys.argv[2],sys.argv[3])))' "$T/rec.md" "$2" "$Q"; }   # 카드 ref 판 기록 지문(fixture recof 는 heredoc 이 파이프 입력을 덮음)
fresh2() { fresh; rm -f "$FIN" "$SF" "$COMM/mailbox.drops.log"; }
open1() { local s="$1" pr="$2"; fresh2; land "$pr"; cardf "$s"; }   # open1 <차례 stem> <PR> — 사례 머리 · 차례 카드 파일(좌석·장부 = 사례가)

step "사전: 기준판 · 짝 사본 · 줄 수 · 파일 꼴 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
for f in ft_nano_record_batch.py ft_nano_record_due.py ft_nano_record_notify.py ft_nano_record_fin.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world
for tm in t2 t3 ops; do printf '{"_master": "byz-%s-master#1", "_arch": "byz-%s-arch#1", "_cards": "design/%s/indices"}\n' "$tm" "$tm" "$tm" > "$ROOT/.fable-team/seats-$tm.json"; done
printf 't2\t.\torigin/ops/base\t%s\nt3\t.\torigin/ops/base\t%s\nops\t.\tup/ops/base\t%s\n' "$T2" "$T3" "$OI" >> "$STATE/directive-roots.tsv"
OREM="$T/ops.git"; OW="$T/opsw"; git init -q --bare -b main "$OREM"; git clone -q "$OREM" "$OW" 2>/dev/null; g "$OW" checkout -q -b ops/base 2>/dev/null
echo o > "$OW/o"; g "$OW" add -A; g "$OW" commit -qm o; g "$OW" push -q -u origin ops/base; g "$ROOT" remote add up "$OREM"; g "$ROOT" fetch -q up

c1() {  # ① (O1) 열린 줄 1 · fetch 대역 10초 → 실행 9초 안 · rc0 · remote-tracking 판 차례 · 표식 끝까지 · fetch 구간 ≤ FB(6초)+0.5
  local s="c1$1"; open1 "$s" 31; cpush; seats "$(NN "$s")|nano|$s"; lt 31 0 "$IDX:$s"
  GW_SLEEP_CARD=10 mx; t "① 9초 안($SECS)" awk -v x="$SECS" 'BEGIN{exit !(x < 9)}'; t "① rc0" [ "$RC" = 0 ]
  t "① 차례 = remote-tracking 판" inc "$(cat "$ROWLOG")" "차례 $(NN "$s") "; t "① 실패 1줄" inc "$OUT" "fetch origin 실패 rc=- — remote-tracking 판"
  t "① 표식 «$(dmarks)»" [ "$(dmarks)" = "due due-1 fetch fetch:origin due-2 끝" ]; t "① fetch 구간 $(seg "fetch origin" due-2)초 ≤ 6.5" awk -v x="$(seg "fetch origin" due-2)" 'BEGIN{exit !(x != "" && x <= 6.5)}'
  t "① 판정 불가 0" exc "$OUT" "판정 불가"
  return $E
}
c2() {  # ② (O2) 묶음 fetch rc1 · 같은 URL 팀 3 → 팀마다 다시 받기 0(fetch 1회 전부) · 판정 불가 0 · 실패 1줄
  local s="c2$1"; open1 "$s" 32; cardx "$T2" "${s}b" "$(setl)" "$(landl 32)"; cardx "$T3" "${s}c" "$(setl)" "$(landl 32)"; cpush
  seats "$(NN "$s")|nano|$s"; lt 32 0 "$IDX:$s" "$T2:${s}b" "$T3:${s}c"
  GW_FETCH_RC=1 mx; t "② fetch 1회(묶음만 · $(nfetch))" [ "$(nfetch)" = 1 ]; t "② 판정 불가 0" exc "$OUT$(cat "$ROWLOG")" "판정 불가"; t "② rc0" [ "$RC" = 0 ]
  t "② 실패 1줄" [ "$(grep -c 'fetch origin 실패 rc=1 — remote-tracking 판' <<<"$OUT")" = 1 ]; t "② 차례 판정" inc "$(cat "$ROWLOG")" "차례 $(NN "$s") "
  t "② t2 끝" inc "$(cat "$ROWLOG")" "끝 ${s}b "; t "② t3 끝" inc "$(cat "$ROWLOG")" "끝 ${s}c "
  return $E
}
c3() {  # ③ (O1·O3) URL 2 · 첫 URL fetch 대역 5.5초 → 둘째 = 상한 1초 미만 건너뜀 · 표식 fetch origin 다음 due-2 · 건너뜀 1줄
  local s="c3$1"; open1 "$s" 33; cpush; cardo "${s}o" "$(setl)" "$(landl 33)"
  seats "$(NN "$s")|nano|$s"; lt 33 0 "$IDX:$s" "$OI:${s}o"
  GW_SLEEP_CARD=5.5 mx; t "③ 표식 «$(dmarks)»" [ "$(dmarks)" = "due due-1 fetch fetch:origin due-2 끝" ]; t "③ ops.git fetch 0" exc "$(grep ' fetch ' "$GITLOG")" ops.git
  t "③ 건너뜀 1줄" inc "$OUT" "fetch up 건너뜀 — remote-tracking 판"; t "③ ops 카드 = remote-tracking 판 끝" inc "$(cat "$ROWLOG")" "끝 ${s}o "; t "③ rc0" [ "$RC" = 0 ]
  return $E
}
c4() {  # ④ (O4) notify 2회 · 주인 기록 끝 2 + 문서 PR 끝 1(팀 t2) + 열린 줄 1 → 둘째 = 세 카드 ls-tree·cat-file 0 · due 줄 바이트 같음 · fin 열쇠 3
  local s="c4$1" r1; open1 "$s" 34; cardx "$T2" "${s}a" "$(setl)" "$(landl 34)"; cardx "$T2" "${s}b" "$(setl)" "$(landl 34)"; cardx "$T2" "${s}d"; cpush
  seats "$(NN "$s")|nano|$s"; lt 34 0 "$IDX:$s" "$T2:${s}a" "$T2:${s}b"; land 35; lt 35 1 "$T2:${s}d"
  mx; r1="$(cat "$ROWLOG")"; t "④ 첫째 주인 기록 2" [ "$(grep -c '(주인 기록)' <<<"$r1")" = 2 ]; t "④ 첫째 문서 PR 1" [ "$(grep -c '(문서 PR · 구현 착지 아님)' <<<"$r1")" = 1 ]
  t "④ 첫째 세 카드 읽음" inc "$(cat "$GITLOG.in")" "${s}d.md"
  mx; t "④ 둘째 t2 ls-tree 0" exc "$(cat "$GITLOG")" "-- $T2"; t "④ 둘째 cat-file 0" exc "$(cat "$GITLOG.in")" "$T2/"
  t "④ due 줄 바이트 같음" [ "$(cat "$ROWLOG")" = "$r1" ]; t "④ fin 열쇠 3" [ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$FIN" 2>&1)" = 3 ]; t "④ rc0" [ "$RC" = 0 ]
  return $E
}
c5() {  # ⑤ (O5) 닫기 요청 #seq 끝 1 → 그 seq 를 버림 원장에 → 둘째 = 닫기 요청 밀림(기억 안 함)
  local s="c5$1" n; n="$(NN "$s")"; open1 "$s" 36; cardf "$s" "$(setl)" "$(landl 36)" "$(donel "$n")"; cpush; seats "$n|nano|$s"; lt 36 0 "$IDX:$s"
  storeset close "$n|$s|$Q" "{\"rec\": \"$(rec2 "$s" "$n")\", \"seq\": 101}"
  mx; t "⑤ 첫째 = 닫기 요청 #101 끝" inc "$(cat "$ROWLOG")" "끝 $s pr=36 착지=${Q:0:10} 좌석=$n (닫기 요청 #101)"
  printf 'ts=x seqs=101\n' > "$COMM/mailbox.drops.log"
  mx; t "⑤ 둘째 = 밀림" inc "$(cat "$ROWLOG")" "닫기 요청 밀림 $n 카드=$s "; t "⑤ fin 에 열쇠 0" exc "$(cat "$FIN" 2>/dev/null)" "|$s\""
  return $E
}
c6() {  # ⑥ (O6) due 손 실행 · fin 있음·없음 → fin 바이트 그대로(없으면 안 생김) · 줄·rc·fetch 횟수 = 기준판
  local s="c6$1" o0 r0 f0 a; open1 "$s" 37; cardx "$T2" "${s}b" "$(setl)" "$(landl 37)"; cpush; seats "$(NN "$s")|nano|$s"; lt 37 0 "$IDX:$s" "$T2:${s}b"
  ( TOOL="$BB/ft-nano-record.sh"; gx due; printf '%s\n%s\n%s' "$RC" "$(nfetch)" "$OUT" > "$T/c6base" ); r0="$(sed -n 1p "$T/c6base")"; f0="$(sed -n 2p "$T/c6base")"; o0="$(sed '1,2d' "$T/c6base")"
  gx due; t "⑥ fin 없음 = 기준판 줄" [ "$OUT" = "$o0" ]; t "⑥ rc = 기준판($r0)" [ "$RC" = "$r0" ]; t "⑥ fetch = 기준판($f0)" [ "$(nfetch)" = "$f0" ]; t "⑥ fin 안 생김" [ ! -e "$FIN" ]
  printf '{"37|%s|%sb": "주인 기록"}\n' "$Q" "$s" > "$FIN"; a="$(cksum < "$FIN")"
  gx due; t "⑥ fin 있음 = 기준판 줄" [ "$OUT" = "$o0" ]; t "⑥ rc 같음" [ "$RC" = "$r0" ]; t "⑥ fetch 같음" [ "$(nfetch)" = "$f0" ]; t "⑥ fin 바이트 그대로" [ "$(cksum < "$FIN")" = "$a" ]
  t "⑥ t2 카드 읽음(fin 안 읽음)" inc "$(cat "$GITLOG.in")" "${s}b.md"
  return $E
}
c7() {  # ⑦ fin 깨짐(JSON 아님) → 전부 판정 · rc0 · 판정 불가 0 · 판 끝에 fin 다시 씀
  local s="c7$1"; open1 "$s" 38; cardx "$T2" "${s}b" "$(setl)" "$(landl 38)"; cpush; seats "$(NN "$s")|nano|$s"; lt 38 0 "$IDX:$s" "$T2:${s}b"
  printf 'not json{\n' > "$FIN"
  mx; t "⑦ rc0" [ "$RC" = 0 ]; t "⑦ 판정 불가 0" exc "$OUT$(cat "$ROWLOG")" "판정 불가"; t "⑦ t2 카드 판정(읽음)" inc "$(cat "$GITLOG.in")" "${s}b.md"
  t "⑦ fin 다시 씀" [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$FIN" "38|$Q|${s}b" 2>&1)" = "주인 기록" ]
  return $E
}
c8() {  # ⑧ 장부 읽기 단계(due-1 앞 ls-tree)에서 부모 kill → 멎은 곳 «due» · fetch 0(fetch 예산과 무관 = 구분만)
  local s="c8$1"; open1 "$s" 39; cpush; seats "$(NN "$s")|nano|$s"; lt 39 0 "$IDX:$s"
  GW_KILL_ON=ls-tree mx; t "⑧ 도구 멈춤(rc≠0)" [ "$RC" != 0 ]; t "⑧ 멎은 곳 = due ($(laststep))" [ "$(laststep)" = due ]; t "⑧ fetch 0" [ "$(nfetch)" = 0 ]
  return $E
}
echo "부분 = $PART (세 부분 = cases · mut · base)"
if [ "$PART" = cases ]; then step "사례 ①~⑧"
run "① fetch 예산 9초 안" c1; step "①"; run "② 묶음 실패 다시 받기 0" c2; run "③ 둘째 URL 건너뜀 · 표식" c3; step "②③"
run "④ 닫힌 줄 기억" c4; run "⑤ 닫기 요청 기억 안 함" c5; run "⑥ due 손 실행 불변" c6; run "⑦ fin 깨짐" c7; run "⑧ 멎은 곳 due 구분" c8; fi
if [ "$PART" = mut ]; then step "변이 M1~M3 (+원본 대조)"
mutbin m1 ft_nano_record_batch.py 'return min(7.0, bud.b / 2 - bud.elapsed()) if bud else 7.0' 'return 7.0'; mutcase M1 c1 1; step "M1"
mutbin m2 ft_nano_record_batch.py '            if bud:   # O2' '            if False:   # O2'; mutcase M2 c2 2; step "M2"
mutbin m3 ft_nano_record_fin.py 'if v in WHY}' 'if v in WHY or v.startswith("닫기 요청")}' ft_nano_record_fin.py 'and r["why"] in WHY}' 'and (r["why"] in WHY or r["why"].startswith("닫기 요청"))}'; mutcase M3 c5 3; fi
if [ "$PART" = base ]; then step "기준판 ①·②·④ Red (팩 $BASE_SHA)"
for c in c1 c2 c4; do o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; printf '%s\n' "$o" | grep '^  x ' | head -3; step "$c"; done; fi
finish
