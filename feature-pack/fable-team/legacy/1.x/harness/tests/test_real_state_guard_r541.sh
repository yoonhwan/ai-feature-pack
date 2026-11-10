#!/usr/bin/env bash
# test_real_state_guard_r541.sh — 시험이 «실» 하네스 상태를 바꾸지 않게 하는 도우미(tests/lib/real_state_guard.sh · tests/scripts/real_state_guard.py) (r541)
# 사건: test_autonomy_hooks_layout 을 BYZ 워크트리 cwd 에서 돌리자 ft_data_root ②(cwd 공용 루트 LIVE_ROOT)를 따라 실 자율 상태에 8회 씀(A11~A18).
# 픽스처 = 임시 «흉내 실 루트» git 리포(.fable-team/LIVE_ROOT → 임시 라이브 · state · comm/mailbox.jsonl · seats.json) · 외부 호출 0 · GIT_* env 0.
# ⓐ 도우미 없이 = 흉내 실 상태 바뀜(지금 꼴) ⓑ 도우미 = git 밖 cwd · 루트 풀이 실패 · 지문 같음 PASS ⓒ 일부러 바꾸면 FAIL ⓓ 시험 밖 변경 = WARN · 우편함 가짜 이름 = FAIL
# ⓔ(기존 시험 base 대조)는 evidence/r541/ · ⓕ 전수 목록 린트(목록 시험이 guard_begin 을 부르나 · 목록 밖 새 시험 0) · `--write-list` = 목록 파일 다시 씀
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HR="$(cd -- "$HERE/.." && pwd)"
LIST="$HR/evidence/r541/tests-calling-cwd-root-tools.txt"
fail=0; ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:-}"; fail=$((fail+1)); fi; }

gen_list() {  # 시험 · 부르는 도구 · env 주입 · 최상위 cd — 도구 = harness/bin 중 ft_data_root·ft_repo_root·ft_comm_dir 를 부르는 것
  python3 - "$HR" <<'PY'
import glob, os, re, sys
hr = sys.argv[1]
tools = sorted(os.path.basename(p) for p in glob.glob(f"{hr}/bin/*") if os.path.isfile(p)
               and not p.endswith("/ft-harness-root.sh")
               and re.search(r"\b(ft_data_root|ft_repo_root|ft_comm_dir)\b", open(p, errors="ignore").read()))
print(f"# r541 — 루트 풀이 3종(cwd 폴백)을 부르는 도구 {len(tools)}개 중 하나라도 부르는 팩 시험 · 열 = 시험\t도구\tenv 주입(FT_ROOT·FT_MBOX_DIR·FT_RES_ROOT)\t최상위 cd")
for p in sorted(glob.glob(f"{hr}/tests/**/test_*", recursive=True)):
    if not p.endswith((".sh", ".py")):
        continue
    s = open(p, errors="ignore").read()
    hit = [t for t in tools if re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", s)]
    if hit:
        env = "yes" if re.search(r"\b(FT_ROOT|FT_MBOX_DIR|FT_RES_ROOT)=", s) else "no"
        cd = "yes" if re.search(r"^cd\s", s, re.M) else "no"
        print(f"{os.path.relpath(p, hr)}\t{','.join(hit)}\t{env}\t{cd}")
PY
}
if [ "${1:-}" = --write-list ]; then mkdir -p "$(dirname "$LIST")"; gen_list > "$LIST"; echo "WROTE $LIST $(grep -vc '^#' "$LIST")"; exit 0; fi

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" FT_AUTONOMY_LEVEL=each; mkdir -p "$HOME"
unset FT_ROOT FT_MBOX_DIR FT_RES_ROOT FT_AUTONOMY_SH FT_AUTONOMY_STATE_DIR CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
REAL="$T/real"; WT="$T/real-wt"; LIVE="$T/real-live"; ST="$LIVE/.fable-team/state"; MB="$REAL/.fable-team/comm/mailbox.jsonl"
git -c init.defaultBranch=main init -q "$REAL" && git -C "$REAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$REAL" worktree add -q -b wt "$WT" main
mkdir -p "$ST" "$REAL/.fable-team/comm" "$T/inner" "$T/outside"
printf '%s\n' "$LIVE" > "$REAL/.fable-team/LIVE_ROOT"; printf 'x\t1\n' > "$ST/other.tsv"
printf '%s\n' '{"seq": 1, "from": "byz-a#0", "to": "byz-b#0", "body": "hi"}' > "$MB"
printf '%s\n' '{"seats": {"byz-c#0": {"role": "nano"}}}' > "$REAL/.fable-team/seats.json"
statesum() { (cd "$ST" && find . -type f -exec shasum {} + | sort | shasum); }
inner() {  # inner <이름> <본문> — 도우미를 맨 위에서 부르는 짧은 시험(바깥 가드의 RSG_ACTIVE·GIT_CEILING 은 지운다)
  printf '%s\n' '#!/usr/bin/env bash' ". \"$HERE/lib/real_state_guard.sh\" && guard_begin \"\$@\"" "$2" > "$T/inner/$1.sh"
}
run_in() { (cd "$1" && env -u RSG_ACTIVE -u GIT_CEILING_DIRECTORIES "$BASH" "$2" >"$T/out" 2>"$T/err"); rc=$?; }

# ⓐ 실패 시험 먼저 — 도우미 없이 «흉내 실 루트» cwd 에서 FT_ROOT 없이 ft-autonomy.sh on → 흉내 실 상태가 바뀐다(지금 꼴)
printf '%s\n' '#!/usr/bin/env bash' "\"\$BASH\" \"$HR/bin/ft-autonomy.sh\" on" > "$T/inner/a.sh"
s0="$(statesum)"; run_in "$WT" "$T/inner/a.sh"
[ "$(statesum)" != "$s0" ] && [ -f "$ST/autonomy.json" ]; r=$?; ck "ⓐ 도우미 없음 = 흉내 실 자율 상태 바뀜(rc=$rc · $(ls "$ST" | tr '\n' ' '))" $r "$(cat "$T/err")"

# ⓑ 같은 호출 + guard_begin → cwd = git 밖 임시 · 루트 풀이 실패 · 흉내 실 상태 그대로 · PASS 줄
inner b "pwd > \"$T/b.pwd\"; git rev-parse --show-toplevel >/dev/null 2>&1; echo \$? > \"$T/b.git\"; \"\$BASH\" \"$HR/bin/ft-autonomy.sh\" on 2>\"$T/b.err\"; echo \$? > \"$T/b.rc\"; true"
s0="$(statesum)"; run_in "$WT" "$T/inner/b.sh"
[ "$rc" = 0 ] && [ "$(statesum)" = "$s0" ] && grep -q '^REAL-STATE-GUARD PASS 실 상태 그대로 roots=data:'"$LIVE"',repo:'"$REAL"',comm:'"$REAL"'/.fable-team/comm' "$T/err"
ck "ⓑ 도우미 = 흉내 실 상태 그대로 + PASS 줄(3 루트)" $? "rc=$rc $(cat "$T/err")"
case "$(cat "$T/b.pwd")" in "$REAL"*|"$WT"*|"$LIVE"*) false;; *) true;; esac && [ "$(cat "$T/b.git")" != 0 ]; r=$?; ck "ⓑ2 자식 cwd = git 밖($(cat "$T/b.pwd"))" $r
[ "$(cat "$T/b.rc")" != 0 ] && grep -q 'ERROR 라이브 루트를 못 풂' "$T/b.err"; r=$?; ck "ⓑ3 루트 풀이 ERROR rc$(cat "$T/b.rc") (실 루트로 안 풀림)" $r "$(cat "$T/b.err")"
inner b4 'exit 3'; run_in "$WT" "$T/inner/b4.sh"; [ "$rc" = 3 ] && grep -q 'REAL-STATE-GUARD PASS' "$T/err"; ck "ⓑ4 시험 rc 그대로 전달(3)" $? "rc=$rc"
run_in "$T/outside" "$T/inner/b.sh"; [ "$rc" = 0 ] && grep -q '^REAL-STATE-GUARD PASS 실 루트 없음' "$T/err"; ck "ⓑ5 BYZ 밖 cwd = «실 루트 없음» PASS" $? "$(cat "$T/err")"

# ⓒ 시험이 일부러 흉내 실 상태를 바꾸면 FAIL «실 상태 바뀜: <파일>»
inner c "echo fake >> \"$ST/autonomy.log\""; run_in "$WT" "$T/inner/c.sh"
[ "$rc" = 1 ] && grep -qF "REAL-STATE-GUARD FAIL 실 상태 바뀜: $ST/autonomy.log" "$T/err" && ! grep -q 'GUARD PASS' "$T/err"; ck "ⓒ 실 상태 바꿈 → FAIL 원문" $? "rc=$rc $(cat "$T/err")"
inner c2 "mkdir -p \"$ST/autonomy-merge-approved\"; echo y > \"$ST/autonomy-merge-approved/$(printf 'a%.0s' {1..40})\""; run_in "$WT" "$T/inner/c2.sh"
[ "$rc" = 1 ] && grep -q 'FAIL 실 상태 바뀜: .*autonomy-merge-approved/' "$T/err"; ck "ⓒ2 가짜 병합 승인 파일 → FAIL" $? "rc=$rc $(cat "$T/err")"

# ⓓ 시험 밖 변경일 수 있는 파일 = WARN 만 · 우편함 = 아는 이름 새 줄 통과 · 가짜 이름 새 줄 FAIL
inner d1 "printf 'y\t2\n' >> \"$ST/other.tsv\""; run_in "$WT" "$T/inner/d1.sh"
[ "$rc" = 0 ] && grep -qF "REAL-STATE-GUARD WARN 시험 밖 변경일 수 있음: $ST/other.tsv" "$T/err" && grep -q 'GUARD PASS' "$T/err"; ck "ⓓ1 다른 state 파일 = WARN + PASS" $? "rc=$rc $(cat "$T/err")"
inner d2 "printf '%s\n' '{\"seq\": 2, \"from\": \"byz-a#0\", \"to\": \"byz-c#0\"}' >> \"$MB\""; run_in "$WT" "$T/inner/d2.sh"
[ "$rc" = 0 ] && grep -q 'GUARD PASS' "$T/err"; ck "ⓓ2 우편함 새 줄(이전 이름 + 명부 이름) = PASS" $? "rc=$rc $(cat "$T/err")"
inner d3 "printf '%s\n' '{\"seq\": 3, \"from\": \"t-fake\", \"to\": \"byz-a#0\"}' >> \"$MB\""; run_in "$WT" "$T/inner/d3.sh"
[ "$rc" = 1 ] && grep -qF "FAIL 우편함 가짜 이름 새 줄: ['t-fake']" "$T/err"; ck "ⓓ3 우편함 가짜 이름 새 줄 = FAIL" $? "rc=$rc $(cat "$T/err")"

# ⓑp·ⓒp 파이썬 짝 — pytest 모듈 픽스처(guard_begin_module) · 스크립트 guard_begin()
PYT="$(command -v pytest)" || { ck "ⓟ pytest 있음" 1 "pytest 없음 — PATH 에 pytest"; PYT=false; }
pyt() { printf '%s\n' "import os, sys; sys.path.insert(0, '$HERE/scripts')" "from real_state_guard import guard_begin_module  # noqa: F401" "def test_x():" "    $2" > "$T/inner/test_$1.py"; }
pyt p1 "assert not os.getcwd().startswith('$T/real'); assert os.environ.get('RSG_ACTIVE') == '1'"
(cd "$WT" && env -u RSG_ACTIVE -u GIT_CEILING_DIRECTORIES "$PYT" -q -s -p no:cacheprovider "$T/inner/test_p1.py" >"$T/out" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q 'GUARD PASS 실 상태 그대로' "$T/out"; ck "ⓑp pytest 픽스처 = git 밖 cwd · PASS" $? "rc=$rc $(tail -5 "$T/out")"
pyt p2 "open('$ST/autonomy.json', 'a').write(' ')"
(cd "$WT" && env -u RSG_ACTIVE -u GIT_CEILING_DIRECTORIES "$PYT" -q -p no:cacheprovider "$T/inner/test_p2.py" >"$T/out" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -qF "FAIL 실 상태 바뀜: $ST/autonomy.json" "$T/out"; ck "ⓒp pytest 픽스처 = 실 상태 바꿈 FAIL" $? "rc=$rc $(tail -5 "$T/out")"
printf '%s\n' "import os, sys; sys.path.insert(0, '$HERE/scripts')" "from real_state_guard import guard_begin; guard_begin()" "open('$ST/autonomy.log', 'a').write('z')" > "$T/inner/s.py"
(cd "$WT" && env -u RSG_ACTIVE -u GIT_CEILING_DIRECTORIES python3 "$T/inner/s.py" >"$T/out" 2>"$T/err"); rc=$?
[ "$rc" = 1 ] && grep -qF "FAIL 실 상태 바뀜: $ST/autonomy.log" "$T/err"; ck "ⓒs 파이썬 스크립트 guard_begin() = FAIL" $? "rc=$rc $(cat "$T/err")"

# ⓕ 전수 목록 린트 — 목록의 시험이 guard_begin 을 부르나 · 지금 생성 결과와 목록이 같은가(목록 밖 새 시험 0)
[ -f "$LIST" ]; ck "ⓕ0 목록 파일 있음($LIST)" $?
miss="$(grep -v '^#' "$LIST" | cut -f1 | while read -r t; do grep -q 'guard_begin' "$HR/$t" || echo "$t"; done)"
[ -z "$miss" ]; r=$?; ck "ⓕ1 목록 $(grep -vc '^#' "$LIST")개 전부 guard_begin" $r "guard_begin 0: $miss"
d="$(diff <(grep -v '^#' "$LIST" | cut -f1) <(gen_list | grep -v '^#' | cut -f1))"
[ -z "$d" ]; ck "ⓕ2 목록 = 지금 생성 결과(새 시험은 목록에 + guard_begin)" $? "$d"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
