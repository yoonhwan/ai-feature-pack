---
description: 새 baton 버전을 ~/.baton/versions/에 추가하고 current 심링 전환
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:upgrade

새 버전의 baton을 `~/.baton/versions/` 에 추가하고, `current` 심볼릭 링크를 새 버전으로 전환합니다.
이전 버전은 7일간 보관 후 자동 삭제됩니다 (기존 워크트리 호환 안전망).

## 사용법
```
/baton:upgrade
```

## 동작
1. `ai-feature-pack` 저장소에서 최신 버전 정보 확인 (또는 로컬 경로)
2. 현재 설치 버전 vs 최신 버전 비교 — 동일하면 "이미 최신" 출력 후 종료
3. `~/.baton/versions/<new-version>/` 에 새 버전 설치
4. 모든 활성 워크트리의 `version.lock.compat_range` 검사 — 새 버전이 범위 밖이면 경고
5. `~/.baton/current → versions/<new-version>/` 심링 갱신
6. Claude Code `~/.claude/commands/baton/` 17개 .md 파일 업데이트
7. 이전 버전 보관 안내 (7일 후 자동 삭제 또는 수동: `rm -rf ~/.baton/versions/<old>`)
8. `baton doctor` 자동 실행하여 업그레이드 결과 검증

## 실행
```bash
bash ~/.baton/current/bin/baton upgrade $ARGUMENTS
```

## 주의 / 가드
- SPEC 메이저 버전 변경(v1 → v2) 시 마이그레이션 가이드 출력 후 사용자 확인 필요.
- 이전 버전 워크트리는 `version.lock.compat_range` 내에서만 호환 보장.
- main/master root에서도 실행 가능.

## 참고
- SPEC: 버저닝 룰 (minor/patch/major 구분)
- SPEC: 멀티 버전 글로벌 설치 구조
- 관련 명령: `/baton:doctor`, `/baton:install`
