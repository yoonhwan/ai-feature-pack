#!/usr/bin/env bash
# test_mbox_keep_seat_lint_shim_r1914.sh — r1914: 루트 bin 의 ft-name-lint.sh 가 r1694 shim 이어도
#   mbox_keep.seat() 가 LIVE_BIN 쪽 진짜 lint 의 ROLES·AGENTS 를 읽는다(BYZ 실측: shim 이라 seat 언제나 False).
#   ① shim + LIVE_BIN(절대·대상 있음) → 실 좌석 True · byz-tool#0 False
#   ② LIVE_BIN 없음·빈 줄·상대경로·대상 없음 → 전부 False · 예외 0
#   ⑤ ① 루트 자기 [완료·닫기 요청] kind 3(HUMAN)  ⑥ ① 루트 좌석 [완료] kind 3(HUMAN)
#   ④ FT_NAME_LINT env = 그 파일 그대로(shim 판정 0)   ③ 지금 팩 꼴 = 기존 test_mbox_keep_human_mail.sh 몫
#   M1 shim 판정 줄을 끄면(if True) ① 이 FAIL 해야 한다 — 사본에만 적용.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$HERE/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/live/bin"; cp "$H/bin/ft-name-lint.sh" "$T/live/bin/"   # 진짜 lint(ROLES·AGENTS 있음)
mk() {   # mk <이름> <LIVE_BIN 내용|-(파일 없음)> [변이 sed] — 임시 루트 = bin/shim + LIVE_BIN + comm/mbox_keep.py 사본
  local r="$T/$1"; mkdir -p "$r/bin" "$r/comm"
  printf '#!/usr/bin/env bash\n# ft-root-bin-shim: ft-name-lint.sh → LIVE_BIN (시험 사본)\nexec true\n' > "$r/bin/ft-name-lint.sh"
  [ "$2" = - ] || printf '%s\n' "$2" > "$r/LIVE_BIN"
  cp "$H/comm/mbox_keep.py" "$r/comm/"; [ -z "${3:-}" ] || sed -i.o "$3" "$r/comm/mbox_keep.py"
}
cat > "$T/probe.py" <<'PY2'
import mbox_keep as m
a = "byz-harness-arch-pi#344"
self_done = m.kind({"from": a, "to": a, "body": "[완료·닫기 요청] r1914"})
seat_done = m.kind({"from": a, "to": "byz-harness-master-pi#252", "body": "[완료] r1914"})
print(f"arch={m.seat(a)} tool={m.seat('byz-tool#0')} self={self_done} done={seat_done}")
PY2
seats() {   # seats <이름> — "arch=<bool> tool=<bool> self=<kind> done=<kind>" 1줄 · 예외면 rc≠0
  (cd "$T/$1/comm" && env PYTHONPATH=. ${LINTENV:+FT_NAME_LINT="$LINTENV"} python3 "$T/probe.py" 2>&1)
}
want() {   # want <칸> <이름> <기대 줄>
  local out; out="$(seats "$2")"; rc=$?
  if [ $rc -eq 0 ] && [ "$out" = "$3" ]; then ok "$1 ($out)"; else bad "$1 rc=$rc got=[$out] want=[$3]"; fi
}
mk r1 "$T/live/bin"; want "①⑤⑥ shim + LIVE_BIN → 진짜 lint · 완료 쪽지 HUMAN" r1 "arch=True tool=False self=3 done=3"
mk r2a -;                want "② LIVE_BIN 없음" r2a "arch=False tool=False self=0 done=2"
mk r2b "";               want "② LIVE_BIN 빈 줄" r2b "arch=False tool=False self=0 done=2"
mk r2c "live/bin";       want "② LIVE_BIN 상대경로" r2c "arch=False tool=False self=0 done=2"
mk r2d "$T/nowhere/bin"; want "② LIVE_BIN 대상 없음" r2d "arch=False tool=False self=0 done=2"
LINTENV="$T/live/bin/ft-name-lint.sh" want "④ env = 진짜 lint" r2a "arch=True tool=False self=3 done=3"
LINTENV="$T/r1/bin/ft-name-lint.sh" want "④ env = shim 그대로(판정 0)" r1 "arch=False tool=False self=0 done=2"
mk m1 "$T/live/bin" 's/if "ft-root-bin-shim:" not in .*# r1914 shim 판정$/if True:/'
if grep -q '^ *if True:' "$T/m1/comm/mbox_keep.py" && [ "$(seats m1)" = "arch=False tool=False self=0 done=2" ]; then
  ok "M1 shim 판정 끔 → ① 빨강 확인"; else bad "M1 변이가 안 잡힘($(seats m1))"; fi
[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAILED $fail"; exit 1
