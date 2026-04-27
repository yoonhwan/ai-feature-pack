# baton — Gemini CLI 어댑터 가이드

## 개요

Gemini CLI에서 baton을 사용하는 패턴입니다.
Gemini CLI는 `--approval-mode yolo` 로 파일 쓰기를 허용합니다.

---

## 사전 요구사항

- baton 설치됨 (`~/.baton/current/bin/baton` 존재)
- Gemini CLI 설치됨 (`gemini --version` 확인)
- `BATON_HOME` 환경변수 설정 (기본: `~/.baton/current`)

---

## 기본 사용 패턴

### 세션 시작 시 상태 확인

```bash
# baton 상태 먼저 확인
baton status

# paused phase 이어받아 Gemini 실행
cd .worktrees/my-feature/
gemini --approval-mode yolo
```

### Gemini에게 baton 컨텍스트 주입

Gemini 프롬프트 시작 시 NEXT.md 내용을 포함:

```bash
# NEXT.md를 초기 프롬프트로 주입
gemini --approval-mode yolo \
  --prompt "$(cat .baton/handoff/NEXT.md)

--- 위 내용을 참고해 작업을 이어서 진행해줘.
작업 완료 후 반드시:
1. baton save 실행
2. .baton/handoff/JOURNAL.md 마지막 Turn ACTIONS/TODO 업데이트
3. .baton/handoff/NEXT.md 에 다음 세션 안내 작성"
```

### 작업 완료 후 baton 저장

```bash
baton save
# 또는 완전 완료 시
baton finish
```

---

## tmux 통합 시나리오 (BATON_TMUX_ENABLE=true)

```bash
# 1. tmux 활성화 후 워크트리 생성
export BATON_TMUX_ENABLE=true
baton wt-create ui-redesign "UI 재설계"
# → tmux 세션 baton-{project}-ui-redesign 자동 생성

# 2. tmux 세션에서 Gemini 실행
tmux attach -t baton-{project}-ui-redesign
# (tmux 세션 안에서)
gemini --approval-mode yolo

# 3. 다른 터미널에서 상태 모니터링
baton status
# → "tmux: baton-{project}-ui-redesign — attach: tmux a -t ..." 표시
```

---

## Gemini CLI 권장 설정

`~/.gemini/settings.json` 또는 `~/.gemini/GEMINI.md` 에 추가:

```markdown
## baton 워크플로우

이 세션은 baton 워크트리 안에서 실행 중입니다.

작업 시작 시:
1. .baton/handoff/CURRENT.md 확인 (현재 phase 상태)
2. .baton/handoff/NEXT.md 확인 (다음 할 일)
3. .baton/handoff/PLAN.md 확인 (전체 계획)

작업 완료 시:
1. `baton save` 실행
2. JOURNAL.md 마지막 Turn 업데이트 (ACTIONS/TODO)
3. NEXT.md 갱신 (다음 세션 안내)
```

---

## JOURNAL.md 기록 패턴

Gemini 세션 내 Bash 도구로:

```bash
# Turn 추가
python ~/.hermes/plugins/baton.py journal "Gemini UI 컴포넌트 작업" 2>/dev/null || \
cat >> .baton/handoff/JOURNAL.md << 'EOF'

## $(date '+%Y-%m-%d %H:%M') — Turn N
- **INTENT**: Gemini 작업 내용
- **HARNESS**: gemini-cli
- **ACTIONS**: -
- **TODO**: -

EOF

# HARNESS 필드 갱신
python ~/.hermes/plugins/baton.py harness gemini-cli 2>/dev/null || true
```

---

## 멀티 에이전트 시나리오

```bash
# 워크트리 A: Claude Code (백엔드)
cd .worktrees/backend-api/
# claude 세션에서 작업

# 워크트리 B: Gemini (프론트엔드 / UI — Gemini 비주얼 강점 활용)
cd .worktrees/frontend-ui/
gemini --approval-mode yolo

# 공통 archive
baton finish && git push  # 각 워크트리에서
```

---

## Gemini 명령 디렉토리 통합

`~/.gemini/commands/baton/` 이 이미 설치되어 있으면 Gemini 슬래시 명령 사용:

```
/baton:status    # 상태 확인
/baton:save      # 저장
/baton:resume    # 이어서 진행
```

설치 확인:

```bash
ls ~/.gemini/commands/baton/
```

---

## 트러블슈팅

### Gemini가 파일 쓰기를 거부

```bash
# yolo 모드 필수
gemini --approval-mode yolo
```

### baton 명령 미인식

```bash
export PATH="$HOME/.baton/current/bin:$PATH"
```

### tmux 세션 이름 확인

```bash
baton status  # tmux 정보 포함 출력
# 또는
tmux list-sessions | grep baton
```
