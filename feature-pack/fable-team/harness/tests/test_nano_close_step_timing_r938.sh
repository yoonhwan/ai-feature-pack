#!/usr/bin/env bash
# test_nano_close_step_timing_r938.sh — r938: ft-nano-close.sh «단계 시각 줄»(ⓐ) + «외부 호출 상한»(ⓑ fetch 7초+재시도 1 · ⓒ 하위 검사 상한)
# 왜: ④checkpoint 면제 WARN 뒤 70초+ 무출력으로 멈추고, 그 뒤 단계들의 출력은 끝에 한꺼번에 나와 «어느 단계가 멈췄는지» 화면으로 알 수 없었다(master#114 #169157 · 실 census 닫기 3회).
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(projects) + 임시 우편함 + 하위 스크립트 대역 — 실제 리포·seats·tmux·원장은 건드리지 않는다.
# 축 ⓐ 단계마다 stderr «STEP <이름> +<초>s» · stdout 0줄(사람 출력 회귀 0) ⓑ fetch 7초+재시도 1 뒤 «origin/main fetch 시간 초과» · 옛 ref 대조 0 · 총 ≤ 20초
#    ⓒ 검사기(증거·cherry·freshness)가 90초 걸리면 상한 뒤 REJECT «시간 초과 — 닫지 않음» · 명부·원장·세션 변경 0 ⓓ 정상 대역 → 지금과 같은 CLOSED
#    ⓔ 실측 재현(카드 인자 꼴 --result·--recv·role=nano·press 산출 0) ⓕ 상한 = min(고정비+7×배수, 70) · 600/300초 0 · /bin/bash 3.2 rc0 · 키트 짝 cmp0
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
git -C "$REPO" branch feat/x "$BASE"                       # ⓑ fetch 경로(FT_NANO_FEAT ≠ main·origin/main)를 타게
git init -q --bare "$T/origin.git" && git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
git -C "$T/origin.git" fetch -q "$REPO" main:main 2>/dev/null || true
git -C "$REPO" remote add origin "$T/origin.git"
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행"
SEAT='byz-planner-nano-ns#0'; BR='nano/ns'; NW="$REPO/.worktrees/v65-ns"
CARD_REL='design/planner/indices/진행/ns.md'; CARD="$REPO/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
LEDGER="$T/ledger.md"; RESULT="$T/result.md"; PROJ="$T/home/.claude/projects/$(printf '%s' "$NW" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
V="$T/calls.log"    # 하위 스크립트 대역 호출 기록

run() { ( cd "$REPO" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_OPENCODE_DB="$T/oc.db" FT_OPENCODE_DB_TIMEOUT=1 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {   # 정상 대역(모두 즉시) — 부를 때마다 하위 스크립트 대역을 «즉시» 판으로 되돌린다
  rm -f "$T/bin/ft-nano-evidence-check.sh" "$T/bin/ft-nano-cherry-gate.sh" "$T/bin/ft-nano-freshness.sh"
  cp "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-freshness.sh" "$T/bin/"
  chmod +x "$T/bin/"*.sh
  git -C "$NW" reset -q --hard "$BASE"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","agent":"claude","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  printf '{"branch":"%s","base":"main","base_sha":"%s","created_at":"2026-10-26 02:00:00"}\n' "$BR" "${BASE:0:10}" > "$NW/.worktree-info.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; : > "$V"
  rm -rf "$T/wtclean" "$PROJ" "$T/oc.db"; mkdir -p "$PROJ"
  printf '{"type":"agent-name","agentName":"%s"}\n{"type":"assistant","timestamp":"2026-10-26T00:00:00Z","message":{"model":"m"}}\n' "$SEAT" > "$PROJ/s1.jsonl"
  printf '{"seq": 1, "from": "byz-planner-master-claude#1", "to": "%s", "body": "[발주]"}\n' "$SEAT" > "$T/comm/mailbox.jsonl"
  echo "산출" > "$RESULT"
  HEAD="$(git -C "$NW" rev-parse HEAD)"
  printf '# 인덱스: ns\n## 상태\n- base_sha: %s (spawn)\n- 세트: %s · 시험: bash tests/x.sh (1 passed) rc=0 · 이슈: 0\n' "${BASE:0:10}" "$HEAD" > "$CARD"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "card" >/dev/null 2>&1 || true
}
slow() {   # slow <이름…> — 그 하위 스크립트를 «90초 대역» 으로 (ⓒ)
  local n; for n in "$@"; do printf '#!/bin/sh\necho "CALL %s" >> "%s"\nsleep 90\n' "$n" "$V" > "$T/bin/ft-nano-$n.sh"; chmod +x "$T/bin/ft-nano-$n.sh"; done
}
instant() {   # instant <이름> <rc> — 즉시 끝나는 대역(호출 기록)
  printf '#!/bin/sh\necho "CALL %s" >> "%s"\necho "REJECT %s 대역"\nexit %s\n' "$1" "$V" "$1" "$2" > "$T/bin/ft-nano-$1.sh"; chmod +x "$T/bin/ft-nano-$1.sh"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT="${FEAT:-main}" \
  FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  SLEEP_FETCH="${SLEEP_FETCH:-}" FT_CARD_REF="${FT_CARD_REF:-}" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$RESULT" --recv 1 "$@"; }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
}
evi() {   # evi <이름> <출력> — R938_EVIDENCE_DIR 가 있으면 그 폴더에 그 실행의 출력(STEP 줄 포함)을 남긴다(증거 harness/evidence/r938)
  [ -z "${R938_EVIDENCE_DIR:-}" ] || { mkdir -p "$R938_EVIDENCE_DIR/steps"; printf '%s\n' "$2" > "$R938_EVIDENCE_DIR/steps/$1.txt"; }
}
steps_of() { printf '%s\n' "$1" | sed -n 's/^STEP \([^ ]*\) +\([0-9]*\)s$/\1/p'; }
elapsed() { echo $(( $(date +%s) - $1 )); }

echo "== ⓐ 정상 대역 → CLOSED · stderr 에 단계마다 «STEP <이름> +<초>s» · stdout 0줄"
setup
_now="$(date +%s)"; runout="$(close)"; rc=$?; took="$(elapsed "$_now")"
evi a-normal "$runout"
[ "$rc" -eq 0 ] && has "$runout" "CLOSED $SEAT" "ⓐ rc=0 · CLOSED" || bad "ⓐ rc=$rc ← ${runout:0:900}"
ST="$(steps_of "$runout")"
for nm in ⑥증거검사 ⑤cherry sheet ledger slots; do
  case "$ST" in *"$nm"*) ok "  └ STEP $nm 줄 있음";; *) bad "  └ STEP $nm 줄 없음 ← $ST";; esac
done
hasnt "$(printf '%s\n' "$runout" | grep -v '^STEP ')" "STEP" "  └ STEP 줄은 stderr 전용(stdout 회귀 0)"
has "$runout" "WARN ④checkpoint 면제" "  └ ④ 면제 WARN 뒤에 단계 줄이 이어진다(실측 그 자리)"
case "$ST" in ⑥증거검사*) ok "  └ 첫 단계는 ⑥증거검사(가장 먼저)";; *) bad "  └ 첫 단계: $ST";; esac
has "$(printf '%s' "$runout" | grep -c '^STEP ')" "5" "  └ 정상 대역 STEP 5줄(⑥·⑤·sheet·ledger·slots)"
[ "$took" -lt 20 ] && ok "  └ 총 소요 ${took}s < 20s(정상 대역)" || bad "  └ 총 소요 ${took}s — 너무 느림"

echo "== ⓑ fetch 대역 30초 → 7초 + 재시도 1 뒤 «origin/main fetch 시간 초과» · 옛 ref 대조 0 · 총 ≤ 20초"
setup; FEAT=feat/x instant cherry-gate 1   # 게이트 REJECT → origin/main 재대조 = fetch 경로
_now="$(date +%s)"; out="$(FEAT=feat/x FT_CARD_REF=main SLEEP_FETCH=30 close)"; rc=$?; took="$(elapsed "$_now")"
evi b-fetch "$out"
[ "$rc" -eq 1 ] && has "$out" "origin/main fetch 시간 초과" "ⓑ REJECT + «origin/main fetch 시간 초과»" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "옛 ref 로 대조하지 않는다" "  └ 옛 ref 대조 0 문구"
[ "$(grep -c 'CALL cherry-gate' "$V")" = "1" ] && ok "  └ fetch 실패 뒤 두 번째 게이트 호출 0(옛 ref 대조 0)" || bad "  └ 게이트 호출 $(grep -c 'CALL cherry-gate' "$V")회(1 이어야)"
[ "$took" -le 20 ] && ok "  └ 총 소요 ${took}s ≤ 20초(7초 + 재시도 1)" || bad "  └ 총 소요 ${took}s > 20초"
hasnt "$out" "CLOSED" "  └ CLOSED 0"; untouched "ⓑ"
setup; _now="$(date +%s)"; out2="$(SLEEP_FETCH=30 close)"; rc2=$?; took2="$(elapsed "$_now")"   # 카드 ref(origin/main) fetch 도 같은 상한
has "$out2" "WARN 카드 ref fetch 실패/시간 초과(origin/main · 7초+재시도 1)" "  └ 카드 ref fetch 도 7초+재시도 1(옛 판 안 읽음)"
[ "$took2" -le 20 ] && ok "  └ 카드 ref fetch 총 소요 ${took2}s ≤ 20초" || bad "  └ 카드 ref fetch ${took2}s > 20초"

echo "== ⓒ 증거 검사 대역 90초 → 상한(≈11초) 뒤 REJECT «⑥증거 검사 시간 초과 — 닫지 않음»"
setup; slow evidence-check
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
evi c-evidence "$out"
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "ⓒ 증거 검사 상한 → REJECT" || bad "ⓒ rc=$rc ← ${out:0:900}"
has "$out" "— 닫지 않음" "  └ «닫지 않음» 문구"
[ "$took" -le 25 ] && ok "  └ 총 소요 ${took}s ≤ 25초(상한 11초 · 멈춤 0)" || bad "  └ 총 소요 ${took}s — 상한이 안 걸렸다"
hasnt "$out" "CLOSED" "  └ CLOSED 0"; untouched "ⓒ⑥"

echo "== ⓒ cherry 게이트 대역 90초 → 상한 뒤 REJECT «⑤cherry 게이트 시간 초과 — 닫지 않음» · 뒤 단계 0"
setup; FEAT=feat/x slow cherry-gate
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
evi c-cherry "$out"
[ "$rc" -eq 1 ] && has "$out" "⑤cherry 게이트 시간 초과" "ⓒ cherry 상한 → REJECT" || bad "ⓒ' rc=$rc ← ${out:0:900}"
[ "$(grep -c 'CALL cherry-gate' "$V")" = "1" ] && ok "  └ 상한 초과 뒤 두 번째 게이트 호출 0" || bad "  └ 게이트 호출 $(grep -c 'CALL cherry-gate' "$V")회"
steps="$(steps_of "$out")"; case "$steps" in *freshness*) bad "  └ 상한 초과인데 freshness 단계가 돎";; *) ok "  └ 상한 초과 → freshness 단계 0";; esac
[ "$took" -le 25 ] && ok "  └ 총 소요 ${took}s ≤ 25초" || bad "  └ 총 소요 ${took}s — 상한이 안 걸렸다"
hasnt "$out" "CLOSED" "  └ CLOSED 0"; untouched "ⓒ⑤"

echo "== ⓒ freshness 대역 90초 → 상한 뒤 «⑤-생애 freshness 시간 초과» · REJECT"
setup; FEAT=feat/x; instant cherry-gate 1; slow freshness
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
evi c-freshness "$out"
[ "$rc" -eq 1 ] && has "$out" "⑤-생애 freshness 시간 초과" "ⓒ freshness 상한 → REJECT" || bad "ⓒ'' rc=$rc ← ${out:0:900}"
[ "$took" -le 35 ] && ok "  └ 총 소요 ${took}s ≤ 35초(게이트 즉시 + fetch 1 + 상한 11)" || bad "  └ 총 소요 ${took}s — 상한이 안 걸렸다"
hasnt "$out" "CLOSED" "  └ CLOSED 0"; untouched "ⓒfreshness"

echo "== ⓓ 정상 대역(모두 즉시) → 지금과 같은 결과(닫힘 · 사람 출력 꼴 그대로)"
setup; instant cherry-gate 0
out="$(FEAT=feat/x close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED " "ⓓ 즉시 대역 → CLOSED" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$out" "SLOTS" "  └ 마지막 slots 단계까지 감"; hasnt "$out" "시간 초과" "  └ 시간 초과 0"
has "$(cat "$LEDGER")" "닫힘(ft-nano-close)" "  └ 원장 닫힘 행 1줄"
has "$(cat "$T/tlog")" "kill-session" "  └ 세션 kill"

echo "== ⓔ 실측 재현 — 카드 인자 꼴(--result · --recv · role=nano · press 산출 0)에서 STEP 줄이 끝까지"
setup; instant cherry-gate 0
printf '%s' "$(git -C "$NW" diff --name-only "$BASE" HEAD | grep -c 'poller_dom\.jsonl')" > "$T/pressed"
[ "$(cat "$T/pressed")" = "0" ] && ok "  └ press 산출 0(나노 좌석)" || bad "  └ press 산출이 있다"
out="$(close)"; rc=$?
has "$out" "WARN ④checkpoint 면제 — 나노 브랜치에 press 산출 0" "ⓔ ④ 면제 자리(실측 마지막 줄) 재현"
ST="$(steps_of "$out")"; [ "$(printf '%s\n' "$ST" | grep -c .)" = "5" ] && ok "  └ STEP 5줄 끝까지(slots 포함)" || bad "  └ STEP 줄 $(printf '%s\n' "$ST" | grep -c .)개 ← $ST"

echo "== ⓕ 상한 계산 = min(고정비 + 7×배수, 70) · 600/300초 0 · 외부 호출 0"
CA="$(bash -c '. "$1"; nf_cap 1; nf_cap 2; nf_cap 20' _ "$SRC/ft-merge-lib.sh" 2>/dev/null; : )"
CA="$(bash -c 'nf_cap(){ m="${1:-1}"; f="${FT_NANO_CALL_FIXED_S:-4.5}"; awk -v f="$f" -v m="$m" "BEGIN{t=f+7*m; if(t>70)t=70; if(t<7)t=7; printf \"%d\\n\", t}"; }; nf_cap 1; nf_cap 2; nf_cap 20')"
[ "$CA" = "$(printf '11\n18\n70')" ] && ok "  └ nf_cap 1=11 · 2=18 · 20=70(최대 70)" || bad "  └ nf_cap 값: $(printf '%s' "$CA" | tr '\n' ' ')"
NEWL="$(grep -nE 'r938|nf_cap|nf_bound|nf_fetch|step ' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -E '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -E 'curl|wget|https?://|nc ')" ":" "외부 호출 0"
[ "$(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")" = "0" ] && ok "  └ 무상한 git fetch 0(전부 nf_fetch 경유)" || bad "  └ fetch -q 잔존 $(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")줄"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
