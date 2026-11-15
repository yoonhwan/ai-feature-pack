#!/usr/bin/env bash
# test_pr_landed_r1800.sh — r1800: «PR #N 이 main 에 착지했나» 판정 도구 ft-pr-landed.sh(착지+설치 h 가 쓰는 1곳).
#   반례 ①~③·⑤·⑦(카드 «반례 집합») · ④⑥ = ft-nano-close 손 0(기준판이 r1169·r1278 로 자동 병합 꼬리를 이미 읽음 · 기존 시험 따로 재실행)
#   임시 bare 리포 + 임시 clone · ff·squash·squash+자동 병합·미착지 꼴을 ft-merge-land 와 같은 commit-tree 로 만든다 · gh = 가짜(FT_GH) · 실 gh·실 팩 0
#   기준판 Red = 옛 h 꼴(«승인 세트 ancestor»)·끝줄 정확히 판정이 squash·자동 병합·낡은 로컬 ref 를 놓치는 것을 같은 리포에서 보인다
#   변이 M1~M6 = bin 사본 1파일에서 한 곳만 · 변이마다 원본으로 같은 사례 1회 더 · sleep 0(가짜 fetch 만 상한 초과용 sleep) · 70초 안
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; TOOL0="$BIN/ft-pr-landed.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$(date +%s); TL=$T0; STEPS=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
lap() { local n; n=$(date +%s); STEPS="$STEPS $1=$((n-TL))s"; TL=$n; }
URL="https://github.com/o/r.git"; BARE="$T/o.git"; W="$T/w"; C="$T/c"
cat > "$T/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$GH_CALLS"; [ "${GH_RC:-0}" = 0 ] || { echo "gh boom" >&2; exit "$GH_RC"; }; cat "$GH_JSON"
EOF
chmod +x "$T/gh"; export FT_GH="$T/gh" GH_CALLS="$T/gh.calls" GH_JSON="$T/gh.json"
ghj() { printf '{"state":"%s","headRefOid":"%s","mergeCommit":%s}\n' "$1" "$2" "$3" > "$GH_JSON"; }
ghj CLOSED 0000000000000000000000000000000000000000 null
# 한 줄·rc 를 같이 본다(반례 ① = 줄 1개 · rc 0/1/3)
run() { local tool="$1"; shift; OUT="$(bash "$tool" "$@" 2>&1)"; RC=$?; }
want() {  # <이름> <rc> <첫 글자> [tool] -- 인자…
  local name="$1" wrc="$2" wpre="$3" tool="$TOOL0"; shift 3; [ "$1" = -- ] || { tool="$1"; shift; }; shift
  run "$tool" "$@"
  local nl; nl="$(printf '%s\n' "$OUT" | grep -c .)"
  if [ "$RC" = "$wrc" ] && [ "$nl" = 1 ] && case "$OUT" in "$wpre"*) true;; *) false;; esac; then ok "$name ($OUT)"; else bad "$name — rc=$RC 줄=$nl «${OUT:0:300}» (want rc=$wrc «$wpre…»)"; fi
}
lap 준비
echo "== 짝 cmp · bash -n"
cmp -s "$BIN/ft-pr-landed.sh" "$KIT/ft-pr-landed.sh" && ok "bin == kit" || bad "bin ≠ kit"
/bin/bash -n "$TOOL0" && ok "/bin/bash 3.2 -n" || bad "bash -n"
[ "$(wc -l < "$TOOL0")" -le 80 ] && ok "≤80줄 ($(wc -l < "$TOOL0" | tr -d ' '))" || bad "80줄 넘음"

git init -q --bare -b main "$BARE"
git init -q -b main "$W"; git -C "$W" commit -q --allow-empty -m base; git -C "$W" remote add origin "$BARE"; git -C "$W" push -q origin main
mkc() { git clone -q "$BARE" "$1"; git -C "$1" config remote.origin.url "$URL"; git -C "$1" config "url.$BARE.insteadOf" "$URL"; }
mkc "$C"; mkc "$T/stale"; mkc "$T/stale2"   # stale·stale2 = 착지 전에 받은 로컬 ref 그대로(⑦ · stale2 는 끝까지 fetch 0)
br() { git -C "$W" checkout -q -B "b$1" origin/main; echo "$1" > "$W/f$1"; git -C "$W" add "f$1"; git -C "$W" commit -q -m "work $1"; git -C "$W" rev-parse HEAD; }
M() { git -C "$W" fetch -q origin; git -C "$W" rev-parse origin/main; }
land() { git -C "$W" push -q origin "$1:refs/heads/main"; }   # 그 커밋을 main 으로(빨리감기만 · force 0)
sq() {  # <S> <메시지> → ft-merge-land :70 과 같은 Q = commit-tree S^{tree} -p M
  local m; m="$(M)"; git -C "$W" commit-tree "$1^{tree}" -p "$m" -m "$2"; }
S1="$(br 1)"; land "$S1"                                                                  # ff
S2="$(br 2)"; Q2="$(sq "$S2" "$(printf 'title 11\n\nbody\n\nPR #11 (head %s)' "$S2")")"; land "$Q2"   # squash(끝줄 PR 줄)
S3="$(br 3)"; C3="$(git -C "$W" commit-tree "$S3^{tree}" -p "$S3" -p "$(M)" -m "auto-merge main into PR #12 (code · approved)")"
Q3="$(sq "$C3" "$(printf 'title 12\n\nbody\n\nPR #12 (head %s)\nmain 자동 병합(코드 · 승인 EQUIV) C=%s' "$S3" "$C3")")"; land "$Q3"   # squash + 자동 병합 꼬리
S4="$(br 4)"                                                                              # 미착지
S5="$(br 5)"; Q5a="$(sq "$S5" "$(printf 't\n\nPR #14 (head %s)' "$S5")")"; land "$Q5a"; Q5b="$(sq "$S5" "$(printf 'again\n\nPR #14 (head %s)' "$S5")")"; land "$Q5b"   # 같은 PR 줄 2개
S6a="$(br 6)"; echo 6b >> "$W/f6"; git -C "$W" commit -q -am "work 6b"; S6b="$(git -C "$W" rev-parse HEAD)"
Q6="$(sq "$S6b" "$(printf 't\n\nPR #15 (head %s)' "$S6b")")"; land "$Q6"                  # 낡은 세트 S6a · 새 head S6b
S7="$(br 7)"; Q7="$(sq "$S7" "title (#17)")"; land "$Q7"                                  # GitHub squash 버튼 꼴(PR 줄 0 · gh MERGED)
lap 리포
echo "== ① 출력 꼴 · ② 근거 순서"
: > "$GH_CALLS"
want "② ff" 0 "LANDED ff pr=10 landing=$S1" -- --repo "$C" --pr 10 --set "$S1"
want "② squash(끝줄 PR 줄)" 0 "LANDED squash pr=11 landing=$Q2" -- --repo "$C" --pr 11 --set "$S2"
want "② squash + 자동 병합 꼬리" 0 "LANDED squash pr=12 landing=$Q3" -- --repo "$C" --pr 12 --set "$S3"
[ -s "$GH_CALLS" ] && bad "③ ①② 참인데 gh 호출 $(wc -l < "$GH_CALLS")" || ok "③ ①② 참이면 gh 호출 0"
want "② 미착지" 1 "NOT-LANDED pr=13" -- --repo "$C" --pr 13 --set "$S4"
want "② 다른 PR 번호 줄만(PR #11 · --pr 1)" 1 "NOT-LANDED pr=1" -- --repo "$C" --pr 1 --set "$S2"
want "② 같은 PR 줄 2개" 3 "판정 불가: 같은 PR 줄 2개" -- --repo "$C" --pr 14 --set "$S5"
echo "== ③ 낡은 세트 · gh"
ghj CLOSED "$S6b" null
want "③ 낡은 세트(main 줄 head = 새 head)" 1 "NOT-LANDED pr=15" -- --repo "$C" --pr 15 --set "$S6a"
want "③ 새 head 는 착지" 0 "LANDED squash pr=15 landing=$Q6" -- --repo "$C" --pr 15 --set "$S6b"
ghj MERGED "$S7" "{\"oid\":\"$Q7\"}"
want "③ merged(gh MERGED ∧ head == SET ∧ mergeCommit ⊂ main)" 0 "LANDED merged pr=17 landing=$Q7" -- --repo "$C" --pr 17 --set "$S7"
want "③ merged 인데 head ≠ SET" 1 "NOT-LANDED pr=17" -- --repo "$C" --pr 17 --set "$S4"
ghj MERGED "$S7" '{"oid":"1234567890123456789012345678901234567890"}'
want "③ merged · mergeCommit 객체 없음(merge-base rc128) → rc3 (DA #311114 ①)" 3 "판정 불가: merge-base(mergeCommit 1234567890" -- --repo "$C" --pr 17 --set "$S7"
echo '[]' > "$GH_JSON"
want "③ gh rc0 · JSON [] → rc3 (DA #311114 ②)" 3 "판정 불가: gh 응답을 못 읽음" -- --repo "$C" --pr 17 --set "$S7"
ghj MERGED "$S7" "{\"oid\":\"$Q7\"}"
GH_RC=1 want "③ gh rc1 → rc3" 3 "판정 불가: gh pr view 17" -- --repo "$C" --pr 17 --set "$S7"
want "① usage(SET 꼴 밖) → rc3 1줄" 3 "판정 불가: usage" -- --repo "$C" --pr 17 --set abc
git -C "$T/stale" config remote.origin.url "file:///x/y"; git -C "$T/stale" config --unset "url.$BARE.insteadOf"
want "③ origin 꼴 밖(file://) → rc3 · gh 호출 0" 3 "판정 불가: origin 꼴 밖" -- --repo "$T/stale" --pr 17 --set "$S7" --no-fetch
git -C "$T/stale" config remote.origin.url "$URL"; git -C "$T/stale" config "url.$BARE.insteadOf" "$URL"
lap 판정
echo "== 기준판 Red(옛 h 꼴 · 끝줄 정확히)"
OLD() { git -C "$C" merge-base --is-ancestor "$1" origin/main 2>/dev/null; }   # h-r17NN…:13 landed() 그대로
OLD "$S2" && bad "기준 h 꼴이 squash 를 착지로 봄(Red 아님)" || ok "Red 기준 h 꼴 squash = 거짓(8/8 rc5 의 원인)"
OLD "$S3" && bad "기준 h 꼴이 자동 병합을 착지로 봄" || ok "Red 기준 h 꼴 squash+자동 병합 = 거짓"
LAST="$(git -C "$C" log -1 --format=%B "$Q3" | grep . | tail -1)"
[ "$LAST" = "PR #12 (head $S3)" ] && bad "끝줄이 PR 줄(Red 아님)" || ok "Red 끝줄 정확히 판정 = 거짓(끝줄 = «${LAST:0:24}…»)"
echo "== ⑤ h 꼴 1줄"
cat > "$T/h.sh" <<'EOF'
#!/usr/bin/env bash
BIN="$1"; P="$2"; PR="$3"; SET="$4"
landed() { bash "$BIN/ft-pr-landed.sh" --repo "$P" --pr "$PR" --set "$SET" >/dev/null; }
landed; rc=$?; [ "$rc" -ne 3 ] || { echo "판정 불가 — 설치 0"; exit 3; }; [ "$rc" -eq 0 ] || { echo "FAIL 착지 확인 실패 — 설치 0"; exit 5; }
echo "설치 단계 진입"
EOF
hrun() { HO="$(bash "$T/h.sh" "$@" 2>&1)"; HR=$?; }
hrun "$(dirname "$TOOL0")" "$C" 11 "$S2"; [ "$HR" = 0 ] && [ "$HO" = "설치 단계 진입" ] && ok "⑤ squash 착지 → 설치 단계 진입" || bad "⑤ squash rc=$HR «$HO»"
git -C "$T/stale" config remote.origin.url /no/such/repo
hrun "$(dirname "$TOOL0")" "$T/stale" 11 "$S2"; [ "$HR" = 3 ] && [ "$HO" = "판정 불가 — 설치 0" ] && ok "⑤ rc3 → «판정 불가 — 설치 0» exit 3" || bad "⑤ rc3 rc=$HR «$HO»"
echo "== ⑦ fetch"
want "⑦ origin 없는 경로(원격엔 착지) → 판정 불가 fetch" 3 "판정 불가: fetch 실패" -- --repo "$T/stale" --pr 11 --set "$S2"
git -C "$T/stale2" config "url.$T/no-such.git.insteadOf" "$URL"; git -C "$T/stale2" config --unset "url.$BARE.insteadOf"   # https 꼴 그대로 · 받을 곳만 없음
want "⑦ https 꼴 · 받을 곳 없음 → 판정 불가 fetch" 3 "판정 불가: fetch 실패" -- --repo "$T/stale2" --pr 11 --set "$S2"
want "⑦ --no-fetch → 낡은 로컬 ref 그대로 · ref=local" 1 "NOT-LANDED pr=11 ref=local" -- --repo "$T/stale2" --pr 11 --set "$S2" --no-fetch
git -C "$T/stale" config remote.origin.url "$URL"
mkdir -p "$T/slow"; RG="$(command -v git)"
printf '#!/bin/sh\ncase " $* " in *" fetch "*) sleep 3;; esac\nexec "%s" "$@"\n' "$RG" > "$T/slow/git"; chmod +x "$T/slow/git"
PATH="$T/slow:$PATH" FT_PR_LANDED_CAP_S=1 want "⑦ fetch 상한 초과 → rc3" 3 "판정 불가: fetch 실패 rc=124" -- --repo "$T/stale" --pr 11 --set "$S2"
git -C "$T/stale" merge-base --is-ancestor "$Q2" origin/main 2>/dev/null && bad "stale ref 가 이미 착지를 가짐" || ok "Red 낡은 로컬 ref 에 착지 커밋 없음(기준 h 꼴 = rc5)"
want "⑦ 낡은 ref + fetch 성공 → LANDED" 0 "LANDED squash pr=11 landing=$Q2" -- --repo "$T/stale" --pr 11 --set "$S2"
lap 'h·fetch'
echo "== 변이(사본 1파일 · 원본 대조)"
mut() {  # <이름> <old> <new> → $T/m/<이름>/ft-pr-landed.sh
  mkdir -p "$T/m/$1"; python3 - "$TOOL0" "$T/m/$1/ft-pr-landed.sh" "$2" "$3" <<'PY' || bad "$1 변이 자리 없음"
import sys; s=open(sys.argv[1],encoding="utf-8").read(); o,n=sys.argv[3],sys.argv[4]
assert s.count(o)==1, f"count={s.count(o)}"; open(sys.argv[2],"w",encoding="utf-8").write(s.replace(o,n))
PY
  MT="$T/m/$1/ft-pr-landed.sh"; }
killed() {  # <이름> <rc> <첫 글자> -- 인자… = 원본은 그 값 · 변이는 다른 값이어야 한다
  local n="$1" r="$2" p="$3"; shift 3; shift
  want "$n 원본" "$r" "$p" -- "$@"
  run "$MT" "$@"; case "$OUT" in "$p"*) [ "$RC" != "$r" ] || { bad "$n 변이 살아남음 «$OUT»"; return; };; esac; ok "$n 변이 죽음 (rc=$RC «${OUT:0:60}»)"; }
mut M1 '/^\001/{h=substr($0,2); next} {sub(/[ \t\r]+$/,"")} $0==want{n++; c=h} END{print n+0, c}' '/^\001/{if(l==want){n++; c=h}; h=substr($0,2); l=""; next} {sub(/[ \t\r]+$/,"")} NF{l=$0} END{if(l==want){n++; c=h}; print n+0, c}'
killed "M1 끝줄 정확히 → 자동 병합 꼴" 0 "LANDED squash pr=12" -- --repo "$C" --pr 12 --set "$S3"
mut M2 '$0==want{n++; c=h}' 'index($0,substr(want,1,length(want)-41))==1{n++; c=h}'
ghj CLOSED "$S6b" null; killed "M2 head = 아무 head → 낡은 세트" 1 "NOT-LANDED pr=15" -- --repo "$C" --pr 15 --set "$S6a"
mut M3 '# ① ff —' '"${FT_GH:-gh}" pr view "$PR" >/dev/null 2>&1 # ① ff —'
: > "$GH_CALLS"; run "$MT" --repo "$C" --pr 10 --set "$S1"; [ -s "$GH_CALLS" ] && ok "M3 gh 먼저 → 호출 $(wc -l < "$GH_CALLS" | tr -d ' ') = 변이 죽음" || bad "M3 살아남음"
: > "$GH_CALLS"; run "$TOOL0" --repo "$C" --pr 10 --set "$S1"; [ -s "$GH_CALLS" ] && bad "M3 원본 gh 호출" || ok "M3 원본 호출 0"
mut M4 '[ "$N" -le 1 ] ||' '[ "$N" -le 1 ] || N=1 ||'
killed "M4 줄 2개 → 첫 줄" 3 "판정 불가: 같은 PR 줄 2개" -- --repo "$C" --pr 14 --set "$S5"
mut M5 "exit 3; }" "exit 5; }"
git -C "$T/stale" config remote.origin.url /no/such/repo
hrun "$T/m/M5" "$T/stale" 11 "$S2"; [ "$HR" = 3 ] && bad "M5 살아남음" || ok "M5 rc3→rc5 → h exit $HR «$HO» = 변이 죽음"
hrun "$(dirname "$TOOL0")" "$T/stale" 11 "$S2"; [ "$HR" = 3 ] && ok "M5 원본 h exit 3" || bad "M5 원본 h exit $HR"
mut M6 '>/dev/null 2>&1 || und "fetch 실패' '>/dev/null 2>&1 || true "fetch 실패'
killed "M6 fetch 실패 무시(낡은 ref 로 NOT-LANDED)" 3 "판정 불가: fetch 실패" -- --repo "$T/stale2" --pr 11 --set "$S2"
lap 변이
echo "단계별 초: 전체=$(( $(date +%s) - T0 ))s ·$STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
