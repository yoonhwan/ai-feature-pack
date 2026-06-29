# tmuxc 세션간 통신 가이드 (COMM-GUIDE)

> 이 파일은 tmuxc로 생성된 모든 Claude Code, Codex, OMX 세션에 주입되는 **통신 인터페이스 표준**이다.
> 세션 시작 시 받은 주입 메시지에 **너의 세션명(`{me}`)**과 **오케스트레이터 세션명(`{orch}`)**이 명시되어 있다. 모든 통신에서 그 이름을 사용한다.

---

## 0. 핵심 원칙: "보냈다 ≠ 도착했다"

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
[{from}→{to}] 메시지 내용
```

- 워커 → 오케스트레이터: `[{me}→{orch}] 빌드 완료, 테스트 통과`
- 오케스트레이터 → 워커: `[{orch}→{me}] 다음 작업: ...`
- 워커 ↔ 워커: `[{me}→{other}] API 스키마 확정됨, 경로: docs/api.md`

prefix가 없는 메시지는 발신자 추적이 불가능하므로 금지.

---

## 2. 검증 송신 프로토콜 (verified send) — 필수 절차

다른 세션에 메시지를 보낼 때 아래 4단계를 **순서대로** 수행한다:

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
tmux send-keys -t {target} -l "[{me}→{to}] 메시지 내용"
sleep 0.3
tmux send-keys -t {target} Enter
```
- `-l` (리터럴) 필수: 특수문자 쉘 확장 방지
- **한 호출에 합치지 말 것**: `send-keys -l "msg" Enter` 형태 금지

### Step 4: 도달 검증 (없으면 재시도, 최대 3회)
```bash
sleep 2
tmux capture-pane -t {target} -p | grep -qF "[{me}→" \
  && echo "✅ 도달 확인" \
  || echo "⚠️ 미도달 — Step 2부터 재시도"
```
- 3회 실패 시: 자기 화면에 `⚠️ [{me}→{to}] 전송 3회 실패` 를 출력해 오케스트레이터가 ask로 발견할 수 있게 한다.
- **검증 통과 전 "전송했다"고 보고 금지.**

---

## 3. 수신

- 다른 세션이 보낸 `[X→{me}] ...` 메시지는 일반 사용자 입력처럼 도착한다. prefix로 발신자를 식별하고 응답이 필요하면 §2 절차로 회신한다.
- 오케스트레이터는 너의 화면을 `capture-pane`으로 읽는다(polling). **중요한 보고는 반드시 화면에 텍스트로 출력**하라 — 도구 호출 결과 안에만 묻혀 있으면 오케스트레이터가 못 본다.

---

## 4. 오케스트레이터에게 보고하기

작업 완료/블로커/질문 발생 시:

```bash
# 1) 자기 화면에 요약 출력 (polling 대비)
# 2) 능동 보고 (push) — §2 검증 송신으로:
tmux send-keys -t {orch} -l "[{me}→{orch}] 작업 완료: <한 줄 요약>"
sleep 0.3
tmux send-keys -t {orch} Enter
# 3) Step 4 검증까지 수행
```

보고 타이밍: 작업 단위 완료 직후 / 블로커 발생 즉시 / 오케스트레이터 질의 수신 시.

---

## 5. 금지 사항 요약

1. ❌ send-keys 후 검증 없이 "전송 완료" 주장
2. ❌ `-l`과 Enter를 한 호출에 합침
3. ❌ claude 미실행 pane에 send-keys
4. ❌ prefix 없는 메시지
5. ❌ 타겟 상태 미확인 송신 (옵션 모드/미제출 입력 잔류 무시)
6. ❌ 작업 실행 중인 타겟에 Escape (작업 중단됨)
