# tmuxc 설치 (에이전트 자동 수행)

이 문서를 읽은 에이전트는 다음을 자동 수행한다.

## 사전 요구

```bash
command -v bash >/dev/null
command -v git >/dev/null
command -v tmux >/dev/null
```

선택 도구:

- Claude Code: `claude`
- Codex CLI: `codex`
- OMX: `omx`
- BYZ 운영 세트: `baton`, `cairn`

## 설치 단계

### 1) install.sh 실행

```bash
bash feature-pack/tmuxc/install.sh
```

수행 내용:

1. `bash`, `git`, `tmux` 확인
2. `~/.tmuxc/versions/<version>/`에 core + Claude Code skill 복사
3. `~/.tmuxc/current` 심링 갱신
4. `~/.local/bin/tmuxc` 심링 설치
5. `~/.local/bin` PATH가 없으면 `~/.zshrc` 또는 `~/.bashrc`에 등록
6. Claude Code가 있으면 `~/.claude/skills/tmuxc`를 설치본으로 연결
7. `tmuxc --help`, `tmuxc list`로 검증

### 2) 검증

Codex 기반 smoke:

```bash
tmuxc --help
tmuxc open "$PWD" --name TMUXC_SMOKE --agent codex --role worker --dry-run
tmuxc list
```

Claude Code skill 연결:

```bash
test -e "$HOME/.claude/skills/tmuxc/SKILL.md"
test -e "$HOME/.claude/skills/tmuxc/COMM-GUIDE.md"
```

### 3) baton/cairn 세트 확인

```bash
command -v baton || true
command -v cairn || true
command -v tmuxc
```

`baton`은 worktree/handoff, `cairn`은 schedule/session ledger, `tmuxc`는 live tmux agent session control을 담당한다.

## 제거

```bash
bash feature-pack/tmuxc/uninstall.sh
```

제거는 전역 `~/.tmuxc`와 설치본을 가리키는 `~/.local/bin/tmuxc`, `~/.claude/skills/tmuxc` 심링만 삭제한다. 사용자의 프로젝트 파일과 tmux 세션은 삭제하지 않는다.

## 트러블슈팅

| 증상 | 해결 |
| --- | --- |
| `tmuxc: command not found` | 새 셸을 열거나 `export PATH="$HOME/.local/bin:$PATH"` 실행 |
| `tmux: command not found` | macOS: `brew install tmux`, Ubuntu: `sudo apt install tmux` |
| Codex 세션에 메시지가 안 보임 | `tmuxc ask <name> 120`으로 capture-pane 확인 후 `tmuxc send` 재시도 |
| Claude Code 내부 세션명 혼선 | `tmuxc` skill의 `COMM-GUIDE.md`와 verified-send 절차 참조 |
