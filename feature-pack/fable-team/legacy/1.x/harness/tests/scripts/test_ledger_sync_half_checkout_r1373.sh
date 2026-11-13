#!/bin/bash
# test_ledger_sync_half_checkout_r1373.sh — r1373: 원장 사본 sync 의 checkout 이 상한에 중간에 죽어 «반쯤 바뀐 사본» 이 남아도 다음 회차가 스스로 마저 끝낸다
# S1 반쯤 checkout(추적 수정 2 · 카드 이동 = 삭제 1 + 미추적 새 파일 1 · 전부 새 판과 같은 내용) → «RESUME <옛10>..<새10> 경로 4» 1줄 · rc0 · HEAD = 새 판 · status 0줄
# S2 단계 분리: --fetch-only 가 fetch 실패면 rc4 · 작업 트리·HEAD 손댐 0 / 뉴스 sync_repo 가 fetch 단계(상한 FETCH_BUDGET_S)와 --advance 단계를 따로 부르고 fetch 상한이면 advance 0
# S3 추적 수정 1개가 새 판과 다름(손 쓰기) → RESUME 0 · rc3 ERROR(지금 문구) · 손 쓴 내용 보존
# S4 새 판에 없는 미추적(뉴스 html) → 판정 밖 · SYNC 정상 · 파일 보존
# S5 깨끗한 사본 + 새 커밋 1 → «SYNC <옛>..<새>» (회귀 0)
# 픽스처 = 임시 bare origin · 실 사본·실 원격 0 · 실제 kill 0 · sleep 0 · 반쯤 checkout = 작업 트리만 새 판 파일로 덮고 index·HEAD 는 옛 판
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../bin"
SYNC="$BIN/ft-ledger-repo-sync.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
run() { timeout 70 bash "$SYNC" "$@"; }

# 판 A: a·b·카드(대기) · 판 B: a·b 수정 + 카드 대기→완성 이동
g init -q --bare "$T/origin.git"
g clone -q "$T/origin.git" "$T/w" 2>/dev/null
mkdir -p "$T/w/cards/wait" "$T/w/cards/done"
echo a1 > "$T/w/a.md"; echo b1 > "$T/w/b.md"; echo card1 > "$T/w/cards/wait/x.md"
g -C "$T/w" add -A && g -C "$T/w" commit -qm A
A="$(git -C "$T/w" rev-parse HEAD)"
echo a2 > "$T/w/a.md"; echo b2 > "$T/w/b.md"
g -C "$T/w" mv cards/wait/x.md cards/done/x.md; echo card2 > "$T/w/cards/done/x.md"
g -C "$T/w" add -A && g -C "$T/w" commit -qm B
B="$(git -C "$T/w" rev-parse HEAD)"
g -C "$T/w" push -q origin HEAD:main

copy() {  # $1 = 사본 이름 → origin/main = B 까지 받은 detached A 사본
  g clone -q "$T/origin.git" "$T/$1" 2>/dev/null && git -C "$T/$1" checkout -q --detach "$A"
}
half() {  # 죽은 checkout 흔적: 작업 트리만 B 판 · index·HEAD = A
  local d="$T/$1"
  for p in a.md b.md cards/done/x.md; do mkdir -p "$d/$(dirname "$p")"; git -C "$d" show "$B:$p" > "$d/$p"; done
  rm -f "$d/cards/wait/x.md"
}
snap() { (cd "$T/$1" && git status --porcelain -uall && cat a.md b.md cards/done/x.md 2>/dev/null && git rev-parse HEAD) | shasum; }

# S1
copy s1; half s1
OUT="$(run "$T/s1")"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "RESUME ${A:0:10}..${B:0:10} 경로 4" ] && ok "S1 반쯤 checkout → $OUT" || bad "S1 rc=$RC out=$OUT"
[ "$(git -C "$T/s1" rev-parse HEAD)" = "$B" ] && [ -z "$(git -C "$T/s1" status --porcelain -uall)" ] && ok "S1 HEAD = 새 판 · status 0줄" || bad "S1 HEAD/status 남음"
copy s1b; half s1b
OUT="$(run --advance "$T/s1b")"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "RESUME ${A:0:10}..${B:0:10} 경로 4" ] && [ "$(git -C "$T/s1b" rev-parse HEAD)" = "$B" ] && ok "S1 --advance 단계도 RESUME" || bad "S1 --advance rc=$RC out=$OUT"

# S2 (sh) — fetch 단계만: fetch 실패 → rc4 · 작업 트리 손댐 0
copy s2; half s2
git -C "$T/s2" remote set-url origin "$T/no-such-origin.git"
BEFORE="$(snap s2)"
OUT="$(run --fetch-only "$T/s2")"; RC=$?
case "$OUT" in "ERROR ledger 사본 fetch 실패: "?*) F=1;; *) F=0;; esac
[ "$RC" = 4 ] && [ "$F" = 1 ] && [ "$(snap s2)" = "$BEFORE" ] && ok "S2 --fetch-only fetch 실패 → rc4 · 손댐 0" || bad "S2 sh rc=$RC out=$OUT"

# S2 (py) — sync_repo 가 두 단계로 부름 · fetch 상한 = FETCH_BUDGET_S · fetch 상한 초과면 advance 0
FT_ROOT="$T" FT_LEDGER_SYNC_STAMP="$T/stamp" BIN="$BIN" timeout 70 python3 - <<'PY'
import os, subprocess, sys
sys.path.insert(0, os.environ["BIN"])
import ft_news_ledger as m
calls = []
def fake(argv, timeout=None, **kw):
    calls.append((argv, timeout))
    if mode == "slow" and "--fetch-only" in argv:
        raise subprocess.TimeoutExpired(argv, timeout)
    return subprocess.CompletedProcess(argv, 0, "SYNC x..y\n", "")
m.subprocess.run = fake
def go(md):
    global mode
    mode = md; calls.clear()
    for k in ("FT_LEDGER_SYNCED", "FT_LEDGER_SYNC_ERROR"): os.environ.pop(k, None)
    if os.path.exists(os.environ["FT_LEDGER_SYNC_STAMP"]): os.remove(os.environ["FT_LEDGER_SYNC_STAMP"])  # 반올림 기록이 «2분 안» 건너뜀으로 새지 않게
    os.environ.update(FT_LEDGER_REPO="/nonexistent-copy", FT_LEDGER_SYNC_MIN="0")
    return m.sync_repo()
bad = 0
r = go("ok")
step = [("--fetch-only" in a, "--advance" in a, t) for a, t in calls]
if len(step) == 2 and step[0][0] and step[0][2] == m.FETCH_BUDGET_S and step[1][1] and step[1][2] and r == "":
    print("PASS S2 sync_repo = fetch 단계(상한 %.0f) + advance 단계(상한 %s)" % (m.FETCH_BUDGET_S, step[1][2]))
else:
    print("FAIL S2 두 단계 아님 calls=%s" % step); bad += 1
r = go("slow")
if len(calls) == 1 and "--fetch-only" in calls[0][0] and r:
    print("PASS S2 fetch 상한 초과 → advance 0 · 오류 줄 있음")
else:
    print("FAIL S2 fetch 상한 뒤 calls=%s r=%r" % ([a for a, _ in calls], r)); bad += 1
sys.exit(bad)
PY
fail=$((fail+$?))

# S3 — a.md 가 B 판과 다름(손 쓰기)
copy s3; half s3; echo "손댐" > "$T/s3/a.md"
OUT="$(run "$T/s3")"; RC=$?
case "$OUT" in "ERROR ledger 사본 미커밋 추적 변경 "*) F=1;; *) F=0;; esac
[ "$RC" = 3 ] && [ "$F" = 1 ] && [ "$(git -C "$T/s3" rev-parse HEAD)" = "$A" ] && [ "$(cat "$T/s3/a.md")" = "손댐" ] && ok "S3 손 쓰기 → rc3 · RESUME 0 · 내용 보존" || bad "S3 rc=$RC out=$OUT"

# S4 — 새 판에 없는 미추적(뉴스 html)
copy s4; echo news > "$T/s4/NEWS-1.html"
OUT="$(run "$T/s4")"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "SYNC ${A:0:10}..${B:0:10}" ] && [ -f "$T/s4/NEWS-1.html" ] && ok "S4 원래 미추적 → $OUT · 보존" || bad "S4 rc=$RC out=$OUT"

# S5 — 깨끗한 사본 · 새 커밋 1
copy s5
OUT="$(run "$T/s5")"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "SYNC ${A:0:10}..${B:0:10}" ] && [ -z "$(git -C "$T/s5" status --porcelain -uall)" ] && ok "S5 깨끗한 전진 → $OUT" || bad "S5 rc=$RC out=$OUT"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
