#!/usr/bin/env bash
# test_mbox_show_r2081.sh — r2081 A: `mbox.sh show <번호>[,…]` = 큐·보낸 기록·회전본·전문 파일을 한 번에 읽고 «어디에 있다/없다» 를 답한다.
#   ① 네 자리(큐만 · 기록만 · 기록.1 만 · 큐+기록) = FOUND 자리 칸 · rc 0 · 실행 앞뒤 폴더 바이트 같음
#   ② 900자 본문 = 앞 300자 + `전문:` 글자 수 = 파일 글자 수 · 번호 6개 = rc 2 · 출력 1줄
#   ③ 빈 번호 = NONE 범위 칸 · rc 1 · 옛 번호 = «보관 범위보다 옛 번호» · FOUND 1 + NONE 1 = rc 1
#   ④ 기록.1 깨진 줄 + 못 찾음 = 판정 불가 rc 3 · 다른 곳에서 찾음 = FOUND «깨진 줄 1» rc 0 · 깨진 줄뿐인 기록(JSON 아닌 줄 3개) = rc 3 · 큐 없음 = 정상 판정
# 변이(사본에만): M1 회전본 읽기 지움 → ① 빨강 · M2 깨진 줄을 조용히 건너뜀 → ④ 빨강
# 기준판 = MBOX_SRC=<팩 origin/main 의 harness/comm 사본> 로 돌린다(동사 없음 = ① Red).
set -uo pipefail   # 실 우편함·실 명부·실 tmux 0 · sleep 0 · 코드 사본($T/code)과 우편함($T/*/comm)을 갈라 __pycache__ 가 폴더 비교에 안 섞인다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${MBOX_SRC:-$HERE/../comm}"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

new_env() {   # 코드 사본 1벌 + 빈 우편함 폴더 · MUT = 사본 변이
  CODE="$(mktemp -d "$T/code.XXXXXX")"; cp -R "$SRC"/. "$CODE/"
  C="$(mktemp -d "$T/env.XXXXXX")/comm"; mkdir -p "$C"; L="$C/mailbox.log.jsonl"
  printf '{}\n' > "$T/seats.json"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
row() {   # row <파일> <seq> [본문] — 시험 준비(제품 경로 아님)
  printf '{"seq": %d, "ts": "2026-11-15T22:49:%02d", "to": "byz-x-desk-pi#1", "from": "byz-x-planner-pi#3", "body": "%s"}\n' \
    "$2" "$(( $2 % 60 ))" "${3:-본문 $2}" >> "$1"
}
show() { FT_SEATS_JSON="$T/seats.json" FT_MBOX_DIR="$C" bash "$CODE/mbox.sh" show "$@" >"$T/out" 2>"$T/err"; RC=$?; }
snap() { (cd "$C" && find . -print | sort && find . -type f -exec shasum {} + | sort); }

mut_m1() { python3 - "$CODE/mbox_show.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); old = ' + [("기록.%d" % n, "%s.%d" % (log, n)) for n in rot]'
assert old in s; open(p, "w").write(s.replace(old, ""))
PY
}
mut_m2() { python3 - "$CODE/mbox_show.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); old = "if why or broken:"
assert old in s; open(p, "w").write(s.replace(old, "if why:").replace('" · 깨진 줄 %d" % broken if broken else ""', '""'))
PY
}

one() {   # ① 네 자리
  new_env; row "$C/mailbox.jsonl" 101; row "$L" 102; row "$L.1" 103; row "$C/mailbox.jsonl" 104; row "$L" 104
  local before; before="$(snap)"; show 101,102,103,104
  local f1 f2 f3 f4; f1="$(grep -c '^FOUND #101 2026-11-15T22:49:41 byz-x-planner-pi#3 -> byz-x-desk-pi#1 자리=큐(안 읽음)$' "$T/out")"
  f2="$(grep -c '^FOUND #102 .* 자리=기록$' "$T/out")"; f3="$(grep -c '^FOUND #103 .* 자리=기록\.1$' "$T/out")"
  f4="$(grep -c '^FOUND #104 .* 자리=큐(안 읽음)+기록$' "$T/out")"
  if [ "$RC" = 0 ] && [ "$f1$f2$f3$f4" = 1111 ] && [ "$before" = "$(snap)" ] && grep -q '^본문 103$' "$T/out"; then
    ok "① 큐·기록·기록.1·큐+기록 넷 다 FOUND · 자리 칸 맞음 · rc 0 · 폴더 바이트 같음"; return 0; fi
  bad "① rc=$RC f=$f1$f2$f3$f4 out=$(tr '\n' '|' < "$T/out") err=$(tr '\n' '|' < "$T/err")"; return 1
}

two() {   # ② 전문 · 인자 상한
  new_env; local body; body="$(python3 -c 'print("가" * 900, end="")')"; mkdir -p "$C/bodies"
  printf '%s' "$body" > "$C/bodies/110.txt"; row "$L" 110 "$body"
  show 110; local l2 full; l2="$(sed -n 2p "$T/out")"; full="$(grep -c "^전문: $C/bodies/110.txt (900자)$" "$T/out")"
  local r1=$RC n2; n2="$(python3 -c 'import sys; print(len(sys.argv[1]))' "$l2")"
  show 1,2,3,4,5,6; local r2=$RC lines; lines="$(cat "$T/out" "$T/err" | grep -c .)"
  if [ "$r1" = 0 ] && [ "$n2" = 300 ] && [ "$full" = 1 ] && [ "$r2" = 2 ] && [ "$lines" = 1 ]; then
    ok "② 본문 앞 300자 + 전문: (900자) · 번호 6개 = rc 2 · 출력 1줄"; return 0; fi
  bad "② r1=$r1 n2=$n2 full=$full r2=$r2 lines=$lines"; return 1
}

three() {   # ③ 없음 · 옛 번호 · 섞임
  new_env; row "$L" 100; row "$L" 120; row "$L" 200
  show 150; local r1=$RC o1; o1="$(cat "$T/out")"
  show 50; local r2=$RC o2; o2="$(cat "$T/out")"
  show 100,150; local r3=$RC o3; o3="$(cat "$T/out")"
  if [ "$r1" = 1 ] && [ "$o1" = "NONE #150 — 읽은 곳 1개 · 기록 범위 #100~#200" ] && [ "$r2" = 1 ] \
     && [ "$o2" = "NONE #50 — 읽은 곳 1개 · 기록 범위 #100~#200 · 보관 범위보다 옛 번호" ] && [ "$r3" = 1 ] \
     && [ "$(grep -c '^FOUND #100 ' <<<"$o3")" = 1 ] && [ "$(grep -c '^NONE #150 ' <<<"$o3")" = 1 ]; then
    ok "③ NONE 범위 칸 · rc 1 · 옛 번호 꼬리 · FOUND 1 + NONE 1 = rc 1"; return 0; fi
  bad "③ r1=$r1 o1=[$o1] r2=$r2 o2=[$o2] r3=$r3 o3=[$(tr '\n' '|' <<<"$o3")]"; return 1
}

four() {   # ④ 판정 불가
  new_env; row "$L" 300; row "$L.1" 290; printf '{"seq": 29' >> "$L.1"; printf '\n' >> "$L.1"
  show 301; local r1=$RC o1; o1="$(cat "$T/out")"
  show 300; local r2=$RC o2; o2="$(head -1 "$T/out")"
  new_env; printf '깨진 줄 1\n{not json\n]]\n' > "$L"   # 보낸 기록 = 일반 파일 · JSON 아닌 줄 3개뿐(하드 룰 19 · 폴더 입력은 범위 밖)
  show 999; local r3=$RC o3; o3="$(cat "$T/out")"
  if [ "$r1" = 3 ] && [[ "$o1" == "판정 불가 #301 — 깨진 줄 1" ]] && [ "$r2" = 0 ] && [[ "$o2" == "FOUND #300 "*" 자리=기록 · 깨진 줄 1" ]] \
     && [ "$r3" = 3 ] && [ "$o3" = "판정 불가 #999 — 깨진 줄 3" ]; then
    ok "④ 깨진 줄 + 못 찾음 = 판정 불가 rc 3 · 찾음 = FOUND «깨진 줄 1» rc 0 · 깨진 줄뿐인 기록(JSON 아닌 줄 3개) = rc 3 · 큐 없음 = ③ 정상 판정"; return 0; fi
  bad "④ r1=$r1 o1=[$o1] r2=$r2 o2=[$o2] r3=$r3 o3=[$o3]"; return 1
}

e=$(date +%s); one; two; three; four; echo "RUN 사례 $(( $(date +%s) - e ))초"
if [ -z "${MBOX_SRC:-}" ]; then
  echo "--- 변이 대조(빨강이어야 정상 · 원본 결과 = 위 PASS)"
  for m in mut_m1:one mut_m2:four; do
    rc=0; ( MUT=${m%:*}; ${m#*:} ) >/dev/null 2>&1 || rc=$?
    if [ "$rc" != 0 ]; then echo "RED-OK ${m%:*} (${m#*:} FAIL)"; else echo "RED-MISS ${m%:*}"; fail=$((fail+1)); fi
  done
fi
echo "결과: fail=$fail"
[ "$fail" = 0 ]
