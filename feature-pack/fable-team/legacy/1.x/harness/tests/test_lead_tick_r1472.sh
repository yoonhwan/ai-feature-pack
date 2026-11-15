#!/usr/bin/env bash
# test_lead_tick_r1472.sh — ft-lead-tick.sh(r1472) 계약: 팀장 «사건 턴» 1회 = 비모델 스크립트 1회 + 결정 필요 N
#   T1 합성 명부·카드(대기 2 · 진행 1)·나노 2(1석 25분 유휴)·쪽지 2([HIL] 1)·열린 h 1 → ≤30줄 · «결정 필요: 3» · [정리] 1통(to=_report_to) · rc0
#   T2 `_master` ≠ 좌석(또는 빈칸) → recv 0 · send 0 · «결속 불일치» 1줄 · rc1
#   T3 좌석 상태 조회 실패(rc3) → «판정 불가 rc=3» 1줄 · 나머지 항목 출력 · send 함(유휴 미상) · rc1
#   T4 FT_LEAD_TICK_BUDGET=1 · 가짜 mbox sleep 2 → rc124 · send 0
#   T5 송신 규칙: N=0 ∧ .last 같음 → send 0 + «조용함» / 카드 변화 → send 1 / _report_to = 자기 → send 0 + «자기 송신 차단» rc1 / _report_to 없음 → planner _master
#   T1b(DA B1) 일반 쪽지 3 뒤 4번째 [HIL] → 결정 필요 1 · 그 머리 표시 · 조용함 해제(send)
#   T3b(DA B2) 실제 ft-seat-status.sh + PATH 의 tmux rc3 → «좌석 상태(tmux) 판정 불가 rc=3» · 유휴 미상 · send 1 · rc1
#   T3c tmux «no server running» rc1 → 살아 있는 좌석 0 정상 · rc0   T3d status [] + tmux 목록에 명부 nano → 모순 판정 불가 · rc1
#   T6(r1472b) TMUX 를 export 한 채 실행 → 자식 tmux·ft-seat-status 가 원래 TMUX 값을 받는다 · rc0 · «판정 불가» 0줄
#   T7(r1472b) 카드 ref = origin/ops/main-base → origin/main 중 카드 폴더가 있는 첫 ref · env FT_LEAD_TICK_CARDS_REF = 그 ref 하나
#   T7c·T7d(DA R1) 두 ref 모두 카드 트리 없음 → «카드(<후보 ref 들>:<_cards>) 트리 없음 판정 불가 rc≠0» 1줄 · 결정 필요 1 · rc1 · [정리] 판정 불가 1 (T7c 기본값 · T7d env 한 ref)
#   T8(r1472b) [정리] 2줄째 «골좌표: <N> — <골 앞 12자>» (정본 골 표 · 팀 칸 첫 낱말) · check --coord-only rc0 · 팀 행 0 = 골좌표 판정 불가
#   Tdesk(옛 T6) test_desk_tick_r1462 rc0 · 설치기·desk 파일 origin/main 대비 diff 0
# 전부 합성(임시 루트·임시 git·가짜 mbox·가짜 ft-hil·가짜 ft-seat-status) · 실 우편함·실 좌석 쓰기 0 · sleep 0(가짜 mbox 의 T4 지연만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../bin/ft-lead-tick.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

NOW=1794103664
LEAD='byz-knowledge-master-pi#99'
REPORT='byz-harness-master-pi#270'
PLANNER='byz-planner-master-pi#310'
R="$T/root"; F="$R/.fable-team"
mkdir -p "$F/comm" "$T/hil" "$T/state" "$R/design/teams/knowledge/indices/대기" "$R/design/teams/knowledge/indices/진행"
roster() {  # roster <_master> [<_report_to>|-]
  python3 - "$F/seats-knowledge.json" "$1" "${2:--}" <<'PY'
import json, sys
d = {"_master": sys.argv[2], "_cards": "design/teams/knowledge/indices"}
if sys.argv[3] != "-": d["_report_to"] = sys.argv[3]
d["byz-knowledge-nano-a#0"] = {"role": "nano", "agent": "pi"}
d["byz-knowledge-nano-b#0"] = {"role": "nano", "agent": "pi"}
d["byz-knowledge-da-codex#3"] = {"role": "da", "agent": "codex"}
d["byz-knowledge-nano-old#0"] = {"role": "stop-ready", "agent": "pi"}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
roster "$LEAD" "$REPORT"
printf '{"_master":"%s"}\n' "$PLANNER" > "$F/seats-planner.json"
: > "$R/design/teams/knowledge/indices/대기/r1.md"; : > "$R/design/teams/knowledge/indices/대기/r2.md"; : > "$R/design/teams/knowledge/indices/진행/r3.md"
git -C "$R" init -q && git -C "$R" add design && git -C "$R" -c user.name=t -c user.email=t@t commit -qm cards \
  && git -C "$R" update-ref refs/remotes/origin/main HEAD || { echo "FAIL 합성 git"; exit 1; }

cat > "$F/comm/mbox.sh" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  send) shift
        python3 - "$FAKE_SENT" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}, ensure_ascii=False) + "\n")
PY
        echo "QUEUED seq=1 to=$1"; exit 0;;
  recv) [ -n "${FAKE_RECV_MARK:-}" ] && printf 'called\n' >> "$FAKE_RECV_MARK"
        [ -n "${FAKE_MBOX_SLEEP:-}" ] && sleep "$FAKE_MBOX_SLEEP"
        [ -n "${FAKE_RECV:-}" ] && [ -f "$FAKE_RECV" ] && cat "$FAKE_RECV" || echo "SCANNED 1 mailbox(es): fake"
        exit 0;;
esac
exit 2
EOS
cat > "$T/hil/ft-hil.sh" <<'EOS'
#!/usr/bin/env bash
[ -f "$HIL_DIR/pending.txt" ] && cat "$HIL_DIR/pending.txt"; exit 0
EOS
cat > "$T/seat-status.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "${STATUS_MARK:-}" ] && printf '%s\n' "${TMUX-<unset>}" >> "$STATUS_MARK"
[ -n "${FAKE_STATUS_RC:-}" ] && { echo "tmux 없음" >&2; exit "$FAKE_STATUS_RC"; }
printf '%s\n' "$FAKE_STATUS"
EOS
ST_IDLE='[{"seat":"byz-knowledge-nano-a#0","pane":"IDLE","jsonl_age":1500},{"seat":"byz-knowledge-nano-b#0","pane":"BUSY","jsonl_age":30},{"seat":"byz-knowledge-da-codex#3","pane":"IDLE","jsonl_age":100},{"seat":"byz-knowledge-nano-old#0","pane":"IDLE","jsonl_age":9000}]'
ST_CALM='[{"seat":"byz-knowledge-nano-a#0","pane":"BUSY","jsonl_age":10},{"seat":"byz-knowledge-nano-b#0","pane":"BUSY","jsonl_age":30}]'
printf 'SCANNED 1 mailbox(es)\nREAD [byz-planner-master-pi#310->%s] #11 — [HIL] 오빠 결정 필요: 지식 색인 재빌드 GO 여부\nREAD [byz-knowledge-nano-a#0->%s] #12 — [회신] r9 끝\n' "$LEAD" "$LEAD" > "$T/recv2.txt"
printf 'h77 30\n' > "$T/hil/pending.txt"; printf 'to=%s\n' "$LEAD" > "$T/hil/h77.notify"

mkdir -p "$T/fakebin" "$T/badbin"; printf '#!/bin/bash\nexit 0\n' > "$T/fakebin/tmux-ok"
printf '#!/bin/bash\nprintf "%%s rc3\\n" "$*" >> "$TMUX_MARK"; exit 3\n' > "$T/badbin/tmux"; chmod +x "$T/fakebin/tmux-ok" "$T/badbin/tmux"
canon() {  # canon <파일> <행…> — 가짜 정본 골 표(«골|팀» 행)
  local f="$1"; shift
  { printf '## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
    for r in "$@"; do printf '| %s | ①증거 |\n' "$r"; done; } > "$f"
}
canon "$T/A6.md" '지식 첫째 골 — 색인 다시 짓기 | knowledge' '하네스 운영 정리 — 끝난 일은 남지 않는다 | harness (byz-harness-master)' '지식 둘째 골 | knowledge · ops(조직)'
canon "$T/A6-noknow.md" '하네스 운영 정리 — 끝난 일은 남지 않는다 | harness (byz-harness-master)'
export FAKE_STATUS="$ST_IDLE" FAKE_RECV="$T/recv2.txt" FAKE_SENT="$T/sent.jsonl" FT_GOAL_A6_MD="$T/A6.md"
run() {
  env FT_ROOT="$R" FT_HIL_DIR="$T/hil" HIL_DIR="$T/hil" \
      FT_LEAD_TICK_MBOX="$F/comm/mbox.sh" FT_LEAD_TICK_HIL="$T/hil/ft-hil.sh" FT_LEAD_TICK_SEAT_STATUS="${LT_STATUS:-$T/seat-status.sh}" \
      FT_LEAD_TICK_TMUX="${LT_TMUX-$T/fakebin/tmux-ok}" \
      FT_LEAD_TICK_NOW="$NOW" FT_LEAD_TICK_STATE_DIR="$T/state" bash "$S" "${LT_SEAT:-$LEAD}" 2>&1
}
sent_n() { [ -f "$T/sent.jsonl" ] && grep -c . "$T/sent.jsonl" || echo 0; }
[ -f "$S" ] || { echo "FAIL ft-lead-tick.sh 없음: $S"; echo "FAILED 1"; exit 1; }
bash -n "$S" && ok "bash -n" || bad "bash -n"

# ── T1
t0="$(date +%s)"; out="$(run)"; rc=$?; el=$(( $(date +%s) - t0 ))
n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
[ "$rc" -eq 0 ] && ok "T1 rc0" || bad "T1 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "$n" -le 30 ] && ok "T1 출력 ${n}줄 ≤30 · ${el}초" || bad "T1 출력 ${n}줄"
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 3' && ok "T1 마지막 줄 «결정 필요: 3»" || bad "T1 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
[ "$(sent_n)" = 1 ] && ok "T1 [정리] 1통" || bad "T1 send $(sent_n)통"
python3 - "$T/sent.jsonl" "$REPORT" <<'PY' && ok "T1 to=_report_to · 4줄 · 첫 줄 «카드 대기 2 · 진행 1 · 유휴 1 · 다음 수 …» · 백틱·\$( 0" || bad "T1 본문"
import json, sys
try: r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
except Exception as e: print("BAD", e); sys.exit(1)
b = r["body"]; bad = []
if r["to"] != sys.argv[2]: bad.append("to=" + r["to"])
if len(b.splitlines()) != 4: bad.append("줄수=%d" % len(b.splitlines()))
if not b.splitlines()[0].startswith("카드 대기 2 · 진행 1 · 유휴 1 · 다음 수 "): bad.append("첫줄=" + b.splitlines()[0])
if "`" in b or "$(" in b: bad.append("백틱/$(")
if bad: print("BAD", bad); sys.exit(1)
PY

# ── T2
for m in 'byz-knowledge-master-pi#98' ''; do
  rm -f "$T/sent.jsonl" "$T/mark"; roster "$m" "$REPORT"
  out="$(FAKE_RECV_MARK="$T/mark" run)"; rc=$?
  [ "$rc" -eq 1 ] && [ ! -f "$T/mark" ] && [ "$(sent_n)" = 0 ] && ok "T2 _master='$m' → recv 0 · send 0 · rc1" || bad "T2 _master='$m' rc=$rc recv=$([ -f "$T/mark" ] && echo y) send=$(sent_n)"
  printf '%s\n' "$out" | grep -q '결속 불일치' && ok "T2 «결속 불일치» 1줄" || bad "T2 줄 없음: $(printf '%s' "$out" | tr '\n' '/')"
done
roster "$LEAD" "$REPORT"

# ── T3
rm -f "$T/sent.jsonl"
out="$(FAKE_STATUS_RC=3 run)"; rc=$?
[ "$rc" -eq 1 ] && ok "T3 rc1" || bad "T3 rc=$rc"
printf '%s\n' "$out" | grep -q '판정 불가 rc=3' && ok "T3 «판정 불가 rc=3»" || bad "T3 판정 불가 줄 없음"
printf '%s\n' "$out" | grep -q '^카드 대기 2 · 진행 1' && printf '%s\n' "$out" | grep -q '^쪽지 2건' && ok "T3 나머지 항목 출력" || bad "T3 나머지: $(printf '%s' "$out" | tr '\n' '/')"
[ "$(sent_n)" = 1 ] && grep -q '유휴 미상' "$T/sent.jsonl" && ok "T3 send 1 · 유휴 미상" || bad "T3 send=$(sent_n) $(cat "$T/sent.jsonl" 2>/dev/null)"

# ── T4
rm -f "$T/sent.jsonl"
t0="$(date +%s)"; out="$(FT_LEAD_TICK_BUDGET=1 FAKE_MBOX_SLEEP=2 run)"; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 124 ] && ok "T4 rc124 (${el}초)" || bad "T4 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "$(sent_n)" = 0 ] && ok "T4 send 0" || bad "T4 send $(sent_n)"

# ── T5
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"; : > "$T/hil/pending.txt"
export FAKE_STATUS="$ST_CALM"; unset FAKE_RECV
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sent_n)" = 1 ] && printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && ok "T5a N=0 첫 회(.last 없음) → send 1" || bad "T5a rc=$rc send=$(sent_n) $(printf '%s' "$out" | tr '\n' '/')"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sent_n)" = 1 ] && ok "T5b N=0 ∧ 무변화 → send 0 · rc0" || bad "T5b rc=$rc send=$(sent_n)"
grep -q '조용함' "$T/state/$LEAD.last" 2>/dev/null && ok "T5b .last «조용함 ts»" || bad "T5b .last: $(cat "$T/state/$LEAD.last" 2>/dev/null)"
: > "$R/design/teams/knowledge/indices/대기/r4.md"
git -C "$R" add design && git -C "$R" -c user.name=t -c user.email=t@t commit -qm r4 && git -C "$R" update-ref refs/remotes/origin/main HEAD
out="$(run)"; rc=$?
[ "$(sent_n)" = 2 ] && tail -1 "$T/sent.jsonl" | grep -q '카드 대기 3' && ok "T5c N=0 인데 카드 변화 → send 1" || bad "T5c send=$(sent_n)"
roster "$LEAD" "$LEAD"
out="$(run)"; rc=$?
[ "$rc" -eq 1 ] && [ "$(sent_n)" = 2 ] && printf '%s\n' "$out" | grep -q '자기 송신 차단' && ok "T5d _report_to=자기 → send 0 · «자기 송신 차단» · rc1" || bad "T5d rc=$rc send=$(sent_n)"
roster "$LEAD" -; rm -rf "$T/state"; mkdir -p "$T/state"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && tail -1 "$T/sent.jsonl" | grep -q "\"to\": \"$PLANNER\"" && ok "T5e _report_to 없음 → planner _master" || bad "T5e rc=$rc $(tail -1 "$T/sent.jsonl")"

# ── T1b(DA B1) 결정 머리 집계는 표시 3줄 상한과 무관 — 4번째 [HIL] 도 센다
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"; roster "$LEAD" "$REPORT"; : > "$T/hil/pending.txt"
export FAKE_STATUS="$ST_CALM"; unset FAKE_RECV
run >/dev/null
printf 'SCANNED 1\nREAD [a#0->%s] #21 — [회신] 1\nREAD [b#0->%s] #22 — [회신] 2\nREAD [c#0->%s] #23 — [회신] 3\nREAD [p#1->%s] #24 — [HIL] 넷째 결정\n' "$LEAD" "$LEAD" "$LEAD" "$LEAD" > "$T/recv4.txt"
out="$(FAKE_RECV="$T/recv4.txt" run)"; rc=$?
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 1' && ok "T1b 4번째 [HIL] → 결정 필요 1" || bad "T1b 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
printf '%s\n' "$out" | grep -q '#24 p#1 \[HIL\]' && ok "T1b 그 머리 표시" || bad "T1b 머리 없음: $(printf '%s' "$out" | tr '\n' '/')"
[ "$rc" -eq 0 ] && [ "$(sent_n)" = 2 ] && tail -1 "$T/sent.jsonl" | grep -q '다음 수 #24' && ok "T1b 조용함 해제 · send · 다음 수 #24" || bad "T1b rc=$rc send=$(sent_n)"

# ── T3b(DA B2) 실제 의존 도구(ft-seat-status.sh)가 tmux 실패를 rc0 [] 로 숨겨도 리드는 판정 불가로 낸다
rm -f "$T/sent.jsonl" "$T/tmux.calls"
out="$(PATH="$T/badbin:$PATH" TMUX_MARK="$T/tmux.calls" FT_ROOTS_TSV="$T/no-roots.tsv" LT_TMUX= LT_STATUS="$HERE/../bin/ft-seat-status.sh" run)"; rc=$?
[ -s "$T/tmux.calls" ] && ok "T3b 주입 확인(tmux rc3 호출 표식)" || bad "T3b tmux 주입 안 됨"
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '좌석 상태.*판정 불가 rc=3' && ok "T3b «좌석 상태 판정 불가 rc=3» · rc1" || bad "T3b rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
printf '%s\n' "$out" | grep -q '^좌석 nano' && bad "T3b 실패인데 정상 좌석 줄" || ok "T3b 정상 좌석 줄 0"
[ "$(sent_n)" = 1 ] && grep -q '유휴 미상' "$T/sent.jsonl" && ok "T3b send 1 · 유휴 미상" || bad "T3b send=$(sent_n)"

# ── T3c tmux «no server running» = 살아 있는 좌석 0 정상(실제 ft-seat-status.sh 경유)
printf '#!/bin/bash\necho "no server running on /tmp/tmux-501/default" >&2; exit 1\n' > "$T/nosrv-tmux"; chmod +x "$T/nosrv-tmux"
mkdir -p "$T/nosrvbin"; cp "$T/nosrv-tmux" "$T/nosrvbin/tmux"
rm -f "$T/sent.jsonl"
out="$(PATH="$T/nosrvbin:$PATH" FT_ROOTS_TSV="$T/no-roots.tsv" LT_TMUX= LT_STATUS="$HERE/../bin/ft-seat-status.sh" run)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^좌석 nano 0 · da 0 · 유휴(20분+) 0$' && ! printf '%s\n' "$out" | grep -q '판정 불가' \
  && ok "T3c no server running → 좌석 0 정상 · rc0" || bad "T3c rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"

# ── T3d status [] 인데 tmux 에 명부 nano 좌석이 산다 = 모순 → 판정 불가
printf '#!/bin/bash\necho "byz-knowledge-nano-a#0"; echo "other-session"\n' > "$T/live-tmux"; chmod +x "$T/live-tmux"
rm -f "$T/sent.jsonl"
out="$(FAKE_STATUS='[]' LT_TMUX="$T/live-tmux" run)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '좌석 상태.*판정 불가 rc=' && ! printf '%s\n' "$out" | grep -q '^좌석 nano' \
  && ok "T3d status [] + tmux 명부 좌석 → 모순 판정 불가 · rc1" || bad "T3d rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "$(sent_n)" = 1 ] && grep -q '유휴 미상' "$T/sent.jsonl" && ok "T3d send 1 · 유휴 미상" || bad "T3d send=$(sent_n)"

# ── T6(r1472b) tmux 가 export 한 TMUX(소켓) 를 덮지 않는다 — 자식 tmux·ft-seat-status 둘 다 원래 값
printf '#!/bin/bash\nprintf "%%s\\n" "${TMUX-<unset>}" >> "$TMUX_MARK"; exit 0\n' > "$T/fakebin/tmux-rec"; chmod +x "$T/fakebin/tmux-rec"
rm -rf "$T/state" "$T/sent.jsonl" "$T/tmux.env" "$T/status.env"; mkdir -p "$T/state"; roster "$LEAD" "$REPORT"
SOCK='/private/tmp/tmux-501/fake-sock,4242,0'
out="$(TMUX="$SOCK" TMUX_MARK="$T/tmux.env" STATUS_MARK="$T/status.env" LT_TMUX="$T/fakebin/tmux-rec" run)"; rc=$?
[ "$(cat "$T/tmux.env" 2>/dev/null)" = "$SOCK" ] && ok "T6 자식 tmux 가 원래 TMUX 를 받음" || bad "T6 자식 tmux TMUX='$(cat "$T/tmux.env" 2>/dev/null)'"
[ "$(cat "$T/status.env" 2>/dev/null)" = "$SOCK" ] && ok "T6 ft-seat-status 가 원래 TMUX 를 받음" || bad "T6 ft-seat-status TMUX='$(cat "$T/status.env" 2>/dev/null)'"
[ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q '판정 불가' && ok "T6 rc0 · 판정 불가 0줄" || bad "T6 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"

# ── T7(r1472b) 카드 ref = keeper 순서(origin/ops/main-base → origin/main) 중 카드 폴더가 있는 첫 ref
mkref() {  # mkref <ref> <대기 수> — 합성 트리(knowledge 카드 폴더 · 대기 N · 진행 1) · N=0 = 카드 폴더 없음
  local idx="$T/idx" blob tree c i; rm -f "$idx"; blob="$(git -C "$R" hash-object -w --stdin </dev/null)"
  if [ "$2" -eq 0 ]; then GIT_INDEX_FILE="$idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,other/x.md"
  else for i in $(seq 1 "$2"); do GIT_INDEX_FILE="$idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,design/teams/knowledge/indices/대기/w$i.md"; done
       GIT_INDEX_FILE="$idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,design/teams/knowledge/indices/진행/d1.md"; fi
  tree="$(GIT_INDEX_FILE="$idx" git -C "$R" write-tree)"; c="$(git -C "$R" -c user.name=t -c user.email=t@t commit-tree "$tree" -m "$1" </dev/null)"
  git -C "$R" update-ref "refs/remotes/$1" "$c"
}
mkref origin/ops/main-base 3; mkref origin/main 1
rm -rf "$T/state"; mkdir -p "$T/state"
out="$(run)"
printf '%s\n' "$out" | grep -qx '카드 대기 3 · 진행 1 (origin/ops/main-base)' && ok "T7a ops/main-base 먼저 → «카드 대기 3 (origin/ops/main-base)»" || bad "T7a $(printf '%s\n' "$out" | grep '^카드' || echo 카드 줄 없음)"
mkref origin/ops/main-base 0
out="$(run)"
printf '%s\n' "$out" | grep -qx '카드 대기 1 · 진행 1 (origin/main)' && ok "T7b ops/main-base 에 카드 폴더 없음 → origin/main" || bad "T7b $(printf '%s\n' "$out" | grep '^카드' || echo 카드 줄 없음)"
mkref origin/ops/main-base 3
out="$(FT_LEAD_TICK_CARDS_REF=origin/main run)"
printf '%s\n' "$out" | grep -qx '카드 대기 1 · 진행 1 (origin/main)' && ok "T7b' env 지정 → 그 ref 하나" || bad "T7b' $(printf '%s\n' "$out" | grep '^카드' || echo 카드 줄 없음)"

# ── T7c·T7d(DA R1) 두 ref 모두 유효 commit · 카드 트리만 없음 = 판정 불가(카드 0 으로 숨기지 않는다) · T7c 기본값 · T7d env 한 ref
mkref origin/ops/main-base 0; mkref origin/main 0
for envref in '' origin/main; do
  tn=T7c; want='origin/ops/main-base origin/main'; [ -n "$envref" ] && { tn=T7d; want="$envref"; }
  rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"
  out="$(FT_LEAD_TICK_CARDS_REF="$envref" run)"; rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c "^카드($want:design/teams/knowledge/indices) 트리 없음 판정 불가 rc=[1-9]")" = 1 ] \
    && ! printf '%s\n' "$out" | grep -q '^카드 대기' && printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 1' \
    && ok "$tn env='$envref' 카드 트리 없음 → «카드($want:…) 트리 없음 판정 불가» 1줄 · 결정 필요 1 · rc1" || bad "$tn env='$envref' rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
  grep -q '판정 불가 1"' "$T/sent.jsonl" 2>/dev/null && grep -q '카드 대기 ? · 진행 ?' "$T/sent.jsonl" \
    && ok "$tn env='$envref' [정리] 카드 대기 ? · 판정 불가 1" || bad "$tn env='$envref' [정리]: $(cat "$T/sent.jsonl" 2>/dev/null)"
done
mkref origin/ops/main-base 3; mkref origin/main 1

# ── T8(r1472b) [정리] 2줄째 골좌표 — 정본 골 표에서 팀 칸 첫 낱말 = 리드 팀인 첫 행
HLEAD='byz-harness-master-pi#271'
printf '{"_master":"%s","_report_to":"%s"}\n' "$HLEAD" "$PLANNER" > "$F/seats-harness.json"
body2() { python3 -c 'import json,sys; b=[json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"].splitlines(); print(b[int(sys.argv[2])] if len(b) > int(sys.argv[2]) else "")' "$T/sent.jsonl" "$1"; }
coord_ok() { python3 -c 'import json,sys; print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$T/sent.jsonl" | python3 "$HERE/../bin/ft_goal_table.py" check --coord-only; }
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"
out="$(LT_SEAT="$HLEAD" run)"; rc=$?
[ "$(body2 1)" = '골좌표: 2 — 하네스 운영 정리 —' ] && ok "T8a harness 리드 2줄째 «골좌표: 2 — 하네스 운영 정리 —»" || bad "T8a rc=$rc 2줄째='$(body2 1)' out=$(printf '%s' "$out" | tr '\n' '/')"
ck="$(coord_ok)" && printf '%s' "$ck" | grep -q '^GOAL-OK n=2' && ok "T8a check --coord-only rc0 ($ck)" || bad "T8a check: $ck"
[ "$(body2 0 | cut -c1-6)" = '카드 대기 ' ] && [ "$(body2 2 | cut -c1-4)" = '[정리]' ] && [ "$(body2 3 | cut -c1-2)" = '회차' ] && ok "T8a 순서 카드 → 골좌표 → [정리] → 회차" || bad "T8a 순서"
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"
run >/dev/null
body2 1 | grep -q '^골좌표: 1 — ' && coord_ok | grep -q '^GOAL-OK n=1' && ok "T8b knowledge 여러 행 → 표 순서 첫 행(1) · check rc0" || bad "T8b 2줄째='$(body2 1)'"
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"
out="$(FT_GOAL_A6_MD="$T/A6-noknow.md" run)"; rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^골좌표 판정 불가 rc=')" = 1 ] && ok "T8c 팀 행 0 → «골좌표 판정 불가» 1줄 · rc1" || bad "T8c rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
! grep -q '골좌표:' "$T/sent.jsonl" && [ "$(body2 1 | cut -c1-4)" = '[정리]' ] && ok "T8c 골좌표 줄 0 · 지어내기 0" || bad "T8c 본문: $(cat "$T/sent.jsonl")"
out="$(FT_GOAL_A6_MD="$T/없는.md" run)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^골좌표 판정 불가 rc=' && ok "T8d 정본 읽기 실패 → 골좌표 판정 불가 · rc1" || bad "T8d rc=$rc"

# ── Tdesk(옛 T6)
bash "$HERE/test_desk_tick_r1462.sh" >/dev/null 2>&1 && ok "T6 test_desk_tick_r1462 rc0" || bad "T6 desk 시험 실패"
B="$HERE/.."
if git -C "$B" rev-parse --verify -q origin/main >/dev/null; then
  git -C "$B" diff --quiet origin/main -- bin/ft-tick-install.sh bin/ft-desk-tick.sh kit/fable-team/bin/ft-tick-install.sh kit/fable-team/bin/ft-desk-tick.sh \
    && ok "T6 설치기·desk 파일 diff 0" || bad "T6 설치기·desk 파일이 바뀌었다"
else bad "T6 origin/main 판정 불가"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
