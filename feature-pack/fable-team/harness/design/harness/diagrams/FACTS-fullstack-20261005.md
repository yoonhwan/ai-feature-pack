# FACTS — 풀스택 다이어그램 사실 (ft-harness-nano#1 · 2026-10-05 · 읽기 전용 · 시크릿 0)
> 상위 ORDER: design/harness/diagrams/ORDER-fullstack-diagram-20261005.md 할 일 1 · 골 축 = 표 A·표 C·원문 5
> 수집 시각(UTC) 2026-10-05 13:37 UTC · 머신 hostname `MacBook-Pro` · HEAD sha `5e53d60f63`
> [사실] 44줄 · [추측] 6줄 · 환경변수는 **이름만**(값 0) · 서버 기동·press·커밋 0

---

## 1. 외부 서비스 (이름·역할·연결)

`grep -rhoE '…_(API_KEY|TOKEN|SECRET|URL|…)' .env.example` + `ls ~/.hermes` + `launchctl list`.

| 외부서비스 | 역할 | 연결 내부 노드 | 출처 |
|---|---|---|---|
| **Slack** | 배포 발행·수신 미러 | `com.hermes.byz-github-slack-mirror` · `com.hermes.byz-mbox-slack-mirror` plist | [사실] `ls ~/Library/LaunchAgents` |
| **GitHub** | 이슈·PR·미러 | `gh` · github-slack-mirror | [사실] plist 명 |
| **Supabase** | 인증·DB(dev/prod 공유 의심) | `NEXT_PUBLIC_SUPABASE_URL`(변수명) · `supabase/` | [사실] env명·디렉토리 |
| **GCP Cloud Run** | ccu-stress gateway/worker | `ccu-stress-gateway`·`ccu-stress-worker`·`ccu-stress-redis` | [사실] `design/ccu/CLOSEOUT…:25` |
| **GCP GCE GPU VM** | STT/vLLM 서빙 | IAP 터널 `:8001→10.0.0.9:8000` · `:8100`·`:38311` | [사실] `/tmp/byz-iap-*.log` · `dev_scripts.md:9` |
| **GCP IAP** | 터널 인증 | `byz-iap-stt-8001`·`byz-iap-tunnel-llm` | [사실] `/tmp/byz-iap-*.log` |
| **STT 프로바이더** | 음성→텍스트 | `DEEPGRAM_API_KEY`·`FIREWORKS_API_KEY`·`GROQ_API_KEY`·`RETURNZERO_API_KEY`·`SONIOX_API_KEY`·`GEMINI_API_KEY`·`GOOGLE_API_KEY`·`CLOVA_*` | [사실] env명 |
| **TTS 프로바이더** | 텍스트→음성 | `ELEVENLABS_API_KEY`·`CARTESIA_API_KEY`·`SUPERTONE_API_KEY`·`GOOGLE_TTS_API_KEY`·`CLOVA_*` | [사실] env명 |
| **LLM 프로바이더** | 번역·polish | `ANTHROPIC_API_KEY`·`OPENAI_API_KEY`·`GEMINI_API_KEY`·`XAI_API_KEY`·`LOCAL_VLLM_BASE_URL` | [사실] env명 |
| **번역** | 번역 API | `DEEPL_API_KEY`·`GOOGLE_TRANSLATE_API_KEY` | [사실] env명 |
| **Perplexity** | 검색·fact-check | `PERPLEXITY_API_KEY` | [사실] env명 |
| **Qdrant** | 벡터 DB(loom embed) | `QDRANT_HOST`·`QDRANT_API_KEY`·`LOOM_EMBED_BASE_URL` | [사실] env명 |
| **LangSmith/LangChain** | 관측 | `LANGSMITH_API_KEY`·`LANGCHAIN_PROJECT` | [사실] env명 |
| **cliproxy / headroom** | 에이전트 CLI 상류 프록시 | `com.cliproxy.api`(:8317)·`com.headroom.proxy`(:8787/8790) | [사실] launchctl·lsof |
| **Cloudflare** | 터널 | `com.cloudflare.cloudflared` | [사실] plist |
| **Codex / Claude / Gemini** | 에이전트 CLI 상류 | `~/.codex/config.toml`·`~/.claude` | [사실] ls |
| **Redis / Postgres** | 인프라 | 로컬 docker·`:6379`/`:5432` | [사실] lsof·docker ps |

**[추측]** `PERPLEXITY_API_KEY`·`XAI_API_KEY` 는 코드 경로가 아니라 에이전트 도구용으로 보인다(worker 서비스 목록에 perplexity/xai provider 디렉토리 미확인).

---

## 2. 머신·프로세스·포트

`lsof -nP -iTCP -sTCP:LISTEN` + `docker ps` + `launchctl list` + `docs/rules/dev_scripts.md`.

| 머신/프로세스 | 포트 | 소유(워크트리/팀) | 출처 |
|---|---|---|---|
| Python(gateway) | **8080** | v6-realtime-live | [사실] lsof · `dev_scripts.md:27` |
| Python(worker) | **8081** | v6-realtime-live | [사실] lsof · `dev_scripts.md:17` |
| node(Next.js) | **3001** | clients/web | [사실] lsof · `dev_scripts.md:18` |
| caddy | **8443** (+2019 admin) | dev h2 리버스 프록시 | [사실] `dev_scripts.md:21` |
| Python(GPU STT tunnel) | **8001** | IAP → `10.0.0.9:8000` | [사실] lsof · `/tmp/byz-iap-8001.log` |
| Python | **8000** | (GPU vLLM 로컬 프록시 추정) | [추측] lsof |
| Python(embed tunnel) | **8100** | loom embed IAP | [사실] `/tmp/byz-iap-tunnel-embed-8100.log` |
| Python(stt tunnel) | **38311** | IAP stt | [사실] `/tmp/byz-iap-tunnel-stt-38311.log` |
| Google Chrome | **9333** | CDP(press 전용) | [사실] lsof · `CLAUDE.md:304` |
| postgres | **5432/5433** | 로컬 DB | [사실] lsof · `infra.sh:25` |
| docker `ops-accounts-pg` | **38391→5432** | postgres:16 | [사실] docker ps |
| docker redis ×다수 | 임의 포트→6379 | 테스트 픽스처(c1c-ta-red·byz-act-tier-b 등) | [사실] docker ps |
| cli-proxy | **8317** | cliproxy | [사실] lsof |
| headroom | **8787/8790** | headroom proxy | [사실] lsof |
| ollama | **11434** | 로컬 LLM | [사실] lsof |
| LM Studio | **1234** | 로컬 LLM | [사실] lsof |
| ssh | **10254/10255/3100/5432/54321/38391** | 터널 | [사실] lsof |
| **GPU VM `A1P:ccu-stress-stt-tts` · `A1P:ccu-stress-vllm`** | — | 미해소 breach 26h | [사실] `state/gce-op-model/BREACH.md` |
| **jarvis**(다른 머신) | — | 미반영(RELEASE 0.1) | [사실] `design/harness/RELEASE-0.1.md` |

**[추측]** `Python :8000` 은 GPU vLLM 로컬 프록시, `:38311`/`:8100` 은 각각 stt/embed IAP 터널(로그 파일명 근거).
**[추측]** 포트 대역 `383xx` 는 워크트리 격리용(`38301` gateway·`38303` FE 예 — `docs/work/loom-domain-ops/BRIEF-T0-orgs-list.md:460`).

---

## 3. 하네스 노드 (정본 SPEC-main-orch-tree §3 과의 **차이만**)

`tmux list-sessions` + `ls .fable-team`.

**[사실] tmux 13 세션**(SPEC §3 은 14:3x 기준 31 — **-18**): 남은 = `FB_CFO#52` · `KakaoBot#14/#17` · `byz-planner-arch#3` · `ft-airag-helm-claude#5` · `ft-airag-master-claude#2` · `ft-harness-arch#2/#3` · `ft-harness-da#1` · `ft-harness-nano#1` · `ft-harness-ops#1/#2/#3` · `ft-v65-master-claude#135`.
**죽은/사라진 것**: `ft-harness-arch#0`(→#2/#3) · `ft-harness-ops#0`(→#1/#2/#3) · `ft-issue-manager#0` · `repro-e2e#0` · `ft-v65-arch-claude#155` · `ft-v65-master-claude#136` · `ft-v65-tester-claude#13` · `ft-v65-temp-*#0`(2) · `ft-kakao-*`(4) · `ft-airag-helm-claude#4` · `ft-harness-da#1`(존속) · `KakaoBot#14`(존속).
**새 것**: `ft-harness-arch#2`·`ft-harness-arch#3`·`ft-harness-ops#3`.
**[사실] 명부 파일 6**: `seats.json`(v65) · `seats-cfo.json` · `seats-kk.json` · `seats-planner.json` · `seats-harness.json` · `seats-issues.json`.
**[사실] mbox 파일 4종 경로**: `.fable-team/comm/{mailbox.jsonl, mailbox.log.jsonl, bodies/, relay/}` (+`mbox.sh`·`mbox.py`·`queues.conf`·`mailbox.lock`).
**[사실] `bin/`**: 루트 `.fable-team/bin/` **비어 있음** — 팀별 `.fable-team/bin-{cfo,harness,issues,kk,planner}/` + 실제 실행 사본 `.worktrees/v6-realtime-live/.fable-team/bin/`(ft-*.sh **36개**).
ft-*.sh 역할 1단어: `ft-checkpoint`(체크포인트) · `ft-context-monitor`(컨텍스트) · `ft-goal-check`/`ft-goal-tick`(골) · `ft-index-*`(인덱스) · `ft-nano-*`(나노) · `ft-role-spawn`(역할) · `ft-press-gate`/`ft-press-set-check`(press) · `ft-reach-check`(도달) · `ft-tick*`(틱) · `ft-wt-sweep`/`ft-worktree-triage`(워크트리).

---

## 4. 로컬 파일시스템 지도 (깊이 2 · 각 폴더 역할 1줄)

**[사실] 리포 루트 `BYZ-Agents/`**: `gateway/`·`worker/`·`shared/`·`clients/`·`tests/`·`scripts/`(실행) · `design/`(설계·판정) · `docs/`(규칙) · `supabase/` · `docker/` · `infrastructure/` · `secrets/` · `state/` · `proto/` · `.claude/`(스킬·훅) · `.fable-team/`(하네스 상태) · `.worktrees/`(워크트리) · `.baton/`·`.omc/`(세션 배턴).
- `.claude/` = `agents/`·`hooks/`(15개: orchestration-gate·context-distill-gate·serena-activate·track-lifecycle-gate 등)·`rules/`(byz-ops-usage·git-worktree-pitfalls·orchestration·troubleshoot)·`skills/`(17개: bts·byz-cycle·byz-e2e·byz-health·byz-loom·byz-ops·byz-zion 등)·`commands/`·`archives/`·`fable-team/`.
- `design/harness/issue-improvement/` = **P1~P9 사실·SPEC·DA**(오늘 트랙). `design/v65/{날짜}/`·`design/cfo/`·`design/ccu/`(워크트리)·`design/kk/`.
- `.worktrees/` = **137 워크트리**(v65-·kk-·ops-·cfo-·ccu-stress·c-level-planning 등).
- `.fable-team/` = `seats*.json`(6)·`comm/`(mbox)·`bin-*/`(팀 키트)·`state/`(원장·락)·`secrets/`·`checkpoint/`.

**[사실] `~/.claude/`**: `CLAUDE.md`·`rules/`·`skills/`·`hooks/`(orchestration-gate·context-distill-gate)·`agents/`(ft-tester·ft-checker 등)·`archives/`(과거 전문)·`projects/`(세션 jsonl)·`daemon/`·`teams/`.
**[사실] `~/.hermes/`**: `SOUL.md`·`config.yaml`·`bin/`·`channel_roles/`·`auth.json`(Slack/에이전트). `~/.codex/`: `AGENTS.md`·`config.toml`. `~/.baton/`: `current`·`versions`.
**[사실] `/tmp`**: `/tmp/mbox/*.md`(relay 전문) · `/tmp/byz-*.log`(gateway·worker·web·caddy·iap-8001·iap-tunnel-*·loom-db-tunnel 등 30여 개).

**[추측]** 루트 `.fable-team/bin/` 공백 + `.worktrees/v6-realtime-live/.fable-team/bin/` 에만 실 스크립트가 있는 구조 = 「라이브 하네스 bin = 워크트리 사본」(#816 이슈) 그대로.

---

## 미해결·미확인 (다음 조사 후보)
- `Python :8000` 프로세스 정체(추측) · cliproxy upstream 목록(`~/.cliproxy*` 부재) · 다른 머신 jarvis 실기 접촉 0(문서만) · Supabase dev/prod 공유 여부(`DESIGN-ccu-stress-infra.md:85` 미해결).