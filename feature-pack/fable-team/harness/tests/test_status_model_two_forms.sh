#!/usr/bin/env bash
# test_status_model_two_forms.sh — r1057: 상태줄 모델 판독 도우미 ft-status-model.sh (구형 «Model:» + 신형 «ctx:N% |»)
#   ⓐ R1 구형 «  Model: Opus 5.5 · …» → «Opus 5.5» (지금 동작 유지) · 변이(구형 꼴 삭제) → FAIL
#   ⓑ R2·R3 신형 «  ctx:?% | Opus 5.5 high | 세션» → «Opus 5.5» (effort 버림 · ft_norm_model 정규화 일치)
#            «ctx:12% | Sonnet 5.5 | x» · «ctx:3% | Fable 5.1 max | y» → 변이(effort 안 버림) → FAIL
#   ⓒ R4·R5 모델줄 없음 = 빈 출력 rc0(스폰은 fail-closed 유지) · 줄 가운데 «ctx:» 는 안 읽음(줄 시작 고정)
#            변이(줄 시작 고정 풀기) → FAIL
#   ⓓ R6 두 꼴이 다 있으면 더 아래 줄 · 변이(첫 매치 우선 = head -1) → FAIL
#   ⓔ 스폰 배선: 두 곳(kit·skill) «Model:» grep 0 · 도우미 호출 1 · 도우미 쌍 cmp0 · 스폰 줄 수 ≤ 기준(origin/main)
# 픽스처 = stdin 텍스트만 · tmux 0 · 실 스폰 0 · 고정 sleep 0 · 자기 재호출 0 · 임시 폴더 mktemp 만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
KITBIN="$ROOT/harness/kit/fable-team/bin"
SKILLBIN="$ROOT/skill/scripts"
HELP="$KITBIN/ft-status-model.sh"
SPAWN_KIT="$KITBIN/ft-tmux-spawn.sh"; SPAWN_SKILL="$SKILLBIN/ft-tmux-spawn.sh"
REPO="$(cd -- "$ROOT/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }
ms()  { python3 -c 'import time;print(int(time.time()*1000))'; }
T0="$(ms)"; st() { echo "⏱ $1 $(( $(ms) - T0 ))ms"; }

# 스폰 스크립트와 같은 정규화 (claude- 프리픽스 제거 · [1m] 제거 · 소문자 영숫자만)
norm() { printf '%s' "$1" | sed -E 's/^claude-//; s/\[1m\]$//' | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }
# run <도우미경로> <픽스처파일> → stdout
run()  { bash "$1" < "$2"; }
fx()   { printf '%s' "$2" > "$T/$1"; }

[ -x "$HELP" ] && ok "도우미 실행 가능: ${HELP#$ROOT/}" || bad "도우미 없음/실행 불가: $HELP"

# ── ⓐ 구형 유지 (R1) ──
fx r1.txt '  ⏵⏵ accept edits on (shift+tab to cycle) · Model: Opus 5.5 · ctx:?%
❯ '
got="$(run "$HELP" "$T/r1.txt")"
[ "${got}" = "Opus 5.5" ] && ok "ⓐ R1 구형 «Model: Opus 5.5» → «${got}»" || bad "ⓐ R1 구형 판독 '${got}' (기대 'Opus 5.5')"
[ "$(norm "${got}")" = "$(norm 'claude-opus-5-5[1m]')" ] && ok "ⓐ R1 정규화 일치($(norm "${got}") = $(norm 'claude-opus-5-5[1m]'))" || bad "ⓐ R1 정규화 불일치"

# ── ⓑ 신형 읽기 (R2·R3 · effort 버림) ──
fx r2.txt '  ctx:?% | Opus 5.5 high | aifp-airag-arch-claude#2
❯ '
got="$(run "$HELP" "$T/r2.txt")"
[ "${got}" = "Opus 5.5" ] && ok "ⓑ R2 신형 «ctx:?% | Opus 5.5 high | …» → «${got}»" || bad "ⓑ R2 신형 판독 '${got}' (기대 'Opus 5.5')"
[ "$(norm "${got}")" = "$(norm 'claude-opus-5-5[1m]')" ] && ok "ⓑ R2 ft_norm_model 뒤 claude-opus-5-5[1m] 와 같다" || bad "ⓑ R2 정규화 불일치($(norm "${got}") ≠ opus55)"
fx r3a.txt '  ctx:12% | Sonnet 5.5 | x
'
got="$(run "$HELP" "$T/r3a.txt")"
[ "${got}" = "Sonnet 5.5" ] && ok "ⓑ R3 effort 없음 «ctx:12% | Sonnet 5.5 | x» → «${got}»" || bad "ⓑ R3 effort 없음 판독 '${got}'"
fx r3b.txt '  ctx:3% | Fable 5.1 max | y
'
got="$(run "$HELP" "$T/r3b.txt")"
[ "${got}" = "Fable 5.1" ] && ok "ⓑ R3 다른 effort «ctx:3% | Fable 5.1 max | y» → «${got}»" || bad "ⓑ R3 max 판독 '${got}'"

st "ⓐⓑ"

# ── ⓒ 없음 = 빈 값 (R4·R5) ──
fx r4.txt '  본문만 있는 화면입니다.
❯ 다음 제안 줄
'
got="$(run "$HELP" "$T/r4.txt")"
[ -z "${got}" ] && ok "ⓒ R4 모델줄 없음 = 빈 출력" || bad "ⓒ R4 빈 값이어야 하는데 '${got}'"
bash "$HELP" < "$T/r4.txt" >/dev/null 2>&1; ck "ⓒ R4 빈 값에서도 rc0(판정은 호출자 몫)" $?
fx r5.txt '  로그 … see ctx:5% | foo 1 | bar
'
got="$(run "$HELP" "$T/r5.txt")"
[ -z "${got}" ] && ok "ⓒ R5 줄 가운데 «ctx:» 는 안 읽음(줄 시작 고정)" || bad "ⓒ R5 가운데 ctx: 를 읽음 '${got}'"

# ── ⓓ 아래 줄 우선 (R6) ──
fx r6a.txt '  Model: Opus 5.5 · 위
  ctx:1% | Sonnet 5.5 | 아래
'
got="$(run "$HELP" "$T/r6a.txt")"
[ "${got}" = "Sonnet 5.5" ] && ok "ⓓ R6 신형이 더 아래 → «${got}»" || bad "ⓓ R6 아래 줄 우선 실패 '${got}'"
fx r6b.txt '  ctx:1% | Sonnet 5.5 | 위
  Model: Opus 5.5 · 아래
'
got="$(run "$HELP" "$T/r6b.txt")"
[ "${got}" = "Opus 5.5" ] && ok "ⓓ R6 구형이 더 아래 → «${got}»" || bad "ⓓ R6 역순 아래 줄 우선 실패 '${got}'"

st "ⓒⓓ"

# ── ⓔ 스폰 배선 ──
n_k="$(grep -c "Model:" "$SPAWN_KIT")"; n_s="$(grep -c "Model:" "$SPAWN_SKILL")"
[ "${n_k}" = 0 ] && [ "${n_s}" = 0 ] && ok "ⓔ 두 곳 «Model:» grep 0 (kit=${n_k} skill=${n_s})" || bad "ⓔ «Model:» 잔존 kit=${n_k} skill=${n_s}"
h_k="$(grep -c 'ft-status-model\.sh' "$SPAWN_KIT")"; h_s="$(grep -c 'ft-status-model\.sh' "$SPAWN_SKILL")"
[ "${h_k}" = 1 ] && [ "${h_s}" = 1 ] && ok "ⓔ 도우미 호출 각 1회(kit=${h_k} skill=${h_s})" || bad "ⓔ 도우미 호출 kit=${h_k} skill=${h_s}"
cmp -s "$HELP" "$SKILLBIN/ft-status-model.sh"; ck "ⓔ 도우미 쌍 cmp0(kit = skill/scripts)" $?
base_k="$(git -C "$REPO" show origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-tmux-spawn.sh 2>/dev/null | wc -l | tr -d ' ')"
now_k="$(wc -l < "$SPAWN_KIT" | tr -d ' ')"; now_s="$(wc -l < "$SPAWN_SKILL" | tr -d ' ')"
[ -n "${base_k}" ] && [ "${now_k}" -le "${base_k}" ] && [ "${now_s}" -le "${base_k}" ] \
  && ok "ⓔ 스폰 줄 수 안 늘림(kit=${now_k} skill=${now_s} ≤ 기준=${base_k})" \
  || bad "ⓔ 스폰 줄 수 kit=${now_k} skill=${now_s} 기준=${base_k}"
grep -q 'MODEL_UNREAD' "$SPAWN_KIT" && grep -q 'exit 7' "$SPAWN_KIT" \
  && ok "ⓔ R4 fail-closed 경로 그대로(MODEL_UNREAD · exit 7)" || bad "ⓔ fail-closed 경로 사라짐"

st "ⓔ"

# ── 변이 4종 (각각 FAIL 로 잡혀야 한다) ──
mut() { # mut <이름> <sed식> <문법확인픽스처> → $T/mut-<이름>/ft-status-model.sh
  local name="$1" expr="$2" probe="$3" d="$T/mut-$1"
  mkdir -p "$d"; sed -E "$expr" "$HELP" > "$d/ft-status-model.sh"
  if cmp -s "$HELP" "$d/ft-status-model.sh"; then bad "변이 $name 적용 실패(대상 줄 없음)"; return 1; fi
  # 변이는 «동작을 하나 망가뜨린 판본» 이어야 한다 — 문법 오류로 죽은 판본은 변이가 아니다
  if ! bash "$d/ft-status-model.sh" < "$probe" > "$d/probe.out" 2> "$d/probe.err"; then
    bad "변이 $name 이 문법 오류로 죽음($(head -2 "$d/probe.err"))"; return 1
  fi
  ok "변이 $name 적용(문법 정상)"; return 0
}
# M1 구형 꼴 삭제 → ⓐ 판독 빈 값
if mut m1 's/Model:\[\[:space:\]\]\*\[A-Za-z\]\+/ModelNOPE/' "$T/r4.txt"; then
  got="$(run "$T/mut-m1/ft-status-model.sh" "$T/r1.txt")"
  [ "${got}" != "Opus 5.5" ] && ok "M1 구형 꼴 삭제 → 잡힘('${got}')" || bad "M1 변이를 못 잡음"
fi
# M2 effort 낱말을 안 버림(«Opus 5.5 high») → 정규화 불일치
if mut m2 's/substr\(g, 1, RLENGTH\)/g/' "$T/r4.txt"; then
  got="$(run "$T/mut-m2/ft-status-model.sh" "$T/r2.txt")"
  [ "$(norm "${got}")" != "$(norm 'claude-opus-5-5[1m]')" ] && ok "M2 effort 안 버림 → 잡힘('${got}' → $(norm "${got}") ≠ opus55)" || bad "M2 변이를 못 잡음('${got}')"
fi
# M3 줄 시작 고정 풀기 → R5(줄 가운데 ctx:) 를 읽어 버린다
if mut m3 's/\^\[\[:space:\]\]\*ctx:/ctx:/' "$T/r1.txt"; then
  got="$(run "$T/mut-m3/ft-status-model.sh" "$T/r5.txt")"
  [ -n "${got}" ] && ok "M3 줄 시작 고정 풀기 → 잡힘('${got}')" || bad "M3 변이를 못 잡음(빈 값 그대로)"
fi
# M4 첫 매치 우선(head -1 과 같은 뜻) → ⓓ 아래 줄 우선이 뒤집힌다
if mut m4 's/if \(i >= best_nr\)/if (best_nr == 0)/g' "$T/r1.txt"; then
  got="$(run "$T/mut-m4/ft-status-model.sh" "$T/r6a.txt")"
  [ "${got}" = "Opus 5.5" ] && ok "M4 첫 매치 우선 → 잡힘('${got}')" || bad "M4 변이를 못 잡음('${got}')"
fi
st "변이"
echo "fail=$fail"; [ "$fail" = 0 ]
