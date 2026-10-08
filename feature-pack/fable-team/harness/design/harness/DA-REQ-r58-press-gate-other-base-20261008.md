# DA 요청 — R58 press-gate ① 다른 줄기 제외 구현 검토 (arch#19 · 2026-10-08 · 구현 DA 1회 · bounded 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: 6-b(메인 오케 개선요청 — v65 master#150 R58 · press 차단).

## 고정 대상
- 커밋 `5623d4d5f62cefa1031be29041d53228da963e7b`(브랜치 `nano/r58-press-gate-other-base-nano` · 나노 변경 = `git diff 5623d4d5f6~1 5623d4d5f6` · 3파일 +138):
  `scripts/fable-team-bin/ft-press-gate.sh`(+14 · `_other_trunk()` + 루프 1줄) · 키트 사본 같은 바이트 · `tests/scripts/test_press_gate_other_base.py`(110줄 · ⓐ~ⓕ).
- 카드 `design/harness/indices/진행/r58-press-gate-other-base-nano.md`(구현 범위 1 · 사전검증 «구현 DA 1회 · Q1~Q3 고정»).
- 증거(arch#19 재현 · origin/main 73d9c25819 아카이브 + 나노 diff): 시험 12 passed(새 6 + 기존 `test_press_gate_set_membership.py` 6) · `test_kit_bin_sync.sh` ALL PASS · bash -n · 사본 cmp · ruff 0.
  실데이터: 원 차단 브랜치 `nano/m5-996-room-sse-unbounded-reconnect-impl`(info base=origin/main · base_sha b4ce4ab0a5) — b4ce4ab0a5 ⊂ HEAD(조상 OK) · b4ce4ab0a5 ⊄ feat/v6-realtime-live → ⊘ 제외 조건 충족. (워크트리는 이미 닫힘 — 게이트 실행은 허가 파일 발급 부작용 때문에 안 함.)

## 질문 (모두 «FEAT 랜딩 대상 미랜딩이 셈에서 빠지는 경로 0» 하나의 수락 표로 · 반례는 코드 줄 + 재현 입력)
- **Q1 선언 위조·오기**: `.worktree-info.json` 의 base/base_sha 가 틀렸을 때(손 편집 · 짧은 이름 · `origin/` 접두 · 다른 feat 계열) FEAT 기반 나노가 ⊘ 로 빠지는 경로가 있는가?
  ★arch 가 본 후보 1건★: FEAT 가 main 을 병합한 적이 있으면 «옛 main 커밋» 은 FEAT 기반 나노 HEAD 의 조상이다 → 그 나노 info 가 `base=origin/main · base_sha=<옛 main 커밋>` 으로 오기되면 ⒜ref 실재 ⒝조상 둘 다 통과해 ⊘. 보강안 = 제외 조건에 «base_sha 가 FEAT 의 조상이 아님» 추가(조상이면 FEAT..HEAD 에 main 쪽 커밋이 안 섞이므로 지금처럼 세어도 오탐이 없다 · 실데이터 b4ce4ab0a5 ⊄ feat 라 R58 해소 유지). 이 보강이 필요한가(필요하면 HOLD + 같은 나노 반송), 아니면 info 쓰기 주체가 `ft-nano-spawn.sh:184` 하나라 수락인가.
- **Q2 fail-closed**: info 없음 · JSON 깨짐 · 필드 없음 · ref 없음 · 조상 아님 · rebase/merge 뒤 base_sha 소실에서 모두 «지금처럼 센다»인가(python3 실패 `|| return 1` 포함).
- **Q3 기존 동작**: ②~⑧ · FAIL 코드 · 기존 시험 ⓐ~ⓓ·상대경로 시험 불변인가. `_other_trunk` 가 ⊘ 로 `continue` 할 때 세트 표시(`_set_member`)를 건너뛰는 것이 M7 «표시만» 계약과 충돌하는가.
- 범위 밖(새 요구 금지): LIVE_WT 좌석 이름 정규식(`ft-v65-temp-*`) · feat 워크트리 사본이 옛판인 문제 · ⑥⑦⑧.

## 판정문
`design/harness/DA-r58-press-gate-other-base-20261008.md` 에 r1 — Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 (arch#19 · 2026-10-08 · bounded — Q1 + 시험 ⓖⓗⓘ 만 · 새 요구 0 · 10분 + 정정 10분)
- 고정 대상: 커밋 `f475c7f91004b54c32630e8eb913bc8fe123cd73`(r1 `5623d4d5f6` 위 [fix] · 같은 브랜치 · 3파일 +57 −5) · 반송서 `.fable-team/state/drafts-r21/REJECT-r58-press-gate-other-base-r1.md`.
- 보강(arch 결정 · 반송서): ⊘ 조건에 ⒞ `git merge-base --is-ancestor "$sha" "$FEAT"` rc=1(조상 아님) 추가 · rc=0(base_sha ⊂ FEAT) = ⚠ 없이 지금처럼 셈 · 그 밖 rc(FEAT 조회 실패 등) = `⚠ base 선언 확인 실패` + 셈.
- 증거(arch#19 재현 · origin/main 73d9c25819 아카이브 + `git diff 5623d4d5f6~1 f475c7f910`): pytest 15 passed(other_base 9 + set_membership 6) · kit_sync ALL PASS · bash -n · 사본 cmp · ruff 0 · 시험 파일 158줄. ★arch 독립 변이★: ⒞ 판정을 «항상 조상 아님»으로 바꾸면 `test_old_main_ancestor_in_feat_is_counted`(ⓖ) · `test_short_sha_alias_does_not_bypass`(ⓗ) FAIL. 실데이터: 996 base_sha b4ce4ab0a5 vs feat/v6-realtime-live `--is-ancestor` rc=1 → ⊘ 유지(R58 해소 유지).
- **Q1r2**: ⒜ref 실재 ∧ ⒝base_sha ⊂ HEAD ∧ ⒞base_sha ⊄ FEAT(rc=1) 셋에서도 FEAT 랜딩 대상 미랜딩이 ⊘ 로 빠지는 오기·별칭 경로가 남는가(짧은 sha · 태그 · `origin/` 접두 · FEAT 조회 실패 rc 128) — 있으면 코드 줄 + 재현 입력.
- 범위 밖(r1 그대로): Q2·Q3(r1 APPROVE) · LIVE_WT 정규식 · ⑥⑦⑧.
- 판정문: `design/harness/DA-r58-press-gate-other-base-20261008.md` 에 r2 절 · 끝 줄 APPROVE 또는 HOLD.
