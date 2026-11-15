#!/usr/bin/env bash
# test_oppa_slack_window_status_r2013.sh — r2013: 오빠 «네» 1회로 승인 확인이 통과한다.
#   ② 창 끊기: T1 질문(head 있음) → desk «[멈춤] …»(40hex 0) → 오빠 «네» = SLACK-OK rc0
#              T2 질문 → desk «다른 head 40hex» 덧글 → 오빠 «네» = REJECT rc2 · T3 질문 → desk 머리 없는 40hex 0 글 → 오빠 «네» = REJECT rc2
#   ① 등록 검사: T4 head 없는 질문 글 --register = rc3 · 장부 쓰기 0 · T5 head 있는 질문 글 --register = rc0 · T6 조회 실패 = rc2 · 장부 0
#   변이(사본에서만): M1 ⓒ 허용 목록 검사 삭제 → T1 FAIL · M2 ⓓ 를 «잇는다» → T3 FAIL · M3 ① 검사 삭제 → T4 FAIL
# 격리: 가짜 조회(FT_SLACK_REPLIES_CMD) · 임시 FT_ROOT · 실 Slack·토큰·게시 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
OPPA="U0AC2JF0M7D"; BOT="U0BOTDESK"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; TH="$T/threads"; mkdir -p "$TH" "$T/root/.fable-team"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:300}"; fail=$((fail+1)); }
mkdir -p "$T/bin0"; cp -R "$BIN/." "$T/bin0/"
printf '#!/usr/bin/env python3\nimport os,sys\np=os.path.join(os.environ["THREADS"], os.environ["FT_SLACK_TS"]+".json")\nos.path.exists(p) or sys.exit(9)\nsys.stdout.write(open(p, encoding="utf-8").read())\n' > "$T/stub"; chmod +x "$T/stub"
cat > "$T/mk.py" <<'MKPY'
import json, sys
ts, d = sys.argv[1], sys.argv[2]
msgs = []
for line in sys.stdin.read().split("\n"):
    if line.strip():
        t, u, x = line.split("|", 2)
        msgs.append({"ts": t, "user": u, "text": x.replace("\\n", "\n"), **({"thread_ts": ts} if msgs else {})})
body = json.dumps({"ok": True, "messages": msgs}, ensure_ascii=False)
for m in msgs:
    open(d + "/" + m["ts"] + ".json", "w", encoding="utf-8").write(body)
MKPY
A=1111111111111111111111111111111111111111; B=2222222222222222222222222222222222222222
Q=1794695900.000001; D=1794695950.000002; O=1794695970.720349
th() { python3 "$T/mk.py" "$Q" "$TH" <<EOF
$Q|$BOT|${1:-[질문 · 팩 PR main 병합] yoonhwan 오빠, 병합해도 될까요?\n- head $A}
$D|$BOT|$2
$O|$OPPA|네
EOF
}
chk() { OUT="$(THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" timeout 20 python3 "$1/ft_oppa_slack_check.py" "$Q" "$A" 2>&1)"; RC=$?; }
LED="$T/led.jsonl"
reg() { rm -f "$LED"; OUT="$( ( cd "$T/root" && THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" FT_ROOT="$T/root" FT_NOW=1794695900 FT_DESK_REPLY_LEDGER="$LED" \
          timeout 30 python3 "$1/ft_desk_reply_wake.py" --register "$Q" h77 "$A" ) 2>&1 )"; RC=$?; }
nled() { [ -s "$LED" ] && wc -l < "$LED" | tr -d ' ' || echo 0; }
t1() { th "" "[멈춤] 병합 도구 점검 중 — 잠시 멈춥니다"; chk "$1"; }
t3() { th "" "새 질문: 설계 승인 부탁드립니다"; chk "$1"; }
t4() { th "[질문 · 팩 PR main 병합] head 를 안 적은 질문" "[알림] x"; reg "$1"; }
case1() {  # case1 <bin> — T1~T6
  t1 "$1"; { [ "$RC" = 0 ] && [ "$OUT" = "SLACK-OK $A parent=$Q reply=$O" ]; } && ok "T1 [멈춤] 덧글 뒤 «네» → SLACK-OK rc0" || bad "T1" "rc=$RC out=$OUT"
  for h in "[정리] 브랜치 정리 끝" "  [알림] 다음 단계 대기"; do th "" "$h"; chk "$1"
    [ "$RC" = 0 ] && ok "T1b «${h:0:8}» 덧글 뒤 «네» → SLACK-OK" || bad "T1b ${h:0:8}" "rc=$RC out=$OUT"; done
  th "" "[멈춤] 다른 건 head $B"; chk "$1"
  [ "$RC" = 2 ] && ok "T2 다른 head 40hex 덧글([멈춤] 머리라도) → REJECT rc2" || bad "T2" "rc=$RC out=$OUT"
  th "" "다른 건 head $B"; chk "$1"
  [ "$RC" = 2 ] && ok "T2b 다른 head 40hex 덧글 → REJECT rc2" || bad "T2b" "rc=$RC out=$OUT"
  t3 "$1"; [ "$RC" = 2 ] && ok "T3 머리 없는 40hex 0 글(새 질문 꼴) → REJECT rc2" || bad "T3" "rc=$RC out=$OUT"
  th "" "설명 줄\n[멈춤] 둘째 줄 머리"; chk "$1"
  [ "$RC" = 2 ] && ok "T3b 머리가 첫 줄 아님 → REJECT rc2" || bad "T3b" "rc=$RC out=$OUT"
  t4 "$1"; { [ "$RC" = 3 ] && [ "$(nled)" = 0 ] && case "$OUT" in *"등록 거절: 질문 글에 head 없음"*) true;; *) false;; esac; } \
    && ok "T4 head 없는 질문 글 등록 → rc3 · 장부 0" || bad "T4" "rc=$RC led=$(nled) out=$OUT"
  th "" "[알림] x"; reg "$1"; { [ "$RC" = 0 ] && [ "$(nled)" = 1 ]; } && ok "T5 head 있는 질문 글 등록 → rc0 · 장부 1줄" || bad "T5" "rc=$RC led=$(nled) out=$OUT"
  rm -f "$TH"/*.json; reg "$1"; { [ "$RC" = 2 ] && [ "$(nled)" = 0 ]; } && ok "T6 조회 실패 → rc2 판정 불가 · 장부 0" || bad "T6" "rc=$RC led=$(nled) out=$OUT"
}
case1 "$BIN"
mut() {  # mut <이름> <파일> <옛> <새> — 깨끗한 사본에 변이 1개
  R="$T/run-$1"; rm -rf "$R"; cp -R "$T/bin0" "$R"; python3 - "$R/$2" "$3" "$4" <<'PY'
import pathlib, sys
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]; s = p.read_text()
assert s.count(old) == 1, old
p.write_text(s.replace(old, new, 1))
PY
  [ $? = 0 ] || { bad "$1 변이 적용 실패" ""; return 1; }; }
mut M1 ft_oppa_slack_check.py " and not status_note(txt)" "" && t1 "$R" && [ "$RC" = 2 ] && ok "M1 허용 목록 검사 삭제 → T1 REJECT(변이 잡힘)" || bad "M1 안 잡힘" "rc=$RC out=$OUT"
mut M2 ft_oppa_slack_check.py " and not status_note(txt)" " and bool(HEX40.search(txt))" && t3 "$R" && [ "$RC" = 0 ] && ok "M2 ⓓ 를 잇는다로 → T3 SLACK-OK(변이 잡힘)" || bad "M2 안 잡힘" "rc=$RC out=$OUT"
mut M3 ft_desk_reply_wake.py "if (rc := head_seen(" "if False and (rc := head_seen(" && t4 "$R" && [ "$RC" = 0 ] && ok "M3 등록 검사 삭제 → T4 rc0(변이 잡힘)" || bad "M3 안 잡힘" "rc=$RC out=$OUT"
for f in ft_oppa_slack_check.py ft_desk_reply_wake.py; do
  cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && ok "bin·kit 사본 같음 $f" || bad "kit 사본 다름 $f" ""; done
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
