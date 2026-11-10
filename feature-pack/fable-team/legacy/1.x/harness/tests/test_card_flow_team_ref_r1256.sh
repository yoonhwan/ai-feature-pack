#!/usr/bin/env bash
# test_card_flow_team_ref_r1256.sh — r1256: ft-card-flow.sh 는 --dir 없이 루트 표(directive-roots.tsv)에 그 팀 행이 있으면 «체크아웃 파일» 이 아니라 그 ref 에서 카드를 읽는다.
# R1 체크아웃이 ref 보다 2커밋 뒤 · 진행 카드 A 가 ref 에서는 완성 → 진행 수·이동 먼저에 A 0 / R2 ref 에만 있는 진행 카드 B 는 센다 / R3 표에 없는 팀 = 파일 길 + «(체크아웃 기준)» /
# R4 ref 없음 = «카드 숫자 확인 불가(ref 없음 <ref>)» rc3 / R5 체크아웃 = ref 면 파일 길(--dir)과 같은 출력.
# 전부 mktemp — 임시 bare 원격·임시 clone·가짜 tmux(PATH). 실 좌석·실 워크트리·실 kill 0 · 자기 재호출 0 · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_NEWS_ROOT FT_NEWS_TREE FT_TEAMS_REF FT_FINISHED_MAIN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; KIT="$REPO/harness/kit/fable-team/bin"; BIN="$REPO/harness/bin"
CF="${R1256_CF:-$KIT/ft-card-flow.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }

bash -n "$BIN/ft-card-flow.sh" && ok "bash -n" || bad "bash -n"
cmp -s "$BIN/ft-card-flow.sh" "$KIT/ft-card-flow.sh" && ok "키트 사본 cmp 0" || bad "키트 사본 불일치"

FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
[ -f "$SESS" ] || { echo "no server running on /tmp/x" >&2; exit 1; }
case "\$1" in ls) cat "$SESS";; *) exit 1;; esac
EOF
chmod 755 "$FAKE/tmux"
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }

G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
card() { mkdir -p "$(dirname "$1")"; printf '# %s\n## 상태\n%s\n' "$(basename "$1" .md)" "${2:-}" > "$1"; }
git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/w" 2>/dev/null
# c0: alpha 진행 A·c · beta 진행 b1 · delta 진행 d1 (체크아웃이 가진 옛 판)
card "$T/w/design/alpha/indices/진행/A.md"; card "$T/w/design/alpha/indices/진행/c.md"
card "$T/w/design/beta/indices/진행/b1.md"; card "$T/w/design/delta/indices/진행/d1.md"
G "$T/w" add -A >/dev/null; G "$T/w" commit -q -m c0; LANDED="$(G "$T/w" rev-parse HEAD)"; G "$T/w" push -q origin main 2>/dev/null
git clone -q "$T/origin.git" "$T/root" 2>/dev/null
# ref 쪽 2커밋: A 완성으로 이동 + B 신설 / 착지 줄 카드 land1 + 대기 W (알파만 바뀜 — delta 는 같음)
G "$T/w" mv design/alpha/indices/진행/A.md design/alpha/indices/완성/A.md 2>/dev/null || { mkdir -p "$T/w/design/alpha/indices/완성"; G "$T/w" mv design/alpha/indices/진행/A.md design/alpha/indices/완성/A.md; }
card "$T/w/design/alpha/indices/진행/B.md"; G "$T/w" add -A >/dev/null; G "$T/w" commit -q -m c1
card "$T/w/design/alpha/indices/진행/land1.md" "- 착지: $LANDED (DA 닫힘 x#§1)"; card "$T/w/design/alpha/indices/대기/W.md"
G "$T/w" add -A >/dev/null; G "$T/w" commit -q -m c2; G "$T/w" push -q origin main 2>/dev/null
R="$T/root"; G "$R" fetch -q origin
[ -f "$R/design/alpha/indices/진행/A.md" ] && ok "전제: 체크아웃은 옛 판(A 가 진행에 있음)" || bad "전제 깨짐"
[ "$(G "$R" rev-list --count HEAD..origin/main)" = 2 ] && ok "전제: 체크아웃이 origin/main 보다 2커밋 뒤" || bad "전제 깨짐(2커밋)"

mkdir -p "$R/.fable-team/state"
printf 'alpha\t.\torigin/main\tdesign/alpha/indices\ngamma\t.\torigin/nope\tdesign/gamma/indices\ndelta\t.\torigin/main\tdesign/delta/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
export FT_FINISHED_MAIN=origin/main
run() { PATH="$FAKE:$PATH" bash "$CF" --root "$R" "$@" 2>&1; }

# R1·R2: alpha — ref 기준(진행 B·c·land1 = 3 · 좌석 1 = c · 착지됐는데 진행 1 = land1 · 대기 W 1) · A 는 어디에도 없다
sess "byz-alpha-nano-c#0"
o="$(run --team alpha)"; rc=$?
[ "$rc" = 0 ] && [ "$o" = "카드 대기 1 · 진행 3(좌석 1) · 착지됐는데 진행 1" ] && ok "R1·R2 ref 기준 숫자 · 표시 없음 · rc0" || bad "R1·R2 rc=$rc «${o}»"
w="$(run --team alpha --warn)"
has "$w" "WARN 카드 흐름 — alpha 진행 3(좌석 1)" "R1 --warn 줄(진행 3)"
has "$w" "land1.md" "R2·착지 카드는 이동 먼저에 든다"
hasnt "$w" "A.md" "R1 이동 먼저에 A 0"
sess "byz-alpha-nano-zz#0"
w="$(run --team alpha --warn)"
has "$w" "진행 3(좌석 0)" "R2 ref 에만 있는 B 포함 → 진행 3(B·c·land1 · A 빠짐)"

# R3: 표에 없는 팀 beta = 체크아웃 파일 길 + 출력 끝 «(체크아웃 기준)»
o="$(run --team beta)"; rc=$?
[ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0 (체크아웃 기준)" ] && ok "R3 표 없는 팀 = 파일 길 + «(체크아웃 기준)»" || bad "R3 rc=$rc «${o}»"

# R4: ref 없음 = 확인 불가 rc3 (빈칸·0 금지)
o="$(run --team gamma)"; rc=$?
[ "$rc" = 3 ] && has "$o" "카드 숫자 확인 불가(ref 없음 origin/nope)" "R4 ref 없음 → 확인 불가 · rc3" || bad "R4 rc=$rc «${o}»"

# R5: 체크아웃 = ref(delta 는 두 커밋이 안 건드림) → 파일 길(--dir)과 같은 출력(회귀)
a="$(run --team delta)"; b="$(run --team delta --dir "$R/design/delta")"
[ "$a" = "$b" ] && [ "$a" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ] && ok "R5 낡음 0 → 파일 길과 같은 출력" || bad "R5 ref «${a}» ≠ 파일 «${b}»"

echo "fail=$fail"; [ "$fail" -eq 0 ]
