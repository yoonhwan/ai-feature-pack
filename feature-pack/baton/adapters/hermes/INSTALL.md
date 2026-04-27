# baton — Hermes 어댑터 설치 가이드

## 개요

Hermes는 범용 Python plugin hook 시스템을 제공하지 않으므로,
baton 어댑터는 **세션 전후 수동 실행** 또는 **Hermes shell_hooks 설정**으로 연동합니다.

---

## 사전 요구사항

- Hermes CLI 설치됨 (`hermes --version` 확인)
- baton 설치됨 (`~/.baton/current/bin/baton` 존재)
  - 미설치 시: [baton INSTALL.md](../../INSTALL.md) 참고
- Python 3.8+
- bash, git, jq

---

## 설치

### 1. 플러그인 파일 복사

```bash
mkdir -p ~/.hermes/plugins
cp adapters/hermes/baton.py ~/.hermes/plugins/baton.py
chmod +x ~/.hermes/plugins/baton.py
```

### 2. 동작 확인

```bash
python ~/.hermes/plugins/baton.py status
```

워크트리 안에서 실행하면 현재 phase 상태가 출력됩니다.

---

## Hermes shell_hooks 설정 (자동화, 권장)

`~/.hermes/config.yaml` 에 shell_hooks 지원 시 추가:

```yaml
shell_hooks:
  pre_session:  "python ~/.hermes/plugins/baton.py on_session_start"
  post_session: "python ~/.hermes/plugins/baton.py on_session_end"
```

Hermes 버전에 따라 `hooks:` 키 이름이 다를 수 있습니다. Hermes 설정 문서 확인.

---

## 수동 사용법 (shell_hooks 미지원 시)

### 세션 시작 전

```bash
python ~/.hermes/plugins/baton.py on_session_start
```

paused phase가 있으면 알림 출력 + 환경 검증.

### 세션 종료 후

```bash
python ~/.hermes/plugins/baton.py on_session_end
```

active phase를 paused로 자동 전환.

### 상태 확인

```bash
python ~/.hermes/plugins/baton.py status
# 또는
~/.baton/current/bin/baton status
```

### 편의 alias 설정 (~/.zshrc 또는 ~/.bashrc)

```bash
alias baton-start="python ~/.hermes/plugins/baton.py on_session_start"
alias baton-end="python ~/.hermes/plugins/baton.py on_session_end"
alias baton="~/.baton/current/bin/baton"
```

---

## Hermes 세션 내에서 baton 사용하기

Hermes 프롬프트에서 직접 baton CLI를 호출하세요:

```
# Hermes 프롬프트에서
> 이어서 작업해줘

# 또는 직접 baton 명령
> /baton:status 결과를 보여줘
```

키워드 "이어서" / "진행" / "go" / "continue" / "next" 를 Hermes에 입력하면
baton이 paused phase를 감지하고 resume 안내를 출력합니다.

---

## BATON_TMUX_ENABLE 활성화 시

`BATON_TMUX_ENABLE=true` 환경변수 설정 시 추가 동작:

```bash
export BATON_TMUX_ENABLE=true
```

- `on_session_start`: 활성 tmux 세션 이름 + attach 명령 표시
- 워크트리 생성(`baton wt-create`) 시 tmux 세션 자동 생성
- `baton wt-clean` 시 tmux 세션 종료 여부 확인

tmux attach:

```bash
tmux a -t baton-{project}-{phase-id}
```

---

## 검증

```bash
# 1. baton 워크트리 안에서
cd .worktrees/my-feature/

# 2. on_session_start 테스트
python ~/.hermes/plugins/baton.py on_session_start
# → "📌 일시정지된 페이즈가 있어요" 또는 정상 환경 출력

# 3. journal 기록 테스트
python ~/.hermes/plugins/baton.py journal "테스트 intent 기록"
# → JOURNAL.md에 Turn 추가 확인

# 4. status 확인
python ~/.hermes/plugins/baton.py status
```

---

## 트러블슈팅

### `baton: command not found`

`~/.baton/current/bin/` 이 PATH에 없는 경우:

```bash
export PATH="$HOME/.baton/current/bin:$PATH"
```

또는 절대경로로 실행:

```bash
python ~/.hermes/plugins/baton.py status
```

### `BATON_HOME` 환경변수

기본값: `~/.baton/current`. 다른 경로 사용 시:

```bash
export BATON_HOME=/custom/path/baton
```

### `.baton/handoff/CURRENT.md` 없음

baton 워크트리 밖에서 실행 중입니다. `baton wt-create` 로 워크트리를 먼저 생성하세요.

### Hermes 세션 내에서 Python 스크립트 실행

Hermes가 shell 명령을 허용하는 경우 Bash 도구로 직접 실행:

```bash
python ~/.hermes/plugins/baton.py on_session_start
```
