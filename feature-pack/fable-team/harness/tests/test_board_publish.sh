#!/usr/bin/env bash
# test_board_publish.sh — ft-board-publish.sh + byz_thread_post update (v423a · 판정 421·423·430·431).
# 실제 슬랙·claude 호출 0: 가짜 슬랙 API(127.0.0.1 임시 포트) + 가짜 ft-board.py(snapshot rc/출력 고정) + 임시 FT_ROOT·장부.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
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
mkdir -p "$T/ft/.fable-team" "$T/stub"   # r455a: R231a 교정 2 — 명부 폴더 없음 = raise · 폴더만 두면 명부 0 = 사람 채널 ∅
LOG="$T/slack.log"; : > "$LOG"

# 가짜 슬랙 API — chat.postMessage / chat.update 만. 한 줄 = METHOD|channel|ts|thread_ts|text 바이트수|text(개행→\n). $T/fail_reply 가 있으면 스레드 답글만 ok=false.
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
                f.write(f"{m}|{p.get('channel')}|{out['ts']}|{p.get('thread_ts', '')}|{len(p['text'].encode())}|{p['text'].replace(chr(10), chr(92) + 'n')}\n")
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
case "$1" in
  snapshot) [ -f "$D/snap_rc" ] && exit "$(cat "$D/snap_rc")"; cat "$D/snap.json" ;;
  render)   cat "$D/body.txt" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$T/stub/fake-board"

export FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/fake-board" FT_THREAD_POST="$TP" FT_BOARD_LEDGER="$T/ledger.json"
export FT_BOARD_POST_ARGS="--slack-base http://127.0.0.1:$(cat "$T/port") --token-file $T/token.env"
python3 "$TP" --init --ledger "$T/ledger.json" >/dev/null || { bad "장부 init"; exit 1; }

snap() { printf '%s' "$1" > "$T/stub/snap.json"; }
# mkbody <라벨> [팀 수] [① 절 채움 바이트] — render --slack 꼴 5절 본문(절 머리 *⓪ ~ *④ )
mkbody() { python3 - "$1" "${2:-2}" "${3:-0}" > "$T/stub/body.txt" <<'PY2'
import sys
lab, n, fill = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
L = ["[상태] 메인팀 보드 10:00", "결정 자리: 없음", "", "*⓪ 팀 요약*"]
L += [f"- 팀{i} | 지금: 진행 1(카드 {lab}) | 큐: 대기 2 | 오빠 할 일 0 | " + "가" * 20 for i in range(1, n + 1)]
L += ["", "*① 완성 트리*"] + [f"트리 줄 {i} " + "나" * 40 for i in range(fill // 60)]
L += ["", "*② 세션 트리*", "세션 줄", "", "*③ 큐*", "큐 줄", "", "*④ 오늘 판정표*", f"판정 줄 {lab}"]
print("\n".join(L))
PY2
}
last_bytes() { tail -1 "$LOG" | awk -F'|' '{print $5}'; }
n_of()  { grep -c "$1" "$LOG" 2>/dev/null || true; }          # 로그에서 패턴 줄 수
publish() { bash "$PUB" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
D1="2026-10-09T10:00:00"; D2="2026-10-10T09:00:00"

bash -n "$PUB" && ok "bash -n" || bad "bash -n"

# 1) snapshot rc≠0 → update 호출 0 · rc 그대로
export FT_BOARD_NOW="$D1"; echo 7 > "$T/stub/snap_rc"; snap '{"snap":"-→aaaa1111","prev":null,"changes":[],"prev_day_last":null}'; mkbody A
rc="$(publish)"
[ "$rc" = 7 ] && [ ! -s "$LOG" ] && ok "snapshot rc≠0 → update 0 (rc=7 그대로 · 슬랙 호출 0)" || bad "snapshot 실패 처리 rc=$rc log=$(wc -l < "$LOG")"
rm -f "$T/stub/snap_rc"

# 2) 날짜 첫 발행 = 뿌리 글 1 · 변화 없음 = 답글 0 / 카드만 바뀜 = update 1 + 답글 1(snap 전→후)
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(n_of '^chat.postMessage|[^|]*|[^|]*||')" = 1 ] && [ "$(n_of '|[^|]*|[^|]*|1700000000\.')" = 0 ] && ok "첫 발행 → 뿌리 글 1 · 답글 0" || bad "첫 발행 rc=$rc: $(cat "$LOG" "$T/err.txt")"
ROOT1="$(awk -F'|' '$1=="chat.postMessage"{print $3; exit}' "$LOG")"
snap '{"snap":"aaaa1111→bbbb2222","prev":"aaaa1111","changes":["카드 harness/v423a 진행→완성"],"prev_day_last":null}'; mkbody B
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(n_of '^chat.update|')" = 1 ] && grep -q "^chat.postMessage|[^|]*|[^|]*|$ROOT1|.*카드 harness/v423a 진행→완성 · snap=aaaa1111→bbbb2222" "$LOG" \
  && ok "카드만 바뀜 → update 1 + 답글 1 (snap 전→후)" || bad "변화 발행 rc=$rc: $(cat "$LOG" "$T/err.txt")"

# 3) 답글 실패 → rc 3 + reply_pending · 다음 발행(입력 해시 같아도)이 «직전 답글 누락 snap=…» 을 함께 낸다
touch "$T/fail_reply"
snap '{"snap":"bbbb2222→cccc3333","prev":"bbbb2222","changes":["판정 5 new"],"prev_day_last":null}'; mkbody C
rc="$(publish)"
grep -q '"reply_pending"' "$T/ledger.json" && [ "$rc" = 3 ] && [ "$(n_of '^chat.update|')" = 2 ] && ok "update 성공 · 답글 실패 → rc 3 + 장부 reply_pending" || bad "답글 실패 처리 rc=$rc: $(cat "$T/err.txt")"
rm -f "$T/fail_reply"
before="$(wc -l < "$LOG" | tr -d ' ')"
snap '{"snap":"cccc3333→cccc3333","prev":"cccc3333","changes":[],"prev_day_last":null}'   # 입력 해시 같음 · 변화 없음
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(( $(wc -l < "$LOG" | tr -d ' ') - before ))" = 2 ] && grep -q "^chat.postMessage|[^|]*|[^|]*|$ROOT1|[0-9]*|직전 답글 누락 — 판정 5 new · snap=bbbb2222→cccc3333" "$LOG" \
  && ! grep -q '"reply_pending"' "$T/ledger.json" && ok "답글 실패 → 다음 발행 누락 snap=bbbb2222→cccc3333 함께 냄(해시 같아도) · pending 해소" || bad "누락 복구 rc=$rc: $(tail -3 "$LOG")"

# 4) 날짜 바뀜 → 오늘 뿌리 글 생성 + 전날 뿌리 글에 동결(update 1회) · 이후 전날 키 갱신 0
export FT_BOARD_NOW="$D2"
snap '{"snap":"-→dddd4444","prev":null,"changes":[],"prev_day_last":"cccc3333"}'; mkbody D
u0="$(n_of "^chat.update|[^|]*|$ROOT1|")"
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(n_of "^chat.update|[^|]*|$ROOT1|")" = $((u0+1)) ] && grep "^chat.update|[^|]*|$ROOT1|" "$LOG" | tail -1 | grep -q '동결 — 마지막 스냅샷 cccc3333' \
  && [ "$(n_of '^chat.postMessage|[^|]*|[^|]*||')" = 2 ] && [ -f "$T/ft/.fable-team/state/board/2026-10-09/frozen" ] && ok "날짜 바뀜 → 새 뿌리 글 1 + 전날 뿌리 동결 1회" || bad "날짜 경계 rc=$rc: $(tail -3 "$LOG") $(cat "$T/err.txt")"
snap '{"snap":"dddd4444→eeee5555","prev":"dddd4444","changes":["Issue #1 open→closed"],"prev_day_last":null}'; mkbody E
rc="$(publish)"
[ "$rc" = 0 ] && [ "$(n_of "^chat.update|[^|]*|$ROOT1|")" = $((u0+1)) ] && ok "같은 날 재발행 → 전날 키 갱신 0" || bad "전날 키 재갱신 rc=$rc"

# 5) 실제 크기 본문(①절 25KB · ⓪ 9팀) → 뿌리 글 ≤ 3500B · ⓪ 9팀·④·끝줄 있음 · ①②③ 절 머리 0
root_ok() {  # root_ok <팀 수> — 마지막 슬랙 호출의 바이트·내용 검사
  local t="$(tail -1 "$LOG")" n="$1"
  [ "$(last_bytes)" -le 3500 ] && echo "$t" | grep -q "팀$n |" && echo "$t" | grep -q '\*④ 오늘 판정표\*' && echo "$t" | grep -q '터미널 보드' \
    && ! echo "$t" | grep -q '\*① \|\*② \|\*③ '
}
export FT_BOARD_NOW="$D2"; snap '{"snap":"eeee5555→ffff6666","prev":"eeee5555","changes":[],"prev_day_last":null}'; mkbody F 9 25000
rc="$(publish)"
[ "$rc" = 0 ] && root_ok 9 && ok "①절 25KB · 9팀 → update text $(last_bytes)B ≤ 3500 · ⓪ 9팀·④·끝줄 있음 · ①②③ 절 머리 0" || bad "큰 본문 rc=$rc bytes=$(last_bytes) $(cat "$T/err.txt")"

# 6) ⓪ 40팀(길게) → `… 외 n팀` · ≤ 3500 · UTF-8 decode 성공
mkbody G 40 25000
R="$(python3 "$ROOT/harness/bin/ft_board_root.py" root < "$T/stub/body.txt" | python3 -c 'import sys; d=sys.stdin.buffer.read(); d.decode("utf-8"); print(len(d))')"
python3 "$ROOT/harness/bin/ft_board_root.py" root < "$T/stub/body.txt" | grep -q '… 외 [0-9]*팀' && [ "$R" -le 3500 ] && ok "⓪ 40팀 → '… 외 n팀' · ${R}B ≤ 3500 · UTF-8 decode OK" || bad "40팀 접기 R=$R"

# 7) 절 머리 없는 본문 → update 0 + rc 1
printf '[상태] 머리만 있는 본문\n' > "$T/stub/body.txt"; before="$(wc -l < "$LOG" | tr -d ' ')"
rc="$(publish)"
[ "$rc" = 1 ] && [ "$(wc -l < "$LOG" | tr -d ' ')" = "$before" ] && ok "절 머리 없는 본문 → update 0 + rc 1" || bad "절 머리 없음 rc=$rc"

# 8) 동결 본문도 상한 안 — 전날 뿌리 글이 3.4KB 근처여도 동결 update ≤ 3500B · 동결 끝줄 남음
mkbody G 40 25000; rc="$(publish)"   # D2 마지막 발행 = 40팀 접힌 본문(상한 근처)
ROOT2="$(awk -F'|' '$1=="chat.postMessage" && $4=="" {n++; if (n==2) print $3}' "$LOG")"
export FT_BOARD_NOW="2026-10-11T09:00:00"; snap '{"snap":"-→gggg7777","prev":null,"changes":[],"prev_day_last":"ffff6666"}'; mkbody H 2 0
rc2="$(publish)"
fz="$(grep "^chat.update|[^|]*|$ROOT2|" "$LOG" | tail -1)"
[ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$(echo "$fz" | awk -F'|' '{print $5}')" -le 3500 ] && echo "$fz" | grep -q '동결 — 마지막 스냅샷 ffff6666' && ok "동결 본문 $(echo "$fz" | awk -F'|' '{print $5}')B ≤ 3500 · 동결 끝줄 유지" || bad "동결 상한 rc=$rc/$rc2 fz=${fz:0:120}"

# 9) 변이 대조: 상한 함수를 우회(통과만 시키는 가짜 ft_board_root.py)하면 ① 검사가 FAIL 해야 한다
mkdir -p "$T/mut"; cp "$PUB" "$T/mut/"; printf 'import sys; sys.stdout.write(sys.stdin.read())\n' > "$T/mut/ft_board_root.py"
export FT_BOARD_NOW="2026-10-12T09:00:00"; snap '{"snap":"-→hhhh8888","prev":null,"changes":[],"prev_day_last":null}'; mkbody M 9 25000
bash "$T/mut/ft-board-publish.sh" >/dev/null 2>&1
root_ok 9 && bad "변이 대조: 상한 우회인데 ① 검사가 통과함(검사가 무력)" || ok "변이 대조: 상한 우회 시 ① FAIL ($(last_bytes)B > 3500)"

echo "fail=$fail"; [ "$fail" = 0 ]
