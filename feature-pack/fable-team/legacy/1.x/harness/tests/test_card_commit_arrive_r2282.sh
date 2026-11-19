#!/usr/bin/env bash
# test_card_commit_arrive_r2282.sh — r2282: ft-card-commit.sh push 7초 끊김 뒤 원격에 이미 도착한 내 커밋 = PUSHED ·
#   다시 만든 판 tree 같음 = NOCHANGE · 두 번째 push 실패 = fetch 1회 더 · fetch 끊김 = 판정 불가(거짓 PUSHED 0).
#   반례 ① ①ⓑ ② ③ⓐⓑⓒ ④ ⑤ (카드 동결) · 변이 M1~M4(사본에서만 · 원본은 위 사례가 같은 판정).
# 격리만: 임시 bare origin + 클론 + PATH git shim(진짜 push 뒤 rc 142 = 7초 alarm 꼴) · 실 리포 · 실 원격 0 · sleep 0.
# 변이용: R2282_TOOL=<사본 경로> 로 도구를 바꿔 끼운다(이때 변이 절은 건너뜀).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2282_TOOL:-$REPO/bin/ft-card-commit.sh}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REAL="$(command -v git)" || { echo "FAIL git 없음"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$T/shim"
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 ($TOOL)"; exit 1; }
printf '#!/usr/bin/env bash\necho "OK $1"\n' > "$T/lint.sh"   # lint 대역: 사유 0(이 시험은 push 뒤 길만 본다)

# git shim: push 마다 plan 의 n 번째 줄 동작 · fetch 는 nofetch 표식이 있으면 끊김(rc 142)
#   arrive = 진짜 push 뒤 rc 142 · other <경로> <파일> = 원격 끝 위에 남의 커밋 · ahead <경로> <파일> = 남의 커밋만 올리고 rc 1
#   arrive-other <경로> <파일> = 진짜 push → 그 위 남의 커밋 → rc 142 · reject = rc 1 · arrive-nofetch = 진짜 push 뒤 fetch 끊김 · 빈 줄 = 진짜
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
REAL="$REAL"; S="$T/s"
other() {  # \$1=경로 \$2=내용 파일 → 원격 끝 위 커밋 1개(남의 커밋)
  local t b tr c; t="\$("\$REAL" -C "\$O" rev-parse refs/heads/ops/main-base)" || exit 9
  rm -f "\$S/idx"; GIT_INDEX_FILE="\$S/idx" "\$REAL" -C "\$O" read-tree "\$t" || exit 9
  b="\$("\$REAL" -C "\$O" hash-object -w "\$2")" && GIT_INDEX_FILE="\$S/idx" "\$REAL" -C "\$O" update-index --add --cacheinfo "100644,\$b,\$1" || exit 9
  tr="\$(GIT_INDEX_FILE="\$S/idx" "\$REAL" -C "\$O" write-tree)" && c="\$(echo other | "\$REAL" -C "\$O" commit-tree "\$tr" -p "\$t")" || exit 9
  "\$REAL" -C "\$O" update-ref refs/heads/ops/main-base "\$c" "\$t" || exit 9; }
if [ "\${1:-}" = push ]; then
  n=\$(( \$(cat "\$S/n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "\$S/n"
  read -r act a1 a2 < <(sed -n "\${n}p" "\$S/plan"; echo)
  case "\$act" in
    arrive) "\$REAL" "\$@" || exit 9; exit 142;;
    arrive-other) "\$REAL" "\$@" || exit 9; other "\$a1" "\$a2"; exit 142;;
    arrive-nofetch) "\$REAL" "\$@" || exit 9; touch "\$S/nofetch"; exit 142;;
    ahead) other "\$a1" "\$a2"; exit 1;;
    reject) exit 1;;
  esac
fi
[ "\${1:-}" = fetch ] && [ -f "\$S/nofetch" ] && exit 142
exec "\$REAL" "\$@"
EOF
chmod +x "$T/shim/git"

CA='design/harness/indices/대기/a.md' LED='design/harness/GOAL-harness.md'
card() { printf '<!-- ledger: %s -->\n# 카드\n%s\n' "$LED" "$1"; }
f() { printf '%s' "$2" > "$T/$1"; echo "$T/$1"; }
world() {   # W(작업) → O(bare) → R(클론 = 원 리포) · plan 줄 = push 차례별 shim 동작
  local d="$T/w.$RANDOM$RANDOM" W; W="$d/W" O="$d/O.git" R="$d/R"; export O
  rm -rf "$T/s"; mkdir -p "$T/s" "$W/design/harness/indices/대기"; printf '%s\n' "$@" > "$T/s/plan"
  git init -q -b ops/main-base "$W" && git init -q --bare -b main "$O"
  printf 'GL-A\n' > "$W/$LED"; printf '%s' "$(card '본문 0')" > "$W/$CA"
  git -C "$W" add -A && git -C "$W" commit -qm base && git -C "$W" push -q "$O" ops/main-base 2>/dev/null
  git clone -q -b ops/main-base "$O" "$R" 2>/dev/null; T0="$(tip)"
}
tip() { git -C "$O" rev-parse refs/heads/ops/main-base; }
pushes() { cat "$T/s/n" 2>/dev/null || echo 0; }
mine() { git -C "$O" log --format=%s "$T0..$(tip)" | grep -vc '^other$'; }   # T0 뒤 내 커밋 수(남의 커밋 뺌)
run() { OUT="$(cd "$R" && PATH="$T/shim:$PATH" FT_CARD_LINT="$T/lint.sh" bash "$TOOL" ops/main-base "카드" "$CA=$1" 2>&1)"; RC=$?; }
F1="$(f c1 "$(card '본문 1')")"; f oth $'other\n' >/dev/null

# ① push 가 원격 갱신 뒤 rc≠0 → PUSHED <NEW> base=<이전 끝> rc0 · 원격 끝 = NEW · 커밋 1개
world arrive; run "$F1"; t1="$(tip)"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "PUSHED $t1 base=$T0" && [ "$(git -C "$O" rev-parse "$t1^")" = "$T0" ] \
  && [ "$(mine)" = 1 ] && [ "$(pushes)" = 1 ]; } && ok "① 도착 → PUSHED <NEW> · 커밋 1 · push 1" || bad "① rc=$RC push=$(pushes) mine=$(mine) out=$OUT"
# ①ⓑ 도착 뒤 남의 커밋 1개가 그 위 → base = NEW^ · diff --stat = 내 파일만
world "arrive-other design/other.md $T/oth"; run "$F1"; t1="$(tip)"; nw="$(git -C "$O" rev-parse "$t1^")"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "PUSHED $nw base=$T0" && [ "$(git -C "$O" rev-parse "$nw^")" = "$T0" ] \
  && printf '%s\n' "$OUT" | grep -q 'a\.md' && ! printf '%s\n' "$OUT" | grep -q 'other\.md' && [ "$(mine)" = 1 ]; } \
  && ok "①ⓑ 도착 + 남의 커밋 → base = NEW^ · stat 내 파일만" || bad "①ⓑ rc=$RC mine=$(mine) out=$OUT"
# ② push rc≠0 · 원격이 남의 커밋으로 앞섬(같은 카드 글자) → NOCHANGE rc0 · 원격 끝 = 남의 커밋 · push 1(첫 시도만)
world "ahead $CA $F1"; run "$F1"; t1="$(tip)"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "NOCHANGE base=$t1" && [ "$(git -C "$O" log -1 --format=%s "$t1")" = other ] \
  && [ "$(mine)" = 0 ] && [ "$(pushes)" = 1 ]; } && ok "② 다시 만든 판 tree 같음 → NOCHANGE · push 0" || bad "② rc=$RC push=$(pushes) mine=$(mine) out=$OUT"
# ③ⓐ 거절(원격이 앞섬 · 다른 파일) → 새 끝 위 1회 다시 · 성공
world "ahead design/ahead.md $T/oth" ""; run "$F1"; t1="$(tip)"; ah="$(git -C "$O" rev-parse "$t1^")"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "PUSHED $t1 base=$ah" && [ "$(git -C "$O" log -1 --format=%s "$ah")" = other ] \
  && git -C "$O" cat-file -e "$t1:design/ahead.md" && [ "$(mine)" = 1 ]; } && ok "③ⓐ 거절 → 새 끝 위 1회 다시 · 성공" || bad "③ⓐ rc=$RC out=$OUT"
# ③ⓑ 두 번째 push 도 원격 갱신 뒤 rc≠0 → PUSHED rc0 · 커밋 1개
world "ahead design/ahead.md $T/oth" arrive; run "$F1"; t1="$(tip)"; ah="$(git -C "$O" rev-parse "$t1^")"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "PUSHED $t1 base=$ah" && [ "$(mine)" = 1 ] && [ "$(pushes)" = 2 ]; } \
  && ok "③ⓑ 두 번째 도착 → PUSHED · 커밋 1" || bad "③ⓑ rc=$RC push=$(pushes) mine=$(mine) out=$OUT"
# ③ⓒ 두 번째도 거절 → 판정 불가 push rc3 · 원격 글자 0
world "ahead design/ahead.md $T/oth" reject; run "$F1"
{ [ "$RC" = 3 ] && printf '%s\n' "$OUT" | grep -q '^판정 불가 push' && [ "$(mine)" = 0 ] && ! printf '%s\n' "$OUT" | grep -q '^PUSHED'; } \
  && ok "③ⓒ 두 번 거절 → 판정 불가 push · 원격 글자 0" || bad "③ⓒ rc=$RC mine=$(mine) out=$OUT"
# ④ push rc≠0 뒤 fetch 끊김 → 판정 불가 fetch rc3 · PUSHED 줄 0
world arrive-nofetch; run "$F1"
{ [ "$RC" = 3 ] && printf '%s\n' "$OUT" | grep -q '^판정 불가 fetch' && ! printf '%s\n' "$OUT" | grep -q '^PUSHED'; } \
  && ok "④ fetch 끊김 → 판정 불가 fetch · PUSHED 0" || bad "④ rc=$RC out=$OUT"
# ⑤ 첫 build 에서 tree 같음 → NOCHANGE rc0 · push 0
world; run "$(f c0 "$(card '본문 0')")"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx "NOCHANGE base=$T0" && [ "$(pushes)" = 0 ]; } && ok "⑤ 첫 판 tree 같음 → NOCHANGE · push 0" || bad "⑤ rc=$RC out=$OUT"

# 변이 M1~M4: 사본에 sed 1곳 → 이 시험을 사본으로 다시 · 기대 사례 FAIL 이어야 함
if [ -z "${R2282_TOOL:-}" ]; then
  mut() {  # $1=이름 $2=기대 FAIL 사례 머리 $3=sed 식
    local m="$T/$1.sh" o; sed "$3" "$TOOL" > "$m"
    cmp -s "$TOOL" "$m" && { bad "$1 sed 안 먹음"; return; }
    o="$(R2282_TOOL="$m" bash "${BASH_SOURCE[0]:-$0}" 2>&1)"
    printf '%s\n' "$o" | grep -q "^FAIL $2 " && ok "$1 → $2 FAIL" || bad "$1 살아남음 ($(printf '%s\n' "$o" | grep '^FAIL' | head -3 | tr '\n' ' '))"
  }
  mut M1 ① 's/^arrived() {.*/arrived() { return 1; }/'
  mut M2 ② 's/{ build; same; }/build/'
  mut M3 ④ 's/OLD="\$BASE"; fetch "(push 도착 여부 모름)"/OLD="$BASE"; (fetch x) >\/dev\/null 2>\&1 || break; fetch/'
  mut M4 ①ⓑ 's/^P0=.*/P0="$BASE"/'
fi
echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
