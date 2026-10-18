# mag609 설계 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 설계 카드 mag609-eli5-readable-decisions · 기준 c3219b677f · 고정 Q1~Q3 · 착수 전.

- Q1 HOLD — PDF 미리보기·확장자별 content-type/기존 kind 키 유지 방향은 수락합니다. 그러나 파일 제목은 정확 일치 멱등 표식입니다(magazine_attach.py:25, :34-39). 기존 phase=posted/files.pdf=sharing에서 옛 `… PDF r0` 파일이 이미 붙어 있어도 새 `… 풀 디테일 r0` 제목으로는 채택하지 못해 불명 차단될 수 있습니다. 설계1에 옛/새 제목 채택 및 HTML→PDF 형식 변경의 부분 발행/resume/reattach 정책을 추가하고 같은 날 done은 기존 HTML을 유지하는지 새 rev로 전환하는지도 시험하십시오. 제목만 바꾸고 키/phase가 같다는 것으로 호환을 닫지 못합니다.
- Q2 HOLD — model.verdicts.line은 planner 원문의 판정 번호 포함 줄을 그대로 처음1개/120자로 보관합니다(magazine_collect_mbox.py:145-159). `[from->to] [판정 N · 오빠 …]`에서 첫 대괄호는 전송 머리라 현재 설계3 필터로 실제 결정이 제외됩니다; 오빠 표식 없는 실제 값도 기타 N으로 묶여 «내린 결정 전부»라는 의미가 보장되지 않습니다. 전송 접두를 먼저 제거하고 명시 결정/미분류 기록의 근거·표시 계약을 정하십시오. mbox.hil을 기존 미회신 원천으로 쓰는 것과 LLM 실패 줄/각주 보존 방향은 수락하지만 완료·확정 여부를 문구만으로 과장하면 안 됩니다.
- Q3 HOLD — 설계4의 [A-Z]\d{1,3}는 경계가 없어 CO2의 O2·UTF8의 F8을 인덱스로 오인하고 B12 같은 실제 이름도 제거합니다(설계 패턴만 순수 대조: CO2→C, UTF8→UT). 반대로 기존 발행/링크/sha 표식의 보존 및 본문 영역 판별은 아직 시험으로 정의되지 않았습니다. 설계4에 metadata token 경계/적용 필드 및 비인덱스 실제내용 보존, 본문·각주 DOM 영역 분리 규칙을 명시하고 CO2/B12/UTF8 통과·R63/판정번호/sha칩 각주 이동·LLM 실패 각주 연결 fixture를 추가하십시오. 새 원문을 추정하는 구현은 요구하지 않습니다.

검토는 문서/기준 코드 및 설계 정규식의 순수 대조만이며 새 코드·LLM·HTML/PDF 생성·Slack·홈 설치 0. 통합 반송: 첨부 표식 전환의 상태 호환, 결정의 근거/접두 분리, 인덱스와 실제 내용 구분. 수정 소유자는 arch, 구현·dry/발행은 요청서의 master/nano 단계입니다.

HOLD

## r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q1 APPROVE — 설계r2-1이 옛/새 제목 채택·sharing 불명 유지·done의 기존HTML 유지·force/reattach 새형식 정책을 명시하고 A1~A4 fixture로 전환 상태를 고정해 r1 호환 공백을 닫습니다. 기존 키/phase 유지와 형식 전환을 구분한 수락입니다.
Q2 APPROVE — r2-2는 전송 접두를 반복 제거하고 박스에 «오빠 표식 기록» 분류 기준을 표시하며 표식 없는 판정도 끝 목록에 전부 남깁니다. 모든 실제 인간 결정을 판별했다고 과장하지 않는 계약·D1/D2 및 LLM 실패 각주/ERROR로 r1을 닫습니다. 수집된 원문120자 한계는 변경하지 않는 범위입니다.
Q3 APPROVE — r2-3은 일반 [A-Z]숫자를 없애고 토큰 경계/필드/본문·각주 영역을 지정해 CO2/B12/UTF8 보존과 metadata 각주 이동을 분리합니다. 순수 regex 대조에서 이 세 문자열의 골코드 M/K·R 토큰 매치0을 확인했고 I1~I4로 실제 렌더에서 검증하도록 고정했습니다. 새 코드/모델/PDF의 실측 승인은 아닙니다.

설계r2가 이전 1/3/4항을 대체하는 범위만 재검했습니다. 구현·LLM·HTML/PDF·Slack·홈/launchd0; arch 구현 재현/실데이터 dry 및 master의 재발행은 완료 조건의 잔여입니다.

APPROVE
