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
