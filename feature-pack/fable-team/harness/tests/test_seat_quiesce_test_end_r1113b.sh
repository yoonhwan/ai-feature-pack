#!/usr/bin/env bash
# test_seat_quiesce_test_end_r1113b.sh — ft-seat-quiesce.sh --scope test + ft-test-run.sh 시험 끝 정리 · 반례 R1~R6 + 사용법 + kit 짝 + 변이 4 (r1113b)
#   가짜 나무 = lib/r1113_fake_tree.sh(sleep 스텁 · 가짜 tmux·launchctl · ps 필터 = 띄운 pid + /r1113b/ 꼴 + 이 시험 임시 폴더 글자) · 실 LSP·실 kill 대상 0 · 자기 재호출 0
#   LSP 스텁 = 런타임 꼴 `node /r1113b/bin/<이름> …`(name_of = 스크립트 이름) · 변이: ⓜ1 시험 범위 끔 → R1 FAIL · ⓜ2 나무 경계 끔 → R2 FAIL · ⓜ3 시험 묶음 끔 · ⓜ4 러너 끝 훅 끔
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
Q="${Q_SCRIPT:-$BIN/ft-seat-quiesce.sh}"; RUN="${RUN_SCRIPT:-$BIN/ft-test-run.sh}"
TMP="$(mktemp -d)"; . "$HERE/lib/r1113_fake_tree.sh"; fake_init; trap fake_cleanup EXIT
export FAKE_KEEP_RE="r1113-(newkid|lchild|mid)|/r1113b/|$TMP"
BP="node /r1113b/bin/basedpyright-langserver --stdio"; PY="node /r1113b/bin/pyright-langserver --stdio"; CL="node /r1113b/@anthropic-ai/claude-code/cli.js"
pass=0; fail=0; T0=$(date +%s)
ck() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; sed 's/^/    | /' "$TMP/last" 2>/dev/null | tail -6; fail=$((fail+1)); fi; }
q() { local s="$1"; shift; bash "$s" "$@" > "$TMP/last" 2>&1; echo $? > "$TMP/rc"; }
rc_is() { [ "$(cat "$TMP/rc")" = "$1" ]; }
has() { grep -qF -- "$1" "$TMP/last"; }
dead() { local p; for p in "$@"; do ! alive "$p" || return 1; done; }
live() { local p; for p in "$@"; do alive "$p" || return 1; done; }
byarg() { /bin/ps -axo pid=,command= | N="$1" awk 'index($0, ENVIRON["N"]) { print $1 }'; }   # byarg <글자> — 명령 줄에 그 글자가 있는 pid(들) · 글자는 env 로(awk 자기 줄에 안 섞이게)
sweep() { byarg "$1" | xargs kill -9 2>/dev/null; return 0; }
grp_orphan() {   # grp_orphan <이름> — 따로 묶은 묶음(set -m) 안 ppid 1 스텁 · 묶음 번호 = $TMP/g.pg · pid = $TMP/g.pid
  local g p i; set -m; ( bash -c 'exec -a "$0" sleep 300' "$1" & echo $! > "$TMP/g.pid" ) & g=$!; set +m; wait "$g"
  p="$(cat "$TMP/g.pid")"; echo "$p" >> "$TMP/pids"; echo "$g" > "$TMP/g.pg"
  for i in $(seq 1 30); do [ "$(/bin/ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && break; sleep 0.1; done; }

r1() { local s="$1" t="R1$2" root; tree "$t" 0 "$BP" "$PY"; root="$(pid_of "$t" root)"
  q "$s" --scope test "$root"; rc_is 0 && has "[시험 정리] test:$root mode=test" && has "term=2 kill=0 left=0" && has "남은 자식 0" \
    && dead "$(pid_of "$t" "$BP")" "$(pid_of "$t" "$PY")" && live "$root"; }
r2() { local s="$1" o="R2o$2" t="R2t$2"; tree "$o" 0 "$PY"; tree "$t" 0 "$PY"
  q "$s" --scope test "$(pid_of "$t" root)"; rc_is 0 && has "term=1" && dead "$(pid_of "$t" "$PY")" && live "$(pid_of "$o" "$PY")"; }
r3() { local s="$1" t="R3$2" h g ok=1; orphan "$PY --human$2"; h="$(cat "$TMP/orphan.pid")"; tree "$t" 0; grp_orphan "$BP --group$2"; g="$(cat "$TMP/g.pid")"
  q "$s" --scope test "$(pid_of "$t" root)" --pgid "$(cat "$TMP/g.pg")"; rc_is 0 && has "term=1" && dead "$g" && live "$h" && ok=0
  kill -9 "$h" "$g" 2>/dev/null; return $ok; }
r4() { local t=R4 root; tree "$t" 0 "$CL" "$BP"; root="$(pid_of "$t" root)"; rss "$(pid_of "$t" "$CL")" 900
  q "$Q" --scope test "$root"; rc_is 0 && has "term=1" && live "$(pid_of "$t" "$CL")" && dead "$(pid_of "$t" "$BP")"; }
mkspawner() { printf '%s\n' 'trap '"'"'bash -c "exec -a \"node /r1113b/bin/basedpyright-langserver --newkid\" sleep 300" & exit 0'"'"' TERM' 'while :; do sleep 0.2; done' > "$TMP/fake/lspawner.sh"
  bash -c 'exec -a "node /r1113b/bin/pyright-langserver --spawner" bash "$1" & exec -a r1113b-shell sleep 300' _ "$TMP/fake/lspawner.sh" & SROOT=$!; echo "$SROOT" >> "$TMP/pids"
  local i; for i in $(seq 1 30); do [ -n "$(byarg '--spawner' | head -1)" ] && break; sleep 0.1; done; sleep 0.2; }
r5() { local ok=1; mkspawner
  q "$Q" --scope test "$SROOT"; rc_is 0 && has "new=1" && has "round=1" && has "남은 자식 0" && [ -z "$(byarg --newkid | while read -r x; do alive "$x" && echo "$x"; done)" ] && ok=0
  sweep --newkid; sweep --spawner; return $ok; }
r5lim() { local ok=1; mkspawner
  FT_QUIESCE_RESCAN_MAX=0 q "$Q" --scope test "$SROOT"; rc_is 1 && has "quiesce-rescan-limit 0" && has "left=1" && has "남은 자식 1" && ok=0
  sweep --newkid; sweep --spawner; return $ok; }
mktest() {   # mktest <rc> <꼬리> — 시험 끝 뒤 남는 LSP 둘(중간 셸이 끝난 고아 1 · 시험 셸 자식 1) · 둘 다 시험 묶음 안
  printf '%s\n' "( exec -a \"node /r1113b/bin/basedpyright-langserver --from-test$2\" sleep 300 & )" \
    "bash -c 'exec -a \"node /r1113b/bin/pyright-langserver --from-test$2\" sleep 300' &" "sleep 0.3; exit $1" > "$TMP/t$2.sh"; }
runner() { local r="$1" rc="$2" sfx="$3" h ok=1; mktest "$rc" "$sfx"; orphan "$PY --human-run$sfx"; h="$(cat "$TMP/orphan.pid")"
  FT_SEAT_QUIESCE_BIN="$Q" FT_TEST_REENTRY_LINT_BIN="$BIN/ft-test-reentry-lint.sh" q "$r" bash "$TMP/t$sfx.sh"
  rc_is "$rc" && has "OK $TMP/t$sfx.sh" && has "[시험 정리]" && has "term=2 kill=0 left=0" && has "남은 자식 0" && [ -z "$(byarg "--from-test$sfx" | while read -r x; do alive "$x" && echo "$x"; done)" ] && live "$h" && ok=0
  sweep "--from-test$sfx"; kill -9 "$h" 2>/dev/null; return $ok; }
warn() { local trc="$1"; printf 'echo "[시험 정리] test:1 mode=test term=1 kill=1 left=1"; echo "남은 자식 1 9 x"; exit 1\n' > "$TMP/fake/q-left"; printf 'exit %s\n' "$trc" > "$TMP/tw.sh"
  FT_SEAT_QUIESCE_BIN="$TMP/fake/q-left" FT_TEST_REENTRY_LINT_BIN="$BIN/ft-test-reentry-lint.sh" q "$RUN" bash "$TMP/tw.sh"
  rc_is "$trc" && has "WARN 시험 정리 rc=1" && has "시험 rc=$trc 그대로"; }
lint() { printf 'touch "%s/ran"\nbash "$0"\n' "$TMP" > "$TMP/tself.sh"; rm -f "$TMP/ran"
  FT_SEAT_QUIESCE_BIN="$Q" FT_TEST_REENTRY_LINT_BIN="$BIN/ft-test-reentry-lint.sh" q "$RUN" bash "$TMP/tself.sh"; rc_is 3 && has "REENTRY $TMP/tself.sh:2" && [ ! -e "$TMP/ran" ]; }
usage() { q "$Q" --scope test abc; rc_is 2 || return 1; q "$Q" --scope test 1 --pgid x; rc_is 2 || return 1; q "$Q" S1 --mode close --pgid 3; rc_is 2 || return 1
  q "$Q" --scope test 999999; rc_is 20 && has "판정 불가" && [ "$(wc -l < "$TMP/last" | tr -d ' ')" = 1 ]; }
kit() { local f; for f in ft-seat-quiesce.sh ft-test-run.sh; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "kit 다름 $f" > "$TMP/last"; return 1; }; done; }

bash -n "$Q" && bash -n "$RUN" || { echo "FAIL bash -n"; exit 1; }
ck "ⓐ R1 시험 나무 안 basedpyright·pyright langserver → 둘 다 정리 · [시험 정리] left=0 · 남은 자식 0" r1 "$Q" ""
ck "ⓑ R2 남의 좌석 나무 pyright-langserver 생존" r2 "$Q" ""
ck "ⓑ R3 시험 나무 밖 사람 LSP(ppid 1) 생존 · 시험 묶음 고아는 정리" r3 "$Q" ""
ck "ⓒ R4 시험 나무 안 Claude 본체 node cli.js 900MB 보호" r4
ck "ⓓ R5 TERM 뒤 새 LSP pid → 재조회 round=1 로 정리 · 남은 자식 0" r5
ck "ⓓ R5 재조회 상한 0 → left=1 · 남은 자식 1 · rc 1" r5lim
ck "ⓐ 러너 rc0 시험 → 시험이 남긴 LSP 2개(고아·자식) 정리 · 사람 LSP 생존 · rc 0" runner "$RUN" 0 a
ck "ⓔ R6 러너 rc1 시험 → 정리 그대로 · 러너 rc 1" runner "$RUN" 1 b
ck "ⓔ R5 정리 left≠0 → WARN 1줄 · 러너 rc = 시험 rc(0)" warn 0
ck "ⓔ R5 정리 left≠0 → WARN 1줄 · 러너 rc = 시험 rc(1)" warn 1
ck "재진입 lint rc3 → 시험 안 돌림 · rc 3" lint
ck "사용법 rc2 · 없는 뿌리 pid = 판정 불가 1줄 rc 20" usage
ck "ⓕ kit 짝 cmp0 (2파일)" kit
T1=$(date +%s)
sed 's/^        return {p for p in tree | grp if pick(t\[p\])}/        return set()/' "$Q" > "$TMP/m1.sh"
sed 's/^        return {p for p in tree | grp if pick(t\[p\])}/        return {p for p in t if pick(t[p])}/' "$Q" > "$TMP/m2.sh"
sed 's/^        grp = {p for p, r in t.items() if tpg and/        grp = set() and {p for p, r in t.items() if tpg and/' "$Q" > "$TMP/m3.sh"
sed 's/^bash "\$Q" --scope test \$\$ --pgid "\$tp"; qrc=\$?/qrc=0/' "$RUN" > "$TMP/m4.sh"
for m in 1 2 3; do cmp -s "$Q" "$TMP/m$m.sh" && echo "WARN 변이 m$m 이 원본과 같음(sed 불일치)"; done; cmp -s "$RUN" "$TMP/m4.sh" && echo "WARN 변이 m4 이 원본과 같음(sed 불일치)"
ck "ⓜ1 시험 범위 끔 → R1 FAIL" eval '! r1 "$TMP/m1.sh" m'
ck "ⓜ2 나무 경계 끔 → R2 FAIL" eval '! r2 "$TMP/m2.sh" m'
ck "ⓜ3 시험 묶음 끔 → R3 FAIL" eval '! r3 "$TMP/m3.sh" m'
ck "ⓜ4 러너 끝 훅 끔 → 러너 R1 FAIL" eval '! runner "$TMP/m4.sh" 0 m'
echo "단계별 초: 본 시험 $((T1 - T0)) · 변이 $(( $(date +%s) - T1 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
