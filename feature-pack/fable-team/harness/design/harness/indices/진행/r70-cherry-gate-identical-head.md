# 인덱스: cherry 게이트 오탐 — tip 내용이 feat HEAD 와 같은 경로는 PASS · spawn 이 게이트 --override 를 넘긴다 (R70 · v65 arch#192 · arch#25)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R70(v65 arch#192 판정 · 쪽지 #70274 · 하네스 master#24 #70276) · ★v65 나노 spawn 차단 중(급함)★
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 git 저장소(가짜 feat·nano 브랜치)만 — 실 v65 브랜치·루트 `.fable-team/` 쓰기 0
- 기준값(arch#25 실측 · 재현 명령 = 요청자 판정문): `bash ft-nano-cherry-gate.sh feat/v6-realtime-live nano/m3-le-lecture-single-psid-v6-route-and-p --repo <v6-realtime-live>` → **REJECT** · ①merge-tree rc=1 — 충돌 경로는 ★design/ 카드 1개뿐★(`design/v65/indices/진행/M3-le-…-paused-lease.md`)인데 `conflict=1` 이면 design/ 밖 delta 검사(①)를 통째로 건너뜀 ②superseded 검사가 `gateway/main.py`(분기점·tip·feat HEAD 셋 다 blob `19c25b257` · 나노가 바꿨다 되돌림 · 순변경 0)를 «분기 뒤 feat 구간에 새 blob 없음» 으로 REJECT. 게이트·spawn 두 추적 사본 바이트 동일(gate `4d3330b20b0b` 181줄 · spawn `839ccdf23b99` 230줄) = 설치본 `.worktrees/v6-realtime-live/.fable-team/bin/` 과 같음.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R70 · 값 = 메인 오케 개선요청(v65 arch#192 판정 ⓐ·ⓒ) · 반영 sha = 이 카드 랜딩 sha.
골의 축: B(메인 오케 개선요청 접수) + C(도구 업그레이드·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
나노를 다시 열 때(`ft-nano-spawn.sh` ②-0) 같은 이름의 옛 나노 브랜치가 남아 있으면 cherry 게이트로 «그 브랜치 코드가 이미 feat 에 들어왔나» 를 본다. 지금 게이트는 «tip 의 내용이 분기 뒤 feat 쪽에서 새로 생긴 blob 으로 있나» 만 증거로 친다(DA 599 H1 — 분기 전 옛 내용으로 되돌린 브랜치를 통과시키지 않으려고). 그런데 나노가 한 파일을 바꿨다가 원래대로 되돌리면, 그 파일의 tip 내용은 feat HEAD 와 «똑같은데도» 분기 뒤 새 blob 이 아니라서 REJECT 된다. 같은 내용이면 머지해도 그 경로는 바뀌지 않으므로(3-way 에서 나노 쪽 = feat 쪽 → 결과 = feat HEAD) 잃을 코드가 없다. 그래서 «경로 P 의 tip (mode,blob) == feat HEAD 의 P (mode,blob)» 이면 그 경로를 통과로 센다. 더해서, 다음 오탐 때 하네스 수정을 기다리지 않도록 spawn 이 게이트의 기존 사람 우회(`--override "<사유>"` · 원장 1행 + ERROR 로그)를 넘길 인자 하나를 둔다.

## 사전검증
- 소환: 아니오 · 면제: 추가 조건은 «경로 내용이 feat HEAD 와 바이트 동일» 일 때만 PASS — 그 경로의 머지 결과 = feat HEAD(변경 0)가 정의상 성립해 새 거짓 PASS 경로 0 · DA 599 H1(옛 blob 롤백)은 tip ≠ feat HEAD 라 그대로 REJECT(회귀 시험으로 고정) · override 는 기존 게이트 경로 재사용(새 우회 0) — arch 서명 byz-harness-arch-claude#25
- 조사 근거: `scripts/fable-team-bin/ft-nano-cherry-gate.sh:87` · `scripts/fable-team-bin/ft-nano-cherry-gate.sh:106` · `scripts/fable-team-bin/ft-nano-cherry-gate.sh:130` · `scripts/fable-team-bin/ft-nano-spawn.sh:14` · `scripts/fable-team-bin/ft-nano-spawn.sh:145`
- 7초 룰 점검(판정 666): 외부 호출 0(로컬 git 만) — 해당 없음.

## 설계 (닫힌 목록)
1. 게이트 superseded 루프(경로 P · tip entry 있음 분기): 분기 뒤 새 blob 조회 «전에» `git ls-tree "$FEAT" -- "$P"` 의 (mode,blob) 이 tip 과 같으면 `nid` +1 · 다음 경로(로그 조회 0). 통과 조건 = `missing` 비었고 `nsup + nid > 0`. INFO 줄에 `feat HEAD 와 동일 ${nid}개` 를 붙이고, 통과 사유 토큰 = `nid>0 ∧ nsup=0` 이면 `content_identical_to_feat_head` · 둘 다 있으면 `content_landed_then_superseded+content_identical_to_feat_head`.
2. tip 에서 삭제된 경로·문서 경로(ndoc)·충돌 메시지·override·`--squashed-pr` 경로 동작 무변경. merge-tree «design/ 만 충돌» 시 ①을 살리는 개선은 하지 않는다(별 후보 — 1번으로 이번 오탐은 닫힘).
3. `ft-nano-spawn.sh`: 인자 `--cherry-override "<사유>"` 1개 — 값이 빈 문자열·공백뿐이면 exit 2. ②-0 게이트 호출에만 `--override "<사유>"` 를 붙이고, 원장 seat 칸이 발주자를 가리키도록 그 호출에 `FT_SEAT="$FROM"` 을 준다. 인자 없으면 호출 바이트 동일(현행 그대로). usage 2곳(머리 주석 2행 · 10행)에 인자 표기.
4. 게이트·spawn 두 추적 사본 쌍은 계속 바이트 동일. 게이트 ≤ 200줄 유지(spawn 은 이미 230줄 — 이 카드에서 분할 0 · 2~3줄만 추가).

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `scripts/fable-team-bin/ft-nano-cherry-gate.sh` · `scripts/harness-install/fable-team/bin/ft-nano-cherry-gate.sh` · `scripts/fable-team-bin/ft-nano-spawn.sh` · `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh`. 새 시험: tests/harness/test_cherry_gate_identical_head.sh.
시험(임시 git 저장소 · 실 브랜치 0): ①**이번 오탐 재현** — nano 가 코드 P 를 바꿨다 되돌림 + design/ 카드 양쪽 수정으로 merge-tree 충돌 → 수정 전 REJECT(기존 사본으로 RED 확인) · 수정 뒤 PASS · 사유 `content_identical_to_feat_head` ②**DA 599 H1 회귀** — 분기 뒤 feat 가 P 를 Y 로 바꿈 · nano tip 은 분기 전 X(롤백) → REJECT 유지 ③nano tip = feat 분기 뒤 새 blob(기존 superseded) → PASS 사유 그대로 ④nano 가 P 를 feat HEAD 와 다른 새 내용으로 바꿈 → REJECT ⑤mode 만 다름(100644 vs 100755 같은 blob) → REJECT ⑥spawn `--cherry-override` 패스스루 — spawn 이 부르는 게이트 자리에 인자 기록 스텁을 두고(사본 복사 · `HERE` 기준) 게이트 인자에 `--override <사유>` + env `FT_SEAT=<from>` · 인자 없으면 `--override` 0 · 빈 사유 → exit 2(spawn 이 ②-0 전 단계에서 멈추면 spawn 인자 파싱 단위만 따로 시험 — 나노 판단으로 최소 경로) ⑦기존 `bash tests/harness/test_cherry_gate_squash.sh` 그대로 PASS ⑧두 쌍 `cmp` · `bash -n` 4파일 · 게이트 `wc -l` ≤ 200.
커밋은 자기 브랜치, **push 금지**. **금지**: 실 v65 브랜치에 쓰기(`--override` 실행 포함) · 루트·`.worktrees/v6-realtime-live/.fable-team/` 쓰기 · 원장 `cherry-gate-override.log` 실 기록.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 기존 squash 시험 rc=0 · arch 독립 재현(+ 기준값 재현 명령을 실 v65 저장소에 읽기 전용으로 돌려 PASS 확인).
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_cherry_gate_identical_head.sh rc=0 · bash tests/harness/test_cherry_gate_squash.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#25 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → CI 확인 → 병합(별 명령) → 설치본 `.worktrees/v6-realtime-live/.fable-team/bin/` 게이트 cp 전 sha256 앞12 `4d3330b20b0b` · spawn `839ccdf23b99` 확인(다르면 cp 0 · arch 반송) → cp + cmp 2 → 기준값 재현 명령 1회 = PASS(사유 `content_identical_to_feat_head`) → v65 master(현역 — `ft-harness-info.sh seats`)에 «게이트 수정 설치 · spawn 재시도 가능 · `--cherry-override` 사용법» 1줄 → 요청 원장 R70 닫힘.

## 상태
- base_sha: 11654cd9cc525ab2b73dd11e58ae56e0f2ea0baa (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#25 · R70 · 원인 실측: design/ 만 충돌인데 ① 생략 + 되돌린 경로를 «새 blob 없음» 으로 REJECT).
- 정본 영향: 하네스 키트 게이트 2 + spawn 2 · 설치본 2 · 홈 정본 0.
- 별 후보(착수 0): ①merge-tree 충돌 경로가 전부 design/ 이면 결과 트리로 design/ 밖 delta 를 그대로 보는 개선(①이 살아남) ②`ft-nano-spawn.sh` 230줄 — 200줄 한도 초과 기존 부채(분할 카드) ③루트 `.fable-team/bin/ft-nano-spawn.sh`(`347db2a1a3c7`)는 키트와 다르고 옆에 게이트가 없음 — 루트 사본으로 ②-0 에 닿으면 실패(쓰는 팀 확인 뒤 정리).
- 2026-10-09 19:35 — 대기→진행 · 좌석 byz-harness-nano-r70-cherry-gate-identical-head#0

## 결과
- 세트: 6a558e64c3b001579512b29054163b491dce3541 · 시험: bash tests/harness/test_cherry_gate_identical_head.sh rc=0 · bash tests/harness/test_cherry_gate_squash.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 하네스 키트 게이트·spawn 사본 2쌍·시험만 (arch 독립 재현 #70287 · 판정서 §115).
