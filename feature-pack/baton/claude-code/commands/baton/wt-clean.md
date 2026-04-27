---
description: 워크트리 정리 + handoff archive 자동 보관 + 만료 prune
argument-hint: [path] [--merged]
allowed-tools: Bash
---

# /baton:wt-clean

워크트리를 제거하고 `.baton/handoff/` 파일들을 `.baton/archive/` 에 tar.gz로 자동 보관합니다.
PR 머지 확인 후 실행하는 `--merged` 플래그 패턴을 권장합니다.
완료 후 `auto_prune.on_wt_clean: true` 설정이 있으면 만료 archive를 자동 prune합니다.

## 사용법
```
/baton:wt-clean [path] [--merged]
```

- `path`: 대상 워크트리 경로 (생략 시 현재 위치)
- `--merged`: PR 머지 여부 확인 후 진행

## 동작
1. 대상 워크트리 경로 확인 (인자 없으면 현재 디렉토리)
2. `--merged` 플래그 시: `git branch --merged` 로 머지 확인, 미머지면 경고 후 진행 재확인
3. `.baton/handoff/` 4-template 파일을 `<phase-id>_<timestamp>.tar.gz` 로 압축
4. `.baton/archive/` 에 보관 + `INDEX.jsonl` 메타 항목 추가
5. `git worktree remove .worktrees/<name>` 실행
6. `.worktree-info.json` 에서 index 해제 (포트 반환)
7. `config.json.archive.auto_prune.on_wt_clean` = true 이면 `baton archive prune` 자동 실행

## 실행
```bash
bash ~/.baton/current/bin/baton wt-clean $ARGUMENTS
```

## 주의 / 가드
- 미머지 브랜치 삭제 시 반드시 경고 출력. 강제 실행은 `--force` 필요.
- archive 보관 후에만 워크트리 삭제 진행 (데이터 손실 방지).
- main/master root에서도 `wt-clean <path>` 는 허용 (경로 지정 형태).

## 참고
- SPEC Rule 3: archive 위치 `.baton/archive/INDEX.jsonl`
- SPEC Rule 4: 포트 반환 (index 해제)
- 관련 명령: `/baton:archive list`, `/baton:archive prune`
