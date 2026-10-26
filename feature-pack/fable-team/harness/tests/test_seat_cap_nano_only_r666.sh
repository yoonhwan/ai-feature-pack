#!/usr/bin/env bash
# test_seat_cap_nano_only_r666.sh — r666: 위성팀 좌석 한도가 팀장·은퇴 팀장 화면까지 세어 나노 자리가 1개 · 거절이 rc1 로 조용히 끝남
#   → ⓐ ft_seat_cap.py count = byz-<팀>-nano- 만(위성 합 한도도) ⓑ 나노 3개면 한도 그대로(숫자 유지)
#   ⓒ 한도면 ft-resource-reclaim.sh --team 회수 1회 → 재판정 → ★r921 W1★ live=cap 이면 WARN + 진행 · live>=cap+1 이면 ft_spawn_queue.py add → exit 7
#   ⓔ 판정기 단독 tmux 실패 = ERROR rc1 그대로 · 스폰 경로는 ERROR 줄 + WARN 측정 실패 + 진행(r921)
# 전부 mktemp — 가짜 tmux·임시 리포·가짜 센서. 실 tmux·실 명부·실 좌석·실 회수 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
KIT="$REPO/feature-pack/fable-team/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
ROOT="$T/root"; FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$ROOT/.fable-team" "$ROOT/.fable-team/state" "$FAKE"
. "$REPO/feature-pack/fable-team/harness/tests/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 명부 — lecture·room 은 같은 위성팀(_parent v65)
echo '{"_parent":"v65","_master":null}' > "$ROOT/.fable-team/seats-lecture.json"
echo '{"_parent":"v65","_master":null}' > "$ROOT/.fable-team/seats-room.json"

# 가짜 tmux — 인자 없이 list-sessions 만 답한다
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; has-session) exit 1;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
sess() { : > "$SESS"; printf '%s\n' "$@" >> "$SESS"; }
cap() { PATH="$FAKE:$PATH" FT_NANO_PREFIX=byz-lecture-nano- FT_TEAM_SEAT_CAP=3 FT_GROUP_SEAT_CAP=6 FT_SEATS_JSON="$ROOT/.fable-team/seats-lecture.json" env "$@" python3 "$KIT/ft_seat_cap.py" --root "$ROOT" 2>&1; }

# ⓐ 실사건 재현 — 팀장 화면 2(현역 + 은퇴한 옛 팀장) + 나노 1 = 옛 판은 «3/3» 로 막았다
sess byz-lecture-master-claude#10 byz-lecture-master-claude#9 byz-lecture-nano-l15#0
o="$(cap)"; rc=$?
{ [ "$rc" = 0 ] && [ -z "$o" ]; } && ok "ⓐ 팀장 2 + 나노 1 → 통과(나노 기준 1/3) rc0" || bad "ⓐ rc=$rc o=$o"
o="$(cap FT_TEAM_SEAT_CAP=1)"; rc=$?
{ [ "$rc" = 1 ] && [ "$o" = "REJECT 좌석 상한 lecture 1/1" ]; } && ok "ⓐ' 나노 1 = 한도 1 → REJECT(나노는 그대로 센다): $o" || bad "ⓐ' rc=$rc o=$o"

# ⓑ 나노 수가 한도 — 3개면 막는다(숫자 유지)
sess byz-lecture-nano-a#0 byz-lecture-nano-b#0 byz-lecture-nano-c#0
o="$(cap)"; rc=$?
{ [ "$rc" = 1 ] && [ "$o" = "REJECT 좌석 상한 lecture 3/3" ]; } && ok "ⓑ 나노 3/3 → REJECT: $o" || bad "ⓑ rc=$rc o=$o"
sess byz-lecture-master-claude#10 byz-lecture-tester-claude#0 byz-lecture-nano-a#0 byz-lecture-nano-b#0 byz-lecture-nano-c#0 byz-lecture-nano-d#0
o="$(cap FT_TEAM_SEAT_CAP=4)"; rc=$?
{ [ "$rc" = 1 ] && [ "$o" = "REJECT 좌석 상한 lecture 4/4" ]; } && ok "ⓑ 역할 좌석이 늘어도 나노 4개로만 센다: $o" || bad "ⓑ rc=$rc o=$o"

# ⓑ' 위성 합 한도도 나노만 — room 나노 3 + lecture 나노 1 · 팀장 화면은 안 센다(옛 판은 6/4)
sess byz-room-master-claude#0 byz-room-master-claude#1 byz-room-nano-a#0 byz-room-nano-b#0 byz-room-nano-c#0 byz-lecture-nano-l15#0
o="$(cap FT_TEAM_SEAT_CAP=9 FT_GROUP_SEAT_CAP=4)"; rc=$?
{ [ "$rc" = 1 ] && [ "$o" = "REJECT 위성 합 상한 4/4" ]; } && ok "ⓑ' 위성 합 = 나노 4/4: $o" || bad "ⓑ' rc=$rc o=$o"

# ⓔ tmux 목록 실패 = ERROR rc1 (조용한 통과 0)
printf '#!/bin/sh\necho "tmux: boom" >&2; exit 1\n' > "$FAKE/tmux"
o="$(cap)"; rc=$?
{ [ "$rc" = 1 ] && grep -q '^ERROR' <<<"$o"; } && ok "ⓔ tmux 실패 = ERROR rc1: $(head -1 <<<"$o")" || bad "ⓔ rc=$rc o=$o"

# ── 스폰 경로 (임시 리포 · 가짜 tmux · 가짜 센서 · 가짜 회수) ─────────────────────────
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; has-session) exit 1;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
git init -q "$T/repo" && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$T/repo/.fable-team/state" "$T/repo/.fable-team/comm" "$T/repo/design/lecture/indices/대기"
printf '#!/bin/sh\necho "SENT stub"\n' > "$T/repo/.fable-team/comm/mbox.sh"; chmod 755 "$T/repo/.fable-team/comm/mbox.sh"
cp "$ROOT/.fable-team/seats-lecture.json" "$ROOT/.fable-team/seats-room.json" "$T/repo/.fable-team/"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$T/repo/.fable-team/state/all-stop.log"
CARD="$T/repo/design/lecture/indices/대기/x.md"; echo '# 카드' > "$CARD"
Q="$T/repo/.fable-team/state/spawn-queue-lecture.tsv"
# 가짜 회수: 인자를 기록하고 FREE 파일이 있으면 lecture 나노 1개를 목록에서 뺀다(= 끝난 나노를 닫았다)
cat > "$T/reclaim.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$T/reclaim.calls"
[ -f "$T/reclaim.free" ] && { grep -v '^byz-lecture-nano-a#0$' "$SESS" > "$SESS.n"; mv "$SESS.n" "$SESS"; }
echo "RECLAIMED 0"
EOF
spawn() { ( cd "$T/repo" && . "$ROOT/.fable-team/seats-lecture.json" 2>/dev/null; \
  FT_SEATS_JSON="$T/repo/.fable-team/seats-lecture.json" FT_MBOX_SH="$T/repo/.fable-team/comm/mbox.sh" \
  FT_NANO_PREFIX=byz-lecture-nano- FT_TEAM_SEAT_CAP=3 FT_GROUP_SEAT_CAP=6 \
  FT_RECLAIM_SH="$T/reclaim.sh" PATH="$FAKE:$PATH" bash "$KIT/ft-nano-spawn.sh" "$CARD" "$@" 2>&1 ); }
sess byz-lecture-master-claude#10 byz-lecture-master-claude#9 byz-lecture-nano-a#0 byz-lecture-nano-b#0 byz-lecture-nano-c#0

# ⓒ 한도(나노 3/3 = cap) → 회수 1회(닫은 것 0) → 재판정 한도 → ★r921 W1★ cap+1 까지 연다(WARN 1줄 · 큐 0 · 다음 단계로)
rm -f "$T/reclaim.calls" "$Q"
o="$(spawn)"; rc=$?
{ [ "$rc" != 7 ] && grep -q 'WARN resource seat-cap REJECT 좌석 상한 lecture 3/3' <<<"$o" && ! grep -q '^QUEUED' <<<"$o" \
  && [ "$(grep -c . "$T/reclaim.calls" 2>/dev/null || echo 0)" = 1 ] && grep -q -- '--need 1 --team lecture' "$T/reclaim.calls" && [ ! -f "$Q" ]; } \
  && ok "ⓒ 한도(cap) → 회수 1회(--team lecture · --need 1) → WARN 1줄 + 진행(rc=$rc · 큐 0 · r921)" || bad "ⓒ rc=$rc o=$o / calls=$(cat "$T/reclaim.calls" 2>/dev/null)"
# ⓒ+ 나노 4/3(cap+1) → 회수 1회(닫은 것 0) → 그래도 포화 → 순번 큐 + exit 7 · 카드 1줄
sess byz-lecture-master-claude#10 byz-lecture-nano-a#0 byz-lecture-nano-b#0 byz-lecture-nano-c#0 byz-lecture-nano-d#0
rm -f "$T/reclaim.calls" "$Q"
o="$(spawn)"; rc=$?
{ [ "$rc" = 7 ] && grep -q '^REJECT 좌석 상한 lecture 4/3' <<<"$o" && grep -q '^QUEUED lecture 순번=1' <<<"$o" \
  && [ "$(grep -c . "$T/reclaim.calls" 2>/dev/null || echo 0)" = 1 ] && [ -f "$Q" ] && [ "$(grep -c . "$Q")" = 1 ] && grep -q 'x.md' "$Q"; } \
  && ok "ⓒ+ cap+1(4/3) → 회수 1회 → 재판정 포화 → QUEUED lecture 순번=1 · rc7 · 큐 1줄" || bad "ⓒ+ rc=$rc o=$o"
sess byz-lecture-master-claude#10 byz-lecture-master-claude#9 byz-lecture-nano-a#0 byz-lecture-nano-b#0 byz-lecture-nano-c#0

# ⓒ' --dry-run 은 회수·큐 0 · 옛 rc1 그대로 (부작용 0 지점 시험)
rm -f "$T/reclaim.calls" "$Q"
o="$(spawn --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && grep -q '^REJECT 좌석 상한 lecture 3/3' <<<"$o" && [ ! -f "$T/reclaim.calls" ] && [ ! -f "$Q" ]; } \
  && ok "ⓒ' --dry-run: 회수 0 · 큐 0 · rc1(옛 동작 보존)" || bad "ⓒ' rc=$rc o=$o"

# ⓒ'' 회수가 자리를 만들면(나노 2/3) 한도를 통과해 다음 단계로 간다 — 좌석 상한 REJECT·큐 0
: > "$T/reclaim.free"; rm -f "$T/reclaim.calls" "$Q"
o="$(spawn)"; rc=$?
{ [ "$rc" != 7 ] && ! grep -q 'REJECT 좌석 상한' <<<"$o" && [ ! -f "$Q" ] && grep -q -- '--team lecture' "$T/reclaim.calls"; } \
  && ok "ⓒ'' 회수로 2/3 이 되면 통과(rc=$rc · 다음 단계가 막은 것) · 큐 0" || bad "ⓒ'' rc=$rc o=$o"

# ⓓ 회수 대상 판정은 기존 reclaim 그대로 — 일하는 나노는 그 도구가 제외한다(이 카드는 인자만 넘긴다)
{ grep -q -- '--team lecture' "$T/reclaim.calls" && ! grep -q -- '--preventive' "$T/reclaim.calls"; } \
  && ok "ⓓ 회수 호출 = --team lecture(팀 한정 · 전좌석 선제 회수 아님)" || bad "ⓓ calls=$(cat "$T/reclaim.calls")"

# ⓔ' 스폰 경로의 tmux 실패 = ERROR 줄 + ★r921 W1★ «측정 실패 WARN + 진행»(정지 0 · 큐 0 · 조용한 통과 0)
printf '#!/bin/sh\necho "tmux: boom" >&2; exit 1\n' > "$FAKE/tmux"; rm -f "$T/reclaim.calls" "$Q"
o="$(spawn)"; rc=$?
{ [ "$rc" != 7 ] && grep -q '^ERROR' <<<"$o" && grep -q 'WARN 좌석 상한 측정 실패' <<<"$o" && [ ! -f "$Q" ] && [ ! -f "$T/reclaim.calls" ]; } \
  && ok "ⓔ' 스폰: tmux 실패 = ERROR 줄 + WARN 측정 실패 · 진행(rc=$rc · 다음 단계가 막은 것) · 큐 0" || bad "ⓔ' rc=$rc o=$o"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED ($fail)"
exit "$fail"
