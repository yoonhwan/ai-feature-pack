#!/usr/bin/env bash
# test_fp_allow_path.sh — R105-a: 훅 오탐 «기록 + 허용» 경로 시험.
# ①판정기 mbox_ok 가 «루트 정본 mbox» 를 워크트리 cwd 에서도 인정(realpath 일치만) ②래퍼 ft-fp-run.sh.
# 명령은 전부 PreToolUse JSON 문자열(실행 0) · 래퍼 시험만 임시 폴더의 무해한 echo 를 실제 실행 · 홈 훅·실 로그 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
HOOKDIR="$ROOT/harness/kit/fable-team/templates/hooks"
HOOK="${BD_HOOK:-$HOOKDIR/block-destructive.sh}"
WRAP="${FP_WRAP:-$ROOT/harness/bin/ft-fp-run.sh}"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
R="$(cd "$T" && pwd -P)/root"
git init -q "$R" && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R/.fable-team/comm"; : > "$R/.fable-team/comm/mbox.sh"
MB="$R/.fable-team/comm/mbox.sh"
git -C "$R" worktree add -q "$R/.worktrees/w1" -b w1 2>/dev/null     # W1: 사본 없음
git -C "$R" worktree add -q "$R/.worktrees/w2" -b w2 2>/dev/null     # W2: 실파일 사본
git -C "$R" worktree add -q "$R/.worktrees/w3" -b w3 2>/dev/null     # W3: 루트 정본 심링크
W1="$R/.worktrees/w1"; W2="$R/.worktrees/w2"; W3="$R/.worktrees/w3"
mkdir -p "$W2/.fable-team/comm" "$W3/.fable-team/comm"
: > "$W2/.fable-team/comm/mbox.sh"; ln -s "$MB" "$W3/.fable-team/comm/mbox.sh"
fail=0; n=0

run() {  # <HOOK> <명령> <cwd> → 훅 종료코드
  python3 -c 'import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$2" "$3" | /bin/bash "$1" >/dev/null 2>&1
}
want() {  # <기대 rc> <이름> <명령> <cwd> [HOOK]
  local rc; run "${5:-$HOOK}" "$3" "$4"; rc=$?; n=$((n+1))
  if [ "$rc" = "$1" ]; then echo "PASS [$2] rc=$rc"; else echo "FAIL [$2] want=$1 got=$rc :: ${3:0:90}"; fail=$((fail+1)); fi
}
BODY='워크트리 정리: git worktree remove /x · rm -rf /tmp/y · git branch -D z'

# ── ① 판정기: 루트 정본 mbox 절대경로 ──────────────────────────────
want 0 "a 워크트리 cwd · 루트 정본 절대경로 send · 파괴 글자 본문" "bash $MB send to from \"$BODY\"" "$W1"
want 0 "b 워크트리 cwd · cd 뒤에도 절대경로 정본" "cd $W1 && bash $MB send to from \"$BODY\"" "$W1"
want 2 "c 워크트리 실파일 사본(realpath≠루트) → 전체 검사" "bash $W2/.fable-team/comm/mbox.sh send to from \"$BODY\"" "$W2"
want 0 "c2 워크트리 심링크 사본(realpath=루트) → 인정" "bash $W3/.fable-team/comm/mbox.sh send to from \"$BODY\"" "$W3"
want 0 "d0 상대경로 · cd 없음 · cwd=comm" "bash ./mbox.sh send to from \"$BODY\"" "$R/.fable-team/comm"
want 2 "d cd /tmp 뒤 상대경로(R64 유지)" "cd /tmp && bash ./mbox.sh send to from \"$BODY\"" "$R/.fable-team/comm"
want 2 "d2 cd /tmp 뒤 다른 파일 절대경로(.. 포함)는 거부" "bash $R/.fable-team/../x/mbox.sh send to from \"$BODY\"" "$W1"
want 2 "d3 진짜 파괴(send 아님)는 그대로 차단" "bash $MB send to from hi; git worktree remove $W1" "$W1"
want 0 "g1 cwd 가 git 밖(/tmp 꼴) · 루트 정본 절대경로" "bash $MB send to from \"$BODY\"" "$T"
want 0 "g2 cwd 가 없는 폴더 · 루트 정본 절대경로" "bash $MB send to from \"$BODY\"" "$T/nonexistent"
want 2 "g3 git 밖 cwd · 상대경로는 여전히 거부" "bash ./mbox.sh send to from \"$BODY\"" "$T"
mkdir -p "$T/fake/.fable-team/comm"; : > "$T/fake/.fable-team/comm/mbox.sh"
want 2 "g4 git 밖 cwd · 리포가 아닌 곳의 mbox.sh 는 거부" "bash $T/fake/.fable-team/comm/mbox.sh send to from \"$BODY\"" "$T"
# ── 오늘 막힌 본문 꼴 3종 ─────────────────────────────────────────
want 0 "e1 쪽지 본문(워크트리 정리 글자) · 워크트리 cwd" "bash $MB send 'byz-harness-master-claude#59' 'byz-x#0' \"스크래치 워크트리 남김 — 닫을 때 git worktree remove 정리 부탁\"" "$W1"
want 0 "e2 쪽지 본문(집행 요청 · 커밋만) · 워크트리 cwd" "bash $MB send master me \"[집행 요청 60] 커밋만(push 0). 정리: rm -rf scratch · git branch -D tmp 은 HIL\"" "$W1"
want 0 "e3 카드 heredoc 본문(시험 예문 글자)" "cat > $W1/card.md <<'EOF'
시험 예문: git worktree remove x · rm -rf /tmp/y
EOF" "$W1"

# ── ② 래퍼 ft-fp-run.sh ──────────────────────────────────────────
export FT_FP_LOG="$T/fp.log" FT_FP_RUN_DIR="$T/fp-run" FT_FP_HOOK="$HOOK" FT_SEND_FROM="test-seat#0"
wrap() { bash "$WRAP" "$@" >"$T/wrap.out" 2>&1; }
chk() {  # <기대 rc> <이름> <실제 rc>
  n=$((n+1)); if [ "$3" = "$1" ]; then echo "PASS [$2] rc=$3"; else echo "FAIL [$2] want=$1 got=$3"; fail=$((fail+1)); fi
}
F1="$T/ok.sh"; printf '%s\n' "echo 'git worktree remove x  rm -rf /y'" 'echo done > "$FT_FP_OUT"' > "$F1"
export FT_FP_OUT="$T/out1"; wrap --file "$F1" "글자만 오탐 시험"; rc=$?
chk 0 "f1 글자만(echo 인자) → 실행" "$rc"
[ -s "$T/out1" ] && chk 0 "f1b 실행 흔적" 0 || chk 0 "f1b 실행 흔적" 1
lines=$(wc -l < "$FT_FP_LOG" 2>/dev/null | tr -d " " || echo 0); chk 1 "f1c 로그 1줄" "$lines"
grep -q "test-seat#0" "$FT_FP_LOG" && grep -q "글자만 오탐 시험" "$FT_FP_LOG" && grep -q "$F1" "$FT_FP_LOG" && c=0 || c=1; chk 0 "f1d 로그에 seat·사유·경로" "$c"
mkdir -p "$T/stub"; printf '#!/bin/sh\necho ran > "$FT_FP_OUT2"\n' > "$T/stub/pkill"; chmod +x "$T/stub/pkill"   # 무해 스텁 — 실제 pkill/git 파괴 명령은 어디서도 실행되지 않는다
F2="$T/bad.sh"; printf '%s\n' 'pkill -f nonexistent-x' > "$F2"
export FT_FP_OUT2="$T/out2"; export PATH="$T/stub:$PATH"; wrap --file "$F2" "진짜 파괴 시험"; rc=$?
chk 3 "f2 실행 자리 파괴 → 거부 rc 3" "$rc"
[ ! -e "$T/out2" ] && chk 0 "f2b 실행 0" 0 || chk 0 "f2b 실행 0" 1
lines=$(wc -l < "$FT_FP_LOG" | tr -d " "); chk 2 "f2c 거부도 로그 1줄 추가" "$lines"
wrap --file "$T/nope.sh" "사유"; chk 2 "f3 파일 없음 rc 2" "$?"
wrap --file "$F1"; chk 2 "f4 사유 없음 rc 2" "$?"
rm -f "$T/out1"; wrap "인라인 시험" -- echo "git worktree remove x"; rc=$?
chk 0 "f5 -- 인라인 입구(글자만) → 실행" "$rc"
ls "$FT_FP_RUN_DIR"/*.sh >/dev/null 2>&1 && c=0 || c=1; chk 0 "f5b 기록 폴더에 명령 파일" "$c"
rm -f "$T/out1"; FT_FP_LOG="$T" wrap --file "$F1" "로그 경로가 디렉터리"; chk 5 "f6 로그 기록 실패 → rc 5" "$?"
[ ! -e "$T/out1" ] && chk 0 "f6b 기록 실패면 실행 0" 0 || chk 0 "f6b 기록 실패면 실행 0" 1
before=$(wc -l < "$FT_FP_LOG" | tr -d " "); wrap --file "$F1" "첫줄
둘째줄"; chk 2 "f7 사유에 개행 → rc 2" "$?"
chk 0 "f7b 개행 사유는 로그 줄 수 불변" "$([ "$(wc -l < "$FT_FP_LOG" | tr -d " ")" = "$before" ] && echo 0 || echo 1)"

# ── 변이 대조 ─────────────────────────────────────────────────────
M="$T/mut"; mkdir -p "$M/hook" "$M/bin"; cp "$HOOKDIR"/block-destructive*.* "$M/hook/"
sed -i.bak 's/ and os.path.realpath(os.path.join(cwd or ".", path)) == want$/ and True/' "$M/hook/block-destructive-judge.py"
cmp -s "$M/hook/block-destructive-judge.py" "$HOOKDIR/block-destructive-judge.py" && { echo "FAIL [변이1 적용 안 됨]"; fail=$((fail+1)); }
want 0 "변이1 realpath 비교 제거 → c(실파일) 가 통과(= 빨강 확인)" "bash $W2/.fable-team/comm/mbox.sh send to from \"$BODY\"" "$W2" "$M/hook/block-destructive.sh"
cp "$WRAP" "$M/bin/ft-fp-run.sh"
sed -i.bak 's/^recheck_rc=.*/recheck_rc=0 # MUTANT/' "$M/bin/ft-fp-run.sh"
cmp -s "$M/bin/ft-fp-run.sh" "$WRAP" && { echo "FAIL [변이2 적용 안 됨]"; fail=$((fail+1)); }
rm -f "$T/out2"; bash "$M/bin/ft-fp-run.sh" --file "$F2" "변이2" >/dev/null 2>&1; rc=$?
chk 0 "변이2 PATTERN 재검사 제거 → f2 가 실행됨(rc 0 = 빨강 확인)" "$rc"
cp "$WRAP" "$M/bin/ft-fp-run3.sh"; sed -i.bak 's/^note ALLOW || .*$/note ALLOW # MUTANT/' "$M/bin/ft-fp-run3.sh"
cmp -s "$M/bin/ft-fp-run3.sh" "$WRAP" && { echo "FAIL [변이3 적용 안 됨]"; fail=$((fail+1)); }
rm -f "$T/out1"; FT_FP_LOG="$T" bash "$M/bin/ft-fp-run3.sh" --file "$F1" "변이3" >/dev/null 2>&1; rc=$?
chk 0 "변이3 기록 실패 전제 제거 → f6 이 실행됨(rc 0 = 빨강 확인)" "$rc"

echo "total=$n fail=$fail"
[ "$fail" = 0 ]
