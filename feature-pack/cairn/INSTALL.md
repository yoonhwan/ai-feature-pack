# cairn 설치 (에이전트 자동 수행)

이 문서를 읽은 에이전트는 다음을 자동 수행한다.

## 사전 요구
- `python3 >= 3.9`, `git >= 2.30`

## 설치 단계

### 1) install.sh 실행

Codex:

```bash
bash install.sh
```

Claude Code:

```text
feature-pack/cairn/INSTALL.md 읽고 bash feature-pack/cairn/install.sh 실행 후 self-test와 hook smoke까지 검증해줘
```
수행: `~/.cairn/versions/<ver>` core 복사 + `current` 심링 + `~/.cairn/venv`(ruamel.yaml) + PATH(`~/.zshrc`) + `~/.cairn/current/hooks/*` + `~/.claude/commands/cairn` + `~/.claude/skills/cairn/SKILL.md` 심링 + `cairn self-test` 검증.

### 2) 검증
```bash
cairn self-test            # self-test OK
cd <임의 프로젝트>
cairn new-project demo     # .cairn/plan.yaml 생성
cairn status
```

### 3) 새 셸 또는 PATH 적용
```bash
export PATH="$HOME/.cairn/current/bin:$PATH"
```

### 4) hook 설치/검증

프로젝트별 git hook:

```bash
mkdir -p .git/hooks
ln -sfn "$HOME/.cairn/current/hooks/post-merge" .git/hooks/post-merge
ln -sfn "$HOME/.cairn/current/hooks/post-checkout" .git/hooks/post-checkout
```

BTS evidence/verification pass 자동 진척 후보:

```bash
CAIRN_TASK_ID=t2 CAIRN_VERIFICATION_STATUS=pass \
  "$HOME/.cairn/current/hooks/cairn-auto-progress"
```

기본 동작은 `.cairn/auto-progress/candidates/`에 후보를 남기는 것입니다. 실제 원장 반영은 아래처럼 명시한 경우에만 실행합니다.

```bash
CAIRN_AUTO_PROGRESS=apply CAIRN_TASK_ID=t2 CAIRN_VERIFICATION_STATUS=pass \
  "$HOME/.cairn/current/hooks/cairn-auto-progress"
```

Claude Code에서 PostToolUse 훅으로 연결할 때도 위 명령을 호출하되, 자동 완료는 `CAIRN_AUTO_PROGRESS=apply`가 있을 때만 허용하세요. Codex에서는 같은 명령을 shell hook 또는 tmuxc 세션 종료/검증 단계에서 호출합니다.

## 제거
```bash
bash uninstall.sh          # 전역만 제거, 프로젝트 .cairn/ 보존
```

## 트러블슈팅
- `cairn: command not found` → 새 셸 또는 위 PATH export.
- `ModuleNotFoundError: ruamel` → `~/.cairn/venv` 누락. `bash install.sh` 재실행.
