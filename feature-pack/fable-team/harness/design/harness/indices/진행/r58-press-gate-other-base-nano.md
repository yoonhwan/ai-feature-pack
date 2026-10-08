# 인덱스: R58 press-gate ① — 선언 base 가 FEAT 가 아닌 나노(origin/main 기반 등)는 미랜딩 셈에서 제외 (원장 R58 · v65 master#150 쪽지 65808 · press 차단 중)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R58(ops 9135eb1859 · 우선 높음 · 011 implant3 press 대기)
- 상태: 대기
- 선행: 없음(v423b DA r2 와 파일 겹침 0 · master 판단으로 먼저 가도 됨 — 쪽지 #65812)
- 시험 입력: 임시 git 저장소 + 가짜 tmux(PATH) + 가짜 seats.json(기존 `tests/scripts/test_press_gate_set_membership.py` 픽스처 그대로) — 실 저장소·tmux·seats.json 접촉 0
- 기준값(arch#19 실측 23:3x): 라이브 좌석 중 ① 대상 1개 = `ft-v65-temp-m5-996-room-sse-unbounded-reconnect-impl#0` → 워크트리 `.worktree-info.json` `"base":"origin/main","base_sha":"b4ce4ab0a5"` · `feat/v6-realtime-live..HEAD` 127커밋(= main 쪽 커밋 전부) · `origin/main..HEAD` 1커밋(나노 자기 수정) → ① 이 「미랜딩 제품 커밋 57」로 FAIL.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 6-b(메인 오케 개선요청 접수·처리 — v65 master#150 R58). 핵심 한 줄: ① 은 «FEAT 에 랜딩될 나노»만 센다 — 선언 base 가 FEAT 가 아니고 그 선언이 git 으로 확인되면 «다른 줄기»로 표시만 하고 셈에서 뺀다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`ft-press-gate.sh` ① 블록(origin/main `scripts/fable-team-bin/ft-press-gate.sh:105-157`)은 seats.json 의 살아 있는 `ft-v65-temp-*`·`ft-v65-(mr|le)-track` 좌석 워크트리마다 `git log "$FEAT"..HEAD -- worker shared gateway clients`(테스트 제외)를 미랜딩 후보로 센다. 이 계산은 «모든 나노가 FEAT 에서 갈라졌다»를 전제한다. 그런데 `ft-nano-spawn.sh --base origin/main`(main PR 랜딩 대상 · `ft-nano-spawn.sh:133-139·184` 가 `.worktree-info.json` 에 `base`·`base_sha` 를 기록)으로 만든 나노는 FEAT 에 없는 main 커밋 전체가 `FEAT..HEAD` 에 섞여, 자기 수정 1커밋인데도 수십 건 미랜딩으로 잡혀 feat press 전체를 막는다. 이 나노는 FEAT 로 랜딩되지 않으므로 FEAT press 세트와 무관하다. R58 의 다른 후보 「`_set_member` ⊘ 이면 제외」는 쓰지 않는다 — 세트 소속은 M7 카드(`design/v65/indices/완성/M7-press-gate-unlanded-nano-set-membership-display.md` · 오빠 HIL #3)가 «표시만 · 차단 기준 불변»으로 닫은 것이고, main 기반 나노는 `FEAT...HEAD` 3점 diff 에도 main 쪽 변경이 섞여 ⊕ 로 오판된다(근거가 같은 결함을 공유).

## 사전검증
- 소환: 아니오
- 면제 사유: 완화 조건이 하나(선언 base ≠ FEAT ∧ 선언이 git 으로 확인됨)이고 확인 실패·필드 없음은 지금처럼 센다(fail-closed 유지) · FAIL 코드·②~⑧ 변경 0 · 구현 DA 1회(bounded · Q 아래 3개)로 닫는다 — arch 서명 byz-harness-arch-claude#19
- 구현 DA 질문(고정): Q1 선언 base 를 위조·누락·오기(짧은 이름·`origin/` 접두)했을 때 FEAT 기반 나노가 셈에서 빠지는 경로 · Q2 base_sha 조상 확인이 실패하는 정상 나노(rebase·merge 뒤)가 막히는가(막히면 fail-closed 로 수락) · Q3 기존 시험 ⓐ~ⓓ·상대경로 시험이 그대로 PASS 인가.

## 조사 근거 (origin/main b4ce4ab0a5 · arch#19)
- `scripts/fable-team-bin/ft-press-gate.sh:108-117` LIVE_WT 계산 · `:134-157` 워크트리 루프(미랜딩 셈 `:148-155` · 세트 표시 `:156`) · `:158` 합산 판정. 파일 254줄(기존 초과 — 늘린 줄 수 RESULT 에 명시).
- `scripts/fable-team-bin/ft-nano-spawn.sh:133` BASE_BRANCH · `:135-139` INFO_BASE(기본 = FEAT 이름) · `:184` `.worktree-info.json` 쓰기.
- 라이브 워크트리 base 분포(23:3x): `feat/v6-realtime-live` 다수 · `feat/v65-732-redis-audio-ref` 2 · `origin/main` 1(#996).
- 키트 사본 `scripts/harness-install/fable-team/bin/ft-press-gate.sh`(같은 바이트 · `test_kit_bin_sync.sh`). ★feat 워크트리 `v6-realtime-live` 의 사본은 origin/main 과 다르다(⑦ 이전판) — 이 카드 범위 밖, 설치 경로는 master 가 정한다.★

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-press-gate.sh` ① 루프(`:134-157`) 안, `[ -e "$W/.git" ] || continue` 바로 뒤에 판정 1개(함수로 빼도 됨):
   - `$W/.worktree-info.json` 의 `base`·`base_sha` 를 읽는다(python3 json · 읽기 실패·필드 없음 = 지금처럼 센다).
   - `base` 가 `$FEAT` 또는 `origin/$FEAT` 이면 지금처럼 센다.
   - 그 밖이면 확인 2개 — ⒜`git -C "$W" rev-parse --verify -q "$base^{commit}"` 성공 ⒝`git -C "$W" merge-base --is-ancestor "$base_sha" HEAD` 성공. 둘 다 맞으면 `say "  ⊘" "다른 줄기($(basename "$W") · base=$base) — FEAT 랜딩 대상 아님 · ① 셈 제외"` 후 `continue`(세트 표시도 생략). 하나라도 틀리면 `say "  ⚠" "base 선언 확인 실패($(basename "$W") · base=$base) — FEAT 기준으로 센다"` 후 지금처럼 센다.
2. 키트 사본 `scripts/harness-install/fable-team/bin/ft-press-gate.sh` 같은 바이트.
3. 시험 `tests/scripts/test_press_gate_other_base.py`(새 파일 · 기존 `test_press_gate_set_membership.py` 의 `fake`·`_gate`·`_section1` 꼴 복사 대신 import 또는 동일 픽스처 · `ft_git_helpers` 사용):
   - ⓐ main 기반 나노(가짜 `main` 브랜치에서 worktree · FEAT 에 없는 worker 커밋 3 + 자기 worker 커밋 1 · info `base=main`) → `⊘ 다른 줄기` · `✓ 미랜딩 제품 커밋 0`.
   - ⓑ 같은 꼴인데 info `base=feat` → 지금처럼 `✗ 미랜딩 제품 커밋 4`, rc=1.
   - ⓒ info 없음 → 지금처럼 셈(✗) · ⓓ `base=main` 인데 base_sha 가 HEAD 조상 아님(가짜 sha) → `⚠ base 선언 확인 실패` + ✗.
   - ⓔ `base=origin/feat` 꼴(가짜 원격 ref) → FEAT 로 취급해 셈.
   - ⓕ 섞임: FEAT 나노(✗ 1) + main 나노(⊘) 동시 → `✗ 미랜딩 제품 커밋 1`(main 쪽 0 기여).
4. 기존 시험 그대로 PASS: `tests/scripts/test_press_gate_set_membership.py` · `tests/harness/test_kit_bin_sync.sh`.
커밋은 자기 브랜치, **push 금지**. **금지**: ②~⑧ 수정 · FAIL 코드 변경 · `ft-press-set-check.sh`·`ft-nano-spawn.sh` 수정 · 라이브 `.fable-team/` 쓰기 · press 실행.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_press_gate_other_base.py tests/scripts/test_press_gate_set_membership.py -q` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · `bash -n` · 사본 cmp · 새 시험 파일 200줄 이하 · gate 늘린 줄 수 RESULT 에 명시.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_press_gate_other_base.py -q rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 게이트 경로 반영(tester 가 부르는 사본 확인) · v65 master#150 에 「press 재시도 가능」 1줄 · #996 워크트리로 gate 1회 실측(⊘ 줄 + ✓ 미랜딩 0).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: dff01b4586eb92f0d1c7e177697789c807f2a8a5 (spawn 2026-10-08)
- 2026-10-08 23:3x — 대기/ 생성 (byz-harness-arch-claude#19 · 원장 R58 · master#19 쪽지 #65812 · 기준값 실측 위).
- 정본 영향 없음: 하네스 게이트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 23:30 — 대기→진행 · 좌석 byz-harness-nano-r58-press-gate-other-base-nano#0
- 2026-10-08 23:5x — 완료 증거(arch r3 독립 재현·서명 · DA 2 HOLD 종료): 세트: f5dc9fb6e3ad9670ddd41cc80908d11a1ec2eaed · 시험: python3 -m pytest tests/scripts/test_press_gate_other_base.py -q rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 press 게이트 셸·시험만 — docs/architect 제품 정본 변경 없음.
