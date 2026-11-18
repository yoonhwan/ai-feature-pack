#!/usr/bin/env bash
# test_desk_tick_mail_peek_r2187.sh — ft-desk-tick.sh ⑤ 는 우편함을 소비하지 않는다(r2187 · 반례 ②~⑪ · L5 글 확인)
#   L1 ⑤ = `mbox.sh peek <좌석> --rows` 1회 · recv 0 · 사본 파일 0  L2 «쪽지 N건» · 머리 ≤3 · «외» · «쪽지 읽기» · «우편함 가득»
#   L3 판독 실패 = «쪽지 판정 불가 rc=N» · 머리 0 · N=0 으로 [완료] · rc1  L4 결속 실패 = mbox 호출 0
# 전부 합성(임시 루트 · 상태 있는 가짜 mbox · 가짜 hil·launchctl·ps) · 실 우편함 · 실 세션 · 외부 호출 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../bin/ft-desk-tick.sh"
DOC="$HERE/../../skill/references/desk-tick-prompt.md"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-desk-tick.sh 없음: $S"; echo "FAILED 1"; exit 1; }

NOW=1794103664
DESK='byz-planner-desk-claude#121'; PLANNER='byz-planner-master-claude#240'
R="$T/root/.fable-team"; M="$R/comm/mbox.sh"
mkdir -p "$R/comm" "$T/fakebin" "$T/hil" "$T/tmp"
bind() { printf '%s\n' "$1" > "$R/seats-planner.json"; }
bind "{\"_master\":\"$PLANNER\",\"_desk\":\"$DESK\"}"

# 상태 있는 가짜 mbox: 큐 = $FAKE_Q(JSON 줄) · 호출 = $FAKE_CALLS 에 «동사 인자…» 1줄
#   peek <me> --rows = 읽기만(FAKE_PEEK_RC 면 그 rc · FAKE_PEEK_RAW 면 그 파일 그대로) · recv = READ 줄 + 큐 비움 · send = $FAKE_SENT
cat > "$M" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CALLS"
case "${1:-}" in
  peek) [ -n "${FAKE_PEEK_RC:-}" ] && exit "$FAKE_PEEK_RC"
        [ -n "${FAKE_PEEK_RAW:-}" ] && { cat "$FAKE_PEEK_RAW"; exit 0; }
        python3 - "$FAKE_Q" <<'PY'
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()] if os.path.exists(sys.argv[1]) else []
print("pending=%d scanned=1 lineage=fake" % len(rows))
for r in rows: print(json.dumps(r, ensure_ascii=False))
PY
        exit 0;;
  recv) python3 - "$FAKE_Q" <<'PY'
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()] if os.path.exists(sys.argv[1]) else []
print("SCANNED 1 mailbox(es): fake")
for r in rows: print("READ [%s->%s] #%s %s %s" % (r["from"], r["to"], r["seq"], r["ts"], r["body"]))
print("PENDING-AFTER 0")
PY
        : > "$FAKE_Q"; exit 0;;
  send) python3 - "$FAKE_SENT" "$2" "$3" "$4" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}) + "\n")
PY
        exit 0;;
esac
exit 2
EOS
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil/ft-hil.sh"
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
echo "$2"; echo "	state = not running"
case "$2" in *ft-tick) echo "	last exit code = (never exited)";; *) echo "	last exit code = 0";; esac
EOS
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "4242 python3 -u - /x/bin %s"\n' "$DESK" > "$T/fakebin/ps"
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps"   # 시험 픽스처만 실행 비트
# ②③④ 정상 픽스처(r1462 T1 과 같음) — 쪽지 말고는 결정 필요 0
printf 'ts=%s stall=0 a=0 b=0 c=0 d=0 seats=1\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$R/comm/mailbox.log.jsonl"
( cd "$T/root" && git init -q && mkdir -p design/teams/planner && printf '## 골 진행\n\n| 1 | a |\n\n## 끝\n' > design/teams/planner/PLAN-oppa-ledger.md && git add design && git -c user.email=t@t -c user.name=t commit -qm t && git update-ref refs/remotes/origin/main HEAD && git update-ref refs/remotes/origin/ops/main-base HEAD )

STATE_DIR="$T/state"
run() {
  : > "$T/calls"; rm -f "$T/sent.jsonl"
  env TMPDIR="$T/tmp" FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$M" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" \
      FT_DESK_TICK_STALL_LOG="$T/stall.log" FT_DESK_TICK_LOG="$R/comm/mailbox.log.jsonl" \
      FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 FT_DESK_TICK_STATE_DIR="$STATE_DIR" \
      FAKE_Q="$T/q.jsonl" FAKE_CALLS="$T/calls" FAKE_SENT="$T/sent.jsonl" bash "$S" "$DESK" 2>&1
}
queue() {  # queue <첫 seq> <통수> — 보통 본문 쪽지를 큐에 쓴다
  python3 - "$T/q.jsonl" "$1" "$2" "$PLANNER" "$DESK" <<'PY'
import json, sys
q, s, n, f, t = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
with open(q, "w", encoding="utf-8") as fh:
    for i in range(s, s + n): fh.write(json.dumps({"seq": i, "ts": "2026-11-17T08:05:59Z", "to": t, "from": f, "body": "쪽지 %d 본문" % i}, ensure_ascii=False) + "\n")
PY
}
heads() { printf '%s\n' "$out" | grep -c '^  #'; }
last() { printf '%s\n' "$out" | tail -1; }
sent_n() { [ -f "$T/sent.jsonl" ] && grep -c . "$T/sent.jsonl" || echo 0; }

# ② 소비 0 — 틱 2회 · 두 번 다 «쪽지 1건» · 큐 바이트 그대로 · 틱 뒤 peek pending=1
queue 501 1; cp "$T/q.jsonl" "$T/q.before"
out="$(run)"; o1="$(printf '%s\n' "$out" | grep '^쪽지 [0-9]*건')"
out="$(run)"; o2="$(printf '%s\n' "$out" | grep '^쪽지 [0-9]*건')"
[ "$o1/$o2" = "쪽지 1건/쪽지 1건" ] && ok "② 틱 2회 모두 «쪽지 1건»" || bad "② 쪽지 줄 = $o1/$o2"
cmp -s "$T/q.before" "$T/q.jsonl" && ok "② 큐 바이트 그대로" || bad "② 큐가 바뀌었다(소비)"
pa="$(FAKE_Q="$T/q.jsonl" FAKE_CALLS=/dev/null bash "$M" peek "$DESK" | head -1)"
case "$pa" in pending=1\ *) ok "② 틱 뒤 pending=1";; *) bad "② 틱 뒤 $pa";; esac
[ -z "$(ls -A "$T/tmp")" ] && [ ! -e "$STATE_DIR" ] && ok "② 사본 파일 0(TMPDIR · 상태 폴더)" || bad "② 사본 파일이 생겼다: $(ls -A "$T/tmp" "$STATE_DIR" 2>/dev/null | tr '\n' ' ')"

# ③ 호출 꼴 — peek <좌석> --rows 1회 · recv 0 · send 1
np="$(grep -cx "peek $DESK --rows" "$T/calls")"; nr="$(grep -c '^recv' "$T/calls")"; ns="$(grep -c '^send' "$T/calls")"
[ "$np/$nr/$ns" = "1/0/1" ] && ok "③ peek 1 · recv 0 · send 1" || bad "③ peek $np · recv $nr · send $ns"

# ④ 머리와 «외» — 5통 → 머리 #11 #12 #13 · «  외 2통» · «쪽지 읽기» · 결정 필요 ≥1
queue 11 5; out="$(run)"
printf '%s\n' "$out" | grep -qx '쪽지 5건' && ok "④ 쪽지 5건" || bad "④ 쪽지 줄 없음"
hs="$(printf '%s\n' "$out" | grep '^  #' | awk '{print $1}' | tr '\n' ' ')"
[ "$hs" = "#11 #12 #13 " ] && ok "④ 머리 3줄 = #11 #12 #13" || bad "④ 머리 = $hs"
printf '%s\n' "$out" | grep -qx '  외 2통' && ok "④ «  외 2통» 1줄" || bad "④ «외» 줄 없음"
printf '%s\n' "$out" | grep -qxF "쪽지 읽기: bash $M recv $DESK" && ok "④ «쪽지 읽기: … recv <좌석>»" || bad "④ «쪽지 읽기» 줄 없음"
last | grep -qE '^결정 필요: [1-9]' && ok "④ 결정 필요 ≥1" || bad "④ 마지막 줄: $(last)"

# ⑤ 0통 — «쪽지 0건» · 머리 0 · «쪽지 읽기» 0 · 결정 필요 0 · rc0
: > "$T/q.jsonl"; out="$(run)"; rc=$?
printf '%s\n' "$out" | grep -qx '쪽지 0건' && [ "$(heads)" = 0 ] && ! printf '%s\n' "$out" | grep -q '^쪽지 읽기' \
  && ok "⑤ 쪽지 0건 · 머리 0 · 읽기 줄 0" || bad "⑤ 출력: $(printf '%s' "$out" | grep '쪽지' | tr '\n' '/')"
[ "$rc" = 0 ] && [ "$(last)" = '결정 필요: 0' ] && ok "⑤ rc0 · 결정 필요 0" || bad "⑤ rc=$rc · $(last)"

# ⑥ 판독 실패 넷 — 머리 0 · rc1 · [완료] 1통(쪽지 0건 · 6항 판정 불가 1건)
queue 21 2
printf 'SCANNED 1 mailbox(es): fake\n' > "$T/raw-b"
printf 'pending=2 scanned=1 lineage=fake\n{"seq": 21, "from": "a", "body": "x"}\n' > "$T/raw-c"
printf 'pending=1 scanned=1 lineage=fake\nnot json\n' > "$T/raw-d"
for c in a b c d; do
  if [ "$c" = a ]; then export FAKE_PEEK_RC=3; want=3; else export FAKE_PEEK_RAW="$T/raw-$c"; want=65; fi
  out="$(run)"; rc=$?; unset FAKE_PEEK_RC FAKE_PEEK_RAW
  b="$(python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).readline())["body"])' "$T/sent.jsonl" 2>/dev/null)"
  if printf '%s\n' "$out" | grep -qx "쪽지 판정 불가 rc=$want" && [ "$(heads)" = 0 ] && [ "$rc" = 1 ] && [ "$(sent_n)" = 1 ] \
     && printf '%s' "$b" | grep -q '쪽지 0건' && printf '%s' "$b" | grep -q '6항 판정 불가 1건'; then ok "⑥$c 판정 불가 rc=$want · 머리 0 · rc1 · [완료] 1통"
  else bad "⑥$c rc=$rc 송신 $(sent_n) · $(printf '%s' "$out" | grep '쪽지' | tr '\n' '/') · 본문 $(printf '%s' "$b" | tr '\n' '/')"; fi
done

# ⑦ 결속 실패 셋 — mbox 호출 0줄 · rc1 · «결속 판정 불가 rc=N»
for c in "{\"_desk\":\"$DESK\"}" "{\"_master\":\"$PLANNER\"}" "{\"_master\":\"$PLANNER\",\"_desk\":\"ft-planner-desk-sonnet#1\"}"; do
  bind "$c"; out="$(run)"; rc=$?
  [ ! -s "$T/calls" ] && [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^결속 판정 불가 rc=' \
    && ok "⑦ 결속 실패 $c → 호출 0 · rc1" || bad "⑦ $c rc=$rc 호출 $(tr '\n' '/' < "$T/calls")"
done
bind "{\"_master\":\"$PLANNER\",\"_desk\":\"$DESK\"}"

# ⑧ [완료] 3줄 — 쪽지 2통 → 1통 · 3줄 · 첫 줄 [완료] desk 틱 — … 쪽지 2건 · 백틱 · $( 0
queue 31 2; out="$(run)"
python3 - "$T/sent.jsonl" <<'PY' && ok "⑧ [완료] 1통 · 3줄 · «쪽지 2건» · 백틱·\$( 0" || bad "⑧ [완료] 본문 위반"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
b = rows[0]["body"] if len(rows) == 1 else ""
l1 = b.splitlines()[0] if b else ""
sys.exit(0 if len(b.splitlines()) == 3 and l1.startswith("[완료] desk 틱 — ") and "쪽지 2건" in l1 and "`" not in b and "$(" not in b else 1)
PY

# ⑨ 상태 폴더 없음 — 부모가 파일 · 쪽지 1통 → rc0 · [완료] 1통 · «쪽지 전문» · «쪽지 저장» 0 · 새 파일 0
printf 'nope\n' > "$T/notadir"; STATE_DIR="$T/notadir/sub"; queue 41 1
out="$(run)"; rc=$?
[ "$rc" = 0 ] && [ "$(sent_n)" = 1 ] && ok "⑨ rc0 · [완료] 1통" || bad "⑨ rc=$rc · 송신 $(sent_n)"
printf '%s\n' "$out" | grep -qE '쪽지 전문|쪽지 저장' && bad "⑨ 사본·저장 글이 남았다" || ok "⑨ «쪽지 전문» · «쪽지 저장» 글 0"
[ -f "$T/notadir" ] && [ "$(cat "$T/notadir")" = nope ] && [ -z "$(ls -A "$T/tmp")" ] && ok "⑨ 새 파일 0" || bad "⑨ 파일이 생겼다"
STATE_DIR="$T/state"

# ⑩ 본문 글자 — 두 줄 · 백틱 · $(touch 표식) · 큰따옴표 · 200자 → 머리 3줄 · 100자 안 · 둘째 줄 0 · 표식 0
python3 - "$T/q.jsonl" "$PLANNER" "$DESK" "$T/marker" <<'PY'
import json, sys
q, f, t, mk = sys.argv[1:5]
bodies = ["첫 줄\n둘째 줄", 'a `id` $(touch %s) "q"' % mk, "가" * 200]
with open(q, "w", encoding="utf-8") as fh:
    for i, b in enumerate(bodies): fh.write(json.dumps({"seq": 51 + i, "ts": "t", "to": t, "from": f, "body": b}, ensure_ascii=False) + "\n")
PY
out="$(run)"
[ "$(heads)" = 3 ] && ok "⑩ 머리 3줄" || bad "⑩ 머리 $(heads)줄"
long="$(printf '%s\n' "$out" | grep '^  #' | python3 -c 'import sys;print(max(len(l.rstrip("\n")) for l in sys.stdin))')"
[ "${long:-999}" -le 100 ] && ok "⑩ 머리 줄 최대 ${long}자 ≤100" || bad "⑩ 머리 줄 ${long}자"
printf '%s\n' "$out" | grep -q '둘째 줄' && bad "⑩ 둘째 줄 글이 나왔다" || ok "⑩ 둘째 줄 글 0"
[ -e "$T/marker" ] && bad "⑩ 본문이 실행됐다(표식 파일)" || ok "⑩ 표식 파일 0"

# ⑪ ring 포화 — pending ≥ 상한(FT_MBOX_RING · 없으면 10) → «우편함 가득» 1줄 · 결정 필요 +1
unset FT_MBOX_RING
for c in "10 - 1 2" "9 - 0 1" "5 5 1 2"; do
  set -- $c; queue 61 "$1"
  if [ "$2" = - ]; then out="$(run)"; else out="$(FT_MBOX_RING=$2 run)"; fi
  nf="$(printf '%s\n' "$out" | grep -c '^우편함 가득')"
  [ "$nf" = "$3" ] && [ "$(last)" = "결정 필요: $4" ] && ok "⑪ pending=$1 ring=$2 → 가득 ${nf}줄 · 결정 필요 $4" || bad "⑪ pending=$1 ring=$2 → 가득 ${nf}줄 · $(last)"
done

# L5 글 — desk-tick-prompt.md 에 «소비» 0 · «mbox.sh recv <좌석>» 안내 있음
[ "$(grep -c '소비' "$DOC")" = 0 ] && grep -qF 'mbox.sh recv <좌석>' "$DOC" && ok "L5 문서 «소비» 0 · recv 안내 있음" || bad "L5 문서 «소비» $(grep -c '소비' "$DOC")회"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
