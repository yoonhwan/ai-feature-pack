#!/usr/bin/env bash
# test_nano_close_due_r1360.sh — r1360: ft-nano-close-due.sh(읽기 전용 «닫기 차례» 조회) + ft-tick.sh 루트 스냅샷 step(close-due.txt) 계약·반례 C1~C12.
#   닫기 차례 = 살아 있음 ∧ 완료 근거(카드 마지막 «세트:» == HEAD · A12 재개 · A14 리서치·미착수) ∧ 착지(ff ∨ squash 끝줄) ∧ 깨끗 ∧ IDLE.
#   임시 루트(TEAMS.md·명부·카드) + 좌석마다 임시 bare remote·clone + 가짜 tmux·ft-seat-status·git 래퍼(PATH 앞)만 쓴다 — 실 명부·tmux·gh·좌석 0 · 고정 sleep 0 · 자기 재호출 0.
#   시간 상한(C8)은 가짜 시계(FT_CLOSE_DUE_CLOCK_STEP) · 주입한 실패(C9)는 «판정 불가 1줄 · 목록 밖 · 반환값 3» 확인용(하드 룰 20).
#   변이 사본 = FT_CLOSE_DUE_UNDER_TEST=<사본 경로>(사본은 ft_team_lib.py 와 같은 폴더) · 기준판 = 도구가 없을 때(FT_CLOSE_DUE_UNDER_TEST=/nonexistent) FAIL.
#   변이(각각 FAIL 기대): 미커밋 검사 끔(C3) · IDLE 검사 끔(C4) · 명부 cwd 칸으로 바꿈(C1) · squash 끝줄을 «포함»으로(C2m) · 재개 검사 끔(C5a) · 근거 칸 끔(C6) · 순서 이어받기 끔(C8) · 반환값 0 고정(C9)
#   짝: bin == kit cmp0 · /bin/bash 3.2 -n.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
ulimit -u 2000 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="${FT_CLOSE_DUE_UNDER_TEST:-$BIN/ft-nano-close-due.sh}"
TICK="$BIN/ft-tick.sh"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
REALGIT="$(command -v git)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }

echo "== 짝 cmp · bash -n"
for f in ft-nano-close-due.sh ft-tick.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; done
bash -n "$BIN/ft-nano-close-due.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$BIN/ft-nano-close-due.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"
eq "$(grep -c 'close-due.txt' "$BIN/ft-nano-close-due.sh")" "0" "C11 도구 자신은 close-due.txt 를 쓰지 않는다(쓰는 곳 = 틱 1곳)"

# ── 가짜 도구 ────────────────────────────────────────────────────────────────────────────────────
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) cat "$FAKE_SESS";;
  display-message) s="${4#=}"; s="${s%:}"; grep -qxF "$s" "$FAKE_TMUXFAIL" 2>/dev/null && exit 1; cat "$FAKE_CWD_DIR/$s";;
  *) exit 9;;
esac
EOF
cat > "$FK/git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-C" ]; then case "\${2:-}" in *GITFAIL*) [ "\${3:-}" = status ] && { echo "fatal: injected" >&2; exit 7; };; esac; fi
exec "$REALGIT" "\$@"
EOF
cat > "$FK/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = turn ] && [ -f "$FAKE_SS_DIR/$2" ] && { cat "$FAKE_SS_DIR/$2"; exit 0; }
exit 1
EOF
chmod +x "$FK/tmux" "$FK/git" "$FK/ft-seat-status.sh"
# 변이 사본이 같은 폴더의 ft_team_lib.py 를 import 한다 — 기본 도구는 bin 의 것
export PATH="$FK:$PATH" FT_CLOSE_DUE_SEAT_STATUS="$FK/ft-seat-status.sh"
export FAKE_SESS="$T/sess" FAKE_TMUXFAIL="$T/tmuxfail" FAKE_CWD_DIR="$T/cwd" FAKE_SS_DIR="$T/ss"

# ── 픽스처 ─────────────────────────────────────────────────────────────────────────────────────────
ROOT=""; LAST_H=""
new_root() {   # <팀…> — 새 임시 루트(TEAMS.md · 명부 줄 모음 비움)
  ROOT="$T/root-$1-$RANDOM"; rm -rf "$T/rem" "$T/wt" "$T/wt2" "$T/cwd" "$T/ss"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design" "$T/rem" "$T/wt" "$T/wt2" "$T/cwd" "$T/ss"
  : > "$T/sess"; : > "$T/tmuxfail"; : > "$T/rows.tsv"
  { printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n'; local t; for t in "$@"; do printf '| %s | `design/teams/%s/` | byz-%s-master-claude | 현역 |\n' "$t" "$t" "$t"; done; } > "$ROOT/design/TEAMS.md"
  TEAMS=("$@")
}
cm() { git -C "$1" commit -q --allow-empty -m "$2" "${@:3}"; }
mk() {   # <좌석> <팀> <slug> <ff|squash|squashmid|none> — remote·clone·가지·착지 · LAST_H = 나노 HEAD
  local seat="$1" team="$2" slug="$3" land="$4" rem="$T/rem/$3.git" wt="$T/wt/$3" m0
  git init -q --bare -b main "$rem"; git clone -q "$rem" "$wt" 2>/dev/null
  git -C "$wt" checkout -q -b main; echo a > "$wt/a"; git -C "$wt" add a; cm "$wt" "M0"; git -C "$wt" push -q origin main 2>/dev/null; m0="$(git -C "$wt" rev-parse HEAD)"
  git -C "$wt" checkout -q -b "nano/$slug"; echo x > "$wt/x"; git -C "$wt" add x; cm "$wt" "work"; LAST_H="$(git -C "$wt" rev-parse HEAD)"
  case "$land" in
    ff) git -C "$wt" push -q origin "nano/$slug:main" 2>/dev/null;;
    squash|squashmid)
      git -C "$wt" checkout -q -b land-tmp main; echo y > "$wt/y"; git -C "$wt" add y
      if [ "$land" = squash ]; then cm "$wt" "[feature] t" -m "body" -m "PR #12 (head $LAST_H)"; else cm "$wt" "[feature] t" -m "PR #12 (head $LAST_H)" -m "다른 꼬리 줄"; fi
      git -C "$wt" push -q origin land-tmp:main 2>/dev/null; git -C "$wt" checkout -q "nano/$slug"; git -C "$wt" branch -q -D land-tmp;;
  esac
  git -C "$wt" update-ref refs/remotes/origin/main "$m0"   # 낡은 remote-tracking — 도구가 fetch 해야 착지가 보인다
  printf '%s\n' "$seat" >> "$T/sess"; printf '%s\n' "$wt" > "$T/cwd/$seat"; printf 'IDLE - - - jsonl\n' > "$T/ss/$seat"
  card "$team" "$slug" "- 세트: $LAST_H · 시험: bash x rc=0 · 이슈: 0"
  printf '%s\t%s\t%s\n' "$team" "$seat" "design/teams/$team/indices/진행/$slug.md" >> "$T/rows.tsv"
}
card() {   # <팀> <slug> <상태 줄…> — 카드 «## 상태» 절
  local team="$1" slug="$2"; shift 2; mkdir -p "$ROOT/design/teams/$team/indices/진행"
  { printf '# 인덱스: %s\n## 구현 범위\n- x\n## 상태\n- base_sha: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (spawn)\n' "$slug"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$ROOT/design/teams/$team/indices/진행/$slug.md"
}
fin() {   # 명부 JSON 쓰기 — 행마다 role=nano · cwd 칸은 일부러 «틀린 경로»(명부 cwd 칸에 기대지 않는다 · A13)
  python3 - "$ROOT" "$T/rows.tsv" "${TEAMS[@]}" <<'PY'
import json, sys
root, rows = sys.argv[1], sys.argv[2]
docs = {t: {"_master": "byz-%s-master-claude#1" % t, "_cards": "design/teams/%s/indices" % t} for t in sys.argv[3:]}
for ln in open(rows):
    t, s, idx = ln.rstrip("\n").split("\t")
    extra = {"_replaced_by": "x#9"} if s.endswith("rep#0") else {}
    docs[t][s] = {"role": "nano", "agent": "claude", "index": idx, "cwd": "/nonexistent/bogus", **extra}
for t, d in docs.items(): json.dump(d, open("%s/.fable-team/seats-%s.json" % (root, t), "w"), ensure_ascii=False)
PY
}
run() { OUT="$(FT_ROOT="$ROOT" "$TOOL" "$@" 2>&1)"; RC=$?; }
snap() {   # 바꾸는 것 0 확인용 지문 — 명부·refs/heads·워크트리 상태·tmux 파일(remote-tracking 제외)
  { cksum "$ROOT"/.fable-team/seats-*.json "$T/sess" "$T/cwd"/* "$T/ss"/* 2>/dev/null
    for w in "$T/wt"/* "$T/wt2"/*; do [ -d "$w" ] && { git -C "$w" for-each-ref refs/heads; git -C "$w" status --porcelain; git -C "$w" worktree list; }; done; } | cksum
}

# ══ 그룹 A — C1~C7 · C10 · C12 ══════════════════════════════════════════════════════════════════
new_root harness lecture
mk "byz-harness-nano-c1#0" harness c1 ff
mk "byz-harness-nano-c1w#0" harness c1wbase ff; H1W="$LAST_H"
git -C "$T/wt/c1wbase" worktree add -q "$T/wt2/c1w" -b nano/c1w "$H1W" 2>/dev/null; printf '%s\n' "$T/wt2/c1w" > "$T/cwd/byz-harness-nano-c1w#0"
mk "byz-harness-nano-c2#0" harness c2 squash
mk "byz-harness-nano-c2m#0" harness c2m squashmid
mk "byz-harness-nano-c3#0" harness c3 ff; echo dirty > "$T/wt/c3/untracked.txt"
mk "byz-harness-nano-c4#0" harness c4 ff; printf 'WORKING 2026-11-05T01:00:00 - no jsonl\n' > "$T/ss/byz-harness-nano-c4#0"
mk "byz-harness-nano-c5a#0" harness c5a ff; card harness c5a "- 세트: $LAST_H · 시험: x rc=0 · 이슈: 0" "- 2026-11-05T02:00 재개(--reopen) · 좌석 byz-harness-nano-c5a#0"
mk "byz-harness-nano-c5b#0" harness c5b ff; card harness c5b "- 세트: $LAST_H · 시험: x rc=0 · 이슈: 0" "- 2026-11-05T02:00 재개(--reopen) · 좌석 byz-harness-nano-c5b#0" "- 세트: $LAST_H · 시험: x rc=0 · 이슈: 0"
mk "byz-harness-nano-c5c#0" harness c5c ff; cm "$T/wt/c5c" "재개 뒤 새 커밋"   # 카드 세트 ≠ HEAD(재개 뒤 새 작업 · 증거 갱신 전)
mk "byz-harness-nano-c5d#0" harness c5d ff; card harness c5d "- 세트: $LAST_H · 시험: x rc=0 · 이슈: 0" "- 재개(--reopen)" "- 세트: $LAST_H · 시험: x rc=0 · 이슈: 0"; printf 'WORKING - - - jsonl\n' > "$T/ss/byz-harness-nano-c5d#0"
mk "byz-harness-nano-x-research#0" harness c6a ff; card harness c6a "- 2026-11-05 조사 결과만 · 코드 0"   # 리서치 좌석
mk "byz-harness-nano-c6b#0" harness c6b none; git -C "$T/wt/c6b" checkout -q main; card harness c6b "- base_sha 만"   # 자기 커밋 0 리서치/미착수(HEAD = main 조상)
mk "byz-harness-nano-c10#0" harness c10 ff; git -C "$T/wt/c10" checkout -q --detach
mk "byz-harness-nano-rep#0" harness rep ff
mk "byz-harness-nano-c0nolive#0" harness c0 ff; grep -vxF "byz-harness-nano-c0nolive#0" "$T/sess" > "$T/sess.n"; mv "$T/sess.n" "$T/sess"
mk "byz-lecture-nano-l1#0" lecture l1 ff
fin
SNAP0="$(snap)"
run --all --why; OUTA="$OUT"; RCA=$RC
eq "$RCA" "0" "C9 판정 불가 0 이면 반환값 0"
has "$OUTA" "닫기 차례 byz-harness-nano-c1#0 팀=harness 가지=nano/c1 landed=ff" "C1(A13) 명부 cwd 가 틀려도 pane cwd 로 → 닫기 차례(ff)"
has "$OUTA" "닫기 차례 byz-harness-nano-c1w#0 팀=harness 가지=nano/c1w landed=ff" "C1 git worktree(.git 파일) 도 pane cwd 로 → 닫기 차례"
has "$OUTA" "닫기 차례 byz-harness-nano-c2#0 팀=harness 가지=nano/c2 landed=squash" "C2 squash 끝줄 → landed=squash"
has "$OUTA" "--landed-pr 12 --result <산출> --recv <seq>" "C2 줄 꼬리 = nano-close 호출 꼴(PR 번호)"
has "$OUTA" "제외 byz-harness-nano-c2m#0 main 에 산출 없음" "C2m 본문 가운데 줄(끝줄 아님) → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-c3#0 미커밋 1줄" "C3 미커밋 → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-c4#0 상태 WORKING" "C4 busy → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-c5a#0 재개 뒤 세트 줄 없음" "C5(A12) 재개 뒤 완료 근거 없음 → 목록 밖"
has "$OUTA" "닫기 차례 byz-harness-nano-c5b#0" "C5(A12) 재개 뒤 새 세트 줄 = 근거 → 닫기 차례"
has "$OUTA" "제외 byz-harness-nano-c5c#0 세트" "C5(A12) 착지 tip 위 새 커밋 → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-c5d#0 상태 WORKING" "C5(A12) 재개·커밋 0 이지만 busy → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-x-research#0 리서치 좌석" "C6(A14) 리서치 좌석 → 목록 밖"
has "$OUTA" "제외 byz-harness-nano-c6b#0 세트 줄 없음" "C6(A14) 자기 커밋 0 가지(HEAD = main 조상)·깨끗·IDLE → 목록 밖"
has "$OUTA" "닫기 차례 byz-harness-nano-c10#0 팀=harness 가지=detached" "C10 detached → 지금 HEAD 로 다시 계산"
hasnt "$OUTA" "닫기 차례 byz-harness-nano-rep#0" "옛 행(_replaced_by) 뺌"
hasnt "$OUTA" "c0nolive" "tmux 세션 없는 좌석 뺌"
has "$OUTA" "닫기 차례 byz-lecture-nano-l1#0 팀=lecture" "C7 틱 없는 팀 포함 전 팀(--all)"
run --all --summary; eq "$OUT" "닫기 차례 harness=5 lecture=1" "C7 --summary 1줄(팀별 수)"
run --team lecture; has "$OUT" "byz-lecture-nano-l1#0" "--team lecture"; hasnt "$OUT" "byz-harness-nano-c1#0" "--team 은 그 팀만"
eq "$(snap)" "$SNAP0" "C12 바꾸는 것 0 — 명부·refs/heads·워크트리·tmux 그대로(2회 실행 뒤)"
eq "$(ls "$ROOT/.fable-team/state" | tr '\n' ' ')" "" "C12 상태 폴더에 새 파일 0(시간 상한에 안 걸리면 순서 파일을 만들지 않는다)"

# ══ 그룹 B — C8(A17) 시간 상한·순서 이어받기 ═════════════════════════════════════════════════════
new_root budg
for n in 0 1 2 3 4; do mk "byz-budg-nano-b$n#0" budg b$n ff; done
fin
FT_CLOSE_DUE_BUDGET=2 FT_CLOSE_DUE_CLOCK_STEP=1 run --all
eq "$RC" "3" "C8 시간 상한 → 반환값 3"
eq "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" "2" "C8 상한 안 좌석 2개 조회"
eq "$(printf '%s\n' "$OUT" | grep -c '^판정 불가 .* 시간 상한')" "3" "C8 남은 좌석 3개 «판정 불가 시간 상한» 1줄씩"
eq "$(cat "$ROOT/.fable-team/state/close-due-cursor.txt" 2>/dev/null)" "byz-budg-nano-b2#0" "C8 순서 파일 = 첫 미조회 좌석"
FT_CLOSE_DUE_BUDGET=2 FT_CLOSE_DUE_CLOCK_STEP=1 run --all --summary; eq "$OUT" "닫기 차례 budg=2+판정불가3" "C8/A23 요약에 팀별 판정 불가 수(2회차도 상한 · 이어받은 b2·b3 만 조회)"
run --all
eq "$(printf '%s\n' "$OUT" | head -1 | cut -d' ' -f3)" "byz-budg-nano-b4#0" "C8(A17) 3회차 = 지난 회차(b2·b3 조회) 미조회 b4 부터 실제 조회"
eq "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" "5" "C8 3회차 5좌석 전부 조회"
eq "$RC" "0" "C8 3회차 반환값 0"
eq "$(tr -d '\n' < "$ROOT/.fable-team/state/close-due-cursor.txt")" "" "C8 다 돌았으면 순서 파일을 비운다"

# ══ 그룹 C — C9(A23) 주입 실패 ═════════════════════════════════════════════════════════════════════
new_root fail
mk "byz-fail-nano-ftmux#0" fail ftmux ff; printf '%s\n' "byz-fail-nano-ftmux#0" > "$T/tmuxfail"
mk "byz-fail-nano-fgit#0" fail f-GITFAIL ff
mk "byz-fail-nano-ffetch#0" fail ffetch ff; git -C "$T/wt/ffetch" remote set-url origin "$T/rem/없는리포.git"
mk "byz-fail-nano-fss#0" fail fss ff; rm -f "$T/ss/byz-fail-nano-fss#0"
mk "byz-fail-nano-fok#0" fail fok ff
fin
run --all
eq "$RC" "3" "C9 판정 불가 있으면 반환값 3"
has "$OUT" "판정 불가 byz-fail-nano-ftmux#0 tmux display-message rc=1" "C9 tmux 실패 → 판정 불가 1줄"
has "$OUT" "판정 불가 byz-fail-nano-fgit#0 git status rc=7" "C9 git 실패 → 판정 불가 1줄"
has "$OUT" "판정 불가 byz-fail-nano-ffetch#0 git fetch origin main rc=128" "C9 fetch 실패 → 판정 불가 1줄"
has "$OUT" "판정 불가 byz-fail-nano-fss#0 ft-seat-status turn rc=1" "C9 seat-status 실패 → 판정 불가 1줄"
has "$OUT" "닫기 차례 byz-fail-nano-fok#0" "C9 한 좌석 실패가 다른 좌석을 막지 않는다"
eq "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" "1" "C9 실패 좌석은 목록 밖"
run --all --summary; eq "$OUT" "닫기 차례 fail=1+판정불가4" "C9/A23 --summary 에 팀별 판정 불가 수"; eq "$RC" "3" "C9 --summary 반환값 3"
run --team 없는팀; has "$OUT" "판정 불가 팀=없는팀 명단 밖" "명단 밖 팀 = 판정 불가"

# ══ 그룹 D — C11 틱 스냅샷(루트 틱 1곳 · 임시→mv) ═══════════════════════════════════════════════════
R3="$T/root-tick"; mkdir -p "$R3/.fable-team/comm" "$R3/.fable-team/state" "$R3/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | x | 현역 |\n' > "$R3/design/TEAMS.md"
printf '{"_version":1}\n' > "$R3/.fable-team/seats.json"; printf '{"_version":1}\n' > "$R3/.fable-team/seats-alpha.json"
printf '#!/bin/sh\nexit 0\n' > "$R3/.fable-team/comm/mbox.sh"; printf '#!/bin/sh\nexit 0\n' > "$T/tm.sh"
CALLS="$T/due-calls"; : > "$CALLS"; MODE="$T/due-mode"; printf 'ok\n' > "$MODE"
cat > "$T/fake-due.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$FT_ROOT" "$FT_CLOSE_DUE_BUDGET $*" >> "$FAKE_DUE_CALLS"
case "$(cat "$FAKE_DUE_MODE")" in ok) echo "닫기 차례 alpha=2"; exit 0;; unk) echo "닫기 차례 alpha=0+판정불가1"; exit 3;; *) echo "boom" >&2; exit 9;; esac
EOF
chmod +x "$T/fake-due.sh"
export FAKE_DUE_CALLS="$CALLS" FAKE_DUE_MODE="$MODE"
tick() { env FT_ROOT="$R3" FT_TICK_SEATS="${SEATSF:-$R3/.fable-team/seats.json}" FT_TICK_PIDFILE="$R3/tick.pid" FT_TICK_STAMP_PREFIX="$R3/stamp-" FT_TICK_STATE_DIR="$R3/.fable-team/state/tick" \
  FT_TICK_MBOX="$R3/.fable-team/comm/mbox.sh" FT_MBOX_DIR="$R3/.fable-team/comm" FT_TICK_TEAMMAIN_BIN="$T/tm.sh" FT_TICK_CLOSE_DUE_BIN="$T/fake-due.sh" \
  FT_TICK_WATCH_SAMPLE=0 FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 \
  FT_TICK_API_OUTAGE=0 FT_TICK_ACCT_PAUSE=0 FT_MODEL_SWAP=0 FT_TICK_WT_SWEEP=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 \
  FT_TICK_CARD_ASSIGN=0 FT_TICK_LAUNCHD=0 FT_TICK_UNPUSHED=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_ACCT=0 FT_TICK_ACCT_POST=0 FT_TICK_ACCT_NOTIFY=0 "$@" \
  bash "$TICK" --once ${DRYARG:-} > "$T/tick.out" 2>&1; }
F="$R3/.fable-team/state/close-due.txt"
DRYARG=--dry-run tick FT_TICK_CLOSE_DUE_GAP=300; has "$(cat "$T/tick.out")" "DRY kind=close-due" "C11 --dry-run = DRY 1줄"; [ ! -f "$F" ] && ok "C11 dry-run 은 파일 0" || bad "C11 dry-run 이 파일을 썼다"
tick FT_TICK_CLOSE_DUE_GAP=300; eq "$(cat "$F" 2>/dev/null)" "닫기 차례 alpha=2" "C11 루트 틱이 요약 1줄을 close-due.txt 에"
eq "$(cat "$CALLS")" "$R3|40 --all --summary" "C11 도구 호출 = 루트 · 예산 40 · --all --summary"
eq "$(ls "$R3/.fable-team/state" | grep -c 'close-due.txt.tmp')" "0" "C11 임시 파일 잔존 0(임시→mv)"
tick FT_TICK_CLOSE_DUE_GAP=300; eq "$(grep -c . "$CALLS")" "1" "C11 갭 안 두 번째 바퀴 = 조회 0"
printf 'unk\n' > "$MODE"; tick FT_TICK_CLOSE_DUE_GAP=0; eq "$(cat "$F")" "닫기 차례 alpha=0+판정불가1" "C11 도구 rc 3 = 그 줄(판정 불가 수 보존)"
printf 'boom\n' > "$MODE"; tick FT_TICK_CLOSE_DUE_GAP=0; eq "$(cat "$F")" "닫기 차례 판정 불가 rc=9" "C11 도구 실패 = «판정 불가 rc=9»(옛 줄을 남기지 않는다)"
: > "$CALLS"; rm -f "$F"; SEATSF="$R3/.fable-team/seats-alpha.json" tick FT_TICK_CLOSE_DUE_GAP=0; eq "$(grep -c . "$CALLS")" "0" "C11 팀 틱(seats-<팀>.json)은 건너뜀"; [ ! -f "$F" ] && ok "C11 팀 틱은 파일 0" || bad "C11 팀 틱이 파일을 썼다"
SEATSF="" tick FT_TICK_CLOSE_DUE_GAP=0 FT_TICK_CLOSE_DUE=0; eq "$(grep -c . "$CALLS")" "0" "C11 FT_TICK_CLOSE_DUE=0 으로 끈다"

echo "== 결과: FAIL=$fail"
exit $(( fail > 0 ? 1 : 0 ))
