# v6-lst-snap-carry — FT state (경량본, 2026-07-23 갱신 — C1c COMPLETE→C2a-R0 진행)

> ★★유일 정본 = `~/Documents/V6/V6-MASTER-ARTIFACT.html`. 신규 문서 생성 금지, 갱신은 이 파일과 아티팩트 둘만.
> **전체 이력은 archive/에 보존, 이 파일은 "현재 상태"만 유지 — 완료된 항목은 요약 후 비워낸다(계속 이어붙이지 않는다).**
> 이전 전체이력: `archive/state-archive-20260721.md` (2026-07-22 07-21 이전 전체 + D1 제출 라운드/구로스터 상세 추가분), `.fable-team/archives/v6-lst-snap-carry-state-FULL-20260719.md` (07-19 이전).

## 인덱스
- [현재 상태](#현재-상태) — 시연종료+HOLD 해제+로스터 교체 + C0/C1/C1a/C1b/C1c/D 게이트 현황
- [로스터](#로스터-2026-07-22) — 신규 8세션 구성
- [역할·방법론](#역할·방법론-확정) — HELM/Master/PM 역할분담 + gate 프로세스 8규칙
- [게이트(불변)](#게이트-불변)
- [사고 기록](#사고-기록) — 최신 1건만, 나머지는 archive

## 현재 상태
> 완료된 항목은 이 섹션에 남기지 않는다 — 즉시 `archive/state-archive-오늘날짜.md`로 이전한다(2026-07-27 구조개편).

- **★★[미이행 필수조건] C-4(a) typed rejection → R-C5 seal 이관(2026-07-25, da-opus#3 판정 mbox seq549)** — **C-4(a)는 현재 '조건부 충족'**이며 GREEN-C 게이트는 통과시키되 **typed rejection 요구는 R-C5 seal 필수조건으로 이관**됐다. **⚠️ 이 항목이 누락되면 R-C5 seal 때 아무도 요구하지 않아 DA 판정이 사실상 무효화된다**('조건부 충족'은 시간이 지나면 그냥 '충족'으로 굳는다). **실증 근거**(DA 소스 직독 + HELM 재현 15:21): fakeredis 2.36.1 `FakeServer.__init__` params = self/version/server_type/config → **`FakeServer(version=(7,4))`가 수락되고 내부 version=(7,4)로 에뮬레이션**된다. 즉 fakeredis는 **이미 redis 버전 개념을 구현**하고 있고 INFO 미지원은 '그 명령만 없는' 상태 → INFO가 stub으로 추가되면 에뮬레이션값 (7,4)를 반환해 **`redis_version>=7.4` assert가 fake에서 통과**하고 거부가 조용히 사라진다. **현재 방어(ResponseError unknown command)는 우연이지 설계가 아니다.** **R-C5 seal 필수 3항**: **(a-1)** real-redis harness는 **fakeredis 타입을 명시 식별해 typed raise**(`isinstance(redis, fakeredis.aioredis.FakeRedis)` 또는 동등한 명시 판별 후 전용 예외) — **'unknown command 의존'은 근거 불인정**. **(a-2)** INFO server `redis_version>=7.4` assert 유지 + **버전 출처가 real server임을 fake가 흉내낼 수 없는 축**(CLUSTER KEYSLOT 실행 성공 등)**과 교차 확인**. **(a-3) ★핵심**: **fakeredis를 주입한 real-harness 호출이 typed raise하는 negative RED 1건**을 핀 — 이것만 있어도 fakeredis 업그레이드 시 테스트가 먼저 깨져 회귀를 잡는다.
- **★★B1 COMPLETE — gate#10 CLOSED(2026-07-27)** — architect가 PASS9조8번을 **payload경계 정정**으로 판정(조항삭제 아님): 번역요구(translate.result/translation DOM)는 **gate15(E1a)+gate17(E1c) 이후 acceptance로 이관**, B1 소유분(segment.confirmed 원문/utterance.finalized seal/DOM same-trace)만 유지. **후단 산출물을 선행 완료조건으로 소급하지 않는다**(B1=gate10, translate=gate15). **r6 최종 실측**: segment.confirmed 1건·utterance.finalized 1건·DOM final bubble(origText 안녕하세요 반갑습니다, status final) 전부 충족, DOM segid==worker psid 완전일치, triggerEvent=segment.confirmed(B1소유 이벤트로 DOM 트리거 직접증거), 발화 CER 0.000 1/1유효.
- **★판정도구 확정(2026-07-27)**: **CER 0 = STT PASS**(번역과 무관). **`trans=[]`는 `NOT APPLICABLE` 또는 `BLOCKED-BY-V6-MISSING-TRANSLATE`로 판정** — **번역 성공으로 해석 금지**(4-state 판별식 fulfilled/incomplete/failed/not-applicable의 실제 적용사례).
- **[정정] 앞선 '오늘최대발견/게이트미달' 판정 철회** — V6 translate.result 미발생은 **결함 아님, 계획에 있던 미구현**(gate15 E1a로 이관 종결). 게이트 미달 판정도 철회 — 해당 항목이 B1 **범위 밖**이었음.
- **오늘 성과 5건(lean)**: ①V6 첫 기동 ②라이브 트래픽 소비(entries-read 12, lag 0) ③source-to-release trace 완주(same-trace로 DOM 도달) ④`a0862875` producer수정 라이브확인(target_langs=[en]) ⑤계측 작동 확인(release_control_exempt 30초주기). **상시규율 6항 박제**(`design/V6-IMPLEMENTATION-LOOP.md`)도 성과로 포함.
- **미해소 잔여(2026-07-27 최종)**: 1순위 종결(provider_error) / **2순위 종결(B1 COMPLETE)** / 3순위 진행중(R6 impl구현중) / 4순위 백로그유지(poison exemption). 별도백로그 유지: runner CER-DOM 불일치.
- **★교훈 — 같은 결함을 3번 놓침**: r5(provider_error 탓으로 넘김) → r4(3축유실로 미판정) → r6(에서야 드러남). **규율 승격(Master가 V6-IMPLEMENTATION-LOOP에 반영)**: 원인 하나 찾았다고 다른 이상징후를 그 원인으로 설명하지 않는다, 설명안된 관측은 별도 카운트.
- **계획 끼어들기 — realtime 설정 UI 세대선택 일원화(2026-07-27, 오빠 지시)** — 경위·범위6항목 전문은 **MASTER §9c가 정본**(상세→archive). 현재=architect설계중→DA승인→impl#42. **B1은 이 작업을 기다리지 않고 독립 진행해 라이브 성공**(순연 무효). Lecture·MR·Note 착수시 하위항목 반영은 MASTER §9b 완료.
  - **★확정 — `policy_version`은 코드 단일 상수로 간다(2026-07-27, DA가 자기 안 철회·architect 안으로 수렴, 논쟁 종결)** — **`SOLO_POLICY_VERSION` 값 `p2-f0b-live`, env 유입 삭제, gateway startup 검사 제거, `.env` 추가 없음.** **DA 철회 근거**: `.env`는 gitignored라 fresh checkout/deploy에 전달되지 않는다 — 그 환경에서 기본 ON이면 gateway FATAL이 그대로 재현된다. 즉 `.env` 안은 **오늘 잡은 사고를 다른 환경에 심는 것**이었다. DA의 'blank 무력화' 반박도 철회됨(architect 안은 env override 자체를 삭제하므로 blank가 될 경로가 사라짐). **이번 라운드 변경범위 3곳**: ①`v6_pulse_consumer.py:53` 기본값 반전 함수 유지 ②`v6_route_producer.py:53` 동일 반전 worker mirror ③`v6_solo_policy_version`/`require_policy_version`/gateway startup 검사 제거, 코드 상수 도입 소비부가 직접 사용.
- **★★[진짜 미결] `V6_AUTHORITATIVE_STT_MODE`+provider가 여전히 기동 env(2026-07-27)** — 오늘 라이브 **2차 실패가 정확히 이 env 누락**이었고 **3차 실패가 `V6_SOLO_ROUTE_ENABLED` 누락**이었다 — **같은 클래스로 두 번 당함**. policy_version/rollout 스위치를 코드로 옮기는 지금, 이것만 env에 남으면 **다음 재기동에서 네 번째로 당한다**. 현재 architect·DA에 판정 요청 중(policy_version에 적용한 논리가 여기도 적용되는지 확인).
- **20개 landing gate 정본 순서(2026-07-24 확정, 2026-07-27 항목10 갱신)**: 1.`C0` LIVE-WIRED `52498eb9` · 2.`C1a` SEALED-SUBSTRATE `aadd50e6` · 3.`C1b` SEALED-SUBSTRATE(`bc761d2a`) · 4.`C1c-ADMISSION` SEALED-SUBSTRATE `007c314f`/`14963add` · 5.`C2a-SUBSTRATE` SEALED-SUBSTRATE `fbc33966`/`9cd9ce77` · 6.`C2b-SUBSTRATE` SEALED-SUBSTRATE `437c48be` · 7.`C2c-AUTHORITY` SEALED-SUBSTRATE `3b47968c` · 8.`C2c-TIER-B` SEALED-EVIDENCE `332e6831` · **9.`C2c-ACT GREEN` ✅CLOSE(SHA `0fe167d5`→`c18bbf94`)** · **10.`C-LIVE equivalence` ✅CLOSE(2026-07-27, B1 COMPLETE — GREEN-C LANDED+PUSHED+라이브관찰 PASS, translate요구는 gate15/17로 이관)**
- **★다음 착수 6-unit 확정(2026-07-27, pm-v6#3+architect#27 공동결정, HELM+Master 발송)** — 오빠 지시 4항목(폴리싱/번역/재번역/취소선)+선결substrate 2개를 **기존 gate#13~20과 완전정합**하는 6단위로 확정: ①D-WIRE(gate13, window_refine(type②)decision→D1/D2→WindowHandoff, **첫 착수단위**) → ②E0(gate14, CommitCandidate 호환추출, V5 byte-equiv) → ③E1a번역(gate15) → ④E1b폴리싱(gate16) → ⑤E1c재번역(gate17) → ⑥E2취소선데이터(gate18-20, commit/prev_text/seal). **완료기준 공통**: production invocation+same-ID Worker/Redis 관측(unit-test만으론 불인정), public-surface단계(E1a/E1c/E2)는 event/DOM까지 포함. **V5무영향 구조**(architect 확정): legacy_graph 노드/edge 고정, mode-agnostic 계산만 typed pure kernel로 추출, V5/V6 양방향 import금지 guard+characterization회귀로 구조적 보장. **Graph duplication 금지와 무충돌**(금지대상=mode별 downstream graph 복제, V5/V6 세대공존은 별개).
- **★D-WIRE 첫 착수 경과(2026-07-27, superseded — 상세는 archive/state-archive-20260727.md)**: 코드랜딩(SHA `ff5b8fcd`, DA랜딩검증12항통과) → r7 라이브발화(미관측, 원인규명) → **최신상태는 line42(재판정2회차)+line44(Unit L신설)가 정본**.
- **P/D(D-WIRE) 설계 DA APPROVE 확정**(da-opus#3, baseline SHA `a0862875`, 정본=`.omo/plans/v6-seam-polish-v5-prepend.md` Unit P/D Exact implementation contract 절). **구현면**: 신규 `d_wire.py`+`d_wire_store.py`, 삽입점=`activation_subgate/consumer.py`의 `_claim_and_execute` **L186-187 사이 1곳**. **순서**: provider locator durable(1st) → D handoff durable(2nd) → lifecycle terminal XACK(3rd). **no-edit 7파일**(정정: 이전 4개→7개로 구체화): `drain_contiguous`/`window_apply`/`d1_boundary`/`d2_assembly`/`contracts`/`envelope_decode`/`release_polish`. **DA 조건(랜딩검증)**: `DWireStore.commit_or_replay`에 `DecisionLocatorStore`가 이미 커밋한 **exact provider result bytes를 재구성 없이 그대로** 전달(재구성 시 decision_digest 어긋남 — diff로 동일객체 확인). **DA 판정근거 4축**(참조용): 이중권위 없음(D는 새 판정 안 만들고 envelope.decision만 입력, 12필드 전부 상위권위 유도) / crash수렴 성립(순서상 terminal이 먼저 안 끝나 PEL 재수렴) / 축소경로금지 충족(drain_contiguous에 decision/provider_result/RefineDecision 참조 0건 코드확인) / V5무영향 충족(d1/d2에 V5 import 0건, AST import guard RED에 박힘).
- **★계획 승격 완료** — `.omo/plans/v6-seam-polish-v5-prepend.md`(20.7KB, architect#27+pm-v6#3 합의 후 승격). **첫 gate=P/D(D-WIRE), DA exact-SHA 판정 필수**. E2a/b/c 하위게이트 전부 필요(단일E2로 안 뭉갬). **판정 4-state**: fulfilled/incomplete/failed/not-applicable(선행단계가 해당 표면을 아직 약속 안 했으면 부재는 정상, incomplete·failed로 오판 금지 — CER≠translation 구분 포함). **D-WIRE 실제 삽입점**: activation consumer decision commit 후, terminal 전. **drain_contiguous/D1·D2 pure 파일은 no-edit**(건드리지 않고 그 뒤에 삽입).
 · 11.`D1` SEALED-SUBSTRATE `c71ef4cc` · 12.`D2` SEALED-SUBSTRATE `4450437f` · 13.`D-WIRE` PENDING · 14.`E0` PENDING · 15.`E1a` PENDING · 16.`E1b` PENDING(Loom Pack `34f6c23d`만 선행 SEALED) · 17.`E1c` PENDING · 18.`E2a` PENDING · 19.`E2b` PENDING · 20.`E2c` PENDING.

## 대기 작업 (타이밍 조건부)
- **[무해 잔여물]** `{scratchpad}/baseline` detached worktree 1개, 오빠 `!`접두 실행으로만 제거 가능(파괴적명령훅 차단). 상세→archive.
- **★★★PM 완료판정 1·2(2026-07-27, 규율15항 첫 적용) — 둘 다 미완료**
  **①D-WIRE Unit P/D = 미완료**. 근거: `.omo/plans/v6-seam-polish-v5-prepend.md` Scope OUT 명문 — "Big-bang C/D/E landing and any unit closed by tests or Redis alone without the defined live appearance"(라이브 없이 test/Redis만으로 단위종결 금지). DA 코드랜딩검증 12항 통과(SHA `ff5b8fcd`)는 **필요조건이나 충분조건 아님**. 라이브관측(trusted-PTT 1회로 refine decision과 D handoff conservation을 Worker+Redis로 관측)이 **GPU COLD로 완전 차단**(gpu-stt-tts/stt/tts 전부 COLD, auto_warmup=false, local warmup=AUTO_WARMUP_DISABLED, manual warmup=403 admin-only, 우리 권한 밖). **해소되면 즉시 재판정**(코드 자체는 이미 랜딩 완료 상태).
  **②R6 = 미완료, 독립항목**(D-WIRE Unit P/D 소속 아님). 근거: R6는 B1 COMPLETE 이전 '미해소4건' 3순위로 이미 독립 추적 중이던 항목(`design/B1-RECLAIM-POISON-ENTRY-RESOLUTION.md` 소재, B1 종결 시에도 '진행중'으로 별도 이월). DA 코드랜딩검증(설계5항+핵심3건+범위3건) 통과했으나 `design/DA-VERDICT-R6-LANDING.md` 자체가 mutation 6종+라이브관측을 **미판정으로 명시**. **[2026-07-27 갱신] 커밋됨**(SHA `f9b618f9`, 13파일 549+/108-, 오염0, push안함=ahead2 — pm-v6#3 독립재검증 완료, Master보고와 일치). **미커밋 근거는 소멸했으나 판정원칙(코드랜딩=필요조건, 라이브관측=충분조건)상 결론 불변** — mutation+라이브관측 미판정, D-WIRE와 동일사유(GPU COLD)로 라이브 차단 지속. **재판정 결과: 미완료 유지.**
  **판정 원칙**: 코드랜딩=필요조건, 라이브관측=충분조건. 이번 결정은 계획서 명문 Scope-OUT 조항을 근거로 한 것이라 향후 재발 시 재검토 불요.
  **HELM 접수 확정(뒤집지 않음)**. **유일 블로커=GPU COLD**(사용자결정 대기, 403 admin-only+auto_warmup 권한밖이라 팀이 못 풂). **갱신**: R6 커밋 임박(DA APPROVE+HELM 사전승인, Master가 SHA 직통전달 예정 — 커밋되면 R6 미커밋조건 해소, 남는건 mutation+라이브관측). mutation은 'unit 지양 규율'로 라이브문제 해결 전까지 보류(DA가 판정문에 기준만 적어둠). GPU COLD 해소 즉시 tester 재발화 → PM 재판정.
- **★★★D-WIRE 재판정 2회차(2026-07-27, r7 라이브발화 후) — 미완료 유지, 블로커 변경**: r7 발화 완료(Run ID `r7-dwire-20260727_222256+0900`, SHA `f9b618f9`, 5축 원본보존)했으나 **D-WIRE 로그·`v6_d_handoff` Redis키 전부 0건 — 미관측 확정**. **원인=activation consumer 미기동, D-WIRE 코드결함 아님**(pm-v6#3 코드직접확인): `worker/main.py:638-642` — `c2c_act_manifest`/`c2c_act_code_sha`가 **둘 다 not None**이어야 activation bootstrap 실행 → `scripts/server/server.sh:223` — `uvicorn worker.main:app --reload...`가 **그 두 값을 전혀 공급하지 않음**(로컬 dev 기동스크립트 gap). **DA 판정: 구조적으로 불가능** — 기동절차 변경 전엔 재발화해도 동일 결과. **판정 원칙(불변) 재적용**: 코드랜딩=필요조건/라이브관측=충분조건, Scope-OUT 명문 그대로 적용 → **미완료**. **★재판정 조건 변경**(GPU COLD 때와 다름): **'재발화'가 아니라 '기동절차 변경(server.sh가 c2c-act-manifest/c2c-act-code-sha 공급)' 선행 필요** — architect+DA가 로컬공급방식 수렴중(완료기준은 낮추지 않음). **★★완전한 원인사슬+Master실측3건(server.sh봉인주석 충돌/parse_args가main()안에있어 uvicorn경로 미도달/별도 c2c_act_entrypoint.py 존재)은 `design/D-WIRE-BLOCKED-CONTEXT-20260727.md`가 정본 — **다음 세션 첫 행동=코드 재독 아닌 이 파일 정독**.

- **★★★Unit L 신설(2026-07-27, architect#27 최종판정, mbox#593, 정본=`design/V6-ORCH-CONSOLIDATION-PLAN-20260727.md`)** — D-WIRE 앞에 반단위 삽입. **판정 5항**: ①갈래B 성립(`c2c_act_entrypoint.py`=승인된 out-of-C0 seam, `main()`이 `install_c2c_activation()`후 `worker_main.main()`호출이라 `parse_args()` 정상도달 — uvicorn CLI 재기동 고집할 때만 미도달 문제였음) ②갈래C(PM제안, env var lifespan이관) REJECT — 불필요+C0안에 2번째 기동권위 생성 ③C1c봉인 유효·보호대상은 c1c_ta뿐(server.sh 주석은 C1c-TA 문맥, D-WIRE=c2c activation과 무관 — 문구는 넓지만 보호대상 아님) ④갈래D(수동관측, server.sh 무변경 `python -m worker.c2c_act_entrypoint` 직접기동)는 기술적 가능하나 D-WIRE완료경로로 불승인(공식launcher 선행조건 미충족 시 라이브 2회 유발=stop-loss위반) ⑤**순서=Unit L(공식launcher가 manifest+SHA쌍으로 c2c entrypoint 선택, invalid=loud refusal, flag-off현행경로·C0 fence보존) 먼저 → 같은 SHA trusted PTT 1회**. **PM 자기기록**: 내 갈래C 제안(seq591)은 architect 반론 2건(main.py수정 필요/env는 이 윈도우 3번 실패 클래스)으로 비채택 — 갈래B가 채택됐다. **코드착수는 오빠승인+HELM게이트 후**(V6-ORCH#0 통지, 아직 대기 상태).
  **기타 확인 사실(참고)**: V6 상류경로 정상(XADD 4건/release_intent sealed/consumer entries-read=20 lag=0/DOM segment.confirmed 정상, trans=[]는 gate15미착수라 정상). **GPU는 무관 확정**(발화내내 WARM). STT 3번째청크 hallucination guard 거부는 별건 백로그(r5에 이어 2번째). **Master 자기정정 1건**: 'V6PulseConsumer도 미기동'으로 보고할 뻔했으나 DA가 반증 — 22:14:29 Starting 로그 존재, Master의 r7 collector 파일은 22:23:08 시작이라 그 구간을 놓친 **수집범위 오류**(파일에 없음≠시스템에 없음).
- **[백로그, B1b 처리 대상] ephemeral docker redis 하네스 안정화(2026-07-27, DA 권고 — 같은 원인 flake 2건째)** — `test_v6_c2a_r0_contract_red::test_ready_entry_accepts_exact_four_field_schema_only` / `test_v6_c1c_ta_contract_red::test_source_head_first_accept_writes_exact_canonical_fields` 둘 다 `_ensure_ephemeral_redis`/`_free_port`+docker run 계열의 **컨테이너 기동·포트 경합**. 단독 실행 시 통과, B1 판정 무영향. **지금 고치지 않는다**(범위확대 금지, DA 권고).
- **[백로그, B1 완료 후 처리] `EnqueueOutcome` 신규 멤버 추가 시 `assert_never` 도입 필요(2026-07-27, DA Q3 부수 관찰)** — `DurableOwnerReleaseCutover.resolve`의 `match result.outcome`은 현재 `EnqueueOutcome` 8/8 전수 커버라 결함 아님. **향후 enum에 신규 멤버가 추가되면 암묵적 `None` 반환**이 되는 silent 경로가 생긴다. **지금 고치지 않는다**(B1 범위 확대이므로). 신규 outcome 추가 시점에 `assert_never` 도입. 근거=`design/DA-VERDICT-B1-Q3.md` §5.
- **[백로그] gateway integration 6건 FAIL(기존결함, Wave B 무관 확정, 상세→archive)** — C-LIVE 무관, 오빠 승인 없이 손대지 않음.
- **[백로그/별도 트랙] venv 의존성 결손 — `soundfile` 미설치**: `tests/worker/unit/test_pulse_audio_duration.py`가 `import soundfile` collection error를 내며 **전체 스위트 실행을 중단**시킴(현재는 `--ignore`로 우회 측정 중). 본 게이트(C-LIVE) 무관하나 실제 문제. **Wave C 착수와 별개 트랙**으로 처리하며, **오빠 승인 없이 requirements 건드리지 않는다**(HELM#25 지시, 2026-07-25).

## 로스터 (2026-07-25 재갱신 — 윈도우 지정으로 역할 경계 고정)

> **★윈도우 지정(2026-07-25, HELM#25 — 8팬 동시 가동 시 중복·유휴 방지용 소유권 경계)**. 각 세션은 자기 윈도우 밖 행위를 하지 않는다.
> - **architect#25 = 설계 윈도우** — Wave C 설계 권위 / RED·GREEN 스펙 확정 / impl 납품 독립검증 / DA seal 요청. **직접 구현 금지**(ctx 소모로 설계 권위 상실 방지 — impl 429 때 직접구현으로 갔던 선례 있음).
> - **impl#40 = 구현 윈도우** — **sole production writer**. **커밋·push 금지**(Master 집행).
> - **da-opus#3 = DA 게이트 윈도우** — 로직 판정 + mutation 반박검증만. **commit/push 판정 금지**(게이트 완화 반영).
> - **checker-luna#2 / FB_Tester#21 = 검증·병렬준비 윈도우** — 독립 재현 + harness 준비 + read-only 조사. **제품/테스트 파일 수정 금지**.
> - **FB_Master#88 = 오케 집행 윈도우** — 발주·릴레이·커밋 승인·push 집행·pane 체크루프.
> - **pm-v6#3 = 원장 윈도우** — state.md/MASTER-ARTIFACT/정본 4문서 정확성. **워커 직접 지시 금지**(라우팅은 Master/HELM 소관).
> - **V6_HELM#25 = 게이트·판정 윈도우** — 오빠 접점 + 교차검증 + 세션 생명주기(스폰·모델·증류).
- **V6_HELM#25** (오케 — #24에서 번호갱신)
- **FB_Master#88** (실행오케, sonnet-5[1m] — #87에서 증류로 번호갱신)
- **ft-lstsnap-architect#25**(은퇴/보존, keep-last-2) — C2a-R1+C2b 봉인부터 C-LIVE Wave A/B/C GREEN-C R6까지 리드. architect#23/#24는 각 작업완료로 은퇴.
- **Serena 가용성(2026-07-25 관측) — 성공/실패는 세션별 편차, 환경균일 아님**(당시 성공4/실패4, 세션 재편 이후 재확인 불요).
- **ft-lstsnap-architect#27**(codex sol high, **라이브 세션 — 설계 윈도우 현역**) — 2026-07-27 V6_HELM#25 단일정본 공표로 architect#26→#27 승계. **B1 방향 재검증 진행 중**(승인 아닌 반박 형식 5축 검증, 판정=APPROVE|APPROVE-WITH-CONDITIONS|REJECT-COUNTER, 산출물 `design/B1-DIRECTION-VERIFICATION.md` 미생성). **판정 전까지 impl#41 구현 착수 금지**.
- **ft-lstsnap-architect#26**(은퇴/보존, keep-last-2, read-only standby 유지) — `design/B1-PLUMBING-DESIGN-HANDOFF.md`(247줄) 작성. §3.7 최소집합 판정/§5.3 PASS 9조/§5.4 미결질문1이 오빠 (a) 결정 근거였음. **ctx 19%에서 문서 우선 고정한 판단이 유효했음이 규율 실증**(작업 중 산출물이라도 완성 즉시 커밋 전 문서화 우선 순서가 재검증 연속성을 지켰다).
- **ft-lstsnap-impl#40** (구현, 라이브 세션 — **claude-sonnet-5[1m] --effort high**, **RED-C owner**. 2026-07-25 impl 모델정책 위반 정정 목적으로 impl#39→#40 전환(Fable5 medium → sonnet-5[1m] high). 세션 내부 `/model` 메뉴로 'Sonnet 5 (1M context) ✔' 실확인. impl#38/#39는 keep-last-2 보존. 상세 규율은 [역할·방법론](#역할·방법론-확정) 참조)
- **은퇴/보존(keep-last-2)**: impl#27~#40 순차 인계 이력(GREEN-B 랜딩=impl#38, dual writer 없음), architect#25/#26(#27로 승계), da-opus#2.
- **ft-lstsnap-checker-luna#2** (규명, gpt-5.6-terra medium — 상시 유지)
- **FB_Tester#21** (라이브 시연, gpt-5.6-terra medium — 상시 유지)
- **da-opus#3** (DA, 라이브 세션 — **Opus 5 1M**(세션전용). 2026-07-25 **모델 오기동 정정 이력**: argv=`claude-opus-4-8[1m]`였으나 세션 내부는 Fable5로 돌고 있던 것을 FB_Master#88이 pane 직독으로 발견 → HELM#25가 `/model`로 확인 후 Opus 5 1M으로 정정. da-opus#2가 2026-07-25 ctx100% 소진으로 교체, da-opus#1은 C2a-R0 3건 서명 후 은퇴/재기동 이력. DA 판정 요청은 da-opus#3으로만 발송)
- **pm-v6#3** (본 세션 — 게이트 감지·기록·경보 + 아티팩트/문서 관리, pm-v6#2 승계)
- **은퇴/보존(keep-last-2, 비로스터 유휴 9세션)** — impl#37/#38/#39(Fable5 정책위반 운영분), da-opus#2(ctx100%), FB_CPO#6, GoogleMeet#0, LOOM_DOMAIN#0, codex UUID 2개. **정리는 HELM#25 판단 사안** — pm-v6#3 소관 아님.

## 역할·방법론 확정
- **★★권한 정리(2026-07-27, 오빠 지시, HELM#26 통지)**: 윈도우분리·순서·범위=architect+DA / 혼란시 정렬=architect+DA / **단위 완료 결정=PM(pm-v6#3)** / 실측검증+실행라우팅=Master / 게이트판정(커밋승인·발화승인 등 진행허가, 완료판정과 다름)+오빠접점=HELM. **절차**: 실측결과+판정근거가 PM에 옴 → PM이 계획기준(원장 완료기준)으로 단위완료 여부 결정 → HELM이 그 결정을 수신. **근거**: PM이 계획원장을 소유하므로 완료판정 기준 자체가 원장에 있음. **HELM 자기수정 사례**: B1 COMPLETE를 HELM이 확정했던 건 순서가 잘못됐었음(계획정합 확인은 PM 몫). 6단위 순서승인·첫단위 D-WIRE 지정도 architect+DA 권한이었음. **HELM이 향후 이런 판정을 내리려 하면 PM이 지적**(0건확인으로 잡은 방식과 동일).
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

## 게이트 (불변)
push·우회 hack·브랜치분리·워크트리분리·신규 세션 스폰(HELM 경유 외) = 오빠 승인 필수. 미push 0(완전동기화, HEAD `b22b8a33`=`origin/feat/v6-realtime-live`, e56762b0 포함).

## 사고 기록
- 2026-07-24: **C2c-ACT GREEN landing gate #9 CLOSE 확정**(FB_Master#87 요청, pm-v6#3 git재검증: exact SHA `0fe167d5`→`c18bbf94`, pytest 102/102→103/103, isolated V6 전체 1371/1371, push 완료 확인) + rollout-fence 회귀 fix 반영. 이후 landing gate #10 `C-LIVE equivalence` 진입 — Wave A/B CLOSE, 현재 Wave C(real Redis same-ID) 대기. 이전 사고기록은 `archive/state-archive-20260721.md` 참조.
