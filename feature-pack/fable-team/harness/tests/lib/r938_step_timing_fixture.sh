#!/usr/bin/env bash
# r938_step_timing_fixture.sh — r938 시험(test_nano_close_step_timing_r938_*.sh 4개)의 공통 준비(r1318 나눔).
#   왜 나눴나: r1316 이 시험 복사 목록의 import 짝을 고치자 r938 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22).
#   여기 담긴 것: 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(projects) + 임시 우편함 + 하위 스크립트 대역 + 도우미.
#   실제 리포·seats·tmux·원장은 건드리지 않는다. 단언 이름(ok/bad 문자열)은 나누기 전과 같은 꼴 — 변이 실행기가 이름으로 칸을 고른다.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/real_state_guard.sh"
guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행 — 재실행되면 아래 본문은 자식에서만 돈다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
# 카드 이름을 대괄호로 고정 — 변이 실행기(mutate_r938_step_timing.py)가 «빨강이어야 할 칸» 을 이름으로 단언한다
card() { echo "[$1] $2"; }

echo "== 키트 2곳 같은 바이트 + bash -n(3.2)"
for f in ft-nano-close.sh ft-merge-lib.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  /bin/bash -n "$SRC/$f" && ok "/bin/bash -n $f (3.2)" || bad "/bin/bash -n $f"
done

mkdir -p "$T/bin" "$T/fake" "$T/home" "$T/comm"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "oc-reap $1 left=0 rc=0"\n' > "$T/bin/ft-opencode-reap.sh"
printf '#!/bin/sh\necho "SLOTS"\n' > "$T/bin/ft-nano-slots.sh"   # 슬롯 대역(실 스크립트는 명부·tmux 를 본다)
cp "$SRC/ft-nano-close.sh" "$SRC/ft-merge-lib.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-freshness.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft_team_lib.py" "$SRC/ft-jsonl-last-ts.py" "$SRC/ft_api_outage_util.py" "$SRC/ft-team-lib.sh" "$T/bin/"
# r1318: ft_changed_paths/ft_changed_paths_wt 는 ft_git_capped.py 를 부른다(ft-team-lib.sh 안 _FT_GITCAP_PY) — 없으면 status rc=2 로 «경로 목록 못 셈» 이 되어 ⓙ 대조군이 빨개진다(나누기 전 70초 컷에 가려 안 보이던 자리).
cp "$SRC/ft_git_capped.py" "$T/bin/"
# 기준판 = 지금 판에서 «r938 시각 줄» 만 기계적으로 뺀 사본 — ⓐ 의 stdout cmp0 대조군(사람이 손으로 만든 사본 0)
python3 - "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close-baseline.sh" <<'PY'
import re, sys
src, dst = sys.argv[1:3]
out = []
for ln in open(src, encoding="utf-8").read().split("\n"):
    if re.match(r'^\s*step [^ ]+$', ln) or re.match(r'^step\(\) \{', ln) or ln.startswith('T0="$(date +%s)"'):
        continue
    out.append(ln)
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY
chmod +x "$T/bin/"* 2>/dev/null
grep -q '^step ' "$T/bin/ft-nano-close-baseline.sh" && bad "기준판 생성 실패(step 줄 남음)" || ok "기준판 사본에 step 줄 0(기계적 제거)"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) [ ! -s "$FAKE_PANES" ] || { cat "$FAKE_PANES"; exit 0; }; echo "no server running on /tmp/fake"; exit 1;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/git" <<'EOF'
#!/usr/bin/env bash
# fetch 대역 — SLEEP_FETCH 초 만큼 늘린다(ⓑ: 30초 대역이 7초+재시도 1 로 잘리는지)
case " $* " in *" fetch "*) [ -z "${SLEEP_FETCH:-}" ] || sleep "$SLEEP_FETCH";; esac
exec /usr/bin/git "$@"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" branch feat/x "$BASE"                       # ⓑ·ⓘ fetch 경로(FT_NANO_FEAT ≠ main·origin/main)를 타게
git init -q --bare "$T/origin.git" && git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
git -C "$T/origin.git" fetch -q "$REPO" main:main 2>/dev/null || true
git -C "$REPO" remote add origin "$T/origin.git"
git -C "$REPO" fetch -q origin   # r842 픽스처: ref(origin/main) 실재 — 단계 판정이 이 ref 를 읽는다(없으면 ERROR + REJECT)
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행"
SEAT='byz-planner-nano-ns#0'; BR='nano/ns'; NW="$REPO/.worktrees/v65-ns"
CARD_REL='design/planner/indices/진행/ns.md'; CARD="$REPO/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
# r958 r4 계약: ⑤ 비교 기준 = 좌석 .worktree-info base «먼저»(env FT_NANO_FEAT 는 base 없을 때만) — 시나리오의 «기준 브랜치» 는 이 파일에 쓰고 커밋 밖에 둔다.
echo ".worktree-info.json" >> "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
setbase() { printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"2026-10-26 02:00:00"}\n' "$BR" "$1" "${BASE:0:10}" > "$NW/.worktree-info.json"; }
LEDGER="$T/ledger.md"; RESULT="$T/result.md"; PROJ="$T/home/.claude/projects/$(printf '%s' "$NW" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
V="$T/calls.log"; PEND="$FT_SHEET_ROOT/.fable-team/state/sheet-events.pending"

run() { ( cd "$REPO" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_OPENCODE_DB="$T/oc.db" FT_OPENCODE_DB_TIMEOUT=1 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" REPO_DIR="$REPO" CALLS="$V" SLEEP_FETCH="${SLEEP_FETCH:-}" \
  FT_NANO_CAP_S="${FT_NANO_CAP_S:-}" FT_CARD_REF="${FT_CARD_REF:-}" FT_FETCH_TIMEOUT_SEC="${FT_FETCH_TIMEOUT_SEC:-}" "$@" ); }   # r1363: fetch 상한(지정)도 대역에 넘긴다 — ⓑ 가 25초×2 를 실제로 기다리지 않게
setup() {   # 정상 대역(모두 즉시) — 부를 때마다 하위 스크립트 대역을 «즉시» 판으로 되돌린다
  rm -f "$T/bin/ft-nano-evidence-check.sh" "$T/bin/ft-nano-cherry-gate.sh" "$T/bin/ft-nano-freshness.sh" "$T/bin/ft-sheet-events.sh"
  cp "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-freshness.sh" "$SRC/ft-sheet-events.sh" "$T/bin/"
  chmod +x "$T/bin/"*.sh
  git -C "$NW" reset -q --hard "$BASE"; git -C "$NW" clean -qfd; git -C "$NW" checkout -q "$BR" 2>/dev/null
  git -C "$REPO" branch -q -f "$BR" "$BASE" 2>/dev/null; git -C "$REPO" checkout -q main 2>/dev/null || true
  rm -rf "$PEND" "$PROJ" "$T/oc.db" "$T/wtclean"; mkdir -p "$PROJ"
  printf '{"%s":{"role":"nano","agent":"claude","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  printf '{"branch":"%s","base":"main","base_sha":"%s","created_at":"2026-10-26 02:00:00"}\n' "$BR" "${BASE:0:10}" > "$NW/.worktree-info.json"   # r958 r4: 기본 기준 = main
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; : > "$V"
  printf '{"type":"agent-name","agentName":"%s"}\n{"type":"assistant","timestamp":"2026-10-26T00:00:00Z","message":{"model":"m"}}\n' "$SEAT" > "$PROJ/s1.jsonl"
  printf '{"seq": 1, "from": "byz-planner-master-claude#1", "to": "%s", "body": "[발주]"}\n' "$SEAT" > "$T/comm/mailbox.jsonl"
  echo "산출" > "$RESULT"
  HEAD="$(git -C "$NW" rev-parse HEAD)"
  printf '# 인덱스: ns\n## 상태\n- base_sha: %s (spawn)\n- 세트: %s · 시험: bash tests/x.sh (1 passed) rc=0 · 이슈: 0\n' "${BASE:0:10}" "$HEAD" > "$CARD"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m card >/dev/null 2>&1 || true
}
slow() {   # slow <이름…> — 그 하위 스크립트를 «90초 대역» 으로 (ⓒ)
  local n; for n in "$@"; do printf '#!/bin/sh\necho "CALL %s" >> "%s"\nsleep 90\n' "$n" "$V" > "$T/bin/ft-nano-$n.sh"; chmod +x "$T/bin/ft-nano-$n.sh"; done
}
instant() {   # instant <이름> <rc> — 즉시 끝나는 대역(호출 기록)
  printf '#!/bin/sh\necho "CALL %s" >> "%s"\necho "REJECT %s 대역"\nexit %s\n' "$1" "$V" "$1" "$2" > "$T/bin/ft-nano-$1.sh"; chmod +x "$T/bin/ft-nano-$1.sh"
}
close() {  # 표준 인자 꼴(--result · --recv · role=nano · press 산출 0) — stdout/stderr 를 따로 남긴다(ⓐ)
  local rc
  setbase "${FEAT:-main}"   # r958 r4: 그 시나리오의 «기준 브랜치» = base(env 우선 아님)
  run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT="${FEAT:-main}" \
    FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
    bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$RESULT" --recv 1 "$@" >"$T/out" 2>"$T/err"
  rc=$?; cat "$T/out" "$T/err"; return "$rc"
}
closebase() {  # 기준판(r938 시각 줄 없는 사본) — stdout cmp0 대조용
  local rc
  setbase "${FEAT:-main}"   # r958 r4: 기준판도 같은 base 를 본다
  run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT="${FEAT:-main}" \
    FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
    bash "$T/bin/ft-nano-close-baseline.sh" "$SEAT" --result "$RESULT" --recv 1 "$@" >"$T/base-out" 2>"$T/base-err"
  rc=$?; cat "$T/base-out" "$T/base-err"; return "$rc"
}
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "$(card "$1" '  └ kill·태그 해제 0')" || bad "$(card "$1" '  └ kill·태그 해제 0 — tmux 변경')"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "$(card "$1" '  └ 명부 그대로')" || bad "$(card "$1" '  └ 명부 삭제됨')"
  [ ! -s "$LEDGER" ] && ok "$(card "$1" '  └ 닫힘 원장 행 0')" || bad "$(card "$1" '  └ 원장 행 생김')"
}
steps_of() { printf '%s\n' "$1" | sed -n 's/^STEP \([^ ]*\) +[0-9]*s$/\1/p'; }
elapsed() { echo $(( $(date +%s) - $1 )); }
evi() {   # evi <이름> <출력> — R938_EVIDENCE_DIR 가 있으면 그 폴더에 남긴다(증거 harness/evidence/r938)
  [ -z "${R938_EVIDENCE_DIR:-}" ] || { mkdir -p "$R938_EVIDENCE_DIR/steps"; printf '%s\n' "$2" > "$R938_EVIDENCE_DIR/steps/$1.txt"; }
}


finish() {   # 나눈 시험마다 끝에서 한 번 — 종전 꼬리(ALL PASS / FAILED n) 그대로
  echo
  [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
}
