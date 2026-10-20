#!/usr/bin/env bash
# test_penalty_spawn_gate.sh — R320b: PENALTY_STOP 가 있으면 ft-nano-spawn.sh·ft-role-spawn.sh 가 재개 전 팀을 REJECT 한다(부작용 전 · --dry-run 도 같다).
# 임시 git 리포 + 가짜 tmux/tmuxc + 가짜 자원 센서 — 실 seats.json·tmux·파일은 건드리지 않는다.
set -u   # pipefail 쓰지 않는다 — `cmd | grep -q` 가 SIGPIPE(141)로 거짓 FAIL 을 낸다
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; mkdir -p "$REPO" "$FAKE"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; *) exit 0;; esac\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmuxc"; chmod +x "$FAKE/tmux" "$FAKE/tmuxc"
fake_comm_root "$REPO" || bad "fake_comm_root"   # r537: git init + .fable-team/comm(r459 spawn-hold 가 푼다) · FT_ROOT=REPO
mkdir -p "$REPO/.fable-team/state" "$REPO/design/v65/indices/inbox/master"; : > "$REPO/design/v65/SEATBELT-README.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$REPO/design/TEAMS.md"   # R382b: v65 폴더는 TEAMS.md 칸으로 풀린다
echo '{}' > "$REPO/.fable-team/seats.json"
STOP="$REPO/.fable-team/state/PENALTY_STOP"

role()  { (cd "$REPO" && env -u FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM="$1" PATH="$FAKE:$PATH" bash "$BIN/ft-role-spawn.sh" master --dry-run 2>&1); }
nano()  { (cd "$REPO" && PATH="$FAKE:$PATH" bash "$BIN/ft-nano-spawn.sh" "design/$1/indices/대기/x.md" --dry-run 2>&1); }

role t1 | grep -q '^PLAN ' && ok "정지 파일 없음 → role PLAN" || bad "정지 파일 없음인데 role 이 막힘"
nano t1 | grep -q 'REJECT penalty' && bad "정지 파일 없음인데 nano 가 penalty REJECT" || ok "정지 파일 없음 → nano penalty 거절 0"

echo '{"since":1,"reason":"시험","order":["t1","t2"],"resumed":[]}' > "$STOP"
role t1 | grep -q '^REJECT penalty' && ok "정지 중 role 재개 전 팀 REJECT" || bad "정지 중 role 이 안 막힘: $(role t1 | head -2)"
role "" | grep -q '^REJECT penalty' && ok "정지 중 role 팀 미상 REJECT" || bad "팀 미상이 통과"
nano t1 | grep -q '^REJECT penalty' && ok "정지 중 nano 재개 전 팀 REJECT" || bad "정지 중 nano 가 안 막힘: $(nano t1 | head -2)"

echo '{"since":1,"reason":"시험","order":["t1","t2"],"resumed":["t1"]}' > "$STOP"
role t1 | grep -q '^PLAN ' && ok "재개된 팀 role 통과" || bad "재개된 t1 role 이 막힘"
role t2 | grep -q '^REJECT penalty' && ok "재개 전 t2 는 계속 REJECT" || bad "t2 가 통과"
nano t1 | grep -q 'REJECT penalty' && bad "재개된 t1 nano 가 penalty 로 막힘" || ok "재개된 팀 nano penalty 거절 0"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
