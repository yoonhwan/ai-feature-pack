## v3 스폰 — tmuxc 세션 (기본 경로, spawn_backend=tmux)

v3 기본값은 **전 역할 tmuxc 세션**이다(비-tmuxc 경로 0 — 승인된 예외 3종 `grok_driver`/`checker_workflow`/`raw_launch_fallback` 제외). 워커는 오케 세션과 생명주기가 분리돼 **오케 증류·재시작에도 생존한다**(v3 핵심 이득). 스폰·통신·증류·정리는 `.fable-team/bin/ft-tmux-*.sh` 검증 래퍼가 tmuxc 명령을 감싸 수행한다 — 오케는 `tmuxc open|kill|clean|distill`을 Bash로 직접 발행하지 않는다(orchestration-gate가 deny, §강제 게이트·설계 §0-2 L3).

| 역할 | 브레인 | v3 스폰 (`ft-tmux-spawn.sh`) | 계약 프롬프트 |
|------|--------|------------------------------|--------------|
| ft-architect | sonnet-5/high (에스컬 시 fable-5/high 재스폰) | `--agent claude --role architect` | `.fable-team/prompts/architect.md` |
| ft-architect=codex | codex-5.6-sol | `--agent codex` (세션 직접 — **ft-architect-x 드라이버 폐지**) | `prompts/da-codex.md` 계열 |
| ft-analyst | opus-4-6/high | `--agent claude --role analyst` | `prompts/analyst.md` |
| ft-implementer | opus-4-8/high | `--agent claude --role implementer` | `prompts/implementer.md` |
| ft-tester/tester2 | sonnet-5/high | `--agent claude --role tester` | `prompts/tester.md` |
| ft-da (codex) | codex-5.6-sol | `--agent codex` (세션 직접, **라운드 2+ resume 불요**) | `prompts/da-codex.md` |
| ft-da2 (grok) | grok-4.6 | 드라이버 세션(예외 `grok_driver` — cursor-agent 비세션형) | `prompts/da-cursor.md` |
| ft-checker | sonnet-4-6/medium | `--agent claude --role checker` (단명 — done 후 kill) | `prompts/checker.md` |
| **ft-pm-memory** (신설) | sonnet-4-6/medium | `--name ft-pm-<proj>#0 --role pm` (상시 세션) | `prompts/pm.md` |

- **세션명 규약**: `ft-<slug>-<role>#0` (증류 시 `#N+1` — tmuxc UC10). PM은 `ft-pm-<proj basename>#0`(프로젝트당 1개, 피처 공유). ★신규 좌석 이름·메인 팀 오케 `master` 통일·이슈 진입로/컨펌 게이트 = `references/main-team-governance.md` (정본 · 2026-10-07)★
- **모델 라우팅**: `tmuxc open --name <sess> --agent claude|codex --role <role> --prompt <계약경로>`가 정본. 모델 full-ID·effort·`FT_WORKER_ROLE` env 주입 가능 여부는 install.json `tmuxc_caps`가 판정 — 갭 시 승인된 `raw_launch_fallback`(headroom 기동 합성) 또는 스폰 스크립트 `exit 4 CAPABILITY_GAP` HIL 상신.
- **역할 계약 전달**: `~/.claude/agents/ft-*.md`는 tmux 세션에 미적용 → 본문을 세션 계약 프롬프트 `.fable-team/prompts/<role>.md`로 이관(Phase 3 산출). 스폰 후 `[orch-><sess>] 계약: <path> Read 후 시작. 입력: <경로들>` 1줄 send.
- **설치 배선**: 세션 계약 프롬프트 원본은 `skill/templates/session-prompts/*.md`(8종) — 설치·업데이트 시 `agent-templates`와 **동일 `{{...}}` 키로 치환**해 `.fable-team/prompts/<role>.md`로 복사한다(신규 인터뷰 질문 불요). 절차는 `references/install-interview.md` §5-3-2, 재치환은 `references/update.md`. 잔여 `{{`는 설치 실패로 간주.
- ★★**나노 슬롯은 «항상 채워서 일을 시킨다» — 메인 오케의 목적 (오빠 2026-10-02 16:2x)**★★ 「나노가 또 놀고있네? 트리는 이렇게 산더미인데 … 열었다 닫고 다음거 안시키고 가능 슬롯을 비워두네」 · 「각 메인이 나노워커 슬롯을 설정하면 작업 리스트에서 어떻게서든 나노를 채워서 일을 시키려는 목적을 가지고 일하라」 · 「테스트가 겹치거나 다른 최우선 작업이 있을 때 정지·미배정 예외는 있어도 가장 우선은 슬롯 배정」 · 「멈추고 기다리고 잊혀지는 나노가 닫아지게 해주는 게 중하다 — 닫는 게 아니라 메인 오케가 확인하면서 풀어줘야지」 · 「증류·완성 뒤 테스트가 끝나면 매번 잘 정리해 닫고 워크트리·브랜치도 정리」. ⇒ ①메인은 슬롯 수(`FT_NANO_SLOTS` · 기본 6)를 정하고 ★«일하는 석»을 그 수로 유지★한다 — 나노를 닫는 «같은 턴»에 대기/ 카드로 spawn · ★arch 지정을 기다리지 않는다★(후보 = `ft-nano-slots.sh` 출력 · 예외는 사유 한 줄) ②★«노는 석»(턴 끝 ≥10분 IDLE)도 슬롯을 먹는다★ — press·DA·랜딩·판정을 기다리는 나노는 «잊힌 석»이다 → 메인이 그 턴에 «무엇을 기다리나»를 확인하고 «푼다»(랜딩 집행 · DA 소환 요청 · press 순번 · 판정 요청) ③풀린 나노는 완성 → 테스트 끝 → `ft-nano-close`(워크트리 정리 · 브랜치 보존 · 증류도 같은 경로) ④도구: `ft-nano-close.sh` 가 CLOSED 직후 `ft-nano-slots.sh` 를 불러 «일하는 석/노는 석/빈 석 + 후보 spawn 명령»을 낸다 — 출력이 빈 석 >0 이면 그 턴은 끝나지 않는다. 실측(10-02 16:2x): 명부 9 중 노는 석 3(press 대기 2·DA 대기 1) · 지적 5회째.
- **Seatbelt 1.0.0 — 좌석 명부·인덱스·나노 생명주기·틱**: `references/SEATBELT.md` (부팅 5단계 · 인덱스=작업 · 상태=폴더 · 좌석은 갈아 끼운다). 알림 여부는 `seats.json`(`tick`) 이 정한다 — `ft-mbox.sh send` 의 `--no-notify` 는 WARN+무시, `--urgent` 는 항상 울림. 템플릿 `templates/seats.json.example` · `templates/index.md.example`.

  | 스크립트 | 하는 일 | exit |
  |---|---|---|
  | `ft-index-lint.sh <index.md>…` | 인덱스가 «누가 읽어도 착수 가능»한가(골 3줄 바이트 일치 · 6절 · 닫는 증거 정본 실재 · 인용 ≤4 · 경로 실재) | 0 OK · 1 REJECT · 2 usage |
  | `ft-index-move.sh <index.md> <대기\|진행\|완성> [--da F#§N] [--seat S]` | 상태=폴더. 대기→진행 은 lint+`--seat`, 진행→완성 은 `--da` 판정문에 「닫힘」/「CLOSE」 필수 | 0 · 1 · 2 |
  | `ft-nano-spawn.sh <indices/대기/X.md> [--agent] [--model] [--dry-run]` | 나노 좌석 한 번에: lint → 워크트리 → tmuxc open → remain-on-exit+태그 → seats.json → 대기→진행 → 첫 발주 → jsonl 도달 | 0 · 1 · 2 · 5(도달 미확인) |
  | `ft-nano-close.sh <좌석> --result P --recv SEQ [--kill]` | 값 3종(결과 실재 · master 회수 seq · 유휴)으로 닫고 명부 삭제·원장 append. kill 은 keep-last-2 밖일 때만 | 0 · 1 · 2 · 3(HIL) |
  | `ft-nano-slots.sh` | ★나노 슬롯 채움★: 일하는 석/노는 석(≥10분 IDLE)/빈 석 + 대기/ press 불요 후보 spawn 명령. `ft-nano-close` 가 CLOSED 직후 자동 호출 | 0 |
  | `ft-role-spawn.sh <master\|da\|pm> [--agent] [--model] [--dry-run]` | 역할 좌석 교체(행 추가+계보 `_replaced_by`/`_replaces`) + 인박스 첫 발주. 구 좌석 kill 안 함 | 0 · 1 · 2 · 5 |
  | `ft-tick.sh [--once] [--dry-run]` | 통합 틱: seats.json 을 매 루프 다시 읽어 master(900s+goal 240s)·pm(600s) 프롬프트 + `stall()` 정지 감시(5분) | — |
  | `ft-tick.plist` · `ft-tick-install.sh [--uninstall]` | launchd KeepAlive 로 틱 생존(`com.byz.ft-tick`, 로그 `/tmp/ft-tick.log`) | — |
  | `ft-seat-status.sh list\|one <좌석>\|stalled [--min N]` | 좌석 정지 판정 정본 = jsonl mtime AND pane 스피너. pane 텍스트 단독 판정 금지 | — |

  v65 고유 상수는 env 기본값(`FT_NANO_PREFIX` `FT_NANO_WT_PREFIX` `FT_ACTIVE_TAG` `FT_NANO_LEDGER` `FT_GOAL_LEDGER` `FT_GOAL_LINES_FILE` `FT_SEATBELT_README` `FT_INBOX_ROOT` `FT_TICK_MASTER_MSG` `FT_TICK_PM_MSG`) — 로직 무변경. `ft-tick.sh` 의 goal-tick 은 `FT_TICK_GOAL_TICK`(기본 옆 `ft-goal-tick.sh`, 팩 미포함 — 없으면 로그 한 줄 후 건너뜀).
- **보고·통신**: 산출물은 워커가 직접 Write, 완료는 파일 센티널(`<sess>.done` 원자 tmp+mv), 오케 수신은 `ft-tmux-poll.sh` 1줄 호출(`DONE <path>`/`MSG`/`NEEDS_INPUT`/`RUNNING`/`HANG`). 세션간 메시지 본문은 **파일 큐 mbox**(`ft-mbox.sh send`=파일 큐+doorbell / `recv`=READ 규약) — send-keys 본문 운반 폐지, doorbell은 지연 최적화. 상세 = 설계 §1-4·§1-6·comm-filebased.
- **가시성**: 워커는 독립 tmux 세션이다 — 우측 pane 상주가 아니라 **필요 시 사용자가 `tmux attach`로 관찰**한다(사용자 승인 2026-07-11). 오케의 HIL 집중 게이트(§1-6 hil 센티널)가 사용자 접점을 단일화하므로 상시 attach는 불요.
- **롤백 진입점**: `install.json spawn_backend.default: "agent-v2"`면 `ft-tmux-spawn.sh`가 `exit 6 USE_AGENT_V2`를 반환 → 오케가 아래 **Legacy spawn 부록** 절차(Agent 도구 스폰 + checker=Workflow)로 전환한다.
