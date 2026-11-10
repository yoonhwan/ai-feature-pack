# DESIGN — 아침 매거진 세트: ①풀 디테일 PDF + ②eli5 HTML (판정 354 · Issue #885 추가 단위)

> byz-harness-arch-claude#10 · 2026-10-08 · 발주 master#12 #61124 · 보강 #61131(오빠 11:0x)
> 오빠 원문: 「하네스마스터 아침 매거진 추가 요청 — 완성 pdf 를 풀디테일로」
> 앞 설계: `DESIGN-morning-magazine-20261008.md`(§5 상태기계 · §8 구조 모델 11칸) — 이 문서는 그 위에 «덧붙이기»만 한다.

## ★골 원문 (GOAL-harness.md 복붙)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: C(배포 발행 — 슬랙) + 6-b(오빠 피드백 반영) + 원문 7(나노 3석 병행). 닫는 증거: 오늘 수동 1회 재첨부 결과 1줄(PDF 경로 · 페이지 수 · HTML 경로 · 슬랙 답글 ts) + 다음 08:00 호의 스레드에 PDF·HTML 2파일.

## §0 결론
- 구조 모델 11칸은 **그대로** 둔다. 새 칸 `detail` **1개만** 더한다(새 수집 모듈이 채운다). 기존 render·요약·시험은 안 바뀐다.
- ①PDF = «1부 요약판(지금 렌더 그대로) + 2부 풀 디테일 7절 + 부록 + 각주표(맨 끝 하나)». **여러 쪽 A4**로 바꾼다 — 한 장 높이 한도(18000px raise)는 풀 디테일 문서에서 뺀다. 잘라내기·요약 0.
- ②HTML = eli5 1장. **LLM 은 JSON 칸만 채우고, HTML 은 우리 템플릿이 만든다**(LLM 이 쓴 HTML·스크립트를 그대로 싣지 않는다). ★사실 영역(결정 박스 전부 · 단위의 제목·상태·닫는 증거 · 머리말)은 모델에서 결정적으로 — LLM 0★. LLM 은 단위별 «비유 1줄 + 쉬운 풀이 1~3줄»뿐이고 화면에 「AI 풀이 — 정본은 옆 원문 줄」 로 구분 표시한다(DA HOLD-F3 교정 · «과장 0» 보장은 사실 영역에만 건다).
- 슬랙 = 뿌리 글 3줄 그대로 + 스레드에 PDF·HTML 2파일. 상태기계에 단계 `pdf_done` 을 하나 끼운다(posted → pdf_done → done). `done` skip 계약은 그대로. ★파일마다 «원격 표식(정확한 파일 제목) 먼저 확인 → 시도 기록(file_id) → 공유» — 불명이면 새 파일 0·ERROR★(DA HOLD-F1 교정).
- 오늘(이미 done 인 날) 재발행 = **새 모드 `--reattach rN`** — 뿌리 글은 새로 쓰지 않고, 그 스레드에 답글 1개 + 2파일만 붙인다. ★`--reattach` 는 `--force`·`--force-root` 와 같이 못 쓴다(argparse 상호배타 · 원격 호출 전 exit 2) · 일반 발행 경로보다 «먼저» 분기★. 지금의 `--force` 단독은 «사람이 명시한 수동 새 뿌리 글 재게시 예외»로 남기고 수락 범위에 적는다(launchd plist 인자에 없음 실측 · DA HOLD-F2 교정). 옛 PDF 삭제 0(되돌릴 수 없는 원격 삭제라서).
- 나노 3석: ①수집(Sonnet 5.5) · ②렌더·PDF·발행(Sonnet 5.5) · ③eli5 HTML(**codex** — 시각 작업은 GPT 좌석 규칙). DA 사전검증 소환 1회.

## §1 풀 디테일 절 구성 (PDF 2부 · 순서 고정)
| 절 | 무엇을 싣나 (자르지 않음) |
|---|---|
| 목차 | 1부·2부 절 제목 + html 앵커 링크(PDF 안에서 눌러 이동) |
| D1 닫힌 단위 | 창 안에 `design/<팀>/indices/완성/` 로 들어온 카드마다: 제목 · 팀 · 왜(`## 배경` 전문) · 골좌표 · 닫는 증거(`## 상태` 의 `세트:` 줄 + 「완료 독립 검증」 줄) · DA 판정문 경로 · 그 카드를 옮긴 커밋 sha |
| D2 판정서 절 | 창 안에 추가·변경된 `design/<팀>/OPS-VERDICTS-*.md` 의 `## §N` 절 «전문» |
| D3 판정(결정 원문) | 창 안 planner 발신 쪽지 중 판정 번호가 붙은 것: 번호 · 시각 · 받는 좌석 · 본문 전문 · relay 전문 파일(있으면 내용, 없으면 「전문 파일 없음(/tmp 휘발)」) · 되돌림(본문·전문에서 「되돌림」 이 든 줄 · 없으면 「원문에 되돌림 없음」 그대로 적음) |
| D4 main 에 들어간 것 | 머지마다 제목 + 커밋 본문 전문(Why·What·Verify·Impact) |
| D5 이슈 | 연 것·닫은 것 전부 + 닫은 이슈의 마지막 댓글 전문(= 닫는 증거) |
| D6 열린 행 | ①창 끝 시점 `진행/`·`대기/` 카드 전부(제목 · 상태 마지막 3줄) ②`REQUEST-LEDGER.md` 의 닫히지 않은 행 전부 ③HOLD = 창 안 추가된 `design/<팀>/DA-*.md` 중 마지막 줄이 HOLD/REJECT 인 것 ④외부 장애 = `state/*/BREACH.md` 전문(git 밖 · 실행 시점 파일) |
| D7 좌석 | 승계·신규 «전부»(지금 5건 상한 없앰) + 닫힘 = 창 안 `NANO-LEDGER-*.md` 에 추가된 「닫힘」 줄 전부 |
| 부록 | 창 안 추가된 BRIEFING·CLOSEOUT 문서 전문 |
| 각주표 | 문서 전체에서 하나(맨 끝) — 구조 칸 번호(머지 PR · 이슈)만. 자유 문장의 `#N` 은 지금처럼 「N번」 으로 푼다(mbox seq 와 GitHub 번호가 섞여 있어서 — `magazine_render.py` scrub 규칙 유지) |

1부(결론 → 오빠 할 일 → 바뀐 것 → 근거)는 지금 `render()` 결과 블록을 그대로 앞에 둔다. 2부가 비면 그 절에 「없어요」 한 줄(빈 절 생략 0 — 수집이 됐다는 표시).

## §2 소스 매핑 (어디서 뽑나 · 읽기 전용)
- **읽을 ref**: `MAGAZINE_REFS`(쉼표 목록 · 기본 `origin/main,ops/main-base,origin/feat/v6-realtime-live`). 하네스 작업은 랜딩 전엔 `ops/main-base` 에만 있다(실측: ops/main-base upstream = origin/main · 원격 사본 0). 작업 트리를 읽지 않고 `git log <ref>` · `git show <ref>:<path>` 만(지금 `magazine_collect_git.py` 와 같은 원칙). ref 가 없으면 MagazineError(조용히 건너뛰기 0).
- 창 경계 sha: ref 마다 `git rev-list -1 --before=<start> <ref>` · `--before=<end>`. 같은 경로가 여러 ref 에 있으면 목록 앞 ref 를 쓴다.
- D1: `git log <ref> --since --until -M --diff-filter=AR --name-status -- 'design/*/indices/완성/*'` → 카드 본문은 `git show <끝 sha>:<path>` → 절 파서(`## 배경`·`## 골좌표`·`## 상태` · `세트:` 줄 · `--da` 경로).
- D2: `git diff <시작 sha> <끝 sha> -- 'design/*/OPS-VERDICTS-*.md'` 의 추가 줄이 속한 `## §N` 머리 → 끝 sha 의 그 절 전문.
- D3: mbox 사본(지금과 같은 `mailbox.log.jsonl`) · planner 발신 · 접두 뗀 본문에 `판정 \d+` · relay 경로 정규식 `/tmp/mbox/[^\s]+\.md`. 같은 번호가 여러 쪽지면 «처음 것» 이 원문, 나머지는 「같은 번호 쪽지 N건 더」 목록.
- D4: `git log origin/main --first-parent --format=%H%x00%B` 창 안 — merges 칸 sha 의 본문만(다른 ref 커밋 본문 0 · 판정 48 반송 r1).
- D5: 닫은 이슈마다 `gh issue view N --json comments` 마지막 1건 · 실패 = MagazineError.
- D6: 끝 sha 의 `git ls-tree` 로 `indices/{진행,대기}/` · `REQUEST-LEDGER.md` 표 행 중 「오빠 값」 칸이 `닫힘` 으로 시작하지 않는 행 · `DA-*.md` 마지막 비어 있지 않은 줄 · `$BYZ_ROOT/state/*/BREACH.md`.
- D7: `git diff` 로 `NANO-LEDGER-*.md` 추가 줄 중 「닫힘」 포함.
- 부록: 기존 `docs` 칸 경로를 `git show origin/main:<path>` 로 전문.

## §3 구조 모델 확장 (계약 · 칸 이름 고정)
기존 11칸 불변. 새 칸 하나:
```
"detail": {
  "refs": [{"name","start_sha","end_sha"}],
  "units": [{"team","path","title","why","coord","evidence":[str],"da","moved_sha","ref"}],
  "verdict_sections": [{"path","section","title","body"}],
  "decisions": [{"n","ts","to","body","relay_path","relay_text","rollback":[str],"more":int}],
  "merge_bodies": {"<sha>": "<본문>"},
  "issue_evidence": {"<번호>": "<마지막 댓글>"},
  "open": {"cards":[{"team","state","path","title","tail":[str]}], "requests":[{"id","text"}], "holds":[{"path","verdict"}], "breaches":[{"path","text"}]},
  "seats_closed": [{"path","line"}],
  "appendix": [{"path","text"}]
}
```
- `relay_text` 없음 = `null`(위 «전문 파일 없음» 문구는 렌더가 붙인다). 빈 목록은 `[]` — 칸 누락은 렌더가 RenderError.
- `--model-file` 로 옛 모델(detail 없음)을 주면 풀 디테일 렌더가 raise(「detail 칸 없음 — 수집부터 다시」). 조용히 1부만 내기 0.

## §4 PDF 여러 쪽 정책
- 풀 디테일 문서는 `page.pdf(format="A4", margin 14/12mm, print_background, display_header_footer)` — 바닥글 「아침 매거진 D · 쪽/전체」. 쪽 수 상한 없음. `MAX_HEIGHT_PX` 한 장 경로는 지울지 남길지 ②나노 판단이 아니라 **지운다**(쓰는 곳이 없어짐 · 데드코드 0).
- CSS: `@page{size:A4}` · `tr{break-inside:avoid}` · `pre,td{overflow-wrap:anywhere}`(sha·경로) · 긴 본문은 `<pre>` 가 아니라 줄마다 `<p>`(줄바꿈 보존 · 잘림 0).
- 시간: 브라우저 `timeout_ms` 30 → 120초. 넘으면 PdfError(raise).
- 쪽 수: 결과 PDF 바이트에서 `/Type /Page`(Pages 제외) 개수를 세서 CLI 출력에 `pages=N` · 0 이면 PdfError.

## §5 eli5 HTML (② · codex 나노)
- 입력 = 같은 구조 모델(풀 디테일 포함). 프롬프트 = eli5 SKILL.md 본문(`~/.claude/plugins/cache/claude-community/eli5/*/skills/eli5/SKILL.md` 중 가장 높은 버전 · 없으면 raise) + 칸 지시. 호출 경로 = 요약과 같은 `DEFAULT_CMD`(헤드룸 cc · `magazine_summary.py:87` `run_cmd` 재사용).
- LLM 출력 = JSON 만: `{"units":[{"ref": "<detail.units[].path>", "icon": "<허용 목록>", "analogy": str, "lines":[1~3개 str]}]}` — ★headline·decided 칸 없음(DA HOLD-F3 교정)★. 형식 검사: `ref` 실재·중복 0 · `icon` 허용 목록(약 20개 이모지 고정) · 줄 ≤ 80자 · 숫자·sha 금지 · 상태·권한 단어 차단 목록(완료·해결·승인·배포·결정·전부·모두·필요 없·안전 등 — 정본 목록은 모듈 상수) — 어긋나면 Eli5Error. ★이 검사는 «보조 필터»이지 의미 검증이 아니다 — 의미 보장은 아래 영역 분리로만 건다★.
- ★영역 분리(과장 0 의 범위)★: ①**사실 영역**(LLM 0): 머리말(「닫힌 일 N건 · 결정 M건 · 오빠 몫 K건」 템플릿) · 결정 박스 전부 · 단위 카드의 제목·팀·상태 칩(「닫힘」)·닫는 증거 칩(sha 앞 10자)·원문 한 줄(`why` 첫 문장 · scrub). ②**AI 풀이 영역**: 단위 카드 안 별도 상자 · 머리 「AI 풀이 — 정본은 옆 원문 줄」 · 흐린 배경·기울임 · 비유 1줄 + 풀이 1~3줄. LLM 문장은 ②에만 들어가고 ①의 칸 값을 바꾸지 못한다(템플릿 자리 고정). 정본 `docs` 없음 — 화면 바닥 1줄 「AI 풀이는 형식만 검사했어요 · 결정·상태는 PDF·원문이 정본」.
- 첫 화면 「오늘의 결정사항」 박스: 왼쪽 **오빠 몫** = `mbox.hil`(답이 안 간 요청 · 모델 그대로) · 오른쪽 **이미 결정된 것** = `verdicts` 의 「판정 N」 + 그 판정 줄(`verdicts[].line` · scrub · 80자에서 «…원문은 PDF D3» 표시로만 줄임) — ★둘 다 LLM 0★. 그 아래 단위 카드(사실 영역 + AI 풀이 상자). 맨 끝 번호 각주표 = PDF 와 같은 notes.
- HTML 은 템플릿 1개(`magazine_eli5_template.html` · 인라인 CSS · 외부 스크립트 0 · 외부 글꼴 0)에 값만 넣는다 — 모든 값 `html.escape`. 시각 디자인(색·배치·아이콘 크기·모바일 폭)은 ③나노 몫.
- ★eli5 실패 = «보이는 실패»★(DA §6 수락): eli5 는 «PDF 렌더 전에» 돌려 결과를 확정한다. 실패 시 HTML 은 만들지 않고 ①ERROR 로그 ②뿌리 글 마지막 줄 「쉬운 판(HTML) 못 만들었어요 — <원인 첫 줄 · `esc` 중화>」(reattach 면 답글 본문에) ③PDF 근거 절에 같은 줄. PDF·뿌리 글(답글) 발행은 계속.

### §5-b 실자료 규모 교정 (판정 49 · arch#10 재현 2026-10-08)
- 실측: 실자료 `collect("2026-10-08")` 의 단위 72개(프롬프트 10만 자)를 «한 번에» 부르니 1회차 30초 뒤 「AI 문장에 상태·권한 차단 단어 있음」(72개 중 하나만 걸려도 전체 실패) · 2회차 90초 timeout. 픽스처(단위 1개)로는 통과 — §5 의 «전체 아니면 0» 계약이 실자료에선 거의 매일 «HTML 없음»이 된다.
- ★묶음 호출★: 단위를 12개씩 나눠 부른다(72개 = 6회) · 동시 3개 · 묶음마다 timeout 90초. 프롬프트·검사 규칙은 §5 그대로(묶음 안 ref 는 그 묶음 단위만).
- ★단위별 보이는 생략★: 묶음 호출 실패(timeout · JSON 아님 · ref 불일치) 또는 한 단위의 형식 검사 실패(차단 단어 · 숫자 · 길이 · 아이콘)는 «그 단위(들)만» AI 풀이 상자를 빼고, 그 자리에 회색 칩 「AI 풀이 없음 — <사유 한 마디: 차단 단어|숫자|길이|아이콘|호출 실패>」 를 넣는다. 사실 영역은 그대로. 생략마다 ERROR 로그 1줄(단위 경로 · 사유).
- 화면 바닥 줄에 「AI 풀이 N/전체 · 생략 M(사유별 건수)」 · 뿌리 글에는 생략이 있을 때만 「쉬운 판 AI 풀이 M건 생략」 1줄. PDF 근거 절에 같은 줄.
- Eli5Error(HTML 없음 · §5 보이는 실패)는 «AI 풀이가 하나도 안 나온 날»과 SKILL.md 없음만.
- 이것은 «사실 데이터의 대체»가 아니라 부가 표현의 단위별 누락이고, 세 조건(ERROR 로그 · 화면 칩 · 바닥/뿌리 글 건수)이 모두 보인다 — #0 RULE 예외 조건 중 «명시 opt-in 플래그»는 이 HTML 자체가 부가물이라는 DA §6 판단(«사실 수집 필수 단계와 다른 부가 표현 단계»)에 기댄다. DA 확인 대상.

## §6 슬랙 · 상태기계 변경
- 뿌리 글 문구: 3줄 그대로 + 마지막 안내 줄만 「본문은 스레드의 PDF(풀 디테일)·HTML(쉬운 판)에 있어요」 (push 링크가 있으면 지금처럼 링크 줄).
- 단계: `posting → posted → pdf_done → done`. `posted` = PDF 부터 · `pdf_done` = HTML 만 · `done` = skip(불변). HTML 이 없는 날(§5 실패)은 `pdf_done` 에서 바로 `done`. 옛 상태 파일(pdf_done 없음)은 그대로 읽힌다.
- ★파일 첨부 멱등(DA HOLD-F1 교정)★ — PDF·HTML 각각, 날짜 r0 과 rN 모두 같은 규칙:
  - 파일 제목 = 원격 표식(«정확 일치»): `아침 매거진 D PDF rK` · `아침 매거진 D HTML rK`(K=0 은 정상 발행).
  - 업로드 «전» `conversations.replies(thread_ts)` 의 봇 글 `files[].title` 에서 그 제목을 찾는다 → 있으면 채택(업로드 0) → 다음 단계 기록.
  - 없으면: 상태 `files.<pdf|html> = {file_id, phase:"sharing"}` 를 `getUploadURLExternal` 직후·`completeUploadExternal` «전»에 기록 → 바이트 전송 → complete → 단계 기록(pdf_done / done).
  - 원격 표식 없음 + 상태에 `sharing` 기록 있음 = **불명** → ERROR 「불명: D <종류> rK 첨부 확인 필요 — 채널 확인 뒤 --force-file <pdf|html>」 + exit 1 · 새 file_id 발급 0. 같은 file_id 로 complete 재호출은 하지 않는다(API 재시도 안전성 미확인 — 가정 0).
  - `--force-file <kind>`: 사람이 채널을 본 뒤 그 기록만 지우고 새로 첨부(`--force-root` 와 같은 수동 탈출구 · `--reattach` 와 함께 쓸 수 있음 · `--force` 와는 배타).
  - Slack 공유가 replies 에 늦게 보이면 곧바로 재실행해도 «불명 ERROR»(보이는 실패)로 끝난다 — 자동 2중 첨부보다 안전한 쪽.
- 업로드는 proposal-tools 나노가 넓힌 `magazine_slack.upload_file(t, ts, path, title, content_type)`(`text/html`)을 쓴다 → **②나노는 proposal-tools 랜딩(ops/main-base 반영) 뒤 base 를 잡는다.**
- ★CLI 모드 계약(DA HOLD-F2 교정)★: `--reattach` 는 argparse 에서 `--force`·`--force-root` 와 상호배타(조합 = 원격 호출 0 · exit 2) · `run()` 첫 분기(done skip·publish_day 보다 앞). `--force` 단독 = «사람이 명시한 수동 새 뿌리 글 재게시» 예외로 «같은 날 뿌리 글 최대 1개» 보장의 유일한 예외(launchd plist 인자에 없음 · 정본·도움말에 「새 뿌리 글을 만듦 — 재첨부는 --reattach」 표기).
- `--reattach rN`(N≥1 · `--date` 필수): 그날 상태가 `done` 이거나 채널에 뿌리 글 표식이 있어야 함(없으면 raise — 새 뿌리 글 0). 상태 칸 `revs.rN = {phase, ts}` · 단계 `posting → posted → pdf_done → done`(제안서 설계 §3 와 같은 원리). 답글 첫 줄 `*아침 매거진 D 재첨부 rN*` «정확 일치»를 `conversations.replies(root_ts)` 에서 먼저 찾아 있으면 채택(답글 2중 0). `posting`+표식 없음 = ERROR·exit 1(자동 재게시 0). 날짜 레코드의 `phase`/`ts` 는 건드리지 않는다(done skip 그대로).
- 답글 본문: 첫 줄 + 「풀 디테일 PDF 와 쉬운 판 HTML 을 다시 붙였어요 — 위의 앞 PDF 는 요약판이에요」. 옛 PDF 삭제 0.

## §7 오늘 수동 1회 · 내일 적용
1. 랜딩(ops/main-base) 뒤 master 가 `install-magazine.sh`(복사만 · plist 변경 0 → `--load` 불요). 복사 목록에 새 모듈 3~4개 + 템플릿 html 추가.
2. `BYZ_ROOT=<루트> python3 ~/.hermes/scripts/byz_morning_magazine.py --date 2026-10-08 --reattach r1 --no-push` → 출력 `reattached date=2026-10-08 rev=r1 ts=<답글 ts> pdf=<경로> pages=<N> html=<경로>`.
3. master → planner 1줄(PDF 경로 · 페이지 수 · HTML 경로 · 슬랙 답글 ts). 내일 08:00 호는 launchd 가 같은 코드로.

## §8 파일 배치 (200줄·함수 40줄 한도)
| 파일 | 나노 |
|---|---|
| `magazine_collect_detail.py`(D1·D2·D6·D7·부록 — git) · `magazine_collect_decisions.py`(D3 — mbox) · `magazine_collect_gh.py` 에 D5 함수 1개 · `magazine_collect.py` 에 `detail` 칸 조립 1곳 | ① |
| `magazine_render_full.py`(2부 블록) · `magazine_emit.py`(목차 앵커 · `pre` 대신 줄 단위 · CSS) · `magazine_pdf.py`(여러 쪽 · pages) · `magazine_publish.py`(pdf_done · reattach) · `magazine_reattach.py`(rN 상태·답글 찾기 — publish 가 200줄 넘으면) · `byz_morning_magazine.py`(--reattach · html 경로 · 출력 줄) · `install-magazine.sh` 복사 목록 | ② |
| `magazine_eli5.py`(`build(model, notes, cmd) -> str` · 프롬프트·JSON 검사·템플릿 채우기) · `magazine_eli5_template.html` | ③ |

- ②↔③ 접점 = `magazine_eli5.build(model: Model, notes: Notes, cmd: str) -> str`(HTML 문자열 · 실패는 `Eli5Error(RuntimeError)`). ②는 이 이름으로 import 하고 시험에서는 가짜 모듈을 `sys.modules` 에 넣는다. ①↔② 접점 = §3 `detail` 스키마(시험 픽스처를 둘이 같이 씀 — `tests/scripts/_magazine_fakes.py` 에 `DETAIL_FIXTURE` 1개, ①이 만든다 · ②는 같은 모양을 자기 시험에 복사해 쓰고 랜딩 때 하나로).

## §9 시험 목록 (tests/scripts/ · 네트워크 0 · 실 슬랙 0)
1. ① `test_magazine_collect_detail.py` — 임시 git 리포 2 ref: 완성 이동(rename) 카드 1 · 창 밖 카드 제외 · 같은 카드 두 ref → 앞 ref · OPS-VERDICTS 절 추가 → 그 절 전문 · REQUEST-LEDGER 닫힘/열림 구분 · DA 마지막 줄 HOLD 만 · NANO-LEDGER 닫힘 줄 · 없는 ref → MagazineError.
2. ① `test_magazine_collect_decisions.py` — 판정 번호 쪽지 처음 것 · relay 파일 있음/없음 · 되돌림 줄 추출/「원문에 되돌림 없음」 · planner 아닌 발신 제외.
3. ② `test_magazine_render_full.py` — 2부 7절 순서 · 빈 절 「없어요」 · detail 없음 → RenderError · 긴 본문 줄 수 보존(입력 줄 수 = 출력 줄 수) · 각주표 1개(맨 끝).
4. ② `test_magazine_pdf.py` 보강 — 여러 쪽(긴 html → pages ≥ 2) · 한 장 한도 raise 시험은 삭제(정책 변경).
5. ② `test_magazine_publish.py` 보강 — ★장애 주입★: PDF 성공 뒤 HTML 실패 → 재실행은 HTML 만(PDF 2중 0) · HTML 없는 날 pdf_done→done · ★F1: PDF/HTML complete 성공 뒤 응답 유실 → 재실행이 replies 의 정확 제목으로 채택(파일 추가 0) · complete 성공 뒤 pdf_done/done 저장 실패 → 같은 채택 · 원격 표식 없음 + sharing 기록 → 불명 ERROR exit 1 + getUploadURLExternal 호출 0 · --force-file 뒤 새 첨부 1 · 비슷한 제목(rK 다름) 은 채택 안 함★ · reattach: 답글 성공 뒤 응답 유실 → replies 정확 첫 줄 채택(답글 추가 0) · 상태 쓰기 실패 → 같은 채택 · posting+표식 없음 → ERROR exit 1 · 뿌리 글 없는 날 reattach → raise · reattach 가 날짜 레코드 phase/ts 불변.
6. ② `test_magazine_cli.py` 보강 — eli5 실패 주입 → 뿌리 글에 경고 줄(원인 중화) + PDF 근거 절에 같은 줄 + PDF 발행 계속 + ERROR 로그 · reattach 에서 eli5 실패 → 답글·새 PDF 에 경고 · ★F2: `--reattach r1 --force` · `--reattach r1 --force-root` → exit 2 + 뿌리 글·답글·파일 호출 0 · done 날짜 `--reattach r1` 정상 · 같은 r1 이 done 이면 skip · `--force` 단독은 기존 동작 그대로★.
7. ③ `test_magazine_eli5.py` — 가짜 LLM: 정상 JSON → HTML 에 결정 박스 2칸·단위 카드·각주표 끝 · 없는/중복 ref · 허용 밖 아이콘 · LLM 칸의 숫자·sha · 80자 초과 · 차단 단어 · JSON 아님 · 모르는 칸(headline·decided) → 각각 Eli5Error · `<script>` 든 값 → 이스케이프됨 · SKILL.md 없음 → raise · ★F3: 차단 목록을 피한 과장 문장(「이제 걱정 없이 내보내도 돼요」)을 넣어도 결정 박스·제목·상태 칩·증거 칩·원문 줄의 HTML 조각이 모델 값과 바이트 동일(LLM 이 사실 영역을 못 건드림) · 그 문장은 「AI 풀이」 상자 안에만 있음 · 바닥 안내 줄 실재★.
8. 기존 `tests/scripts/test_magazine_*.py` 전부 통과(1부 회귀 0).

## §10 나노 카드 3장 · 모델
| 카드 | 좌석 | 선행 |
|---|---|---|
| `indices/대기/magazine-detail-collect.md` | Sonnet 5.5 | DA APPROVE |
| `indices/대기/magazine-full-render-publish.md` | Sonnet 5.5 | DA APPROVE + proposal-tools 랜딩(upload_file) |
| `indices/대기/magazine-eli5-html.md` | **codex**(`--agent codex` · 시각 작업 = GPT 좌석) | DA APPROVE |
①③은 지금 병행 · ②는 proposal-tools 랜딩 뒤. 통합 순서: ①·③ cherry-pick → ② rebase → 시험 전체 → 수동 1회.

## §11 금지선 · 되돌림
- 이 단위: 원격 삭제 0(옛 PDF 포함) · 새 뿌리 글 0(reattach) · 실 슬랙 시험 0 · launchd 재적재 0(plist 변경 0) · LLM 이 쓴 HTML 직접 게시 0.
- 되돌림: PR revert + `install-magazine.sh` 가 남긴 `~/.hermes/scripts/*.bak-<시각>` 복원. 상태 파일 새 칸(`revs`·`pdf_done`)은 옛 코드가 무시해도 깨지지 않는다(옛 코드는 `phase=="done"` 만 본다 — 단 `pdf_done` 인 날은 옛 코드가 PDF 를 한 번 더 붙인다 · 되돌림 직후 하루만).

## §12 DA 소환 판단
- r1(DA HOLD-1 · DA-magazine-fulldetail-20261008.md): F1 = 파일 제목 원격 표식 + file_id 시도 기록 + 불명 ERROR + `--force-file`(§6) · F2 = `--reattach` 상호배타·첫 분기 + `--force` 단독은 명시 예외(§0·§6) · F3 = 사실 영역 LLM 0 + AI 풀이 상자 구분 + 바닥 안내 줄 · headline·decided 칸 삭제 · «과장 0» 은 사실 영역에만(§0·§5) · 시험 §9 5·6·7 장애 주입 추가. 같은 범위 교정 1회.

- r2(판정 49 재현 · §5-b): 실자료 72단위에서 «전체 아니면 0» 이 매일 실패 → 12개 묶음 · 단위별 보이는 생략 · 전부 실패일 때만 Eli5Error. DA 확인 범위 = §5-b 만.

**소환함(사전검증 1회 · 10분+10분 · 2 HOLD 면 중단)**. 볼 곳 3: ①eli5 실패를 «보이는 실패 + PDF 계속»으로 두는 것이 #0 RULE(조용한 대체 0)과 맞는가 — 앞 설계 요약 실패 계약과 같은 수준인가 ②reattach 의 rN 상태·정확 첫 줄 채택이 «같은 날 뿌리 글 최대 1개 · done skip» 계약을 정말 안 깨는가(옛 `--force` 와 겹침 포함) ③LLM JSON 칸 검사(실재 ref·n · 숫자 금지 · 허용 아이콘)로 «과장 0»이 충분한가.
