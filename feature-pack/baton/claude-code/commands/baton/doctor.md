---
description: baton 설치 상태 및 환경 진단
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:doctor

baton의 설치 상태, 의존성, 어댑터 등록, 활성 phase 목록을 종합 진단합니다.
문제 항목에 대해 원인과 수동 수정 방법을 안내합니다.

## 사용법
```
/baton:doctor
```

## 동작
1. **버전 호환성**: `version.lock` 의 `compat_range` vs 현재 `~/.baton/current` 버전 비교
2. **의존성 확인**: `jq`, `git`, `bash`, `tar` 존재 여부 (`✓` / `✗` 표시)
3. **어댑터 등록 상태**: 감지된 에이전트마다 커맨드 파일 + 훅 등록 여부 확인
   - Claude Code: `~/.claude/commands/baton/` 17개 파일 존재 + `settings.json` hooks 항목
   - Gemini/OpenCode/Hermes: 각 경로 확인
4. **활성 phase 목록**: `.worktrees/` 스캔 + CURRENT.md status 확인 (있으면 출력)
5. **심볼릭 링크 유효성**: `config.json.shared_links` 항목의 링크 대상 존재 여부
6. **session.lock 고아**: lock 존재하나 프로세스 없는 경우 감지 + 해제 안내
7. 진단 결과 요약: `✓ N개 정상 / ✗ M개 문제`

## 실행
```bash
bash ~/.baton/current/bin/baton doctor $ARGUMENTS
```

## 주의 / 가드
- 없음. main/master root 포함 어디서든 실행 가능.
- 문제 자동 수정은 하지 않음 — 안내만 제공. 수정은 `baton install` 또는 수동 진행.

## 참고
- INSTALL.md: 트러블슈팅 표
- 관련 명령: `/baton:install`, `/baton:upgrade`
