#!/usr/bin/env bash
# test_teamset_standby_r1119.sh — r1119: 오빠 판정(ft-seat-close --verdict)으로 arch 를 닫은 «대기 팀»은
# 팀장 교대(arch-live --seat)를 통과하고 teamset check 에서 ERR 이 아니다. 죽은 arch·빈 칸·자율 켜기(--team)는 그대로 막는다.
# 전부 mktemp 안 — 가짜 명부·가짜 TEAMSET 표·가짜 tmux(PATH). 실 tmux·실 명부 0 · 자기 재호출 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; SKL="$REPO/skill/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

MD="$T/TEAMSET.md"; ROOT="$T/root"; FAKE="$T/fake"; SESS="$T/sessions.txt"
mkdir -p "$ROOT/.fable-team" "$FAKE"
cat > "$MD" <<'EOF'
# 가짜 팀셋
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | a | b |
| arch | 상시 | `opus-5-5` | high | `_arch` | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: `_name` `_doc` `_closed`
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 3 | 0 | 상시 |
EOF
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
FM="$T/fake-mbox.sh"; printf '#!/bin/sh\nexit 0\n' > "$FM"
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
M="byz-alpha-master-claude#1"; RJ="$ROOT/.fable-team/seats-alpha.json"
# roster <_arch> <closed_from|-> <verdict|-> [추가 행 JSON 조각] — arch#3 행이 «닫힌 행»(stop-ready · 판정 닫힘)
roster() {
  python3 - "$RJ" "$M" "$1" "$2" "$3" "${4:-}" <<'PY'
import json, sys
p, m, arch, cf, vd, extra = sys.argv[1:7]
d = {"_name": "alpha", "_master": m, "_arch": arch, m: {"role": "master"}}
c = {"by": m, "at": "2026-10-29T14:47:44", "reason": "대기 팀 전환"}
if vd != "-":
    c["verdict"] = vd
row = {"role": "stop-ready", "_closed": c}
if cf != "-":
    row["_closed_from"] = [cf]
d["byz-alpha-arch-claude#3"] = row
if extra:
    d.update(json.loads(extra))
json.dump(d, open(p, "w"))
PY
}
run() { local b="$1"; shift; PATH="$FAKE:$PATH" FT_TEAMSET_MBOX="$FM" python3 "$b/ft_teamset.py" "$@" --root "$ROOT" --md "$MD" 2>&1; }
ABS="$ROOT/.fable-team/seats-alpha.json:_arch"; REL=".fable-team/seats-alpha.json:_arch"

# 반례 R1~R10 을 한 판(b = ft_teamset.py 가 있는 폴더)으로 돈다 · 결과 = 칸마다 «이름 P|F» 줄
cases() {
  local b="$1" o rc
  sess "$M"
  roster "" "$ABS" 2768;  o="$(run "$b" arch-live --seat "$M")"; rc=$?
  { [ $rc = 0 ] && [[ "$o" == "OK alpha _master · 대기(arch 닫힘 판정 2768 byz-alpha-arch-claude#3)" ]]; } && echo "R1 P $o" || echo "R1 F rc=$rc $o"
  roster "" "$REL" 2766;  o="$(run "$b" arch-live --seat "$M")"; rc=$?
  { [ $rc = 0 ] && [[ "$o" == *"대기(arch 닫힘 판정 2766"* ]]; } && echo "R2 P" || echo "R2 F rc=$rc $o"
  roster "byz-alpha-arch-claude#5" "$ABS" 2768; o="$(run "$b" arch-live --seat "$M")"; rc=$?
  { [ $rc = 3 ] && [[ "$o" == "NO alpha arch 없음 — 명부 _arch byz-alpha-arch-claude#5 라이브 아님"* ]]; } && echo "R3 P" || echo "R3 F rc=$rc $o"
  printf '{"_name":"alpha","_master":"%s","_arch":""}\n' "$M" > "$RJ"; o="$(run "$b" arch-live --seat "$M")"; rc=$?
  { [ $rc = 3 ] && [[ "$o" == "NO alpha arch 없음 — 명부 _arch 칸이 비었다"* ]]; } && echo "R4 P" || echo "R4 F rc=$rc $o"
  roster "" "$ABS" -; o="$(run "$b" arch-live --seat "$M")"; rc=$?
  [ $rc = 3 ] && echo "R5 P" || echo "R5 F rc=$rc $o"
  # R5b 가장 늦은 닫힘 행에 verdict 없음(앞선 행엔 있음) → rc3
  roster "" "$ABS" 2768 "{\"byz-alpha-arch-claude#4\":{\"role\":\"stop-ready\",\"_closed\":{\"at\":\"2026-10-29T15:00:00\"},\"_closed_from\":[\"$ABS\"]}}"
  o="$(run "$b" arch-live --seat "$M")"; rc=$?; [ $rc = 3 ] && echo "R5b P" || echo "R5b F rc=$rc $o"
  roster "" "$ABS" 2768 '{"byz-alpha-arch-claude#4":{"role":"arch"}}'; sess "$M" "byz-alpha-arch-claude#4"
  o="$(run "$b" arch-live --seat "$M")"; rc=$?; [ $rc = 3 ] && echo "R6 P" || echo "R6 F rc=$rc $o"
  sess "$M"
  roster "" "$ABS" 2768 '{"byz-alpha-arch-claude#1":{"role":"arch"},"byz-alpha-arch-claude#2":{"role":"arch"}}'
  o="$(run "$b" arch-live --seat "$M")"; rc=$?; { [ $rc = 0 ] && [[ "$o" == *"대기(arch 닫힘 판정 2768"* ]]; } && echo "R10 P" || echo "R10 F rc=$rc $o"
  roster "" "$ABS" 2768; o="$(run "$b" arch-live --team alpha)"; rc=$?
  { [ $rc = 3 ] && [[ "$o" == "NO alpha arch 없음"* ]]; } && echo "R7 P" || echo "R7 F rc=$rc $o"
  o="$(run "$b" check --team alpha)"; rc=$?
  { [ $rc = 0 ] && [[ "$o" == "alpha OK "*"대기(arch 닫힘 판정 2768)"* ]] && [[ "$o" != *"arch 없음"* ]]; } && echo "R8 P $o" || echo "R8 F rc=$rc $o"
  sess "byz-alpha-master-claude#9"; o="$(run "$b" check --team alpha)"; rc=$?
  { [ $rc = 1 ] && [[ "$o" == "alpha ERR "*"_master $M 라이브 아님"* ]]; } && echo "R8b P" || echo "R8b F rc=$rc $o"
  sess "$M"; roster "" "$ROOT/.fable-team/seats-other.json:_arch" 2768; o="$(run "$b" arch-live --seat "$M")"; rc=$?
  [ $rc = 3 ] && echo "R9 P" || echo "R9 F rc=$rc $o"
}

t0=$SECONDS
python3 -m py_compile "$BIN/ft_teamset.py" && ok "py_compile ft_teamset.py" || bad "py_compile"
# 기준판(바꾸기 전 꼴): R1 이 지금 «NO … _arch 칸이 비었다» rc3 이었다 — 그 문구는 R4 가 그대로 지킨다
out="$(cases "$BIN")"
while read -r name st rest; do
  [ "$st" = P ] && ok "$name ${rest:-}" || bad "$name ${rest:-}"
done <<<"$out"
echo "INFO green ${SECONDS}s"

# 변이 — 사본 폴더에서 판정 한 줄을 바꿔 해당 반례가 FAIL 하는지 본다(자기 재호출 0 · cases 함수만 다시 돈다)
mutant() {  # mutant <이름> <바꿀 문자열> <새 문자열> <FAIL 해야 할 반례>
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$BIN/ft_spawn_queue.py" "$d/"
  python3 - "$BIN/ft_teamset.py" "$d/ft_teamset.py" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s, "변이 대상 문자열 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  [ $? = 0 ] || { bad "변이 $1 — 대상 문자열 없음"; return; }
  grep -q "^$4 F" <<<"$(cases "$d")" && ok "변이 $1 → $4 FAIL" || bad "변이 $1 → $4 가 여전히 PASS(시험이 못 잡는다)"
}
mutant realpath 'os.path.realpath(os.path.join(root, f)) == me' 'f == str(roster_path(root, team))' R2
mutant no-live-check ' or any(k.startswith(f"byz-{team}-arch-") and k in live for k in d)' '' R6
mutant role-based 'any(k.startswith(f"byz-{team}-arch-") and k in live for k in d)' 'any(isinstance(v, dict) and v.get("role") == "arch" for v in d.values())' R10
echo "INFO 변이 ${SECONDS}s"

# 세 사본 같은 내용
for c in "$KIT/ft_teamset.py" "$SKL/ft_teamset.py"; do cmp -s "$BIN/ft_teamset.py" "$c" && ok "사본 cmp0 ${c#"$REPO"/}" || bad "사본 불일치 ${c#"$REPO"/}"; done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
