# r908 — 자율 범위 상한 30 → 100 (Issue BYZ #3408)

- 지시: 오빠 «scope max 50으로 키워» → 정정 «100으로 늘려두라해» (master#110 #165657 · planner 165649)
- 바뀐 것: `harness/bin/ft-autonomy-scope.sh:32` scope_validate `--max` 상한 `-le 30` → `-le 100` + 문구 «1~100» · 짝 사본 `kit/fable-team/bin/ft-autonomy-scope.sh` cmp0
- `--daily`·`--code-max` 는 «1~max» 규칙 그대로 → max 상한 100 을 따라 자동으로 1~100 (규칙 변경 0)
- 레벨 기본값(full/mid 의 max=30) 은 범위 밖 — 그대로

## 시험 (base 팩 origin/main 99635196)

| 묶음 | rc | PASS / FAIL |
|---|---|---|
| tests/test_autonomy_scope.sh | 0 | 139 / 0 |
| tests/test_autonomy_scope_pack.sh | 0 | 13 / 0 |
| tests/test_autonomy_scope_plain3_r658.sh | 0 | 27 / 0 |
| tests/test_autonomy_level.sh | 0 | 65 / 0 |
| tests/test_autonomy_scope_classify.sh | 1 | 67 / 6 — ★base 99635196 에서도 같은 6줄(착지 «대상 리포 remote URL 해석 실패»)★ · 상한과 무관한 기존 실패 |

새 칸(test_autonomy_scope.sh): ⓐ `--max 100` 통과(GR 줄 max=100) · `--daily 100` 통과 · `--code-max 100` 통과(log codemax=100) · ⓑ `--max 101` REJECT rc2 «1~100» · `--max 100 --daily 101` REJECT · `--max 100 --code-max 101` REJECT.
test_autonomy_level.sh ⓕ «--max 40 → REJECT» 칸은 상한이 올라 통과하게 되므로 `--max 101` 로 바꿈.

## 변이

| 변이 | test_autonomy_scope.sh |
|---|---|
| `-le 30` (옛 상한) | rc1 · FAIL 5 (ⓐ 3칸 + ⓑ daily·code-max 2칸) |
| `-le 101` (한 칸 넘침) | rc1 · FAIL 6 (ⓑ --max 101 통과 + 뒤 칸 연쇄) |

원복 후 bin·kit cmp0.

## r2 — DA⑥ r1 HOLD 1 고침: 산술 넘침 (2026-10-25)

- 결함: `scope_validate` 가 `^[0-9]+$` 로 받은 수를 **곧바로** `$((10#$mx))` 로 산술 → 64bit 넘침. `--max 18446744073709551716`(= 2^64 + 100) 이 **100 이 되어 통과**.
- 고침(1곳 · 세 숫자): `bin/ft-autonomy-scope.sh:31` 에 `NUM_RE='^0*[0-9]{1,3}$'` 를 두고 `--max`(`:32`)·`--daily`(`:34`)·`--code-max`(`:44`) 의 정규식을 그 상수로 교체 — **산술 «전»** 자릿수 거름(앞자리 0 허용「0100=100」 · 의미 있는 3자리 초과 거절). 비교 규칙(1~100 / 1~max)은 그대로. 짝 사본 `kit/fable-team/bin/ft-autonomy-scope.sh` cmp0.
- `bin/ft-autonomy-level.sh:23` 은 같은 `scope_validate` 를 부르므로 레벨 경로도 함께 막힌다(별도 수정 0).
- 새 칸(ⓓ 5): `--max 18446744073709551716` REJECT rc2 · `--max 100 --daily 18446744073709551716` REJECT · `--code-max 18446744073709551716` REJECT · `--max 0100` 통과(100) · `--max 1000` REJECT.
- 시험 재실행(base 99635196): `test_autonomy_scope.sh` **144/0 rc0** · `_pack` 13/0 · `_plain3_r658` 27/0 · `_level` 65/0 — ALL PASS.
- 변이: `NUM_RE` 를 `^[0-9]+$` 로 되돌리면 **rc1 · FAIL 3**(ⓓ 큰 수 3칸: max·daily·code-max) — 자릿수 거름이 그 세 칸을 실제로 잡는다(같은 변이에서 «설치 미러 cmp0» 칸도 bin 만 고쳤으므로 함께 빨강 = 기대된 부수). 원복 후 bin·kit cmp0.
- 범위 밖 관측(손대지 않음): `cmd_approve_scope` 의 `--for` 는 `^([0-9]+)h$` 뒤 곧바로 `10#` 산술(`:157`)이라 같은 계열 넘침 경로가 있다(예: `18446744073709551617h` → 1h 로 통과). DA⑥ 지시가 «세 숫자» 로 좁혀 와서 고치지 않았다 — 판단은 arch/DA 소관.
