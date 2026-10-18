# DESIGN — R30 승계 때 오빠 창 자동 이관 (오빠 체감 버그 · 2026-10-08 · byz-harness-arch-claude#12 · r2 교정 = #13)

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: A 모니터·오빠 요청(오빠 원문 「이걸 나보고 하라는 것도 버그다 … 잘 혼자 하던 증류를 사용자에게 요청하면 버그」) + C 반영. 원장 R30 · planner#9 → master#14 #62370 · 보고 = planner#10.

## §1 실측 (2026-10-08 13:5x)
| 사실 | 값 |
|---|---|
| 오빠가 보는 창 | Ghostty 탭마다 tmux 클라이언트 1개(`tmux new-session -A -s tmm` 래퍼 → 좌석 세션). `tmux list-clients` 9개 · 각 client_tty 가 좌석 세션 하나에 붙음 |
| 같은 버그 실례 (지금) | `/dev/ttys000` 이 byz-feature-master-claude#2 에 붙어 있음 — seats-feature.json `_master` = #3. 오빠 탭은 옛 좌석 |
| planner 사건 | #9 → #10 증류 뒤 오빠 탭이 #9 에 남음 → #9 가 「#10 pane 에서」 + attach 명령을 오빠께 2회 · #9 가 받은 오빠 지시를 #10 에 relay 하며 판정 번호 충돌 2회(408·410) |
| attach 명령의 출처 | `~/.claude/skills/tmuxc/SKILL.md:89` — tmuxc open 이 「접속: tmux attach -t {name}」을 출력 → 좌석이 그대로 오빠께 옮김 |
| 창 이관 수단 | `tmux switch-client -c <client_tty> -t <후계>` — 그 탭이 후계 세션을 보게 된다(탭·Ghostty 손댐 0 · 되돌림 = 같은 명령 역방향) |

## §2 안 (r2 · DA HOLD-H1·H2·H3 교정 반영 — 바뀐 곳은 ★r2★)
1. **`ft-seat-handover.sh`** (키트 fable-team bin + 라이브 FT_BIN) — 하위 명령 3개 · 기록 = 영속 장부 `.fable-team/state/handover.jsonl`(append-only · 한 줄 = 한 승계).
   - ★r2★ **`snapshot <구> <후계>`** — 실행 시점 = 후계 tmuxc open «직전»(구 좌석이 아직 현역인 마지막 순간). 구 세션 클라이언트를 `tmux list-clients -t =<구> -F '#{client_tty} #{client_pid} #{client_created}'` 로 떠서 장부에 `{"state":"pending","old","new","follow":[{tty,pid,created}…],"ts"}` 1줄. ★근거: T0 에는 구 좌석이 유일한 현역이라 «보관·조회 탭»이 아직 존재할 수 없다 — 그때 붙어 있던 탭 = 현재 작업을 따라가는 탭(H1 의 follow 판정 근거를 도구가 기록)★.
   - ★r2★ **`apply <구> <후계>`** — 실행 시점 = 후계 부팅 보고 «수신» 뒤. 순서: ①후계 세션 실재(`has-session -t =<후계>`) + 명부 `_<역할>` == 후계 (아니면 rc 1 · 아무것도 안 함) ②pending 행의 follow 목록만 대상 — 각 항목을 «실행 직전» 재조회해 tty·pid·created 3개 모두 같고 client_session == 구 일 때만 `switch-client -c <tty> -t =<후계>` ③재조회로 후계에 붙었는지 확인 ④장부에 `{"state":"done","moved":[…],"skipped":[{tty,reason}…]}` 1줄. skipped reason = `gone`(탭 닫힘) · `moved-by-user`(오빠가 이미 다른 세션으로) · `identity-changed`(같은 tty 재사용 · pid/created 다름) · `switch-failed`(rc 1). ★T0 뒤에 구 세션에 붙은 클라이언트는 대상 밖(= 오빠가 일부러 직전 세션을 보러 온 탭 · keep-last-2 조회 용도) — switch 0★.
   - 출력 1줄 `HANDOVER <구> -> <후계> moved=<n> skipped=<n> (<tty:reason> …)` — 승계 원장·부팅 보고에 그대로.
   - follow 0 이면 `OK no-client`(정상). 구 세션 kill 0(keep-last-2). 구 세션 옵션 `@handed_over_to=<후계>` 는 ★힌트·캐시로만★ 단다(권위 아님 · 3 참조).
   - ★r2★ **`status <세션>`** — 3 의 판정기. `<세션>` 은 호출자가 `tmux display-message -p -t "$TMUX_PANE" '#{session_name}'` 로 고정(ambient/default 세션 오독 차단 · H3).
2. **승계 표준에 두 단계** — 순서: ★r2★ `snapshot <구> <후계>` → 후계 tmuxc open → 승계 발주 → 후계 부팅 보고 «수신» → `apply <구> <후계>` → 구 좌석 정지 레디 보고. 실행자 = 구 좌석 자신. 정본 문장 3곳(governance §승계 · BOOT 13조 뒤 · 글로벌 CLAUDE.md 「증류 실행 절차」 ③ 뒤 ③-b 와 ⑤ 뒤 ⑤-b) — 반영 master(전파본 동기화 포함).
3. **은퇴 좌석 판정 = 영속 권위 대조** (★r2 · H3★)
   - `status <나>` 판정표 (세 근거 = ①장부 done 행 old==나 ②명부 `_<역할>` ③옵션 `@handed_over_to` on `=<나>`):
     | ① 장부 | ② 명부 | 결과 |
     |---|---|---|
     | 없음 | 나 | `ACTIVE` — 평소대로 |
     | done 나→X | X (X 세션 실재) | `RETIRED X` — 옵션이 없거나 다르면 X 로 복원(캐시 재생성) |
     | done 나→X | Y≠X 또는 X 세션 없음 | `MISMATCH` |
     | 없음 | Z≠나 | `MISMATCH`(장부 없이 명부만 바뀜 — 이름 문자열로 후계 추측 0) |
     | pending 만 | 나 | `ACTIVE`(승계 진행 중 · apply 전) |
   - **집행 = UserPromptSubmit 훅 `retired-seat-guard.sh`**(선언 아닌 강제): 입력이 들어올 때마다 `status` 를 돌려 결과를 additionalContext 로 주입.
     - `RETIRED X`: ★읽기 전용 질의(직전 세션 기록·근거 질문)★ 는 자기 이력으로 답한다(keep-last-2 조회 용도 유지). ★새 작업·새 판정·판정 번호 0★ — 새 요청이면 원문 그대로 `mbox send X <나> "[relay 오빠 원문] …"` 1통 → QUEUED seq 확인 + `ft-reach-check.sh X <seq>` 도달 확인 뒤에만 오빠께 「후계 X 에 전달했어요(쪽지 seq)」 1줄. 도달 미확인이면 「X 에 보냈지만 도착 확인 안 됨」 그대로. ★「창은 이미 옮겨 둠」 같은 현재 창 상태 단정 문구 0★(돌아온 탭이 바로 그 반례).
     - `MISMATCH`: 새 판정·relay 0 · 오빠께 「이 좌석의 후계 관계가 장부·명부에서 어긋남 — 하네스 master 에 확인 요청함」 1줄 + `mbox send <하네스 master> … [handover-mismatch] <세 근거 값>`.
     - `ACTIVE`: 주입 0.
4. **오빠께 승계 실행을 떠넘기는 문장 lint** (★r2 · H2★ — 차단 대상을 «요청 형태»로 좁히고 나머지는 오탐 규칙)
   - Stop 훅 `no-attach-to-user.sh`: 그 턴 마지막 assistant 텍스트(transcript_path 의 마지막 assistant 항목)에서
     - **block**: attach 패턴(`tmux attach`·`tmux a -t`·`attach-session`·`tmuxc attach`)이 ★«오빠 실행 요청 형태»★ 인 줄 — (a) `! ` 접두 명령(오빠께 명령을 맡기는 이 하네스의 표준 꼴 · 메모리 「User-run commands = plain text」) 또는 (b) 같은 줄에 요청어(`해 주세요`·`하세요`·`붙어 주`·`접속해`·`들어가 주`·`실행해`). 사유 「승계 창 이관은 ft-seat-handover.sh apply 로 직접 — 오빠께 attach 실행을 맡기지 않는다(R30)」.
     - **기록만(허용)**: 그 밖의 모든 등장(문서·감사·코드 블록 설명·실패 원문 인용·[HIL] 막힌 명령 원문) → `.fable-team/state/hil-falsepos.log` 에 1줄(기존 오탐 규칙 경로 · governance §7) · 묶음 알림은 기존 오탐 묶음과 같은 길.
     - **무한 루프 차단**: 훅 입력 `stop_hook_active == true` 면 block 하지 않고 기록만(재검 1회 뒤 통과 · 두 번째 block 0).
   - ★r2★ **mbox send 가드는 뺀다** — [HIL] 막힌 명령 원문 전달(governance §7 필수 경로)을 막는 부작용이 처방 이득보다 크다. planner 쪽 전파는 4 의 Stop 훅이 planner 좌석 자신의 최종 텍스트에서 같은 기준으로 잡는다.
   - tmuxc open 출력의 「접속: tmux attach -t」 줄은 그대로(사람이 직접 칠 때 쓸모).
5. **지금 남은 실례(첫 적용)** — feature 탭 `/dev/ttys000`(#2 → #3)은 ★snapshot 이 없는 과거 승계★ 라 follow 판정 근거가 없다(DA §2 끝 문장). → `apply --client /dev/ttys000 --confirmed-by <HIL 쪽지 seq>` 1회 모드: master 가 [HIL] 로 planner 에 「이 탭을 #3 으로 옮길까」 1문 → 값 받은 seq 를 인자로 · 장부에 그 seq 를 근거로 남김. 근거 seq 없으면 rc 1.

## §3 나노 범위 (1장)
- `scripts/fable-team-bin/ft-seat-handover.sh`(snapshot·apply·status · + 키트 사본) · 템플릿 훅 2: `no-attach-to-user.sh`(Stop) · `retired-seat-guard.sh`(UserPromptSubmit).
- 시험 (가짜 tmux 스텁 + 가짜 명부·장부 · 실 tmux switch 0):
  - handover: follow 0/1/2 · ★follow 1 + T0 뒤 붙은 조회 탭 1(→ 조회 탭 switch 0)★ · 선택 뒤 오빠가 다른 세션으로(moved-by-user) · tty 재사용(identity-changed) · 후계 없음 · 명부 불일치 · 일부 switch 실패(rc 1 + skipped 출력) · `--client` 모드 근거 seq 없음 rc 1.
  - status: 판정표 5행 전부 · 옵션 유실(→ RETIRED + 복원) · 옵션이 엉뚱한 X'(→ 장부·명부가 이김) · 세션 재생성 · ★다른 default 세션에서 호출(TMUX_PANE 고정 확인)★.
  - Stop 훅: block 6(`! tmux attach`·요청어 4종·attach-session) · 기록만 6(코드 블록 설명·감사 인용·[HIL] 원문·문서 작성·tmuxc 출력 인용·영문 설명) · `stop_hook_active=true` 면 block 0.
  - guard 훅: RETIRED·MISMATCH·ACTIVE 주입 문구 3.
- 정본 문장 3곳 문안만 카드에 · 반영 master.

## §4 DA 에 묻는 것 (r1 · 1회 → HOLD 1 · 원인 3)
1. switch-client 가 오빠의 «다른 의도»를 덮는 경우 — 실행 시점으로 충분한가. → ★r2: T0 snapshot follow 목록 + 실행 직전 identity 3중 재확인 · T0 뒤 붙은 탭 대상 밖★
2. Stop 훅 오탐 — 오탐 규칙과 충돌하는가. → ★r2: block 은 «오빠 실행 요청 형태»만 · 나머지 hil-falsepos.log 기록 · mbox 가드 제거 · stop_hook_active 루프 차단★
3. 표식만으로 relay 판정 — 유실·오표식. → ★r2: 장부(영속)+명부 대조 권위 · 옵션은 캐시 · MISMATCH 면 판정·relay 0 + 보이는 오류 · 도달 확인 뒤에만 전달 문구★

## §5 r2 교정 질문 (같은 DA · 10분 1회 · 2번째 HOLD 면 이관)
- H1·H2·H3 각각에 대해 r2 §2 의 해당 항목이 DA §2~§4 의 «최소 교정»을 충족하는가 — 새 원인만 반박.

## §6 통합 이관 (DA 2 HOLD · 연속 리뷰 종료 · DA §7·§8 · byz-harness-arch-claude#13 → master#14)
| 항목 | DA 판정 | 이관 내용 |
|---|---|---|
| H3 은퇴 권위(장부+명부 · 옵션 캐시 · TMUX_PANE 고정 · 역사 질의 유지 · 도달 확인 뒤 전달 문구) | ★APPROVE★ | r2 §2-1 status · §2-3 그대로 구현 |
| H1 보호 장치(identity 3중 재확인 · T0 뒤 탭 제외 · 오빠 이동 skip · legacy `--client` + HIL seq) | 수락 | r2 §2-1 apply · §2-5 그대로 |
| H2 보호 장치(mbox 가드 제거 · stop_hook_active 루프 차단 · 오탐 기록 경로) | 수락 | r2 §2-4 그대로 |
| **H1 잔여** — T0 «이전»부터 붙어 있던 조회 탭도 follow 로 추정됨 | HOLD | 아래 ①안 |
| **H2 잔여** — 요청문을 «인용한» 줄(감사·HIL 원문·코드 블록의 `! tmux attach`)이 요청어 조건에 걸려 block | HOLD | 아래 ②안 |

**① H1 잔여 처방안 (arch 권고 · DA 미검증)** — 의도 추정 대신 «모호하면 묻는다»로 판정 가능하게:
- 실측 배치 = 오빠 Ghostty 탭 1개 = 좌석 세션 1개(13:5x `list-clients` 10개 · 세션 10개 전부 다름 · 한 세션에 2 탭 0).
- snapshot 규칙: T0 에 구 세션 클라이언트가 ★정확히 1개★ 면 follow(배치 관례 = 그 팀 작업 탭). ★2개 이상이면 follow 0 + `ambiguous` 기록★ → apply 는 그 세션을 옮기지 않고 master 가 [HIL] 1문(「어느 탭을 후계로」 · tty 목록) → 값 seq 로 `--client` 모드. 0 개면 no-client.
- fixture: T0 follow 1 + archive 1 (= 2개) → switch 0 + ambiguous · T0 1개 → move · HIL 값 받은 `--client` → 그 tty 만.
- 이 관례(1 탭 = 작업 탭)를 받아들일지 = master 판단(하네스 내부 · 오빠 인터뷰 불요). 거부하면 대안 = launcher(`tmm` 래퍼)가 탭 생성 때 follow 표식을 남기는 길(Ghostty 쪽 수정 · 범위 큼).

**② H2 잔여 처방안 (arch 권고 · DA 미검증)** — 인용 문맥을 요청 검사보다 «먼저» 떼어낸다:
- 1단 제외(기록만): 코드 펜스 안 줄 · `>` 인용 줄 · 패턴이 따옴표(`"…"`·`「…」`·`'…'`·백틱) 안에 있는 줄 · 텍스트 첫 줄이 `[HIL]`·`감사`·`AUDIT`·`DESIGN` 로 시작하는 메시지 전체.
- 2단 block: 남은 줄 중 `! ` 접두 또는 요청어 동반 줄만.
- fixture(같은 파일에서 구분): 인용 안 「tmux attach -t X 를 실행해 주세요」 → 기록 · 코드 펜스 안 `! tmux attach` → 기록 · [HIL] 원문 → 기록 · 맨 줄 `! tmux attach -t X` → block · 맨 줄 「tmux attach -t X 로 접속해 주세요」 → block.

**나노 배정(master)**: r2 §3 범위 + 위 ①② fixture 를 «한 카드»로. 카드 작성은 master 결정 뒤 arch 가 대기/ 에 올림(lint 통과 · 미커밋). 실제 창 이동·홈 설치는 카드 범위 밖(master 집행).
