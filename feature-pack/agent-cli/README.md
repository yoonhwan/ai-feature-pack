# 🔀 agent-cli

**AI 코딩 에이전트 CLI 툴킷 — 설치·비교 + 비대화 위임 하네스**

AI 코딩 에이전트 CLI(Claude Code · Codex · Gemini · OpenCode · Cursor Agent · Pi)의 **설치·인증·비교**부터, 현재 세션 안에서 **다른 모델을 비대화로 소환→자율주행→resume**으로 이어가는 **위임 하네스**까지 한 팩으로 제공한다. 페르소나(**DA**·designer·architect)를 주입해 즉시 역할을 부여한다.

> v2.0 — 기존 `agent-cli`(설치·비교 가이드)에 `cross-cli`의 실행 하네스(스크립트·페르소나·안전·oh-my/baton/tmuxc 연계)를 통합하고, 2026-06 실증으로 4건 오류를 정정.

## 왜 쓰나

- **author ↔ review 분리** — 내가/한 모델이 짠 걸 *다른 모델*이 적대검증(DA)
- **프로바이더 무관 위임** — 같은 작업을 codex/gemini/claude에 던져 cross-check
- **세션 영속성** — 비대화로도 다회 Q&A·HIL·점진 결정 (`resume`)
- **설치·비교·Trust 가이드** — 어떤 CLI를 어떻게 깔고 래핑할지
- **상위 하네스**(선택, 로컬 설치 시) — oh-my-\*(ulw/ultraplan), baton, tmuxc. **미설치면 무시** — 핵심 기능(비대화 위임·페르소나·resume)은 이들 없이도 동작

## 6종 지원 (2026-06 실증 + Pi 추가)

| CLI | 비대화 | 자동주행 | resume |
|-----|--------|---------|--------|
| Claude Code | `claude -p` | `--dangerously-skip-permissions` | `--resume <sid>` |
| Codex | `codex exec` | `--full-auto` ⎮ `--yolo` | `codex exec resume --last` |
| Gemini | `gemini -p` | `--approval-mode yolo` | `--resume <session_id>` |
| OpenCode | `opencode run` | 기본 무승인 | `-s <sid>` / `-c` |
| Cursor Agent | `cursor-agent -p` | `-f` / `--force` | `--resume <chatId>` |
| Pi | `pi -p` | `--tools <allowlist>` (승인 프롬프트 없음) | `--session-id <sid>` / `--session <sid>` |

(+ Aider/Amp 참고 — `references/install-and-compare.md`)

## 구성

```
agent-cli/
├── SKILL.md                       ← 스킬 정의 (메인 지침 + 매트릭스 + 페르소나)
├── references/
│   ├── per-cli.md                 ← CLI별 비대화/자동주행/resume 상세
│   ├── install-and-compare.md     ← 설치·인증·Trust·래핑 비교·함정
│   └── personas.md                ← DA/designer/architect system-prompt
├── scripts/
│   ├── selftest.sh                ← 6종 비대화·자율·resume 일괄 점검(타임아웃·로그)
│   ├── test_opencode.sh           ← opencode 단독(모델 자동탐색)
│   ├── resume_chain.sh            ← 페르소나+다회 resume 체인
│   └── cloud-dataset-batch.sh     ← cloud session credits 로 학습·라벨링 데이터 대량 생성(+회수)
├── cli/install.md                 ← 에이전트 CLI 설치 안내
├── config/tools-section.md        ← TOOLS.md 추가 섹션
└── test/verify.md                 ← 설치 검증
```

## 클라우드 크레딧 배치 (학습·라벨링 데이터 생성)

Claude **cloud session credits**(구독과 별도로 지급되는 $250류)는 *cloud session 에서만* 차감된다. 로컬 CLI·프록시 경유 호출로는 0. 그래서 데이터 생성 물량을 크레딧으로 태우려면 이 경로뿐이다.

`scripts/cloud-dataset-batch.sh` 는 **repo·코드 없이** 빈 폴더에서 cloud session 을 띄우고, 완료되면 회수(teleport)해서 답변에 찍힌 JSONL 만 뽑아 데이터셋으로 적재한다.

```bash
bash scripts/cloud-dataset-batch.sh --task lexicon --lang ko,ja,th --count 300 --batch 25 --parallel 3 --budget 20
bash scripts/cloud-dataset-batch.sh --task label   --lang ko --labels work,tech,legal,daily,billing,other --count 200
bash scripts/cloud-dataset-batch.sh --task doc     --lang ko --count 4 --batch 4 --parallel 1 --budget 1   # 소량 시험
```

| task | 만드는 데이터 |
|---|---|
| `lexicon` | 언어학 사전 항목(lemma·pos·IPA·gloss·예문·register) |
| `parallel` | 병렬 말뭉치(src/tgt·domain) |
| `label` | 분류 라벨링(text·label·rationale) — `--labels` 로 폐쇄 집합 고정 |
| `qa` | 언어 학습 Q/A(level·topic) |
| `doc` | 장문 문서 섹션(520자/줄) — 대량 소진용 |
| `free` | 자유 형식 |

- 출력: `<out>/data.jsonl`(배치 간 중복 제거 + `id` 재부여) · `<out>/run-*/index.tsv`(세션·건수 원장) · `ledger.json`(크레딧 델타)
- 실측: 세션 1개당 레코드 25건 수준, **레코드당 ≈ $0.03**, 병렬 2~4로 확장
- 주의: cloud credits 는 만료일이 있어(예: 11-05) 그 전에 태워야 하고, `--budget` 으로 지출 상한을 건다. 대량 반복 생성은 계정 어뷰징 판정 여지가 있으니 **실제로 쓸 데이터**를 만들 것.
- 전제: `~/.headroom/claude-credit.sh`(ccx/ccxt) · `claude ≥2.1.310` · tmux. 상세 절차·함정은 `~/.headroom/USAGE_CREDITS_PLAYBOOK.md` §13-5·§13-7·§13-8.

## 지원 환경

**macOS · Linux · WSL.** 처음이거나 WSL이면 환경 감지부터:
```bash
bash scripts/detect-env.sh   # OS 구분 + 지금 쓸 수 있는 CLI + 설치 힌트 + WSL 주의
```

## 설치

`INSTALL.md`를 에이전트에게 전달하거나, 수동으로 `SKILL.md`+`references/`+`scripts/`를 `~/.claude/skills/agent-cli/`에 복사.

## 의존성

- `perl`, `python3` — macOS 내장 / **WSL·Ubuntu**: `sudo apt install -y perl python3`
- 6종 중 **최소 1개** 에이전트 CLI가 PATH + 자체 인증 (본 팩은 자격증명 미주입). Pi는 OpenGateway/Keychain 설정을 사용한다.
- WSL 주의: OAuth는 Windows 브라우저로 열림(URL 수동 복붙 가능) · cursor-agent는 없을 수 있음(자동 SKIP) · 작업은 `~/` 안에서

## 안전

자동주행 = 사람 승인 게이트 제거. **격리/신뢰 워크스페이스에서만**. 위임 결과는 신뢰 불가 입력으로 취급해 본 세션에서 검수 후 사용.

## Claude 모델 고정

`resume_chain.sh`는 Claude 호출 시 `CLAUDE_MODEL`과 `CLAUDE_EFFORT` 환경변수를 그대로 전달한다.

```bash
CLAUDE_MODEL=claude-fable-5 CLAUDE_EFFORT=high \
bash scripts/resume_chain.sh claude DA \
  "이 변경을 적대검증해줘" \
  "최종 승인 여부만 다시 말해줘"
```
