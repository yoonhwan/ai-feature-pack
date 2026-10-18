# R58 구현 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 5623d4d5f6 · 고정 Q1~Q3 · 게이트 완화 구현 검토.

- Q1 HOLD — arch 후보를 독립 재현했습니다. 격리 DAG A(main)→F(feat)→N(nano)에서 info base=main/base_sha=A로 오기하면 base ref 실재·A⊂HEAD만 확인해 나노를 ⊘ 제외합니다(ft-press-gate.sh:_other_trunk, 신규 행 142의 조건). 실제 A는 feat의 조상이므로 미랜딩 N이 셈에서 빠져서는 안 됩니다. helper 실행 rc0/⊘를 확인했으며 전체 게이트·허가 파일 생성은 실행하지 않았습니다. base_sha⊂FEAT이면 기존 셈으로 돌아가는 보강과 옛 main 조상·짧은 ref/동일 commit alias·오기 fixture가 필요합니다. info 작성자가 하나라는 사실은 이후 수정/오기와 git 계보를 보증하지 않습니다.
- Q2 APPROVE — info 없음/JSON·필드·python 실패는 return1이며 ref/HEAD 조상 검증 실패도 return1로 기존 셈을 유지합니다(ft-press-gate.sh:134-146). rebase로 base_sha가 조상이 아니면 제외되지 않습니다. 단 git 검증 두 개가 성공하면서 선언만 틀린 경우는 Q1 반례이므로 fail-closed 수락과 분리합니다.
- Q3 APPROVE(변경 범위 확인) — diff는 helper 및 ① 루프의 continue 한 줄뿐으로 ②~⑧/FAIL 코드 변경이 없습니다(ft-press-gate.sh:149). 다른 줄기 판정이 옳다면 셈/세트 표시를 함께 생략하는 것은 표시만 계약과 충돌하지 않습니다; 오분류는 Q1에서 닫아야 합니다. 기존 6+신규6 통과·키트/ruff는 arch 보고이며 이번 검토에서 전체 게이트 시험을 독립 재실행하지 않았습니다.

반송 원인 1개: 선언 base의 ref 실재와 HEAD 조상만으로 FEAT 대상 제외를 승인함. 수정은 같은 나노, 실제 press 게이트/허가 발급·랜딩·설치는 master 책임입니다. 격리 git helper 검증만 수행(실 repo·tmux·press·허가 파일 0).

HOLD

## r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q1r2 HOLD — 대상 f475c7f910. base_sha⊂FEAT 및 조회실패 시 기존 셈으로 돌아가는 교정과 ⓖⓗⓘ는 수락하며 격리 helper에서 옛 main/짧은 SHA/없는 FEAT 모두 rc1을 독립 확인했습니다. 그러나 base ref 실재와 base_sha의 관계를 검사하지 않아 같은 Q1 오기 경로가 남습니다(ft-press-gate.sh:142-145).
독립 반례: 격리 DAG A(main)→F(feat)→N(nano)의 info를 `{base:'main',base_sha:N}`으로 오기 → main ref 실재·N⊂HEAD·N⊄FEAT(rc1) 모두 통과하고 helper는 rc0/⊘ 제외입니다. N은 main의 조상이 아니며 자기 미랜딩 커밋이므로 FEAT 나노를 제외하면 안 됩니다. base_sha가 선언 base의 실제 계보에 속하는지까지 검증하는 최소 보강과 «main ref=A, base_sha=자기 N» 회귀 시험이 필요합니다. 선언 파일 작성 주체 하나는 이 관계의 보증이 아닙니다.
Q2·Q3 재심 없음(기존 수락 유지). 전체 게이트/허가 파일 생성·실 repo·tmux·press 실행 0; 수행한 것은 기존 격리 git helper의 4 probes입니다.

두 번째 HOLD이므로 연속 DA 리뷰를 종료하고 master에 통합 이관합니다. 수락 교정: 옛 main/짧은 alias/FEAT 조회 실패. 통합 잔여: 선언 ref와 base_sha 계보의 결합 증거 부재.

HOLD
