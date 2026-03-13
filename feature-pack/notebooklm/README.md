# 📓 Feature Pack: NotebookLM

Google NotebookLM을 터미널에서 제어하는 CLI + OpenClaw 스킬 패키지.

## 할 수 있는 것

- 🔍 **소스 기반 Q&A** — 업로드한 문서에서만 답변 (할루시네이션 제로)
- 🎙️ **오디오 팟캐스트** — 문서 기반 AI 팟캐스트 자동 생성
- 🎬 **비디오 오버뷰** — 요약 비디오 생성
- 📊 **리포트/퀴즈/플래시카드** — 학습 자료 자동 생성
- 🌐 **딥 리서치** — 웹 소스 자동 수집 & 분석
- 🗂️ **노트북 관리** — 생성/삭제/공유/별칭
- 📎 **Obsidian 연동** — 볼트 문서를 NotebookLM 소스로 활용

## 빠른 시작

```bash
# 1. 설치
uv tool install notebooklm-mcp-cli

# 2. 인증
nlm login

# 3. 사용
nlm notebook list
nlm query notebook <id> "질문"
```

## 설치

OpenClaw 에이전트에게 `INSTALL.md`를 전달하세요:
> "INSTALL.md 읽고 설치해줘"

## 구조

```
notebooklm/
├── INSTALL.md        ← 에이전트용 설치 프롬프트
├── README.md         ← 이 파일
├── manifest.json     ← 메타데이터
├── skill/            ← OpenClaw 스킬
│   ├── SKILL.md      ← 스킬 정의
│   └── references/   ← 확장 문서
├── cli/              ← CLI 설치 가이드
│   └── install.md
├── config/           ← OpenClaw 설정 조각
│   └── tools-section.md
├── obsidian/         ← Obsidian 연동 가이드
│   └── setup.md
└── test/             ← 검증
    └── verify.md
```

## 요구사항

- macOS (Apple Silicon / Intel)
- Python 3.10+
- Google 계정
- Chrome 브라우저
