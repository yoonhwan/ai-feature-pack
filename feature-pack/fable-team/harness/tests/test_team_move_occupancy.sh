#!/usr/bin/env bash
# test_team_move_occupancy.sh — R382d `ft-team-move --plan --all` 점유 판정 = lsof «한 번» (7초 룰 · 총 마감 70초)
#   ⓐ 워크트리 N(=3×100) × 팀 13: lsof 호출 1회(≤ 팀 수) · 경과 < 70 s · 옛 함수(팀×워크트리 `lsof +D` 직렬)와 같은 픽스처에서 LSOF/CWD 결과 동일
#   ⓑ lsof 7초 초과·실패·부재 → `BLOCK … 점유 판정 불가` + plan rc≠0 + apply REJECT(쓰기 0)
# 임시 폴더·가짜 tmux·가짜 lsof 만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"; KIT="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }

echo "== 0 키트 사본 cmp0"
cmp -s "$SRC/ft_team_move.py" "$KIT/ft_team_move.py" && ok "키트 사본 cmp0 ft_team_move.py" || bad "키트 사본 cmp ft_team_move.py"

mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) if [ -s "${FAKE_PANES:-/nonexistent}" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;\nesac\n' > "$T/fake/tmux"
# 가짜 lsof — 호출 인자를 FAKE_LSOF_CALLS 에 한 줄씩 남기고, FAKE_LSOF(줄마다 "<명령> <pid> <열린 경로>") 를
#   `-Fpcn`(새 방식)은 p/c/n 레코드로, `+D <dir>`(옛 방식 · 동치 대조 전용)은 dir 아래 파일만 컬럼 줄로 낸다. FAKE_LSOF_MODE=hang|fail
cat > "$T/fake/lsof" <<'EOF'
#!/usr/bin/env python3
import os, sys
open(os.environ["FAKE_LSOF_CALLS"], "a").write(" ".join(sys.argv[1:]) + "\n")
mode = os.environ.get("FAKE_LSOF_MODE", "")
if os.environ.get("FAKE_LSOF_FAIL_AFTER") and len(open(os.environ["FAKE_LSOF_CALLS"]).read().splitlines()) > int(os.environ["FAKE_LSOF_FAIL_AFTER"]):
    mode = "fail"   # N 번째 호출까지 정상 · 그 뒤 실패(팀 루프 중간 실패 모사)
if mode == "hang":
    import time; time.sleep(60)
if mode == "fail":
    sys.stderr.write("lsof: WARNING: boom\n"); sys.exit(2)
if mode == "empty":
    sys.exit(0)   # rc0 + 빈 stdout
rows = [ln.split(None, 2) for ln in open(os.environ.get("FAKE_LSOF", "/dev/null")).read().splitlines() if ln.strip()]
if sys.argv[1] == "+D":
    d = sys.argv[2].rstrip("/") + "/"
    print("COMMAND PID USER FD TYPE NAME")
    for c, p, n in rows:
        if n.startswith(d) or n == d.rstrip("/"):
            print(f"{c} {p} u cwd DIR {n}")
else:
    print("p1\ncfake\nn/dev/null")
    for c, p, n in rows:
        print(f"p{p}\nc{c}\nn{n}")
EOF
chmod +x "$T/fake/tmux" "$T/fake/lsof"
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

TEAMS13=(harness planner cfo ops graphics issues feature kk v65 loom lecture room concierge)
REPO="$T/repo"; mkdir -p "$REPO/design" "$REPO/.fable-team" "$REPO/.worktrees"
git -C "$REPO" init -q -b main
{ printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'; for t in "${TEAMS13[@]}"; do printf '| %s | `design/%s/` | byz-%s-master-claude | 현역 |\n' "$t" "$t" "$t"; done; } > "$REPO/design/TEAMS.md"
{ printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n'; for t in "${TEAMS13[@]}"; do printf '| %s | 3 |\n' "$t"; done; } > "$REPO/design/TEAMSET.md"
for t in "${TEAMS13[@]}"; do mkdir -p "$REPO/design/$t"; printf '# %s\n' "$t" > "$REPO/design/$t/README.md"; done
printf '.worktrees/\n.fable-team/\n' > "$REPO/.gitignore"
GITC "$REPO" add -A >/dev/null 2>&1; GITC "$REPO" commit -q -m init
N=$((3*100))
for i in $(seq 1 $N); do for t in "${TEAMS13[@]}"; do mkdir -p "$REPO/.worktrees/w$i/design/$t"; done; done

# 열린 파일 — 팀 폴더 안(루트·워크트리·깊은 경로·폴더 자체) 5 + 바깥(접두만 같은 형제 폴더·팀 아닌 경로) 3
W5="$REPO/.worktrees/w5"; W7="$REPO/.worktrees/w7"
cat > "$T/lsof.rows" <<EOF
vim 4242 $REPO/design/harness/README.md
node 5151 $W5/design/cfo/sub/deep/x.md
zsh 6001 $W7/design/harness
vim 4243 $W7/design/harness/README.md
code 7007 $REPO/design/planner/a.md
vim 8001 $REPO/design/harness2/decoy.md
vim 8002 $W5/src/main.py
vim 8003 $REPO/design/teams/harness/new.md
EOF
printf 'byz-cfo-master-claude#1\t%s/design/cfo\nbyz-x#0\t%s/.worktrees/w9/design/ops/sub\nbyz-y#0\t%s/design/cfo2\n' "$REPO" "$REPO" "$REPO" > "$T/panes"
RUNENV() { FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_LSOF_CALLS="$T/calls" FAKE_LSOF="$T/lsof.rows" FAKE_PANES="$T/panes" PATH="$T/fake:$PATH" "$@"; }

echo "== ⓐ 워크트리 $N × 팀 13 — lsof 1회 · < 70 s · 옛 방식과 결과 동일"
: > "$T/calls"; s=$SECONDS
out="$(RUNENV bash "$SRC/ft-team-move.sh" --plan --all 2>&1)"; rc=$?; el=$((SECONDS-s))
[ "$rc" = 0 ] && ok "ⓐ plan --all rc0" || bad "ⓐ plan rc=$rc ← ${out:0:400}"
calls="$(wc -l < "$T/calls" | tr -d ' ')"
[ "$calls" -le 13 ] && [ "$calls" = 1 ] && ok "ⓐ lsof 호출 $calls 회(팀 13 · 워크트리 $N 인데도 1회)" || bad "ⓐ lsof 호출 $calls 회"
[ "$el" -lt 70 ] && ok "ⓐ 전체 경과 ${el}s < 70" || bad "ⓐ 경과 ${el}s"
has "$out" "LSOF vim pid=4242 $REPO/design/harness" "ⓐ 루트 팀 폴더 안 열린 파일"
has "$out" "LSOF node pid=5151 $W5/design/cfo" "ⓐ 워크트리 팀 폴더 깊은 경로"
has "$out" "LSOF zsh pid=6001 $W7/design/harness" "ⓐ 팀 폴더 자체를 연 프로세스"
has "$out" "CWD byz-cfo-master-claude#1 $REPO/design/cfo" "ⓐ tmux pane cwd 판정 그대로"
case "$out" in *decoy*|*pid=8001*|*pid=8002*|*pid=8003*|*cfo2*) bad "ⓐ 접두만 같은/팀 밖 경로가 점유로 잡힘";; *) ok "ⓐ 접두만 같은 형제(harness2·cfo2)·팀 밖 경로는 점유 아님";; esac
cat > "$T/equiv.py" <<'PYEOF'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import ft_team_move as m

def old_occupancy(ctx, team):   # R382 착지판(88cec102bc) — 팀 × 폴더마다 `lsof +D` 직렬. 동치 대조의 기준(oracle)
    dirs = [ctx.root / "design" / team] + [w / "design" / team for w in ctx.worktrees()]
    out = []
    tm = m.run("tmux", "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}")
    if tm.returncode == 0:
        for line in tm.stdout.splitlines():
            sess, _, cwd = line.partition("\t")
            if any(cwd == str(d) or cwd.startswith(f"{d}/") for d in dirs):
                out.append(f"CWD {sess} {cwd}")
    for d in dirs:
        if not d.is_dir():
            continue
        ls = m.run(os.environ["FT_TEAM_MOVE_LSOF"], "+D", str(d), timeout=7)
        out += [f"LSOF {ln.split()[0]} pid={ln.split()[1]} {d}" for ln in ls.stdout.splitlines()[1:] if len(ln.split()) > 1]
    return out

ctx = m.make_ctx()
snap = m.occupancy_snapshot()
diff = [t for t in ctx.rows if sorted(old_occupancy(ctx, t)) != sorted(m.occupancy(ctx, t, snap))]
total = sum(len(m.occupancy(ctx, t, snap)) for t in ctx.rows)
print(f"EQUIV teams={len(ctx.rows)} diff={diff} lines={total}")
PYEOF
res="$(RUNENV python3 -I "$T/equiv.py" "$SRC" 2>&1 | tail -1)"
case "$res" in "EQUIV teams=13 diff=[] lines="[1-9]*) ok "ⓐ 옛 함수 vs 새 함수 13팀 결과 집합 동일 ← $res";; *) bad "ⓐ 동치 대조: $res";; esac

echo "== ⓑ lsof 7초 초과·실패·부재 → BLOCK 점유 판정 불가 · plan rc≠0 · apply REJECT"
HEAD0="$(git -C "$REPO" rev-parse HEAD)"
: > "$T/calls"; s=$SECONDS
out="$(FAKE_LSOF_MODE=hang RUNENV bash "$SRC/ft-team-move.sh" --plan --all 2>&1)"; rc=$?; el=$((SECONDS-s))
[ "$rc" != 0 ] && ok "ⓑ lsof 멈춤: plan rc=$rc(≠0)" || bad "ⓑ lsof 멈춤인데 plan rc0"
has "$out" "BLOCK lsof 7초 초과" "ⓑ BLOCK 줄"
[ "$(printf '%s\n' "$out" | grep -c 'BLOCK')" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^PLAN ')" = 0 ] && ok "ⓑ BLOCK 은 팀 루프 전 «한 줄» · 13팀 반복 0 · PLAN 줄 0" || bad "ⓑ BLOCK 반복: $(printf '%s\n' "$out" | grep -c 'BLOCK')줄 ← ${out:0:400}"
[ "$el" -lt 70 ] && [ "$(wc -l < "$T/calls" | tr -d ' ')" = 1 ] && ok "ⓑ 멈춘 lsof 도 1회 · ${el}s < 70(팀마다 7초씩 쌓이지 않음)" || bad "ⓑ 경과 ${el}s · 호출 $(wc -l < "$T/calls")"
out="$(FAKE_LSOF_MODE=fail RUNENV bash "$SRC/ft-team-move.sh" --plan harness 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "점유 판정 불가" "ⓑ lsof 실패(rc2·출력 없음): plan rc≠0 + BLOCK" || bad "ⓑ lsof 실패 rc=$rc ← ${out:0:400}"
out="$(FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_TEAM_MOVE_LSOF=/nonexistent/lsof PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --plan harness 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "lsof 를 실행하지 못했다" "ⓑ lsof 부재: Traceback 대신 BLOCK + rc≠0" || bad "ⓑ lsof 부재 rc=$rc ← ${out:0:400}"
out="$(FAKE_LSOF_MODE=fail RUNENV bash "$SRC/ft-team-move.sh" --apply harness 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 점유 판정 불가" "ⓑ lsof 실패: apply REJECT rc1" || bad "ⓑ apply rc=$rc ← ${out:0:400}"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && [ -d "$REPO/design/harness" ] && [ ! -d "$REPO/design/teams/harness" ] && ok "ⓑ REJECT 는 쓰기 0(HEAD·폴더 그대로)" || bad "ⓑ REJECT 인데 변경됨"

echo "== ⓑ' lsof rc0 + 빈 stdout(레코드 0) = 관찰 실패 → BLOCK · plan rc1 · apply REJECT · 쓰기 0 (DA⑥ Q3)"
out="$(FAKE_LSOF_MODE=empty RUNENV bash "$SRC/ft-team-move.sh" --plan harness 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "열린 파일 레코드 0" "ⓑ' rc0+빈 stdout: plan rc1 + BLOCK" || bad "ⓑ' plan rc=$rc ← ${out:0:400}"
out="$(FAKE_LSOF_MODE=empty RUNENV bash "$SRC/ft-team-move.sh" --apply --all 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && [ -d "$REPO/design/harness" ] && [ ! -d "$REPO/design/teams/harness" ] && ok "ⓑ' rc0+빈 stdout: apply rc1 · HEAD·폴더 불변" || bad "ⓑ' apply rc=$rc ← ${out:0:400}"

echo "== ⓑ'' design/<팀> 이 «실경로에 design 이 없는» 심볼릭 링크여도 그 안 열린 파일이 점유로 잡힌다 (DA⑥ Q2)"
R4="$T/repo4"; git clone -q "$REPO" "$R4"; mkdir -p "$R4/.fable-team" "$R4/.worktrees" "$T/actual"
rm -rf "$R4/design/planner"; ln -s "$T/actual" "$R4/design/planner"
printf 'vim 9001 %s/held.txt\n' "$T/actual" > "$T/lsof.alias"
out="$(FT_REPO_ROOT="$R4" FT_PROJECT_ROOT="$R4" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_LSOF_CALLS="$T/calls" FAKE_LSOF="$T/lsof.alias" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --plan planner 2>&1)"
has "$out" "LSOF vim pid=9001 $R4/design/planner" "ⓑ'' alias(실경로에 design 없음)의 열린 파일 = LSOF 점유"

echo "== ⓒ --apply --all — 팀 이동 «직전» 마다 점유 재스냅샷 · 총 경과 < 70 s · 중간 실패 1줄 중단 · 마감 소진 PARTIAL rc3 (DA⑥ Q1·Q4)"
: > "$T/calls"
out="$(FAKE_LSOF_MODE=fail RUNENV bash "$SRC/ft-team-move.sh" --apply --all 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(wc -l < "$T/calls" | tr -d ' ')" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c 'BLOCK')" = 1 ] && ok "ⓒ lsof 실패 apply --all: 팀 루프 전 BLOCK 1줄 · rc1 · lsof 호출 1회" || bad "ⓒ 실패 apply --all rc=$rc 호출 $(wc -l < "$T/calls" | tr -d ' ') BLOCK $(printf '%s\n' "$out" | grep -c 'BLOCK') ← ${out:0:400}"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && ok "ⓒ  └ 쓰기 0(HEAD 불변)" || bad "ⓒ 실패인데 HEAD 변경"
newrepo() { git clone -q "$REPO" "$1"; mkdir -p "$1/.fable-team" "$1/.worktrees"; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }
CL() { local R="$1"; shift; env FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_LSOF_CALLS="$T/calls" FAKE_LSOF=/dev/null PATH="$T/fake:$PATH" "$@"; }
R2="$T/repo2"; newrepo "$R2"; : > "$T/calls"; s=$SECONDS
out="$(CL "$R2" bash "$SRC/ft-team-move.sh" --apply --all 2>&1)"; rc=$?; el=$((SECONDS-s))
[ "$(printf '%s\n' "$out" | grep -c '^MOVED ')" = 13 ] && [ "$(wc -l < "$T/calls" | tr -d ' ')" = 13 ] && [ "$el" -lt 70 ] && ok "ⓒ 점유 없음 apply --all: 13팀 MOVED · lsof 호출 13회(팀 수) · ${el}s < 70 (복제 리포)" || bad "ⓒ 성공 apply --all rc=$rc MOVED=$(printf '%s\n' "$out" | grep -c '^MOVED ') 호출 $(wc -l < "$T/calls" | tr -d ' ') ${el}s ← ${out: -400}"
R3="$T/repo3"; newrepo "$R3"; : > "$T/calls"
out="$(CL "$R3" env FAKE_LSOF_FAIL_AFTER=2 bash "$SRC/ft-team-move.sh" --apply --all 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^MOVED ')" = 2 ] && [ "$(printf '%s\n' "$out" | grep -c 'BLOCK')" = 1 ] && [ "$(wc -l < "$T/calls" | tr -d ' ')" = 3 ] && ok "ⓒ 3번째 팀 직전 lsof 실패: 앞 2팀 MOVED · BLOCK 1줄 · 루프 중단(호출 3회) · rc1" || bad "ⓒ 중간 실패 rc=$rc MOVED=$(printf '%s\n' "$out" | grep -c '^MOVED ') 호출 $(wc -l < "$T/calls" | tr -d ' ') ← ${out: -500}"
cat > "$T/partial.py" <<'PYEOF'
import sys, time
sys.path.insert(0, sys.argv[1])
import ft_team_move as m, ft_team_move_apply as ap
clock = [0.0]
time.monotonic = lambda: clock[0]            # 가짜 시계 — 실제로 기다리지 않는다(subprocess 는 자기 시계를 쓴다)
real = m.run
def fake(*cmd, **kw):
    if str(cmd[0]).endswith("lsof"):
        clock[0] += 30                       # lsof 한 번이 30초 걸린다고 모사
    return real(*cmd, **kw)
m.run = fake
print("RC=%d" % ap.main(["--apply", "--all"], m.make_ctx()))
PYEOF
R5="$T/repo5"; newrepo "$R5"; : > "$T/calls"
out="$(CL "$R5" python3 -I "$T/partial.py" "$SRC" 2>&1)"
[ "$(printf '%s\n' "$out" | grep -c '^MOVED ')" = 3 ] && has "$out" "RC=3" "ⓒ 총 마감 70 s 소진(lsof 30 s×3): 3팀 MOVED 뒤 PARTIAL rc3" || bad "ⓒ 마감 소진 ← ${out: -500}"
has "$out" "PARTIAL " "ⓒ  └ PARTIAL 줄(남은 팀 목록 + 다음 --apply 이어감)"
# 재스냅샷 «도중» 마감 소진(DA⑥ r2 Q4) — 첫 팀 뒤 69 s · 둘째 팀 lsof 잔여 cap 1 s 초과 = BLOCK(rc1) 이 아니라 이동 전 PARTIAL rc3 · 남은 팀 pending 기록 · 앞 팀 MOVED 보존
cat > "$T/partial2.py" <<'PYEOF'
import glob, json, os, subprocess, sys, time
sys.path.insert(0, sys.argv[1])
import ft_team_move as m, ft_team_move_apply as ap
clock, n = [0.0], [0]
time.monotonic = lambda: clock[0]
real = m.run
def fake(*cmd, **kw):
    if str(cmd[0]).endswith("lsof"):
        n[0] += 1
        if n[0] == 1:
            clock[0] += 69                   # 첫 팀(루프 전 스냅샷) 뒤 69 s 지남
        elif kw["timeout"] < 7:
            raise subprocess.TimeoutExpired(list(cmd), kw["timeout"])   # 잔여 cap(1 s)을 넘겨 걸린다
    return real(*cmd, **kw)
m.run = fake
rc = ap.main(["--apply", "--all"], m.make_ctx())
snap = json.load(open(sorted(glob.glob(os.environ["FT_REPO_ROOT"] + "/.fable-team/state/team-move/*/snapshot.json"))[-1], encoding="utf-8"))
print("RESULT " + json.dumps({"rc": rc, "pending": snap["pending_teams"]}))
PYEOF
R6="$T/repo6"; newrepo "$R6"; : > "$T/calls"
out="$(CL "$R6" python3 -I "$T/partial2.py" "$SRC" 2>&1)"; res="$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')"
python3 -I -c 'import json,sys;r=json.loads(sys.argv[1]);assert r["rc"]==3,r;assert len(r["pending"])==12 and "harness" not in r["pending"],r' "$res" \
  && [ "$(printf '%s\n' "$out" | grep -c '^MOVED ')" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c 'BLOCK')" = 0 ] && has "$out" "PARTIAL planner" "ⓒ 재스냅샷 도중 마감 소진: 첫 팀 MOVED 보존 · 둘째 팀부터 이동 전 PARTIAL rc3 · 남은 12팀 pending 기록 · BLOCK 0 ← $res" || bad "ⓒ 도중 마감 소진: res=$res ← ${out: -500}"
[ -d "$R6/design/planner" ] && [ ! -d "$R6/design/teams/planner" ] && ok "ⓒ  └ 둘째 팀(planner) 미이동" || bad "ⓒ 둘째 팀이 옮겨졌다"

echo "== fail=$fail"; [ "$fail" = 0 ]
