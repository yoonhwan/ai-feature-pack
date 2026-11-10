#!/usr/bin/env bash
# test_r655_nano_name_prefix.sh — r655: v65 나노 이름 접두 = byz-v65-nano-(다른 팀과 같은 꼴) · 옛 이름 ft-v65-temp- 는 «인식만» · 이름 규칙 정본 = ft_teamset.py 한 곳.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)·가짜 TEAMSET/명단/카드. 실 좌석·실 워크트리·실 tmux·실 상태 쓰기 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="${R655_SUT_KIT:-$REPO/harness/kit/fable-team/bin}"; SKILL="$REPO/skill/scripts"
. "$HERE/lib/tmux_isolate.sh"   # r957: 실 tmux 서버 격리(TMUX·TMUX_PANE 제거 + TMUX_TMPDIR) — 가짜 tmuxc 가 없는 경로도 격리 소켓만 본다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
export HIL_DIR="$T/hil"; mkdir -p "$HIL_DIR"   # ★실 /tmp/h<N> 번호표 누수 0★(2026-10-22 master 발주 #135523 — ft-tick «HIL 미실행» 오경보) — ft-hil.sh 진입점은 이 폴더에만
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE" "$T/repo/.fable-team/comm" "$T/repo/.fable-team/state"
# 가짜 tmux — list-sessions(세션 목록) · list-panes(pane·created) · display-message(pane cwd) · 오류 주입(FAKE_ERR).
FAKE_ERR="$T/tmux-err.txt"; FAKE_PANES="$T/panes.txt"; FAKE_CWD="$T/pane-cwd.txt"; : > "$FAKE_PANES"; : > "$FAKE_ERR"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
case "\$1" in
  list-sessions|ls) if [ -s "$FAKE_ERR" ]; then cat "$FAKE_ERR" >&2; exit 1; fi; cat "$SESS";;
  list-panes) cat "$FAKE_PANES";;
  display-message) if [ -s "$FAKE_CWD" ]; then cat "$FAKE_CWD"; else exit 1; fi;;
  *) exit 1;;
esac
EOF
chmod 755 "$FAKE/tmux"; : > "$SESS"
# 가짜 tmm(r1134) — r975 뒤 spawn 은 «tmm ls byz-<팀>» 에서 보고 대상을 고른다 · 격리 tmux 에는 좌석이 0 이라 실 tmm 이면 ⓐ 가 REJECT
. "$HERE/lib/fake_tmm.sh" && fake_tmm "$FAKE" "byz-v65-master-claude#1"
GIT="git -C $T/repo -c user.name=t -c user.email=t@t"
git init -q "$T/repo"
printf '2026-01-01T00:00:00\toff\tby test\tinit\n' > "$T/repo/.fable-team/state/all-stop.log"

# 카드·명단·목표·팀셋 (spawn dry-run 이 통과하는 최소 꼴 — ft-index-lint·ft_team_cands_ref 규칙 그대로)
mkdir -p "$T/repo/design/teams/v65/indices/대기"
printf '가짜 골 1줄\n가짜 골 2줄\n가짜 골 3줄\n' > "$T/goal.txt"
printf '# GOAL-LEDGER v65\n| 좌표 | 닫는 증거 |\n|---|---|\n| M1 | 「가짜 닫는 증거 원문입니다 스물자 넘김 확인용」 |\n' > "$T/repo/design/teams/v65/GOAL-LEDGER-v65.md"
printf '# 인덱스: x\n- 제안서: 없음 — 시험 픽스처\n## 골 원문 (항상 이 3줄)\n가짜 골 1줄\n가짜 골 2줄\n가짜 골 3줄\n## 골좌표\nM1 「가짜 닫는 증거 원문입니다 스물자 넘김 확인용」\n## 배경\n시험 픽스처 카드.\n## 구현 범위\n- a\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| a | b |\n## 완료 조건\n- b\n## 상태\n- 2026-10-21 대기\n' > "$T/repo/design/teams/v65/indices/대기/x.md"
printf '| 팀 | 폴더 |\n|---|---|\n| v65 | `design/teams/v65/` |\n' > "$T/repo/design/TEAMS.md"
cat > "$T/TEAMSET.md" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 3
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| v65 | 4 | 0 | 상시 |
EOF
echo '{"_version":"t"}' > "$T/repo/.fable-team/seats.json"
$GIT add -A >/dev/null && $GIT commit -qm init && $GIT update-ref refs/remotes/origin/main HEAD

# 명부 = 옛 이름 1 + 새 이름 1 + 다른 팀 1 + stop-ready 1 (전부 tmux 에 살아 있다)
cat > "$T/seats-mixed.json" <<'EOF'
{"_version":"t",
 "ft-v65-temp-oldone#0": {"role":"nano","agent":"claude","tick":null,"index":"x"},
 "byz-v65-nano-newone#0": {"role":"nano","agent":"claude","tick":null,"index":"x"},
 "byz-alpha-nano-otherone#0": {"role":"nano","agent":"claude","tick":null,"index":"x"},
 "byz-v65-nano-doneone#0": {"role":"stop-ready"}}
EOF
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0" "byz-alpha-nano-otherone#0" "byz-v65-nano-doneone#0"

sp() { ( cd "$T/repo" && PATH="$FAKE:$PATH" FT_RES_ROOT="$T/repo" FT_GOAL_LINES_FILE="$T/goal.txt" FT_TEAMSET_MD="$T/TEAMSET.md" \
  bash "$KIT/ft-nano-spawn.sh" design/teams/v65/indices/대기/x.md --dry-run --from byz-v65-master-claude#1 "$@" 2>&1 ); }
tsx() { python3 "$KIT/ft_teamset.py" "$@"; }

# ── ⓐ 새 이름(byz-v65-nano-) — v65 카드 + env 없음. 고치기 전 판은 ft-v65-temp- 라 여기서 FAIL 한다
o="$(sp)"; rc=$?
# 본문(BODY)에 실리는 규칙 글자와 섞이지 않게 «PLAN 줄» 만 본다
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-v65-nano-x#0"* ]] && ! printf '%s\n' "$o" | grep -q "PLAN seat=ft-v65-temp-"; } \
  && ok "ⓐ v65 카드 spawn → byz-v65-nano-x#0 (옛 접두 0)" || bad "ⓐ rc=$rc $(printf '%s' "$o" | tail -3)"

# ── ⓑ 워크트리·브랜치 이름은 불변 — 좌석 이름만 바뀐다
{ [[ "$o" == *"wt=$T/repo/.worktrees/v65-x"* ]] && [[ "$o" == *"branch=nano/x"* ]]; } \
  && ok "ⓑ 워크트리 v65-x · 브랜치 nano/x 불변" || bad "ⓑ $(printf '%s' "$o" | grep -m1 PLAN)"

# ── ⓒ press 게이트가 보는 «현역 v65 나노 워크트리» — 옛 이름도 새 이름도 같은 키로 센다 · stop-ready·다른 팀 제외
o="$(PATH="$FAKE:$PATH" tsx wt-v65 --seats "$T/seats-mixed.json" 2>&1 || true)"
[ "$o" = "v65-newone v65-oldone" ] && ok "ⓒ wt-v65 = 옛·새 이름 둘 다(v65-newone v65-oldone) · stop-ready·다른 팀 0" || bad "ⓒ «${o}»"
o="$(PATH="$FAKE:$PATH" bash -c "FT_NANO_PFX_V65='' python3 '$KIT/ft_teamset.py' wt-v65 --seats '$T/seats-mixed.json'" 2>&1)"
[[ "$o" == *"v65-oldone"* ]] && ok "ⓒ 옛 이름만 살아 있어도 LIVE_WT 에 남는다" || bad "ⓒ-2 «${o}»"
o="$(PATH="$FAKE:$PATH" tsx wt-v65 --seats "$T/noseats.json" 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"명부 읽기 실패"* ]]; } && ok "ⓒ 명부 없음 → rc1(조용한 통과 0)" || bad "ⓒ-3 rc=$rc «${o}»"

# ── ⓓ 닫기·되돌리기: 옛 이름·새 이름 둘 다 이름 게이트를 지난다 · 남의 팀 좌석은 이름 게이트에서 막힌다
# DA⑥ r1 H5①: --plan-only 뒤 워크트리 인자 없이 부르면 usage rc2 라 «이름 게이트» 에 도달하지 못했다 → 유효 인자(①결과·②seq)를 주고
#   이름 게이트를 «지났다» 는 증거(ENV team=… 출력)로 본다. rc 는 끝까지 간 결과(REJECT=1)이며 판정 대상이 아니다.
printf 'r\n' > "$T/result.txt"; mkdir -p "$T/repo/.fable-team/comm/bodies"; printf 'x\n' > "$T/repo/.fable-team/comm/bodies/1.txt"; printf '1' > "$T/repo/.fable-team/comm/.mbox-seq"
cl() { ( cd "$T/repo" && PATH="$FAKE:$PATH" FT_SEATS_JSON="$T/seats-mixed.json" FT_NANO_LEDGER="$T/ledger.md" FT_TMUX_BIN="$FAKE/tmux" bash "$KIT/ft-nano-close.sh" "$1" --result "$T/result.txt" --recv 1 2>&1 ); }
for s in "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0"; do
  o="$(cl "$s")"
  { [[ "$o" == *"ENV team=v65"* ]] && [[ "$o" != *"usage"* ]] && [[ "$o" != *"나노 좌석 이름이 아니다"* ]]; } \
    && ok "ⓓ 닫기 이름 게이트 통과(ENV team=v65 까지) — $s" || bad "ⓓ $s «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"
done
o="$( cd "$T/repo" && PATH="$FAKE:$PATH" FT_SEATS_JSON="$T/seats-mixed.json" FT_NANO_LEDGER="$T/ledger.md" bash "$KIT/ft-nano-close.sh" "byz-alpha-master-claude#1" --result "$T/result.txt" --recv 1 2>&1 )"
[[ "$o" == *"나노 좌석 이름이 아니다"* ]] && ok "ⓓ 남의 역할 좌석(byz-alpha-master-…)은 이름 게이트에서 REJECT" || bad "ⓓ-3 «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"
# 이름 규칙 «조회 실패» ≠ «미등록 이름» (DA⑥ r1 H4⑥) — 규칙기 없는 사본에서 돌면 미등록 REJECT 가 아니라 ERROR 로 멈춘다
T3="$T/norule-close"; mkdir -p "$T3"; cp "$KIT/ft-nano-close.sh" "$T3/"
o="$( cd "$T/repo" && PATH="$FAKE:$PATH" FT_SEATS_JSON="$T/seats-mixed.json" FT_NANO_LEDGER="$T/ledger.md" bash "$T3/ft-nano-close.sh" "byz-v65-nano-newone#0" --result "$T/result.txt" --recv 1 2>&1 )"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"ERROR 나노 이름 규칙 없음"* ]] && [[ "$o" != *"나노 좌석 이름이 아니다"* ]]; } \
  && ok "ⓓ 규칙기 없음 → ERROR(미등록 이름으로 삼키지 않음)" || bad "ⓓ-4 rc=$rc «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"

# ⓓ-undo 되돌리기 접두 게이트(ⓑ) — DA⑥ r1 H5②: 예전 칸은 카드 없음·list-panes 실패로 ⓑ 에 도달하기 전에 REJECT 되어 아무것도 재지 않았다.
#   별도 리포·가짜 pane·쪽지 기록·턴 jsonl 픽스처로 gate() 를 ⓑ 까지 통과시킨다: 옛 이름은 ⓑ 를 지나 UNDONE/PLANNED 까지, 규칙 밖 이름은 ⓑ REJECT.
UR="$T/undo-repo"; U="$UR/.worktrees/v65-u"
{ git init -q "$UR" && mkdir -p "$UR/design/teams/v65/indices/대기" "$UR/design/teams/v65/indices/진행" "$UR/.fable-team/comm" "$UR/.fable-team/state" \
  && printf 'x\n' > "$UR/base.txt" && git -C "$UR" add -A && git -C "$UR" -c user.name=t -c user.email=t@t commit -qm base \
  && git -C "$UR" branch -q nano/u && git -C "$UR" worktree add -q "$U" nano/u \
  && printf '{"branch":"nano/u","base_sha":"%s"}\n' "$(git -C "$UR" rev-parse HEAD)" > "$U/.worktree-info.json" \
  && printf '# 인덱스: u\n## 상태\n- 대기\n' > "$UR/design/teams/v65/indices/대기/u.md" \
  && : > "$UR/.fable-team/comm/mailbox.log.jsonl"; } >/dev/null 2>&1
cat > "$T/seats-undo.json" <<'EOF'
{"_version":"t",
 "ft-v65-temp-u#0": {"role":"nano","agent":"claude","tick":null,"index":"design/teams/v65/indices/진행/u.md"},
 "byz-v65-nano-u#0": {"role":"nano","agent":"claude","tick":null,"index":"design/teams/v65/indices/진행/u.md"},
 "ft-v65-oldx#0": {"role":"nano","agent":"claude","tick":null,"index":"design/teams/v65/indices/진행/u.md"}}
EOF
mkdir -p "$T/hil"   # ft-hil.sh 진입점(/tmp/h<N>) 누수 0 — 시험은 임시 폴더에만 쓴다
ENC="$(python3 -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$U")"
mkdir -p "$T/home/.claude/projects/$ENC"
: > "$FAKE_PANES"
i=0
for s in "ft-v65-temp-u#0" "byz-v65-nano-u#0" "ft-v65-oldx#0"; do   # 턴 jsonl(좌석별) + pane — gate() 가 ⓑ 까지 가려면 ⓐⓓⓖ 를 지나야 한다
  i=$((i+1)); printf '{"agentName":"%s","type":"system"}\n' "$s" > "$T/home/.claude/projects/$ENC/s$i.jsonl"
  printf '%s|%%%s|1700000000\n' "$s" "$i" >> "$FAKE_PANES"
done
printf '%s' "$U" > "$FAKE_CWD"
ud() { ( cd "$UR" && HOME="$T/home" HIL_DIR="$T/hil" PATH="$FAKE:$PATH" FT_SEATS_JSON="$T/seats-undo.json" FT_UNDO_STATE="$UR/.fable-team/state" \
  FT_MBOX_DIR="$UR/.fable-team/comm" FT_NANO_LEDGER="$T/undo-ledger.md" FT_TMUX_BIN="$FAKE/tmux" bash "$KIT/ft-nano-spawn-undo.sh" "$1" 2>&1 ); }
for s in "ft-v65-temp-u#0" "byz-v65-nano-u#0"; do
  o="$(ud "$s")"
  { [[ "$o" == *"PLANNED"* ]] && [[ "$o" != *"나노 접두"* ]] && [[ "$o" != *"로 시작하지 않는다"* ]] && [[ "$o" != *"팀 env 없음"* ]]; } \
    && ok "ⓓ-undo 접두 게이트(ⓑ) 통과 → PLANNED — $s" || bad "ⓓ-undo $s «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"
done
o="$(ud "ft-v65-oldx#0")"
{ [[ "$o" == *"나노 접두"* ]] && [[ "$o" == *"ft-v65-oldx#0"* ]]; } && ok "ⓓ-undo 접두 게이트 — 규칙 밖 이름(ft-v65-oldx#0)은 ⓑ REJECT" || bad "ⓓ-undo-neg «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"
: > "$FAKE_PANES"; : > "$FAKE_CWD"

# ── ⓔ 회수·팀셋: 옛·새 이름을 같은 v65 나노로 세고 키(접두 뺀 slug)가 같은 꼴 · 다른 팀 접두 판정 불변
o="$(tsx seat-info byz-v65-nano-newone#0 2>&1 || true)"; nk="${o#*key=}"; nk="${nk%% *}"
o2="$(tsx seat-info ft-v65-temp-newone#0 2>&1 || true)"; ok2="${o2#*key=}"; ok2="${ok2%% *}"
{ [[ "$o" == "team=v65"* ]] && [[ "$o2" == "team=v65"* ]] && [ "$nk" = "$ok2" ] && [ "$nk" = "newone" ]; } \
  && ok "ⓔ 옛·새 이름 → 같은 팀(v65)·같은 키(newone)" || bad "ⓔ «${o}» / «${o2}»"
o="$(tsx seat-info byz-alpha-nano-otherone#0 2>&1 || true)"
[[ "$o" == "team=alpha"* ]] && ok "ⓔ 다른 팀 접두 판정 불변(alpha)" || bad "ⓔ-2 «${o}»"
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_ALLOW_TRACKED_BIN=1 FT_SEATS_JSON="$T/seats-mixed.json" FT_RES_ROOT="$T/repo" bash "$KIT/ft-resource-reclaim.sh" --dry-run --caller byz-v65-master-claude#1 --need 1 --team v65 2>&1)"
{ [[ "$o" != *"팀 소속 아님(ft-v65-temp-oldone#0)"* ]] && [[ "$o" != *"팀 소속 아님(byz-v65-nano-newone#0)"* ]] && [[ "$o" != *"otherone"* ]] && [[ "$o" == *"ft-v65-temp-oldone#0"* ]] && [[ "$o" == *"byz-v65-nano-newone#0"* ]]; } \
  && ok "ⓔ 회수 --team v65 후보 = 옛·새 이름 둘 다(소속 인정) · 다른 팀 좌석은 후보 0" || bad "ⓔ-3 $(printf '%s' "$o" | head -4 | tr '\n' ' ')"

# ── ⓕ 디스크 조사: 워크트리 v65-x 의 주인 = 옛 이름 좌석이 살아 있어도 «주인 있음»
git -C "$T/repo" branch -q nano/y && git -C "$T/repo" worktree add -q "$T/repo/.worktrees/v65-y" nano/y 2>/dev/null
sess "ft-v65-temp-y#0"
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_RES_ROOT="$T/repo" FT_CENSUS_OUT="$T/census.json" bash "$KIT/ft-disk-census.sh" --json 2>&1)"; rc=$?
row="$(printf '%s' "$o" | grep -F 'v65-y' | head -1)"
{ [ "$rc" = 0 ] && [ -n "$row" ] && [[ "$row" == *live* ]] && [[ "$row" != *'"live": "?"'* ]]; } \
  && ok "ⓕ 옛 이름 좌석(ft-v65-temp-y#0) 살아 있음 → 워크트리 v65-y «live» 판정" || bad "ⓕ rc=$rc row=«${row}»"
grep -q 'ft_teamset.py" prefixes' "$KIT/ft-disk-census.sh" && ok "ⓕ 디스크 조사가 공용 규칙(접두 목록)을 읽는다" || bad "ⓕ 접두 목록 참조 없음"
# 규칙기를 못 읽으면 «주인 없음» 오판 대신 중단(fail-closed) — 규칙 파일 없는 복사본으로 확인
T2="$T/norule"; mkdir -p "$T2"; cp "$KIT/ft-disk-census.sh" "$T2/"; cp "$KIT/ft-harness-root.sh" "$T2/" 2>/dev/null
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_RES_ROOT="$T/repo" FT_CENSUS_OUT="$T/c2.json" bash "$T2/ft-disk-census.sh" --json 2>&1)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *"나노 이름 규칙"* ]]; } && ok "ⓕ 규칙기 없음 → rc4 중단(주인 없음 오판 0)" || bad "ⓕ-2 rc=$rc «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"

# ── ⓖ 키트 안 «옛 이름» 글자 = 공용 규칙 한 곳(ft_teamset.py) + 틱 문구(두 이름 다 적음) 뿐
hits="$(grep -n 'ft-v65-temp-' "$KIT"/* 2>/dev/null | grep -v 'ft_teamset.py:' | grep -v 'ft-tick-team.sh:' | grep -v 'ft-pm-tick.sh:' | grep -v '\.pyc')"
[ -z "$hits" ] && ok "ⓖ 키트 판정·이름 만드는 곳의 옛 접두 글자 = 0(정본 ft_teamset.py 밖)" || bad "ⓖ 남은 곳: $(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
grep -q 'ft-v65-temp-' "$KIT/ft-tick-team.sh" && grep -q 'byz-v65-nano-' "$KIT/ft-tick-team.sh" && ok "ⓖ 틱 문구는 두 이름 다 적는다" || bad "ⓖ 틱 문구"
[ "$(python3 "$KIT/ft_teamset.py" prefixes --team v65)" = "byz-v65-nano- ft-v65-temp-" ] && ok "ⓖ 접두 목록 정본 = byz-v65-nano- 먼저 · 옛 이름 뒤" || bad "ⓖ 접두 목록"

# ── ⓗ skill/scripts 사본 4개도 같은 규칙을 부른다(규칙 사본 = 키트와 cmp 0)
cmp -s "$SKILL/ft_teamset.py" "$KIT/ft_teamset.py" && ok "ⓗ skill/scripts/ft_teamset.py = 키트와 cmp 0" || bad "ⓗ 규칙 사본 불일치"
for f in ft-nano-spawn.sh ft-nano-close.sh ft-press-gate.sh; do
  grep -q 'ft_teamset.py' "$SKILL/$f" && ok "ⓗ $f 가 공용 규칙을 부른다" || bad "ⓗ $f 규칙 호출 0"
done
{ grep -q 'ft-v65-temp-' "$SKILL/ft-nano-spawn.sh" || true; } # spawn 사본에 옛 접두 글자 0 이어야 한다
h2="$(grep -n 'ft-v65-temp-' "$SKILL"/ft-nano-spawn.sh "$SKILL"/ft-nano-close.sh "$SKILL"/ft-press-gate.sh 2>/dev/null)"
[ -z "$h2" ] && ok "ⓗ 사본 3종에 옛 접두 글자 0" || bad "ⓗ 사본 잔여: $h2"

# ── DA⑥ r1 H1: 상한이 «그 팀의 접두 전부»(옛+새)를 센다 — 접두 하나만 세면 옛 1 + 새 N 이 상한을 통과했다
sed 's/^| v65 | 4 |/| v65 | 2 |/' "$T/TEAMSET.md" > "$T/TEAMSET-cap2.md"
grep -q '^| v65 | 2 |' "$T/TEAMSET-cap2.md" || bad "H1 픽스처(상한 2) 생성 실패"
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0"
o="$(PATH="$FAKE:$PATH" tsx cap --root "$T/repo" --md "$T/TEAMSET-cap2.md" --prefix byz-v65-nano- 2>&1)"; rc=$?
{ [ "$rc" = 4 ] && [[ "$o" == *"AT-CAP v65 live=2 cap=2"* ]]; } && ok "H1 옛1+새1 · 상한 2 → AT-CAP live=2 rc4(우회 0)" || bad "H1 rc=$rc «${o}»"
sess "byz-v65-nano-newone#0"
o="$(PATH="$FAKE:$PATH" tsx cap --root "$T/repo" --md "$T/TEAMSET-cap2.md" --prefix byz-v65-nano- 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"CAP v65 live=1 cap=2"* ]]; } && ok "H1 새 이름 1 · 상한 2 → CAP live=1 rc0(음성대조)" || bad "H1-2 rc=$rc «${o}»"
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0" "byz-alpha-nano-otherone#0" "byz-v65-nano-doneone#0"

# ── DA⑥ r1 H2: 회수 분류가 옛 이름 좌석을 «나노» 로 센다 + 규칙 조회 실패 = 회수 전체 ERROR(rc≠0)
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_ALLOW_TRACKED_BIN=1 FT_SEATS_JSON="$T/seats-mixed.json" FT_RES_ROOT="$T/repo" bash "$KIT/ft-resource-reclaim.sh" --dry-run --caller byz-v65-master-claude#1 --need 1 --team v65 2>&1)"
k_old="$(printf '%s\n' "$o" | awk -F' \\| ' '$1=="ft-v65-temp-oldone#0"{print $2}' | head -1)"
k_new="$(printf '%s\n' "$o" | awk -F' \\| ' '$1=="byz-v65-nano-newone#0"{print $2}' | head -1)"
{ [[ "$k_old" == *"나노"* ]] && [[ "$k_new" == *"나노"* ]]; } && ok "H2 회수 분류 — 옛·새 이름 둘 다 «나노»(${k_old:-빈값} / ${k_new:-빈값})" || bad "H2 분류 old=«${k_old}» new=«${k_new}»"
T4="$T/norule-reclaim"; mkdir -p "$T4"; cp -R "$KIT/." "$T4/" 2>/dev/null; rm -f "$T4/ft_teamset.py"   # 규칙기만 빼고 전부 복사 — 다른 형제 스크립트 부재가 아니라 «규칙 부재» 를 잰다
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_ALLOW_TRACKED_BIN=1 FT_SEATS_JSON="$T/seats-mixed.json" FT_RES_ROOT="$T/repo" bash "$T4/ft-resource-reclaim.sh" --dry-run --caller byz-v65-master-claude#1 --need 1 --team v65 2>&1)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"ERROR 나노 이름 규칙"* ]]; } && ok "H2 규칙 조회 실패 → rc=$rc ERROR(«남의 팀» 으로 삼키지 않음)" || bad "H2-2 rc=$rc «$(printf '%s' "$o" | head -3 | tr '\n' ' ')»"

# ── DA⑥ r1 H3: 디스크 조사가 «팀까지 맞는» 좌석만 주인으로 본다 — byz-alpha-nano-z#0 이 v65-z 를 지키면 안 된다
git -C "$T/repo" branch -q nano/z && git -C "$T/repo" worktree add -q "$T/repo/.worktrees/v65-z" nano/z 2>/dev/null
sess "ft-v65-temp-y#0" "byz-alpha-nano-z#0"
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_RES_ROOT="$T/repo" FT_CENSUS_OUT="$T/census-h3.json" bash "$KIT/ft-disk-census.sh" --json 2>&1)"; rc=$?
lz="$(printf '%s' "$o" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next((str(r["live"])+"/"+r["route"] for r in d["rows"] if r["path"].endswith("/v65-z")), ""))' 2>/dev/null)"
ly="$(printf '%s' "$o" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next((str(r["live"])+"/"+r["route"] for r in d["rows"] if r["path"].endswith("/v65-y")), ""))' 2>/dev/null)"
{ [ "$rc" = 0 ] && [[ "$lz" == False* ]] && [[ "$ly" == True* ]]; } \
  && ok "H3 남의 팀 좌석(alpha)은 v65-z 주인이 아니다(live=false · $lz) · 같은 팀 옛 이름은 주인($ly)" \
  || bad "H3 rc=$rc z=«${lz}» y=«${ly}»"
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0" "byz-alpha-nano-otherone#0" "byz-v65-nano-doneone#0" "ft-v65-temp-y#0"

# ── arch 119 H3 재대조: 워크트리 이름 앞이 «팀이 아닌» 것(concierge-·land-·set-·repo- …)은 팀을 못 읽으니 옛 패턴(모든 팀 `-nano-<키>`)으로 센다 — 실측 8개가 다른 팀 좌석이 살아 있어도 plan:nano-close 로 갔다
#   픽스처: 워크트리 `concierge-w`(머리 concierge = 팀 목록에 없음) + 가지 nano/w + 다른 팀 살아 있는 좌석 byz-alpha-nano-w#0 → 주인 있음(keep:live-seat)
git -C "$T/repo" branch -q nano/w && git -C "$T/repo" worktree add -q "$T/repo/.worktrees/concierge-w" nano/w 2>/dev/null
sess "byz-alpha-nano-w#0"
o="$(cd "$T/repo" && PATH="$FAKE:$PATH" FT_RES_ROOT="$T/repo" FT_CENSUS_OUT="$T/census-h3b.json" bash "$KIT/ft-disk-census.sh" --json 2>&1)"; rc=$?
lw="$(printf '%s' "$o" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next((str(r["live"])+"/"+r["route"] for r in d["rows"] if r["path"].endswith("/concierge-w")), ""))' 2>/dev/null)"
{ [ "$rc" = 0 ] && [[ "$lw" == True/keep:live-seat ]]; } \
  && ok "H3b 팀을 못 읽는 워크트리(concierge-w)도 옛 패턴으로 주인을 센다(live=true · $lw)" \
  || bad "H3b rc=$rc w=«${lw}»"
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0" "byz-alpha-nano-otherone#0" "byz-v65-nano-doneone#0" "ft-v65-temp-y#0"

# ── DA⑥ r1 H4⑦: tmux 오류는 «빈 목록» 이 아니라 ERROR — wt-v65 가 조용히 0 이 되면 press ① 검사가 통째로 사라진다
printf 'error connecting to /tmp/nope (Operation not permitted)\n' > "$FAKE_ERR"
o="$(PATH="$FAKE:$PATH" tsx wt-v65 --seats "$T/seats-mixed.json" 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"tmux list-sessions 실패"* ]]; } && ok "H4⑦ tmux 오류(other) → rc1 ERROR(빈 결과 통과 0)" || bad "H4⑦ rc=$rc «${o}»"
: > "$FAKE_ERR"
o="$(PATH="$FAKE:$PATH" tsx wt-v65 --seats "$T/seats-mixed.json" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"v65-oldone"* ]]; } && ok "H4⑦ 서버 없음(정상 rc0)은 그대로" || bad "H4⑦-2 rc=$rc «${o}»"

# ── DA⑥ r1 H5③: press 게이트 ① 의 «막힘 원문» — 새 이름 좌석만 열려 있어도 LIVE_WT 에 들어가 미랜딩이 막힌다(옛 코드: 검사 대상 0 → 조용한 통과)
GR="$T/gate-repo"; GW="$GR/.worktrees/v65-g"
{ git init -q "$GR" && mkdir -p "$GR/.fable-team/state" "$GR/worker" \
  && printf '2026-01-01T00:00:00\toff\tx\tinit\n' > "$GR/.fable-team/state/all-stop.log" \
  && printf '{"byz-v65-nano-g#0":{"role":"nano","agent":"claude","tick":null,"index":"x"}}\n' > "$GR/.fable-team/seats.json" \
  && printf 'a\n' > "$GR/worker/foo.py" && git -C "$GR" add -A && git -C "$GR" -c user.name=t -c user.email=t@t commit -qm base \
  && git -C "$GR" branch -q feat/v6-realtime-live && git -C "$GR" branch -q nano/g && git -C "$GR" worktree add -q "$GW" nano/g \
  && printf 'b\n' > "$GW/worker/foo.py" && git -C "$GW" -c user.name=t -c user.email=t@t commit -qam 'product change'; } >/dev/null 2>&1
sess "byz-v65-nano-g#0"   # ★새 이름 하나만★ — 옛 코드는 여기서 LIVE_WT 가 비어 ① 이 «✓» 로 통과했다
mkdir -p "$T/permits"
o="$( cd "$GW" && PATH="$FAKE:$PATH" FT_PRESS_WT="$GW" FT_PRESS_ROOT="$GR" FT_PRESS_PERMIT_DIR="$T/permits" FT_NANO_FEAT=feat/v6-realtime-live bash "$KIT/ft-press-gate.sh" 2>&1 )"; rc=$?   # r1128: 기본 기준이 origin/main 이 됐다 — 이 픽스처는 옛 feat 가지만 있다
{ [ "$rc" = 1 ] && [[ "$o" == *"✗ 미랜딩 제품 커밋 1 — v65-g"* ]] && [[ "$o" == *"PRESS-GATE BLOCK"* ]]; } \
  && ok "H5③ press ① 이 새 이름 좌석의 워크트리를 막는다(✗ 미랜딩 제품 커밋 1 — v65-g · BLOCK)" \
  || bad "H5③ rc=$rc «$(printf '%s' "$o" | grep -E '미랜딩|BLOCK' | head -3 | tr '\n' ' ')»"
sess "ft-v65-temp-oldone#0" "byz-v65-nano-newone#0" "byz-alpha-nano-otherone#0" "byz-v65-nano-doneone#0" "ft-v65-temp-y#0"

# ── DA⑥ r1 H4⑤: 다른 가지 보호가 접두 «목록 전체»(옛+새)를 본다 — 함수 본문 대조(전 경로 도달은 ③·⑤ 게이트 뒤라 픽스처 비용 > 값)
body="$(awk '/^_resolve_std_wt_other\(\)/,/^}/' "$KIT/ft-nano-close.sh")"
{ printf '%s' "$body" | grep -q 'for _p in \$_NANO_PREFIXES' && [[ "$(printf '%s' "$body" | grep -c 'grep -x "\${_p}\${okey}') " != 0 ]]; } \
  && ok "H4⑤ 다른 가지 보호가 접두 목록 전부를 본다(_resolve_std_wt_other)" || bad "H4⑤ 접두 하나만 본다"

# ── DA⑥ r1 H4①②③④: 팀 좌석 접두를 스크립트마다 박지 않는다 — 공용 규칙(team-prefixes)을 부른다 · 리터럴 잔여 0
for f in ft-news-tick-cfo.sh ft-news-tick.sh ft-blocked-on-master.sh ft-context-monitor.sh; do
  has_rule=0; ! grep -qF 'ft_teamset.py" prefixes --team v65' "$KIT/$f" || has_rule=1
  ! grep -qF 'ft_teamset.py" team-prefixes --team v65' "$KIT/$f" || has_rule=1
  lit="$(grep -nF -e "'^ft-v65'" -e "startswith('ft-v65')" -e 'prefix="$SESSION_PREFIX"' "$KIT/$f")"
  { [ "$has_rule" = 1 ] && [ -z "$lit" ]; } && ok "H4 규칙 단일화 — $f" || bad "H4 $f rule=$has_rule lit=«$(printf '%s' "$lit" | head -2 | tr '\n' ' ')»"
done

# ── DA⑥ r1 H4⑧: skill/scripts 사본이 «실행된다»(set -u 에서 HERE 미정의로 모든 호출이 죽었다)
o="$( cd "$T/repo" && PATH="$FAKE:$PATH" HOME="$T/home" FT_SEATS_JSON="$T/seats-mixed.json" bash "$SKILL/ft-nano-close.sh" byz-v65-nano-newone#0 --result "$T/result.txt" --recv 1 2>&1 )"
{ [[ "$o" != *"unbound variable"* ]] && [[ "$o" != *"HERE"* ]]; } && ok "H4⑧ skill 사본 실행 — HERE unbound 0(판정까지 감)" || bad "H4⑧ «$(printf '%s' "$o" | head -2 | tr '\n' ' ')»"

# ── 짝(추적본 bin) 바이트 일치
for f in ft-nano-spawn.sh ft-nano-close.sh ft-nano-spawn-undo.sh ft-press-gate.sh ft-resource-reclaim.sh ft-disk-census.sh ft_teamset.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 cmp 0 $f" || bad "짝 불일치 $f"
done

# ── r957 누수 검사: 실 tmux 서버에 시험 세션(byz-alpha-·byz-v65-·ft-v65-temp-)이 남으면 FAIL ──
tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
