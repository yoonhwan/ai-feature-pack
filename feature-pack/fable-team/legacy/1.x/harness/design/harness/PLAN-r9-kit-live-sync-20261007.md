# PLAN — R9 키트·라이브 동기 (arch#7 안 · 2026-10-07)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 원문 1 C(배포·반영 — 랜딩된 하네스 변경을 키트·설치본에 반영). R15 H 카드의 선행 조건.

## 결론
**단독 cp 2파일로 간다(승인).** 0.4 일괄 동기에 묶지 않는다.

## 실측 (origin/main 기준 · 이 세션)
| 파일 | 추적본 scripts/fable-team-bin | 키트 scripts/harness-install/fable-team/bin | 라이브 v6-realtime-live/.fable-team/bin |
|---|---|---|---|
| ft-press-gate.sh | 57a36d6a (834 ⑥ 기준선 포함) | 1fe22000 (옛) | 1fe22000 (옛 · 10-03) |
| ft-press-baseline-check.sh | 7b107146 | 없음 | 없음 |
| ft-press-set-check.sh (baseline-check 의존) | 6d971146 | 6d971146 | 6d971146 |

- test_kit_bin_sync.sh (origin/main 사본으로 실행) = FAILED 1 — 어긋남은 위 2파일뿐(추적본→키트 방향).
- 라이브는 이 2파일 말고도 넓게 옛것이다: ft-nano-close·ft-nano-spawn·ft-nano-slots·ft-nano-evidence-check·ft-role-spawn 바이트 다름(라이브 10-02~10-03판) + 키트에만 있는 파일 약 25개. → 이것은 R9 가 아니다(아래 「별건」).

## 왜 단독인가 (이유 3줄)
1. R9 범위는 2파일이고 의존(ft-press-set-check.sh)은 세 곳 모두 같다 — 2파일 cp 로 닫힌다.
2. 라이브 일괄 동기는 v65 좌석이 쓰는 nano-close·spawn 동작을 한꺼번에 바꾼다 — press·나노가 도는 중에 섞이면 세트 섞임(10-02 사고) 위험. 별도 단위로 떼야 한다.
3. R15 H 카드는 키트·라이브의 press-gate 가 ⑥ 을 가진 상태를 전제로 한다 — 기다릴 이유가 없다.

## 집행 순서 (master)
1. **키트 (리포)** — origin/main 에서 새 브랜치:
   `cp -p scripts/fable-team-bin/ft-press-gate.sh scripts/fable-team-bin/ft-press-baseline-check.sh scripts/harness-install/fable-team/bin/`
   → `cmp` 2회 → `bash tests/harness/test_kit_bin_sync.sh` = ALL PASS → 커밋 `[chore] 키트 bin 동기 — press-gate ⑥·baseline-check (R9)` → PR → 랜딩.
2. **라이브 설치** — ★v65 master 에 1줄 통지 먼저★(⑥ 이 켜지면 FT_PRESS_CARD 없는 press 는 막힌다 = 834 설계 의도지만, 라이브에 «켜는 순간» 은 v65 소유자가 알아야 한다). press 진행 중이 아님을 확인(realtime_multi_e2e 프로세스 0 · 이 안 작성 시점 0)한 뒤:
   `L=…/v6-realtime-live/.fable-team/bin; cp -p $L/ft-press-gate.sh $L/ft-press-gate.sh.bak-r9-1007; cp -p <추적본>/ft-press-gate.sh <추적본>/ft-press-baseline-check.sh $L/` → `cmp` 2회.
3. **확인** — `FT_PRESS_GATE_SELFTEST=1 FT_PRESS_CARD=<v65 진행 카드 하나> bash $L/ft-press-gate.sh` → exit 3(PASS) 또는 1(BLOCK, 기준선 칸 미기재) — 둘 다 «⑥ 이 돈다» 증거. exit 0 이 나오면 실패(⑥ 미적용).
4. 되돌림: 키트 = PR revert · 라이브 = `cp -p $L/ft-press-gate.sh.bak-r9-1007 $L/ft-press-gate.sh; rm $L/ft-press-baseline-check.sh`(rm 은 훅에 막히면 governance §7 경로).

## 닫는 증거
키트 랜딩 sha + test_kit_bin_sync ALL PASS 1줄 + 라이브 cmp 2회 일치 + selftest exit 코드 1줄.

## 별건 (R9 아님 · 원장 새 행 후보)
- **라이브 FT_BIN 전반 옛판** — 5개 바이트 다름 + 키트 전용 약 25개 없음. harness-env·feature-env 의 FT_BIN 이 이 디렉터리를 가리킨다. 어느 좌석이 라이브 경로로 부르는지(호출 경로 실측)부터 → 일괄 동기 단위(인계문 열린 일 6 「bin 폴더 합치기」와 같은 줄기). 완성 전/후: 하네스 골 «완성 전»(원문 1 C 배포·반영).
