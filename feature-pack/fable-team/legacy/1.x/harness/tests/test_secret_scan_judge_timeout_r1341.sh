#!/usr/bin/env bash
# test_secret_scan_judge_timeout_r1341.sh — r1341 단계 2: 계획 1건 판정기의 시간 초과·rc=2·출력 꼴 어긋남이
#   스캔 회차 전체를 죽이지 않는다 — «판정 불가» 1줄 + 그 파일만 세고(judge_unknown) 반복 계속 · sig 저장 0(다음 회차 재판정)
#   · 같은 파일 3회차 연속 판정 불가면 [긴급] 1통 · 회차 rc=3 · 재시도 1(시간 초과만) · J6 정상 검출은 지금 그대로
#   격리: 임시 HOME·임시 SCAN_HERE(대역 판정기)·가짜 mbox·임시 계획 파일 · 실 세션 기록·실 /tmp/h* 0 · sleep = 대역 안 7초 초과만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
now() { date +%s; }; secs() { echo "$(( $(now) - $1 ))초"; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
B="$T/bin"; R="$T/realbin"; mkdir -p "$B" "$R" "$T/home" "$T/root/design" "$T/plans"
cp -p "$BIN/ft-secret-scan.sh" "$BIN"/ft_secret_*.py "$B/"   # 판정기 동봉 모듈까지(대역으로 갈아 끼운다)
cp -p "$BIN/ft-secret-scan.sh" "$BIN"/ft_secret_*.py "$R/"   # J6 = 진짜 판정기
cat > "$B/ft_secret_judge.py" <<'PY'
import os, sys, time   # 대역 판정기 — FAKE_SCRIPT(호출 순번별 동작) 만
n = int(open(os.environ["FAKE_CNT"]).read() or 0) + 1 if os.path.exists(os.environ["FAKE_CNT"]) else 1
open(os.environ["FAKE_CNT"], "w").write(str(n))
acts = open(os.environ["FAKE_SCRIPT"]).read().split()
act = acts[n - 1] if n <= len(acts) else "ok"
if act == "sleep8":
    time.sleep(8)
if act == "rc2":
    sys.exit(2)
if act == "reject":
    print("reject 1 비밀 조회 치환이 인자로 넘어감"); sys.exit(1)
if act == "weird":
    sys.exit(1)
print("ok")
PY
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/mail.log"\nexit 0\n' "$T" > "$T/mbox.sh"; chmod 644 "$T/mbox.sh"
printf '{"_hil_route":"fx-desk#0"}\n' > "$T/seats.json"
for i in 1 2 3; do printf 'plan %s\n' "$i" > "$T/plans/p$i"; done
printf 'env "$X" bash x.sh\n' > "$T/plans/real"
scan() {  # scan <bin> <동작목록> <계획…> — 대역 판정기로 한 회차
  printf '%s\n' $2 > "$T/acts"; rm -f "$T/cnt"
  out="$(HOME="$T/home" FT_SECRET_SCAN_ROOT="$T/root" FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json" \
         FAKE_SCRIPT="$T/acts" FAKE_CNT="$T/cnt" timeout 70 bash "$1/ft-secret-scan.sh" --plans "${@:3}" 2>&1)"; rc=$?
}
reset() { rm -rf "$T/home/.fable-team" "$T/mail.log" "$T/acts" "$T/cnt"; }
t0=$(now)
# J1 — 3개 중 2번째 8초: 1·3 판정 · 2 판정 불가 · judge_unknown=1 · rc=3
reset; scan "$B" "ok sleep8 sleep8 ok" "$T/plans/p1" "$T/plans/p2" "$T/plans/p3"
st="$(cat "$T/home/.fable-team/state/secret-scan.state" 2>/dev/null)"
ck "J1 판정 불가 1줄 · judge_unknown=1 · rc=$rc ($(secs "$t0"))" \
  "$([ "$rc" = 3 ] && grep -q '판정 불가 .*판정기 7초' <<<"$out" && grep -q 'judge_unknown=1' <<<"$out" && echo 0 || echo 1)"
ck "J1 상태에 판정 불가 파일 sig 0 · 판정된 2개만 sig" \
  "$(python3 - "$T/home/.fable-team/state/secret-scan.state" "$T/plans/p2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(0 if (sys.argv[2] not in d["files"] and len(d["files"]) == 2 and d.get("unknown", {}).get(sys.argv[2], [0])[0] == 1) else 1)
PY
)"
# J2 — rc=2 + 빈 stdout → 판정 불가(«found 0» 으로 세지 않음)
reset; scan "$B" "rc2" "$T/plans/p1"
ck "J2 rc=2 → 판정 불가 rc=$rc · new=0 셈 아님" \
  "$([ "$rc" = 3 ] && grep -q '판정 불가 .*판정기 rc=2' <<<"$out" && grep -q 'judge_unknown=1' <<<"$out" && [ ! -s "$T/home/.fable-team/state/secret-scan.log" ] && echo 0 || echo 1)"
# J3 — 같은 파일 3회차 연속 판정 불가 → 3회차에 [긴급] 1통
reset; for i in 1 2 3; do scan "$B" "rc2" "$T/plans/p1"; done
ck "J3 3회차 = [긴급] 1통(경로·사유) · rc=$rc" \
  "$([ "$rc" = 3 ] && [ "$(grep -c '\[긴급\]' "$T/mail.log" 2>/dev/null)" = 1 ] && grep -q 'p1' "$T/mail.log" && grep -q 'rc=2' "$T/mail.log" && echo 0 || echo 1)"
# J4 — 모두 정상 = 지금 끝 줄 그대로 · judge_unknown=0 · rc0
reset; scan "$B" "ok ok ok" "$T/plans/p1" "$T/plans/p2" "$T/plans/p3"
ck "J4 모두 정상 → rc=0 · judge_unknown=0 · SCAN 줄" \
  "$([ "$rc" = 0 ] && grep -q 'SCAN read=3 skipped=0 new=0 judge_unknown=0' <<<"$out" && echo 0 || echo 1)"
# J5 — 재시도에서 통과(첫 8초 · 둘째 1초) → 판정됨 · judge_unknown=0
reset; t=$(now); scan "$B" "sleep8 ok" "$T/plans/p1"
ck "J5 재시도 1로 통과 · judge_unknown=0 · rc=0 ($(secs "$t"))" \
  "$([ "$rc" = 0 ] && grep -q 'judge_unknown=0' <<<"$out" && [ -n "$(cat "$T/home/.fable-team/state/secret-scan.state" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["files"] and 1 or "")')" ] && echo 0 || echo 1)"
# J6 — 정상 검출 회귀(진짜 판정기 · «env "$X" bash x.sh»)
reset; t=$(now)
out="$(HOME="$T/home" FT_SECRET_SCAN_ROOT="$T/root" FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json" \
       timeout 70 bash "$R/ft-secret-scan.sh" --plans "$T/plans/real" 2>&1)"; rc=$?
ck "J6 진짜 검출 = new=1 · judge_unknown=0 · rc=0 · [HIL] 1통 ($(secs "$t"))" \
  "$([ "$rc" = 0 ] && grep -q 'new=1 judge_unknown=0' <<<"$out" && grep -q '\[HIL\]' "$T/mail.log" && echo 0 || echo 1)"

# 변이 — 사본에서만(실 파일 치환 0)
mut() {  # mut <이름> <원문> <바꿀 글> → $T/mut-<이름>
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; cp -p "$B"/ft-secret-scan.sh "$B"/ft_secret_*.py "$d"/
  python3 - "$d/ft-secret-scan.sh" "$2" "$3" <<'PYM' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return 1; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PYM
}
mut M1 '        except subprocess.TimeoutExpired:
            if attempt == 1:
                continue
            return [], "판정기 7초"' '        except ZeroDivisionError:
            pass'
reset; scan "$T/mut-M1" "sleep8 sleep8 ok" "$T/plans/p1"
ck "변이 1 try 제거 → J1 빨강(traceback · rc=$rc)" \
  "$([ "$rc" != 3 ] && grep -qi 'traceback\|TimeoutExpired' <<<"$out" && echo 0 || echo 1)"
mut M2 'return [], "판정기 rc=2" if r.returncode == 2 else "판정기 출력 꼴"' 'return [], None'
reset; scan "$T/mut-M2" "rc2" "$T/plans/p1"
ck "변이 2 rc 확인 제거 → J2 빨강(rc=$rc · rc=2 를 깨끗으로 셈)" \
  "$([ "$rc" = 0 ] && grep -q 'judge_unknown=0' <<<"$out" && echo 0 || echo 1)"
mut M3 'if r.returncode == 1 and rejects:' 'if r.returncode == 1 and rejects and False:'
reset; scan "$T/mut-M3" "reject" "$T/plans/p1"
ck "변이 3 rc1 도 판정 불가로 셈 → J6 빨강(rc=$rc)" \
  "$([ "$rc" = 3 ] && grep -q '판정 불가' <<<"$out" && echo 0 || echo 1)"

cmp -s "$BIN/ft-secret-scan.sh" "$KIT/ft-secret-scan.sh"; ck "kit 사본 cmp0" $?
[ "$(stat -f %Lp "$HERE/test_secret_scan_judge_timeout_r1341.sh")" = 644 ]; ck "새 시험 파일 모드 644(실행 비트 0)" $?
echo "RUN 1회차 $(secs "$t0")"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
