# 인덱스: spawn ②-0 이 cherry 게이트에 --base sha 대신 «랜딩 브랜치»를 넘긴다 (R71 · v65 master#156 #70298 · arch#25)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R71(v65 master#156 쪽지 #70298 · 하네스 master#24 #70302) · ★R70 설치 뒤에도 v65 나노 spawn 차단 중(급함)★
- 상태: 대기
- 선행: R70 랜딩·설치(완료 — 설치본 게이트 sha256 앞12 `d0b27c9ca663`)
- 시험 입력: 임시 git 저장소(가짜 feat 브랜치 · 그 위 commit sha · 옛 nano 브랜치) + 인자 기록 스텁 게이트 — 실 v65 브랜치·루트 `.fable-team/` 쓰기 0
- 기준값(arch#25 실측 · 실 v65 저장소 읽기 전용): `ft-nano-spawn.sh <카드> --base 4c19fa1ffe --recheck <판정문>` → `REJECT cherry 게이트 — 브랜치 없음: 4c19fa1ffe`. 원인 = ②-0 게이트 호출(origin/main 155행)이 `$BASE_BRANCH`(= `--base` 값 그대로 · 133행)를 넘김 → 게이트 49행은 feat 를 `refs/heads/`·`refs/remotes/` 만 받음 → sha 는 «브랜치 없음». `--override` 도 그 검사보다 뒤라 못 넘음(실측: `--override probe` 도 같은 REJECT · 원장 기록 0). 같은 게이트에 `feat/v6-realtime-live` 를 주면 PASS(`content_identical_to_feat_head`). `4c19fa1ffe` 는 commit 이고 feat 의 조상. spawn 은 R42 분기(origin/main 136–141행)로 sha 일 때 `INFO_BASE` = `FT_NANO_FEAT` 또는 호출 워크트리 브랜치(v65 = `feat/v6-realtime-live`)를 이미 구해 둔다 — ②-0 만 그 값을 안 씀.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R71 · 값 = 메인 오케 개선요청(v65 master#156 #70298) · 반영 sha = 이 카드 랜딩 sha.
골의 축: B(메인 오케 개선요청 접수) + C(도구 업그레이드·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
v65 는 나노를 열 때 `--base <sha>` 로 기준점을 고정한다(재대조 판정문이 그 sha 를 적고, feat 브랜치는 계속 움직이기 때문). spawn 은 이미 «sha 로 받았으면 랜딩 브랜치 이름을 따로 구해 두는» 분기(R42 · `INFO_BASE`)를 갖고 있고 닫기 게이트도 그 랜딩 브랜치로 비교한다. 그런데 옛 나노 브랜치를 판정하는 ②-0 만 sha 를 그대로 cherry 게이트에 넘겨서, 게이트가 «브랜치 없음» 으로 즉시 막는다(사람 우회 `--override` 도 그 앞에서 막힘). 질문이 «옛 브랜치 코드가 랜딩 브랜치에 들어왔나» 이므로 비교 대상은 sha 가 아니라 랜딩 브랜치(최신)가 맞다 — ②-0 게이트 호출의 첫 인자를 `$INFO_BASE` 로 바꾼다. `--base` 가 브랜치이거나 없을 때는 `INFO_BASE == BASE_BRANCH` 라 동작이 바이트 단위로 같다.

## 사전검증
- 소환: 아니오 · 면제: 인자 1개를 이미 계산된 랜딩 브랜치 값으로 바꿈(R42 와 같은 기준 · 닫기 게이트와 같은 비교 대상) · `--base` 가 브랜치·없음이면 무변경 · 게이트 코드 변경 0 — arch 서명 byz-harness-arch-claude#25
- 조사 근거: `scripts/fable-team-bin/ft-nano-spawn.sh:133` · `scripts/fable-team-bin/ft-nano-spawn.sh:145` · `scripts/fable-team-bin/ft-nano-cherry-gate.sh:49`
- 7초 룰 점검(판정 666): 외부 호출 0(로컬 git 만) — 해당 없음.

## 설계 (닫힌 목록)
1. `ft-nano-spawn.sh` ②-0 게이트 호출의 첫 인자 `"$BASE_BRANCH"` → `"$INFO_BASE"`(한 단어). 바로 위 주석에 «R71: --base 가 sha 면 게이트는 랜딩 브랜치(INFO_BASE · R42)와 비교» 1줄.
2. `INFO_BASE` 가 ②-0 보다 앞에서 정해지는지 확인(origin/main 기준 137–141행 < 155행) — 순서 변경 0.
3. 워크트리 생성(`worktree add … "$BASE_BRANCH"`)·`base_sha`·PLAN 줄은 그대로 sha 를 쓴다(기준점 고정은 유지).
4. 두 추적 사본 바이트 동일 · 게이트 무변경.

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `scripts/fable-team-bin/ft-nano-spawn.sh` · `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh`. 새 시험: tests/harness/test_spawn_gate_landing_branch.sh.
시험(임시 저장소 · spawn 의 ②-0 게이트 호출 줄을 인자 기록 스텁 게이트로 실행 — R70 arch 재현 방식 · 또는 나노 판단의 최소 경로): ①`--base <sha>`(feat 의 조상 commit) + `FT_NANO_FEAT` 없음 → 게이트 첫 인자 = 호출 워크트리 브랜치 ②`--base <sha>` + `FT_NANO_FEAT=feat/x` → 첫 인자 `feat/x` ③`--base <브랜치>` → 첫 인자 = 그 브랜치(현행 동일) ④`--base` 없음 → 첫 인자 = 워크트리 브랜치(현행 동일) ⑤`--cherry-override` 와 함께 → `--override <사유>` 여전히 전달 ⑥실 게이트(스텁 아님)로 ①의 임시 저장소에서 «브랜치 없음» 0 · 내용 판정까지 감 ⑦기존 `bash tests/harness/test_cherry_gate_identical_head.sh` · `bash tests/harness/test_cherry_gate_squash.sh` 그대로 PASS ⑧두 사본 `cmp` · `bash -n`.
커밋은 자기 브랜치, **push 금지**. **금지**: 실 v65 브랜치·카드에 spawn 실행(`--dry-run` 포함 — 카드 base_sha 를 써넣는다) · 루트·`.worktrees/v6-realtime-live/.fable-team/` 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 기존 cherry 시험 2종 rc=0 · arch 독립 재현(실 v65 저장소 읽기 전용: 새 spawn 의 ②-0 호출 줄을 실 게이트로 → PASS).
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_spawn_gate_landing_branch.sh rc=0 · bash tests/harness/test_cherry_gate_identical_head.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#25 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → CI 확인 → 병합(별 명령) → 설치본 `.worktrees/v6-realtime-live/.fable-team/bin/ft-nano-spawn.sh` cp 전 sha256 앞12 `8465896b0868`(R70 설치값 · arch#25 실측 · 다르면 cp 0 · arch 반송) → cp + cmp → v65 master(현역)에 «spawn --base <sha> 재시도 가능» 1줄 → 요청 원장 R71 닫힘.

## 상태
- base_sha: 02b45e8832c72b24590926b6a1397db2de629f6a (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#25 · R71 · 원인 실측: ②-0 만 R42 랜딩 브랜치 값을 안 쓰고 sha 를 게이트에 넘김).
- 정본 영향: 하네스 키트 spawn 2 · 설치본 1 · 홈 정본 0.
- 2026-10-09 19:46 — 대기→진행 · 좌석 byz-harness-nano-r71-spawn-gate-landing-branch#0

## 결과
- 세트: 51b31f5dfd6f27f52e3a867973f0ed5245740abd · 시험: bash tests/harness/test_spawn_gate_landing_branch.sh rc=0 · bash tests/harness/test_cherry_gate_identical_head.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 하네스 키트 spawn 사본 1쌍·시험만 (arch 독립 재현 #70322 · 판정서 §116).
- 2026-10-09 19:52 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§116
