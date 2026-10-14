#!/usr/bin/env bash
# graphics 팀 설치 시험 (판정 649 · 카드 g649-graphics-team-install) — 실 좌석·워크트리·tmux 0, 임시 ROOT 만 쓴다.
# 실행: bash tests/harness/test_graphics_install.sh   (리포 어느 워크트리에서든)
set -uo pipefail
export FT_AGENT_MAX=100000 FT_DISK_MIN_GIB=0 FT_SWAP_MAX_MIB=100000000 FT_MEM_FREE_MIN_PCT=0   # spawn 입구 자원 문지기는 실측 머신 부하로 REJECT 한다 — 이 시험은 문지기 결과를 보지 않는다(R163 · 수정 전부터 RED)
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRC="$REPO/scripts/harness-install/graphics"
KIT="$REPO/scripts/harness-install/fable-team/bin"     # spawn·lint 키트(scripts/fable-team-bin 에는 ft-index-lint.sh 가 없다 — 같은 ft-nano-spawn.sh)
LIVE_GOV="$HOME/.claude/skills/fable-team/references/main-team-governance.md"
STAGED_GOV="$REPO/design/harness/staged-649/main-team-governance.md"
T="$(mktemp -d)"; ROOT="$T/root"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# ① bash -n 전 스크립트
for f in "$SRC/install.sh" "$SRC/graphics-env.sh" "${BASH_SOURCE[0]}"; do
  bash -n "$f" && ok "① bash -n ${f#$REPO/}" || bad "① bash -n ${f#$REPO/}"
done

# ② 임시 ROOT 에 install.sh → 3파일 cmp 0
git init -q "$ROOT" && git -C "$ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
ROOT="$(cd "$ROOT" && pwd -P)"   # macOS /var → /private/var — spawn 은 git 이 돌려준 실경로를 PLAN 에 찍는다
if out="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; then
  cmp -s "$SRC/seats-graphics.json" "$ROOT/.fable-team/seats-graphics.json" \
   && cmp -s "$SRC/graphics-env.sh" "$ROOT/.fable-team/bin-graphics/graphics-env.sh" \
   && cmp -s "$SRC/goal-lines-graphics.txt" "$ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt" \
   && ok "② install.sh 3파일 cmp 0" || bad "② 설치 뒤 cmp 불일치"
else bad "② install.sh rc!=0: $out"; fi
# ②b 재설치 = .bak 보존 + 다시 cmp 0 (이미 있을 때 덮기)
echo x >> "$ROOT/.fable-team/seats-graphics.json"
bash "$SRC/install.sh" "$ROOT" >/dev/null 2>&1 && ls "$ROOT"/.fable-team/seats-graphics.json.bak-* >/dev/null 2>&1 \
  && cmp -s "$SRC/seats-graphics.json" "$ROOT/.fable-team/seats-graphics.json" && ok "②b 재설치 .bak 보존 + cmp 0" || bad "②b 재설치"

# ③ env source 뒤 변수 전부 비어 있지 않음 (FT_IMPL_MODEL 제외 — 비어 있어야 한다)
envchk="$(env -u FT_NANO_PREFIX -u FT_IMPL_MODEL bash -c '
  . "$1"; miss=""
  for v in FT_SEATS_JSON FT_NANO_PREFIX FT_NANO_WT_PREFIX FT_ACTIVE_TAG FT_NANO_LEDGER_WT FT_NANO_LEDGER FT_GOAL_LEDGER FT_SEND_FROM FT_BIN FT_NANO_FEAT FT_GOAL_LINES_FILE FT_MBOX_SH FT_CARD_REQUIRE_PREVERIFY; do
    [ -n "${!v:-}" ] || miss="$miss $v"; done
  [ -z "${FT_IMPL_MODEL:-}" ] || miss="$miss FT_IMPL_MODEL(있으면 안 됨)"
  [ "$FT_SEATS_JSON" = "$2/.fable-team/seats-graphics.json" ] || miss="$miss FT_SEATS_JSON(ROOT 불일치:$FT_SEATS_JSON)"
  echo "MISS:$miss"' _ "$ROOT/.fable-team/bin-graphics/graphics-env.sh" "$ROOT")"
[ "$envchk" = "MISS:" ] && ok "③ env 변수 13개 비어 있지 않음 · FT_IMPL_MODEL 없음 · ROOT 경로 일치" || bad "③ $envchk"

# ④ seats-graphics.json 파싱 + 필수 키
python3 - "$ROOT/.fable-team/seats-graphics.json" <<'PY' && ok "④ seats-graphics.json 파싱 · _master/_hil_route/_cards 존재 · 좌석 0" || bad "④ seats-graphics.json"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("_master", "_hil_route", "_cards"):
    assert isinstance(d.get(k), str) and d[k], k
assert d.get("_tick") is None and d.get("_label") == "graphics"
assert not [k for k in d if not k.startswith("_")], "좌석 행이 있다"
PY

# ⑤ ft-name-lint
for n in byz-graphics-nano-g0-test#0 byz-graphics-arch-codex#0 byz-graphics-da-claude#0; do
  bash "$REPO/scripts/fable-team-bin/ft-name-lint.sh" "$n" >/dev/null 2>&1 && ok "⑤ name-lint $n" || bad "⑤ name-lint $n"
done

# ⑥ 임시 카드 → ft-nano-spawn --dry-run (임시 ROOT · 실 좌석 0)
mkdir -p "$ROOT/design/graphics/indices/대기"
cp "$REPO/design/graphics/GOAL-graphics.md" "$ROOT/design/graphics/GOAL-graphics.md"
CARD="$ROOT/design/graphics/indices/대기/g0-dryrun.md"
{
  echo "# 인덱스: g0-dryrun (graphics 설치 시험용 임시 카드)"
  echo "<!-- ledger: design/graphics/GOAL-graphics.md -->"
  echo "- Issue: 없음"; echo "- 상태: 대기"; echo "- 선행: 없음"; echo "- 시험 입력: 없음"; echo "- 기준값: 없음 → 대체 축 spawn PLAN 줄"
  echo; echo "## 골 원문 (항상 이 3줄)"; sed -n 1,3p "$ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt"
  echo; echo "## 골좌표"; echo "시험용 / 닫는 증거: 「하네스마스터 발주. 신규. 그래픽스 디자인 ui/ux팀 구성.」"
  echo; echo "## 배경"; echo "설치 시험용 임시 카드."
  echo; echo "## 사전검증"; echo "- 소환: 아니오"; echo "- 면제: 설치 시험용 임시 카드라 실제 작업 없음 — arch 서명 byz-graphics-arch-codex#0"
  echo "## 조사 근거"; echo "- design/graphics/GOAL-graphics.md:1"
  echo; echo "## 구현 범위"; echo "design/graphics/GOAL-graphics.md 읽기만."
  echo; echo "## 완료 조건"; echo "dry-run PLAN 줄."
  echo; echo "## 상태"; echo "- 임시"
} > "$CARD"
git -C "$ROOT" add -A >/dev/null && git -C "$ROOT" -c user.name=t -c user.email=t@t commit -q -m card
plan="$(cd "$ROOT" && env -u FT_NANO_PREFIX -u FT_IMPL_MODEL bash "$KIT/ft-nano-spawn.sh" design/graphics/indices/대기/g0-dryrun.md --agent codex --model gpt-6.1-sol --dry-run 2>&1)"; prc=$?
rm -f "$CARD"
if [ "$prc" = 0 ] && grep -q "^ENV team=graphics prefix=byz-graphics-nano-" <<<"$plan" \
   && grep -q "^PLAN .*branch=nano/g0-dryrun" <<<"$plan" && grep -q "wt=$ROOT/.worktrees/graphics-nano-g0-dryrun " <<<"$plan"; then
  ok "⑥ spawn --dry-run: $(grep '^PLAN ' <<<"$plan" | cut -c1-160)"
else bad "⑥ spawn --dry-run rc=$prc: $plan"; fi

# ⑦ staged governance — 설계 5 의 4곳만(추가 줄만 · 정본과 diff 가 그 4곳). 설치 뒤에는 정본이 같아져 diff 0 도 통과.
for pat in '판정 649' 'graphics = master 0' '^| graphics | `byz-graphics-`' 'graphics 좌석이 열려 있는 동안'; do
  grep -q -- "$pat" "$STAGED_GOV" && ok "⑦ staged 에 «${pat}»" || bad "⑦ staged 에 «${pat}» 없음"
done
if [ -f "$LIVE_GOV" ]; then
  d="$(diff "$LIVE_GOV" "$STAGED_GOV")"; drc=$?
  if [ "$drc" = 0 ]; then ok "⑦ 정본과 staged 동일(이미 설치됨)"
  else
    removed="$(grep -c '^<' <<<"$d")"; hunks="$(grep -cE '^[0-9]+(,[0-9]+)?a[0-9]+' <<<"$d")"
    { [ "$removed" = 0 ] && [ "$hunks" = 4 ] && [ "$(grep -c '^[0-9]' <<<"$d")" = 4 ]; } \
      && ok "⑦ 정본 대비 추가 hunk 4개 · 삭제 0" || bad "⑦ diff 가 4곳 추가가 아니다 (삭제 $removed · hunk $hunks)"
  fi
else bad "⑦ 정본 없음: $LIVE_GOV"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
