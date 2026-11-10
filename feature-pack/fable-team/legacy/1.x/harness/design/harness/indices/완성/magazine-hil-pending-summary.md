# 인덱스: 아침 매거진 「오빠 할 일」을 «답이 안 간 요청»으로 + 요약 3줄을 구체적으로 (판정 350 후속 · 내일 08:00 호 전)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 350(오빠: launchd·랜딩 GO + 이 후속) · 설계 design/teams/harness/DESIGN-morning-magazine-20261008.md
- 상태: 대기
- 선행: 없음(§43·§44 랜딩분 위에서)
- 시험 입력: 가짜 mbox jsonl(요청·회신 쌍) · 가짜 구조 모델 · 가짜 요약 명령 — 실 슬랙 0 · 실 LLM 은 완료 조건의 dry-run 1회만
- 기준값: 10-08 호(뿌리 글 ts 1791417434.528749) — 「오빠 할 일 8건」 = 상한값(실제 «[HIL» 포함 글 80건 · 그중 본문이 «[HIL» 로 시작하는 요청 45건 · planner 가 그 좌석 «계보»에 회신 안 한 것 1건 · arch#9 실측 · master#12 대조 반영). 결론 줄 = 「수리 버튼 백엔드, 외상 알림, 개인 차단 등 주요 기능들의 개발이 완료되어 병합되었어요」(일반적).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 6-b(오빠 피드백 반영). 핵심 한 줄: 판정 350 오빠 피드백 — 첫 호의 「오빠 할 일 N건」이 부풀려졌고 요약 3줄이 일반적.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진(매일 08:00 · 슬랙 미러 채널 + PDF)의 첫 호가 나갔다. 오빠 피드백 두 가지. ①「오빠 할 일 8건」: 수집기가 planner 로 간 쪽지 중 본문 «어디에든» `[HIL` 이 들어간 것을 8개까지 담고(magazine_collect_mbox.py:98) 뿌리 글은 그 개수를 그대로 쓴다(byz_morning_magazine.py:125 → magazine_slack.py:36). 그래서 부팅 보고·규칙 설명처럼 `[HIL` 을 «언급»만 한 글, 이미 오빠 값이 내려간 요청까지 세고, 8에서 잘려 늘 8 근처가 된다. 실측(10-07 08:00~10-08 08:00): 포함 80 → 본문이 `[HIL` 로 «시작»하는 요청 45 → 그 뒤 창 안에서 planner 가 그 좌석 계보에 쪽지를 보내지 않은 것 1(정확한 이름으로만 보면 2 — #60339 은 22:13 후계 #146 으로 「#60339 답」 회신 #60363 이 갔다). 이 1건이 진짜 «오빠 할 일»이다. ②요약 3줄이 「주요 기능들의 개발이 완료」 같은 일반론이다 — 요약기 입력(magazine_summary.py `facts`)이 건수와 제목 나열뿐이고, 프롬프트가 «무엇을 콕 집어 말하라»를 요구하지 않는다. 이 카드는 «요청 = 본문 시작이 [HIL», «답이 안 감 = 요청 시각 뒤 창 끝까지 planner 좌석 → 그 요청 좌석의 «계보»(이름에서 `#N` 뗀 베이스 · 승계 좌석 포함) 쪽지 0»으로 세고(개수는 상한 없이 · 표시는 8줄), 요약 입력·프롬프트를 칸 3개로 고정해 구체적으로 만든다.

## 사전검증
- 소환: 아니오
- 면제: DA 사전검증 APPROVE 된 설계(DA-magazine-20261008.md)의 게시 경로·상태기계·실패 처리는 그대로 두고, 수집 칸 하나의 집계 규칙과 요약 프롬프트 문장만 바꾼다. 바깥 쓰기 경로 변경 0 · 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#9

## 조사 근거
- `scripts/harness-install/slack-mirror/magazine_collect_mbox.py:98` — `if "[HIL" in r["body"] and len(hil) < HIL_MAX` (포함 매칭 + 8 상한).
- `scripts/harness-install/slack-mirror/byz_morning_magazine.py:125` — `hil = len(model["mbox"].get("hil", []))` → `scripts/harness-install/slack-mirror/magazine_slack.py:36` 「오빠 할 일이 N건 있어요」.
- `scripts/harness-install/slack-mirror/magazine_render.py:50` `_hil_blocks` — 「최대 8건까지만 보여요」.
- `scripts/harness-install/slack-mirror/magazine_summary.py` `facts`·`PROMPT` — 입력 = 건수 5개 + 머지·이슈 제목 나열, 문장 지시 = 「가장 큰 변화 / 그 밖의 변화 / 오빠 할 일」.
- 실측 스크립트(arch#9 · master#12 대조 #61054 반영): 창 안 planner 수신 쪽지 중 `[HIL` 포함 80 · 원문 맨 앞이 `[HIL` 17(접두 `[a->b]` 있는 글이 빠짐) · 접두 뗀 본문이 `[HIL` 로 시작 45 · 답 안 감: 정확한 이름 기준 2(seq 60339 `byz-v65-master-claude#145`→planner#6 22:07 「[HIL · 오빠 손 1] 툴바 press …」 · seq 60960 `byz-cfo-master-claude#56`→planner#8 07:48 「[HIL] 판정 341 집행 2/3 막힘 …」) → 계보 기준 1(60339 은 후계 #146 회신 #60363 22:13 · 60960 은 창 뒤 08:23 #60981 회신 — 08:00 기준 미답이 맞음).

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_collect_mbox.py`: 요청 = planner 좌석(`byz-planner-`) 수신 + 접두 뗀 본문이 `[HIL` 로 «시작». 답 = 요청 시각 뒤 ~ 창 끝 사이 `from` 이 planner 좌석이고 `to` 의 계보(`#N` 뗀 이름)가 요청 `from` 의 계보와 같은 쪽지가 1건 이상(승계로 이름이 바뀌어도 회신을 놓치지 않게). `mbox` 칸에 `hil_asked`(창 안 요청 수 · int) 추가, `hil` = 답이 안 간 요청의 첫 문장 목록(★상한 없음★ · 오래된 순). 계약 변경은 이 «칸 1개 추가 + hil 뜻 변경»뿐.
2. `scripts/harness-install/slack-mirror/magazine_render.py` `_hil_blocks`: 제목 아래 1줄 「요청 {hil_asked}건 중 답이 안 간 {len(hil)}건 — planner 가 그 좌석에 회신한 것은 뺐어요」 · 목록은 8줄까지 + 남으면 「외 N건」. `scripts/harness-install/slack-mirror/magazine_slack.py` `root_text` 는 «답이 안 간 수»(= len(hil))를 그대로 쓴다(코드 변경 불요면 0).
3. `scripts/harness-install/slack-mirror/magazine_summary.py`: `facts` 에 ⓐ답이 안 간 요청 첫 문장(최대 3) ⓑ꼬리표가 `[feature]`·`[fix]` 인 머지 제목 우선 5개 ⓒ닫힌 이슈 제목 5개 ⓓ건너뛴 날·깨진 줄이 있으면 그 사실 — 를 넣는다. `PROMPT` 칸 3개 고정: 1문장 = 가장 중요한 결과 1개를 «기능·문제 이름 그대로» · 2문장 = 오빠가 결정할 것 1개(답이 안 간 요청 중 첫 건의 요지 · 없으면 「오빠가 결정할 건 없어요」) · 3문장 = 주의할 것 1개(막힘·실패·건너뛴 날 · 없으면 그 밖의 큰 변화). 「주요 기능들」「여러 작업」 같은 묶음말 금지 문장을 프롬프트에 넣는다. `deterministic_lines` 의 「오빠 할 일」 수도 새 뜻으로.
4. 시험: `tests/scripts/test_magazine_collect_mbox.py`(요청 시작 판정 · 접두 `[a->b]` 있는 요청 포함 · 언급만 한 글 제외 · 회신 있으면 제외 · ★후계 좌석(#N+1) 회신도 답으로 침★ · 다른 계보 회신은 무관 · 창 끝 뒤 회신은 무시 · 상한 없음 · hil_asked) · `tests/scripts/test_magazine_render.py`(「요청 N건 중 …」 줄 · 9건 → 8줄 + 「외 1건」) · `tests/scripts/test_magazine_summary.py`(facts 에 ⓐ~ⓓ · 프롬프트에 칸 3개·묶음말 금지 문구). 설계 `design/teams/harness/DESIGN-morning-magazine-20261008.md` §1 #4 · §8 계약 줄에 `hil_asked`·`hil` 새 뜻 1줄씩.

커밋은 자기 브랜치, **push 금지**. **금지**: 상태기계·슬랙 게시·push·PDF 모듈 변경 · 실 슬랙 게시 · launchd 조작 · 미러 모듈 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_*.py -q` rc=0 · `bash tests/harness/test_magazine_plist.sh` rc=0.
- 실자료 `collect("2026-10-08", …)` → `hil_asked=45 · len(hil)=1`(seq 60960 만)(기준값과 다르면 이유 1줄).
- 실 LLM dry-run 1회: `BYZ_ROOT=<루트> python3 byz_morning_magazine.py --date 2026-10-08 --dry-run --force --out-dir <scratch> --state <scratch>/state.json` → 슬랙 뿌리 글 3줄 + 「오빠 할 일이 1건」 줄 복붙(첫 줄에 기능·문제 이름이 그대로 있어야 함).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 2ee0357f3a6b26c4c8a9bb7c2c218c21732b1a2f (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 판정 350 후속). spawn 은 master 판단 · 내일 08:00 호 전 랜딩 + 라이브 cp(~/.hermes/scripts — 장기 루프 아님 · 다음 발사부터 반영).
- 정본 영향 없음: 하네스 슬랙 키트 모듈·시험·하네스 설계 1줄 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:01 — 대기→진행 · 좌석 byz-harness-nano-magazine-hil-pending-summary#0
- 2026-10-08 — 완료 독립 검증 (arch#9 · 판정서 §45 초안) — 나노 3d5fcaff2a: 매거진 시험 82 passed · 회신 판정은 planner 발신 쪽지만(collect_mbox.py:112) · 요청 뒤 회신만 셈 · 실자료 hil_asked=45·hil=1(seq 60960) · 실 LLM dry-run 3줄 = 「수리 버튼 백엔드…」「판정 341 집행이 운영자 토큰 부재로 막혀…」「로컬 테스트 11건 기존 실패…」(구체적) · 뿌리 글 「오빠 할 일이 1건」.
세트: 3d5fcaff2ab823cabbaef9f9cea80f941cc2aa5f · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0
- 2026-10-08 09:11 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§45
