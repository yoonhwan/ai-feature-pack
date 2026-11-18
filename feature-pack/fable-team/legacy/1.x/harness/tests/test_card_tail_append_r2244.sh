#!/usr/bin/env bash
# test_card_tail_append_r2244.sh — r2244: ft-card-tail(O1 꼬리 보기) · ft-card-append(O2 덧붙이기 · O3 거절 · O4 불변).
# 로컬 bare 리포 = origin · 네트워크 0 · sleep 0. 반례 ①~⑨ + 변이 M1~M4(사본에서만 · 변이마다 원본으로 같은 사례 1회 더).
# FT_CT_PATH · FT_CA_PATH = 다른 판을 줄 때 · FT_R2244_BASELINE=1 = 기준판(도구 없음 = git show 전문 · 좌석 손 도구 꼴 끝 덧붙이기) → ① ⑨ 빨강.
# FT_R2244_TMPBASE = 임시 폴더 뿌리(/tmp · /private/tmp 두 경로 시험).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KB="$HERE/../../harness/kit/fable-team/bin"
CT0="${FT_CT_PATH:-$KB/ft-card-tail.sh}"; CA0="${FT_CA_PATH:-$KB/ft-card-append.sh}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
TMP="$(mktemp -d "${FT_R2244_TMPBASE:-${TMPDIR:-/tmp}}/r2244.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
: > "$TMP/gitconfig"; export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
if [ -n "${FT_R2244_BASELINE:-}" ]; then
  CT0="$TMP/base-tail.sh"; CA0="$TMP/base-append.sh"
  printf '#!/usr/bin/env bash\nref=origin/ops/main-base; [ "${2:-}" = --ref ] && ref="$3"; git show "$ref:$1"\n' > "$CT0"
  cat > "$CA0" <<'SH'
#!/usr/bin/env bash
git fetch -q --refmap= origin "+refs/heads/$1:refs/base/$1" || exit 3; B=$(git rev-parse "refs/base/$1")
git show "$B:$2" > /tmp/.r2244b.$$ && cat "$3" >> /tmp/.r2244b.$$ || exit 2
export GIT_INDEX_FILE=/tmp/.r2244i.$$; git read-tree "$B"; git update-index --cacheinfo "100644,$(git hash-object -w /tmp/.r2244b.$$),$2"
C=$(git commit-tree "$(git write-tree)" -p "$B" -m "$4"); rm -f /tmp/.r2244[bi].$$; git push -q origin "$C:refs/heads/$1" && echo "PUSHED $C base=$B"
SH
fi
{ [ -f "$CT0" ] && [ -f "$CA0" ] && bash -n "$CT0" && bash -n "$CA0"; } || { echo "FAIL 준비: CT=$CT0 CA=$CA0"; echo "FAILED 1"; exit 1; }
CT="$CT0"; CA="$CA0"
D="design/harness/indices/대기"
mkcards() { # mkcards <폴더> — 반례 카드 4장
  local d="$1/$D" i; mkdir -p "$d"
  { echo "# 인덱스: r9001-twelve — 끝: 시험 카드"; echo "- 상태: 대기"; echo; echo "## 배경"; echo "본문"; echo; echo "## 상태"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "- 상태 줄 $i"; done; } > "$d/r9001.md"
  printf '# 인덱스: r9002-nostate\n- 상태: 대기\n\n## 배경\n본문\n' > "$d/r9002.md"
  { echo "# 인덱스: r9003-long"; echo; echo "## 상태"; echo "- 짧은 줄 1"
    printf -- '- %s\n' "$(python3 -c 'print("가"*999+"x")')"; echo "- 짧은 줄 3"; } > "$d/r9003.md"
  printf '# 인덱스: r9004-step\n\n## 상태\n- 상태 줄 1\n- 상태 줄 2\n\n## 단계 2\n- 단계 줄\n' > "$d/r9004.md"
}
fresh() { # fresh — 새 origin(bare) · 씨 리포 S · 작업 리포 W(시험 도구는 W 에서 돈다)
  rm -rf "$TMP/o.git" "$TMP/s" "$TMP/w"; git init -q --bare "$TMP/o.git"
  git init -q -b ops/main-base "$TMP/s" && mkcards "$TMP/s" && echo other > "$TMP/s/other.txt"
  git -C "$TMP/s" add -A && git -C "$TMP/s" commit -qm seed && git -C "$TMP/s" remote add origin "$TMP/o.git"
  git -C "$TMP/s" push -q origin ops/main-base && git clone -q -b ops/main-base "$TMP/o.git" "$TMP/w"
  W="$TMP/w"; OREF="$(git -C "$TMP/o.git" rev-parse ops/main-base)"
}
tail_() { (cd "$W" && bash "$CT" "$@") > "$TMP/out" 2>&1; RC=$?; }
app() { (cd "$W" && bash "$CA" ops/main-base "$1" "$2" "${3:-[docs] 시험}") > "$TMP/out" 2>&1; RC=$?; }
ocard() { git -C "$TMP/o.git" show "ops/main-base:$D/$1"; }
bytes() { wc -c < "$TMP/out" | tr -d ' '; }
nl_() { grep -c '' "$TMP/out"; }
printf -- '- 덧1 판정 줄\n- 덧2 세트 줄\n- 덧3 착지 줄\n' > "$TMP/draft3"
printf -- '- 새 줄 하나\n' > "$TMP/draft1"
printf -- '- 한글 원고\n' | iconv -f UTF-8 -t EUC-KR > "$TMP/draft_euc"

# ① 12줄 꼬리 → 머리 1 + 꼬리 6 · ≤ 2048B
fresh; tail_ "$D/r9001.md"
[ "$RC" = 0 ] && [ "$(nl_)" = 7 ] && [ "$(bytes)" -le 2048 ] && head -1 "$TMP/out" | grep -q '^# 인덱스: r9001' \
  && sed -n 2p "$TMP/out" | grep -qx -- '- 상태 줄 7' && tail -1 "$TMP/out" | grep -qx -- '- 상태 줄 12' \
  && ok "① 꼬리 6줄 + 머리 1줄 · $(bytes)B" || bad "① rc=$RC 줄=$(nl_) $(bytes)B" "$(head -c 400 "$TMP/out")"
# ② 상태 절 없음
tail_ "$D/r9002.md"
[ "$RC" = 0 ] && [ "$(nl_)" = 2 ] && sed -n 2p "$TMP/out" | grep -qx '상태 절 없음' \
  && ok "② 상태 절 없음 1줄 · rc 0" || bad "② rc=$RC" "$(cat "$TMP/out")"
# ③ 3000B 한 줄 → 300B + «…(자름 3000B)» · ≤ 2048B
tail_ "$D/r9003.md"; L="$(grep -- '자름' "$TMP/out")"
[ "$RC" = 0 ] && [ "$(bytes)" -le 2048 ] && printf '%s' "$L" | grep -q '…(자름 3000B)$' \
  && [ "$(printf '%s' "${L%…(자름 3000B)}" | wc -c | tr -d ' ')" -le 300 ] && grep -qx -- '- 짧은 줄 3' "$TMP/out" \
  && ok "③ 긴 줄 300B + 자름 표시 · $(bytes)B" || bad "③ rc=$RC $(bytes)B" "$(head -c 400 "$TMP/out")"
# ④ 원고 3줄 덧붙이기 → 카드 끝 3줄 = 원고 · 카드 밖 diff 0 · 출력 ≤ 3줄 · 작업 트리·index 손 0
fresh; IDX0="$(git -C "$W" ls-files -s | shasum)"; app "$D/r9001.md" "$TMP/draft3"; C="$(sed -n 's/^PUSHED \([0-9a-f]\{40\}\) base=.*/\1/p' "$TMP/out")"
[ "$RC" = 0 ] && [ -n "$C" ] && [ "$(nl_)" -le 3 ] && [ "$(ocard r9001.md | tail -3)" = "$(cat "$TMP/draft3")" ] \
  && [ "$(git -C "$TMP/o.git" -c core.quotePath=false diff --name-only "$OREF" ops/main-base)" = "$D/r9001.md" ] \
  && [ "$(git -C "$TMP/o.git" show "$OREF:$D/r9001.md"; cat "$TMP/draft3")" = "$(ocard r9001.md)" ] \
  && [ -z "$(git -C "$W" status --porcelain)" ] && [ "$IDX0" = "$(git -C "$W" ls-files -s | shasum)" ] \
  && ok "④ 3줄 덧붙음 · 카드 밖 diff 0 · 출력 $(nl_)줄" || bad "④ rc=$RC" "$(cat "$TMP/out")"
# ⑤ EUC-KR 원고 → rc 4 · origin ref 그대로
fresh; app "$D/r9001.md" "$TMP/draft_euc"
[ "$RC" = 4 ] && [ "$(git -C "$TMP/o.git" rev-parse ops/main-base)" = "$OREF" ] && ok "⑤ EUC-KR → rc 4 · push 0" || bad "⑤ rc=$RC" "$(cat "$TMP/out")"
# ⑥ 가지 끝에 없는 카드 → rc 2 · push 0
app "$D/r9999.md" "$TMP/draft1"
[ "$RC" = 2 ] && [ "$(git -C "$TMP/o.git" rev-parse ops/main-base)" = "$OREF" ] && [ -z "$(git -C "$W" status --porcelain)" ] \
  && ok "⑥ 카드 없음 → rc 2 · push 0" || bad "⑥ rc=$RC" "$(cat "$TMP/out")"
# ⑦ refs/remotes/origin/<가지>.lock 남음 → rc 0 · 출력 ≤ 3줄 · --ref <PUSHED> 꼬리에 새 줄
case7() { fresh; OLD7="$OREF"; echo more >> "$TMP/s/other.txt" && git -C "$TMP/s" commit -qam ahead && git -C "$TMP/s" push -q origin ops/main-base
  OREF="$(git -C "$TMP/o.git" rev-parse ops/main-base)"; mkdir -p "$W/.git/refs/remotes/origin/ops"; : > "$W/.git/refs/remotes/origin/ops/main-base.lock"
  app "$D/r9001.md" "$TMP/draft1"; R7=$RC; N7="$(nl_)"; O7="$(cat "$TMP/out")"; C="$(sed -n 's/^PUSHED \([0-9a-f]\{40\}\) .*/\1/p' "$TMP/out")"
  P7=""; [ -n "$C" ] && { tail_ "$D/r9001.md" --ref "$C"; tail -1 "$TMP/out" | grep -qx -- '- 새 줄 하나' && P7=1; }
  STALE=""; [ "$(git -C "$W" rev-parse origin/ops/main-base)" = "$OLD7" ] && STALE=1; }
case7; [ "$R7" = 0 ] && [ "$N7" -le 3 ] && [ -n "$P7" ] && [ -n "$STALE" ] \
  && ok "⑦ 잠금 남음 → rc 0 · 출력 ${N7}줄 · --ref PUSHED 꼬리에 새 줄 · 로컬 추적 ref 묵음" || bad "⑦ rc=$R7 줄=$N7 보임=$P7 묵음=$STALE" "$O7"
# ⑧ 그 사이 origin 이 앞섬 → «판정 불가 push rc=1» 1줄 rc 3 · 카드 손 0
fresh; mkdir -p "$W/.git/hooks"
cat > "$W/.git/hooks/pre-push" <<SH
#!/usr/bin/env bash
[ -f "$TMP/raced" ] && exit 0; : > "$TMP/raced"
echo more >> "$TMP/s/other.txt" && git -C "$TMP/s" commit -qam race && git -C "$TMP/s" push -q origin ops/main-base
SH
chmod +x "$W/.git/hooks/pre-push"; rm -f "$TMP/raced"; app "$D/r9001.md" "$TMP/draft1"
[ "$RC" = 3 ] && [ "$(cat "$TMP/out")" = "판정 불가 push rc=1" ] && [ "$(ocard r9001.md)" = "$(git -C "$TMP/o.git" show "$OREF:$D/r9001.md")" ] \
  && [ "$(git -C "$TMP/o.git" rev-parse ops/main-base)" != "$OREF" ] && ok "⑧ push 거절 → 판정 불가 1줄 rc 3 · 카드 손 0" || bad "⑧ rc=$RC" "$(cat "$TMP/out")"
# ⑨ «## 상태» 뒤에 «## 단계 2» → 덧붙이기 rc 2 · push 0 · 꼬리 보기 끝에 «뒤에 ## 절 있음: 단계 2»
case9() { fresh; app "$D/r9004.md" "$TMP/draft1"; R9=$RC; O9="$(cat "$TMP/out")"; PUSH9=0
  [ "$(git -C "$TMP/o.git" rev-parse ops/main-base)" != "$OREF" ] && PUSH9=1; }
case9; tail_ "$D/r9004.md"
[ "$R9" = 2 ] && [ "$PUSH9" = 0 ] && tail -1 "$TMP/out" | grep -qx '뒤에 ## 절 있음: 단계 2' && sed -n 3p "$TMP/out" | grep -qx -- '- 상태 줄 2' \
  && ok "⑨ 단계 절 뒤 → rc 2 · push 0 · 꼬리 보기 끝 1줄" || bad "⑨ rc=$R9 push=$PUSH9" "$O9 / $(cat "$TMP/out")"

# 변이 M1~M4 — 사본에서만 · 변이 판 = 반대 결과 · 원본으로 같은 사례 1회 더
mutate() { # mutate <원본> <이름> <sed 식> <grep 확인> → $MUT
  MUT="$TMP/mut-$2-$(basename -- "$1")"; sed "$3" "$1" > "$MUT" && grep -qF -- "$4" "$MUT" && ! cmp -s "$1" "$MUT"
}
if [ -z "${FT_R2244_BASELINE:-}" ]; then
  mutate "$CT0" M1 's/out_tail = sec\[-n:\]/out_tail = sec/' 'out_tail = sec' || bad "M1 적용 실패" ""
  fresh; CT="$MUT"; tail_ "$D/r9001.md"; m="$(nl_)"; CT="$CT0"; tail_ "$D/r9001.md"
  [ "$m" = 13 ] && [ "$(nl_)" = 7 ] && ok "M1 꼬리 상한 뺌 → ① 12줄 · 원본 6줄" || bad "M1 변이 $m줄 · 원본 $(nl_)줄" ""
  mutate "$CA0" M2 's/t = b.decode("utf-8")/t = b.decode("utf-8", "replace")/' '"utf-8", "replace")' || bad "M2 적용 실패" ""
  fresh; CA="$MUT"; app "$D/r9001.md" "$TMP/draft_euc"; m=$RC; mp=0; [ "$(git -C "$TMP/o.git" rev-parse ops/main-base)" != "$OREF" ] && mp=1
  fresh; CA="$CA0"; app "$D/r9001.md" "$TMP/draft_euc"
  [ "$m" = 0 ] && [ "$mp" = 1 ] && [ "$RC" = 4 ] && ok "M2 UTF-8 검사 뺌 → ⑤ push 1 · 원본 rc 4" || bad "M2 변이 rc=$m push=$mp · 원본 rc=$RC" ""
  mutate "$CA0" M3 's/ --refmap= / /' 'fetch -q --no-tags origin' || bad "M3 적용 실패" ""
  CA="$MUT"; case7; m=$R7; CA="$CA0"; case7
  [ "$m" = 3 ] && [ "$R7" = 0 ] && ok "M3 --refmap= 뺌 → ⑦ rc 3 · 원본 rc 0" || bad "M3 변이 rc=$m · 원본 rc=$R7" "$O7"
  mutate "$CA0" M4 's/^if after:$/if False and after:/' 'if False and after:' || bad "M4 적용 실패" ""
  CA="$MUT"; case9; m=$PUSH9; CA="$CA0"; case9
  [ "$m" = 1 ] && [ "$R9" = 2 ] && [ "$PUSH9" = 0 ] && ok "M4 마지막 절 검사 뺌 → ⑨ push 1 · 원본 rc 2" || bad "M4 변이 push=$m · 원본 rc=$R9" "$O9"
fi
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
