# r546 증거 — 실행 전 Bash 훅 4 의 조각내기·env 분해 사본 → 공용 모듈 1 (구조 커밋 · 동작 변경 0)

카드: `design/harness/indices/진행/r546-hook-cmd-split-shared-module.md` · 팩 브랜치 `nano/r546-hook-cmd-split-shared-module` · 1.1.101 · base = origin/main `f2d53cfd`

| 파일 | 무엇 |
|---|---|
| `after-test_hook_cmd_split_shared_r546.sh.txt` → `after-test_hook_cmd_split_shared_r546.txt` | 새 시험 전문 ⓐ~ⓕ **ALL PASS 19**(61초) |
| `before-5existing-tests.txt` | 바꾸기 **전**(origin/main 판) 기존 시험 5종 stdout 원문 — `test_tracked_bin_call_gate` 는 **이미 FAIL 25**(ⓖ live-entry 계열 · r546 이전부터 빨강) |
| `after-5existing-tests.txt` | 바꾼 **뒤** 같은 명령·같은 5종 원문 — FAIL 수 25 그대로(새 FAIL 0) |
| `mutation-negative-control.txt` | 변이 2종(모듈 숨김 · `segments` 구분자 1개 제거)에서 시험이 **빨개진다**(FAILED 9 · FAILED 2) → 초록이 «우연» 이 아님 |
| `ruff.txt` | `merge_cmd.py` E702 **2 → 6**(늘어난 4 = 복사한 `segments` 본문의 문체 · 카드가 «글자 그대로» 요구 → 손대지 않음 · 이 파일은 r230 이래 ruff-clean 아님) · 새 파일 2종(기록기·픽스처) All checks passed |

ⓐ 원문(4훅 × 30명령 × 자율 off/on = 240줄)은 `harness/tests/fixtures/r546_hook_cmd_split/base_verdicts.tsv` 한 벌만 둔다(사본 0) — 명령 묶음 = 같은 폴더 `commands.json` · 옛 함수 원문 = 같은 폴더 `base_functions.py`(ⓒⓓ 대조용). 재측정: `python3 harness/tests/lib/r546_verdicts.py harness/kit/hooks harness/kit/fable-team/templates/hooks`.

press(라이브 오디오) 0 — 이 카드는 훅·파이썬 축이고 실 settings·실 상태를 건드리지 않는다(픽스처 = 임시 HOME·임시 루트·«설치 꼴» 임시 훅 폴더). **press 필요 없음.**
설치·실사건(Bash 1회가 이 4훅을 지나 통과한 원문)은 master 집행 — 이 카드 범위 밖(설치 뒤 홈 `~/.claude/hooks/` cmp0 5).
