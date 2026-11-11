# 인덱스: r1680-ft20-cond15-landing-remainder — 끝: 조건 15 «완성본 전체 착지» 중 r1613 이 범위 밖으로 둔 몫을 닫는다. 다른 Pi checker 가 팩 main 소스↔패키지 대응을 1줄로 확인하고, 문서 정본 판본 sha·패키지 꼴 1줄·원장 착지 대조가 각각 증거 1줄을 가진다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8341 (byz-agents · team:harness-ops)
- 지시: aifp master #3869 ② «r1613 완성 → 남은 몫(설치 등) 판정 · 있으면 카드 초안 1장» (planner #3866 ④)
- 판정 1줄: 남은 몫 있음 — r1613 은 패키지 도구(build·check)와 착지 뒤 master 자체 check(ⓖ)까지다. 조건 15 정의의 «문서·원장·BTS·Git 2.0 착지»와 ROUTE 게이트 ①의 «독립 checker 1줄»은 r1613 범위 밖에 남았다. 설치는 조건 16(r1614) 몫이라 여기 넣지 않는다
- 근거(읽기만 · 2026-11-11): BYZ ROUTE-ft20-complete-land-migrate-20261109.md(dcd10ad67c) :32 «15 · 문서·원장·BTS·Git·패키지 2.0 착지 · 랜딩 PR ⑤» · :47 게이트 ① 닫는 증거 «PR ⑤ 착지 sha + 독립 checker «소스↔패키지 대응 일치» 1줄 (게이지 15 닫힘)» · :62 ⓪ 문서 정본 = PLAN·core.html·slack.html 최종판(컨펌 판본 sha) · TABLE-ft20-conditions-12-18-done-arch286-20261111.md(7c540ec133) 15행 ② «패키지·manifest(PR⑤) 0 · 문서·원장·BTS·Git 2.0 착지 0» · r1613 카드(fd8647481c) §범위 밖 «문서·원장 정본 착지 묶음(착지 h 때 master)» · 머리 «패키지 꼴 확정은 착지 뒤 PLAN 1줄 = master» · §상태 ⓖ 실행자 = master-pi#192(같은 집행 좌석 · 독립 아님)
- 원인 1줄: r1613 은 조건 15 의 «패키지» 칸만 닫았다. 같은 조건의 문서·원장 착지와 독립 확인은 담당 카드가 없다
- 실사건: 없음 — 빈 칸 발견(조건 표 15행 ② 대조)
- 기준값: 독립 checker 줄 0 · PLAN 의 패키지 꼴 줄 0(PLAN 최신 ed9d9622b3 에서 «PACKAGE»·«ft2-<» 검색 0건) · 문서 정본 판본 sha 기록 0(조건 표 15행) · 컨펌 판본 = 요약 62a9dd86 → BYZ main 착지 661bf877(planner 판정 4144 «승인 대상 = 컨펌 요약 62a9dd86(정본 착지 661bf877)» · VERDICTS-planner-225-20261104.md:103) · 컨펌 뒤 origin/main 939526f827 까지 변경 = PLAN 22커밋 · core.html 4 · slack.html 5(카드 r1483·r1561·r1564·r1566·r1567·r1572·r1599·r1622·r1625·r1666)
- 중복 확인: r1613(완성 · 패키지 도구) · r1631(완성 · manifest) · r1614(진행 · 설치 = 조건 16) · r1666(완성 · PLAN 스케줄 절 · 조건 15 아님) → 같은 카드 0
- 끝: checker 줄 1 + 문서 정본 판본 sha 줄 1 + PLAN 패키지 꼴 1줄 + 원장 착지 대조 줄 1 → 조건 표 15행 닫힘 1줄(master)
- 묶음 판정: 1건 — 모두 조건 15 닫힘 증거 한 묶음이고 코드 변경 0
- 제안서: 없음 — 새 안 0 · 이미 정한 조건의 남은 증거 묶음
- 상태: 완성 · 2026-11-12 00:11 · aifp-ft-arch-pi#1
- 설치: 없음 — 증거·문서 줄만(설치·되돌림 = 조건 16 r1614)
- 선행: 조건 12·13·14 카드 완성(r1607~r1612 · fd8647481c 트리 완성 폴더 실측) · r1613 착지 a8028bd7
- 시험 입력: 팩 main 착지 sha 의 detached 사본 · tmp 출력 폴더 · 실 설치·실 데이터 쓰기 0 · 사례 70초 · sleep 0
- 수용 기준:
  - ⓐ 독립 checker: master 가 아닌 다른 Pi 좌석이 팩 main 최신 sha 사본에서 `package.py build` → `package.py check` = SAME rc0 · PACKAGE.json source.sha = 그 sha · 1줄(좌석 이름·sha·files·manifest_sha256·초)
  - ⓑ 문서 정본: PLAN·core.html·slack.html 3파일을 조건 표 15행에 두 칸으로 적는다 = «컨펌 기준 62a9dd86(main 착지 661bf877 · 판정 4144) · 착지 판본 ed9d9622b3(BYZ origin/main · r1666 PLAN 정본 반입 + 오빠 결정 3 반영 · blob PLAN 4695a0115c · core.html 6f4b563048 · slack.html a9ca423455)» (harness arch#298 답 · aifp #3881·#3883 · blob 3개 = ed9d9622b3 트리 실측 일치) · 착지 때 origin/main 의 3파일 blob 이 위 3개와 다르면 «판정 불가» · 못 찾으면 «판정 불가» 1줄 + [HIL](지어내기 0)
  - ⓒ 패키지 꼴: PLAN 에 r1613 패키지 꼴(ft2-<버전>/ · MANIFEST.json · PACKAGE.json 6칸) 1줄 · 문면 = r1613 카드 머리 «패키지 꼴» 줄 복붙
  - ⓓ 원장·BTS·Git 착지 대조: 조건 15 착지 묶음의 PR·sha 목록 1표(PR ⑤ = a8028bd7 포함) · BTS = BYZ Triangulation Spiral(로그·스펙·코드 3자 대조 + 나선 수렴 하네스 · BYZ CLAUDE.md:216 · .claude/skills/bts/SKILL.md · PLAN :751 «문서·원장·BTS 정합») → 칸 = 착지 묶음의 BTS 회차 기록이 착지 sha 와 맞는지 1줄 · 단일 BTS 장부 파일 없음(BTS = 방법) · 2.0 기록 꼴 실례 = BYZ design/harness/research/ft-2.0/role-integration/results/ws-artifacts/bts.jsonl (harness arch#298 답 · origin/main 실재 확인) · BTS = BYZ Triangulation Spiral 스킬 착지(.claude/skills/bts) · 근거 오빠 Slack 1794388201.094249
  - ⓔ 닫힘: ⓐ~ⓓ 4줄이 다 있을 때만 조건 표 15행 «닫힘» · 하나라도 «판정 불가»면 미완 유지(준비를 완료로 세지 않음)
- 변이: 없음 — 코드 0 · 대신 ⓐ 에서 패키지 1파일을 바꾼 사본으로 check rc1 «내용 다름 1» 을 1회 같이 본다(checker 가 실제로 본다는 확인)
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 2(문서 착지·PR = master 집행) · 하드 룰 20 · 하드 룰 22
- 팩 파일 owner: harness 팀(ft2/tools/package.py 읽기만) · 문서 정본 owner = harness arch · aifp 는 이 카드에서 쓰기 0
- 인수 조건: ① 이 카드 lint OK 판 + base_sha · ② ⓑ·ⓓ 의 남은 [확인 필요] 1칸(ⓓ 착지 장부 경로)은 harness master 결정 뒤 착수 · ⓑ 는 harness arch#298 답으로 채움 · ③ checker 좌석 = master·이 카드 작성자 아닌 Pi · ④ 문서 커밋·PR = master
- 대상(읽기 = checker · 팩 1곳): feature-pack/fable-team/ft2/tools/package.py · ★쓰기 금지★ 팩 코드 · 라이브 설치 · 실 데이터 루트
- 크기: 증거 줄 4 · 코드 0
- 정본 영향 없음: aifp 정본 변경 0 — 바뀐 정본은 BYZ 문서뿐이고 harness 가 반입을 끝냈다(PLAN ⓒ 1줄 = BYZ main 6a6ea4462b · 조건 표 15행·§1.1 = BYZ ops/main-base 69940c953850d4d2caadd78bb8603872062bbbdf) · 원래 줄 «정본 영향 있음: PLAN 1줄(ⓒ) · 조건 표 15행 1줄 = master 집행»
- 배정: 대기(선행 · 2026-11-11T18:20)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」 · 골의 축: 4(하네스 운영 정리 — 끝난 일은 남지 않고, 좌석은 정한 순서로 열린다) · 이 카드의 증거 = ⓐ~ⓓ 4줄 + 조건 표 15행 닫힘 1줄.

## 배경 (한 단락)
조건 15 는 «완성본 전체 착지» 이다. 정의에는 패키지와 함께 문서·원장·BTS·Git 의 2.0 착지가 들어 있다. r1613 은 패키지 도구를 만들고 착지 뒤 master 가 한 번 확인했다. 그러나 게이트는 독립 checker 1줄을 요구하고, 문서·원장 착지는 r1613 이 범위 밖으로 넘겼다. 이 카드는 그 남은 증거를 한 묶음으로 모은다.

## 고칠 안 1개
- 코드 변경 없이 조건 15 닫힘 증거 4줄(독립 check · 문서 판본 sha · PLAN 패키지 꼴 · 착지 대조)을 채운다.

## 구현 범위 (checker 1 · master 집행)
- checker: `feature-pack/fable-team/ft2/tools/package.py` 를 팩 main 사본에서 build·check 1회(ⓐ) · 결과 1줄 arch 에
- master: ⓑ·ⓒ·ⓓ 줄 커밋 · 조건 표 15행 갱신

## 범위 밖
- 설치·되돌림(r1614 · 조건 16) · 패키지 도구 수정 · 구 writer 차단(r1675 · 조건 18)

## 완료 조건
- ⓐ~ⓔ

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| 다른 좌석이 소스↔패키지 대응을 본다 | ⓐ |
| 문서 정본 판본이 sha 로 남는다 | ⓑ |
| 패키지 꼴이 PLAN 에 있다 | ⓒ |
| 착지 묶음이 표로 남는다 | ⓓ |
| 4줄이 다 있어야 닫힌다 | ⓔ |

## 상태
- 2026-11-11 · byz-aifp-arch-pi#0 초안(aifp #3869 ②) · 대기
- 2026-11-11 ⓐ 끝 — 독립 checker aifp-ft-nano-r1675-ft20-cond18-old-writer-block-switc#0(master·작성자 아님) · 팩 origin/main 20b2beff4f8ea48c9e2082fe9a7eb63a3a0d6496 detached 사본 · package.py build → check = SAME rc0 · files=132 · manifest_sha256=9084568a08399e301e390d5f8d6ed45b4ba4397707f083c0cc19ee8598c5c31d · PACKAGE.json source.sha = 20b2beff…6496 · 반례(패키지 tools/package.py 1줄 추가 사본) check rc1 «내용 다름 1» · 4초 (aifp 4026·4027) · arch 재현 build 같은 manifest_sha256(aifp 4028)
- 2026-11-11 정본 자리(aifp-ft-arch-pi#1 실측 · aifp 4029) — ⓑⓒⓓ·조건 표 15행 = BYZ 몫(문서 정본 owner = harness · 이 카드 aifp 쓰기 0 그대로): PLAN·core.html·slack.html = BYZ origin/main 43d4810080 design/harness/research/ft-2.0/ (blob 4695a0115c·6f4b563048·a9ca423455 = ed9d9622b3 판 그대로) · 조건 표 TABLE-ft20-conditions-12-18-done-arch286-20261111.md(7c540ec133)·ROUTE(dcd10ad67c)·r1607~r1613 카드 = BYZ main 에 없음(가지에만) → 15행·ⓓ 표를 쓸 자리 = harness master 결정 · BTS 칸 = 판정 불가(BYZ main bts.jsonl 1줄 = r1510 · 착지 sha a8028bd7·ffa99a93 언급 0)
- 2026-11-12 ⓔ 판정 = 닫힘(aifp-ft-arch-pi#1 · aifp 4054 · 읽기만) — BYZ ops/main-base 1064aa8951 TABLE §1.1 에 ⓐ~ⓓ 실재: ⓐ 팩 20b2beff SAME(팩 ft2 는 f522d309 까지 변경 0) · ⓑ PLAN c1a61a3a0d(= ed9d9622b3 + ⓒ 2줄)·core 6f4b563048·slack a9ca423455 = BYZ origin/main 6a6ea4462b 실측 · ⓒ BYZ main 6a6ea4462b(PR #8380 · PLAN :37) · ⓓ Git ffa99a93·a8028bd7(팩 main 조상) · 원장 224a3b00 · BTS ops/main-base 84ebc23024 bts-cond15.jsonl 1행(JSON 1줄 · 초안과 바이트 같음) → 남은 것 = BYZ TABLE 15행·ⓔ 줄 반입(harness) → 그 sha 오면 이 카드 완성 이동
- 2026-11-12 00:08 — 대기→진행 · 좌석 aifp-ft-arch-pi#1
- 2026-11-12 00:11 — 진행→완성 · 좌석 aifp-ft-arch-pi#1 · DA /Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm/bodies/4061.txt#§1
