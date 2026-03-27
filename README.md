# 🏞️ AI Feature Pack

**OpenClaw 에이전트를 위한 피처별 선택 설치 패키지**

> 이 레포의 각 Feature Pack은 독립적입니다.
> 필요한 것만 골라서 설치하세요.

---

## 📦 피처 카탈로그

| # | Feature Pack | 설명 | 설치시간 | API 키 | 인증 |
|---|-------------|------|---------|--------|------|
| 1 | [agent-browser](feature-pack/agent-browser/) | 웹 자동화 — 스크래핑, 스크린샷, 폼 입력, 녹화 | ~3분 | ❌ | ❌ |
| 2 | [imsg](feature-pack/imsg/) | iMessage/SMS — 대화 조회, 메시지 전송, 실시간 감시 | ~3분 | ❌ | ❌ |
| 3 | [notebooklm](feature-pack/notebooklm/) | Google NotebookLM — 소스 기반 Q&A, 리서치, 오디오 생성 | ~5분 | ❌ | Google |
| 4 | [obsidian-cli](feature-pack/obsidian-cli/) | Obsidian 볼트 CLI — 노트 조회/생성/검색/이동 | ~3분 | ❌ | ❌ |
| 5 | [tts-say](feature-pack/tts-say/) | 통합 TTS — macOS say + ElevenLabs 음성 합성 | ~3분 | ElevenLabs | ❌ |
| 6 | [yt-transcribe](feature-pack/yt-transcribe/) | YouTube → STT → 요약 자동 파이프라인 | ~10분 | ❌ | ❌ |
| 7 | [termaid](feature-pack/termaid/) | Mermaid 다이어그램 터미널 렌더링 — 설계 시각화 자동 발동 | ~2분 | ❌ | ❌ |

### 난이도 & 의존성

| Feature Pack | CLI | 설치 방식 | macOS | 비고 |
|-------------|-----|----------|:-----:|------|
| agent-browser | `agent-browser` | `npm i -g @anthropic-ai/agent-browser` | ✅ | Node.js 필요 |
| imsg | `imsg` | `brew install` | ✅ | macOS 전용 (iMessage) |
| notebooklm | `nlm` | `uv tool install` | ✅ | Google 계정 로그인 필요 |
| obsidian-cli | `obsidian-cli` | `brew install` | ✅ | Obsidian 앱 선택적 |
| tts-say | `tts-say` | 스크립트 복사 | ✅ | ElevenLabs API 키 선택적 |
| yt-transcribe | `ytdl` + `whisper-cli` + `ffmpeg` | cargo + brew | ✅ | 빌드 시간 ~5분 |
| termaid | `termaid-render` | go build + cp | ✅ | Go 필요 |

---

## 🚀 설치 방법

### 방법 1: 에이전트 자율 설치 (추천)

```bash
# 1. 레포 클론
git clone https://github.com/yoonhwan/ai-feature-pack.git

# 2. 원하는 피처팩의 INSTALL.md를 에이전트에게 전달
# 예: "feature-pack/agent-browser/INSTALL.md 읽고 설치해줘"
```

에이전트가 INSTALL.md를 읽고:
1. 사전 요구사항 확인
2. CLI 설치
3. 인증/설정 (필요시 사용자에게 질문)
4. OpenClaw 스킬 등록
5. TOOLS.md / AGENTS.md 설정 추가
6. 설치 검증

### 방법 2: 수동 설치

각 피처팩 폴더의 `README.md`를 읽고 순서대로 진행:

```
feature-pack/{name}/
├── README.md        ← 사람용 개요 (여기서 시작)
├── cli/install.md   ← CLI 설치 명령어
├── skill/SKILL.md   ← 스킬 정의 복사
├── config/          ← TOOLS.md / AGENTS.md 추가 내용
└── test/verify.md   ← 설치 검증
```

### 방법 3: 전체 설치

```
에이전트에게: "ai-feature-pack 레포의 모든 피처팩을 순서대로 설치해줘"
```

> ⚠️ 전체 설치 시 약 25분 소요. 의존성 없는 팩부터 자동 정렬.

---

## 📋 추천 설치 순서

피처 간 의존성은 없지만, 활용도 기준 추천 순서:

1. **obsidian-cli** — 세컨드브레인 기반 (다른 피처의 노트 저장처)
2. **agent-browser** — 웹 자동화 (가장 범용적)
3. **yt-transcribe** — YouTube 전사 (obsidian-cli와 시너지)
4. **notebooklm** — 지식 Q&A (소스 기반 답변)
5. **tts-say** — 음성 출력 (편의성)
6. **imsg** — iMessage 연동 (macOS 전용)

---

## 🔧 피처팩 구조 (공통)

```
feature-pack/{name}/
├── INSTALL.md          ← 에이전트용 설치 프롬프트 (핵심!)
│                         {{PLACEHOLDER}} → 사용자 인터뷰로 대치
├── README.md           ← 사람용 개요
├── manifest.json       ← 메타데이터 (OS, 의존성, 설치시간)
├── skill/              ← OpenClaw 스킬 폴더
│   └── SKILL.md        ← 스킬 정의 (CLI 명령어 전체)
├── cli/                ← CLI 설치
│   └── install.md      ← 설치 명령어 + 검증
├── config/             ← OpenClaw 설정 조각
│   ├── tools-section.md    ← TOOLS.md 추가 섹션
│   └── agents-section.md   ← AGENTS.md 추가 섹션 (해당 시)
├── obsidian/           ← Obsidian 연동 (해당 시)
│   └── setup.md
└── test/               ← 설치 검증
    └── verify.md
```

---

## 📌 참고

- **OS**: 현재 macOS만 지원 (Linux/Windows 추후 업데이트)
- **OpenClaw**: [openclaw.ai](https://openclaw.ai) | [GitHub](https://github.com/openclaw/openclaw)
- **문의**: 이슈 등록 또는 [Discord](https://discord.com/invite/clawd)

## 라이선스

MIT
