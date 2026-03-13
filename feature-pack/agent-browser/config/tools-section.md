# TOOLS.md — agent-browser 섹션

아래 내용을 TOOLS.md에 추가하세요.

---

### 🌐 브라우저 자동화: agent-browser 우선 사용!

**agent-browser**: Vercel Labs가 만든 **Rust 기반** 브라우저 자동화 CLI (Node.js fallback 지원)
- GitHub: https://github.com/vercel-labs/agent-browser
- Site: https://agent-browser.dev/
- AI 에이전트용 headless 브라우저 자동화에 최적화

**기본 규칙: 웹 페이지 자동화/컨트롤은 `agent-browser`를 먼저 사용한다.**
**⚠️ agent-browser는 검색 도구가 아니다.** 웹페이지를 열고 조작하는 자동화 도구임.
- 웹 검색이 필요하면 → `web_fetch` (URL 알 때) 또는 DuckDuckGo를 열고 검색
- 동적 페이지 컨트롤, 스크린샷, 스크래핑 → `agent-browser --native`

#### 🚀 `--native` 모드 (기본값으로 사용!)

| 항목 | `--native` (Rust CDP) | 기본 (Node.js Playwright) |
|------|:---------------------:|:-------------------------:|
| 조회 속도 | **~150ms/페이지** 🚀 | ~350ms/페이지 ⚡ |
| cold start | **~300ms** | ~950ms |
| 연속 작업 | **~100-200ms** | ~200-500ms |
| Node.js 필요 | ❌ 불필요 | ✅ 필요 |
| 안정성 | experimental | stable |
| headless | ✅ | ✅ |

**`--native` 사용법:**
```bash
agent-browser --native --session <name> open <url>
agent-browser --native --session <name> eval '<js>'
agent-browser --native --session <name> screenshot <path>
agent-browser --native --session <name> snapshot
agent-browser --native --session <name> close
```

**언제 `--native` vs 기본 모드?**
- ✅ `--native` 기본 사용: 동적 페이지 컨트롤, 스크래핑, 스크린샷, Chrome CDP 직접 연결
- ⚠️ 기본 모드 fallback: `--native` 실패 시, 복잡한 JS 렌더링 이슈 발생 시
- ❌ 검색 도구로 사용 금지: 검색이 필요하면 web_fetch 또는 DuckDuckGo 열기

**agent-browser 올바른 사용 목적:**
- ✅ 특정 URL 페이지 열고 → 클릭/입력/스크롤 등 컨트롤
- ✅ 동적 콘텐츠(SPA/React) 렌더링 후 데이터 추출
- ✅ 로그인 팝업 우회 후 콘텐츠 스크래핑
- ✅ 스크린샷, PDF 캡처
- ✅ Chrome CDP 직접 연결 (E2E 자동화)
- ❌ 검색 엔진 역할 (검색은 web_fetch 또는 DuckDuckGo 직접)

#### 📹 영상 캡처

```bash
agent-browser record start <path.webm> [url]  # 녹화 시작
agent-browser record stop                      # 녹화 종료

# GIF 변환
ffmpeg -i video.webm -vf "fps=10,scale=480:-1:flags=lanczos" -c:v gif output.gif
```

#### 📱 스크린샷 카드 생성 (모바일 최적화)

HTML(375px) → agent-browser 스크린샷 → PIL 크롭+2× 스케일 → 830px 레티나 PNG

```bash
# 1. HTML 작성 (375px, ≤620px 높이)
# 2. agent-browser --native screenshot
# 3. python3 PIL 크롭 (415px → 2× = 830px)
```

뷰포트 고정 1280×720 → 620px 초과 시 잘림 주의. 카드 분리 필수.
