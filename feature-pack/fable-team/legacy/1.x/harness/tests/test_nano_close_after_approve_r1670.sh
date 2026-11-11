#!/usr/bin/env bash
# test_nano_close_after_approve_r1670.sh — r1670 승인 갈래: 인수 줄 도구(ⓐ) + close-due 승인 갈래(ⓑ) + 앞 세트 거절(ⓒ) + 변이 M1.
#   임시 루트(명부·카드·판정문·우편함) + 좌석마다 임시 bare remote·clone + 가짜 tmux·ft-seat-status 만 쓴다 — 실 명부·tmux·좌석·네트워크 0 · sleep 0 · 자기 재호출 0.
#   ★닫기 집행(ⓓ)·주기 실행(ⓔ)·닫기 금지(ⓕ)·회귀(ⓖ) 는 짝 파일 test_nano_close_after_approve_driver_r1670.sh 가 본다(카드 크기 «시험 ≤120줄» — 사례별 2파일).
#   환경: FT_NANO_AUTO_CLOSE=1 일 때만 승인 갈래가 목록에 들어온다(기본 0 = 지금 출력 그대로) · 판정문 = 카드 «DA 판정:» 경로 · 값 규칙 = r1664.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
ulimit -u 2000 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
REALGIT="$(command -v git)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }

echo "== 짝 cmp · bash -n · 실행 비트"
for f in ft-nano-close-due.sh ft-nano-accept.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"
  bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  /bin/bash -n "$BIN/$f" && ok "/bin/bash 3.2 -n $f" || bad "/bin/bash 3.2 -n $f"
done
[ ! -x "$BIN/ft-nano-accept.sh" ] && ok "새 도구 = 100644(실행 비트 0)" || bad "ft-nano-accept.sh 실행 비트 있음"

FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) cat "$FAKE_SESS";;
  display-message) s="${4#=}"; s="${s%:}"; cat "$FAKE_CWD_DIR/$s";;
  *) exit 9;;
esac
EOF
cat > "$FK/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = turn ] && [ -f "$FAKE_SS_DIR/$2" ] && { cat "$FAKE_SS_DIR/$2"; exit 0; }
exit 1
EOF
cat > "$FK/quiet" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_QUIET:-OK}" = "__RC9__" ] && exit 9
echo "${FAKE_QUIET:-OK}"
EOF
chmod +x "$FK/tmux" "$FK/ft-seat-status.sh" "$FK/quiet"
export PATH="$FK:$PATH" FAKE_SESS="$T/sess" FAKE_CWD_DIR="$T/cwd" FAKE_SS_DIR="$T/ss" FK="$FK"
SEAT='byz-harness-nano-ok#0'; WT="$T/wt"; H=""; M0=""
mkdir -p "$T/cwd" "$T/ss" "$T/rem" "$T/wt"

new_root() {  # 좌석 1개(승인 갈래) + 판정문 + 우편함
  ROOT="$T/root"; rm -rf "$ROOT" "$T/rem" "$T/wt" "$T/cwd" "$T/ss"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm/bodies" "$ROOT/design/teams/harness/indices/진행" "$ROOT/design/harness" "$T/cwd" "$T/ss"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$ROOT/design/TEAMS.md"
  printf '%s\n' "$SEAT" > "$T/sess"; printf '%s\n' "$WT" > "$T/cwd/$SEAT"; printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"
  printf '{"seq": 7, "from": "%s", "to": "byz-harness-master-pi#196", "body": "산출 보고"}\n' "$SEAT" > "$ROOT/.fable-team/comm/mailbox.jsonl"
  printf '산출 보고\n' > "$ROOT/.fable-team/comm/bodies/7.txt"
  printf '{"%s": {"role": "nano", "agent": "pi", "index": "design/teams/harness/indices/진행/ok.md"}}\n' "$SEAT" > "$ROOT/.fable-team/seats-harness.json"
}
seat_repo() {  # 좌석 워크트리 = bare remote 의 clone · 가지 nano/ok 를 «원격에» 보존
  git init -q --bare -b main "$T/rem/r.git"; git clone -q "$T/rem/r.git" "$T/wt" 2>/dev/null
  git -C "$T/wt" checkout -q -b main; echo a > "$T/wt/a"; git -C "$T/wt" add a; git -C "$T/wt" commit -q -m M0
  git -C "$T/wt" push -q origin main; M0="$(git -C "$T/wt" rev-parse HEAD)"
  git -C "$T/wt" checkout -q -b nano/ok; echo x > "$T/wt/x"; git -C "$T/wt" add x; git -C "$T/wt" commit -q -m work; H="$(git -C "$T/wt" rev-parse HEAD)"
  git -C "$T/wt" push -q origin nano/ok   # 원격 보존(refs/remotes/origin/nano/ok 생김)
  git -C "$T/wt" update-ref refs/remotes/origin/main "$M0"   # main 은 낡음 = 착지 없음
}
card() {  # <상태 줄…>
  { printf '# 인덱스: ok\n## 구현 범위\n- x\n## 상태\n- base_sha: %s (spawn)\n' "$M0"; printf '%s\n' "$@"; } > "$ROOT/design/teams/harness/indices/진행/ok.md"
}
verdict() {  # <판정 값> <적을 sha> — 첫 «판정:» 줄이 값 · 본문에 sha 한 줄
  printf '단계별 초: 1\n\n# 승인 갈래 판정\n\n## §1 판정: %s\n\n승인 sha: %s\n' "$1" "$2" > "$ROOT/design/harness/DA-ok.md"
  printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT"
}
run() { OUT="$(FT_ROOT="$ROOT" FT_NANO_AUTO_CLOSE="${AUTO:-0}" FT_CLOSE_DUE_SEAT_STATUS="$FK/ft-seat-status.sh" FT_CLOSE_DUE_QUIET="$FK/quiet" bash "${DUE:-$BIN/ft-nano-close-due.sh}" "$@" 2>&1)"; RC=$?; }

echo "== ⓐ 인수 줄 도구 — 같은 sha 0줄 · 다른 sha 새 줄 · 남은 일 빈 칸 REJECT"
new_root; seat_repo; card "- 세트: $H" "$(verdict APPROVE "$H")"
VLINE="$T/v.txt"
out="$(bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$H" "검증=arch 랜딩=master" --by byz-harness-master-pi#196 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "ACCEPT ${H:0:9}" "ⓐ 인수 줄 1개" || bad "ⓐ rc=$rc ← $out"
has "$(cat "$ROOT/design/teams/harness/indices/진행/ok.md")" "- 인수: $H · 남은 일: 검증=arch 랜딩=master · 쓴 이: byz-harness-master-pi#196" "ⓐ 꼴 = 인수·남은 일·쓴 이"
eq "$(grep -c '인수: ' "$ROOT/design/teams/harness/indices/진행/ok.md")" "1" "ⓐ 1줄만"
out="$(bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$H" "검증=arch" --by x 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "ALREADY" "ⓐ 같은 sha 재실행 = 0줄(rc0)" || bad "ⓐ 재실행 rc=$rc ← $out"
eq "$(grep -c '인수: ' "$ROOT/design/teams/harness/indices/진행/ok.md")" "1" "ⓐ 같은 sha 는 줄을 안 늘린다"
out="$(bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$M0" "랜딩=master" --by x 2>&1)"; rc=$?
eq "$(grep -c '인수: ' "$ROOT/design/teams/harness/indices/진행/ok.md")" "2" "ⓐ 다른 sha = 새 줄"
out="$(bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$H" "" --by x 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT 남은 일 칸이 비어" "ⓐ 남은 일 빈 칸 REJECT"
out="$(bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "zz" "a=b" --by x 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "40hex" "ⓐ 40hex 아님 REJECT"

echo "== ⓑ 승인 갈래 = 마지막 세트·DA APPROVE·인수·원격 보존 → 닫기 차례 … 갈래=승인"
new_root; seat_repo; card "- 세트: $H" "$(verdict APPROVE "$H")"
bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$H" "검증=arch" --by m >/dev/null 2>&1
run --all --why; O1="$OUT"; R1="$RC"
hasnt "$O1" "갈래=승인" "ⓑ0 기본(FT_NANO_AUTO_CLOSE 0) = 승인 갈래를 안 낸다(지금 출력 그대로)"
has "$O1" "제외 $SEAT main 에 산출 없음" "ⓑ0 꺼짐 = 기존 제외 줄 그대로"
AUTO=1 run --all --why; O2="$OUT"; R2="$RC"
has "$O2" "닫기 차례 $SEAT 팀=harness 갈래=승인 set=$H" "ⓑ 켜짐 = 갈래=승인 줄"
has "$O2" "— bash ft-nano-close.sh $SEAT --approved $ROOT/design/harness/DA-ok.md --result $ROOT/.fable-team/comm/bodies/7.txt --recv 7" "ⓑ 줄 꼬리 = 닫기 명령(판정문·결과·seq 값)"
eq "$R2" "0" "ⓑ 판정 불가 0 → rc0"
run --summary; has "$OUT" "닫기 차례 harness=0" "ⓑ0 요약은 승인 갈래를 안 센다(꺼짐)"
AUTO=1 run --summary; has "$OUT" "닫기 차례 harness=1" "ⓑ 켜짐 요약 = 1"
FT_APPROVE_VERDICT="$ROOT/design/harness/DA-ok.md" run --approve-gate "$SEAT"; OG="$OUT"; RG="$RC"
eq "$RG" "0" "ⓑ 게이트 rc0"
has "$OG" "APPROVE-OK $SEAT set=$H verdict=$ROOT/design/harness/DA-ok.md" "ⓑ 게이트 = APPROVE-OK <좌석> set=<HEAD> verdict=<경로>"
FT_APPROVE_VERDICT="$T/other.md" run --approve-gate "$SEAT"
[ "$RC" -eq 1 ] && has "$OUT" "--approved 경로가 카드 «DA 판정:» 경로와 다름" "ⓑ 게이트 = 넘겨받은 판정문 ≠ 카드 판정문 → REJECT"
verdict APPROVE "$M0"; AUTO=1 run --all --why   # 판정문이 «앞 세트» 를 적음
hasnt "$OUT" "닫기 차례 $SEAT" "ⓑ 판정문 sha ≠ 지금 세트 → 승인 갈래 아님"
has "$OUT" "DA 판정문의 승인 sha ≠ HEAD" "ⓑ 사유 = 판정문의 «승인 sha:» 가 지금 세트와 다름"
verdict HOLD "$H"; AUTO=1 run --all --why
has "$OUT" "DA 판정 값이 APPROVE 아님" "ⓑ 값 HOLD → 승인 갈래 아님"
for v in "APPROVE — 사유 있음" "APPROVE (조건 2개)"; do   # r1664 값 규칙
  verdict "$v" "$H"; AUTO=1 run --all
  has "$OUT" "닫기 차례 $SEAT 팀=harness 갈래=승인" "ⓑ 값 «APPROVE …» 꼴 통과: $v"
done
verdict APPROVE "$H"; card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $H · 남은 일: 검증=arch · 쓴 이: m" "- 2026-11-11 재개(--reopen) · 좌석 $SEAT"
AUTO=1 run --all --why
has "$OUT" "재개 뒤 세트 줄 없음(A12)" "ⓑ 인수 뒤 재개 줄 → 세트 근거 0(A12) → 닫기 0"
card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $H · 남은 일: 검증=arch · 쓴 이: m" "- 2026-11-11 DA HOLD · 보정 요청 1건"
AUTO=1 run --all --why
has "$OUT" "인수 뒤 «- 2026-11-11 DA HOLD" "ⓑ 인수 뒤 HOLD·보정 요청 줄 → 닫기 0"
printf '단계별 초: 1\n\n# 승인 갈래 판정\n\n## §1 판정: APPROVE\n\n승인 sha: %s\n\n참고 후보: %s (미승인)\n' "$M0" "$H" > "$ROOT/design/harness/DA-ok.md"   # ① 본문에 HEAD 언급만 있고 승인 sha 는 앞 세트
AUTO=1 run --all --why
has "$OUT" "승인 sha ≠ HEAD" "① 판정문 본문에 HEAD 언급만(승인 sha 는 다른 세트) → 승인 갈래 아님"
hasnt "$OUT" "닫기 차례 $SEAT" "① 본문 언급만으로는 닫기 차례 0"
printf '단계별 초: 1\n\n## §1 판정: APPROVE\n\n승인 sha: %s\n승인 sha: %s\n' "$H" "$M0" > "$ROOT/design/harness/DA-ok.md"   # 승인 sha 두 줄(모호)
AUTO=1 run --all --why
has "$OUT" "«승인 sha:» 줄이 2개" "① 승인 sha 가 2개(모호) → 승인 갈래 아님"
verdict APPROVE "$H"
card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")"   # 인수 줄 없음
AUTO=1 run --all --why; has "$OUT" "카드에 «인수:» 줄 없음" "ⓑ 인수 줄 없음 → 닫기 0"
git -C "$T/wt" push -q origin :nano/ok   # 원격 가지 삭제 = 원격 보존 아님
card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $H · 남은 일: 검증=arch · 쓴 이: m"
git -C "$T/wt" update-ref -d refs/remotes/origin/nano/ok
AUTO=1 run --all --why; has "$OUT" "HEAD 가 origin 원격 가지에 없음" "ⓑ 원격 보존 아님 → 닫기 0"

echo "== ⓒ 앞 세트 승인은 안 센다 — 세트 A 에 APPROVE·인수, 뒤 세트 B(HEAD)"
new_root; seat_repo; HA="$H"
git -C "$T/wt" checkout -q -b tmp "$HA"; echo y > "$T/wt/y"; git -C "$T/wt" add y; git -C "$T/wt" commit -q -m work2
git -C "$T/wt" checkout -q nano/ok; git -C "$T/wt" merge -q --ff-only tmp; git -C "$T/wt" branch -q -D tmp; HB="$(git -C "$T/wt" rev-parse HEAD)"; git -C "$T/wt" push -q origin nano/ok
verdict APPROVE "$HA"
card "- 세트: $HA" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $HA · 남은 일: 검증=arch · 쓴 이: m" "- 세트: $HB"
AUTO=1 run --all --why; OC="$OUT"
hasnt "$OC" "닫기 차례 $SEAT" "ⓒ 앞 세트 승인·인수 + 뒤 세트 B → 닫기 차례 0"
has "$OC" "DA 판정문의 승인 sha ≠ HEAD ${HB:0:9}" "ⓒ 사유 = 판정문의 승인 sha 가 지금 세트와 다름"
AUTO=1 run --summary; has "$OUT" "닫기 차례 harness=0" "ⓒ 요약 0"

echo "== 변이 M1 — «APPROVE·인수를 HEAD 에 묶는» 대조 2개 삭제 → ⓒ 가 못 잡는다(변이 FAIL 기대)"
MUT="$T/mut"; mkdir -p "$MUT"; cp "$BIN/ft_team_lib.py" "$MUT/"
python3 - "$BIN/ft-nano-close-due.sh" "$MUT/ft-nano-close-due.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
drop = ['    if shas.pop() != head: return False, f"DA 판정문의 승인 sha ≠ HEAD {head[:9]}(본문 언급만으로는 승인 0)"\n',
        '    if a_sha != head: return False, f"인수 {a_sha[:9]} ≠ HEAD {head[:9]}"\n']   # «APPROVE·인수를 HEAD 에 묶는» 두 대조
for d in drop:
    assert d in s, "M1 앵커 없음"
    s = s.replace(d, "", 1)
open(dst, "w", encoding="utf-8").write(s)
PY
DUE="$MUT/ft-nano-close-due.sh" AUTO=1 run --all --why; OM="$OUT"
case "$OM" in *"닫기 차례 $SEAT"*) ok "M1 변이 → ⓒ 가 닫기 차례(대조가 실제로 잡고 있었다 = 변이 FAIL 유도)";; *) bad "M1 변이에서도 ⓒ 가 안 열림 — 변이 무의미";; esac

echo "== ⓕ 닫기 금지 — WORKING · 도구 셸/미제출 입력 · 미커밋 · 판정 불가"
new_root; seat_repo; card "- 세트: $H" "$(verdict APPROVE "$H")"
bash "$BIN/ft-nano-accept.sh" "$ROOT/design/teams/harness/indices/진행/ok.md" "$H" "검증=arch" --by m >/dev/null 2>&1
printf 'WORKING 2026-11-11T01:00:00 - - jsonl\n' > "$T/ss/$SEAT"
AUTO=1 run --all --why; has "$OUT" "제외 $SEAT 상태 WORKING" "ⓕ WORKING → 닫기 0"
printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"
FAKE_QUIET="BUSY 도구 셸 실행" AUTO=1 run --all --why; has "$OUT" "제외 $SEAT 도구 셸 실행" "ⓕ 도구 셸 실행 → 닫기 0"
FAKE_QUIET="BUSY 미제출 입력" AUTO=1 run --all --why; has "$OUT" "제외 $SEAT 미제출 입력" "ⓕ 미제출 입력 → 닫기 0"
FAKE_QUIET="BUSY pane 작업 중" AUTO=1 run --all --why; has "$OUT" "제외 $SEAT pane 작업 중" "ⓕ pane 작업 중 → 닫기 0"
echo dirty > "$T/wt/dirty.txt"; FAKE_QUIET=OK AUTO=1 run --all --why; has "$OUT" "제외 $SEAT 미커밋 1줄" "ⓕ 미커밋 1줄 → 닫기 0"
rm -f "$T/wt/dirty.txt"; mkdir -p "$T/wt/.serena"; echo noise > "$T/wt/.serena/project.yml"   # 미추적 잡음 한 줄(세트·HEAD 는 그대로)
AUTO=1 run --all --why; has "$OUT" "닫기 차례 $SEAT 팀=harness 갈래=승인" "ⓕ 잡음 .serena/project.yml 한 줄은 미커밋으로 안 센다"
FAKE_QUIET="BUSY 도구 셸 실행" run --approve-gate "$SEAT"   # ② AUTO=0 직접 재계산도 같은 닫기 금지
[ "$RC" -eq 1 ] && has "$OUT" "APPROVE-REJECT $SEAT 도구 셸 실행" "② 직접 --approve-gate 도 도구 셸이면 거절" || bad "② 직접 재계산 rc=$RC ← ${OUT:0:300}"
FAKE_QUIET="BUSY 미제출 입력" run --approve-gate "$SEAT"
[ "$RC" -eq 1 ] && has "$OUT" "미제출 입력" "② 직접 재계산 = 미제출 입력도 거절" || bad "② 미제출 rc=$RC"
FAKE_QUIET=OK run --approve-gate "$SEAT"; eq "$RC" "0" "② 조용하면 직접 재계산 rc0"
FAKE_QUIET="__RC9__" AUTO=1 run --all; eq "$RC" "3" "ⓕ 조용함 조회 실패 = rc3(판정 불가)"
has "$OUT" "판정 불가 $SEAT 조용함 조회 rc=9" "ⓕ 판정 불가 1줄(하드 룰 20)"

echo "== 변이 M4 — «승인 sha == HEAD» 정확 대조 삭제 → ① 사례가 안 잡힌다(변이 FAIL 기대)"
MUT4="$T/mut4"; mkdir -p "$MUT4"; cp "$BIN/ft_team_lib.py" "$MUT4/"
python3 - "$BIN/ft-nano-close-due.sh" "$MUT4/ft-nano-close-due.sh" <<'PY4'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
old = '    if shas.pop() != head: return False, f"DA 판정문의 승인 sha ≠ HEAD {head[:9]}(본문 언급만으로는 승인 0)"\n'
assert old in s, "M4 앵커 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, "", 1))
PY4
printf '단계별 초: 1\n\n## §1 판정: APPROVE\n\n승인 sha: %s\n\n후보: %s\n' "$M0" "$H" > "$ROOT/design/harness/DA-ok.md"
DUE="$MUT4/ft-nano-close-due.sh" AUTO=1 run --all --why; OM4="$OUT"
case "$OM4" in *"닫기 차례 $SEAT"*) ok "M4 변이 → 다른 sha 승인문으로도 닫기 차례(정확 대조가 잡고 있었다)";; *) bad "M4 변이에서도 닫기 차례 0 — 변이 무의미 ← ${OM4:0:300}";; esac

verdict APPROVE "$H"; card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $H · 남은 일: 검증=arch · 쓴 이: m"   # 변이 앞 상태 복구(앞 사례가 남긴 승인문 지움)
echo "== 변이 M3 — ⓕ 의 IDLE 확인 삭제 → WORKING 좌석이 닫기 차례로 열린다(변이 FAIL 기대)"
MUT3="$T/mut3"; mkdir -p "$MUT3"; cp "$BIN/ft_team_lib.py" "$MUT3/"
python3 - "$BIN/ft-nano-close-due.sh" "$MUT3/ft-nano-close-due.sh" <<'PY2'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
old = '            if _st != "IDLE": exc.append(f"제외 {k} 상태 {_st or \'-\'} (IDLE 아님)"); return None'
assert old in s, "M3 앵커 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, "", 1))
PY2
printf 'WORKING 2026-11-11T01:00:00 - - jsonl\n' > "$T/ss/$SEAT"; FAKE_QUIET=OK
DUE="$MUT3/ft-nano-close-due.sh" AUTO=1 run --all --why; OM3="$OUT"
case "$OM3" in *"닫기 차례 $SEAT"*) ok "M3 변이 → WORKING 좌석이 닫기 차례(IDLE 확인이 실제로 잡고 있었다)";; *) bad "M3 변이에서도 닫기 차례 0 — 변이 무의미 ← ${OM3:0:300}";; esac
printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"

verdict APPROVE "$H"; card "- 세트: $H" "$(printf -- '- DA 판정: %s/design/harness/DA-ok.md#§1\n' "$ROOT")" "- 인수: $H · 남은 일: 검증=arch · 쓴 이: m"   # 변이 앞 상태 복구
echo "== 변이 M5 — ⓕ 를 «AUTO 만» 으로 되돌림 → ② 직접 재계산이 도구 셸을 못 본다(변이 FAIL 기대)"
MUT5="$T/mut5"; mkdir -p "$MUT5"; cp "$BIN/ft_team_lib.py" "$MUT5/"
python3 - "$BIN/ft-nano-close-due.sh" "$MUT5/ft-nano-close-due.sh" <<'PY5'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
old = '    if AUTO or GATE:   # ⓕ 닫기 금지'
assert old in s, "M5 앵커 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, '    if AUTO:   # ⓕ 닫기 금지', 1))
PY5
FAKE_QUIET="BUSY 도구 셸 실행" DUE="$MUT5/ft-nano-close-due.sh" run --approve-gate "$SEAT"; OM5="$OUT"
case "$OM5" in *APPROVE-OK*) ok "M5 변이 → 직접 재계산이 도구 셸을 무시(공통 검사가 잡고 있었다)";; *) bad "M5 변이에서도 거절 — 변이 무의미 ← ${OM5:0:300}";; esac

echo "== 결과: FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
