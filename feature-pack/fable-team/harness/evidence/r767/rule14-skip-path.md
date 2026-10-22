# r767 — 카드 사전검증 «소환: 규칙14» 길 증거 (r1 · r2 고침 누적)
좌석: byz-harness-nano-r767-preverify-rule14-skip-path#0 · 2026-10-23 · 가지 nano/r767-preverify-rule14-skip-path(구 c86ee639 위 1커밋)
고침 3: ⓐ 보류 횟수 = «라운드 수»(「DA:」 줄 전부 · 서로 다른 경로 ≥2 · 내용 다름 cmp · 각 파일 마지막 판정 HOLD) ⓑ 원장 판정 N 줄 «내용» = (규칙|룰) ?14 + 카드 id(파일 이름 첫 조각) ⓒ 「합본 DA⑥」 줄에 생략|없음|면제|불요 = REJECT


## r2 (DA⑥ r2 HOLD → 결정 A) 고침 3
- 생략 낱말은 «붙어 있을 때만»: `합본 DA⑥[[:space:]」:—-]*(생략|없음|면제|불요)` — 「합본 DA⑥ — 잔여 HOLD 없음 확인」 은 통과
- 원장 대조 = «같은 줄» 에 (규칙|룰) ?14 **와** 카드 id 경계 `(^|[^[:alnum:]])<id>([^[:alnum:]]|$)` (대소문자 무시) 둘 다
- INFO 끝에 1구 « · DA: 줄 N개 = 라운드 N 으로 셈(원문·요약 중복 금지)»

### r2 반례 4 — 변이 없음(기준) vs 변이 4종 (원문)
```
### 기준(변이 없음) — 완료 조건 「합본 DA⑥ — 잔여 HOLD 없음 확인」 은 통과해야 한다
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r767-a2.md (ledger=design/LEDGER.md)
rc=0

### 변이 1 — 붙은 낱말 검사를 «줄 전체» 로
REJECT T/r767-a2.md (ledger=design/LEDGER.md)
  - 사전검증: 규칙 14 불성립 — 합본 DA⑥ 를 생략하는 꼴 — 합본 DA⑥ 는 필수다
rc=1

### 변이 2 — 「규칙 14」 검사만 삭제 (id 만 있는 원장 줄)
INFO 사전검증: 규칙 14 · 판정 7007 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/e1-d.md (ledger=design/LEDGER.md)
rc=0

### 변이 3 — id 경계 → 부분 문자열 (r76 카드 vs r767 줄)
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r76-b.md (ledger=design/LEDGER.md)
rc=0

### 변이 4 — 같은 줄 조건 해제(|| continue 삭제, 원장 2파일에 번호가 갈린 꼴)
INFO 사전검증: 규칙 14 · 판정 7006 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r767-c2.md (ledger=design/LEDGER.md)
rc=0
```

### r1 (DA⑥ r1 HOLD) 고침 — 라운드 셈 · 원장 내용 · 생략 거절 (기준선)
```
### ⓐ' 구판(r1 전 c86ee639 · 낱말 셈) — 라운드 1개 카드가 «통과해 버린다»
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수
OK T/r767-a.md (ledger=design/LEDGER.md)
rc=0

### ⓐ' 신판 — 같은 카드
REJECT T/r767-a.md (ledger=design/LEDGER.md)
  - 사전검증: 규칙 14 불성립 — 규칙 14 는 보류 2회부터 — 라운드별 판정문을 「DA:」 줄로 각각 적는다 (지금 1개)
rc=1

### ⓑ' 신판 — DA: 2줄(r1·r2)
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r767-b.md (ledger=design/LEDGER.md)
rc=0

### 변이 1 — 라운드 셈을 낱말 셈으로 되돌림 → ⓐ' 카드
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 1개 = 라운드 1 으로 셈(원문·요약 중복 금지)
OK T/r767-a.md (ledger=design/LEDGER.md)
rc=0

### 변이 2 — 원장 줄 «규칙 14 + 카드 id» 검사 삭제 → ⓔ' 카드(판정 9001)
INFO 사전검증: 규칙 14 · 판정 9001 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r767-e.md (ledger=design/LEDGER.md)
rc=0

### 변이 3 — 「합본 DA⑥ 생략」 낱말 검사 삭제 → ⓗ' 카드
INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)
OK T/r767-h.md (ledger=design/LEDGER.md)
rc=0

### 신판 — ⓗ' 카드(변이 없으면 REJECT)
REJECT T/r767-h.md (ledger=design/LEDGER.md)
  - 사전검증: 규칙 14 불성립 — 합본 DA⑥ 를 생략하는 꼴 — 합본 DA⑥ 는 필수다
rc=1
```

### 시험 전문 — tests/test_index_lint_rule14.sh (r1 ⓐ'~ⓘ' + r2 ⓐ~ⓓ · 35 PASS)
```
PASS bash -n
PASS ⓐ' 라운드 1개(낱말 2회) REJECT
PASS ⓑ' DA 줄 2개(r1·r2 · 각 마지막 HOLD) → OK
PASS ⓑ' INFO 줄 바이트 동일
PASS ⓒ' 같은 경로 2줄 REJECT
PASS ⓓ' 내용 같은 2파일 REJECT
PASS ⓔ' 원장 줄에 「규칙 14」 없음 REJECT
PASS ⓕ' 원장 줄에 카드 id 없음 REJECT
PASS ⓖ' 원장 줄에 «규칙 14» + 카드 id 둘 다 → OK
PASS ⓗ' 합본 DA⑥ 생략 REJECT
PASS r2ⓐ 「합본 DA⑥ — 잔여 HOLD 없음 확인」 통과
PASS r2ⓐ 「합본 DA⑥: 불요」 REJECT
PASS r2ⓑ r76 카드 + 원장 「규칙 14 … r767」 → REJECT(경계)
PASS r2ⓑ e1 카드 + 원장 「규칙 14 — e10」 → REJECT
PASS r2ⓑ e1 카드 + 원장 「규칙 14 — we1-export」 → REJECT
PASS r2ⓑ e1 카드 + 원장 「규칙 14 — E1 재설계」 → 통과(대소문자 무시)
PASS r2ⓒ 같은 번호 2파일(규칙14 줄 + id 줄 따로) → REJECT
PASS r2ⓓ 원장 줄에 id 만 있고 「규칙 14」 없음 → REJECT
PASS ⓙ' 완료 조건 「합본 DA⑥」 없음 REJECT
PASS ⓙ' 원장에 판정 9999 없음 REJECT
PASS ⓙ' 마지막 DA 줄이 APPROVE REJECT
PASS ⓙ' 구판(origin/main)은 규칙14 카드를 REJECT(빨강)
PASS ⓙ' 「소환: 예」 APPROVE 출력 바이트 동일
PASS ⓙ' 「소환: 아니오」 면제 출력 바이트 동일
PASS ⓙ' HOLD 조건부 예외 출력 바이트 동일
PASS ⓘ' 라운드 셈→낱말 셈 되돌림 → ⓐ' 가 통과해 버린다(변이 검출)
PASS ⓘ' 원장 줄 내용 검사 삭제 → ⓔ' 가 통과해 버린다(변이 검출)
PASS ⓘ' 생략 낱말 검사 삭제 → ⓗ' 가 통과해 버린다(변이 검출)
PASS r2ⓓ 「규칙 14」 검사만 삭제 → id 만 있는 원장 줄이 통과해 버린다
PASS r2ⓓ id 경계→부분 문자열 → r76 카드가 r767 줄에 통과해 버린다
PASS r2ⓓ 같은 줄 조건 해제(|| continue 삭제) → ⓒ 가 통과해 버린다
PASS r2ⓓ 붙은 낱말→줄 전체 → 「잔여 HOLD 없음 확인」 이 오거절된다
PASS 격리: 판정이 임시 리포 안에서만 돈다
PASS 격리: origin/main ref 없음 → 원장 확인 불가 REJECT(로컬 파일로 새지 않는다)
PASS 격리: ref 복구 → 다시 OK
fail=0
rc=0
```

### 회귀 4종 (env -u TMUX -u TMUX_PANE)
```
== test_index_lint.sh rc=0 · fail=0
== test_index_lint_conditional.sh rc=0 · fail=0
== test_verdict_row.sh rc=0 · REAL-STATE-GUARD PASS 실 상태 그대로 roots=repo:/Users/yoonhwan/Project/ai-feature-pack,comm:/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm files=0
== test_proposal_card.sh rc=0 · ALL PASS
```

### 한계 (카드에 적음 · 손대지 않음)
- 같은 r1 의 원문·요약을 DA: 2줄로 적으면 2라운드로 셈 — 기계로 못 가림 · 합본 DA⑥ 가 받침.
- 닫기 게이트(ft-index-move · ft_da_hold_gate.py)의 «규칙14 → 합본 DA⑥» 전용 강제는 미구현(범위 밖).
- skill/scripts/ft-index-lint.sh 사본은 구판(68줄) — 이번에도 범위 밖.
