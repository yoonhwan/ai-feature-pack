# 인덱스: 그래픽스 팀장 체제 정본화 — governance·지도·RUNBOOK·env·명부 문장을 «하네스 대행(649)» → «팀장 planner 직속(690)» 으로 · ft-harness-info 가 팀 명부를 보여 줌 (판정 690 · 오빠 「그래픽팀 발주하고 하네스마스터한테 시스템 정보화 시켜」 · harness master#23 #68693)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 690
- 상태: 대기
- 선행: 판정 649 설치(PR 1076 `4fc3140297`) · 팀장 좌석 `byz-graphics-master-claude#0` 개설·명부 `_master` 교체·g678 인계(harness master#23 · `design/graphics/HANDOFF-g678-to-graphics-master-20261009.md`)
- 시험 입력: 임시 ROOT(가짜 `.fable-team/seats-*.json` 3개) · tmux 실좌석 읽기만 — 명부·홈 쓰기 0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 C / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」 — 이 단위의 반영 = governance·지도 설치 cmp + 랜딩 sha.
골의 축: C(업그레이드·반영 — 팀장 체제가 정본·도구에 실린다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
판정 649 는 그래픽스 팀을 «master 0 · 하네스 master 가 열기·감시·닫기 대행»으로 설치했다. 오빠가 판정 690 으로 바꿨다: 그래픽스 팀장 `byz-graphics-master-claude` 를 두고(planner 직속 · 상시 0 · 요청 단위로 열고 닫음), 하네스는 도구·설치·래퍼만 맡는다. 팀장 좌석은 이미 열렸고 루트 명부 `_master` 도 바뀌었다. 그런데 정본 문서와 스테이징 파일에는 649 문장이 남아 있다. governance §1·§1-1·§8 · 하네스 지도 · RUNBOOK · env 주석 · 명부 `_doc` 에 «하네스 master 대행»이 그대로다. 그러면 다음 승계 좌석이 옛 문장대로 움직인다. 또 `ft-harness-info.sh seats` 는 tmux 세션 이름만 보여 줘서, «이 팀의 팀장·arch·HIL 경로가 누구인가»를 명부에서 바로 볼 수 없다. 이 카드는 문장을 690 으로 맞추고, seats 출력에 팀 명부 요약을 더한다.

## 사전검증
- 소환: 아니오
- 면제: 오빠 판정 690 의 구조를 문장·조회 도구에 옮기는 단위(새 정책 0 · 읽기 전용 도구 1곳 출력 추가) — arch 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#24
- 7초 룰 점검(판정 666): 외부 호출 0.

## 조사 근거
- governance 649 문장: 홈 정본(sha256 앞16 `d16650b52a809ecf`) §1 12행 «graphics = master 0 · 하네스 master 가 대행» · §8 73행 «하네스 master 는 seats-graphics.json … 감시» → arch 스테이징 `design/harness/staged-690/main-team-governance.md`(diff 9줄 · 5곳)에 690 문장으로 이미 바꿈.
- 하네스 지도: 홈 `harness-map.md`(sha256 앞16 `33065f92565e622f`) 10행 팀 목록에 graphics 없음 → `design/harness/staged-690/harness-map.md` 에 추가.
- RUNBOOK 649 문장: `design/graphics/RUNBOOK-open-close.md:2`(«열기·감시·닫기는 하네스 master») · `design/graphics/RUNBOOK-open-close.md:14`(감시) · `design/graphics/RUNBOOK-open-close.md:19`(닫기 판단).
- 조회 도구: `scripts/harness-install/fable-team/bin/ft-harness-info.sh:45`(seats = tmux 이름 + lint 만) · 같은 내용 사본 `scripts/fable-team-bin/ft-harness-info.sh`(origin/main 두 파일 동일).
- ★스테이징 설치 위험(실측)★: origin/main 의 graphics 스테이징 install.sh 20행(`git show origin/main:scripts/harness-install/graphics/install.sh` · ops 줄기엔 없음)이 `seats-graphics.json` 을 루트 명부에 «덮어쓴다» — 지금 루트 명부엔 팀장·arch·나노 g678 좌석 행이 있다 → 재설치하면 라이브 명부가 빈 템플릿으로 지워진다.

## 설계 (닫힌 목록)
1. **governance·지도** = arch 스테이징 2장(`design/harness/staged-690/`) 그대로 — 나노는 내용 수정 0 · 시험 대상만.
2. **RUNBOOK** `design/graphics/RUNBOOK-open-close.md` 머리 문장·감시·닫기 절을 690 으로: 열기 = planner 가 팀장을 열고(요청 1건) 팀장이 arch(astra)·나노(sol)·DA(Claude Opus)를 연다 · 감시 = 팀장 자기 10분 크론(governance §8) · 닫기 = 팀장이 제안서 §3.7 공통 3실측 뒤 좌석 닫고 planner 에 1줄 · 원격 보존·랜딩 병합 push = 하네스 master(도구) 에 요청 · 설치 절 = 하네스 master. 발주 경로 1줄: planner → graphics 팀장 → arch·나노 · HIL = 팀장 → planner.
3. **스테이징 명부·env**(`scripts/harness-install/graphics/`): `seats-graphics.json` `_master` = `byz-graphics-master-claude#0` · `_hil_route` = planner 현역(템플릿 값은 `byz-planner-master-claude#17` · 승계 때 고친다는 문장) · `_doc` 의 649 문장(«열기·감시·닫기 = 하네스 master») → 690 문장 · `graphics-env.sh` `FT_SEND_FROM` = `byz-graphics-master-claude#0` + 주석(«팀장 승계 때 _master 와 같이 고친다»).
4. **install.sh 안전**: `seats-graphics.json` 은 루트에 «없을 때만» 복사(있으면 `SKIP seats-graphics.json (라이브 명부 보존 — _doc·_master 는 손으로)` 1줄) · env·goal-lines 는 지금처럼 .bak 후 덮기 + cmp.
5. **ft-harness-info.sh seats**: 지금 출력(라이브 tmux + lint) 뒤에 «팀 명부» 절 추가 — 루트 `.fable-team/seats-*.json`(`.bak*` 제외) 파일마다 1줄: `<파일> master=<_master> arch=<_arch> hil=<_hil_route> 좌석=<등록 행 수> 열림=<그중 tmux 실재 수>` · 읽기 전용 · 파싱 실패 파일은 `ERR <파일> 파싱 실패` 1줄(조용한 누락 0). 두 사본(`scripts/fable-team-bin/`·`scripts/harness-install/fable-team/bin/`) 같은 내용.
6. **STRUCTURE**(planner 정본 `design/planner/STRUCTURE-main-satellite.md` §1-1 메인 팀 표): graphics 행 1줄(맡는 것 = 요청 때만 여는 공용 서비스 · 오케 = `byz-graphics-master-claude` planner 직속 · 워크트리 = 카드 `harness-ops` · 나노 = origin/main 기준) — ★planner 문서라 나노는 1행 추가만, 랜딩 뒤 master 가 planner 에 1줄 통지★.

## 구현 범위 (닫힌 목록 · 나노 · base = origin/main)
기존 파일(수정): `scripts/harness-install/fable-team/bin/ft-harness-info.sh` · `scripts/fable-team-bin/ft-harness-info.sh` · `design/graphics/RUNBOOK-open-close.md`(origin/main 에 있음) · scripts/harness-install/graphics/ 의 seats-graphics.json · graphics-env.sh · install.sh · `design/planner/STRUCTURE-main-satellite.md`(1행).
가져오기: arch 스테이징 2장 `design/harness/staged-690/main-team-governance.md`·`design/harness/staged-690/harness-map.md` 는 ops 줄기 커밋 → 나노 브랜치에 같은 경로로 cherry-pick 또는 `git show <ops sha>:<경로>` 로 반입(내용 수정 0).
시험 새로 만든다 — tests/harness/test_graphics_690.sh: ①`bash -n` 수정 스크립트 전부 ②임시 ROOT 에 가짜 명부 3개(정상 2 · 깨진 JSON 1) → `ft-harness-info.sh seats` 출력에 팀 명부 절 · 정상 2줄 · `ERR … 파싱 실패` 1줄 · 두 사본 출력 동일 ③임시 ROOT 에 기존 seats-graphics.json(좌석 행 1) 둔 채 install.sh → SKIP 줄 · 명부 바이트 그대로(cmp) · env·goal-lines CMP OK ④루트가 비었으면 install.sh 가 명부 복사 ⑤스테이징 명부 JSON 파싱 · `_master`=byz-graphics-master-claude#0 · `_doc` 에 «하네스 master 가 열기» 문장 0 ⑥RUNBOOK·env·`_doc` 에 «master 0»·«하네스 master 가 대행» 문장 0(grep) ⑦governance 스테이징 vs 홈 정본 diff = 5곳(추가 1 · 바꿈 4) · harness-map diff = 1줄.
커밋은 자기 브랜치, **push 금지**. **금지**: 루트 `.fable-team/`·홈 `~/.claude/` 쓰기(설치는 master) · tmux 좌석 조작 · secrets/·*.cred·토큰 파일 내용 출력(키 이름·존재·크기만 · 판정 676).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_graphics_690.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#24 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → 병합 → 하네스 키트 설치(ft-harness-info 설치본 cmp) → 홈 governance cp 전 sha256 앞16 = `d16650b52a809ecf` 확인 뒤 staged-690 cp + cmp(다르면 cp 0 · arch 반송) → 홈 harness-map cp 전 `33065f92565e622f` 확인 뒤 cp + cmp → 루트 env 만 install.sh 로(명부 SKIP 확인) · 루트 명부 `_doc` 은 손으로 690 문장(파일 쓰기 1회 · 좌석 행 보존) → `ft-harness-info.sh seats` 팀 명부 절에 graphics 줄 확인 → planner#17 에 «STRUCTURE graphics 행 · 팀장 체제 정본화 끝» 1줄.

## 상태
- base_sha: 56e95079462d4c60c33263e3b54f45122a9451d6 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#24 · 판정 690 · harness master#23 #68693).
- 정본 영향: 홈 governance §1·§1-1·§8 + 머리 1줄 · 홈 harness-map 1줄 · RUNBOOK · STRUCTURE 1행 · ft-harness-info 출력 1절.
- 2026-10-09 13:42 — 대기→진행 · 좌석 byz-harness-nano-g690-graphics-master-system-info#0

## 결과
- 세트: 6a265244239d9d8af8fefc94f91adfd2dbcc6e4b · 시험: bash tests/harness/test_graphics_690.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 하네스 키트·홈 governance·그래픽스 정본만 (arch 재현 #68745 · 판정서 §110).
- 2026-10-09 13:48 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§110
