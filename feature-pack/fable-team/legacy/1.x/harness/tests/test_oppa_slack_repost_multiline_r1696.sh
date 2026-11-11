#!/usr/bin/env bash
# test_oppa_slack_repost_multiline_r1696.sh — r1696: 오빠 승인 답을 «같은 sha 를 다시 물은 글» 뒤에도, 첫 줄이 승인이고 뒤에 설명 줄이 붙어도 받는다.
#   ⓐ 재게시(같은 sha 담은 다음 글) 뒤 답 · ⓑ 다른 sha 질문 뒤 답 막음 · ⓒ 40hex 없는 같은 작성자 글은 지금처럼 창을 끊음 · ⓒ2 이 sha 담은 독촉 글은 잇음
#   ⓓ «예\n\n설명»·«예 / 이건 다음에» 승인
#   ⓔ «예\n근데 보류» 거절 · ⓕ «잠깐\n예»·«네? 왜요» 판정 불가 · ⓕ2 붙은 «/»(«네/아니오»·«예/보류»·«네 /보류») = 승인 0 rc2(DA R1) · ⓖ 질문 수정 뒤 답 막음 · ⓗ --reply-only 같은 창 · ⓙ 실사건 스레드 5글 재생
#   변이(사본에서만): M1 창 끝=다음 글(sha 무시) → ⓐ·ⓒ2 FAIL · M1b 40hex 없는 글도 안 끊음 → ⓒ FAIL · M2 «아무 40hex» → ⓑ FAIL · M3 마지막 조각 판정 → ⓓ·ⓕ FAIL · M4 거절=첫 조각만 → ⓔ FAIL
# 스텁 스레드만(FT_SLACK_REPLIES_CMD) · 실 Slack·토큰·게시 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
CHK="${FT_CHK_PATH:-$REPO/harness/bin/ft_oppa_slack_check.py}"; OPPA="U0AC2JF0M7D"; BOT="U0BOTDESK"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; TH="$T/threads"; mkdir -p "$TH"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:300}"; fail=$((fail+1)); }
expect() {  # expect <ok|rej|un|no> <라벨> — $OUT/$RC 판정
  case "$1" in
    ok)  case "$OUT" in "SLACK-OK"*) ok "$2";; *) bad "$2" "rc=$RC out=$OUT";; esac;;
    rej) { [ "$RC" = 2 ] && case "$OUT" in *"거절 답글"*) true;; *) false;; esac; } && ok "$2" || bad "$2" "rc=$RC out=$OUT";;
    un)  { [ "$RC" = 2 ] && case "$OUT" in *"판정 불가"*) true;; *) false;; esac; } && ok "$2" || bad "$2" "rc=$RC out=$OUT";;
    no)  { [ "$RC" != 0 ]; } && ok "$2" || bad "$2" "rc=$RC out=$OUT";;
  esac; }
printf '#!/usr/bin/env python3\nimport os,sys\nsys.stdout.write(open(os.path.join(os.environ["THREADS"], os.environ["FT_SLACK_TS"]+".json"), encoding="utf-8").read())\n' > "$T/stub"; chmod +x "$T/stub"
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
        m["thread_ts"] = ts   # 실 Slack 꼴 — 스레드 답글은 thread_ts 를 갖는다
    msgs.append(m)
body = json.dumps({"ok": True, "messages": msgs}, ensure_ascii=False)
open(out, "w", encoding="utf-8").write(body)
for m in msgs:   # conversations.replies 는 어느 글 ts 로 물어도 같은 스레드를 준다
    open(out.rsplit("/", 1)[0] + "/" + m["ts"] + ".json", "w", encoding="utf-8").write(body)
MKPY
thread() { python3 "$T/mk.py" "$1" "$TH/$1.json"; }   # thread <질문 ts> — stdin 한 줄 = "ts|user|text"
run() { OUT="$(THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" timeout 20 python3 "${CHKP:-$CHK}" "$@" 2>&1)"; RC=$?; }
A=1111111111111111111111111111111111111111; B=2222222222222222222222222222222222222222
T1=1794393905.746509; Q1=1794394100.000001; O1=1794394200.000002
th() { thread "$T1" <<EOF
$T1|$BOT|[질문] PR main 병합 승인? head $A
${2:-$Q1}|$BOT|${3:-[질문 · 다시 여쭘] 같은 건 · head $A}
${4:-$O1}|$OPPA|${5:-네}
EOF
}
# ⓐ 재게시 뒤 답
th; run "$T1" "$A"
{ [ "$RC" = 0 ] && [ "$OUT" = "SLACK-OK $A parent=$T1 reply=$O1" ]; } && ok "ⓐ 재게시 Q2(sha A) 뒤 «네» → SLACK-OK reply=$O1" || bad "ⓐ" "rc=$RC out=$OUT"
# ⓑ 다른 sha 질문 뒤 답은 이 sha 의 답이 아니다(그 sha 에는 답이다)
th "$T1" "$Q1" "[질문 · 다시 여쭘] 다른 건 · head $B"
run "$T1" "$A"; expect no "ⓑ A 는 REJECT rc2(다른 sha 질문 뒤 답)"
run "$Q1" "$B"; expect ok "ⓑ Q2 의 B 는 SLACK-OK"
# ⓒ 40hex 없는 같은 작성자 글은 지금처럼 창을 끊는다(계약 (b) 판정) · ⓒ2 이 sha 를 담은 독촉·재게시는 잇는다
th "$T1" "$Q1" "4. 다음 질문(40hex 없음)"
run "$T1" "$A"; expect no "ⓒ 40hex 없는 같은 작성자 글 → REJECT(지금과 같다)"
th "$T1" "$Q1" "재게시 · 독촉 — head $A 확인 부탁"
run "$T1" "$A"; expect ok "ⓒ2 이 sha 담은 독촉 글은 창을 잇는다 → SLACK-OK"
# ⓓ 여러 줄 승인 · ⓔ 거절 섞임 · ⓕ 첫 줄 승인 아님
while IFS='|' read -r txt want; do
  th "$T1" "$Q1" "[질문] head $A" "$O1" "$txt"; run "$T1" "$A"
  expect "$want" "$want «${txt:0:14}»"
done <<'TBL'
예\n\n헤드는 안꼬이게 메인을 서로 올릴수있도록 이제 플랜팀에서|ok
예 / 이건 다음에|ok
예\n근데 보류|rej
잠깐\n예|un
네? 왜요|un
네/아니오|un
예/보류|un
네 /보류|un
TBL
# ⓖ 질문이 수정된 뒤의 답은 지금처럼 막는다
th; python3 - "$TH/$T1.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8")); d["messages"][0]["edited"] = {"ts": "1794394500.000009"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
run "$T1" "$A"; expect no "ⓖ 질문 수정 뒤 답 → REJECT(지금과 같다)"
# ⓗ --reply-only 같은 창 · 답 없음 rc3
th; run --reply-only "$T1"
{ [ "$RC" = 0 ] && [ "$OUT" = "REPLY-SEEN parent=$T1 reply=$O1" ]; } && ok "ⓗ --reply-only 재게시 뒤 답 → REPLY-SEEN rc0" || bad "ⓗ" "rc=$RC out=$OUT"
thread "$T1" <<EOF
$T1|$BOT|[질문] head $A
EOF
run --reply-only "$T1"; { [ "$RC" = 3 ]; } && ok "ⓗ 답 없음 → rc3(지금과 같다)" || bad "ⓗ-2" "rc=$RC out=$OUT"
# ⓙ 실사건 재생 — 스레드 1794393905.746509 5글(ts·글쓴이·본문 그대로)
SHA_R=d97fd14c447d61f4902993a2a128cee75a546c79; R_REPLY=1794394093.477089
thread 1794393905.746509 <<EOF
1794393905.746509|U0BOTDESK|[질문 · 팩 PR 930 main 병합] yoonhwan 오빠, 병합 도구가 대상 브랜치마다 기준 head 를 따로 보게 하는 수정을 main 에 병합해도 될까요?\n- head $SHA_R\n이 글 스레드에 «네» 또는 «아니오» 로 답해 주세요.
1794394093.477089|$OPPA|예\n\n헤드는 안꼬이게 메인을 서로 올릴수있도록 이제 플랜팀에서\n각 팀장들이 웨크트리와.브랜치를 관리 지원 이것도 2.0.0의 메인축으로 있다
1794394185.783869|U0BOTDESK|오빠, 말씀 감사합니다. 뒤의 운영 지시는 planner 에 그대로 전했습니다. 승인 확인 도구는 한 단어 답만 승인으로 읽습니다
1794394242.162919|$OPPA|네
1794394246.893799|U0BOTDESK|담당 planner · Issue #8363 (워크트리·브랜치 관리 지원)
EOF
run 1794393905.746509 "$SHA_R"
{ [ "$RC" = 0 ] && [ "$OUT" = "SLACK-OK $SHA_R parent=1794393905.746509 reply=$R_REPLY" ]; } \
  && ok "ⓙ 실사건 재생 → SLACK-OK reply=$R_REPLY" || bad "ⓙ" "rc=$RC out=$OUT"
python3 - "$TH/1794393905.746509.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8")); d["messages"][1]["text"] = "아니오\n\n헤드는 안꼬이게 메인을 서로 올릴수있도록"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
run 1794393905.746509 "$SHA_R"; expect rej "ⓙ 첫 답을 «아니오\n…» 로 바꾸면 REJECT 거절 답글"
# ── 변이 M1~M4 (사본에서만 · 변이마다 깨끗한 사본을 새 폴더에)
MX="$T/mx"; mkdir -p "$MX"; cp -R "$(dirname -- "$CHK")/." "$MX/"
mut() {
  R="$T/run-$1"; rm -rf "$R"; cp -R "$MX" "$R"; CHKP="$R/$(basename -- "$CHK")"; python3 - "$CHKP" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); kind = sys.argv[2]
def sub(old, new):
    global s
    assert s.count(old) == 1, old[:40]
    s = s.replace(old, new, 1)
MUTS = {
    "M1":  ("not has_sha(txt, sha)", "True"),                       # 창 끝 = 무조건 다음 글(sha 무시) → ⓐ·ⓒ2 FAIL
    "M1b": ("not has_sha(txt, sha)", "False"),                      # 40hex 없는 글도 안 끊음(이전 판) → ⓒ FAIL
    "M2":  ("not has_sha(txt, sha)", "not HEX40.search(txt)"),      # «아무 40hex» 면 이 sha 로 봄 → ⓑ FAIL
    "M3":  ('    for chunk in re.split(r"[\\r\\n]+|\\s+/\\s+", t):', '    for chunk in list(reversed([c for c in re.split(r"[\\r\\n]+|\\s+/\\s+", t)])):'),
    "M4":  ("no = [t for t, ws, _ in said if REJECT_WORDS.intersection(ws)]", "no = [t for t, _, fc in said if REJECT_WORDS.intersection(fc)]"),
    "M5":  ('re.split(r"[\\r\\n]+|\\s+/\\s+", t)', 're.split(r"[\\r\\n]+|/", t)'),
}
sub(*MUTS[kind]); p.write_text(s)
PY
}
mut M1; th; run "$T1" "$A"; expect no "M1 창 끝=다음 글(sha 무시) → ⓐ REJECT(변이 잡힘)"
th "$T1" "$Q1" "재게시 · 독촉 — head $A 확인 부탁"; run "$T1" "$A"; expect no "M1 → ⓒ2 REJECT(변이 잡힘)"
mut M1b; th "$T1" "$Q1" "4. 다음 질문(40hex 없음)"; run "$T1" "$A"; expect ok "M1b 40hex 없는 글도 안 끊음 → ⓒ SLACK-OK(변이 잡힘)"
mut M2; th "$T1" "$Q1" "[질문 · 다시 여쭘] 다른 건 · head $B"; run "$T1" "$A"; expect ok "M2 «아무 40hex 면 이 sha» → ⓑ SLACK-OK(변이 잡힘)"
mut M3; th "$T1" "$Q1" "[질문] head $A" "$O1" '예 / 이건 다음에'; run "$T1" "$A"; expect no "M3 마지막 조각 판정 → ⓓ REJECT(변이 잡힘)"
th "$T1" "$Q1" "[질문] head $A" "$O1" '잠깐\n예'; run "$T1" "$A"; expect ok "M3 마지막 조각 판정 → ⓕ SLACK-OK(변이 잡힘)"
mut M4; th "$T1" "$Q1" "[질문] head $A" "$O1" '예\n근데 보류'; run "$T1" "$A"; expect ok "M4 거절=첫 조각만 → ⓔ SLACK-OK(변이 잡힘)"
mut M5; th "$T1" "$Q1" "[질문] head $A" "$O1" '네/아니오'; run "$T1" "$A"; expect ok "M5 조각 경계=아무 «/» → ⓕ2 SLACK-OK(변이 잡힘)"
cmp -s "$REPO/harness/bin/ft_oppa_slack_check.py" "$REPO/harness/kit/fable-team/bin/ft_oppa_slack_check.py" \
  && ok "ⓘ bin·kit 사본 cmp 0" || bad "ⓘ" "bin·kit 다름"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
