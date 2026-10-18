#!/usr/bin/env bash
# test_board_publish_tick.sh — ft-board-publish.sh FT_BOARD_ONLY_CHANGED=1 (v555 · 판정 555 ② · 558 ③ ⓐ).
# 실제 슬랙 호출 0: 가짜 슬랙 API(127.0.0.1 임시 포트) + 호출을 세는 가짜 ft-board.py + 임시 FT_ROOT·장부.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
PUB="$ROOT/harness/bin/ft-board-publish.sh"
TP="$ROOT/harness/kit/slack-mirror/byz_thread_post.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/ft" "$T/stub"
LOG="$T/slack.log"; CALLS="$T/calls"; : > "$LOG"; : > "$CALLS"

# 가짜 슬랙 API — 한 줄 = METHOD|channel|ts|thread_ts. $T/fail_reply 가 있으면 스레드 답글만 ok=false.
python3 - "$T" <<'PY' &
import http.server, json, os, sys
T = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    n = 0
    def do_POST(self):
        p = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        m = self.path.rsplit("/", 1)[-1]
        if m == "chat.postMessage" and p.get("thread_ts") and os.path.exists(f"{T}/fail_reply"):
            out = {"ok": False, "error": "stub_reply_failed"}
        else:
            H.n += 1
            out = {"ok": True, "ts": p.get("ts") or f"1700000000.{H.n:06d}"}
            with open(f"{T}/slack.log", "a") as f:
                f.write(f"{m}|{p.get('channel')}|{out['ts']}|{p.get('thread_ts', '')}\n")
        b = json.dumps(out).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(f"{T}/port", "w").write(str(s.server_port))
s.serve_forever()
PY
SRV=$!
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
[ -s "$T/port" ] && ok "가짜 슬랙 기동" || { bad "가짜 슬랙 기동 실패"; exit 1; }

printf 'YOONHWAN_BOT_TOKEN=stub-token\n' > "$T/token.env"
cat > "$T/stub/fake-board" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"
echo "$*" >> "$D/../calls"
case "$1" in
  snapshot) cat "$D/snap.json" ;;
  render)   cat "$D/body.txt" ;;
  prune)    [ -f "$D/../prune_fail" ] && exit 9; exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$T/stub/fake-board"

export FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/fake-board" FT_THREAD_POST="$TP" FT_BOARD_LEDGER="$T/ledger.json"
export FT_BOARD_POST_ARGS="--slack-base http://127.0.0.1:$(cat "$T/port") --token-file $T/token.env"
python3 "$TP" --init --ledger "$T/ledger.json" >/dev/null || { bad "장부 init"; exit 1; }

snap() { printf '%s' "$1" > "$T/stub/snap.json"; }
# mkbody <라벨> <정지 분> <머리 시각> — render --slack 꼴 5절 본문. 정지 분·머리 시각만 바꿔 «분 숫자만 다름» 을 만든다
mkbody() { python3 - "$1" "$2" "$3" > "$T/stub/body.txt" <<'PY2'
import sys
lab, m, ht = sys.argv[1], sys.argv[2], sys.argv[3]
L = [f"[상태] 메인팀 보드 {ht}", "결정 자리: 없음", "", "*⓪ 팀 요약*",
     f"- 팀1 | 지금: 진행 1(카드 {lab}) ⚠정지 {m}분(턴 끝 09:56) | 큐: 대기 2 | 오빠 할 일 0",
     "", "*① 완성 트리*", "트리 줄", "", "*② 세션 트리*", "세션 줄", "", "*③ 큐*", "큐 줄", "", "*④ 오늘 판정표*", f"판정 줄 {lab}"]
print("\n".join(L))
PY2
}
cnt()    { grep -c "$1" "$CALLS" || true; }        # 가짜 보드 호출 수
upd()    { grep -c '^chat.update|' "$LOG" || true; } # 슬랙 update 호출 수
publish() { bash "$PUB" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
SDIR="$T/ft/.fable-team/state/board"
D1="2026-10-09T10:00:00"; D2="2026-10-10T09:00:00"
export FT_BOARD_ONLY_CHANGED=1 FT_BOARD_NOW="$D1"
NOCH='{"snap":"aaaa1111→aaaa1111","prev":"aaaa1111","changes":[],"prev_day_last":null}'

# ⓕ·ⓖ 날짜 첫 발행 = 「다름」 → snapshot 1 + 뿌리 글 1 + prune --days 7 1회
snap "$NOCH"; mkbody A 4 10:00
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^snapshot')" = 1 ] && [ "$(upd)" = 0 ] && [ "$(grep -c '^chat.postMessage|[^|]*|[^|]*|$' "$LOG")" = 1 ] \
  && [ "$(cnt '^prune --days 7$')" = 1 ] && ok "ⓕ 날짜 첫 발행 → 다름(snapshot 1 · 뿌리 글 1) · ⓖ prune --days 7 1회" || bad "ⓕⓖ 첫 발행 rc=$rc calls=$(tr '\n' ',' < "$CALLS") $(cat "$T/err.txt")"

# ⓐ 같은 본문 2회째 → snapshot·슬랙·prune 0 · rc 0 · 「변화 없음」
s0="$(cnt '^snapshot')"; l0="$(wc -l < "$LOG" | tr -d ' ')"
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^snapshot')" = "$s0" ] && [ "$(wc -l < "$LOG" | tr -d ' ')" = "$l0" ] && grep -q '변화 없음' "$T/out.txt" \
  && ok "ⓐ 같은 본문 → snapshot 0 · update 0 · rc 0 · 변화 없음" || bad "ⓐ rc=$rc calls=$(tr '\n' ',' < "$CALLS")"

# ⓑ 머리 시각·정지 분 숫자만 다름 → 호출 0
mkbody A 9 10:05
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^snapshot')" = "$s0" ] && [ "$(wc -l < "$LOG" | tr -d ' ')" = "$l0" ] && grep -q '변화 없음' "$T/out.txt" \
  && ok "ⓑ 머리 시각·정지 N분 숫자만 다름 → 호출 0" || bad "ⓑ rc=$rc"

# ⓒ 카드 상태 1개 다름 → snapshot 1 + update 1
snap '{"snap":"aaaa1111→bbbb2222","prev":"aaaa1111","changes":["카드 x 진행→완성"],"prev_day_last":null}'; mkbody B 9 10:10
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^snapshot')" = $((s0+1)) ] && [ "$(upd)" = 1 ] \
  && ok "ⓒ 카드 1개 다름 → snapshot 1 + update 1" || bad "ⓒ rc=$rc upd=$(upd) calls=$(tr '\n' ',' < "$CALLS")"

# ⓓ 답글 실패(rc 3) → reply_pending 표식 → 다음 틱은 본문 같아도 update 1회 → rc 0 이면 표식 삭제 → 그 다음 틱은 0
touch "$T/fail_reply"
snap '{"snap":"bbbb2222→cccc3333","prev":"bbbb2222","changes":["판정 5 new"],"prev_day_last":null}'; mkbody C 9 10:15
rc="$(publish)"
[ "$rc" = 3 ] && [ -f "$SDIR/2026-10-09/reply_pending" ] && ok "ⓓ update 성공·답글 실패 → rc 3 + reply_pending 표식" || bad "ⓓ-1 rc=$rc"
rm -f "$T/fail_reply"; u0="$(upd)"
snap '{"snap":"cccc3333→cccc3333","prev":"cccc3333","changes":[],"prev_day_last":null}'
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(upd)" = $((u0+1)) ] && [ ! -f "$SDIR/2026-10-09/reply_pending" ] \
  && ok "ⓓ 표식 있으면 본문 같아도 update 1회 → rc 0 → 표식 삭제" || bad "ⓓ-2 rc=$rc upd=$(upd)"
u0="$(upd)"; rc="$(publish)"
[ "$rc" = 0 ] && [ "$(upd)" = "$u0" ] && ok "ⓓ 표식 삭제 뒤 같은 본문 → 호출 0" || bad "ⓓ-3 rc=$rc"

# ⓖ 다음 날 첫 발행 + prune 실패 주입 → 발행 rc 불변 · 기록 1줄 · 같은 날 2번째 발행 → prune 0
export FT_BOARD_NOW="$D2"; touch "$T/prune_fail"; p0="$(cnt '^prune')"
snap "$NOCH"; mkbody D 1 09:00
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^prune')" = $((p0+1)) ] && [ "$(grep -c 'prune 실패' "$T/err.txt")" = 1 ] \
  && ok "ⓖ prune 실패 주입 → 발행 rc 0 불변 + 기록 1줄" || bad "ⓖ-1 rc=$rc err=$(cat "$T/err.txt")"
rm -f "$T/prune_fail"; mkbody E 1 09:05
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^prune')" = $((p0+1)) ] && ok "ⓖ 같은 날 2번째 발행 → prune 0" || bad "ⓖ-2 rc=$rc prune=$(cnt '^prune')"

# ⓔ ONLY_CHANGED 미설정 → 같은 본문이어도 지금처럼 snapshot + update (수동 발행 동작 불변) · prune 호출 0
unset FT_BOARD_ONLY_CHANGED; s0="$(cnt '^snapshot')"; u0="$(upd)"; p0="$(cnt '^prune')"
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(cnt '^snapshot')" = $((s0+1)) ] && [ "$(upd)" = $((u0+1)) ] && [ "$(cnt '^prune')" = "$p0" ] \
  && ok "ⓔ ONLY_CHANGED 미설정 → 같은 본문도 snapshot 1 + update 1 · prune 0" || bad "ⓔ rc=$rc"

# ⓗ launchd 꼴 = /bin/bash(3.2) + FT_BOARD_POST_ARGS·FT_BOARD_LEDGER 미설정 → 빈 POST_ARGS 로도 update 1회 · rc 0 · unbound 0
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
open(os.path.join(os.path.dirname(__file__), "..", "tp_calls"), "a").write(" ".join(sys.argv[1:2]) + "\n")
EOF
export FT_BOARD_NOW="2026-10-11T09:00:00"; export FT_BOARD_ONLY_CHANGED=1; : > "$T/tp_calls"
snap "$NOCH"; mkbody H 1 09:00
run_launchd() { env -u FT_BOARD_POST_ARGS -u FT_BOARD_LEDGER FT_THREAD_POST="$T/stub/tp.py" /bin/bash "$1" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
rc="$(run_launchd "$PUB")"
[ "$rc" = 0 ] && [ "$(grep -c '^update$' "$T/tp_calls")" = 1 ] && ! grep -q unbound "$T/err.txt" \
  && ok "ⓗ /bin/bash + POST_ARGS 미설정 → update 1회 · rc 0 · unbound 0" || bad "ⓗ rc=$rc err=$(cat "$T/err.txt")"
# 변이 대조: 빈 배열 안전 꼴을 되돌리면 ⓗ 가 FAIL(unbound) 해야 한다
mkdir -p "$T/mut"; cp "$ROOT"/harness/bin/ft_board_root.py "$T/mut/"
sed 's/\${POST_ARGS\[@\]+"\${POST_ARGS\[@\]}"}/"${POST_ARGS[@]}"/' "$PUB" > "$T/mut/ft-board-publish.sh"
grep -q 'update "${POST_ARGS\[@\]}"' "$T/mut/ft-board-publish.sh" || bad "변이 파일 생성 실패"
export FT_BOARD_NOW="2026-10-12T09:00:00"; mkbody I 1 09:00; : > "$T/tp_calls"
rc="$(run_launchd "$T/mut/ft-board-publish.sh")"
{ [ "$rc" != 0 ] && grep -q unbound "$T/err.txt"; } && ok "변이 대조: 빈 배열 안전 꼴 되돌리면 ⓗ FAIL (rc=$rc unbound)" || bad "변이 대조: 되돌려도 ⓗ 통과(검사 무력) rc=$rc"

# ⓘ 템플릿 ProgramArguments 첫 값 · env · StartInterval · RunAtLoad
PL="$ROOT/harness/kit/slack-mirror/com.byz.ft-board-publish.plist.template"
python3 - "$PL" <<'PY3' && ok "ⓘ 템플릿: /opt/homebrew/bin/bash · ONLY_CHANGED=1 · StartInterval 300 · RunAtLoad false" || bad "ⓘ 템플릿 값"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
assert d["ProgramArguments"][0] == "/opt/homebrew/bin/bash"
assert d["EnvironmentVariables"]["FT_BOARD_ONLY_CHANGED"] == "1"
assert d["StartInterval"] == 300 and d["RunAtLoad"] is False
PY3

echo "fail=$fail"; [ "$fail" = 0 ]
