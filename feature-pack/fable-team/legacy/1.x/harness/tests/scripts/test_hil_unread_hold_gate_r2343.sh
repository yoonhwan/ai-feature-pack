#!/usr/bin/env bash
# test_hil_unread_hold_gate_r2343.sh — r2343: h 실행 직전(.held 뒤 · .sha 대조 앞)에 실행 좌석 ∪ 요청 좌석 쪽지함의 «그 h 보류 쪽지 미읽음» 이면 REJECT rc1 · 확인 못 함 = 판정 불가 rc3 · 계획 바이트 0
#   반례 ①~⑯ · 변이 M1~M8(사본 · 변이마다 원본 같은 사례 1회 더 = 반대 결과 대조) · 기준판 = 팩 커밋 24d192ab bin(① Red) · bin·kit 같은 바이트 · ft-hil.sh 200줄
#   격리: 임시 HIL_DIR · 임시 HOME · HIL_CLIP=0 · 가짜 쪽지함(peek --rows · recv 만 · mbox.py peek 출력 꼴 그대로 2026-11-20 실물 대조) · 리포 밖 계획 · 실 /tmp/h* · 실 쪽지함 0
#         sleep 0(⑦b 만 가짜 peek 8초 = 7초 절단 확인) · 회귀(1.x hil 시험 묶음)는 이 시험 안에서 돌리지 않는다(하드 룰 22 · 시험 1개 70초)
set -uo pipefail
unset FT_SEAT   # 격리: 좌석 env 의 FT_SEAT 를 물려받으면 ⑥·M4 가 «실행 좌석 있음» 이 되어 원본이 FAIL 로 보인다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R2343_BIN:-$HERE/../../bin}"; KIT="$HERE/../../kit/fable-team/bin"; BASE=24d192abc33fee0756cdea818bd0549e612af542
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/none" "$T/sidemail"
printf '#!/bin/bash\nexit 0\n' > "$T/sidemail/mbox.sh"
fail=0; T0=$SECONDS; WHY=""
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1 — $WHY"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
chk() { local t="$1"; shift; if "$@"; then ok "$t"; else bad "$t"; fi; }
S_DESK='byz-harness-desk-pi#130'; S_ARCH='byz-harness-arch-pi#127'; S_OPS='byz-harness-ops-pi#127'

# ── 가짜 쪽지함(peek --rows · recv) — 실 mbox.py peek 출력과 같은 꼴(첫 줄 pending= · 그 뒤 JSON 1줄씩) ──
cat > "$T/peek.py" <<'PY'
import json, os, re, sys
mb, cmd, seat = sys.argv[1], sys.argv[2], sys.argv[3]
rk = lambda n: re.sub(r"#\d+$", "", n or "")
q, rd = os.path.join(mb, "mailbox.jsonl"), os.path.join(mb, "read.jsonl")
rows = [json.loads(l) for l in open(q, encoding="utf-8") if l.strip()] if os.path.exists(q) else []
rdy = {str(json.loads(l)["seq"]) for l in open(rd, encoding="utf-8")} if os.path.exists(rd) else set()
if cmd == "peek":
    open(os.path.join(mb, "peeks.log"), "a", encoding="utf-8").write(seat + "\n")
mine = sorted((r for r in rows if rk(r.get("to")) == rk(seat) and str(r.get("seq")) not in rdy), key=lambda r: r["seq"])
if cmd == "recv":
    with open(rd, "a", encoding="utf-8") as f:
        f.writelines(json.dumps({"seq": r["seq"]}) + "\n" for r in mine)
    print(f"READ {len(mine)}"); sys.exit(0)
print("pending=%d" % len(mine) + (" latest_seq=%d from=%s" % (mine[-1]["seq"], mine[-1]["from"]) if mine else ""))
for r in mine:
    print(json.dumps({"seq": r["seq"], "ts": r.get("ts"), "to": r.get("to"), "from": r.get("from"), "body": r.get("body", "")}, ensure_ascii=False))
PY

send() {  # <to> <from> <본문> — 쪽지 원장 1행(seq = 줄 수 + 1) · stdout = seq
  python3 - "$MB" "$@" <<'PY'
import json, os, sys
mb, to, frm, body = sys.argv[1:5]
p = os.path.join(mb, "mailbox.jsonl")
n = len(open(p, encoding="utf-8").read().splitlines()) if os.path.exists(p) else 0
open(p, "a", encoding="utf-8").write(json.dumps({"seq": n + 1, "ts": "2026-11-20T19:08:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
print(n + 1)
PY
}
world() {  # <이름> — HD·C(쪽지함)·MB(원장)·HOME 새로
  W="$T/w$1"; rm -rf "$W"; mkdir -p "$W/hil" "$W/comm" "$W/mail" "$W/home"
  HD="$W/hil"; C="$W/comm"; MB="$W/mail"; MARK="$W/mark"
  cat > "$C/mbox.sh" <<EOS
#!/bin/bash
case "\${1:-}" in
  peek) [ "\${FAKE_PEEK_FAIL:-0}" = 0 ] || exit 3
        [ "\${FAKE_PEEK_SLEEP:-0}" = 0 ] || sleep "\$FAKE_PEEK_SLEEP"
        exec python3 "$T/peek.py" "$MB" peek "\$2" ;;
  recv) exec python3 "$T/peek.py" "$MB" recv "\$2" ;;
  *) exit 0 ;;
esac
EOS
  chmod +x "$C/mbox.sh"
}
mk() {  # <계획 이름> <h 번호> [요청 좌석…] — 계획·h·.sha(GG 판정기가 씀)·.notify(comm=이 쪽지함)
  local pn="$1" n="$2"; shift 2
  P="$W/$pn.sh.hil"; H="$HD/h$n"
  { echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'; echo ": > $W/mark"; [ $# = 0 ] || echo "# ft-hil-request seat=$*"; echo 'echo RAN'; } > "$P"
  : > "$H"; bash "$GG" write "$(bash "$GG" pre "$P")" "$H" || { WHY=".sha 못 씀"; return 1; }
  printf 'seat=%s\ncomm=%s\n' "${1:-$S_DESK}" "$C" > "$H.notify"
}
rd() {  # [ENV=V…] — 판정기 read 직접(진입 파일 없이) · out=stdout · stderr=$W/err · rc
  local e=("$@")
  out="$(env ${e[@]+"${e[@]}"} bash "$GG" read "$P" "$H" 2>"$W/err")"; rc=$?
}
nope() { [ ! -e "$MARK" ] || { WHY="계획이 돌았다(mark 있음)"; return 1; }; }
add() {  # <bin> <계획> <notify 좌석> → 진입 파일 경로(HD 안)
  local b="$1" p="$2" ns="$3" o
  o="$(env -i HOME="$W/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$W/none.py" FT_MBOX_DIR="$T/sidemail" bash "$b/ft-hil.sh" --add "$p" --notify "$ns" --notify-comm "$C" 2>/dev/null | sed -n 's/^! bash //p' | head -1)"
  [ -n "$o" ] || { WHY="h 등록 실패"; return 1; }; printf '%s' "$o"; }
mke() {  # <bin> <계획 이름> <번호 씨앗> <notify 좌석> → 진입 파일(번호 = 씨앗+1) · P·H 채움
  local b="$1" pn="$2" sd="$3" ns="$4"
  P="$W/$pn.sh.hil"
  { echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'; echo ": > $W/mark"; echo "# ft-hil-request seat=$ns"; echo 'echo RAN'; } > "$P"
  : > "$HD/h$sd"; H="$(add "$b" "$P" "$ns")" || return 1
  [ "${H##*/}" = "h$((sd + 1))" ] || { WHY="번호가 $((sd + 1)) 이 아니다(${H##*/})"; return 1; }; }
runh() {  # <h> [ENV=V…] → stdout(진입 파일) · stderr=$W/err · rc
  local h="$1"; shift; ( cd /tmp && env -i HOME="$W/home" PATH="/usr/bin:/bin" "$@" bash "$h" 2>"$W/err" ); }

# ── 반례 ①~⑯ ──────────────────────────────────────────────────────────────
c1() { GG="$1"; world 1; mk p1 8625 || return 1
  send "$S_DESK" "$S_OPS" '[HIL] h8625 apply 보류 — apply 0 · 실행 0' >/dev/null; rd FT_SEAT="$S_DESK"
  [ "$rc" = 1 ] || { WHY="rc=$rc ≠ 1"; return 1; }
  [ -z "$out" ] || { WHY="stdout 에 계획 바이트가 나갔다(${#out}자)"; return 1; }
  grep -q 'REJECT 보류 쪽지 미읽음 1' "$W/err" || { WHY="REJECT 줄 없음 · err=$(head -1 "$W/err")"; return 1; }; }
c1e() {  # ① 진입 파일 쪽 — 계획 실행 0 · .ran 줄 0
  world 1e; GG="$BIN0/ft-hil-gate.sh"; mke "$BIN0" p1 8624 "$S_DESK" || return 1
  local o; send "$S_DESK" "$S_OPS" '[HIL] h8625 apply 보류 — apply 0' >/dev/null
  o="$(runh "$H" FT_SEAT="$S_DESK")"; [ "$?" = 1 ] || { WHY="rc≠1 · err=$(head -2 "$W/err")"; return 1; }
  [ -z "$o" ] || { WHY="stdout ${#o}자"; return 1; }
  [ ! -e "$H.ran" ] || { WHY=".ran 줄이 생겼다"; return 1; }; nope; }
c2() { GG="$1"; world 2; mk p2 8625 || return 1
  send "$S_DESK" "$S_OPS" '[HIL] h8625 apply 보류 — apply 0' >/dev/null; bash "$C/mbox.sh" recv "$S_DESK" >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="rc=$rc ≠ 0 · err=$(head -1 "$W/err")"; return 1; }
  case "$out" in *'echo RAN'*) ;; *) WHY="계획 바이트가 안 나왔다"; return 1;; esac; }
c3() { GG="$1"; world 3; mk p3 8625 || return 1
  send "$S_DESK" 'ft-hil-h8625' '[HIL] h8625 발급 — 실행 줄 = ! bash /tmp/h8625 · 계획 /tmp/p3.sh.hil' >/dev/null
  send "$S_DESK" 'ft-hil-h8625' '[완료 h8625] rc=1 · apply 0 — 결과 줄 · 계획 /tmp/p3.sh.hil' >/dev/null
  send "$S_DESK" "$S_OPS" '[HIL 미실행] h8625 — 30분 넘게 안 돌았다' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="자동 쪽지에 막혔다 rc=$rc · $(head -1 "$W/err")"; return 1; }; }
c4() { GG="$1"; world 4; mk p4 8625 || return 1
  send "$S_DESK" "$S_OPS" 'h86250 보류 — 실행 0' >/dev/null; send "$S_DESK" "$S_OPS" 'h862 보류 — 멈춤' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="번호 경계가 안 지켜졌다 rc=$rc · $(head -1 "$W/err")"; return 1; }; }
c5() { GG="$1"; world 5; mk p5 8625 || return 1
  send "$S_DESK" "$S_OPS" 'p5.sh.hil 보류 — 계획 멈춤' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 1 ] || { WHY="계획 이름 보류를 못 잡았다 rc=$rc"; return 1; }; }
c6() { GG="$1"; world 6; mk p6 8625 "$S_ARCH" || return 1
  printf 'seat=%s\ncomm=%s\n' "$S_OPS" "$C" > "$H.notify"   # notify 좌석 = 제3 좌석(요청 좌석은 계획 머리로만 보이게)
  send "$S_ARCH" "$S_OPS" 'h8625 실행 0 — arch 판정 대기' >/dev/null
  rd; [ "$rc" = 1 ] || { WHY="FT_SEAT 없이 요청 좌석을 못 봤다 rc=$rc"; return 1; }
  grep -q "REJECT 보류 쪽지 미읽음 1 — #1 $S_ARCH" "$W/err" || { WHY="쪽지 줄이 아니다 · $(head -1 "$W/err")"; return 1; }; }
c7a() { GG="$1"; world 7a; mk p7 8625 || return 1
  mkdir -p "$W/empty"; printf 'seat=%s\ncomm=%s\n' "$S_DESK" "$W/empty" > "$H.notify"
  rd FT_SEAT="$S_DESK"; [ "$rc" = 3 ] || { WHY="쪽지함 도구 없음 = rc $rc ≠ 3"; return 1; }
  [ -z "$out" ] || { WHY="판정 불가인데 바이트가 나갔다"; return 1; }
  grep -q '판정 불가 — 보류 쪽지 확인 못 함' "$W/err" || { WHY="판정 불가 줄 없음"; return 1; }; }
c7b() { GG="$1"; world 7b; mk p7 8625 || return 1
  local t; t="$SECONDS"; rd FT_SEAT="$S_DESK" FAKE_PEEK_SLEEP=8; t=$((SECONDS - t))
  [ "$rc" = 3 ] || { WHY="8초 peek = rc $rc ≠ 3"; return 1; }
  [ "$t" -ge 7 ] && [ "$t" -le 25 ] || { WHY="7초 절단·25초 상한 밖(${t}초)"; return 1; }; }
c7c() { GG="$1"; world 7c; mk p7 8625 || return 1
  rd FT_SEAT="$S_DESK" FAKE_PEEK_FAIL=1; [ "$rc" = 3 ] || { WHY="peek rc≠0 인데 rc=$rc ≠ 3"; return 1; }
  [ -z "$out" ] || { WHY="판정 불가인데 바이트가 나갔다"; return 1; }; }
c8() { GG="$1"; world 8; mk p8 8625 || return 1
  send "$S_DESK" "$S_OPS" 'h8627 delete 보류 — apply 0' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="다른 h 보류에 막혔다 rc=$rc"; return 1; }; }
c9() { world 9; GG="$BIN0/ft-hil-gate.sh"; mke "$BIN0" p9 8624 "$S_DESK" || return 1
  local o; o="$(runh "$H" FT_SEAT="$S_DESK")" || { WHY="첫 실행 rc≠0 · err=$(head -1 "$W/err")"; return 1; }
  send "$S_DESK" "$S_OPS" 'h8625 apply 보류 — 실행 0' >/dev/null
  o="$(runh "$H" FT_SEAT="$S_DESK")"; [ "$?" = 1 ] || { WHY="보류 뒤 둘째 실행이 안 막혔다(rc=$?)"; return 1; }; }
c10() {  # ⑩ 옛 꼴 진입 파일(기준판 ft-hil.sh) + 새 판정기
  local b="$T/b-old" o
  rm -rf "$b"; cp -R "$BB" "$b" && cp "$1" "$b/ft-hil-gate.sh"
  world 10; GG="$b/ft-hil-gate.sh"; mke "$b" p10 8624 "$S_DESK" || return 1
  send "$S_DESK" "$S_OPS" 'h8625 apply 보류 — 실행 0' >/dev/null
  o="$(runh "$H" FT_SEAT="$S_DESK")"; [ "$?" = 1 ] || { WHY="옛 진입 파일이 보류를 못 봤다"; return 1; }; }
c11() { GG="$1"; world 11; mk p11 8625 || return 1
  send "$S_DESK" "$S_OPS" 'h8625 결과 봄 — 문제 없음' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="보류 낱말 없는 쪽지에 막혔다 rc=$rc"; return 1; }; }
c12() { GG="$1"; world 12; mk p12 8625 "$S_ARCH" "$S_OPS" || return 1
  local t; t="$SECONDS"; rd FT_SEAT="$S_DESK"; t=$((SECONDS - t))
  [ "$rc" = 0 ] || { WHY="rc=$rc · $(head -1 "$W/err")"; return 1; }
  [ "$(grep -c . "$MB/peeks.log" 2>/dev/null)" = 3 ] || { WHY="peek 횟수 $(grep -c . "$MB/peeks.log" 2>/dev/null) ≠ 3"; return 1; }
  [ "$t" -le 25 ] || { WHY="좌석 3개 ${t}초 > 25초"; return 1; }; }
c13() {  # ⑬ 요청 좌석(닫힌 나노) 보류 → seen 으로 풀림
  GG="$1"; world 13; mk p13 8625 "$S_ARCH" || return 1
  local sq; sq="$(send "$S_ARCH" "$S_OPS" 'h8625 apply 보류 — apply 0')"
  rd FT_SEAT="$S_DESK"; [ "$rc" = 1 ] || { WHY="요청 좌석 보류를 못 잡았다 rc=$rc"; return 1; }
  bash "$GG" seen "$H" "$sq" 'ops 판정 #354950 로 풀림' || { WHY="seen 명령 실패"; return 1; }
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="seen 뒤에도 막혔다 rc=$rc · $(head -1 "$W/err")"; return 1; }
  grep -q "본 것으로 침 #$sq" "$W/err" || { WHY="«본 것으로 침 #$sq» 줄 없음 · $(head -1 "$W/err")"; return 1; }; }
c14() { c13 "$1" || return 1
  send "$S_ARCH" "$S_OPS" 'h8625 다시 보류 — 멈춤' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 1 ] || { WHY="새 seq 보류가 안 막혔다 rc=$rc"; return 1; }; }
c15() { GG="$1"; world 15; mk p15 8625 || return 1
  send "$S_DESK" "$S_OPS" "$(python3 -c 'print("가" * 400 + " h8625 … HOLD")')" >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 1 ] || { WHY="700자 넘는 쪽지 끝의 HOLD 를 못 잡았다 rc=$rc"; return 1; }; }
c16() { GG="$1"; world 16; mk p16 8622 || return 1
  send "$S_DESK" "$S_OPS" 'h8622 threshold 85% 넘음' >/dev/null; send "$S_DESK" "$S_OPS" 'h8622 holder 바뀜' >/dev/null
  rd FT_SEAT="$S_DESK"; [ "$rc" = 0 ] || { WHY="영문 낱말 경계(threshold·holder)에서 막혔다 rc=$rc"; return 1; }; }

sec "기준판·kit"
git -C "$(git -C "$HERE" rev-parse --show-toplevel)" archive "$BASE" -- "$(git -C "$BIN0" rev-parse --show-prefix)" 2>/dev/null | tar -x -C "$T/base" 2>/dev/null
BB="$(find "$T/base" -type d -path '*harness/bin' | head -1)"
[ -f "${BB:-/}/ft-hil.sh" ] || { echo "FAIL 기준판($BASE)을 못 꺼냄 — 판정 불가"; exit 1; }
for f in ft-hil-gate.sh ft-hil.sh; do cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || { WHY="kit 사본 다름"; bad "bin=kit $f"; }; done
chk "ft-hil.sh 200줄(늘지 않음)" test "$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')" = 200

sec "① 실행 좌석 쪽지함의 보류 미읽음 → REJECT rc1 · 계획 실행 0 · .ran 0"; chk "① REJECT rc1 · 바이트 0" c1 "$BIN0/ft-hil-gate.sh"; chk "① 진입 파일 = 실행 0 · .ran 0" c1e
sec "② recv 로 읽은 뒤 → 실행"; chk "② 실행 rc0" c2 "$BIN0/ft-hil-gate.sh"
sec "③ 자동 쪽지(발급·완료·미실행)만 → 실행"; chk "③ 오탐 0" c3 "$BIN0/ft-hil-gate.sh"
sec "④ h86250 · h862 → 실행(번호 경계)"; chk "④ 번호 경계" c4 "$BIN0/ft-hil-gate.sh"
sec "⑤ 계획 파일 이름만 담은 보류 → REJECT"; chk "⑤ 계획 이름" c5 "$BIN0/ft-hil-gate.sh"
sec "⑥ FT_SEAT 없음 · 요청 좌석 보류 → REJECT"; chk "⑥ 요청 좌석" c6 "$BIN0/ft-hil-gate.sh"
sec "⑦ peek 실패 → 판정 불가 rc3 · 실행 0"; chk "⑦a 쪽지함 도구 없음" c7a "$BIN0/ft-hil-gate.sh"; chk "⑦b 가짜 peek 8초 = 7초 절단" c7b "$BIN0/ft-hil-gate.sh"; chk "⑦c peek rc≠0" c7c "$BIN0/ft-hil-gate.sh"
sec "⑧ 다른 h(h8627) 보류만 → 실행"; chk "⑧ 다른 h" c8 "$BIN0/ft-hil-gate.sh"
sec "⑨ 첫 실행 뒤 보류 도착 → 둘째 REJECT"; chk "⑨ 둘째 실행 막힘" c9
sec "⑩ 옛 꼴 진입 파일 + 새 판정기 → REJECT"; chk "⑩ 옛 진입 파일" c10 "$BIN0/ft-hil-gate.sh"
sec "⑪ 보류 낱말 없는 h 언급 → 실행"; chk "⑪ 낱말 거름" c11 "$BIN0/ft-hil-gate.sh"
sec "⑫ 좌석 3 · peek 3회 · ≤25초"; chk "⑫ 25초 상한" c12 "$BIN0/ft-hil-gate.sh"
sec "⑬ seen 으로 풀림"; chk "⑬ seen 뒤 실행" c13 "$BIN0/ft-hil-gate.sh"
sec "⑭ ⑬ 뒤 다른 seq 새 보류 → 다시 REJECT"; chk "⑭ 새 보류 재차단" c14 "$BIN0/ft-hil-gate.sh"
sec "⑮ 700자 넘는 쪽지 끝의 HOLD → REJECT"; chk "⑮ 전문 판독" c15 "$BIN0/ft-hil-gate.sh"
sec "⑯ threshold · holder → 실행(영문 낱말 경계)"; chk "⑯ 낱말 경계" c16 "$BIN0/ft-hil-gate.sh"

if [ -z "${R2343_BIN:-}" ]; then
  sec "기준판 ① Red — 판정기 24d192ab"
  if c1 "$BB/ft-hil-gate.sh" >/dev/null 2>&1; then WHY="기준판이 막았다(Red 아님)"; bad "기준판 ① Red"; else ok "기준판 ① = 실행(Red)"; fi

  sec "변이 M1~M8 — 사본 FAIL · 원본 같은 사례 PASS"
  mut() {  # <이름> <사례 함수> <줄 표식> <새 줄> [<둘째 표식> <새 줄>]
    local m="$T/m-$1" g
    rm -rf "$m"; cp -R "$BIN0" "$m"; g="$m/ft-hil-gate.sh"
    if ! python3 - "$g" "$1" "$3" "$4" ${5:+"$5"} ${6:+"$6"} <<'PY'
import sys
p, nm, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(p, encoding="utf-8").read()
for tok, new in zip(pairs[::2], pairs[1::2]):
    hits = [i for i, l in enumerate(s.splitlines()) if tok in l]
    if len(hits) != 1:
        sys.exit(f"REJECT 변이 {nm} «{tok}» 자리 {len(hits)}곳")
    ls = s.splitlines()
    ls[hits[0]] = new
    s = "\n".join(ls) + ("\n" if s.endswith("\n") else "")
open(p, "w", encoding="utf-8").write(s)
PY
    then WHY="변이 자리 못 찾아 주입 실패"; bad "변이 $1"; return; fi
    cmp -s "$BIN0/ft-hil-gate.sh" "$g" && { WHY="사본 = 원본"; bad "변이 $1 주입 실패"; return; }
    if "$2" "$g" >/dev/null 2>&1; then WHY="$2 가 변이를 못 잡음"; bad "변이 $1"; return; fi
    local w="$WHY"; "$2" "$BIN0/ft-hil-gate.sh" >/dev/null 2>&1 && ok "변이 $1 → $2 FAIL($w) · 원본 PASS" || bad "변이 $1 원본 $2 FAIL — $WHY"
  }
  mut M1-낱말 c11 '# M1 낱말 거름' '    if (hit.search(b) or plan in b):   # M1 낱말 거름'
  mut M2-경계 c4 '· M2' 'hit = re.compile(n, re.I)   # ④ 번호 경계 · M2'
  mut M3-실패통과 c7c '# M3 = 실패를 통과로' '    [ "$rc" = 0 ] || rc=0   # M3 = 실패를 통과로'
  mut M4-실행좌석만 c6 'ft-hil-request[[:space:]]*seat=//p' '    true'
  mut M5-자동쪽지 c3 '· M5' 'auto = re.compile(r"(?!)")   # ③ r1130 자동 쪽지 · M5'
  mut M6-자리 c1 'hm_gate "$2" "$3" || exit $?' '    :' "printf '%s' \"\$b\" ;;" "    printf '%s' \"\$b\"; hm_gate \"\$2\" \"\$3\" || exit \$? ;;"
  mut M7-seen전체 c14 '# M7 = seq 대신 h 전체를 뺌' '    if not b or seen or auto.match(b):   # M7 = seq 대신 h 전체를 뺌'
  mut M8-대소문자 c15 '· M8 대소문자' 'wrd = re.compile(r"\b(hold|stop)\b")   # ⑯ 영문 낱말 경계(threshold·holder = 아님) · M8 대소문자'
fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS ($((SECONDS - T0))s)"; exit 0; } || { echo "FAIL $fail ($((SECONDS - T0))s)"; exit 1; }
