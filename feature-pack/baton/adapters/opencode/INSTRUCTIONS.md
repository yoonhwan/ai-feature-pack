# baton — OpenCode 어댑터 가이드

## 개요

OpenCode에서 baton을 사용하는 패턴입니다.
OpenCode는 `~/.config/opencode/` 기반 설정과 slash commands를 지원합니다.

---

## 사전 요구사항

- baton 설치됨 (`~/.baton/current/bin/baton` 존재)
- OpenCode 설치됨
- `~/.config/opencode/commands/baton/` 슬래시 명령 설치됨 (선택)

---

## 슬래시 명령 확인

```bash
ls ~/.config/opencode/commands/baton/
```

이미 설치되어 있으면 OpenCode 안에서:

```
/baton:status    # 상태 확인
/baton:save      # 저장
/baton:resume    # 이어서 진행
/baton:finish    # 완료
/baton:plan      # 계획 수립
```

---

## 기본 사용 패턴

### 세션 시작 시

```bash
# baton 상태 확인
baton status

# 워크트리 안에서 OpenCode 실행
cd .worktrees/my-feature/
opencode
```

### OpenCode에게 baton 컨텍스트 주입

OpenCode 프롬프트에서:

```
NEXT.md 내용을 참고해 이어서 작업해줘:

$(cat .baton/handoff/NEXT.md)
```

또는 OpenCode AGENTS.md / 시스템 프롬프트 파일 활용:

```bash
# .baton/handoff/NEXT.md 를 OpenCode 프로젝트 컨텍스트로 링크
ln -sf .baton/handoff/NEXT.md AGENTS.md
```

---

## tmux 통합 시나리오 (BATON_TMUX_ENABLE=true)

```bash
# 1. tmux 활성화
export BATON_TMUX_ENABLE=true

# 2. 워크트리 생성 → tmux 세션 자동 생성
baton wt-create opencode-task "OpenCode 작업"
# → tmux 세션: baton-{project}-opencode-task

# 3. tmux 세션에서 OpenCode 실행
tmux attach -t baton-{project}-opencode-task
opencode  # tmux 세션 안에서

# 4. 상태 모니터링 (다른 터미널)
baton status
# → "tmux: baton-{project}-opencode-task — attach: tmux a -t ..." 표시
```

---

## OpenCode 설정 통합

`~/.config/opencode/config.json` 또는 프로젝트 AGENTS.md에 추가:

```markdown
## baton 워크플로우 규칙

현재 baton 워크트리 안에서 작업 중입니다.

### 세션 시작 시 반드시 확인
- `.baton/handoff/CURRENT.md` — 현재 phase 상태 (status, phase_id)
- `.baton/handoff/NEXT.md` — 다음에 할 일
- `.baton/handoff/PLAN.md` — 전체 계획

### 작업 완료 시 반드시 실행
1. `baton save` — 현재 상태 저장
2. `.baton/handoff/JOURNAL.md` 마지막 Turn ACTIONS/TODO 업데이트
3. `.baton/handoff/NEXT.md` 갱신 — 다음 세션 안내 작성

### 키워드 트리거
"이어서" / "진행" / "go" / "continue" / "next" 입력 시 NEXT.md 확인 후 재개
```

---

## JOURNAL.md 기록

OpenCode 세션 내 Shell 도구로:

```bash
# Hermes 어댑터 활용 (설치 시)
python ~/.hermes/plugins/baton.py journal "OpenCode 작업 내용"
python ~/.hermes/plugins/baton.py harness opencode

# 직접 append
cat >> .baton/handoff/JOURNAL.md << 'EOF'

## $(date '+%Y-%m-%d %H:%M') — Turn N
- **INTENT**: OpenCode 작업
- **HARNESS**: opencode
- **ACTIONS**: -
- **TODO**: -

EOF
```

---

## 멀티 에이전트 시나리오

```bash
# 워크트리 A: Claude Code
cd .worktrees/feature-a/ && claude

# 워크트리 B: OpenCode (별도 터미널)
cd .worktrees/feature-b/ && opencode

# 워크트리 C: Codex
cd .worktrees/feature-c/
codex exec --dangerously-bypass-approvals-and-sandbox \
  -C "$(pwd)" "$(cat .baton/handoff/NEXT.md)"

# 공통: archive 누적 + git push로 크루 간 sync
# (각 워크트리에서)
baton finish
git push
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

**non-TTY (opencode run 비대화형) 경로**: `[baton-resume-mismatch] kind=... saved_worktree=... current_worktree=...` 한 줄을 stdout으로 받으면 그대로 사용자에게 보여주고 진행 여부 확인하세요.

---

## 트러블슈팅

### OpenCode가 baton 파일 수정 거부

OpenCode 설정에서 파일 쓰기 권한 허용:

```json
{
  "permissions": {
    "allow": [".baton/**"]
  }
}
```

### slash commands 미작동

```bash
# 설치 확인
ls ~/.config/opencode/commands/baton/

# 없으면 baton install.sh 재실행
bash /path/to/baton/install.sh
```

### baton PATH 인식

```bash
export PATH="$HOME/.baton/current/bin:$PATH"
```
