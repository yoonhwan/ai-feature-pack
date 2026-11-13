#!/bin/bash
# test_launchd_llm_gate_line_allow_r1867.sh — r1867: launchd LLM 판정기 허용 장부 4칸 줄(<라벨>\t<상대경로>\t<줄 sha16>\t<ts>) = 그 한 줄만 G4 통과
# ① x.py 한 줄 ["pi"] + 그 줄 4칸 허용 → ALLOW rc0 (기준판 = REJECT → Red)
# ② ① + 다른 파일 y.py ["claude"] → REJECT y.py (나머지 검사 켜짐)
# ③ ① 줄을 ["pi", "-x"] 로 바꿈 → REJECT (sha 다름)
# ④ 4칸 줄 ts 칸 = 오빠 → REJECT   ⑤ 4칸 줄 라벨 다름 → REJECT   ⑥ 2칸 라벨 줄(기존) → ALLOW
# ⑦ x.py 안 허용 줄 + 다른 줄 ["claude"] → REJECT x.py:2 (같은 파일 다른 줄 · DA 추가)
# ⑧ 꼴 틀림(3칸 · 5칸 · sha16 이 16 hex 아님) → REJECT (닫힌 쪽)   ⑨ bin·kit 같은 내용(cmp0)
# R1(DA HOLD #296326): ⑩ 4칸 둘째 칸 = ts(경로 불일치) → REJECT ⑪ 같은 줄 5칸 → REJECT ⑫ 정상 2칸 → ALLOW 유지
# 변이 = R1867_GATE=<변이판> 으로 같은 시험(M1 sha 대조 빼기 → ③ FAIL · M2 라벨 대조 빼기 → ⑤ FAIL · M3 self.allowed 켜기 → ② FAIL · M4 통째 허용 «2칸 이상» → ⑩⑪ FAIL)
# 임시 폴더·가짜 입력만 · 실 허용 장부·기준선·plist·launchctl 0 · 실행·네트워크 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin/ft_launchd_llm_gate.py"
KIT="$HERE/../kit/fable-team/bin/ft_launchd_llm_gate.py"
GATE="${R1867_GATE:-$BIN}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 — $2"; fail=$((fail+1)); }
TS=1763000000.123456
LINE='subprocess.run(["pi"])'
H16="$(printf '%s' "$LINE" | shasum -a 256 | cut -c1-16)"

# case <이름> <allow 내용> <파일=내용>... → 출력 1줄 · rc 를 $RC 에
case_run() {
  local d="$T/$1"; shift
  mkdir -p "$d/root"; printf '%b' "$1" > "$d/allow.tsv"; shift
  local kv; for kv in "$@"; do printf '%b' "${kv#*=}" > "$d/root/${kv%%=*}"; done
  OUT="$(python3 "$GATE" check --root-dir "$d/root" --allow "$d/allow.tsv" 2>&1)"; RC=$?
}
expect() {  # expect <번호> <rc> <출력 패턴>
  if [ "$RC" = "$2" ] && printf '%s' "$OUT" | grep -q -- "$3"; then ok "$1"; else bad "$1" "rc=$RC out=$OUT"; fi
}
X="x.py=import subprocess\n$LINE\n"
A4="ft2-current\tft2-current/x.py\t$H16\t$TS\n"

case_run c1 "$A4" "$X"
expect "① 4칸 허용 줄 → ALLOW" 0 "^ALLOW ft2-current"

case_run c2 "$A4" "$X" 'y.py=import subprocess\nsubprocess.run(["claude"])\n'
expect "② 다른 파일 y.py → REJECT" 1 "REJECT launchd-llm ft2-current 글자 그대로 LLM 호출 ft2-current/y.py:2"

case_run c3 "$A4" 'x.py=import subprocess\nsubprocess.run(["pi", "-x"])\n'
expect "③ 줄 바뀜(sha 다름) → REJECT" 1 "REJECT .* ft2-current/x.py:2"

case_run c4 "ft2-current\tft2-current/x.py\t$H16\t오빠\n" "$X"
expect "④ ts 칸 = 오빠 → REJECT" 1 "REJECT .* ft2-current/x.py:2"

case_run c5 "other-label\tft2-current/x.py\t$H16\t$TS\n" "$X"
expect "⑤ 라벨 다름 → REJECT" 1 "REJECT .* ft2-current/x.py:2"

case_run c6 "ft2-current\t$TS\n" "$X" 'y.py=import subprocess\nsubprocess.run(["claude"])\n'
expect "⑥ 2칸 라벨 줄(기존 뜻) → ALLOW" 0 "^ALLOW ft2-current"

case_run c7 "$A4" "x.py=import subprocess\n$LINE\nsubprocess.run([\"claude\"])\n"
expect "⑦ 같은 파일 다른 LLM 줄 → REJECT x.py:3" 1 "REJECT .* ft2-current/x.py:3"

case_run c8a "ft2-current\tft2-current/x.py\t$H16\n" "$X"
expect "⑧ⓐ 3칸 → REJECT" 1 "REJECT .* ft2-current/x.py:2"
case_run c8b "ft2-current\tft2-current/x.py\t$H16\t$TS\textra\n" "$X"
expect "⑧ⓑ 5칸 → REJECT" 1 "REJECT .* ft2-current/x.py:2"
case_run c8c "ft2-current\tft2-current/x.py\t${H16%?}Z\t$TS\n" "$X"
expect "⑧ⓒ sha16 hex 아님 → REJECT" 1 "REJECT .* ft2-current/x.py:2"

Y='y.py=import subprocess\nsubprocess.run(["claude"])\n'
case_run c10 "ft2-current\t$TS\t$H16\t$TS\n" "$X" "$Y"
expect "⑩ 4칸 둘째 칸 = ts(경로 불일치) → REJECT" 1 "REJECT .* ft2-current/x.py:2"
case_run c11 "ft2-current\t$TS\t$H16\t$TS\textra\n" "$X" "$Y"
expect "⑪ 5칸(둘째 칸 = ts) → REJECT" 1 "REJECT .* ft2-current/x.py:2"
case_run c12 "ft2-current\t$TS\n" "$X" "$Y"
expect "⑫ 정상 2칸 → ALLOW 유지" 0 "^ALLOW ft2-current"

if cmp -s "$BIN" "$KIT"; then ok "⑨ bin·kit 같은 내용"; else bad "⑨ bin·kit" "cmp 다름"; fi

echo "fail=$fail"
[ "$fail" -eq 0 ]
