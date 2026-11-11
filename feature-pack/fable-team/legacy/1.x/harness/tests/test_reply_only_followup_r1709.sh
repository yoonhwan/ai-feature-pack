#!/usr/bin/env bash
# test_reply_only_followup_r1709.sh — r1709: 승인 없는 «질문» 감시(--reply-only)는 질문 뒤 같은 스레드 desk 정정·보충 글에 창이 끊기지 않는다.
#   ① 질문(bot) → 정정(bot·40hex 없음) → 오빠 «네» → --reply-only = REPLY-SEEN reply=<오빠 글> rc0 (기준판 = REPLY-NONE rc3)
#   ② 질문 → 오빠 «네» → 정정 → REPLY-SEEN = «가장 이른» 답   ③ 질문 → 정정 → 답 없음 → rc3
#   ④ 승인 길(질문 글에 sha)은 지금처럼 거절(창 규칙 한 글자도 안 바뀜)   ⑤ 회귀 4파일 FAIL 줄 앞 판과 같다
#   변이 W1~W3 + 변이마다 원본 대조 · 스텁 스레드만(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · sleep 0 · 70초 안
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
CHK="${R1709_CHK:-$REPO/harness/bin/ft_oppa_slack_check.py}"; KIT="$REPO/harness/kit/fable-team/bin"
OPPA="U0AC2JF0M7D"; BOT="U0BOTDESK"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; TH="$T/threads"; mkdir -p "$TH"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1 :: ${2:-}"; fail=$((fail+1)); }
printf '#!/usr/bin/env python3\nimport os,sys\nsys.stdout.write(open(os.path.join(os.environ["THREADS"], os.environ["FT_SLACK_TS"]+".json"), encoding="utf-8").read())\n' > "$T/stub"; chmod 755 "$T/stub"
cat > "$T/mk.py" <<'MKPY'
import json, sys
ts, out = sys.argv[1], sys.argv[2]
msgs = []
for line in sys.stdin.read().split("\n"):
    if not line.strip():
        continue
    t, u, x = line.split("|", 2)
    m = {"ts": t, "user": u, "text": x.replace("\\n", "\n")}
    if msgs:
        m["thread_ts"] = ts
    msgs.append(m)
body = json.dumps({"ok": True, "messages": msgs}, ensure_ascii=False)
open(out, "w", encoding="utf-8").write(body)
for m in msgs:
    open(out.rsplit("/", 1)[0] + "/" + m["ts"] + ".json", "w", encoding="utf-8").write(body)
MKPY
thread(){ python3 "$T/mk.py" "$1" "$TH/$1.json"; }
run(){ OUT="$(THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" timeout 20 python3 "$1" "${@:2}" 2>&1)"; RC=$?; }
A=1111111111111111111111111111111111111111
Q=1794397642.291969; C=1794400000.000001; O=1794400001.000002
# ① 사건 ② 재생: 질문 → 정정(40hex 없음) → 오빠 «네»
thread "$Q" <<EOF
$Q|$BOT|[질문 · 이슈 등록 컨펌] nano-spawn 테스트 이슈
$C|$BOT|정정: 위 글의 «아직 확인되지 않은 내용이에요»
$O|$OPPA|네
EOF
run "$CHK" --reply-only "$Q"
{ [ "$RC" = 0 ] && [ "$OUT" = "REPLY-SEEN parent=$Q reply=$O" ]; } && ok "① 정정 글 뒤 오빠 답 → REPLY-SEEN rc0" || bad "① rc=$RC out=$OUT"
# ② 질문 → 오빠 «네» → 정정 → 가장 이른 답
O2=1794400002.000003
thread "$Q" <<EOF
$Q|$BOT|[질문] 이슈 등록 컨펌
$O|$OPPA|네
$O2|$BOT|정정: 보충 설명
EOF
run "$CHK" --reply-only "$Q"
{ [ "$RC" = 0 ] && [ "$OUT" = "REPLY-SEEN parent=$Q reply=$O" ]; } && ok "② 정정이 답 뒤에 와도 «가장 이른 답» = $O" || bad "② rc=$RC out=$OUT"
# ③ 질문 → 정정 → 답 없음 → rc3
thread "$Q" <<EOF
$Q|$BOT|[질문] 이슈 등록 컨펌
$C|$BOT|정정: 보충 설명
EOF
run "$CHK" --reply-only "$Q"
{ [ "$RC" = 3 ] && [[ "$OUT" == *"REPLY-NONE"* ]]; } && ok "③ 답 없음 → REPLY-NONE rc3" || bad "③ rc=$RC out=$OUT"
# ④ 승인 길(질문 글에 sha A) — 창 규칙 그대로: 정정이 창을 끊어 거절
thread "$Q" <<EOF
$Q|$BOT|[질문] PR 승인? head $A
$C|$BOT|정정: 위 글의 head 는 확인 안 된 값
$O|$OPPA|네
EOF
run "$CHK" "$Q" "$A"
{ [ "$RC" != 0 ] && [[ "$OUT" != SLACK-OK* ]]; } && ok "④ 승인 길은 지금처럼 거절(창 규칙 불변) rc=$RC" || bad "④ rc=$RC out=$OUT"
T4="test_oppa_slack_repost_multiline_r1696.sh test_oppa_slack_reply_words_r1606.sh test_desk_reply_wake_question_r1591.sh test_hil_oppa_thread_r1275.sh"
# ⑤ 회귀 4파일 — «SKIP»(PASS 0 · 하드 룰 22: 시험 1개 70초 밖) · 보고에서 파일마다 따로 돌린다
echo "SKIP ⑤ 회귀 4파일 — 파일마다 따로(보고): $T4"
for f in ft_oppa_slack_check.py; do cmp -s "$REPO/harness/bin/$f" "$KIT/$f" && ok "⑤ bin·kit cmp 0 $f" || bad "⑤ bin·kit 불일치 $f"; done
# 변이 3종(사본에서만 · 변이마다 원본 대조)
mkx(){ local d="$T/w-$1"; mkdir -p "$d"; cp "$REPO/harness/bin/ft_oppa_slack_check.py" "$d/"
  python3 - "$d/ft_oppa_slack_check.py" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:70]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s\n' "$d/ft_oppa_slack_check.py"; }
thread "$Q" <<EOF
$Q|$BOT|[질문 · 이슈 등록 컨펌] nano-spawn
$C|$BOT|정정: 보충
$O|$OPPA|네
EOF
X="$(mkx w1 'brk = [] if not sha else [x for x, txt in mine if x > parent and not has_sha(txt, sha)]' 'brk = [x for x, txt in mine if x > parent and not has_sha(txt, sha)]')"
run "$X" --reply-only "$Q"; r1="$RC"; o1="$OUT"; run "$CHK" --reply-only "$Q"; r2="$RC"; o2="$OUT"
{ [ "$r1" = 3 ] && [ "$r2" = 0 ] && [[ "$o2" == REPLY-SEEN* ]]; } && ok "W1 reply-only 창 넓힘 삭제 → ① FAIL(원본은 rc0 · 대조)" || bad "W1 검출 실패 rc=${RC} «${OUT}»"
thread "$Q" <<EOF
$Q|$BOT|[질문] PR 승인? head $A
$C|$BOT|정정: head 는 미확인
$O|$OPPA|네
EOF
X="$(mkx w2 'nxt = brk[0] if brk else None' 'nxt = None')"   # 창을 안 끊는다(승인 길에도 적용되는 변이)
run "$X" "$Q" "$A"; r1="$RC"; o1="$OUT"; run "$CHK" "$Q" "$A"; r2="$RC"; o2="$OUT"
{ [ "$r1" = 0 ] && [ "$r2" != 0 ]; } && ok "W2 창 넓힘을 승인 길에도 → ④ FAIL(원본은 거절 · 대조)" || bad "W2 검출 실패 r1=${r1} o1=«${o1}» r2=${r2}"
O3=1794400003.000004
thread "$Q" <<EOF
$Q|$BOT|[질문] 이슈 등록 컨펌
$O|$OPPA|네
$O3|$OPPA|네, 좋아요
EOF
X="$(mkx w3 'out.append("REPLY-SEEN parent=%s reply=%s" % (ts, ok[0][0]))' 'out.append("REPLY-SEEN parent=%s reply=%s" % (ts, ok[-1][0]))')"
run "$X" --reply-only "$Q"; o1="$OUT"; run "$CHK" --reply-only "$Q"; o2="$OUT"
{ [[ "$o1" == *"reply=$O3"* ]] && [[ "$o2" == *"reply=$O"* ]] && [[ "$o2" != *"reply=$O3"* ]]; } \
  && ok "W3 «마지막 답» 으로 바꿈 → ② FAIL(원본은 가장 이른 답 · 대조)" || bad "W3 검출 실패 «${o1}» / «${o2}»"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
