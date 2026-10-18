#!/usr/bin/env bash
# test_team_move_resume.sh — R383 ⓔ `ft-team-move --apply --all` «이어하기»: refs() 가 팀당 25 s 걸려 공유 마감 70 s 를 넘겨도 같은 --apply 재호출이 끝까지 간다
#   모의: 가짜 시계(time.monotonic) + refs() 호출마다 +25 s(팀당 2회 = 이동 전 REF · 이동 뒤 AFTER → 팀당 50 s · 한 호출에 2팀) — 실 sleep 0 · 실 tmux·lsof 0(가짜 lsof) · 복제 리포에서만 쓴다(실제 리포·seats·세션은 건드리지 않는다)
#   기대: 13팀 한 번에 → PARTIAL rc3(pending_teams 기록) → 같은 호출 N회 → 마지막 rc0 · MOVED 13 · pending=[] · 이동 커밋 13개(중복 0) · 스냅샷 폴더마다 따로(앞 스냅샷 바이트 불변)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) echo "no server running on /tmp/fake"; exit 1;;\nesac\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\nprintf "p1\\ncfake\\nn/dev/null\\n"\nexit 0\n' > "$T/fake/lsof"
chmod +x "$T/fake/tmux" "$T/fake/lsof"

TEAMS13=(harness planner cfo ops graphics issues feature kk v65 loom lecture room concierge)
REPO="$T/repo"; mkdir -p "$REPO/design" "$REPO/.fable-team" "$REPO/.worktrees"
git -C "$REPO" init -q -b main
{ printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'; for t in "${TEAMS13[@]}"; do printf '| %s | `design/%s/` | byz-%s-master-claude | 현역 |\n' "$t" "$t" "$t"; done; } > "$REPO/design/TEAMS.md"
{ printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n'; for t in "${TEAMS13[@]}"; do printf '| %s | 3 |\n' "$t"; done; } > "$REPO/design/TEAMSET.md"
for t in "${TEAMS13[@]}"; do mkdir -p "$REPO/design/$t"; printf '# %s\n정본: design/%s/README.md\n' "$t" "$t" > "$REPO/design/$t/README.md"; done
printf '.worktrees/\n.fable-team/\n' > "$REPO/.gitignore"
GITC "$REPO" add -A >/dev/null 2>&1; GITC "$REPO" commit -q -m init

cat > "$T/pass.py" <<'PYEOF'
import json, os, sys
sys.path.insert(0, sys.argv[1]); clock0 = float(sys.argv[2]); per_refs = float(sys.argv[3])
import ft_team_move as m, ft_team_move_apply as ap
clock = [clock0]
ap.time.monotonic = lambda: clock[0]          # 가짜 시계 — 실제로 기다리지 않는다
m.time.monotonic = ap.time.monotonic
real_refs = ap.refs
def slow_refs(ctx, team):
    clock[0] += per_refs                      # refs() 한 번이 팀당 25 s 라고 모사(실측 · r382d)
    return real_refs(ctx, team)
ap.refs = slow_refs
rc = ap.main(["--apply", "--all"], m.make_ctx())
print("CLOCK %s" % clock[0])
print("RC=%d" % rc)
PYEOF
PASS() { env FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_TEAM_MOVE_STATE="$REPO/.fable-team/state/team-move" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" python3 -I "$T/pass.py" "$SRC" "$1" 25 2>&1; }

echo "== ⓔ 이어하기 — 13팀 · refs() 팀당 25 s · 공유 마감 70 s"
clock=0; rcs=""; movedn=0; first_snap=""; first_sha=""; seen=""; dup=0; maxpass=10
for n in $(seq 1 $maxpass); do
  out="$(PASS "$clock")"; rc="$(printf '%s\n' "$out" | sed -n 's/^RC=//p')"; clock="$(printf '%s\n' "$out" | sed -n 's/^CLOCK //p')"
  rcs="$rcs $rc"; m="$(printf '%s\n' "$out" | sed -n 's/^MOVED \([a-z0-9]*\) .*/\1/p')"
  for t in $m; do case " $seen " in *" $t "*) dup=$((dup+1));; esac; seen="$seen $t"; done
  movedn=$((movedn + $(printf '%s\n' "$m" | grep -c .)))
  snap="$(ls -d "$REPO"/.fable-team/state/team-move/*/ 2>/dev/null | sort | tail -1)"
  if [ "$n" = 1 ]; then
    first_snap="${snap}snapshot.json"; first_sha="$(shasum -a 256 "$first_snap" | cut -d' ' -f1)"
    p1="$(python3 -I -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["pending_teams"]))' "$first_snap")"
    [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -q '^PARTIAL ' && ok "ⓔ 1회차: PARTIAL rc3 + PARTIAL 줄(남은 팀 목록 · 다음 --apply 가 이어간다)" || bad "ⓔ 1회차 rc=$rc ← ${out: -400}"
    [ "$p1" = 11 ] && ok "ⓔ 1회차 스냅샷 pending_teams=11(처리 못 한 팀 기록 · 2팀 MOVED)" || bad "ⓔ 1회차 pending=${p1}"
  fi
  [ "$rc" = 0 ] && break
done
[ "$rcs" = " 3 3 3 3 3 3 0" ] && ok "ⓔ rc 순서 3→3→3→3→3→3→0(같은 --apply --all 재호출 7회로 끝까지)" || bad "ⓔ rc 순서 [${rcs} ]"
[ "$movedn" = 13 ] && ok "ⓔ MOVED 합 13(팀마다 정확히 1번)" || bad "ⓔ MOVED 합 $movedn"
[ "$dup" = 0 ] && ok "ⓔ 같은 팀 두 번 이동 0(옮긴 팀은 RESYNC)" || bad "ⓔ 중복 이동 $dup"
last="$(ls -d "$REPO"/.fable-team/state/team-move/*/ | sort | tail -1)snapshot.json"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["pending_teams"]==[],d["pending_teams"]' "$last" && ok "ⓔ 마지막 스냅샷 pending_teams=[](소진)" || bad "ⓔ 마지막 pending 남음"
[ "$(ls -d "$REPO"/.fable-team/state/team-move/*/ | wc -l | tr -d ' ')" = 7 ] && [ "$(shasum -a 256 "$first_snap" | cut -d' ' -f1)" = "$first_sha" ] && ok "ⓔ 스냅샷 7개 따로 · 1회차 스냅샷 바이트 불변(덮어쓰기 0)" || bad "ⓔ 스냅샷 개수·불변"
cnt="$(git -C "$REPO" log --format=%s | grep -c '^\[structure\] 팀 폴더 이동 ')"
[ "$cnt" = 13 ] && ok "ⓔ 이동 커밋 13개(팀마다 1 · 중복 0)" || bad "ⓔ 이동 커밋 $cnt"
left="$(for t in "${TEAMS13[@]}"; do [ -d "$REPO/design/$t" ] && echo "$t"; done | tr '\n' ' ')"; made="$(for t in "${TEAMS13[@]}"; do [ -d "$REPO/design/teams/$t" ] && echo "$t"; done | wc -l | tr -d ' ')"
[ -z "$left" ] && [ "$made" = 13 ] && ok "ⓔ design/<팀>/ 0 · design/teams/<팀>/ 13" || bad "ⓔ 폴더 left=[${left}] made=${made}"
v="$(env FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --verify --all 2>&1)"; vrc=$?
[ "$vrc" = 0 ] && printf '%s\n' "$v" | grep -q 'VERIFY ERR=0' && ok "ⓔ 이어하기 끝난 뒤 --verify --all ERR=0" || bad "ⓔ verify rc=$vrc ← ${v: -300}"
echo "== fail=$fail"; [ "$fail" = 0 ]
