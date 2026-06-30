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
| 8 | [baton](feature-pack/baton/) | 멀티 에이전트 handoff/worktree/archive 표준 — Claude Code·Codex·Gemini 간 작업 인계 | ~2분 | ❌ | ❌ |
| 9 | [cairn](feature-pack/cairn/) | 일정 + 멀티 에이전트 복구 원장 — milestone/task/session lineage, baton/tmuxc 연동 | ~2분 | ❌ | ❌ |
| 10 | [tmuxc](feature-pack/tmuxc/) | tmux 기반 Claude Code·Codex·OMX 세션 launcher/control — verified send/capture 통신 표준 포함 | ~1분 | ❌ | ❌ |
| 11 | [auto](feature-pack/auto/) | AutoResearch 자율 실험 루프 — 베이스라인→목표→자율주행 최적화 | ~1분 | ❌ | ❌ |
| 12 | [nanoclaw](feature-pack/nanoclaw/) | **AI 멀티 에이전트 플랫폼** — OpenClaw 대체. Claude SDK Brain, Docker 격리, 멀티 크루 | ~15분 | ❌ | Slack |
| 13 | [agent-cli](feature-pack/agent-cli/) | **AI 코딩 에이전트 CLI 툴킷** — 설치·비교 + 비대화 위임(DA/designer/architect 페르소나·자율주행·resume): claude·codex·gemini·opencode·cursor | ~3분 | ❌ | ❌ |
| 14 | [headroom](feature-pack/headroom/) | Claude Code·Codex 등 AI 코딩 에이전트 컨텍스트 압축 프록시 + `/headroom` 토글 | ~5분 | ❌ | ❌ |
| 15 | [cliproxyapi](feature-pack/cliproxyapi/) | headroom → CLIProxyAPI 구독 프록시 스택 — Claude/Codex/Gemini OAuth plan 경유 + Hermes 게이트웨이 | ~10분 | ❌ | OAuth |

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
| baton | `baton` | 스크립트 설치 | ✅ | bash, git, tmux 선택 |
| cairn | `cairn` | 스크립트 설치 + venv | ✅ | python3, git, ruamel.yaml |
| tmuxc | `tmuxc` | 스크립트 설치 | ✅ | bash, git, tmux |
| auto | — (순수 스킬) | 스킬 파일 복사 | ✅ | git, python3 필요 |
| agent-cli | (기존 에이전트 CLI 호출) | 스킬 파일 복사 | ✅ | perl, python3 + 에이전트 CLI ≥1 |
| headroom | `headroom` / LaunchAgent | venv + 스킬 파일 복사 | ✅ | python3.12, curl |
| cliproxyapi | `cli-proxy-api` | 바이너리 + LaunchAgent + 스킬 파일 복사 | ✅ | headroom, OAuth 계정 |

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

운영형 멀티 에이전트 작업은 다음 순서를 권장합니다.

1. **baton** — worktree/handoff/archive 기준점
2. **cairn** — schedule/session lineage 원장
3. **tmuxc** — Claude Code/Codex/OMX tmux 세션 실행과 verified-send 통신

이 세트의 책임 경계:

| 도구 | 담당 |
|------|------|
| baton | 작업 시작/저장/복구용 `.baton/handoff/`와 worktree/archive |
| cairn | `.cairn/plan.yaml` 기반 milestone/task/session lineage와 hook reconcile |
| tmuxc | live tmux agent session 생성, capture, send, kill, Codex verified-send 표준 |

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
