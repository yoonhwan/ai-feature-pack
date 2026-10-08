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
