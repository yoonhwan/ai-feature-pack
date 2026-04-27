# baton — Codex CLI 어댑터 가이드

## 개요

Codex CLI에서 baton을 사용하는 패턴입니다.
Codex는 sandbox 실행 환경이므로 baton CLI를 직접 호출하는 방식으로 연동합니다.

---

## 사전 요구사항

- baton 설치됨 (`~/.baton/current/bin/baton` 존재)
- Codex CLI 설치됨
- `BATON_HOME` 환경변수 설정 (기본: `~/.baton/current`)

---

## 기본 사용 패턴

### 세션 시작 시 상태 확인

```bash
# Codex 세션 시작 전 baton 상태 확인
baton status

# 또는 on_session_start 동등 (Hermes 어댑터 활용)
python ~/.hermes/plugins/baton.py on_session_start 2>/dev/null || baton status
```

### Codex 실행 시 baton 컨텍스트 주입

```bash
# 워크트리 안에서 Codex 실행 — NEXT.md를 시스템 프롬프트로 주입
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -c model='gpt-4.1' \
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
3. .baton/handoff/NEXT.md 에 다음 세션 안내 작성
```

---

## JOURNAL.md 수동 기록

Codex 세션 내에서 직접 JOURNAL.md를 append:

```bash
cat >> .baton/handoff/JOURNAL.md << 'EOF'

## $(date '+%Y-%m-%d %H:%M') — Turn N
- **INTENT**: Codex 작업 내용
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
