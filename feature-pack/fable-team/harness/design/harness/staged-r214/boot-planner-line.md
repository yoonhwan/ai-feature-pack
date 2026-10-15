# R214 상시 로드 줄 초안 (판정 1804) — master 가 홈에 설치

> 원문(오빠 판정 1804): «결정리스트를 매번 카운팅을 공유해. 결정인터뷰 N건, 스크립트 N건을 플래너팀 마스터는 출력해서 나에게 알리고 밀리지 않도록한다»
> 강제 장치(이 줄만으로는 규칙이 아니다): Stop 훅 `scripts/harness-install/hooks/planner-decision-line.sh` — planner `_master` 좌석 settings 에만 등록(전역 0) · 도구 `ft-decision-count.sh` · 경보 launchd `com.byz.ft-planner-decisions`.

## 1. COMM-GUIDE-BOOT.md 새 조항 (35번 — 34 아래)

```
35. **planner 보고 첫 줄 = `결정 인터뷰 N건 · 스크립트 N건`**(2026-10-15 오빠 판정 1804 · 원장 R214): planner(메인 팀 오케)가 오빠께 올리는 모든 최종 답변의 첫 줄은 `bash <루트>/.fable-team/bin/ft-decision-count.sh` 출력 줄로 시작한다 — 결정 인터뷰 N = 인박스 ②[HIL]·③판정 요청 미닫힘 + MERGE-QUEUE «대기» + AUTONOMY-QUEUE 행 · 스크립트 N = 오빠가 아직 안 친 h(R186 표식) · 팀 대기 = 다른 팀이 planner 값을 기다리는 건수(30분 넘으면 경보 쪽지 `[결정 대기 경보]` → 그 턴에 정하거나 오빠 인터뷰). 강제 = Stop 훅 `planner-decision-line.sh`(첫 줄이 없거나 숫자가 도구와 다르면 턴당 1회 block). `--detail` 이 항목별 목록.
```

## 2. main-team-governance.md §9 1줄

```
- ★planner 보고 첫 줄 = 결정 대기열(판정 1804 · R214)★: `결정 인터뷰 N건 · 스크립트 N건 · 팀 대기 N건` 을 오빠께 올리는 글 맨 위에 쓴다(도구 `ft-decision-count.sh` · 강제 Stop 훅 `planner-decision-line.sh`). 팀 대기가 30분 넘으면 도구 경보(`--alarm`, launchd 300 s)가 planner 에 쪽지 1통 — 받은 그 턴에 정하거나 오빠께 인터뷰한다.
```

## 3. 설치 순서 (master · 홈)

1. 키트 → 런타임 bin 복사(cmp 0): `ft-decision-count.sh` · `ft_decision_count.py` · `ft_news_ledger.py` · `ft_news_ledger_text.py` (`scripts/harness-install/fable-team/bin/` ↔ `.fable-team/bin/`).
2. 훅 복사: `scripts/harness-install/hooks/planner-decision-line.sh` → `~/.claude/hooks/` 후 **planner 좌석 settings 에만** Stop 훅으로 등록(`report-coverage.sh` 와 같은 자리 · 전역 0).
3. launchd: `com.byz.ft-planner-decisions.plist.template` 의 `__FT_BIN__`·`__BYZ_ROOT__` 를 채워 `~/Library/LaunchAgents/` 에 두고 load(StartInterval 300). 경보 발신자 이름 = `ft-decision-count`(env `FT_DECISION_FROM`).
4. 위 1·2 줄을 BOOT·governance 에 넣고 `COMM-GUIDE.md` sha/줄 범위 표 갱신(`ft-version.sh check`).

## 4. 원장 R214 행 «처리» 칸 초안

`처리: 구현 10-15 — ft-decision-count.sh(결정 인터뷰·스크립트·팀 대기 한 줄 · --detail · --alarm) · Stop 훅 planner-decision-line.sh · launchd com.byz.ft-planner-decisions(300 s) · 뉴스 첫 줄(ft_news_ledger_text.py lead) · 병합 sha <sha> · 설치 <날짜> · 실물 확인(보고 첫 줄 1건 · 경보 1통 또는 «팀 대기 0» 줄) 대기`

## 5. 알아 둘 것

- AUTONOMY-QUEUE 에 «처리됨» 칸이 없어 전 행을 센다(줄 끝 `(자율 큐 처리 표식 없음)`) — 칸을 만들면 도구가 빈 칸만 센다(planner 문서 형식).
- 팀 대기 = 인박스 미닫힘 ①~④·미상. 실 인박스에는 일주일 넘은 줄이 남아 있어 첫 실행 값이 크다 — 정리는 planner·오빠 몫(카드 범위 밖).
