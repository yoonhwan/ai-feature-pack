# 인덱스: 인박스 큐 행에 분류 출처 `via` = rule | haiku | unknown — Haiku 성공률·호출 수를 셀 수 있게 (판정 461 · 판정 441 후속)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 461(planner#11 #63736 · master#16 #63739 · 근거 판정 441 점검표 master 실측)
- 상태: 대기
- 선행: 없음 — ★origin/main 최신에서 브랜치★(인박스 파일은 main 에만 있다 · ops/main-base 에 없음 · 라이브 `.fable-team/bin` 사본 = main 바이트 동일 arch cmp)
- 시험 입력: 기존 `tests/harness/test_inbox.sh` 의 mktemp 임시 FT_ROOT + 가짜 Haiku 스텁(성공·실패) — 실제 mbox·claude 호출 0 · 라이브 .fable-team 쓰기 0
- 기준값: 큐 행 필드 = body_path·cls·from·group·mark·prio·reported·seq·ts 9개 — 규칙 분류인지 Haiku 라벨인지 행만 보고 구분 못 함(판정 441 점검표)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터 — 인박스 Haiku 호출의 성공·실패를 셀 수 있게) + C(반영). 핵심 한 줄: 큐 행마다 «누가 분류했나» 를 남긴다 — 규칙표면 rule, Haiku 라벨이 붙으면 haiku, 아직 미상이면 unknown.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
메인팀 인박스(`ft-inbox.py` + `ft_inbox_core.py`)는 쪽지를 받으면 규칙표(`rule_class`)로 즉시 분류해 큐 파일(jsonl)에 한 행을 쓰고, 규칙표에 안 맞아 «미상» 이면 분리 프로세스(`classify`)가 Haiku 를 한 번 불러 라벨을 갱신한다(실패·timeout 이면 미상 유지 + hook-errors.log 1줄). 지금 행에는 분류 출처가 없어서 «Haiku 가 몇 번 불렸고 몇 번 성공했나» 를 셀 수 없다. 이 카드는 행에 `via` 하나만 더한다: ingest 때 규칙표가 분류하면 `via="rule"`, 미상이면 `via="unknown"`, classify 가 라벨을 붙이면 같은 잠금 안 갱신에서 `via="haiku"`, Haiku 실패면 `unknown` 그대로. 이미 쌓인 옛 행(via 없음)은 고치지 않는다(마이그레이션 0) — 읽는 쪽은 `x.get("via", "unknown")` 로 본다. 화면 출력(`show`·`show --compact`)과 mark/report/archive 동작은 바꾸지 않는다(필드는 셈 전용 · 강제 0). 셈은 큐 파일을 jq 로 읽는다(예: `jq -s 'group_by(.via // "unknown") | map({via: (.[0].via // "unknown"), n: length})' <큐>.jsonl`).

## 사전검증
- 소환: 아니오
- 면제: 행에 기록 필드 1개 추가 · 분류·화면·mark/report/archive 동작 0 변경 · 옛 행 무수정 · 되돌림 1커밋 · planner 판정 461 GO(소형) — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- 라이브 사본(= origin/main 바이트 동일): `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py:38` ingest 규칙표 분류 · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py:39` 행 dict(필드 9개) · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py:43` 미상이면 classify 분리 실행 · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py:65` classify 성공 시 `x.update(cls=…, prio=…)` · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py:56` 실패 시 미상 유지 + 로그.
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft_inbox_core.py:114` `rule_class`(안 맞으면 「미상」) · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft_inbox_core.py:63` `read_q`.
- 시험(origin/main): `tests/harness/test_inbox.sh` 152줄 — 1) 분류 101~108(규칙표 6 · 미상+Haiku 성공 107 · 미상+Haiku 실패 108).

## 구현 범위 (닫힌 목록 · 정본 `scripts/fable-team-bin/` + 키트 사본 `scripts/harness-install/fable-team/bin/` 같은 바이트)
1. `scripts/fable-team-bin/ft-inbox.py`(+ 사본):
   - ingest 행 dict 에 `"via": "unknown" if cls == "미상" else "rule"`.
   - classify 성공 갱신을 `x.update(cls=cls, prio=PRIO[cls], via="haiku")` 로. 실패 경로 무변경(via 그대로).
   - 그 밖(view·show·show --compact·mark·report·archive·usage 문구) 무변경.
2. `ft_inbox_core.py` 는 바꿀 필요가 없으면 0(헬퍼 추가 금지 — 읽는 곳이 생기면 그때).
3. 시험 `tests/harness/test_inbox.sh` 에 단언 추가(기존 단언 무변경): ①101~106 `via=rule` ②107(미상+Haiku 성공) 갱신 뒤 `via=haiku` ③108(미상+Haiku 실패) `via=unknown` ④옛 행 픽스처(via 키 없는 줄을 큐 파일에 직접 1줄) → show 출력·mark·report·archive 가 지금과 같고 그 행에 via 키가 «써지지 않음»(마이그레이션 0) ⑤`show` · `show --compact`(가짜 Haiku) 출력 바이트가 변경 전과 같음(같은 입력으로 전·후 비교).
4. RESULT 에 jq 셈 한 줄과 시험 큐에서 뽑은 예시 출력.
5. 설치 대상(랜딩 뒤 master cp · 나노는 쓰기 0): `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py`.

커밋은 자기 브랜치, **push 금지**. **금지**: 옛 행 일괄 수정 · show/compact 표시 변경 · 분류 규칙·Haiku 프롬프트 변경 · mark/report 강제 · 라이브 `.fable-team` 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_inbox.sh` rc=0(기존 + ①~⑤) · `tests/harness/test_kit_bin_sync.sh` PASS · 사본 cmp · `python3 -m py_compile` 2파일.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `.fable-team/bin` cp(ft-inbox.py) + cmp · 다음 쪽지 1건 적재 뒤 큐 행에 via 실재 확인.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 03f6fd39cd50901644c8fc6fafa288d4817e3b6d (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 461 · master #63739).
- 정본 영향 없음: 하네스 인박스 도구 행 필드·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 18:15 — 대기→진행 · 좌석 byz-harness-nano-v461-inbox-row-via#0
세트: c1c262a0c2113d2864bbe6fa63b7fcf87df03ce1 · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0
- 2026-10-08 18:32 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§70
