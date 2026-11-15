#!/usr/bin/env bash
# test_h_land_template_r2014.sh — r2014: 착지 h 틀(kit templates/h-land.sh.tmpl)의 landed() = ft-land-verify.sh 1줄(r1814 B2)
#   T1 다른 커밋 본문 «PR #7 은 … 병합 0» → landed rc≠0 · precheck «7=착지됨» 0 · T2 squash «PR #7 (head S)» → rc0
#   T3 세트가 main 조상(FF) → rc0 · T4 «PR #7 (head 다른 sha)» → rc≠0
#   변이 M1 = 옛 grep -qF "PR #$1 " → T1 FAIL · M2 = PR 번호만(^PR #N \(head ) → T4 FAIL
#   세계 = 사례마다 임시 bare 원격 + 가짜 R(.fable-team · 가짜 ft-autonomy·ft-merge-land) + 가짜 gh · 실 리포·실 gh·실 착지 0 · sleep 0
set -u
T_START=$SECONDS; fail=0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team"; TPL="$KIT/templates/h-land.sh.tmpl"; LV="$KIT/bin/ft-land-verify.sh"
GOV="$HERE/../../skill/references/main-team-governance.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: ${2:0:400}}"; fail=$((fail+1)); }
step() { echo "== $1 (누적 $((SECONDS - T_START))초)"; }
G() { git -C "$P" "$@" >/dev/null 2>&1; }

world() {  # world <이름> — P(작업 사본) · S(세트) · O(다른 sha) · OLD(main 앞) · R(가짜 루트)
  D="$TMP/$1"; P="$D/p"; R="$D/R"; mkdir -p "$D/stub" "$D/lb" "$R/.fable-team/bin" "$D/sd/autonomy-merge-approved"
  git init -q --bare "$D/o.git"; git init -q -b main "$P"; G remote add origin "$D/o.git"
  echo a > "$P/a"; G add a; G commit -qm base; G push -q origin main; OLD="$(git -C "$P" rev-parse HEAD)"
  G switch -qc feat; echo f > "$P/f"; G add f; G commit -qm feat; S="$(git -C "$P" rev-parse HEAD)"; G push -q origin feat
  G switch -qc other main; echo o > "$P/o"; G add o; G commit -qm other; O="$(git -C "$P" rev-parse HEAD)"; G switch -q main
  cp "$LV" "$D/lb/"; printf '%s\n' "$D/lr" > "$R/.fable-team/LIVE_ROOT"; printf '%s\n' "$D/lb" > "$R/.fable-team/LIVE_BIN"
  printf '#!/usr/bin/env bash\necho %s\n' "$D/sd" > "$R/.fable-team/bin/ft-autonomy.sh"
  printf '#!/usr/bin/env bash\necho "DRY 가짜 착지 판정 OK"\n' > "$R/.fable-team/bin/ft-merge-land.sh"
  printf '#!/usr/bin/env bash\necho "OPEN|%s"\n' "$S" > "$D/stub/gh"; chmod +x "$D/stub/gh"; : > "$D/sd/autonomy-merge-approved/$S"
}
inst() {  # inst <틀> → $D/h.sh (자리표 채움)
  sed -e "s|@ROOT@|$R|g" -e "s|@REPO@|$P|g" -e "s|@PR@|7|g" -e "s|@SET@|$S|g" -e "s|@HEADSHA@|$S|g" -e "s|@OLD@|$OLD|g" \
      -e "s|@BRANCH@|feat|g" -e "s|@WORK@|r0000-t|g" -e "s|@SEATS@|byz-t-master#1|g" -e "s|@EXPECT@|LANDED pr=7|g" "$1" > "$D/h.sh"
}
main_commit() {  # main_commit <본문> [트리 sha] — main 위에 커밋 1개(ft-merge-land squash 꼴 commit-tree) + push
  local tr="${2:-$(git -C "$P" rev-parse "main^{tree}")}" c
  c="$(git -C "$P" commit-tree "$tr" -p main -m "$1")"; G update-ref refs/heads/main "$c"; G push -q origin main
}
lnd() {  # lnd → 틀의 landed() 1줄만 꺼내 부른 rc
  ( git -C "$P" fetch -q origin main; LB="$D/lb"; HEADSHA="$S"; eval "$(grep -m1 '^landed()' "$D/h.sh")"; landed 7 "$S" >/dev/null 2>&1 )
}
T1() { world "t1$2"; inst "$1"; main_commit "$(printf '[fix] r2009 분류표\n\nr1716 PR #7 은 아직 병합 0')"
  lnd && return 1; local o; o="$(PATH="$D/stub:$PATH" bash "$D/h.sh" --precheck 2>&1)"
  case "$o" in *"7=착지됨"*) return 1;; *"PRECHECK OK"*) return 0;; *) echo "  precheck: ${o:0:300}"; return 1;; esac; }
T2() { world "t2$2"; inst "$1"; main_commit "$(printf 'feat (#7)\n\nPR #7 (head %s)' "$S")" "$(git -C "$P" rev-parse "$S^{tree}")"; lnd; }
T3() { world "t3$2"; inst "$1"; G push -q origin "$S:main"; lnd; }
T4() { world "t4$2"; inst "$1"; main_commit "$(printf 'feat (#7)\n\nPR #7 (head %s)' "$O")" "$(git -C "$P" rev-parse "$S^{tree}")"; ! lnd; }
mut() { ML="$2" awk '/^landed\(\)/ { print ENVIRON["ML"]; next } { print }' "$TPL" > "$TMP/$1.tmpl"; }   # ENVIRON = awk -v 의 \( 풀이 0

step "사전: 틀 · 문법 · 자리표 · landed 1줄 · 안내 1줄"
[ -f "$TPL" ] || { bad "틀 없음 $TPL"; echo "FAILED $fail"; exit 1; }
world s0; inst "$TPL"
bash -n "$D/h.sh" 2>/dev/null && /bin/bash -n "$D/h.sh" 2>/dev/null && ok "채운 틀 bash -n(/bin/bash 3.2 포함)" || bad "채운 틀 bash -n"
grep -qE '@[A-Z]+@' "$D/h.sh" && bad "남은 자리표 $(grep -oE '@[A-Z]+@' "$D/h.sh" | sort -u | tr '\n' ' ')" || ok "자리표 남김 0"
[ "$(grep -c '^landed()' "$TPL")" = 1 ] && grep -q '^landed() { bash "$LB/ft-land-verify.sh" "$P" "$1" "$2" --since "$OLD" --head "$HEADSHA" >/dev/null; }' "$TPL" && ok "landed() = ft-land-verify 1줄" || bad "landed() 꼴 다름"
grep -qE 'format=%B|grep -q[EF]* "\^?PR #' "$TPL" && bad "틀에 본문 grep 줄" || ok "본문 grep 줄 0"
grep -qF '착지 h 는 `templates/h-land.sh.tmpl` 에서 만든다 · 앞 h 복사 0' "$GOV" && ok "안내 1줄(main-team-governance)" || bad "안내 1줄 없음"

step "T1~T4 (원본 틀)"
for c in T1 T2 T3 T4; do $c "$TPL" o && ok "$c" || bad "$c"; done

step "변이 M1·M2 (원본 대조)"
mut m1 'landed() { L=$(mktemp); git -C "$P" merge-base --is-ancestor "$2" origin/main && return 0; git -C "$P" log origin/main -80 --format=%B > "$L" || return 1; grep -qF "PR #$1 " "$L"; }'
T1 "$TMP/m1.tmpl" m1 && bad "M1(옛 grep -qF) 인데 T1 통과" || ok "M1 → T1 FAIL"
mut m2 'landed() { L=$(mktemp); git -C "$P" merge-base --is-ancestor "$2" origin/main && return 0; git -C "$P" log origin/main -80 --format=%B > "$L" || return 1; grep -qE "^PR #$1 \(head " "$L"; }'
T4 "$TMP/m2.tmpl" m2 && bad "M2(PR 번호만) 인데 T4 통과" || ok "M2 → T4 FAIL"

echo "단계별 초: 전체 $((SECONDS - T_START))"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
