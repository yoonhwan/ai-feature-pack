# tmuxc 세션간 통신 가이드 (COMM-GUIDE)

> 이 파일은 tmuxc로 생성된 모든 Claude Code, Codex, OMX 세션에 주입되는 **통신 인터페이스 표준**이다.
> 세션 시작 시 받은 주입 메시지에 **너의 세션명(`{me}`)**과 **오케스트레이터 세션명(`{orch}`)**이 명시되어 있다. 모든 통신에서 그 이름을 사용한다.

---

## Serena 활성화 체크 (Claude + codex 세션 부팅 시)

### ★활성화는 처음부터 절대경로로 (워크트리 필수)

**`activate_project`에는 프로젝트 **이름**을 넣지 말고 **현재 워크트리 절대경로**를 넣는다.** 이름으로 부르면 워크트리에서 실패한다 — 루트와 워크트리 여러 개가 같은 이름으로 등록돼 있어 어느 것인지 못 가른다.

```
❌ activate_project(project="BYZ-Agents")           # 워크트리에서 오류
✅ activate_project(project="/Users/.../.worktrees/v6-realtime-live")
```

경로는 **자신의 cwd**를 쓴다(`pwd`). 이름으로 먼저 시도했다가 실패하고 경로로 재시도하는 왕복이 **세션마다 반복되므로**, 처음부터 경로로 호출한다.

---

Claude/codex 계열 세션(architect/impl/DA/master/helm/checker/tester/**pm** 등) 모두 부팅 직후 Serena 활성화 확인 후 우선 사용한다. **pm도 기본 탑재다(2026-08-14 오빠 지시)** — codex pm은 `/mcp`로 handshake 확인. **Claude**: `mcp__serena__activate_project(project="<절대경로>")`를 바로 호출한다(사전승인·확인불필요) — `get_current_config`을 먼저 부르지 말 것(활성화 전 호출 시 응답이 비대해 신선한 세션 컨텍스트를 1회에 전소시키는 버그 실측됨). **codex**: `~/.codex/config.toml`에 `[mcp_servers.serena]`로 이미 등록돼 있으면(v1.28.1+ 확인됨) 세션 시작 시 자동 handshake — 기동 확인은 `/mcp`로. **동일 이름의 프로젝트가 여러 워크트리에 등록돼 있으면(예: 루트+워크트리 다수가 전부 같은 이름) 이름만으로는 fatal error가 난다** — `claude mcp get serena`로 등록 args 확인 후 `--project <이름>` 대신 `--project <절대경로>`로 로컬 등록 교체(`claude mcp remove serena -s local` → `add ... --project <절대경로>`). 활성화되면 grep 대신 `find_symbol`/`find_referencing_symbols`/`search_for_pattern` 등 심볼 기반 도구를 우선 사용한다(실측: Lua 스크립트 전수 검색 2회 호출로 완료, grep보다 빠르고 정확).

**★도구 미노출 시 (2026-07-29 실측)**: 부팅 안내에 deferred 목록으로 나열되고 SessionStart 훅이 `Success`를 찍어도 **실제 도구 목록에 안 나타나는 경우가 있다**. 훅 성공 표시와 도구 가시성은 별개다. 확인은 도구 검색으로 하고(`mcp__serena__` 접두 0건이면 미노출), `claude mcp list`가 `Connected`여도 세션 노출은 별개다. 미노출이면 **재시작하지 말고**(맥락 손실이 더 크다) Read/Grep으로 진행하되 **보고에 "Serena 미사용, grep 기반"을 반드시 명시**하고, 코드 수정 시 참조 영향은 grep 전수로 대체한 사실을 남긴다(나중에 재확인 대상). 계열 편차 실측: codex 세션은 정상 노출, Claude 세션은 미노출 사례 다수.

**★md·문서 검색에도 Serena를 쓴다 (2026-08-11 실측 추가)**: `find_symbol`은 LSP 심볼 기반이라 md에 안 걸리지만 **`search_for_pattern`·`find_file`은 md·txt·설정 등 모든 텍스트 파일에서 동작한다**(`restrict_search_to_code_files=false`가 기본). 설계문·핸드오프·판정문을 찾을 때 `grep -rn` 대신 이 둘을 쓴다 — 정규식 멀티라인·컨텍스트 라인·glob 필터가 한 번에 되고, 대량 매치 시 자동 요약이라 컨텍스트를 덜 먹는다. **실측(2026-08-11)**: 같은 세션에서 architect·DA·fable **셋 다 Serena가 로드돼 있는데 하루 종일 사용 0회**였고 전부 `grep`/`rg`/`Read`로 돌았다 — 도구가 있다는 것과 쓰는 것은 별개다. **★단 한 겹 더**: Serena로 본 것도 **"코드에 그렇게 적혀 있다"일 뿐 실행이 그렇다는 증거가 아니다** — 실행 여부는 여전히 로그로 확인한다. 같은 날 "함수가 있다→실행이 겹친다", "게이트가 없다→계속 낸다" 류의 오판이 **4건** 났고 도구를 바꿔도 그 층은 안 바뀐다.

**★부팅 첫 보고 필수 3항(+1)**: 세션명 / **모델 + 창 크기**(`[1m]` 여부 — 승계 세션은 창을 자동 상속하지 않아 명시 없이 스폰하면 조용히 200k로 열리고 auto-compact 전까지 안 드러난다) / **Serena 가부**. master·architect·DA는 여기에 **i-have-adhd 로드 여부**를 더한다(기본 탑재 — 하단 스킬 절 참조). 이걸 첫 보고에 적지 않으면 상위가 실측을 다시 해야 한다.

---

## Command Code(`--agent cmd`) 세션 특이사항 (2026-08-17 신설)

tmuxc `--agent cmd`(commandcode.ai, 바이너리 `cmd`)로 뜬 세션은 Claude/codex 계열과 부팅 확인 항목이 다르다.

**부팅 첫 보고 3항** — Claude 계열 3항을 이 계열에 맞게 치환한다:
1. **세션명**
2. **모델** — 스폰 커맨드의 `--model`. 미지정이면 Command Code 기본값 `deepseek/deepseek-v4-flash`. 컨텍스트는 전 모델 최대 1M이라 `[1m]` 같은 창 선택자 개념이 없다.
3. **크레딧 가부** — `cmd status`. ★Claude 계열의 "Serena 가부" 자리를 이게 대신한다.

★**크레딧 소진은 "세션 멈춤"으로 위장한다 (2026-08-17 실측)**: 잔액이 0이면 무료 모델(`poolside/laguna-s-2.1-free`)조차 거부하고 **`exit 10`으로 즉사**한다. 오케가 `capture-pane`으로 폴링하면 **빈 pane·무응답**으로만 보여 hang·권한·경로 문제로 오진하기 쉽다. **cmd 세션이 응답 없으면 §2 재시도·Escape 보정 전에 `cmd status`부터 친다.** 충전: https://commandcode.ai/billing (최소 Go $1/mo).

**통신 프로토콜은 그대로 적용된다**: mbox(§1)·검증 송신(§2)·수신(§3)·보고(§4)는 전부 tmux 레이어라 에이전트 종류와 무관하다. 본문 prefix `[{me}->{to}]` 규약도 동일하다.

**스킬 — 별도 주입 불필요 (2026-08-17 실측)**: `cmd`는 **`~/.agents/skills`를 글로벌 스코프로 자동 발견**한다. `cmd skills list`로 `i-have-adhd`·`find-skills`·`k-skill-setup`·`orchestration`·`srt-booking` 5종이 잡히는 것을 확인했다 — 즉 **`--skill <path>` 주입 없이 `/i-have-adhd`가 그대로 뜬다.** 번들 스킬 6종(`command-code-knowledge`·`design`·`skill-builder`·`mod-builder`·`agent-browser`·`config`)도 함께 로드된다.

**Serena — 계열별로 따로 등록해야 한다 (2026-08-17 실측)**: `cmd`는 MCP를 완전 지원하지만(`add`/`list`/`get`/`remove`/`add-json`/`auth`, stdio·http 트랜스포트) **claude의 MCP 등록을 공유하지 않는다.** 신규 설치 직후 `cmd mcp list`는 `No MCP servers configured`다. cmd 세션에서 Serena를 쓰려면 **그 프로젝트에서 한 번 등록**한다:
```bash
cmd mcp add --transport stdio serena -- <claude 쪽과 동일한 command+args, --project 는 절대경로>
cmd mcp list          # 등록 확인
```
등록 전이라면 부팅 첫 보고의 3번 항목에 **"Serena 미등록 — grep 기반"**을 명시한다(Claude 계열의 「도구 미노출 시」 규율과 동일 취급).

**`/import claude` — 1회만 하면 된다 (2026-08-17 실측)**: `~/.claude` 자산이 `~/.commandcode/`(유저 레벨)로 **복사**된다. 실측 결과 **총 162건 임포트·실패 0**: skills 76/77(`pdf-reader`만 스킵 — SKILL.md frontmatter에 name+description 누락), agents 12/12(`ft-*` 로스터 전부), slash commands 72/72, MCP 1/1, memory 1/1. **원본은 변경되지 않는다**(`Your original setup was not changed`). 리포트: `{프로젝트}/.commandcode/import-report.md`.

**`/learn-taste` — taste 부트스트랩 (2026-08-17 실측)**: 기존 코딩 에이전트 세션에서 취향을 증류한다. 실측 56세션(Claude Code 7 + Codex 48 + Cursor 1) → 3패키지 9learnings(`coding-style`/`workflow`/`communication`). 산출물은 **프로젝트 스코프**(`{프로젝트}/.commandcode/taste/`)라, 전 프로젝트에 쓰려면 **`cmd taste push <pkg> -g`로 글로벌 승격**해야 한다. ★**`cmd taste push`의 기본값은 `--remote`(commandcode.ai 업로드)다** — 내부 작업 패턴이 외부로 나가므로 **반드시 `-g/--global`을 명시**한다. 세션 상시 학습 스위치는 `cmd taste enable -u`.

★**cmd 세션은 턴 실행 중 입력을 삼킨다 (2026-08-17 실측)**: 작업 중인 cmd 세션에 `send-keys`로 슬래시 커맨드를 보내면 **제출도 큐잉도 안 되고 흔적 없이 사라진다**(`capture-pane -S -400` 전수 검색으로 미검출 확인). §0의 유실 케이스에 이 항을 추가한다 — **cmd 세션에 보낼 때는 `Escape`로 현재 턴을 끊고 `C-u`로 입력줄을 비운 뒤 §2 3스텝으로 보낸다.** `/import`·`/learn-taste` 같은 TTY 필요 커맨드는 비대화(`-p`)로 못 친다(Ink raw mode 에러).

---

## 출력 스타일 스킬 (i-have-adhd) — master·architect 기본 탑재 (2026-08-14 오빠 지시로 승격)

**master(오케스트레이터/helm)·architect·pm 세션은 `i-have-adhd`가 기본 탑재다**(pm 편입 2026-08-14 오빠 지시) — 부팅 절차의 일부로 반드시 로드하고, **로드 여부를 부팅 첫 보고에 포함한다**(아래 첫 보고 항목 참조). DA 세션도 로드한다. 행동 우선·번호 스텝·매 턴 상태 재고지 출력 스타일.

- 로드 방법 — Claude 세션: `/i-have-adhd` 호출(또는 Skill 도구). codex 세션: `$i-have-adhd`. 정본은 `~/.agents/skills/i-have-adhd`이며 claude/codex/opencode/hermes 스킬 디렉토리에 링크로 공유돼 있다.
- **제외(로드 금지)**: implementer·tester 등 작업자 워커, checker·analyst(로그·문서·코드 수집), pm — 이 역할들의 보고 포맷 계약(BRIEF·전 호출 나열·4축 실측 나열)이 스킬의 목록 5개 제한 등과 충돌하므로 로드하지 않는다.
- 우선순위: 로드 후에도 COMM-GUIDE의 보고 의무(§3·부팅 첫 보고 3항)와 역할 템플릿 계약이 스킬 규칙보다 우선한다.

---

## 1. 기본 통신: 파일 기반 메시지 큐 (mbox) — PRIMARY

세션간 메시지는 **파일 큐(mailbox)**를 기본 채널로 쓴다. tmux send-keys(§3)는 pane scrollback 유실·캡처 타이밍 오탐·멀티바이트 손상이 잦아 **폴백**으로만 쓴다.

**헬퍼**: **주입 메시지의 `{mbox}` 경로를 그대로 쓴다** — 설치에 따라 `.fable-team/bin/ft-mbox.sh`(fable-team 팩) 또는 `.fable-team/comm/mbox.sh`(v6)이며 경로는 스폰 시 주입되니 하드코딩하지 않는다. 없으면 오케에게 요청.

```bash
# 송신 (읽힐 때까지 큐에 보존)
{mbox} send {to} {me} "메시지 본문"          # → QUEUED seq=N to={to} pending=K

# 수신 (내 앞으로 온 것만 LIFO로 출력 + 큐에서 즉시 제거)
{mbox} recv {me}                             # → READ [from->me] #seq — 본문  (최신 먼저, 빈 큐는 READ none)

# 미리보기 (제거 없이 개수 확인)
{mbox} peek {me}                             # → pending=K latest_seq=N from=...
```

**규약**:
- **push 알림(핵심)**: `send`는 파일 append **후 수신자 tmux pane에 `recv` 트리거를 자동 주입**한다(pane_id 정확 매칭으로 `#`-suffix 세션 함정 회피). 즉 본문은 파일(유실·손상 0), 알림은 push(즉시 도착) — 수신자는 폴링 없이도 트리거로 바로 recv해 본문을 읽는다. **파일에만 쓰고 알림을 안 보내면 순수 pull이 되어 수신자가 영영 못 본다 — send는 반드시 notify까지 한 동작이다.** 트리거 없이 조용히 넣어야 할 때만 `--no-notify`.
- **LIFO**: `recv`는 최신 메시지부터 출력(급한 최신 지시 우선).
- **to==me grep**: 세션은 **자기 앞으로 온 메시지만**(`to`==본인 세션명) 읽는다. 남의 메시지는 건드리지 않는다.
- **consume-on-read**: `recv` 한 번이면 내 메시지는 큐에서 사라진다(중복 처리 방지). 보관이 필요하면 읽은 내용을 스스로 기록.
- **per-to 10 ring**: 한 수신자에게 안 읽힌 메시지가 10개를 넘으면 **가장 오래된 것이 자동 폐기**된다. push 알림이 기본이라 보통 즉시 소비되지만, 작업 중 트리거가 큐잉될 수 있으니 수신자는 작업 경계마다 `recv`로 잔여 확인.
- **동시쓰기 안전**: 내부 `fcntl.flock`으로 직렬화되므로 여러 세션이 동시에 send해도 안전. 호출자는 lock 신경 쓸 필요 없다.
- **본문 규약**: 방향은 `send`의 `{to} {me}` 인자가 담으므로 본문에 `[from->to]` prefix 중복 불필요. 다부작/대용량은 §4a대로 원문을 파일에 두고 큐엔 경로+요약만.
- **오케도 예외 아님**: 오케스트레이터도 워커가 `send`로 보내면 자기 pane에 recv 트리거가 주입된다 — 받은 즉시 recv해 회수한다. 작업 대기 중이라도 제 우편함을 방치하지 않는다.
- **읽음 표시 (필수)**: recv 출력의 `READ [from->me] #seq — 요약` 라인을 **자기 화면(보이는 응답)에 그대로 출력**해 누가→누구에게 보낸 무슨 내용인지와 "읽음(READ)"을 명시한 뒤 작업을 이어간다. 파일 큐는 send-keys와 달리 수신이 화면에 안 남으므로, 이 출력이 오케·사람의 polling 추적 근거다. 빈 큐는 `READ none`.

---

## 0. 보조 원칙: "보냈다 ≠ 도착했다" (tmux 폴백 사용 시)

`tmux send-keys`는 **항상 exit 0**을 반환한다. 전송 성공처럼 보여도 다음 이유로 유실된다:

| 유실 원인 | 증상 |
|-----------|------|
| `-l "msg" Enter`를 한 호출에 합침 | Enter가 리터럴 텍스트 "Enter"로 입력되거나 제출 누락 |
| Enter 별도 호출 누락 | 타겟 입력창에 텍스트만 쌓이고 미제출 (`❯ 텍스트` 상태) |
| 타겟이 AskUserQuestion 옵션 모드 | 텍스트 입력이 통째로 무시됨 |
| 타겟 agent 부팅 미완료 | 입력이 쉘로 흘러가거나 증발 |
| 타겟 세션에 agent 미실행 | 쉘에 명령으로 직접 실행될 위험 (보안 사고) |

**따라서 송신 후 반드시 §2의 검증 단계를 수행하고, 검증 통과 전에는 절대 "전송 완료"라고 보고하지 않는다.**

---

## 1. 메시지 포맷 (필수)

모든 세션간 메시지는 방향 prefix를 붙인다:

```
[{from}->{to}] 메시지 내용
```

> 구분자는 **순수 ASCII `->`**. 유니코드 화살표(→)는 tmux pane/Claude TUI 렌더링에서 U+FFFD로 손상돼
> capture 기반 도달검증이 영구 실패할 수 있다(실측). 프로토콜 prefix는 ASCII만 쓴다. (레거시 `→` 수신은 계속 인식.)

- 워커 → 오케스트레이터: `[{me}->{orch}] 빌드 완료, 테스트 통과`
- 오케스트레이터 → 워커: `[{orch}->{me}] 다음 작업: ...`
- 워커 ↔ 워커: `[{me}->{other}] API 스키마 확정됨, 경로: docs/api.md`

prefix가 없는 메시지는 발신자 추적이 불가능하므로 금지.

---

## 2. 검증 송신 프로토콜 (verified send) — tmux 폴백 전용

> mbox(§1)가 기본이다. mbox 헬퍼가 없거나, 상대가 즉시 화면 반응해야 하는 인터랙티브 상황(옵션 모드 해제 등)에서만 tmux send-keys를 쓴다. 이때는 아래 4단계를 **순서대로** 수행한다:

### Step 1: 타겟 세션 + agent 실행 확인 (HARD GATE)
```bash
tmux has-session -t {target} 2>/dev/null || { echo "❌ 타겟 세션 없음"; }
PANE=$(tmux list-panes -t {target} -F '#{pane_pid}' | head -1)
pgrep -P "$PANE" >/dev/null || { echo "❌ 타겟에 agent 미실행 — send 금지"; }
```
Claude/Codex/OMX가 안 떠 있으면 **절대 send-keys 하지 않는다** (쉘 직접 실행 위험).

### Step 2: 타겟 상태 판독
```bash
tmux capture-pane -t {target} -p | grep -vE '^\s*$' | tail -8
```
- `Enter to select · ↑/↓ to navigate` 보임 = **옵션 모드** → `tmux send-keys -t {target} Escape; sleep 2` 후 진행
  (단, 타겟이 작업 실행 중이면 Escape가 작업을 중단시킴 — `❯` 프롬프트/statusline으로 옵션 대기인지 먼저 확인)
- `❯ 기존텍스트` (미제출 입력 잔류) = 먼저 `tmux send-keys -t {target} C-u`로 입력줄 클리어

### Step 3: 송신 — `-l`과 Enter는 반드시 별도 호출
```bash
tmux send-keys -t {target} -l "[{me}->{to}] 메시지 내용"
sleep 0.3
tmux send-keys -t {target} Enter
```
- `-l` (리터럴) 필수: 특수문자 쉘 확장 방지
- **한 호출에 합치지 말 것**: `send-keys -l "msg" Enter` 형태 금지

### Step 4: 도달 검증 (없으면 재시도, 최대 3회)
```bash
sleep 2
# capture엔 TUI 박스문자·잘린 멀티바이트 등 invalid UTF-8이 섞여 UTF-8 로케일 grep이
# binary 판정/illegal byte로 오판하므로 LC_ALL=C grep -a(바이트매치)로 확인한다.
tmux capture-pane -t {target} -p | LC_ALL=C grep -aqF "[{me}->" \
  && echo "✅ 도달 확인" \
  || echo "⚠️ 미도달 — Step 2부터 재시도"
```
- 3회 실패 시: 자기 화면에 `⚠️ [{me}->{to}] 전송 3회 실패` 를 출력해 오케스트레이터가 ask로 발견할 수 있게 한다.
- **검증 통과 전 "전송했다"고 보고 금지.**

---

## 3. 수신

- 다른 세션이 보낸 `[X->{me}] ...` 메시지는 일반 사용자 입력처럼 도착한다. prefix로 발신자를 식별하고 응답이 필요하면 §2 절차로 회신한다.
- 오케스트레이터는 너의 화면을 `capture-pane`으로 읽는다(polling). **중요한 보고는 반드시 화면에 텍스트로 출력**하라 — 도구 호출 결과 안에만 묻혀 있으면 오케스트레이터가 못 본다.

---

## 4. 오케스트레이터에게 보고하기

작업 완료/블로커/질문 발생 시:

```bash
# 1) 자기 화면에 요약 출력 (polling 대비)
# 2) 능동 보고 (push) — §2 검증 송신으로:
tmux send-keys -t {orch} -l "[{me}->{orch}] 작업 완료: <한 줄 요약>"
sleep 0.3
tmux send-keys -t {orch} Enter
# 3) Step 4 검증까지 수행
```

보고 타이밍: 작업 단위 완료 직후 / 블로커 발생 즉시 / 오케스트레이터 질의 수신 시.

---

## 4a. 대용량/다부작 메시지 — 파일 우선

멀티파트로 나눠 보내는 설계·판정(예: `1/3`, `AUTH-1/5`)이거나 단일 메시지가 길어 tmux pane에서 잘릴 위험이 있으면:

1. **원문을 먼저 공유 파일에 write**(권위문서/설계plan/평문 스크래치 파일 — 프로젝트 컨벤션에 맞는 위치).
2. tmux 메시지는 **파일 경로 + 핵심 요약 한둘**만 보낸다. "원문은 `{path}` 참조"를 명시.
3. 수신 측은 파일을 Read해서 원문을 확정하고, tmux 텍스트만으로 판단하지 않는다.
4. 발신자가 tmux로 계속 여러 파트를 보내는 관행 자체는 막지 않되(원저작), **중계·집계 책임(오케 등)은 파일화해 authoritative 버전을 고정**한다 — pane별 scrollback 유실/캡처 타이밍 오탐을 근본 차단.

## 4b. 설계·판정 방식 — 하네스 대신 DA approve loop (2026-07-29 확정)

**architect / DA 세션은 부팅 시 이 절을 반드시 읽는다.**

**원칙**: 내부 하네스(omo 등)로 설계 루프를 돌리지 않는다. 하네스는 **루프가 설계 문서를 다시 만들면서 깊어지고, 산출은 늘지만 검증은 안 된다**. 대신 **DA approve loop**를 쓴다 — 적대검증이 붙은 왕복이라야 설계가 단단해진다. (실증: Todo7 계획이 DA R1→R4 왕복에서 hard gate 조건을 얻음. 하네스로는 안 나온다.)

| 역할 | 하는 일 |
|---|---|
| **architect** | codex native로 직접 설계. **DA 소환 여부를 정한다** |
| **DA** | 적대검증. **승인기가 아니라 반박 게이트** |
| **checker** | DA 승인 **뒤에** 정상 여부 read-only 확인 ← 승인이 끝이 아니다 |

**architect 준수 4항**
1. 설계는 codex native로. 하네스 금지. 진짜 필요하면 **상위(HELM)에 목적 한 줄로 올려 승인받고** 쓴다
2. **DA 소환 기준을 낮춘다** — 새 계약이 아니어도 판단이 갈릴 여지가 있으면 부른다
3. **DA 반박에 반박한다** — 조건을 그대로 수용만 하지 말 것. 그 왕복이 설계를 만든다
4. **왕복 결과를 문서로 남긴다** — mbox 회신만으로는 밖에서 DA loop가 도는지 안 보인다

**DA 준수 3항**
1. 단순 승인 금지. **과적합 상수·silent fallback·관측성 소실·선언과 강제의 분리**를 반박한다
2. 판정문에 **"checker 확인 대상" 포인터**를 한 줄 싣는다 — 없으면 checker 단계가 실제로 작동하지 않는다
3. **소환되지 않은 구간도 무엇을 심사했고 무엇은 소환 없어 안 했는지** 짧게 남긴다 — 안 불린 것과 불렸는데 안 남긴 것이 밖에서 구분되어야 한다

**★architect Tester-first 반사 (2026-08-05 오빠 지시)**: architect의 기본 반사는 **"어떻게든 tester press를 한 번이라도 더 빨리 돌리는 것"**이다. 설계·판정·문서화가 press를 기다리게 하고, press가 설계를 기다리게 하지 않는다. 실제 BTS는 checker 4축 보고로만 들어온다 — 코드리딩 결론은 press 1회의 관측보다 항상 약하다. 분석이 2턴을 넘기면 그 사이 돌릴 press부터 찾고, preflight를 다듬느라 press를 밀지 않으며(최소 조건 즉시 GO), 상위 회신 대기 중에도 tester가 놀지 않게 독립 관측 press를 미리 설계해 둔다. (실증 2026-08-04: 원인 4개 전부 press가 찾았고 분석이 찾은 것은 0개.)

**산출물 경로**: 확정 설계·판정문·인계 문서는 **처음부터 tracked 경로**(`design/` 등)에 쓴다. `.omo/`는 gitignore 대상이라 워크트리 정리 시 유실된다. **tracked 경로 확인은 작성자 1차 책임**이고 Master/PM은 발견 시 이관하는 2차 안전망일 뿐 — 사후발견 의존구조는 항상 늦다. (실증: 같은 클래스 2회 발생, 그중 하나는 크리티컬 패스 정본)

---

## 4c. 테스트 실행 전 버전 정합 체크 (tester·checker 필수, 2026-07-30 오빠 지시)

> **오빠 원문**: "서버, 프론트, 레디스 버전 정합 재시작도 매번 얘기하는데 챙겨야 한다" / "워커, 프론트, 게이트웨이, 레디스 모두 버전 최신화 특히 신경쓰라 했고"

**매 테스트 실행 전에 4종의 버전 정합을 직접 실측하고 evidence에 남긴다.** 이건 게이트가 아니라 **실행 절차의 일부**다 — 안 하면 무엇을 테스트했는지 알 수 없다.

### 확인 4종 (전건 실측, 추정 금지)

| 대상 | 확인 | 실패 시 |
|---|---|---|
| **worker** | 기동 시각 > 최신 커밋 시각 | 재기동 후 재확인 |
| **gateway** | 동상 | 동상 |
| **frontend** | 동상 (+ 탭 reload, 콘솔 500/ReferenceError 스캔) | 동상 |
| **redis** | 컨테이너/버전 + 대상 키 잔여 데이터 | keep/flush 결정을 **명시 기록** |

```bash
# 기동 시각
lsof -ti:8080 | head -1 | xargs -I{} ps -o lstart=,command= -p {}
lsof -ti:8081 | head -1 | xargs -I{} ps -o lstart=,command= -p {}
lsof -ti:3001 | head -1 | xargs -I{} ps -o lstart=,command= -p {}
# 최신 커밋
git log -1 --format='%ci %h'
# 기동 이후 제품 코드 변경 여부 (이게 진짜 판정)
git log --since='<기동시각>' --format='' --name-only -- shared/ worker/ gateway/ clients/ | sort -u
# redis
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
```

### ★hot reload를 신뢰하지 않는다

- **기동 시각만 보고 "reload 됐겠지"로 넘어가지 않는다.** 실제로 reload가 걸렸는지 **로그로 확인**한다.
- **reload가 없는 구성이 존재한다** — 예: worker가 `c2c_act_entrypoint --c2c-act-dev`로 뜨면 `server.sh`가 명시하듯 **hot reload가 없다**. 이 구성에서 코드 변경이 있으면 **무조건 재기동**이다.
- 프로세스 command line을 직접 읽어 어떤 구성으로 떠 있는지 확인한다.

### 기록 의무

evidence README에 **4종 각각의 기동 시각 / 최신 커밋 / 기동 이후 제품 코드 변경 유무 / redis keep·flush 결정**을 남긴다. 없으면 그 회차는 **나중에 같은 의심을 다시 받는다**.

> **2026-07-30 실증**: 서버 3종이 13:05 기동, 14:50에 worker 제품 코드 6파일 변경, 그러나 worker가 reload 없는 entrypoint라 **재기동 없이 5시간 반을 구버전으로 테스트**했다. 그 사이 관측 도구·제품 경로·race 가설을 차례로 의심했고 **정작 서빙 코드가 구버전이라는 것을 아무도 안 봤다.**

---

## 5. 금지 사항 요약

1. ❌ send-keys 후 검증 없이 "전송 완료" 주장
2. ❌ `-l`과 Enter를 한 호출에 합침
3. ❌ claude 미실행 pane에 send-keys
4. ❌ prefix 없는 메시지
5. ❌ 타겟 상태 미확인 송신 (옵션 모드/미제출 입력 잔류 무시)
6. ❌ 작업 실행 중인 타겟에 Escape (작업 중단됨)
