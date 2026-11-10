# v6-lst-snap-carry — FT state (경량본, 2026-07-23 갱신 — C1c COMPLETE→C2a-R0 진행)

> ★★정본 구조(2026-07-28 오빠직접지시로 V5/V6 분리, mbox#661) — **V5상태=`docs/architect/v5/V5-CANONICAL-STATUS.md`, V6상태=`docs/architect/v6/V6-CANONICAL-STATUS.md`, 작업원장(현재 진행·역할·게이트)=이 파일, 오빠보고용 아티팩트=`~/Documents/V6/V6-MASTER-ARTIFACT.html`**. 4곳 외 신규 정본 생성 금지 — 갱신은 이 넷만. 나머지(SSOT 최종단일화 여부)는 4대범위 4번째항목(DA APPROVE 트리거 대기).
> **전체 이력은 archive/에 보존, 이 파일은 "현재 상태"만 유지 — 완료된 항목은 요약 후 비워낸다(계속 이어붙이지 않는다).**
> 이전 전체이력: `archive/state-archive-20260721.md` (2026-07-22 07-21 이전 전체 + D1 제출 라운드/구로스터 상세 추가분), `.fable-team/archives/v6-lst-snap-carry-state-FULL-20260719.md` (07-19 이전).

## 인덱스
- [현재 상태](#현재-상태) — 시연종료+HOLD 해제+로스터 교체 + C0/C1/C1a/C1b/C1c/D 게이트 현황
- [로스터](#로스터-2026-07-22) — 신규 8세션 구성
- [역할·방법론](#역할·방법론-확정) — HELM/Master/PM 역할분담 + gate 프로세스 8규칙
- [게이트(불변)](#게이트-불변)
- [사고 기록](#사고-기록) — 최신 1건만, 나머지는 archive

## 현재 상태
> 완료된 항목은 이 섹션에 남기지 않는다 — 즉시 `archive/state-archive-YYYYMMDD.md`(증류·정리 시점 날짜)로 이전한다(2026-07-27 구조개편).

- **★★[야간BTS, 2026-07-29밤~30새벽 07-30 10:2x 기준] P1→P8 진행 — P1~P7 CLOSED+커밋+push완료, P8 구현완료·라이브press만 남음.** 상세이력(P1~P4 전문)=archive/state-archive-20260730-nightbts.md.
  **P1** GPU COLD=코드결함아님(DEV_SINGLE유지, WARM poll복구). **P2** E1a→E1b배선 DA APPROVE, BTS-r4 CLOSED(SHA 7a676e3c/5f7e6305). **P3** E1c changed-only retranslator DA APPROVE, BTS-r5 CLOSED, 잔여7핀=백로그[00:38]. **P4** E2a-only production배선 DA APPROVE("E2a완료·E2전체미완" 명명), BTS-r6 CLOSED(SHA 6a744c81).
  **P5** E2b durable authority(Redis 단일키 CAS+zero-write replay 실증) DA APPROVE→LIVE CLOSURE+커밋집행(정리스윕 132 passed·0 failed). **P6** E2c publish+seal — DA REVISE 1회(outbox 선publish 부패노출/receipt 자기검증만 2건 blocking)→보정→즉결재심 APPROVE→press8 CLOSED(FE도달). **P7** token dedupe(reconnect게이트) DA one-shot APPROVE→press9 부분GREEN(게이트 미검증, 9-b재발주)→r2~r4 native reconnect 실증으로 CLOSED. push됨: `0ce92ed3`→`7dfdb246`(14커밋 P2-P6) + `d2839986`/`756c2da3`/`b8354307`(P7, origin=b8354307).
  **P8 취소선(decider+CAS+strict zip+translate_single주입)**: architect DESIGN_REVIEW HOLD(CAS조회가 provider 뒤=fresh-only위반)→read-only atomic classifier(`e_cas_classify.py`)로 보정, 판정문amendment(§8 신규3+수정5→**신규10+수정5**, 근거=180LOC hard gate)까지 **커밋 `4228052e`로 랜딩·push완료**(DA one-shot APPROVE 조건0). 이어 **press1 실행**(`9eeea071` 증거고정): backend prev_text가 replay frame까지 도달, **화면 취소선 미표시**. **Master#92(mbox#701) 구두전달: architect가 press1 자극을 무효로 판정**(근거문서 미커밋·미확인, 원출처 재확인 필요) — 유효재현 전까지 결론보류. **종결기준(화면 취소선 실표시)은 아직 미증명.**
  **오빠 아침판단 대기 4건**: Unit L flag-on manifest 재발급(비차단) / GPU스케줄러 pause 비용 재개여부 / 소소(LOC3파일처분·seal ordered-array exact·DA observability drop counter) / **P8 press1 재현 여부(architect 무효판정 확인 후)**.
  **[Master#92 mbox#701, PM검증완료] 진행분 push=`118f79b3`까지(10커밋 전건 실재확인, HEAD=origin 일치)**: press2 발화#1 판정에서 D residual_only row_count=0 관측(window-polish가 원문을 단일 REWRITE atom으로 재작성→D가 candidate boundary 못 만듦) → **P8.1 신설**(comparator public surface `has_semantic_change` 2층구조+E2 exact경계 `_resolve_prev_text` 1곳+tester 5핀+DA검증면8항, 설계·계약 완성·착수전, 착수조건=P8 CLOSED+Master발주). **press2는 3연속 게이트 미충족**(회차 미소모, 원인 매번 다름: 설정모달 오버레이/커넥션-per-이벤트 자체드라이버/settle타이밍부족 — **실행경로 문제, 자극·코드 문제 아님**), architect 유효자극 설계 아직 미실행. **신규트랙 승격**: 폴리셔 3종 시스템프롬프트 조절 실험(3종 폴리셔가 최소편집 유도되면 atom이 여러개로 갈려 D경계 성립 가능이라는 오빠관찰) — 정본 `design/V6-THREE-POLISHER-NODE-VALIDATION.md`+`design/evidence/polisher-3type-mapping.md`(.omo이관·`d4acb7af`, PM 유실위험 patterns과 동일사례), **P8 다음 트랙**으로 정렬, 발주는 P8 CLOSED 후. 미커밋 잔여: `design/evidence/v6-night-p8/20260730T135812+0900-press2/`(untracked, tracked경로 안이라 유실위험 낮음, 추후 docs커밋 예정).
  **[SKELETON-WIRE격리]**: HOLD선언전 정본에 미검증 중간patch(+122/-19) 잔존(B4만v2/3-plane, B6/G3/G4/G6은v1 — 내부불일치), 야간BTS와 무관 격리(전노드관통후 별도처분).

- **★★★★[2026-07-29 야간, 오빠지시] 야간자율 루프 개시 — 계약라운드(다라운드 approve) 중단, BTS관통우선. 상세=DISCIPLINE.md**. **완성=결과지표(화면/취소선/중복없음) 아니라 2항**: ①V6그래프 전노드(C1·C2·D1·D2·E0·E1a·E1b·E1c·E2) 구현완료, 빈껍데기 없음 ②프론트→백엔드전노드→프론트 왕복 연결완료. **종료조건**=오빠 "자율완료" 선언까지 무정지, 블로커는 그 트랙만 기록하고 타트랙 계속. **기록의무**: 에러·추가기획거리=`design/V6-NIGHT-BACKLOG-20260730.md`(tracked, 시계열, PM경유append 가능) 하나로 통일. HELM=야간연속성축.

- **[2026-07-28~29] 윈도우체인 W0→W1→W2 확정 + W0-A DEFECT판정(D splitter 계약위반, 랜딩SHA `07365655`) + 골격우선(skeleton-first) 전략채택 이력** — 전문=archive/state-archive-20260729.md. **핵심만**: W0=Todo5/W1=Todo7(SHA `b7415cf1` DA APPROVE)/W2=Todo4. 골격우선전략 사유·확정3항=DISCIPLINE.md. **이 트랙은 SKELETON-WIRE(아래)로 흡수·대체 진행중** — 세션별 최신현황은 로스터 섹션 참조(이 줄에 재기록 안 함).
- **★★★SKELETON-WIRE 구조+행위 계약랜딩 완료(7단계완주, DA R14 APPROVE) — 정본=`design/V6-SKELETON-WIRE-AF.md` SHA `63fad63e`(폐기10건 R5~R14, 인용금지)**. PM판정 당시: 계약랜딩 자체는 완료, 생산배선·라이브관측 포함 전체유닛은 미완. **PM예측한 다음단위="생산배선(E2 recorder shell) 랜딩"이 실제로 아래 야간BTS P1~P5로 진행중** — 이 블록의 세부(7단계 판정문·이사이클산물·DA잔여목록 등)는 archive로 이관, 최신 진행은 아래 야간BTS 블록 참조.
  R1~R13 세부이력·SHA체인 전문=archive/state-archive-20260729.md.
- **[2026-07-29, 오빠지시 별건설계] BTS 역할체인 관측도구 자체 보강 — W0과 우선순위·커밋 분리**: 목표=tester 실행만/checker는 실행 0·읽기전용으로 원인규명 필요사실 전부 산출. 완료기준=tester가 라이브 1회 실행 후 checker가 함수실행 없이 읽기만으로 사실을 전부 도출 가능. 모든 진단기록에 **입력 지문(input fingerprint)을 기본 필드로 고정**. 우선순위=W0 다음.
- **[2026-07-29] 규율 9건 원장예약 — Master가 창 닫으면 일괄커밋**. 비중 큰 2건: (1) 실행로그가 현재 코드의 결과인지 선검증 없이 값 하나를 오독하면 판정 전체가 무효화되고 검출이 우연에 의존한다는 사례 (2) 역할분리가 실제로 걸러낸 첫 사례 — tester가 "통과"로 보고한 것을 checker가 판정 없이 사실만 올려 불일치가 드러남(한 세션이 전부 했으면 놓쳤을 것).
- **★★[미이행 필수조건] C-4(a) typed rejection → R-C5 seal 이관(2026-07-25, da-opus#3 판정)** — fakeredis가 이미 redis version 개념을 구현해 INFO stub 추가 시 `redis_version>=7.4` assert가 fake에서 통과할 위험(현재 방어는 우연). **R-C5 seal 필수 3항**(fakeredis typed raise/INFO assert+교차확인/negative RED핀) 누락 시 DA판정 무효화. 전문=archive/state-archive-20260729.md. R-C5는 SKELETON-WIRE 이전 트랙, 골격우선 전환 후에도 유효(미해소).
- **★★B1 COMPLETE — gate#10 CLOSED(07-27, 상세=archive)** — 번역요구는 gate15/17이관, B1소유분(segment.confirmed/finalized seal/DOM)만 판정. r6실측 충족(CER0).
- **★판정도구 확정(2026-07-27)**: **CER 0 = STT PASS**(번역과 무관). **`trans=[]`는 `NOT APPLICABLE` 또는 `BLOCKED-BY-V6-MISSING-TRANSLATE`로 판정** — **번역 성공으로 해석 금지**(4-state 판별식 fulfilled/incomplete/failed/not-applicable의 실제 적용사례).
- **[07-27 4종 superseded 이력 통합, 2026-07-28 pm-v6#4 33KB자율정리, 전문=archive/state-archive-20260727.md]**: 정정/성과/잔여(translate.result미발생=계획된 gate15이관·07-27 성과5건·미해소잔여 1·2순위종결/3순위f9b618f9완료/4순위백로그) / D-WIRE첫착수경과(SHA`ff5b8fcd`, r7미관측→line42/44가정본) / D-WIRE재판정2회차(원인=server.sh기동스위치부재→Unit L`e96c2272`로해소) / 완성그래프07-27~28초판 — 전부 line42·43·44가 현행 정본, 원문은 archive만.
- **계획 끼어들기 — realtime 설정 UI 세대선택 일원화(2026-07-27, 오빠 지시)** — 경위·범위6항목 전문은 **MASTER §9c가 정본**(상세→archive). 현재=architect설계중→DA승인→impl#42. **B1은 이 작업을 기다리지 않고 독립 진행해 라이브 성공**(순연 무효). Lecture·MR·Note 착수시 하위항목 반영은 MASTER §9b 완료.
  - **★확정 — `policy_version`은 코드 단일 상수(`SOLO_POLICY_VERSION`=`p2-f0b-live`)로 간다(2026-07-27, DA·architect 수렴, 논쟁종결, 근거전문=archive)** — env유입삭제, gateway startup검사제거, `.env`추가없음. 변경범위 3곳: `v6_pulse_consumer.py:53`/`v6_route_producer.py:53` 반전함수유지, startup검사 제거.
- **★★[진짜 미결] `V6_AUTHORITATIVE_STT_MODE`+provider가 여전히 기동 env(2026-07-27)** — 그 회차 라이브 **2차 실패가 정확히 이 env 누락**이었고 **3차 실패가 `V6_SOLO_ROUTE_ENABLED` 누락**이었다 — **같은 클래스로 두 번 당함**. policy_version/rollout 스위치를 코드로 옮기는 지금, 이것만 env에 남으면 **다음 재기동에서 네 번째로 당한다**. 현재 architect·DA에 판정 요청 중(policy_version에 적용한 논리가 여기도 적용되는지 확인).
- **20개 landing gate 정본 순서(2026-07-24 확정, 2026-07-27 항목10 갱신)**: 1.`C0` LIVE-WIRED `52498eb9` · 2.`C1a` SEALED-SUBSTRATE `aadd50e6` · 3.`C1b` SEALED-SUBSTRATE(`bc761d2a`) · 4.`C1c-ADMISSION` SEALED-SUBSTRATE `007c314f`/`14963add` · 5.`C2a-SUBSTRATE` SEALED-SUBSTRATE `fbc33966`/`9cd9ce77` · 6.`C2b-SUBSTRATE` SEALED-SUBSTRATE `437c48be` · 7.`C2c-AUTHORITY` SEALED-SUBSTRATE `3b47968c` · 8.`C2c-TIER-B` SEALED-EVIDENCE `332e6831` · **9.`C2c-ACT GREEN` ✅CLOSE(SHA `0fe167d5`→`c18bbf94`)** · **10.`C-LIVE equivalence` ✅CLOSE(2026-07-27, B1 COMPLETE — GREEN-C LANDED+PUSHED+라이브관찰 PASS, translate요구는 gate15/17로 이관)**
- **[2026-07-27 6-unit 착수순서 확정분, 2026-07-28 순서만 superseded(현행=line43 빌드순서확정) — 원 순서나열 전문=archive/state-archive-20260727.md]**: **완료기준 공통**: production invocation+same-ID Worker/Redis 관측(unit-test만으론 불인정), public-surface단계(E1a/E1c/E2)는 event/DOM까지 포함. **V5무영향 구조**(architect 확정): legacy_graph 노드/edge 고정, mode-agnostic 계산만 typed pure kernel로 추출, V5/V6 양방향 import금지 guard+characterization회귀로 구조적 보장. **Graph duplication 금지와 무충돌**(금지대상=mode별 downstream graph 복제, V5/V6 세대공존은 별개).
- **P/D(D-WIRE) 설계 DA APPROVE 확정** — 상세(구현면/순서/no-edit7파일/DA조건/판정근거4축)는 archive/state-archive-20260727.md 하단+정본 `.omo/plans/v6-seam-polish-v5-prepend.md` Unit P/D절. 요지만: baseline SHA `a0862875`, 삽입점=`activation_subgate/consumer.py`의 `_claim_and_execute` L186-187 사이.
- **★계획 승격 완료** — `.omo/plans/v6-seam-polish-v5-prepend.md`(20.7KB, architect#27+pm-v6#3 합의 후 승격). **첫 gate=P/D(D-WIRE), DA exact-SHA 판정 필수**. E2a/b/c 하위게이트 전부 필요(단일E2로 안 뭉갬). **판정 4-state**: fulfilled/incomplete/failed/not-applicable(선행단계가 해당 표면을 아직 약속 안 했으면 부재는 정상, incomplete·failed로 오판 금지 — CER≠translation 구분 포함). **D-WIRE 실제 삽입점**: activation consumer decision commit 후, terminal 전. **drain_contiguous/D1·D2 pure 파일은 no-edit**(건드리지 않고 그 뒤에 삽입).
 · 11.`D1` SEALED-SUBSTRATE `c71ef4cc` · 12.`D2` SEALED-SUBSTRATE `4450437f` · **13.`D-WIRE` ✅CLOSE(2026-07-28, PM판정 FULFILLED)** · 14.`E0` PENDING · 15.`E1a` PENDING · 16.`E1b` PENDING(Loom Pack `34f6c23d`만 선행 SEALED) · 17.`E1c` PENDING · 18.`E2a` PENDING · 19.`E2b` PENDING · 20.`E2c` PENDING.

## 대기 작업 (타이밍 조건부)
- **[무해 잔여물]** `{scratchpad}/baseline` detached worktree 1개, 오빠 `!`접두 실행으로만 제거 가능(파괴적명령훅 차단). 상세→archive.
- **★★★PM 완료판정 1·2(2026-07-27, 규율15항 첫 적용) — 둘 다 미완료**
  **①D-WIRE Unit P/D 당시판정=미완료(GPU COLD로 라이브관측차단, 코드랜딩만 충족) — 2026-07-28 FULFILLED로 재판정 완료(하단 최신항목이 정본), 원문=archive/state-archive-20260727.md**.
  **②R6 = 미완료, 독립항목**(D-WIRE Unit P/D 소속 아님). 근거: R6는 B1 COMPLETE 이전 '미해소4건' 3순위로 이미 독립 추적 중이던 항목(`design/B1-RECLAIM-POISON-ENTRY-RESOLUTION.md` 소재, B1 종결 시에도 '진행중'으로 별도 이월). DA 코드랜딩검증(설계5항+핵심3건+범위3건) 통과했으나 `design/DA-VERDICT-R6-LANDING.md` 자체가 mutation 6종+라이브관측을 **미판정으로 명시**. **[2026-07-27 갱신] 커밋됨**(SHA `f9b618f9`, 13파일 549+/108-, 오염0, push안함=ahead2 — pm-v6#3 독립재검증 완료, Master보고와 일치). **미커밋 근거는 소멸했으나 판정원칙(코드랜딩=필요조건, 라이브관측=충분조건)상 결론 불변** — mutation+라이브관측 미판정, D-WIRE와 동일사유(GPU COLD)로 라이브 차단 지속. **재판정 결과: 미완료 유지.**
  **판정 원칙**: 코드랜딩=필요조건, 라이브관측=충분조건. 이번 결정은 계획서 명문 Scope-OUT 조항을 근거로 한 것이라 향후 재발 시 재검토 불요.
  **HELM 접수확정(뒤집지 않음)**. GPU COLD/R6 최신상태(2026-07-28 HELM확정판단④)=`docs/architect/v5/V5-CANONICAL-STATUS.md` §11(2026-07-28 §10에 호출구조테이블 삽입으로 번호이동), 원문(당시 R6커밋임박 서술 포함, 이후 f9b618f9로 완료돼 superseded)=archive/state-archive-20260727.md.
- **[07-28] D-WIRE 관문열림 최초보고(상세=archive)** — code_sha게이트 제거, 커밋5건검증, E0착수. 이후 FULFILLED 확정(아래).
- **★★★D-WIRE = FULFILLED(PM판정, gate13 CLOSE) — 6단위 중 1번째 완료**. 상세근거=archive/state-archive-20260727.md.
- **★★★[2026-07-28] gate14=증상, 이월판정 전면철회 — V5정상화 랜딩완료(`1a1e64e0`)+T1 PASS로 CLOSED 확정**. V5상태정본=`docs/architect/v5/V5-CANONICAL-STATUS.md`, V6정본=`docs/architect/v6/V6-CANONICAL-STATUS.md`(둘 다 07-28 오빠지시 분리생성). **안전장치6종 중 아직 유효한 것만 요지**: 3층분리(commit층 11건 불변검증축 승격+canonical V5 topology mutant핀 11/11 GREEN+capability guards 별도축)/mutant감시 상시화/DA독립검증 완료. 전문(재기준화 철회 경위·3층 상세)=archive/state-archive-20260729.md.
- **★★★[2026-07-28] 빌드순서 확정(PM승인, architect제안+Master발송, mbox#656)**: **D-WIRE(완료)→E0→E2-CORE→E1a→E1b→E1c→E2-ENRICH+CLOSE**. E2가 E2-CORE(commit_prepare+segment_commit, ='진짜 V6노드연결'=D-WIRE handoff→SegmentLedger/commit adapter — 새단위 아님)와 E2-ENRICH+CLOSE(취소선 enrichment+seal, E1c 재번역결과 필요해서 원위치)로 분리됨. **런타임 정본순서는 불변**(D→E1 seam→commit_prepare→segment_commit→seal — 실행순서 아니라 빌드/검증순서만 바뀜, E1a-c가 release_finalize_mapper 임시bridge 위에 쌓이는 걸 막으려면 E2-CORE 선행이 기술적으로도 맞음). **gate번호(14~20)는 정체성으로 그대로 유지, 빌드순서만 별도표기**(혼동방지).

- **[2026-07-28, Master#88 mbox#658/659] architect V6기획 정본초안(`v6-window-reuse-isolation.md`) — 당시 Metis REJECT+블로커6건 상태였음(전문=archive/state-archive-20260729.md). 이후 골격우선 전환(아래 07-29 항목)으로 A~F 재기획 진행 중, 블로커6건 개별추적표는 미작성 상태로 대체됨.** 문제해결 표준체인(checker→Master→architect→(DA)→Master→impl)은 여전히 유효.
- **[2026-07-28] HELM 자기판단오류 정정 이력**(전문=archive/state-archive-20260729.md) — Metis REJECT를 V5정상화까지 묶어 전트랙 정지시킨 오판, project #4 RULE 위반, 2회반복 자인. **세션 현재상태는 로스터 섹션이 유일정본, 이 문단엔 재기록 안 함.** **표현규율(유효)**: "대기" 쓸 때 무엇을 기다리는지 명시(오빠결정대기/architect판정대기/순번대기 셋 중 하나).
- **★★★[2026-07-28] T1 PASS 확정 — gate14/V5정상화 라이브검증 CLOSED**(전문=`docs/architect/v5/V5-CANONICAL-STATUS.md`§8). **세대판별자=origin/XADD대상스트림/V6_SOLO_ROUTE_ENABLED/V6_LST 넷뿐**(화면만으론 V5/V6 실행세대 판별 불가). 세션계획·"다음국면" 서술은 이후 W0/W1/W2 window-chain으로 대체, 원문=archive/state-archive-20260729.md.
- **★Unit L(2026-07-27 설계확정, 상세=archive/state-archive-20260727.md)** — 갈래B(`c2c_act_entrypoint.py` out-of-C0 seam) 채택. **[2026-07-28] 구현·커밋 완료(`e96c2272`), D-WIRE 관문 열림 확인**(아래 07-28 항목). 게이트완화 원칙(architect+DA결정=진행근거, 오빠는 파괴·비가역만) 여전히 유효.
- **★★★[2026-07-28] E2-CORE 정본판정(architect 확정, 오너=architect, 오빠지시)**: E2-CORE=gate18 E2a(commit_prepare, V6전용 pure prepare, side-effect0)+gate19 E2b(canonical segment_commit adapter — 새authority아님, E0(`88c0833a`) shared kernel 호출, V5도 같은kernel써서 byte-output불변). E2c(seal cutover)는 CORE밖 gate20. 정본용어=SegmentLedger폐기, E0 shared commit core+E2b canonical adapter. 공백B/C 답변+랜딩커밋(`ebd06271`/`57bd7ea6`/`52157f43`/`966f99ff`/`8052912b`)+세션정지 이력=archive/state-archive-20260729.md.
- **[백로그 2건, 2026-07-28 pm-v6#4 33KB자율정리로 archive이관, 전문=archive/state-archive-20260727.md 하단]**: ①ephemeral docker redis 하네스 안정화(flake 2건째, B1판정무영향, DA권고로 지금안고침) ②`EnqueueOutcome` 신규멤버 시 `assert_never`도입 필요(현재8/8커버라 결함아님, B1완료후 처리, 근거`design/DA-VERDICT-B1-Q3.md`§5).
- **[백로그] gateway integration 6건 FAIL(기존결함, Wave B 무관 확정, 상세→archive)** — C-LIVE 무관, 오빠 승인 없이 손대지 않음.
- **[백로그/별도 트랙] venv 의존성 결손 — `soundfile` 미설치**: `tests/worker/unit/test_pulse_audio_duration.py`가 `import soundfile` collection error를 내며 **전체 스위트 실행을 중단**시킴(현재는 `--ignore`로 우회 측정 중). 본 게이트(C-LIVE) 무관하나 실제 문제. **Wave C 착수와 별개 트랙**으로 처리하며, **오빠 승인 없이 requirements 건드리지 않는다**(HELM#25 지시, 2026-07-25).

## 로스터 (2026-07-29 HELM#26 tmux 실측 갱신 — 이 섹션이 세션 현재상태 유일 정본, 구버전 전문=archive/state-archive-20260727.md)

**상시(살아있는 8세션)**: V6_HELM#26(오케) / FB_Master#90(실행오케) / pm-v6#5(원장) / ft-lstsnap-architect#27(설계) / ft-lstsnap-checker-luna#3(규명) / ft-lstsnap-impl#50(구현, 유일 생존 구현세션) / FB_Tester#21(라이브시연) / da-opus#4(DA, Opus5 1M high — 2026-07-29 da-opus#3 승계, 오빠 claude-fable-5→Opus5 1M 전환확정, ctx68%→14%, 증류불필요)
**구현 단일화(오빠지시)**: impl은 **ft-lstsnap-impl#50 하나로 통합**됨 — **워커 여섯(impl#43~48)이 각자 모듈을 만들면 배선은 아무도 하지 않는다는 진단** 때문. impl#43/#44/#45/#46/#47/#48은 전부 접힘(아래 은퇴/보존 목록 편입, 개별 미커밋분 소유권 이력은 archive 참조).
**유휴 보유(로스터 외)**: ft-lstsnap-impl#49 — **[2026-07-29 갱신] 접기 승인됨**(Master#90 mbox#696, 상세 별도공지 대기 — 승인 전 상태는 archive 참조).
**별도 트랙(본 로스터 밖)**: V6_POLISH_DESIGN#0 — 오빠 인터뷰 대기.
**윈도우 원칙**(불변): architect=설계권위+직접구현금지 / impl=sole production writer+커밋·push금지 / DA=로직판정+mutation반박 / checker·tester=독립재현+제품파일수정금지 / Master=발주·릴레이·커밋승인·push집행 / PM=원장정확성+워커직접지시금지 / HELM=오빠접점+파괴·비가역·main병합만 게이트.
- **은퇴/보존(keep-last-2)** — impl#43/#44/#45/#46/#47/#48(오빠지시 #50단일화로 전부 접힘) / pm-v6#4(pm-v6#5로 증류승계) / pm-v6#3 / impl#37/#38/#39(Fable5 정책위반 운영분) / da-opus#2(ctx100%) / FB_CPO#6 / GoogleMeet#0 / LOOM_DOMAIN#0 / codex UUID 2개. **정리는 HELM#26 판단 사안** — pm-v6#5 소관 아님.

## 역할·방법론 확정
- **★★★[2026-07-28, 오빠질문에 architect 자기평가, Master#88 mbox#658/#667 — 이 세션 최중요 판정으로 지정됨]**: 우리가 만드는 것=상급 실시간 분산시스템 제품화 구간, **연구난제 아님**. 요구를 낮춘 데모=3일~1주면 되나 장애/재시도 시 중복답변·중복비용이 생겨도 되는 시제품. 우리 요구수준=작은 숙련팀 기준으로도 **여러 주가 정상범위**. **현재 위치=출시준비 100중 60~65**, dev lane+단일권위 확보로 속도 붙을 가능성 높음. **낭비분해**: 본질적난이도 40~50% + **우리가 만든 낭비 50~60%**, 최대실책=개발뒤테스트가 아니라 **테스트·승인구조를 먼저 크게 만든 뒤 첫 실제실행을 너무 늦게 한 순서**. **운영규율 4건(즉시 적용)**: ①실제실행 최대한 앞당김 — 유닛통과=진행률 아님, **생산배선0인 GREEN=완료 아니라 미완**(320테스트통과+배선0=이번달 대표낭비 사례) ②승인구조 작업마다 재생성 안함 — 작은코드변경에 승인절차 전체를 재생성한 라운드 2회 있었음, **되돌릴수있는건 그냥 하고, 게이트는 되돌릴수없거나 운영영향있는것에만**(project#4RULE 재확인) ③기준선 먼저 고정 — V5에 실험남긴채 기준선확인 늦어 4주 돎, **앞으로 모든 변경은 변경전 상태를 실측으로 먼저 박고 시작**(tester baseline 사례가 올바른 절차의 예) ④남은 진짜 어려운것에 집중 — 잔여난제는 계산코드가 아니라 **commit·publish·seal·XACK 사이에서 죽어도 중복·유실의미가 안흔들리게 닫는 일**, 여기에 자원집중.
- **[2026-07-28, Master#88 mbox#658] 환경사고 등재(재발방지가치 큼)**: tester가 18:07 발화했으나 worker는 18:11 기동 — **그 발화가 이전 프로세스에서 돌았음**. FE는 14:43 번들 — **그 뒤 변경이 전혀 안 실림**. 결과가 정상화 전 동작과 동일하게 나왔으나 **stale 때문인지 코드 때문인지 가릴 수 없어 무효처리**. **규율**: 발화 전 FE·worker·gateway **3축 기동시각을 커밋시각과 대조기록**하고 시작할 것 — 이번엔 이를 안 해서 무효측정이 나옴(CLAUDE.md의 test-env refresh gate와 동일철학, 이번 V6세션 실측사례로 재확인).
- **[2026-07-28, Master#88 mbox#658, 미확정 — 판정은 architect소관] checker 실측**: 18:15구간 로그에서 **V5세션의 confirmed audio를 gateway가 origin `v6_solo`로 `v6_pulse_requests`에 queued**했고, worker가 **V6_LST=1 상태에서 node lst/node window_preview의 `utterance.live`를 V5 session events stream에 XADD**함 — V5세션인데 V6경로로 흐른 흔적. **stale 프로세스 산물인지 랜딩 후에도 남는 현상인지는 재기동 후 재현으로만 가름, 지금은 미확정으로만 기록**(판정 요청하지 않음, architect 소관).
- **★★권한 정리(2026-07-27, 오빠 지시, HELM#26 통지)**: 윈도우분리·순서·범위=architect+DA / 혼란시 정렬=architect+DA / **단위 완료 결정=PM(pm-v6#3)** / 실측검증+실행라우팅=Master / 게이트판정(커밋승인·발화승인 등 진행허가, 완료판정과 다름)+오빠접점=HELM. **절차**: 실측결과+판정근거가 PM에 옴 → PM이 계획기준(원장 완료기준)으로 단위완료 여부 결정 → HELM이 그 결정을 수신. **근거**: PM이 계획원장을 소유하므로 완료판정 기준 자체가 원장에 있음. **HELM 자기수정 사례**: B1 COMPLETE를 HELM이 확정했던 건 순서가 잘못됐었음(계획정합 확인은 PM 몫). 6단위 순서승인·첫단위 D-WIRE 지정도 architect+DA 권한이었음. **HELM이 향후 이런 판정을 내리려 하면 PM이 지적**(0건확인으로 잡은 방식과 동일).
- **[2026-07-28 갱신] 게이트 추가완화(HELM#26 야간목표 하달, mbox#601)** — 커밋게이트: DA APPROVE=HELM승인과 동일(재경유 불요), 조건은 미완항목 커밋body 명시+파일지정 커밋 2개뿐. push도 사전승인, lint통과 확인만. **HELM을 거치는 유일 항목=파괴·비가역+main병합+오빠보고사안.** 단위완료판정(PM)·다음단위결정(architect+DA)은 HELM 미경유 원칙 재확인(변경 없음, 재확인만).
- **[2026-07-28] PM판정권한 일시정지(D-WIRE완주논쟁 당시, mbox#662)** — D-WIRE는 이후 CLOSE 확정으로 논쟁종결, 이 정지도 해소됨(현재 PM은 SKELETON-WIRE 등 완료판정 계속 수행중). 전문=archive/state-archive-20260729.md.
- **[2026-07-28, HELM#26 mbox#655] 원장크기 자율정리 임계값** — 30KB(30720B) 한도, 현재 31507B로 787B 초과 확인됐으나 4대범위(DA APPROVE 트리거) 일괄정리 예정이라 지금은 미조치. **33KB(33792B) 초과 시 트리거 대기 없이 PM 자율로 부분정리**(완료항목·중간판정본 archive 이관부터, HELM 승인불요). 4대범위 아카이브 정리 시 gate14 오판+철회 전체, 감시핀 재기준화 가설+철회 등은 archive로 빼되 정본엔 각 1줄 요약(오판 이력=왜 오판했는지, 특히 "증상을 원인으로 오독" 패턴이 핵심) 유지.
- **[2026-07-28, 오빠 인터뷰 확정 3건, HELM#26 mbox#658]**: ①Todo6에 **dev전용 가시화 추가** — 화면변화0 정책을 dev모드 한정노출로 완화(정식화면계약·이벤트taxonomy 무변경). ②최종라이브검증 **이중게이트**로 변경(사람개입0→): 에이전트 4축자동수집+**최종완료선언은 오빠 육안**, headless 금지 불변. ③확인주기=**단계별라이브 확정**: 각 Todo 랜딩직후 발화1~2회 확인, 화면변화없는 단계는 확인대상 별도특정.
- **★규율 정본 = `DISCIPLINE.md`**(이 디렉토리). 아래는 인덱스이며 **전문·근거·실증은 전부 DISCIPLINE.md**에 있다. 규율 변경 시 DISCIPLINE.md만 고친다.
  - 역할분담
  - Gate 운영 프로세스 8규칙
  - 워커 자기발명 산출물의 게이트 차등
  - 분할 경계는 상호의존성으로 잡는다 — 빅뱅 금지의 짝 규율
  - 재작업 발주도 1이슈·1스텝 규율을 받는다
  - mbox 표기 규칙 — 금지 4종(백틱·대괄호·중괄호·달러)
  - Serena 상시 사용 의무 + 세션별 가용성 편차
  - mbox `recv` classifier 차단 시 표준 우회
  - claude 429 시 codex 트랙 전환 표준
  - 승계 정본의 '현재 진행중' 갱신 의무 + 이력/미래지시 판별 기준
  - 변동값은 정본 1곳에만 — 문서에 카운트·수치를 박지 않는다
  - 정본 문서 목록 고정
  - 증류 경계 = 750k, ctx 판단은 HELM 외부 실측이 정본
  - impl 워커 모델 = sonnet-5[1m] high 기본, Fable5 impl 금지
  - 세션 모델 검증 = 3자 대조
  - 공유 워크트리에서 stash/reset/checkout/clean 계열 금지
  - 작업 중 파일의 수치는 측정 시각과 함께 기록한다
  - 테스트 수치 보고 = exact 커맨드 병기 표준
  - 게이트별 commit order는 문맥 의존 — 일반 정본으로 전파 금지
  - 판정 반박·수용 모두 설계 대조 선행 (양방향)
  - seal 심사 순서 — 계약↔테스트 매핑 확인을 mutation보다 선행
  - HELM 중간검증은 통과 신호가 아니다 — 경계 명시
  - 라이브 테스트 전 환경 신선도 게이트(Redis 축 신규 추가)
  - 의사결정 속도(즉시상신·선택지+권고·재확인금지·파괴만HIL)
  - 원인 하나를 찾았다고 다른 이상징후를 그 원인으로 설명하지 않는다
  - 존재 확인과 도달 확인은 별개다
  - archive 압축 시 병합범위 내 타 정본리스트 선확인
  - 문서에 완료사실만 남기지 않는다 — 지금 무엇이 돌고 있는지 매번 갱신
  - 진행표현 규율 — 단위기준으로만, 완료표현은 아티팩트 전체에만
  - V6 구현 루프 정본(design/V6-IMPLEMENTATION-LOOP.md)
  - 게이트 3라운드 에스컬레이션 표준절차
  - 잔여 게이트 Tier A/B 스코프 분리 기본값
  - 오빠 방향성
  - 컨텍스트 위생
  - 게이트 전환 표준 점검
  - 구현 범위·작업 윈도우 결정 권한 = Architect
  - 랜딩≠완료(BTS 5단계로 완료판정)
  - 도구 빈값→도구부터 검증
  - 통과개수 아니라 무엇을 고정했는지를 본다
  - 지표 쓰기전 답하는질문 대조(컨텍스트=세션창대비%)
  - 세션승계 시 하위워커 수신처 전부 갱신
  - 판정의 범위를 확대해석하지 않는다
  - 날짜기준 표현 금지(단위기준으로만)
  - 이유 없는 백로그 금지

## 게이트 (불변)
push·우회hack·브랜치분리·워크트리분리·신규세션스폰(HELM경유외)=오빠승인필수. **미push0**(구 HEAD 5f66a858 시점, 이후 SKELETON-WIRE 커밋 다수 추가 — 최신 커밋현황은 위 SKELETON-WIRE블록 참조). Todo2/3/3b 완료 이력=archive/state-archive-20260729.md.

## 사고 기록
- **[2026-07-28, Master#89 mbox#673] Redis 사고 1건 — 자가복구, 영향 0**: checker가 XCLAIM JUSTID 오사용으로 entry `1785137996027-0` 소유권이 일시 `__read_only__`로 이동 → worker reclaim 루프가 자가복구(owner `v6-pulse-worker-1`, deliveries 증가중, `__read_only__` pending 0). 대상이 Signal1 stranded artifact 하나뿐이라 fresh evidence 영향 0. **Signal1 처분 시 이 이력을 스냅샷에 남길지는 HELM 판단 대기**(왜 지금 안 하는지=Signal1 처분 자체가 미착수, 언제=Signal1 처분 시점에 HELM이 결정). 이전 사고기록은 `archive/state-archive-20260721.md`+`archive/state-archive-20260727.md` 참조.
