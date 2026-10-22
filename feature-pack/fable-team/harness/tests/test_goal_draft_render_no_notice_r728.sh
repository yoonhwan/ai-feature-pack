#!/usr/bin/env bash
# test_goal_draft_render_no_notice_r728.sh — 골 표 «시험·시안 렌더»(FT_GOAL_A6_MD 를 기본이 아닌 값으로 주입)가 «골 번호 바뀜» 공지를 실발송하고 표식까지 덮어써, 다음 진짜 렌더가 재공지하던 것(r728).
#   ⓐ 빨강 — base 판(origin/main 50e88b8c)은 시안 렌더에서 공지 1통 + 표식 = 시안 판 → 다음 기본 렌더가 재공지 1통
#   ⓑ 후판 — 같은 순서에서 시안 렌더 = 공지 0 · 표식 바이트 그대로(전후 cmp) · 렌더 블록은 그대로(7행) · stderr INFO 1줄
#          (시안 출처 3종: 파일 경로 = `file:` 표지 · 기본과 다른 gitref · 같은 ref 의 정본 꼴 아닌 이름) · 다음 기본 렌더 = 재공지 0
#   ⓒ 기본 정본(env 없음 · env == 기본 spec 글자)의 번호표 바뀜 = 지금처럼 공지 1통 + 표식 전진(r668 시험 그대로)
#   ⓓ r726 유예 시험(test_goal_renumber_grace_r726.sh) 그대로 PASS — 표식 prev 줄이 시안으로 오염 0
#   ⓔ 변이 — 조건 삭제(if True:) 판이면 시안 렌더가 공지한다(= ⓑ 가 FAIL 하는 것을 재현)
# 픽스처 = mktemp 임시 git 리포·임시 루트·가짜 mbox(인자 기록만) — 실 리포·실 원장·실 좌석·외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd -- "$HERE/../.." && pwd)"
TOOL="$REPO/harness/bin/ft_goal_table.py"
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"; KITREL="${REPO#"$ROOT"/}/harness/kit/fable-team/bin"
BASESHA=50e88b8c   # r726 착지 판 = 이 카드 이전(«이동하는 origin/main» 아님 · 고정 sha)
MODS="ft_goal_table.py ft_goal_ledger.py ft_team_lib.py ft_goal_readjust_state.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음 «$2» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨 «$2» ← ${1:0:300}";; *) ok "$3";; esac; }

snap() {  # <bin 폴더> — 지금 판정기 모듈 사본
  local d="$1" f; mkdir -p "$d"
  for f in $MODS; do cp "$REPO/harness/bin/$f" "$d/$f" || return 1; done
}
snapsha() {  # <sha> <bin 폴더> — 그 sha 의 판정기 모듈 사본(없는 모듈은 건너뛴다)
  local sha="$1" d="$2" f got=0; mkdir -p "$d"
  for f in $MODS; do git -C "$ROOT" cat-file -e "$sha:$KITREL/$f" 2>/dev/null || continue
    git -C "$ROOT" show "$sha:$KITREL/$f" > "$d/$f" && got=1 || return 1; done
  [ "$got" = 1 ]
}
CUR="$T/curbin"; snap "$CUR" || bad "지금 판 사본 못 뜸"
BASE="$T/basebin"; snapsha "$BASESHA" "$BASE" || bad "base 사본 못 뜸($BASESHA)"
MUT="$T/mutbin"; snap "$MUT" && sed -i.bak 's/^    if _canon_render():/    if True:/' "$MUT/ft_goal_table.py"
cmp -s "$MUT/ft_goal_table.py" "$CUR/ft_goal_table.py" && bad "변이 사본이 안 만들어졌다(조건 줄 못 찾음)"

CPATH=design/planner/AUTONOMY-GOAL-A6-20261018.md; LPATH=design/planner/PLAN-oppa-ledger.md
DPATH=design/planner/draft-preview.md; DRPATH=design/planner/draft-gitref.md; DLPATH=design/planner/draft-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner" "$R/.fable-team/state" "$T/mbox"; git -C "$R" init -q -b main
printf '{"_master":"master-a#1"}\n' > "$R/.fable-team/seats-a.json"
printf '| 팀 | 폴더 | 좌석 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#1 | 현역 |\n' > "$R/design/TEAMS.md"
cat > "$T/mbox/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
SH
chmod +x "$T/mbox/mbox.sh"; export MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
MARK="$R/.fable-team/state/goal-numbering.tsv"
canon() {  # <골 이름...>
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local g; for g in "$@"; do printf '| %s | 팀x | 착지 sha |\n' "$g"; done
}
ledger() {  # <행 수> — 원장 절 이름은 옛 꼴(«메인 골 6줄») 그대로(r668 범위 밖)
  printf '# 원장\n\n> 마지막 갱신: 2026-10-22 12:00 · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n'
  local i; for i in $(seq 1 "$1"); do printf '| 원장 글자 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
render() {  # <도구 폴더> <FT_GOAL_A6_MD 값 · 빈 글 = env 없음> [원장 spec]
  local d="$1" md="$2" led="${3:-gitref:origin/main:$LPATH}"
  if [ -n "$md" ]; then export FT_GOAL_A6_MD="$md"; else unset FT_GOAL_A6_MD; fi
  env -u FT_GOAL_MAX -u FT_MBOX FT_ROOT="$R" FT_MBOX="$T/mbox/mbox.sh" FT_NOW="2026-10-22 12:00" \
    FT_GOAL_A6_LEDGER="$led" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$d/ft_goal_table.py" 2>&1
}
rows() { printf '%s\n' "$1" | grep -c '^| .* | .* | .* | .* |$'; }
nmail() { wc -l < "$MBOX_LOG" | tr -d ' '; }
DEF="gitref:origin/main:$CPATH"; DRF="gitref:origin/draft:$DRPATH"; DLED="gitref:origin/main:$DLPATH"

canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"
canon k1 k9 k9b k4 k5 k6 k7 > "$R/$DPATH"; cp "$R/$DPATH" "$R/$DRPATH"; ledger 7 > "$R/$DLPATH"   # 시안 = 7행 판
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m base6
git -C "$R" update-ref refs/remotes/origin/main HEAD; git -C "$R" update-ref refs/remotes/origin/draft HEAD

echo "== ⓐ 빨강 — base 판($BASESHA): 시안 렌더가 공지 1통 + 표식 덮어씀 → 다음 기본 렌더가 재공지"
: > "$MBOX_LOG"; rm -f "$MARK"
B="$(render "$BASE" "$DEF")"; RC=$?
[ "$RC" = 0 ] && ok "ⓐ0 base · 기본 6행 렌더 rc0" || bad "ⓐ0 base 렌더 rc=$RC :: $B"
[ ! -s "$MBOX_LOG" ] && ok "ⓐ0 base · 첫 렌더 공지 0 · 표식 생김" || bad "ⓐ0 base 공지 :: $(cat "$MBOX_LOG")"
MARK6="$(head -1 "$MARK")"
B="$(render "$BASE" "$R/$DPATH" "$DLED")"; RC=$?
[ "$RC" = 0 ] && [ "$(nmail)" = 1 ] && has "$(cat "$MBOX_LOG")" "[골 번호 바뀜]" "ⓐ1 base · 시안 렌더 = 공지 1통(빨강 = 이 카드의 결함)"
[ "$(head -1 "$MARK")" != "$MARK6" ] && ok "ⓐ2 base · 표식 첫 줄이 시안 판으로 덮어써짐" || bad "ⓐ2 base 표식 안 덮임 :: $(cat "$MARK")"
B="$(render "$BASE" "$DEF")"; RC=$?
[ "$(nmail)" = 2 ] && has "$(cat "$MBOX_LOG")" "[골 번호 바뀜]" "ⓐ3 base · 다음 기본 렌더가 재공지 1통(번호표는 그대로인데)"

echo "== ⓑ 후판 — 시안 렌더 = 공지 0 · 표식 바이트 그대로 · 블록 7행 그대로 · stderr INFO 1줄"
: > "$MBOX_LOG"; rm -f "$MARK"
B="$(render "$CUR" "$DEF")"; RC=$?
[ "$RC" = 0 ] && [ ! -s "$MBOX_LOG" ] && ok "ⓑ0 기본 6행 렌더 rc0 · 공지 0 · 표식 생김" || bad "ⓑ0 rc=$RC :: $B / $(cat "$MBOX_LOG")"
cp "$MARK" "$T/mark-before"
for name in 파일 다른ref 같은ref다른이름; do
  case "$name" in
    파일) draft="$R/$DPATH";;        # 파일 경로 = `file:` 표지
    다른ref) draft="$DRF";;          # 기본과 다른 ref
    같은ref다른이름) draft="gitref:origin/main:$DPATH";;  # 같은 ref · 정본 꼴 아닌 이름
  esac
  B="$(render "$CUR" "$draft" "$DLED")"; RC=$?
  [ "$RC" = 0 ] && [ "$(rows "$B")" = 8 ] && ok "ⓑ1[$name] 시안 렌더 rc0 · 표 8줄(7행+머리) — 블록은 그대로 그린다" || bad "ⓑ1[$name] rc=$RC :: $B"
  [ ! -s "$MBOX_LOG" ] && ok "ⓑ2[$name] 시안 렌더 공지 0" || bad "ⓑ2[$name] 공지 :: $(cat "$MBOX_LOG")"
  cmp -s "$MARK" "$T/mark-before" && ok "ⓑ3[$name] 표식 바이트 그대로(전후 cmp)" || bad "ⓑ3[$name] 표식 변함 :: $(cat "$MARK")"
  has "$B" "INFO 시안 렌더 — 번호 공지·표식 0" "ⓑ4[$name] stderr INFO 1줄"
done
B="$(render "$CUR" "$DEF")"; RC=$?
[ ! -s "$MBOX_LOG" ] && ok "ⓑ5 시안 렌더 뒤 기본 렌더 = 재공지 0(공지 총 0)" || bad "ⓑ5 재공지 :: $(cat "$MBOX_LOG")"
cmp -s "$MARK" "$T/mark-before" && ok "ⓑ6 기본 렌더도 표식 그대로(번호표 그대로인 판)" || bad "ⓑ6 표식 :: $(cat "$MARK")"
not "$B" "INFO 시안 렌더" "ⓑ7 기본 렌더에는 시안 INFO 줄이 없다"

echo "== ⓒ 기본 정본의 번호표 바뀜 = 지금처럼 공지 1통 + 표식 전진(env 없음 / env == 기본 spec 글자)"
for tag in env없음 env같음; do
  : > "$MBOX_LOG"; rm -f "$MARK"
  if [ "$tag" = env없음 ]; then md=""; else md="$DEF"; fi
  B="$(render "$CUR" "$md")"; RC=$?
  [ "$RC" = 0 ] && [ ! -s "$MBOX_LOG" ] && ok "ⓒ0[$tag] 6행 첫 렌더 rc0 · 공지 0" || bad "ⓒ0[$tag] rc=$RC :: $B"
  canon k1 k9 k9b k4 k5 k6 k7 > "$R/$CPATH"; ledger 7 > "$R/$LPATH"; commit renumber7
  B="$(render "$CUR" "$md")"; RC=$?
  [ "$RC" = 0 ] && [ "$(nmail)" = 1 ] && has "$(cat "$MBOX_LOG")" "[골 번호 바뀜] 정본" "ⓒ1[$tag] 번호표 바뀐 기본 렌더 = 공지 1통"
  grep -q '^prev	' "$MARK" && ok "ⓒ2[$tag] 표식 전진 + prev 줄(r726 그대로)" || bad "ⓒ2[$tag] 표식 :: $(cat "$MARK")"
  not "$B" "INFO 시안 렌더" "ⓒ3[$tag] 기본 렌더에 시안 INFO 0"
  canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit back6
done

echo "== ⓓ r726 유예 시험 그대로 PASS(prev 줄이 시안으로 오염 0)"
D="$(bash "$REPO/harness/tests/test_goal_renumber_grace_r726.sh" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "ⓓ r726 시험 rc0($(printf '%s\n' "$D" | grep -c '^PASS') PASS · 0 FAIL)" || bad "ⓓ r726 시험 rc=$RC :: $(printf '%s\n' "$D" | grep '^FAIL' | head -5)"

echo "== ⓔ 변이 — 조건 삭제(if True:) 판이면 시안 렌더가 공지한다(= ⓑ FAIL 재현)"
: > "$MBOX_LOG"; rm -f "$MARK"
render "$MUT" "$DEF" > /dev/null
M="$(render "$MUT" "$R/$DPATH" "$DLED")"
[ "$(nmail)" = 1 ] && has "$(cat "$MBOX_LOG")" "[골 번호 바뀜]" "ⓔ 변이 판 = 시안 렌더 공지 1통(조건이 실제로 문다)"
not "$M" "INFO 시안 렌더" "ⓔ 변이 판에는 INFO 줄 0"

echo
[ "$fail" = 0 ] && { echo "ALL PASS r728 (draft-render-no-notice)"; exit 0; }
echo "FAILED $fail"; exit 1
