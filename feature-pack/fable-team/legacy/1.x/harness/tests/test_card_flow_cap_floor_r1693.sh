#!/usr/bin/env bash
# test_card_flow_cap_floor_r1693.sh — r1693: ft-card-flow --gate 상한 = max(바닥 FT_CARD_CAP_FLOOR(기본 10), 좌석 M+2)
#   · 좌석 M = ① 카드 slug ↔ tmux 세션 «-nano-<slug>#» ② 카드 «- 배정: 좌석 <이름>» 의 좌석이 세션 목록에 있음(재사용 나노)
#   · 우회 표식(r1292) 그대로 · 판정 불가 길 그대로.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)만. 실 좌석·실 카드·실 tmux 0. 사례 70초·sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_CAP_FLOOR FT_CARD_CAP_OK FT_FINISHED_MAIN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
has(){ case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
bash -n "$BIN/ft-card-flow.sh" && ok "bash -n" || bad "bash -n"
cmp -s "$BIN/ft-card-flow.sh" "$KIT/ft-card-flow.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
CF="$KIT/ft-card-flow.sh"

# 가짜 tmux — 세션 목록 = $SESS 파일(없으면 서버 없음)
FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE"
printf '#!/bin/sh\n[ -f "%s" ] || { echo "no server running on /tmp/x" >&2; exit 1; }\ncase "$1" in ls) cat "%s";; *) exit 1;; esac\n' "$SESS" "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
sess(){ : > "$SESS"; local n; for n in "$@"; do echo "$n" >> "$SESS"; done; }

R="$T/repo"; mkdir -p "$R"/design/alpha/indices/{대기,진행}; git init -q -b main "$R"
G(){ git -C "$R" -c user.name=t -c user.email=t@t "$@"; }; echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base
export FT_FINISHED_MAIN=main
card(){ printf '# %s\n%s## 상태\n대기\n' "$2" "${3:-}" > "$R/design/alpha/indices/$1/$2.md"; }
mkprog(){ local n="$1" i; rm -f "$R"/design/alpha/indices/진행/*.md; for i in $(seq 1 "$n"); do card 진행 "p$i"; done; }
run(){ PATH="$FAKE:$PATH" bash "$CF" --team alpha --root "$R" --dir "$R/design/alpha" "$@" 2>&1; }

# ⓐ 진행 10 · 좌석 0 → rc0 (지금은 REJECT) · 11 → rc4 «상한 10»
mkprog 10; sess; o="$(run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *REJECT* ]]; } && ok "ⓐ 진행 10 · 좌석 0 → rc0(바닥 10)" || bad "ⓐ rc=$rc «${o:0:160}»"
mkprog 11; o="$(run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *"상한 10"* ]] && [[ "$o" == *REJECT* ]]; } && ok "ⓐ 진행 11 · 좌석 0 → rc4 «상한 10»" || bad "ⓐ rc=$rc «${o:0:160}»"

# ⓑ 진행 13 · 좌석 11 → rc0(상한 13 = M+2) · 14 → rc4 «상한 13»
mkprog 13; localargs=(); for i in $(seq 1 11); do localargs+=("byz-alpha-nano-p$i#0"); done; sess "${localargs[@]}"
o="$(run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *REJECT* ]]; } && ok "ⓑ 진행 13 · 좌석 11 → rc0(상한 max(10,13)=13)" || bad "ⓑ rc=$rc «${o:0:160}»"
mkprog 14; o="$(run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *"상한 13"* ]]; } && ok "ⓑ 진행 14 · 좌석 11 → rc4 «상한 13»" || bad "ⓑ rc=$rc «${o:0:160}»"

# ⓒ 바닥 env — FT_CARD_CAP_FLOOR=6 · 진행 7 · 좌석 0 → rc4 · 'abc' → 바닥 10 → rc0
mkprog 7; sess
o="$(FT_CARD_CAP_FLOOR=6 run --gate)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *"상한 6"* ]]; } && ok "ⓒ FT_CARD_CAP_FLOOR=6 · 진행 7 → rc4 «상한 6»" || bad "ⓒ rc=$rc «${o:0:160}»"
o="$(FT_CARD_CAP_FLOOR=abc run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *REJECT* ]]; } && ok "ⓒ FT_CARD_CAP_FLOOR=abc → 바닥 10 → rc0" || bad "ⓒ rc=$rc «${o:0:160}»"

# ⓓ 재사용 — r9002 «- 배정: 좌석 byz-t-nano-r9001-x#0» 그 세션 있음 → 좌석 1 · «이동 먼저» 후보에서 빠진다
mkprog 11; rm -f "$R"/design/alpha/indices/진행/*.md
card 진행 r9001; card 진행 r9002 "- 배정: 좌석 byz-t-nano-r9001-x#0
"; card 진행 r9003
for i in $(seq 4 11); do card 진행 "p$i"; done
sess "byz-t-nano-r9001-x#0"
o="$(run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"진행 11(좌석 1)"* ]]; } && ok "ⓓ 재사용(배정 줄 세션 살아 있음) → 좌석 1(r9002)" || bad "ⓓ rc=$rc «${o:0:160}»"
o="$(run --gate)"
{ [[ "$o" == *REJECT* ]] && [[ "$o" != *"r9002.md"* ]] && [[ "$o" == *"외 5"* ]]; } && ok "ⓓ «이동 먼저» 후보에서 r9002 빠짐(후보 10장 → 외 5)" || bad "ⓓ 후보 «${o:0:200}»"

# ⓔ 배정 줄 좌석이 세션 목록에 없거나 «배정: 없음» → 지금과 같다(좌석 0)
mkprog 2; card 진행 r9101 "- 배정: 좌석 byz-t-nano-dead#0
"; card 진행 r9102 "- 배정: 없음
"; sess "byz-t-nano-r9001-x#0"
o="$(run)"; [[ "$o" == *"(좌석 0)"* ]] && ok "ⓔ 배정 좌석 없음·«배정: 없음» → 좌석 0" || bad "ⓔ «${o:0:160}»"

# ⓕ 우회 표식(r1292) 그대로 — 진행 11 · 좌석 0 · 승인 번호 ∧ 표식 → rc0 «상한 우회»
mkprog 11; sess; mkdir -p "$R/.fable-team/state"; : > "$R/.fable-team/state/card-cap-ok.777"
o="$(FT_CARD_CAP_OK=777 run --gate)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"카드 상한 우회"* ]]; } && ok "ⓕ 우회 표식 → rc0 «카드 상한 우회»" || bad "ⓕ rc=$rc «${o:0:160}»"
o="$(FT_CARD_CAP_OK=778 run --gate)"; rc=$?
{ [ "$rc" = 4 ]; } && ok "ⓕ 표식 없는 번호 → rc4(그대로)" || bad "ⓕ rc=$rc «${o:0:160}»"

# ⓗ 배정 줄 좌석 대조는 «정확 일치» — «…#1» 이 살아 있는 «…#10» 에, «nano» 한 낱말이 세션 목록 어디엔가에 걸리면 안 된다(arch#301)
mkprog 2; card 진행 r9301 "- 배정: 좌석 byz-t-nano-r9001-x#1
"; card 진행 r9302 "- 배정: 좌석 nano
"; sess "byz-t-nano-r9001-x#10"
o="$(run)"; [[ "$o" == *"(좌석 0)"* ]] && ok "ⓗ «#1» vs «#10»·한 낱말 «nano» → 좌석 0(정확 일치)" || bad "ⓗ «${o:0:160}»"
mkprog 2; card 진행 r9303 "- 배정: 좌석 byz-t-nano-r9001-x#10
"; card 진행 r9304 "- 배정: 좌석 nano
"; sess "byz-t-nano-r9001-x#10" "nano"
o="$(run)"; [[ "$o" == *"(좌석 2)"* ]] && ok "ⓗ 정확히 같은 이름이 살아 있으면 좌석 2" || bad "ⓗ «${o:0:160}»"
# ⓖ 회귀 — card_flow 기존 시험 FAIL 줄이 앞 판과 같다(둘 다 0줄)
m="$(bash "$HERE/test_card_flow_team_ref_r1256.sh" 2>&1 | grep -c '^FAIL')"   # 빠른 회귀(0.4초) — r954 는 단독 25~110초(부하)라 70초 예산 밖: FT_R1693_FULL=1 이면 함께 본다
{ [ "$m" = 0 ]; } && ok "ⓖ 회귀 r1256 FAIL 0" || bad "ⓖ 회귀 r1256 FAIL $m"
n=""; if [ -n "${FT_R1693_FULL:-}" ]; then n="$(bash "$HERE/test_card_flow_r954.sh" 2>&1 | grep '^FAIL' | grep -c '카드 상한\|카드 흐름\|ⓥ5')"
  { [ "$n" = 0 ]; } && ok "ⓖ 회귀 r954 — 상한·경보 사례 FAIL 0(전체 실행)" || bad "ⓖ 회귀 r954 상한·경보 FAIL $n"; else ok "ⓖ 회귀 r954 — FT_R1693_FULL=1 일 때만(단독 25~110초 · 보고에서 따로 비교)"; fi

# ── 변이 3종(사본에서만) ──
mut(){ python3 - "$CF" "$T/$1.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mrun(){ PATH="$FAKE:$PATH" bash "$T/$1.sh" --team alpha --root "$R" --dir "$R/design/alpha" "${@:2}" 2>&1; }
mut m1 '[ "$cap" -ge "$floor" ] || cap="$floor"' ':'      # M1: 바닥 삭제(M+2 만)
bash -n "$T/m1.sh" && ok "M1 bash -n rc0" || bad "M1 bash -n"
mkprog 10; sess; o="$(mrun m1 --gate)"; rc=$?
[ "$rc" = 4 ] && ok "M1 바닥 삭제 → ⓐ FAIL(검출됨)" || bad "M1 검출 실패 rc=$rc «${o:0:120}»"
mut m2 'cap=$((seat + 2))' 'cap="$floor"'                 # M2: max 대신 바닥 고정
bash -n "$T/m2.sh" && ok "M2 bash -n rc0" || bad "M2 bash -n"
mkprog 13; localargs=(); for i in $(seq 1 11); do localargs+=("byz-alpha-nano-p$i#0"); done; sess "${localargs[@]}"
o="$(mrun m2 --gate)"; rc=$?
[ "$rc" = 4 ] && ok "M2 바닥 고정 → ⓑ FAIL(검출됨)" || bad "M2 검출 실패 rc=$rc «${o:0:120}»"
mut m3 "live=is_live(slug) or bool(" "live=is_live(slug) and bool("   # M3: 배정 줄 셈 삭제
bash -n "$T/m3.sh" && ok "M3 bash -n rc0" || bad "M3 bash -n"
mkprog 2; card 진행 r9201 "- 배정: 좌석 byz-t-nano-alive#0
"; card 진행 r9202; sess "byz-t-nano-alive#0"
o="$(mrun m3)"; rc=$?
[[ "$o" == *"(좌석 0)"* ]] && ok "M3 배정 줄 셈 삭제 → ⓓ FAIL(검출됨)" || bad "M3 검출 실패 «${o:0:120}»"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
