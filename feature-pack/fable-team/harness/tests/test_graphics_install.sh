#!/usr/bin/env bash
# graphics 팀 설치 시험 (판정 649 · 카드 g649-graphics-team-install) — 실 좌석·워크트리·tmux 0, 임시 ROOT 만 쓴다.
# 실행: bash tests/harness/test_graphics_install.sh   (리포 어느 워크트리에서든)
set -uo pipefail
export FT_TEAMSET=0   # R351: 팀셋 표는 이 시험의 주제가 아님(임시 리포엔 origin/main 표가 없다) — 표 판정은 test_teamset_gitref.sh·test_nano_spawn_teamset_cap.sh 가 본다
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRC="$REPO/feature-pack/fable-team/harness/kit/graphics"
KIT="$REPO/feature-pack/fable-team/harness/kit/fable-team/bin"     # spawn·lint 키트(scripts/fable-team-bin 에는 ft-index-lint.sh 가 없다 — 같은 ft-nano-spawn.sh)
LIVE_GOV="$HOME/.claude/skills/fable-team/references/main-team-governance.md"
STAGED_GOV="$REPO/feature-pack/fable-team/harness/design/harness/staged-649/main-team-governance.md"
T="$(mktemp -d)"; ROOT="$T/root"; trap 'rm -rf "$T"' EXIT
. "$REPO/feature-pack/fable-team/harness/tests/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# ① bash -n 전 스크립트
for f in "$SRC/install.sh" "$SRC/graphics-env.sh" "${BASH_SOURCE[0]}"; do
  bash -n "$f" && ok "① bash -n ${f#$REPO/}" || bad "① bash -n ${f#$REPO/}"
done

# ② 임시 ROOT 에 install.sh → 3파일 cmp 0
mkdir -p "$ROOT/design"; printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$ROOT/design/TEAMS.md"   # R383: spawn 이 팀 폴더 명단을 읽는다
git init -q "$ROOT" && git -C "$ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
ROOT="$(cd "$ROOT" && pwd -P)"   # macOS /var → /private/var — spawn 은 git 이 돌려준 실경로를 PLAN 에 찍는다
if out="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; then
  cmp -s "$SRC/seats-graphics.json" "$ROOT/.fable-team/seats-graphics.json" \
   && cmp -s "$SRC/graphics-env.sh" "$ROOT/.fable-team/bin-graphics/graphics-env.sh" \
   && cmp -s "$SRC/goal-lines-graphics.txt" "$ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt" \
   && ok "② install.sh 3파일 cmp 0" || bad "② 설치 뒤 cmp 불일치"
else bad "② install.sh rc!=0: $out"; fi
cp "$ROOT/.fable-team/seats-graphics.json" "$T/seats-first.json"   # ④ 는 ②b 와 독립인 첫 설치 사본을 파싱한다
# ②b 재설치 (판정 690): 명부는 «있으면 SKIP·보존»(덮지 않음) · env·goal-lines 는 .bak-<ts> 뒤 덮기 → cmp 0
echo x >> "$ROOT/.fable-team/seats-graphics.json"; cp "$ROOT/.fable-team/seats-graphics.json" "$T/seats-edited.json"
echo x >> "$ROOT/.fable-team/bin-graphics/graphics-env.sh"; echo x >> "$ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt"
out2b="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; rc2b=$?
{ [ "$rc2b" = 0 ] && grep -q '^SKIP seats-graphics.json' <<<"$out2b" \
  && cmp -s "$T/seats-edited.json" "$ROOT/.fable-team/seats-graphics.json" \
  && ! ls "$ROOT"/.fable-team/seats-graphics.json.bak-* >/dev/null 2>&1 \
  && ls "$ROOT"/.fable-team/bin-graphics/graphics-env.sh.bak-* >/dev/null 2>&1 \
  && ls "$ROOT"/.fable-team/bin-graphics/goal-lines-graphics.txt.bak-* >/dev/null 2>&1 \
  && cmp -s "$SRC/graphics-env.sh" "$ROOT/.fable-team/bin-graphics/graphics-env.sh" \
  && cmp -s "$SRC/goal-lines-graphics.txt" "$ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt"; } \
  && ok "②b 재설치: 명부 SKIP·내용 보존 · env/goal-lines .bak 뒤 덮기 cmp 0" || bad "②b 재설치 rc=$rc2b: $out2b"

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
python3 - "$T/seats-first.json" <<'PY' && ok "④ seats-graphics.json 파싱 · _master/_hil_route/_cards 존재 · 좌석 0" || bad "④ seats-graphics.json"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("_master", "_hil_route", "_cards"):
    assert isinstance(d.get(k), str) and d[k], k
assert d.get("_tick") is None and d.get("_label") == "graphics"
assert not [k for k in d if not k.startswith("_")], "좌석 행이 있다"
PY

# ⑤ ft-name-lint
for n in byz-graphics-nano-g0-test#0 byz-graphics-arch-codex#0 byz-graphics-da-claude#0; do
  bash "$REPO/feature-pack/fable-team/harness/bin/ft-name-lint.sh" "$n" >/dev/null 2>&1 && ok "⑤ name-lint $n" || bad "⑤ name-lint $n"
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

# ⑦ staged governance 의 graphics 4곳 — staged 에 있고(기존 줄 유지) 라이브 정본에도 실제로 들어갔다.
#   (staged 는 설치 «당시» 사본이라 라이브와의 전체 diff 는 이후 판정으로 시간이 지나면 반드시 깨진다 — 4곳 포함 여부만 본다.)
#   판정 690 이 4곳 중 2곳(「graphics = master 0」·「graphics 좌석이 열려 있는 동안」)을 팀장 신설 문구로 대체했다 — 라이브는 그 «대체 문구» 로 단언한다.
STAGED_PATS=('판정 649' 'graphics = master 0' '^| graphics | `byz-graphics-`' 'graphics 좌석이 열려 있는 동안')
LIVE_PATS=('판정 649' 'graphics 팀장 = `byz-graphics-master-claude#N`' '^| graphics | `byz-graphics-`' 'graphics 는 팀장(`seats-graphics.json` `_master`)이')
for i in 0 1 2 3; do
  pat="${STAGED_PATS[$i]}"; lpat="${LIVE_PATS[$i]}"
  grep -q -- "$pat" "$STAGED_GOV" && ok "⑦ staged 에 «${pat}»" || bad "⑦ staged 에 «${pat}» 없음"
  if [ -f "$LIVE_GOV" ]; then
    grep -q -- "$lpat" "$LIVE_GOV" && ok "⑦ 라이브 정본에 «${lpat}»" || bad "⑦ 라이브 정본에 «${lpat}» 없음"
  else bad "⑦ 정본 없음: $LIVE_GOV"; fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
