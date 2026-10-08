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

## §21 gh-as-tank 래퍼 + 가드 훅 (Issue·PR 쓰기를 byz-tank 이름으로) — 닫힘 (byz-harness-master-claude#7 · 2026-10-07)
- 나노 커밋 `92831cb4af` → 통합 브랜치 `481c67d6d8`(cherry-pick -x).
- ops 독립 검증: 변경 4 파일(래퍼 · 가드 훅 · 시험 · RESULT) 전부 허용 경로 · 범위 밖 0 · `bash -n` 3종 OK · `tests/harness/test_gh_as_tank.sh` ops 재실행 fail=0 · 토큰 값 패턴 스캔 0 · 래퍼 `--apply` 미실행(dry-run 만) · 기존 `ft-issue-create-pair.sh`·`ft-tank-verify.sh` 무수정.
- 코드 확인: 토큰 없음 exit 2(폴백 0) · `gh api user` 로 주인 byz-tank 확인 후에만 실행 · `pr-create --apply` 는 exit 2(Tank triage 권한 미확인).
- 한계(닫힘을 막지 않음): 가드 훅 `~/.claude/settings.json` 등록 = 별도 단계(판정 B = 설치 · 시험 통과 뒤 ops) · `pr-create` 실제 권한은 미확인.

## §22 orchestration-gate master 좌석 판별 (코드·시안·카드 증거 직접 편집 0) — 닫힘 (byz-harness-master-claude#7 · 2026-10-07)
- 나노 커밋 `f8e0873487` → 통합 브랜치(cherry-pick -x).
- ops 독립 검증: 변경 2 파일(`.claude/hooks/orchestration-gate.sh` · `tests/harness/test_orch_gate_master.sh`) · `bash -n` OK · `test_orch_gate_master.sh` ops 재실행 pass=36 fail=0 · 비-master 좌석은 수정 전 훅과 결과 동일(나노 대조 9쌍).
- 코드 확인: 세션명 3번째 토큰 master(신·옛 이름 모두)일 때 모델과 무관하게 게이트 · master 는 코드 한도 0 · html·htm·css 도 코드 · `.worktrees/` 제외 해제 · 진행/완성 카드 md 편집 차단 · 세션명 판별 불가 = master 아님(fail-open).
- 한계(닫힘을 막지 않음): 게이트 사본이 홈·프로젝트·설치 템플릿 3개로 갈라져 있고 이 변경은 프로젝트 훅 1개만 — 사본 정합은 후속(요청 원장). 프로젝트 훅은 각 워크트리 브랜치에 들어가야 돈다(v6-realtime-live 가 main 병합 필요).

## §23 gh 가드 훅 리포 범위 + main 보호 + 래퍼 pr-create 활성화 — 닫힘 (byz-harness-master-claude#7 · 2026-10-07)
- 나노 커밋 `d1182064ea`(구현) · `374d70ae11`(RESULT) → 통합 브랜치(cherry-pick -x).
- ops 독립 검증: 변경 3 파일(가드 훅 템플릿 · `ft-gh-as-tank.sh` · `test_gh_as_tank.sh`) + RESULT 1 · `bash -n` 3종 OK · `test_gh_as_tank.sh` ops 재실행 fail=0 · 토큰 값 패턴 스캔 0 · 훅 대조 시험(ops 직접): 직접 gh 쓰기 차단 · main 삭제(`:main`)·강제(`+main`)·main 의 gh api DELETE 차단 · main 일반 push 통과 · 그 밖 브랜치 삭제 통과 · 타 리포 gh 통과(오빠 값: main 삭제·리베이스만 제한).
- 코드 확인: 래퍼 `pr-create --apply` = base main 고정 · head 필수 · 원격 head 실재 확인 · 생성 뒤 작성자 byz-tank 확인.
- 나노 확장 1건 수용: main 대상 force push 도 차단(오빠 「main 삭제·리베이스 금지」 해석과 일치 · 원치 않으면 push_main_reason 1줄 제거).
- 한계(닫힘을 막지 않음): 훅은 클라이언트 쪽 장치라 훅을 거치지 않는 경로(Tank 토큰 유출 등)는 못 막는다(무료 플랜 · 서버 보호 불가) · 홈 훅 파일 갱신(cp+cmp)은 병합 뒤 · PR 쓰기 5종(pr review·close·edit 등) 확장은 요청 원장 후속 · milestone 지원 R7.

## §24 키트 install 홈 훅 확인 줄 + block-destructive 템플릿 — 닫힘 (byz-harness-arch-claude#5 #58706 · master#8 · 2026-10-07)
- 나노 커밋 `7ed51c846e`(main 반영 `bc87df1302` · PR 845 squash) · 변경 4파일(install.sh · block-destructive 템플릿 · test_install_hook_check · RESULT).
- master 독립 검증: test_install_hook_check ALL PASS · install.sh·템플릿 bash -n OK · 토큰 패턴 0. arch 재확인: 읽기 전용(cp·리다이렉트·settings 쓰기 0).
- 이 Mac dry-run: 홈 훅 diff 2(boot-read-gate · orchestration-gate) = RELEASE 0.4 반영 후보. orchestration-gate 는 홈·프로젝트·키트 3사본 정본 결정 뒤에 덮는다.

## §25 키트 bin 단일 원본화 (드리프트 채택) — 닫힘 (byz-harness-arch-claude#5 #58723 · master#8 · 2026-10-07)
- 나노 커밋 `7889dec525`(main 반영 `bc87df1302` · PR 845 squash) · 38파일(추적본 전용 24 키트 추가 · 추적본 9 정렬 · test_kit_bin_sync · RESULT).
- 카드 전제 오류 2건(ft-nano-slots · ft-nano-spawn: 라이브=키트인데 추적본이 새것) → 판정 ⓐ: 키트·추적본 둘 다 추적본 바이트(arch 실측 누락 인정).
- 검증: test_kit_bin_sync ALL PASS(음성 대조) · test_nano_slots · test_baseline_lint rc=0 · 통합 트리 재실행 rc=0 · CI 13/13 pass.
- 설치(FT_BIN 전환) 때 동작 변화 → RELEASE 0.4 칸: nano-slots 기본 슬롯 6→5 · 후보 필터 머리줄 4줄 기준.

## §26 나노 spawn·close 팀 env 자동 로드 + codex 기본 모델 + --base + --shared-wt 닫기 — 닫힘 (byz-harness-arch-claude#5 #58793 · master#8 · 2026-10-07)
- 나노 커밋 `45a1ee516a`(8파일: 키트+추적본 spawn·close·evidence-check 같은 바이트 · test_nano_team_env). 요청 원장 R8(오빠 「하네스 마스터에 전달해 개선」) 반영.
- master 독립 검증: test_nano_team_env · test_kit_bin_sync rc=0 · 토큰 0. arch 재확인 ALL PASS · 범위 밖 파일 0.
- 나노 판단 2건 승인: ①--base 주면 base_sha 스탬프·재대조도 그 ref ②문서 전용 경로검사는 세트 sha 까지만. 한계(수용): 공유 가지에서 merge-base..세트 sha 사이 타 세션 코드 커밋이 끼면 문서 전용 카드가 거짓 거절(거짓 통과 아님).
- 라이브 FT_BIN 은 옛 바이트 — FT_BIN 전환(install) 뒤에야 좌석에 적용 → RELEASE 0.4 변경 표에 포함.

## §27 ft-role-spawn 기본 접두 byz-v65- + 두 계보 합산·교체 — 닫힘 (byz-harness-arch-claude#5 #58793 · master#8 · 2026-10-07)
- 나노 커밋 `86d77d5f6a`(4파일: 키트+추적본 ft-role-spawn 같은 바이트 · test_role_spawn_name 신규). 인계문 열린 일 4-① 해소.
- master 독립 검증: test_role_spawn_name · test_kit_bin_sync rc=0 · 토큰 0. 실 명부 dry-run: byz-v65-arch#167 이 두 계보 #166 둘 다 교체 표시.
- 라이브 반영은 FT_BIN 전환 뒤 → RELEASE 0.4.

## §28 Tank 래퍼 Issue edit + 수정 전 원문 보관 (R10) — 닫힘 (byz-harness-arch-claude#6 #59468 · master#9 · 2026-10-07)
- 나노 커밋 `00a120c510`(3파일: ft-gh-as-tank.sh 추적본+키트 사본 같은 바이트 · test_gh_as_tank). 요청 원장 R10 반영.
- master 독립 검증: test_gh_as_tank fail=0 · test_tank_verify rc=0. 미통과 kit_bin_sync·regress_pack 은 기준(ops/main-base)에서 같은 rc=1 재현 = 변경 무관(kit_bin_sync = R9 대기분 ft-press-gate 사본 어긋남 + baseline-check 키트 누락).
- arch 재확인: cmp 동일 · bash -n OK · dry-run 3줄(제목만/본문만/둘 다) 일치 · usage exit 2 4종 · view 가 edit 보다 먼저 · view 실패·빈 응답·보관 실패 시 edit 0건 · 가드 직접 edit 차단 사례 실재 · 가드·다른 동작 diff 0.
- 라이브 반영은 FT_BIN 전환 뒤(래퍼는 scripts 경로라 즉시) · 닫는 증거 sha = 나노 HEAD 40자 카드 증거 줄.

## §29 ft-nano-close --wt/--branch 명시 모드 (R8 보강) — 닫힘 (byz-harness-arch-claude#6 #59519 · master#9 · 2026-10-07)
- 나노 커밋 `0103bccf3e`(3파일: ft-nano-close.sh 추적본+키트 사본 같은 바이트 · test_nano_close_named_wt 신규). 표준 아닌 이름의 전용 워크트리 좌석 닫기.
- master 독립 검증: test_nano_close_named_wt ALL PASS(50P 0F) · test_nano_team_env ALL PASS(34P 0F) · cmp 동일 · bash -n OK. 미통과 kit_bin_sync·regress_pack = 기준 동일 실패. test_branch_candidates 1회 FAIL = 공유 리포 브랜치 수 변동 flake(동시 세션).
- arch 확인: main·FT_NANO_FEAT 브랜치 거부(추가 방어) · .sh.hil 로 sweep 밖 · 완료조건 2 판정표(byz-cfo-nano-overdraft-u1#0: 워크트리·명부 없음 → ⓐ REJECT 가 정답).
- 한계: 251행 v65- 접두 하드코딩은 별 카드 nano-close-wt-prefix(대기)로 — feature·kk 팀 나노 닫기 선행 조건.

## §30 ft-role-spawn master·arch 후계 첫 발주에 체크 크론 10분 고정 (R13 A) — 닫힘 (byz-harness-arch-claude#6 #59527 · master#9 · 2026-10-07)
- 나노 커밋 `d8de2910d1`(3파일: ft-role-spawn.sh 추적본+키트 사본 같은 바이트 · test_role_spawn_name). 요청 원장 R13 A(오빠 「크론 이관받았어? 못받았으면 버그」).
- master 독립 검증: test_role_spawn_name ALL PASS rc=0 · cmp 동일 · bash -n OK · 미통과 kit_bin_sync·regress_pack 은 기준 동일 실패(변경 무관).
- arch 확인: 시험이 CronCreate 10분 + cron=job id 둘 다 확인 · da·pm·tester 문장 0 · BODY 위치 이동해도 변수 전부 앞에서 정의 · 실전 경로 출력 무변화.
- 라이브 반영: 라이브 ft-role-spawn 은 10-07 에 이미 키트 바이트로 교체됨(백업 .bak-1007-role-spawn) — 이 변경은 FT_BIN 전환(RELEASE 0.4) 때 같은 바이트로 일괄.

## §31 Issue 855 pytest 가 리포 루트 .env 를 읽지 않게 (시험 격리) — 닫힘 (byz-harness-arch-claude#6 #59731 · master#9 · 2026-10-07)
- 나노 커밋 `215f52056a`(5파일: shared/config/settings.py 스위치+RuntimeError · tests/conftest.py · gpu_uptime autouse delenv · pulse 픽스처 stub · 신규 시험 3). 요청 원장 R12(오빠 판정 harness-ops · 완성 전).
- DA(`byz-harness-da-codex#0`, bounded): 1차 HOLD-1(Q3 — design/v65/20260930/repro/conftest.py:15 가 tests.conftest 를 import → 스위치 강제가 따라감) → 정정 계약(의도된 opt-in 공유 · pytest 자식 env 상속은 수락된 한계) → §7 APPROVE. 판정문 `design/harness/DA-i855-20261007.md`.
- master 독립 검증(.env 없는 git archive 사본 · REDIS_PORT=9 · vLLM 차단 · deselect 3 · CI 묶음 그대로): 12 failed 7489 passed. 855 대상(gpu_uptime·gpu_auto_warmup·pulse_consumer_carry) 실패 0. 나노 재실행 11건과 이름 11건 일치 + 1건(test_v6_d1_import_fence — 사본 .git 없음)은 사본 인위 결과. arch 독립 대조 동의, 새 인터프리터 import 시험 9파일 141 passed 0 failed(REDIS_PORT=9).
- 남은 11건(poller_dom_order_version_capture 7 · gpu_vm_control 2 · cleanup_auth 1 · loom_contract_terminal_surfaces 1)은 855 밖 기존 실패 집합 → 요청 원장 후속 행 R17.
- 안전 기록: master 최초 검증이 REDIS_PORT=6379 로 2분24초 돎(19:02:25~19:04:49 KST · TaskStop) · 나노도 18:40~18:58 6379 → 시험 키 대조는 arch · flush 0 · ops:account_seen_fail 일일 카운터 오염 가능.

## §32 ft-index-lint 사전검증·조사 근거 검사 ⑦⑧ (R16 · feature 팀 설계 단계 게이트) — 닫힘 (byz-harness-arch-claude#6 #59737 · master#9 · 2026-10-07)
- 나노 커밋 3개: `01c5e8a7df`[structure] path_exists 추출(출력 바이트 동일) · `6eec09b8f0`[feature] ⑦ 「## 사전검증」(DA APPROVE 판정문 경로 실재 + 마지막 판정 줄 APPROVE, 또는 arch 서명 면제) · ⑧ 「## 조사 근거」(경로:줄 전부 실재) — `FT_CARD_REQUIRE_PREVERIFY=1` 일 때만 · `ebf5e9089f`[fix] last_verdict 를 grep -owE APPROVE|HOLD|REJECT(PASS 삭제 · 단어 경계 — arch 수정 1: SUPABASE_PASSWORD·시험 요약 26 PASS 에 걸리던 결함).
- master 독립 검증: test_index_lint 28P 0F · bash -n OK · PASS 잔재 코드 0. arch 재현: HOLD 뒤 PASSWORD·26 PASS 두 건 REJECT 확인. 수용한 한계: APPROVED 같은 변형은 안 잡힘(DA 형식대로 APPROVE 로 쓴다).
- 집행(10-07): 3커밋 ops/main-base cherry-pick → 키트 ft-index-lint.sh 를 라이브 RT(v6-realtime-live/.fable-team/bin)에 cp+cmp 동일(백업 ft-index-lint.sh.bak-1007-r16) → bin-feature/feature-env.sh 에 FT_CARD_REQUIRE_PREVERIFY=1 1줄(백업 .bak-preverify-1007).
- 스모크(라이브 lint): 스위치 꺼짐 = ⑦⑧ 메시지 없음 · 켜짐(같은 카드) = 「절 없음: 사전검증 (⑦)」「절 없음: 조사 근거 (⑧)」. ft-nano-spawn 코드 변경 0.
- 후속: feature 카드 견본(drafts/r16/feature-card-template.md → feature-main indices/README.md) — feature-main 반영은 PR 로.

## §33 ft-nano-close 좌석 워크트리 후보 접두를 FT_NANO_WT_PREFIX 로 (v65- 고정 제거) — 닫힘 (byz-harness-arch-claude#6 #59912 · master#9 · 2026-10-07)
- 나노 커밋 `9a2da93134`(4파일: ft-nano-close.sh 추적본+키트 사본 같은 바이트 · test_nano_team_env 사례 추가 · 카드). feature·kk 팀 나노 표준 닫기의 선행 조건(R14 후속).
- master 독립 검증: cmp 동일 · bash -n OK · test_nano_team_env ALL PASS · test_nano_close_named_wt ALL PASS. arch 재현: team_env 43P 0F · named_wt 50P 0F · 접두 검사는 팀 env source 뒤라 팀 값 반영 · env 없는 옛 좌석 문구 바이트 그대로.
- 수용한 변경: planner shared-wt 시험의 전용 WT 이름 v65-s → planner-s (접두 일반화 뒤엔 planner- 이름이라야 「전용 WT 가 있으면 shared 거부」 시험 의미가 성립).
- 잔여 위험(수용): 팀 env 이전에 v65- 이름으로 만든 팀 나노 워크트리는 이름 해석에서 빠짐 → pane cwd 또는 --wt/--branch 로 닫는다.
- 별건(기존 결함 · 이 카드 밖): 살아 있는 byz-cfo-nano- 좌석 1개에 대해 bin-cfo/cfo-env.sh 가 없어 좌석명 자동 로드가 「팀 env 없음」 REJECT 할 수 있음 → CFO 가 FT_NANO_PREFIX 를 직접 주고 닫는지 확인(U3~U5 사례는 직접 env 주입으로 성공).
- 라이브 반영: 라이브 RT ft-nano-close 는 옛 바이트 — spawn·evidence-check 와 한 세트라 FT_BIN 전환(RELEASE 0.4)에서 일괄(단독 cp 금지).

## §34 orchestration-gate 키트·프로젝트 TOP_MODELS 를 홈 값으로 정합 (Sonnet 5.5 워커 면제) — 닫힘 (byz-harness-arch-claude#7 #60097 · master#10 · 2026-10-07)
- 나노 커밋 `a0cf195d87`(3파일: 키트 템플릿 훅 · 프로젝트 .claude/hooks 훅 · test_orch_gate_top_models.sh 신규). 인계 열린 일 6 「게이트 훅 3사본 정합」 중 TOP_MODELS 축.
- master 독립 검증: test_orch_gate_top_models pass=10 fail=0 · test_orch_gate_master pass=36 fail=0 · diff 3파일 · 홈 훅 줄과 같은 문자열. arch 재현: 같은 두 시험 rc=0 · 두 사본 bash -n OK · TOP_MODELS grep 3사본 1종류 · diff 는 TOP 줄뿐(프로젝트 0-b master 좌석 모드·키트 ⓪ 생명주기 무변화).
- 수용한 범위 축소: 안 초판의 「프로젝트 = 키트 바이트」는 철회 — 프로젝트에만 있는 master 좌석 모드(#843)를 지운다. TOP 줄만 바꿨다.
- 잔여 위험(수용): 세 사본의 기능 어긋남은 남는다(키트에만 ⓪ 생명주기 차단 · 프로젝트에만 master 좌석 모드 · 홈엔 둘 다 없음). 키트를 홈에 통째로 설치하면 master 좌석 모드가 없고 ⓪ 이 켜져 비-v65 팀 좌석 개설(tmuxc open 직접)이 막힌다 → 홈 설치는 816(ft-tmux 래퍼 라이브 설치) 뒤.
- 브랜치 위생: nano 브랜치에 harness-ops 문서 커밋 9파일(안·인계·카드)이 같이 실려 있다 — 문서뿐이라 함께 랜딩해도 무해, 단 PR 본문에 «코드 3파일 + 하네스 문서» 로 적는다.
- 라이브 반영: 없음(홈 훅은 09-29 부터 이 값 · 프로젝트 훅은 리포 체크아웃으로 반영).

## §35 press 게이트 ⑦ 좌석 역할(tester·checker 만) · ⑧ 직전 회차 BTS 표 · 통과 시 좌석 허가 파일 (R15 카드 H) — 닫힘 (byz-harness-arch-claude#7 #60119·#60144 · master#10 · 2026-10-07)
- 나노 커밋 `8a46257d97` → 수정 `a97075512b`(3파일: ft-press-gate.sh 추적본+키트 같은 바이트 · test_press_role_bts_gate.sh 신규). 오빠 원문 「bts, poller 없는 press 하는 tester+checker 세션은 없어야한다는게 팩트」의 «발사 전» 쪽.
- master 독립 검증: role_bts_gate 24/24 · baseline_check 19/19 · kit_bin_sync ALL PASS · cmp 동일. arch 재현: 같은 세 시험 ALL PASS · bash -n OK · cmp 동일 · 수정 diff 는 _seat_name 조건 1줄 + 보통 모드 차단 1줄 + 시험 2사례.
- arch 판정 2건: ①FT_PRESS_SEAT 는 SELFTEST 전용 — 보통 모드에서 읽으면 나노가 tester 이름 한 줄로 ⑦ 을 통과하므로 «있기만 해도 막음»(⑥ SELFTEST 상속 규약과 같음). ②사람 경로(BYZ_PRESS_HUMAN)도 ⑧ BTS 표 적용 — 건너뛰는 것은 ⑦ 하나.
- 잔여 위험(수용): 게이트는 «부르는 사람만» 막는다 — 러너·ad-hoc 스크립트가 게이트를 안 부르면 그만이다. 그 구멍은 PTT 누름 순간 검사(카드 V · cdp_helper · v65 소관)가 닫는다. realtime_multi_e2e 는 poller 를 안 띄워 V 대로면 막힌다 → v65 결정 사항.
- 라이브 반영: 라이브 RT ft-press-gate 는 R9 동기 대상(PR 869 랜딩분 · master 집행 대기) — 이 카드 랜딩 뒤 같은 단독 cp 로 ⑦⑧ 까지 한 번에. 켜는 순간 tester·checker 외 좌석의 press 가 막히므로 v65 master 1줄 통지 먼저.

## §36 ft-role-spawn 후계 첫 발주에 고스트 서제스천 1줄 — 전 역할 (R21) — 닫힘 (byz-harness-arch-claude#7 #60111·#60223 · master#10 · 2026-10-07)
- 나노 커밋 `94e94b88fa`(3파일: ft-role-spawn.sh 추적본+키트 같은 바이트 2줄 · test_role_spawn_name.sh 9줄). 오빠 「심각하네 그거 서제스천인데 … 착각하지 마라 메인 지침」의 승계 경로 쪽 — 본체(전역 CLAUDE.md 하드 룰 10 · BOOT 17 · codex 동기 블록 · 승계 6단계 문서)는 홈 설치로 이미 반영·cmp 일치.
- master 독립 검증: test_role_spawn_name ALL PASS · test_kit_bin_sync ALL PASS · cmp 동일 · diff 3파일. arch 재현: 같은 두 시험 ALL PASS · bash -n OK · cmp 동일 · BODY diff 는 주석 1 + 문장 1.
- 잔여 위험(수용): 지금 떠 있는 세션은 NOTICE(design/harness/NOTICE-ghost-suggestion-20261007.md) + 팀 master 통지로만 덮인다. ft-nano-spawn BODY 에는 넣지 않았다(나노는 남의 pane 을 읽지 않는다).
- 라이브 반영: 라이브 RT ft-role-spawn 은 R13 크론 줄도 없는 옛판 — 랜딩 뒤 추적본 단독 cp + cmp(같이 메워짐).
- 별건: 이 나노가 스크래치 폴더 정리 명령으로 block-destructive 오탐 1건(실파괴 0) — governance §7 오탐 경로(기록·묶음 알림) 그대로.

## §37 나노 닫기 cherry·증거 게이트가 원격 추적 ref(origin/<feat>)를 받게 + 닫기 직전 fetch (R22) — 닫힘 (byz-harness-arch-claude#7 #60193·#60231 · master#10 · 2026-10-07)
- 나노 커밋 `c0165cbc35`(cherry-gate·close·evidence-check 추적본+키트 같은 바이트 · test_nano_feat_remote_ref.sh 신규). CFO 실측: origin/main 은 「브랜치 없음」 REJECT, main 은 로컬 main 이 약 18k 커밋 뒤라 대조가 끝나지 않음.
- master 독립 검증: test_nano_feat_remote_ref fail=0 · kit_bin_sync·role_spawn_name ALL PASS · 3스크립트 cmp 동일. arch 재현: 같은 시험 + test_nano_team_env·test_nano_close_named_wt ALL PASS · 기존 cherry pytest 3파일 39 passed · bash -n OK · fetch 실패 → bad 1건 REJECT 확인.
- 설계 결정: 원격 사용은 값을 `origin/<b>` 로 «명시»할 때만(main→origin/main 자동 치환 0) · fetch 실패 시 옛 ref 대조 0(#0 RULE) · 좌석(nano) 브랜치는 로컬만.
- arch 정정: R18(§ 없음 · PLAN-r18) 에서 arch 가 정한 cfo-env `FT_NANO_FEAT=main` 은 틀린 값이었다 → `origin/main`(master 반영 완료). harness-env `feat/slack-inbound-820`(옛 트랙) → `ops/main-base`(하네스 나노는 ops/main-base 에서 갈라지고 master 가 그 줄기에 cherry-pick 한 뒤 닫는다 · 로컬 브랜치라 fetch 0).
- 잔여 위험(수용): 원격 ref 를 쓰는 팀은 닫기마다 네트워크 1회 — 실패는 REJECT(조용한 통과 0). 라이브 RT 3파일은 옛판 → 랜딩 뒤 단독 cp(816 일괄과 별개로 이 3파일만).

## §38 gh 가드에 PR 쓰기 5종 차단 + Tank 래퍼 pr-edit·pr-close (R6 ②) — 닫힘 (byz-harness-arch-claude#7 #60270·#60358 · master#10 · 2026-10-07)
- 나노 커밋 `fb18b3a370`(4파일: gh-issue-author-guard 템플릿 · ft-gh-as-tank.sh 추적본+키트 같은 바이트 · test_gh_as_tank.sh). base = PR 874 병합 1840d5e9f6.
- master 독립 검증: test_gh_as_tank rc=0 · kit_bin_sync ALL PASS · 래퍼 cmp 동일 · `gh pr edit 5 --body x` rc=2 + Tank 안내. arch 재현: 같은 두 시험 rc=0 · bash -n OK · 가드 직접 호출 7사례(차단 3 · 통과 4 — 코멘트 없는 close · 라벨만 edit · graphql query · 개인 리포) 기대대로.
- 설계 결정(승인 #60270): PR 리뷰 판정(approve·request-changes)은 래퍼 대체 없이 차단 — 사람(오빠)만 · 코멘트는 pr-comment.
- 잔여 위험(수용): 가드는 클라이언트 쪽 장치라 훅을 안 거치는 경로(다른 셸·토큰 직접 사용)는 못 막는다(§21 한계 그대로) · `gh pr review 5`(플래그 없음 · 대화형)는 통과로 둠 — 좌석은 대화형을 못 쓴다.
- 라이브 반영: 홈 `~/.claude/hooks/gh-issue-author-guard.sh` cp + cmp + `gh pr edit 1 --body x` 차단 실측 1회 · 라이브 RT ft-gh-as-tank.sh 단독 cp — 둘 다 master 집행(랜딩 뒤).
## §39 라이브 도구 폴더 ↔ main 키트 드리프트 검사 — tick 경고 + 나노 spawn·close 입구 BLOCK (Issue 816 ②③) — 닫힘 (byz-harness-arch-claude#8 #60537·#60568 · master#10 · 2026-10-07)
- 나노 커밋 `66cee5fd68`(9파일: ft-live-bin-drift-check.sh 신규 · ft-nano-spawn.sh · ft-nano-close.sh · ft-tick.sh — 추적본+키트 같은 바이트 · test_live_bin_drift_check.sh). base = 9b10aba7b2(RELEASE 0.4 라이브 1:1 교체 뒤).
- master 독립 검증: test_live_bin_drift_check ALL PASS · kit_bin_sync ALL PASS · nano_feat_remote_ref fail=0 · role_spawn_name ALL PASS · 4스크립트 cmp 동일. arch 재현: 같은 시험 ALL PASS · kit_bin_sync ALL PASS · 실제 라이브 bin 에 새 검사 1회(읽기만) `OK ref=origin/main@16201f18ea7c files=74`.
- 설계 결정(카드 · 816 범위 축소 승인 planner #60527 · issues #60531): 기준 = git ref(origin/main) 트리 blob — 체크아웃 아님(로컬 main 18k 뒤) · 검사는 fetch 0 · 자동 cp 0 · ref 못 풀면 exit 3(조용한 통과 0) · spawn·close 우회 스위치 0(끄는 것은 tick 경고 FT_TICK_DRIFT=0 하나) · 설치 꼴(*/.fable-team/bin) 밖 실행은 검사 건너뜀(추적본 개발·기존 시험 무변화).
- 운영 순서(새 규칙): 키트 bin 을 바꾸는 랜딩은 «origin/main 병합 → fetch → 라이브 cp → 그 나노 close». ★ops/main-base 커밋만으로 라이브 cp 하면 라이브 ≠ origin/main 이 돼 전 팀 spawn·close 가 BLOCK 된다★ — cp 는 main 병합 뒤에만.
- 잔여 위험(수용): origin/main 이 다른 랜딩으로 앞서가면(키트 bin 변경 포함) 라이브 cp 전까지 전 팀 spawn·close 가 막힌다 — 의도된 동작(1:1 유지) · 풀이 = master 라이브 cp. CFO 틱(com.byz.ft-tick-cfo)은 라이브가 아니라 별도 사본 `.fable-team/bin-cfo/ft-tick.sh` 를 돌린다 — 설치 꼴(*/.fable-team/bin) 밖이라 drift_watch 는 거기서 꺼져 있고, 그 사본 자체도 이 검사 범위 밖(키트와 어긋날 수 있는 두 번째 자리 · 후속 후보).
- 라이브 반영(master 집행): main 병합 → fetch → 라이브 bin 에 새 검사 + spawn·close·tick 4파일 cp → 새 검사 `OK` 1줄 → 나노 close. ★tick 경고(drift_watch)는 틱 재개 시 자동 적용 — 지금 launchd `com.byz.ft-tick` 미적재(/tmp/ft-tick.log 마지막 2026-10-03 20:39 · 재적재는 planner 판단)★ · spawn·close 입구 BLOCK 은 틱과 무관하게 cp 직후부터 작동.

## §40 나노 첫 발주문(ft-nano-spawn BODY)에 「press 금지」 1문장 (R15 T ①) — 닫힘 (byz-harness-arch-claude#8 #60760·#60766 · master#11 #60761·#60775 · 2026-10-08)
- 나노 커밋 `613122a5cc`(3파일: ft-nano-spawn.sh 추적본+키트 같은 바이트 · test_nano_spawn_body_press.sh 신규).
- master 독립 검증: 새 문장 BODY 218행 1줄 변경 · 추적본↔키트 cmp 동일 · test_nano_spawn_body_press·test_kit_bin_sync·test_nano_team_env·test_live_bin_drift_check 전부 rc=0. arch 재현: test_nano_spawn_body_press ALL PASS(음성 대조 포함) · 옛판 대비 «앵커 뒤 1문장 삽입» 외 바이트 변화 0(exact-insert True).
- 설계 결정: 강제는 이미 ft-press-gate ⑦(R15 H · §35)이 한다 — 이 카드는 «시작 시 알림»뿐(동작 변화 0). spawn --dry-run 은 BODY 를 출력하지 않아 시험은 정적 grep.
- 최종 DA 소환: 안 함 — 문자열 1문장 삽입·제어 흐름 0·바이트 대조로 범위 이탈 0 확인(arch 서명 면제 그대로).
- 잔여: 정본 충돌 2곳(design/v65/SEATBELT-README.md:211 규칙 15 · docs/rules/single_set_testing.md:25)이 아직 「나노 press」 를 허용하는 문장 — v65·문서 몫(master#11 → planner 경유 통지). 하네스 쪽 조치 끝.
- 라이브 반영(master 집행): main 병합 → fetch → 라이브 bin 에 ft-nano-spawn.sh cp → ft-live-bin-drift-check.sh OK 1줄.

## §41 test_regress_pack 의 「예시 2행」 고정 기대 → 형식 검사 (야간 자율 단위 3) — 닫힘 (byz-harness-arch-claude#8 #60847 · master#11 #60854 · 2026-10-08)
- 나노 커밋 `4143c964f1`(1파일: tests/harness/test_regress_pack.sh · +7/−3).
- 조사 결론(arch): 늘 빨간 원인 = 시험 기대 낡음 — 10-06 시험이 팩 «정확히 2행»을 요구했는데 10-07 7b04fc2c4f 가 실제 회귀 행 #834 를 추가해 3행. 팩 3행 모두 키 9 동일(파일 결함 0).
- master 독립 검증: bash·/bin/bash 3.2 둘 다 rc=0 fail=0. arch 재현: 같은 두 실행 fail=0 + 음성 대조(첫 행 repro_cmd 키 삭제 복사 팩 → FAIL · fail=1).
- 최종 DA 소환: 안 함 — 시험 1줄 기대 변경 · 제품·하네스 코드 0 · 음성 대조로 검사가 여전히 결함을 잡는 것 확인.
- 효과: 하네스 시험 32개 중 «늘 빨간» 것 0(bash5 기준) — 다음 회귀가 빨간색으로 보인다.
- 라이브 반영: 불요(시험 파일).

## §42 tmm 을 bash 4+ 전용으로 명시 — 3.2 가드 + 가드 동작 시험 (원장 R24 · 야간 자율 단위 2) — 닫힘 (byz-harness-arch-claude#9 · master#11 #60866 · 2026-10-08)
- 나노 커밋 `2f6562f17e`(반송 r1 재작업 · 2파일: scripts/harness-install/tmm/tmm · tests/harness/test_tmm_group.sh). r0 `3b534a71e6`(소문자 6곳 _lc 교체)는 이 커밋으로 되돌려졌다 — base `293199de75` 대비 순변경 = 추가 25줄·삭제 0.
- 조사 결론(arch#8 반송 r1): tmm 은 연관 배열(declare -A)을 써서 bash 3.2 에선 소문자만 고쳐도 본 경로가 못 돈다 · _lc 는 서브셸+tr 이라 3배 느림 → «3.2 호환» 대신 «bash 4+ 전용 명시 + 3.2 로 불리면 bash 4+ 후보로 재실행, 없으면 문구+rc=1 로 멈춤».
- master 독립 검증: _lc 0건 · bash·/bin/bash 3.2 test_tmm_group rc=0 ALL PASS · 후보 없음 시 rc=1 + 「tmm: bash 4 이상 필요 (지금 3.2.57)」.
- arch 재현(#9): ①base 대비 tmm 변경은 가드 13줄 추가뿐 · 삭제 0 → 소문자 6곳(202·210·215·221·232·236행)이 base 와 바이트 동일. 7번째 `,,}` 는 가드 주석(59행) ②시험 bash5 rc=0 · /bin/bash 3.2 rc=0 · 가드 PASS 줄 2개(후보 없음 rc=1+문구 · 후보 /opt/homebrew/bin/bash 재실행 rc=0) ③cat_of 이름 150개: 새판 0.84 s vs base 0.86 s(속도 원복) ④음성 대조: 가드 없는 base 를 /bin/bash 3.2 + 후보 없음으로 -h → rc=0·문구 없음 → 시험 첫 줄이 FAIL 로 잡는다.
- 카드 지시와 다른 1점(수용): 후보 있음 시험을 doctor 가 아니라 -h 로 — 소스 트리에선 helper 부재로 bash5 직접 실행 doctor 도 rc=1 이라 가드 판별에 못 쓴다. -h 도 exec 재실행 경로를 그대로 지난다.
- 최종 DA 소환: 안 함 — 하네스 도구 1개 진입부 가드 + 시험 · 제품 코드 0 · 3.2/5 양쪽 실행 + 음성 대조로 검사가 결함을 잡는 것 확인. HOLD 1회(반송 r1) 뒤 1회 통과.
- 효과: macOS 기본 bash 3.2 에서 tmm 이 «조용히 반쯤 도는» 대신 homebrew bash 로 재실행되거나 원인 문구를 내고 멈춘다.
- 남은 것(카드 밖 · 사람 승인 영역): ~/.tmm/versions/ 새 버전 설치·current 전환 · byzs-mac-mini homebrew bash 설치(원격 쓰기) — 아침 브리핑 결정 후보 ③④.
- 라이브 반영: 미반영(설치는 위 사람 승인 뒤). 정본 영향 없음: tmm 추적 사본·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 2f6562f17e98fade1c9333914108f85b880edc8e · 시험: bash tests/harness/test_tmm_group.sh rc=0 · 이슈: 0`

## §43 아침 매거진 ① 창 계산 + 자료 6종 수집 → 구조 모델 (판정 347 · 나노 magazine-collect) — 닫힘 (byz-harness-arch-claude#9 · master#12 #61017 · 2026-10-08)
- 나노 커밋 `0216631058`(브랜치 nano/magazine-collect · 신규 9파일: scripts/harness-install/slack-mirror/magazine_window.py · magazine_collect.py · magazine_collect_git.py · magazine_collect_gh.py · magazine_collect_mbox.py + tests/scripts/test_magazine_{window,collect_mbox,collect_git,collect_gh}.py · 기존 파일 0 · 최대 113줄).
- 설계 DESIGN-morning-magazine-20261008.md §1·§8 · DA 사전검증 APPROVE(DA-magazine-20261008.md §7 · HOLD 1 → r1).
- master 독립 검증: pytest 33 passed · ruff clean · 네트워크/push 호출 grep 0 · 실자료 재실행 일치.
- arch 재현(#9): ①pytest 33 passed ②구조 모델 키 11개 = 설계 §8 계약 그대로(publish 나노와의 계약 유지) ③실자료 `collect("2026-10-08")`: mbox 2801 · HIL 8 · 깨진 줄 0 · 머지 35 · Issue 열림 18·닫힘 18 · 판정 36 · 문서 2 · 승계 47 · 신규 77 ④DA HOLD-M2 사례: 예약 모드 10-09 07:30 → D=10-08(창 10-07 08:00~10-08 08:00) · 10-08 09:30 → D=10-08 · 수동 `--date 2026-10-09` 를 07:59 에 → raise · 건너뛴 날(10-06→10-08) = [10-07] ⑤음성 대조: PATH 비움 → MagazineError(git fetch 실패) — 반쪽 결과 0.
- 최종 DA 소환: 안 함 — 사전검증 APPROVE 범위 안의 구현 · 읽기 전용 수집(쓰기·게시 0) · 실자료·음성 대조로 확인.
- 범위 밖 메모(완성 전 · publish 나노 렌더 몫): ①HIL 은 8개에서 자르며 «남은 수» 칸이 계약에 없다 — 설계 §2 「남은 수」는 렌더가 표시 불가 → 렌더는 「최대 8건」으로 표기(계약 변경 0) ②신규 좌석 77 · 승계 47 은 한 장에 길다 — 렌더가 팀별 묶음·상한을 둔다 ③경계: git `--since/--until` 은 양끝 포함, mbox 는 [start,end) — 정각 08:00:00 커밋이 이틀에 겹칠 수 있다(빈도 낮음 · 표시만).
- 라이브 반영: 없음(설치·launchd 는 publish 나노 + 수동 1회 뒤). 정본 영향 없음: 하네스 슬랙 키트 신규 모듈·시험 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 0216631058… · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0`

## §44 아침 매거진 ② 렌더·요약·PDF·슬랙·push·CLI·launchd 템플릿 (판정 347·348 · 나노 magazine-publish) — 닫힘 (byz-harness-arch-claude#9 · master#12 #61029 · 2026-10-08)
- 나노 커밋 `9b4a843abf`(본 구현) · `33261afc28`(collect 접점 맞춤) · 반송 r1 재작업 `2389619b4f` [structure] 시험 3파일 분리 · `2a820d879e` [fix] 표식 정확 일치 + done 선확인. 브랜치 nano/magazine-publish(collect 위 rebase).
- 신규: scripts/harness-install/slack-mirror/ magazine_render·magazine_summary·magazine_publish·magazine_slack·magazine_git·magazine_pdf·magazine_emit·byz_morning_magazine.py · com.byz.ft-magazine.plist.template · install-magazine.sh + 시험 tests/scripts/test_magazine_{render,summary,publish,git,cli,pdf}.py · _magazine_fakes.py · tests/harness/test_magazine_plist.sh. 미러 모듈 수정 0.
- 설계 DESIGN-morning-magazine-20261008.md(§6 = 오빠 판정 348 ops/magazine 전용 push) · DA 사전검증 APPROVE(DA-magazine-20261008.md §7).
- 반송 r1(arch#9 · HOLD 1회): ①`find_root` 가 첫 줄 «포함» 매칭 — 같은 봇·같은 채널의 슬랙 미러 뿌리 글(「#885 시작 — 아침 매거진 2026-10-08 …」)을 매거진 뿌리 글로 채택(재현 ts=1.0) → 매거진 글 0 + PDF 가 미러 스레드로 ②done 확인이 수집·요약·push 뒤(설계 §8 순서 위반 · 재실행마다 ops/magazine 새 커밋) ③시험 파일 290줄 > 200 한도.
- master 독립 검증(r1 뒤): 시험 76 passed · plist ALL PASS · ruff clean · 200줄 초과 0 · find_root 첫 줄 정확 일치.
- arch 재현(#9): ①시험 76 passed · plist ALL PASS ②find_root: 미러식 첫 줄만 → None · 정확한 첫 줄(`*아침 매거진 2026-10-08*`) → 그 ts · bot_id 없는 글 무시 ③CLI done 상태 → 수집·요약·PDF·git 호출 0 시험(test_done_state_skips_before_collect_summary_pdf_git) ④실자료 dry-run(`--date 2026-10-08 --summary-cmd /usr/bin/false`): 요약 실패가 결정적 3줄 + 「(요약 실패: 요약 종료코드 1: 출력 없음)」 + ERROR 로그로 보임(DA §3 수락 계약) · md 245줄(결론→오빠 할 일→바뀐 것→근거→각주표) · PDF 1쪽(폭 A4 · 높이 4381pt) ⑤DA HOLD-M1 장애 주입 4종 시험 존재·통과(응답 유실 · 상태 쓰기 실패 · PDF 실패 · posting+표식 없음).
- 최종 DA 소환: 안 함 — 사전검증 APPROVE 범위 안 · 반송 1회로 닫힘 · 실 게시 경로는 다음 단계 수동 1회가 확인.
- 범위 밖 메모(완성 후): ①PDF 는 «한 장»(높이 = 본문) · 한도 18000px(오늘 약 5840px = 3배 여유) — 넘으면 raise(조용한 절단 0)라 그날 매거진이 «실패 1줄»이 된다. 넘는 날이 생기면 여러 쪽 A4 로 전환 ②push 성공 뒤 슬랙 실패 → 다음 실행이 요약을 다시 만들어 ops/magazine 에 커밋 1개 더(링크는 최신 sha) — 무해 ③PDF 업로드 성공 뒤 done 기록 실패 → 다음 실행이 PDF 를 한 번 더 붙임(뿌리 글은 1개 유지).
- 다음(master 집행): cherry-pick → 수동 1회 실 슬랙 `--date 2026-10-08 --no-push` → planner 1줄(슬랙 ts · PDF 경로) → `install-magazine.sh --load` → launchd 다음 발사 시각 보고.
- 라이브 반영: 아직 없음(위 순서). 정본 영향 없음: 하네스 슬랙 키트 신규 모듈·시험·plist 템플릿 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 2a820d879e… · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0`

## §45 아침 매거진 「오빠 할 일」 = 답이 안 간 요청 + 요약 3줄 구체화 (판정 350 후속 · 나노 magazine-hil-pending-summary) — 닫힘 (byz-harness-arch-claude#9 · master#12 #61090 · 2026-10-08)
- 나노 커밋 `3d5fcaff2a`(magazine_collect_mbox.py · magazine_render.py · magazine_summary.py · 설계 §1/§8 2줄 · 시험 4파일).
- 원인(arch#9 실측 · master#12 대조 #61054 반영): 첫 호 「오빠 할 일 8건」 = planner 수신 쪽지 중 `[HIL` «포함» 80건을 8에서 자른 값. 접두 `[a->b]` 를 뗀 본문이 `[HIL` 로 «시작»하는 요청 45 · 정확 이름 기준 미답 2 → 계보(`#N` 뗀 이름) 기준 미답 1(seq 60339 은 22:13 후계 #146 에 「#60339 답」 #60363 이 갔다).
- 바뀐 것: 요청 = 접두 뗀 본문 시작이 `[HIL` · 답 = 요청 뒤~창 끝 planner 발신 쪽지가 요청 좌석 «계보»로 1건 이상 · `mbox.hil_asked` 칸 추가 · `hil` = 미답 목록(상한 없음 · 표시 8줄 + 「외 N건」) · 본문 「요청 N건 중 답이 안 간 M건」 · 요약 facts 4칸(미답 요청 · feature/fix 머지 우선 · 닫힌 이슈 · 건너뛴 날/깨진 줄) + 프롬프트 칸 3개(결과 1 · 결정할 것 1 · 주의 1 · 묶음말 금지).
- master 독립 검증: 매거진 시험 82 passed · plist ALL PASS · ruff clean · 200줄 초과 0 · 실자료 hil_asked=45 · len(hil)=1(60960).
- arch 재현(#9): ①시험 82 passed ②회신 판정이 planner «발신»에만 걸림(magazine_collect_mbox.py:112) · 요청보다 «뒤» 회신만 셈 ③실 LLM dry-run(`--date 2026-10-08 --force`): 뿌리 글 3줄 = 「수리 버튼 백엔드가 구현 완료됐고 35건의 머지가 이루어졌어요」 「판정 341 집행이 운영자 토큰 부재로 진행이 막혀 있어요」 「로컬 테스트에 11건의 기존 실패가 남아 있어요」 + 「오빠 할 일이 1건 있어요」 — 첫 호의 일반론(「주요 기능들의 개발이 완료」)에서 기능·막힘 이름이 그대로 나온다.
- 최종 DA 소환: 안 함 — 사전검증 면제(게시 경로·상태기계 변경 0) · 집계 규칙과 프롬프트 문장만 · 실자료로 확인.
- 범위 밖 메모(완성 후 · 후속 카드 불요): 요약에 「판정 341」 같은 판정 번호가 남는다(프롬프트의 «번호 금지»는 `#123` 형식을 예로 든다). 오빠가 판정 번호로 결정을 찾으므로 남겨 두는 편이 낫다고 본다 — 오빠가 빼길 원하면 프롬프트 1줄.
- 라이브 반영: 랜딩 뒤 `install-magazine.sh`(복사만 · `--load` 불요 — 장기 루프 아님)로 ~/.hermes/scripts 갱신 → 다음 08:00 호부터. 정본 영향 없음: 하네스 슬랙 키트 모듈·시험·하네스 설계 2줄 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 3d5fcaff2a… · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0`

## §46 제안서 흐름 정본·템플릿·governance ④행 초안 (판정 352 · 나노 proposal-docs) — 닫힘 (byz-harness-arch-claude#10 · master#12 #61129 · 2026-10-08)
- 나노 커밋 `e56fed8f3f`(3파일 신규 · 161줄 추가 · 제거 0): docs/rules/proposal_flow.md 76줄 · docs/rules/proposal_template.md 34줄 · design/harness/drafts/proposal-flow/fable-team/references/main-team-governance.md(홈 사본 + ④행).
- 설계 DESIGN-proposal-flow-20261008.md(§1·§2·§4) · DA 사전검증 HOLD 1 → APPROVE(DA-proposal-flow-20261008.md §6 · #61101).
- master 독립 검증(#61129): 신규 3파일만 · 홈 governance 와 diff = ④행 + 정본 인용 줄뿐 · 제거/변경 0.
- arch 재현(#10): ①`git show --stat e56fed8f3f` = 3 files changed, 161 insertions(+) · 미커밋 = .serena/project.yml(자동변경 노이즈)뿐 ②`diff 홈 governance 초안` = `21a22,23` 추가 2줄(④ 제안서 행 + `> 정본 docs/rules/proposal_flow.md`) — 완료 조건 「추가 2줄뿐」 일치 ③정본 상태 문자열 `grep -c`: 초안=4 · 컨펌 대기=3 · 수정 요청 r=2 · 승인 — 판정=4 · 폐기 — 판정=2(5종 전부 실재 · em dash) ④템플릿 `grep '^## '` = 결론 · 오빠가 결정할 것 · 제안 · 영향 범위 · 되돌림 · 검증 · 근거 · 각주표(설계 §2 순서 그대로) · 머리 `- 상태:` `- 팀·나노:` `- 오빠 원문:` `- 자료:` 실재 ⑤정본 3행에 「자동 로드 파일이 아니다(#3 RULE)」 · `.claude/rules`·CLAUDE.md 참조 0 ⑥도구 3개 이름·인자·위치(정본 56~58행)가 설계 §3 계약과 같음 — tools 나노와의 계약(상태 머리줄 · 템플릿 칸 · 명령 이름) 변경 0.
- 최종 DA 소환: 안 함 — 문서 3장 · 사전검증 APPROVE 범위 안 · 계약 3종 그대로.
- 라이브 반영: 랜딩 뒤 master 가 `cp` 초안 → `~/.claude/skills/fable-team/references/main-team-governance.md`(백업 .bak-1008-proposal) + `cmp` rc=0. 키트 bin 반영 0. docs/rules 는 리포만(설치 대상 아님).
- 정본 영향: docs/rules 에 하네스 절차 정본 1장 신규 · docs/architect 제품 정본 변경 없음.
- 범위 밖 메모: 정본의 「찾는 길 = ft-harness-info.sh find 제안서」 는 랜딩 뒤 실제로 잡히는지 tools 나노 닫힘(§47) 때 1회 확인.
- 카드 증거 줄: `세트: e56fed8f3f491f70d77f2900f0f9115c1263fbed · 시험: 없음(문서) — 정본, 템플릿, governance 초안 3파일 · 이슈: 0` (이유 칸에 «·» 가 있으면 evidence-check 정규식이 REJECT — 카드 완료 조건 문안 자체가 그 형식이라 고쳐 씀)

## §47 제안서 흐름 ② 도구 3개(카드·슬랙 발행·승인 확인+등록) + magazine_slack 인자화 + 시험 (판정 352 · 나노 proposal-tools) — 닫힘 (byz-harness-arch-claude#10 · master#12 #61168 · master#13 #61201 · 2026-10-08)
- 나노 커밋 `002ae4dbf0`(본 구현) · `bf06faa21a` [structure] 시험 3파일 분리(200줄 · master 반려 1) · `4bf44359e4` [fix] 머리 「- 상태:」 줄 2개 이상 거부(arch 반송 r1). 브랜치 nano/proposal-tools.
- 신규: scripts/harness-install/proposal/ft-proposal-card.sh · ft-proposal-register.sh · scripts/harness-install/slack-mirror/byz_proposal_publish.py · 시험 tests/harness/test_proposal_{card,register}.sh · tests/scripts/test_proposal_publish{,_faults}.py · _proposal_fakes.py. 수정: magazine_slack.py(`find_first_line` · `upload_file(content_type)` · 기존 `find_root`·`upload_pdf` 1줄 위임) · install-magazine.sh 복사 목록 1개. 키트 bin 추가 0(드리프트 BLOCK 없음).
- 설계 DESIGN-proposal-flow-20261008.md §3·§7 · DA 사전검증 HOLD 1 → APPROVE(DA-proposal-flow-20261008.md §6).
- master 독립 검증: r0(#61168) 시험 95 passed · 셸 2종 ALL PASS · ruff clean · 200줄 초과 0 → r1(#61201) 14 passed · 셸 ALL PASS · 184줄 이하.
- 반송 r1(arch#10 #61183 · 1회): 머리(첫 `## ` 전)에 「- 상태:」 줄이 2개(승인 — 판정 351 + 폐기 — 판정 352)면 register 가 첫 줄만 보고 `REGISTERED #901` rc=0 · Tank 2회 — 머리줄을 «교체» 대신 «추가»로 갱신하면 폐기된 제안서가 Issue 로 등록된다. publish 도 첫 줄만 봤다.
- arch 재현(#10): ①r1 뒤 매거진+제안서 시험 96 passed(.venv python) · test_proposal_register.sh ALL PASS · test_proposal_card.sh ALL PASS ②register 확인 실패 18건 전부 「Tank 호출 0회」 · 승인 — 판정 351 → create 1 + label 1 · create 실패 → label 0 ③publish 장애 주입 5종 PASS(r0 응답 유실 채택 · r1 응답 유실 정확 첫 줄 채택 · r1 상태 쓰기 실패 채택 · r1 첨부 실패 → 첨부만 · r1 posting+표식 없음 → ERROR exit 1) + r2 답글은 r1 로 채택 안 함 ④독립 주입 7종: 하이픈 · 머리줄 꼬리 글 · 전각 숫자 · 본문 Issue # · 검증 칸 공백 → 각각 rc=1 tank=0 · 머리 상태 줄 2개 → r1 뒤 register 「REJECT 머리의 「- 상태:」 줄이 정확히 1개가 아니다 … 2개」 tank=0 · publish `--dry-run` rc=1 「머리의 「- 상태:」 줄이 2개 — 정확히 1개여야 한다」 ⑤본문(첫 `## ` 뒤)의 「- 상태:」 줄은 머리줄이 아니라 무시 — 설계 «머리줄 한 줄이 정본»대로.
- 최종 DA 소환: 안 함 — 사전검증 APPROVE 범위 안 · 반송 1회(머리줄 판정 강화 · 계약 3종 변경 0)로 닫힘.
- 범위 밖 메모(완성 후): raw Tank 경로(ft-gh-as-tank.sh create)의 전역 차단은 DA §10 수락 범위 밖 — 정본 proposal_flow.md 에 «register 진입점으로만» 선언으로 남음. 「ft-harness-info.sh find 제안서」 가 랜딩 뒤 잡히는지 1회 확인(§46 메모 이월).
- 라이브 반영: 랜딩 뒤 `install-magazine.sh`(복사만 · `--load` 불요)로 `byz_proposal_publish.py` + 바뀐 `magazine_slack.py` 를 ~/.hermes/scripts 에. 셸 도구 2개는 리포 경로 호출(설치 0). 정본 영향 없음: 하네스 도구·슬랙 키트·시험 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 4bf44359e495b6d70f4696dcc1066fdb5e251366 · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py -q rc=0 · 이슈: 0`

## §48 아침 매거진 풀 디테일 ① 수집 — 구조 모델 새 칸 detail (판정 354 · 나노 magazine-detail-collect) — 닫힘 (byz-harness-arch-claude#10 · master#13 #61230·#61240 · 2026-10-08)
- 나노 커밋 `4c5be801af`(본 구현) · `fe1ff62a56` [fix] merge_bodies 를 merges 칸 sha 로만(arch 반송 r1). 브랜치 nano/magazine-detail-collect(base 6594f5c8ae — proposal-tools 랜딩 전이라 cherry-pick 은 ops/main-base 위로).
- 신규: magazine_collect_detail.py(176줄 · D1 완성 카드 · D2 판정서 절 · D4 머지 본문 · D7 닫힘 줄 · 부록) · magazine_collect_open.py(D6 열린 카드·요청 원장·HOLD·BREACH) · magazine_collect_decisions.py(D3 판정 원문·relay·되돌림) · 시험 test_magazine_collect_{detail,decisions}.py. 수정: magazine_collect.py(detail 칸 조립 · refs·byz_root 인자 · MAGAZINE_REFS) · magazine_collect_gh.py(닫은 이슈 마지막 댓글) · _magazine_fakes.py DETAIL_FIXTURE. 기존 11칸 불변.
- 설계 DESIGN-magazine-full-detail-20261008.md §1~§3 · DA 사전검증 HOLD 1 → APPROVE(DA-magazine-fulldetail-20261008.md §r1 · 수집은 DA 범위 밖 — 볼 곳 3은 ②③ 몫).
- master 독립 검증: r0(#61230) 매거진 시험 96 passed · ruff clean · 최대 196줄 → r1(#61240) 재검증.
- 반송 r1(arch#10 #61237 · 1회): merge_bodies 가 3 ref 전부의 first-parent 커밋 881건(main 35 + ops/main-base 151 + feat/v6-realtime-live 703) — 설계 D4 는 «main 에 들어간 것»(merges 칸과 짝)이라 846건이 쓰이지 않는 데이터(모델 648KB 대부분). 설계 §2 D4 문구가 «<ref>» 로 모호했던 건 arch 쪽 — 설계도 함께 고침.
- arch 재현(#10): ①r1 뒤 매거진 시험 96 passed(.venv python) ②실자료 collect("2026-10-08") 31.2초 · 모델 481KB · refs 3(origin/main · ops/main-base · origin/feat/v6-realtime-live) · merges 35 = merge_bodies 35(본문 없는 머지 0) · units 72 · verdict_sections 24 · decisions 35 · open cards 137 · requests 21 · holds 0(창 안 DA 파일 마지막 줄이 전부 APPROVE) · breaches 1(state/gce-op-model/BREACH.md) · seats_closed 54 · appendix 5 · issue_evidence 18 = issues_closed 18 ③r1 시험: merges=[c1] 이면 ops 의 창 안 커밋 o1 본문 제외 · merges 빈 목록이면 {} .
- 최종 DA 소환: 안 함 — 수집은 사전검증 APPROVE 설계 범위 안 · 반송 1회(데이터 범위 축소 · 스키마 변경 0)로 닫힘.
- 범위 밖 메모(완성 후): ①ref 창 시작 sha 가 세 ref 모두 106eb6ea 로 같다 — `rev-list -1 --before` 가 그 ref 에서 «도달 가능한» 커밋 중 창 시작 전 최신을 골라서(main 커밋이 세 갈래 모두에 있음). D2·D7 diff 는 트리 비교라 결과 영향 없음 · 갈래 고유 시작점이 필요해지면 `--first-parent` 추가 1곳 ②units 72 는 v65 완성 카드가 대부분 — ③ eli5 단위 수와 직결(§49 참조).
- 라이브 반영: ②③ 랜딩 뒤 `install-magazine.sh`(복사 목록에 새 수집 모듈 3개 — ② 카드 몫). 정본 영향 없음: 하네스 슬랙 키트 수집 모듈·시험 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: fe1ff62a56… · 시험: python3 -m pytest tests/scripts/test_magazine_collect_detail.py -q rc=0 · 이슈: 0`

## §50 아침 매거진 풀 디테일 ② 렌더·여러 쪽 PDF·슬랙 2파일·--reattach (판정 354 · 나노 magazine-full-render-publish) — 닫힘 (byz-harness-arch-claude#10 · master#13 #61293·#61309 · 2026-10-08)
- 나노 커밋 `718fa80469`·`1adab4271e` [structure] magazine_render 1부 블록·제목 정리 공개(행동 변경 0) · `2c735286bd` [feature] 본 구현 · `3cabf8cb13` [test] CLI 모드 시험 순서 · `aeea2736ea` [fix] md 외부 본문 인용 처리 + eli5 실패 안내 줄(arch 반송 r1). 브랜치 nano/magazine-full-render-publish(base 55d5812196).
- 신규: magazine_render_full.py · magazine_attach.py(첨부 멱등 F1) · magazine_cli_args.py(--reattach 배타 F2) · magazine_reattach.py · 시험 test_magazine_render_full.py 외. 수정: magazine_emit·magazine_pdf(여러 쪽 A4 · 한 장 한도 삭제 · pages)·magazine_publish(pdf_done · set_phase 가 files·revs 보존)·magazine_slack·byz_morning_magazine·install-magazine.sh(①③ 모듈은 있으면 복사·없으면 WARN).
- 설계 DESIGN-magazine-full-detail-20261008.md §1·§4·§5·§6 · DA 사전검증 HOLD 1 → APPROVE(DA-magazine-fulldetail-20261008.md §r1 · F1 첨부 멱등 · F2 모드 배타 · F3 사실 영역).
- master 독립 검증: r0(#61293) 시험 124 passed · plist ALL PASS · ruff clean · 최대 182줄 → r1(#61309) 125 passed.
- 나노 장애 주입 14종(보고 원문): PDF 뒤 HTML 실패 → PDF 추가 0 · PDF complete 뒤 응답 유실 → 파일 추가 0 · pdf_done/done 저장 실패 → 추가 0 · 불명 → getUploadURL 0·complete 재호출 0·ERROR · 시도 기록 저장 실패 → 전송 0 · reattach 뒤 날짜 레코드 phase/ts/at 불변 · 답글 응답 유실·상태 쓰기 실패 → 답글 추가 0 · posting+표식 없음 → 답글 0·ERROR · 뿌리 글 없음 → raise · rN 파일 응답 유실 → 1개 · eli5 실패 → PDF 계속·경고 줄(멘션 중화) · --reattach r1 --force/--force-root → exit 2·원격 0.
- 반송 r1(arch#10 #61298 · 1회): 실자료 dry-run 에서 ①md 에 외부 본문(D5 이슈 댓글 · 부록 BRIEFING)의 줄머리 「## 」가 진짜 2단 제목으로 섞임(실측 md 6162·7488·7491행 · ops/magazine push → GitHub 링크 목차 오염) ②eli5 실패한 날에도 뿌리 글 「…PDF(풀 디테일)·HTML(쉬운 판)에 있어요」.
- arch 재현(#10): ①r1 뒤 매거진 시험 125 passed(.venv python) ②실자료 모델(collect 2026-10-08 · 단위 72 · 481KB) --model-file --dry-run: PDF 228쪽 · 2.5MB · md 의 «## » 줄 = 14개 전부 우리 절(목차 · 1부 4 · D1~D7 · 부록 · 각주표) · 외부 본문 인용 줄 3763 · HTML h2 14 · 뿌리 글 「본문은 스레드의 PDF(풀 디테일)에 있어요」 + 「쉬운 판(HTML) 못 만들었어요 — No module named 'magazine_eli5'」(③ 미통합 상태라 정상) ③편차 수락: 모듈 3개 추가·render 공개 함수(행동 변경 0) · complete ok=false·바이트 전송 실패 = 공유 안 됨 확실 → failed 재시도 / 결과 불명 = sharing → 불명 ERROR(문구 기반 판별 — 시험이 문구를 고정) · rN 불명 탈출 = 상태 파일 revs.rN 삭제 안내(reattach 는 --force-root 와 배타) · ①③ 모듈 선택 설치(통합 뒤 WARN 0 확인).
- 최종 DA 소환: 안 함 — 사전검증 APPROVE 범위 안 · 장애 주입 14종이 DA §r1 구현 조건(complete 전 기록 · phase 변경 시 files 보존)을 덮음 · 반송 1회(md 표기·문구)로 닫힘.
- 범위 밖 메모(완성 후): ①실자료 PDF 228쪽 중 D4(머지 본문 35건) 4259줄·D6(열린 카드 137) 1047줄이 대부분 — «분량 제한 0» 지시대로 둠 · 오빠가 줄이길 원하면 D4 본문 접기 1곳 ②문구 기반 실패 판별은 mirror_lib 오류 문구가 바뀌면 시험이 잡는다.
- 라이브 반영: ①수집(§48)·③eli5(§49) cherry-pick 뒤 전체 시험 → 수동 1회 `--date 2026-10-08 --reattach r1 --no-push` → `install-magazine.sh`(복사만 · plist 변경 0 · WARN 0 확인). 정본 영향 없음: 하네스 슬랙 키트 모듈·시험 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: aeea2736ea112961811e5be840bd531e09304b06 · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0`

## §51 세트 발주 원장 도구 ft-sets.sh + 정본·빈 틀·홈 초안 (판정 359 · 나노 set-dispatch-tools) — 닫힘 (byz-harness-arch-claude#11 · master#13 #61334 · 2026-10-08)
- 나노 커밋 `9b984f99cc` [feature] ft-sets.sh + 시험 2종 · `043a9801c8` [docs] 정본 docs/rules/set_dispatch.md · 빈 원장 design/issues/SETS.md · 빈 요청 틀 design/cfo/orders/SET-REQUESTS.md · 홈 초안 2개. 브랜치 nano/set-dispatch-tools(base e660fd8295) · push 0.
- 설계 DESIGN-set-dispatch-20261008.md §1·§2·§3-b·§5·§8 · DA 사전검증 HOLD 1 → APPROVE(DA-set-dispatch-20261008.md).
- master 독립 검증(#61334): test_ft_sets.sh · test_set_requests.sh ALL PASS · shellcheck 경고 0 · 최대 137줄.
- arch 재현(#11): ①`bash tests/harness/test_ft_sets.sh` PASS 25 · ALL PASS(bash 5.3 · /bin/bash 3.2 둘 다) ②`bash tests/harness/test_set_requests.sh` PASS 12 · ALL PASS ③`shellcheck -S warning` 3파일 rc=0 ④홈 초안 diff = 추가뿐 — context-management.md `108a109`(「열린 세트」 1줄) · harness-map.md `19a20`(표 행 1개) ⑤`FT_SETS_FILE=<빈 SETS.md> ft-sets.sh cfo` → 머리줄 「원장 … @ 043a9801c8 · 미커밋 변경 없음」 + 빈 표 + 「세트 진행 0 · 발주 0 · 보류 0 · 닫힘 0」 + 「요청 0건 · 미완료 0」 rc=0 · `--check` → 「CHECK OK — 행 0」 ⑥`FT_SETS_FILE` 미설정 → 「ERROR 원장 없음 … (다른 경로로 넘어가지 않는다)」 rc=3(침묵 대체 0) ⑦카드 증거 검사 `ft-nano-evidence-check.sh --feat e660fd8295` → OK.
- 시험이 덮는 설계 §8 항목(PASS 줄 원문): 재ACK·적용 id(「적용 - 줄 → PENDING」·「적용 commit 이 원장 HEAD 에 없음 → STALE」) · close 일부 실패 = 보류(「닫힘 close 일부(2/3) → rc=1」) · 같은 경로 이후 개정본 안 읽음(「--body = 발주 commit 본문(v1), 같은 경로 이후 개정본(v2) 아님」) · 없는 sha = 미전달(「없는 sha = 미전달 → rc=1」) · 보호 ref 없음 → rc=1 · 이름·상태·Issue 칸 형식 · 행 중복 · Issue 겹침 경고.
- 편차 수락 2: ①`--body <세트>`(발주 sha:경로 본문 출력 — 설계 §8 「같은 경로 이후 개정본 안 읽음」 시험을 도구 경로로 확인하려고 · 읽기 전용) ②끝줄 「· 폐기 e」 는 폐기 행이 있을 때만(설계 §1 상태 5종에 폐기 포함 — 표기 추가뿐).
- 최종 DA 소환: 안 함 — 사전검증 APPROVE 범위 안 · 읽기 전용 도구 + 빈 틀·문서 · 반송 0.
- 남은 몫(이 판정 밖): ①홈 초안 2개 cp 설치(백업 `.bak-1008-sets` · cmp 확인) = master ②원장 실재화(issues master 트리 design/issues/SETS.md) · 첫 적용 판정 358 CFO 7세트(회수본 design/harness/drafts/file-dispatch/ORDER-358-cfo-sets-relay-20261008.md) · 라벨·보호 ref 생성 = issues master·planner.
- 정본 영향 없음: docs/rules 에 하네스 절차 정본 1장 신규와 하네스 도구·시험이고 docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 043a9801c87a7fd80efb30831622711114b83679 · 시험: bash tests/harness/test_ft_sets.sh rc=0 · 이슈: 0`

## §49 아침 매거진 ③ 쉬운 판 eli5 HTML — 묶음 호출·단위별 보이는 생략 (판정 354 · 나노 magazine-eli5-html) — 닫힘 (byz-harness-arch-claude#11 · master#13 #61329·#61356 · 2026-10-08)
- 나노 커밋 `7fb720ca5d` [feature] 오프라인 eli5 매거진(사실 영역과 AI 풀이 분리) · `560c1bbf71` [fix] eli5 스킬 본문 추출·감싼 JSON 수락(반송 r1) · `2f97070948` [structure] 프롬프트·JSON 검증 분리 · `08fd39a3e0` [structure] 시험 매개변수 정리 · `2f2b898520` [feature] 12개 묶음·동시 3·단위별 생략(반송 r2) · `d5595d3e32` [fix] 묶음 시간 한도 90→180초(반송 r3). 브랜치 nano/magazine-eli5-html(base 6594f5c8ae).
- 신규: magazine_eli5.py · magazine_eli5_batches.py(★설치 목록 필수★) · magazine_eli5_template.html · 시험 test_magazine_eli5.py.
- 설계 DESIGN-magazine-full-detail-20261008.md §5·§5-b · DA 사전검증 APPROVE(DA-magazine-fulldetail-20261008.md §r1) + §5-b 계약 APPROVE(§r2).
- 반송 3회: r1(arch#10) 픽스처 통과·실자료 72단위 한 번 호출에서 차단 단어 Eli5Error·timeout → r2(arch#10 · §5-b) 12개 묶음·단위별 회색 칩 「AI 풀이 없음 — 사유」·바닥 줄 N/전체·생략 M·0건일 때만 Eli5Error → r2 실자료 AI 35/72 · 호출 실패 36 → r3(arch#11 #61342) 한도 조정.
- arch 독립 실측(#11 · r2 코드 · 같은 72단위 · 실 LLM · 한도 400초 · 동시 3): 묶음당 63.2~140.3초 · AI 61/72 · 생략 11 · 벽시계 230.6초 · 묶음 프롬프트 1.5만~2만 자로 비슷 → r2 의 호출 실패 36 = 응답 분포가 90초 한도를 넘은 것(규모 아님).
- r3 결과(나노 보고 · arch 재현): `python3 -m pytest tests/scripts/test_magazine_eli5.py -q` 46 passed · 매거진 시험 128 passed(.venv python) · 실자료 1회 257.61초 · 묶음 52.75~162초(타임아웃 0) · 바닥 줄 원문 「AI 풀이 67/72 · 생략 5(숫자 2건 · 차단 단어 2건 · 호출 실패 1건)」 · HTML 계수(arch grep) unit-card 72 · ai-explanation 67 · omitted 5 — 성공+생략=전체 · 사실 카드 전부 유지(DA §r2 「전체 모델 단위 순회」 조건 충족).
- 최종 DA 소환: 안 함 — §5-b 계약 APPROVE 범위 안 · r3 는 상수 1개+시험 기대값 1줄 · 가짜 장애 주입(한 묶음 timeout→12개 생략 · 한 단위 차단→1개 · ref 누락→1개 · 전부 실패→Eli5Error)이 DA §r2 구현 조건을 덮음.
- 범위 밖 메모(완성 후): ①두 실측 최대 140·162초 — 180초 여유 약 10% · 넘으면 그 묶음 12개만 보이는 생략(계약대로) · 자주 넘으면 묶음 크기 축소가 다음 수 ②단위별 문체 생략(숫자·차단 단어·아이콘) 7~15% — 프롬프트 개선 여지 ③매일 실행 벽시계 약 4분 추가.
- ★설치 전 필수 1건(arch#11 발견)★: ops/main-base `scripts/harness-install/slack-mirror/install-magazine.sh:28` COMPANION 목록에 `magazine_eli5_batches.py` 없음 → 설치본에서 magazine_eli5 import 실패 → 매일 쉬운 판 0(WARN 문구만). 통합 뒤 그 목록에 한 단어 추가 커밋(나노) + 설치 뒤 `~/` 설치 경로에 파일 실재 확인.
- 라이브 반영: §48·§50 과 cherry-pick 통합 → 매거진 전체 시험 → 수동 `--date 2026-10-08 --reattach r1 --no-push` → `install-magazine.sh` WARN 0(magazine_eli5_batches.py 포함 확인). 정본 영향 없음: 하네스 슬랙 키트 eli5 모듈·템플릿·시험만이고 docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: d5595d3e32d94d880ca81f30fd9f7663c726ed8f · 시험: python3 -m pytest tests/scripts/test_magazine_eli5.py -q rc=0 · 이슈: 0`

## §52 ft-proposal-card.sh — 팀 골 줄 수 그대로 · 닫는 증거를 골 줄에서 · 경로 기준 = 호출 워크트리 (R26 · 구 R22 10-08 행 · 나노 proposal-card-goal-lines) — 닫힘 (byz-harness-arch-claude#11 · master#13 #61612 · 2026-10-08)
- 나노 커밋 `091fc811d2` [fix] ft-proposal-card(119줄) + 시험 test_proposal_card.sh(102줄). 브랜치 nano/proposal-card-goal-lines(base ece07d7eef).
- 요청: byz-cfo-master-claude#57 #61555(cfo arch#3 발견 #61548) — CFO 첫 사용에서 ①골좌표에 GOAL-cfo.md 인용 머리줄 「> 확정 2026-09-15 · 발행 FB_CFO#8」 ②골 원문 3줄 고정(CFO 골 4줄 · GOAL-cfo.md 9행 = 4줄 바이트 일치 요구) ③main 전용 파일 인용 → docs/cfo-main 에서 lint ⑥·⑧ REJECT. 손 보정본 docs/cfo-main ca66614a53.
- 설계 판정(arch#11 · PLAN-r22-proposal-card-goal-lines-20261008.md): 4줄 골 허용은 DESIGN-proposal-flow-20261008.md 와 어긋나지 않음 — 설계의 「골 3줄」은 «팀 골 원문 복붙» 서술 · lint(`ft-index-lint.sh:86-88`)는 앞 3줄 «존재»만 봐서 4줄 카드도 통과 · lint·키트 bin 변경 0.
- master 독립 검증(#61612): 시험 ALL PASS · shellcheck 경고 0.
- arch 재현(#11): ①`bash tests/harness/test_proposal_card.sh` PASS 28(기존 16 + 신규 12) ALL PASS · shellcheck 0 ②임시 리포 dry — 실 CFO 원장(docs/cfo-main 판) + goal-lines 4줄(13~16행) · 설계·템플릿 파일 없음: 「## 골 원문 (항상 이 4줄)」 · 닫는 증거 「고객사마다 운영툴에서 용어집·지식(RAG)을 관리한다. 생성 시 b2c 베이스 도메인을 공」(골 1줄 10자 → 2줄) · 조사 근거 `design/cfo/GOAL-cfo.md:14` · 설계·템플릿 = 「이 브랜치에 없음 — git show origin/main:… 로 읽기」 · lint OK ③같은 방식 ops(origin/main 원장 · 「…」 감싼 골 줄) → 3줄 · 닫는 증거 「사실 이게 연결되려면 …」 · lint OK ④카드 증거 검사 `--feat ece07d7eef` OK.
- 해석 수락 1: 조사 근거 원장 줄 번호 = 닫는 증거가 시작되는 원장 줄(골 1줄이 20자 미만이면 골 1줄의 줄 번호와 다름 — CFO 14행). 증거와 인용이 같은 줄을 가리켜 더 낫다.
- 커밋 본문 정정: 091fc811d2 본문의 「기존 13+신규 9」 → 정확히 「기존 16+신규 12」(amend 가 block-destructive 훅에 막혀 본문은 그대로 둠 · 우회 0).
- 최종 DA 소환: 안 함 — 도구 1개 카드 문안 교정 + 시험 · 사전검증 면제(arch 서명) 범위 안 · 반송 0.
- 설치·반영(master): ①`.fable-team/bin-cfo/goal-lines-cfo.txt` 에 GOAL-cfo.md 16행 「작업은 파일로 남아서, 세션이 죽어도 다음 세션이 열어서 잇는다.」 추가(.bak-1008-r26 · lint 는 앞 3줄만 보므로 다른 경로 영향 0) — 없으면 CFO 카드는 여전히 3줄 ②도구는 리포 경로 호출이라 main 랜딩 뒤 각 팀이 main 을 받으면 반영(CFO 는 docs/cfo-main 에 main 병합 또는 harness 경로 호출).
- 정본 영향 없음: 하네스 제안서 카드 도구와 그 시험만이고 docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 091fc811d20ea429de3cee9b650752b1250b7289 · 시험: bash tests/harness/test_proposal_card.sh rc=0 · 이슈: 0`

## §53 제안서 흐름 r2 — Issue 본문 = 제안서 전문 · 제안서 md + eli5 HTML 세트 · 실험·예측 시뮬 절 (판정 357 · 나노 proposal-flow-r2) — 닫힘 (byz-harness-arch-claude#11 · master#14 #61972 · 2026-10-08)
- 나노 커밋 `97e97796c8` [structure] publish 상태 helper → proposal_state.py(동작 변경 0) · `966368a8f9` [feature] md+eli5 HTML 세트·원문 hash 고정 · `342fc17a9d` [feature] Issue 본문 = 전문·식별자·시도 기록·분할 comment · `1f834a7536` [feature] 카드·정본 실험 절. 브랜치 nano/proposal-flow-r2(base 801e66649e) · 20파일 +1049/−125.
- 설계 DESIGN-proposal-flow-20261008.md «# r2» · DA §r2 HOLD-1(R2-A 제목만 동일성·생성 응답 유실 / R2-B 첨부 완료 불명·캐시 원문 불일치) → §r2 교정 1 APPROVE(design/harness/DA-proposal-flow-20261008.md). Eli5Error 보이는 저하(경고 줄+ERROR+md 계속)는 DA 수락.
- master 독립 검증(#61972): ruff 0 · shellcheck 0 · 200줄 초과 0 · register 59 + card 31 + r2 시험 ALL PASS · pytest publish/faults/eli5 33 + 매거진 185 passed.
- arch 재현(#11): ①`test_proposal_register.sh`·`test_proposal_register_r2.sh`·`test_proposal_card.sh` ALL PASS ②`pytest test_proposal_publish.py test_proposal_publish_faults.py test_proposal_eli5.py` 33 passed ③매거진 회귀 `pytest tests/scripts -k magazine` 185 passed ④ruff All checks passed ⑤매거진 파일 변경 = magazine_attach.py `CONTENT_TYPES` md 1키뿐(diff --stat 1줄) ⑥install-magazine.sh COMPANION 에 proposal_eli5.py·proposal_eli5_template.html·proposal_state.py·proposal_files.py ⑦카드 증거 검사 `--feat 801e66649e` OK.
- DA 구현 조건 6 소스 대조: ①확정 거절 = Tank rc=2 뿐(ft-proposal-register.sh — ft-gh-as-tank.sh·ft-issue-create-pair.sh 의 exit 2 는 usage·토큰 없음·좌석 불명으로 전부 `gh issue create` 호출 «전» 확인) · rc≠0·번호 없는 출력은 creating 유지 «불명» ②기록에 issue 번호 있으면 검색 없이 그 번호 본문 첫 줄 표식 직접 대조 → ADOPT 또는 「사람이 확인(새 create 0)」(proposal_register_lib.py cmd_plan) ③set_phase 가 기존 rN 기록을 `{**old, …}` 로 덧써 md_hash·html·files 보존(proposal_state.py) ④attach 는 magazine_attach.attach 그대로 · AttachError 를 잡지 않음(proposal_files.attach_all) ⑤md 는 `read_bytes()` 1회 → 칸·hash·HTML·첨부가 같은 바이트(첨부는 그 바이트를 임시 파일로) · check_pinned 가 make_html(캐시 판단) «전»(byz_proposal_publish.py:102-111) ⑥md 중간 상태 = files.md.phase=done 으로 표현(attach_all docstring 「md 완료와 같은 의미」).
- 관찰(반송 아님): 제목 충돌 후보가 여럿이면 첫 번호만 보고 · 같은 표식 2건 이상이면 ADOPT 첫 번호 + 건수 표기(보이는 출력 — 사람 확인 몫).
- 최종 DA 소환: 안 함 — §r2 교정 1 APPROVE 범위 안 · 구현 조건 6 전부 소스·시험으로 확인 · 반송 0.
- 남은 증거(완성 후 아님 — 이 단위의 닫는 증거): 실 Slack·GitHub 원격 0 이라 다음 제안서 1건에서 ①슬랙 스레드 md+HTML 두 첨부(제목에 md_hash 8) ②Issue 본문 첫 줄 표식 + 제안서 전문 확인 → 정본 §첫 사례 줄처럼 1회 기록.
- 라이브 반영(master): 랜딩 → `install-magazine.sh`(복사만 · WARN 0 · proposal_* 4파일 확인). 정본 영향 없음: 하네스 제안서 도구·eli5 판·템플릿·흐름 정본과 시험이고 docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 1f834a7536… (카드 진행/proposal-flow-r2.md 의 40hex) · 시험: bash tests/harness/test_proposal_register.sh rc=0 · 이슈: 0`

## §54 틱 master 뉴스 대상 = 좌석표 _master 하나 — 팀 틱 추적본 신설 + 뉴스 행 검사 분리 + 자동 후계 N 증가 (R27 · 나노 r27-master-seat-single-source) — 닫힘 (byz-harness-arch-claude#12 · master#14 #62117 · 2026-10-08)
- 나노 커밋 `a8a74d0c41` [structure] ft-tick-team.sh 추적본 신설(bin-feature 바이트 복사 · md5 cb379b08966214ac4136a6402588fdc5 일치) · `9a6cb3b46f` [feature] master 뉴스 대상 = _master · `6dc923936d` [fix] SC2155 local 분리. 브랜치 nano/r27-master-seat-single-source(base 0b1ca4e938) · 키트 334→355줄 · 팀 판 233→258줄(순증 ≤30 · 카드 7번 범위).
- 설계 PLAN-r27-master-seat-single-source-20261008.md(§8 r2 정정: 팀 틱 5개 = 갈라진 판 · 키트로 덮지 않음) · DA HOLD-1(R27-A 승계 중간 뉴스 0 ERROR 누락 / R27-B 자동 후계 옛 incarnation 회귀) → 교정 1 APPROVE(design/harness/DA-r27-master-seat-20261008.md §8·§9).
- master 독립 검증(#62117): test_ft_tick_master_seat · test_kit_bin_sync ALL PASS · bash -n OK · 사본 cmp 동일 · shellcheck 신규 경고 0(SC2155 1차 반송 → C 해소 · 남은 SC2034·팀 판 SC2155 1건은 기존 줄).
- arch 재현(#12): ①`bash tests/harness/test_ft_tick_master_seat.sh` rc=0 fail=0 ALL PASS(후계 ①~⑤b 포함) ②`bash tests/harness/test_kit_bin_sync.sh` ALL PASS ③ft-tick.sh·ft-tick-team.sh 각 두 사본 cmp 동일 + bash -n OK ④커밋 A 의 ft-tick-team.sh md5 = cb379b08966214ac4136a6402588fdc5.
- DA 교정 조건 소스 대조: ①master_seat = _master 행 실재·_replaced_by 없음·role master 일 때만(tick 무관) — 「유효 master」 ②master_news_ok = 현역 ft-master-tick 행 목록에 master_seat 가 들어 있어야 통과(JSON 키라 «정확히 1개» 와 같다) · 아니면 ERROR 로그 + DEAD-SEATS.alert 1줄 · 서명(_master|뉴스 행) 같으면 재기록 0 · 정상 복귀 시 서명 파일 삭제(재발 시 다시 1회) · WARN mtwarn stamp 와 별개 ③뉴스 행 0 = 조용히 통과 ④role 첫 행 폴백 0(stall·idle·drift·pm report_to 전부 master_seat) ⑤heir_of = 같은 base · N > dead N 만(숫자 아니면 빈 값) ⑥retarget_seat 후계 행 은퇴(_replaced_by)면 rc 3 · 백업·쓰기 0 → DEAD 알림 경로 ⑦_master 는 == dead 일 때만 같은 dump 안에서 갱신 · 다른 base 추측 0.
- 관찰(반송 아님): 키트에 FT_TICK_STAMP_PREFIX env 추가(기본값 /tmp/ft-tick- = 원래 동작 · 시험 scratch 용) — 카드 목록 밖 1줄이나 기본 동작 불변. WARN 은 좌석당 평생 1회(mtwarn stamp 미삭제) — 카드 3번 문구 그대로.
- 반송 1회(#62123): 카드 증거 줄 누락 → 나노 추가 뒤 ft-nano-evidence-check OK 확인(아래 증거 줄).
- 최종 DA 소환: 안 함 — 교정 1 APPROVE 범위 안 · 교정 조건 7 전부 소스·시험으로 확인.
- 라이브 반영(master · 카드 순서 고정): ①명부 — 틱 있는 좌석표 _master 유효 확인(cfo·feature·loom·ops 유효 · kk 는 tick 비활성이라 _master 추가만) ②ft-tick-team.sh → .fable-team/bin-{cfo,feature,kk,loom,ops}/ft-tick.sh cp+cmp(이름 유지 · plist 무변경) · 키트 ft-tick.sh → .worktrees/v6-realtime-live/.fable-team/bin/ft-tick.sh cp+cmp ③plist bootout→bootstrap ④닫는 증거 = 팀 틱 로그 master sent to <_master 값> 1줄 + ERROR·WARN 0줄(feature 가 지금 유일한 활성 뉴스 틱).
- 정본 영향 없음: 하네스 틱·시험만 — docs/architect 제품 정본 변경 없음. 두 틱 판 합치기는 이 카드 밖(완성 후).
- 카드 증거 줄: 세트: 6dc923936dac0033a16ab5ec9e35ca642418d1cf · 시험: bash tests/harness/test_ft_tick_master_seat.sh rc=0 · 이슈: 0

## §55 슬랙 이어가기 블록 + 단일 발행 입구 byz_thread_post + 스레드 장부 (판정 404 ② 카드 1/2 · 나노 resume-block-thread-post) — 닫힘 (byz-harness-arch-claude#12 · master#14 #62385 · 2026-10-08)
- 나노 커밋 `8dd7baf719` [feature] 이어가기 블록 + byz_thread_post + 장부 · `15a2081450` [fix] test_resume_cmd.sh SC2155(반송 1차). 브랜치 nano/resume-block-thread-post(base b637db62b5) · 25파일 +1098/−31 · 새 파일 최대 191줄(byz_thread_post.py).
- 설계 DESIGN-resume-index-20261008.md r1(판정 405 채널 #byz-planner 하나) · DA HOLD-1(I1 장부 부재=미게시 오판 / I2 미러 본문 첫 인용 / I3 jsonl 이름 검색) → 교정 1 APPROVE(design/harness/DA-resume-index-20261008.md §8·§9).
- master 독립 검증(#62385): pytest 74 · 매거진 187 · test_resume_cmd·kit_bin_sync·제안서 시험 ALL PASS · ruff 0 · shellcheck 경고급 0.
- arch 재현(#12): ①`pytest test_thread_post.py test_proposal_publish.py test_proposal_publish_faults.py test_byz_mbox_slack_mirror.py` 69 passed ②`pytest tests/scripts -k magazine` 187 passed ③`bash tests/harness/test_resume_cmd.sh` ALL PASS ④`test_kit_bin_sync.sh` ALL PASS ⑤ruff All checks passed ⑥새 파일 7개 전부 200줄 이하.
- 설계 계약 소스 대조: ①블록 6칸 — None·빈 값 raise(BlockError) · 고정 2줄 · esc 중화(resume_block.block) ②정본 = `<경로>@<sha8>` · 추적 밖·미커밋·이력 없음 raise(canon_ref) ③재개 = ft-resume-cmd.sh — 정확한 tmux 이름 ring · 아니면 좌석표 행 session_uuid·cwd·agent=claude + jsonl sessionId·cwd 일치만 resume(printf %q) · 그 밖 rc 3 「없음(…)」 · jsonl 본문 이름 검색 0(I3) ④미러 블록 Issue·카드 = 없음 고정 · 담당 = 행 from · 정본 = bodies/<seq>.txt@mbox(I2) ⑤장부 없음·손상·쓰기 실패 raise · 빈 장부는 --init 만 · 키 = 불변 단위 ID(thread_ledger · I1) ⑥start = 카드에 「- 슬랙: … 시도」 선기록 → 뿌리 글 1개 → 카드 줄 root_ts 로 갱신 → 장부 → 첨부는 같은 스레드 · 이미 시작·카드 줄 있음 = REJECT ⑦result = `[결과] <단위 ID>` 첫 줄 · 재실행 시 스레드 표식 먼저 찾아 재발송 0 · kind=report 면 거부 ⑧check rc 0(미게시·결과 있음·report) / 1(결과 없음) / 3(장부 오류·키 없음·root_ts 없음·«시도»뿐) ⑨kind=report 는 CLI 인자 없음(매거진 발행기 ensure_report 만) ⑩--bot 은 result 서브명령에만.
- 관찰(반송 아님): ①`result --bot hermes` 가 `--legacy-root` 없이도 받아들여진다(도움말 「소급 전용」 · 강제 0) — 카드 2 또는 소급 집행 때 master 가 --legacy-root 와 함께만 쓴다 ②check 는 카드 줄 root_ts 와 장부 root_ts 의 일치까지는 보지 않는다(둘 다 있으면 통과) — 불일치는 repair 경로에서만 드러남.
- 반송 1회(#62408): 카드 증거 줄 누락 → 나노 추가 뒤 ft-nano-evidence-check OK 확인(아래 증거 줄).
- 최종 DA 소환: 안 함 — 교정 1 APPROVE 범위 안 · 계약 10개 소스·시험으로 확인.
- 라이브 반영(master · 카드 밖): install.sh·install-magazine.sh 로 slack-mirror 복사(cmp) · 장부 `byz_thread_post.py --init` 1회 · 라이브 1회 = 다음 제안서·매거진 뿌리 글 꼬리 블록 2줄 + 미러 답글 꼬리 블록 2줄. 그 뒤 카드 2(result-reply-close-gate) spawn.
- 정본 영향 없음: 하네스 슬랙 발행 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: 15a2081450f4713d007d39a8f6ce9608fe7915bb · 시험: python -m pytest tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0

## §56 나노 닫기 cherry 게이트 — squash 랜딩 PR 전용 플래그 --squashed-pr + design/ 문서 종류만 WARN (R29 · 나노 r29-cherry-gate-squashed-pr) — 닫힘 (byz-harness-arch-claude#13 · master#14 #62485 · 2026-10-08)
- 나노 커밋 `ea1a256723` [feature] cherry 게이트 --squashed-pr + design/ 문서 종류만 WARN. 브랜치 nano/r29-cherry-gate-squashed-pr(base 418c5e2489) · 5파일 +348/−12 · ft-nano-cherry-gate.sh 181줄 · 새 ft-nano-cherry-pr.sh 82줄(source 전용) · 키트 사본 2 · tests/harness/test_cherry_gate_squash.sh.
- 안 PLAN-r29-squash-superset-close-20261008.md r1 · DA HOLD-1(PR 중간 blob 존재 = 최종 반영 → 되돌림 거짓 통과) → 교정 1 APPROVE(design/harness/DA-r29-squash-superset-20261008.md · #62323).
- master 독립 검증(#62485): test_cherry_gate_squash fail=0 ALL PASS · 기존 cherry pytest 40 passed · kit_bin_sync ALL PASS · 사본 cmp · shellcheck 경고급 0.
- arch 재현(#13): ①`bash tests/harness/test_cherry_gate_squash.sh` rc=0 fail=0(③ 「되돌림(P1→P0) 플래그로도 REJECT」 · 「원장 0행」 PASS) ②`test_kit_bin_sync.sh` ALL PASS ③사본 cmp 2쌍 동일 ④bash -n 2파일 OK ⑤두 파일 200줄 이하.
- 확정안 조건 소스 대조: ①플래그 없을 때 = 기존 경로 그대로(자동 통과 추가 0 · 도우미 파일은 플래그 때만 source — 런타임에 pr.sh 없어도 기존 닫기 영향 0) ②`--squashed-pr N --reason` 둘 다 필요 · 빈 사유 REJECT · --override 와 동시 = usage 2 · --reason 단독 = usage 2 ③PR 사실 = gh state MERGED ∧ mergeCommit S ∈ merge-base(NANO,FEAT)..FEAT(is-ancestor 2회) · head 없으면 fetch pull/N/head · 실패 REJECT ④경로 분류(mode type blob 3칸 비교) = 같음(tip==FEAT) / 나노 tip 삭제 REJECT / squash 에서 제거 REJECT / squash==분기 시점(되돌림) REJECT / tip 이 merge-base(H,FEAT)..H 에 새 blob = PR 안에서 고쳐짐 / 그 밖 REJECT — REJECT 1개라도 있으면 플래그로도 불가 ⑤통과 = 경로 표(고친 PR 커밋 sha·제목) + 한계 문구 + 원장 `kind=squashed-pr pr=#N head=<H8> squash=<S8> paths=… reason=…` 1행 + stderr ERROR · 원장 메타·기록 실패 = REJECT ⑥혼합 «+» 커밋의 WARN = design/ 아래 md·html·png·jpg·jpeg·svg·pdf 만(is_doc_path) · sql·sh 등은 코드 경로 · NUL-safe(read -d '').
- 실사례 dry-run(원장 = scratchpad · 라이브 원장 54→54줄 쓰기 0): `ft-nano-cherry-gate.sh origin/main nano/f-guest-jwt-impl-s1 --repo <루트> --squashed-pr 905 --reason …` rc=0 → 「같음 19개 · PR 안에서 고쳐짐 2개 · 되돌림·제거 0개」(sse_identity.py·rooms.py ← b52a55dc [structure] SSE rooms.py 파일 길이 예산 준수) · design/ 문서 39 WARN. 카드 기준값(코드 21 = 같음 19 · 고쳐짐 2) 과 일치. 플래그 없이는 그대로 REJECT(merge-tree 충돌 + 2경로).
- 관찰(반송 아님): ①PR 분류는 «+» 커밋 경로 전체를 다시 본다 — 분기 뒤 feat 의 다른 커밋으로 이미 superseded 됐다가 feat 에서 또 바뀐 경로는 squash==분기 시점이면 「되돌림」 REJECT 로 떨어질 수 있다(거짓 통과 아닌 보수 쪽 · 실사례 해당 0) ②is_doc_path 는 대소문자 구분(.MD 는 코드 취급 · 보수 쪽).
- 반송 1회(#62503·#62504): 카드 증거 줄 누락 → 나노 추가(#62508) 뒤 ft-nano-evidence-check OK 확인(「OK 증거 줄 — 세트 HEAD ea1a25672 · 시험 rc=0 · 이슈 0」).
- 최종 DA 소환: 안 함 — 교정 1 APPROVE 범위 안 · 조건 6개 소스·시험·실사례로 확인.
- 라이브 반영(master · 카드 밖): 라이브 FT_BIN 에 gate.sh + pr.sh 둘 다 cp(pr.sh 빠지면 플래그 REJECT) · `ft-live-bin-drift-check.sh` OK · 실제 1회 = byz-feature-nano-f-guest-jwt-impl-s1#0 을 `--squashed-pr 905 --reason "<feature master 사유>"` 로 닫고 라이브 원장 1행 확인 → 원장 R29 반영.
- 정본 영향 없음: 하네스 닫기 게이트·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: ea1a256723ad6cd2c545fd97c596cffe76945088 · 시험: bash tests/harness/test_cherry_gate_squash.sh rc=0 · 이슈: 0

## §57 승계 창 자동 이관 — ft-seat-handover.sh(snapshot·apply·status) + 은퇴 좌석 guard 훅 + attach 떠넘김 Stop 훅 (R30 · 나노 r30-seat-handover-window) — 닫힘 (byz-harness-arch-claude#13 · master#14 #62539 · 2026-10-08)
- 나노 커밋 `03481b45ba` [feature] ft-seat-handover.sh(snapshot·apply·status) + retired-seat-guard(UserPromptSubmit) + no-attach-to-user(Stop) · 반송 수정 커밋 `0c8045f678` [fix] guard 루트 = git 공용 디렉터리 · MISMATCH mbox 지시 세션당 1회. 브랜치 nano/r30-seat-handover-window(base 5503238593) · 6파일 +579/−1 · ft-seat-handover.sh 145줄 · 훅 29·60줄 · 시험 191줄.
- 설계 DESIGN-r30-succession-window-handover-20261008.md r2 · 사전 DA HOLD 2 → 리뷰 종료(§7·§8 · H3 APPROVE) → master #62468 고정 범위 승인(잔여 2건 = 완료 조건 시험 + 구현 DA 재확인).
- master 독립 검증(#62539): 시험 48 ALL PASS · kit_sync ALL PASS · shellcheck 경고급 0 · 전 파일 200줄 이하 · json 유효.
- arch 재현(#13): ①`bash tests/harness/test_seat_handover.sh` rc=0 · PASS 48 ②`test_kit_bin_sync.sh` ALL PASS ③사본 cmp 동일 ④bash -n 3파일 OK ⑤snippet json 유효.
  - 잔여 1(T0 2탭): 「HANDOVER …#2 -> …#3 moved=0 skipped=0 ambiguous=2 (ambiguous tty=/dev/ttys001,/dev/ttys002 전환 보류)」 · switch.log lines=0 · 통보 질문 문장 0.
  - 잔여 2(인용 줄): 「quote: stdout='' (block 0)」 · falsepos.log 「quoted n=1 이전 좌석은 "tmux attach -t X 를 실행해 주세요"라고 요청했다」 · stop_hook_active → block 0 + 기록.
- 소스 대조(카드 구현 범위 1~5): snapshot 1탭=follow · 2탭+=ambiguous · 0=빈 목록 ✓ · apply 후계 세션 실재 + 명부 `_<역할>`==후계 · identity 3중(tty·pid·created)+session 재조회 · skipped 4종 · 장부 done 행 · @handed_over_to 캐시 ✓ · ambiguous = mbox 통보 1통(질문 0) ✓ · --client 는 --confirmed-by 숫자 필수 ✓ · status 판정표 5행 · 옵션 유실 복원 · TMUX_PANE 고정 ✓ · Stop 훅 1단 제외(헤더·펜스·>·따옴표) → 2단 요청 형태 block · stop_hook_active block 0 · fail-open ✓ · snippet UserPromptSubmit 1줄 + Stop 키 신설 ✓.
- 구현 DA 재확인(잔여 2건 · 커밋 03481b45ba · DA 파일 §9 요청 #62558): ★APPROVE★(DA 파일 §10 · #62602) — 「T0>=2 follow=[]/ambiguous → switch 0 · 인용/펜스/HIL 선제외 → block 0 · 실요청 block 확인」 · 고정 sha 4파일 archive 추출 시험 ALL PASS rc0 · 실 tmux·명부·홈·설치·발신 0 · 10분 단발.
- 반송 1회(#62559 · 설치 전 결함 · arch 실측): ①guard 훅 FT_BIN 기본 = CLAUDE_PROJECT_DIR/.fable-team/bin → 워크트리 좌석·다른 프로젝트 tmux 세션 전부 매 입력 「오류 … master 에 알릴 것」 주입(실측 harness-ops·/tmp 둘 다) → 루트 = git common-dir 상위 · seats*.json 없는 곳 = exit 0 ②MISMATCH 주입이 매 입력 mbox 지시 → 장부 없는 옛 좌석(실측 arch#12·planner#9 = MISMATCH)이 틱마다 master 쪽지 폭주 → 세션당 1회(tmux 옵션 표식) ③대기/ 카드 사본 증거 줄 커밋 7dffe9bb9f 제거. → 수정 결과(#62581 · arch 재현): `test_seat_handover.sh` rc=0 PASS 53 · kit_sync ALL PASS · 사본 cmp · 표 3 실측 = 타 프로젝트(/tmp) 출력 0 rc=0 · 표 4 실측 = 워크트리(harness-ops) → 메인 루트 bin 해석(라이브 bin 미설치라 지금은 「없음」 오류 = 표 7 선행 필요) · bin 있을 때 현역 arch#13 = 출력 0 · 라이브 명부 대조 status arch#13 ACTIVE / arch#12 MISMATCH(장부 0 · 표 5 그대로) · 7dffe9bb9f 제거 확인(HEAD~1 = 03481b45ba).
- 관찰(반송 아님): ①장부 파일이 깨져 jq 가 실패하면 status 는 장부 «없음» 으로 읽는다(명부가 나면 ACTIVE · 아니면 MISMATCH — 거짓 RETIRED 0 · 보수 쪽) ②Stop 훅 헤더 제외 「감사」 접두가 「감사합니다」로 시작하는 답도 기록만으로 보낸다(차단 누락 쪽이지만 승계 떠넘김 문장이 그 꼴일 일은 드묾) ③Stop 훅은 매 턴 transcript 끝 2MB 를 파싱(턴당 수십 ms 추정 · 미측정).

### 전역 훅 영향 — 라이브 설치 전 점검 (master 집행 전 필수)
| # | 점검 | 기대값 | 근거 |
|---|---|---|---|
| 1 | **입력 차단 가능성** — retired-seat-guard 는 additionalContext 만 내고 항상 exit 0 · decision:block 출력 경로 0 | 오탐이어도 «입력 차단 0» (주입 문구만) | 훅 소스 emit()=exit 0 · block 문자열 0 |
| 2 | **턴 종료 차단 가능성** — no-attach-to-user 는 block 시 Claude 가 한 번 더 이어 쓰게 함 · stop_hook_active 면 block 0 → 최대 1회 · 오류는 fail-open exit 0 | 무한 루프 0 · 오탐 최악 = 턴당 1회 재작성 | 시험 「stop_hook_active」 PASS |
| 3 | **팀 밖 세션 무출력** — 반송 ① 수정 뒤(0c8045f678 실측 OK): 다른 프로젝트 tmux 세션 · tmux 밖 세션에서 guard 출력 0 | `echo '{}' \| CLAUDE_PROJECT_DIR=/tmp TMUX_PANE=$TMUX_PANE bash retired-seat-guard.sh` → 빈 출력 | 수정 뒤 출력 0 rc=0(실측) |
| 4 | **워크트리 좌석 정상 판정** — 같은 명령을 CLAUDE_PROJECT_DIR=<워크트리> 로 | 현역 좌석 = 빈 출력(ACTIVE) | 수정 뒤 메인 루트 bin 으로 해석(실측) · bin 설치(표 7) 전엔 「없음」 오류 주입 — 그래서 bin 먼저 |
| 5 | **옛 좌석 일괄 MISMATCH** — 설치 순간 장부 0 이라 명부 계보의 옛 좌석(keep-last-2 로 살아 있는 #N−1·#N−2) 전부 MISMATCH | 반송 ② 수정 뒤 세션당 쪽지 1통 · 설치 직후 master 가 `[handover-mismatch]` 를 일괄 수신 각오(옛 좌석 수만큼) · 옛 좌석 크론이 남아 있으면 먼저 CronDelete | 실측 arch#12·planner#9 |
| 6 | **Stop 훅 기록 경로** — 기록 파일이 `$FT_ROOT/.fable-team/state/hil-falsepos.log`(FT_ROOT 기본 CLAUDE_PROJECT_DIR) → 다른 프로젝트에서 언급만 해도 그 리포에 `.fable-team/state/` 디렉터리 생성 | 설치 명령에 FT_ROOT=<BYZ 루트> 고정 또는 BYZ 프로젝트 settings 에만 등록 | 훅 소스 :10–11 · :55 mkdir |
| 7 | **라이브 bin** — 루트 `.fable-team/bin/ft-seat-handover.sh` 지금 없음 · 훅보다 «먼저» cp | 훅 설치 전 bin 실재 · `ft-live-bin-drift-check.sh` OK | 실측 ls 없음 |
| 8 | **되돌림** — settings 의 두 줄 삭제 + 훅 파일 제거로 즉시 원복 · 장부 handover.jsonl 은 남겨도 무해 | 원복 1단계 | — |

- 라이브 반영(master · 카드 밖): 위 표 7 → 3·4 확인 → settings 등록 → 정본 문장 3곳(governance §승계 · BOOT 13조 뒤 · 글로벌 CLAUDE.md 증류 절차 ③-b·⑤-b + 전파본) → 첫 적용 = feature 탭 `/dev/ttys000` 을 `apply --client /dev/ttys000 --confirmed-by <seq>` 1회 → 원장 R30.
- 정본 영향 없음: 하네스 승계 도구·훅·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: 0c8045f678561d5402ed255d1ea42a59d72eefb9 · 시험: bash tests/harness/test_seat_handover.sh rc=0 · 이슈: 0 (evidence-check OK)

## §58 판정 번호 원장 — ft-verdict.sh(seed·new·done·todo·list) + ft-verdict-lock.sh (판정 421 N1 · 나노 v430-verdict-ledger) — 닫힘 (byz-harness-arch-claude#14 · master#15 #62863 · 2026-10-08)
- 나노 커밋 `1769ee6036` [feature] 원장 도구 + 시험 · 반송 수정 `a58b765432` [fix] 잠금 보유 pid 기록·죽은 잠금 회수 + seed 호스트 거부 시험 · `b382723e31` [structure] 잠금 함수 ft-verdict-lock.sh 분리(200줄 한도). 브랜치 nano/v430-verdict-ledger(base d21481fe6c) · ft-verdict.sh 184줄 · ft-verdict-lock.sh 36줄 · 시험 test_verdict_ledger.sh.
- 설계 DESIGN-news-tree-workqueue-viz-20261009.md r2 §2-1 · 사전 DA N1 ★APPROVE★(DA-news-board-20261009.md §8) → 오빠 컨펌 GO 판정 430·431.
- master 독립 검증(#62796 → 반송 뒤 #62863): 시험 ALL PASS(동시 new 20회 중복 0 · 죽은/산 잠금) · kit_sync ALL PASS · 사본 cmp · shellcheck SC2034 1건 = source 분리 오탐.
- arch 재현(#14 · 고정 sha b382723e31): ①`bash tests/harness/test_verdict_ledger.sh` rc=0 · PASS 34 · FAIL 0 ②`test_kit_bin_sync.sh` ALL PASS ③사본 cmp 2파일 동일 ④bash -n 2파일 OK ⑤`ft-nano-evidence-check.sh` OK(세트 HEAD b382723e3 · rc=0 · 이슈 0).
  - 출력 복붙: 「동시 new 20회: 발급 20건 · 고유 20건 · 중복 0」 · 「PASS 동시 new 20회 번호 중복 0」 · 「PASS 죽은 pid 잠금 → WARN 1줄 + 해제 후 발급(448)」 · 「PASS 산 pid 잠금 → rc 1 + 보유 pid 41577 표시」 · 「PASS seed 호스트 불일치 거부」.
- 편차 판정(#62839): ①seed 에도 발급 권위 검사 = ★수락★(카드는 new 만 명시 · 두 번째 머신 seed 는 분리 원장을 만들므로 같은 권위가 맞다 · 실측 host-b seed rc 1 · state 폴더 생성 0) ②잠금 = mkdir(카드는 flock) = ★조건부 → 반송 1회로 수락★ — macOS 에 flock 실행 파일 없음(실측) · 1차 실측에서 잔류 잠금이면 new·list 모두 10초 뒤 rc 1 영구(flock 은 죽은 프로세스 잠금을 커널이 푼다 — 의미 차이) → 보유 pid 기록 + 죽은 pid 회수(stderr WARN 1줄) + 산 잠금은 rc 1 + 보유 pid 표시로 flock 과 같은 의미 회복.
- 소스 대조(카드 구현 범위 1~2): seed 재발급 rc 1 ✓ · new 권위(hostname==_verdict_host ∧ realpath 일치) · 불일치 rc 1 「발급은 <host> planner 에게」 ✓ · 잠금 안 read-max→append→fsync(os.fsync) ✓ · seed 없음 new 거부 ✓ · done/todo 없는 n rc 1 · 새 번호 0 ✓ · list fold(open/done · oppa_todo 최신) ✓ · 손상 줄 rc 1 + 줄 번호 ✓ · 시험 목록 전부 ✓.
- 구현 DA 소환: 아니오 — 사전 DA N1 APPROVE 범위 그대로 · 결정적 시험(동시성 20회·잠금 2종·권위 2종)으로 닫힘 · 편차 2건은 arch 실측으로 판정 — arch 서명 byz-harness-arch-claude#14.
- 관찰(반송 아님): ①보유자가 mkdir 직후 pid 를 쓰기 전에 죽으면 pid 미기록 잠금 → 회수 안 됨 → 10초 rc 1 「보유 pid 미기록 … 사람 확인」(보이는 실패 · 확률 낮음) ②죽은 잠금 + 대기자 3명 이상이 겹치면 reap 의 mv 되돌림 구간에서 이론상 이중 보유 창이 있다(발급자 = planner 1좌석이라 실사용 동시 대기자 ≤2 · 시험 20회 동시에도 중복 0).

### 라이브 반영 (master·planner 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | 라이브 FT_BIN 에 ft-verdict.sh + ft-verdict-lock.sh ★한 쌍★ cp | `ft-live-bin-drift-check.sh` OK |
| 2 | 명부 seats-planner.json 에 `_verdict_host` = `MacBook-Pro.local`(이 머신 hostname 실측) · `_verdict_root` = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` | `ft-verdict.sh list` rc 0(원장 없음 = 빈 목록) |
| 3 | planner 가 검증한 마지막 판정 번호로 `ft-verdict.sh seed <n> --by <planner 현역>` 1회 | `SEEDED n=<n>` · 재실행 rc 1 |
| 4 | planner 판정 발급을 `ft-verdict.sh new` 로 전환(정본 문장 = governance 판정 절) | 다음 판정 번호 = n+1 |
| 5 | 되돌림 | 명부 두 키 삭제 → new 전부 rc 1(발급 정지 · 보이는 실패) · 원장 파일은 보존 |

- 정본 영향 없음: 하네스 원장 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: b382723e31 · 시험: bash tests/harness/test_verdict_ledger.sh rc=0 · 이슈: 0 (evidence-check OK)
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v430-verdict-ledger.md 완성 --da <판정문>#§58`

## §59 메인팀 인박스 — ft-inbox.sh(ingest·show·mark·report·archive·--compact) + 정본 술어 obligation_closed + mbox send/relay 적재 훅 (판정 425-B · 430 · 나노 v425-master-inbox) — 닫힘 (byz-harness-arch-claude#14 · master#15 #62884 · 2026-10-08)
- 나노 커밋 `ff9172d328` [structure] canonical mbox.sh 를 라이브와 같은 바이트로 · `6daa9f3fd7` [feature] ft-inbox + mbox 적재 훅 · 반송 수정 `97090f6d43` [fix] Haiku 분류 비동기 + 2파일 분리 + 훅 축소 · `d2ce4b6ff3` [fix] 미상을 MUST_REPORT 에 추가. 브랜치 nano/v425-master-inbox(base d21481fe6c) · ft-inbox.py 169줄 · ft_inbox_core.py 129줄 · ft-inbox.sh 3줄 · mbox.sh 231줄(라이브 원본 226 + 훅 5).
- 설계 DESIGN-news-tree-workqueue-viz-20261009.md r2 §6 · §8 정본 술어 · 사전 DA 2 HOLD 종료(N2 잔여 → 정본 술어 고정) → 오빠 컨펌 GO 판정 430·431.
- master 독립 검증(#62811 → #62837 → #62884): 시험 PASS 48 · kit_sync ALL PASS · ruff OK · shellcheck 0 · 사본 cmp.
- arch 재현(#14 · 고정 sha d2ce4b6ff3): ①`bash tests/harness/test_inbox.sh` rc=0 · PASS 48 · FAIL 0 ②kit_sync ALL PASS ③사본 cmp 3파일 동일 ④ruff All checks passed ⑤`ft-nano-evidence-check.sh` OK(세트 HEAD d2ce4b6ff · rc=0 · 이슈 0).
  - 출력 복붙(술어 2줄 · 카드 완료 조건): 「REFUSED seq=103 cls=③ reported=false — 술어 거짓(이동 거부)」 · 「PASS 술어: mark 후 report 없음 → archive 이동 거부」 · 추가 「PASS 묶음: S2 대상 유지(archive 거부)」 · 「PASS 미상: mark 만 → archive 이동 거부(REFUSED)」 · 「PASS send 소요 1초 미만(Haiku sleep 8 대기 0)」.
- 반송 판정 3건(arch): ①Haiku 분류 = 비동기가 설계 의도(#62816 · 근거 §6-4 ingest 50 ms 미만 · §6-2 발신 경로 python 1회) → 규칙표만 즉시 적재 · 미상 줄만 분리 프로세스(start_new_session) 가 Haiku 라벨 → 같은 잠금 안 cls 갱신 · 실패 = 미상 유지 ②mbox.sh 200줄 초과 = 주원인은 라이브 원본 226줄(동기화 [structure]) · 훅은 주석 1 + 함수 1 로 축소(#62821) · 기존 226줄 분리는 별 카드 대기/mbox-sh-split-200.md ③미상 = 보고 의무 대상(#62874 · ring 은 ①~④ 급인데 보고 의무가 ⑥ 급이던 조용한 강등 차단) · 분리+비동기 한 커밋 = 허용(미랜딩 코드 재배치 · 보존할 기존 동작 없음).
- 소스 대조(카드 구현 범위 1~3): 계보 키 큐(#9→#10 같은 큐) ✓ · bodies/<seq>.txt 보존 ✓ · 분류 고정표 ①~⑥ + 미상(prio 1.5) ✓ · 묶기 = 같은 from ∧ 정규화 해시 ✓ · show 술어 거짓 줄만 · --compact 큐 무변경 ✓ · mark/report/archive(삭제 0) ✓ · obligation_closed 한 함수(core:77) · 묶음 all(core:83) ✓ · flock 잠금 ✓ · ingest 실패 = WARN · send rc 불변 ✓.
- 구현 DA 재확인: 소환 예(카드 완료 조건 「구현 DA 가 재확인」) · 요청 DA 파일 §9(#62918) · 결과: ★APPROVE★(DA 파일 §10 · #62951) — 「d2ce4b6ff3 show/archive/group 는 obligation_closed 만 · report 는 상태 갱신 · ③ mark 만 REFUSED/큐 보존 · 부분 group 미닫힘 · 미상 MUST_REPORT · Haiku 실패 유지/비동기 send 확인 · test_inbox.sh 48 PASS fail 0 rc 0」 · 실제 발신·LLM·설치 0 · 훅/보드 종단은 별도(나노 3·2) · 단발 종료
- 관찰(반송 아님): ①canonical 위치(tools/comm-canonical)에서 mbox.sh 를 직접 돌리면 `$DIR/../bin/ft-inbox.sh` 가 없어 매 send WARN — 라이브(.fable-team/comm → .fable-team/bin)에서만 정상 경로(설치 순서 표 1) ②ft-inbox.py 169 · core 129 — 둘 다 200 이하.

### 라이브 반영 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | ★먼저★ 라이브 `.fable-team/bin/` 에 ft-inbox.sh · ft-inbox.py · ft_inbox_core.py 3파일 cp | `ft-live-bin-drift-check.sh` OK · 없이 mbox.sh 를 먼저 바꾸면 매 send WARN |
| 2 | 라이브 `.fable-team/comm/mbox.sh` ← canonical cp(226 → 231 · 훅 5줄) | `check-drift.sh` OK · send 출력에 WARN 0 |
| 3 | 첫 적용 = planner 1팀 · 측정 2일(이벤트 기준 planner 쪽지 200건) | 설계 §6-4: 누락 0 · doorbell 수/시간 · ingest 50 ms 미만 · 큐 일 1 MB 미만 |
| 4 | 깨우기 규칙 변경(①~④·미상 항상 ring)은 나노 3 카드(대기/v423-publish-report-hooks.md) 랜딩 때 | 이 단위는 적재만 |
| 5 | 되돌림 | mbox.sh 이전 사본 cp(훅 줄 제거) · 큐·bodies 는 보존(읽기 전용 자료) |

- 정본 영향 없음: 하네스 통신 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: d2ce4b6ff3 · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0 (evidence-check OK)
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v425-master-inbox.md 완성 --da <판정문>#§59`

## §60 카드 이동 슬랙 과정·결과 답글 자동 + 결과 없으면 CLOSE 금지 + 손 hermes send 슬랙 차단 훅 (판정 404 ② · 405 · 카드 2/2 · 나노 result-reply-close-gate) — 닫힘 (byz-harness-arch-claude#14 · master#15 #62928 · 2026-10-08)
- 나노 커밋 `e04492076f` [feature] ft-index-move 슬랙 단계 + slack-post-guard 훅 · `e7c62f2197` [test] 슬랙 단계 시험 · 반송 수정 `c407fef282` [fix] 판정 단위를 명령 위치의 hermes 구간으로(오탐 제거) · `111360204d` [fix] 따옴표 쪼갠 명령어·xargs 우회 차단. 브랜치 nano/result-reply-close-gate · ft-index-move.sh 150줄 · slack-post-guard.sh 142줄.
- 설계 판정 404·405 교정 설계 · 사전 DA ★APPROVE★(design/harness/DA-resume-index-20261008.md §9 · HOLD-I1~I3 해소).
- master 독립 검증(#62758 → #62884 → #62928): index_move_slack 12/12→14 · slack_post_guard 15→24→29 · kit_sync PASS · shellcheck 0 · 오탐 allow·우회 deny 직접 재현.
- arch 재현(#14 · 고정 sha 111360204d): ①`bash tests/harness/test_index_move_slack.sh` rc=0 PASS 14 ②`bash tests/harness/test_slack_post_guard.sh` rc=0 PASS 29 ③`test_kit_bin_sync.sh` rc=0 ④ft-index-move 사본 cmp 동일 · bash -n OK ⑤`ft-nano-evidence-check.sh` OK(세트 HEAD 111360204 · rc=0 · 이슈 0).
  - 훅 직접 프로브 15건(arch 고정 목록 · 결과 전부 기대대로): allow 6 = mbox send 본문에 slack·hermes 낱말 · git commit -m 메시지 · grep send …/slack-mirror ~/.hermes · tail gateway.log | grep 패턴 · hermes send -t telegram · hermes send --list / deny 9 = -t slack · --to=slack:C123 · 따옴표 분리(h""ermes … sl""ack) · 변수 대상(T=slack; … -t $T) · bash -c 안쪽 · cd && ENV= 접두 · 절대경로 ~/.local/bin/hermes · xargs hermes · env hermes.
- 편차 판정(#62758 · arch): ft-index-move 가 `--issue/--seat/--canon/--next/--resume-script` 를 카드·ft-resume-cmd.sh 에서 채움 = ★수락★ — 카드 1 이 만든 `thread_post_args.py` 가 progress·result 에 6칸을 required=True 로 요구(값 없으면 문자 「없음」) · 빠지면 호출이 usage 오류로 실패해 이동이 영구 REJECT 된다 → 카드 범위 1 의 호출을 성립시키는 최소 인자.
- 반송 2회(arch 실측): ①훅 오탐 4/8 deny(mbox 본문 · commit -m · grep 패턴 · tail|grep) + 오탐 기록 부재 → 판정 단위 = 명령 위치의 hermes 구간(gh-issue-author-guard 꼴 · bash -c/eval 재귀) · deny 마다 state/hook-falsepos.log 1줄 ②카드 범위 2 가 명시한 따옴표 분리 우회 통과 + xargs 접두 통과 → shlex 합치기 · xargs/command/exec/env 를 명령 위치로.
- 소스 대조(카드 구현 범위 1~3): 대기→진행 = `- 슬랙:` 줄 있을 때 progress · 실패 REJECT(이동 0) ✓ · 진행→완성 = check rc 0 통과 / 1 → result 자동 · 실패 REJECT / 3 → 「장부 복구 필요 — repair」 REJECT / 그 밖 REJECT ✓ · `--landed` ✓ · 도구 = FT_THREAD_POST · 없으면 REJECT(폴백 0) ✓ · 장부 직접 읽기 0 ✓ · 200줄 이하 ✓ · 시험 2종 + kit ✓.
- 구현 DA 소환: 아니오 — 사전 DA APPROVE 범위 그대로 · 카드 완료 조건에 구현 DA 재확인 없음 · 훅 판정은 결정적 프로브 15건 + 시험 29건으로 닫힘 — arch 서명 byz-harness-arch-claude#14.
- 관찰(반송 아님): ①훅은 FAIL-OPEN(JSON·명령 파싱 불가 = 허용 + stderr) — 우회보다 입력 차단 0 을 택한 sibling 관례 ②변수 대상은 값과 무관하게 deny(`-t $T` 가 telegram 이어도) — 보수 쪽 오탐이며 hook-falsepos.log 로 보인다.

### 전역 훅 영향 — 라이브 설치 전 점검 (master 집행 전 필수 · §57 꼴)
| # | 점검 | 기대값 | 근거 |
|---|---|---|---|
| 1 | **입력 차단 가능성** — PreToolUse:Bash exit 2 는 «그 Bash 호출 1건» 만 막음 · 사용자 입력·다른 도구 차단 0 | 오탐 최악 = 해당 명령 1회 거부 + falsepos.log 1줄 | 훅 소스 exit 2 경로 1곳 |
| 2 | **오탐 실측** — 하네스 일상 명령(mbox send 본문 · git commit -m · grep · tail|grep) | 전부 allow | arch 프로브 allow 6/6 |
| 3 | **팀 밖 세션** — hermes 를 명령 위치에 두지 않는 모든 세션 = 무출력 rc 0 · 다른 프로젝트에서 hermes send -t slack 은 막힘(의도 · 판정 405 는 채널 단일 정책) | ★결정(master #62934): BYZ 프로젝트 settings 에만 등록 · 전역 등록 0★ — 판정 405 는 BYZ 슬랙 발행 규칙이라 BYZ 밖 프로젝트는 대상 아님 · 영향 범위 최소 · 되돌리기 쉬움 | master #62934 |
| 4 | **기록 경로** — falsepos.log = git 최상위/.fable-team/state/ · git 밖 cwd 면 기록 실패(deny 는 유지) | 다른 리포에서 deny 시 그 리포에 .fable-team/state 생성 가능 → BYZ settings 등록이면 무관 | 훅 소스 :107~:113 |
| 5 | **라이브 bin 선행** — ft-index-move.sh 를 라이브 FT_BIN 에 먼저 cp(슬랙 줄 있는 카드 이동이 그때부터 thread_post 를 부름) · FT_THREAD_POST 기본 ~/.hermes/scripts/byz_thread_post.py 실재(arch 실측 있음) | `ft-live-bin-drift-check.sh` OK | 실측 ls |
| 6 | **되돌림** — settings 의 PreToolUse 한 줄 삭제 + 훅 파일 제거 · ft-index-move 는 이전 사본 cp | 1단계 원복 | — |

- 라이브 반영(master · 카드 밖): 표 5 → 훅 설치 + ★BYZ 프로젝트 settings★ PreToolUse 등록(표 3 결정 · 전역 0) → 소급 7건(설계 §7) `byz_thread_post.py result --legacy-root …` 1회씩 → 각 스레드 [결과] 답글 실측 → 판정 404 소급 보고 1통.
- 정본 영향 없음: 하네스 카드 이동 도구·가드 훅·시험만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: 세트: 111360204d · 시험: bash tests/harness/test_index_move_slack.sh rc=0 · 이슈: 0 (evidence-check OK)
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/result-reply-close-gate.md 완성 --da <판정문>#§60`

## §61 CI 비용 차단 5개 — .github/workflows/ci.yml 문서 제외 · concurrency · observe-only 수동화 · main push 축소 (판정 436 · 오빠 즉시 · 나노 v436-ci-cost-cut) — 닫힘 (byz-harness-arch-claude#14 · 2026-10-08)
- 나노 커밋 `6fe01a83a1` [chore] CI 비용 차단 — 판정 436. 브랜치 nano/v436-ci-cost-cut · `.github/workflows/ci.yml` 1파일 +19/−0(트리거·concurrency·잡 `if:` 만 · steps·services·env 무변경).
- 근거: 오빠 판정 436(「github ci/cd bucket 크래딧 소모가 심각해」「1주?사이에 $120」) · planner REQ-436 · master #62971 · DA 생략(오빠 즉시).
- arch 독립 재현(#14 · 고정 sha 6fe01a83a1):
  ①yaml.safe_load OK · `on` = pull_request · push · workflow_dispatch
  ②잡 집합 전후 동일 13개 · needs 대상 전부 실재 · 조건 붙은 잡을 needs 로 받는 무조건 잡 0(연쇄 건너뜀 0)
  ③이벤트별 실행 잡(needs 전파 반영):
    - pull_request 10 = static_v4_feature_guard · python-lint · file-size-budget · python-test · schema-migrations · llm-contract · v5-spike-test · web-lint · web-test · mobile-test
    - push(main·develop) 4 = python-lint · schema-migrations · llm-contract · web-lint
    - workflow_dispatch 11 = 위 PR 잡 중 PR 전용 2개 제외 + python-test-red-observe · rbac-critical-drift · web-test-red-observe
    - 문서 경로만(docs/** · design/** · **/*.md · .fable-team/**) = 워크플로 미기동
  ④`actionlint -shellcheck= .github/workflows/ci.yml` rc=0 · 기본 actionlint rc=1 은 SC2086 info 2건 — 변경 전 파일도 같은 2건(본문 무변경 · 새 경고 0)
  ⑤concurrency group = workflow + PR 번호 또는 ref · cancel-in-progress = pull_request 일 때만(main·develop push 취소 0)
- 회당 분 전/후 예상(planner 회당 분 근거 · 실측 아님): PR 1회 ≈53 → ≈40(RED observe 12.2 + RBAC 제외) · main push 1회 ≈53 → ≈5(린트·스키마·LLM 계약) · 문서 전용 push 0 · 같은 PR 연속 push = 마지막 1회만. planner 실측 1.6일 기준(PR 129 · main push 129) 환산 ≈10,000분 → ≈5,800분(−42% · 문서 전용·취소분 미반영이라 하한).
- 구현 DA 소환: 아니오 — 오빠 판정 436 「즉시」·DA 생략(master #62971) · 1파일 트리거·조건만 · 되돌림 = revert 1커밋 — arch 서명 byz-harness-arch-claude#14.
- 반송 1건(형식): 증거 줄이 상태 줄 안에 괄호 설명과 섞여 evidence-check REJECT → 카드 끝 맨몸 1줄로 다시(나노).
- 관찰(반송 아님): ①develop push 도 main 과 같이 축소 — develop 대상 PR 에서 전체 시험이 돈다 ②`**/*.md` 제외라 CLAUDE.md·rules 같은 하네스 문서만 바꾼 PR 도 CI 0(의도) ③브랜치 보호 필수 체크 없음(rulesets API 403 요금제 · arch 실측) → 문서 전용 PR 이 체크 대기에 걸리지 않음 ④cd-dev.yml(main push)·cd-prod.yml(수동) 무변경 — CD 는 CI 결과와 독립으로 그대로 돈다.

### 랜딩 (master 집행 · ★판정 436 예외 1건★)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | PR 생성 · 본문에 위 재현 ①~⑤ 와 회당 분 1줄 | PR 번호 |
| 2 | 결제 복구 «전» squash 머지(이 PR 1건만 · CI 미실행 상태로 로컬 검증 증거로) | main 에 ci.yml 반영 |
| 3 | planner 회신: PR 번호 + 로컬 검증 증거 + 회당 분 전/후 1줄 | REQ-436 닫힘 |
| 4 | 결제 복구 뒤 첫 PR 1건 · 첫 main push 1건에서 이벤트별 잡 표 실측 대조 | PR 10 · push 4 · 문서 전용 0 |
| 5 | 되돌림 | ci.yml revert 1커밋 |

- 정본 영향 없음: CI 트리거·조건만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄(나노 재기입 뒤): 세트: 6fe01a83a1f27fed2386520a8a67ceac166079d1 · 시험: actionlint -shellcheck= .github/workflows/ci.yml rc=0 · 이슈: 0
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v436-ci-cost-cut.md 완성 --da <판정문>#§61`

## §62 공용 격리 Redis fixture 기동 대기 단축 — _v65_l6_redis._serve 소켓 대기 후 ping + kill 정리 (판정 438 · 설계 §2 안 가 · 나노 v438-l6-redis-fixture-fast) — 닫힘 (카드 v438 · 안 가 랜딩 5785530bea · ★판정 438 6분 목표는 열림 — 다음 한 수 아래★ · byz-harness-arch-claude#14 · #15 랜딩 실측 · 2026-10-08)
- 나노 커밋 `2106bc70f9` [fix] 격리 Redis fixture — 소켓 대기 후 ping · kill 정리 (판정 438). 브랜치 nano/v438-l6-redis-fixture-fast(base e3556432ae) · `tests/worker/unit/_v65_l6_redis.py` +6/−7(제품 코드 0).
- 설계 design/harness/DESIGN-pytest-speed-438-20261008.md r1 §1(발생 위치 = redis-py 7.4 기본 재시도 `ExponentialWithJitterBackoff(base=1, cap=10)` 가 소켓 생성 전 ping 안에서 잠듦) · §2 안 가 채택 · 나 기각 · 다·라 = 측정 게이트 뒤.
- 나노 보고(커밋 본문): CI 와 같은 경로 로컬 전 1028초 → 후 254초 · 7708 passed / 50 failed / 40 errors 전후 동일(실패·에러 97건 집합 diff 0).
- arch 독립 재현(#14 · 고정 sha 2106bc70f9 · 같은 머신):
  ①`LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1 timeout 1500 uv run pytest tests/gateway/unit tests/worker/unit tests/infrastructure/gpu --ignore-glob='*_red.py' --ignore-glob='*_red_*.py' -q -p no:cacheprovider --durations=20 -rfE` → 「50 failed, 7708 passed, 2 skipped, 60 deselected, 4 xfailed, 835 warnings, 40 errors in 248.50s (0:04:08)」(벽시계 252초)
  ②실패·에러 97건 = 18파일 · ★그중 `_v65_l6_redis` import 0파일★ — 이 변경이 닿을 수 없는 시험 · 원인 = `RuntimeError: PAYMENT_MODE is not set …`(81줄 · 로컬 env 미설정 · CI 는 설정) · node eval 실패 7 · 그 밖 소수
  ③후 durations 상위 = 전부 «call»(fixture setup 0) — e210 replay 35.8·32.1·9.3·9.2초 · owner_hydrate memory_peak 3.6초 · term_registry 3.4~2.9초 → 남은 시간은 설계 §1 의 «fixture 무관 CPU» 그대로
  ④diff 소스 대조: 소켓 파일 2ms×1000회 대기(프로세스 사망·상한 초과 = 기존 RuntimeError 문구) → ping 1회 → teardown kill · 서버 인자·fixture 이름·이중 정의·격리(테스트마다 새 서버) 무변경 · 고아 import(ConnectionError) 제거만
- 설계 전 실측과 대조: 샘플 12파일 70테스트 88.79 → 3.38초(arch 실험 플러그인)와 같은 방향 · 전체 4.1배.
- 구현 DA 소환: 아니오 — 격리 의미 무변경(판정 438 planner 「DA 는 격리 의미가 바뀌는 안만」) · 결정적 재현(전후 통과 수 동일 · 실패 파일 fixture 무관) — arch 서명 byz-harness-arch-claude#14.
- 반송 1건(형식): 진행 카드 끝 증거 줄 없음 → 나노가 맨몸 1줄 append(`세트: 2106bc70f9… · 시험: uv run pytest tests/worker/unit -q -p no:cacheprovider rc=… · 이슈: 0` — 카드 완료 조건 꼴 · rc 는 로컬 PAYMENT_MODE 미설정 실패 포함이면 그 사실을 이슈 칸이 아니라 RESULT 에).
- 반송 2건째(형식 · byz-harness-arch-claude#15 · #63194): 16:26 origin/main 병합 `7280f7cf5a`(main 포함 확인) 뒤 세트 HEAD 불일치 → 나노가 새 HEAD 에서 재시험·줄 교체(#63198) · evidence-check OK(arch#15 재실행). 병합이 `tests/worker/unit/_v65_l6_redis.py` 에 준 diff 0줄 · origin/main...HEAD = 그 파일 +6/−7 하나 → ①~④ 재현 유효. arch#15 새 HEAD 재현: `LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1 timeout 600 uv run pytest tests/worker/unit/test_v65_unsealed_terminal.py tests/worker/unit/test_v65_l6_pair_boundaries.py -q -p no:cacheprovider` → 「21 passed in 1.96s」.
- 관찰(반송 아님): ①PR CI 예상(추정 · 실측 아님) = Run tests 19.2분 × 248/1028 ≈ 4.6분 + 잡 준비 ≈1.8분 ≈ 6.4분 — ★목표 6분 경계★ · 설계 §3-3(라·다) 판단은 PR CI 실측으로 ②로컬 `PAYMENT_MODE` 미설정 97건은 이 단위 밖(로컬 env 정본 문제 · 별건 후보).

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 | 실측 (master#16 #63264 · arch#15 확인) |
|---|---|---|---|
| 1 | PR 생성 · 본문에 위 재현 ①~④ | PR 번호 | PR #935 · head `7280f7cf5a` · 병합 `5785530beafa0b93a59a9a4e2543409393f2990b`(origin/main 조상 확인 · diff = `_v65_l6_redis.py` +6/−7 하나) |
| 2 | PR CI Python Test 잡 분 실측 | 전 21.0분 → 후 n분 | 잡 21m37s → ★8m53s★(07:27:11→07:36:04Z · SUCCESS · run 37743465246 job 113199471577) · 단계: 준비(Set up~Install deps) 1m27s · ★Run tests 7m01s★ · V5 focused 18s |
| 3 | planner 회신: 로컬 1028→248초 + CI 분 전·후 1줄 | ≤6분 = 판정 438 닫힘 · >6분 = 설계 §3-3 planner 결정 | ★6분 초과(8m53s)★ — 설계 r1 §3 추정 6.4분이 틀림(CI Run tests 421초 = 로컬 248초의 1.7배 · 추정은 1:1 가정) · 판정 438 은 열림 유지 → 다음 한 수 아래 |
| 4 | 되돌림 | 1커밋 revert | 불필요(전후 통과 동일 · CI SUCCESS) |

### 다음 한 수 (arch#15 판정 · 설계 438 §3-3)
- 6분 잡 = Run tests ≤ 약 4m10s 필요(준비 1m27s + V5 18s 고정).
- 라(slow 마크 · e210 replay 4 + term_registry): 로컬 합 ≈ 86초+α × CI 1.7배 ≈ −2.5~3분 → Run tests ≈ 4~4.5분 · 잡 ≈ 6~6.3분(★경계 · 못 넘을 수 있음★) + PR 커버리지 이동(e210 회귀가 야간에야 잡힘 · 오빠 판정 필요).
- 다(pytest-xdist `-n auto` · ubuntu-latest 4 vCPU): Run tests ≈ 2~2.5분(추정 · 직렬 고정분 있음) · 잡 ≈ 4분 · 커버리지 무변경 · 대가 = 테스트 간 동시 실행이 새로 생김(/tmp·env·모듈 전역) → 사전 DA 1회 + 로컬 `-n 4` 전후 실패 집합 diff 0 시험.
- ★arch 판정: 다 (사전 DA 1회 뒤 나노 1)★ — 라 는 6분을 확실히 못 넘기고 커버리지를 잃는다. 라 는 다 실측 뒤에도 >6분일 때만 다시 연다. 설계 §3-3 이 «planner 결정» 으로 묶어 두었으므로 planner 값 1개(다 착수 GO) 필요.

- 정본 영향 없음: 테스트 fixture 만 — docs/architect 제품 정본 변경 없음.
- 카드 증거 줄: `세트: 7280f7cf5a…` · evidence-check 「OK 증거 줄 — 세트 HEAD 7280f7cf5 · 시험 rc=0 · 이슈 0」(카드 미커밋 · master 커밋). PR 은 HEAD `7280f7cf5a` 로.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v438-l6-redis-fixture-fast.md 완성 --da <판정문>#§62`

## §63 PR 템플릿 정본 줄·Refs 자리·완료 6항 (판정 444 · 440 설계 r2 §4 순서 3 · 나노 v444-pr-template-canon-line) — 닫힘 (byz-harness-arch-claude#15 · 2026-10-08)
- 대상 카드: v444-pr-template-canon-line
- 나노 커밋 `7e1250a375` [docs] PR 템플릿에 정본 줄·Refs 자리·완료 6항. 브랜치 nano/v444-pr-template-canon-line(base origin/main cb0d313486) · `.github/PULL_REQUEST_TEMPLATE.md` +9/−2 1파일.
- arch 독립 확인(#15 · 고정 sha 7e1250a375): ①`git diff --stat origin/main...HEAD` = 템플릿 1파일 ②세 자리 실재 — 첫 줄 주석 「큰 Issue 의 일부면 이 줄을 `Refs #N` 으로(최종 닫는 PR 만 Closes)」 · `## 정본` 절(정본 줄 / 영향 없음 줄 + worker·gateway·shared 안내 주석) · 완료 항목 「- [ ] 정본:」 + `정본: <X>#<절>@<랜딩 sha>` 안내 ③「5항」 글자 0 · 23줄(≤40) ④`git diff --check origin/main HEAD` rc=0.
- 카드 증거 줄 evidence-check(arch 재실행 · --feat origin/main): 「OK 증거 줄 — 세트 HEAD 7e1250a37 · 시험 rc=0 · 이슈 0」. 카드는 문서 전용 꼴(「시험: 없음(문서)」)을 적었으나 나노가 `git diff --check` rc=0 을 적음 — 검사 통과 · 반송 아님.
- 구현 DA 소환: 아니오 — 문서 1파일 · 동작 0 · 440 r2 APPROVE 범위 그대로 — arch 서명 byz-harness-arch-claude#15.
- 관찰(반송 아님): 템플릿 자리표시 `<파일>`·`<이유 ≥10자>` 가 그대로 Issue 코멘트에 복사되면 issue-close-check 줄 규칙(`[^<\s]`)이 미기재로 본다 — 의도대로.

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | PR(문서 전용 · paths-ignore 로 CI 0 예상) 또는 444 다른 카드와 한 PR | ★PR #941 · 병합 `0cb14f7d39`(origin/main 조상 확인 · main 템플릿에 「6항」 실재)★ |
| 2 | 팀 master 들 1줄 공지 | 「랜딩 PR 본문 정본 줄 필수 · 부분 PR 은 Refs」 |
| 3 | 되돌림 | 1커밋 revert |

- 정본 영향 없음: PR 템플릿 문서만 — docs/architect 제품 정본 변경 없음.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v444-pr-template-canon-line.md 완성 --da <판정문>#§63`

## §64 ft-index-move 진행→완성 — 정본 갱신 카드 랜딩 commit 사실 검사 + 정본 쪽지 수신자 팀 _arch + DA 절-카드 결속(R37 합침) (판정 444 · 440 설계 r2 §4 순서 1 · 나노 v444-index-move-canon-landed) — 닫힘 (byz-harness-arch-claude#15 · 2026-10-08)
- 대상 카드: r37-index-move-da-section-binding (R37 · 범위 전부가 이 절의 v444-index-move-canon-landed 에 합쳐져 PR 944 로 랜딩 — 합침 카드 정리 · arch#15 #63740)
- 나노 커밋 `726d0bd7ab` [feature] + 반송 반영 `57c765fffe`(REJECT 문구에 고치는 법). 브랜치 nano/v444-index-move-canon-landed(base origin/main cb0d313486) · `scripts/fable-team-bin/ft-index-move.sh` 110줄 + 새 `ft-index-move-canon.sh` 86줄(각 키트 사본 같은 바이트) · `tests/harness/test_index_move_canon_landed.sh` 113줄 · `test_index_move_slack.sh` 기대 문구 맞춤.
- arch 독립 재현(#15 · 고정 sha 57c765fffe · 같은 머신): `test_index_move_canon_landed.sh` fail=0 rc=0(①~⑧ + 음성 6) · `test_index_move_slack.sh` fail=0 · `test_kit_bin_sync.sh` ALL PASS · 사본 cmp 2쌍 OK · bash -n 2개 OK.
- arch 소스 대조: (R37)절 찾기 = `## ` 헤더 안 §N 뒤가 숫자가 아님(§ 없는 이름은 포함 비교) · 절 본문에 카드 basename 없으면 REJECT + 「그 판정 절에 「대상 카드: <카드>」 줄을 넣고 다시」 · 정본 갱신 줄 «전부» 검사(옛 코드는 첫 줄만) · `--landed S|T..S` 필수(갱신 카드) · (가)`merge-base --is-ancestor S $FT_LAND_REF`(기본 origin/main · fetch 0 · S 없으면 「git fetch 후 다시」) (나)R(S)=`S^1..S` 또는 `T..S` 의 name-only 에 X (다)판정 절의 `정본 diff 확인: X §… @C` 마다 `C:X` blob == `S:X` · 영향 없음 카드는 --landed 있을 때 (가)만 · merge-base 계산 0 · 정본 쪽지 수신 = 명부 최상위 `_arch`(없으면 INFO · 쪽지 0) · 슬랙 결과 답글엔 S 만 넘김(`${LANDED##*..}`).
- 재판정 표(나노 RESULT · 읽기만): origin/main 완성 654장 중 판정 가능 523 = 통과 269 / 거부 254(전부 「절에 카드 이름 없음」 — v65 213 · harness 40 · planner 1) · 판정 불가 131.
- ★arch 판정(master#16 #63424 질문 → #63443): (가) 엄격 유지 · 소급 없음★ — 규칙은 앞으로의 완성 이동에서만 돈다. arch 재분류: harness 40 = 옛 OPS-VERDICTS 묶음 절(c10~c19 · §58~ 꼴은 절에 「진행→완성: ft-index-move.sh …/<카드>.md」 줄이 있어 통과) · v65 = 카드 전용 판정 파일인데 절에 카드 이름 없는 꼴 160 + 여러 카드 파일 54. (나)WARN 기각 — master 실례(v436 → §60 다른 카드 절)가 조용히 통과 = 선언만 있고 강제 없음 · 「전용 파일 면제」 기각(면제 목록 금지). 비용 = 다음 완성 이동부터 판정 절에 「대상 카드: <카드>」 1줄.
- 반송 1건(문구): REJECT 에 고치는 법 없음 → `57c765fffe` 반영.
- 구현 DA 소환: 아니오 — 440 r2 DA APPROVE(§6-1 ①~③ · §6-5 fixture 3) 범위 그대로 · 시험이 DA 지정 fixture 를 직접 가짐 — arch 서명 byz-harness-arch-claude#15.
- 관찰(반송 아님): 카드 이름 대조는 부분 문자열(grep -F) — 짧은 basename 이 긴 이름에 포함되면 통과할 수 있음(현 카드 이름 길이로는 실해 0 · 필요 시 별건).

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | PR(444 다른 카드와 묶어도 됨) · 본문에 재현·판정 (가) | ★PR #944 · 병합 `1140076188b86a7c866e1db6377071dd6a77ed73`(origin/main 조상 확인 · 6파일 +328/−121)★ |
| 2 | 라이브 FT_BIN cp(`ft-index-move.sh` + 새 `ft-index-move-canon.sh`) · `ft-live-bin-drift-check.sh` | ★설치 완료(master#16 #63579) · arch cmp: 라이브 FT_BIN 두 파일 = origin/main 바이트 동일★ |
| 3 | 팀 master·DA 좌석 공지 1줄 | 「완성 이동: 판정 절에 「대상 카드: <카드>」 줄 · 정본 갱신 카드는 --landed <랜딩 sha>」 |
| 4 | 되돌림 | 1커밋 revert + FT_BIN 이전 사본 |

- 정본 영향 없음: 하네스 카드 이동 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v444-index-move-canon-landed.md 완성 --da <판정문>#§64` — ★이 절은 카드 이름 `v444-index-move-canon-landed` 를 싣는다(새 결속 규칙 자기 적용)★.

## §65 CI Mobile Test — 모바일 무변경 PR 은 잡 레벨 skip(Detect Changes) + Set up Flutter 5분 timeout (판정 451 ⓐ+ⓑ · 나노 v451-ci-mobile-test-gate) — 닫힘 (byz-harness-arch-claude#15 · 2026-10-08)
- 대상 카드: v451-ci-mobile-test-gate
- 나노 커밋 `0ccbf415cc` [chore] + origin/main 병합 `5ce91ec4ce`. 브랜치 nano/v451-ci-mobile-test-gate · `.github/workflows/ci.yml` +38/−1 1파일(새 잡 changes · mobile-test needs+if · Set up Flutter timeout-minutes 5 · 다른 잡 무변경).
- arch 독립 재현(#15 · 같은 머신): ci.yml 에서 detect step run 본문을 yaml 로 뽑아 임시 git 리포 5경우 실행 → (a)clients/mobile 변경 rc=0 mobile=true (b)worker 만 rc=0 mobile=false (c)ci.yml 변경 rc=0 mobile=true (d)없는 base sha rc=128 출력 0(감지 실패 = changes 잡 실패) (e)workflow_dispatch rc=0 mobile=true — 나노 RESULT 와 같음.
- actionlint: rc=1 = 기존 SC2086 info 2건(550행 등 · 건드린 줄 밖) · ★origin/main 사본과 findings 동일(arch diff 0)★ · `actionlint -shellcheck= .github/workflows/ci.yml` rc=0. 카드 완료 조건 「actionlint rc=0」 은 기존 findings 를 못 본 arch 문구 실수 → 수락(증거 줄 시험 칸 = `actionlint -shellcheck=` rc=0).
- `if:` 식 검토: changes 실패면 mobile-test skip 이지만 changes 잡 빨강으로 워크플로 실패 = 조용한 통과 0. branch protection·rulesets API 403(비공개·무료) = 필수 검사 없음 — 잡 레벨 방식은 필수 검사가 생겨도 안전.
- 구현 DA 소환: 아니오 — CI 1파일 · 되돌림 1커밋 · 위험 2개(조용한 skip · 밖 경로 의존 0) 재현으로 확인 — arch 서명 byz-harness-arch-claude#15.
- 관찰(반송 아님): 감지는 `base.sha..head.sha` 2점 diff — PR 이 오래돼 main 에 모바일 변경이 쌓이면 mobile=true 로 «더 돈다»(빠뜨림 방향 아님 · 비용만).

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | PR 1회 · 446(ci.yml Run tests 줄)과 랜딩 순서 정함 | ★PR #945 · 병합 `4108c1f531d96e88df7804ccebd705c994db8d65`(origin/main 조상 확인 · ci.yml +38/−1) · 451 먼저 → 446 은 그 위로 병합(master)★ |
| 2 | 그 PR CI: Detect Changes 로그 「changed=n matched=m -> mobile=true」(ci.yml 변경 = 경우 c 실물) · Mobile Test 실행 | ★Detect Changes 33s 통과 · Mobile Test 1m23s 실행(경우 c 실물 · master#16 #63579)★ |
| 3 | 다음 비모바일 PR 1건: Mobile Test = skipped(경우 b 실물 · 따로 PR 만들지 않음) → planner 회신 | skipped — ★대기(다음 정상 PR)★ |
| 4 | 되돌림 | 1커밋 revert |

- 정본 영향 없음: CI 워크플로 1파일 — docs/architect 제품 정본 변경 없음.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v451-ci-mobile-test-gate.md 완성 --da <판정문>#§65`

## §66 ft-issue-close-check 6항 «정본» — 랜딩 commit 에 정본 diff 가 있어야 Issue 닫기 통과 + 픽스처 3 + ISSUE-TRANSITIONS §3 1행 (판정 444 · 440 설계 r2 §4 순서 2 · 나노 v444-issue-close-canon-6th) — 닫힘 (byz-harness-arch-claude#15 · 2026-10-08)
- 대상 카드: v444-issue-close-canon-6th
- 나노 세트 `ef6fb99143`(카드 증거 줄) → master#16 독립 검증 뒤 PR #943 squash 병합 `eb0a9263a054bb712c456bda603c713b12da7253`(첫 부모 1da5a43a3d · origin/main 조상) · 7파일 +200/−20: `scripts/fable-team-bin/ft-issue-close-check.sh`(+ 키트 사본) · 픽스처 `closed-with-6items-canon.json`·`closed-with-6items-no-impact.json`·`closed-partial-two-sha.json` · `tests/harness/test_issue_close_canon.sh` 88줄 · `design/harness/ISSUE-TRANSITIONS.md` §3.
- arch 독립 재현(#15 · 병합 eb0a9263a0 을 포함하고 그 7파일에 diff 0 인 HEAD 5ce91ec4ce 워크트리 · 나노 워크트리는 닫힘): `test_issue_close_canon.sh` ALL PASS rc=0(①~⑧ + S 로컬 없음 → fetch 안내 MISS) · `test_kit_bin_sync.sh` ALL PASS · 사본 cmp OK · bash -n OK.
- arch 소스 대조: 6항 `정본: <파일>#<절>@<sha 목록>` · 각 sha (가)`merge-base --is-ancestor S $FT_LAND_REF`(기본 origin/main · fetch 0 · S 없으면 「git fetch 후 다시」) (나)`S^1..S` 또는 `T..S` name-only 에 파일 · 부분 PR `@S1,S2` 각각 · `정본 영향 없음:` 은 글자 수 ≥10(jq length · 로케일 무관) · 키 정규식이 `정본\s*[:：]` 라 「정본 영향 없음:」 줄과 섞이지 않음 · 5항·Closes 검사 무변경 · gh 호출 1회·쓰기 0 유지.
- 구현 DA 소환: 아니오 — 440 r2 DA APPROVE(§2-3 표 2행 · §6-1 ①② · §6-3 · §6-5 fixture 4행) 범위 그대로 — arch 서명 byz-harness-arch-claude#15.
- 관찰(반송 아님): 정본 파일 경로는 디렉터리 제한이 없다(카드 이동 문은 docs/architect 만) — Issue 작업은 하네스 정본(docs/rules · 스킬 references)도 고치므로 의도대로.

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | PR | ★PR #943 · 병합 `eb0a9263a0`(origin/main 조상 확인)★ |
| 2 | 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` | ★arch cmp: 라이브 FT_BIN `ft-issue-close-check.sh` = origin/main 바이트 동일★ |
| 3 | issues master 공지 1줄 | 「Issue 닫기 코멘트에 6항 정본 줄 필수」 |
| 4 | 되돌림 | 1커밋 revert |

- 정본 영향 없음: 하네스 Issue 닫기 검사 도구·전이표·시험만 — docs/architect 제품 정본 변경 없음.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v444-issue-close-canon-6th.md 완성 --da <판정문>#§66`

## §67 CI Python Test 병렬화 — pytest-xdist `-n auto --dist loadgroup` + 공유 Redis 접촉 26모듈 한 그룹 (판정 446 · 설계 r2 · 판정 438 6분 목표 · 나노 v446-ci-pytest-xdist) — 닫힘 (카드 v446 · ★판정 438 6분 목표는 열림 — CI 2 워커 · 다음 한 수 아래★ · byz-harness-arch-claude#15 · 2026-10-08)
- 대상 카드: v446-ci-pytest-xdist
- 나노 커밋 4개(base origin/main cb0d313486): `6371d098e2` dev extra pytest-xdist + uv.lock(xdist 3.8.0 + execnet 2.1.2 추가뿐) · `ffae65cef4` 26모듈 `pytestmark = pytest.mark.xdist_group("shared_redis_6379")`(기존 pytestmark 3개는 리스트 합침 · arch 대조: 추가 줄 = 마커 23 + 빈 줄 23 + 합침 3 · 본문 변경 0) · `d79fccd5ce` ci.yml Run tests 에 `-n auto --dist loadgroup`(1줄) · `3295007174` RESULT.
- 공유 모듈 찾은 법(나노 · 정적 grep 아님): 직렬 실행 중 컨테이너 Redis `total_commands_processed`·`total_connections_received` 증가 > 0 인 시험의 모듈 → 26(gateway 라우트 21 — 앱 기본 REDIS_HOST/PORT 로 공유 6379 접속 · worker 5). arch 설계 §2 의 grep(worker lst_* 만)보다 넓다 — 실측이 이긴다. 한계: 직렬 2회 기준 · 타이밍 의존 접촉은 놓칠 수 있음(RESULT 「한계」).
- 가려진 공유 Redis 시험(DA Q3): `LST_TEST_REDIS_URL=redis://localhost:6379/15` 직렬 vs 기본 직렬 nodeid 상태 diff 0 → 가려진 nodeid 0 · db15 요구 시험은 `requires_real_redis` deselect 60 쪽 → 설계 6-2 조건 불성립으로 ci.yml env 추가 안 함(수락).
- ★arch 독립 재현(#15)★: 나노 HEAD `3295007174` 를 `git archive` 로 새 볼륨에 풀고(나노 작업 볼륨 미사용 · node_modules·venv 만 의존성 환경으로 재사용) `docker run --network none --cpus 4` 일회용 컨테이너 안 자체 redis-server(127.0.0.1:6379)로 CI 경로 실행:
  ①직렬 「1 failed, 7812 passed, 2 skipped, 60 deselected, 4 xfailed in 273.50s」 · 병렬 `-n 4 --dist loadgroup` 「1 failed, 7812 passed, 2 skipped, 4 xfailed in 116.99s」 · 「created: 4/4 workers」 · crash 문자열 0
  ②junit nodeid 상태(그룹 접미 정규화) arch 직렬 ↔ arch 병렬 diff 0 (7819 / 7819) · arch 직렬 ↔ 나노 serial2 diff 0
  ③유일 실패 = `test_v6_d1_import_fence::test_consumers_package_and_pulse_init_are_untouched_by_this_fix`(실행 볼륨이 git 리포 아님 · 직렬·병렬 같은 원인 · 나노와 같음 · CI 러너는 리포라 통과 추정)
  ④병렬 -v 로그 `@shared_redis_6379` 720줄(시작·결과 2줄 × 약 360 nodeid · 나노 359 와 일치)
  ⑤벽시계 직렬 278s → 병렬 118s(2.36배 · 나노 2.4배와 같음). 개발 Redis 접속 0.
- 반복 2회(나노 r1·r2) + arch 1회 = 제한된 관측 · flake 부재 증명 아님.
- 사전 DA: design/harness/DA-xdist-446-20261008.md r1 HOLD(Q3) → r2 APPROVE(#63367). 구현 DA 소환: 아니오 — r2 승인 조건(nodeid 상태표 · 가려진 시험 증거 · 격리 실행) 전부 충족 · arch 재현 일치 — arch 서명 byz-harness-arch-claude#15.
- 관찰(반송 아님): ci.yml 은 나노 base(cb0d313486) 위 — 451(#945) 이 같은 파일 다른 잡을 고침 → master 가 origin/main 병합 뒤 push.

### 랜딩 (master 집행 · 카드 밖)
| # | 할 일 | 기대값 |
|---|---|---|
| 1 | origin/main 병합(451 포함) · ci.yml 충돌 확인(`merge-tree` · rc 확인) · PR 1회 push | ★PR #951 head `cb4f40b636`(master 병합 · ci.yml 에 -n auto 1줄 + Detect Changes 둘 다)★ · 나노 뒤 커밋 `b7c0600dd`(RESULT 3줄 문서만 · 열린 PR 에 문서 단독 push 0 — 판정 436) |
| 2 | PR CI Python Test 잡 시간 + 로그 「created: N/N workers」 | ★잡 8m53s → 7m15s(08:34:05→08:41:20Z · SUCCESS · job 113222868878) · 「created: 2/2 workers」(비공개 리포 러너 2 vCPU — 설계 §3 추정대로) · Run tests 7m01s → 5m19s(「7834 passed, 2 skipped, 4 xfailed in 315.26s」) · 준비 1m34s · V5 16s★ |
| 3 | planner 회신 | ★>6분(7m15s) → 판정 438 열림 · 다음 한 수 planner 결정(아래)★ |
| 4 | CI 간헐 실패 시 | 해당 모듈을 그룹에 추가(RESULT 「한계」) — 재실행 반복 0(판정 436) |
| 5 | 되돌림 | ci.yml 1커밋 revert(또는 4커밋) |

### 병합 HEAD 재시험(나노 #63675 · 접촉 측정)
- master 병합으로 CI 경로에 새 시험 3파일(glossary_public_visibility · glossary_write_service · loom_admin_errors) → 나노 redis_touch 측정 접촉 0 · 마커 없는 접촉 모듈 0 · 병합 HEAD 직렬 4:36 ↔ `-n 4` 1:44 · nodeid 7840 diff 0 · 증거 줄 evidence-check OK(세트 b7c0600dd · arch 재실행). → 2차 push 불필요.

### 판정 438 다음 한 수 (arch#15 · 6분 = 잡 −1m15s 필요)
| 안 | 기대(추정) | 대가 | 결정자 |
|---|---|---|---|
| 라 slow 마크(e210 replay 4 + term_registry) PR 제외 · 수동/야간 | Run tests −1~1.3분(직렬 ≈2.5분 ÷ 2 워커) → 잡 ≈6.0분(경계) | e210 회귀 PR 커버리지 이동 | 오빠(커버리지) |
| 큰 러너(4 vCPU · GitHub larger runner) | 4 워커 · Run tests ≈3분 → 잡 ≈5분 | 분당 단가 2배 → 잡당 비용 ≈+40%(5분×2 vs 7.25분) · 조직 결제 설정 | 오빠(비용) |
| `-n 3`/`-n 4` on 2 vCPU | 0~30초(I/O 대기분만) | 거의 0 · PR 1회 측정 | planner |
| 준비 다듬기(npm·apt 캐시) | −15~25초 | 작음 | planner |
- arch 추천: ★6분 목표를 꼭 지킬 거면 라 + 준비 다듬기(무료 · 커버리지 결정 1개)★ · 비용보다 속도면 큰 러너. 지금 7m15s 도 전(21m37s) 대비 3배 — «목표를 7분 반으로 고칠지» 도 오빠 선택지.

- 정본 영향 없음: CI 설정·테스트 마커·dev 의존성만 — docs/architect 제품 정본 변경 없음.
- 진행→완성: `ft-index-move.sh design/harness/indices/진행/v446-ci-pytest-xdist.md 완성 --da <판정문>#§67`

## §68 슬랙 미러 둘 정지 복구 — github 미러 format_row 호출 정합 + mbox 미러 좌석 정규식 (판정 442 · 오빠 「슬랙 알림 전혀 안 옴」 · 나노 v442-slack-mirror-two-dead) — 닫힘 (byz-harness-master-claude#16 · 2026-10-08)
- 대상 카드: v442-slack-mirror-two-dead
- 원인 2건(planner 진단 = master 실측 일치): ①PR 911 이 `mirror_lib.format_row` 시그니처를 바꿨는데 `byz_github_slack_mirror.py:57` 이 옛 위치 인자 7개로 호출 → TypeError 크래시 루프 ②mbox 미러 plist `--seat '^byz-planner-arch#…'` 가 현역 `byz-planner-master-claude#N` 과 매칭 0.
- 수정(PR 937 병합 `cb0d313486` · 나노 커밋 `80afa05c83` 이후 `37350a4a04`): github 미러가 `resume_block.block` 으로 format_row 호출 정합 · `install.sh` 좌석 기본값 `^byz-planner-(arch|master-claude)#[0-9]+$` · `install-github.sh` 가 `resume_block.py` 도 설치 · 시험 `tests/harness/test_slack_mirror_signature.sh`(ALL PASS).
- master 독립 검증: 시험 ALL PASS · ruff 0 · shellcheck -S warning OK · 미러 pytest 37 passed(수정 전 github 7 실패) — 최신 main 병합 뒤 재시험 후 push 1회.
- 라이브 반영(master 집행): `install-github.sh` + `install.sh` 재실행 → github 미러 재기동 뒤 크래시 0 · mbox 미러 launchctl bootstrap 1회 I/O 에러 뒤 재시도로 로드 · 실제 슬랙 도착 = 오빠 실측(#63158) · planner 확인(#63164).
- 열린 것: `com.hermes.byz-slack-mbox-inbound` 는 설치 뒤 누가 bootout 한 상태(설치 스크립트 결함 아님) — 로드하지 않음, 필요해지면 planner [HIL].
- 정본 영향 없음: 하네스 슬랙 미러 도구·시험만 — docs/architect 제품 정본 변경 없음.

## §69 판정 438 닫힘 — pytest(Python Test) 속도 목표를 7분 반으로 조정 (판정 460 · 오빠 · planner#11 #63729 · 2026-10-08)
- 결정: Python Test 잡 목표 = 7분 반. 현재 7m15s(PR 951 · cec6f0f8c8)로 판정 438 닫힘. 추가 단축 작업 0 — slow 마크·4 vCPU 큰 러너 안 함. 6분 목표(설계 438 §3-3)는 이 결정으로 대체.
- 경과: 21m37s(PR 929) → 8m53s(PR 935 fixture · §62) → 7m15s(PR 951 xdist · §67).
- 정본 영향 없음: CI 목표 수치 결정만 — docs/architect 제품 정본 변경 없음.

## §70 인박스 큐 행 분류 출처 필드 via = rule|haiku|unknown (판정 461 · 나노 v461-inbox-row-via) — 닫힘 (byz-harness-arch-claude#16 · 2026-10-08)
- 대상 카드: v461-inbox-row-via
- 랜딩: PR #954 병합 `ed256f78ab`(origin/main · 부모 `fc75608f73`) — 3파일: `scripts/fable-team-bin/ft-inbox.py` · 키트 사본 `scripts/harness-install/fable-team/bin/ft-inbox.py` · `tests/harness/test_inbox.sh`(+41).
- 변경 2줄(셈 전용): `cmd_ingest` 새 행에 `"via": "unknown" if cls == "미상" else "rule"` · `cmd_classify`(Haiku 갱신)에서 `via="haiku"`. 표시·mark·report·archive 무변경 · 옛 행 마이그레이션 0.
- ★arch 독립 재현(#16)★: `git archive ed256f78ab scripts tests/harness tools/comm-canonical` 을 스크래치패드 새 폴더에 풀어 `bash tests/harness/test_inbox.sh` → rc=0 · PASS 64 · RESULT fail=0(via 101~106 = rule · 107 미상+Haiku 성공 = haiku · 108 미상+Haiku 실패 = unknown · 새 행 502 = rule · show/--compact 바이트 = via 키 제거본과 같음 · 옛 행 mark·report·보관 뒤 via 키 없음 · mbox send 훅 rc 0 유지 · test_kit_bin_sync PASS) · `bash -n` OK. 나노 보고(PASS 64 · fail 0)와 같은 값.
  - 첫 재현은 `tools/comm-canonical` 을 빼고 풀어 mbox send 훅 7건 FAIL(rc 127 = 파일 없음) — 시험이 `$REPO/tools/comm-canonical/mbox.sh` 를 복사해 쓰기 때문 · 추출 범위 문제(제품 결함 아님).
- 설치: 라이브 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-inbox.py` = `ed256f78ab` 정본과 cmp 같음 · 키트 사본 cmp 같음(arch#16 확인).
- 남은 확인(master 몫 · #63807): 다음 쪽지 적재 때 라이브 큐 행에 `via` 가 실제로 들어가는지 1건.
- ★증거 줄 공백(관찰 · 반송 아님)★: 카드는 ops/main-base `design/harness/indices/진행/` 에 있고 나노 워크트리(origin/main 기준)에는 카드가 없어 나노가 카드 끝 증거 줄을 못 썼다 — 나노는 pane 보고로 대신함. 판정 444 ②(하네스 나노 base = origin/main) 이후 카드 위치(ops/main-base)와 나노 base 가 갈라진 구조 문제 → master 판단 요청(카드를 main 에 두거나 · 증거 줄을 판정 절로 대체 허용).
- 사전검증 DA: 소환 아니오(카드 면제 · arch#15 서명) · 구현 DA 소환: 아니오 — 변경 2줄 · 셈 전용 필드 · arch 재현 일치 — arch 서명 byz-harness-arch-claude#16.
- 정본 영향 없음: 하네스 인박스 도구 행 필드·시험만.

## §71 `--base <sha>` 로 연 나노 좌석 닫기 막힘 해소 — close 는 sha 를 랜딩 브랜치로 환원(조상 아니면 REJECT) · spawn 은 base 에 브랜치 기록 (R42 · v65 master#148 실례 · 나노 r42-nano-close-sha-base) — 닫힘 (byz-harness-arch-claude#16 · 2026-10-08)
- 대상 카드: r42-nano-close-sha-base
- 나노 커밋 1개(base origin/main): `ce1d7da3dc28ae86ca4552a7f22a3154a047faff` = PR #956 head · 5파일(close·spawn 정본 + 키트 사본 · 시험 `tests/harness/test_nano_close_sha_base.sh` +115). `ft-nano-cherry-gate.sh` diff 0(카드 금지 준수).
- 변경: close — `FT_NANO_FEAT` 미지정 + info.base 가 refs/heads·refs/remotes 아니고 commit 이면 `_BASE_SHA` 로 떼고 기본 사슬로 랜딩 브랜치 결정 → fetch 뒤 `merge-base --is-ancestor` 참이면 `INFO base sha <9> → 랜딩 브랜치 <x>` · 거짓이면 REJECT 「base 가 sha <9> 이고 <x> 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시」. spawn — `--base` 가 commit 이면 info `"base"` = `FT_NANO_FEAT` 또는 지금 브랜치 · `"base_sha"` 는 기존대로.
- ★arch 독립 재현(#16)★: `git archive ce1d7da3dc scripts tests/harness tools/comm-canonical` → 스크래치패드 새 폴더: `test_nano_close_sha_base.sh` rc=0 PASS 21 · `test_nano_close_named_wt.sh` rc=0 PASS 50 · `test_cherry_gate_squash.sh` rc=0 PASS 27 · `test_kit_bin_sync.sh` rc=0 PASS 6 · close·spawn·cherry-gate 사본 cmp + bash -n OK. 카드 ①~⑥ 전부 대응(sha 조상 → CLOSED+INFO+기준=랜딩 브랜치 · 조상 아님 → REJECT+kill 0+명부 그대로 · 브랜치 base 무변경 · FT_NANO_FEAT 우선 · spawn sha→브랜치/FT_NANO_FEAT · 이름/없음 무변경).
- PR #956 CI: Python Test·Lint·Static Guard 등 전부 SUCCESS(관찰 2026-10-08).
- 카드 증거 줄: 나노 pane 보고에 「세트/시험/이슈」 맨 끝 1줄 형식 없음(커밋 ce1d7da3dc · 시험 rc=0 만 서술) → master 가 `세트: ce1d7da3dc28ae86ca4552a7f22a3154a047faff · 시험: bash tests/harness/test_nano_close_sha_base.sh rc=0 · 이슈: 0` 을 카드 끝에 적고 evidence-check(나노 wt) 확인.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp 2파일(ft-nano-close.sh · ft-nano-spawn.sh) + cmp · v65 master 에 1줄(「--base <sha> 좌석도 FT_NANO_FEAT 없이 닫힘 · 랜딩 브랜치 조상 아니면 REJECT 문구대로」).
- 사전검증 DA: 소환 아니오(카드 면제 · arch#15 서명) · 구현 DA 소환: 아니오 — 게이트 무변경 · 조상 아니면 REJECT(추측 0) · arch 재현 일치 — arch 서명 byz-harness-arch-claude#16.
- 정본 영향 없음: 하네스 나노 개설·닫기 도구·시험만.

## §72 ft-index-move 완성 이동 — 「정본 영향 없음」 카드는 [정본 갱신 요청] 쪽지 생략 (R41 · 소음 실례 #63684·#63707·#63747·#63820 · 나노 r41-index-move-canon-notice-noise) — 닫힘 (byz-harness-arch-claude#16 · 2026-10-08)
- 대상 카드: r41-index-move-canon-notice-noise
- 나노 커밋 1개(base origin/main): `66e26a1edda0e89be171ab291559e78e075185e7` (PR #958) · 3파일(ft-index-move.sh 정본 + 키트 사본 +4 · `tests/harness/test_index_move_canon_landed.sh` +9/−4). `ft-index-move-canon.sh` 무변경.
- 변경: 쪽지 단계(이동·원장 기록 뒤)에서 `CANON_NOTE` 가 `정본 영향 없음:` 으로 시작하면 `INFO 정본 쪽지 생략 — 정본 영향 없음 카드` 후 exit 0 — 정본 게이트·슬랙·원장 무변경.
- ★arch 독립 재현(#16)★: `git archive 66e26a1edd scripts tests/harness tools/comm-canonical` → 스크래치패드 새 폴더: `test_index_move_canon_landed.sh` rc=0 PASS 18(⑧ 갱신 카드 → _arch 쪽지 NOTIFIED · ⑧b _arch 없음 → INFO · ⑧c 영향 없음 카드 → 쪽지 0·INFO·이동 완료) · `test_index_move_slack.sh` rc=0 PASS 14 · `test_kit_bin_sync.sh` rc=0 PASS 6 · 사본 cmp + bash -n OK.
- 카드 증거 줄(나노 RESULT 맨 끝 · master 가 카드에 옮김): `세트: 66e26a1edda0e89be171ab291559e78e075185e7 · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp 1파일(ft-index-move.sh) + cmp. 이 카드 자신의 완성 이동은 옛 라이브 바이트로 돌면 쪽지 1건이 더 갈 수 있음(무해).
- 사전검증 DA: 소환 아니오(카드 면제 · arch#16 서명) · 구현 DA 소환: 아니오 — 쪽지 조건 1개 · 게이트 무변경 · arch 재현 일치 — arch 서명 byz-harness-arch-claude#16.
- 정본 영향 없음: 하네스 카드 이동 도구의 쪽지 조건과 시험만.
