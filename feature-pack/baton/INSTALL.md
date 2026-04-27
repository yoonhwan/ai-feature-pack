# baton — 에이전트용 설치 프롬프트

이 문서를 읽은 에이전트는 다음 단계를 자동 수행해야 합니다.

## 사전 요구사항 확인

```bash
# 필수 도구 확인
command -v bash >/dev/null && bash --version | head -1
command -v git >/dev/null && git --version
command -v jq >/dev/null && jq --version
command -v tar >/dev/null

# 누락된 게 있으면 사용자에게 설치 안내:
# macOS:  brew install jq
# Ubuntu: apt install jq
```

## 설치 단계

### 1) install.sh 실행 — 인터뷰형 자동 설치

```bash
bash {repo-path}/feature-pack/baton/install.sh
```

설치 스크립트가 자동 수행:
1. **환경 감지** — Claude Code / Gemini CLI / OpenCode / Hermes 발견 여부
2. **multi-version 글로벌 설치** — `~/.baton/versions/1.0.0/` 에 core/ 복사
3. **current 심링** — `~/.baton/current → versions/1.0.0/`
4. **PATH 등록 안내** — `export PATH="$HOME/.baton/current/bin:$PATH"` 를 .zshrc/.bashrc에 추가
5. **에이전트별 등록**:
   - **Claude Code**: `~/.claude/commands/baton/` 17개 .md 복사 + `~/.claude/skills/baton/SKILL.md` 심링 + `~/.claude/settings.json` hooks 패치
   - **Gemini CLI**: `~/.gemini/commands/baton/` TOML 복사 + `~/.gemini/settings.json` hooks 패치
   - **OpenCode**: `~/.config/opencode/commands/baton/` 복사 + plugins 등록
   - **Hermes**: `~/.hermes/plugins/baton.py` 복사
   - **Codex / OpenClaw**: 수동 등록 가이드 출력
6. **인터뷰** — 어느 훅에 어떤 baton 작업을 등록할지 사용자에게 묻기 (recommended 자동 선택 가능)

### 2) 검증

```bash
~/.baton/current/bin/baton doctor
```

확인 항목:
- 호환 버전
- 어댑터 등록 상태 (감지된 에이전트 모두 ✓)
- `jq` 의무 의존성
- 활성 phase 목록 (있으면)

### 3) 첫 phase 만들기 (선택)

```bash
# [main 루트에서] 워크트리 + 포트 + 심링 + phase.json stub 자동 생성
/baton:wt-create test-phase

# [워크트리 진입]
cd .worktrees/test-phase

# [워크트리 안에서] phase 기획 (선택 — 큰 작업만, 옵션 B 가드)
/baton:plan test-phase     # phase.json 채우기
/baton:status              # 상태 확인
```

> **옵션 B**: `/baton:plan`은 워크트리 안에서만 호출됩니다. main/master root에서는 거부됩니다.

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| `jq: command not found` | `brew install jq` (macOS) / `apt install jq` (Ubuntu) |
| `~/.claude/settings.json: hooks 키 충돌` | install.sh가 백업(`settings.json.baton-backup`) 후 머지 시도. 충돌 시 사용자에게 수동 머지 안내 |
| `슬래시 /baton:* 미인식` | `~/.claude/commands/baton/*.md` 존재 확인. 또는 Claude Code 재시작 |
| `baton: command not found` | PATH 등록 확인. 또는 절대 경로 `~/.baton/current/bin/baton` |

## 비활성화 / 제거

```bash
bash {repo-path}/feature-pack/baton/uninstall.sh
```

uninstall은 다음을 제거 (확인 prompt 후):
- `~/.baton/` 전체 (multi-version 포함)
- `~/.claude/skills/baton/`, `~/.claude/commands/baton/`
- `~/.claude/settings.json` 의 baton hooks 항목
- 다른 에이전트 등록 항목

프로젝트 내 `.baton/` 은 보존 (사용자 데이터). 수동 삭제 필요.

## 참고 문서

- [README.md](README.md) — 사람용 개요
- [core/SPEC.md](core/SPEC.md) — Interop Contract
- [flows/_index.md](flows/_index.md) — 8개 플로우 케이스
- README.md "외부 하네스 추천" 표 — baton이 동적 instruction을 주입하므로 카탈로그 yaml 없음
