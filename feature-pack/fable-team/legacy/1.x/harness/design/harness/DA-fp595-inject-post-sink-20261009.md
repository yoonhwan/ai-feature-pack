# fp595 INJECT 게시 싱크 구현 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 e5588bb096 · 고정 Q1~Q4 · 홈 설치 제외.

- Q1 HOLD — F1은 토큰에 파일 basename이 보일 때만 다른 소비로 보고 `$RUNFILE`이나 다른 basename의 기존 심링크를 놓칩니다(block-destructive-judge.py:133-135, :157-161). JSON 반례: 따옴표 heredoc으로 /tmp/body595.txt에 Redis SET 본문을 쓰고 gh --body-file로 게시한 뒤 `bash "$RUNFILE"`(환경값이 F) 또는 `bash /tmp/other595.sh`(기존 심링크가 F)를 호출하면 rc0; 같은 F를 직접 실행하면 rc2입니다. 이것은 동일 명령에서 생성된 본문의 실행 소비이며 요청의 $VAR/심링크 경계입니다. 본문 파일과의 관계를 증명하지 못하는 실행 소비가 있으면 게시 본문 제거를 허용하지 않는 보수적 경계와 fixture가 필요합니다.
- Q2 선별 오탐 확인 APPROVE — F1 게시파일 전용 및 F2 gh 본문 heredoc의 금지 문자열은 독립 JSON rc0이고 직접 파일 실행은 rc2입니다. arch F7/전체 두 시험은 보고 증거로 구분합니다. 일상 게시 형태 전체·실사례 원문 독립 전수는 이번 검증이 아닙니다.
- Q3 APPROVE — 기본 judge 출력의 echo/일반문장/글자 그대로 --inject 세 입력을 이전 판과 비교해 stdout·rc 동치를 확인했습니다. 새 모드 분기는 인자4개+--inject일 때만이고 나머지 기본 호출은 그대로입니다(:162-176). Python 프로세스 실패의 셸 || INJ_SRC=EFFECTIVE fallback도 유지됩니다; 모드 내부 판정 불가는 명령 원문으로 더 엄격하게 복귀합니다.
- Q4 코드 확인 APPROVE — diff에서 PATTERN/STAGE 및 기본 judge 본문 변경은 없고 추가 shell 호출은 기존 Python 인자 전달 방식입니다. 새 bash3.2 불가 구문은 확인하지 못했습니다. 전체 회귀 rc0은 arch 증거이며 독립 전수 재실행하지 않았습니다.

X7 판정: `redis-cli $(cat <<'EOF'\nSET k v\nEOF\n)`는 독립 JSON rc0이고 기존 빈틈이라는 구분은 수락합니다. 다만 실제 명령줄에서 제품 상태를 생성하는 경로라 전역 INJECT가 임의 쓰기를 막는다는 수락 주장에는 설치 전 열린 blocker입니다. 현재 커밋이 새로 만들었다고 주장하지 않으며 이번 카드 밖 수정 설계를 요구하지 않습니다; master는 별건 보완/명시된 제한 판정을 받아야 합니다.
독립 검증: JSON6종+기본판정3종 동치. 명령 문자열 실행·본문파일/심링크 실행·제품 Redis/DOM·gh 게시·홈 쓰기 0. 수정은 같은 나노, 설치는 master 책임입니다. 통합 반송은 알 수 없는 실행 소비가 있어도 F1 본문을 제거하는 경계에 한정합니다.

HOLD

## r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q1 HOLD — 고정 fdc6b3f36f에서 미해소 $RUNFILE 및 다른 이름 심링크→F는 독립 JSON rc2로 교정됐습니다. 그러나 literal_env(segs)가 모든 구간의 마지막 대입을 수집하고 그 최종 env를 앞 구간 실행에도 적용합니다(block-destructive-judge.py:140-150, :181-190). «실행 시점 앞의 대입» 증명이 아니므로 같은 r1 성질의 파일 실행을 숨길 수 있습니다.
독립 JSON 반례(훅 실행 환경 RUNFILE=F): quoted heredoc으로 F에 Redis SET 본문 생성→gh --body-file F→`bash "$RUNFILE"`→그 뒤 `RUNFILE=/tmp/safe.sh`. 훅은 나중 safe 경로를 앞 bash에 적용해 realpath≠F로 보고 rc0입니다; 실제 Bash는 safe 대입 전에 F를 실행합니다. 마지막 safe 대입을 빼면 rc2. 4 probes(post only0/unknown var2/symlink2/late assignment0)를 임시 훅으로 확인했고 명령 문자열은 실행하지 않았습니다. 구간 순서에 따라 대입을 해소하거나 뒤 대입을 앞 소비의 증거로 사용하지 않는 fail-closed 교정 및 회귀 fixture가 필요합니다.
Q2~Q4 재심 없음. X7은 master #67070의 명시 제한·후속 카드 결정이 원장에 있어 이번 재검에서 제외했습니다. 본문 파일/Redis/DOM/gh 게시·홈/라이브 쓰기 실행 0(임시 훅·심링크 fixture와 JSON 판정만).

두 번째 HOLD이므로 연속 DA 리뷰 종료·master 통합 이관. 수락: 미해소 변수/심링크 동일 F 차단. 잔여 1개: 대입 해소의 실행 순서 역전으로 같은 F 소비를 다른 경로로 오증명.

HOLD
