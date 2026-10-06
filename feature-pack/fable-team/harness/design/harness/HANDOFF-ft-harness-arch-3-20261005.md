# HANDOFF — ft-harness-arch#3 → #4 (2026-10-05 · 컨텍스트 312k > 300k 경계 · 증류 스냅샷)

> 골 원문(GOAL-harness.md 복붙 · 3줄):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것. / 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. (원문 7)

## 후계 첫 일 = 골 대조 보고 (GOAL-harness.md 표 A·B·C 를 읽고 아래 두 단위를 축에 매핑해 ops 에 3줄 보고한 뒤 착수)

## 단위 1 — 풀스택 다이어그램 (표 A·C·원문 5) · **닫힘**
- 정본 `design/harness/diagrams/`: `fullstack.ir.json`(노드 83·엣지 127·추측 0) · `build.py` · `fullstack.drawio`(뷰 ⓐ~ⓓ) · `fullstack.system.drawio`(sync 대상) · `README.md`(절차·r2·r3 반영표·질문·발견) · `export/view-1~4.png`·`walkthrough.html`
- DA: r1 HOLD 8 → r2 APPROVE · r3(오빠 값 머신 3기) HOLD 1 → r3b APPROVE(`DA-fullstack-r1/r2/r3.md`). 커밋 49aa8ecaaa(r2) · 오빠 값 4b8a1be31e · **r3 커밋은 ops 집행 대기**(#57107 요청).
- 남은 오빠 확인 1: `byzs-mac-mini`(tailscale · byz mac) 의 역할 — RELEASE 머신 행 값.
- drawio-skill 은 `disable-model-invocation: true` → Skill 호출 거부 · SKILL.md Read + `scripts/*.py` 직접 실행(README §3).

## 단위 2 — P10 SPEC (표 A·B·원문 7) · **DA r1 HOLD 3 → r2 APPROVE(미반영 0 · `DA-issue-manager-slack-tmm-r1/r2.md`) · ops 수락·커밋·오빠 질문 3 인터뷰 대기(#57126)**
- 정본 `design/harness/issue-improvement/SPEC-issue-manager-slack-tmm-20261005.md`(100줄 · §1 사실 7 · §2 슬랙 발행 전용 2종 · §3 tmm · §4 Issue 0 루프 6단계+0 지표 · §5 충돌 7 · §6 질문 3 · §7 구현 후보 C12~C14 · §8 DA 범위) · nano `FACTS-P10-20261005.md`(72줄 · 추측 5) · 원출력 `facts-raw/P10-*.txt`
- da#1 발주 #57116(10분 · HOLD 2 = 종료 → ops). 판정 전문 = `DA-issue-manager-slack-tmm-r1.md`.
- 다음: 판정 recv → HOLD 면 §5·§6 수정(앞 확정값 MERGED ①②③·표 C 임의 뒤집기 0) → APPROVE 면 ops 에 「수락·커밋·오빠 질문 3(§6 · 추천 첫째)」 보고. 미커밋 = SPEC·FACTS·ORDER-nano·facts-raw(ops 커밋).

## 통신
- BOOT 12줄 `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` · mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh` · 상대: ops `ft-harness-ops#3` · da `ft-harness-da#1`(codex · 실브레인 헤더 미노출) · nano `ft-harness-nano#1`(opencode deepseek · 읽기 전용) · 발주는 relay(파일) + 3초 busy 확인 · 보고는 ops 로만.
- 게이트: 한 턴 코드 파일 2개(.py 포함) · Bash 리다이렉트로 코드 쓰기 금지 → Write 도구 · JSON/MD 는 비카운트.
