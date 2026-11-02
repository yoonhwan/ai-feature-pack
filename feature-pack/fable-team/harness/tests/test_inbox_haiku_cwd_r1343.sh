#!/usr/bin/env bash
# test_inbox_haiku_cwd_r1343.sh — 쪽지 분류기(ft_inbox_core.haiku)가 빈 작업 폴더에서 claude 를 부르는지 시험 (r1343).
# H1 기본 haiku-cwd · H2 폴더 없음→만듦(파일 0) · H3 자리에 일반 파일→분류 미상 유지+err 1줄 · H4 FT_INBOX_HAIKU_CWD 지정
# 변이 1(cwd 인자 제거)→H1 FAIL · 변이 2(makedirs 를 빼고 cwd=None)→H3 FAIL
# 전부 mktemp 임시 FT_ROOT · 스텁 Haiku(자기 cwd 를 파일에 적음) · 실 claude 0 · 네트워크 0 · 자기 재호출 0 · 실행 비트 0 (bash <파일>).
set -uo pipefail
[ -n "${R1343_REENTRY:-}" ] && exit 0   # 재진입 가드 — 이 파일은 자기를 다시 부르지 않는다
export R1343_REENTRY=1
ulimit -u $(( $(ps -u "$(id -u)" 2>/dev/null | wc -l) + 300 )) 2>/dev/null || true
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
Q="$FT_ROOT/.fable-team/state/inbox"
ERRLOG="$FT_ROOT/.fable-team/state/hook-errors.log"
HCWD="$Q/haiku-cwd"
M=master-x; SEQ=701
# 스텁 Haiku: 자기 cwd(물리 경로)를 파일에 적고 라벨 5 한 줄
printf '#!/bin/sh\ncat >/dev/null\npwd -P > "%s/cwd.txt"\necho 5\n' "$T" > "$T/haiku-stub.sh"
export FT_INBOX_HAIKU="sh $T/haiku-stub.sh"
printf '[a#1->%s#9] 이상한 문장 가나다\n' "$M" > "$FT_ROOT/.fable-team/comm/bodies/$SEQ.txt"

seed() {  # 큐를 «미상» 1줄로 되돌림
  python3 - "$Q/$M.jsonl" "$FT_ROOT/.fable-team/comm/bodies/$SEQ.txt" "$SEQ" <<'PY'
import json, sys
q, bp, seq = sys.argv[1], sys.argv[2], int(sys.argv[3])
row = {"seq": seq, "ts": "2026-11-02T20:00:00", "from": "a#1", "cls": "미상", "prio": 1.5, "group": "g1", "body_path": bp,
       "mark": None, "reported": False, "via": "rule"}
open(q, "w", encoding="utf-8").write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}
cls_of() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(x["cls"])' "$Q/$M.jsonl" "$SEQ"; }
rows_ok() { python3 -c 'import json,sys
n=0
for l in open(sys.argv[1]): json.loads(l); n+=1
print(n)' "$Q/$M.jsonl"; }
classify() {  # <ft-inbox.py 경로> — cwd=/ 에서 동기 실행 (ingest 의 분리 자식을 거치지 않는다)
  rm -f "$T/cwd.txt"
  (cd / && python3 "$1" classify "$SEQ" "$M#9" >/dev/null 2>&1)
}
phys() { (cd "$1" 2>/dev/null && pwd -P); }
EXP="$(phys "$Q")/haiku-cwd"   # 폴더가 없어도 기대값은 큐 물리 경로 + /haiku-cwd

PY="$BIN/ft-inbox.py"
# H1 — 기본 haiku-cwd
seed; classify "$PY"
eq "H1 스텁 cwd = haiku-cwd" "$(cat "$T/cwd.txt" 2>/dev/null)" "$EXP"
eq "H1 큐 cls = 스텁 라벨 ⑤" "$(cls_of)" "⑤"

# H2 — 폴더 없음 → 만든 뒤 H1 과 같음 · 폴더 안 파일 0
rm -rf "$HCWD"; seed; classify "$PY"
eq "H2 폴더 새로 만듦 → 스텁 cwd = haiku-cwd" "$(cat "$T/cwd.txt" 2>/dev/null)" "$EXP"
eq "H2 큐 cls = ⑤" "$(cls_of)" "⑤"
eq "H2 폴더 안 파일 수 0" "$(find "$HCWD" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0"

# H3 — haiku-cwd 자리에 일반 파일 → 분류 미상 그대로 · err 1줄(haiku-cwd 포함) · 큐 손상 0
rm -rf "$HCWD"; : > "$HCWD"; seed; rm -f "$ERRLOG"; classify "$PY"
eq "H3 큐 cls 미상 유지" "$(cls_of)" "미상"
eq "H3 큐 줄 수 1 · 파싱 성공" "$(rows_ok)" "1"
eq "H3 err 로그에 haiku-cwd 1줄" "$(grep -c 'haiku-cwd' "$ERRLOG" 2>/dev/null)" "1"
[ ! -e "$T/cwd.txt" ] && ok "H3 스텁 실행 0" || bad "H3 폴더 못 만들었는데 스텁이 돌았다"
rm -f "$HCWD"

# H4 — FT_INBOX_HAIKU_CWD 지정
seed; FT_INBOX_HAIKU_CWD="$T/custom" classify "$PY"
eq "H4 스텁 cwd = 지정 폴더" "$(cat "$T/cwd.txt" 2>/dev/null)" "$(phys "$T/custom")"

# 변이 — bin 사본을 고쳐 같은 검사가 FAIL 하는지
mut() {  # <이름> <sed 식>
  mkdir -p "$T/$1"; cp "$BIN/ft-inbox.py" "$BIN"/ft_inbox_*.py "$T/$1/"
  sed -i.bak "$2" "$T/$1/ft_inbox_core.py"; cmp -s "$BIN/ft_inbox_core.py" "$T/$1/ft_inbox_core.py" && echo "NOCHANGE"
}
r=$(mut m1 's/, cwd=cwd)/)/'); [ -z "$r" ] || bad "변이 1 적용 실패"
rm -rf "$HCWD"; seed; classify "$T/m1/ft-inbox.py"
[ "$(cat "$T/cwd.txt" 2>/dev/null)" != "$EXP" ] && ok "변이 1 → H1 FAIL(cwd = 부른 쪽)" || bad "변이 1 인데 H1 이 통과했다"

r=$(mut m2 's/^    os.makedirs(cwd := .*$/    cwd = None/'); [ -z "$r" ] || bad "변이 2 적용 실패"
rm -rf "$HCWD"; : > "$HCWD"; seed; rm -f "$ERRLOG"; classify "$T/m2/ft-inbox.py"
n=$(grep -c 'haiku-cwd' "$ERRLOG" 2>/dev/null); [ "${n:-0}" = "0" ] && [ "$(cls_of)" != "미상" ] && ok "변이 2 → H3 FAIL(err 0 · 분류가 바뀜)" || bad "변이 2 인데 H3 이 통과했다"

echo "---"; [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
