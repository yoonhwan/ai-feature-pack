---
description: baton 인터뷰형 설치 실행 (multi-version 글로벌 설치)
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:install

`install.sh`를 실행하여 baton을 인터뷰형으로 설치합니다.
감지된 에이전트(Claude Code / Gemini / OpenCode / Hermes 등)별로 훅 등록 방식을 사용자에게 확인합니다.

## 사용법
```
/baton:install
```

## 동작
1. 사전 요구사항 확인: `bash`, `git`, `jq`, `tar` 설치 여부 검사 — 누락 시 설치 안내
2. 환경 감지 — Claude Code / Gemini CLI / OpenCode / Hermes / Codex / OpenClaw 발견 여부
3. multi-version 글로벌 설치:
   - `~/.baton/versions/1.0.0/` 에 core/ 복사
   - `~/.baton/current → versions/1.0.0/` 심링 생성
4. PATH 등록 안내 (`export PATH="$HOME/.baton/current/bin:$PATH"`)
5. 에이전트별 어댑터 등록:
   - Claude Code: `~/.claude/commands/baton/` 17개 .md 복사 + hooks 패치
   - 기타 에이전트: 해당 경로에 커맨드 파일 + hooks 패치
6. 훅 등록 인터뷰 — 어느 훅에 어떤 baton 작업 연결할지 사용자에게 확인
7. `baton doctor` 자동 실행하여 설치 결과 검증

## 실행
```bash
bash ~/.baton/current/bin/baton install $ARGUMENTS
```

## 주의 / 가드
- `~/.claude/settings.json` 수정 전 `settings.json.baton-backup` 자동 백업 생성.
- 이미 설치된 경우 버전 비교 후 업그레이드 여부 확인 (upgrade 명령으로 유도).
- Codex / OpenClaw는 수동 등록 가이드 출력.

## 참고
- INSTALL.md: 에이전트용 설치 프롬프트
- 관련 명령: `/baton:doctor`, `/baton:upgrade`
