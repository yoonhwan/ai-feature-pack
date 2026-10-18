#!/usr/bin/env bash
# _proposal_issue_env.sh — 제안 Issue 도구(open·approve·inbox) 시험 공용 환경(source 용). 실 gh·실 슬랙·실 tmux 0.
#   가짜 Tank: 호출 한 줄(`create …`·`comment 12 …`·`label 12 --add approved …`)을 $TANK_LOG 에 적고, 첫 번째 «파일 인자» 내용을 $T/body-<호출 순번> 으로 보관한다.
#   가짜 gh 읽기(FT_GH_READ): issue list(--label 이 있으면 inbox 용 list-inbox.json · 없으면 find 용 list-find.json · 기본 []) · issue view N → view-N.json · api …/timeline → timeline-N.json
#   GH_FAIL=1 이면 rc 1. 변형 픽스처 = _proposal_issue_fixture.py.
# shellcheck disable=SC2034  # source 되는 파일 — 변수는 부르는 시험 스크립트가 쓴다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROP="$HERE/../../scripts/harness-install/proposal"; FX="$HERE/_proposal_issue_fixture.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TANK_LOG="$T/tank.log" TANK_DIR="$T" FAKE="$T" GH_REPO="test/repo" FT_PLANNER_VERDICTS_DIR="$T/planner"; mkdir -p "$T/planner"
cat > "$T/fake-tank.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TANK_LOG"; idx="$(wc -l < "$TANK_LOG" | tr -d ' ')"
for a in "$@"; do [ -f "$a" ] && { cp "$a" "$TANK_DIR/body-$idx"; break; }; done
case "$1" in
  label) [ -n "${TANK_FAIL_LABEL:-}" ] && { echo boom >&2; exit 1; }; echo "OK as=byz-tank label";;
  comment) [ -n "${TANK_FAIL_COMMENT:-}" ] && { echo boom >&2; exit 1; }; echo "OK as=byz-tank comment";;
  create) [ -n "${TANK_FAIL_CREATE:-}" ] && { echo boom >&2; exit 1; }; echo "OK as=byz-tank create — PAIR issue=#901 manager=x";;
  *) echo "OK as=byz-tank $1";;
esac
EOF
cat > "$T/fake-gh.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && { echo "gh: network" >&2; exit 1; }
case "$1 $2" in
  "issue list") case " $* " in *" --label "*) cat "$FAKE/list-inbox.json" 2>/dev/null || echo '[]';; *) cat "$FAKE/list-find.json" 2>/dev/null || echo '[]';; esac;;
  "issue view") cat "$FAKE/view-$3.json";;
  "api --paginate") n="${4#repos/*/issues/}"; cat "$FAKE/timeline-${n%/timeline}.json";;
  *) exit 1;;
esac
EOF
export FT_TANK_CMD="bash $T/fake-tank.sh" FT_GH_READ="bash $T/fake-gh.sh"
calls() { [ -f "$TANK_LOG" ] && wc -l < "$TANK_LOG" | tr -d ' ' || echo 0; }
n_of() { { grep -c "^$1 " "$TANK_LOG" 2>/dev/null || true; } | head -1; }
reset() { : > "$TANK_LOG"; rm -f "$T"/body-* "$T"/list-*.json "$T"/view-*.json "$T"/timeline-*.json; }
fx() { python3 "$FX" "$T" "$@"; }
