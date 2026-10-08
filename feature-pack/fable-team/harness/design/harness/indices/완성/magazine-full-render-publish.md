# 인덱스: 아침 매거진 풀 디테일 ② 렌더·여러 쪽 PDF·슬랙 2파일·--reattach (판정 354)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: #885 추가 단위 → 판정 354(planner#8 → master#12 발주 · 설계 design/harness/DESIGN-magazine-full-detail-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래) + proposal-tools 랜딩(magazine_slack.upload_file · find_first_line 이 ops/main-base 에 있어야 함) — base 는 그 뒤로 잡는다
- 시험 입력: detail 픽스처(설계 §3 모양) · 가짜 Slack(tests/scripts/_magazine_fakes.py) · 가짜 eli5 모듈(sys.modules 주입) — 실 슬랙 0
- 기준값: PDF 한 장(높이 한도 18000px raise) · 상태 posting→posted→done · 재발행은 --force(새 뿌리 글)뿐

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 6-b(오빠 피드백 반영) + 원문 7(나노 3석 병행). 핵심 한 줄: 판정 354 오빠 원문 「하네스마스터 아침 매거진 추가 요청 — 완성 pdf 를 풀디테일로」 + 보강(#61131) 「①풀 디테일 PDF + ②eli5 HTML」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진 PDF 를 «1부 요약판(지금 render() 그대로) + 2부 풀 디테일 7절 + 부록 + 각주표(맨 끝 하나)» 로 바꾸고(설계 §1), 한 장 PDF 를 여러 쪽 A4(바닥글 쪽/전체 · 쪽 수 상한 없음 · 한 장 높이 한도 코드는 삭제)로 바꾼다(§4). 슬랙은 뿌리 글 3줄 그대로 + 스레드에 PDF·eli5 HTML 2파일 — 상태기계에 pdf_done 단계를 끼운다(posted → pdf_done → done · done skip 불변 · HTML 없는 날은 pdf_done→done). eli5 HTML 은 ③나노의 `magazine_eli5.build(model, notes, cmd) -> str`(실패 = Eli5Error)를 부르고, 실패하면 «보이는 실패»(ERROR 로그 + 뿌리 글 마지막 줄 경고 + PDF 근거 절 같은 줄)로 PDF 발행은 계속한다(§5). 이미 done 인 날 재발행은 새 모드 `--reattach rN` — 새 뿌리 글 0, 그 스레드에 답글(첫 줄 `*아침 매거진 D 재첨부 rN*` 정확 일치) + 2파일, 상태 revs.rN 단계 posting→posted→pdf_done→done, 쓰기 전 replies 정확 첫 줄 채택, posting+표식 없음 = ERROR exit 1, 날짜 레코드 phase/ts 불변(§6). ★DA r1 교정★: 파일마다 업로드 전 replies 의 정확한 파일 제목(`아침 매거진 D PDF rK`·`… HTML rK`)으로 채택 → 없으면 file_id 시도 기록(complete 전) → 공유 · 표식 없음+시도 기록 = 불명 ERROR exit 1(새 file_id 0 · 같은 file_id complete 재호출 0) · 탈출구 `--force-file <pdf|html>`(F1). `--reattach` 는 `--force`·`--force-root` 와 argparse 상호배타(exit 2 · 원격 호출 0) · run() 첫 분기 · `--force` 단독은 «수동 새 뿌리 글» 명시 예외로 기존 동작 유지(F2). ★DA r1 구현 조건★: file_id 시도 기록은 업로드 helper «안»에서 complete 호출 전에 쓴다 · `set_phase`(magazine_publish.py:57)는 지금 날짜 레코드를 통째로 덮어쓰므로 단계를 바꿀 때 `files`·`revs` 칸을 보존하게 고친다(안 그러면 다음 단계 기록이 시도 기록을 지워 F1 이 다시 열린다 — 시험으로 고정). eli5 는 PDF 렌더 전에 돌려 실패 문구를 PDF 근거 절·뿌리 글(답글)에 넣는다. 옛 PDF 삭제 0.

## 사전검증
- 소환: 예
- DA: design/harness/DA-magazine-fulldetail-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/magazine_pdf.py:4` MAX_HEIGHT_PX · `:28` page.pdf 한 장(height=본문 · page_ranges="1").
- `scripts/harness-install/slack-mirror/magazine_publish.py:71` — `--force` 면 find_root 를 건너뛰고 새 뿌리 글(재발행에 쓰면 뿌리 글 2개) · `:84` publish_day 단계 우선순위.
- `scripts/harness-install/slack-mirror/magazine_render.py:151` render() — 1부로 그대로 재사용 · scrub 규칙(자유 문장 #N → N번) 유지.
- `scripts/harness-install/slack-mirror/byz_morning_magazine.py:85` make_files · `:116` run — html 경로·pages 출력·--reattach 분기 지점.
- `scripts/harness-install/slack-mirror/install-magazine.sh:23` REQUIRED 복사 목록.

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_render_full.py` 신규 · `scripts/harness-install/slack-mirror/magazine_emit.py`(목차 앵커 · 긴 본문 줄 단위 · 여러 쪽 CSS) · `scripts/harness-install/slack-mirror/magazine_pdf.py`(여러 쪽 · timeout 120초 · pages 세기).
2. `scripts/harness-install/slack-mirror/magazine_publish.py`(pdf_done · html 업로드) · `scripts/harness-install/slack-mirror/magazine_reattach.py` 신규(rN 상태 · replies 정확 첫 줄) · `scripts/harness-install/slack-mirror/magazine_slack.py`(뿌리 글 안내 줄 · replies 찾기 함수 — proposal-tools 에 같은 것이 있으면 재사용) · `scripts/harness-install/slack-mirror/byz_morning_magazine.py`(--reattach · html · 출력 줄) · `scripts/harness-install/slack-mirror/install-magazine.sh`(새 모듈·템플릿 복사).
3. 시험 `tests/scripts/test_magazine_render_full.py` 신규 · `tests/scripts/test_magazine_pdf.py`·`tests/scripts/test_magazine_publish.py`·`tests/scripts/test_magazine_cli.py` 보강(설계 §9 3~6 · ★장애 주입 전부★).

커밋은 자기 브랜치, **push 금지**. **금지**: 수집 모듈(①)·eli5 모듈(③) 수정 · 실 슬랙 게시 · ~/.hermes 설치 · plist 변경 · 옛 PDF 삭제 경로.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_*.py -q` rc=0 · `bash tests/harness/test_magazine_plist.sh` rc=0.
- 장애 주입 출력 줄 복붙: PDF 뒤 HTML 실패 재실행 「PDF 추가 0」 · 파일 complete 뒤 응답 유실·단계 저장 실패 「파일 추가 0」 2종 · 파일 불명 「ERROR · getUploadURL 0」 1종 · `--reattach --force`/`--force-root` 「exit 2 · 호출 0」 2종 · reattach 「답글 추가 0」 2종(응답 유실 · 상태 쓰기 실패) · 「불명 ERROR」 1종 · 「뿌리 글 없음 raise」 1종 · reattach 뒤 날짜 레코드 phase/ts 불변.
- 픽스처 dry-run 1회: `--model-file <detail 픽스처 모델> --dry-run` → PDF pages ≥ 2 · 뿌리 글 텍스트 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f51e3c53d5e2d50b21192352bbbf369037ea85c0 (카드 작성 시점 · proposal-tools 랜딩 뒤 spawn 때 갱신)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#10 · 판정 354). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 슬랙 키트 렌더·발행 모듈·시험만이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:35 — 대기→진행 · 좌석 byz-harness-nano-magazine-full-render-publish#0
- 2026-10-08 — 완료 독립 검증 (arch#10 · 판정서 §50 초안) — 나노 aeea2736ea(반송 r1: md 외부 본문 인용 · eli5 실패 안내 줄): 시험 125 passed · 실자료 PDF 228쪽 · md 2단 제목 14개 전부 우리 절.
세트: aeea2736ea112961811e5be840bd531e09304b06 · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0
- 2026-10-08 09:57 — 진행→완성 · 좌석 byz-harness-nano-magazine-full-render-publish#0 · DA design/harness/OPS-VERDICTS-20261006.md#§50
