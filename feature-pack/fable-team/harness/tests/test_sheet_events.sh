#!/usr/bin/env bash
# test_sheet_events.sh — ft-sheet-events.sh(사건 원장 훅 · PLAN-status-sheet §3·§3-1) + 훅 5곳 연결 시험. 빨강 먼저(구현 전 rc≠0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../fixtures/sheet/sheet_env.sh"
SE="$BIN/ft-sheet-events.sh"
rows() { [ -f "$FB/state/sheet-events.jsonl" ] && wc -l < "$FB/state/sheet-events.jsonl" | tr -d ' ' || echo 0; }
pdir() { ls "$FB/state/sheet-events.pending" 2>/dev/null | wc -l | tr -d ' '; }
jsonof() { python3 -c 'import json,sys;print(json.dumps({"ev":sys.argv[1],"team":"harness","id":sys.argv[2],"seat":"s#0","ref":sys.argv[3],"by":"test"}))' "$@"; }
promote() { python3 - "$FB" <<'PY'
import os, sys
d = os.path.join(sys.argv[1], "state", "sheet-events.pending")
for f in os.listdir(d):
    if f.endswith(".prepared"):
        os.rename(os.path.join(d, f), os.path.join(d, f[:-9] + ".committed"))
PY
}

# 훅 5곳 × 사건 한 종류씩: 이름|키 만드는 인자|ev|id|ref
CASES=("spawn|spawn job-a h-nano-a#0|spawn|job-a|design/harness/indices/진행/job-a.md"
       "nano-close|nano-close h-nano-a#0 0123456789abcdef0123456789abcdef01234567|nano-close|h-nano-a|세트: 0123"
       "gh-close|issue-close 77|issue-close|#77|completed"
       "land|land-candidate feat1 aaaabbbbccccdddd|land-candidate|feat1|T=abc"
       "mbox|stop-ready h-master#1 0123456789abcdef|stop-ready|h-master|seq 1")
for c in "${CASES[@]}"; do
  IFS='|' read -r NAME KARGS EV ID REF <<<"$c"
  # 행 a — prepared → 작업 성공 → committed → append 실패 → 재실행 = 작업 1회 + 행 1
  new_root; K="$(bash "$SE" key $KARGS)"; [ -n "$K" ] && ok "$NAME key 생성: $K" || bad "$NAME key"
  W=0; bash "$SE" prepare "$K" "$(jsonof "$EV" "$ID" "$REF")" && W=$((W+1))
  mkdir -p "$FB/state"; : > "$FB/state/sheet-events.jsonl"; chmod a-w "$FB/state/sheet-events.jsonl"
  ERR="$(bash "$SE" commit "$K" 2>&1 >/dev/null)"; rc=$?
  eq "$NAME a: append 실패여도 작업 rc 그대로 0" "$rc" 0; has "$NAME a: SHEET-EVENT-PENDING" "$ERR" "SHEET-EVENT-PENDING"
  chmod u+w "$FB/state/sheet-events.jsonl"; bash "$SE" reconcile >/dev/null
  eq "$NAME a: 재실행 뒤 작업 1회" "$W" 1; eq "$NAME a: 행 1" "$(rows)" 1; eq "$NAME a: pending 폴더 0" "$(pdir)" 0
  # 행 b — prepared 실패 → 작업 0 · rc≠0 · 행 0
  new_root; K="$(bash "$SE" key $KARGS)"; W=0; mkdir -p "$FB/state/sheet-events.pending"; chmod a-w "$FB/state/sheet-events.pending"
  bash "$SE" prepare "$K" "$(jsonof "$EV" "$ID" "$REF")" 2>/dev/null && W=1
  eq "$NAME b: prepare 실패 → 작업 0" "$W" 0; eq "$NAME b: 행 0" "$(rows)" 0; chmod u+w "$FB/state/sheet-events.pending"
  # 행 c — prepared → (작업 중) 시트 렌더 → 작업 실패 → abort: 행 0 · 확인 중 1 → 0
  new_root; K="$(bash "$SE" key $KARGS)"; bash "$SE" prepare "$K" "$(jsonof "$EV" "$ID" "$REF")"
  has "$NAME c: 작업 중 시트 머리 확인 중 1" "$(sheet_txt)" "확인 중 1"; eq "$NAME c: 작업 중 행 0" "$(rows)" 0
  bash "$SE" abort "$K"; eq "$NAME c: 실패 뒤 행 0" "$(rows)" 0; has "$NAME c: 확인 중 0" "$(sheet_txt)" "확인 중 0"
  # 행 d — prepared → 작업 중 collect → 성공 → committed → 다음 collect → 행 1
  new_root; K="$(bash "$SE" key $KARGS)"; bash "$SE" prepare "$K" "$(jsonof "$EV" "$ID" "$REF")"
  board collect >/dev/null; eq "$NAME d: 작업 중 collect 가 prepared 를 안 올림" "$(rows)" 0
  promote; board collect >/dev/null; eq "$NAME d: committed 뒤 collect → 행 1" "$(rows)" 1; eq "$NAME d: pending 폴더 0" "$(pdir)" 0
  # 행 e — prepared 잔존(도구 죽음) → reconcile --confirm: 성공 행 1 / 실패 행 0·확인 중 유지
  new_root; K="$(bash "$SE" key $KARGS)"; bash "$SE" prepare "$K" "$(jsonof "$EV" "$ID" "$REF")"
  FT_SHEET_CONFIRM_CMD=false bash "$SE" reconcile --confirm >/dev/null; eq "$NAME e: 확인 실패 → 행 0" "$(rows)" 0; has "$NAME e: 확인 중 유지" "$(sheet_txt)" "확인 중 1"
  FT_SHEET_CONFIRM_CMD=true bash "$SE" reconcile --confirm >/dev/null; eq "$NAME e: 확인 성공 → 행 1" "$(rows)" 1; eq "$NAME e: pending 폴더 0" "$(pdir)" 0
done

# dup 0 — 같은 키 두 번 commit = 행 1 · stdout dup
new_root; K="$(bash "$SE" key issue-close 5)"
for i in 1 2; do bash "$SE" prepare "$K" "$(jsonof issue-close '#5' completed)"; OUT="$(bash "$SE" commit "$K")"; done
eq "dup: 행 1" "$(rows)" 1; has "dup: 두 번째 stdout" "$OUT" "sheet-event: dup $K"

# 훅 연결(실제 도구) — gh-as-tank: close(not-planned 은 게이트 면제)·label 성공 → 행 · gh 실패 → 행 0 · 이미 닫힘 재실행 = 상태 확인
new_root; mkdir "$T/ghbin"; cat > "$T/ghbin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "api user") echo byz-tank;;
  "issue view") if [[ "$*" == *--jq* ]]; then echo "${STUB_STATE:-OPEN}"; else echo "{\"state\":\"${STUB_STATE:-OPEN}\"}"; fi;;
  "issue close"|"issue edit") [ "${STUB_FAIL:-0}" = 1 ] && { echo boom >&2; exit 1; }; echo "https://github.com/o/r/issues/${3:-0}";;
esac
exit 0
GH
chmod +x "$T/ghbin/gh"; export STUB_LOG="$T/gh.log" PATH="$T/ghbin:$PATH" FT_ISSUE_BOT_TOKEN=tok; : > "$STUB_LOG"
TANK="$BIN/ft-gh-as-tank.sh"
STUB_FAIL=1 bash "$TANK" close 88 --reason not-planned --apply >/dev/null 2>&1; rc=$?; eq "gh 실패 → rc≠0" "$([ $rc -ne 0 ] && echo y)" y; eq "gh 실패 → 행 0" "$(rows)" 0; eq "gh 실패 → pending 0" "$(pdir)" 0
bash "$TANK" close 88 --reason not-planned --apply >/dev/null 2>&1; eq "close 성공 → 행 1" "$(rows)" 1; has "close 행 키" "$(cat "$FB/state/sheet-events.jsonl")" '"key": "issue-close:#88"'
has "F3 생산자 ev == issue-close(confirm 분기 이름표와 같다)" "$(cat "$FB/state/sheet-events.jsonl")" '"ev": "issue-close"'
bash "$TANK" label 88 --add approved --apply >/dev/null 2>&1; eq "label 성공 → 행 2" "$(rows)" 2
: > "$STUB_LOG"; STUB_STATE=CLOSED bash "$TANK" close 88 --reason not-planned --apply >/dev/null 2>&1
lacks "이미 닫힘 재실행 = close 재수행 0" "$(cat "$STUB_LOG")" "issue close"; eq "재실행 = dup(행 2 그대로)" "$(rows)" 2

# 훅 연결 — mbox: 머리 3종만 1행(본문은 안 읽음) · 일반 쪽지 0행
new_root; export FT_MBOX_DIR="$FT_ROOT/.fable-team/comm"; MB="$BIN/../harness-install/fable-team/bin/ft-mbox.sh"
bash "$MB" send p-master#1 h-master#1 "[정지 레디] 끝 ZZ-body-9" >/dev/null 2>&1; bash "$MB" send p-master#1 h-master#1 "[완료·휴식] 끝" >/dev/null 2>&1
bash "$MB" send p-master#1 h-master#1 "그냥 쪽지" >/dev/null 2>&1
eq "mbox: 머리 3종만 → 행 2" "$(rows)" 2; lacks "mbox: 본문 안 읽음" "$(cat "$FB/state/sheet-events.jsonl")" "ZZ-body-9"
has "mbox: ev done" "$(cat "$FB/state/sheet-events.jsonl")" '"ev": "done"'; unset FT_MBOX_DIR

# ── fix2 F1 — commit 의 rename 실패 → 생산자 EXIT trap 의 abort 가 prepared 를 지우지 않는다(commit-pending) → 복구
new_root; K="$(bash "$SE" key issue-close 31)"; bash "$SE" prepare "$K" "$(jsonof issue-close '#31' completed)"
mkdir -p "$FB/state/sheet-events.pending/$K.committed"   # rename 대상이 디렉터리 → rename 실패
ERR="$(bash "$SE" commit "$K" 2>&1 >/dev/null)"; rc=$?; eq "F1 rename 실패여도 commit rc 0" "$rc" 0; has "F1 stderr SHEET-EVENT-PENDING" "$ERR" "SHEET-EVENT-PENDING"
ERR="$(bash "$SE" abort "$K" 2>&1 >/dev/null)"; has "F1 abort 가 SHEET-EVENT-KEPT" "$ERR" "SHEET-EVENT-KEPT"
[ -f "$FB/state/sheet-events.pending/$K.prepared" ] && ok "F1 abort 뒤에도 prepared 잔존" || bad "F1 prepared 사라짐"
rmdir "$FB/state/sheet-events.pending/$K.committed"
FT_SHEET_CONFIRM_CMD=true bash "$SE" reconcile --confirm >/dev/null; eq "F1 reconcile --confirm → 원장 1행" "$(rows)" 1; eq "F1 pending 폴더 0" "$(pdir)" 0
# 대조: commit 시도 «전» 의 일반 abort 는 그대로 prepared 삭제
new_root; K="$(bash "$SE" key issue-close 32)"; bash "$SE" prepare "$K" "$(jsonof issue-close '#32' completed)"; bash "$SE" abort "$K"; eq "F1 대조: 일반 abort 는 삭제" "$(pdir)" 0

# ── fix2 F2 — commit 과 reconcile 동시 append → 같은 key 1행 (has_key 를 느리게 만든 뒤 두 프로세스 경쟁) · 변이(잠금 제거) → 2행
RACE_PY="$T/race.py"; cat > "$RACE_PY" <<'RPY'
import multiprocessing as mp, os, sys, time
sys.path.insert(0, sys.argv[1]); import ft_sheet_events as E
from pathlib import Path
root, key, orig = Path(os.environ["FT_SHEET_ROOT"]), sys.argv[2], E.has_key
def slow(r, k):
    v = orig(r, k); time.sleep(0.4); return v   # 확인→쓰기 사이를 넓힌다
E.has_key = slow
ctx = mp.get_context("fork")  # macOS 기본 spawn 은 monkeypatch 를 잃는다
a = ctx.Process(target=E.commit, args=(root, key)); b = ctx.Process(target=E.reconcile, args=(root,))
a.start(); b.start(); a.join(); b.join()
RPY
race() { # race <bindir> — (호출 전 new_root 필수: $(…) 서브셸 안의 new_root 는 NROOT 증가가 부모에 안 돌아온다) .committed 1개를 commit/reconcile 로 동시에 append → 그 key 행 수
  local k; k="$(bash "$1/ft-sheet-events.sh" key issue-close 41)"
  bash "$1/ft-sheet-events.sh" prepare "$k" "$(jsonof issue-close '#41' completed)"
  mv "$FB/state/sheet-events.pending/$k.prepared" "$FB/state/sheet-events.pending/$k.committed"
  FT_SHEET_ROOT="$FT_ROOT" python3 "$RACE_PY" "$1" "$k" >/dev/null 2>&1
  grep -c '"key": "issue-close:#41"' "$FB/state/sheet-events.jsonl" 2>/dev/null || echo 0
}
new_root; eq "F2 동시 commit+reconcile → 그 key 1행" "$(race "$BIN")" 1
MUT="$T/mut-events"; mkdir -p "$MUT"; cp "$BIN"/ft*.py "$BIN"/ft-sheet-events.sh "$MUT/"; /usr/bin/sed -i '' 's/fcntl.flock(\(.*\), fcntl.LOCK_EX)/pass/' "$MUT/ft_sheet_events.py"
new_root; eq "F2 변이(잠금 제거) → 2행(시험이 잠금을 잡는다)" "$(race "$MUT")" 2

# ── fix2 F3 — 미등록 ev 는 key 단계에서 REJECT rc 2 · confirm 은 issue-close(gh 스텁 CLOSED) 승격
new_root; bash "$SE" key foo a b >/dev/null 2>"$T/k.err"; rc=$?; eq "F3 key 미등록 ev → rc 2" "$rc" 2; has "F3 REJECT unknown ev" "$(cat "$T/k.err")" "REJECT unknown ev"
K="$(bash "$SE" key issue-close 5)"; bash "$SE" prepare "$K" "$(jsonof issue-close '#5' completed)"
STUB_STATE=CLOSED bash "$SE" reconcile --confirm >/dev/null 2>&1; eq "F3 confirm(gh CLOSED) 승격 → 행 1" "$(rows)" 1

# ── fix2 F6 — 라이브 진입점 = 정본 tools/comm-canonical/mbox.sh : 머리 3종만 훅 · 헬퍼 부재 시 send rc 0 + stderr 1줄
CANON="$HERE/../../tools/comm-canonical"
canon_env() { # canon_env <헬퍼 설치 여부 1|0>
  new_root; CE="$T/canon$NROOT"; mkdir -p "$CE/comm" "$CE/bin" "$CE/seats"; cp "$CANON"/mbox*.py "$CANON"/mbox*.sh "$CE/comm/"; git -C "$CE" init -q
  echo '{}' > "$CE/seats/seats.json"; echo '{}' > "$CE/seats/seats-planner.json"
  [ "$1" = 1 ] && cp "$BIN"/ft-sheet-events.sh "$BIN"/ft_sheet_events.py "$BIN"/ft_sheet_confirm.py "$BIN"/ft_sheet_key.py "$BIN"/ft_board_env.py "$BIN"/ft_board_mail.py "$CE/bin/"
  mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
}
csend() { (cd "$CE" && env -u FT_ROOT PATH="$T/stub:$PATH" FT_SHEET_ROOT="$FT_ROOT" FT_SEATS_JSON="$CE/seats/seats.json" FT_MBOX_DIR="$CE/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 bash "$CE/comm/mbox.sh" send "$1" "me#1" "$2" 2>&1); }
canon_env 1
csend x#1 "[완료·휴식] 끝 ZZ-canon-9" >/dev/null; eq "F6 정본 [완료·휴식] → 원장 1행" "$(rows)" 1; lacks "F6 본문 안 읽음" "$(cat "$FB/state/sheet-events.jsonl" 2>/dev/null)" "ZZ-canon-9"
csend x#1 "[부팅 보고] 세션=a" >/dev/null; eq "F6 정본 [부팅 보고] → 행 그대로 1" "$(rows)" 1; eq "F6 pending 0" "$(pdir)" 0
canon_env 0; OUT="$(csend x#1 "[완료] 끝")"; rc=$?; eq "F6 헬퍼 부재 → send rc 0" "$rc" 0; has "F6 헬퍼 부재 stderr 1줄" "$OUT" "ft-sheet-events.sh"; eq "F6 헬퍼 부재 → 행 0" "$(rows)" 0

# 훅 연결 — ft-land.sh: 후보 확정 1행(push 경로 없음 → 이름은 land-candidate)
new_root; G="$T/landrepo"; git init -q "$G" && git -C "$G" commit -q --allow-empty -m a && git -C "$G" branch -M main && git clone -q "$G" "$T/landclone" && git -C "$T/landclone" commit -q --allow-empty -m b
bash "$BIN/ft-land.sh" --feat HEAD --repo "$T/landclone" >/dev/null 2>&1; eq "land: 후보 확정 → 행 1" "$(rows)" 1; has "land: ev" "$(cat "$FB/state/sheet-events.jsonl")" '"ev": "land-candidate"'

# 훅 연결 — spawn·nano-close(통째 실행 불가: tmux·tmuxc 필요) = 정적 확인: 호출 순서 prepare < 작업 < commit, 실패 경로 abort
for f in ft-nano-spawn.sh ft-nano-close.sh; do
  bash -n "$BIN/$f" && ok "$f bash -n" || bad "$f bash -n"
  P="$(grep -n 'ft-sheet-events.sh" prepare' "$BIN/$f" | head -1 | cut -d: -f1)"; C="$(grep -n 'ft-sheet-events.sh" commit' "$BIN/$f" | tail -1 | cut -d: -f1)"
  [ -n "$P" ] && [ -n "$C" ] && [ "$P" -lt "$C" ] && ok "$f prepare($P) < commit($C)" || bad "$f 훅 순서"
  grep -q 'ft-sheet-events.sh" abort' "$BIN/$f" && ok "$f abort 경로" || bad "$f abort 없음"
done
exit $((fail>0))
