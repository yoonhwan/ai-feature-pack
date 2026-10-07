# ops 수락 판정문 — 구현 단위 (ft-harness-ops#4 · 2026-10-06)

> 작성자(나노)와 승인자(ops)를 분리한다. ops 가 독립 검증한 출력을 근거로 적는다. 판정 형식: 단위 · 검증 · 결과 · 「닫힘」/「HOLD」.

## §1 C1a 설치 키트 채택 + install.sh + MACHINES·RELEASE 템플릿 — 닫힘
- 나노 커밋 `89171f202d` → 통합 브랜치 `57423fa7e5`(cherry-pick -x).
- ops 독립 검증: 변경 파일 전부 허용 경로(`scripts/harness-install/fable-team/` · `design/harness/{KIT-ADOPT,MACHINES,RELEASE-TEMPLATE}` · 카드) · 범위 밖 0 · `bash -n` 전 .sh 실패 0 · 빈 HOME(mktemp) `install.sh --apply` rc=0 · 설치 파일 76 · 비밀 패턴 스캔 0.
- 한계(닫힘을 막지 않음): 원격 머신(jarvis·byzs-mac-mini) 설치는 사람 승인 뒤 · MACHINES 행은 «미확인» · 라이브 FT_BIN 이전(#816 ⑤)은 이 단위 범위 밖. 닫힘.

## §2 C5 planner 이슈 큐 절 + GOAL-cfo·GOAL-ccu + 투입≠발주 — 닫힘
- 나노 커밋 `1d290f18b8` → 통합 브랜치 `82039ad5b3`(cherry-pick -x).
- ops 독립 검증: 변경 4 파일(design/ccu·cfo·planner) · BOARD.md 삭제 줄 0(추가만) · 큐 절 표 8칸 · 상태 7값 · 예시 행이 실제 열린 Issue(#827). GOAL-cfo·GOAL-ccu 는 나노가 원본과 바이트 일치(cmp)로 보고. 닫힘.

## §3 C3 질문 원장 ft-hil-ask·ft-hil-answer — 닫힘
- 나노 커밋 `678b072da7` → 통합 브랜치 `19eec9187d`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일 전부 허용 경로 · `bash -n` 3종 OK · `tests/harness/test_hil_ledger.sh` ops 재실행 ALL PASS(ask→answer→applied 1바퀴·거부·mbox 실패 재시도) · 라이브 mbox 미접촉.
- 한계(닫힘을 막지 않음): 범위 2 `tmm h` 노출 = **[사실: 불가]**(tmm 이 외부 원장 입력 경로 없음) → 대안(tmm 본체에 `tmm q` 질문 목록 명령 추가)은 별도 발주 후보 — 오빠 보고에 남김. 닫힘.

## §4 C4 Issue 전이표 5 + Closes 규약 + close 5항 검사 + reopen — 닫힘
- 나노 커밋 `2b62f388d0` → 통합 브랜치 `f09daa8fdf`(cherry-pick -x).
- ops 독립 검증: 변경 7 파일 전부 허용 경로 · `bash -n` OK · `ft-issue-close-check.sh 827`(열린 Issue) 미비 판정 출력 · `ft-issue-reopen.sh` 는 `--apply` 없이는 명령만 출력(가드 확인: `ft-issue-reopen.sh:25`) · gh edit/close 실행 0.
- 한계: 실제 5항 코멘트가 달린 닫힌 Issue 가 없어 exit 0 은 fixture 로만 검증 · SPEC r5 §12 의 reopen 역링크·회귀 팩은 C20~C23 으로 별도. 닫힘.

## §5 C11 문서 정정 — 닫힘
- 나노 커밋 `c592d9abbc` → 통합 브랜치 `06cb8d7db3`(cherry-pick -x · `GUIDE-planner.md` 충돌 1건 = C5 와 같은 「투입≠발주」 줄이라 C5 쪽 문장으로 해소).
- ops 독립 검증: 변경 12 파일 전부 `design/**.md`(코드·스킬 0) · 보고서 C11-REPORT 반영 표/미반영 표 존재. 나노의 판정 요청 2건 결정: **⑨** `docs/rules/single_set_testing.md` §3 ⑤ = 오빠 값(P5 Q3 `cherry-pick -x` 기본) 그대로 ops 가 직접 1줄 정정 · **⑬** P2 표 1 열 추가 = 열 수 불변 조건과 충돌 → 구현 카드(C2) 쪽에서 해소 · 미반영으로 남김. 닫힘.

## §6 C9-기계 ft-land.sh 후보 확정 + LANDING-LEDGER 형식 — 닫힘 (기계 부분만)
- 나노 커밋 `1c65f85aa4` → 통합 브랜치 `b0a609ece8`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일(허용 경로) · `bash -n` OK · `tests/harness/test_ft_land.sh` ops 재실행 ALL PASS(ff · main 이동 merge-tree · S10 주입 abort rc=1 · 충돌 abort · `--push` 거부) · 스크립트에 push 호출 0(주석·usage 뿐).
- 한계: push·수락 부분(후보 게이트→push→원격 확인)은 C7·C10 뒤 — 이 단위에 포함하지 않음. 닫힘(기계 부분).

## §7 C8 고아 카드 목록 + wt= 3값 확인 — 닫힘
- 나노 커밋 `367ea794b5` → 통합 브랜치 `b7e357331d`(cherry-pick -x).
- ops 독립 검증: 변경 1 파일(`ft-orphan-cards.sh` · 읽기 전용) · 실행 전후 git status 변화 0 · 결과 v65=28/28 · cfo=17/17 고아(MERGED 값과 일치). `wt=` 3값 + sweep 재시도는 [사실: 이미 구현됨]로 무변경(나노 보고 · 개명 시 `cleaned` 매칭 코드 다수 → 개명 안 함 — 타당).
- 한계: v65·cfo 고아 45장의 `대기/` 복귀 이동은 **이 단위에서 하지 않음**(다른 팀 카드 · 해당 팀 오케 승인 필요) — 아침 브리핑에 올림. 닫힘.

## §8 C6 카드 머리줄 lint + 슬롯 정정 — 닫힘
- 나노 커밋 `264eeab8b4` → 통합 브랜치(cherry-pick -x · 아래 log 참조).
- ops 독립 검증: 변경 3 파일(허용 경로) · `bash -n` 2종 OK · `tests/harness/test_nano_slots.sh` ops 재실행 ALL PASS · spawn 쪽 변경은 WARN(후보 제외) 뿐 REJECT 아님(오빠 값 Q2 유지).
- 나노 가정 3개 수락: ①활성 Issue = env `FT_ACTIVE_ISSUES`(미설정 시 필터 없음) ②예약석 점유자 = seats 행 `reserved:true` · 라이브 카드 = 카드 `상태:` 에 「라이브」 ③press-불요 정규식 대체 → 머리줄 필터(P9 3-A 와 일치).
- 한계: 이 변경은 **추적본**(`scripts/fable-team-bin/`)에만 있고 라이브 FT_BIN 에는 아직 안 간다(#816 ⑤ · 사람 승인). 키트 채택 뒤 카드 머리줄 4줄이 없는 카드는 슬롯 후보에서 제외되므로 **이 하네스 카드 양식에 머리줄 4줄 추가 필요**(아침 브리핑 항목). 닫힘.

## §9 C2 명부 생성기 + 세션명 lint + test_bundle lint — 닫힘
- 나노 커밋 `466d62474e` → 통합 브랜치 `10a4f30110`(cherry-pick -x).
- ops 독립 검증: 변경 6 파일(허용 경로) · `bash -n` 3종 OK · `test_name_lint.sh`·`test_seat_live.sh` ops 재실행 fail=0 · 입력 명부 md5 불변(나노 보고) · 읽기 전용(tmux 변경 0).
- 발견: 현행 세션 28개 중 문법 통과 9 · REJECT 19(구 문법). **`ft-harness-ops#4` 자체가 REJECT**(P6 역할 예약어에 `ops` 없음) — P6 문서 정정 또는 세션 개명 결정이 필요해 아침 브리핑에 올림(구현은 안 막음). P2 표 1 열 추가(⑬)는 이 단위에서도 하지 않음. 닫힘.

## §10 C17 임시 기획 세션 인계 ft-plan-handoff.sh — 닫힘
- 나노 커밋 `f3def419b2` → 통합 브랜치 `0394851486`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일(허용 경로) · `bash -n` OK · `test_plan_handoff.sh` ops 재실행 ALL PASS(24건) · 실제 mbox 발신·Issue 생성 0(dry-run).
- 나노 가정 수락: planner 수신자 = `seats-planner.json` 의 `_master`(없으면 REJECT · 폴백 0). 닫힘.

## §11 C21 닫힌 Issue 회귀 팩 — 닫힘
- 나노 커밋 `28e9e40240` → 통합 브랜치 `0016f6c81a`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일(`ft-regress-pack.sh` · 시험 · `issue_pack.jsonl` 예시 2행) · `bash -n` OK · `test_regress_pack.sh` ops 재실행 fail=0(add→select→run→retire · 상한 20 경고 · press 행 목록만).
- 한계: 실제 닫힌 Issue 의 재현 명령을 모으는 일(add)은 매니저 구동 뒤 — 지금은 예시 행뿐. 닫힘.

## §12 C22·C23 회귀 재오픈 + close 사유 3종 검사 — 닫힘
- 나노 커밋 `3f8fdc8b5a` → 통합 브랜치 `1581f1ab0a`(cherry-pick -x).
- ops 독립 검증: 변경 5 파일 · `bash -n` 2종 OK · fixture 판정 ops 재확인(교체+seq rc=0 · 교체-seq rc=1 · 불필요-근거 rc=1) · reopen 은 `--apply` 없이는 명령만 출력 · 원장 밖 sha 는 거부(rc≠0, 역링크 불가 사유 출력).
- 나노 결정 수락: close 사유 줄 형식(`close-사유:` · `승계:` · `확인 seq:`)을 이 스크립트가 정본으로 정함 — SPEC §12-4 에 문법이 없던 자리이므로 **SPEC 문법 반영은 후속 문서 정정(아침 브리핑)**. 닫힘.

## §13 C7 허가 2종 파일 + 획득/해제 스크립트 — 닫힘
- 나노 커밋 `8698d482a7` → 통합 브랜치 `63297ebbec`(cherry-pick -x).
- ops 독립 검증: 변경 2 파일(`ft-press-permit.sh` · 시험) · `bash -n` OK · `test_press_permit.sh` ops 재실행 ALL PASS(5 시나리오 + 상한·비멤버 보조 · fail=0) · 라이브 permits 디렉터리 미생성(ops 확인) · 기존 `ft-press-gate.sh` 미수정.
- 한계: 이 허가 파일은 아직 어떤 press 러너에도 연결되지 않음(연결은 C10 · 라이브 FT_BIN 이전 뒤) · 멤버 상한 1 시작(실측으로 올림 — C10). 닫힘.

## §14 C15 Issue 폼 보강 — 닫힘
- 나노 커밋 `3ea186afac` → 통합 브랜치 `f49639b842`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일(폼 2 + 시험) · `test_issue_forms.sh` ops 재실행 ALL PASS(YAML 6/6 · 기존 id 삭제 0 · 폼 라벨 전부 GitHub 에 실재) · 삭제 줄 0 · `config.yml` 무변경.
- 한계: 새 체크 2개는 **라벨을 자동으로 붙이지 않는다**(필요한 라벨은 이미 있는 것만 사용 — 없는 라벨 생성은 외부 쓰기라 안 함). `from:member` 자동 라벨은 라벨 생성 승인 뒤. 닫힘.

## §15 C20 기준값 템플릿 + lint — 닫힘
- 나노 커밋 `7c01a1221f` → 통합 브랜치 `b58ce045d6`(cherry-pick -x).
- ops 독립 검증: 변경 4 파일 · `test_baseline_lint.sh` ops 재실행 ALL PASS(기준값 있음/없음→대체 축/빈칸 · 기존 머리줄 경고 무영향) · 삭제 줄 0.
- 나노 해석 수락: 5항 표의 「기준값 대비」는 열이 아니라 행으로 추가(삭제 줄 0 조건 때문). 닫힘.

## §16 C16 Issue 작성 경로 분류기 + 발견 지연 열 + 좌석 등록 쌍 래퍼 — 닫힘
- 나노 커밋 `880879cfa2` → 통합 브랜치 `7cbd9d01c0`(cherry-pick -x).
- ops 독립 검증: 변경 8 파일(스크립트 2·시험 1·고정 입력 4·실측 결과 1) · `bash -n` OK · `test_issue_classify.sh` ops 재실행 ALL PASS · 삭제 줄 0 · 비밀 값 스캔 0.
- 실측(나노): 열린 Issue 93건 읽기 1회(쓰기 0) — 경로①=70 · ②③④=0 · 미분류 23 · 미발견 79. 전제 2개(라벨 6계열 · 마커 3종)는 나노 가정 — 뒤집으면 분류 규칙만 바뀜(코드 구조 불변).
- 한계: `--apply`·mbox 실발신은 미실행(외부 쓰기). 닫힘.

## §17 C10-라이트 시험 묶음 상태 전이 — 닫힘
- 나노 커밋 `edd6fa134e` → 통합 브랜치 `c9d92a7345`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일 · `bash -n` OK · `test_bundle_state.sh` ops 재실행 fail=0(정상 1바퀴 · 금지 전이 3종 · 재오픈 1회 · 원본 md5 불변) · 삭제 줄 0.
- 나노 질문 판정: 인덱스의 state 값(reported·classified)이 C2 lint 허용값에 없어 REJECT 됨 → **lint 허용값 확장으로 수락**(통합 `f5e1c99d1c` · reported·classified PASS · 엉뚱한 값 REJECT · 기존 5값 불변). 재오픈 목표값 `reopen` 은 SPEC 값이라 수락.
- 한계: C10 실측(N=1→2→4)은 관측 프로필 승인 필요라 하지 않음. 닫힘.

## §18 C19 좌석 없는 팀 「좌석 필요」 문구 — 닫힘
- 나노 커밋 `4be185dfbe` → 통합 브랜치 `a10f2a183d`(cherry-pick -x).
- ops 독립 검증: 변경 8 파일 · `bash -n` OK · `test_seat_request.sh` ops 재실행 fail=0(명부 없음·gh 실패→exit 1 · usage→2) · 삭제 줄 0 · 발신 0(본문 출력만).
- 나노 실측: 좌석 없는 팀 대조 — cfo 46 · v65 29 · planner 7 · harness-ops 6 · shared-harness 4 · ccu 1. planner 로 올리는 발신은 승인 뒤. 닫힘.

## §19 C18 브랜치 정리 후보 목록(읽기 전용) — 닫힘
- 나노 커밋 `8403cd27a7` → 통합 브랜치 `aaacca3559`(cherry-pick -x).
- ops 독립 검증: 변경 3 파일 · `bash -n` OK · `test_branch_candidates.sh` ops 재실행 fail=0 · 삭제 줄 0 · 스크립트가 쓰는 git 은 읽기 명령뿐(삭제 명령 문구는 사람이 실행할 목록으로 «출력만» 함 — 파이프·eval 0) · 실행 전후 브랜치 수 1042 = 1042 · 비밀 값 스캔 0.
- 실측(나노): 원격 416개 = 지워도 되는 후보 12 · 검토 137 · 보존 267 / 로컬 622개 = 후보 48 · 검토 104 · 보존 470. 나노 주의 수락: 보관본(tar) 열은 매핑 불명확해 제외.
- 한계: 브랜치 삭제는 오빠 승인 영역 — 후보 목록만 올림. 닫힘.

## §20 tmm 그룹 탭 일반화 (신 이름 규칙 → 팀별 탭) — 닫힘 (ft-harness-ops#6 · 2026-10-07)
- 나노 커밋 `da5685b995`(nano/tmm-group-tab-generalize · push 0) · 카드 `tmm-group-tab-generalize`.
- ops 독립 검증: 변경 4 파일(`scripts/harness-install/tmm/{tmm,VERSION}` · `tests/harness/test_tmm_group.sh` · `design/harness/RESULT-tmm-group-tab-20261007.md`) · 설치본 0.7.3 과 diff = `cat_of()` 안 추가 23줄 + 1줄 이동뿐(삭제 0) · `bash -n` OK · `test_tmm_group.sh` ops 재실행 ALL PASS(신 6·구 6·공존·충돌·규칙파일 우선·ROLES 일치) · `~/.tmm` 변경 0.
- 결과(나노 실측): byz-* 4개가 `byz` 한 탭 → cfo·issues·planner 로 분리 · 구 이름 25개 라벨 불변(회귀 0) · 충돌은 라이브 0건(시험으로만 `b-bot`/`k-bot`).
- 한계(닫힘을 막지 않음): ①`~/.tmm` 설치·`current` 전환은 오빠 승인 영역(미실행) ②충돌 판정이 P6 이름마다 `tmux list-sessions` 1회 — 체감 지연 시 호출부 선계산 후속. 닫힘.
