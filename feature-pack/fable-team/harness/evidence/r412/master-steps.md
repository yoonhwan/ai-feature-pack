# r412 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r412-scope-classify-forbid-old-install-p` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `9aaef214`(origin/main · 1.1.11 · r411 #69 착지 뒤). 변경 = `harness/bin/autonomy_scope_classify.py`·`harness/kit/fable-team/bin/autonomy_scope_classify.py` 같은 1줄(cmp 0) + 이 증거 폴더. 시험 본문 변경 0.
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(r410 규약) — 착지 순서대로 다음 번호를 master 가 붙인다. 문안 = 아래 «CHANGES 절».
2. 되돌림 준비(설치 전): 라이브 bin `autonomy_scope_classify.py` `cp -p … .bak-r412`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → `cmp <키트>/bin/autonomy_scope_classify.py <LIVE_BIN>/autonomy_scope_classify.py` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 닫는 증거(실사건): r411 code 종류 실사건(오빠 `approve-scope --classes …,code` 1줄) «전» 설치 완료 줄 1개 + 라이브 분류기로
   `path_reason("scripts/harness-install/fable-team/bin/ft-x.sh")` → `전역 규칙 경로: …`(지금 라이브는 `None`).

## CHANGES 절 (착지 번호를 붙여 머리에)
## 2026-10-19 — 범위 분류기 «전역 규칙» 이 옛 라이브 설치 사본 경로 `scripts/harness-install/` 도 FORBID 한다 (1.1.N)

카드 r412 · arch#95 재현 · 판정 1395(떨어지는 시험 = 고침 단위). 팩 이전 때 «전역 규칙» 정규식에 새 경로 `harness/kit/` 만 넣고 옛 경로가 빠져, 머리 주석(「옛·새 경로 어느 쪽이든 맞으면 FORBID」)과 어긋났고 팩 시험 절 «scripts/harness-install/ → FORBID» 가 base 부터 FAIL 1(`rc=0 out=CLASS code`)이었습니다. r411 이 code 종류를 연 뒤에는 옛 설치 경로를 다시 들여오는 세트가 code 로 대리 승인될 수 있어 실사건 전에 막습니다.

- **`autonomy_scope_classify.py`**(bin·kit 짝 cmp0): `PATH_RULES` «전역 규칙» 같은 줄에 `|(^|/)scripts/harness-install/` 1 토큰 · 줄 수 200 불변. `src/x.py` → code 그대로(오탐 0).
- **시험**: 본문 변경 0 — `test_autonomy_scope_classify.sh` ALL PASS rc0 · `test_autonomy_scope.sh` fail=0 rc0. 증거 `harness/evidence/r412/test.txt`.

## 관측
- 고치기 전(같은 base 9aaef214): `test_autonomy_scope_classify.sh` → `FAIL scripts/harness-install/ → FORBID :: rc=0 out=CLASS code · FAILED 1` rc=1 (arch#95 재현과 같음).
- 고친 뒤: ALL PASS rc=0 — test.txt 원문.
