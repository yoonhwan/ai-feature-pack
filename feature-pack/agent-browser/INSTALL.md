# Feature Pack: agent-browser

> 에이전트 자율 설치 프롬프트 — 이 문서를 AI 에이전트에게 전달하면 자동 설치됩니다.

## 개요

agent-browser는 AI 에이전트용 브라우저 자동화 CLI입니다. 웹 스크래핑, 스크린샷, 폼 자동입력, 비디오 녹화, 네트워크 디버그, 스타일드 카드 생성을 지원합니다. Playwright(Node.js) + Rust CDP 두 가지 모드를 제공하며, Native(Rust CDP) 모드가 기본 우선입니다.

**할 수 있는 것:**
- 웹 페이지 열기/클릭/입력/스크롤 자동화
- 동적 SPA/React 페이지 스크래핑
- 전체/부분 스크린샷 + 2× 레티나 카드 생성
- WebM 비디오 녹화 → GIF 변환
- 콘솔/에러/네트워크 디버그 + Mock
- 로그인 세션(쿠키) 저장/복원
- Chrome CDP 직접 연결 (확장 프로그램 지원)

## Prerequisites

- macOS (arm64 또는 x86_64)
- Node.js 18+ (`node --version`으로 확인)
- Python 3 (`python3 --version`으로 확인)
- npm (`npm --version`으로 확인)

## Step 1: CLI 설치

```bash
# agent-browser 글로벌 설치
npm install -g agent-browser

# Chromium 다운로드 (최초 1회, ~150MB)
agent-browser install

# 버전 확인 (0.16.3+ 필요)
agent-browser --version
```

## Step 2: Pillow 설치 (스크린샷 카드용)

```bash
pip3 install Pillow
# 검증
python3 -c "from PIL import Image; print('Pillow OK')"
```

## Step 3: 스킬 설치

`skill/` 폴더 전체를 OpenClaw 스킬 디렉토리에 복사:

```bash
cp -r skill/ {{OPENCLAW_SKILLS_PATH}}/agent-browser/
```

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_SKILLS_PATH}}` | OpenClaw 스킬 폴더 경로 | `~/.openclaw/workspace/skills` |

> Claude Code 사용자: `~/.claude/skills/agent-browser/`에 복사

## Step 4: OpenClaw 설정

`config/tools-section.md` 내용을 TOOLS.md에 추가:

```bash
cat config/tools-section.md >> {{OPENCLAW_WORKSPACE}}/TOOLS.md
```

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_WORKSPACE}}` | OpenClaw workspace 경로 | `~/.openclaw/workspace` |

**추가되는 내용:**
- agent-browser 사용 규칙 (native 우선, 검색 도구 아님)
- 속도 비교 테이블
- 영상 캡처 명령어
- 스크린샷 카드 생성 파이프라인

## Step 5: 설치 검증

```bash
# 1. CLI 버전
agent-browser --version

# 2. Native 모드 테스트
agent-browser --native open "https://example.com" \
  && agent-browser --native get title \
  && agent-browser --native screenshot /tmp/ab-verify.png \
  && agent-browser --native close

# 3. Snapshot 테스트
agent-browser --native open "https://example.com" \
  && agent-browser --native snapshot -i \
  && agent-browser --native close

# 4. Pillow 테스트
python3 -c "from PIL import Image; img = Image.new('RGB', (375, 100), '#1a1a2e'); img.save('/tmp/ab-pillow.png'); print('Pillow OK')"

# 정리
rm -f /tmp/ab-verify.png /tmp/ab-pillow.png
```

모든 항목 통과 시 설치 완료.

## Troubleshooting

| 문제 | 해결 |
|------|------|
| `agent-browser: command not found` | `npm install -g agent-browser` 재실행 |
| `Chromium not found` | `agent-browser install` 실행 |
| `--native` 모드 실패 | `--native` 없이 standard 모드로 fallback |
| Pillow import 에러 | `pip3 install Pillow` 재실행 |
| 스크린샷 잘림 | HTML 높이 ≤620px 확인, 초과 시 카드 분리 |

## Placeholder 정리

| Placeholder | 질문 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_SKILLS_PATH}}` | "OpenClaw 스킬 폴더 경로가 어디인가요?" | `~/.openclaw/workspace/skills` |
| `{{OPENCLAW_WORKSPACE}}` | "OpenClaw workspace 경로가 어디인가요?" | `~/.openclaw/workspace` |

## 설치 완료 후

에이전트에게 다음과 같이 요청할 수 있습니다:

- "이 페이지 스크린샷 찍어줘" → agent-browser 자동 트리거
- "example.com 스크래핑해줘" → native 모드로 콘텐츠 추출
- "로그인 자동화해줘" → 폼 입력 + 쿠키 저장
- "데모 영상 녹화해줘" → WebM 녹화
- "히어로카드 만들어줘" → HTML → 스크린샷 → PIL 크롭 → 레티나 PNG
