# 인덱스: r1341-scope-secret-doc-inline-code-only — 끝: 범위 분류기(autonomy_scope_secret.py doc_cmds)가 문서(.md) 줄을 «백틱이 있다» 는 이유만으로 고를 때 줄 전체가 아니라 백틱 안 글(인라인 코드)만 셸 판정기(ft_secret_judge.plan)에 넘긴다 — 표 «|»·산문 «env …» 낱말을 명령으로 읽어 FORBID kind=secret 내는 오판 0 · 울타리·들여쓰기·«$ »/«! »/«> » 줄은 지금처럼 줄 전체
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8375 (SecondWindStudio/byz-agents · harness#203 발급)
- 이식: 원본 = harness#203 전문 /tmp/mbox/20261111T214547-byz-harness-master-pi#203-to-aifp-ft-master-pi#5-r1341-scope-secret-doc-inline-code-only.md(BYZ origin/main 4ee8346c38 design/harness/indices 에 같은 이름 파일 0) → aifp design/aifp/indices/대기/ · 바꾼 것 = ledger·대상·시험 경로(legacy/1.x 이동 625fbdfc) · 원인 줄 번호 · 반례 S3→S3' · S4·S8 = 회귀 · 완료 조건 · 나머지 원문 그대로 · 1.x 그대로 수정(harness 답 · 전환 표식 0 · 선례 r1699 PR #941) (aifp #3972 · #3974)
- 지시: 판정 3482(planner #230991) · master#153 #231004
- 근거: desk #230969 · 3건 원문 실측(arch#213 · 판정기 plan() 을 추가 줄마다 직접 호출):
  - ops 6076(b0915b4279) design/teams/ops/indices/대기/ops-gpu-vm-stt-tts-two-instances.md 추가 12행 «| ① | (시험 파일 `tests/gateway/unit/test_gpu_vm_control.py` · …) env `GCE_VM_STT_TTS` 1개(기본) → … |» → «env 뒤 명령을 글자로 확정할 수 없음» = ★거짓(표 산문)★
  - chatbot 6054(08ec10b221) 순수 이동 19장(similarity 100%) 중 design/teams/chatbot/indices/아카이브/2026-11/C-fix-gateway-local-worker-health-url.md «- 끝 칸: … ①`settings.worker_health_url`(…) 을 격리 스택 기동 절차에 명시(env `WORKER_HEALTH_URL`) 하거나 …» → 같은 이유 = ★거짓(산문)★
  - 팩 692(f84aad617e) feature-pack/fable-team/harness/tests/scripts/test_stall_scan_judge_cap_r1282.sh «run_scan() { env "${ENV[@]}" ${EXTRA[@]+"${EXTRA[@]}"} bash "$BINDIR/ft-stall-scan.sh" "$@"; }» → 같은 이유 = ★진짜(.sh 셸 줄 · env 뒤 첫 낱말이 배열 펼침)★ — 분류기 규칙대로 · 이 카드 범위 밖(나노가 env 대입을 글자로 쓰거나 env 없이 고침)
- 원인 1줄: feature-pack/fable-team/legacy/1.x/harness/bin/autonomy_scope_secret.py:130(origin/main · 작성 때 live 1.1.255 :128) doc_cmds 가 «"`" in ln» 인 문서 줄을 실행될 수 있는 줄로 보고 :134(작성 때 :135) 에서 줄 전체를 plan() 에 넘김 → 표의 «|» 는 파이프 · «env `X`» 는 env + 명령 치환으로 읽힘 → env 뒤 명령 확정 불가 = FORBID kind=secret
- 끝: 팩 가지 1 · 시험 rc0 · 기준판 FAIL · 변이 FAIL · 착지 · 설치(live bin autonomy_scope_secret.py cmp0) · 실사건 = 설치 뒤 6076·6054 와 같은 꼴 문서 줄이 든 PR 1건 scope-approve SCOPE-OK 원문(또는 두 PR head 를 다시 판정해 FORBID 0 원문)
- 묶음 판정: «규칙 한 줄로 끝나나» = 아니오 — «문서에 env 낱말 쓰지 말 것» 규칙은 13팀 산문 전부에 걸리고, 순수 이동 PR(6054)은 옛 카드 산문이라 고칠 수도 없다 · 읽는 쪽 1곳
- 겹침 대조: r1195(완성 · 코드 확장자 «문자열 리터럴 안» 만 · 같은 생각을 문서 인라인 코드에) · PR 6020 «VAR_DSN=… timeout pytest» FORBID(메모리 · 문서 시험 입력 줄 · 백틱 안 진짜 명령 꼴 → 이 카드 뒤에도 그대로 판정 = 맞음)
- 제안서: 없음 — 판정 1곳 · 되돌림 = revert 1커밋
- 상태: 완성
- 착지: 20b2beff4f8ea48c9e2082fe9a7eb63a3a0d6496(팩 main · PR #947)
- 설치: 있음 — /Users/yoonhwan/.claude/fable-team/live/<LIVE_BIN 최신 sort -V>/bin/autonomy_scope_secret.py ← 팩 harness/bin 판 cmp0(kit 같은 판)
- 선행: 없음(팩 origin/main)
- 시험 입력: 임시 리포(base·head 커밋) · .md 추가 줄 S1~S6 · .sh 추가 줄 1 · 네트워크 0 · 자기 재호출 0 · ulimit -u 2000 + timeout 70 · cwd = /
- 기준값: 오늘 같은 꼴 거절 2건(6076 · 6054) · 우회 = 팀이 «env» 낱말을 «환경변수» 로 바꿔 새 head(ops)·내용 PR 먼저(chatbot)
- 재실측(aifp-ft-arch-pi#0 · 2026-11-11 · origin/main 판 feature-pack/fable-team/legacy/1.x/harness/bin/ft_secret_judge.py --plan 직접 호출 · 쓰기 0): S1 rc=1 · S2 rc=1(«env 뒤 명령을 글자로 확정할 수 없음» · 오탐 살아 있음) · S8 rc=0(기준판도 통과 · 판정기 쪽 변화) · 옛 S3(env FOO="$(cat .env)")·옛 S4(VAR_DSN=…) = 줄 전체·백틱 안 글 둘 다 rc=0 → «지금처럼 FORBID» 성립 안 함 · S3' 줄 전체 rc=1(비밀 조회 치환) · 백틱 안 글 rc=1(env 뒤 명령 확정 불가)
- 규칙: 없음 — 분류기 내부 판정
- 대상: 팩 feature-pack/fable-team/legacy/1.x/harness/bin/autonomy_scope_secret.py(doc_cmds) · feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/autonomy_scope_secret.py(같은 판) · 시험 feature-pack/fable-team/legacy/1.x/harness/tests/test_scope_secret_doc_inline_code_r1341.sh(신설 · 100644)
- 정본 영향 없음: 하네스 범위 분류기 판정 — 제품 정본 0
- 배정: 대기(석 · 2026-11-02T20:21:41)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 1(하네스 착지 — 팀 착지가 문서 산문 때문에 막히지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 실사건.

## 배경 (한 단락)
범위 분류기는 문서(.md) 추가 줄 가운데 «실행될 수 있는 줄» 만 셸 판정기에 넘긴다. 그런데 «백틱이 있다» 는 이유만으로 고른 산문·표 줄도 줄 전체를 넘겨서, 백틱 쌍이 셸 명령 치환으로, 표의 «|» 가 파이프로, 산문의 «env» 낱말이 명령으로 읽힌다. 그래서 코드 0 · 문서만 바꾼 PR(6076 · 6054 · 6792)이 «FORBID kind=secret» 로 막히고 오빠 승인 h 를 한 번 더 탄다. 백틱 안 글만 넘기면 진짜 명령(S3·S4)은 그대로 잡고 산문 오탐은 사라진다.

## 계약
- A1 문서 줄이 울타리 안·들여쓰기(4칸·탭)·«$ »/«! »/«> » 머리로 골라졌으면 = 지금처럼 줄 전체(프롬프트 표시만 뗌)
- A2 그 밖에 «`» 때문에만 골라진 줄 = 짝이 맞는 백틱 구간(`…`·``…``) 글만 한 덩어리씩 plan() 에 넘김 · 구간 밖 산문·«|» 는 넘기지 않음
- A3 짝이 안 맞는 백틱(홀수)이면 = 지금처럼 줄 전체(닫힌 쪽)
- A4 비밀 꼴(SECRET_SHAPE)·셸 확장자·셔뱅·코드 확장자 갈래는 그대로

## 반례 집합
- S1 «| ① | … env `GCE_VM_STT_TTS` 1개 |»(6076 원문) → FORBID 0(기준판 FORBID)
- S2 «… 명시(env `WORKER_HEALTH_URL`) 하거나 …»(6054 원문) → FORBID 0(기준판 FORBID)
- S3' «실행: `env "$X" bash x.sh`» → 회귀: FORBID 유지(백틱 안 진짜 명령 · 기준판·고친 판 둘 다 검출 · 변이 2 에서만 FAIL · 재실측 원문 위 · 기준판 FAIL/고친 판 PASS 로 가르는 사례는 S1·S2)
- S4 «`VAR_DSN=postgres://u:p@h/db timeout 70 pytest`»(PR 6020 꼴) → 회귀: 기준판·고친 판 판정 같음(지금 둘 다 FORBID 0 · 재실측)
- S5 울타리 ```bash 안 «env "$X"» → 지금처럼 FORBID(A1)
- S6 백틱 홀수 줄 «env `X 1개» → 지금처럼 줄 전체 판정(A3)
- S7 .sh 추가 줄 «env "${ENV[@]}" bash x.sh»(692 원문) → 지금처럼 FORBID(문서 아님)
- S8 «1. 코드(1곳 · v65 승인): `act_green_ready_helpers.py` 의 `_LLM_CONCURRENCY_LIMIT` 를 `parse_permits("V6_TRANSLATION_PERMITS", os.getenv(...), 12)` 로 읽는다(…)»(BYZ PR 6792 · design/teams/ccu/indices/대기/ccu-worker-cap-open-measure.md:6 원문) → 회귀: FORBID 0(작성 때 기준판 FORBID · 2026-11-11 재실측 기준판도 rc=0 · 고친 뒤에도 0 이어야 함)
- 변이 1: A2 를 줄 전체로 되돌림 → S1·S2 FAIL · 변이 2: 백틱 구간도 버림 → S3' FAIL · 변이 3: A3 홀수 처리 제거(구간 0 = 넘김 0) → S6 FAIL

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/fable-team/legacy/1.x/harness/bin/autonomy_scope_secret.py doc_cmds(:112~134 · origin/main) — A1~A4 대로 «백틱 때문에만 고른 줄» 은 짝 맞는 백틱 구간 글만 덩어리마다 넘김 · kit 사본 같은 판(cmp0)
2. 시험 신설 feature-pack/fable-team/legacy/1.x/harness/tests/test_scope_secret_doc_inline_code_r1341.sh(100644 · S1~S8 · 변이 3 · 루트 cwd · ulimit -u 2000 · timeout 70) + 회귀 feature-pack/fable-team/legacy/1.x/harness/tests/test_autonomy_scope_code_literals_r1195.sh · test_autonomy_scope_classify.sh(단계별 초)

## 완료 조건
- 나노: S1~S8 rc0 · 기준판(origin/main + 새 시험) S1·S2 FAIL(S3'·S4·S8 = 회귀라 기준판도 PASS) · 변이 1(A2 뺌 = 줄 전체) → S1·S2 FAIL · 변이 2(백틱 구간 버림) → S3' FAIL · 변이 3(A3 홀수 백틱도 구간만) → S6 FAIL · bin·kit cmp0 · 시험 100644
- master: 착지 → 설치 cmp0 → 실사건(6792 head f67a12683d 다시 분류 → FORBID 0 원문) → 완성

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| A1 울타리·들여쓰기·프롬프트 줄 = 줄 전체 | S5 |
| A2 백틱 때문에만 고른 줄 = 백틱 안 글만 | S1 · S2 · S3' · S4 · S8 · 변이 1 · 변이 2 |
| A3 홀수 백틱 = 줄 전체 | S6 · 변이 3 |
| A4 다른 갈래 그대로 | S7 |

## 범위 밖
- 순수 이동(similarity 100%) PR 이 옮긴 파일 전문을 다시 판정하는 것(:44 --no-renames · 이동 PR 이 옛 카드 산문에 걸림 · 이 카드로 S2 꼴은 풀리지만 이동 PR 판정 자체는 그대로 · 후속 후보)
- 692 셸 줄(진짜 · 나노 몫)

## 상태
- 2026-11-02T19:3x 대기 — arch#213 작성(판정 3482 · master#153 #231004 · 3건 원문 plan() 직접 호출 실측) · 다음 = master Issue · 사전 DA 면제 후보(문서 갈래 1곳 · 셸·코드 갈래 무변경)
- 2026-11-03T22:5x 대기 — arch#219 반례 S8 보탬(master#157 #246030 · planner #246021 · BYZ PR 6792 문서 2·코드 0 FORBID secret) · 판정: 722(r1195 단계 2 · 파이썬 셔뱅)와 «다른 칸» — 6792 는 문서 백틱 갈래(이 카드 A2) · 고치면 S8 통과 · *.md 를 secret 검사에서 통째로 빼지는 않음(울타리·«$ » 줄의 진짜 명령은 S3~S5 처럼 잡아야 함)
- 2026-11-11T21:4x 대기 — aifp 사본(aifp-ft-arch-pi#0 · master #3972 · 실측 #3971): 경로 legacy/1.x · 원인 줄 :130·:134 · S3' · S4·S8 회귀 · 완료 조건 S1·S2 FAIL · Issue #8375
- 2026-11-11 19:47 — DA 최종 HOLD 2 보정(R1 백틱 길이 짝 · R2 판정기 출력 꼴) · 세트: e31c43ca043e827b5baf649f778fd74b5e171816 · 시험: bash tests/test_scope_secret_doc_inline_code_r1341.sh (27 passed — S9 이중 백틱 구간 · 변이 4/4) rc=0 3초 · bash tests/test_secret_scan_judge_timeout_r1341.sh (16 passed — J7 rc0 출력 꼴 · J8 reject 문법 · 변이 5/5) rc=0 30초 · 회귀 r1195 16P0F 2초 · classify 74P6F 8초(앞 판 FAIL 줄 동일) · secret_scan 16P0F 1초
- 2026-11-11 19:34 — arch 인수 보류 1 보정(기준판 sha 고정) · 세트: a3ae114e338970014c8fccc578eda81b9213fa14 · 시험: bash tests/test_scope_secret_doc_inline_code_r1341.sh (24 passed — 기준판 = 251b1f00 판 고정 · 커밋 뒤에도 S1·S2 기준판 FORBID 재현) rc=0 3초 · 바꾼 것 = `git show HEAD:` → `git show 251b1f00:` 1줄
- 2026-11-11 19:25 — 나노 구현 완료(단계1·2) · 세트: 4edf133ef0ddf9ecd62428e7a64c4aba1fbc199c · 시험: bash tests/test_scope_secret_doc_inline_code_r1341.sh (24 passed · 기준판 S1·S2 FORBID 재현 · 변이 3/3) rc=0 · bash tests/test_secret_scan_judge_timeout_r1341.sh (12 passed · J1~J6 · 변이 3/3) rc=0 · 회귀 test_autonomy_scope_code_literals_r1195 16P0F 2초 · test_autonomy_scope_classify 74P6F 11초(앞 판 FAIL 줄 동일) · test_secret_scan 16P0F 1초 · 단계별 초 = 단계1 3초 · 단계2 29초(J1 14 · J5 8) · 이슈: #8375
- 2026-11-11T22:0x 대기 — DA HOLD R1 보정(aifp 3978 · master #3979): 단계 2 설계 1 = rc1+reject 정상 검출 유지 · rc2·시간 초과·출력 꼴 어긋남만 판정 불가 · J6(정상 검출 회귀)·변이 3 추가 · S3' = 회귀 문구

## 단계 2 — 비밀 스캔이 판정기 1건 시간 초과로 회차 전체가 죽음 (판단만 · 자율정지 중 착수 0 · arch#223 · 2026-11-04 06:5x · master#159 #251262 · launchd-check [급] #251259 · 새 카드 동결 3614 → 같은 판정기(ft_secret_judge.plan) 계열 대기 카드에 합침)
- 합침 자리: 열린 secret 카드 중 ft-secret-scan.sh 를 대상으로 둔 카드 0(r135b 완성) · r1195 는 완성 상태 줄 · 이 카드 r1341 = 같은 판정기(ft_secret_judge.plan)를 부르는 쪽 고침 → 단계 2 로 붙임(파일은 다름 · 나노 1석 같은 팩 가지)
- 실측(읽기만): /tmp/ft-secret-scan.log 끝 = Traceback … subprocess.TimeoutExpired: Command '[… /Users/yoonhwan/.claude/fable-team/live/1.1.255/bin/ft_secret_judge.py, --plan, /tmp/h355]' timed out after 7 · 같은 줄 2번(runs 2 · com.byz.ft-secret-scan rc1) · 호출 자리 live /Users/yoonhwan/.claude/fable-team/live/1.1.255/bin/ft-secret-scan.sh:75 `subprocess.run([... "--plan", p], capture_output=True, text=True, timeout=7)` — try 0 · r.returncode 확인 0 · 상태 저장(json.dump · :101 근처)은 반복 «뒤» 라 예외면 그 회차 상태 저장 0
- 원인 1줄: 계획 파일 1개의 판정 시간 초과가 잡히지 않아 스캔 회차 전체가 rc1 로 죽고 상태도 안 남아 다음 회차가 같은 자리에서 또 죽는다(그 뒤 파일들의 비밀은 보고 0) · 판정기가 rc=2(내부 오류)로 끝나도 reject 줄이 없어 «found 0» 으로 셈 = 조용한 통과 → 하드 룰 20 · BYZ #0 RULE 위반 꼴
- 설계:
  1. :75 호출을 한 함수 judge_plan(p) 로 감싼다 — 판정기 rc 계약(ft_secret_judge.py:3~5 · 0 ok / 1 reject / 2 내부 오류)대로 가른다: rc0 + «ok» = 깨끗 · rc1 + «reject » 줄 1개 이상 = ★정상 검출(지금처럼 found 수집 · sig 저장)★ · TimeoutExpired = «판정 불가 <p> 판정기 7초» 1줄 · rc2 = «판정 불가 <p> 판정기 rc=2» 1줄 · 그 밖 꼴(rc1 인데 reject 줄 0 · rc0 인데 reject 줄 · 다른 rc) = «판정 불가 <p> 판정기 출력 꼴» 1줄(닫힌 쪽) · 판정 불가는 그 파일만 세고(셈 judge_unknown=N) 반복은 계속 (DA HOLD R1 · aifp 3978)
  2. 판정 불가 파일은 상태(files)에 «안 읽음» 으로 둔다(sig 저장 0) — 다음 회차에 다시 판정 · 같은 파일이 3회차 연속 판정 불가면 [긴급] 1통(그 파일 경로 · 마지막 사유) · 조용한 영구 건너뜀 0
  3. 회차 rc: judge_unknown>0 이면 rc=3(판정 불가 · 0 과 구분) · 끝 줄 SCAN 에 judge_unknown 칸 · 그 밖 rc 뜻 그대로
  4. 재시도 1(하드 룰 12 · rc 124/TimeoutExpired 일 때만) · 판정기 호출 시간 상한은 7초 그대로
  5. 그대로 두는 것: 로그 파일 mask 판정 · 계획 판정 줄 꼴(reject …) · 쪽지 경로(_hil_route)
- 반례(단계 2):
  - J1 계획 3개 중 2번째 판정기 대역이 8초 → 1·3번 판정됨 · 2번 «판정 불가 … 7초» 1줄 · judge_unknown=1 · rc=3 · 상태에 1·3번만 sig
  - J2 판정기 대역 rc=2 + stdout 빈 → «판정 불가 … rc=2» · found 0 으로 세지 않음
  - J3 같은 파일 3회차 연속 J1 → 3회차에 [긴급] 1통(가짜 mbox 대역 · 받는이 = _hil_route)
  - J4 모두 정상 → 지금 끝 줄 그대로 · judge_unknown=0 · rc0
  - J5 재시도에서 통과(첫 호출 8초 · 둘째 1초) → 판정됨 · judge_unknown=0
  - J6 정상 검출 회귀: 판정기 대역(또는 실제 판정기 + 계획 파일 «env "$X" bash x.sh») rc1 + «reject 1 …» → found 1 · 쪽지 경로 그대로 · judge_unknown=0 · sig 저장(기준판·고친 판 둘 다 PASS)
  - 변이 1: try 제거 → J1 FAIL(traceback) · 변이 2: rc 확인 제거 → J2 FAIL · 변이 3: rc1 도 판정 불가로 셈 → J6 FAIL
- 시험 입력: 임시 SCAN_* env(로그 0 · 계획 파일 3) · ft_secret_judge 대역(SCAN_HERE 를 임시 폴더로 · 대역 안 sleep 만) · 가짜 mbox · 실 /tmp/h* 0 · 자기 재호출 0 · ulimit -u + timeout 70
- 대상(보탬): 팩 feature-pack/fable-team/legacy/1.x/harness/bin/ft-secret-scan.sh · feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-secret-scan.sh(같은 판) · 시험 feature-pack/fable-team/legacy/1.x/harness/tests/test_secret_scan_judge_timeout_r1341.sh(신설 · 100644) · 회귀 feature-pack/fable-team/legacy/1.x/harness/tests/test_secret_scan.sh
- 재실측(2026-11-11 · origin/main): feature-pack/fable-team/legacy/1.x/harness/bin/ft-secret-scan.sh:75 subprocess.run(… timeout=7) try 0 · TimeoutExpired 잡지 않음 · r.returncode 확인 0 · :81 files[p]=sig 를 판정 실패에도 저장 → 결함 그대로
- 남는 질문(이 단계 밖): /tmp/h355(자율 범위 승인 계획 진입 파일) 판정이 왜 7초를 넘는지 — 부하 탓인지 판정기 탓인지 확인 0(그 파일은 자율 상태 훅이 좌석 읽기를 막음) · 덧: launchd-check «죽음» 문구 = r1186(master 합침)
