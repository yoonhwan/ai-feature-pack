# factpack-carry.md
# v6 missing-track: carry/splitter drop 메커니즘 규명 (chk-carry, 2026-07-08)
# 대상: v6-partdb-verify-5r (R1~R5) + HIL 웜탭(38801 EN / 38802 KO)

## 1. 관찰 대상 및 로그 범위

| 라운드 | EN press (ptt) | KO press (ptt) | 로그 시각 |
|--------|---------------|---------------|---------|
| R1 | cf23dd95 | d7c468cf | 14:58~14:59 |
| R2 | 8e14c06f | e97ba6fe | 15:06 |
| R3 | 8c221b47 | b673d67f | 15:08~15:10 |
| R4 | dafc03f1 | f2f73cab | 15:11~15:12 |
| R5 | (result.json 최종) | — | 15:12~15:13 |
| 웜탭 EN | e71a1881 | — | 17:31~17:32 |
| 웜탭 KO | — | 8ec1df71 | 17:32~17:33 |

## 2. 관찰 축 결과 요약

- D-1 carry 단조 비감소 ✓ 전 구간 (최대 502, cap 3000 미도달, [carry.cap]/[carry.tail] 미발생)
- EN "smallest customer segment": R1 missing(A型) / R2 missing(B型) / R3 포함(B型+완전문장 회복) / R4 missing(B型) / 웜탭 missing(B型)
- KO: R1 "배포 이후로" / R2 "교차 확인" / R3·R4 CLEAN / 웜탭 "교차 확인"(C型-tail)

## 3. 메커니즘 규명: 유형별

### A型 — STT 수신 + 동일 청크 demote_skip + residual 강제 0
대상 문장 STT가 직전 청크에서 수신 → tail 청크 no_speech_tail suppressed → demote_skip → press_end final_boundary residual=0 강제 → D-2 flush 대상 없음.
사례: R1 EN c9b4e944 "Smallest customer segment".
시그니처: `no_speech_tail suppressed` → `demote_skip` → `final_boundary residual_len=0`.

### B型 — no_speech_tail + press_end 잔여 tail 부분 미흡수
마지막 의미 청크 후 82자 residual → tail 청크 gpu ""+groq "" 거부 → no_speech_tail → press_end에서 49~50자만 완전 문장으로 확정, 32~33자 tail 탈락.
**회복 조건**: R3 — 82자 residual이 완전 문장 형성 시 force_finalize 전량 흡수(확률적 회복, 문장 완결 여부에 의존).
사례: R2/R4/R5 EN, 웜탭 EN ②(0758e0e0, L16032~L16110, prev 348→398(+50), 32자 탈락).

### C型-mid (신규) — splitter가 누적 residual 처리 중 중간 텍스트 silently drop
- 순수 누적(prev=0, res 0→47→102→131→184)으로 184자 residual = S1(129)+S2_partial(55, "After digging through the logs for almost two hours,")
- 다음 청크 f9396bb8 STT="Someone finally noticed that the...."(33자) → splitter가 S1 confirm + new_residual=33자(신규 STT만) → **중간 55자 bridge text silently dropped**
- demote_skip: splitter_residual(33) matches delta → keeps 33
- 사례: 웜탭 EN ① e71a1881/f9396bb8 (L15423~L15535). **"중간 문장 통째 소실" — 신규 유형, STT 수신됐음에도 발생.**

### C型-tail (신규) — STT 수신 후 다음 청크 splitter가 tail drop + residual=0
- 779628ed STT="교차 확인하는 데 큰 도움이 될 것입니다."(23자 수신) → res=62
- 0d2490d4 처리: splitter가 앞 36자("혹시 비슷한...알려주시면.")만 confirm → residual=0 고정 (demote_skip splitter_residual=0)
- **tail 23자 "교차 확인..." DROPPED** → 이후 e571502b no_speech_tail → final_boundary confirmed_len=214
- 사례: 웜탭 KO 8ec1df71/0d2490d4 (L16992~L17068).

## 4. 유형별 발생 조건 표 (설계 입력용)

| 유형 | STT 수신 | drop 위치 | 트리거 조건 | demote_skip splitter_residual | 사례 |
|------|---------|----------|-----------|------------------------------|------|
| A型 | ✓(이전 청크) | tail | 대상 포함 residual + tail 청크 no_speech_tail + press_end res=0 | 양수 | R1 EN |
| B型 | ✗ no_speech_tail | tail | 82자 residual + tail 양쪽 STT 거부 → 49~50자만 흡수 | 발동 | R2/R4/R5 EN, 웜탭 EN② |
| C型-mid | ✓(누적 청크) | **중간** | 대형 누적 residual(>130자)+신규 STT 후반 제공 → splitter 경계 재확정 시 bridge 탈락 | =신규STT 길이 | 웜탭 EN① |
| C型-tail | ✓(직전 청크) | tail | STT 수신으로 residual 증가 → 다음 청크 splitter가 앞부분만 confirm+res=0 | =0 | 웜탭 KO |

### 공통 전제 (전 유형)
- carry prev_len 충분히 누적(context pressure)
- demote_skip 발동("splitter_residual matches delta_sentences")
- translate_raw sentences=1(부분 확정)
- final_boundary residual_len=0

### C型 특이 (A/B型 미발생)
- **STT 수신 = 데이터 보존 가정 위반** — splitter의 sentence boundary 재확정이 residual 내 텍스트를 고아로 남김
- 트리거: 순수 누적 130자+ 후 새 STT 청크 제공 시점

## 5. 수정 방향 힌트 (관찰 기반)

- **B型 근본**: press_end force_finalize가 residual을 완전 문장 기준으로 절단 → 경계 틀리면 tail 탈락. press_end 통째 flush 또는 D-2 carry.tail 강화 필요.
- **C型 근본**: splitter가 누적 residual 처리 시 중간/후미 텍스트 삭제 — demote_skip이 "keeps previous residual"이라 하나 실제로는 splitter 출력(짧은 residual)을 유지. **residual 합집합 보존 정책** 또는 splitter residual이 이전보다 짧아질 때 병합 로직 필요.
