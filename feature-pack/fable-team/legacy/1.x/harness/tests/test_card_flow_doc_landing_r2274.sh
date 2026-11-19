#!/usr/bin/env bash
# test_card_flow_doc_landing_r2274.sh — r2274: ft-card-flow «착지됐는데 진행» 이 카드 문서만 바꾼 합침을 구현 착지로 세지 않는다(카드 반례 ⑤ ⑥ · 변이 M1 · M3)
#   ⑤ 진행 카드 2장 · 마지막 착지 줄 = 카드 .md 만 바꾼 합침 → «착지됐는데 진행 0 · 문서 착지 2» · --warn 출력 0(rc 밖)
#   ⑥ 구현 착지 3꼴(ⓐ 코드 + 카드 .md · ⓑ design/rag/sql/*.sql + 카드 .md · ⓒ kit/fable-team/templates/team/indices 배포 템플릿) → 지금과 같음(L 3 · «문서 착지» 칸 없음)
#   판정 = ft-land-kind-lib.sh ft_land_kind 한 곳(bin · kit 같은 글자)
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)만. 실 좌석·실 카드·실 tmux 0. 사례 70초·sleep 0. 기준판 = ⑤ Red(착지됐는데 진행 2)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_CAP_FLOOR FT_CARD_CAP_OK FT_FINISHED_MAIN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
for f in ft-card-flow.sh ft-land-kind-lib.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "bin·kit cmp 0 $f" || bad "bin·kit 불일치 $f"
done
CF="$KIT/ft-card-flow.sh"
FAKE="$T/fake"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "no server running on /tmp/x" >&2; exit 1\n' > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
export FT_FINISHED_MAIN=main

R="$T/repo"; mkdir -p "$R/design/alpha/indices/진행"; git init -q -b main "$R"
G(){ git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base
P="$R/design/alpha/indices/진행"
# 카드 신설 합침(카드 .md + 덧붙일 파일) → 그 sha 를 같은 카드의 «- 착지:» 줄로
landed(){ local name="$1"; shift; printf '# %s\n' "$name" > "$P/$name.md"; for x in "$@"; do mkdir -p "$(dirname "$R/$x")"; echo y > "$R/$x"; done
  G add -A >/dev/null; G commit -q -m "card $name"; printf '# %s\n- 착지: %s\n' "$name" "$(G rev-parse HEAD)" > "$P/$name.md"; G add -A >/dev/null; G commit -q -m "land $name"; }
run(){ PATH="$FAKE:$PATH" bash "${CFX:-$CF}" --team alpha --root "$R" --dir "$R/design/alpha" "$@" 2>&1; }

# ⑤ 카드 문서만 2장
landed d1; landed d2
o="$(run)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 2(좌석 0 · 관찰 대기 0) · 착지됐는데 진행 0 · 문서 착지 2" ]; } && ok "⑤ 문서만 2 → 착지됐는데 진행 0 · 문서 착지 2" || bad "⑤ rc=$rc «${o}»"
o="$(run --warn)"; rc=$?
{ [ "$rc" = 0 ] && [ -z "$o" ]; } && ok "⑤ --warn 출력 0 · rc0" || bad "⑤ warn rc=$rc «${o}»"

# ⑥ 구현 착지 3꼴 → L 3 · 문서 착지 칸 없음
rm -f "$P"/d1.md "$P"/d2.md; G add -A >/dev/null; G commit -q -m rm
landed c1 src/app.py; landed s1 design/rag/sql/m6.sql; landed t1 kit/fable-team/templates/team/indices/대기/t.md
o="$(run)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 3(좌석 0 · 관찰 대기 0) · 착지됐는데 진행 3" ]; } && ok "⑥ 코드·SQL·템플릿 착지 → 착지됐는데 진행 3(지금과 같음)" || bad "⑥ rc=$rc «${o}»"
o="$(run --warn)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "WARN 카드 흐름 — alpha 진행 3(좌석 0 · 관찰 대기 0) · 착지됐는데 진행 3 · 이동 먼저: "* ]]; } && ok "⑥ --warn 지금과 같음" || bad "⑥ warn rc=$rc «${o}»"

# ── 변이(사본에서만 · 원본 사례는 위 ⑤ ⑥) ──
mut(){ mkdir -p "$T/$1"; cp "$CF" "$T/$1/ft-card-flow.sh"; python3 - "$KIT/ft-land-kind-lib.sh" "$T/$1/ft-land-kind-lib.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mut m1 '"카드 문서만" if paths' '"구현" if paths'     # M1 늘 «구현»
BOUND='x.startswith("design/") and "/indices/" in x'
mut m3 "$BOUND" 'x.startswith("design/")'          # M3 경계 design/* 로 넓힘
mut m3b "$BOUND" '"/indices/" in x'                 # M3 경계 */indices/* 로 풂
o="$(CFX="$T/m1/ft-card-flow.sh" run)"
[[ "$o" == *"착지됐는데 진행 3" ]] && ok "M1 늘 구현 → ⑥ 그대로 · 아래 ⑤ 재생에서 FAIL 확인" || bad "M1 ⑥ «${o}»"
o="$(CFX="$T/m3/ft-card-flow.sh" run)"
[[ "$o" == *"착지됐는데 진행 2 · 문서 착지 1" ]] && ok "M3 design/* → ⑥ⓑ FAIL(SQL 착지를 문서만으로 봄)" || bad "M3 «${o}»"
o="$(CFX="$T/m3b/ft-card-flow.sh" run)"
[[ "$o" == *"착지됐는데 진행 2 · 문서 착지 1" ]] && ok "M3b */indices/* → ⑥ⓒ FAIL(템플릿을 문서로 봄)" || bad "M3b «${o}»"
rm -f "$P"/c1.md "$P"/s1.md "$P"/t1.md; G add -A >/dev/null; G commit -q -m rm2; landed d3; landed d4
o="$(CFX="$T/m1/ft-card-flow.sh" run)"
[[ "$o" == *"착지됐는데 진행 2" ]] && ok "M1 늘 구현 → ⑤ FAIL(문서만 2 를 L 로 셈)" || bad "M1 ⑤ «${o}»"
o="$(run)"
[[ "$o" == *"착지됐는데 진행 0 · 문서 착지 2" ]] && ok "M1 대조 원본 ⑤ PASS" || bad "M1 대조 원본 «${o}»"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
