#!/usr/bin/env bash
# test_card_assign_lint_undecided_r1250.sh — r1250 카드 배정 줄 검사의 git 실패(시간 초과·rc≠0) = «판정 불가» 1줄 rc3(트레이스백 0) · ft-index-lint 는 rc3 = WARN+진행 · 위반 rc1 = REJECT 그대로.
# 반례 R1~R5 + 변이 2. 임시 git 리포 · 가짜 git(PATH 앞 · 배정 검사의 `log … --format=%ct` 호출 «만» 지연/실패 · 그 밖은 실 git 절대경로로 exec 위임 — 대응표 검사 git 은 지연 0)
# · 실 STATE·실 좌석·네트워크 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0(지연은 가짜 git 안 1호출 · 예산 1초 env).
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_lint_undecided_r1250.sh
[ -z "${R1250_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1250_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1250_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_ASSIGN_GIT_TIMEOUT FT_DIRECTIVE_GIT_SEC FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; TOOL="$BIN/ft_card_assign_watch.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
NOW=$(date +%s); H=design/harness/indices; REALGIT="$(command -v git)"
gc() { GIT_AUTHOR_DATE="$2 +0900" GIT_COMMITTER_DATE="$2 +0900" "$REALGIT" -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
# 가짜 git — FG_MODE=log_delay(배정 검사 log 지연) · rev_delay(installed_at 의 `-C <폴더> rev-parse --git-common-dir` 만 지연 · 도구 import 시 루트 판정용 rev-parse 는 실 git) · log_rc(배정 검사 log rc128) · 그 밖 전부 실 git
mkdir -p "$T/fg"; printf '#!/bin/sh\nargs="$*"\ncase "$args" in\n  *--diff-filter=A*--format=%%ct*) case "${FG_MODE:-}" in log_delay) exec sleep 5;; log_rc) exit 128;; esac;;\n  *rev-parse*--git-common-dir*) [ "${FG_MODE:-}" = rev_delay ] && [ "$1" = -C ] && exec sleep 5;;\nesac\nexec "%s" "$@"\n' "$REALGIT" > "$T/fg/git"; chmod 755 "$T/fg/git"
new_root() {  # R = git 리포(main) + 대기·진행 폴더 · 가짜 installed_at = NOW−5000
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign" "$R/$H/대기" "$R/$H/진행"
  "$REALGIT" -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; "$REALGIT" -C "$R" add .gitignore; gc "$R" "$((NOW - 200000))" init
  echo "$((NOW - 5000))" > "$R/.fable-team/state/card-assign/installed_at"
}
add() {  # <상대경로> <커밋 epoch> — 배정 줄 없는 카드 추가 커밋
  mkdir -p "$(dirname "$R/$1")"; printf '# 카드\n- 상태: 대기\n## 상태\n- 시험\n' > "$R/$1"; "$REALGIT" -C "$R" add "$1"; gc "$R" "$2" "add $1"
}
lint() {  # <모드> <카드 상대경로> — stdout = OUT · stderr = ERR · rc = RC (예산 env 1초)
  OUT="$(cd "$R" && env PATH="$T/fg:$PATH" FG_MODE="$1" FT_ROOT="${LROOT-$R}" FT_DIRECTIVE_GIT_SEC="${BUDGET:-1}" python3 "${TOOL_RUN:-$TOOL}" lint "$R/$2" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
}
ixl() {  # <모드> <카드 상대경로> [키트 디렉터리] — ft-index-lint 전체(가짜 git) · IXOUT · IXRC
  IXOUT="$(cd "$R" && env PATH="$T/fg:$PATH" FG_MODE="$1" FT_ROOT="$R" FT_DIRECTIVE_GIT_SEC=1 FT_GOAL_LEDGER=.gitignore bash "${3:-$KIT}/ft-index-lint.sh" "$2" 2>&1)"; IXRC=$?
}
one() { [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ]; }
tb() { printf '%s%s' "$OUT" "$ERR" | grep -q Traceback; }

# R1 — 배정 검사 log 만 예산+ 지연 → rc3 · stdout 1줄 · stderr 0 · ft-index-lint = WARN 1줄(배정 REJECT 0 · 대응표 !TIMEOUT 0)
new_root; add "$H/대기/n.md" "$((NOW - 200))"; lint log_delay "$H/대기/n.md"
[ "$RC" = 3 ] && one && printf '%s' "$OUT" | grep -q '^배정 줄 검사 판정 불가 — git log 1초 초과 · ' && [ -z "$ERR" ] && ! tb && r1a=1 || r1a=0
ixl log_delay "$H/대기/n.md"
printf '%s\n' "$IXOUT" | grep -q '^WARN .*n\.md — 배정 줄 검사 판정 불가 — git log 1초 초과' && ! printf '%s\n' "$IXOUT" | grep -qE '^  - .*배정|TIMEOUT|Traceback' && r1b=1 || r1b=0
[ "$r1a$r1b" = 11 ] && ok "R1 배정 검사 log 지연 → rc3 · 1줄 · stderr 0 · ft-index-lint WARN 1줄(배정 REJECT 0 · 대응표 !TIMEOUT 0)" || bad "R1 a=$r1a b=$r1b rc=$RC :: $OUT :: $ERR :: $IXOUT"
lap R1
# R2 — FT_ROOT 해제 환경 rev-parse 지연 → rc3 «git rev-parse 1초 초과» · 트레이스백 0 · (대조) 리포 아님 정상 실패 rc≠0 = 옛대로 미설치 rc0
LROOT= ; lint rev_delay "$H/대기/n.md"; LROOT="$R"
[ "$RC" = 3 ] && one && printf '%s' "$OUT" | grep -q '^배정 줄 검사 판정 불가 — git rev-parse 1초 초과 · ' && [ -z "$ERR" ] && ! tb && r2a=1 || r2a=0
mkdir -p "$T/plain/$H/대기"; printf '# p\n- 상태: 대기\n## 상태\n' > "$T/plain/$H/대기/p.md"
OUT="$(cd "$R" && env FT_ROOT= PATH="$T/fg:$PATH" FG_MODE= FT_DIRECTIVE_GIT_SEC=1 python3 "$TOOL" lint "$T/plain/$H/대기/p.md" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && r2b=1 || r2b=0
[ "$r2a$r2b" = 11 ] && ok "R2 FT_ROOT 없이 rev-parse 지연 → rc3 · 1줄 · 트레이스백 0 · (대조) 리포 아님 rc≠0 → 옛 미설치 rc0" || bad "R2 a=$r2a b=$r2b :: $OUT :: $ERR"
lap R2
# R3 — 배정 검사 git log rc≠0(가짜 128) → rc3 «git log rc=128» (옛 rc1 → 위반과 분리)
new_root; add "$H/대기/n.md" "$((NOW - 200))"; lint log_rc "$H/대기/n.md"
[ "$RC" = 3 ] && one && printf '%s' "$OUT" | grep -q '^배정 줄 검사 판정 불가 — git log rc=128 · ' && [ -z "$ERR" ] && ! tb && ok "R3 git log rc=128 → rc3 · 1줄 (위반 rc1 과 분리)" || bad "R3 rc=$RC :: $OUT :: $ERR"
lap R3
# R4 — 위반은 그대로: 값 꼴 위반 rc1 · 새 카드 배정 줄 없음 rc1 · ft-index-lint bad(REJECT) 그대로
new_root; printf '# b\n- 배정: 아무거나\n## 상태\n' > "$R/$H/대기/b.md"; add "$H/대기/n.md" "$((NOW - 200))"
lint "" "$H/대기/b.md"; v1="$RC:$(printf '%s' "$OUT" | grep -c '값 꼴')"; lint "" "$H/대기/n.md"; v2="$RC:$(printf '%s' "$OUT" | grep -c '줄 없음 (새 카드 의무')"
ixl "" "$H/대기/b.md"; x1="$(printf '%s\n' "$IXOUT" | grep -c '^  - .*값 꼴')"; ixl "" "$H/대기/n.md"; x2="$(printf '%s\n' "$IXOUT" | grep -c '^  - .*줄 없음 (새 카드 의무')"
[ "$v1|$v2|$x1" = "1:1|1:1|1" ] && [ "$x2" -ge 1 ] && ok "R4 값 꼴 위반 rc1 · 새 카드 줄 없음 rc1 · ft-index-lint bad 그대로(REJECT)" || bad "R4 $v1|$v2|$x1|$x2"
lap R4
# R5 — 실제 ft-nano-spawn --dry-run(가짜 git · 배정 검사 log 만 지연) → WARN 1줄 뒤 dry-run 이 계속(차단 0) · 예산 30(= 지연보다 큼)이면 WARN 0 + 정상 판정(새 카드 → REJECT)
. "$HERE/lib/fake_resource_env.sh"; . "$HERE/lib/fake_tmm.sh"
SP="$T/sp"; KB="$SP/bin"; FK="$SP/fake"; mkdir -p "$SP" "$FK"; cp -R "$KIT" "$KB"; fake_resource_env "$SP" ok; fake_tmm "$FK" byz-alpha-master-claude#1
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s/sess 2>/dev/null;; has-session) exit 1;; *) exit 1;; esac\n' "$SP" > "$FK/tmux"; : > "$SP/sess"
printf '#!/bin/sh\necho "{\\"number\\":5342,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/x/y/issues/5342\\",\\"labels\\":[]}"\n' > "$FK/gh"; chmod 755 "$FK"/*
printf '## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| nano | 상한 N | `sonnet-5-5` | high | — | a | b |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 2 | 0 | 상시 |\n' > "$SP/TEAMSET.md"
SR="$SP/repo"; "$REALGIT" init -q -b main "$SR"; mkdir -p "$SR/.fable-team/state/card-assign" "$SR/.fable-team/comm" "$SR/design/alpha/indices/대기" "$SR/src"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$SR/.fable-team/state/all-stop.log"; echo '{"_name":"alpha","_master":"byz-alpha-master-claude#1","byz-alpha-master-claude#1":{"role":"master"}}' > "$SR/.fable-team/seats-alpha.json"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| alpha | `design/alpha/` | a | 현역 |\n' > "$SR/design/TEAMS.md"; printf 'l1\n' > "$SR/src/t.sh"; printf '골 1\n골 2\n골 3\n' > "$SP/goal.txt"
echo '원장: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$SR/design/LEDGER.md"; printf '.fable-team/\n' > "$SR/.gitignore"; echo "$((NOW - 5000))" > "$SR/.fable-team/state/card-assign/installed_at"
card_body() { printf '%s\n' '# 인덱스: y' '- 제안서: 없음 — 시험 카드' '- Issue: #5342' "$@" '## 골 원문' '골 1' '골 2' '골 3' '## 골좌표' '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '## 배경' '시험.' '## 구현 범위' '1. src/t.sh 수정' '## 완료 조건' '- 시험.' '## 계약↔시험 대응표' '| 계약 | 시험 |' '|---|---|' '| ① 시험 | ⓐ 시험 |' '## 상태' '- 시험'; }
CY="$SR/design/alpha/indices/대기/y.md"; card_body > "$CY"
"$REALGIT" -C "$SR" add -A; gc "$SR" "$((NOW - 200))" cards; echo y > "$SR/src/t.sh"; "$REALGIT" -C "$SR" add -A; gc "$SR" "$((NOW - 100))" base
"$REALGIT" clone -q --bare "$SR" "$SP/origin.git"; "$REALGIT" -C "$SR" remote add origin "$SP/origin.git"; "$REALGIT" -C "$SR" fetch -q origin
printf '#!/bin/bash\necho "RECLAIMED 0"\n' > "$SP/reclaim.sh"; chmod 755 "$SP/reclaim.sh"; printf '#!/bin/sh\necho "$2" >> %s/mbox.sent; echo "QUEUED seq=1 to=$2"\n' "$SP" > "$SP/mbox.sh"; chmod 755 "$SP/mbox.sh"
sp() {  # <카드> <모드> <예산> — 실제 ft-nano-spawn --dry-run
  ( cd "$SR" && export FT_ROOT="$SR" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$SR/.fable-team/seats-alpha.json" FT_TEAMSET_MD="$SP/TEAMSET.md" FT_RECLAIM_SH="$SP/reclaim.sh" \
    FT_MBOX_SH="$SP/mbox.sh" FT_GH_READ="$FK/gh" FT_GOAL_LINES_FILE="$SP/goal.txt" FT_GOAL_LEDGER=design/LEDGER.md FG_MODE="$2" FT_DIRECTIVE_GIT_SEC="$3" GH_REPO=x/y && PATH="$T/fg:$FK:$PATH" bash "$KB/ft-nano-spawn.sh" "$1" --from byz-alpha-master-claude#1 --dry-run 2>&1 ); }
o1="$(sp "$CY" log_delay 1)"; o2="$(sp "$CY" "" 30)"
w1="$(printf '%s\n' "$o1" | grep -c 'WARN .*배정 줄 검사 판정 불가 — git log 1초 초과')"; rj="$(printf '%s\n' "$o1" | grep -cE '^REJECT|REJECT lint|Traceback')"
w2="$(printf '%s\n' "$o2" | grep -c '배정 줄 검사 판정 불가')"; pl="$(printf '%s\n' "$o1" | grep -c '^PLAN ')"; n2="$(printf '%s\n' "$o2" | grep -c '줄 없음 (새 카드 의무')";
[ "$w1" = 1 ] && [ "$rj" = 0 ] && [ "$pl" -ge 1 ] && [ "$w2" = 0 ] && [ "$n2" -ge 1 ] && ok "R5 spawn --dry-run — 배정 검사 지연 → WARN 1줄 뒤 차단 0 · 예산 30 → WARN 0 + 새 카드 REJECT(검사 생략과 구별)" || bad "R5 w1=$w1 rj=$rj pl=$pl w2=$w2 n2=$n2 :: o1=$(printf '%s' "$o1" | tail -4) :: o2=$(printf '%s' "$o2" | tail -4)"
lap R5

# ── 변이 2 (그 칸만 다시 돈다)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mkdir -p "$T/m1"; cp "$BIN"/ft_*.py "$T/m1/"
mut "$TOOL" "$T/m1/ft_card_assign_watch.py" '    except Undecided as e:  # r1250' '    except KeyError as e:  # r1250'
new_root; add "$H/대기/n.md" "$((NOW - 200))"; TOOL_RUN="$T/m1/ft_card_assign_watch.py" lint log_delay "$H/대기/n.md"
[ "$RC" != 3 ] && tb && ok "변이1(lint 의 Undecided except 제거) → R1 빨강(트레이스백 · rc3 아님)" || bad "변이1 이 R1 에 안 잡힘 rc=$RC :: $OUT :: $ERR"
cp -R "$KIT" "$T/m2"; mut "$KIT/ft-index-lint.sh" "$T/m2/ft-index-lint.sh" '3) echo "WARN $f — ${al:-배정 줄 검사 판정 불가}";;' '3) bad+=("${al:-판정 불가}");;'
new_root; add "$H/대기/n.md" "$((NOW - 200))"; ixl log_delay "$H/대기/n.md" "$T/m2"
printf '%s\n' "$IXOUT" | grep -qE '^  - .*배정 줄 검사 판정 불가' && ! printf '%s\n' "$IXOUT" | grep -q '^WARN .*배정 줄 검사 판정 불가' && ok "변이2(ft-index-lint 가 rc3 을 bad 로) → R1·R5 빨강(WARN 대신 REJECT 항목 · spawn 차단)" || bad "변이2 가 R1 에 안 잡힘 :: $IXOUT"
lap mutation

# bin·kit 같은 판 · 문법
cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit ft_card_assign_watch.py 같은 내용" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && bash -n "$KIT/ft-index-lint.sh" && ok "py_compile · bash -n" || bad "문법"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
