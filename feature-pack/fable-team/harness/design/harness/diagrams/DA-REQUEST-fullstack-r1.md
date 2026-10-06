# DA 요청 — 풀스택 다이어그램 r1 사실 정합 (ft-harness-arch#3 → ft-harness-da#1 · 2026-10-05 · bounded 10분)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 골의 축: 표 A·표 C·원문 5 — 닫는 증거의 둘째 = 「DA 사실 정합 APPROVE」(ORDER-fullstack-diagram 8줄). 이 요청이 그것.

## 범위 (고정 · 넓히지 않는다)
**질문 하나**: `fullstack.ir.json` 의 노드·엣지가 **실재와 맞는가** — 있는데 빠진 것 / 없는데 그린 것 / 방향·종류가 틀린 것.
- 읽을 것(순서): `design/harness/diagrams/README.md` §1·§4 → `fullstack.ir.json` → `FACTS-fullstack-20261005.md` → `design/harness/issue-improvement/SPEC-main-orch-tree-20261005.md` §3.
- 실측 허용(읽기 전용): `tmux list-sessions` · `lsof -nP -iTCP -sTCP:LISTEN` · `launchctl list` · `docker ps` · `ls`. 서버 기동·press·수정·커밋 0.
- 보지 않는 것: 그림의 미관·배치 · 설계 의견 · 하네스 규칙 적정성 · 시크릿(값은 어디에도 없어야 하며 있으면 즉시 REJECT).
- [추측] 노드 2(`py-8000` · `redis-dev`)는 사실로 확정하거나 삭제 권고 — README §4 의 확인 방법.

## 판정 형식 (mbox 5줄 이내 + 전문은 `design/harness/diagrams/DA-fullstack-r1.md`)
```
판정: APPROVE | HOLD(수정 N건) | REJECT(사유 1줄)
실브레인: model: … / provider: … (실행 헤더 두 줄 복붙)
틀린 노드·엣지: id — 실재 — 출처(명령/파일:줄)   ← 최대 10줄 · 없으면 「0」
[추측] 2 처분: py-8000 = … / redis-dev = …
범위 밖 발견(있으면 1줄 · 판정에 안 섞음)
```
10분 · HOLD 2회면 직렬 종료 → ops 결정.
