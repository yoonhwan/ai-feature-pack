#!/usr/bin/env bash
# _proposal_register_env.sh — ft-proposal-register.sh 시험 공용 환경(source 용): 임시 git 리포 · 가짜 Tank · 가짜 gh 읽기(FT_GH_READ).
#   원격·실 LLM 0. 가짜 Tank 는 호출을 TANK_LOG 에 적고 본문 파일을 $T/body-<호출 순번> 으로 보관한다.
#   가짜 gh 읽기: `issue list` → $T/gh-list.json(기본 []) · `issue view N` → $T/gh-view-N.json · GH_FAIL=1 이면 rc=1.
# shellcheck disable=SC2034  # source 되는 파일 — 변수는 부르는 시험 스크립트가 쓴다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REG="$HERE/../../scripts/harness-install/proposal/ft-proposal-register.sh"
LIB="$HERE/../../scripts/harness-install/proposal/proposal_register_lib.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TANK_LOG="$T/tank.log" TANK_DIR="$T" GH_REPO="test/repo" FT_PROPOSAL_STATE="$T/state.json" GH_T="$T"
cat > "$T/fake-tank.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$TANK_LOG"; idx="$(wc -l < "$TANK_LOG" | tr -d ' ')"
[ -f "${3:-}" ] && cp "$3" "$TANK_DIR/body-$idx"
case "$1" in
  create) [ -n "${TANK_FAIL_CREATE:-}" ] && { echo "boom" >&2; exit "${TANK_FAIL_CREATE_RC:-1}"; }
          [ -n "${TANK_CREATE_NO_NUMBER:-}" ] && { echo "OK created"; exit 0; }
          echo "OK as=byz-tank create — PAIR issue=#901 manager=x";;
  comment) n="$(grep -c '^comment$' "$TANK_LOG")"; [ "${TANK_FAIL_COMMENT_N:-0}" = "$n" ] && exit 1; echo "OK comment";;
  label)  [ -n "${TANK_FAIL_LABEL:-}" ] && exit 1; echo "OK as=byz-tank label $2";;
esac
EOF
cat > "$T/fake-gh.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && { echo "gh: network" >&2; exit 1; }
if [ "$1 $2" = "issue list" ]; then cat "$GH_T/gh-list.json" 2>/dev/null || echo '[]'; exit 0; fi
if [ "$1 $2" = "issue view" ]; then cat "$GH_T/gh-view-$3.json" 2>/dev/null || { echo "not found" >&2; exit 1; }; exit 0; fi
exit 1
EOF
export FT_TANK_CMD="bash $T/fake-tank.sh" FT_GH_READ="bash $T/fake-gh.sh"
calls() { [ -f "$TANK_LOG" ] && wc -l < "$TANK_LOG" | tr -d ' ' || echo 0; }
n_of() { { grep -c "^$1\$" "$TANK_LOG" 2>/dev/null || true; } | head -1; }
reset() { : > "$TANK_LOG"; rm -f "$T"/body-* "$T"/gh-list.json "$T"/gh-view-*.json "$FT_PROPOSAL_STATE"; }

# 임시 git 리포 — 제안서는 «커밋된 그대로» 여야 등록된다(경로@sha)
R="$T/repo"; mkdir -p "$R/design/feature"; git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
# mkn <파일 이름> <상태 머리줄> <검증 본문|-> [추가 본문줄] → 커밋된 제안서 경로
mkn() {
  local f="$R/design/feature/$1"
  { echo '# 제안서 — 줄바꿈 CSS'; echo "- 상태: $2"; echo; echo '## 결론'; echo '한 줄이면 된다.'
    [ "$3" != "-" ] && { echo; echo '## 검증'; printf '%b\n' "$3"; }
    [ -n "${4:-}" ] && { echo; echo "$4"; }; } > "$f"
  git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm "p $1" >/dev/null 2>&1; echo "$f"
}
mk() { mkn "PROPOSAL-t$RANDOM-20261008.md" "$@"; }
GOODV='화면에서 줄이 단어 중간에서 안 끊긴다.'
sha16() { shasum -a 256 "$1" | cut -c1-16; }
pid_of() { echo "test/repo:design/feature/$(basename "$1")@판정$2#$(sha16 "$1")"; }
# view_json <번호> <본문 첫 줄 표식 ID> [제목] / list_json <번호> <제목>
view_json() { python3 -c 'import json,sys;print(json.dumps({"title":sys.argv[3],"body":"<!-- byz-proposal-id: "+sys.argv[2]+" -->\nx"}))' "$1" "$2" "${3:-[제안서] 줄바꿈 CSS}" > "$T/gh-view-$1.json"; }
list_json() { python3 -c 'import json,sys;print(json.dumps([{"number":int(sys.argv[1]),"title":sys.argv[2]}]))' "$1" "${2:-[제안서] 줄바꿈 CSS}" > "$T/gh-list.json"; }
