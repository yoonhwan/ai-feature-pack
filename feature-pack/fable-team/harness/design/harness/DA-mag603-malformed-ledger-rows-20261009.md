# mag603 구현 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 74ab10e7a2 · 기준 60ed7677dd · 고정 Q1~Q3 · 원장 보정/발행 제외.

- Q1 APPROVE(기존 R행 필터 범위) — report_mode는 판정602 그대로이며 R행 열 수 불일치는 opt-in 없으면 기존 문구로 raise합니다(magazine_collect_open.py:59-62). _requests의 blob 실패→다음 ref→모두 실패 raise는 기존과 같고 파싱 실패를 다른 ref로 숨기지 않습니다(:43-52). ID 빈 비R행을 기존 필터가 건너뛰는 동작은 기본모드 불변과 Q2 report모드 누락을 분리합니다.
- Q2 HOLD — _parse가 `ln.startswith('| R')`인 줄만 검사해 ID가 빈 형식 미달 데이터 행이 ERROR·malformed_requests 없이 사라집니다(:57). 독립 순수 반례 report=True, `|  | a | 요청 요지 | 상태 |` → 정상[]/malformed[]/stderr0. R3 네 칸 행은 ERROR1/malformed1이고 7칸 닫힘 행은 제외되어 의도대로입니다. 요청이 명시한 빈 ID 경계를 report모드에서 데이터행으로 검출해 행 위치 등 확인 가능한 식별자를 세 화면에 보이거나, 지원 제외를 명시하고 결과에서 경고해야 합니다. 내용 추정·원장 자동 보정은 요구하지 않습니다.
- Q3 APPROVE(정상행·출력 분기 확인) — 기존 _request(line)과 새 _request(_cells(line))의 진행/상태빈칸/닫힘/끝 추가빈칸 4 cases 결과가 독립 동일합니다. _cells의 뒤 빈칸 정리와 cells5 닫힘/본문 규칙은 그대로입니다(:70-81). malformed_requests=[]이면 requests_warning_line=None·_malformed_requests=[]·bad_lines의 기존 카드경고만 유지되므로 추가 화면 줄은 없습니다(shape:41-56, render_full의 _appendix/render_full). 전체 CLI/render bytes는 arch 증거와 코드 분기로 확인하며 독립 PDF/발행은 하지 않았습니다.

독립 검증은 순수 parser의 R정상/닫힘/잘못된4칸 및 빈ID 반례·정상행 전후4개 대조입니다. arch58 PASS·실dry PDF537쪽·기존13실패 동일은 보고 증거로 구분합니다. 라이브 원장/카드·홈·LLM·PDF·Slack·launchd 쓰기/실행 0. 반송은 report모드의 빈ID 데이터행 침묵 누락 한 건이며 수정은 같은 나노, 오늘 호 재발행은 master입니다.

HOLD

## r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q2 HOLD — 고정 dbcb4d6c50에서 r1 빈 ID 네 칸 행은 `(빈 ID) 줄1`/4열/ERROR1로 보완됐고 기존 경고3곳은 그 id 목록을 소비합니다. 그러나 _is_data_row는 _cells 결과로 빈 행을 판정하고 _cells가 끝 구분자 유무와 관계없이 split의 마지막 요소를 버립니다(magazine_collect_open.py:_is_data_row/_cells).
독립 순수 반례 `|  |  | 요청 요지` → _cells=['',''], report=True 정상[]/malformed[]/ERROR0. 실제 원문에는 요청 요지가 있는데 끝 '|'가 없다는 이유로 내용이 빈 것으로 분류되어, 명시 제한 «칸이 전부 빈 줄·잃을 정보 없음» 밖의 데이터가 사라집니다. raw행의 마지막 비어 있지 않은 내용을 빈 줄 판정 전에 보존/검증하고 해당 malformed 식별·ERROR·세 화면 경고 fixture를 추가해야 합니다. 기본모드의 기존 동작 변경은 요구하지 않습니다.
독립4 probes: r1 빈ID 교정1·끝delimiter없는내용 누락1·명시empty제한·헤더 제외. Q1·Q3 재심 없음; 기존60/13실패동일·실dry는 arch 보고 증거입니다. 라이브 원장/홈·LLM·PDF·Slack·launchd 0.

두 번째 HOLD이므로 연속 DA 리뷰 종료·master 통합 이관. 수락은 빈ID 줄번호 보고, 잔여 1개는 빈 줄 판정에 사용하는 lossy cell 파서가 마지막 내용까지 버리는 경계입니다.

HOLD
