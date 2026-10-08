# DA — 슬랙 읽기 전용 공유판 + 결정 자리 현역 세션 안내 (사전검증 · r1)

- 요청: byz-harness-arch-claude#16 · 2026-10-08 · 발주 master#17 #64368(오빠 발주 · 최우선)
- 설계: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/DESIGN-slack-readonly-share-20261008.md`
- 코드(정본): `git -C /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops show origin/main:scripts/harness-install/slack-mirror/<파일>` (라이브 `~/.hermes/scripts/` 와 cmp 같음)
- 범위 고정: 설계 §7 Q1~Q4 만. 10분 + 10분 · HOLD 2회면 종료.
- ★판정은 이 파일 맨 아래 「## r1 판정」 절에 쓴다★(relay 사본 /tmp/mbox/… 금지).

## r1 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

설계 §7 Q1~Q4 사전 검토 · 구현/시험 실행/슬랙 발송/라이브 설치 0.

- Q1 HOLD — 프롬프트 변경만으로 «답장 요구 0»을 보장하지 못합니다. LLM what/todo와 요약 실패 first_sentence 및 첨부 전문은 원문 문구를 그대로 출력할 수 있습니다(mirror_summary.py:43-55, mirror_lib.py:184, :192, :143-148). 매거진 실패의 deterministic_lines에도 «오빠 할 일(답이 안 간 요청)»이 남는데 설계 §2/§5 수정 목록에 이 함수의 교정이 명시되지 않았습니다(magazine_summary.py:63-68). 최종 표시 경계에서 자유 문장 검증+결정적 상태 문구 fallback을 명시하고, 전문 인용을 원문 참고로 보존할지 화면 규칙에서 예외로 둘지 확정하십시오. 요약 성공/위반/실패·원문/전문 경로 시험이 필요합니다.
- Q2 HOLD — `_master` 확인 및 조용한 대체 금지는 수락합니다. 그러나 planner 없음에서 저장·재시도 상태 전이가 없습니다(설계:54). 기존 plan은 수신자를 최초 한 번 저장하고 열린 질문 좌석/추정 좌석에도 전달하므로 planner_seat 함수 교체만으로 planner 단일 경로가 되지 않습니다(mirror_plan.py:33, :39-41). 또한 recips=[]이면 all(empty)가 true라 finished로 끝납니다(byz_slack_mbox_inbound.py:104-113). 원문/Slack ts를 durable pending으로 먼저 저장, planner 없음이면 unfinished 유지·알림 중복 억제, 복구/승계 뒤 미전달 건의 현역 재조회 및 기존 전달 marker 중복 방지까지 정하십시오(:125-135). 명부 누락/JSON 오류/tmux 실행 실패도 확인 불가로 구분하고 원문 유실 0 시험을 추가하십시오.
- Q3 HOLD — §4:50 매핑에 종류 6 inbound 안내가 빠졌고, «첫 줄 4종 중 하나»와 종류 2 루트 무표기 예외가 충돌합니다. 종류 7의 재첨부는 별도 magazine_reattach.reply_text에서 첫 줄을 만들어 §5 수정 파일/시험 목록으로 덮이지 않습니다(magazine_reattach.py:19-25). 실제 9종+실패/경고/재첨부의 머리표 행렬 또는 의도한 예외를 명시하고 첫 줄 표식에 의존하는 재발행 중복 방지와 함께 시험하십시오.
- Q4 APPROVE — 공용 planner 조회·표시 규칙은 하나의 계약이므로 한 단위에서 맞추는 것이 적정합니다. 파일 수만으로 분리할 필요는 없습니다. 단 §5 파일 목록에 inbound durable pending/수신자 결정 및 재첨부 생성 위치를 포함해 Q1~Q3의 동일 계약을 완결해야 합니다. 설치·launchd 재기동은 현재처럼 master 단계로 유지하십시오.

교정 범위: 출력의 성공/실패 경계, 현역 없음·승계 시 원문 보존과 재시도, 종류별 머리표 누락. 질문 저장소 폐기·inbound 끄기 여부는 재심하지 않았습니다.

HOLD

## r2 요청 (arch#16)
설계 §4-r2(A 표시 경계 검사 · B inbound 역할 수신자·유실 0 · C 머리표 행렬+중복 방지 호환 · D 파일 추가)로 r1 Q1·Q2·Q3 교정. 같은 Q1~Q4 범위로 아래 r2 판정 절에.

## r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q1 HOLD — §4-r2 A의 REPLY_ASK에는 §2/§5가 없애기로 한 `확인해 주세요` 및 표시용 `Q숫자` 검사가 없습니다. 가짜 요약 `{"what":"전문을 확인해 주세요", "todo":null}`은 명시된 guard를 그대로 통과합니다; 원문 first_sentence도 같습니다(mirror_lib.py:184, 설계 §5 시험①). 합의된 13문구/표시 규칙의 검사를 최종 출력 경계에 완결하고 이 성공·실패 반례를 시험하십시오. 전문 원문 보존의 명시 예외와 매거진 deterministic fallback 교정은 수락합니다.
- Q2 HOLD — 새 plan의 @planner 역할 수신자·매 패스 현역 조회·unfinished/알림/토큰 계약은 수락합니다. 그러나 기존 ledger의 미완료 recips에는 이미 옛 planner 이름이 저장되어 있고, run_pass는 그 항목에 plan을 다시 호출하지 않습니다(byz_slack_mbox_inbound.py:125-126, mirror_plan.py:14-17). §4-r2 B는 신규 plan만 바꿔 기존 미전달 건의 현역 승계를 보장하지 못합니다. 기존 ledger의 planner 역할 판별/이관 규칙(질문 좌석과 혼동 금지), 원래 attempt/수신자별 marker 기록 보존, 이미 전달한 건의 재발송 0을 명시하고 «옛 이름 pending 원장→새 현역»·«옛 이름 첫 시도 뒤 crash→현역 승계» fixture를 추가하십시오.
- Q3 APPROVE — §4-r2 C가 루트·inbound·재첨부/실패를 포함한 행렬로 누락을 닫고, 옛/새 첫 줄을 머리표 제거 후 비교하는 중복 방지 호환 시험을 명시했습니다. 본문 경고 줄은 첫 줄 분류의 예외가 아니라 본문임을 수락합니다.
- Q4 APPROVE — r1 수락 유지. D의 inbound/재첨부/첫 줄 비교 파일 추가로 동일 단위 계약 범위를 보완했습니다. 설치/launchd 재기동은 master 단계입니다.

두 번째 HOLD이므로 연속 DA 리뷰를 종료하고 위 두 잔여를 master 통합으로 이관합니다. 구현·시험 실행·슬랙 발송·라이브 설치 0.

HOLD

## r3 스팟 요청 (arch#17 · 판정 497 · 판정 468 선례 · 1회)
- 범위 고정: r2 잔여 2건만 — 설계 `### A-r3`(Q1 잔여: `REPLY_ASK` 에 `확인해\s*주` + 질문 번호 `(?<![A-Za-z0-9])Q\d+(?!\d)` · 반례 시험) · `### B-r3`(Q2 잔여: 기존 원장 미완료 recips 의 `byz-planner-` 접두 이름 → `@planner` 이관 · done/attempt 이관 · 옛·새 토큰 둘 다 marker 검사 · fixture 4). Q3·Q4 APPROVE 재심 0.
- 10분. HOLD 면 여기서 종료하고 planner#12 로 올린다(재요청 0).
- 판정은 아래 「## r3 판정」 절에 쓴다(모델·provider 두 줄 포함).

## r3 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

판정 497의 예외 1회 스팟 승인을 공통 원장 #64452(planner)·#64454/#64456(master)에서 확인했습니다. 범위는 A-r3/B-r3의 지정 잔여만이며 Q3·Q4 및 판정 496 범위는 재심하지 않았습니다.

APPROVE — A-r3의 확인 요청·Q번호 정규식과 성공/실패 반례 시험이 r2 Q1의 누락을 닫습니다. B-r3는 미완료 재개 전에 기존 planner 접두 수신자를 @planner로 이관하고 done/attempt·옛 이름 목록·구/신 marker를 보존해 r2 Q2의 기존 pending 승계 공백을 닫습니다. 미전달·marker 있음/없음 crash·다른 팀 질문 좌석 보존의 네 fixture가 지정됐습니다.
사전 설계 승인입니다. 구현의 이관 멱등성과 marker 중복 방지는 위 fixture 실행으로 확인해야 합니다. 이번 검토에서 구현/시험 실행·슬랙 발송·라이브 설치는 수행하지 않았습니다.

APPROVE

## 판정 496 r1 요청 (arch#17 · 같은 단위 · 새 범위 — 슬랙 공유판 Q1~Q4 재심 0)
- 설계: 같은 폴더 `DESIGN-slack-readonly-share-20261008.md` `## §8` 만(8-1 실측 · 8-2 안 · 8-3 ⑥ 관계 · 8-4 단위 · 8-5 Q5~Q8).
- 함께 볼 것: `design/harness/indices/대기/v421-board.md`(델타의 바탕 · N3 APPROVE 범위는 재심 0) · `scripts/fable-team-bin/ft-news-tree.py`·`ft-news-tick.sh:47-49`(⑥ 지금).
- 범위 고정 Q5~Q8 · 10분 + 10분 · HOLD 2회면 종료(bounded_da_review).
- 판정은 아래 「## 판정 496 r1 판정」 절에(모델·provider 두 줄).

## 판정 496 r1 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

범위: 설계 §8 Q5~Q8만. 슬랙 공유판 Q1~Q4/N3 수락분 재심·구현·시험·발송 0.

- Q5 HOLD — NEWS-TREE를 구조/축 이름만 읽고 상태를 카드 폴더로 결정하는 방향은 손 상태 금지와 일치합니다. 다만 `[idx:]` 없는 제목과 «손 상태 글자 있었음» 경보만으로는 트리에 아예 없는 카드를 발견하지 못합니다. §8-2의 5팀 트리 작성 지시도 진행·대기만 연결하며 완성 카드 대조가 없습니다. 카드 폴더의 전체 고유 카드 집합과 트리 idx 집합을 대조해 미연결 완성/진행/대기 카드를 표시(축 미지정 묶음 또는 누락 수+목록)하고 중복 idx 집계를 방지하는 규칙·시험을 추가하십시오. 미지정 팀 표시 자체는 수락합니다.
- Q6 HOLD — 접기 형식 «완성 n + 마지막 1장»과 --full 펼침은 기본 요약에 적정하지만, §8-2대로면 n의 분모가 연결된 카드뿐이어서 ✅ 소실 0을 증명하지 못합니다. 반례: 완성 폴더 A·B, 트리 idx A만 → 완성 1·full에서도 B 소실. Q5의 전체 카드 대조를 동일 dict에 담아 기본/full 모두 미연결 B를 보이고, 동일 카드 중복 링크는 n에 한 번만 세는 시험을 요구합니다. «마지막» 선정 기준도 기존 오늘 완성과 축별 전체 완성을 혼동하지 않게 명시하십시오.
- Q7 APPROVE — §8-2의 open ∧ oppa_todo count를 기존 fold 출력에서 가져오고 결정 자리를 동일 planner 명부/tmux 생존 규칙으로 표시하는 계약은 답장 요구 0과 충돌하지 않습니다. pane/slack은 수집된 동일 dict의 planner 확인 결과와 수를 렌더해야 하며 각 렌더에서 재조회/재계산하지 않는 구현으로 검증하십시오. 최종 문구 검사는 기존 §4-r2/r3 계약을 재사용하는 범위입니다.
- Q8 APPROVE — 아직 미착수인 v421에 동일 collect dict의 요약/트리 칸을 더하는 한 단위가 적정합니다. 파서·요약 모듈 분리는 허용된 파일 크기 경계 안에서 수행하고 v423 발행·호출부 전환은 별 단위로 유지하십시오. 명부 _tree 설정/각 팀 트리 준비는 배포의 구체적 잔여이며 도구 설계 승인과 실환경 전체 팀 커버리지 완료를 구분해야 합니다.

통합 반송 원인 1개: 카드 폴더→트리 연결의 전체성/중복 집계 계약 부재. 구현 착수 전에 미연결 카드 보존과 기본/full 시험으로 보완하십시오.

HOLD

## 판정 496 r2 요청 (arch#17)
설계 `### 8-2-r2`(A 전체 대조·불변식 · B 접기/«최근» 기준 · C 한 번 수집 · D 배포 잔여 · 시험 ①~⑥)로 r1 Q5·Q6 교정, Q7·Q8 조건 반영. 같은 Q5~Q8 범위로 아래 r2 판정 절에. (r2 HOLD 면 bounded 종료 → planner#12 로)

## 판정 496 r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q5 APPROVE — §8-2-r2 A가 카드 폴더 전체를 분모로 삼고 C−T를 합성 미연결 축에 보존하며, 중복 idx는 첫 배치에서만 계수합니다. 미지정 트리/폴더 중복도 숨기지 않는 규칙과 불변식 시험으로 r1의 전체성 공백을 닫습니다.
- Q6 APPROVE — B의 누적 완성 접기·최근 mtime/동률 기준·오늘 완성 구분과 기본/full A·B 보존 시험이 r1 반례를 닫습니다. 미연결 축도 full에서는 전부 펼칩니다.
- Q7 APPROVE — C의 collect 1회 및 렌더 재조회 0 계약·호출 수 시험이 기존 수락 조건을 반영했습니다.
- Q8 APPROVE — D가 도구 시험 완료와 master의 명부/트리 배포 잔여를 구분하고 잔여 팀도 미연결 축에 보존합니다. 단일 구현 단위 및 발행 별 단위 수락 유지.

사전 설계 승인입니다. 지정된 불변식/기본·full/중복/수집 1회 시험은 구현에서 실행해야 합니다. 이전 슬랙 공유판 범위·N3 재심, 구현·시험 실행·발송·라이브 변경 0.

APPROVE

## 구현 재확인 요청 (arch#17 · 카드 slack-readonly-share 완료 조건 「구현 DA 가 재확인」 · 1회 · 10분)
- 세트: `nano/slack-readonly-share` 커밋 `dc4ad4176b`(feature) · `015dba85f5`(structure) · RESULT `git -C /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-slack-readonly-share show 248e6775cf:design/harness/RESULT-slack-readonly-share-20261008.md` 「## 설계와 다르게 한 곳」 1~5 · 「B-r3 fixture 4 (+1)」.
- arch 재현(arch#17): `git archive dc4ad4176b scripts tests/harness tools/comm-canonical` → 시험 8종 rc=0(새 시험 ALL PASS · 기존 7종 PASS) · ruff 0 · 최대 195줄 · share_guard 반례 `Q3`·`Q3에 대해`·`(질문Q12)` 교정 / `FAQ3`·`Q`·평문 통과.
- 질문 하나만: 편차 1~5 가 설계 §4-r2(A·B·C·A-r3·B-r3) 승인 범위 안인가 — 특히 ②GitHub plain 경로 검사 제외 ③명부 «경로» 유도 + `install-github.sh` BYZ_ROOT 필수(없으면 exit 1) ⑤옛 원장 `ask` 미게시(전달은 유지 — `byz_slack_mbox_inbound.py` diff 에서 ask 게시 3줄만 삭제). 범위 밖 재심 0.
- 판정은 아래 「## 구현 재확인 판정」 절에.

## 구현 재확인 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

APPROVE — 고정 커밋 dc4ad4176b 및 RESULT 248e6775cf의 편차 1~5만 확인했습니다. 전체 구현 DA/판정 496 재심은 포함하지 않습니다.

1. 교정 표시를 메시지당 첫 줄에 한 번 두는 것은 교정 사실 표시·조용한 교정 0 계약 안입니다(mirror_lib.py:191).
2. GitHub plain 실패 경로는 고정 사건 문구+원문 제목이며 설계 A의 제목 사실 예외 안입니다; 요약 성공은 share_lines 검사를 유지합니다(byz_github_slack_mirror.py:50-61, mirror_lib.py:187-188). plain은 그 GitHub 경로에만 쓰는 전제입니다.
3. 명부 경로만 입력 위치에서 유도하고 이름은 매번 _master/tmux로 확인하는 것은 하드코딩 0 계약 안입니다(mirror_share.py:67-91). install-github.sh의 BYZ_ROOT 또는 MIRROR_PLANNER_SEATS 필수·없으면 설치 전에 exit 1은 조용한 기본값 금지에 맞습니다(install-github.sh:15-16). installer 복사 목록 보강은 새 모듈의 설치에 필요한 범위이며 실제 설치 승인/집행과 구분합니다.
4. 질문 좌석이 현역 planner와 같은 경우 역할의 done을 같은 수신자로 표시해 중복 발송을 피하는 것은 기존 planner!=seat 의미를 보존합니다(byz_slack_mbox_inbound.py:92-94). 최종 finished는 모든 실제 수신자 done을 요구합니다(:115).
5. 옛 ask 게시만 제거하고 recips/text 전달은 유지한 변경은 슬랙 되묻기 0 및 원문 전달 유지 계약 안입니다(같은 파일 _deliver:82 이후; diff의 ask 게시 블록 삭제).

arch 재현 8종 PASS·ruff 0은 보고 증거이며 이번 한정 재확인에서는 독립 시험/슬랙 발송/라이브 설치를 수행하지 않았습니다.

APPROVE
