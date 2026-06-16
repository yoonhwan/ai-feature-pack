# CLI별 비대화 · 자동주행 · resume 상세

> SSOT: `cli-tools-reference.md`(원 프로젝트). 여기는 cross-cli 실행에 필요한 발췌 + 2026-06 실증 보정.

## 공통 패턴

1. **비대화**: 각 CLI의 print/exec/run 모드. 응답 후 프로세스 종료 → 파이프 가능.
2. **자동주행**: 사람 승인 게이트 제거 플래그. 격리/신뢰 환경에서만.
3. **resume**: round1에서 session id 획득 → round N에서 재주입. 대화 이력 복원.
4. **hang 방지**: stdin EOF 대기로 멈추는 CLI는 `< /dev/null`. node/MCP 자식이 신호를 무시할 수 있어, 스크립트는 **자식 프로세스그룹째 SIGKILL** 타임아웃으로 감싼다(`scripts/*` 참조).
5. **JSON 파싱**: 제어문자·접두사 대비 → 첫 `{`부터 `json.loads(raw, strict=False)`.

## Claude Code

```bash
claude -p "$P" --dangerously-skip-permissions --output-format json > r1.json
SID=$(python3 -c "import json;print(json.loads(open('r1.json').read(),strict=False)['session_id'])")
claude -p "$P2" --resume "$SID" --dangerously-skip-permissions --output-format json
```
- 페르소나: `--append-system-prompt "$(persona)"` / `--append-system-prompt-file <path>`(ARG_MAX 우회).
- 권한 단계: L3 `--dangerously-skip-permissions`, L2/L1 `--disallowedTools Bash,Write,Edit[,Glob]`.
- JSON 키: `session_id`, `result`, `total_cost_usd`, `usage`. (서버 과부하 시 `is_error:true` + `api_error_status:529` — 일시적, 재시도.)

## Codex

```bash
codex exec --full-auto --skip-git-repo-check "$P" < /dev/null            # 무승인+workspace-write
# 또는 (배타): codex exec --yolo --skip-git-repo-check "$P" < /dev/null
# ⚠️ codex는 session id를 stderr로만 노출 → sid 추출 대신 최근 세션 resume:
codex exec resume --last --full-auto --skip-git-repo-check "$P2" < /dev/null
```
- `--full-auto` 와 `--yolo`(=`--dangerously-bypass-approvals-and-sandbox`)는 **상호 배타**.
- `< /dev/null` 필수 — 없으면 stdin EOF 대기로 hang.
- 신버전은 `--full-auto` deprecated 경고(`--sandbox workspace-write` 권장) — 동작엔 지장 없음.
- 특정 세션 resume은 `~/.codex/sessions/`의 id를 인자로.

## Gemini

```bash
gemini -p "$P" --approval-mode yolo -o json > r1.json
# ⚠️ -o json 출력 앞에 "MCP issues detected..." 접두사가 붙을 수 있다 → 첫 '{'부터 파싱.
SID=$(python3 -c "import json,sys;s=open('r1.json').read();i=s.find('{');print(json.loads(s[i:],strict=False).get('session_id','') if i>=0 else '')")
gemini -p "$P2" --resume "$SID" --approval-mode yolo -o json
```
- `--approval-mode yolo`(신규 통합) 권장. 구 `-y`/`--yolo`와 **동시 사용 금지**.
- ⚠️ resume은 **JSON `session_id`로** — `--resume latest`는 비대화에서 hang 사례 관측(2026-06-15).
- MCP 서버가 startup에서 멈추면 첫 호출이 행할 수 있음 → 타임아웃 보호 필수. JSON 키: 결과=`response`, 세션=`session_id`.

## OpenCode

```bash
opencode run -m "$PROVIDER/$MODEL" "$P"           # run 기본 무승인
opencode run -s "$SID" -m "$PROVIDER/$MODEL" "$P2"  # 또는 -c (최근 세션)
```
- **유효 provider/model 필수** — `opencode models`로 확인. 예: `opencode/deepseek-v4-flash-free`(무료 zen), `google/antigravity-claude-sonnet-4-5`.
- 미설정 모델은 `ProviderModelNotFoundError`. antigravity Google 모델은 GCP 프로젝트 API enable 필요.
- 설정 파일은 **하나만**(opencode.json) 두기 — `.json`+`.jsonc` 공존 시 플러그인 중복 로드.

## Cursor Agent (≠ `cursor` IDE)

```bash
cursor-agent -p -f --output-format json "$P" > r1.json
SID=$(python3 -c "import json;print(json.loads(open('r1.json').read(),strict=False)['session_id'])")
cursor-agent -p -f --output-format json --resume "$SID" "$P2"
```
- `cursor`(IDE 바이너리)가 아니라 별도 `cursor-agent` CLI(3.0.12).
- `-f`/`--force` 필수 — 없으면 Workspace Trust 프롬프트로 블로킹.
- 페르소나는 프롬프트 prepend. JSON 키 `session_id`.

## Antigravity (`agy`) — Gemini CLI 후속/통합본

```bash
agy -p "$P" --print-timeout 60s --dangerously-skip-permissions          # R1 비대화+자율
agy -c -p "$P2" --print-timeout 60s --dangerously-skip-permissions       # 직전 대화 이어가기(resume)
agy --conversation "$ID" -p "$P2" ...                                    # ID로 특정 대화 resume
agy models                                                               # 모델 목록
```
- `agy`(v1.0.8+) = Google Antigravity CLI. **`gemini` CLI를 흡수·대체** — gemini OAuth가 깨졌어도 agy는 별도 Google 로그인으로 동작(2026-06-16 실증).
- **멀티모델 게이트웨이**: Gemini 3.5/3.1 Pro·Flash + Claude Sonnet/Opus 4.6 + GPT-OSS. `--model "Claude Opus 4.6 (Thinking)"` 식으로 모델 선택.
- resume = `-c`(최근 대화) 또는 `--conversation <ID>`. sid JSON 없음 → codex/opencode식 continue 모델.
- **`--print-timeout` 필수** — 없으면 답 출력 후 프로세스가 self-exit 안 하고 기본 5분 대기. 짧게(30~90s) 주면 즉시 종료.
- 첫 콜 cold-start 지연 가능(에이전트 데몬 기동) — 타임아웃이 처리. 페르소나는 프롬프트 prepend.
