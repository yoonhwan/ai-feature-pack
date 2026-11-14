#!/usr/bin/env bash
# test_child_watch_card_ref_r1655.sh — ft-child-watch [유휴 나노] 카드 = 카드 ref 먼저(r1655 · Issue #8303)
#   tmp git 리포 1개(카드 = 가지 cards 에만 커밋 · 작업 트리 = 빈 main) · FT_CARD_REF=cards(로컬 ref · fetch 0) · 실 tmux·실 우편함 0 · sleep 0
#   가짜 나무 = lib/r1113_fake_tree.sh · 발신 = FT_CHILD_MBOX_SH 스텁(기록만) · 변이 M1·M2 = 사본에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
W="${W_SCRIPT:-$BIN/ft-child-watch.sh}"
TMP="$(mktemp -d)"; . "$HERE/lib/r1113_fake_tree.sh"; fake_init; trap fake_cleanup EXIT
pass=0; fail=0; T0=$(date +%s)
ck() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; sed 's/^/    | /' "$TMP/last" 2>/dev/null | tail -6; fail=$((fail+1)); fi; }
R="$TMP/root"; I="design/harness/indices"; mkdir -p "$R/.fable-team/state" "$TMP/cw"
export FT_ROOT="$R" FT_CHILD_STATE_DIR="$TMP/cw" FT_CHILD_WATCH_EVERY_SEC=0 FT_CHILD_MBOX_SH="$TMP/fake/mbox" FT_SEAT_QUIESCE_BIN="$BIN/ft-seat-quiesce.sh" FT_CHILD_AUTONOMY=off
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
printf 'echo "$2|$4" >> "%s"\n' "$TMP/sent" > "$TMP/fake/mbox"; : > "$TMP/sent"
g() { git -C "$R" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
g init -q -b main; g commit -q --allow-empty -m base; g switch -q -c cards
mkdir -p "$R/$I/완성" "$R/$I/진행"
printf '# c1\n## 상태\n- 2026-11-11 — 착지\n' > "$R/$I/완성/c1.md"
printf '# c2\n## 상태\n- 2026-11-11 — 진행\n- 세트: %s\n' "$(printf 'a%.0s' $(seq 40))" > "$R/$I/진행/c2.md"
printf '# c3\n## 상태\n- 2026-11-11 — 대기→진행 · 작업 중\n' > "$R/$I/진행/c3.md"
g add design; g commit -q -m cards; g switch -q main
[ -e "$R/$I" ] && echo "WARN 작업 트리에 카드가 남음"
cat > "$R/.fable-team/seats-harness.json" <<EOF
{"_master": "HM#1", "N1": {"role": "nano", "agent": "pi", "index": "$I/진행/c1.md"}, "N2": {"role": "nano", "agent": "pi", "index": "$I/진행/c2.md"},
 "N3": {"role": "nano", "agent": "pi", "index": "$I/진행/c3.md"}, "N4": {"role": "nano", "agent": "pi", "index": "$I/진행/c4.md"}}
EOF
tree N1 31; tree N2 31; tree N3 31; tree N4 31
w() { : > "$TMP/sent"; : > "$TMP/cw/child-watch.sent"; bash "${WB:-$W}" > "$TMP/last" 2>&1; }
sent() { grep -c -- "$1" "$TMP/sent" | tr -d ' '; }
FT_CARD_REF=cards w
c1() { [ "$(sent 'HM#1|\[유휴 나노\] N1 유휴 31분 · 카드 완성 폴더')" = 1 ]; }
c2() { [ "$(sent 'HM#1|\[유휴 나노\] N2 유휴 31분 · 카드 - 세트: aaaa')" = 1 ]; }
c3() { [ "$(sent 'N3')" = 0 ]; }
c4() { [ "$(sent 'N4')" = 0 ] && grep -q 'nano=2 ' "$TMP/last"; }
ck "ⓒ① 카드가 ref 완성/ 에만 · 유휴 31분 → [유휴 나노] 1통 «카드 완성 폴더»" c1
ck "ⓒ② ref 진행/ 상태 마지막 줄 = 세트 줄 → 1통" c2
ck "ⓒ③ ref 진행/ 상태 = 작업 중 → 0통" c3
ck "ⓒ④ ref·작업 트리 모두 없음 → 카드 못 찾음 0통" c4
printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\tcards\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
ck "ⓑ FT_CARD_REF 없음 → directive-roots.tsv 의 harness 행 ref" eval '( unset FT_CARD_REF; w ); c1 && c2'
printf '*\t.\tnope-ref\tx\n' > "$R/.fable-team/state/directive-roots.tsv"
ck "ⓑ 팀 행 없음 → «*» 행(없는 ref) → 작업 트리 길 · 0통" eval '( unset FT_CARD_REF; w ); [ "$(sent "유휴 나노")" = 0 ]'
mkdir -p "$TMP/wbin"; cp -p "$BIN/ft-harness-root.sh" "$TMP/wbin/"
sed "s/ if m else ()/ if False else ()/" "$W" > "$TMP/wbin/M1.sh"; cmp -s "$W" "$TMP/wbin/M1.sh" && echo "WARN 변이 M1 이 원본과 같음"
sed 's/("진행", "완성", "아카이브", "대기")/("진행", "아카이브", "대기")/' "$W" > "$TMP/wbin/M2.sh"; cmp -s "$W" "$TMP/wbin/M2.sh" && echo "WARN 변이 M2 가 원본과 같음"
for f in M1 M2; do cp "$TMP/wbin/$f.sh" "$TMP/wbin/ft-child-watch.sh"; WB="$TMP/wbin/ft-child-watch.sh" FT_CARD_REF=cards w
  ck "변이 $f → ⓒ① FAIL(잡힘)" eval '! c1'; done
echo "단계별 초: child-watch-card-ref $(( $(date +%s) - T0 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
