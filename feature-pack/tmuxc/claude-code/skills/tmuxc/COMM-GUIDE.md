# tmuxc 세션간 통신 가이드 (COMM-GUIDE)

> 이 파일은 tmuxc로 생성된 모든 Claude Code, Codex, OMX 세션에 주입되는 **통신 인터페이스 표준**이다.
> 세션 시작 시 받은 주입 메시지에 **너의 세션명(`{me}`)**과 **오케스트레이터 세션명(`{orch}`)**이 명시되어 있다. 모든 통신에서 그 이름을 사용한다.

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

## 5. 금지 사항 요약

1. ❌ send-keys 후 검증 없이 "전송 완료" 주장
2. ❌ `-l`과 Enter를 한 호출에 합침
3. ❌ claude 미실행 pane에 send-keys
4. ❌ prefix 없는 메시지
5. ❌ 타겟 상태 미확인 송신 (옵션 모드/미제출 입력 잔류 무시)
6. ❌ 작업 실행 중인 타겟에 Escape (작업 중단됨)
