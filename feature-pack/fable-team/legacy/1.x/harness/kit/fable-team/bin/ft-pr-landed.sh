#!/usr/bin/env bash
# ft-pr-landed.sh — r1800: «PR #N 이 main 에 착지했나» 판정 1곳(착지+설치 h · 사람 손이 같이 쓴다 · 읽기만 · 쓰기 = fetch ref 1개).
#   usage: ft-pr-landed.sh --repo <리포 루트> --pr <N> --set <승인 sha40> [--main origin/main] [--no-fetch]
#   출력 1줄: «LANDED <ff|squash|merged> pr=<N> landing=<sha>[ ref=local]» rc0 · «NOT-LANDED pr=<N>[ ref=local]» rc1 · «판정 불가: <사유>» rc3(그 밖 rc 0)
#   근거 순서(먼저 참인 것): ①ff = SET 이 main 의 조상 ②squash = main 최근 200 커밋 메시지에 «PR #<N> (head <SET>)» 줄이 정확히 1줄
#     (끝줄 아니어도 됨 · ft-merge-land 꼬리 «main 자동 병합(…) C=<S>» 가 뒤에 붙어도 됨 · head 는 SET 로만 맞춘다 = 낡은 세트 착지 0) · 2줄 이상 = rc3
#     ③merged = gh state=MERGED ∧ headRefOid == SET ∧ mergeCommit 이 main 의 조상 · gh 는 ③ 에서만(FT_GH = 시험 가짜 · 7초 + 재시도 1)
#   fetch: 판정 직전 «git fetch <원격> <가지>» 1회(7초 + 재시도 1 · 하드 룰 12) · 실패·시간 초과 = rc3(낡은 ref 로 NOT-LANDED 0) · --no-fetch = 호출자가 방금 받음(출력에 ref=local)
#   리포 = --repo 의 remote.origin.url 꼴(ssh «user@host:owner/repo» · https «http(s)://host/owner/repo») — ft-nano-close _lp_slug_of 와 같은 규칙 · 꼴 밖 = rc3
#   h 꼴(템플릿 1줄 · fetch 줄 0): landed() { bash "$BIN/ft-pr-landed.sh" --repo "$P" --pr "$PR" --set "$SET" >/dev/null; } · rc3 = «판정 불가 — 설치 0» exit 3(rc5 와 따로)
set -uo pipefail
und() { printf '판정 불가: %s\n' "$*"; exit 3; }
REPO=""; PR=""; SET=""; MAIN="origin/main"; FETCH=1; LOC=""
while [ $# -gt 0 ]; do case "$1" in
  --repo|--pr|--set|--main) [ $# -ge 2 ] || und "usage — $1 값 없음"; case "$1" in --repo) REPO="$2";; --pr) PR="$2";; --set) SET="$2";; --main) MAIN="$2";; esac; shift 2;;
  --no-fetch) FETCH=0; LOC=" ref=local"; shift;;
  *) und "usage — 모르는 인자 $1";; esac; done
[ -n "$REPO" ] && [ -d "$REPO" ] || und "usage — --repo 리포 루트 없음(${REPO:-빈 값})"
case "$PR" in ''|*[!0-9]*) und "usage — --pr 번호 꼴 밖(${PR:-빈 값})";; esac
[[ "$SET" =~ ^[0-9a-f]{40}$ ]] || und "usage — --set 은 40자 소문자 hex(${SET:0:12})"
case "$MAIN" in */*) RMT="${MAIN%%/*}"; BR="${MAIN#*/}";; *) und "usage — --main 은 <원격>/<가지>($MAIN)";; esac
CAP="${FT_PR_LANDED_CAP_S:-7}"; case "$CAP" in ''|*[!0-9]*|0) CAP=7;; esac
TB="$(command -v timeout || command -v gtimeout)" || und "timeout/gtimeout 없음 — 상한을 걸 수 없어 외부 호출 0"
G() { git -c gc.auto=0 -C "$REPO" "$@"; }
t2() { local rc=0 i; for i in 1 2; do "$TB" "$CAP" "$@" && return 0; rc=$?; done; return "$rc"; }   # 하드 룰 12: 7초 + 재시도 1
if [ "$FETCH" = 1 ]; then t2 git -c gc.auto=0 -C "$REPO" fetch --quiet "$RMT" "+refs/heads/$BR:refs/remotes/$MAIN" >/dev/null 2>&1 || und "fetch 실패 rc=$? ($MAIN · ${CAP}초 상한 + 재시도 1)"; fi
M="$(G rev-parse --verify -q "refs/remotes/$MAIN^{commit}")" || und "main ref 없음(refs/remotes/$MAIN)"
# ① ff — SET 객체가 없으면 main 의 조상일 수 없다(main 이력은 로컬에 다 있다) → ② 로
if G cat-file -e "$SET^{commit}" 2>/dev/null; then
  G merge-base --is-ancestor "$SET" "$M" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] && { echo "LANDED ff pr=$PR landing=$SET$LOC"; exit 0; }
  [ "$rc" -eq 1 ] || und "merge-base 실패 rc=$rc"
fi
# ② squash — 줄 «정확히» 일치(끝 공백·CR 무시) · 접두 겹침(PR #44 vs 4)·꼬리 붙은 줄 = 0
LOG="$("$TB" "$CAP" git -c gc.auto=0 -C "$REPO" log -n 200 --format='%x01%H%n%B' "$M" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || und "git log 실패 rc=$rc$([ "$rc" -eq 124 ] && echo " (${CAP}초 상한)")"
HIT="$(printf '%s\n' "$LOG" | awk -v want="PR #$PR (head $SET)" '/^\001/{h=substr($0,2); next} {sub(/[ \t\r]+$/,"")} $0==want{n++; c=h} END{print n+0, c}')"
N="${HIT%% *}"; Q="${HIT#* }"
[ "$N" -le 1 ] || und "같은 PR 줄 ${N}개(PR #$PR (head ${SET:0:10}) · main 최근 200 커밋) — 착지 커밋을 하나로 못 정함"
[ "$N" -eq 0 ] || { echo "LANDED squash pr=$PR landing=$Q$LOC"; exit 0; }
# ③ merged — gh 는 여기서만
url="$(G config --get remote.origin.url)"; url="${url%.git}"; url="${url%/}"
if [[ "$url" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]]; then SLUG="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
elif [[ "$url" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]+)?/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]]; then SLUG="${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
else und "origin 꼴 밖(${url:0:40}) — ssh·https 만 푼다"; fi
OUT="$(t2 "${FT_GH:-gh}" pr view "$PR" -R "$SLUG" --json state,mergeCommit,headRefOid 2>&1)" || und "gh pr view $PR -R $SLUG 실패 rc=$? ($(printf '%s' "$OUT" | head -1 | cut -c1-120))"
read -r ST HD MC <<<"$(printf '%s' "$OUT" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("? ? ?"); sys.exit()
m=d.get("mergeCommit"); m=(m or {}).get("oid") if isinstance(m,dict) else m
print(d.get("state") or "?", d.get("headRefOid") or "?", m or "-")')"
[ "$ST" != "?" ] && [ "$HD" != "?" ] || und "gh 응답을 못 읽음(state·headRefOid 없음): $(printf '%s' "$OUT" | head -1 | cut -c1-120)"
if [ "$ST" = MERGED ] && [ "$HD" = "$SET" ] && [ "$MC" != "-" ] && G merge-base --is-ancestor "$MC" "$M" 2>/dev/null; then echo "LANDED merged pr=$PR landing=$MC$LOC"; exit 0; fi
echo "NOT-LANDED pr=$PR$LOC"; exit 1
