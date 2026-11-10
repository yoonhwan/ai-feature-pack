# R725 증거 — «한 팀 폴더 .md 만인 PR 은 오빠 승인 h 없이 착지»

카드: r725-doc-only-pr-lands-without-approve-h · 범위 = master #140107 확정(모든 팀 폴더 design/teams/<팀>/ .md · 2576 포함)

## 판정 1곳
- `bin/ft_doc_exempt.py` (신규 · 키트 사본 = `kit/fable-team/bin/ft_doc_exempt.py`)
  - doc-exempt: ①좌석 = 그 팀 master 또는 planner `_master`(명부 · ft-name-lint) ②base 가 head 의 조상
    ③한 팀 폴더 «직속» *.md(정본·승인근거 이름 GOAL-/GUIDE-/SEATBELT/VERDICTS-/AUTONOMY-/BOARD/README 제외)
    ④추가·수정만 ⑤모드 100644 만 · 바이너리 0 ⑥NFC·제어문자·대소문자 그대로
  - md-files: diff 전부 *.md (ft-proxy-decide docs-push 의 `design/x.py` 구멍 막기)
  - FT_DOC_EXEMPT=0 → 예외 꺼짐

## 두 문이 같은 판정을 부른다
- `ft-merge-land.sh`: 승인 값(`--approve-sha`)이 «없을 때만» 판정 · fetch·head 확인·게이트 «뒤» · 실패 = 면제 0 · squash 그대로
- `autonomy-merge-guard.sh`: `ok(sha)` 안에서 같은 판정을 승인으로 사용 — 판정 실패·예외·모듈 없음 = deny(fail-open 0)
- `ft-proxy-decide.sh` docs-push: 같은 모듈 `--mode md-files`
- 기록: `autonomy.log` `doc-exempt <sha> team=<팀> files=<N> by=<좌석>` · 실패 `doc-exempt-reject <sha> by=<좌석>` (ft-autonomy 위변조 판정에 형식 허용)

## 파일
- 01-red-old-land.txt — 옛 판(origin/main) 이 문서 전용 PR 을 REJECT 하던 원문(빨강)
- 02-tests.txt — tests/test_doc_exempt_r725.sh 전문(ⓐ~ⓘ · 51 PASS · ALL PASS)
- 03-kit-bin-cmp.txt — 키트 ↔ harness/bin cmp0 · 줄 수 상한(merge-land 120 · autonomy 200)
- 04-scope-change.txt — 범위 확정 전후 차이(planner 직속 HANDOFF/CLOSEOUT → 모든 팀 폴더 .md)
- 05-regression.txt — 기존 계약 시험 10종 rc0 · 선행 실패 4종은 기준선(origin/main)에서도 동일
