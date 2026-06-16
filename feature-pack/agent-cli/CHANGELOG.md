# agent-cli — Changelog

## v2.1.0 (2026-06-16) — WSL/Linux 지원

WSL 사용자 문의 폭주 대응. macOS 편중이던 설치·경로를 cross-platform으로 보강.

### ✨ Added
- **`scripts/detect-env.sh`** — 실행 환경 자동감지: OS(macOS/Linux/**WSL**) 구분 + **지금 바로 쓸 수 있는 CLI** 목록 + 미설치분 환경별 설치 힌트 + WSL 주의사항을 한 번에 리포트. (읽기 전용 진단) WSL 사용자는 "링크 받고 → detect-env 실행 → 가능한 것부터" 흐름.
- `INSTALL.md`에 **Step 0: 환경 파악** 추가.

### 🔧 Changed
- `cli/install.md`: macOS / **Linux / WSL** 3분기 설치표로 재작성 (npm·curl 우선, brew는 mac 한정).
- WSL 주의 명문화: OAuth는 Windows 브라우저로 열림(URL 수동 복붙) · `cursor-agent`는 WSL PATH에 없을 수 있음(자동 SKIP) · 작업은 WSL 네이티브 FS(`~/`)에서 · `perl/python3` 없으면 `apt install`.
- `manifest.json` os에 `wsl` 추가, compatibility/README에 지원 환경 명시.

### 🩹 Fixed (사용자 문의)
- macOS 전용 안내(`/opt/homebrew`, `brew`)만 있어 WSL에서 설치 막막하던 문제 해소 — 환경 자동 분기로 안내.

---

## v2.0.0 (2026-06-16)

기존 `agent-cli`(설치·비교 가이드)에 비대화 **위임 하네스**(cross-cli)를 통합하고, 5종 CLI를 실기로 재검증해 정정한 메이저 릴리스.

### ✨ Added — 비대화 위임 하네스

- **세션 내 타 프로바이더 CLI 위임**: 현재 코딩/채팅 세션을 벗어나지 않고 claude·codex·gemini·opencode·cursor-agent 를 비대화로 소환→자율주행→결과 회수.
- **페르소나 프리셋** (`references/personas.md`): **DA**(적대검증)·**designer**·**architect** system-prompt 주입.
- **실행 스크립트** (`scripts/`):
  - `selftest.sh` — 5종 ①PATH ②비대화+자율 R1 ③resume R2(회상) 일괄 점검, 로그 영속(`logs/`, 매 실행 삭제·재생성).
  - `test_opencode.sh` — OpenCode 단독 점검(모델 자동탐색).
  - `resume_chain.sh` — 페르소나 + 다회 resume 체인 헬퍼.
- **강제 타임아웃**: 모든 외부 호출을 perl fork+setpgrp **프로세스그룹 SIGKILL**로 감싸 node/MCP startup 행(hang)이 스위트 전체를 멈추지 못하게 차단.
- **표준 피처팩 구조**: `manifest.json`, `INSTALL.md`, `cli/install.md`, `config/tools-section.md`, `test/verify.md`, `references/install-and-compare.md` 추가. 루트 카탈로그(#10) 등재.
- **상위 하네스 선택 연계**: oh-my-\*(ulw/ultraplan)·baton·tmuxc — **로컬 설치 시에만 사용, 미설치면 무시**(핵심 기능은 독립 동작).

### 🔧 Fixed — 2026-06 실기 검증 보정 (이전 가이드 오류)

- **Cursor**: "비대화 불가 / IDE 전용 / 부적합" → **틀림.** `cursor`(IDE)와 별개인 `cursor-agent` CLI는 `-p -f --output-format json --resume`로 **비대화·자율·resume 전부 작동**. 둘을 명확히 구분.
- **Codex resume**: "stdout `session id:`에서 추출" → 실제 sid는 **stderr**에만 노출 → **`codex exec resume --last`** 로 변경.
- **Gemini resume**: `--resume latest` 가 비대화에서 **hang** → JSON `session_id` 기반 `--resume <id>` 로 변경. `-o json` 앞 `MCP issues detected...` 접두사 제거 파싱.
- **Gemini 설치**: `@anthropic-ai/gemini-cli`(오류) → **Google 패키지**로 정정.
- **OpenCode 기본 모델**: 유효 provider/model 필요 → 기본값 `opencode/deepseek-v4-flash-free`(무료 zen).

### ✅ Verified

- selftest 라이브: **claude · codex · opencode · cursor-agent** 4종 비대화+자율+resume 통과. gemini는 환경 MCP startup 행을 타임아웃이 안전 처리.
- 보안 점검: 토큰/API키/시크릿 유출 **0건**(추적 파일·히스토리). 스크립트는 자격증명 미보유(사용자 CLI 인증만 사용).

### 🔁 Migration

- 별도 `cross-cli` 팩은 **agent-cli로 통합·제거**됨. 글로벌 스킬은 `~/.claude/skills/agent-cli`.
- `logs/`는 `.gitignore` 처리(테스트 산출물 추적 제외).

### 🔒 Security notes

- 스크립트의 자동주행 플래그(dangerous/full-auto/yolo/force)는 **격리/신뢰 워크스페이스에서만**.
- 위임받는 CLI는 각자 자체 인증 필요 — 본 팩은 토큰을 주입·저장하지 않음.
- 위임 결과(payload)는 신뢰 불가 입력으로 취급, 본 세션에서 검수 후 사용.

---

## v1.x (이전)

- `agent-cli` — AI 코딩 에이전트 CLI 설치·비대화 실행·resume·도구제한·래핑 비교 가이드 (단일 `SKILL.md`).
