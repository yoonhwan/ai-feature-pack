# R241 상시 로드 줄 초안 — desk 정지 0 (설계 §5) — master 가 홈에 설치

> 원문(오빠 10-15): «데스크에 인터뷰가 떠 있으면 슬랙도 다 멈추고 나는 원격으로 들어가 인터뷰해야 함» · «데스크 안 멈추게»
> 강제 장치(이 줄만으로는 규칙이 아니다 · R106): 홈 훅 `desk-self-interview-gate.sh`(AskUserQuestion) · `desk-bash-fg-gate.sh`(Bash) · 수신 데몬 `--ack` · 유휴 깨우기 `ft-idle-wake.sh`.

## 1. main-team-governance.md §11-1 desk 행 (+ 키트 사본 `design/teams/harness/staged-r205/main-team-governance.md`)

```
| desk | `byz-planner-desk-claude#N` | Opus 5.5 [1m] high | 오빠 창 기본 대화 · #byz-talk 사람 글 응대(`byz_thread_post.py reply`) · 요청 정리해 master 에 1통 | ★화면 인터뷰 0★(오빠가 desk 화면에 붙은 뒤 10분 안에 직접 키를 친 때만 예외 · 강제 `desk-self-interview-gate.sh`) — 질문은 #byz-desk 스레드 묶음 글 · ★전경 명령 30초 이하★(`timeout: 30000` 또는 `run_in_background` · 강제 `desk-bash-fg-gate.sh` · 쪽지 `mbox.sh`·`byz_thread_post.py` 도 timeout 을 준다) · 코드·커밋 0 · 팀에 직접 발주 0(master 경유) · 비밀·내부어 게시 0 |
```

## 2. planner 설계 `DESIGN-planner-human-facing-roles-20261015.md` 개정 문안 (planner 몫 · 문안만)

- §2 51행 «한다 ③»: «오빠가 pane 에 있으면 AskUserQuestion» → «슬랙 질문 묶음 글(R235) · 화면 인터뷰는 오빠가 desk 화면에서 직접 친 지 10분 안일 때만»
- §2 72행 «인터뷰 중 슬랙 대기» 단락 → «화면 인터뷰는 훅이 막는다(R241) — 슬랙 대기 비용 0»

## 3. 설치 순서 (master · 병합 뒤 · 설계 §8)

1. 홈 훅 2개: `scripts/harness-install/hooks/desk-self-interview-gate.sh`·`desk-bash-fg-gate.sh` → `~/.claude/hooks/` cp+cmp0 → `~/.claude/settings.json` PreToolUse 등록(AskUserQuestion 1 · Bash 1) → desk 좌석에서 첫 AskUserQuestion deny 1줄 · 전경 명령(timeout 없음) deny 1줄 확인.
2. 수신 데몬(talk 인스턴스만): `install-inbound.sh --label com.hermes.byz-slack-talk-inbound --channel <ID> --to-key _desk --humans-from-seats --ack` → `mirror_ack.py`·`mirror_ack_alarm.py` 포함 cp+cmp0(`~/.hermes/scripts/`) · plist 재생성 · kickstart → 오빠 글 1건에 «받았어요» 1줄 확인. (#byz-harness 인스턴스는 `--ack` 없음 = 변경 0)
3. 유휴 깨우기: `scripts/fable-team-bin/ft-idle-wake.sh` ↔ `.fable-team/bin/` cp+cmp0 → `com.byz.ft-idle-wake.plist.template` 의 `__FT_BIN__`·`__BYZ_ROOT__` 를 채워 `~/Library/LaunchAgents/` 에 두고 load(StartInterval 60) → 첫 실행 로그 `.fable-team/state/idle-wake.log` 1줄 확인.
4. 위 1절 줄을 governance 에, 2절 문안을 planner 설계에 반영 · 메모리 `feedback_desk_no_pane_interview_slack_only.md` 에 훅 이름 1구 추가.

## 4. 시험에서 실측한 값 · 보장의 한계

- 직접 키 예외 = «attach 뒤 실제 키 사건»: `#{client_activity} > #{client_created}` 이고 now−activity ≤ 600 s. attach 만 했거나 `send-keys` 만 있으면 activity 가 attach 시각 그대로라 예외 불성립(deny) — `tests/harness/test_desk_self_interview_gate.sh` ②a·②b·③ 이 확인한다. `client_created` 를 못 읽어도 불성립. 같은 초에 attach+타이핑하면 deny(드묾 · 안전한 쪽).
- control-mode(`tmux -C`) 클라이언트는 입력해도 `client_activity` 가 갱신되지 않는다 — 사람 입력 없음으로 읽힌다(안전한 쪽).
- ★ft-idle-wake 의 «입력 절단 0» 은 보장이 아니다(DA⑥ H3)★: ring 직전에 `client_activity` 를 한 번 더 읽어 최근 키면 보류한다. 그 재확인과 `mbox.sh ring` 의 send-keys 사이(수 ms)에 키가 들어오는 창은 남는다 — «창을 최소화» 한 것이지 «0 보장» 이 아니다. 동시 실행은 flock 으로 막고(실패=종료 0), 상태 손상은 ring 0 + rc 4, 명시 실패(mbox rc≠0)만 재시도, 결과 불명·attempt 로 남은 seq 는 재전송 0.
- 데몬 경보 순서(DA⑥ H2): planner 쪽지 먼저(성공 뒤에만 슬랙 «알렸어요»). 결과 불명이면 `alarm_planner_unsure` 기록·재전송 0·슬랙 줄 0 — 사람 확인은 stderr ERROR 로 남는다.

## 5. 원장 R241 행 «처리» 칸 초안

```
처리: 훅 2(desk-self-interview-gate · desk-bash-fg-gate)·수신 데몬 --ack(mirror_ack.py)·유휴 깨우기(ft-idle-wake.sh + plist 틀) 구현 — 브랜치 nano/r241-desk-never-stall(커밋 이력은 증거 줄) · 시험 4종 rc0 · 병합·설치(홈 훅 cp+settings·데몬 cp+plist 재생성·launchctl load)는 master · 완료 1줄 = desk 1번(_desk 현역) 실측.
```
