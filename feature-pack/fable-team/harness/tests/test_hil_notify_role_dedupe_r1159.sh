#!/usr/bin/env bash
# test_hil_notify_role_dedupe_r1159.sh — r1159: ft-hil-notify done 수신자 거르기 = 역할 키(끝 #N 뺀 이름 · mbox_conf.role_key).
# 가짜 쪽지함 폴더(가짜 mbox.sh = 받은 to 를 파일에 적고 · 같은 역할 키 두 번째는 rc1 = RESEND_COOLDOWN 흉내 · REJECT_TO 는 진짜 거절)
# + 가짜 seats-planner.json · 가짜 h 접두(.out) — 실 우편함 0 · 자기 재호출 0 · 고정 sleep 0.
# 빨강 대조: FT_HIL_NOTIFY_BIN=<base 사본>/ft-hil-notify.sh 로 돌리면 ⓐ 가 FAIL 한다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../bin/ft-hil-notify.sh"
BIN="${FT_HIL_NOTIFY_BIN:-$SRC}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 가짜 세계: <w>/comm/mbox.sh · <w>/seats-planner.json · <w>/h1(.out)
world() {  # <폴더> <planner _master>
  mkdir -p "$1/comm"
  cat > "$1/comm/mbox.sh" <<'SH'
#!/usr/bin/env bash
d="$(cd -- "$(dirname -- "$0")" && pwd)"; to="$2"; k="$(printf '%s' "$to" | sed -E 's/#[0-9]+$//')"
case " ${REJECT_TO:-} " in *" $to "*) exit 1;; esac
grep -qxF "$k" "$d/keys" 2>/dev/null && exit 1
echo "$k" >> "$d/keys"; echo "$to" >> "$d/sent"
SH
  printf '{"_master":"%s"}\n' "$2" > "$1/seats-planner.json"
  printf '# ft-hil-entry plan=/p/plan.sh.hil\n' > "$1/h1"; printf 'x\n=== 결과 === OK\n' > "$1/h1.out"
}
run() {  # <bin> <폴더> <좌석…> → stdout «rc|보낸 줄 수|보낸 이름|stderr»
  local b="$1" w="$2" rc e; shift 2
  e="$(env -i PATH="/usr/bin:/bin" REJECT_TO="${REJECT_TO:-}" bash "$b" done "$w/h1" 0 "$w/comm" "$@" 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s|%s|%s' "$rc" "$(wc -l < "$w/comm/sent" 2>/dev/null | tr -d ' ' || echo 0)" "$(tr '\n' ' ' < "$w/comm/sent" 2>/dev/null)" "$e"
}
s=$(date +%s)

echo "== ⓐ R1 같은 역할(S=X#1 · _master=X#2) = 1통(to=X#1) · rc0 · «rc≠0» 0"
world "$T/r1" 'byz-planner-master-claude#2'; o="$(run "$BIN" "$T/r1" 'byz-planner-master-claude#1')"
[ "$o" = "0|1|byz-planner-master-claude#1 |" ] && ok "R1 = $o" || bad "R1 = $o"

echo "== ⓐ R3 같은 이름(S=X#2 · _master=X#2) = 1통 · rc0"
world "$T/r3" 'byz-planner-master-claude#2'; o="$(run "$BIN" "$T/r3" 'byz-planner-master-claude#2')"
[ "$o" = "0|1|byz-planner-master-claude#2 |" ] && ok "R3 = $o" || bad "R3 = $o"

echo "== ⓑ R2 다른 역할(S=Y#5 · _master=X#2) = 2통 · rc0"
world "$T/r2" 'byz-planner-master-claude#2'; o="$(run "$BIN" "$T/r2" 'byz-harness-master-claude#5')"
[ "$o" = "0|2|byz-harness-master-claude#5 byz-planner-master-claude#2 |" ] && ok "R2 = $o" || bad "R2 = $o"

echo "== ⓒ R4 진짜 거절(Y#5 rc1) = stderr «mbox send rc≠0 to=Y#5» · rc1"
world "$T/r4" 'byz-planner-master-claude#2'; o="$(REJECT_TO='byz-harness-master-claude#5' run "$BIN" "$T/r4" 'byz-harness-master-claude#5')"
case "$o" in "1|1|byz-planner-master-claude#2 |ft-hil-notify 판정 불가 — mbox send rc≠0 to=byz-harness-master-claude#5") ok "R4 = $o";; *) bad "R4 = $o";; esac

echo "== ⓓ bin·kit 같은 내용"
cmp -s "$SRC" "$HERE/../kit/fable-team/bin/ft-hil-notify.sh" && ok "ft-hil-notify.sh cmp 0" || bad "kit 다름"

echo "== 변이: 거르기 키를 «이름 그대로» 로 되돌림 → R1 rc1 = FAIL(검출)"
M="$T/mut.sh"; sed '/BASH_REMATCH\[1\]/s/; \[\[ .* && k="\${BASH_REMATCH\[1\]}"$//' "$SRC" > "$M"
! cmp -s "$SRC" "$M" && ok "변이 사본이 원본과 다르다" || bad "변이 사본 = 원본"
world "$T/m1" 'byz-planner-master-claude#2'; o="$(run "$M" "$T/m1" 'byz-planner-master-claude#1')"
case "$o" in "1|1|"*"rc≠0 to=byz-planner-master-claude#2"*) ok "변이: R1 rc1 · 두 번째 거절 WARN = ⓐ FAIL";; *) bad "변이가 R1 을 못 깬다: $o";; esac

echo "단계 초: 전체 $(( $(date +%s) - s ))"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
