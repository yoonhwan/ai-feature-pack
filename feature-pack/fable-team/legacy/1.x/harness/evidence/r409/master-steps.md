# r409 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r409-stall-a-prereq-line-parse-and-card-` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `81afaacf`(origin/main · 1.1.9). 파일 겹침: r407(harness-freeze-gate)·r408 과 0 — 이 가지 = `ft_stall_detect.py` · `ft_stall_scan.py`(bin·kit 둘 다) + `tests/scripts/test_ft_stall_scan.py`.
   ★버전 번호는 이 가지에 안 넣었다★ — r407 가지가 이미 1.1.10 을 쓴다. 착지 순서대로 다음 번호(CHANGES 머리·manifest 둘 다)를 master 가 붙인다.
2. 되돌림 준비(설치 전): 라이브 bin 의 `ft_stall_detect.py` · `ft_stall_scan.py` 2 파일 `cp -p … .bak-r409`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 키트 2 파일 `cmp <키트>/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 닫는 증거: 다음 v65 `[stall a]` 쪽지 원문 1회 — `대기 카드 N장(<이름들>) · 선행 미판정 M장 제외` 꼴 · «선행 있음» 카드(예 `M5-owner-stale-exhausted-closing-event` = `선행: M5-owner-stale-cas-retry-unbounded 착지`)가 이름 목록에 없음 → 카드 `- 실사건:` 줄.
   (또는 같은 꼴 임시 리포 재현 = 새 시험 `test_a_r409_card_input_set`.)

## 관측 (실행→나온 것 · 원문 test.txt)
- 시험 `test_ft_stall_scan.py`(새 절 ⓐ~ⓓ + 카드 시험 입력 1 · 기존 절 그대로) · `test_ft_stall_news_cell.py` · `test_ft_penalty.py` = 48 passed rc=0.
- 실제 v65 대기 110장(v6-realtime-live · lint 스텁) → ready 100 · 선행 실재 3 · 미판정 7. v65 110271 의 «선행 있음» 카드 `M5-owner-stale-exhausted-closing-event` 는 이제 미판정(제외) — 옛 코드는 ready 로 셌다.
- 하네스 대기 176장 → ready 100 · 선행 실재 16 · 미판정 60.

## 판단 (DA⑥ 기록용 질문 3)
- ① 이름 매칭 = 대기/·진행/ 폴더 목록 stem 집합과 «정확 일치»(대소문자 그대로 — macOS 대소문자 무시 파일시스템이라 exists() 대신 목록) · 토큰 경계 `[\w.\-]+` 라 `C-extra` 는 `C` 에 안 걸린다 · 자기 이름 제외. 시험 ⓐ.
- ② 미판정 → ready 경로 0: 선행 줄에 경로 꼴·열린 카드 이름을 뺀 글자가 남으면 unknown, 남는 글자가 없을 때만 ready(`없음` 시작 · 끝난 카드 경로만 · 줄 없음). 여러 줄이면 blocked > unknown > ready.
- ③ 알림 길이: 이름 5개 + «+N» · 시험 ⓒ 에서 700자 미만 확인.
- lint 실패 카드는 `blocked:(lint)` — 미판정 수에 안 넣는다(선행 판정이 아니다 · 기존 동작 그대로).

## 끝선 뒤 (범위 밖 · 손 0)
- 미판정 7(v65)·60(하네스) 은 «선행: r405 착지» 처럼 끝난 카드 이름 + 조건 글자 꼴이 대부분 — 완성/ 실재로 충족 처리하려면 «착지·뒤·랜딩» 같은 연결어 규칙이 필요하다(카드 범위 밖 · 조용한 통과 위험 → DA 판단).
