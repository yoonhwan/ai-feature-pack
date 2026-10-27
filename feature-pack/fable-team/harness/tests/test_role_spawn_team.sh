#!/usr/bin/env bash
# test_role_spawn_team.sh — R437: ft-role-spawn --team(명부·폴더·이름이 그 팀) + arch 없음 REJECT/ERR 문구가 «있는 길» 1줄을 적는다.
#   ⓐ --team feat → 명부 seats-feat.json · 인박스·README = feat 폴더 · 이름 byz-feat-arch-claude#N · seats.json 쓰기 0 · 빈 _arch 채움
#   ⓑ --team 없음 → v65 동작 불변 ⓒ feat 폴더에 README 없음 → REJECT(v65 대체 0) ⓓ 명단에 없는 팀 → REJECT · _arch 가 남의 좌석 → REJECT(successor-open 안내)
#   ⓔ successor-open arch-live REJECT 문구 = 죽은 arch → successor-open 명령 / _arch 없음 → role-spawn --team 명령 ⓕ teamset-check ERR 같은 1줄 ⓖ 600/300 0
# 전부 mktemp 안 — 가짜 tmux/tmuxc(PATH)·가짜 송신·가짜 자원 센서. 실 tmux·실 명부·실 쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok

for f in ft-role-spawn.sh ft-successor-open.sh ft-teamset-check.sh; do bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f"; done

# ── 픽스처: 임시 리포 · TEAMS.md(v65 꼴1 · feat·nor 꼴2) · 명부 · 팀 폴더 ──
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK"
git init -q "$R"; mkdir -p "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n| feat | `design/teams/feat/` | x | 현역 |\n| nor | `design/teams/nor/` | x | 현역 |\n' > "$R/design/TEAMS.md"
mkdir -p "$R/design/v65/indices/inbox/arch" "$R/design/teams/feat/indices/inbox/arch" "$R/design/teams/nor/indices/inbox/arch"
: > "$R/design/v65/SEATBELT-README.md"; : > "$R/design/teams/feat/SEATBELT-README.md"   # nor 는 README 없음(ⓒ)
printf '{"_master":"byz-v65-master-claude#1","byz-v65-arch-claude#3":{"role":"arch","agent":"claude"}}\n' > "$R/.fable-team/seats.json"
printf '{"_name":"nor","_master":"byz-nor-master-claude#1"}\n' > "$R/.fable-team/seats-nor.json"
feat_roster() { printf '{"_name":"feat","_master":"byz-feat-master-claude#30"%s}\n' "${1:+,\"_arch\":\"$1\"}" > "$R/.fable-team/seats-feat.json"; }
cp -p "$R/.fable-team/seats.json" "$T/seats.v65.before"

# 실행본 = 키트 사본 + 가짜 송신(실 쪽지 0)
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done   # r921: 문지기가 swap-lib 를 source 한다(임시 bin 짝 누락 보충)
printf '#!/usr/bin/env bash\nexit 0\n' > "$B"/ft-all-stop.sh   # r626 DA⑥ r2: spawn 이 .fable-team 있으면 늘 전팀 정지 check — 사본 bin 에 없으면 REJECT · 이 시험 주제 밖이라 통과 스텁
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
# 가짜 tmuxc: open 이면 --name 을 열린 목록에 적는다 · 가짜 tmux: 열린 목록에 있는 이름만 has-session 0
OPENED="$T/opened"; : > "$OPENED"
printf '#!/bin/bash\n[ "$1" = open ] || exit 0\nn=""; d=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && d=1; shift; done\n[ "$d" = 1 ] && { echo "TMUXC-DRY $n"; exit 0; }\necho "$n" >> %s\n' "$OPENED" > "$FK/tmuxc"
cat > "$FK/tmux" <<EOF
#!/bin/bash
case "\$1" in
  has-session) n="\${3#=}"; grep -qxF -- "\$n" "$OPENED";;
  list-panes) while read -r n; do echo "\$n|%9"; done < "$OPENED";;
  show-option) echo 1;;
  list-sessions) [ -s "$T/sessions" ] && cat "$T/sessions"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x "$B"/* "$FK"/*
rs() { (cd "$R" && PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1); }

# ⓐ --team feat (dry-run → 실제)
feat_roster ""
o="$(rs arch --team feat --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-feat-arch-claude#0 role=arch"* ]] && [[ "$o" == *"inbox=design/teams/feat/indices/inbox/arch"* ]] \
  && [[ "$o" == *"$R/design/teams/feat/SEATBELT-README.md §2"* ]] && [[ "$o" != *"design/v65"* ]]; } \
  && ok "ⓐ dry-run: 이름 byz-feat-arch-claude#0 · 인박스·README = feat 폴더 · v65 경로 0" || bad "ⓐ dry-run rc=$rc $o"
o="$(rs arch --team feat)"; rc=$?
row="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));r=d.get("byz-feat-arch-claude#0",{});print(r.get("role"),r.get("index"),d.get("_arch"))' "$R/.fable-team/seats-feat.json")"
{ [ "$rc" = 0 ] && [[ "$o" == *"SPAWNED byz-feat-arch-claude#0 role=arch inbox=design/teams/feat/indices/inbox/arch"* ]] \
  && [ "$row" = "arch design/teams/feat/indices/inbox/arch/ byz-feat-arch-claude#0" ] && cmp -s "$R/.fable-team/seats.json" "$T/seats.v65.before"; } \
  && ok "ⓐ 실제: seats-feat.json 행+_arch=byz-feat-arch-claude#0 · seats.json(v65) 쓰기 0" || bad "ⓐ 실제 rc=$rc row=[$row] $o"
o="$(rs arch --team feat --dry-run)"
[[ "$o" == *"PLAN seat=byz-feat-arch-claude#1 "*"replaces=[byz-feat-arch-claude#0]"* ]] && ok "ⓐ 다음 회: 번호 이어받기 #1 · 교체 = 현역 #0" || bad "ⓐ 다음 회 $o"

# ⓑ --team 없음 → v65 동작 불변
o="$(rs arch --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-v65-arch-claude#4 "*"inbox=design/v65/indices/inbox/arch "*"replaces=[byz-v65-arch-claude#3]"* ]]; } \
  && ok "ⓑ --team 없음: byz-v65-arch-claude#4 · v65 인박스 · 교체 #3 (불변)" || bad "ⓑ rc=$rc $o"
o="$(rs arch --team v65 --dry-run)"
[[ "$o" == *"PLAN seat=byz-v65-arch-claude#4 "*"inbox=design/v65/indices/inbox/arch "* ]] && ok "ⓑ --team v65 = 기본과 같다" || bad "ⓑ --team v65 $o"

# ⓒ feat 꼴인데 README 없음 → REJECT · v65 로 대체 0
o="$(rs arch --team nor --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT nor SEATBELT-README.md 없음: $R/design/teams/nor/SEATBELT-README.md"* ]] && [[ "$o" != *PLAN* ]] && [[ "$o" != *design/v65* ]]; } \
  && ok "ⓒ README 없음 → REJECT(경로) rc1 · PLAN 0 · v65 대체 0" || bad "ⓒ rc=$rc $o"

# ⓓ 명단에 없는 팀 → REJECT · 명부 _arch 가 교체 대상 밖(죽은 좌석) → REJECT(successor-open 안내)
o="$(rs arch --team zzz --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT zzz 팀 폴더를 못 풀었다"* ]] && [[ "$o" != *PLAN* ]]; } && ok "ⓓ 명단 밖 팀 → REJECT rc1" || bad "ⓓ rc=$rc $o"
o="$(rs arch --team 'Bad Team' --dry-run)"; rc=$?
[ "$rc" = 2 ] && ok "ⓓ 팀 이름 형식 위반 → usage rc2" || bad "ⓓ 형식 rc=$rc $o"
feat_roster "byz-feat-arch-claude#41"
o="$(rs arch --team feat --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT 명부 _arch=byz-feat-arch-claude#41 가 이미 있다"*"ft-successor-open.sh 'byz-feat-arch-claude#41'"* ]] && [[ "$o" != *"PLAN "* ]]; } \
  && ok "ⓓ _arch=#41(행 없음·죽음) → REJECT + successor-open 안내 · 두 arch 0" || bad "ⓓ _arch 충돌 rc=$rc $o"

# ── ⓔⓕ arch 없음 문구 (successor-open · teamset-check · 판정기 하나 = ft_teamset.py) ──
MD="$T/TEAMSET.md"
cat > "$MD" <<'EOF'
# 가짜 팀셋
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | a | b |
| arch | 상시 팀만 1 | `opus-5-5` | high | `_arch` | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: `_name`
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| feat | 3 | 0 | 상시 |
EOF
M="byz-feat-master-claude#30"; DEAD="byz-feat-arch-claude#41"
SRES="$FT_RES_ROOT"; mkdir -p "$SRES/.fable-team"
printf '골 1\n골 2\n골 3\n본문\n' > "$T/body.txt"; git init -q "$T/wt"
for x in send mbox reach; do printf '#!/bin/sh\nexit 1\n' > "$FK/$x"; done; chmod +x "$FK"/*
echo "$M" > "$T/sessions"
so() { cp "$R/.fable-team/seats-feat.json" "$SRES/.fable-team/seats-feat.json"
  env HOME="$T/home" PATH="$FK:$PATH" FT_RES_ROOT="$SRES" FT_TEAMSET_MD="$MD" FT_SO_POLL=0 FT_SO_WAIT_MAX=1 \
      FT_SEND_VERIFIED="$FK/send" FT_MBOX_SH="$FK/mbox" FT_REACH_CHECK="$FK/reach" \
      bash "$KIT/ft-successor-open.sh" "$M" "$T/wt" --name "byz-feat-master-claude#31" --agent claude --model m --body-file "$T/body.txt" 2>&1; }
HINT_SO="→ 열기: ft-successor-open.sh '$DEAD' <feat 워크트리> --name 'byz-feat-arch-claude#42' --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file <골 3줄+인계>"
HINT_RS="→ 열기: ft-role-spawn.sh arch --team feat"

feat_roster "$DEAD"
o="$(so)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT 그 팀 arch 좌석 없음"* ]] && [[ "$o" == *"$HINT_SO"* ]] && [[ "$o" != *"$HINT_RS"* ]]; } \
  && ok "ⓔ 죽은 arch(_arch=#41) → REJECT 문구에 successor-open #41→#42 명령 1줄" || bad "ⓔ 죽은 arch rc=$rc $o"
feat_roster ""
o="$(so)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT 그 팀 arch 좌석 없음"* ]] && [[ "$o" == *"$HINT_RS"* ]] && [[ "$o" != *"ft-successor-open.sh '"* ]]; } \
  && ok "ⓔ _arch 칸 없음 → REJECT 문구에 ft-role-spawn.sh arch --team feat 1줄" || bad "ⓔ arch 없음 rc=$rc $o"
feat_roster "$DEAD"; cp "$R/.fable-team/seats-feat.json" "$SRES/.fable-team/seats-feat.json"
o="$(PATH="$FK:$PATH" python3 "$KIT/ft_teamset.py" arch-live --root "$SRES" --md "$MD" --seat "$DEAD" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "OK feat _arch" ]; } && ok "ⓔ arch 자신의 교대는 여전히 통과(게이트 기준 불변): $o" || bad "ⓔ arch 자신 rc=$rc $o"

FS="$T/fake-status.sh"; printf '#!/bin/sh\necho "IDLE - - - jsonl"\n' > "$FS"; chmod +x "$FS"
chk() { FT_TEAMSET_MBOX="$FK/mbox" FT_SEAT_STATUS="$FS" PATH="$FK:$PATH" FT_TEAMSET_ROOT="$R" FT_TEAMSET_MD="$MD" ZC_RESUME_DIR="$T/resume" bash "$KIT/ft-teamset-check.sh" feat 2>&1; }
feat_roster "$DEAD"
o="$(chk)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "feat ERR "*"arch 없음 — 명부 _arch $DEAD 라이브 아님 $HINT_SO"* ]]; } && ok "ⓕ teamset-check ERR 줄 = 죽은 arch + successor-open 1줄" || bad "ⓕ 죽은 arch rc=$rc $o"
feat_roster ""
o="$(chk)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "feat ERR "*"arch 없음 — 명부 _arch 칸이 비었다 $HINT_RS"* ]]; } && ok "ⓕ teamset-check ERR 줄 = 빈 _arch + role-spawn --team 1줄" || bad "ⓕ 빈 _arch rc=$rc $o"

# ⓖ 이 단위가 바꾼 줄에 600/300 초 0 (7초 룰 · 하드 룰 12)
n="$(git -C "$HERE/.." diff origin/main -- kit/fable-team/bin/ft-role-spawn.sh kit/fable-team/bin/ft-successor-open.sh kit/fable-team/bin/ft-teamset-check.sh kit/fable-team/bin/ft_teamset.py 2>/dev/null | grep '^+' | grep -cE '\b(600|300)\b')"
[ "$n" = 0 ] && ok "ⓖ 바꾼 줄 600/300 0" || bad "ⓖ 바꾼 줄에 600/300 $n곳"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
