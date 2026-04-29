# 🪃 baton

> **멀티 에이전트 시대의 무중단 컨텍스트 인계 표준** — 워크트리·아카이브·작업 메모리를 한 그릇에. Claude Code / Codex / Gemini / OpenCode / Hermes 어디서 시작했든 다음 도구가 그대로 이어 작업합니다.
>
> tmux 통합으로 세션 끊김 0. 어떤 에이전트든 워크트리 tmux 세션 attach해서 즉시 이어 작업.

---

## 🤔 왜 baton?

**친구들아, 멀티 에이전트로 작업하면서 이런 거 안 겪어봤어?**

- 🌅 아침에 **Claude Code**로 plan 짜고 → 점심에 **Codex**로 구현 → 저녁에 **Gemini**로 검증
  → 그런데 **각 도구가 어제 뭘 했는지 모름**. 매번 처음부터 설명...
- 💀 main에서 워크트리 까먹고 작업 → 충돌 폭탄 → 한참 후 정리하다 archive 부재로 **결정 이력 통째로 손실**
- 🔄 어떤 phase는 호흡이 길어서 plan/work/review를 N번 돌려야 하는데
  → **세션 끝나면 사라짐**. 다음 세션이 어디서부터 이어야 할지 모름
- 🤖 **에이전트 N개를 멀티로 돌리려면** 각자 같은 컨텍스트를 봐야 하는데, 표준이 없으면 **N×M 어댑터 지옥**

baton은 이걸 한 줄에 해결합니다:

> **모든 도구가 같은 그릇(`.baton/handoff/`)에 결과를 누적한다. 그릇 포맷은 SPEC.md 4룰로 표준화. 어느 도구든 그릇만 읽으면 즉시 인계.**

다중 에이전트 = 다중 도구 = 다중 세션. 표준이 없으면 컨텍스트가 매번 새로 시작. baton이 있으면 **그릇 하나로 무중단**.

---

## 🎬 한 그림으로 보는 baton

```
                   ┌──────────────────────────────────┐
                   │   .baton/handoff/  (표준 그릇)   │
                   │  PLAN / JOURNAL / CURRENT / NEXT │
                   └────────────┬─────────────────────┘
                                ↑ 표준 포맷 (SPEC.md 4룰)
                  ┌─────────────┼─────────────┐
                  ↓             ↓             ↓
            ┌──────────┐   ┌─────────┐   ┌──────────┐
            │ Claude   │   │  Codex  │   │  Gemini  │
            │  Code    │   │   CLI   │   │   CLI    │
            └──────────┘   └─────────┘   └──────────┘
            (plan 작성)    (구현 실행)    (검증)
                  ↓             ↓             ↓
                  └─────────────┴─────────────┘
                                ↓
                       ┌──────────────────┐
                       │  archive/        │
                       │  git-tracked     │  ← 완료 시 자동 압축 (30일)
                       │  머신 간 sync    │     전체 검색 가능
                       └──────────────────┘

세 에이전트가 같은 phase를 이어 작업.
baton은 매번 "이전에 뭘 했나" 컨텍스트를 알아서 챙겨줌.
```

---

## 🖥️ tmux 통합 — 세션 영속 + 멀티 에이전트 동시 작업

`export BATON_TMUX_ENABLE=true` 한 줄로 활성화.

```
$ /baton:wt-create v5-pr-a4
✓ 워크트리 생성: .worktrees/v5-pr-a4
  Branch: feat/v5-pr-a4
  Ports: GATEWAY=8090 / WEB=3011 / MOBILE=3012
✓ tmux 세션 생성: baton-byz-agents-v5-pr-a4
  접속:        tmux attach -t baton-byz-agents-v5-pr-a4
  📱 모바일 SSH: ssh yoonhwan@100.x.x.x  → tmux a -t baton-byz-agents-v5-pr-a4
```

> 📱 **모바일 SSH 안내는 Tailscale 설치 시 자동.** baton이 `tailscale ip -4` 결과 + `$USER` 로 한 줄 생성. 핸드폰 Termius/Blink/JuiceSSH 앱에서 그대로 복붙해 attach 가능.

세션 안에서:
- baton은 `BATON_AGENT`가 없으면 `CODEX_*`/`OMX_SESSION_ID`로 Codex, `CLAUDE_*`로 Claude를 감지합니다. 명시하려면 `BATON_AGENT=codex` 또는 `BATON_AGENT=claude-code`를 설정합니다.
- 사용자가 직접 작업 (vim, claude code, codex exec 등)
- 또는 다른 에이전트가 attach해서 자율 진행
- 세션 종료 안 함 → 노트북 닫아도 백그라운드 유지

### 📱 모바일 attach 시나리오 (Tailscale)

```
[집 노트북: macOS]                    [외출: 핸드폰]
  baton-byz-v5-pr-a4 세션 활성   ←──  Termius/Blink ssh user@100.x.x.x
  Claude/Codex/superpowers 진행                ↓
                                      tmux a -t baton-byz-v5-pr-a4
                                                ↓
                                      그대로 작업 모니터링·명령 추가
```

준비:
```bash
sudo tailscale set --ssh           # macOS Tailscale SSH 활성 (한 번)
sudo systemsetup -setremotelogin on  # SSH 활성
sudo pmset -c sleep 0              # 전원 연결 시 슬립 OFF
```

→ baton이 `wt-create` / `plan` / `save` / `resume` / `finish` 출력에 자동으로 모바일 SSH 명령 한 줄 표시.

`/baton:status` 출력에 tmux 정보 포함:
```
활성 워크트리:
  - v5-pr-a4 (feat/v5-pr-a4) (tmux: baton-byz-v5-pr-a4 — attach: tmux a -t baton-byz-v5-pr-a4)
```

---

## ✨ 핵심 플로우

```
[main 루트에서]
/baton:wt-create v5-pr-a3   ─→  워크트리 + 포트 + 심링 (옵션 B 가드)
cd .worktrees/v5-pr-a3

[워크트리 안에서]
/baton:plan v5-pr-a3        ─→  PLAN.md (선택, 큰 작업만)
                                  ↓
                       외부 하네스 (superpowers / OMX·Codex / OMC·Claude / ...)
                                  ↓
                       매 turn 자동 → JOURNAL.md
                       (UserPromptSubmit + PostToolUse 훅)
                                  ↓
/baton:save                 ─→  CURRENT.md status=paused, NEXT.md 갱신

[다음 세션 — 어떤 에이전트든]
"이어서" / "go" / "continue"
/baton:resume               ─→  NEXT.md 자동 출력, 작업 재개

[완료]
/baton:finish               ─→  status=done
/baton:wt-clean             ─→  archive 자동 보관 + 30일 prune
```

작업의 **앞(시작)** 과 **뒤(완료)** 만 baton이 관리. **중간(plan/code/review)** 은 외부 하네스에 위임. baton은 표준 파일 위치를 강제해서 어느 도구가 와도 그릇을 읽고 이어갑니다.

---

## 🎯 책임 경계

| ✅ baton이 하는 것 | ❌ baton이 안 하는 것 |
|--------------------|----------------------|
| 워크트리 생성·정리·아카이브 | LLM 작업 실행 |
| 포트 할당·반환·심볼릭 링크 | plan 인터뷰·코딩·리뷰·테스트 |
| `PLAN/JOURNAL/CURRENT/NEXT.md` 메모리 관리 | 검증·문서화 |
| 외부 하네스 invocation 가이드 | 백엔드 매핑 |

---

## 📂 디렉토리 한눈에

### 글로벌 (multi-version)
```
~/.baton/
├── versions/1.0.0/{bin,lib,templates,SPEC.md,...}
└── current → versions/1.0.0/
```

### 프로젝트 (워크트리마다)
```
{project}/.baton/
├── config.json          # commit O
├── version.lock         # commit O
└── archive/             # commit O (자동 sync)

{worktree}/.baton/
├── config.json          # 프로젝트 상속
├── phase.json           # commit O
├── handoff/             # gitignore
│   ├── PLAN.md
│   ├── JOURNAL.md
│   ├── CURRENT.md
│   └── NEXT.md
└── session.lock
```

---

## 🚀 빠른 시작

```bash
# 1. 설치 (인터뷰형 — 어느 에이전트에 어떤 훅 등록할지 묻습니다)
git clone https://github.com/yoonhwan/ai-feature-pack
bash ai-feature-pack/feature-pack/baton/install.sh

# 1.5. tmux 활성화 (선택, 권장)
export BATON_TMUX_ENABLE=true   # ~/.zshrc 또는 ~/.bashrc 에 추가

# 2. 현재 에이전트에서 (옵션 B: main에서는 wt-create만 가능)

# [main 루트에서] 워크트리 + 포트 + 심링 + phase.json stub 자동 생성
/baton:wt-create v5-pr-a3
cd .worktrees/v5-pr-a3

# [워크트리 안에서] phase 기획 (선택 — 큰 작업만)
/baton:plan v5-pr-a3                       # PLAN.md 채우기 (deep-interview 등 호출)

# 작업: 외부 하네스로
# Codex/OMX 런타임: $autopilot "..."
# Claude/OMC 런타임: /oh-my-claudecode:autopilot "..."

# 완료
/baton:finish                              # 페이즈 완료
/baton:wt-clean                            # 정리 + archive 자동 보관
```

> ⚠️ `/baton:plan`은 **워크트리 안에서만** 호출 가능. main/master root에서는 옵션 B 가드로 거부됩니다.

다음 세션 (다른 에이전트도 OK):
```bash
$ cd .worktrees/v5-pr-a3
$ codex     # 또는 gemini, opencode, hermes
> /baton:resume     # NEXT.md 컨텍스트 자동 로드
> 이어서             # 또는 "진행", "go", "continue", "next"
```

---

## 📚 플로우 케이스 — 자세한 시나리오는 별도 문서

| 케이스 | 시나리오 | 문서 |
|--------|----------|------|
| **A. plan-first** | 호흡 긴 작업 — plan부터 정석 | [flows/plan-first.md](flows/plan-first.md) |
| **B. wt-first** | 가벼운 작업 — 워크트리만 즉시 | [flows/wt-first.md](flows/wt-first.md) |
| **C. wt-finish** | 단일 종료 | [flows/wt-finish.md](flows/wt-finish.md) |
| **D. branch-pivot** | 다중 브랜치 분기 후 정리 | [flows/branch-pivot.md](flows/branch-pivot.md) |
| **E. abandoned** | phase 포기 처리 | [flows/abandoned.md](flows/abandoned.md) |
| **F. hotfix-mode** | main에서 직접 hotfix | [flows/hotfix-mode.md](flows/hotfix-mode.md) |
| **G. orphan-recovery** | .baton/ 손상 복구 | [flows/orphan-recovery.md](flows/orphan-recovery.md) |
| **H. handoff-rollback** | handoff/ 손상 시 archive 복원 | [flows/handoff-rollback.md](flows/handoff-rollback.md) |

플로우 인덱스: [flows/_index.md](flows/_index.md)

---

## 🤝 멀티 에이전트 동시 작업 — 크루 워크플로우

```
[사용자 main]                                  [엑스클로우 크루 / 다른 머신]
  │                                              │
  /baton:wt-create A                             git pull
  /baton:wt-create B                             /baton:archive search "..."
  /baton:wt-create C                             ← 이전 결정 즉시 조회
  │                                              │
  ┌─── tmux 세션 3개 (BATON_TMUX_ENABLE=true) ──┐
  │  baton-byz-A  baton-byz-B  baton-byz-C      │
  │   ↓            ↓            ↓                │
  │  Claude Opus  Codex CLI    Gemini CLI        │
  │   in A         in B         in C             │
  └──────────────────────────────────────────────┘
        │            │            │
        └────────────┴────────────┘
                     ↓
          .baton/archive/INDEX.jsonl  ← git-tracked
          (3건 자동 누적)
                     ↓
          git push
                     ↓
          [크루: git pull → /baton:archive search]
```

핵심: archive는 git-tracked. push만 하면 크루 모두 ".이전에 비슷한 거 했나?"를 즉시 조회 가능.

---

## 🔌 외부 하네스 어댑터

`/baton:plan` 호출 시 사용 가능한 하네스 후보 출력. 사용자 선택(첫 3회) 또는 `config.preferred_plan` 자동.

| 하네스 (최신 슬래시) | 역할 | 결과 누적 위치 |
|---------------------|------|----------------|
| `/superpowers:brainstorming` | 아이디어 발굴 | `PLAN.md` |
| `/superpowers:writing-plans` | plan 작성 | `PLAN.md` |
| `/superpowers:executing-plans` | plan 실행 | `JOURNAL.md` |
| Codex/OMX `$plan`, `$ralplan` | 전략·합의 계획 | `PLAN.md` |
| Codex/OMX `$deep-interview` | Socratic 인터뷰 | `PLAN.md` |
| Codex/OMX `$autopilot`, `$ralph` | 자율 실행 | `JOURNAL.md` |
| Codex/OMX `$team`, `$ultrawork` | 다중 에이전트 | `JOURNAL.md` |
| Claude/OMC `/oh-my-claudecode:plan` | 전략 계획 | `PLAN.md` |
| Claude/OMC `/oh-my-claudecode:deep-interview` | Socratic 인터뷰 | `PLAN.md` |
| Claude/OMC `/oh-my-claudecode:autopilot` | 자율 실행 | `JOURNAL.md` |
| Claude/OMC `/oh-my-claudecode:team` | 다중 에이전트 | `JOURNAL.md` |
| `/claude-mem:mem-search` | 과거 메모리 검색 | (조회만) |
| `/claude-mem:make-plan` | phased 계획 생성 | `PLAN.md` |
| `/claude-mem:do` | phased 실행 | `JOURNAL.md` |

> ⚠️ **Deprecated 슬래시 사용 금지** (제거 예정):
> `superpowers:write-plan`, `superpowers:execute-plan`, `superpowers:brainstorm` → 위 표의 최신 슬래시 사용
>
> baton의 추천 출력도 위 최신 슬래시만 표시합니다.

→ baton은 **표준 instruction을 동적 주입**합니다 (yaml 카탈로그 없음). 신규 하네스는 그냥 호출하면 baton이 이름 매칭으로 PLAN.md/JOURNAL.md에 결과 누적 지시. 추천은 `config.json`의 `harnesses.preferred_plan` 값으로 변경 가능.

---

## 🪝 훅 (Claude Code 5개)

| 훅 | baton 작업 |
|----|----|
| **SessionStart** | paused 알림 + 환경 검증 + archive lazy prune |
| **UserPromptSubmit** | 사용자 입력을 JOURNAL.md INTENT 섹션에 즉시 append |
| **PostToolUse** | 하네스 사용 자동 추출 → JOURNAL.md HARNESS 섹션 + invocation 검증 |
| **PreCompact** | 백업 dump 지시 (UserPromptSubmit 누락 안전망) |
| **SessionEnd** | 백업 dump 지시 |

> Claude Code의 Stop은 모델 컨텍스트 미주입이라 사용 안 함 (안전한 PreCompact + UserPromptSubmit 조합)

---

## 🛡️ 옵션 B — main/root strict

**main / master 브랜치 root**에서:
- ❌ `baton plan` 거부 (워크트리에서만)
- ❌ `baton save / resume / finish` 거부
- ✅ `baton wt-create` (워크트리 생성)
- ✅ `baton archive list/search` (조회)
- ✅ `baton status` (활성 워크트리 목록)
- ✅ `baton hotfix-mode` (main 직접 작업, lite mode)

→ main 오염 0, 단일 진실(phase는 워크트리에만 산다).

---

## 📐 핵심 명령 (전체 17개)

| 명령 | 역할 |
|------|------|
| `/baton:plan <id>` | phase.json 빈 stub (워크트리에서만) |
| `/baton:wt-create <name>` | 워크트리 + 포트 + 심링 + 메모리 초기화 |
| `/baton:save` | 핸드오프 즉시 dump |
| `/baton:resume` | NEXT.md 출력 (키워드: 이어서/진행/go/continue/next) |
| `/baton:finish` | 페이즈 완료 + wt-clean 제안 |
| `/baton:wt-clean [path?] [--merged]` | 워크트리 정리 + archive 자동 |
| `/baton:status` | phase + 활성 워크트리 |
| `/baton:help` | ASCII 시퀀스 |
| `/baton:install` | 인터뷰형 설치 |
| `/baton:doctor` | 진단 |
| `/baton:upgrade` | 새 버전 설치 (multi-version) |
| `/baton:archive list` | 최근 30일 |
| `/baton:archive search <query> [--global]` | 메타 + 내용 검색 |
| `/baton:archive show <id>` | 상세 |
| `/baton:archive extract <id>` | 임시 폴더로 압축 해제 |
| `/baton:archive close <id>` | 임시 폴더 정리 |
| `/baton:archive prune [--dry-run] [--days N]` | 만료 정리 (자동 + 수동) |

---

## 📋 Interop Contract

다른 에이전트와 호환하려면 [SPEC.md](core/SPEC.md) 의 4룰만 준수:
1. 4-template 핸드오프 포맷
2. phase.json 스키마
3. 워크트리 위치 + 옵션 B
4. 포트 할당 룰

---

## 📜 라이선스

MIT
