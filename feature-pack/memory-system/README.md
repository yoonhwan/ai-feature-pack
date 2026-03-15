# Memory System Feature Pack

OpenClaw 에이전트의 기억 시스템 전체 구조를 세팅하는 피처팩.

## 포함 요소

| 구성 | 설명 |
|------|------|
| **OC 워크스페이스 메모리** | MEMORY.md(장기기억) + memory/(데일리 노트) 구조 |
| **Obsidian 볼트** | 세컨드브레인 폴더 구조 (News-Links, Meetings, People 등) |
| **메모리 검색 통합** | extraPaths로 볼트↔메모리 검색 연동 + 임베딩 설정 |
| **NotebookLM CLI** | nlm CLI로 소스 기반 Q&A, 리서치 (별도 피처팩 의존) |

## 아키텍처

```
[OC Workspace]              [Obsidian Vault]
 ├── MEMORY.md ─────미러───→ Daily/MEMORY.md
 ├── memory/YYYY-MM-DD.md ─→ Daily/memory/
 └── memorySearch ──extraPaths──→ 볼트 전체
                                  ├── News-Links/
                                  ├── Meetings/
                                  ├── People/
                                  ├── Projects/  (빈 폴더)
                                  └── ...

[NotebookLM]
 └── nlm CLI → 볼트 문서를 소스로 추가 → 소스 기반 Q&A
```

## 설치

`INSTALL.md`를 에이전트에게 전달하면 자율 설치됩니다.
