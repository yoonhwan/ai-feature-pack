#!/usr/bin/env bash
# test_r975_nano_spawn_reply_target.sh — r975: ft-nano-spawn.sh 의 발주문 «회신 대상» 이 명부 밖 별칭이 아니라
#   «--from > env FT_SEND_FROM > 그 팀 명부 현역 `_master`» 로 풀리는가. 못 풀면 열지 않고 REJECT.
#   실사건 r972: 옛 기본값 글자(명부에 없는 별칭)로 나노 보고가 가서 우편함 ring 10 포화 → 가장 오래된 1건 영구 유실.
# 전부 mktemp — 임시 저장소·가짜 tmux·가짜 센서·가짜 회수. 실 좌석·실 워크트리·실 우편함·실 tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok   # 자원 문지기 센서를 가짜로 — 실 머신 부하·압력에 시험이 흔들리지 않게(R218)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
MATS="byz-harness-master-claude#3"

# ── 고정 픽스처: 임시 리포 + 명부 + 카드 + 가짜 tmux/회수 ──
mkfix() { # <디렉터리> <_master 값>
  local d="$1" master="$2"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/design/harness/indices/대기"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$d/design/TEAMS.md"
  printf '# 카드\n' > "$d/design/harness/indices/대기/x.md"
  python3 - "$d/.fable-team/seats-harness.json" "$master" <<'PY'
import json, sys
p, m = sys.argv[1], sys.argv[2]
d = {"_version": "1.0.0", "_master": m,
     "byz-harness-master-claude#3": {"role": "master", "agent": "claude"},
     "byz-harness-arch-claude#1": {"role": "arch", "agent": "claude"}}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  git init -q "$d" && git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"

sp() { # sp <bindir> <픽스처> [인자…] — 그 픽스처 리포 안에서 spawn 1회(출력 2>&1 · rc 는 호출자가 본다)
  local bd="$1" d="$2"; shift 2
  ( cd "$d" && env FT_ROOT="$d" FT_NANO_PREFIX="byz-harness-nano-" FT_SEATS_JSON="$d/.fable-team/seats-harness.json" \
      FT_RECLAIM_SH="$T/reclaim.sh" FT_TEAMSET=0 \
      bash "$bd/ft-nano-spawn.sh" design/harness/indices/대기/x.md "$@" 2>&1 )
}
wts() { git -C "$1" worktree list | wc -l | tr -d ' '; }

for f in ft-nano-spawn.sh; do
  bash -n "$BIN/$f" && ok "bash -n 추적본 $f" || bad "bash -n 추적본 $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "두 사본 cmp 0 $f" || bad "두 사본 불일치 $f"
done
[ "$(grep -c 'dispatch' "$BIN/ft-nano-spawn.sh")" = 0 ] && ok "«dispatch» 글자 0(추적본)" || bad "«dispatch» 글자가 남아 있다(추적본)"
grep -q 'FT_SEND_FROM="\$FROM" bash "\$HERE/ft-send-verified.sh"' "$KIT/ft-nano-spawn.sh" && ok "발주문 송신 from = 해석된 \$FROM" || bad "발주문 송신이 \$FROM 을 안 쓴다"

# ── ⓐ 인자·env 없음 + 명부 `_master` → 그 값이 회신 대상 (옛 판은 명부 밖 별칭) ──
D="$T/a"; mkfix "$D" "$MATS"
o="$(sp "$KIT" "$D")"
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "ⓐ 회신 대상 = 명부 _master($MATS)" || bad "ⓐ $o"
[[ "$o" != *"[dispatch->"* ]] && ok "ⓐ 명부 밖 별칭 머리 0" || bad "ⓐ 명부 밖 별칭 머리: $o"

# ── ⓑ 명부 `_master` 빈 값 → REJECT rc≠0 · 워크트리·세션 0 ──
D="$T/b"; mkfix "$D" ""
o="$(sp "$KIT" "$D")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상을 못 풀었다"* ]] && [ "$(wts "$D")" = 1 ] && [ ! -d "$D/.worktrees" ]; } \
  && ok "ⓑ _master 빈 값 → REJECT rc=$rc · 부작용 0" || bad "ⓑ rc=$rc $o"
# ⓑ-2 명부 파일 자체가 없음 → 이미 있던 «seats.json 없음» REJECT 로 먼저 막힘(기본값으로 진행 0)
D="$T/b2"; mkfix "$D" "$MATS"; rm -f "$D/.fable-team/seats-harness.json"
o="$(sp "$KIT" "$D")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT"* ]] && [ "$(wts "$D")" = 1 ]; } && ok "ⓑ-2 명부 없음 → REJECT rc=$rc" || bad "ⓑ-2 rc=$rc $o"

# ── ⓒ --from 명시 우선 · 단 이름 lint 를 지난다 ──
D="$T/c"; mkfix "$D" "$MATS"
o="$(sp "$KIT" "$D" --from byz-harness-arch-claude#1)"
[[ "$o" == *"INFO 회신 대상 = byz-harness-arch-claude#1"* ]] && ok "ⓒ --from 명시가 이긴다" || bad "ⓒ $o"
o="$(sp "$KIT" "$D" --from dispatch)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상 이름 lint 실패"* ]] && [[ "$o" != *"SPAWNED"* ]]; } \
  && ok "ⓒ --from 명부 밖 별칭 → lint REJECT rc=$rc" || bad "ⓒ rc=$rc $o"
o="$(sp "$KIT" "$D" --from byz-harness-da-claude#9)"; rc=$?   # 이름 문법은 지나지만 명부에 없다
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상이 명부에 없다"* ]]; } && ok "ⓒ-2 명부에 없는 좌석 → REJECT rc=$rc" || bad "ⓒ-2 rc=$rc $o"

# ── ⓓ env FT_SEND_FROM 만 → 옛 세대는 명부 현역으로 해석(같은 계보) ──
D="$T/d"; mkfix "$D" "$MATS"
o="$( cd "$D" && env FT_ROOT="$D" FT_NANO_PREFIX="byz-harness-nano-" FT_SEATS_JSON="$D/.fable-team/seats-harness.json" FT_RECLAIM_SH="$T/reclaim.sh" FT_TEAMSET=0 FT_SEND_FROM="byz-harness-master-claude#9" \
      bash "$KIT/ft-nano-spawn.sh" design/harness/indices/대기/x.md 2>&1 )"
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "ⓓ FT_SEND_FROM 옛 세대(#9) → 명부 현역($MATS)" || bad "ⓓ $o"

# ── 변이 3종 — 각각 «그 시험만» FAIL 이어야 한다 ──
cp -R "$KIT" "$T/bin-a"; cp -R "$KIT" "$T/bin-b"; cp -R "$KIT" "$T/bin-c"
BASE="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || echo "")"
if [ -n "$BASE" ] && git -C "$REPO" show "$BASE:feature-pack/fable-team/harness/kit/fable-team/bin/ft-nano-spawn.sh" > "$T/bin-a/ft-nano-spawn.sh" 2>/dev/null; then
  D="$T/ma"; mkfix "$D" "$MATS"; o="$(sp "$T/bin-a" "$D")"
  [[ "$o" != *"INFO 회신 대상 = $MATS"* ]] && ok "변이 ⓐ: 옛 판(기본값 되살림) → ⓐ FAIL" || bad "변이 ⓐ: 옛 판인데 ⓐ 통과"
else echo "SKIP 변이 ⓐ — origin/main 사본을 못 꺼냈다"; fi

grep -v 'REJECT 회신 대상을 못 풀었다' "$KIT/ft-nano-spawn.sh" > "$T/bin-b/ft-nano-spawn.sh"
D="$T/mb"; mkfix "$D" ""; o="$(sp "$T/bin-b" "$D")"
[[ "$o" != *"REJECT 회신 대상을 못 풀었다"* ]] && ok "변이 ⓑ: 못 풀면 빈 값 진행 → ⓑ FAIL" || bad "변이 ⓑ: 빈 값인데도 REJECT"

grep -v 'REJECT 회신 대상 이름 lint 실패' "$T/bin-c/ft-nano-spawn.sh" | grep -v 'REJECT 회신 대상이 명부에 없다' > "$T/mut-c.sh"
mv "$T/mut-c.sh" "$T/bin-c/ft-nano-spawn.sh"
D="$T/mc"; mkfix "$D" "$MATS"; o="$(sp "$T/bin-c" "$D" --from dispatch)"; rc=$?
{ [[ "$o" != *"REJECT 회신 대상 이름 lint 실패"* ]] && ! { [ "$rc" != 0 ] && [[ "$o" == *"회신 대상 이름 lint 실패"* ]]; }; } \
  && ok "변이 ⓒ: lint 칸 삭제 → 명부 밖 별칭이 REJECT 안 됨(= ⓒ FAIL)" || bad "변이 ⓒ: 칸을 지웠는데도 REJECT"

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
