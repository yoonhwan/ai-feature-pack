# DESIGN — R30 승계 때 오빠 창 자동 이관 (오빠 체감 버그 · 2026-10-08 · byz-harness-arch-claude#12)

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

## §2 안
1. **`ft-seat-handover.sh <구 좌석> <후계 좌석>`** (키트 fable-team bin + 라이브 FT_BIN):
   - 후계 세션 실재 확인(`tmux has-session -t =<후계>`) · 없으면 rc 1(아무것도 안 함).
   - 구 좌석에 붙은 클라이언트 전부(`tmux list-clients -t =<구>`)를 `switch-client -c <tty> -t =<후계>` · 다시 `list-clients` 로 각 tty 가 후계에 붙었는지 확인 → 하나라도 아니면 rc 1 + 그 tty 출력(조용한 실패 0).
   - 붙은 클라이언트가 0 이면 `OK no-client`(오빠가 그 좌석을 안 보고 있었음 — 정상).
   - 구 세션은 kill 하지 않는다(keep-last-2 · 직전 세션 질의). 구 세션에 tmux 옵션 `@handed_over_to=<후계>` 를 단다(아래 3이 읽는 표식).
   - 출력 1줄 `HANDOVER <구> → <후계> clients=<n> (<tty 목록>)` — 승계 원장·부팅 보고에 그대로 붙인다.
2. **승계 표준에 한 단계** — 순서: 후계 tmuxc open → 승계 발주 → 후계 부팅 보고 «수신» → ★`ft-seat-handover.sh <구> <후계>`★ → 구 좌석 정지 레디 보고. 실행자 = 구 좌석 자신(증류하는 쪽). 정본에 박을 곳: governance §승계 1줄 · BOOT 13조(승계 이름) 뒤 1줄 · 글로벌 CLAUDE.md 「증류 실행 절차」 ⑤ 뒤 ⑤-b 1줄(전파 동기화 규칙에 따라 codex·hermes 전파본 동시 갱신 — master 집행).
3. **구 좌석의 «relay 만» 모드** — BOOT 에 1줄: 「`tmux show-option -qv @handed_over_to` 가 비어 있지 않은 세션은 오빠 입력을 받으면 판단·판정 번호·작업 0 — 원문 그대로 `mbox send <후계> … [relay 오빠 원문]` 1통 + 오빠께 「후계 <이름> 이 이어받았어요(창은 이미 옮겨 둠)」 1줄만」. 판정 번호 충돌(408·410)의 원인 = 구 좌석이 번호를 매긴 것 → 번호는 후계만.
   - 혹시 오빠가 탭을 수동으로 구 세션에 되돌려 둔 경우도 같은 규칙(표식은 세션에 남아 있음).
4. **오빠께 attach 명령 금지 lint** — 두 지점:
   - Stop 훅 `no-attach-to-user.sh`: 그 턴 마지막 assistant 텍스트에 `tmux attach`·`tmux a -t`·`attach-session`·`tmuxc attach` 가 있으면 block + 사유 「창 이관은 ft-seat-handover.sh 로 직접 — 오빠께 attach 명령을 올리지 않는다(R30)」. 코드 블록 안 인용도 같게 막는다(오빠가 읽는 글이라 구분 안 함). 하위 좌석·나노 pane 은 오빠가 안 보지만 같은 문장이 mbox 로 올라가므로 전 좌석 적용.
   - mbox send 경로: `[HIL]` 또는 planner 수신 본문에 같은 패턴이면 REJECT(planner 가 그대로 인터뷰에 옮기는 길 차단).
   - tmuxc open 출력의 「접속: tmux attach -t」 줄은 그대로 둔다(사람이 직접 tmuxc 를 칠 때 쓸모) — 좌석이 그 줄을 오빠께 옮기는 것만 막는다.
5. **지금 남은 실례 정리(첫 적용)**: feature 탭 `/dev/ttys000`(#2 → #3)을 ft-seat-handover 로 옮긴다 — master 집행 · 1회.

## §3 나노 범위 (1장)
- `scripts/fable-team-bin/ft-seat-handover.sh`(+ 키트 사본) · `scripts/harness-install/fable-team/templates/hooks/no-attach-to-user.sh` · mbox send 가드(mbox.sh 의 기존 본문 검사 자리 — 키트 사본) · 시험(가짜 tmux 스텁: 클라이언트 0/1/2 · switch 실패 · 후계 없음 / Stop 훅 입력 JSON 패턴 6 · 정상 4 / mbox HIL 본문).
- 정본 문장 3곳(governance §승계 · BOOT · 글로벌 CLAUDE.md ⑤-b) 은 문안만 카드에 · 반영은 master(홈 파일 · 전파본 동기화).

## §4 DA 에 묻는 것 (1회 · 10+10분)
1. switch-client 가 오빠의 «다른 의도»(일부러 구 세션을 보던 탭)를 덮는 경우 — 실행 시점(후계 부팅 보고 수신 뒤 · 구 좌석 자신이 실행)으로 충분한가.
2. Stop 훅이 정당한 문장(예: 문서 작성 중 tmux attach 를 설명)을 막는 오탐 — 오탐 규칙(기록·허용·묶음 알림)과 충돌하는가.
3. `@handed_over_to` 표식만으로 relay 모드 판정 — 표식 유실(세션 재시작)·잘못된 표식 때 구 좌석이 다시 판정을 시작하는 길.
