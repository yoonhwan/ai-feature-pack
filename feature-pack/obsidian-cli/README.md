# Obsidian CLI Feature Pack

Obsidian 볼트(Markdown 노트)를 CLI로 완전 관리하는 피처팩.

## 할 수 있는 것

- 📋 **조회**: 볼트 파일/폴더 목록, 노트 내용 읽기
- 🔍 **검색**: 노트 이름 퍼지 검색, 노트 내용 검색
- ✏️ **생성**: 노트 생성 (폴더 자동 생성), 데일리 노트
- 📝 **수정**: 덮어쓰기, 추가(append), frontmatter 편집
- 🗑️ **삭제**: 노트 삭제
- 📦 **이동**: 노트 이동/이름변경 + 위키링크 자동 업데이트

## 설치

에이전트에게 `INSTALL.md`를 전달하면 자율 설치됩니다.

## 요구사항

- macOS
- Homebrew
- Obsidian 앱 설치 (URI handler용)

## 구성

```
obsidian-cli/
├── INSTALL.md          # 에이전트 자율 설치 프롬프트
├── README.md           # 이 파일
├── manifest.json       # 메타데이터
├── skill/
│   └── SKILL.md        # OpenClaw 스킬 정의
├── cli/
│   └── install.md      # CLI 설치 명령어
├── config/
│   └── tools-section.md # TOOLS.md 추가 섹션
├── obsidian/
│   └── setup.md        # Obsidian 앱 설정 가이드
└── test/
    └── verify.md       # 설치 검증 CRUD 테스트
```
