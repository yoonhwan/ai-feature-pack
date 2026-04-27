---
description: baton 전체 명령 ASCII 시퀀스 및 플로우 안내 출력
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:help

baton의 전체 17개 명령과 표준 워크플로 시퀀스를 ASCII 다이어그램으로 출력합니다.
플로우 케이스 8개와 외부 하네스 목록도 함께 안내합니다.

## 사용법
```
/baton:help
```

## 동작
1. ASCII 워크플로 시퀀스 출력:
   ```
   plan ─→ wt-create ─→ [하네스 작업] ─→ save ─→ resume ─→ finish ─→ wt-clean
   ```
2. 전체 17개 명령 목록을 카테고리별 출력:
   - 워크플로: plan / wt-create / save / resume / finish / wt-clean
   - 조회: status / help
   - 유지보수: install / doctor / upgrade
   - 아카이브: archive list / search / show / extract / close / prune
3. 옵션 B 가드 요약 (main에서 불가/가능 명령 구분)
4. 키워드 트리거 목록 (`이어서` / `진행` / `go` / `continue` / `next` → resume)
5. 플로우 케이스 인덱스 (A~H) 간략 안내
6. 외부 하네스 후보 목록 (preferred_plan, preferred_execution)

## 실행
```bash
bash ~/.baton/current/bin/baton help $ARGUMENTS
```

## 주의 / 가드
- 없음. 어디서든 실행 가능.

## 참고
- README.md: 전체 개요
- flows/_index.md: 8개 플로우 케이스
- README.md "외부 하네스 추천" 표 (yaml 카탈로그 폐기, 표준 instruction 동적 주입)
- core/SPEC.md: Interop Contract
