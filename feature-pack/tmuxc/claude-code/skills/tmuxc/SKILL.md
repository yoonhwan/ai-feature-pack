---
name: tmuxc
description: tmux + Claude/Codex/OMX session control. "tmux 세션 열어", "claude/codex/omx 세션 만들어", "tmuxc", "tmc", "리모트 세션", "remote session", "프로젝트 세션 생성", "tmux 목록", "tmux 정리", "세션 정리", "세션 증류", "세션 클린업", "세션 복원", "세션 복구", "양방향 메시지", "세션간 메시지" 요청 시 자동 실행. (global) (user)
---

# tmuxc — tmux + Claude/Codex/OMX Session Control

## 개요

특정 프로젝트 폴더에 tmux 세션을 생성하고 Claude Code, Codex CLI, 또는 OMX Codex 런타임을 실행한다. Claude는 `--remote-control` 옵션을 쓰고, Codex/OMX는 tmux pane + verified send/capture 방식으로 제어한다. 세션 생성·목록·**양방향 메시지**·종료·정리·**증류(클린업)**·**복원**을 한곳에서 관리.

오케스트레이터(예: "00" 중앙 세션)가 여러 워커 세션을 tmux로 조율하는 패턴을 1급 지원한다. 아래 UC9~11은 2026-06 BYZ-Agents nextjs-redesign fan-out(00↔01~05) 오케스트레이션에서 **실전 검증**된 방법론이다.

## 명령어

| 명령 | 설명 |
|------|------|
| `tmuxc open {path} [--name N] [--agent claude\|codex\|omx] [--role worker\|orchestrator\|designer] [--prompt P]` | 프로젝트에 세션 생성 |
| `tmuxc list` | 활성 세션 목록 + Claude 상태 |
| `tmuxc attach {name}` | 세션 접속 안내 |
| `tmuxc send {name} "msg"` | 세션에 메시지 전달 (보안 가드) |
| `tmuxc ask {name}` | 세션 응답/상태 읽기 (capture-pane) — 양방향 수신 |
| `tmuxc msg {name} "msg"` | 메시지 전송 후 응답까지 확인 (send + ask 왕복) |
| `tmuxc rename {old} {new}` | tmux 세션명 + claude 내부 세션명(`/rename`) **동시 변경** |
| `tmuxc kill {name} [--all]` | 세션 종료 |
| `tmuxc clean` | Claude 종료된 빈 세션 정리 |
| `tmuxc wt {worktree-path} [--prompt P]` | 워크트리 연계 세션 생성 |
| `tmuxc distill {name} [--to {newbase}]` | **세션 증류** — `{base}#{N+1}` 신규 세션에 컨텍스트 이전 후 구세션 정리 |
| `tmuxc recover [--all]` | cmux에서 디스커넥트된 tmux 세션 자동 재연결 |
| `tmuxc restore [--all]` | **tmux 서버 사망 복원** — claude 세션 인덱스 기반 tmux 재생성 + `--resume` |

---

## UC1: 세션 생성 (`tmuxc open`)

```
tmuxc open /path/to/project --name my-session --agent omx --role worker --prompt "NEXT.md 읽고 시작"
```

**동작:**
1. 프로젝트 경로 존재 확인
2. **경로 정규화 (worktree/repo root 자동 cd)**:
   - `git -C {path} rev-parse --show-toplevel` 시도. 성공 시 결과를 `{root}`로 사용
   - 실패 (git repo 아님) 시 `{path}` 그대로 `{root}` 사용
   - 사용자가 `.../runpod-stt-tts-poc/tests/manual/fixtures/runpod_smoke` 같은 sub-dir에서 호출해도 워크트리 root에서 세션 시작됨
3. 세션 이름 결정: `--name` 지정 시 사용, 아니면 `{root}` basename에서 자동 생성
   - **세션명 sanitize**: `.` `:` → `-`, 공백 → `-`, 비ASCII 제거
   - **증류 카운터 `#0` 상시 부여**: 최종 세션명에 `#{N}` 카운터가 없으면 `{base}#0`으로 시작 — UC10 증류를 기본 대비 (첫 증류 = `#1`)
4. 동명 세션 존재 시 → 에러 (attach 안내)
5. `tmux new-session -d -s {name} -c {root}` ← 정규화된 root 기준 cwd
6. **agent 실행 명령 해석** (아래 "CLI 명령 해석" 섹션 참조):
   - 1순위: `~/.zshrc`의 **역할별 alias**(`ccd`/`ccf`) 체인을 해석한 결과 + `--name {name} --remote-control {name}` 추가
     - **모델 라우팅**(UC1-4): 3-tier — `ccs`(Sonnet, 코딩·작업) / `ccd`(Opus, 테스트·검증·오케스트레이터) / `ccf`(Fable, 설계자문·기획, 자문 완료 후 닫음). 역할→세션 정본은 byz-zion 「세션 모델 라우팅」.
   - 2순위 (ccd 미정의 시 fallback): `claude --name {name} --remote-control {name}`
   - **[필수] `--name {name}` 누락 금지**: claude 내부 세션 display name을 기동 시점에 지정 (`-n, --name <name>`). 누락하면 내부 세션 식별 불가 → 사후 `/rename` 주입이 매번 필요해지는 문제 재발 (2026-06-05 개선)
   - Codex: `codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort="<medium|high>"`
   - OMX: `omx --madmax [--high]`
   - Codex/OMX는 Claude의 `--remote-control`이 없으므로 tmux verified-send + `capture-pane`로 제어한다.
7. `tmux send-keys -t {name} "{resolved-cmd}" Enter`
8. **[필수] 통신 가이드 주입**: claude 부팅 대기(아래 "부팅 대기 패턴") 후 COMM-GUIDE 주입 메시지를 첫 메시지로 전송:
   ```bash
   tmux send-keys -t {name} -l "[{orch}→{name}] 통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE.md 를 지금 Read하고 그대로 따를 것. 너의 세션명(me)={name}, 오케스트레이터(orch)={orch}. 세션간 메시지는 반드시 검증 송신 프로토콜(가이드 §2) 준수 — send 후 도달 확인 전 '전송 완료' 보고 금지."
   tmux send-keys -t {name} Enter
   ```
   - `{orch}` = 이 tmuxc를 실행 중인 오케스트레이터 세션명 (자신이 tmux 안이면 `tmux display-message -p '#S'`, 아니면 `00` 등 호출자 지정)
   - 세션간 메시지 유실("보냈다는데 안 감")의 근본 대책 — 모든 신규 세션이 동일 프로토콜을 공유하게 한다
9. `--prompt` 있으면 가이드 주입 후 `tmux send-keys -t {name} -l -- "{prompt}"` + Enter (별도 호출 분리)
10. 출력:
   ```
   ✅ tmuxc 세션 생성
   세션: {name}
   원본 경로: {path}
   세션 cwd: {root}    (worktree root로 정규화됨)
   Remote: {resolved-cmd}
   통신 가이드: 주입 완료 (COMM-GUIDE.md)
   접속: tmux attach -t {name}
   ```

### UC1-C: Codex/OMX agent mode

V6 BYZ 작업처럼 Codex + OMO 스킬을 써야 하는 경우 기본 권장값은 OMX다:

```bash
tmuxc open /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents \
  --name BYZ_V6#0 \
  --agent omx \
  --role orchestrator \
  --prompt "AGENTS.md와 .omo/plans/v5-energy-vad-realtime-live.md를 읽고 V6 작업 준비"
```

Codex 단독이 필요하면:

```bash
tmuxc open . --name BYZ_V6_WORKER#1 --agent codex --role worker
```

역할 라우팅:

| agent | role | 실행 |
| --- | --- | --- |
| `claude` | `worker` | `ccs ... --name --remote-control` |
| `claude` | `orchestrator` | `ccd ... --name --remote-control` |
| `claude` | `designer` | `ccf ... --name --remote-control` |
| `codex` | `worker` | `codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort="medium"` |
| `codex` | `orchestrator/designer` | `codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort="high"` |
| `omx` | `worker` | `omx --madmax` |
| `omx` | `orchestrator/designer` | `omx --madmax --high` |

## UC1-2: Claude Code 세션 내부 이름 (`/rename`)

**tmux 세션명과 Claude Code 내부 세션 이름은 별개다.** `tmux rename-session` 만 하면 tmux 레벨만 바뀌고 claude 내부 세션은 구분이 안 된다 — 멀티 세션 오케스트레이션에서 세션을 알아보려면 **둘 다** 맞춰야 한다.

> **신규 세션은 이 섹션 불필요**: UC1이 기동 시 `--name {name}`으로 내부 세션명을 바로 지정하므로 `/rename` 사후 주입은 **이미 떠 있는 세션의 이름 변경** 시에만 사용 (→ `tmuxc rename`, UC1-3).

| 레벨 | 설정 방법 | 반영 위치 |
|------|-----------|-----------|
| tmux 세션명 | `tmux rename-session -t <old> <new>` | `tmux ls`, `attach -t` 대상 |
| Claude Code 내부 세션명 | `/rename <name>` (claude 슬래시 명령) | `/resume` 목록·세션 식별 (statusline 미표시) |

### 원격으로 `/rename` 주입 (오케스트레이터 → 세션)

```bash
# claude 가 idle(프롬프트 대기)일 때 권장. 작업 중이면 입력 큐 → 다음 턴 적용.
tmux send-keys -t <session> "/rename <name>"; sleep 0.4
tmux send-keys -t <session> Enter
```

- **tmux명 = /rename명 일치 권장** (예: tmux `FB_RT` ↔ claude `/rename FB_RT`) — 혼선 방지.
- 적용 확인은 `capture-pane` 으로 **안 됨**(statusline 에 세션명 미표시) → 세션 탭 제목 / `/resume` 목록에서 확인.
- 작업 중(thinking/skill 실행) 주입 시 슬래시 명령이 다음 idle 턴에 처리됨 → 세션이 **보고를 보낸 직후**(= 잠깐 idle) 타이밍에 주입하면 확실.

## UC1-3: 이름 변경 (`tmuxc rename`)

기존 세션의 이름을 **tmux + claude 내부 양쪽 동시에** 변경. 생성 시 `--name` 누락·오타, 역할 변경, 증류 카운터 정정에 대응.

```
tmuxc rename {old} {new}
```

**동작:**
1. 세션 존재 + claude 실행 확인 (UC4와 동일 HARD GATE — claude 미실행이면 tmux 레벨만 rename하고 `/rename` 주입 생략 안내)
2. `{new}` sanitize (UC1 규칙) + **카운터 보존**: `{new}`에 `#{N}`이 없으면 `{old}`의 카운터 승계 (`proj#2` → `api`로 rename 시 `api#2`; old도 카운터 없으면 `{new}#0`)
3. tmux 레벨: `tmux rename-session -t {old} {new}`
4. claude 내부 레벨: `/rename {new}` 주입 (idle 타이밍 권장 — UC1-2 패턴):
   ```bash
   tmux send-keys -t {new} "/rename {new}"; sleep 0.4
   tmux send-keys -t {new} Enter
   ```
5. 출력: `✅ {old} → {new} (tmux + claude 내부 동시 변경)`

**주의**: remote-control 채널명은 기동 시 `--remote-control {old}`로 고정 — rename 후에도 채널은 구이름 유지. 채널까지 새 이름으로 맞추려면 UC10 증류(재기동)로 처리.

## UC1-4: 세션 모델 라우팅 (3-tier: ccs=Sonnet / ccd=Opus / ccf=Fable)

세션을 **역할**에 맞는 모델 alias로 기동한다. 모두 headroom 래퍼(`~/.headroom/claude-hr.sh`) 경유 — 등록 프로젝트면 압축 자동 적용 + 프록시 死이면 직결(fail-open). 글로벌 `ANTHROPIC_BASE_URL` 정적 export 금지 규칙과 양립.

| alias | 모델 | effort | 역할 |
|-------|------|--------|------|
| `ccs` | Sonnet 4.6 (`claude-sonnet-4-6`) | max | **코딩·작업·라이브러리 서치·작업 하네스** — 구현 루프, 파일 수정, 리서치 보조 |
| `ccd` | Opus 4.8 (`claude-opus-4-8[1M]`) | high | **테스트·버그·로그 증명·확인·문제 정의** — 검증, 재현, DA 폴백, 오케스트레이터 |
| `ccf` | Fable 5 (`claude-fable-5`) | medium | **아키텍처·기획·설계·문제해결 자문** — 설계 검토 후 닫음, 결과만 수신 |

### 표준 3-세션 구조 (2026-06-12 확정 — HIL 지침)

**핵심 원칙: worker(sonnet) 컨텍스트를 풀로 태워 토큰 효율을 극대화한다.** orchestrator(opus)는 디스패치·판정·조율만 하며 컨텍스트를 아끼고, 실제 작업량(로그·코드 풀서치·구현)은 sonnet worker가 풀컨텍스트로 소화한다.

```
[ccd = orchestrator] opus   — 지휘·테스팅 판정·증거 취합·머지 조율. ctx 절약(디스패치/판정만).
[ccf = designer]     fable  — 문제 정의·수정 기획·설계·막힘 시 문제해결 위임처.
[ccs = worker]       sonnet — 실작업: 로그 풀서치·코드 컨텍스트 풀서치·구현. ctx 풀로 소진(토큰효율 극대화).
```

worker가 **항상 가장 큰 작업량**을 담당하도록 설계한다. orch·designer는 결론만 들고 가볍게 유지. worker ctx가 한계(80%+)면 증류/교체하되 역할(작업 주력)은 유지한다.

**★ 전략참모 (Strategist) — 3구조 위 프로젝트 전략층 (2026-06-12 신설)**: `FB_Main_#10000`(fable, #1000+ tier). orch(작업 사이클 지휘) 위에서 **프로젝트 전반 전략·기획·설계 + codex DA approve loop으로 전략 생산**. designer(작업단위 기획)와 달리 **상시 영구**(두고두고) — 테스트방법 SOP·세션 증류전략·디버그 방법론·인프라 SOP를 DA approve로 정립. orch가 전략 과제 발급 → 전략참모가 DA 검증된 전략 공급. 작업 사이클(orch/designer/worker)이 코드에 매몰될 때 상위 전략·방법론을 잡아준다.

**경량 변형(2-세션)**: 설계·기획이 불필요한 단순 사이클은 ccd(orch+판정) + ccs(worker)만으로 돌리고, 자문이 필요할 때만 ccf를 추가로 열어 방향 확정 후 닫는다(증류 또는 kill).

**★ design↔dev↔orch 의존성 루프 (필수 순환)**: designer(문제정의/기획) → worker(구현) → orch(라이브 판정) → **designer(기획 검증·gap 발견)** 로 순환한다. **designer를 빼고 orch+worker만 돌리면 "코드가 기획을 멋대로 결정"하는 구멍이 생긴다** (2026-06-12 실증: release 진입 UX를 `realtime-room-station:97` 하드코딩이 멋대로 결정 중인 걸 designer 투입 후에야 발견 — 동시에 기획 gap 5건+리스크 3건 적출). 개발이 코드에 매몰될수록 designer의 기획 검증 패스가 값을 낸다. P2-c식 협업 = worker 구현초안 → designer §5 대조리뷰 1왕복.

**★ e2e 베이스 (증류 신규 세션 필독)**: 코드 merged·**jest green ≠ 완료**. **라이브 e2e + HIL 확인이 완료 게이트**. "jest green"은 DoD가 아니다 — 각 phase DoD에 검증 게이트(G번호 등)를 명시하라. **멀티 워크트리 dev 포트 혼선**(여러 워크트리가 :3131/:3001/:3015 dev 동시 기동 → 발화가 어느 코드로 갈지 비결정 → 옛 코드 통과=가짜검증)은 라이브 e2e 최대 함정 — "어느 포트=어느 워크트리=어느 commit" 객관확정 + 로컬 auth는 `?mockHostId=`(실로그인 아님)가 SOP. 신규 세션 증류 시 이 루프·e2e 베이스를 반드시 참고 (야간 e2e 0회로 4시간+토큰 절반 날린 2026-06-12 재발 방지).

### 모델별 특성·비용 메모

- **Fable 5**: 최상위 모델, Opus 비용 초과 + 토크나이저 ~30% 토큰↑ = ctx 소비 빠름. 자문 결과가 나오면 즉시 닫아 비용 절감.
- **Fable 윈도우 정책**: ccf는 **1M 윈도우 금지** — 표준 윈도우로 기동, **ctx 80%에서 증류** (일반 70% 예외). ccf alias에 `[1M]` 붙어있으면 제거.
- **Opus 4.8**: 검증·로그 분석·DA 기본 모델. `[1M]` 윈도우 허용(긴 로그·diff 처리).
- **Sonnet 4.6**: 빠르고 비용 효율적. 구현·서치 루프에서 대부분의 실제 작업량 담당.
- **alias 해석**: `zsh -ic 'type ccs|ccd|ccf'`로 해석, eval 금지·type 출력만 신뢰.
- **증류 시 모델 선택**: UC10-2 참조 (역할 유지 or 의도적 업/다운 가이드).
- **Fable hang 임계**: 수 분~십수 분 정상(롱호라이즌) → "무변화 시간"만으로 hang 금지. CPU<0.3 2회 연속이 최종심.

## UC1-5: FB_OPS 세션 번호 규약 — 자릿수별 모델·effort 라우팅 (2026-06-11 확정)

FB_OPS 세션명은 `FB_OPS#{N}` 형태이며, **번호 자릿수**가 모델·effort를 결정한다.

| 번호 범위 | 자릿수 | alias | 모델 | effort | think | 대표 예시 |
|-----------|--------|-------|------|--------|-------|-----------|
| `#0 ~ #99` | 2자리 | `ccs` | Sonnet 4.6 (`claude-sonnet-4-6`) | max | on | `FB_OPS#0`, `FB_OPS#99` |
| `#100 ~ #999` | 3자리 | `ccd` | Opus 4.8 (`claude-opus-4-8`) | high | on | `FB_OPS#100`, `FB_OPS#999` |
| `#1000+` | 4자리+ | `ccf` | Fable 5 (`claude-fable-5`) | medium | on | `FB_OPS#9999`, `FB_OPS#10000` |

**기동 예시 (세션 생성 시 번호별 alias 선택)**:
```bash
# 2자리 — sonnet + ultracode
ccs --effort max --name "FB_OPS#99" --remote-control "FB_OPS#99"

# 3자리 — opus4.8 + high
ccd --effort high --name "FB_OPS#999" --remote-control "FB_OPS#999"

# 4자리+ — fable5 + medium (ccf, 1M 윈도우 금지)
ccf --effort medium --name "FB_OPS#9999" --remote-control "FB_OPS#9999"
```

**규칙**:
- **세션은 실제 작업이 있을 때만 열기** — 번호 tier가 정해졌다고 미리 오픈하지 말 것. 태스크 주입 직전에 생성하고, 작업 완료 후 닫는다. 작업 없는 대기 세션은 비용·ctx 낭비.
- alias가 정의되지 않은 경우(`ccs` 미정의): `zsh -ic 'type ccs'` 실패 → ccd로 fallback하고 `--model claude-sonnet-4-6`을 명시 추가
- ccf는 UC1-4 Fable 윈도우 정책 그대로 적용 (1M 금지, ctx 80% 증류)
- 번호 자릿수는 증류 시 카운터(`#N`)가 아닌 **원래 번호**로 판정 (`FB_OPS#99` → 2자리 = sonnet tier 유지)
- `#0`(오케스트레이터·온콜)은 0~99 tier이지만 특수 세션이므로 ccd로 기동하는 것이 일반적

## UC2: 세션 목록 (`tmuxc list`)

```
tmuxc list
```

**동작:**
1. `tmux list-sessions` 실행
2. 각 세션에서 claude 프로세스 확인 (`tmux list-panes -t {session} -F "#{pane_current_command}"`)
3. 테이블 출력:
   ```
   # | 세션명         | 경로                     | Claude | 상태
   1 | baton-upgrade  | ~/Project/ai-feature-... | ✅     | active
   2 | byz-old        | ~/Project/Agent/BYZ-...  | ❌     | zombie (shell-only)
   ```

## UC3: 세션 접속 (`tmuxc attach`)

```
tmuxc attach {name}
```

`tmux attach -t {name}` 또는 iTerm2 통합 `tmux -CC attach -t {name}` 실행.
**경고**: cmux 안에서는 `tmux -CC`(control 모드) 금지 — UC8 참조.

## UC4: 메시지 전송 (`tmuxc send`) — 오케스트레이터 → 세션

```
tmuxc send {name} "메시지 내용"
```

**동작:**
1. 세션 존재 확인
2. **[HARD GATE] Claude 프로세스 실행 확인** — `pane_current_command`(또는 `pgrep -P {pane_pid}`)에 `claude`가 없으면 **절대 send-keys 실행 금지**:
   ```
   ❌ 세션 '{name}'에 Claude가 실행 중이 아닙니다.
   쉘에 직접 명령이 전달될 위험이 있어 차단합니다.
   tmuxc kill {name} 후 재생성하세요.
   ```
3. 메시지 전달 (**-l 과 Enter 분리** — 실전 안정):
   ```bash
   tmux send-keys -t {name} -l "메시지 내용"   # -l 리터럴: 특수문자 쉘 확장 방지
   tmux send-keys -t {name} Enter              # 별도 호출로 제출
   ```
   - `-l`+`Enter`를 한 호출에 합치지 말 것. 분리해야 입력 누락/오제출이 적다 (실전).

---

## UC9: 양방향 세션간 메시지 (`tmuxc ask` / `tmuxc msg`)

오케스트레이터(00)와 워커 세션 간 **양방향** 소통. send(UC4)가 00→세션이라면, ask는 세션→00 수신, msg는 왕복.

### 9-1. 세션 응답/상태 읽기 (`tmuxc ask` — 세션 → 00)

claude는 stdin 단방향이라 "역방향 메시지 API"가 없다. **세션의 tmux pane 버퍼를 읽어 응답·상태를 회수**한다.

```bash
tmux capture-pane -t {name} -p | grep -vE '^\s*$' | tail -16
```

읽은 화면에서 다음을 판독한다:
- **세션의 텍스트 응답** (claude가 출력한 보고/질문)
- **statusline**: `thinking` / `ctx:NN%` / `🤖N`(서브에이전트 수) / `session:Nm`
- **입력 대기 상태**: `❯ ` 빈 프롬프트 = idle, `❯ 텍스트` = 미제출 입력
- **AskUserQuestion 옵션 화면**: `Enter to select · ↑/↓ to navigate · Esc to cancel`

### 9-2. 생존/hang 판별 (실전 — CPU 기반)

화면이 안 변하면 thinking인지 hang인지 CPU로 판별한다:
```bash
PANE=$(tmux list-panes -t {name} -F '#{pane_pid}' | head -1)
CL=$(pgrep -P $PANE | head -1)          # pane 자식 claude PID
ps -o %cpu=,etime= -p $CL
```
- **%CPU ≥ 0.3** = 정상 thinking → 방해 금지 (ctx도 증가)
- **%CPU < 0.3** + 화면 수분간 무변화 = **hang** → UC10 리프레시(kill→재기동→resume)
  (단일 경계 0.3 — dead-zone 없음. 경계 근처(0.2~0.3)면 화면 변화·ctx·etime 증가를 보조로 판단)
  - **Fable 5(ccf) 세션 보정**: Fable은 단일 요청이 수 분~십수 분 실행이 정상(롱호라이즌). CPU<0.3 **2회 연속(45~60초 간격)**일 때만 hang 확정 — "무변화 시간"만으로 판정 금지(정상 사고 오판). CPU가 최종심인 건 동일.
- (실전 2026-06-01: 05 세션이 codex DA hang으로 CPU 0.1·30분 무변화 → 가짜 `thinking` statusline. CPU가 진위 판별.)

### 9-3. 메시지 왕복 (`tmuxc msg`)

```bash
tmuxc send {name} "질문/지시"      # UC4
sleep 3~5                           # claude 처리 대기
tmuxc ask {name}                    # 9-1로 응답 읽기
```
응답이 thinking이면 추가 대기, 입력 대기면 다음 지시. 필요한 만큼 왕복.

### 9-4. AskUserQuestion 응답 (옵션 화면 → 자유 텍스트)

세션이 자체 AskUserQuestion 옵션 화면(`1. ... 2. ...`)에 멈춰 있으면, **send-keys 텍스트가 옵션 모드에서 무시**된다. 처리법(실전 검증):
```bash
tmux send-keys -t {name} Escape       # 옵션 모드 탈출 → 일반 프롬프트(❯)
sleep 2
tmux send-keys -t {name} -l "자유 텍스트 응답/지시"
tmux send-keys -t {name} Enter
```
- 단 claude가 **작업 실행 중**일 때 Escape는 "Interrupted"로 작업 중단 — 실행 중 vs 옵션 대기를 9-1·9-2로 먼저 구분.

### 9-5. 양방향 규약 (메시지 포맷)

혼선 방지를 위해 메시지 앞에 방향 prefix를 붙인다:
- 00 → 세션: `[00→{name}] 내용`
- 세션 → 00: 세션이 `tmux send-keys -t {00-session} -l "[{name}→00] 내용"` + Enter 로 **역방향 send** 가능 (00도 일반 claude 세션이면 수신). 또는 00이 9-1로 polling.
- 신규↔구 세션 질의(UC10): `[{new}→{old}] 질의`, `[{old}→{new}] 답변`

### 9-6. 검증 송신 프로토콜 (verified send) — 유실 방지 필수

`send-keys`는 **항상 exit 0** — "보냈다 ≠ 도착했다". 세션이 "보냈다"고 주장해도 미도달인 사례 빈발(2026-06-05). 모든 세션간 송신은 **`~/.claude/skills/tmuxc/COMM-GUIDE.md` §2의 4단계** 준수:

1. 타겟 세션 + claude 실행 확인 (HARD GATE)
2. 타겟 상태 판독 — 옵션 모드면 Escape, 미제출 입력(`❯ 텍스트`) 잔류면 `C-u` 클리어
3. `-l` 송신 + Enter **별도 호출** (sleep 0.3 사이)
4. `sleep 2` 후 `capture-pane -t {target} -p | grep -qF "[{me}→"` 도달 검증 — 미도달이면 Step 2부터 재시도(최대 3회)

**검증 통과 전 "전송 완료" 보고 금지.** 이 프로토콜은 UC1 step 8에서 모든 신규 세션에 COMM-GUIDE로 자동 주입된다.

---

## UC5: 세션 종료 (`tmuxc kill`)

```
tmuxc kill {name}
tmuxc kill --all
```

**동작:**
1. Claude 실행 중이면 `/exit` 전달 (graceful). hang이라 `/exit` 무반응이면 → claude PID에 `kill -TERM {pid}` (pane은 shell로 복귀).
2. 5초 대기
3. `tmux kill-session -t {name}`

## UC6: 세션 정리 (`tmuxc clean`)

```
tmuxc clean
```

Claude가 종료된 빈(zombie/shell-only) tmux 세션을 찾아 정리. 사용자 확인 후 kill.

## UC7: 워크트리 연계 (`tmuxc wt`)

```
tmuxc wt .worktrees/v5-phase-c --prompt "NEXT.md 읽고 시작"
```

워크트리 경로 → 절대 경로 변환, 그 다음 UC1과 동일하게 `git rev-parse --show-toplevel`로 root 재확인 (워크트리 내부 sub-dir이 들어와도 root로 정규화). 세션명 = root basename. 나머지(claude 실행 명령은 역할에 따라 ccs|ccd|ccf alias 해석, UC1-4 기준)는 UC1과 동일.

**현 cwd가 워크트리 sub-dir인 경우**:
```
$ pwd
/Users/x/proj/.worktrees/feat-a/tests/manual/fixtures
$ tmuxc wt .
# → root: /Users/x/proj/.worktrees/feat-a (자동 정규화)
# → 세션명: feat-a
# → 세션 cwd: 워크트리 root
```

---

## UC10: 세션 증류 / 클린업 워크플로우 (`tmuxc distill`)

긴 세션(ctx 과다, **70%+**)이나 hang된 세션을 **새 깨끗한 세션으로 컨텍스트를 이전**하고 구세션을 닫는다. `compact`보다 정확·재현(핸드오프 SSoT 기반)하며 cache miss를 피한다.

> **증류 트리거 = ctx 70%** (구 80%에서 하향). cache miss·증류 작업분의 여유 마진 확보. **예외 — Fable 5(ccf) 세션은 80%까지 사용** (2026-06-11 사용자 확정): ccf는 1M 윈도우 금지·표준 윈도우 전제이므로 80%에서 증류. (5h:9X% 사용량 한도는 별개 축 — 둘 중 먼저 닿는 쪽이 baton save 트리거.)

### 10-1. 세션명 카운터 `{base}#{N}`

세션명은 `{base}#{N}` 형식. N = 증류 횟수(몇 번째 증류본인지). 신규 증류는 N+1. **UC1 규약상 신규 세션은 상시 `{base}#0`으로 시작**하므로 첫 증류 = `#1` (카운터 없는 구식 세션은 N=0 취급 — 아래 파싱이 방어).
```bash
# 현재 세션명에서 base/N 파싱 (#{N} 없으면 N=0 → #1부터)
cur="myproj#3"
case "$cur" in
  *#*) base="${cur%#*}"; N="${cur##*#}";;   # myproj#3 → base=myproj, N=3
  *)   base="$cur"; N=0;;                    # myproj(#없음) → base=myproj, N=0
esac
new="${base}#$((N+1))"                        # myproj#4 (또는 myproj#1)
```
카운터는 세션명에 내장되므로 별도 파일 불필요 (`tmux list-sessions`로 현재 N 확인).

### 10-2. 증류 절차 (실전)

**증류 시 모델 선택 (3-tier: ccs→ccd→ccf)**

증류 신규 세션의 모델은 아래 3가지 중 하나를 의도적으로 선택한다. **기본은 역할 유지(동일 tier)**.

| 선택 | 조건 | 예시 |
|------|------|------|
| **동일 tier 유지** | 역할 변화 없이 ctx 초과만 해소 | ccs 세션 증류 → ccs로 재기동 |
| **업그레이드** | 작업이 복잡해져 더 강한 추론 필요 | ccs 작업 중 근본 원인 분석 필요 → ccd로 업 |
| **다운그레이드** | 자문 완료·설계 확정 후 구현 단계 진입 | ccf 설계 세션 증류 → ccs로 다운(구현 전환) |

- **업그레이드 흐름**: ccs → ccd(검증 필요) → ccf(설계 재검토) — 작업이 깊어질수록
- **다운그레이드 흐름**: ccf(자문 완료) → ccd(검증) → ccs(구현) — 방향 확정 후 비용 절감
- ccf 자문 세션은 결과 도출 후 ccd·ccs로 다운그레이드 증류가 일반적 (ccf는 상시 유지 비용 높음)
- FB_OPS 번호 규약 세션(UC1-5)은 번호 자릿수가 tier를 결정하므로, 다운그레이드 시 번호도 변경 (`#9999` → `#999`)

```
1. (선택) 구세션에서 핸드오프 저장:  baton 세션이면 tmuxc send {old} "[00→old] /baton:save"
2. 신규 세션 생성 — 모델은 위 선택 기준에 따라 결정:
   tmux new-session -d -s {base}#{N+1} -c {root}
   tmux send-keys -t {base}#{N+1} -l "{ccs|ccd|ccf-resolved} --name {base}#{N+1} --remote-control {base}#{N+1}"
   tmux send-keys -t {base}#{N+1} Enter
3. remote ready 대기(부팅): 9~12초 후 capture-pane으로 `❯`(ctx:0%) 확인 (아래 "부팅 대기 패턴")
3-1. **통신 가이드 주입** (UC1 step 8과 동일 — COMM-GUIDE.md 경로 + me={base}#{N+1}, orch 명시)
4. 컨텍스트 이전(둘 중 택1):
   (a) baton 세션:   tmuxc send {base}#{N+1} "[00→new] /baton:resume"   # NEXT.md/CURRENT 자동 복원
   (b) 비-baton:     구세션 핵심 컨텍스트 풀 메시지 + 파일 인덱스 경로를 send
       - 역할/완료 커밋/현재 작업/검증 기준/후속 + 관련 파일 경로 목록(예: 'PLAN: .claude/plans/X.md')
5. 로드 확인: tmuxc ask {base}#{N+1} → 신규 세션이 컨텍스트 이해했는지 응답 판독.
   부족하면 추가 메시지 발급(얼마든). 신규→구 역질의도 가능: [new→old] 질의 → old가 [old→new] 답.
6. 완료(신규가 정상 인계 확인)되면 구세션 정리:  tmuxc kill {base}#{N}
```

### 10-3. 같은 세션 즉시 리프레시 (hang 복구 변형)

증류(새 세션명)까지 안 가고 **같은 pane에서 claude만 재기동**하는 경량 변형. UC9-2로 hang 확진된 세션에:
```bash
kill -TERM {claude-pid}                                   # hang claude 종료 → pane이 shell 복귀
# claude 종료 시 "Resume this session with: claude --resume {uuid}" 출력 → uuid 즉시 보존
# (capture tail-16 밖으로 스크롤돼 uuid 못 잡으면 → UC11 sessions-index.json 조회로 fallback, 추측 금지)
tmux send-keys -t {name} -l "{ccd-resolved} --name {name}"; tmux send-keys -t {name} Enter   # 새 claude 기동 (내부 세션명 유지)
sleep 9                                                   # 부팅
tmux send-keys -t {name} -l "/baton:resume"; tmux send-keys -t {name} Enter    # 핸드오프 복원
```
(실전 2026-06-01: 05 hang → 이 절차로 복구 → baton resume으로 미커밋 작업까지 이어감.)

### 10-4. baton 연계 (v1.2.11~13 컨텍스트 레디)

baton 세션(`.baton/handoff/` 존재)은 증류 시 `/baton:save`(구) → `/baton:resume`(신)로 핸드오프(NEXT/CURRENT/PLAN/JOURNAL) 자동 전수. 비-baton 세션은 10-2(b) 수동 컨텍스트 전달.

**컨텍스트 레디 가속** (워밍 시간↓·본체 ctx↓ — 2026-06-13 도그푸딩 실증):
- **save 시**: 구세션(풀컨텍스트)이 CURRENT.md 두 섹션을 채운다 — `## 🎯 즉시 읽기 (CONTEXT_PACK)`(다음 세션이 탐색 없이 열 핵심 파일 `경로:라인 — 이유`, **라인은 `grep -n` 실측**) + `## ✅ 검증됨@commit`(이미 실측된 사실 — 같은 commit이면 재실측 생략).
- **resume 시**: 신규 세션은 NEXT.md 출력 직후 CONTEXT_PACK을 **단일 메시지 병렬 Read**로 선로딩(재탐색 0회). 5개 초과/대용량이면 **haiku/sonnet 요약 에이전트(Workflow)로 회수 → 본체 ctx 99%+ 절약**(7파일 307k토큰 격리/본체 ~0.5KB 실측). 끝나면 `baton warming-done`(워밍 계측, `warming-stats`로 추이).
- **ad-hoc 세션**(tmuxc 직접 발주 등 wt-create 비경유, `.baton/handoff` 부재): `baton save`가 거부되면 `baton init-handoff <phase-id>`로 자가복구 후 save (수동 템플릿 sed 금지).

**에러 대응** → 이 워크플로우(baton save/resume·증류·tmux 송신)에서 막히면 **`references/baton-tmuxc-troubleshooting.md`** 참조 (실증 함정 + 1줄 처방).

---

## UC8/UC11: 재해 복구 (cmux 디스커넥트 / tmux 서버 사망)

**장애 시에만** 필요한 복구 절차는 본문에서 분리 → **`references/tmuxc-disaster-recovery.md`** (on-demand Read).

- **UC8 (cmux 디스커넥트)**: `[server exited unexpectedly]`로 세션이 끊겼으나 `tmux list-sessions`에 `attached=0`로 살아있음 → cmux 미러만 끊긴 것. cmux CLI로 재연결. (`tmux -CC` control 모드 금지가 근본 규칙.)
- **UC11 (서버 사망)**: `tmux list-sessions`가 `no server running` 에러 → 서버 프로세스 자체 사망. `~/.claude/projects/*/sessions-index.json`으로 tmux 재생성 + `claude --resume {sessionId}`로 대화 복원.
- **먼저 구분**: `attached=0` = UC8 / `no server running` = UC11. 상세 절차·함정은 위 reference.

---

## Claude Code 네이티브 `--tmux`와의 차이

`claude -w name --tmux`는 워크트리+tmux를 한번에 생성하는 빌트인 기능.

**tmuxc의 차별점:**
- `--remote-control` 결합 (네이티브에 없음)
- 다중 세션 lifecycle 관리 (list, clean, kill --all)
- **양방향 메시지**(ask/msg, UC9) + **세션 증류**(distill, UC10) + **서버 사망 복원**(restore, UC11)
- 임의 프로젝트 폴더 지원 (워크트리 아닌 일반 디렉토리도 가능)
- `send` 명령으로 외부에서 메시지 주입
- baton 핸드오프(`/baton:save`·`/baton:resume`) 연계

## 부팅 대기 패턴

claude 기동 직후 즉시 send하면 입력이 흘러간다. 부팅 완료를 확인하고 send한다:
```bash
tmux send-keys -t {name} -l "{ccd-resolved} --name {name} --remote-control {name}"; tmux send-keys -t {name} Enter
# 부팅 폴링 (#0 RULE: ctx:0% 미확인 시 미준비 pane에 send 금지 — 명시적 실패 보고)
for try in 1 2 3 4 5; do
  sleep 3
  tmux capture-pane -t {name} -p | grep -q "ctx:0%" && { echo READY; break; }
  [ $try -eq 5 ] && { echo "❌ {name} 부팅 실패(ctx:0% 15초 미출현) — send 중단, 사용자 보고"; return 1; }
done
```

## CLI 명령 해석 (ccd alias chain)

사용자별로 `claude` 실행 옵션(모델/스킵 권한/베타 채널 등)이 `.zshrc`에 alias로 정의되는 경우가 많음. tmuxc는 그 alias를 존중한다.

**해석 절차**:
1. `zsh -ic 'type ccd 2>/dev/null'` 출력에서 `ccd` 정의를 파싱
2. `ccd is an alias for cc` 형태면 한 단계 더 풀기 — `zsh -ic 'type cc'`로 최종 실행 명령 회수
3. 최종 명령 끝에 `--name {session-name} --remote-control {session-name}` (또는 복원 시 `--resume {id}` 추가) — **`--name` 누락 금지**
4. tmux pane에 send-keys

**예시 (실측 alias, 2026-06)**:
```
$ zsh -ic 'type ccd; type cc'
ccd is an alias for cc
cc  is an alias for ~/.local/bin/claude --dangerously-skip-permissions --model "claude-opus-4-8[1M]"
```
→ 최종 send-keys 명령:
```
~/.local/bin/claude --dangerously-skip-permissions --model "claude-opus-4-8[1M]" --name {name} --remote-control {name}
```
- `ccd`는 dangerously-skip-permissions + opus-4.8-1M로 기동(권한 프롬프트 없이 자율 작업).

**Fallback 순서** (alias 해석 실패 시):
1. `ccd --name {name} --remote-control {name}` — tmux pane이 interactive zsh면 alias 자동 expand
2. `claude --name {name} --remote-control {name}` — 일반 fallback (PATH의 `claude` 사용)

**가드**:
- 해석된 명령이 빈 문자열이면 → 에러로 차단
- ccd 정의에 `;`, `&&`, `|` 등이 보이면 → 경고 후 사용자 컨펌

## UC12: 세션 멈춤 감지·능동보고·dumb-time 과징 (멍청한짓 방지)

오케스트레이터가 워커 세션을 백그라운드 watcher로 모니터할 때 **멈춤 방치 = 멍청한짓**(`~/.claude/rules/dumb-time-ledger.md` 과징). troubleshoot처럼 항상 참고할 표준.

### 12-1. 멈춤 watcher 표준 (false-positive 방지)
- **idle 판정 = CPU 우선**: `pgrep -P {pane_pid}` claude pid의 `%cpu < 0.3`을 **2회 연속**(30~45초 간격) 확인. CPU가 진위 판별 1순위.
- **라이브 명령 대기 ≠ 멈춤, 그러나 CPU가 최종심**: 화면에 `python …`/`Running…`/`Waiting for`/`600000`(timeout) 잔상이 있어도 **CPU<0.3 2회면 진짜 멈춤**으로 판정. 잔상 grep만으로 skip하면 멈춤 방치(2026-06-09 폴링/watcher 방치 ×2 히트 실증) — CPU 교차검증 필수.
- 폴링 간격 30~45초. 너무 길면 방치, 너무 짧으면 노이즈.

### 12-2. 능동 중간보고 의무
- 백그라운드 watcher만 걸고 알림 대기 = 방치(멍청한짓). watcher가 멈춤 감지 시 **즉시** 독려/보고.
- "시스템은 안 멈췄다" 변명 금지 — **HIL 관점 = CC 진행·보고 공백 = 멈춤**.

### 12-3. dumb-time 과징 연계
- HIL이 "멈췄네 / 얼마나 멈췄어 / 멈춘시간 / 시간확인"으로 지적 = **멍청한짓 1건** → `dumb-time-ledger.md` 즉시 기록(일시·유형·원시간·배수·누적). 같은 유형 재발 = 0번 이동 + ×2 히트.

### 12-4. 멈춤 패널티 로그 (작업별)
- 워커 멈춤 추적: 워크트리 `.baton/handoff/{TASK}_PENALTY.md`에 감지시각·지속·시나리오·자동독려 누적.
- 야간 자율 모드: 단순 멈춤은 watcher가 자동독려+패널티 기록(계속 watch), 판단 필요(확인요청·머지게이트·한도 도달·블로커)만 HIL을 깨운다. 한도(`5h:9X%`) 도달 시 baton save 유도.

## 제약사항

- macOS/Linux 전용 (tmux 필수 — 미설치 시 `brew install tmux` 안내)
- Claude Code CLI (`claude` 또는 사용자 정의 alias `ccd`) PATH에 있어야 함
- `--remote-control` / `--remote-control-session-name-prefix`는 Claude Code 최신 버전 필요 (세션명 지정·자동 생성 지원)
- ccd alias 해석을 위해 `~/.zshrc`가 interactive zsh에서 source 되어야 함 (대부분 기본값)
- 양방향 수신(UC9)은 claude 단방향 stdin 한계상 **pane 버퍼 capture** 기반 (네이티브 역방향 API 부재)

## 보안 원칙

- UC4 `send`: Claude 미실행 세션에 send-keys **절대 금지** (쉘 직접 실행 위험). `pgrep -P {pane_pid}`로 claude 자식 확인 후에만.
- 메시지 리터럴: `tmux send-keys -l` + Enter 분리 (쉘 확장 방지)
- alias 해석 시 사용자 의도와 다른 명령이 합성되지 않도록 `zsh -ic 'type'` 출력만 신뢰 (eval 금지)
- UC10 증류 시 구세션 kill 전 반드시 신규 세션의 컨텍스트 인계를 UC9-1로 확인 (조기 kill = 작업 유실)
- UC11 `--resume`은 직전 대화 복원이라 토큰 무거움 — 가벼운 복원은 `/baton:resume` 우선

## 레퍼런스 (on-demand — 막히면 Read)

자동 로드 안 됨. 해당 상황에서만 Read해 컨텍스트 절약.

| 문서 | 언제 참조 |
|------|-----------|
| `~/.claude/skills/tmuxc/COMM-GUIDE.md` | 세션간 메시지 포맷·검증 송신 §2 (모든 send 전 표준) |
| `references/baton-tmuxc-troubleshooting.md` | baton save/resume·증류·tmux 송신에서 **에러/막힘** — 실증 함정 8종 + 1줄 처방 (save 거부→init-handoff, set -e 트립, status exit 128, 라인핀 오차, 미제출, alias 미정의, 부팅 대기, 컨텍스트 축소 패턴) |
| `references/tmuxc-disaster-recovery.md` | **세션/서버 장애 복구** (UC8 cmux 디스커넥트 / UC11 tmux 서버 사망) — 진단 분기·재연결·`--resume` 복원·재발방지 |
