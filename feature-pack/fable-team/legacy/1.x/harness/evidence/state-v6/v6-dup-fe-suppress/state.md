---
slug: v6-dup-fe-suppress
pipeline: standard
pattern: P-BUG
da: loop
stage: 4
status: running
da_round: 6
brains: {architect: claude-fable-5/high, da: codex-5.6-sol/high, implementer: claude-opus-4-8/high, checker: claude-sonnet-4-6/medium}
design: .claude/plans/v6-dup-fe-suppress-integrated-design.md
da_records: state/v6-dup-fe-suppress/da-round1~5.md
orch_channel: V6_HELM#7(pane %105), me=FB_Master#66
updated: 2026-07-12T12:5x
---

## ★핵심원칙 재강조 (오빠 직접지시, 07-12 12:5x, V6_HELM#7→V6_HELM#8 릴레이) — 4조, 최우선·항상 준수
전파: v6-rt-ux-issue-ledger.md 동일 박제 + FB_Master#67/Tester#9 전파 완료.
1. **빠른 반복** — 작은 수정 1개 단위 즉시 회전. 설계/DA 대기시간엔 검증파이프·다음 항목 선준비. 빅뱅·장시간 무회전 금지.
2. **빠른 확인** — 수정 랜딩 즉시 poller/로그로 확인. 확인 지연 금지.
3. **빠른 수정** — 확인에서 발견된 결함은 그 자리에서 수술적 수정. 백로그로 미루지 말 것.
4. **★로스트 금지** — 확인결과·발견은 확인된 그 순간 원장+state.md에 기록. **"기록 없는 확인=확인 안 한 것"**. 워커 확인분도 오케가 회수 즉시 기록.

# 문제 ① — DUP+shrink 통합 FE 수정 (v5-fuzzy-guard.ts S1+S2)

**골**: S1(exact)+S2(fuzzy0.85) 통합 랜딩. ★핵심난제=S2 좌/우 laterality 단음절 안전가드(방향반전 억제금지 vs STT변이 억제허용 구분).
**방법론(오빠 지시)**: 빅뱅금지·문제하나씩. architect→DA(codex)승인→구현→체커3 교차검증+poller증거→PASS→원장갱신+마일스톤 보고. 라운드 유연(실질진전 없으면 에스컬레이션).

## 원장
| 워커 | 브레인 | 상태 | 비고 |
|------|--------|------|------|
| architect#1 (S2 laterality 재설계) | opus-4-8 | ✅ 완료(06:3x) | §2.8 CONTRAST_FAMILIES 의미축 폐집합+contrastAsymmetric 게이트⑧+S2a/S2b 스테이징+R8 |
| architect#2 (보강 리뷰) | fable-5 | ✅ 완료(09:45, 2회 stall이나 파일편집 전부 랜딩) | §2.9 6문 판정+FINAL:구현착수가능. R8 P1승격(6번↔7번 jamo0.75+단음절 좌/우 = 현존 라이브 결함). 순서: S2a→R8-BE→S2b |
| ft-da (codex-5.6-sol high) | codex | ✅ r6 완료 | S2a=APPROVE w/COND(밀리그램/그램 longest-match tokenization+경계테스트)·R8-BE=APPROVE(P1독립)·S2b=CONDITIONAL(§3.1 5게이트 green 후 flip). blocker 3종 전부 해소 |
| ft-implementer (opus-4-8) | — | ✅ S2a+R8-BE 완료 | S2a=23a5ff28+4bac9ae4+af998a25 / R8-BE=4dc26933(Master 재실측 후 단일창구 커밋: ruff clean·294pass·FE parity 일치) |
| checker×3 (교차검증) | sonnet-4-6 | 대기 | 구현 후 adversarial 3자 |

## 완료조건
S1+S2 랜딩 + jest green + poller 라이브증거(DUP transient 0 + laterality 반전쌍 미억제 + 이중부정 미억제) + 체커3 PASS → 원장(v6-rt-ux-issue-ledger.md) 갱신 + V6_HELM#7 보고.

## 주간자율 확장 스코프 (오빠 지시, V6_HELM#7 릴레이 06:2x)
로스터 확정: orch/architect=fable-5, DA=codex-5.6-sol(high), impl=opus-4-8, 체커·테스터=기존.
**전체 골 = 원장(v6-rt-ux-issue-ledger.md) 남은 문제리스트 전체 완성** (순서):
1. ①DUP+shrink 통합 FE (현재 — architect#1 opus 완료대기→fable5 보강)
2. ②settle70s 4조합(M1/M3/M4) 재검증
3. ③polish.result FE핸들러 부재
4. ④LST설정 공용화 (domains/conversation/ 이전+lecture/note 배선)
5. 진행 중 발견 UX 보완점도 즉시 해결(미루기 금지)
제외(오빠 게이트): lecture V4→V6 전환, PR머지, push.
루프: 기획→DA→적용→테스트→poller확인→수정→재확인, 짧고 빠르게. 항목마다 완전마감. 마일스톤마다 V6_HELM#7 보고.

## ★운영 원칙 박제 (오빠 직지시, 07-12 10:0x)
**기본 문제 기획·해결 = architect↔DA approve loop 베이스, "완전한 해결(APPROVE)" 기준.**
- DA CHANGES_REQUESTED → 지적을 architect(fable-5)에 자동 회부 → 설계 보강 → DA 재심사 → APPROVE까지 왕복(오케는 중계만, 매 라운드 HIL 문의 없음. 단 실질진전 없는 라운드 반복 시 에스컬레이션).
- APPROVE된 설계 = 기준선 → 이를 테스터·체커 컨텍스트로 BTS 반복(구현→테스트→poller증거→수술수정→재확인).

## orch 강조 3조 (V6_HELM#7, 10:0x — 랜딩 규율)
1. **R8-BE = P1 지체금지**: S2a(inert) 랜딩 직후 즉시 발화갭 확인→독립커밋. (6번↔7번 치아번호 jamo0.75 + 단음절 좌/우 = 현존 라이브 상태손실 결함)
2. **스테이지=1커밋 + DA조건 이행 + 랜딩마다 Tester#8 poller A/B**(baseline=/tmp/dupfix2_20260712_052149.jsonl) 즉시 회전. S2a 조건=밀리그램/그램 longest-match tokenization+경계 유닛테스트.
3. **S2b flip = §3.1 5게이트 전건 green 확인 전 절대 금지** (Tier-A recross=0 / EV1~5 green / anti-pairs unsuppressed / T-1~T-3 green / DA r6 approve).

## ★BTS 증거 사이클 (오빠 원칙 재확인, 10:2x — "수정하고 봐야 뭐가 됐는지 안다")
**매 수정 = baseline 증거 → 규명 → 기획보강 → 랜딩 → 동일조건 재측정(A/B) → 효과실측 확인까지가 한 단위.**
- **S2a baseline(랜딩 前, 확보완료)**: `/tmp/dupfix2_20260712_052149.jsonl` — DUP transient **8.32s/26프레임**("오늘은임플란트"2회 동시노출, 05:22:09~17) + final self-heal. 4조합 1차(M2클린/M1·M3·M4 아티팩트). 이 수치가 S2a 효과 판정의 비교선.
- **S2a 랜딩 後 A/B(예정)**: 동일 덴탈 스크립트+trusted press, 보강 poller(settle+CAPTURE_END reason=settled 필수)로 재캡처 → 판정: ①DUP 노출 프레임/지속시간 8.32s 대비 감소량 ②suppress_fuzzy decision 발동 기록 ③laterality/이중부정 반전쌍 스크립트 미억제 ④final 원문 무손실. 체커3(독립 교차) = poller증거/코드diff/worker.log 각각 담당.
- R8-BE·S2b도 동일 사이클 반복. 증거 없이 "됐다" 선언 금지.

## ★single-writer 규율 (orch 지시, 재발방지 — 10:3x 박제)
**커밋은 FB_Master#66 단일창구.** 서브에이전트(implementer 포함)는 git commit 직접 실행 금지 — 구현·검증까지만 하고 diff 상태로 보고, 커밋은 Master가 검증 후 실행. (배경: 23a5ff28/4bac9ae4 커밋 주체 불명 사건 — 같은 세션 서브에이전트 이중커밋 시그니처. 4bac9ae4는 §2.8.3 정합 규율커밋으로 수용, jest green 확인됨(monotonic 12/12 pass).)

## 크로스체크 프로토콜 (10:3x 합의)
V6_HELM#7 prefix 메시지 중 일부는 오빠 직접 입력일 수 있음(PR#435 방침이 그 사례 — 사실검증 통과). **파괴적/게이트성 지시(revert/reset/브랜치조작/머지/스코프변경)는 실행 전 V6_HELM#7에 크로스체크 요청** 후 진행.

## 증류경계 스냅샷 (11:2x, ctx 450k 경계)
- **랜딩 커밋(HEAD→과거)**: 003967f3(poller 다중인스턴스 가드) ← af998a25(동시작업자: Gap3 judge 프리미티브) ← 4bac9ae4(단조성 하네스) ← 23a5ff28(S2a 본체) ← badb962b(poller settle+CAPTURE_END) ← 8dcf073e(S0 W2게이트)
- **poller 버그 해소**: 스테일 무한모드 2개(pid 71795/81462) drain 경쟁이 settle 기아·캡처 부분화 원인 — kill+가드 커밋. headless 의혹→9333 본체 headed 확인+탭 전면화.
- **체커3**: 코드축 10/10 PASS 완료 / poller축·log축 = A/B 캡처 후 스폰 대기.
- **진행중**: Tester#8 A/B 재실행(유효조건: 가드+headed+CAPTURE_END settled) — 세션 v5_7b517dd1 press 진행 로그실체 확인됨. 판정 4축: DUP vs baseline 8.32s / suppress_fuzzy 발동 / 반전쌍(laterality·이중부정) 미억제 / final 무손실.
- **다음**: A/B 4축 판정 → 3축 합산 → 원장(v6-rt-ux-issue-ledger.md) 갱신+orch 보고 → R8-BE(assemble.py 게이트⑧ 미러, 발화갭 필수) → S2b(0.85 flip, Tier-A recross0 게이트) → 문제② settle70s 4조합.
- **증류 시 복원**: 이 파일+ACTIVE(v6-dup-fe-suppress)+NEXT.md. orch=V6_HELM#7(%105), Tester=FB_Tester#8(%62).

## ★역할위반 사건+교훈 (11:1x, 오빠 직접지적 — 재발방지 박제)
- **위반**: Master(orch)가 poller 무한대기 버그를 analyst 진단·architect 설계·DA 없이 직접수정 커밋(43907eab) → 오빠 "네가 아키텍터야?" 지적 → revert(23541451).
- **실근본원인은 딴 곳**: Tester#8 진단 — 07-11 저녁 스테일 poller 2개(무한모드)가 살아남아 새 poller와 drain(공유버퍼 원자 비우기) 경쟁 → 레코드 기아로 settle 영원대기. Tester가 스테일 kill+다중인스턴스 가드 커밋(003967f3, REFUSED+--force)으로 해소. 내 수정(exit-on-settle 6s 기본 활성)은 원인 오진+press간 갭>6s 시 캡처 조기절단 리스크(무DA 행위변경).
- **교훈**: ①증상(무한대기)을 보고 코드부터 고치지 말 것 — 프로세스 상태(스테일 인스턴스)부터 진단 ②poller 같은 dev도구도 코드수정은 진단→설계→DA→impl 경로 ③Tester의 직접커밋(003967f3)도 single-writer 위반이나 내용 유효로 수용 — 이후 Tester에도 커밋금지 리마인드.

## 커밋 규율 최종 확정 (V6_HELM#7, 11:1x)
1. **커밋 = 예외없이 Master 단일창구** — 제품코드·테스트도구(poller 포함) 불문, 워커는 diff/제안까지만. Tester 003967f3은 내용 유효로 수용하되 **마지막 예외**.
2. **orch 직접수정**: 원칙 금지 유지. 단 1~2줄 긴급가드는 "수정 전 V6_HELM#7에 1줄 보고" 조건부 허용(회전 지연 방지).


## ★S2a 종합판정 = PASS (11:2x, Master 확정)
- 체커3 전축 PASS(코드 10/10·안전 7/7·테스트 해소) + 라이브 A/B headed(CAPTURE_END settled 3/3): case2 laterality 반전쌍 final 둘다표시(억제금지✅), case3 이중부정 DUP 0, case1 변이DUP transient 8.32s→**1.17s**(BE W2 효과+final 클린). 잔존 변이DUP 1.17s=S2a exact 설계한계(S2b 영역, 예상대로).
- 랜딩 스택: 23a5ff28+4bac9ae4+af998a25 (+poller 003967f3 Tester예외, 43907eab revert됨)
- 다음: R8-BE(P1, assemble.py 게이트⑧ 미러 — 발화갭 필수) → S2b(5게이트 green 후 flip)

## 모니터링 규율 (오빠 지적 3조, 11:2x)
1. 상태변화 없는 Monitor 이벤트=조용히 스킵, 출력엔 항상 현재상태 요약 동반.
2. 3분 무활동 개입 Monitor는 **Tester가 실제 press/러너 가동 중에만** — idle/대기면 해제, 재개 시 재무장. (현재: Tester 발화정지 상태라 Monitor 미가동이 정상)
3. 오빠 직접 입력엔 반드시 실질 응답.


## ★S2a 판정 정정 (오빠 직접목격, 11:5x — PASS 철회)
- **S2a = "내부검증 통과·부분개선(잔존확인)"** — PASS 아님. 오빠가 화면에서 중복 잔존 직접 목격. 완성판정 기준=오빠 눈(내부지표 1.17s/7.35s transient 아님).
- 11:17 retest 실측: finalizing 7.35s 변이DUP 노출 후 final 소거(50프레임) — 오빠 목격과 정합 여부 질문 상신(Q1 어느탭/Q2 transient vs 고착).
- **이후 모든 PASS 선언 = "내부검증 통과"로만 표기, 최종게이트=오빠 육안 무중복 확인**(S2b flip 후 포함).
- 환경정합 실측: ①②④⑤ 전부 이 워크트리·신번들·탭충돌없음 ✅. worker 11:25 재기동=R8-BE 파일저장(발화갭 중, 무해).

## R8-BE 랜딩 완료 (11:5x)
4dc26933 — contrast_guard.py(152L)+assemble.py(+7 veto)+테스트(+220). 6번↔7번/단음절 좌우 상태손실 봉합. worker는 이 코드로 가동중. 다음: 오빠 답변→오빠 앞 라이브 press 1회→판정 재개. S2b는 5게이트+오빠 육안 게이트.


## 제3트랙 개설 — 폴리셔 부정반전(환자안전 P0) + 고착DUP (11:5x~12:0x)
- 오빠 목격 고착DUP 정체=폴리셔 의역 쌍둥이("금식이 필요합니다" 조사차이 2회, B_contrast 11:04 실증). 반전쌍 병렬표시 오인 가능성(b)도 병존 — 둘 다 원장 등재.
- analyst 3자대조 발주(polish.py negation_asymmetry 가드 log-only vs 버그 ↔ 11:04 로그 ↔ 폴리셔 프롬프트). 이후 architect(방향: asymmetry시 polished 기각+raw 폴백)→DA→구현.
- Tester#8→#9 인계됨(pane %109). 재개과업: R8-BE 스팟(6번/7번·좌/우 보존) + 폴리셔 반전 재현 2press.
- 원장 신규 2행 등재 완료(P0 제3트랙 + 반전쌍 UX).

## S2a 라이브 판정 + 증류직전 스냅샷 (11:5x, ctx 461k → 증류)
**S2a 케이스A(DUP 재현쌍) 판정 = PASS(설계 예상 범위)**: /tmp/s2a_retest_20260712_111711.jsonl (5709rec, 11:17~11:45)
- final DUP **0건** + 최종 원문 무손실("골이식…픽스처…마취하면 입술이 좀 저려요" 폴리싱 완벽) + self-heal 정상
- DUP transient 7.62s/55프레임(baseline 8.32s와 유사) — **exact-only(FUZZY 1.0)라 변이DUP 잔존은 설계 명시 예상**, 제거는 S2b 몫
- 체커3: 코드축 10/10 PASS + poller축(오케 직접분석, 위) / log축·반전쌍 라이브(laterality·이중부정 캡처 미검출 — 유닛으론 핀됨) = **다음세션 잔여**
**동시작업자 라인 추가 랜딩**: 4dc26933(★R8-BE 게이트⑧ 임상대비어 veto — 내 다음단계였음) + 43907eab→23541451(poller --exit-on-settle 랜딩 후 self-revert). Tester#9가 R8-BE 라이브검증 poller 가동중(/tmp/tester9_r8be_20260712_114437/).
**채널 변경**: FB_Tester#8 증류종료 → **FB_Tester#9**(Sonnet5 1m). 
**다음세션 우선순위**: ①R8-BE 라이브검증 결과 회수·판정(Tester#9) ②반전쌍(laterality·이중부정) 라이브 캡처 완결 ③S2b(0.85 flip — Tier-A recross0+실측20쌍 게이트) ④문제② settle70s 4조합 ⑤poller SIGTERM시 CAPTURE_END 미기록 한계(kill -2 사용 규약 or 핸들러 보강 검토).

## 제3트랙 설계 완료 (12:1x) + 테스트 방법론 교정 (오빠 직접지적)
- **★테스트 규율(오빠, 영구)**: 비교·재현·A/B는 **기존 코퍼스/시나리오 원본 그대로**(한 press 다문장 연속발화 — dupfix2 덴탈, B_contrast 스크립트). 문장단위 쪼갠 press는 결함을 숨겨 "정상처럼 보이는" 무효 테스트 — 격리분석용 별도라벨 보존만, 판정 미사용.
- **폴리셔 설계 랜딩**: `.claude/plans/v6-polisher-negation-integrity-design.md` (architect fable-5, rev2)
  - 반전 2지점 확정: polish D4 log-only(11:04 실증) + **translate 무가드(Tester#9 11:52 실증)** → Layer 4(translate) 신설: 렉시컬 차단 금지(교차언어 미탐·오탐), 결정적 이중부정 감지+per-request 힌트+WARN 관측.
  - polish v1: D4 presence 차단 승격 + `안(?=[되돼됩])` regex 보강(띄어쓰기 flip 오탐 해소) + contrast는 D5 관측 전용(밀리그램→mg 구조적 오비대칭이라 차단 자기모순) + 부분기각·count는 실측 후 증분.
  - FE lstNorm 조사 정규화 **기각**(SSOT 3중 리스크, 쌍둥이 제조원=폴리셔라 L1이 소스 차단).
  - 스테이징: 커밋 A(worker D4)/B(폴리시 프롬프트)/C(translate) 독립, 전부 발화갭 랜딩. S1~S4 press 시나리오(KO극성+EN폴라리티, 5회+).
- **다음(증류 후 새세션)**: ①Tester#9 코퍼스 press(dupfix2+B_contrast 원본) 결과 회수 ②폴리셔 설계 DA(codex) 발주(state/v6-polisher-negation/da-round1.md부터) ③APPROVE 시 impl(발화갭)→코퍼스 A/B ④S2b는 5게이트+오빠 육안 게이트 유지.

## ★architect 최종 poller 탐지 (증류 직전 12:2x — 다음세션 첫 입력)
B_contrast.jsonl(11:03, 216줄) 재분석: ①의역수렴 탐지(seq55~75: raw "안 드시면 돼요"→폴리싱 "금식이 필요합니다" 재작성 포착) ②**재누적 쌍둥이 고착 DUP 결정적(seq125~137)**: 한 버블 origText에 폴리싱본 3문장+raw 3문장 연속 공존, '금식' 149회=세션 끝까지 고착 지속 — "자동화 전량 miss"가 아니라 **수집됐으나 판정로직이 못 잡은 것**(판정로직 보강 필요) ③이중부정 반전 정본 증거=11:04 worker.log(KO)+Tester#9 11:52(EN "must not eat"). HIL 눈확인↔poller 대조축 3개: 최종 origText 일치/쌍둥이 버블 수/trans 폴라리티.

## ★P0 폴리셔 부정반전 트랙 → **SSOT = `state/v6-polisher-negation/state.md`** (DA 왕복 이력·수렴추세)
증거회수: R8-BE poller(114437) 반전쌍 전부보존·상태손실0=PASS방향 + P0 translate반전 seq200 재확인. 현재 rev5→DA r4 진행중. (중복방지 — 상세는 P0 전용 state.md 참조)
