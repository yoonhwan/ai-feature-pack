---
규칙: 팀장(리드) 사건 턴 = «ft-lead-tick.sh 1회 → 마지막 줄 결정 필요 0 이면 끝» 1줄 (사람 #273320 «돈낭비 컨텍스트 낭비를 완전히 제거» · master#170 #274214)
적용: 팀장 좌석이 쪽지 doorbell 로 깬 턴 · 부팅 본문·승계서에 넣는 일은 r1479(이 파일은 정본만)
출처: r1472 카드(arch#244 · arch#245 범위 수정 · DESIGN-lead-keepalive 62a46f729d DA APPROVE #274670)
검토: 나노 byz-harness-nano-r1472-lead-tick-script-once-like-desk#0 (2026-11-15)
---

# 팀장 사건 턴 프롬프트 (정본 1줄)

## 프롬프트 — 이 줄을 그대로 쓴다
```
쪽지로 깬 턴 = bash <LIVE_BIN>/ft-lead-tick.sh <내 좌석> 1회 → «결정 필요: 0» 이면 끝 · N≥1 이면 그 항목만 도구 1회 · 주기 호출 0
```

`<LIVE_BIN>` = `~/.claude/fable-team/live/<판>/bin` (라이브 설치 자리).

## 스크립트가 대신하는 것
| 항목 | 내용 |
|---|---|
| ① 결속 | 팀 = 좌석 둘째 토큰 · `seats-<팀>.json` `_master` == 내 좌석 · 아니면 recv 0 · send 0 · rc1 |
| ② 카드 수 | `git ls-tree origin/main <_cards>/{대기,진행}` (`FT_LEAD_TICK_CARDS_REF` 로 덮음) |
| ③ 좌석 | 명부의 같은 팀 nano·da 행 × `ft-seat-status.sh list --json` · 20분+ 유휴만 줄 |
| ④ 열린 h | `ft-hil.sh --pending` 중 `.notify` 에 내 이름이 있는 것 |
| ⑤ 쪽지 | `mbox.sh recv` 머리(seq·from·60자) · 전문은 `<루트>/.fable-team/state/lead-tick/` |
| ⑥ [정리] | 3줄을 스크립트가 조립해 보고처로 send(모델 출력 아님) |

`결정 필요 N` = 받은 쪽지 중 `[HIL]`·`[결정]`·`[긴급]` 머리 + 20분+ 유휴 좌석 + 이 팀 열린 h + 판정 불가 항목.

## 송신 규칙
- 보고처 = 명부 `_report_to` · 없으면 planner `_master`. 자기·같은 좌석이면 send 0 + «자기 송신 차단» · rc1.
- N=0 이고 ②~④ 가 `<상태>/<좌석>.last` 와 같으면 send 0(파일에 «조용함 ts» 만). 심박이 아니다.
- [정리] 첫 줄 = `카드 대기 N · 진행 N · 유휴 N · 다음 수 …`.

## 하지 않는 것
- 주기 틱에서 부르지 않는다. 쪽지로 깬 턴에서만 1회 부른다(두 번째 호출 = recv 소비 + [정리] 1통 더).
- `결정 필요: 0` 인데 «더 확인» 하려고 도구를 부르지 않는다. 그 확인이 E1 위반이다.
- 스크립트는 일을 착수하지 않는다. 착수는 «결정 필요» 항목이 시킨 것만.

## 상한
항목당 7초 · 전체 25초(`FT_LEAD_TICK_BUDGET`) · 남은 예산 0 이면 실행 0 · rc124 · send 0. 출력 30줄(넘으면 접고 마지막 줄은 지킨다).
