# gate-hook-kit-equals-home 최종 DA
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 4ed459ddfc · 고정 Q1~Q3 · 판정343의 홈 정본 동기화 범위.

- Q1 APPROVE — diff에서 제거된 37줄은 LIFECYCLE_RE/in_ft_tmux 정의와 생명주기 deny·FT_WORKER_ROLE/ft-tmux 워커 면제 블록뿐입니다. 고정 키트와 현재 홈 파일을 독립 바이트 대조해 동일을 확인했습니다(sha256 22cca9f5757dba4edbb543795b6049650728312051a4ce01d824e5059e367377). 판정343은 홈을 정본으로 정하고 생명주기 활성화를 보류한 범위입니다(TABLE-gate-hook-copies-20261008.md «오빠 결정»). 홈 내용 추가/변경은 없습니다.
- Q2 APPROVE — spawn의 FT_WORKER_ROLE 전파와 worker-guard의 역할 allowlist는 각각 독립이며 변경되지 않았습니다(ft-tmux-spawn.sh:100-109, templates/hooks/ft-worker-guard.sh:10-11). 키트 hooks/tests의 관련 문자열을 고정 SHA에서 대조했고 ⓪가 현재 켜졌다는 관련 문서는 orchestration.md:39뿐이며 같은 줄에 현재 없음/보류를 명시했습니다. FT_WORKER_ROLE만으로 orchestration-gate를 면제하던 키트 전용 효과는 의도대로 없어지고 홈의 model/agent_id 규칙을 따릅니다; worker-guard 자체의 역할 검사는 유지됩니다.
- Q3 APPROVE — TOP/model normalization·2파일 한도·agent_id/agent_type 면제는 삭제 블록 밖으로 바이트 불변입니다(orchestration-gate.sh:88-113). 독립 JSON 4모델 cases: Sonnet5/Fable 3번째 Edit rc2, Sonnet5.5/agent_id rc0. bash-n rc0, 셔뱅 /bin/bash 유지. 실제 Edit는 수행하지 않고 임시 transcript/카운터만 사용했습니다.

arch의 test10 PASS·install home=same/settings=registered는 보고 증거이며 installer를 독립 실행하지 않았습니다. 홈 훅/settings·프로젝트 사본·tmux/생명주기 명령 실행 0. 이 승인은 고정 커밋의 판정343 동기화에 한정하며 ⓪ 활성화/프로젝트 위임은 승인하지 않습니다.

APPROVE
