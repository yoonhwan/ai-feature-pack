# pi 업스트림 요청 문안 — streaming 중 `!` 결과(pending bash)를 agent_settled 에서 대화로 옮겨 달라

- 작성: byz-harness-nano-r1540-pi-bash-pending-block-and-reload-r#0 · 2026-11-10 · 카드 `r1540-pi-bash-pending-block-and-reload-race`
- 상태: **문안만** — 외부 게시 0(게시는 오빠 승인 뒤 · 2.0 PLAN :300 «업스트림 요청과 로컬 대응을 구분»)
- 대상 버전: pi 1.5.0 · `~/.pi/agent/install/releases/1.5.0/node_modules/@earendil-works/pi-coding-agent`

## 1. 증상(오빠 보고 원문 요지)

desk pi 창에서 `! bash /tmp/hN` 을 연달아 치면 **결과 블록이 입력창 위 대기 영역에 쌓인다**. 대화로 옮겨지지 않으므로 화면이 결과 블록으로 가려진다(desk #277647 · h7987~h7992 실측). 같은 창에서 `/reload` 를 치면 `Wait for the current response to finish before reloading.` 경고가 뜨고 reload 가 거절된다.

## 2. 재현(코드 경로)

1. 확장이 `agent_settled`(또는 `user_bash` 반환 직후)에서 `pi.sendMessage(..., { triggerTurn: true, deliverAs: "followUp" })` 로 턴을 1회 요청한다.
2. 그 턴이 도는 동안(= `session.isStreaming`) 오빠가 `! bash /tmp/hN` 을 친다.
3. `dist/modes/interactive/interactive-mode.js:5982` — 로컬 실행 경로가 streaming 이면
   `this.pendingMessagesContainer.addChild(this.bashComponent)` + `this.pendingBashComponents.push(...)` 로 **대기 영역**에 넣는다. 확장이 결과를 반환하는 경로도 같은 판정이다(`:5960`).
4. 대화로 옮기는 함수는 `flushPendingBashComponents()`(`:4068` · `interactive-mode.d.ts:416` private) 하나뿐이고, 호출처는 **일반 메시지 제출** 한 곳(`:2781`)이다.
   - 즉 `agent_end` · `agent_settled` · `sendMessage` 로 만든 턴에서는 **옮기지 않는다**.
5. 확장 API 에는 대기 영역·flush 를 다루는 표면이 없다(`docs/extensions.md:1076` `user_bash` = 실행 가로채기 · `:2405` `createLocalBashOperations` = 로컬 실행 재사용). 세션 기록은 정상이라(`agent-session.js` 경로) 재개하면 다시 보인다.

## 3. 요청

**`agent_settled` 시점에 `pendingBashComponents` 를 대화 컨테이너로 옮겨 달라.** 즉 `flushPendingBashComponents()` 호출을 `:2781`(일반 메시지 제출) 외에 «agent_settled(최종 유휴 확정)» 에서도 1회 하도록 확장 표면을 열어 달라. 선택지 두 가지 중 어느 쪽이든 좋다.

- (a) `agent_settled` 뒤 pi 본체가 스스로 flush 1회 — 확장 변경 0.
- (b) `ExtensionAPI` 에 `ctx.flushPendingBash()`(또는 동등)를 공개 — 확장이 «턴을 만들기 직전» 에 부를 수 있다.

## 4. 부수 요청 — reload 거절 시 요청 보존

`handleReloadCommand()`(`:5437`)는 `session.isStreaming` 이면 경고만 하고 return 한다. 확장이 `agent_settled` 에서 reload 를 요청하는 패턴(`docs/extensions.md:1536` 이 권하는 방식)이므로, **거절을 확장이 알 수 있는 신호**(반환값·이벤트)로 달라. 지금은 확장이 «거절됐다» 를 알 수 없어 스스로 `ctx.isIdle()` 재확인 + 요청 복원으로 방어한다(`ft-reload-request.ts` · r1540).

## 5. 우리 로컬 대응(업스트림과 구분 · 이미 구현)

| 축 | 로컬 대응(r1540) |
|---|---|
| 대기 영역 쌓임 | `ft-mbox-wake.ts` — h 끝을 모아 마지막 h 뒤 조용함 창(`FT_H_DONE_QUIET_MS` 20000)이 지나고 좌석이 쉬면 턴 1회, 일하는 중이면 다음 정상 settled 1회 → 우리 턴이 streaming 과 겹치는 빈도를 줄인다 |
| reload 경고·요청 소실 | `ft-reload-request.ts` — `ctx.reload()` 직전 `ctx.isIdle()` 재확인 · 거절이면 요청 파일 복원 + 1줄 + 다음 settled |
| 남는 한계 | 쪽지 깨움 턴이 도는 중에 친 `!` 은 여전히 대기 영역으로 간다(업스트림 수정 전까지 오빠 일반 메시지 1회로 비운다) |

## 6. 근거 줄 요약

| 파일:줄 | 내용 |
|---|---|
| `dist/modes/interactive/interactive-mode.js:5960` | 확장 결과 경로 — streaming 이면 pending 영역 |
| `dist/modes/interactive/interactive-mode.js:5982` | 로컬 실행 경로 — streaming 이면 pending 영역 |
| `dist/modes/interactive/interactive-mode.js:4068` | `flushPendingBashComponents()` 정의(대기 → 대화) |
| `dist/modes/interactive/interactive-mode.js:2781` | 유일한 호출처 = 일반 메시지 제출 |
| `dist/modes/interactive/interactive-mode.d.ts:416` | private — 확장에서 접근 불가 |
| `dist/modes/interactive/interactive-mode.js:5437-5439` | streaming 이면 reload 경고 후 return |
| `docs/extensions.md:1536` | «Pi cannot reload while the agent is running» |
| `docs/extensions.md:1076` / `:2405` | `user_bash` 표면 = 실행 가로채기 · 로컬 backend 재사용 |
