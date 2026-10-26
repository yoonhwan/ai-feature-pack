#!/usr/bin/env bash
# test_r989_role_spawn_add.sh — r989: ft-role-spawn.sh `--add` = 같은 역할의 «추가 좌석»(교체 0).
#   ⓐ `--add --dry-run` PLAN = replaces=[<없음>] mode=add · 명부 쓰기 0 · `_add` 없는 호출은 교체 PLAN 그대로
#   ⓑ 실전 모의: 새 행 1 추가 · 기존 행 `_replaced_by` 0 · role 그대로 · tick 그대로 · `_arch` 키 불변
#      + `--add` 의 tick 은 «역할 기본값»(구 좌석 tick 을 물려받지 않는다 — pm 행 ft-custom-tick 픽스처)
#   ⓒ `--add` 첫 발주문에 retire 칸 0 (없는 호출엔 있음)
#   ⓓ `--add` 없는 호출은 지금과 같다(교체 · stop-ready · tick null · `_arch` 이동 · retire 칸) + 기존 시험 2종 ALL PASS
#   ⓔ 변이: `--add` 가 구 좌석을 닫도록 되돌리면 ⓑ 가 FAIL
#   ⑥ kit/bin 짝 cmp0 · /bin/bash 3.2 로 실행
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

for f in ft-role-spawn.sh; do bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f"; done

# ⑥ kit 짝 = harness/bin 사본 (ft-goal-check 관례)
cmp -s "$KIT/ft-role-spawn.sh" "$HERE/../bin/ft-role-spawn.sh" && ok "⑥ kit·bin 짝 cmp0" || bad "⑥ kit·bin 짝이 다르다"
/bin/bash -c 'true' && ok "⑥ /bin/bash 실행 가능" || bad "⑥ /bin/bash 없음"

# ── 픽스처: 임시 리포 · TEAMS.md · feat 명부(arch#3 현역 · pm#2 tick=ft-custom-tick) · 팀 폴더 ──
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK"
git init -q "$R"; mkdir -p "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| feat | `design/teams/feat/` | x | 현역 |\n' > "$R/design/TEAMS.md"
mkdir -p "$R/design/teams/feat/indices/inbox/arch" "$R/design/teams/feat/indices/inbox/pm"
: > "$R/design/teams/feat/SEATBELT-README.md"
feat_roster() { printf '{"_name":"feat","_master":"byz-feat-master-claude#30","_arch":"byz-feat-arch-claude#3"%s,\n "byz-feat-arch-claude#3":{"role":"arch","agent":"claude","tick":null,"model":"claude-opus-5-5[1m]","index":"design/teams/feat/indices/inbox/arch/"},\n "byz-feat-pm-claude#2":{"role":"pm","agent":"claude","tick":"ft-custom-tick","model":"claude-opus-5-5[1m]","index":"design/teams/feat/indices/inbox/pm/"}}\n' "${1:+,$1}" > "$R/.fable-team/seats-feat.json"; }
feat_roster ""
cp -p "$R/.fable-team/seats-feat.json" "$T/roster.before"

# 실행본 = 키트 사본 + 가짜 송신·가짜 전팀정지 (실 쪽지 0)
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$B"/ft-all-stop.sh
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
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
row() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));n=sys.argv[2];r=d.get(n,{});print("absent" if not r else "%s|%s|%s"%(r.get("_replaced_by") or "NONE", r.get("role"), r.get("tick")))' "$R/.fable-team/seats-feat.json" "$1"; }

# ── ⓐ --add --dry-run: PLAN = replaces=[<없음>] mode=add · 명부 쓰기 0 ──
o="$(rs arch --team feat --add --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-feat-arch-claude#4 role=arch"* && "$o" == *"replaces=[<없음>] mode=add"* ]]; } \
  && ok "ⓐ --add dry-run: 새 번호 #4 · replaces=[<없음>] mode=add" || bad "ⓐ rc=$rc $o"
cmp -s "$R/.fable-team/seats-feat.json" "$T/roster.before" && ok "ⓐ dry-run 명부 쓰기 0" || bad "ⓐ dry-run 이 명부를 건드렸다"
o="$(rs arch --team feat --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"replaces=[byz-feat-arch-claude#3]"* && "$o" != *"mode=add"* ]]; } \
  && ok "ⓐ --add 없는 호출: 교체 PLAN 그대로(mode=add 0)" || bad "ⓐ 없이 rc=$rc $o"

# ── ⓒ BODY retire 칸: --add 0 · 없으면 있음 ──
o="$(rs arch --team feat --add --dry-run)"
[[ "$o" == *"BODY "* && "$o" != *"retire="* ]] && ok "ⓒ --add 첫 발주문에 retire 칸 0" || bad "ⓒ --add BODY $o"
o="$(rs arch --team feat --dry-run)"
[[ "$o" == *"retire="* ]] && ok "ⓒ --add 없으면 retire 칸 있음" || bad "ⓒ 없이 BODY $o"

# ── ⓑ 실전 모의: arch --add + pm --add (tick = 역할 기본값) ──
o="$(rs arch --team feat --add)"; rc=$?
a="$(row byz-feat-arch-claude#3)"; n="$(row byz-feat-arch-claude#4)"
k="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("_arch"),d["byz-feat-arch-claude#4"]["_replaces"],sum(1 for x,v in d.items() if isinstance(v,dict) and v.get("role")=="arch" and not v.get("_replaced_by")))' "$R/.fable-team/seats-feat.json")"
{ [ "$rc" = 0 ] && [[ "$o" == *"SPAWNED byz-feat-arch-claude#4 role=arch"* ]] \
  && [ "$n" = "NONE|arch|None" ] && [ "$a" = "NONE|arch|None" ] && [ "$k" = "byz-feat-arch-claude#3 [] 2" ]; } \
  && ok "ⓑ --add 실전: 새 행 #4(_replaces=[]) · 기존 #3 _replaced_by 0·role·tick 그대로 · _arch=#3 불변 · 현역 arch 2" \
  || bad "ⓑ rc=$rc old=[$a] new=[$n] keys=[$k] $o"
o="$(rs pm --team feat --add)"; rc=$?
p="$(row byz-feat-pm-claude#3)"
{ [ "$rc" = 0 ] && [ "$p" = "NONE|pm|ft-pm-tick" ] && [ "$(row byz-feat-pm-claude#2)" = "NONE|pm|ft-custom-tick" ]; } \
  && ok "ⓑ --add tick = 역할 기본값(ft-pm-tick) · 구 좌석 tick(ft-custom-tick) 물려받지 않음" || bad "ⓑ pm rc=$rc new=[$p] $o"

# ── ⓓ --add 없는 호출 = 지금 그대로(교체) ──
feat_roster ""; cp -p "$R/.fable-team/seats-feat.json" "$T/roster.before"; : > "$OPENED"   # 번호 = max(명부·열린 세션)+1 — 앞 절이 연 세션을 지워 #4 로 고정
o="$(rs arch --team feat)"; rc=$?
a="$(row byz-feat-arch-claude#3)"; n="$(row byz-feat-arch-claude#4)"
k="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("_arch"),",".join(d["byz-feat-arch-claude#4"]["_replaces"]))' "$R/.fable-team/seats-feat.json")"
{ [ "$rc" = 0 ] && [ "$a" = "byz-feat-arch-claude#4|stop-ready|None" ] && [ "$n" = "NONE|arch|None" ] \
  && [ "$k" = "byz-feat-arch-claude#4 byz-feat-arch-claude#3" ]; } \
  && ok "ⓓ --add 없음: 구 #3 을 _replaced_by·stop-ready·tick null 로 닫고 _arch 이동(불변 동작)" || bad "ⓓ rc=$rc old=[$a] new=[$n] keys=[$k] $o"
for t in test_role_spawn_name.sh test_role_spawn_team.sh; do
  out="$(cd "$HERE" && bash "$HERE/$t" 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && [[ "$out" == *"ALL PASS"* ]]; } && ok "ⓓ 기존 시험 $t ALL PASS" || bad "ⓓ 기존 시험 $t rc=$rc $(printf '%s' "$out" | tail -3)"
done

# ── ⓔ 변이: --add 가 old 를 닫도록 되돌리면 ⓑ 가 FAIL ──
MUT="$B/mut"; mkdir -p "$MUT"; cp -p "$B"/*.sh "$B"/*.py "$MUT/" 2>/dev/null
sed 's/^old = \[\] if add else /old = /' "$B/ft-role-spawn.sh" > "$MUT/ft-role-spawn.sh"
grep -q '^old = \[k for k' "$MUT/ft-role-spawn.sh" && ok "ⓔ 변이본 생성(old = [] if add else → old = [k for k …])" || bad "ⓔ 변이 sed 불일치"
feat_roster ""; : > "$OPENED"
o="$(cd "$R" && PATH="$FK:$PATH" bash "$MUT/ft-role-spawn.sh" arch --team feat --add 2>&1)"; rc=$?
a="$(row byz-feat-arch-claude#3)"
{ [ "$rc" = 0 ] && [[ "$a" == *"|stop-ready|None" ]] && [ "$a" != "NONE|arch|None" ]; } \
  && ok "ⓔ 변이: --add 가 구 좌석을 닫는다($a) → ⓑ('_replaced_by 0') FAIL 재현" || bad "ⓔ 변이 rc=$rc old=[$a] $o"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
