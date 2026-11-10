#!/usr/bin/env bash
# test_spawn_queue_folder_done_r681.sh — r681: spawn 순번 큐의 완료 판정을 «명부 행» 에서 «같은 indices 아래 진행/·완성/ 에 같은 이름 실재» 로 바꾼다(양의 증거만).
#   ⓑ 진행/·완성/ 으로 옮겨진 카드는 큐에서 빠지고 순번 = 대기/ 실재 행만 · ⓒ 어디에도 없는 카드만 확인 필요(행 유지·순번 밖)
#   ⓓ 반송된 카드는 다시 셈 · ⓔ 팀 폴더 꼴 경로도 같다 · ⓕ 알림 맨 앞 = 대기 첫째 · teamset 확인 필요 = 확인 필요만 · ⓖ 기존 시험 대조
# 전부 mktemp 안 — 가짜 루트·가짜 명부·가짜 mbox. 실 좌석·실 큐 파일 손대지 않는다.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
. "$HERE/lib/tmux_isolate.sh"   # r957: 실 tmux 서버 격리(TMUX·TMUX_PANE 제거 + TMUX_TMPDIR)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

ROOT="$T/root"; IDX="$T/idx"; mkdir -p "$ROOT/.fable-team/state" "$IDX/대기" "$IDX/진행" "$IDX/완성"
Q="$ROOT/.fable-team/state/spawn-queue-alpha.tsv"
# 명부에 나노 행 0 = 완료 근거를 «명부 행» 에서 뺐다는 증명(옛 판은 이 상태에서 아무것도 지우지 못한다)
printf '{"_name":"alpha","_master":"byz-alpha-master-claude#1","_arch":"byz-alpha-arch-claude#1"}\n' > "$ROOT/.fable-team/seats-alpha.json"
q() { python3 "$BIN/ft_spawn_queue.py" "$@" --root "$ROOT" --prefix byz-alpha-nano- 2>&1; }
card() { : > "$IDX/대기/$1"; echo "$IDX/대기/$1"; }
reset() { rm -f "$Q" "${Q%.tsv}.notified"; }
nq() { [ -f "$Q" ] && grep -c . "$Q" || echo 0; }
has() { grep -qF "$1" "$Q" 2>/dev/null; }

[ -f "$BIN/ft_spawn_queue.py" ] && python3 -m py_compile "$BIN/ft_spawn_queue.py" && ok "py_compile ft_spawn_queue.py" || bad "ft_spawn_queue.py 없음/문법"
cmp -s "$BIN/ft_spawn_queue.py" "$KIT/ft_spawn_queue.py" && ok "키트 사본 cmp 0" || bad "키트 사본 불일치"

# ⓑ 재현 → 후판: 3행 = 대기 실재 1 + 진행/ 으로 옮겨졌고 명부 행 없음 1 + 완성/ 1 → 새 카드 순번 = 2 · 큐 2행 · stuck 0
reset
c1="$(card c1.md)"; c2="$(card c2.md)"; c3="$(card c3.md)"
o1="$(q add --card "$c1" --from m#1)"; o2="$(q add --card "$c2" --from m#1)"; o3="$(q add --card "$c3" --from m#1)"
{ [[ "$o1" == "QUEUED alpha 순번=1" ]] && [[ "$o2" == "QUEUED alpha 순번=2" ]] && [[ "$o3" == "QUEUED alpha 순번=3" ]]; } && ok "ⓑ 준비 3행 순번 1·2·3" || bad "ⓑ-0 $o1 / $o2 / $o3"
mv "$IDX/대기/c2.md" "$IDX/진행/c2.md"; mv "$IDX/대기/c3.md" "$IDX/완성/c3.md"
o4="$(q add --card "$(card c4.md)" --from m#1)"
{ [[ "$o4" == "QUEUED alpha 순번=2" ]] && [ "$(nq)" = 2 ] && has "$c1" && has "$IDX/대기/c4.md" && ! has "$c2" && ! has "$c3" && [ -z "$(q stuck)" ]; } \
  && ok "ⓑ 진행/·완성/ 으로 간 카드는 큐에서 빠짐 · 순번=대기 실재만(2) · stuck 0" || bad "ⓑ $o4 q=$(cat "$Q") stuck=$(q stuck)"

# ⓒ 큐 3행 = 대기 실재 1 + 진행/ 1 + 완성/ 1 → 반송(대기로 되돌림)된 카드는 다시 센다
reset
d1="$(card d1.md)"; d2="$(card d2.md)"
q add --card "$d1" --from m#1 >/dev/null; q add --card "$d2" --from m#1 >/dev/null
mv "$IDX/대기/d2.md" "$IDX/진행/d2.md"; mv "$IDX/진행/d2.md" "$IDX/대기/d2.md"   # 반송(r655 꼴) — 큐 갱신 전에 되돌아왔다
o="$(q add --card "$(card d3.md)" --from m#1)"
{ [[ "$o" == "QUEUED alpha 순번=3" ]] && [ "$(nq)" = 3 ]; } && ok "ⓓ 반송된 카드(진행→대기)는 다시 대기 행으로 셈: $o" || bad "ⓓ $o q=$(cat "$Q")"

# ⓒ 어디에도 없는 카드 = 확인 필요 유지 · 순번 밖 · stuck 출력 1줄
reset
q add --card "$(card e1.md)" --from m#1 >/dev/null; e2="$(card e2.md)"; q add --card "$e2" --from m#1 >/dev/null
rm -f "$e2"
o="$(q add --card "$(card e3.md)" --from m#1)"; s="$(q stuck)"
{ [[ "$o" == "QUEUED alpha 순번=2" ]] && [ "$(nq)" = 3 ] && has "$e2" && [ "$s" = "$e2" ]; } \
  && ok "ⓒ 어디에도 없는 카드 = 확인 필요 유지(행 3·순번 2)·stuck 1줄" || bad "ⓒ $o q=$(cat "$Q") stuck=$s"

# ⓔ 팀 폴더 꼴 경로 design/teams/<팀>/indices/{대기,진행} 도 같은 판정
R2="$T/root2"; I2="$R2/design/teams/alpha/indices"; mkdir -p "$R2/.fable-team/state" "$I2/대기" "$I2/진행" "$I2/완성"
cp "$ROOT/.fable-team/seats-alpha.json" "$R2/.fable-team/seats-alpha.json"
q2() { python3 "$BIN/ft_spawn_queue.py" "$@" --root "$R2" --prefix byz-alpha-nano- 2>&1; }
: > "$I2/대기/f1.md"; : > "$I2/대기/f2.md"
q2 add --card "$I2/대기/f1.md" --from m#1 >/dev/null; q2 add --card "$I2/대기/f2.md" --from m#1 >/dev/null
mv "$I2/대기/f2.md" "$I2/진행/f2.md"; : > "$I2/대기/f3.md"
o="$(q2 add --card "$I2/대기/f3.md" --from m#1)"
Q2="$R2/.fable-team/state/spawn-queue-alpha.tsv"
{ [[ "$o" == "QUEUED alpha 순번=2" ]] && [ "$(grep -c . "$Q2")" = 2 ] && [ -z "$(q2 stuck)" ]; } && ok "ⓔ 팀 폴더 꼴 경로도 진행/ 실재 = 완료: $o" || bad "ⓔ $o $(cat "$Q2")"

# ⓕ 알림 맨 앞 카드 = 대기/ 실재 행 중 첫째(확인 필요 행은 알림 대상 아님) · teamset «큐 확인 필요 N» = 확인 필요만
reset
g1="$(card g1.md)"; q add --card "$g1" --from m#1 >/dev/null; rm -f "$g1"
g2="$(card g2.md)"; q add --card "$g2" --from m#1 >/dev/null
FM="$T/fake-mbox.sh"; printf '#!/bin/sh\necho "$*" >> %s/mbox.log\n' "$T" > "$FM"
o="$(q notify --mbox "$FM" --to byz-alpha-master-claude#1)"
{ [[ "$o" == "큐 알림 g2.md" ]] && grep -F 'send byz-alpha-master-claude#1' "$T/mbox.log" | grep -qF 'g2.md' && grep -F '대기 1' "$T/mbox.log" >/dev/null; } \
  && ok "ⓕ 알림 = 대기 첫째 g2.md(확인 필요 g1.md 아님) · 대기 1: $o" || bad "ⓕ $o / $(cat "$T/mbox.log" 2>/dev/null)"
stk="$(python3 -c "
import sys; sys.path.insert(0, '$BIN')
import ft_spawn_queue as sq
print(len(sq.stuck_cards('$ROOT', 'byz-alpha-nano-')))
" 2>&1)"
[ "$stk" = 1 ] && ok "ⓕ teamset «큐 확인 필요 N» = 확인 필요 1(대기 행 안 셈)" || bad "ⓕ stuck_cards=$stk"

# ── r957 누수 검사: 실 tmux 서버에 시험 세션(byz-alpha-·byz-v65-·ft-v65-temp-)이 남으면 FAIL ──
tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
