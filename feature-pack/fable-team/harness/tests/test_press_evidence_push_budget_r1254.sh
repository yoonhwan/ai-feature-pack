#!/usr/bin/env bash
# test_press_evidence_push_budget_r1254.sh — r1254: press 증거 push(묶음·빚·상환 ref) = 하드 룰 12 «쪼갤 수 없는 배치» min(고정비 9 + 7, 70) s
#   + 끊긴 뒤 ls-remote 로 «그 ref 가 그 sha 로 있나» 확인 · 다른 sha 는 덮어쓰지 않음 · fetch 는 그대로 7 s
#   반례 R1~R6(카드 동결 집합) · 변이 3(상한 고정 1 s → R1 FAIL · 원격 확인 끔 → R2 FAIL · 다른 sha 검사 끔 → R4 FAIL)
#   임시 origin(bare) + PATH 앞의 가짜 git(push·fetch 만 늦추거나 끊음 · 나머지는 실 git) · 가짜 지연 3 s 이하 · 자기 재호출은 real_state_guard 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"

REAL_GIT="$(command -v git)"; FAKEB="$T/fakebin"; PUSH_LOG="$T/push.log"; export REAL_GIT PUSH_LOG; mkdir -p "$FAKEB"
cat > "$FAKEB/git" <<'EOF'
#!/bin/bash
# 가짜 git: push·fetch 만 가로챈다. STUB_PUSH = ok(실 git) · slow(STUB_SLEEP 뒤 실 git) · late(실 git 먼저·STUB_SLEEP 뒤 끝) · fail(1 줄 오류 rc1)
for a in "$@"; do case "$a" in push) p=1;; fetch) f=1;; esac; done
if [ -n "${p:-}" ]; then
  echo push >> "$PUSH_LOG"
  case "${STUB_PUSH:-ok}" in
    slow) sleep "$STUB_SLEEP"; exec "$REAL_GIT" "$@";;
    late) "$REAL_GIT" "$@"; exec sleep "$STUB_SLEEP";;
    fail) echo "fatal: stub remote hung up" >&2; exit 1;;
  esac
fi
[ -n "${f:-}" ] && [ -n "${STUB_FETCH_SLEEP:-}" ] && sleep "$STUB_FETCH_SLEEP"
exec "$REAL_GIT" "$@"
EOF
chmod +x "$FAKEB/git"
S="$(sha "$REPO" HEAD)"; EVTX="$EVT"
mpk() {  # mpk <run> <모드> <가짜 지연 초> <상한 초(빈 값 = 기본)> → out · rc · PUSHES(push 호출 수)
  : > "$PUSH_LOG"; ev "$T/ev/$1" "$1"
  out="$(PATH="$FAKEB:$PATH" STUB_PUSH="$2" STUB_SLEEP="$3" FT_PRESS_PUSH_SEC="$4" bash "$EVTX" pack "$S" --run "$1" --poller "$T/ev/$1/poller_dom.jsonl" --table "$T/ev/$1/table.md" --turbopack "$T/ev/$1/turbopack.txt" --repo "$REPO" 2>&1)"; rc=$?
  PUSHES="$(wc -l < "$PUSH_LOG" | tr -d ' ')"
}
r1() { mpk "$1" slow 1.5 2; [ "$rc" = 0 ] && [[ "$out" == *"PACKED ref=refs/press/$S-$1 "* ]] && [ "$PUSHES" = 1 ] && [ -n "$(sha "$ORIGIN" "refs/press/$S-$1")" ]; }
r2() { mpk "$1" late 3 1; [ "$rc" = 0 ] && [[ "$out" == *"INFO push 끊김 · 원격에 있음 · 성공으로 셈 refs/press/$S-$1"* ]] && [[ "$out" == *"PACKED ref="* ]] && [ "$PUSHES" = 1 ]; }
r4() {  # 원격 ref 가 다른 sha → 덮어쓰기 0
  O="$(git -C "$REPO" commit-tree "$S^{tree}" -p "$S" -m other)"; git -C "$REPO" push -q origin "$O:refs/press/$S-$1"
  mpk "$1" ok 0 ""; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 원격 refs/press/$S-$1 가 다른 sha(${O:0:10}) — 사람 판정"* ]] && [ "$PUSHES" = 1 ] && [ "$(sha "$ORIGIN" "refs/press/$S-$1")" = "$O" ]
}
mutate() {  # mutate <이름> <바꿀 문자열> <새 문자열> → EVTX = 변이 복사본 도구
  local d="$T/mut-$1" f; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/press_evidence_verify.py"
  python3 - "$BIN/press_evidence_verify.py" "$d/press_evidence_verify.py" "$2" "$3" <<'PY' || { echo "FAIL 변이 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  EVTX="$d/ft-press-evidence.sh"
}

# ===== R1: 상한 안(가짜 1.5 s · 상한 2 s)에 성공 → PACKED · 같은 가짜를 짧은 상한(1 s)에 넣으면 판정 불가 =====
r1 r1; ck "R1 push 1.5 s · 상한 2 s → PACKED · 원격에 ref · push 1회" $?
mpk r1s slow 1.5 1; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: git push 실패(1 s + 재시도 1 · 원격 확인 0) 1 s 초과"* ]] && [ "$PUSHES" = 2 ]; ck "R1 같은 가짜 · 상한 1 s → 판정 불가 1줄(상한은 시간 비례)" $?
mpk r1d fail 0 ""; [[ "$out" == *"git push 실패(16 s + 재시도 1"* ]]; ck "R1 기본 상한 = min(9 + 7, 70) = 16 s" $?
out="$(FT_PRESS_PUSH_FIXED=100 python3 -c "import sys;sys.path.insert(0,'$BIN');import press_evidence_verify as v;print(v.push_sec())")"; [ "$out" = 70.0 ]; ck "R1 고정비가 커도 상한 70 s" $?
echo "단계 초: R1 $((SECONDS - T_START))s"
# ===== R2: 상한에서 끊기지만 서버는 ref 갱신 → ls-remote 확인 → 성공 INFO 1줄 · 재시도 0 =====
r2 r2; ck "R2 push 끊김 · 원격에 있음 → 성공 INFO · PACKED · push 1회" $?
echo "단계 초: R2 $((SECONDS - T_START))s"
# ===== R3: 두 번 다 실패 · 원격 ref 없음 → 판정 불가 «원격 확인 0» 1줄 rc1 =====
mpk r3 fail 0 2; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: git push 실패(2 s + 재시도 1 · 원격 확인 0) fatal: stub remote hung up"* ]] && [ "$PUSHES" = 2 ] && [ -z "$(git -C "$ORIGIN" for-each-ref "refs/press/$S-r3")" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]
ck "R3 push 2회 실패 · 원격 ref 없음 → 판정 불가 1줄 rc1" $?
# ===== R4: 원격 ref 가 다른 sha → 덮어쓰기 0 =====
r4 r4; ck "R4 원격 ref 가 다른 sha → «사람 판정» 1줄 rc1 · 원격 ref 그대로 · 재시도 0" $?
echo "단계 초: R3~R4 $((SECONDS - T_START))s"
# ===== R5: fetch 는 push 상한을 따르지 않고 지금 그대로(7 s 갈래 · 상한 1 s 에서도 3 s fetch 통과) =====
out="$(PATH="$FAKEB:$PATH" STUB_PUSH=ok STUB_FETCH_SLEEP=3 FT_PRESS_PUSH_SEC=1 bash "$EVT" debt --repo "$REPO" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == "press 빚 0" ]]; ck "R5 push 상한 1 s 에서도 fetch 3 s 통과(fetch 갈래 그대로 · 실패 문구는 gate_b R11 회귀)" $?
# ===== R6: 빚 ref·상환 ref push 도 같은 갈래(land 경로 · 서버는 받았는데 손님만 끊긴 꼴) =====
adv "worker/l.py=L"; L="$(sha "$REPO" HEAD)"; brn b6r; git -C "$REPO" revert --no-edit "$L" >/dev/null; RV="$(sha "$REPO" HEAD)"
landpy() { out="$(PATH="$FAKEB:$PATH" STUB_PUSH=late STUB_SLEEP=3 FT_PRESS_PUSH_SEC=1 python3 "$BIN/press_evidence_land.py" land --repo "$REPO" --main origin/main --root "$T" "$@" 2>&1)"; rc=$?; }
landpy --head "$RV" --landing "$RV" --pr 61 --title "[harness] Revert ${L:0:10}"
[ "$rc" = 0 ] && [[ "$out" == *"INFO push 끊김 · 원격에 있음"* ]] && [[ "$out" == *"press=revert:${L:0:10}" ]] && git -C "$ORIGIN" log -1 --format=%B "refs/press-debt/$RV" | grep -q "pr=61 reverted=$L"; ck "R6 빚 ref push 끊김 → 원격 확인 → 성공(press=revert · 빚 ref 있음)" $?
git -C "$REPO" push -q origin "$RV:refs/heads/main"; brn b6p; put worker/n.py n; cm "$REPO" "pr 62"; S6="$(sha "$REPO" HEAD)"
ev "$T/ev/r6" r6; bash "$EVT" pack "$S6" --run r6 --poller "$T/ev/r6/poller_dom.jsonl" --table "$T/ev/r6/table.md" --turbopack "$T/ev/r6/turbopack.txt" --repo "$REPO" >/dev/null 2>&1
landpy --head "$S6" --landing "$S6" --pr 62
[ "$rc" = 0 ] && [[ "$out" == *"INFO push 끊김 · 원격에 있음"* ]] && [[ "$out" == *"빚 상환 1"* ]] && [ "$(sha "$ORIGIN" "refs/press-debt-paid/$RV")" = "$(sha "$ORIGIN" "refs/press/$S6-r6")" ]; ck "R6 상환 ref push 끊김 → 원격 확인 → 성공(refs/press-debt-paid = 갚은 묶음)" $?
echo "단계 초: R5~R6 $((SECONDS - T_START))s"

# ===== 변이 3 =====
mutate m1 'return float(os.environ.get("FT_PRESS_PUSH_SEC") or min(fixed + 7, 70))' 'return 1.0'; r1 r1m; [ $? != 0 ]; ck "ⓜ변이 1(push 상한 고정 1 s) → R1 FAIL = 계약 깨짐 재현" $?
mutate m2 'now = remote_sha(repo, remote, ref)' 'now = None'; r2 r2m; [ $? != 0 ]; ck "ⓜ변이 2(원격 확인 끔) → R2 FAIL = 계약 깨짐 재현" $?
mutate m3 'if now:' 'if False:'; r4 r4m; [ $? != 0 ]; ck "ⓜ변이 3(다른 sha 검사 끔) → R4 FAIL = 계약 깨짐 재현" $?
EVTX="$EVT"
echo "단계 초: 변이 $((SECONDS - T_START))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
