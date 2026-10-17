#!/usr/bin/env bash
# test_inbox_ingest_root_rotate.sh — R328: `ft-inbox.sh ingest <seq>` 가 recv 뒤 «mailbox 에서 못 찾음» 으로 거절되던 두 구멍
#  ⓐ git 밖 cwd + FT_ROOT 없음 → 루트를 못 정함 = rc≠0 + «루트를 못 정함» 메시지 · 큐·bodies 쓰기 0 (빈 경로 «/.fable-team» 로 진행 금지)
#  ⓑ 회전본 mailbox.log.jsonl.1 에만 있는 seq → ingest 성공(큐 행 1)
#  ⓒ 세 파일 어디에도 없는 seq → rc≠0 + 메시지에 «읽은 파일 목록»
#  ⓔ 같은 seq 두 번 ingest = SKIP 그대로(큐 행 1)
# 임시 FT_ROOT + 임시 «git 밖» cwd — 실 mailbox·실 인박스 0 · GIT_* 는 걸지 않는다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

ROOT="$T/root"; BIN="$ROOT/.fable-team/bin"; COMM="$ROOT/.fable-team/comm"; Q="$ROOT/.fable-team/state/inbox"
mkdir -p "$BIN" "$COMM" "$T/outside"
cp "$KIT"/ft-inbox.sh "$KIT"/ft-inbox.py "$KIT"/ft_inbox_core.py "$BIN/"
row() {  # <seq> <body> → mailbox 한 줄
  python3 -c 'import json,sys; print(json.dumps({"seq":int(sys.argv[1]),"ts":"2026-10-17T20:00:00","from":"snd#1","to":"rcv-x#1","body":sys.argv[2]}, ensure_ascii=False))' "$1" "$2"
}
row 9001 "참고: 현행 파일" > "$COMM/mailbox.jsonl"
row 9002 "참고: 로그 파일" > "$COMM/mailbox.log.jsonl"
row 9003 "참고: 회전본" > "$COMM/mailbox.log.jsonl.1"
unset FT_ROOT
rows() {  # <큐 경로> <seq>
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
try:
    print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if l.strip() and json.loads(l)["seq"] == int(sys.argv[2])))
except FileNotFoundError:
    print(0)
PYEOF
}

# ⓐ git 밖 cwd + FT_ROOT 없음 → 루트를 못 정함
(cd "$T/outside" && env -u FT_ROOT bash "$BIN/ft-inbox.sh" ingest 9002) 2>"$T/err" >"$T/out"; rc=$?
[ "$rc" -ne 0 ] && ok "ⓐ git 밖 + FT_ROOT 없음 → rc≠0($rc)" || bad "ⓐ rc 0 으로 끝남"
grep -q "루트를 못 정함" "$T/err" && ok "ⓐ 메시지에 «루트를 못 정함»" || bad "ⓐ 메시지 없음: $(cat "$T/err")"
grep -q "못 찾음" "$T/err" && bad "ⓐ «쪽지 없음» 으로 바꿔 말함: $(cat "$T/err")" || ok "ⓐ «못 찾음»(쪽지 없음) 으로 바꿔 말하지 않음"
eq "ⓐ 큐 쓰기 0" "$(ls "$Q" 2>/dev/null | wc -l | tr -d ' ')" 0
eq "ⓐ bodies 쓰기 0" "$(ls "$COMM/bodies" 2>/dev/null | wc -l | tr -d ' ')" 0

# ⓑ 회전본에만 있는 seq → ingest 성공
(cd "$T/outside" && FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest 9003) 2>"$T/err" >"$T/out"; rc=$?
eq "ⓑ 회전본(.1)에만 있는 seq → rc 0" "$rc" 0
eq "ⓑ 큐 행 1" "$(rows "$Q/rcv-x.jsonl" 9003)" 1
# 로그·현행 파일 seq 는 지금처럼 찾힌다
(cd "$T/outside" && FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest 9002) >/dev/null 2>&1
eq "ⓑ mailbox.log.jsonl 의 seq 도 적재" "$(rows "$Q/rcv-x.jsonl" 9002)" 1

# ⓒ 어디에도 없는 seq → rc≠0 + 읽은 파일 목록
(cd "$T/outside" && FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest 9999) 2>"$T/err" >"$T/out"; rc=$?
[ "$rc" -ne 0 ] && ok "ⓒ 없는 seq → rc≠0($rc)" || bad "ⓒ rc 0"
for f in mailbox.jsonl mailbox.log.jsonl mailbox.log.jsonl.1; do
  grep -q "$f" "$T/err" && ok "ⓒ 메시지에 읽은 파일 $f" || bad "ⓒ 읽은 파일 목록에 $f 없음: $(cat "$T/err")"
done

# ⓔ 같은 seq 두 번 = SKIP · 큐 행 1
(cd "$T/outside" && FT_ROOT="$ROOT" bash "$BIN/ft-inbox.sh" ingest 9003) 2>"$T/err" >"$T/out"
grep -q "^SKIP seq=9003" "$T/out" && ok "ⓔ 두 번째 ingest = SKIP" || bad "ⓔ SKIP 아님: $(cat "$T/out")"
eq "ⓔ 큐 행 1 그대로" "$(rows "$Q/rcv-x.jsonl" 9003)" 1

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
