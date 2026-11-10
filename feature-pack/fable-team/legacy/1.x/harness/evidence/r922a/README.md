# r922a 증거 — 옛 뉴스 잡(초안 모드)의 골 표 묶음 검증 실패가 planner [긴급] 이 아니라 로그 경고 1줄인가

카드 = `design/harness/indices/진행/r922a-news-draft-goal-gate-warn-not-urgent.md`
브랜치 = `nano/r922a-news-draft-goal-gate-warn-not-urge` · base = `63ae5209`(origin/main) · push 0(master).

## 고친 자리 1 + 짝 사본

| 파일 | 무엇 |
|---|---|
| `feature-pack/fable-team/harness/bin/ft_news_post.py` (`_refuse` 신설 + `publish` R362 분기) | 묶음 검증 실패 거절을 `_refuse` 한 곳으로 모았다. 초안 모드(`FT_NEWS_MODE=draft`) **이고** 무장(`state/goal-gate.armed`)이면 `goal_gate.refuse` 를 부르지 않고 `WARN draft 묶음 검증 실패(긴급 0 — 발행 0 모드) <사유 앞 200자>` 1줄만 남긴 뒤 `True`(막는다)를 돌려준다. 발행 모드·비무장은 지금 그대로 `goal_gate.refuse` 를 부른다 |
| `feature-pack/fable-team/harness/kit/fable-team/bin/ft_news_post.py` | 짝 사본 cmp0 |

`publish` 쪽: `LOG.error("REJECT 골 표 없음 …")` 는 초안 모드에서 찍지 않는다(«로그 경고 1줄로만»). `rc`·발행 0·기준선 불변은 그대로 — 초안+무장 실패 = `rc=3`, 초안+비무장 = `rc=0`.

**게이트 본체(`ft_goal_gate`)가 없는 설치**도 같은 문을 지난다 — `_MissingGate.armed` 가 있어 초안 모드면 최소 통지(`_notify_minimal`)도 나가지 않는다(`armed` 판정만 `_refuse` 가 따로 보는 이유: 통지는 `refuse` 안에 있어 «로그만 남기는» 길이 없다).

### 지키는 선 (DA 질문 2개에 대한 선반영)

| 물음 | 답 |
|---|---|
| 발행 모드의 긴급을 숨기는 길이 생기나 | 아니다 — `is_draft()` 가 참이고 무장일 때만 통지를 건너뛴다. ⓑ(html)·ⓑ'(본체 없음+html) 가 `[긴급]` 1통을 그대로 확인한다 |
| env 오타·빈 값이 draft 로 읽히는 길 | 아니다 — `is_draft()` 는 `== "draft"` 완전 일치다. `drafts`·빈 값 = 발행 모드로 읽혀 `[긴급]` 이 나간다(ⓓ). 조용한 강등 0 |

## 시험

```
bash feature-pack/fable-team/harness/tests/test_r922a_news_draft_gate_warn.sh
python3 feature-pack/fable-team/harness/tests/mutate_r922a_draft_gate.py
```

| 파일 | 무엇 | rc |
|---|---|---|
| `test-red.txt` | 고치기 전(HEAD 판 `ft_news_post.py`) → ⓐ·ⓐ' 빨강 5 fail(ⓑ·ⓑ'·ⓒ·ⓓ·ⓔ 는 그때도 초록 = 대조군) | 1 |
| `test-green.txt` | 고친 판 → 35 PASS · `fail=0` | 0 |
| `mutation.txt` | 변이 2종(초안 분기 끔 → ⓐ 4 fail · 모든 모드 WARN → ⓑⓑ'ⓓ 9 fail) = `MUTATION-ALL-RED` | 0 |

새 시험이 보는 값:

ⓐ 초안+무장+검증 실패 → `rc=3`(지금과 같다) · mbox 송신 0 · WARN 1줄 · `ERROR REJECT 골 표 없음` 0 · 발행 도구 0 · `last.sha` 안 옮김
ⓐ' 게이트 본체 없음 + 초안+무장 → 최소 통지 0 · WARN 1줄 · `rc=3`
ⓑ html + 무장 + 같은 입력 → `[긴급] 뉴스 발행 거절 — 골 표` 1통 · `ERROR REJECT 골 표 없음` 1줄 · draft WARN 0
ⓑ' 본체 없음 + html → 최소 통지 1통
ⓒ 초안+정상 묶음 → `rc=0` · WARN 0 · REJECT 0 · 통지 0 · 발행 도구 0 · 초안 파일은 남음
ⓓ `FT_NEWS_MODE=drafts`·빈 값 → draft 아님(`[긴급]` 1통)
ⓔ 초안+비무장 → `rc=0` · `WOULD-REJECT` 로그 · 통지 0

## 회귀

| 시험 | 값 |
|---|---|
| `tests/test_news_html.sh` | rc 0 · FAIL 0 |

선행 빨강(내 변경과 무관) — `tests/test_goal_table_gate.sh` 의 `ⓕ r458 600/300 상한 등장` 1 fail. 근거는 `bin/ft_news_ledger.py:453` 의 `FT_NEWS_FETCH_MIN` 기본값 `300` 이며 이 카드가 건드린 파일이 아니다.

## 설치 대상(master 집행) — `LIVE_BIN` = `/Users/yoonhwan/.claude/fable-team/live/1.1.244/bin`

`ft_news_post.py` 1개 cp + cmp0. 설치 뒤 옛 잡(`FT_NEWS_MODE=draft`) 다음 회차에서 **planner 우편함 `[긴급]` 0 · 로그에 WARN 1줄**이 닫는 값이다(라이브 1회는 master+DA 소관).

## press

press 필요 없음(단위·격리 시험만 — 라이브 오디오 경로 0). press 가 필요하면 «옛 잡 다음 회차 로그·우편함 1회 확인» 이며 그건 master 가 한다.
