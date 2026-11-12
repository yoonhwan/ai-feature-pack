#!/usr/bin/env bash
# test_card_flow_observe_wait_r1715.sh — r1715: ft-card-flow --gate 상한 셈이 «관찰 대기» 카드를 세지 않는다
#   관찰 대기 = 진행 카드에 «- 착지: <sha>» ∧ «- 대기 사건: <값>» ∧ «- 마감 기준: <값>» 세 줄이 다 있는 카드(C1)
#   셈 = 진행 P − 관찰 대기 K · 상한 식(max(바닥, 좌석+2))은 그대로(C2)
#   두 줄 중 하나라도 없거나(C3) 값이 비면 셈에 든다 · 착지 줄이 없으면 셈에 든다(C4)
#   카드 읽기 실패 = 확인 불가 rc3(관찰 대기로 빼지 않음 · C5) · 문구 = «진행 P(좌석 M · 관찰 대기 K)»(C6)
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)만. 실 좌석·실 카드·실 tmux 0. 사례 70초·sleep 0·자기 재호출 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_CAP_FLOOR FT_CARD_CAP_OK FT_FINISHED_MAIN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$BIN/ft-card-flow.sh" && ok "bash -n" || bad "bash -n"
cmp -s "$BIN/ft-card-flow.sh" "$KIT/ft-card-flow.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
CF="$KIT/ft-card-flow.sh"

# 가짜 tmux — 세션 목록 = $SESS 파일(없으면 서버 없음)
FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE"
printf '#!/bin/sh\n[ -f "%s" ] || { echo "no server running on /tmp/x" >&2; exit 1; }\ncase "$1" in ls) cat "%s";; *) exit 1;; esac\n' "$SESS" "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
sess(){ : > "$SESS"; }

R="$T/repo"; mkdir -p "$R"/design/alpha/indices/{대기,진행}; git init -q -b main "$R"
G(){ git -C "$R" -c user.name=t -c user.email=t@t "$@"; }; echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base
LANDED="$(G rev-parse HEAD)"
export FT_FINISHED_MAIN=main
card(){ printf '# %s\n%s## 상태\n대기\n' "$2" "${3:-}" > "$R/design/alpha/indices/$1/$2.md"; }
mkprog(){ local n="$1" i; rm -rf "$R"/design/alpha/indices/진행; mkdir -p "$R/design/alpha/indices/진행"; for i in $(seq 1 "$n"); do card 진행 "p$i"; done; }
# 관찰 대기 카드 4꼴 — 세 줄 다 · 마감 기준 없음 · 마감 기준 값 빈칸 · 착지 줄 없음
obs_full(){ card 진행 "$1" "- 착지: $LANDED
- 대기 사건: 설치 뒤 --gate 가 rc 0 인가(ft-card-flow --gate 실측)
- 마감 기준: $2 까지 안 오면 master 에 1줄
"; }
obs_nodue(){ card 진행 "$1" "- 착지: $LANDED
- 대기 사건: 설치 뒤 --gate 가 rc 0 인가(ft-card-flow --gate 실측)
"; }
obs_blank(){ card 진행 "$1" "- 착지: $LANDED
- 대기 사건: 설치 뒤 --gate 가 rc 0 인가(ft-card-flow --gate 실측)
- 마감 기준:   
"; }
obs_noland(){ card 진행 "$1" "- 대기 사건: 설치 뒤 --gate 가 rc 0 인가(ft-card-flow --gate 실측)
- 마감 기준: 11-20 까지 안 오면 master 에 1줄
"; }
run(){ PATH="$FAKE:$PATH" bash "$CF" --team alpha --root "$R" --dir "$R/design/alpha" "$@" 2>&1; }

# ① 진행 12 · 관찰 대기 3(세 줄 다) → P 9 ≤ 10 → rc0 · 기본 줄 «진행 9(좌석 0 · 관찰 대기 3)»   (기준판 = REJECT rc4 · FAIL)
mkprog 9; obs_full o1 11-20; obs_full o2 11-21; obs_full o3 11-22; sess
o="$(run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *REJECT* ]] && [[ "$o" == *"관찰 대기 3"* ]]; } && ok "① 진행 12 · 관찰 대기 3 → P 9 ≤ 10 → rc0" || bad "① rc=$rc «${o:0:200}»"
o="$(run)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 9(좌석 0 · 관찰 대기 3) · 착지됐는데 진행 3" ]; } && ok "① 기본 줄 = 진행 9(좌석 0 · 관찰 대기 3) · K 3" || bad "① 기본 «${o}»"

# ② 진행 12 · «대기 사건» 만 있고 «마감 기준» 없음 3 → P 12 > 10 → REJECT rc4 (C2)
mkprog 9; obs_nodue n1; obs_nodue n2; obs_nodue n3; sess
o="$(run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *REJECT* ]] && [[ "$o" == *"진행 12(좌석 0 · 관찰 대기 0)"* ]]; } && ok "② «마감 기준» 없는 3장은 셈에 든다 → 진행 12 → REJECT rc4" || bad "② rc=$rc «${o:0:200}»"

# ③ «마감 기준:» 값 빈칸 → 셈에 든다(C3) — 진행 11 > 10 → rc4
mkprog 10; obs_blank b1; sess
o="$(run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *REJECT* ]] && [[ "$o" == *"진행 11(좌석 0 · 관찰 대기 0)"* ]]; } && ok "③ «마감 기준» 값 빈칸 → 셈에 든다 → 진행 11 → rc4" || bad "③ rc=$rc «${o:0:200}»"

# ④ 착지 줄 없이 두 줄만 → 셈에 든다(C4) — 진행 11 > 10 → rc4
mkprog 10; obs_noland l1; sess
o="$(run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *REJECT* ]] && [[ "$o" == *"진행 11(좌석 0 · 관찰 대기 0)"* ]]; } && ok "④ 착지 줄 없는 카드 → 셈에 든다 → rc4" || bad "④ rc=$rc «${o:0:200}»"

# ⑤ 관찰 대기 카드가 읽기 실패(EISDIR) → 확인 불가 rc3 · 막지 않음(C5)
mkprog 2; mkdir -p "$R/design/alpha/indices/진행/obsbad.md"; sess
o="$(run --gate)"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"판정 불가"* ]] && [[ "$o" == *"막지 않음"* ]] && [[ "$o" != *REJECT* ]]; } && ok "⑤ 관찰 대기 카드 읽기 실패 → rc3 판정 불가(막지 않음)" || bad "⑤ rc=$rc «${o:0:200}»"

# ⑥ 관찰 대기 0 → rc 앞 판과 같음 · 문구는 «관찰 대기 0» 덧붙임만 다름(C6)
mkprog 4; sess
o="$(run)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 4(좌석 0 · 관찰 대기 0) · 착지됐는데 진행 0" ]; } && ok "⑥ 관찰 대기 0 → 문구만 덧붙임 · rc0" || bad "⑥ rc=$rc «${o}»"
o="$(run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *REJECT* ]]; } && ok "⑥ --gate 관찰 대기 0 → rc0(앞 판과 같음)" || bad "⑥ gate rc=$rc «${o:0:160}»"

# ── 변이 3종(사본에서만 · 각 변이마다 원본으로 같은 사례 1회 대조) ──
mut(){ python3 - "$CF" "$T/$1.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mrun(){ PATH="$FAKE:$PATH" bash "$T/$1.sh" --team alpha --root "$R" --dir "$R/design/alpha" "${@:2}" 2>&1; }
mut m1 "and obs_line(body,'마감 기준')" ""             # M1: «마감 기준» 검사 삭제
[ -f "$T/m1.sh" ] && bash -n "$T/m1.sh" && ok "M1 bash -n rc0" || bad "M1 변이·bash -n 실패"
mkprog 9; obs_nodue n1; obs_nodue n2; obs_nodue n3; sess
o="$(run --gate)"; rc=$?; [ "$rc" = 4 ] && ok "M1 원본 대조 — ② rc4" || bad "M1 원본 대조 rc=$rc «${o:0:160}»"
o="$(mrun m1 --gate)"; rc=$?
[ "$rc" = 0 ] && ok "M1 «마감 기준» 검사 삭제 → ② 검출(rc0 ≠ 4)" || bad "M1 검출 실패 rc=$rc «${o:0:160}»"
mut m2 "r':[ \\t]*(\\S)'" "r':[ \\t]*(.*)'"             # M2: 값 빈칸 검사 삭제
[ -f "$T/m2.sh" ] && bash -n "$T/m2.sh" && ok "M2 bash -n rc0" || bad "M2 변이·bash -n 실패"
mkprog 10; obs_blank b1; sess
o="$(run --gate)"; rc=$?; [ "$rc" = 4 ] && ok "M2 원본 대조 — ③ rc4" || bad "M2 원본 대조 rc=$rc «${o:0:160}»"
o="$(mrun m2 --gate)"; rc=$?
[ "$rc" = 0 ] && ok "M2 값 빈칸 검사 삭제 → ③ 검출(rc0 ≠ 4)" || bad "M2 검출 실패 rc=$rc «${o:0:160}»"
mut m3 "bool(m) and " ""                                # M3: 착지 줄 검사 삭제
[ -f "$T/m3.sh" ] && bash -n "$T/m3.sh" && ok "M3 bash -n rc0" || bad "M3 변이·bash -n 실패"
mkprog 10; obs_noland l1; sess
o="$(run --gate)"; rc=$?; [ "$rc" = 4 ] && ok "M3 원본 대조 — ④ rc4" || bad "M3 원본 대조 rc=$rc «${o:0:160}»"
o="$(mrun m3 --gate)"; rc=$?
[ "$rc" = 0 ] && ok "M3 착지 줄 검사 삭제 → ④ 검출(rc0 ≠ 4)" || bad "M3 검출 실패 rc=$rc «${o:0:160}»"

# ⓖ 회귀 — 기존 card_flow 시험 FAIL 줄이 앞 판과 같다(새 FAIL 0)
m="$(timeout 70 bash "$HERE/test_card_flow_team_ref_r1256.sh" 2>&1 | grep -c '^FAIL ')"
[ "$m" = 0 ] && ok "ⓖ 회귀 r1256 FAIL 0" || bad "ⓖ 회귀 r1256 FAIL $m"
n="$(timeout 70 bash "$HERE/test_card_flow_cap_floor_r1693.sh" 2>&1 | grep -c '^FAIL ')"
[ "$n" = 0 ] && ok "ⓖ 회귀 r1693 FAIL 0" || bad "ⓖ 회귀 r1693 FAIL $n"
if [ -n "${FT_R1715_FULL:-}" ]; then   # r954 19초 · r1292 16초 — 단독 예산 밖: 이 표식이 있을 때만 함께 본다
  k="$(timeout 70 bash "$HERE/test_card_flow_r954.sh" 2>&1 | grep '^FAIL ' | grep -vc '^FAIL ⓔ')"
  [ "$k" = 0 ] && ok "ⓖ 회귀 r954 — 기존 ⓔ(spawn 게이트) 밖 새 FAIL 0" || bad "ⓖ 회귀 r954 새 FAIL $k"
  c="$(timeout 70 bash "$HERE/test_card_cap_gate_r1292.sh" 2>&1 | grep '^FAIL ' | grep -v '^FAIL R' | grep -vc '^FAIL 변이 2 — R1 가 변이를 못 잡음')"   # 변이 2 줄은 앞 판에도 있다(sed 대상 «-gt $((seat + 2))» 가 이미 없는 줄)
  [ "$c" = 0 ] && ok "ⓖ 회귀 r1292 — 기존 R·변이 2 밖 새 FAIL 0" || bad "ⓖ 회귀 r1292 새 FAIL $c"
else ok "ⓖ 회귀 r954·r1292 — FT_R1715_FULL=1 일 때만(단독 19·16초 · 보고에서 따로 비교)"; fi
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
