#!/usr/bin/env bash
# test_nano_record_due_open_rows_r2071.sh — r2071 due·notify 의 카드 읽기 묶음(A2) · 같은 원격 fetch 묶음(A3) · 다시 보는 판 = 전 항목 그대로(A1) · 실패 = 판정 불가(A4) · 불변(A5)
#   사례 ①~⑦ + ⑧ 일부(done 1회의 fetch·cat-file 수 · kit cmp · 줄 수) + 변이 M1~M4(변이마다 원본 대조) + 기준판 ④·⑤ Red · ①·③ Green
#   ⑧ 나머지 = 기존 tests/test_nano_record_*.sh 를 따로 돌린다 · 인자 = 부분(cases 기본 | mut | base) — 시험 1개 70초 상한이라 세 번 부른다(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh + 팀 여럿(임시 directive-roots.tsv · seats-<팀>.json) + 원격 둘째 사본(C2 · ROOT 의 remote-tracking 은 그대로)
#     + PATH 앞 git 감싸개(인자를 GITLOG 에 1줄 · 진짜 git 을 부른다 · 주입 GW_BATCH_RC · GW_FIFO · GW_FETCH_RC) · 실 장부·실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0
PART="${1:-cases}"; case "$PART" in cases|mut|base) ;; *) echo "usage: $0 [cases|mut|base]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=92c2dac2ae1606124bbf8f7746194c70b5ef95b6   # 기준판 = 이 카드 전 팩 origin/main
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
REALGIT="$(command -v git)"; GW="$T/gw"; GITLOG="$T/git.log"; C2="$T/c2"; OREM="$T/other.git"; mkdir -p "$GW"; export REALGIT GITLOG
cat > "$GW/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GITLOG"
case " $* " in
  *" cat-file --batch "*) [ -z "${GW_BATCH_RC:-}" ] || exit "$GW_BATCH_RC"; [ -z "${GW_FIFO:-}" ] || read -r _ < "$GW_FIFO";;
  *" fetch "*) [ -z "${GW_FETCH_RC:-}" ] || { echo "fatal: 주입" >&2; exit "$GW_FETCH_RC"; };;
esac
exec "$REALGIT" "$@"
EOF
chmod +x "$GW/git"
gx() { : > "$GITLOG"; local tool="$1"; shift; OUT="$(cd "$T" && PATH="$GW:$PATH" bash "$tool" "$@" 2>&1)"; RC=$?; }   # gx <도구> <동사…> — 감싸개 아래 1회 → OUT·RC·GITLOG
BT() { printf '%s/ft-nano-record.sh' "$BB"; }   # 기준판 도구
nfetch() { grep -c ' fetch ' "$GITLOG" || true; }; ncat() { grep -c ' cat-file ' "$GITLOG" || true; }; ngit() { grep -c . "$GITLOG" || true; }
nref() { g "$ROOT" for-each-ref refs/ft-record | grep -c . || true; }
nreset() { rm -rf "$STATE/land-record-notified.json" "$STATE/seat-record"; : > "$MBOX_LOG"; : > "$NC_LOG"; : > "$CRIT_LOG"; }
mbody() { grep -v '^FAIL' "$MBOX_LOG" | cut -f2- | sed "s#$BB/#$BIN/#g"; }   # 받는 이·보낸 이·본문(본문의 도구 경로 = 기준판 사본 경로를 시험 bin 으로 맞춤)
roots() {  # roots <팀|ref|indices 뿌리>… — 카드 루트 표를 그 행들로 다시 쓰고 harness 밖 팀 명부(_master 만)를 둔다
  : > "$STATE/directive-roots.tsv"; local r tm
  for r in "$@"; do tm="${r%%|*}"; r="${r#*|}"; printf '%s\t.\t%s\t%s\n' "$tm" "${r%%|*}" "${r#*|}" >> "$STATE/directive-roots.tsv"
    [ "$tm" = harness ] || printf '{"_master": "byz-%s-master-pi#1", "_cards": "%s"}' "$tm" "${r#*|}" > "$ROOT/.fable-team/seats-$tm.json"; done
}
HR="harness|origin/ops/base|$IDX"; PIDX="design/teams/planner/indices"; PR_="planner|origin/ops/base|$PIDX"; FIDX="design/teams/cfo/indices"; FR="cfo|origin/main|$FIDX"
ent() {  # ent <pr> <doc_only 0|1> [<ROOT 기준 카드 경로>…] — 장부 1줄(가짜 착지 sha = pr 의 40자 hex · by 없음)
  python3 -c 'import json,sys;a=sys.argv;print(json.dumps({"pr":int(a[1]),"repo":"p","target":"main","landed":"%040x"%int(a[1]),"pr_head":"0"*40,"by":"","cards":[a[3]+"/"+c for c in a[4:]],"doc_only":a[2]=="1","ts":"t"},ensure_ascii=False))' "$1" "$2" "$ROOT" "${@:3}" >> "$STATE/land-record-turn.jsonl"
}
cf() { mkdir -p "$1/$2/진행"; printf '# 인덱스: %s\n\n## 상태\n- 2026-11-12 대기\n' "$3" > "$1/$2/진행/$3.md"; }   # cf <작업 트리> <indices 뿌리> <stem> — 기록 없는 카드 1장(올리기 별도)
opsh() { (cd "$OPS" && git add -A && git commit -qm c && git pull -q --rebase origin ops/base 2>/dev/null; git push -q origin ops/base); }
mainc() { cf "$ROOT" "$FIDX" "$1"; g "$ROOT" add "$FIDX"; g "$ROOT" commit -qm c; g "$ROOT" push -q origin main; }   # cfo 카드 = main 가지
c2card() { g "$C2" fetch -q origin; g "$C2" checkout -q -B ops/base origin/ops/base; OPS="$C2" cardf "$@"; g "$C2" add -A; g "$C2" commit -qm c2; g "$C2" push -q origin ops/base; }   # 원격 끝만 바꿈
open1() { cf "$OPS" "$IDX" "$1"; seats "$(NN "$1")|nano|$1"; }   # 열린 줄(차례) 1장 — 기록 없는 harness 카드 + 산 나노(올리기·장부 별도)

step "사전: 기준판 · 짝 사본 · 줄 수 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
for f in ft_nano_record.py ft_nano_record_due.py ft_nano_record_batch.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$({ wc -l < "$SRC/$f"; } 2>/dev/null || echo 999)" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음(또는 없음) $f"
done
world; git clone -q "$CREM" "$C2" 2>/dev/null
git init -q --bare -b cards "$OREM"; git clone -q "$OREM" "$T/oc" 2>/dev/null; g "$T/oc" checkout -q -b cards 2>/dev/null
cf "$T/oc" design/teams/ext/indices e1; g "$T/oc" add -A; g "$T/oc" commit -qm c; g "$T/oc" push -q origin cards; g "$ROOT" remote add other "$OREM"; g "$ROOT" fetch -q other

c1() {  # ① (A1 · 사전 DA R1) local 판 «끝(남은 일)» → 원격 판 남은 일 없음 = «닫기 요청 밀림» · r2 차례 · 출력·쪽지 = 기준판
  local a="c1a$1" b="c1b$1" na nb o m1; na="$(NN "$a")"; nb="$(NN "$b")"; fresh; roots "$HR"; land 41
  card "$a" "$(setl)" "$(landl 41)" "$(donel "$na" "남은 일: 추가 작업")"; card "$b"; seats "$na|nano|$a" "$nb|nano|$b"; turn 41 "$a" "$b"
  c2card "$a" "$(setl)" "$(landl 41)" "$(donel "$na" "남은 일: 없음")"
  gx "$TOOL" due --no-fetch; t "① --no-fetch 끝 r1(남은 일)" inc "$OUT" "끝 $a pr=41 착지=${Q:0:10} 좌석=$na (남은 일 — 닫기 요청 0)"
  t "① --no-fetch 차례 r2" inc "$OUT" "차례 $nb 종류=닫기 빠짐=ⓢⓛⓒ 카드=$b"; t "① --no-fetch fetch 0" [ "$(nfetch)" = 0 ]; o="$OUT"
  gx "$(BT)" due --no-fetch; t "① --no-fetch = 기준판" [ "$OUT" = "$o" ]
  gx "$TOOL" due; t "① fetch 켬 = 닫기 요청 밀림 r1" inc "$OUT" "닫기 요청 밀림 $na 카드=$a pr=41"; t "① fetch 켬 차례 r2" inc "$OUT" "차례 $nb"; t "① rc0" [ "$RC" = 0 ]; o="$OUT"
  gx "$(BT)" due; t "① fetch 켬 = 기준판" [ "$OUT" = "$o" ]
  nreset; gx "$TOOL" notify; m1="$(mbody)"; t "① notify 쪽지 있음" [ -n "$m1" ]; nreset; gx "$(BT)" notify; t "① notify 쪽지 = 기준판" [ "$(mbody)" = "$m1" ]
  return $E
}
c2() {  # ② (A1) 열린 줄 0 → fetch 0 · 판 1회(ls-tree 1) · 출력 = 기준판 / --no-fetch → fetch 0
  local s="c2$1" o; fresh; roots "$HR"; cf "$OPS" "$IDX" "${s}x"; cf "$OPS" "$IDX" "${s}y"; opsh; seats; ent 51 1 "$IDX/진행/${s}x.md"; ent 52 1 "$IDX/진행/${s}y.md"
  gx "$TOOL" due; t "② 전부 끝" [ "$(printf '%s\n' "$OUT" | grep -c '^끝 ')" = 2 ]; t "② fetch 0" [ "$(nfetch)" = 0 ]; t "② 판 1회(ls-tree 1)" [ "$(grep -c ' ls-tree ' "$GITLOG")" = 1 ]; o="$OUT"
  gx "$(BT)" due; t "② = 기준판" [ "$OUT" = "$o" ]; gx "$TOOL" due --no-fetch; t "② --no-fetch fetch 0" [ "$(nfetch)" = 0 ]
  return $E
}
c3() {  # ③ (A1 · A2 · 사전 DA R2) ⓐ cards=[] = 두 판 모두 «카드 없음» · 그 항목 git 0 ⓑ 경로 있음 · local 없음 · 원격 있음 = --no-fetch 판정 불가 / fetch 켬 = 원격 판(기준판)
  local s="c3$1" n1 o; fresh; roots "$HR"; open1 "${s}o"; opsh; ent 61 0 "$IDX/진행/${s}o.md"
  gx "$TOOL" due; n1="$(ngit)"; ent 62 0; c2card "${s}r"
  gx "$TOOL" due --no-fetch; t "③ⓐ --no-fetch 카드 없음" inc "$OUT" "카드 없음 PR #62 담당=- 착지="
  gx "$TOOL" due; t "③ⓐ fetch 켬 카드 없음" inc "$OUT" "카드 없음 PR #62 담당=- 착지="; t "③ⓐ 그 항목 git 0" [ "$(ngit)" = "$n1" ]
  : > "$STATE/land-record-turn.jsonl"; ent 61 0 "$IDX/진행/${s}o.md"; ent 63 0 "$IDX/진행/${s}r.md"
  gx "$TOOL" due --no-fetch; t "③ⓑ --no-fetch 판정 불가" inc "$OUT" "판정 불가 ${s}r 카드 ref 에 카드 없음(origin/ops/base) rc=1"; t "③ⓑ --no-fetch rc3" [ "$RC" = 3 ]; o="$OUT"
  gx "$(BT)" due --no-fetch; t "③ⓑ --no-fetch = 기준판" [ "$OUT" = "$o" ]
  gx "$TOOL" due; t "③ⓑ fetch 켬 = 원격 판(판정 불가 아님)" exc "$OUT" "판정 불가"; t "③ⓑ 원격 판 줄" inc "$OUT" "주인 없음 ${s}r"; o="$OUT"
  gx "$(BT)" due; t "③ⓑ fetch 켬 = 기준판" [ "$OUT" = "$o" ]
  return $E
}
bulk() {  # bulk <n> <꼬리표> → 한 팀 · 카드 있는 «끝» n항목 + 차례 1 · due(fetch 켬 = 두 판) 1회의 git 호출 수
  local i s="c4$2n$1"; fresh; roots "$HR"; open1 "${s}o"; for ((i = 0; i < $1; i++)); do cf "$OPS" "$IDX" "${s}k$i"; done; opsh
  python3 - "$STATE/land-record-turn.jsonl" "$ROOT/$IDX/진행" "$s" "$1" <<'PY'
import json, sys
p, d, s, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
with open(p, "a", encoding="utf-8") as fh:
    for i in range(n):
        fh.write(json.dumps({"pr": 1000 + i, "landed": "%040x" % (1000 + i), "by": "", "cards": [f"{d}/{s}k{i}.md"], "doc_only": True}) + "\n")
    fh.write(json.dumps({"pr": 999, "landed": "%040x" % 999, "by": "", "cards": [f"{d}/{s}o.md"]}) + "\n")
PY
  gx "$TOOL" due; [ "$(printf '%s\n' "$OUT" | grep -c '^끝 ')" = "$1" ] && inc "$OUT" "차례 " && echo "$(ngit) $(nfetch) ok" || echo "$(ngit) $(nfetch) bad"
}
c4() {  # ④ (A2) 30항목과 300항목의 git 호출 수 차이 2회 안
  local a b; a="$(bulk 30 "$1")"; b="$(bulk 300 "$1")"; echo "  ④ git 호출·fetch 30=«$a» 300=«$b»" | tee "$T/c4-$1"
  t "④ 출력 꼴(끝 n · 차례 1)" [ "${a##* }${b##* }" = okok ]; t "④ 차이 2회 안" [ $(( ${b%% *} - ${a%% *} )) -le 2 ]
  return $E
}
c5() {  # ⑤ (A3) 같은 URL 팀 3 · 카드 가지 2 → fetch 1 · 출력 = 기준판 · 개인 ref 0 / 다른 URL 팀 1 → fetch 2 / 같은 URL 팀 2 중 가지 없음(사전 DA R3) → fetch 3 · rc3
  local s="c5$1" o; fresh; roots "$HR" "$PR_" "$FR"; open1 "${s}o"; cf "$OPS" "$PIDX" "${s}p"; opsh; mainc "${s}f"
  ent 71 0 "$IDX/진행/${s}o.md"; python3 - "$STATE/land-record-turn.jsonl" "$ROOT" "$PIDX/진행/${s}p.md" "$FIDX/진행/${s}f.md" <<'PY'
import json, sys
p, r, a, b = sys.argv[1:5]
with open(p, "a", encoding="utf-8") as fh:
    for n, c in ((72, a), (73, b)):
        fh.write(json.dumps({"pr": n, "landed": "%040x" % n, "by": "", "cards": [f"{r}/{c}"], "doc_only": True}) + "\n")
PY
  gx "$TOOL" due; t "⑤ fetch 1" [ "$(nfetch)" = 1 ]; t "⑤ 끝 2 · 차례 1" [ "$(printf '%s\n' "$OUT" | grep -c '^끝 ') $(printf '%s\n' "$OUT" | grep -c '^차례 ')" = "2 1" ]; t "⑤ 개인 ref 0" [ "$(nref)" = 0 ]; o="$OUT"
  gx "$(BT)" due; t "⑤ = 기준판" [ "$OUT" = "$o" ]; echo "  ⑤ fetch 기준판 $(nfetch)"
  roots "$HR" "$PR_" "$FR" "ext|other/cards|design/teams/ext/indices"; ent 74 1 design/teams/ext/indices/진행/e1.md
  gx "$TOOL" due; t "⑤ 다른 URL → fetch 2" [ "$(nfetch)" = 2 ]; t "⑤ ext 끝" inc "$OUT" "끝 e1 pr=74"; t "⑤ 개인 ref 0 (2)" [ "$(nref)" = 0 ]; o="$OUT"
  gx "$(BT)" due; t "⑤ 다른 URL = 기준판" [ "$OUT" = "$o" ]
  g "$C2" checkout -q -B gone origin/main; cf "$C2" design/teams/gone/indices "${s}g"; g "$C2" add -A; g "$C2" commit -qm g; g "$C2" push -q origin gone
  g "$ROOT" fetch -q origin; g "$C2" push -q origin :gone   # ROOT remote-tracking origin/gone 은 남고 원격 가지는 없음
  : > "$STATE/land-record-turn.jsonl"; roots "$HR" "gone|origin/gone|design/teams/gone/indices"; ent 71 0 "$IDX/진행/${s}o.md"; ent 75 1 "design/teams/gone/indices/진행/${s}g.md"
  gx "$TOOL" due; t "⑤ 가지 없음 → fetch 3(묶음 1 + 팀마다 2)" [ "$(nfetch)" = 3 ]; t "⑤ 가지 있는 팀 = 정상 판정" inc "$OUT" "차례 $(NN "${s}o")"
  t "⑤ 가지 없는 팀 = 판정 불가 fetch" inc "$OUT" "판정 불가 ${s}g 카드 ref fetch origin/gone rc=128"; t "⑤ rc3" [ "$RC" = 3 ]; t "⑤ 개인 ref 0 (3)" [ "$(nref)" = 0 ]; o="$OUT"
  gx "$(BT)" due; t "⑤ 가지 없음 = 기준판" [ "$OUT" = "$o" ]
  return $E
}
c6() {  # ⑥ (A4) 묶음 읽기 rc1 → 그 카드들 판정 불가 rc=1 · rc3 · 쪽지 0 / fifo 멈춤 → 7+2초 안 판정 불가 / 모든 fetch rc128 → 기준판과 같은 판정 불가
  local s="c6$1" o t0; fresh; roots "$HR" "$PR_"; open1 "${s}o"; cf "$OPS" "$IDX" "${s}k"; cf "$OPS" "$PIDX" "${s}p"; opsh; ent 81 0 "$IDX/진행/${s}o.md"; ent 82 1 "$IDX/진행/${s}k.md"; ent 83 1 "$PIDX/진행/${s}p.md"
  GW_BATCH_RC=1 gx "$TOOL" due; t "⑥ 묶음 rc1 = 판정 불가 rc=1" [ "$(printf '%s\n' "$OUT" | grep -c "^판정 불가 ${s}[okp] git cat-file 카드 rc=1$")" = 3 ]; t "⑥ rc3" [ "$RC" = 3 ]
  nreset; GW_BATCH_RC=1 gx "$TOOL" notify; t "⑥ notify rc3" [ "$RC" = 3 ]; t "⑥ 쪽지 0" [ "$(nmsg .)" = 0 ]
  mkfifo "$T/fifo-$1"; t0="$(date +%s)"; GW_FIFO="$T/fifo-$1" gx "$TOOL" due --no-fetch
  t "⑥ fifo 멈춤 = 9초 안" [ $(( $(date +%s) - t0 )) -le 9 ]; t "⑥ fifo = 판정 불가 rc=-" inc "$OUT" "판정 불가 ${s}o git cat-file 카드 rc=-"; t "⑥ fifo rc3" [ "$RC" = 3 ]
  GW_FETCH_RC=128 gx "$TOOL" due; t "⑥ fetch 전부 rc128 = 팀마다 판정 불가" [ "$(printf '%s\n' "$OUT" | grep -c "^판정 불가 ${s}[okp] 카드 ref fetch origin/ops/base rc=128$")" = 3 ]; t "⑥ fetch rc3" [ "$RC" = 3 ]; o="$OUT"
  GW_FETCH_RC=128 gx "$(BT)" due; t "⑥ fetch 실패 = 기준판" [ "$OUT" = "$o" ]
  return $E
}
c7() {  # ⑦ (A5) 열린 줄 1(차례) → 쪽지 1통 · 보낸 기록 1줄 · 본문 = 기준판 / 같은 열쇠 다시 → 0통
  local s="c7$1" n m1; n="$(NN "${s}o")"; fresh; roots "$HR"; open1 "${s}o"; opsh; ent 91 0 "$IDX/진행/${s}o.md"
  nreset; gx "$TOOL" notify; t "⑦ 1통" [ "$(nto "$n")" = 1 ]; t "⑦ 보낸 기록 1줄" [ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["sent"]))' "$STATE/land-record-notified.json")" = 1 ]; m1="$(mbody)"
  gx "$TOOL" notify; t "⑦ 다시 = 0통" [ "$(nto "$n")" = 1 ]
  nreset; gx "$(BT)" notify; t "⑦ 본문 = 기준판" [ "$(mbody)" = "$m1" ]
  return $E
}
c8() {  # ⑧ (A5) done 1회의 git fetch 수 · cat-file 수 = 기준판
  local s="c8$1" a; work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; }; fresh; roots "$HR"; card "${s}a"; card "${s}b"; seats "$(NN "${s}a")|nano|${s}a" "$(NN "${s}b")|nano|${s}b"
  work "${s}a"; gx "$TOOL" done --seat "$(NN "${s}a")" --card "${s}a" --did x --test "bash t.sh rc=0" --wt "$PACK"; t "⑧ done DONE" inc "$OUT" "DONE"; a="$(nfetch) $(ncat)"
  work "${s}b"; gx "$(BT)" done --seat "$(NN "${s}b")" --card "${s}b" --did x --test "bash t.sh rc=0" --wt "$PACK"; t "⑧ done fetch·cat-file 수 = 기준판(head «$a»)" [ "$(nfetch) $(ncat)" = "$a" ]
  return $E
}
echo "부분 = $PART (세 부분 = cases · mut · base)"
if [ "$PART" = cases ]; then step "사례 ①~⑧"
run "① 끝 다시 판정 = 기준판" c1; run "② 열린 줄 0" c2; run "③ 카드없음·판정 불가 가름" c3; run "④ 묶음 읽기" c4
run "⑤ fetch 묶음" c5; run "⑥ 실패 = 판정 불가" c6; run "⑦ notify 불변" c7; run "⑧ done git 수 불변" c8; echo "head 수:$(cat "$T/c4-")"; fi
if [ "$PART" = mut ]; then
step "변이 M1~M4 (+원본 대조)"
mutbin m1 ft_nano_record_due.py '        out = rows(prepare(ctx, ks), pr)' '        out = [r if r["k"] == "끝" else n for r, n in zip(out, rows(prepare(ctx, ks), pr))]'; mutcase M1 c1 1
mutbin m2 ft_nano_record_batch.py '    return {k: (p, got[s])' '    return {} and {k: (p, got[s])'; mutcase M2 c4 2
mutbin m3 ft_nano_record_batch.py '    if ctx.fetch:' '    if False:'; mutcase M3 c5 3
mutbin m4 ft_nano_record_batch.py '                ctx.tip(team)   # 묶음 실패' '                raise Unjudged("카드 ref fetch 묶음 rc=128")   # 묶음 실패'; mutcase M4 c5 4; fi
if [ "$PART" = base ]; then
step "기준판 ④·⑤ Red · ①·③ Green (팩 $BASE_SHA)"
for c in c4 c5; do o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; printf '%s\n' "$o" | grep -e '④ git' -e '⑤ fetch' -e '^  x ' | head -4; done
for c in c1 c3; do ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(지키는 칸)" || bad "기준판 $c FAIL"; done; fi
finish
