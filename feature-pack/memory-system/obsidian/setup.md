# Obsidian 볼트 구조 설정 가이드

## 볼트 폴더 구조

```
{{VAULT_NAME}}/
├── HOME.md               ← 볼트 시작점 (대시보드)
├── Daily/
│   ├── memory/           ← OC 데일리 노트 미러 (심링크 또는 복사)
│   └── MEMORY.md         ← OC 장기기억 미러 (심링크 또는 복사)
├── News-Links/           ← 뉴스/링크 → 노트 자동 변환
│   └── YYYY-MM-DD 제목/
│       └── README.md     ← 요약 + 키포인트 + 원본 URL
├── Meetings/             ← 대화/통화 기록
│   ├── _INDEX.md         ← 전체 목록 인덱스
│   └── YYYY-MM-DD 상대방명 - 주제.md
├── People/               ← 인물 프로필 (진화형)
│   ├── _INDEX.md         ← 전체 목록 인덱스
│   └── 이름.md           ← 기본정보 + 특성 + 인사이트 로그
├── Projects/             ← 프로젝트별 노트 (빈 폴더로 시작)
├── Reference/            ← 참조 문서
├── Ideas/                ← 아이디어
├── Trading/              ← 투자/트레이딩 (선택)
├── Tools/                ← 도구/CLI 가이드
└── Archive/              ← 아카이브
```

## 폴더별 용도

### Daily/
- `memory/`: OC 워크스페이스의 `memory/` 폴더 미러
- `MEMORY.md`: OC의 `MEMORY.md` 미러
- 방법: 심볼릭 링크 (추천) 또는 크론 복사

### News-Links/
- 뉴스/소셜미디어 링크를 공유하면 에이전트가 자동으로 노트로 변환
- 구조: `YYYY-MM-DD 영상/기사 제목/README.md`
- 원본 URL 필수 포함 (frontmatter + 본문)

### Meetings/
- 대화/통화 후 기록을 공유하면 에이전트가 자동 정리
- `_INDEX.md`로 전체 목록 관리
- 인물 프로필(`People/`)과 양방향 크로스링크

### People/
- 진화형 인물 프로필: 대화마다 인사이트가 누적
- 기본정보 + 특성 + 인사이트 로그 + 대화 이력 (전체 링크)
- `_INDEX.md`로 전체 목록 관리

### Projects/
- 프로젝트별 서브폴더로 관리
- 초기에는 빈 폴더 — 프로젝트 시작 시 생성

## 추천 플러그인

| 플러그인 | 용도 |
|---------|------|
| Dataview | 메타데이터 기반 동적 목록/테이블 |
| Calendar | 데일리 노트 캘린더 뷰 |
| Templater | 노트 템플릿 자동 적용 |
| Graph View | (기본) 노트 관계 시각화 |
