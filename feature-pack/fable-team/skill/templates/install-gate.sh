#!/bin/bash
# fable-team orchestration-gate 설치 지원 (프로젝트 스코프)
# 사용: install-gate.sh [--check|--install] [--with-resolver-env] [project-dir]
#   --check              : 설치 상태만 진단 (기본)
#   --install            : 템플릿에서 프로젝트 .claude/ 로 4-레이어 설치 (멱등·백업·원자적)
#   --with-resolver-env  : settings.json env에 ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL 병합
#                          (값: 프로세스 env → <proj>/.fable-team/install.json.resolver_env). [1m] leak 교정.
# 템플릿 소스: 이 스크립트와 같은 디렉토리 (설치된 스킬의 templates/)
set -euo pipefail

MODE="--check"; PROJ=""; WITH_ENV="false"
for a in "$@"; do
  case "$a" in
    --check|--install) MODE="$a";;
    --with-resolver-env) WITH_ENV="true";;
    *) PROJ="$a";;
  esac
done
[ -z "$PROJ" ] && PROJ="$(pwd)"
# 프로젝트 루트 정규화 (git root 우선)
if GITROOT=$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null); then PROJ="$GITROOT"; fi

TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$PROJ/.claude"
HOOKS=(orchestration-gate.sh orchestration-turn-reset.sh context-distill-gate.sh)

# ── 상태 진단 ──
hook_ok=true
for h in "${HOOKS[@]}"; do [ -x "$CLAUDE_DIR/hooks/$h" ] || hook_ok=false; done
rules_ok=false; [ -f "$CLAUDE_DIR/rules/orchestration.md" ] && rules_ok=true
settings_ok=true; settings_missing=""
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  set +e
  settings_missing=$(python3 - "$CLAUDE_DIR/settings.json" "$TPL_DIR/settings-hooks.snippet.json" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f: actual = json.load(f)
    with open(sys.argv[2]) as f: snippet = json.load(f)
except Exception:
    print(" (파싱 실패)"); sys.exit(1)
missing = []
for event, entries in snippet.get("hooks", {}).items():
    actual_entries = actual.get("hooks", {}).get(event, [])
    for se in entries:
        s_matcher = se.get("matcher", "")
        s_cmds = {h.get("command", "") for h in se.get("hooks", [])}
        found = False
        for ae in actual_entries:
            if ae.get("matcher", "") == s_matcher and s_cmds <= {h.get("command", "") for h in ae.get("hooks", [])}:
                found = True; break
        if not found:
            missing.append(f"{event}/{s_matcher or '(no-matcher)'}")
if missing:
    print(" " + ", ".join(missing)); sys.exit(1)
sys.exit(0)
PYEOF
  )
  RC_CHK=$?
  set -e
  [ "$RC_CHK" != "0" ] && settings_ok=false
else
  settings_ok=false; settings_missing=" (파일 없음)"
fi

echo "─────────────────────────────────────────"
echo "📊 orchestration-gate 설치 상태 — $PROJ"
echo "─────────────────────────────────────────"
echo "  훅 3종(hooks/):      $([ "$hook_ok" = true ] && echo '✅ 설치됨' || echo '❌ 미설치')"
echo "  기준(rules/):        $([ "$rules_ok" = true ] && echo '✅ 설치됨' || echo '❌ 미설치')"
echo "  강제(settings.json): $([ "$settings_ok" = true ] && echo '✅ 연결됨 (3훅 전부)' || echo "❌ 미연결:$settings_missing")"

if [ "$MODE" = "--check" ]; then
  if [ "$hook_ok" = true ] && [ "$rules_ok" = true ] && [ "$settings_ok" = true ]; then
    echo "  → 완전 설치 상태."
  else
    echo "  → 미완. 설치하려면: install-gate.sh --install \"$PROJ\""
  fi
  exit 0
fi

# ── 설치 ──
echo ""; echo "🔧 설치 진행..."

# ① settings.json 파싱+merge dry-run (검증 우선). 깨진 기존 JSON → 중단(원본 보존, 파일 복사 0건).
#    성공 시 .tmp 생성(원자적 교체용) — 이 단계 이전엔 어떤 파일도 변경하지 않는다(부분설치 방지).
SETTINGS="$CLAUDE_DIR/settings.json"
SETTINGS_TMP="$CLAUDE_DIR/.settings.json.ftgate.tmp"
had_settings=false; [ -f "$CLAUDE_DIR/settings.json" ] && had_settings=true
mkdir -p "$CLAUDE_DIR"
set +e
python3 - "$SETTINGS" "$TPL_DIR/settings-hooks.snippet.json" "$SETTINGS_TMP" "$WITH_ENV" "$PROJ" <<'PYEOF'
import json, sys, os
sp, snp, tmp, with_env, proj = sys.argv[1:6]

# 기존 settings 파싱 — 깨진 JSON이면 중단(원본 보존, clobber 금지)
base = {}
if os.path.isfile(sp):
    try:
        with open(sp) as f:
            base = json.load(f)
    except Exception:
        sys.exit(3)          # 깨진 JSON → 설치 중단
    if not isinstance(base, dict):
        sys.exit(3)

snip = json.load(open(snp))
base.setdefault("hooks", {})
def cmd_of(h): return h.get("hooks",[{}])[0].get("command","") + "|" + h.get("matcher","")
for event, entries in snip["hooks"].items():
    cur = base["hooks"].setdefault(event, [])
    have = {cmd_of(e) for e in cur}
    for e in entries:
        if cmd_of(e) not in have:
            cur.append(e); have.add(cmd_of(e))

# P2-10: --with-resolver-env → env에 ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL 병합.
#        값 출처: 프로세스 env → <proj>/.fable-team/install.json (resolver_env or 동명 키). 없으면 생략.
if with_env == "true":
    keys = ("ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL")
    src = {}
    ij = os.path.join(proj, ".fable-team", "install.json")
    if os.path.isfile(ij):
        try:
            d = json.load(open(ij))
            if isinstance(d, dict):
                if isinstance(d.get("resolver_env"), dict):
                    src.update(d["resolver_env"])
                for k in keys:
                    if k in d:
                        src[k] = d[k]
        except Exception:
            pass
    env = base.setdefault("env", {})
    added = []
    for k in keys:
        v = os.environ.get(k) or src.get(k)
        if v:
            env[k] = v
            added.append(k)
    if added:
        print("  ✓ resolver env 병합: " + ", ".join(added))
    else:
        print("  ⏭ resolver env: 값 미발견(프로세스 env 또는 install.json.resolver_env 필요) — 생략")

with open(tmp, "w") as f:
    json.dump(base, f, ensure_ascii=False, indent=2)
with open(tmp) as f:
    json.load(f)             # dry-run 재검증 — 실패 시 예외 → rc!=0 → 중단
sys.exit(0)
PYEOF
RC=$?
set -e
if [ "$RC" != "0" ]; then
  rm -f "$SETTINGS_TMP" 2>/dev/null
  echo "  ❌ 기존 settings.json 파싱/merge 실패 — 설치를 중단합니다 (기존 파일·훅 보존, 부분설치 방지)."
  echo "     원인: 기존 $SETTINGS 이(가) 깨진 JSON이거나 병합 불가."
  echo "     조치: JSON을 수동으로 고친 뒤 다시 실행하세요. 예) python3 -m json.tool \"$SETTINGS\""
  exit 1
fi

# ② 검증 통과 → 훅·기준 복사 (여기서부터 파일 변경 시작)
mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/rules"
for h in "${HOOKS[@]}"; do
  cp "$TPL_DIR/hooks/$h" "$CLAUDE_DIR/hooks/$h"
  chmod +x "$CLAUDE_DIR/hooks/$h"
  echo "  ✓ hooks/$h"
done
cp "$TPL_DIR/rules/orchestration.md" "$CLAUDE_DIR/rules/orchestration.md"
echo "  ✓ rules/orchestration.md"

# ③ settings.json 원자적 교체 (기존은 .bak 백업 후 rename)
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak"
mv "$SETTINGS_TMP" "$SETTINGS"
echo "  ✓ settings.json (hooks 병합, 원자적 교체, 백업 .bak)"

# CLAUDE.md 선언 스니펫 (멱등 — 마커로 중복 방지). 실패해도 비치명(롤백 안 함 — 아래).
CM="$PROJ/CLAUDE.md"
cm_ok=true
if [ -d "$CM" ]; then
  cm_ok=false
  echo "  ❌ CLAUDE.md가 디렉토리입니다 — 스니펫 추가 불가"
elif [ -f "$CM" ] && grep -q "fable-team:orchestration-gate BEGIN" "$CM" 2>/dev/null; then
  echo "  ⏭ CLAUDE.md 스니펫 이미 있음"
else
  set +e
  { [ -f "$CM" ] && echo ""; cat "$TPL_DIR/CLAUDE.orchestration.snippet.md"; } >> "$CM" 2>/dev/null
  if [ $? -ne 0 ]; then cm_ok=false; echo "  ❌ CLAUDE.md 쓰기 실패"; fi
  set -e
fi

if [ "$cm_ok" = false ]; then
  # ★ 롤백하지 않는다 — CLAUDE.md(프로젝트 루트 유저 문서) 실패로 이미 원자 설치된
  #   hooks·rules·settings를 삭제하면 pre-existing(기존 설치분)까지 지워 정상 설치를 오히려 깨뜨린다
  #   (codex DA R4 지적). 선언 스니펫은 비치명·재실행 멱등이며, 게이트는 훅으로 이미 작동한다.
  echo ""
  echo "  ⚠️ CLAUDE.md 선언 스니펫 추가 실패 — **비치명**(핵심 hooks·rules·settings는 이미 설치·작동)."
  echo "     원인: CLAUDE.md가 디렉토리이거나 쓰기 불가. 게이트 자체는 정상 발동합니다."
  echo "     수동 조치(선택): $TPL_DIR/CLAUDE.orchestration.snippet.md 내용을 프로젝트 CLAUDE.md에 직접 추가."
fi

echo ""; echo "✅ orchestration-gate 설치 완료. 새 세션에서 훅이 활성화됩니다 (settings 변경 반영 = /hooks 열거나 재시작)."
