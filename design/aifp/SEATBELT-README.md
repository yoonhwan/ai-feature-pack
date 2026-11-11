# Seatbelt — aifp(ai-feature-pack) 팀 운영 지침 (이 파일 하나로 시작한다)

aifp-ft-master-pi#3 이거 맞네 (오빠 원문 · aifp 정본화 정식 팀 팀장 결정 · planner#261 발주)
2.0.0 랜딩 뒤에도 aifp 정본화 팀은 상시 팀 · 랜딩 뒤에는 크리티컬 외 즉시 수정 0 · 쌓아서 개선 회차로 묶어 돌린다 (오빠 결정 · planner#261 전달)
ft master 증류 pi opus 팀장으로 증류 (오빠 원문 · planner#262 발주)

> 위 3줄 = 팀 골·운영 원문. 크리티컬 = 서비스 중단·데이터 손실·보안 · 그 외 발견은 `.fable-team/state/aifp-improve-queue.md` 에 쌓는다.
> **너는 어떤 에이전트여도 된다.** 이 파일을 읽고 «부팅 5단계»를 그대로 하면 이어갈 수 있다. 형식·도구 공통 규칙 정본 = BYZ `design/teams/v65/SEATBELT-README.md` — 여기는 aifp 델타만.

---

## 1. 원리 세 줄

1. **작업 = 카드 파일 1개.** `design/aifp/indices/{대기,진행,완성}/<이름>.md` · 1카드 = 1좌석.
2. **상태 = 폴더.** 대기→진행은 spawn 이 옮기고, 진행→완성은 닫힘 판정이 있을 때만 옮긴다(`ft-index-move --da`).
3. **좌석은 갈아 끼운다.** 좌석이 죽어도 파일(카드·판정문·원장)이 상태다. 승계 첫 일 = 골 대조 보고.

## 2. 부팅 5단계 (모든 좌석 공통 · 순서대로)

```
① 골 대조  : 위 3줄을 읽었다. 내 일이 골의 어느 줄·어느 카드인지 «한 줄» 적을 수 있어야 착수.
② 내 자리  : source <루트>/.fable-team/bin-aifp/aifp-env.sh → 명부 seats-aifp.json · 카드 폴더 design/aifp/indices
③ 내 일    : role=nano → 명부 index 의 카드 §구현 범위·§완료 조건이 전부.
             role=master/arch/da → design/aifp/indices/inbox/<role>/ 맨 위부터(없으면 발주문이 일이다).
④ 통신     : bash <루트>/.fable-team/comm/mbox.sh recv <나> · 보고 = mbox send <상대> <나> "<3~5줄>" · 백틱 0
⑤ 첫 보고  : 팀장(명부 _master)에게 «세션명 / 모델·창 / ci 가부 / ①의 골 대조 한 줄 (+ 승계면 retire 칸 · cron=0)». 팀장은 planner 에.
```

## 3. 좌석 구성

| 역할 | 좌석 이름 | 모델 | 비고 |
|---|---|---|---|
| 팀장(master) | `aifp-ft-master-pi#N` | pi · claude-opus-5-5 | 집행만(커밋·push·좌석·착지 순번 요청) · 코드·카드 증거 줄 편집 0 · 크론 0(깨움 = 쪽지·발주) · 상시 유지 |
| arch | `byz-aifp-arch-pi#N` | pi · claude-opus-5-5 | 기획·설계·카드 편집 · 코드 0 |
| DA | `byz-aifp-da-<에이전트>#N` | arch 와 다른 계열(codex 안) | 사전검증·최종판정 · 보류 2회 = 재설계 |
| 나노 | `byz-aifp-nano-<카드>#0` | `FT_IMPL_MODEL` | `ft-nano-spawn.sh <카드> --base origin/main --from <master>` |

- 명부 `.fable-team/seats-aifp.json` 은 손 편집 0 — 바꿈은 planner·도구(`ft-role-spawn`·`ft-seat-retire`) 경유.
- 커밋은 워크트리에서만(팩 루트 main 직접 커밋 = 훅 REJECT) · 착지 = planner 착지 순번 뒤에만.

## 4. 역할 좌석 교체

`ft-role-spawn.sh <role> --team aifp --agent <에이전트> --model <ID>`(첫 개설) · 이미 `_<role>` 이 있으면 `ft-successor-open.sh <구> <워크트리> --name <베이스>#<N+1> --agent … --model … --body-file <발주>` — 발주 첫 3줄 = 골 원문 · 후계 부팅 보고에 `retire=… rc=0`·`cron=0` 필수.

## 5. 형식

카드 필수 절 = BYZ v65 판 §5 그대로(골 원문 · 골좌표 · 배경 · 구현 범위 · 완료 조건 · 조사 근거 · 사전검증 · 상태) · 증거 줄 = `세트: <40hex> · 시험: <명령> rc=<n> · 이슈: <카드>` · 착지 줄 = `- 착지: <sha>`.
