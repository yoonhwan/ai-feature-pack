#!/usr/bin/env bash
# test_merge_land.sh — ft-merge-land.sh 착지 시험 (R230 교정 2 H1 · 임시 origin+clone · gh 는 스텁 · 실 gh·실 원격 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/shim" "$T/.fable-team"
REAL_GIT="$(command -v git)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac   # ft-gh-as-tank.sh 는 하이픈 동사만 받는다(R261)
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
cat > "$T/shim/git" <<EOF
#!/bin/bash
for a in "\$@"; do if [ "\$a" = commit-tree ] && [ -n "\${RACE_WT:-}" ] && [ ! -e "\$RACE_MARK" ]; then : > "\$RACE_MARK"; "$REAL_GIT" -C "\$RACE_WT" commit -q --allow-empty -m race && "$REAL_GIT" -C "\$RACE_WT" push -q origin HEAD:main; fi; done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gh-stub" "$T/shim/git"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> <브랜치> <시작점> <state> — PR head 를 origin refs/pull/N/head 에 올리고 스텁 JSON 작성
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":sys.argv[3],"baseRefName":"main"}))' "$PRSHA" "$1" "${4:-OPEN}" > "$STUB_JSON"
}
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
ZERO=0000000000000000000000000000000000000000

bash -n "$LAND"; ck "bash -n land" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
printf 'l1\nMAIN-LINE\nl2\nl3\n' > "$W/a.txt"; cm "$W" "main adds"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
M1="$(omain)"
mkpr 7 pr7 origin/main; P7="$PRSHA"

land 7; [ "$rc" = 1 ] && [[ "$out" == *"doc-exempt"* ]] && [ "$(omain)" = "$M1" ] && [ ! -s "$STUB_LOG" ]; ck "승인 값 없음 + 문서 아님 → rc1 REJECT(doc-exempt 아님) · main 불변 · PR 쓰기 0(R725)" $?
land 7 --approve-sha "$ZERO"; [ "$rc" = 1 ] && [[ "$out" == *"승인 sha"* ]] && [ "$(omain)" = "$M1" ]; ck "승인 sha != PR head → REJECT · main 불변" $?
mkpr 6 pr6 origin/main CLOSED; land 6 --approve-sha "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"OPEN 아님"* ]] && [ "$(omain)" = "$M1" ]; ck "PR 가 OPEN 아님 → REJECT" $?
mkpr 8 pr8 "$M0"; land 8 --approve-sha "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"게이트"* ]] && [[ "$out" == *"포함하지 않음"* ]] && [ "$(omain)" = "$M1" ]; ck "main 미포함 옛 세트 PR → 게이트 REJECT · main 불변" $?

# 검사 뒤 main 전진 → 서버 non-FF 거절(착지 0)
git -C "$T" clone -q "$ORIGIN" "$T/race"; git -C "$T/race" config user.name t; git -C "$T/race" config user.email t@t
mkpr 9 pr9 origin/main; P9="$PRSHA"
apv --approve-sha "$P9"; out="$(PATH="$T/shim:$PATH" RACE_WT="$T/race" RACE_MARK="$T/race.mark" bash "$LAND" 9 --approve-sha "$P9" --repo "$W" 2>&1)"; rc=$?
RACE="$(omain)"
[ "$rc" = 1 ] && [[ "$out" == *"non-FF"* ]]; ck "검사 뒤 main 이 움직임 → 서버 non-FF 거절 → REJECT" $?
[ "$RACE" != "$M1" ] && [ "$(git -C "$ORIGIN" log -1 --format=%s main)" = race ]; ck "착지 0 — origin main 은 경주 커밋 그대로(트리 어긋남 없음)" $?
[ ! -s "$STUB_LOG" ]; ck "거절이면 PR 코멘트·닫기 0" $?

# 정상 착지
git -C "$W" fetch -q origin; mkpr 11 pr11 origin/main; P11="$PRSHA"; M2="$(omain)"
land 11 --approve-sha "$P11"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "정상 착지 rc=0" $?
L="$(omain)"; [[ "$out" == *"sha=$L"* ]]; ck "출력 착지 sha == origin main" $?
[ "$(sha "$ORIGIN" "$L^{tree}")" = "$(sha "$W" "$P11^{tree}")" ]; ck "착지 트리 == 검사한 PR head 트리" $?
[ "$(sha "$ORIGIN" "$L^")" = "$M2" ] && [ "$(git -C "$ORIGIN" rev-list --parents -n1 "$L" | wc -w | tr -d ' ')" = 2 ]; ck "squash 1커밋(부모 = 검사 때 main 1개)" $?
git -C "$ORIGIN" log -1 --format=%B "$L" | grep -q 'PR #11' && git -C "$ORIGIN" log -1 --format=%B "$L" | grep -q 'feat: PR 11'; ck "메시지 = PR 제목·본문 + PR #11" $?
grep -q "^pr-close 11 --comment .*--apply :: 착지 sha $L" "$STUB_LOG" && ! grep -q BADVERB "$STUB_LOG"; ck "PR 11 에 착지 sha 코멘트 + 닫기(ft-gh-as-tank 하이픈 동사 pr-close --comment <파일> --apply · R261)" $?
grep -q "head=$P11 method=ft-merge-land .*landed=$L pr=11" "$T/state/merge-gate.log"; ck "결속 기록 1줄(main·head·방법·트리·착지)" $?

# R271: PR head fetch 가 auto gc 실패로 rc≠0 이어도 «fetch 실패» 로 오판하지 않는다 — 프로세스 한정 -c gc.auto=0 이 없으면 rc1 을 내는 shim
mkdir -p "$T/shim3"; printf '#!/bin/bash\nsaw=0; gc=0; for a in "$@"; do case "$a" in *pull/*/head*) saw=1;; gc.auto=0) gc=1;; esac; done\n"%s" "$@"; r=$?\n[ "$saw" = 1 ] && [ "$gc" = 0 ] && exit 1\nexit $r\n' "$REAL_GIT" > "$T/shim3/git"; chmod +x "$T/shim3/git"
git -C "$W" fetch -q origin; mkpr 12 pr12 origin/main; P12="$PRSHA"
apv --approve-sha "$P12"; out="$(PATH="$T/shim3:$PATH" bash "$LAND" 12 --approve-sha "$P12" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "fetch 에 -c gc.auto=0 — gc 실패 rc≠0 이어도 착지(R271)" $?

# 자율 ON — 승인 파일 없으면 실행 0 · approve-merge 뒤 착지
bash "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; git -C "$W" fetch -q origin; mkpr 10 pr10 origin/main; P10="$PRSHA"; M3="$(omain)"; : > "$STUB_LOG"
NOAP=1 land 10 --approve-sha "$P10"; [ "$rc" = 2 ] && [[ "$out" == *"approve-merge"* ]] && [ "$(omain)" = "$M3" ] && [ ! -s "$STUB_LOG" ]; ck "자율 ON · 승인 파일 없음 → rc2 · 실행 0" $?
bash "$BIN/ft-autonomy.sh" approve-merge "$P10" >/dev/null 2>&1
land 10 --approve-sha "$P10"; [ "$rc" = 0 ] && [ "$(omain)" != "$M3" ]; ck "자율 ON · approve-merge 승인 뒤 착지" $?

# R354: push 시도당 상한 = min(F + 7 × ceil(객체수/U0), 70) — 대역 timeout(push 인자 기록 · 시도별 결과 주입) + 대역 git(rev-list --objects 개수 주입)
SP="$T/shimP"; mkdir -p "$SP"; PLOG="$T/push.log"; PSEQ="$T/push.seq"; REAL_TO="$(command -v timeout)"
cat > "$SP/git" <<EOF
#!/bin/bash
r=0; o=0; for a in "\$@"; do [ "\$a" = rev-list ] && r=1; [ "\$a" = --objects ] && o=1; done
if [ "\$r\$o" = 11 ]; then
  [ -n "\${STUB_REVLIST_FAIL:-}" ] && { echo "fatal: stub rev-list fail" >&2; exit 128; }
  [ -n "\${STUB_OBJECTS:-}" ] && { seq 1 "\$STUB_OBJECTS"; exit 0; }
fi
exec "$REAL_GIT" "\$@"
EOF
cat > "$SP/timeout" <<EOF
#!/bin/bash
p=0; l=0; for a in "\$@"; do [ "\$a" = push ] && p=1; [ "\$a" = ls-remote ] && l=1; done
[ "\$l" = 1 ] && [ -n "\${STUB_LSREMOTE_FAIL:-}" ] && { echo "fatal: unable to access (stub)" >&2; exit 128; }
[ "\$p" = 1 ] || exec "$REAL_TO" "\$@"
echo "\$1" >> "$PLOG"; n="\$(wc -l < "$PLOG" | tr -d ' ')"; mode="\$(printf '%s' "\${PUSH_MODES:-ok}" | cut -d' ' -f"\$n")"; [ -n "\$mode" ] || mode=ok
[ -n "\${PUSH_SLEEP:-}" ] && [ "\$n" = 1 ] && sleep "\$PUSH_SLEEP"
case "\$mode" in
  rc124) exit 124;;
  conn) echo "ssh: connect to host github.com port 22: Operation timed out" >&2; echo "fatal: Could not read from remote repository." >&2; exit 128;;
  reject) echo " ! [rejected]        Q -> main (fetch first)" >&2; echo "error: failed to push some refs" >&2; exit 1;;
  nff) echo " ! [remote rejected] Q -> main (pre-receive hook declined)" >&2; exit 1;;
  other) echo "fatal: protocol error" >&2; exit 128;;
  afterland) shift; "\$@" >/dev/null 2>&1; echo "remote: Resolving deltas: 100% (3/3), done." >&2; echo "To stub-origin" >&2; exit 124;;   # 서버가 받아 ref 갱신 뒤 timeout
  reset) echo "remote: Counting objects" >&2; echo "fatal: the remote end hung up unexpectedly" >&2; echo "Connection reset by peer" >&2; exit 128;;   # 응답 후 단절(착지 0)
  *) shift; exec "\$@";;
esac
EOF
chmod +x "$SP/git" "$SP/timeout"
pland() {  # pland <PR> <env…> — 대역 PATH 로 착지 · 시도 기록 초기화(env 는 KEY=VAL 로 앞에 둔다)
  local pr="$1"; shift; : > "$PLOG"; git -C "$W" fetch -q origin; mkpr "$pr" "pr$pr" origin/main; local P="$PRSHA"; apv --approve-sha "$P"
  out="$(env PATH="$SP:$PATH" "$@" bash "$LAND" "$pr" --approve-sha "$P" --repo "$W" 2>&1)"; rc=$?
}
pb() { sed -n '1p' "$PLOG"; }   # 첫 push 시도의 timeout 인자
pland 21 STUB_OBJECTS=1; [ "$rc" = 0 ] && [ "$(pb)" = 11 ] && [[ "$out" == *"push ok objects=1 bound=11 attempt=11 took="* ]]; ck "ⓐ 객체 1 → bound 11 (4.5+7) · push ok 줄(bound=PB attempt=AB)" $?
pland 22 STUB_OBJECTS=390; [ "$rc" = 0 ] && [ "$(pb)" = 32 ] && [[ "$out" == *"push ok objects=390 bound=32 attempt=32 took="* ]]; ck "ⓑ 객체 390(#1859) → ceil(390/100)=4 → bound 32" $?
[ "$(. "$BIN/ft-merge-lib.sh"; fm_push_calc 5000 2>/dev/null)" = 70 ] && [ "$(. "$BIN/ft-merge-lib.sh"; fm_push_calc 900 2>/dev/null)" = 67 ]; ck "ⓒ 객체 5,000 → 4.5+350 → 70 클램프 · 900 → 67(fm_push_calc)" $?
pland 23 STUB_REVLIST_FAIL=1; [ "$rc" = 0 ] && [ "$(pb)" = 11 ] && [[ "$out" == *"objects=?"* ]] && [[ "$out" == *"WARN"* ]]; ck "ⓓ 객체 수 조회 실패 → F+7=11 호환값 + stderr WARN 1줄(조용한 통과 0)" $?
np() { wc -l < "$PLOG" | tr -d ' '; }   # push 시도 수
# DA⑥ H1 ⓗ — 재시도 = «서버 응답 전 연결 실패» 뿐 · timeout·reset·remote 출력은 불명 → 재시도 0 + ls-remote 1회로 착지됨/착지 0/불명 판정
MH="$(omain)"; pland 24 STUB_OBJECTS=1 PUSH_MODES="afterland ok"
[ "$rc" = 0 ] && [ "$(np)" = 1 ] && [ "$(omain)" != "$MH" ] && [[ "$out" == *"confirmed=ls-remote"* ]] && tail -n1 "$T/state/merge-gate.log" | grep -q 'push-confirmed=ls-remote'; ck "ⓗ1 응답 후 timeout(remote: 줄 뒤 rc124 · 원격 ref=Q) → 재시도 0 · ls-remote==Q → 착지됨 정상 종료" $?
MH="$(omain)"; pland 25 STUB_OBJECTS=1 PUSH_MODES="reset ok"
[ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(omain)" = "$MH" ] && [[ "$out" == *"착지 0 확정"* ]] && [[ "$out" == *"응답 불명"* ]]; ck "ⓗ2 응답 후 reset(remote: 줄 뒤) → 불명 · ls-remote==M → rej «착지 0 · 불명» · 재시도 0" $?
MH="$(omain)"; pland 32 STUB_OBJECTS=1 PUSH_MODES="rc124 ok"
[ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(omain)" = "$MH" ] && [[ "$out" == *"착지 0 확정"* ]]; ck "ⓗ2b remote 출력 0 인 rc124 도 불명 → 재시도 0(옛 ⓔ1 대체) · ls-remote==M → rej" $?
pland 26 STUB_OBJECTS=1 PUSH_MODES="conn ok"; [ "$rc" = 0 ] && [ "$(np)" = 2 ] && [ "$(sed -n 2p "$PLOG")" = 11 ]; ck "ⓗ3 응답 없음 연결 실패(remote: 0 · ssh timed out) → 재시도 1 후 착지 · 2차도 bound 11" $?
MH="$(omain)"; pland 34 STUB_OBJECTS=1 PUSH_MODES="rc124 ok" STUB_LSREMOTE_FAIL=1
[ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(omain)" = "$MH" ] && [[ "$out" == *"원격 상태 불명"* ]] && [[ "$out" != *"착지 0 확정"* ]]; ck "ⓗ4 불명 + ls-remote 실패 → rej «원격 상태 불명» · «착지 0 확정» 문구 0(조용한 통과 0)" $?
# ⓔ3: 1차가 시간을 먹어 남은 총 마감 < PB → 재시도 0 — main 기준값은 호출 «전» 캡처 · PB·AB·시도 수 명시 단언
ME="$(omain)"; pland 35 STUB_OBJECTS=1 FT_PUSH_FIXED_S=1 FT_LAND_TOTAL_S=14 PUSH_SLEEP=7 PUSH_MODES="conn ok"
[ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(pb)" = 8 ] && [ "$(omain)" = "$ME" ] && [[ "$out" == *"총 마감 14 s"* ]] && [[ "$out" != *"push ok"* ]]; ck "ⓔ3 PB=AB=8 · 1차 conn 실패 뒤 남은 < 8 → 시도 1 · 재시도 0 · main 불변(호출 전 캡처)" $?
# DA⑥ H2 ⓘ — PB(70) > 남은 시간 REM ≥ PV(11): 1차 timeout 인자 == REM(=AB) 로 절단
pland 33 STUB_OBJECTS=5000 FT_LAND_TOTAL_S=30; a="$(pb)"
[ "$rc" = 0 ] && [ "$(np)" = 1 ] && [ "$a" -ge 11 ] && [ "$a" -le 30 ] && [[ "$out" == *"push ok objects=5000 bound=70 attempt=$a took="* ]]; ck "ⓘ1 PB 70 > REM → 1차 timeout 인자 == REM(=AB $a) · 절단 성공 → 착지 · bound=70 attempt=AB" $?
MI="$(omain)"; pland 36 STUB_OBJECTS=5000 FT_LAND_TOTAL_S=30 PUSH_MODES="rc124 ok"; a="$(pb)"
[ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$a" -ge 11 ] && [ "$a" -lt 70 ] && [ "$(omain)" = "$MI" ] && [[ "$out" == *"총 마감 안에 끝내지 못함"* ]]; ck "ⓘ2 절단된 1차(AB $a) timeout → 재시도 조건 REM ≥ PB 거짓 → 시도 1 · rej «다음 틱» · main 불변" $?
pland 27 STUB_OBJECTS=1 PUSH_MODES="reject ok"; [ "$rc" = 1 ] && [ "$(wc -l < "$PLOG" | tr -d ' ')" = 1 ] && [[ "$out" == *"non-FF"* ]]; ck "ⓕ1 서버 거절(fetch first) → 재시도 0" $?
pland 28 STUB_OBJECTS=1 PUSH_MODES="nff ok"; [ "$rc" = 1 ] && [ "$(wc -l < "$PLOG" | tr -d ' ')" = 1 ]; ck "ⓕ2 pre-receive 거절 → 재시도 0" $?
pland 29 STUB_OBJECTS=1 PUSH_MODES="other ok"; [ "$rc" = 1 ] && [ "$(wc -l < "$PLOG" | tr -d ' ')" = 1 ] && [[ "$out" == *"push 실패"* ]]; ck "ⓕ3 분류 못 한 실패 → 재시도 0 + push 실패 REJECT" $?
pland 30 STUB_OBJECTS=1 FT_PUSH_FIXED_S=9; [ "$rc" = 0 ] && [ "$(pb)" = 14 ] && [[ "$out" == *"WARN"*"FT_PUSH_FIXED_S"* ]]; ck "ⓖ1 FT_PUSH_FIXED_S=9 → 7 로 클램프(bound 14) + WARN" $?
pland 31 STUB_OBJECTS=250 FT_PUSH_UNIT_OBJECTS=0; [ "$rc" = 0 ] && [ "$(pb)" = 25 ] && [[ "$out" == *"WARN"*"FT_PUSH_UNIT_OBJECTS"* ]]; ck "ⓖ2 FT_PUSH_UNIT_OBJECTS=0 → 기본 100(250객체=3단위 → 25) + WARN" $?
# R392 ⓘff — --ff: 승인 sha == PR head ∧ main 이 head 의 조상 → commit-tree 0 · push <HEAD>:refs/heads/main · 객체 0
SF="$T/shimF"; mkdir -p "$SF"; FLOG="$T/ff.log"; RCNT="$T/ff.rcnt"
cat > "$SF/git" <<EOF
#!/bin/bash
for a in "\$@"; do case "\$a" in commit-tree|push) echo "\$a \$*" >> "$FLOG";; esac; done
if [ -n "\${FF_RACE:-}" ] && [[ " \$* " == *" refs/remotes/origin/main^{commit} "* ]]; then   # 2번째(land 의 M 읽기 · 1번째 = 게이트) 직전에 main 전진 + 로컬 원격 ref 갱신
  echo x >> "$RCNT"; [ "\$(wc -l < "$RCNT" | tr -d ' ')" = 2 ] && "$REAL_GIT" -C "$T/race" commit -q --allow-empty -m ffrace && "$REAL_GIT" -C "$T/race" push -q origin HEAD:main && "$REAL_GIT" -C "$W" fetch -q origin
fi
exec "$REAL_GIT" "\$@"
EOF
printf '#!/bin/bash\necho "ICHK $*"\n' > "$SF/ichk"; chmod +x "$SF/git" "$SF/ichk"
fland() {  # fland <PR> <승인 sha|head> <env…> — 대역 PATH 로 --ff 착지 · 2커밋 PR(커밋 수 보존 확인용)
  local pr="$1" ap="$2"; shift 2; : > "$FLOG"; : > "$RCNT"; git -C "$W" fetch -q origin; FM="$(omain)"; mkpr "$pr" "pr$pr" origin/main
  echo two > "$W/pr$pr.b"; cm "$W" "pr $pr second"; git -C "$W" push -q origin "pr$pr:refs/pull/$pr/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["headRefOid"]=sys.argv[2];json.dump(d,open(sys.argv[1],"w"))' "$STUB_JSON" "$PRSHA"
  [ "$ap" = head ] && ap="$PRSHA"; apv --approve-sha "$ap"
  out="$(env PATH="$SF:$PATH" FT_INSTALL_CHECK="$SF/ichk" "$@" bash "$LAND" "$pr" --approve-sha "$ap" --ff --repo "$W" 2>&1)"; rc=$?
}
fland 40 head; F40="$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=40 sha=$F40 "*" mode=ff"* ]] && [ "$(omain)" = "$F40" ]; ck "ⓘff① 정상 → LANDED sha=HEAD mode=ff · origin main == PR head" $?
! grep -q '^commit-tree' "$FLOG" && grep -q "^push .* $F40:refs/heads/main" "$FLOG" && ! grep -q '^push .*+' "$FLOG"; ck "ⓘff① commit-tree 호출 0 · push refspec <HEAD>:refs/heads/main(non-force)" $?
[ "$(git -C "$ORIGIN" rev-list --count "$FM..main")" = 2 ] && ! git -C "$ORIGIN" log --format=%B "$FM..main" | grep -q 'PR #40'; ck "ⓘff① 커밋 수 보존(2) · squash 커밋 0" $?
tail -n1 "$T/state/merge-gate.log" | grep -q "head=$F40 method=ft-merge-land-ff tree=.* landed=$F40 pr=40"; ck "ⓘff① merge-gate.log method=ft-merge-land-ff · landed=HEAD" $?
[ "$(head -n1 "$T/.fable-team/state/base-head")" = "$F40" ] && [[ "$out" == *"ICHK --range $FM..$F40 --ref $F40 "* ]]; ck "ⓘff① base-head · install 검사 Q=HEAD(--range M..HEAD)" $?
[[ "$out" == *"push ok objects=0 bound=11 "* ]]; ck "ⓘff④ 전송 객체 0 → push ok objects=0 bound=11" $?
git -C "$T/race" fetch -q origin && git -C "$T/race" checkout -q -B main origin/main
fland 41 head FF_RACE=1; [ "$rc" = 1 ] && [[ "$out" == *"ff 불가"* ]] && [ "$(git -C "$ORIGIN" log -1 --format=%s main)" = ffrace ] && ! grep -q '^push' "$FLOG"; ck "ⓘff② 검사 뒤 main 전진(head 조상 아님) → push 전 REJECT · origin main = 경주 커밋 그대로" $?
: > "$PLOG"; MF="$(omain)"; fland 42 head PATH="$SP:$SF:$PATH" STUB_OBJECTS=1 PUSH_MODES="reject"
[ "$rc" = 1 ] && [[ "$out" == *"non-FF"* ]] && [ "$(wc -l < "$PLOG" | tr -d ' ')" = 1 ] && [ "$(omain)" = "$MF" ]; ck "ⓘff② 서버 non-FF 거절 스텁 → REJECT · 재시도 0 · main 불변" $?
MF="$(omain)"; fland 43 "$M1"; [ "$rc" = 1 ] && [[ "$out" == *"ff 는 승인 sha == PR head 만"* ]] && [[ "$out" != *EQUIV* ]] && ! grep -q '^push' "$FLOG" && [ "$(omain)" = "$MF" ]; ck "ⓘff③ 승인 sha != PR head → REJECT(equiv 경로 0) · push 0 · main 불변" $?
# ── r706 H4: PR head 는 개인 ref refs/ft-land/<PR> 로 받고 그 ref 를 읽는다 — 공용 FETCH_HEAD 읽기 0(다른 좌석 fetch 가 덮어도 남의 sha 를 읽지 않음) ──
refs() { git -C "$W" for-each-ref --format='%(refname)' refs/ft-land 2>/dev/null | tr '\n' ' '; }
git -C "$W" update-ref -d refs/ft-land/99 2>/dev/null   # 앞 칸(R271)에서 남은 다른 좌석 ref 정리 — 이 칸은 «다른 좌석 ref 99 만 있는» 상태로 시작
SX="$T/shimR"; mkdir -p "$SX"
intr() {  # intr() — 받는 중에 다른 좌석이 FETCH_HEAD 를 덮는 대역 git(끼어들 PR 번호 a b)
  cat > "$SX/git" <<EOF
#!/bin/bash
"$REAL_GIT" "\$@"; r=\$?
for a in "\$@"; do case "\$a" in *pull/$1/head*) "$REAL_GIT" -C "$W" fetch -q origin pull/$2/head; "$REAL_GIT" -C "$W" rev-parse FETCH_HEAD > "$T/fh.r706";; esac; done
exit \$r
EOF
  chmod +x "$SX/git"
}
! sed 's/#.*//' "$LAND" | grep -q 'FETCH_HEAD'; ck "① 착지 도구가 FETCH_HEAD 를 읽는 줄 0(grep)" $?
git -C "$W" fetch -q origin; mkpr 51 pr51 origin/main; P51="$PRSHA"; mkpr 50 pr50 origin/main; P50="$PRSHA"; intr 50 51
git -C "$W" update-ref refs/ft-land/99 "$P51"   # 다른 좌석의 개인 ref(지우면 안 됨)
apv --approve-sha "$P50"; out="$(PATH="$SX:$PATH" bash "$LAND" 50 --approve-sha "$P50" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "① 다른 좌석 fetch 가 FETCH_HEAD 를 덮어도 자기 PR head(개인 ref)로 착지" $?
[ "$(cat "$T/fh.r706" 2>/dev/null)" = "$P51" ]; ck "① (전제) PR 50 fetch 직후 공용 FETCH_HEAD = 남의 sha(PR 51)" $?
L50="$(omain)"; [ "$(sha "$ORIGIN" "$L50^{tree}")" = "$(sha "$W" "$P50^{tree}")" ]; ck "① 착지 트리 == PR 50 head 트리(남의 sha 섞임 0)" $?
[ "$(refs)" = "refs/ft-land/99 " ]; ck "② 성공 착지 뒤 개인 ref 잔여 0 · 다른 좌석 ref 99 는 그대로" $?
git -C "$W" fetch -q origin; mkpr 52 pr52 "$M0"; P52="$PRSHA"   # 옛 main 기준 → 게이트 거절
apv --approve-sha "$P52"; out="$(bash "$LAND" 52 --approve-sha "$P52" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(refs)" = "refs/ft-land/99 " ]; ck "② 거절(게이트) 뒤 개인 ref 잔여 0" $?
cat > "$SX/git" <<EOF
#!/bin/bash
for a in "\$@"; do case "\$a" in *pull/53/head*) "$REAL_GIT" "\$@"; exit 128;; esac; done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SX/git"   # ref 를 쓴 «뒤» 실패 — 부분 쓰기 잔여를 남기는 대역
git -C "$W" fetch -q origin; mkpr 53 pr53 origin/main; P53="$PRSHA"; apv --approve-sha "$P53"
out="$(PATH="$SX:$PATH" bash "$LAND" 53 --approve-sha "$P53" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"PR head fetch 실패"* ]]; ck "③ fetch 실패 → «PR head fetch 실패» 거절 그대로(R3)" $?
[ "$(refs)" = "refs/ft-land/99 " ]; ck "② fetch 실패 뒤 개인 ref 잔여 0(부분 쓰기 남김 0 · R3)" $?
git -C "$W" fetch -q origin; mkpr 54 pr54 origin/main; P54="$PRSHA"
git -C "$W" update-ref refs/ft-land/54 "$P51"   # 옛 실행 잔여(다른 sha)
apv --approve-sha "$P54"; out="$(bash "$LAND" 54 --approve-sha "$P54" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(sha "$ORIGIN" "$(omain)^{tree}")" = "$(sha "$W" "$P54^{tree}")" ]; ck "③ 옛 잔여 refs/ft-land/54 를 강제 갱신(+)으로 새 head 로 — 옛 sha 비교 0(R4)" $?
[ "$(refs)" = "refs/ft-land/99 " ]; ck "② R4 착지 뒤에도 잔여 0" $?
# 변이: 개인 ref 읽기를 FETCH_HEAD 로 되돌리면 ① 칸이 FAIL(시험의 검출력)
MB="$T/mutbin"; mkdir -p "$MB"; cp "$LAND" "$MB/ft-merge-land.sh"
for f in "$BIN"/*; do [ "$(basename "$f")" = ft-merge-land.sh ] || ln -sf "$f" "$MB/"; done
sed -i '' 's|refs/ft-land/\$PR^{commit}|FETCH_HEAD^{commit}|' "$MB/ft-merge-land.sh"
! cmp -s "$LAND" "$MB/ft-merge-land.sh"; ck "④ 변이본 적용(sed — 원본과 다름)" $?
git -C "$W" fetch -q origin; mkpr 57 pr57 origin/main; mkpr 56 pr56 origin/main; P56="$PRSHA"; intr 56 57   # 57 먼저(끼어들 좌석) · 56 마지막(STUB_JSON = PR 56)
apv --approve-sha "$P56"; out="$(PATH="$SX:$PATH" bash "$MB/ft-merge-land.sh" 56 --approve-sha "$P56" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" != *LANDED* ]] && [[ "$out" == *REJECT* ]]; ck "④ 변이(FETCH_HEAD 읽기)는 착지 0 — ① 칸 FAIL(시험 검출력)" $?
# ⑤ E1 — fetch 성공 뒤 총 마감 거절(deadline)처럼 «흐름 밖 출구»로 빠져도 EXIT trap 이 개인 ref 를 지운다
SE="$T/shimE"; mkdir -p "$SE"; asle() {  # asle - PR head fetch 가 2 초 느린 대역(총 마감 소진용)
  cat > "$SE/git" <<EOF
#!/bin/bash
for a in "\$@"; do case "\$a" in *pull/*/head*) sleep 2;; esac; done
exec "$REAL_GIT" "\$@"
EOF
  chmod +x "$SE/git"
}
asle; git -C "$W" fetch -q origin; mkpr 60 pr60 origin/main; P60="$PRSHA"; apv --approve-sha "$P60"
out="$(PATH="$SE:$PATH" FT_LAND_TOTAL_S=2 bash "$LAND" 60 --approve-sha "$P60" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"총 마감"* ]]; ck "⑤ E1 fetch 뒤 «총 마감» 거절(전제)" $?
[ "$(refs)" = "refs/ft-land/99 " ]; ck "② E1 총 마감 거절 뒤에도 개인 ref 잔여 0(EXIT trap — 흐름 밖 출구)" $?
# ⑥ E2 — ref 정리가 실패하면 착지«전»에 멈춘다(조용한 성공 0 · 사유 1줄)
cat > "$SE/git" <<EOF
#!/bin/bash
case "\$*" in *"update-ref -d refs/ft-land"*) echo "fatal: cannot lock ref 'refs/ft-land/61': File exists." >&2; exit 128;; esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SE/git"
git -C "$W" fetch -q origin; mkpr 61 pr61 origin/main; P61="$PRSHA"; M61="$(omain)"; apv --approve-sha "$P61"
out="$(PATH="$SE:$PATH" bash "$LAND" 61 --approve-sha "$P61" --repo "$W" 2>&1)"; rc=$?
[ "$rc" != 0 ] && [[ "$out" == *"개인 ref 정리 실패"* ]] && [[ "$out" != *LANDED* ]] && [ "$(omain)" = "$M61" ]; ck "⑥ E2 정리(update-ref -d) 실패 → 착지 0 · rc≠0 · 사유 1줄(조용한 성공 0)" $?
git -C "$W" update-ref -d refs/ft-land/61 2>/dev/null   # 대역이 못 지운 ref — 다음 칸 전 정리
git -C "$W" checkout -q -B main origin/main
# 변이: trap 등록(lr_trap)을 지우면 E1 칸(ref 잔여 0)이 FAIL
MB2="$T/mutbin2"; mkdir -p "$MB2"; cp "$LAND" "$MB2/ft-merge-land.sh"
for f in "$BIN"/*; do [ "$(basename "$f")" = ft-merge-land.sh ] || ln -sf "$f" "$MB2/"; done
sed -i '' 's/lr_trap; if /if /' "$MB2/ft-merge-land.sh"   # r1069: fetch 줄이 «lr_trap; if [지정] … else fm_fetch» 꼴이 됐다 — 변이 의도(EXIT trap 등록 삭제)는 그대로
! cmp -s "$LAND" "$MB2/ft-merge-land.sh"; ck "⑤ 변이본 적용(lr_trap 등록 삭제)" $?
asle; git -C "$W" fetch -q origin; mkpr 62 pr62 origin/main; P62="$PRSHA"; apv --approve-sha "$P62"
out="$(PATH="$SE:$PATH" FT_LAND_TOTAL_S=2 bash "$MB2/ft-merge-land.sh" 62 --approve-sha "$P62" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"총 마감"* ]] && [ -n "$(git -C "$W" for-each-ref refs/ft-land/62)" ]; ck "⑤ 변이(trap 없음)는 E1 칸(잔여 0)에서 FAIL — 시험 검출력" $?
git -C "$W" update-ref -d refs/ft-land/62 2>/dev/null
[ "$(refs)" = "refs/ft-land/99 " ]; ck "② E1·E2·변이 칸 뒤 잔여 0(다른 좌석 ref 99 만)" $?

! grep -vE '^\s*#' "$BIN/ft-merge-land.sh" "$BIN/ft-merge-lib.sh" | grep -qE '\b(600|300)\b'; ck "600·300 글자 0" $?
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
! grep -vE '^\s*#' "$LAND" | grep -qE 'git[^|]*(reset|rebase|--force|\+refs)|push[^|]*-f '; ck "정적: land 에 force·reset·rebase·+refspec 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
