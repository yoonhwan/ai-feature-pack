# r748 증거 — 자율 범위 몫(총·하루): docs·ff 는 `counted=0` 칸이 있을 때만 셈 0 (그 밖은 셈 1 = 실패 닫힘)

정본: `harness/kit/fable-team/bin/ft-autonomy-scope.sh` (+ `harness/bin` 짝 사본 · cmp0)
      `harness/{bin,kit/fable-team/bin}/ft-autonomy.sh` — `SCOPE_USE_RE`: `counted=0` 만 허용 · **종류 docs·ff 뒤에만**
시험: `tests/test_autonomy_scope_code_only_r748.sh` (새 파일 · **분류기 stub 0 · 실제 분류기·실 git**)

## 셈 규칙 (카드 §구현 범위 1·2·2b + DA⑥ r1 처방 1 + **DA⑥ r2 · master 결정 A(기본 뒤집기)**)

| scope-use 줄 | 셈 | 비고 |
|---|---|---|
| 종류 `code` | 1 | `codemax` 도 깎는다(진짜 경계 · R411 카드 시험 세트) |
| 끝 칸 `learned=<키>` | 1 | 학습표 통과분(원래 FORBID → docs) — `max·daily` 만, `codemax` 아님 |
| 종류 `docs`·`ff` + 끝 칸 **`counted=0`** | 0 | 작성기가 «바뀐 경로 전부 `.md` ∧ learned 아님» 일 때만 이 칸을 쓴다 |
| 종류 `docs`·`ff` + 칸 없음 (**r748 전 옛 줄 포함**) | 1 | 실패 닫힘 — 못 재거나 비-md 경로가 섞이면 칸이 없다 |
| 종류 `revert`·`equiv` | 0 | 종전 그대로 |

정규식(`SCOPE_USE_RE`): `counted=0` 은 **`docs`·`ff` 뒤에만** — `revert … counted=0` · `code … counted=0` · `docs … counted=1` 은 위변조(거절).
`approve-scope --repos` 생략 기본 = `byz,pack`(명시 `--repos byz` 는 byz · `repos=` 칸 없는 옛 승인 줄은 `byz` 그대로 = 소급 0).

## 파일

| 파일 | 무엇 |
|---|---|
| `00-red-first.txt` | ⓐ 빨강 먼저 — 19d7e279 판(고치기 전)으로 새 시험 = **20 FAIL** |
| `01-r748-tests.txt` | 새 시험 **47 PASS rc=0** (ⓐⓑⓒⓓⓔⓕⓖⓗⓘⓜⓟ · **ⓐ2 옛 줄 이어받기 · ⓓ2 정규식**) |
| `02-scope-tests.txt` | `test_autonomy_scope.sh` fail=0 |
| `03-pack-tests.txt` | `test_autonomy_scope_pack.sh` (ⓝⓞ + ⓟ 팩 manifest.json) fail=0 |
| `04-r560-tests.txt` | `test_r560_approval_equiv_base_and_hook.sh` fail=0 |
| `05-r658-tests.txt` | `test_autonomy_scope_plain3_r658.sh` fail=0 |
| `06-level-equiv.txt` | `test_autonomy_level.sh` · `test_autonomy_merge_equiv.sh` fail=0 (ⓕ 기존 시험 PASS) |
| `07-mutations.txt` | 변이 4종 전부 기대대로 FAIL — «칸 없음=셈 0»(옛 판) → ⓐ2·ⓟ / 정규식 종류 제한 삭제 → ⓓ2 / counted=0 칸 미기록 → ⓑ / code 셈 0 → ⓓ · 복구 cmp0 |
| `08-preexisting-baseline.txt` | 기존 실패 = 카드 전과 같은 값(core fail=3 · classify FAILED 5) |

## 새 시험 항목(처방 4)

- ⓐ2 옛 줄 이어받기: r748 전 꼴 `scope-use S1 <40hex> docs <ts>`(칸 없음) 1줄 + `max=1` → 다음 docs(.js = 셈 1) 승인 **거절**(몫 1 이미 씀) · status «정지: 건수 도달(1/1)»
- ⓑ 새 `.md` 전용 docs = `counted=0` 칸 · 셈 0 (scope-use 줄 바이트까지 확인)
- ⓒ `.js` docs = 칸 없음 · 셈 1
- ⓓ2 정규식: `revert … counted=0` · `code … counted=0` · `docs … counted=1` = 거절 / `docs … counted=0` · `ff … counted=0` = 허용 / 작성기가 쓴 줄도 위변조 아님

## 범위 밖(새 카드 r766 · 손대지 않음)

분류기 구멍(팀 폴더 실행 확장자 docs · 카드 이동 내용 · SQL 적용 기록 · revert 마지막 커밋 대조 · 팩 manifest.json·evidence docs).
