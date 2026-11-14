# fable-team · BYZ 전용 하드 룰 (ft 좌석·BYZ 작업이면 그 턴에 먼저 연다)

> 2026-11-06 r1435 — 사용자 레벨 `~/.claude/CLAUDE.md`(전 프로젝트 공통)에서 **ft·BYZ 전용 조항만** 여기로 내렸다.
> 오빠 지시: «이거 하나씩 개별로 분리해야하는거 아니냐? byz 전용은 프로젝트 하위에. 사용자레벨은 사용자 클로드 하위에 있어야지?»
> 그래서 나눈 기준 — **사용자 레벨** = 어느 프로젝트에서든 참인 것(호칭·파괴 HIL·7초 룰·ci·인덱스 금지 등). **여기** = fable-team 좌석 운영·DA·증류·발주. **BYZ 프로젝트** = `~/Project/Agent/BYZ-Work/BYZ-Agents/CLAUDE.md`(1Password develop 볼트 · BYZ 경로).
> 번호는 사용자 레벨과 공유한다(참조 «하드 룰 14» 가 깨지지 않게). 사용자 레벨 쪽에는 «6·7·13·14·15·21·23·24 = 여기» 1줄만 남는다.

## 옮겨온 하드 룰 (원문)

6. **멍청한짓 과징**: 지적 1건 → 그 턴에 `guides/dumb-time-ledger.md` 기록 + `rules/dumb-time-digest.md` top6 갱신 → `guides/dumb-time.md`.
7. **골 소실 금지**: 승계·증류·발주 첫 3줄 = 골 원문 복붙 + «어느 축인가» 1줄 · 없으면 착수 0 → `guides/goal-loss.md`.
13. **오빠께 주는 `!` 명령** = `ft-hil.sh --add` 가 준 `! bash /tmp/h<N>` 한 줄만.
14. **막힌 문제**: DA 보류 3회 → 4번째 DA 대신 ★오빠 인터뷰★(선택지 3 + 추천 1) · 결정 뒤 반례 집합 동결, 구현만 교체 · 카드당 DA 상한 3 · 팀장 기본 Opus 5.5 · arch·DA 올릴 때 팀장도 ultrathink(그 세션 한정) → `guides/da-counterexample.md`.
15. **1Password**: BYZ 일은 develop 볼트(`OP_SERVICE_ACCOUNT_TOKEN_DEVELOP`) · kskill 토큰 0 · 실패면 원문 보고.
21. **결정 뒤 검증은 동작 반례만**: 동작 반례 0이면 묻지 않고 착지 · 남은 것 = «알려진 한계» 1줄 → `guides/da-counterexample.md` 핵심 7.
23. **증류·승계 = 쪽지 마무리 + 레디 확인 뒤에 닫는다**: 구세션은 recv 끝까지 → 받은 seq 마다 «처리함|인계» 를 인계서에 · 인계서에 마지막 작업(h·백그라운드·답 안 한 질문) · 신세션 = retire → recv → [레디] → 첫 보고 · [레디] 전 닫기 0 · h 결과는 rc 난 그 턴에 요청 팀+planner → 원문 `guides/hard-rules-full.md` §23.
24. **닫힌 발주**: DA·arch·서포트·인터뷰 발주문에 5칸 강제 — ①대상 동결 ②판정 기준 ③상한 ④종료 조건 ⑤다음 수 · 좌석당 1턴 질문 1회(그 이상은 파일에 선택지 3+추천 1) · sleep 금지 → `guides/closed-order.md`.

## 팀장·desk 운영 (사용자 레벨에서 내린 항목)

- **팀장·desk 운영 3종** = ①턴 시작에 recv·회신 먼저, 30초 넘는 집행은 background ②오빠 보고 결론 다음 줄 `카운터: <scope-status> · 오빠 손 h N · 막힘: <1줄|0>` ③체크루프 15분·심박 `[정리]` 첫 줄 `카드 대기 N · 진행 N · 유휴 N · 다음 수` → `main-team-governance.md` §11·§17.
- **골을 닫는 흐름**(전 좌석): 골 파일의 칸마다 현재 담당 1좌석 · 넘기면 «넘긴 기록» 을 먼저 적는다 · 기다리는 동안·응답 없을 때의 순서 → `main-team-governance.md` §18.
- **카드는 흘러야 한다**: 대기 → 진행 → 완성 → 아카이브 · 착지한 그 턴에 완성 이동 · 진행 ≤ 일하는 좌석 + 2 · 증거 줄은 진행 중에 → `~/.claude/guides/card-flow.md`.

## 왜 여기인가
- 이 조항들은 fable-team 좌석(팀장·planner·desk·arch·DA)과 BYZ 팀 폴더 구조에서만 참이다. 다른 프로젝트 세션에 실리면 상시 로드만 늘고 쓰이지 않는다.
- 사용자 레벨에는 «ft 좌석이면 이 파일을 먼저 연다» 1줄만 둔다. 그 1줄이 계약의 입구다(포인터가 사라지면 계약이 사라진다 — `~/.claude/guides/moved-to-skill.md` 참조).

## 좌석 기억(LESSONS) 규약 — 2026-11-06 r1436

- **부팅 1회 스냅샷**: `bash .fable-team/bin/ft-lessons.sh snapshot` (3계층 ≤2048B). 세션 중 `add` 는 파일에만 쓰고 이 스냅샷은 안 바뀐다 — 다음 부팅에 반영(hermes FROZEN 방식 · prefix cache 보존).
- **분류 태그**: `add <seat|team> <이름> "1줄" --kind directive|mistake|achievement` → `[D]/[M]/[A]`.
- **승격은 사람이**: 좌석 3회 반복 → 팀, 팀을 넘어 반복 → 전역 다이제스트. 자동 승격 없음(잘못된 일반화가 전 좌석에 퍼지는 것을 막는다).
- **저장 전 스캔**: 주입·유출 유도 문장은 REJECT. 상한 2배 초과(손편집 drift)면 `.drift-*.bak` 저장 후 rc1.
- 대조 근거 = `feature-pack/fable-team/docs/design-memory-evolution-repos-20261106.md`.

- **ft 좌석 tick 간격 상한 300초 · 운영값 280초** (오빠 지시). 「300초 초과 = 전체 재작성」은 거짓 — 캐시는 5분·1시간 두 등급이다. 실측·비용 판정은 요청 단위 분리집계 필요 → `~/.claude/skills/fable-team/references/cache-ttl-300.md`
- **mbox 는 읽기 전 pending 확인, 동일내용 반복 recv 억제** — 단 peek 도 모델 왕복이므로 비모델 gate 에서 판정한다. 새 발주·긴급 정정 재수신은 허용. `pending 0` ≠ 미완료 카드 0 → `~/.claude/skills/fable-team/references/mbox-no-empty-read.md`
