#!/usr/bin/env bash
# test_secret_triage_r1002.sh — ft-secret-triage.sh 읽기 전용 3값 점검 (r1002 · 계약 C1~C6)
# 격리: 임시 HOME(합성 session jsonl · 합성 원장) + 임시 --out. 실 세션 기록·실 원장 읽기 0 · 쓰기 0. 값은 전부 가짜.
# 변이 2종(«값 출력 되살림» · «7초 초과 조용히 생략»)은 mktemp 사본에서만 — 이 시험이 그것을 FAIL 로 잡는지 본다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_TRIAGE_UNDER_TEST:-$HARNESS/bin}"          # 변이 사본을 넣어 이 시험 자체를 다시 돌린다
SH="$BIND/ft-secret-triage.sh"; PY="$BIND/ft_secret_triage.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"; chmod -R u+rwX "$T" 2>/dev/null' EXIT
export HOME="$T/home" FT_SECRET_TRIAGE_LOG="$T/secret-scan.log" FT_SECRET_TRIAGE_ROW_SECS=7
mkdir -p "$HOME" "$T/tests"
REAL="$T/real.jsonl"; NAMED="$T/nameonly.jsonl"; FAKE="$T/tests/fake.jsonl"; NOREAD="$T/noread.jsonl"; FIFO="$T/slow.jsonl"
V1='ZQ7xREALvalue0123456789ab'; V2='ghp_ZQ7xREALvalue0123456789ab'; V3='ZQ7xREALpassword99'; V4='ZQ7xDUMMYvalue0123456789ab'
printf '{"stdout":"API_TOKEN=%s ok"}\n' "$V1" > "$REAL"
printf '{"out":"%s PGPASSWORD=%s"}\n' "$V2" "$V3" >> "$REAL"
printf '{"note":"dummy line API_TOKEN=%s"}\n' "$V4" >> "$REAL"
printf '{"API_TOKEN": ""}\n' > "$NAMED"
printf 'X_API_SECRET=<TOKEN>\n' >> "$NAMED"
printf 'DBSECRET="***"\n' >> "$NAMED"
printf '{"out":"%s"}\n' "$V2" > "$FAKE"           # 시험 폴더 = 예시·가짜(값이 진짜 꼴이어도)
printf 'TOKEN=%s\n' "$V4" > "$NOREAD"; chmod 000 "$NOREAD"
TAB=$'\t'
{ printf '2026-10-27 03:32:22%s%s:1 named-secret\n' "$TAB" "$REAL"
  printf '2026-10-27 03:32:22%s%s:2 token-prefix\n' "$TAB" "$REAL"
  printf '2026-10-27 03:32:22%s%s:2 pgpassword\n' "$TAB" "$REAL"
  printf '2026-10-27 03:32:22%s%s:3 named-secret\n' "$TAB" "$REAL"
  printf '2026-10-27 03:32:22%s%s:1 named-secret\n' "$TAB" "$NAMED"
  printf '2026-10-27 03:32:22%s%s:2 named-secret\n' "$TAB" "$NAMED"
  printf '2026-10-27 03:32:22%s%s:3 named-secret\n' "$TAB" "$NAMED"
  printf '2026-10-27 03:32:22%s%s:1 token-prefix\n' "$TAB" "$FAKE"
  printf '2026-10-27 03:32:22%s%s:1 named-secret\n' "$TAB" "$NOREAD"
  printf '2026-10-27 03:32:22%s%s:1 token-prefix\n' "$TAB" "$T/missing.jsonl"
  printf '2026-10-27 03:32:22%s%s:99 named-secret\n' "$TAB" "$REAL"
  printf '2026-10-27 03:32:22%s탭없는행 named-secret\n' "$TAB"
  printf '2026-10-26 03:32:22%s%s:1 named-secret\n' "$TAB" "$REAL"
} > "$FT_SECRET_TRIAGE_LOG"
mkfifo "$FIFO" 2>/dev/null || echo "WARN fifo 없음 — 시간 초과 검사 건너뜀" >&2
fail=0; out=""; err=""; rc=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200} err=${err:0:200}"; fail=$((fail+1)); fi; }
run() { out="$(bash "$SH" "$@" 2>"$T/e")"; rc=$?; err="$(cat "$T/e")"; }
rowsmd() { awk '/^## 행별 판정/{f=1;next} /^## /{f=0} f && /^\| / && !/^\| 파일 / && !/^\| --- /' "$1"; }
count() { rowsmd "$1" | cut -d'|' -f5 | grep -c "^ $2 $" || true; }
novalue() { ! grep -q -e ZQ7xREAL -e ZQ7xDUMMY -e ghp_ZQ7 "$@"; }
rowsof() { rowsmd "$1" | wc -l | tr -d ' '; }

bash -n "$SH"; ck "bash -n (bin/sh)" $?
[ -x /bin/bash ] && { /bin/bash -n "$SH"; ck "bash -n (/bin/bash 3.2)" $?; }
python3 -m py_compile "$PY"; ck "py_compile" $?
[ "$(wc -l < "$PY")" -le 200 ] && [ "$(wc -l < "$SH")" -le 200 ]; ck "200줄 상한(py·sh)" $?

# C1 · C4 · C5 — 3값 분류와 합계
sha_before="$(shasum -a 256 "$FT_SECRET_TRIAGE_LOG" "$REAL" "$NAMED" "$FAKE" | awk '{print $1}' | tr '\n' ' ')"
run --since 2026-10-27 --out "$T/t1.md"
[ "$rc" = 0 ] && [ "$(grep -c . <<<"$out")" = 1 ]; ck "rc0 · 표준출력 1줄" $?
grep -q 'triage=12 real=3 name=3 example=2 unknown=4' <<<"$out"; ck "합계 triage=12 real=3 name=3 example=2 unknown=4 (C1·C5)" $?
[ "$(count "$T/t1.md" 실값)" = 3 ] && [ "$(count "$T/t1.md" 이름만)" = 3 ] && [ "$(count "$T/t1.md" '예시·가짜')" = 2 ] && [ "$(count "$T/t1.md" '판정 불가')" = 4 ]
ck "표 행별 3값 3/3/2/4 (C1)" $?
[ "$(rowsof "$T/t1.md")" = 12 ]; ck "표 행수 = triage(조용한 생략 0)" $?
grep -q 'real.jsonl:2.*token-prefix' "$T/t1.md" && grep -q 'real.jsonl:2.*pgpassword' "$T/t1.md"; ck "같은 파일 같은 줄 2종류 각각 판정" $?
grep -q 'nameonly.jsonl | 1 | named-secret | 이름만' "$T/t1.md"; ck "이름만: 값 자리 빈 것" $?
grep -q 'tests/fake.jsonl' "$T/t1.md"; ck "예시·가짜: 시험 폴더" $?
grep -q '판정 불가 (이유)' "$T/t1.md" && grep -q '줄 번호가 파일 길이 넘음: 1건' "$T/t1.md"; ck "판정 불가 사유 목록(넘는 줄)" $?
sha_after="$(shasum -a 256 "$FT_SECRET_TRIAGE_LOG" "$REAL" "$NAMED" "$FAKE" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "C4 원장·세션 파일 sha 불변" $?

# C2 — 값 글자 0 (표·표준출력·표준오류)
novalue "$T/t1.md" "$T/e" <<<"$out"; ck "C2 값 0 (표·stdout·stderr)" $?

# C3 — 날짜 범위 밖 행은 세지 않는다 · 빈 원장
: > "$T/empty.log"
FT_SECRET_TRIAGE_LOG="$T/empty.log" bash "$SH" --out "$T/t2.md" >"$T/o2" 2>"$T/e2"
grep -q 'triage=0 real=0 name=0 example=0 unknown=0' "$T/o2"; ck "빈 원장 = triage=0 rc0" $?

# C3 — 행 상한 초과 → 판정 불가(조용한 생략 0)
if [ -p "$FIFO" ]; then
  printf '2026-10-27 04:00:00%s%s:1 named-secret\n' "$TAB" "$FIFO" > "$T/slow.log"
  FT_SECRET_TRIAGE_LOG="$T/slow.log" FT_SECRET_TRIAGE_ROW_SECS=1 bash "$SH" --out "$T/t3.md" >"$T/o3" 2>"$T/e3"
  grep -q 'triage=1 real=0 name=0 example=0 unknown=1' "$T/o3" && grep -q '초과: 1건' "$T/t3.md"; ck "C3 1초 넘는 행 = 판정 불가 · 표에 남음" $?
fi

# C1 R1 — jsonl 문자열 안(역슬래시 감싼) 이름·자리표시자 = 이름만 (DA⑥ r1 고침 1)
ESCJ="$T/esc.jsonl"
printf '{"stdout":"[INFO] \\"GITHUB_TOKEN\\": \\"***\\" saved"}\n' > "$ESCJ"
printf '{"cfg":"\\"API_KEY\\": \\"<TOKEN>\\" here"}\n' >> "$ESCJ"
printf '2026-10-27 05:00:00%s%s:1 named-secret\n2026-10-27 05:00:00%s%s:2 named-secret\n' "$TAB" "$ESCJ" "$TAB" "$ESCJ" > "$T/esc.log"
FT_SECRET_TRIAGE_LOG="$T/esc.log" bash "$SH" --out "$T/t4.md" >"$T/o4" 2>"$T/e4b"
grep -q 'triage=2 real=0 name=2 example=0 unknown=0' "$T/o4"; ck "R1 jsonl 이스케이프 이름만 2 (고침 1)" $?

# C3 R2 — 분류(가림 함수) 구간에도 행·전체 상한 (DA⑥ r1 고침 2 · 지연 스텁)
SB="$T/slowbin"; mkdir -p "$SB"; cp -p "$BIND"/ft_secret_*.py "$SH" "$SB/"  # 의존 모듈(ft_secret_targets·lex)까지 함께
printf 'import os, time\ndef mask(text):\n    time.sleep(float(os.environ.get("FT_TRIAGE_MASK_SLEEP") or "2"))\n    return text, []\n' > "$SB/ft_secret_shapes.py"
printf 'API_TOKEN=abcdefghijklmnop\n' > "$T/one.jsonl"
printf '2026-10-27 06:00:00%s%s:1 named-secret\n' "$TAB" "$T/one.jsonl" > "$T/one.log"
FT_SECRET_TRIAGE_LOG="$T/one.log" FT_TRIAGE_MASK_SLEEP=3 FT_SECRET_TRIAGE_ROW_SECS=0.5 bash "$SB/ft-secret-triage.sh" --out "$T/t5.md" >"$T/o5" 2>"$T/e5"
grep -q 'triage=1 real=0 name=0 example=0 unknown=1' "$T/o5" && grep -q '행 0.5초 초과: 1건' "$T/t5.md"; ck "R2 지연 가림 함수 → 행 상한 판정 불가 (고침 2)" $?
printf 'API_TOKEN=abcdefghijklmnop\nSECRET_KEY=qqq\nDB_PASSWORD=zzz\n' > "$T/three.jsonl"
printf '2026-10-27 06:10:00%s%s:1 named-secret\n2026-10-27 06:10:00%s%s:2 named-secret\n2026-10-27 06:10:00%s%s:3 named-secret\n' \
  "$TAB" "$T/three.jsonl" "$TAB" "$T/three.jsonl" "$TAB" "$T/three.jsonl" > "$T/three.log"
FT_SECRET_TRIAGE_LOG="$T/three.log" FT_TRIAGE_MASK_SLEEP=0.2 FT_SECRET_TRIAGE_TOTAL_SECS=0.25 bash "$SB/ft-secret-triage.sh" --out "$T/t6.md" >"$T/o6" 2>"$T/e6"
grep -q 'triage=3 real=0 name=0 example=0 unknown=3' "$T/o6" && grep -q '전체 상한 초과: 2건' "$T/t6.md"; ck "R2 전체 상한 축소 → 남은 행 판정 불가 · 합계 일치" $?

# C3 — 표 쓰기 실패 = rc≠0
mkdir -p "$T/ro"; chmod 500 "$T/ro"
bash "$SH" --out "$T/ro/x/y.md" >/dev/null 2>"$T/e4"; rc=$?
[ "$rc" != 0 ]; ck "C3 표 폴더 못 만들면 rc≠0" $?
chmod 700 "$T/ro"

# C6 — kit 짝 사본 cmp0 + 실행 비트
KIT="$HARNESS/kit/fable-team/bin"
if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$PY" "$KIT/ft_secret_triage.py" && cmp -s "$SH" "$KIT/ft-secret-triage.sh"; ck "C6 kit 짝 cmp0" $?
fi

# 변이 2종 — 사본을 고쳐 이 시험 자체를 다시 돌린다(FAIL 이어야 잡힌 것)
mut() {  # mut <이름> <patch.py 코드> [env]
  local d="$T/mut-$1"; mkdir -p "$d"; cp -p "$BIND"/ft_secret_*.py "$SH" "$d/"  # 의존 모듈까지 — 못 읽는 사본으로 «우연히» FAIL 하지 않게
  python3 - "$d/ft_secret_triage.py" "$2" <<'EOF'
import sys
p, code = sys.argv[1], sys.argv[2]
s = open(p).read()
for pair in code.split("\n#---\n"):
    if pair.strip():
        a, b = pair.split("\n>>>\n")
        assert a in s, a[:40]
        s = s.replace(a, b)
open(p, "w").write(s)
EOF
}
LEAK='                    r["verdict"] = timed_verdict(path, got[no], budget := min(row_secs, left))
>>>
                    r["verdict"] = timed_verdict(path, got[no], budget := min(row_secs, left))
                    r["why"] = got[no][:120]
#---
    print(f"triage={len(rows)}
>>>
    print("LEAK " + " ".join(r.get("why", "") for r in rows))
    print(f"triage={len(rows)}'
DROP='def table(rows: list[dict[str, str]], log: str, since: str, until: str) -> str:
>>>
def table(rows: list[dict[str, str]], log: str, since: str, until: str) -> str:
    rows = [r for r in rows if "초과" not in r.get("why", "")]'
ESC_OFF='    for cand in (line, ESC.sub(r"\1", line)):  # R1 — 원문에서 못 찾으면 1단 푼 줄로 한 번 더
>>>
    for cand in (line,):'
TIMER_OFF='                    r["verdict"] = timed_verdict(path, got[no], budget := min(row_secs, left))
>>>
                    r["verdict"] = verdict(path, got[no])'
if [ -z "${FT_TRIAGE_UNDER_TEST:-}" ]; then   # 변이 자식은 다시 변이를 만들지 않는다(무한 재귀 차단)
  for name in leak drop esc timer; do
    case "$name" in
      leak) mut "$name" "$LEAK" ;;
      drop) mut "$name" "$DROP" ;;
      esc) mut "$name" "$ESC_OFF" ;;
      timer) mut "$name" "$TIMER_OFF" ;;
    esac
    FT_TRIAGE_UNDER_TEST="$T/mut-$name" bash "${BASH_SOURCE[0]:-$0}" >"$T/m-$name.log" 2>&1
    [ $? -ne 0 ]; ck "변이 $name → 이 시험이 FAIL 로 잡음" $?
  done
fi

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-triage r1002)"; exit 0; }
echo "FAILED $fail"; exit 1
