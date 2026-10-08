# bd-judge-split-200 최종 DA
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 7e8b08cb7e · 기준 4f5009a926 · 고정 Q1~Q3 · 판정 규칙 재심 없음.

- Q1 APPROVE — 이전 heredoc Python 본문과 새 .py의 머리 주석 두 줄 제외 본문을 독립 대조해 동일을 확인했습니다. 본문은 argv1/argv2를 사용하며 stdin/__file__/argv0를 판정에 쓰지 않고 cwd는 기존 그대로입니다(block-destructive-judge.py:116-123). 임시 전/후 훅의 JSON 7종 종료코드가 동일했습니다(글 인용·실제 명령 표기·Redis 표기·STAGE·일반문장·쓰기 heredoc·bash-c; 명령 자체 실행 0).
- Q2 APPROVE — 판정기는 BASH_SOURCE 훅 파일의 같은 디렉터리 경로를 쓰며 python3 실패면 EFFECTIVE=CMD로 돌아갑니다(block-destructive.sh:25-27). 실제 등록의 절대 홈 경로·키트 경로는 해당 짝 파일을 선택하며 임시 다른 폴더 훅에 판정기 없이 인용 문자열 JSON을 넣어 rc2를 독립 확인했습니다. symlink 설치는 명시된 범위 밖이며 다른 폴더의 helper 탐색 fallback은 없습니다.
- Q3 APPROVE(검사·보고 범위) — install.sh는 .sh/.py를 모두 home same/diff/absent 집계하며 .py settings=n/a는 등록 수에 더하지 않습니다(install.sh:62-73). test_install_hook_check는 helper 템플릿 존재 및 홈 파일이 있으면 cmp를 확인합니다(:63-70). 홈 helper 없음은 SKIP이고 installer는 absent로 보이므로 이 시험만으로 설치 완료를 선언할 수 없습니다; 기존 홈이 분리 전인 현재 rc1/absent는 master의 두 파일 동시 설치 후 재확인 잔여로 유지합니다. [[ name == *.py ]]는 bash3.2 지원 구문입니다.

독립 검증: 판정기 본문 동일·JSON 전후7종 동치·helper 없음 fail-closed·bash-n. arch 전체74/23·22/32·mutant15 결과는 보고 증거로 구분합니다. 임시 사본만 만들었고 홈/settings·실제 파괴/Redis/DOM/게시 명령 실행 0. 최종 DA 승인은 분리 구현에 한정하며 홈 두 파일 cmp와 설치 후 회귀는 master 집행 조건입니다.

APPROVE
