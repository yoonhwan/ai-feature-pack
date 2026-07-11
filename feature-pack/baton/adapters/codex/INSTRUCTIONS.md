# baton — Codex CLI 어댑터 가이드

## 개요

Codex CLI에서 baton을 사용하는 패턴입니다.
Codex는 sandbox 실행 환경이므로 baton CLI를 직접 호출하는 방식으로 연동합니다.

---

## 사전 요구사항

- baton 설치됨 (`~/.baton/current/bin/baton` 존재)
- Codex CLI 설치됨
- `BATON_HOME` 환경변수 설정 (기본: `~/.baton/current`)
- 권장: `BATON_AGENT=codex` (미설정 시 `CODEX_THREAD_ID`, `CODEX_CI`, `CODEX_MANAGED_BY_NPM`, `OMX_SESSION_ID` 로 자동 감지)

---

## 기본 사용 패턴

### 세션 시작 시 상태 확인

```bash
# Codex 세션 시작 전 baton 상태 확인
export BATON_AGENT=codex
baton status

# 또는 on_session_start 동등 (Hermes 어댑터 활용)
python ~/.hermes/plugins/baton.py on_session_start 2>/dev/null || baton status
```

### Codex 실행 시 baton 컨텍스트 주입

```bash
# 워크트리 안에서 Codex 실행 — NEXT.md를 시스템 프롬프트로 주입
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -c model_reasoning_effort="high" \
  -C "$(pwd)" \
  "$(cat .baton/handoff/NEXT.md) --- 위 NEXT.md 내용을 참고해 작업을 이어서 진행해줘"
```

### 작업 완료 후 baton 저장

```bash
# Codex 작업 완료 후
baton save

# 또는 finish (완전 완료)
baton finish
```

---

## tmux 통합 시나리오 (BATON_TMUX_ENABLE=true)

```bash
# 1. baton 워크트리 생성 (tmux 세션 자동 생성)
export BATON_TMUX_ENABLE=true
baton wt-create my-feature "새 기능 구현"

# 2. tmux 세션에서 Codex 실행
tmux attach -t baton-{project}-my-feature
# (tmux 세션 안에서)
codex exec --dangerously-bypass-approvals-and-sandbox \
  -C "$(pwd)" \
  "$(cat .baton/handoff/NEXT.md) --- 이어서 진행해줘"

# 3. 결과를 baton에 저장
baton save
```

---

## OMX 런타임 스킬 사용

Codex 세션이 oh-my-codex(OMX)로 실행 중이면 baton의 실행 하네스는 Claude/OMC 슬래시가 아니라 OMX 스킬 키워드를 사용합니다.

```text
$deep-interview "요구사항 명확화"
$ralplan "계획 합의"
$autopilot "승인된 작업 자율 실행"
$team 3:executor "병렬 실행"
$ultraqa "검증-수정 반복"
$code-review "현재 브랜치 리뷰"
```

`preferred_execution: "runtime:auto"` 프로젝트에서는 현재 런타임이 Codex/OMX이면 위 스킬들을 우선 사용하고, 필요할 때만 `codex exec`를 fallback으로 사용합니다.

---

## Codex sandbox 제약 해결

Codex 기본 실행은 sandbox 모드입니다. baton 파일(.baton/handoff/) 쓰기가 필요하므로:

```bash
# sandbox 우회 (baton 파일 쓰기 허용)
codex --dangerously-bypass-approvals-and-sandbox
```

또는 Codex에게 baton CLI를 직접 호출하도록 지시:

```
[시스템 프롬프트 / 초기 지시]
작업 완료 후 반드시:
1. ~/.baton/current/bin/baton save 실행
2. .baton/handoff/JOURNAL.md 마지막 Turn의 ACTIONS/TODO 업데이트
3. (v1.2.14+) bash ~/.baton/current/bin/baton next-archive || true — 기존 NEXT.md 보존(스냅샷)
4. .baton/handoff/NEXT.md 에 다음 세션 안내 작성
```

---

## JOURNAL.md 수동 기록

Codex 세션 내에서 직접 JOURNAL.md를 append:

```bash
cat >> .baton/handoff/JOURNAL.md << 'EOF'

## $(date '+%Y-%m-%d %H:%M') — Turn N
- **INTENT**: Codex/OMX 작업 내용
- **HARNESS**: codex-cli
- **ACTIONS**: 구현 완료
- **TODO**: 리뷰 필요

EOF
```

---

## 멀티 에이전트 시나리오

여러 워크트리를 각기 다른 에이전트가 동시 작업:

```bash
# 워크트리 A: Claude Code 담당
cd .worktrees/feature-a/
claude  # Claude Code 세션 시작

# 워크트리 B: Codex 담당 (별도 터미널)
cd .worktrees/feature-b/
codex exec --dangerously-bypass-approvals-and-sandbox \
  -C "$(pwd)" "$(cat .baton/handoff/NEXT.md)"

# 공통: archive에 결과 누적
baton finish  # 각 워크트리에서
git push      # 크루 간 자동 sync
```

---

## /baton:resume 가드 (v1.2.5+)

워크트리/commit mismatch 자동 감지 — 4분류:

| 분류 | 조건 | 동작 |
|------|------|------|
| `match` | 워크트리 + commit 일치 | 그대로 NEXT.md 출력 |
| `commit_only` | 해시만 다름 (main 머지 등) | INFO + 1초 wait + 자동 진행 |
| `worktree_only` | 다른 워크트리 | TTY는 `[y/N]`, non-TTY는 `[baton-resume-mismatch]` stdout + NEXT.md |
| `both` | 워크트리 + commit 모두 다름 | 위와 동일 |

**Hard abort**: archive extract 경로(`/tmp/baton-extracted/*`)는 `--force`로도 우회 불가.

```bash
# mismatch 우회 (archive extract 제외)
baton resume --force
```

**non-TTY (Codex/OMX exec) 경로**: `[baton-resume-mismatch] kind=... saved_worktree=... current_worktree=...` 한 줄을 stdout으로 받으면 그대로 사용자에게 보여주고 진행 여부 확인하세요. Codex/OMX는 일반적으로 non-TTY 실행이므로 이 분기에 빠집니다.

---

## 트러블슈팅

### baton 파일 쓰기 실패

sandbox 모드에서는 `~/.baton/` 쓰기가 차단될 수 있습니다:

```bash
# sandbox 완전 우회
codex --dangerously-bypass-approvals-and-sandbox
```

### BATON_HOME 인식 안 됨

```bash
export BATON_HOME="$HOME/.baton/current"
export PATH="$BATON_HOME/bin:$PATH"
```
