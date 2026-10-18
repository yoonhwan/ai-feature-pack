# FACTS — 팀 구성 필수 요소 4(tester·checker·bts·poller) 실측 (ft-harness-arch#1 요청 · ft-harness-nano#1 실행 · 조각 P7)

> 측정 시각 **2026-10-05 15:56 KST** · 읽기 전용 · 수정 0.
> 산출 위치 = `design/teams/harness/issue-improvement/`. 원본 = `design/teams/harness/issue-improvement/facts-raw/E*.txt`.
> 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #57016 · 발주 = ops#2 #57013.

---

## E1. 넷의 정체 — 좌석 / 스킬 / 도구

| 요소 | 정체 | 근거(파일:줄) | 사실/추측 |
|---|---|---|---|
| **tester** | **에이전트 정의 + 좌석** | `~/.claude/agents/ft-tester.md:1-7` 「name: ft-tester … 테스트 설계·실행·재현 전담. 구현 수정 금지, 결과만 보고 · model: claude-sonnet-5 · effort: high」 · live 좌석 `ft-v65-tester-claude#13` (tmux **Y**) | [사실] |
| **checker** | **에이전트 정의(현재 좌석 0)** | `~/.claude/agents/ft-checker.md:1-8` 「name: ft-checker … 읽기 전용, 서브에이전트 스폰 불가 · model: claude-sonnet-4-6 · effort: medium」 · live checker **0** · seats `role=checker` **0행** | [사실] |
| **bts** | **스킬**(좌석 아님) | `.claude/skills/bts/SKILL.md:1-3` 「name: bts — 로그·아키텍처/기획·코드 3자 대조 … 나선 수렴」 · 정본 `design/BTS-N-ROUND-LOOP-STANDARD.md:1` 「BTS N-회차 루프 — 표준(2026-08-04)」 | [사실] |
| **poller** | **러너 도구(tests/e2e)** | `tests/e2e/test_tcc8_multi_turn_and_poller.py:1-6` 「tcc8 다회 PTT 턴 + poller n채록 … 산출물에 poller_dom.jsonl」 · `tcc8_completion_press.py:144` `POLLER_INTENT_PATH` · `m1_cadence_round_metrics.py:257` `def dom_axis(poller_path…)` | [사실] |

**[사실] tester 좌석 실례**: `ft-v65-tester-claude#13` tmux **Y** · `seats.json` `role=tester` **12행** · `seats-issues.json` `role=tester` **1행**(= `repro-e2e#0`). cfo/ccu/kk/harness/planner 명부엔 tester 행 **0**.
**[사실] 여는 명령**: `ft-role-spawn.sh:15` `case "$ROLE" in master|da|pm|arch|tester) ;; *) …usage…` → **tester 있음 · checker 없음** (da·arch 와 같은 경로).
**[사실] checker 4축 정본**: `~/.claude/archives/orchestration.md-full-20261001.md:51` 「checker 4축 실측 규칙 — 라이브 관측 판정은 **FE 콘솔 / poller·DOM / worker 로그 / durable 저장소(Redis)** 4축 전부」.
**[사실] bts 호출 주체**: mbox 로그에서 본문 「BTS」 포함 행 = **0** (로그 338행 기준) → 좌석이 아니라 **필요 시 좌석이 부르는 스킬**.
**[사실] poller 켜는 주체**: press 러너 자동 — `tcc8_completion_press.py`(PollerIntent) · `ft-press-gate.sh` 는 **poller 를 grep 하지 않음**(요구 안 함). 산출 `poller_dom.jsonl` 실재 위치 예: `.worktrees/v6-realtime-live/tests/fixtures/press_checkpoint/p2/poller_dom.jsonl`(10-01 13:29 · 88927 B).

---

## E2. 팀별 지금 상태 (셀 = 좌석명 / 「스킬·러너 자동」 / 「없음」)

| 팀 | tester | checker | bts | poller |
|---|---|---|---|---|
| **v65** | `ft-v65-tester-claude#13` (live Y) | **없음** (agent 정의만 · live 0 · 「필요할 때 열고 닫음」) | 스킬(좌석 무관) | **러너 자동**(tcc8 press) — `evid-tester*/` 산출 |
| **cfo** | 없음 | 없음 | 스킬 | **없음** (오디오 press 없음) |
| **ccu** | 없음 | 없음 | 스킬 | **없음** (FE 없음 → 화면 관측 대체) |

**[사실] 근거**: v65 = `design/v65/20261003/evid-tester9-press-seq-001/runner-seq.log`·`evid-tester10-k4-002/`(READ/runner 파일명에 tester) · cfo = cfo 트리에서 `poller_dom|checker|BTS` 히트 0(정책·비용 문서뿐) · ccu = `DESIGN-ccu-stress-infra.md:63` 「①A2「FE cover 시각」은 FE 없음 → «이벤트 수신 시각(SSE)» 으로 대체」.
**[추측]** ccu 는 오디오 press·FE 가 없으므로 poller 부재가 **정상**(SSE 수신 시각이 대체 축) — cfo 도 오디오 press 없어 poller 부재가 정상.

---

## E3. 여는 방식·시점

| 항목 | 인용(파일:줄) | 사실/추측 |
|---|---|---|
| ft-role-spawn 역할 목록 | `ft-role-spawn.sh:15` `case "$ROLE" in master\|da\|pm\|arch\|tester)` — tester **포함**, checker **없음** · da·arch 와 같은 경로 | [사실] |
| P2 트리에 tester·checker | `SPEC-main-orch-tree-20261005.md:78` `└─ tester ★repro-e2e#0` · `:84` `├─ tester ★ft-v65-tester-claude#13 … press·시험` · `:87` 「da · checker 는 필요할 때 열고 닫음 — 지금 0」 · `:110` 「오케 1 밑에 arch·da·nano·tester·checker」 | [사실] |
| 시험 lane(P3-3) | `SPEC-roles-mission-flow-20261005.md:81` 「P3-3 press 석 = **나노 밖** — press 는 tester 또는 오케 좌석만(나노 press 금지)」 | [사실] |
| single_set §3 ③ | `single_set_testing.md:57` 「③ 그 워크트리 세트(서비스·러너·FE 같은 HEAD)로 시험 시작」 | [사실] |
| V6-IMPLEMENTATION-LOOP §7 ⑤ | `design/V6-IMPLEMENTATION-LOOP.md:15` 「5. **일괄검증** — checker: 독립 재현 + 무변경 생존 확인. tester: 실환경 + 라이브 관찰」 · `:41` 게이트 B `arch → tester → checker → arch` · `:53` 「tester 와 checker 는 독립 경로 — 같은 값을 둘이 따로 산출해 대조」 | [사실] |

---

## 회신 요약

- **못 한 항목**: 없음 — E1~E3 전부 실행.
- **사실/추측**: [사실] 약 20항 / [추측] 1항 → **사실 ≈ 95% · 추측 ≈ 5%**.
- **두드러진 3**: ① 넷의 정체 = **tester(좌석+agent) · checker(agent 만·live 0) · bts(스킬) · poller(러너 도구)** ② checker 는 `ft-role-spawn` 역할 목록에 **없고** 지금 살아있는 좌석 0(「필요할 때 열고 닫음」) ③ poller 는 **press 러너 자동**(ft-press-gate 는 요구 안 함) — ccu/cfo 는 오디오 press 없어 poller 부재가 정상(ccu = SSE 수신 시각 대체).