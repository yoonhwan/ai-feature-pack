---
slug: v6-variant-dup-carry-leak
pipeline: standard
pattern: 변이DUP (carry/residual finalize 후 미정리 → 다음 세그 유출)
ledger: v6-rt-ux-issue-ledger.md P4-1 계열 (신규트랙 아님, append)
orch_channel: V6_HELM#9, worker=FB_Master#68, tester=FB_Tester#10(%127)
updated: 2026-07-12T21:4x
---
> ★★★ 영구 규율 (오빠 직접, 07-12 최상단 박제) — FB_Master#69 이하 전 세션 적용:
> **지금부터 오빠가 요청하는 것만 딱 그것만 수행한다.** 자율 판단·선제 작업·후속 제안 실행·
> 백그라운드 발주·Monitor 재무장 전부 **금지**. 절차 = 지시 1건 수신 → 그것만 수행 → 한 줄 보고 → 대기.
> (오빠+orch가 직접 하나씩 완성하는 체제. 이 블록 삭제/이동 금지.)
>
> ★★★ 영구 규율 2 (오빠 직접, 07-13 A-1 1단계 승인과 함께 발효) — **폴백 절대 금지**:
> **모델 tier 폴백/승격 코드는 제안 자체 금지** — 앞으로도. QUALITY tier 라우팅·상위모델
> 스왑·cap 이원화·rescue skip 류의 모델 특정 대응 일절 불가. 품질/안전 대응 수단 =
> **폴리시(결정적 감지+출력 가드) + 프롬프트(시스템 지시문)만**. (A-1 재작업 8c9c322c 계기 —
> pro 폴백 C/E 제거. #0 RULE(no silent fallback)의 모델-tier 확장판.)

# 변이DUP — carry/residual finalize 후 미정리 유출 (직렬 1이슈, 오빠 지정)

## 재현 확정 (Tester#10 rep1 + Master 독립검증) — 21:4x
- 시나리오: 임플란트/골이식 dupfix2 코퍼스 2-pause(3세그 2휴지). JSONL=/tmp/tester10_dupfix2_rep1_202306.jsonl(183프레임).
- **poller 패턴**: seq124 origLen=57(seg1 정상종결 db7b46ba, confirmed_len=56) → seq145~179 finalizing origLen 77→110 단조증가+dupCount=2(신규세그 a5b33a05) → seq180 origLen=110 dupCount=2 **확정표시(화면노출)** → seq182 origLen=83 SHRINK 자가교정(dupCount=1). 노출 1.6s.
- **★근본 (Master 독직검증 확정)**: seg2(a5b33a05) new_segment text_preview="**가 부족한 곳은 고리식으로 보강한 귀 픽스 스처를 심겠습니다** 오늘은 임플란트 식립 위치를 정하고 뼈."(L43287, confirmed_len=77) = **seg1(db7b46ba)의 이미 커밋된 tail이 seg2 신규발화에 prepend됨**. seg1 finalize 후 carry/residual 미정리 유출.
- **track2 게이트 0건 확인**(20:23:06~38 window: redub_fuzzy_drop/force_finalize/inv4_fuzzy_echo_drop/carry_dedup/hash_dedup_skip 전부 0) = 커밋 8dcf073e/8c0b6684 **무관, 별개 근본**.
- 정확 코드지점 미확인(assemble.py carry/residual 정리 or pulse_consumer carry store/load, finalize→next-segment 전이) → architect 트리아지 대상.

## 다음: architect 트리아지 (carry 미정리 코드지점 규명) → 설계 → DA → impl → 라이브 재검증
- Tester#10 홀드(rep1 재현 충분, architect 규명 중 추가 채증은 필요 시).

## ★ Master 솔로 규명 완료 (read-only) — 21:5x
### 원인 코드지점 (pinned)
- **pulse_consumer.py L2024~2091 mid-press-final carry 블록** (seg1/seg2 동일 press ptt:a7cd156a, 2-pause).
- seg1 final_boundary: splitter `input_len=56 sentences=1 residual_len=33`. T11(L2072-2076)이 residual을 trim base에서 절제해 **residual 생존 보장**(track2 anti-loss 의도) → residual-save 게이트(L2061-2084)가 residual을 `last_published_source`(커밋/polished 텍스트)에만 대조 trim → **seg1 tail(33자)이 라이브 표시됐는데도(origLen=57 rendered) 커밋텍스트엔 없어 trim 미발동 → pulse_residual 저장 → seg2 new_segment carry load → prepend 재표시**(L43287 text_preview="가 부족한 곳은...심겠습니다 오늘은 임플란트..."). 
- SHRINK 자가교정은 seg3 커밋(20:23:35)에 하류 dedup으로 **늦게** 발동 → 1.6s transient DUP 노출.
- track2 게이트(redub/force_finalize/inv4/carry_dedup/hash) 20:23 window 0건 = 별개 근본 확정.

### ★수정방향 1개 (track2-safe)
- residual-save 게이트(L2063-2084)의 overlap-trim base를 **커밋텍스트(last_published_source)뿐 아니라 seg1이 라이브 렌더한 텍스트(live_text/assembled 발행분)까지** 포함하도록 확장 → 이미 표시된 tail residual은 carry 전 trim.
- **track2 무회귀 근거**: track2의 손실 residual은 **렌더된 적 없음**(demote silent)이라 live-rendered base에 없음 → 여전히 carry(손실 방지 유지). 이번 DUP residual은 **렌더됨**이라 trim됨. discriminant="이미 표시됐나".
- impl 선확인: 이 게이트 스코프에 seg1 live_text 접근 가능 여부(assemble_confirmed_raw 인근 필드).
- 대안(하류): SHRINK dedup을 seg2 finalizing 프레임에 동기화(FE reducer/worker supersede 조기발동) — 단 근본은 carry 게이트라 상류 trim이 정본.

### ★Master 컨텍스트 노트
- 이 세션 대규모(track2 완주+변이DUP 규명). 증류경계 근접 가능 — orch 판단 시 impl은 fresh 세션/워커로 넘기는 것도 옵션(state 전량 write-through 완료).

## ★★ 재규명 — 원안 폐기 + 정본 방향 (orch가 content-loss 역회귀 포착) — 22:0x
- ★orch 포착: 원안(residual carry 전 trim)은 **content-loss 역회귀**(track2 FE 변형 재도입). 이유: seg1 tail은 라이브 표시만·**커밋 안 됨** → carry가 유일하게 tail을 최종전사에 넣는 self-heal 경로. trim하면 seg1커밋에도·carry에도 없어 영구소실.
- **self-heal 확인(Master 로그검증)**: seg1(db7b46ba) 커밋 text_len=**19**(짧은문장만, tail 미커밋) / seg2(a5b33a05) 커밋 text_len=**32**(carry된 tail이 seg2 커밋으로 최종전사 진입). = 현재동작=1.6s transient DUP 후 seg2 커밋으로 tail 정확히 1회 보존(self-heal). **원안=transient DUP를 영구소실로 맞바꿈 → 폐기.**
- **★정본 방향 = 표시-커밋 분리(display-layer)**: carry+commit 유지(self-heal 보존) + **seg2 new_segment 라이브 표시에서만 carried-tail prepend 억제** → transient DUP 미표시, 최종전사 무손실. (대안: 하류 dedup=seg3 35s 발동을 seg2 confirmed 시점으로 앞당김.)
- 작업 레이어=FE reducer(v5-segment-reducer.ts/solo-transcripts.ts/v5-transcript-types.ts liveText/liveTextPsid). worker carry 무변경.
- ★Master 노트: 원안 1회 오설계(carry-loss 함정) + 이 세션 대규모(track2 완주+변이DUP 규명). FE display-layer 정밀 재설계는 fresh 세션/architect(sonnet-5) + DA가 안전. Master 증류(FB_Master#69) or impl 라우팅 orch 판단 요청. state 전량 write-through.

## ★★★ 라이브 재검증 FAIL + REVERT (FB_Master#69, 오빠 게이트) — 21:1x
### 진행 요약
- orch(V6_HELM#9)가 파이프라인 컷: display-layer fix=FE reducer 1~2파일=오케 직접처리. Master(FB_Master#69) 직접 구현.
- 커밋 **7367f454**(FE 3파일 display-layer + 유닛 pin 4): V5State.liveTailByCycle 스냅샷 + seg2 partial carried-tail exact-strip. 유닛 4 GREEN(L43287 표시제거/track2 no-op/self-heal)+기존 122 회귀0. Tester#10 REV=I7 fresh 확인.
- **라이브 rep1/rep2 = FAIL** → 오빠 직접 지시로 **REVERT 커밋 69ce0b2c**(7367f454 되돌림, 센티널 I6 복원, jest 122 GREEN).

### ★근본 재규명 — A변이 vs B변이 (핵심)
- **A변이(기존 규명·state.md 위)**: seg1이 SHORT만 커밋(tail 미커밋) → worker carry가 tail을 seg2 커밋에 넣는 **유일 self-heal 경로** → transient 1.6s DUP 후 최종전사 정확히 1회. 7367f454가 커버(표시축 partial-strip).
- **★B변이(라이브 rep1/rep2 실증·미커버)**: seg1이 tail 포함 **FULL 커밋**(orch 로그직독 L43800 seg1 confirmed_len=83에 tail 포함) + worker가 그 tail을 seg2 **확정커밋에 재포함/redub** → **confirmed-vs-confirmed 영구중복**(rep1 final origLen=101, "가 부족한 곳은…심겠습니다" 2회 고착 / rep2 fuzzy 풀문장 중복 origLen=124). STT 비결정으로 A/B가 갈림.
- **왜 유닛 4 GREEN이 못 잡았나**: pin이 **표시 lane(partial strip)만** 검증하고 **최종전사 조립(confirmed-vs-confirmed 형제 병합)을 안 봤음**. B변이는 partial 축이 아니라 확정 세그 간 중복이라 원천적으로 pin 범위 밖.
- **정본 재설정(orch)**: B변이 근본 = **worker carry/redub의 확정커밋 중복**. FE 형제 dedup(exact+fuzzy, self-heal 안전)은 또 **대증**. 근본 해결은 worker carry 재설계 영역.

### 상태
- **이슈 status = 부분개선(잔존 FAIL) — PASS 아님**. A변이 표시축 규명·검증됐으나 revert로 트리 미반영. B변이 미해결.
- **오늘 이 이슈 추가 작업 없음** — 재설계는 오빠 게이트. Tester#10 홀드. Master/Tester baton save 후 대기.
- 아티팩트: 7367f454(fix, reverted)/69ce0b2c(revert)/설계=.claude/plans/v6-variant-dup-display-layer-design.md/유닛=삭제됨(revert). rep JSONL=/tmp/tester10_dupfix2_repverify{1,2}_*.jsonl.
- ★Tester#10 신규관찰(별개, 미확정): rep2 duration9s config에서 FE 버블 status가 'finalizing'→'final' 전이 실패·settle_timeout 고착(BE는 21:13:09 완전확정). fix와 유관/무관 미판정 — 후속 트리아지 대상.

## ★A-1 재작업 (pro 폴백 제거, 07-13, FB_Master#69) — 1단계 완료+2단계 표 완성
### 1단계 (커밋 8c9c322c, 오빠 승인·orch 독립검증 PASS)
- C(6449d2e7 QUALITY pro 라우팅)+E(564c84cd cap25s+rescue skip) 제거, 7파일 +141/-281.
- F 폴라리티 가드 게이트 `_routed_quality`→`_double_neg` 재배선(모델무관 생존), 예산 env FINAL_CAP 7s 정합. loom skip 게이트 삭제. rescue 무조건 실행 복원.
- 보존: has_ko_double_negation SSOT / polish A(38e74724)·B(4115c624) / F(ab740c8f) / retry-소진 fallback_model(C 이전 기존기능) / 프롬프트 POLARITY 지시(C 도입분).
- Verify: ruff clean, 핵심 17+광역 236 passed. 실측 A/B(orch): 폴라리티 정답 유지+translate 14.7s→1.9s(-87%)+왕복 -72%.

### 2단계 — 4레이어 프롬프트 이중부정 현황+개선안 표 (read-only, 수정 GO 대기. 원본=/tmp/v6-a1-stage2-prompt-table.md)
| 레이어 | 정본 프롬프트 파일 | 현행 이중부정 지시 | 개선안(초안) | 리스크 |
|--------|-------------------|-------------------|--------------|--------|
| STT | groq/fireworks 프롬프트 파라미터 미사용(language만, groq.py:61-64·fireworks.py:90). gpu_stt 없음. gemini.py:32 `_TRANSCRIBE_PROMPT`(verbatim)만 | 없음(verbatim=사실상 보존계약) | **변경 0 권고** — 음향층 폴라리티 지시는 prompt-bias로 안 들린 부정어 "생성" 환각 위험이 역으로 큼 | 개선 시도 자체가 리스크. 비적용이 정답 |
| splitter | composable/profiles/sentence_splitter.yaml(216L v2.2.0 structure-only) | 없음 — 단 RULE3(수정금지)+RULE6(TEXT INTEGRITY 전단어 1회 보존)이 구조적 보존 | (a)최소=변경0 (b)보강=ko few-shot 1개(`안 드시면 안 돼요 물도 안 됩니다`→2문장, 중간절단 방지 확인) | ~2100토큰 예산·min_cache_tokens=2048 계약(약한 예시 교체로만, append 금지). 캐시 무효화→cold start |
| polish | ①Loom: polish.yaml:66-71 ②정적: polish.py:37 §3a | **있음(양쪽, B커밋)**: NEGATION INTEGRITY — 반전금지+안/않/못/없/아니/말-/금지 보존+"안 드시면 안 돼요"=MUST eat 명시+simplify 금지+모호시 무변경 | **현행 유지**(이미 정본) | polish.kr.yaml엔 부재 — 단 compose.py:167 `f"{profile}.yaml"` 고정경로라 .kr.yaml은 코드 미소비(dead 추정, 소비처 0). 스코프 밖 |
| translate | ①Loom: translate.yaml:58-66 POLARITY ②정적: translation.py:211 ③per-request `[POLARITY NOTE]` 힌트(C 도입·보존) | **있음(3중, C커밋)**: 이중부정=의무(must X), 금지(must not X) 렌더 금지+단일부정=금지 유지 | (a)최소=변경0(3중+F가드=4중 방어) (b)**보강=translate.yaml EXAMPLES에 few-shot 1쌍**: `안 드시면 안 돼요→You must eat.`+대조쌍 `드시면 안 돼요→You must not eat.` (flash-lite는 지시문보다 few-shot 순응도↑ — 3.1 전환 대비) | few-shot 추가 시 토큰 예산+캐시(1h) 재웜업. translate.kr.yaml도 POLARITY 부재하나 미소비 추정 |

**종합 권고**: ①translate few-shot 1쌍 추가(실효 최대·변경 최소) ②splitter/polish/STT 변경 0 ③(스코프밖) .kr.yaml 2종 dead 추정 — 별도 정리 이슈.
방어 스택 전체상 = 프롬프트(polish §3a+translate 3중)×결정적 가드(polish D4b+translate F `_double_neg`) 2축, 모델 무관 — 폴백 금지 영구규율 정합.
**다음**: 오빠 GO→(채택 시) 수정→Tester 재라이브→A-1 종결→B-1(변이DUP B변이).
