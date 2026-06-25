# cairn 설치 (에이전트 자동 수행)

이 문서를 읽은 에이전트는 다음을 자동 수행한다.

## 사전 요구
- `python3 >= 3.9`, `git >= 2.30`

## 설치 단계

### 1) install.sh 실행
```bash
bash install.sh
```
수행: `~/.cairn/versions/<ver>` core 복사 + `current` 심링 + `~/.cairn/venv`(ruamel.yaml) + PATH(`~/.zshrc`) + `~/.claude/commands/cairn` + `~/.claude/skills/cairn/SKILL.md` 심링 + `cairn self-test` 검증.

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

## 제거
```bash
bash uninstall.sh          # 전역만 제거, 프로젝트 .cairn/ 보존
```

## 트러블슈팅
- `cairn: command not found` → 새 셸 또는 위 PATH export.
- `ModuleNotFoundError: ruamel` → `~/.cairn/venv` 누락. `bash install.sh` 재실행.
