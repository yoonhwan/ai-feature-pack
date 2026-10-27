#!/usr/bin/env bash
# test_nano_close_step_timing_r938.sh — r938: ft-nano-close.sh «단계 시각 줄»(ⓐ) + «외부 호출 상한»(ⓑ fetch 7초+재시도 1 · ⓒ 검사 상한 = 고정비 + 7초 × 작업량)
# 왜: ④checkpoint 면제 WARN 뒤 70초+ 무출력으로 멈추고, 그 뒤 단계들의 출력은 끝에 한꺼번에 나와 «어느 단계가 멈췄는지» 화면으로 알 수 없었다(master#114 #169157 · 실 census 닫기 3회).
# r2(DA⑥ r1 HOLD): N1 상한 검사가 모든 쓰기보다 먼저(+abort trap 은 prepare 전) · N2 상한 = 프로세스 묶음째 TERM→1초→KILL · N3 배수 = 커밋 수 · N4 fetch 실패 = 그 자리 REJECT.
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(projects) + 임시 우편함 + 하위 스크립트 대역 — 실제 리포·seats·tmux·원장은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
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
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "oc-reap $1 left=0 rc=0"\n' > "$T/bin/ft-opencode-reap.sh"
printf '#!/bin/sh\necho "SLOTS"\n' > "$T/bin/ft-nano-slots.sh"   # 슬롯 대역(실 스크립트는 명부·tmux 를 본다)
cp "$SRC/ft-nano-close.sh" "$SRC/ft-merge-lib.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-freshness.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft-jsonl-last-ts.py" "$SRC/ft-team-lib.sh" "$T/bin/"
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
  FT_NANO_CAP_S="${FT_NANO_CAP_S:-}" FT_CARD_REF="${FT_CARD_REF:-}" "$@" ); }
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

echo "== ⓐ 정상 대역 → CLOSED · STEP 줄은 stderr 에만 · stdout 은 기준판과 cmp0"
setup; runout="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$runout" "CLOSED $SEAT" "$(card ⓐ 'rc=0 · CLOSED(새 판)')" || bad "ⓐ rc=$rc ← ${runout:0:900}"
evi a-new "$runout"
ST="$(steps_of "$(cat "$T/err")")"
for nm in ⑥증거검사 ⑤cherry sheet ledger slots; do
  case "$ST" in *"$nm"*) ok "$(card ⓐ "  └ STEP $nm 줄이 stderr 에 있음")";; *) bad "$(card ⓐ "  └ STEP $nm 줄 없음 ← $ST")";; esac
done
hasnt "$(cat "$T/out")" "STEP" "$(card ⓐ '  └ stdout 에 STEP 0줄')"
setup; FB=feat/x; runbase="$(FEAT=feat/x closebase)"; rcb=$?   # 기준판 = r938 시각 줄만 뺀 사본
setup; FEAT=feat/x out="$(close)"; rc2=$?
[ "$rcb" -eq 0 ] && [ "$rc2" -eq 0 ] || bad "$(card ⓐ "기준판/새 판 rc=$rcb/$rc2")"
cmp -s "$T/base-out" "$T/out" && ok "$(card ⓐ '  └ stdout 기준판 cmp0(사람 출력 회귀 0)')" || bad "stdout 이 기준판과 다름: $(diff "$T/base-out" "$T/out" | head -4)"
hasnt "$(cat "$T/base-err")" "STEP ⑥증거검사" "$(card ⓐ '  └ 기준판 stderr 에는 STEP 0줄(대조군 확인)')"

echo "== ⓑ fetch 대역 30초 → 7초 + 재시도 1 뒤 «origin/main fetch 실패» · 옛 ref 대조 0 · 총 ≤ 20초"
setup; FEAT=feat/x instant cherry-gate 1   # 게이트 REJECT → origin/main 재대조 = fetch 경로
_now="$(date +%s)"; out="$(FEAT=feat/x FT_CARD_REF=main SLEEP_FETCH=30 close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "origin/main fetch 실패" "$(card ⓑ 'REJECT + «origin/main fetch 실패»')" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "옛 ref 대조 0" "$(card ⓑ '  └ 옛 ref 대조 0 문구')"
hasnt "$out" "origin/main 기준:" "$(card ⓑ '  └ 두 번째 게이트 호출 0(옛 ref 대조 0)')"
[ "$(grep -c 'CALL cherry-gate' "$V")" = "1" ] && ok "$(card ⓑ '  └ 게이트 대역 1회만')" || bad "게이트 호출 $(grep -c 'CALL cherry-gate' "$V")회"
[ "$took" -le 20 ] && ok "$(card ⓑ '  └ 총 소요 ≤ 20초(7초 + 재시도 1)')" || bad "총 소요 ${took}s > 20초"
hasnt "$out" "CLOSED" "$(card ⓑ '  └ CLOSED 0')"; untouched ⓑ
setup; _now="$(date +%s)"; out2="$(SLEEP_FETCH=30 close)"; took2="$(elapsed "$_now")"   # 카드 ref(origin/main) fetch 도 같은 상한
has "$out2" "WARN 카드 ref fetch 실패/시간 초과(origin/main" "$(card ⓑ '  └ 카드 ref fetch 도 7초+재시도 1')"
[ "$took2" -le 20 ] && ok "$(card ⓑ '  └ 카드 ref fetch 총 소요 ≤ 20초')" || bad "카드 ref fetch ${took2}s > 20초"

echo "== ⓒ 검사 대역 90초 → 상한 뒤 REJECT(걸린/상한 초·배수·다시 하는 길) · 명부·원장·세션 변경 0"
setup; slow evidence-check
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓒ '⑥ 증거 검사 상한 → REJECT')" || bad "ⓒ⑥ rc=$rc ← ${out:0:900}"
has "$out" "· 배수 1 — 다시: 같은 명령" "$(card ⓒ '  └ 배수·다시 하는 길 1줄')"
has "$out" "arch 에 증거 검사" "$(card ⓒ '  └ 계속이면 arch 보고 안내')"
[ "$took" -le 25 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 25초(상한 8초 · 멈춤 0)')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒ⑥
setup; FEAT=feat/x slow cherry-gate
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑤cherry 게이트 시간 초과" "$(card ⓒ '⑤ cherry 상한 → REJECT')" || bad "ⓒ⑤ rc=$rc ← ${out:0:900}"
case "$(steps_of "$(cat "$T/err")")" in *freshness*) bad "상한 초과인데 freshness 단계가 돎";; *) ok "$(card ⓒ '  └ 상한 초과 → freshness 단계 0')";; esac
[ "$took" -le 25 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 25초')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒ⑤
setup; FEAT=feat/x; instant cherry-gate 1; slow freshness
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑤-생애 freshness 시간 초과" "$(card ⓒ 'freshness 상한 → REJECT')" || bad "ⓒfr rc=$rc ← ${out:0:900}"
[ "$took" -le 35 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 35초')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒfr

echo "== ⓓ 정상 대역(모두 즉시) → 지금과 같은 결과(닫힘)"
setup; instant cherry-gate 0
out="$(FEAT=feat/x close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED " "$(card ⓓ '즉시 대역 → CLOSED')" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$out" "SLOTS" "$(card ⓓ '  └ 마지막 slots 단계까지 감')"; hasnt "$out" "시간 초과" "$(card ⓓ '  └ 시간 초과 0')"
has "$(cat "$LEDGER")" "닫힘(ft-nano-close)" "$(card ⓓ '  └ 원장 닫힘 행 1줄')"
has "$(cat "$T/tlog")" "kill-session" "$(card ⓓ '  └ 세션 kill')"

echo "== ⓔ 실측 재현 — 카드 인자 꼴(--result · --recv · role=nano · press 산출 0)에서 STEP 줄이 끝까지"
setup; instant cherry-gate 0
n_press="$(git -C "$NW" diff --name-only "$BASE" HEAD | grep -c 'poller_dom\.jsonl')"
[ "$n_press" = "0" ] && ok "$(card ⓔ '  └ press 산출 0(나노 좌석)')" || bad "press 산출이 있다"
out="$(FEAT=feat/x close)"; rc=$?
has "$out" "WARN ④checkpoint 면제 — 나노 브랜치에 press 산출 0" "$(card ⓔ '④ 면제 자리(실측 마지막 줄) 재현')"
ST="$(steps_of "$(cat "$T/err")")"
[ "$(printf '%s\n' "$ST" | grep -c .)" = "5" ] && ok "$(card ⓔ '  └ STEP 5줄 끝까지(slots 포함)')" || bad "STEP 줄 $(printf '%s\n' "$ST" | grep -c .)개 ← $ST"

echo "== ⓕ 상한 REJECT 시 쓰기 0 — .prepared 0 · 명부·원장 바이트 불변(DA⑥ r1 반례 1)"
setup; slow evidence-check
seats_before="$(shasum -a1 "$REPO/.fable-team/seats-planner.json" | cut -d' ' -f1)"; : > "$LEDGER"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓕ '상한 REJECT(증거 검사 대역)')" || bad "ⓕ rc=$rc ← ${out:0:400}"
[ ! -e "$PEND" ] || [ -z "$(ls -A "$PEND" 2>/dev/null)" ] && ok "$(card ⓕ '  └ .prepared 0')" || bad "ⓕ .prepared 남음: $(ls -A "$PEND" 2>/dev/null | tr '\n' ' ')"
[ "$(shasum -a1 "$REPO/.fable-team/seats-planner.json" | cut -d' ' -f1)" = "$seats_before" ] && ok "$(card ⓕ '  └ 명부 바이트 불변')" || bad "ⓕ 명부 바뀜"
[ ! -s "$LEDGER" ] && ok "$(card ⓕ '  └ 원장 바이트 불변')" || bad "ⓕ 원장 바뀜"
# ⓕ2 prepare «자체» 가 상한에 잘려도 .prepared 0 — abort trap 이 prepare 전에 등록돼 있어야 한다
setup
cat > "$T/bin/ft-sheet-events.sh" <<'EOF'
#!/bin/sh
p="$FT_SHEET_ROOT/.fable-team/state/sheet-events.pending"
case "$1" in
  key) printf 'k-%s' "$3";;
  prepare) mkdir -p "$p"; : > "$p/$2.prepared"; sleep 60;;
  abort) rm -f "$p/$2.prepared";;
  commit) ;;
esac
EOF
chmod +x "$T/bin/ft-sheet-events.sh"
out="$(FT_NANO_CAP_S=1 close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "사건 원장 prepared 실패" "$(card ⓕ 'prepare 상한 → REJECT')" || bad "ⓕ2 rc=$rc ← ${out:0:500}"
has "$out" "시간 초과" "$(card ⓕ '  └ «시간 초과» 표기')"
[ -z "$(ls -A "$PEND" 2>/dev/null)" ] && ok "$(card ⓕ '  └ prepare 잘린 뒤 .prepared 0(trap 이 prepare 전)')" || bad "ⓕ2 .prepared 남음: $(ls -A "$PEND" 2>/dev/null | tr '\n' ' ')"
# ⓕ3(r3 · astra r2 반례 N1): 앞 검사가 이미 bad(증거 검사 상한) + --cherry-override → 우회 원장 쓰기 0 · 대조군: bad 0 이면 override 그대로(원장 1행)
codecommit() {   # 코드 «+» 커밋 1개(cherry REJECT 거리) + 카드 증거 줄을 새 HEAD 로
  echo x > "$NW/code.sh"; git -C "$NW" add code.sh; git -C "$NW" commit -q -m code
  printf '# 인덱스: ns\n## 상태\n- 세트: %s · 시험: bash tests/x.sh (1 passing) rc=0 · 이슈: 0\n' "$(git -C "$NW" rev-parse HEAD)" > "$CARD"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m cardc >/dev/null 2>&1 || true
}
setup; codecommit; slow evidence-check; : > "$T/cherry.log"
out="$(close --cherry-override dummy)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓕ 'bad(증거 검사 상한) + --cherry-override → REJECT')" || bad "$(card ⓕ "override rc=$rc ← ${out:0:500}")"
[ ! -s "$T/cherry.log" ] && ok "$(card ⓕ '  └ 우회 원장(cherry override) 행 0')" || bad "$(card ⓕ "  └ 우회 원장에 행 생김: $(head -1 "$T/cherry.log")")"
has "$out" "⑤REJECT cherry 게이트" "$(card ⓕ '  └ cherry 는 읽기 전용 판정(REJECT 줄)')"
untouched ⓕ
setup; codecommit; : > "$T/cherry.log"
out="$(close --cherry-override dummy)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c . "$T/cherry.log")" = "1" ] && ok "$(card ⓕ '  └ 대조군: bad 0 이면 override 전달 · 원장 1행 · CLOSED')" || bad "$(card ⓕ "  └ 대조군 rc=$rc 원장 $(grep -c . "$T/cherry.log")행 ← ${out:0:500}")"

echo "== ⓖ 상한이 프로세스 묶음째 끝냄 — 자식이 분리돼도 REJECT 뒤 자식 쓰기 0"
setup
cat > "$T/bin/ft-nano-evidence-check.sh" <<'EOF'
#!/bin/sh
( sleep 3; echo late > "$REPO_DIR/late-write.txt" ) &      # 분리된 자식 — 상한이 묶음째 끝내야 한다
echo "CALL evidence" >> "$CALLS"
sleep 90
EOF
chmod +x "$T/bin/ft-nano-evidence-check.sh"
rm -f "$REPO/late-write.txt"
out="$(FT_NANO_CAP_S=1 close)"; rc=$?; sleep 3
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓖ '상한 → REJECT')" || bad "$(card ⓖ "rc=$rc ← ${out:0:400}")"
[ ! -e "$REPO/late-write.txt" ] && ok "$(card ⓖ '  └ REJECT 뒤 3초 자식 쓰기 0')" || bad "$(card ⓖ '  └ 자식이 늦게 씀(묶음째 kill 실패)')"
pgrep -f "sleep 90" >/dev/null 2>&1 && bad "$(card ⓖ '  └ 상한 뒤 살아 있는 대역 프로세스 있음')" || ok "$(card ⓖ '  └ 그 묶음 생존 0')"
# ⓖ-손자(r3 · astra r2 반례 N2): 자식이 setsid 로 새 세션 손자를 띄우고(출력 fd 물려받음) 4초 뒤 쓰기 → nf_bound 1 은 ≤ 3초 반환 · 반환 뒤 5초 쓰기 0 · 손자 생존 0
awk '/^nf_fixed\(\) \{/{p=1} /^if \[ "\$REPLAN" -eq 0 \]/{p=0} p' "$T/bin/ft-nano-close.sh" > "$T/fn.sh"
GC="$T/gc"; rm -f "$GC.pid" "$GC.late"
cat > "$T/gc.sh" <<'EOF'
#!/bin/sh
python3 - "$1" <<'PY' &
import os, sys, time
os.setsid()
open(sys.argv[1] + ".pid", "w").write(str(os.getpid()))
time.sleep(4)
open(sys.argv[1] + ".late", "w").write("late")
PY
echo started
sleep 90
EOF
_now="$(date +%s)"; out="$(bash -c '. "$1"; nf_bound 1 sh "$2" "$3"; echo "rc=$?"' _ "$T/fn.sh" "$T/gc.sh" "$GC")"; took="$(elapsed "$_now")"
has "$out" "rc=124" "$(card ⓖ 'setsid 손자 대역 · 상한 1초 → rc 124')"
[ "$took" -le 3 ] && ok "$(card ⓖ "  └ ${took}초에 반환(≤3초 · 손자가 출력 fd 를 물고 있어도)")" || bad "$(card ⓖ "  └ 반환 ${took}s > 3초(손자 fd 기다림)")"
sleep 5
[ ! -e "$GC.late" ] && ok "$(card ⓖ '  └ 반환 뒤 5초 손자 쓰기 0')" || bad "$(card ⓖ '  └ 손자가 반환 뒤에 씀(새 세션 손자 회수 실패)')"
gpid="$(cat "$GC.pid" 2>/dev/null)"
[ -n "$gpid" ] && ! kill -0 "$gpid" 2>/dev/null && ok "$(card ⓖ "  └ 손자 pid ${gpid} 생존 0")" || { bad "$(card ⓖ "  └ 손자 pid ${gpid:-<없음>} 살아 있음/기록 없음")"; [ -z "$gpid" ] || kill -9 "$gpid" 2>/dev/null; }
# ⓖ2·ⓖ3(r5 계약 · astra r3 반례): 총(nf_bound 호출부터 rc 까지) ≤ 상한 + 4초 — ps 가 안 돌아와도 · 대상이 TERM 을 무시해도 · 손자가 출력 fd 를 물고 있어도 그 안에 rc(상한 = 124)를 돌려준다
#   시험 단언 ≤ 4.9초(상한 1초) < 계약 상한 5.0초 = 의도
#   PATH 앞 ps 대역 — ⓖ2 는 0.7초 잠든 뒤 진짜 ps · ⓖ3 는 5초 잠듦(조회 상한 1초에 잘림 · exec 로 대역 = 한 프로세스 = 진짜 ps 가 멈춘 꼴)
timed() {  # timed <ps 대역 폴더> — nf_bound 1 /bin/sleep 10 의 «rc 걸린초» (소수 3자리)
  PATH="$1:$PATH" python3 -c 'import subprocess,sys,time
t=time.time(); r=subprocess.run(["bash","-c",". \"$1\"; nf_bound 1 /bin/sleep 10","_",sys.argv[1]])
print(r.returncode, "%.3f" % (time.time()-t))' "$T/fn.sh"
}
mkdir -p "$T/ps07" "$T/ps5"
printf '#!/bin/sh\nsleep 0.7\nexec /bin/ps "$@"\n' > "$T/ps07/ps"; printf '#!/bin/sh\nexec /bin/sleep 5\n' > "$T/ps5/ps"; chmod +x "$T/ps07/ps" "$T/ps5/ps"
for g in ⓖ2:ps07 ⓖ3:ps5; do
  nm="${g%%:*}"; r="$(timed "$T/${g#*:}")"; rrc="${r%% *}"; sec="${r#* }"
  [ "$rrc" = "124" ] && ok "$(card ⓖ "$nm ps 대역(${g#*:}) · nf_bound 1 /bin/sleep 10 → rc 124")" || bad "$(card ⓖ "$nm rc=$rrc ← $r")"
  awk -v s="$sec" 'BEGIN{exit !(s <= 4.9)}' && ok "$(card ⓖ "  └ $nm ${sec}초 ≤ 4.9초(시험 단언 · 계약 상한 1 + 4 = 5.0초)")" || bad "$(card ⓖ "  └ $nm ${sec}초 > 4.9초(시험 단언 밖)")"
  pgrep -f '^/bin/sleep 10$' >/dev/null 2>&1 && bad "$(card ⓖ "  └ $nm 대상 /bin/sleep 10 살아 있음")" || ok "$(card ⓖ "  └ $nm 대상 /bin/sleep 10 생존 0")"
done
pgrep -f '^/bin/sleep 5$' >/dev/null 2>&1 && bad "$(card ⓖ '  └ ⓖ3 대역 ps(sleep 5) 살아 있음')" || ok "$(card ⓖ '  └ ⓖ3 대역 ps(sleep 5) 생존 0(조회 상한 1초에 잘림)')"

echo "== ⓗ TERM 무시 대역 · 상한 1초 → 3초 안에 끝남(KILL 유예 1초)"
setup
cat > "$T/bin/ft-nano-evidence-check.sh" <<'EOF'
#!/bin/sh
trap '' TERM
echo "CALL evidence" >> "$CALLS"
sleep 90
EOF
chmod +x "$T/bin/ft-nano-evidence-check.sh"
awk '/^nf_fixed\(\) \{/{p=1} /^if \[ "\$REPLAN" -eq 0 \]/{p=0} p' "$T/bin/ft-nano-close.sh" > "$T/fn.sh"
_now="$(date +%s)"; bash "$T/fn.sh" 2>/dev/null; out="$(bash -c '. "$1"; nf_bound 1 sh -c "trap \"\" TERM; sleep 90"; echo "rc=$?"' _ "$T/fn.sh")"; took="$(elapsed "$_now")"
has "$out" "rc=124" "$(card ⓗ 'TERM 무시 대역 · 상한 1초 → rc 124')"
[ "$took" -le 3 ] && ok "$(card ⓗ "  └ 상한+유예 = ${took}초(≤3초 · KILL 유예 1초)")" || bad "ⓗ took=${took}s > 3초 ← $out"
pgrep -f "sleep 90" >/dev/null 2>&1 && bad "ⓗ TERM 무시 대역이 살아 있음" || ok "$(card ⓗ '  └ 그 묶음 생존 0')"

echo "== ⓘ 배수 = 커밋 수 — 커밋 12 · 커밋당 1초 대역은 «정상 느림» 이라 통과(거짓 거절 0)"
setup
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "$i" > "$NW/c$i.txt"; git -C "$NW" add "c$i.txt"; git -C "$NW" commit -q -m "c$i"; done
HEAD12="$(git -C "$NW" rev-parse HEAD)"
printf '# 인덱스: ns\n## 상태\n- 세트: %s · 시험: bash tests/x.sh (1 passing) rc=0 · 이슈: 0\n' "$HEAD12" > "$CARD"
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m card12 >/dev/null 2>&1 || true
cat > "$T/bin/ft-nano-cherry-gate.sh" <<'EOF'
#!/bin/sh
n=$(git -C "$REPO_DIR" rev-list --count "feat/x..nano/ns" 2>/dev/null || echo 0)
echo "CALL cherry-gate commits=$n" >> "$CALLS"
sleep "$n"
echo "OK cherry 게이트 대역 commits=$n"
exit 0
EOF
chmod +x "$T/bin/ft-nano-cherry-gate.sh"
_now="$(date +%s)"; out="$(FEAT=feat/x close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 0 ] && has "$out" "commits=12" "$(card ⓘ '커밋 12 · 커밋당 1초 → 배수 12 상한 안 → 통과(rc0)')" || bad "$(card ⓘ "rc=$rc ← ${out:0:600}")"
[ "$took" -ge 10 ] && ok "$(card ⓘ "  └ 대역이 실제로 ${took}초 걸렸다(느림 재현)")" || bad "$(card ⓘ "  └ 대역이 ${took}s — 느림 재현 실패")"

echo "== ⓙ 원격 없음 + 캐시 origin/main → fetch 실패 REJECT · cherry 통과 줄 0(DA⑥ r1 반례 3)"
setup; FEAT=origin/main
git -C "$REPO" remote remove origin; git -C "$REPO" update-ref refs/remotes/origin/main "$BASE"   # 원격 없음 + 캐시 ref 남음
out="$(FEAT=origin/main close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "origin/main fetch 실패" "$(card ⓙ 'fetch 실패 → 그 자리 REJECT')" || bad "ⓙ rc=$rc ← ${out:0:700}"
hasnt "$out" "전부 origin/main 에 있" "$(card ⓙ '  └ cherry 통과 줄 0')"
has "$out" "옛 ref 대조 0" "$(card ⓙ '  └ 옛 ref 대조 0 문구')"
git -C "$REPO" remote add origin "$T/origin.git"
untouched ⓙ
# ⓙ2(r3 · astra r2 반례 N4): --research · 원격 없음 + 캐시 origin/main · FT_NANO_FEAT=main → 리서치 fetch 실패 = 그 자리 REJECT(병합 대조 0)
#   리서치 «미커밋 0» 을 맞추려고 대역 .worktree-info.json 을 제외 목록에 둔다(아래 대조군 뒤 원복) — 거절 사유가 fetch 하나뿐이게
EXCL="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/info/exclude"; mkdir -p "$(dirname "$EXCL")"; cp "$EXCL" "$T/exclude.bak" 2>/dev/null || : > "$T/exclude.bak"
echo ".worktree-info.json" >> "$EXCL"
setup
git -C "$REPO" remote remove origin; git -C "$REPO" update-ref refs/remotes/origin/main "$BASE"
out="$(FEAT=main close --research)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓙ '--research fetch 실패 → rc1')" || bad "$(card ⓙ "--research rc=$rc ← ${out:0:700}")"
[ "$(printf '%s\n' "$out" | grep -c '⑥리서치 origin/main fetch 실패')" = "1" ] && ok "$(card ⓙ '  └ «⑥리서치 origin/main fetch 실패» 1줄')" || bad "$(card ⓙ "  └ 리서치 fetch 실패 줄 $(printf '%s\n' "$out" | grep -c '⑥리서치 origin/main fetch 실패')개")"
hasnt "$out" "RESEARCH-OK" "$(card ⓙ '  └ 리서치 통과 줄 0(옛 ref 병합 대조 0)')"
hasnt "$out" "CLOSED" "$(card ⓙ '  └ CLOSED 0')"
evi j-research-fetch-fail "$out"
git -C "$REPO" remote add origin "$T/origin.git"
untouched ⓙ
setup; out="$(FEAT=main close --research)"; rc=$?   # 대조군: 원격 있음 → 같은 인자 꼴이 리서치 통과(거절 사유가 fetch 하나뿐임을 보인다)
evi j-research-control "$out"
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "$(card ⓙ '  └ 대조군: 원격 있음 → RESEARCH-OK · rc0')" || bad "$(card ⓙ "  └ 대조군 rc=$rc ← ${out:0:700}")"
cp "$T/exclude.bak" "$EXCL"

echo "== ⓚ 상한식 = min(고정비 + 7×배수, 70) · 600/300초 0 · 무상한 fetch 0"
CA="$(bash -c 'nf_cap(){ f="${1:-1}"; m="${2:-1}"; awk -v f="$f" -v m="$m" "BEGIN{t=f+7*m; if(t>70)t=70; if(t<7)t=7; printf \"%d\\n\", t}"; }; nf_cap 1 1; nf_cap 1 2; nf_cap 2 12; nf_cap 1 20')"
[ "$CA" = "$(printf '8\n15\n70\n70')" ] && ok "$(card ⓚ '배수 1→8 · 2→15 · 12→70(상한)')" || bad "nf_cap 값: $(printf '%s' "$CA" | tr '\n' ' ')"
NEWL="$(grep -nE 'r938|nf_cap|nf_bound|nf_fetch|nf_again|nf_fixed|nf_mult|step ' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -E '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "$(card ⓚ '600/300 숫자 0')"
hasnt "$(printf '%s\n' "$NEWL" | grep -E 'curl|wget|https?://|nc ')" ":" "$(card ⓚ '외부 호출 0')"
[ "$(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")" = "0" ] && ok "$(card ⓚ '무상한 git fetch 0(전부 nf_fetch 경유)')" || bad "fetch -q 잔존 $(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")줄"
awk '/ft-sheet-events.sh" key/{k=NR} /^trap .*abort/{a=NR} /^nf_bound .*ft-sheet-events.sh" prepare/{p=NR} END{exit !(a>k && a<p)}' "$SRC/ft-nano-close.sh" \
  && ok "$(card ⓚ 'abort trap 이 prepare 전에 등록(N1)')" || bad "trap 위치가 prepare 뒤"

echo "== ⓛ 첫 cherry 즉시 REJECT · fetch 성공 · 둘째 cherry(origin/main) 6초 · 상한 1초 → 그 자리 REJECT · freshness 0(astra r2 반례 N3)"
setup
cat > "$T/bin/ft-nano-cherry-gate.sh" <<'EOF'
#!/bin/sh
echo "CALL cherry-gate $1" >> "$CALLS"
case "$1" in origin/main) sleep 6; echo "OK 늦은 통과"; exit 0;; esac
echo "REJECT cherry 게이트 대역($1)"; exit 1
EOF
chmod +x "$T/bin/ft-nano-cherry-gate.sh"
out="$(FEAT=feat/x FT_NANO_CAP_S=1 close)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓛ 'rc1')" || bad "$(card ⓛ "rc=$rc ← ${out:0:700}")"
[ "$(grep -c 'CALL cherry-gate origin/main' "$V")" = "1" ] && ok "$(card ⓛ '  └ 둘째 cherry(origin/main) 호출 1회(fetch 성공 경로)')" || bad "$(card ⓛ "  └ 둘째 cherry 호출 $(grep -c 'CALL cherry-gate origin/main' "$V")회")"
[ "$(printf '%s\n' "$out" | grep -cE 'cherry 게이트\(origin/main\) 시간 초과 [0-9]+s/1s · 배수 [0-9]+ — 다시:')" = "1" ] && ok "$(card ⓛ '  └ «cherry 게이트(origin/main) 시간 초과 <초>s/<상한>s · 배수 <n> — 다시:» 1줄')" || bad "$(card ⓛ "  └ 둘째 cherry 상한 줄 없음 ← ${out:0:700}")"
hasnt "$out" "origin/main 기준: " "$(card ⓛ '  └ 빈 «origin/main 기준:» 줄 0')"
case "$(steps_of "$(cat "$T/err")")" in *freshness*) bad "$(card ⓛ '  └ 상한 초과인데 freshness STEP 줄 있음')";; *) ok "$(card ⓛ '  └ freshness STEP 줄 0')";; esac
hasnt "$out" "CLOSED" "$(card ⓛ '  └ CLOSED 0')"; untouched ⓛ

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
