# SPEC — tmux 세션명 전역 규칙 + tmm·tmuxc·tmux 현황 (r5 · ft-harness-arch#1 · 2026-10-05 · 조각 P6)

> **건드리는 정본**: `ft-role-spawn.sh:35~39`·`ft-nano-spawn.sh:92~94`(이름 생성) · 팀 `*-env.sh`(`FT_NANO_PREFIX`·`FT_ACTIVE_TAG`) · `tmm` `cat_of`(카테고리 추출) · `~/.tmm/categories` · 명부 생성기 설계(P1 §3-1 「계보 접두 = 회원 판정」) · zombie-clean keep-last-2 계보 파싱. **이름 변경·kill·파일 수정 0 — 규칙 문서만.**
> **전제 조각**: P1 `DESIGN-harness-composition`(e184bc1f57 · seats.live.json 생성기 · 계보 접두 회원 판정) · P2 `SPEC-main-orch-tree`(37e19724b5 · 7 오케 세션명 실측) · P3·P5(나노·큐 — 이름이 팀·역할·계보를 말해야 슬롯·큐 대조가 자동이 된다).
> **핵심 한 줄 기여**(GOAL-harness 원문 7 「큰일을 쪼개서 동시에」): 동시에 도는 세션이 많아질수록 **이름만 보고 팀·역할·계보·임시 여부를 알아야** 모니터(tmm)·슬롯(ft-nano-slots)·정리(zombie-clean)·명부(생성기)가 사람 손 없이 맞는다 — 이 조각은 «동시 처리 폭»을 떠받치는 식별 층이다.
>
> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) — 세션 이름이 일관돼야 명부·모니터가 이름만 보고 팀·역할·계보를 안다. 닫는 증거 = DA APPROVE + 오빠 「맞다」. 발주 = ops#2 `ORDER-session-naming`(#57004). 오빠 지시: 「tmm tmuxc tmux 확인, 시스템 세션명 전역 규칙도 일관성 있고 명확하게」.
> r4→r5(오빠 Q6 값 #57031): tmm 탭 묶음 = 팀 이름 · 접두 제거 목록 `FB_ ft- byz- kakao- rag-`(빈 값 금지) → 질문 0 · P6 수락.
> r3→r4(오빠 P6 값 #57024 · VALUES 하단): Q2 master · Q3 nano · Q4/Q5 추천 그대로 · **Q1 변경 = 맨 앞 «프로젝트(주제) 토큰» 필수**(byz·kakao·rag …) → 문법 `<프로젝트>-<팀>-<역할>[-<꼬리>]#N` · 예시표·매핑표·생성기·tmm 그룹 키 정정 · 새 질문 1(tmm 그룹 키).
> r2→r3(DA APPROVE 뒤 nano FACTS-session-naming 반영 · 사실 추가만): §1-C 7 태그 하드코딩 · 문법 9종.
> r1→r2: DA r1(`DA-session-naming-r1.md` HOLD 4) 반영 — ①슬롯 식별 = 명부 role·정확 키 조인(접두 아님) ②나노 접두는 세대별 유지 · 구 나노 0 뒤 전환 ③계보 매핑표 1장(구→신) 을 번호 배정·keep-last-2·생성기가 같이 읽음 · 에이전트 꼬리 필수 ④tmm `TMM_CAT_STRIP` 빈 값 = 기본 복원 · 불규칙 이름 7 은 매핑표 행으로.
> 실측 15:4x KST: arch 직접(`tmux ls` · tmuxc 0.4.0 · tmm 0.7.3 · spawn 스크립트 · env) + nano#1 `FACTS-session-naming-20261005.md`(발주 #57005 · 도착 시 §1 수치 보정). [사실]/[제안]/[추측].

## 1. 현황 [사실]

### 1-A. 세션 전수 — 이름 문법 분류 (`tmux ls` 31 세션 · 15:4x)
| 문법 | 예 | 건수 | 누가 만드나 |
|---|---|---|---|
| `ft-<팀>-<역할>-<에이전트>#N` | `ft-v65-master-claude#136` · `ft-v65-arch-claude#155` · `ft-v65-tester-claude#13` | v65 4 · airag 3(`ft-airag-master`·`ft-airag-helm-claude`) | `ft-role-spawn.sh:35` `BASE_NAME="ft-v65-$ROLE-$AGENT"` · `:38` 빈 번호 탐색 `N=maxn+1` |
| `ft-<팀>-<역할>#N`(에이전트 생략) | `ft-harness-ops#2` · `ft-harness-arch#1` · `ft-harness-da#1` · `ft-harness-nano#1` · `ft-issue-manager#0` · `ft-kakao-arch#*` · `ft-kakao-nano#*` | harness 7 · issue 1 · kakao 7 | 사람·오케가 `tmuxc open --name` 직접 |
| `ft-<팀>-temp-<slug>#0`(나노) | `ft-v65-temp-m7-p90-lang-update-gap-decomposition#0` | v65 2 | `ft-nano-spawn.sh:92` `BASE_NAME="${FT_NANO_PREFIX:-ft-v65-temp-}$SLUG"` · env: issues `ft-issues-temp-` · harness `ft-harness-temp-` · kk `ft-kk-temp-` |
| `FB_<팀>#N` | `FB_CFO#52` · `FB_CCU#12` | 2 | 사람(구 문법 · cfo·ccu 오케) |
| `<팀>_<역할>#N` | `CFO_OPS_ARCH#2` · `CCU_NANO#25` · `DATA_PG#4`(명부·mbox 로그에만 · 세션 0) | 0 (명부 22행) | 사람(구 문법 · cfo·ccu 하위) |
| `byz-<팀>-<역할>#N` | `byz-planner-arch#3`(`#1` 잔존) | 2 | 사람(planner 개설 10-03) |
| 기타 | `repro-e2e#0` · `KakaoBot*` 2 · `tmm` 1 | 4 | 사람 |
[사실] 같은 팀에 문법 둘: **cfo·ccu = `FB_` 오케 + `<팀>_` 하위** vs **v65·harness·issues·kakao = `ft-`**. planner 만 `byz-`. 한 팀 안에서도 역할 좌석은 `ft-v65-arch-claude` 인데 나노는 `ft-v65-temp-` 로 「역할」 자리에 `temp` 가 온다.

### 1-B. 도구가 이름을 다루는 방식
| 도구 | 하는 일 | 근거 |
|---|---|---|
| tmuxc 0.4.0 | `open --name` 은 받은 이름 그대로 · 이미 있으면 `die "session already exists"` · **자동 `#N` 증가 없음**(계보 번호는 호출자 책임) · target 은 `=$name` 접두로 `#` 충돌 회피 | `tmuxc:526·686` |
| ft-role-spawn | `ft-v65-$ROLE-$AGENT#N` · N = 같은 BASE 의 최대+1(빈 자리 재사용 0) — **`v65` 리터럴** | `:35~39` |
| ft-nano-spawn | `${FT_NANO_PREFIX}$SLUG#$N` · 접두는 env · slug 는 카드 파일명 | `:92~94` |
| tmm 0.7.3 | 카테고리 = `~/.tmm/categories` 글롭 → 없으면 **접두 `FB_`·`ft-` 를 떼고 첫 토큰(-/_ 앞) 소문자** · `#N` 은 비교 전에 뗌 · 폭 넘치면 가운데 접고 `#N` 보존 | `tmm:183~200 · 292` · categories: `KakaoBot→kakao` `cfo_*→CFO` `DATA_PG→LOOM` |
| 명부 | `seats.json` 행 키 = 세션명 그대로 · `_replaced_by` 로 계보 · `_name: Seatbelt-<TEAM>` | 6 파일 |
| 태그 | `@zc_<팀>_active`(env `FT_ACTIVE_TAG` · 기본 `@zc_v65_active`) — 이름이 아니라 tmux user option | env 4 · ft-nano-close:378 |
| 슬롯 | `ft-nano-slots.sh:48~53` — 나노 = **명부 행 `role==nano` 이고 `_replaced_by` 없는 키 ∩ `tmux ls` 정확 키**(접두로 식별하지 않는다) · 접두(`FT_NANO_PREFIX`)를 쓰는 곳 = **spawn(이름 생성 :92)** · **close(:24 `$NANO_PREFIX*` 만 수락 · 워크트리·브랜치 키 = 이름에서 접두를 뗀 slug)** | arch 직접(DA r1 ①②) |
| 정리 | keep-last-2 = 「역할별 베이스명 + `#N` 계열」(글로벌 CLAUDE.md) — 베이스명 = `#` 앞 전체 문자열 | zombie-clean · closeout-policy |

### 1-C. 어긋나는 곳 [사실 → 함의]
1. **팀 토큰 위치가 둘**: `ft-<팀>-…`(2번째) vs `FB_<팀>`·`<팀>_<역할>`(1번째) → tmm 은 접두를 떼서 맞추지만 명부 생성기(P1)는 「계보 접두」를 팀마다 두 개 알아야 한다.
2. **역할 자리에 `temp`**: 나노는 역할 토큰이 아니라 임시 표시 → 「역할 = 3번째 토큰」 규칙이 나노에서 깨진다 · 나노 식별은 명부 role(슬롯)과 접두(spawn·close)로 **둘**이라 어느 한쪽만 바꾸면 어긋난다.
3. **에이전트 토큰 유무**: `ft-v65-master-claude#136` vs `ft-harness-ops#2` → 같은 역할 좌석인데 토큰 수가 4/3 · 접두 글롭이 달라진다.
4. **`#N` 의미 둘**: 역할 좌석 = 승계 번호(계보 · keep-last-2 대상) · 나노 = 거의 항상 `#0`(카드 1 = 세션 1 · 재spawn 때만 +1) → 같은 기호가 「세대」와 「재시도」를 뜻한다.
5. **planner 만 `byz-`**: 「프로젝트 접두」가 하나 더 생김 · tmm 폴백은 `byz-` 를 안 떼므로 카테고리가 `byz` 가 된다 [추측 — 규칙 파일에 planner 행 없음 확인 필요 · nano N3].
6. **리터럴 `v65`**: `ft-role-spawn.sh:35` 는 팀 토큰이 고정 → 다른 팀 역할 좌석은 손으로 이름 짓는다(1-A 2행 전부).
7. **태그 하드코딩**(nano N4 · DA APPROVE 뒤 사실 추가): spawn 은 `FT_ACTIVE_TAG`(팀별)로 태그를 붙이는데 `ft-nano-close.sh:378` 은 `@zc_v65_active` 리터럴로 뗀다 → 다른 팀 나노는 close 가 태그 해제 FAIL(세션 잔존) · 문법 9종 혼재(v65·kakao 는 팀당 2문법) — §2-C `ft-nano-close` 행의 전환 조건에 「태그도 env 로」 1구 추가 대상(구현 조각).

## 2. 제안 [제안]

### 2-A. 이름 문법 1개
```
<프로젝트>-<팀>-<역할>[-<꼬리>]#<N>
  프로젝트 = 주제 토큰 · 소문자 (byz = BYZ 에이전트 · kakao · rag …) — 필수(오빠 10-05 값)
  팀   = 소문자·숫자 (v65 · cfo · ccu · kk · planner · harness · issues · kakao · airag)  — 명부 파일 seats-<팀>.json 과 같은 글자
  역할 = master | arch | da | tester | checker | analyst | pm | nano | repro | tool | desk   — 예약어 11 · 추가는 이 표에만 (desk = planner 팀 사람 대응 좌석 · R205 · 오빠 판정 1779)
  꼬리 = 소문자·숫자·'-' · nano 는 카드 slug(필수) · 역할 좌석은 에이전트(claude|codex|opencode|cmd|pi) **필수**(선택이면 계보가 둘로 갈린다 — DA r1 ③)
  #N   = 계보 번호 · 역할 좌석: 승계마다 +1(keep-last-2 단위) · nano: 재spawn 횟수(0 부터)
  구분자 = '-' 만 · '_'·대문자·공백 0 · 길이 ≤ 60(tmm 가운데 접기 전 전체가 ls 에 보이게)
```
- 접두 `ft-`·`FB_` 는 **없애고** 대신 첫 토큰 = **프로젝트**(오빠 값). 둘째 = 팀. 명부 생성기의 계보 키 = `<프로젝트>-<팀>-<역할>[-<꼬리>]`. tmm 폴백(첫 토큰 = 카테고리)은 이제 **프로젝트**를 잡으므로 팀 그룹이 깨진다 — §2-C tmm 행 · Q6.
- `temp` 는 역할 `nano` 로 바꾼다 — 「임시」는 역할이 아니라 생애(카드 1 = 세션 1)이고, 그건 `#N` 과 명부 `role` 이 말한다.

### 2-B. 예시 표
| 팀 | 오케 | arch | da | nano | tester |
|---|---|---|---|---|---|
| v65 | `byz-v65-master-claude#137` | `byz-v65-arch-claude#156` | `byz-v65-da-codex#0` | `byz-v65-nano-m7-p90-lang-update-gap#0` | `byz-v65-tester-claude#14` |
| cfo | `byz-cfo-master-claude#53` | `byz-cfo-arch-claude#3` | `byz-cfo-da-codex#2` | `byz-cfo-nano-f-nano-27#0` | `byz-cfo-tester-claude#0` |
| ccu | `byz-ccu-master-claude#13` | `byz-ccu-arch-claude#18` | — | `byz-ccu-nano-r6-n10#0` | — |
| planner | `byz-planner-master-claude#4` | — | `byz-planner-da-codex#1` | — | — |
| harness | `byz-harness-master-claude#3` | `byz-harness-arch-claude#2` | `byz-harness-da-codex#2` | `byz-harness-nano-facts-session#0` | — |
| issues | `byz-issues-master-claude#1` | — | — | `byz-issues-nano-<slug>#0` | `byz-issues-repro-claude#0`(= repro-e2e) |
| kakao · rag | `kakao-bot-master-claude#0` · `rag-airag-master-claude#3` | `kakao-bot-arch-claude#2` | `kakao-bot-da-codex#1` | `kakao-bot-nano-<slug>#0` | — |
(프로젝트 토큰 = byz(BYZ 에이전트) · kakao · rag — 카톡·rag 도 앞으로 주제를 앞에 붙인다(오빠 값). 오케 역할명은 `master` 로 통일 — `ops`·`FB_`·`planner-arch` 처럼 팀마다 달랐던 오케 호칭을 하나로. planner 의 지금 좌석 `byz-planner-arch#3` 은 역할이 「오케」이므로 `planner-master`.)

### 2-C. 기계와의 연결
| 기계 | 바뀌는 것 | 왜 |
|---|---|---|
| 계보 매핑표(신설 · 설계만) | `.fable-team/lineage-map.tsv` 행 = `구 베이스명<TAB>신 베이스명`(예 `ft-v65-master-claude → byz-v65-master-claude` · `ft-harness-ops → byz-harness-master-claude` · `ft-issue-manager → byz-issues-master-claude` · `byz-planner-arch → byz-planner-master-claude` · `FB_CFO → byz-cfo-master-claude` · `FB_CCU → byz-ccu-master-claude` · `repro-e2e → byz-issues-repro-claude` · `KakaoBot → kakao-bot-master-claude` · `ft-airag-master → rag-airag-master-claude`) · **읽는 곳 3 = 번호 배정 · keep-last-2 · 명부 생성기** — 셋이 같은 표를 읽어야 계보가 하나다 | 접두 떼기·뒤집기 1줄로는 불규칙 7 이 안 맞는다(DA r1 ④) · 번호·정리·회원이 각자 파싱하면 계보가 셋 |
| `ft-role-spawn.sh` | `BASE_NAME="${FT_PROJECT}-${FT_TEAM}-$ROLE-$AGENT"`(리터럴 `v65` → env) · **N = max(신 베이스 N, 매핑표의 구 베이스 N)+1** | 지금은 정확 베이스만 세어 신 문법 첫 좌석이 `#0` 으로 떨어진다(DA r1 ③) |
| `ft-nano-spawn.sh`·`ft-nano-close.sh` · env | `FT_NANO_PREFIX=<프로젝트>-<팀>-nano-` 전환은 **그 팀의 구 접두 나노 세션이 0 일 때만**(나노는 카드 1 = 세션 1 이라 자연 소멸) · 전환 전엔 구 값 유지 · 전환 뒤 구 나노가 남아 있으면 close 가 `$NANO_PREFIX*` 불일치로 REJECT 하므로 **그 세션만 구 env 로 close** | close:24 는 단일 접두만 수락 · 워크트리·브랜치 키가 접두 제거 slug 라 허용 목록으로 풀면 키가 바뀐다(DA r1 ②) |
| 명부 생성기(P1 B1) | 회원 판정 = **매핑표로 정규화한 뒤** 첫 토큰 == 프로젝트 **그리고** 둘째 토큰 == 팀 · 역할 = 셋째 토큰 · 계보 = 정규화 베이스명 · 번호 = `#N` · 팀 ↔ 명부 파일은 표 1행(`v65 → seats.json`(seats-v65 없음) · `ccu → 없음(P2)` 명시) | 명부 파일명으로 팀을 추론할 수 없다(DA r1 ④) |
| tmm | [사실] 폴백 = 접두(`FB_ ft-`) 제거 뒤 **첫 토큰**(-/_ 앞 8자) = 카테고리 → 신 문법에선 첫 토큰이 `byz` 가 되어 **모든 BYZ 팀이 한 탭**으로 뭉친다(팀 그룹 깨짐) · `~/.tmm/categories` 글롭이 폴백보다 우선 · 그룹 키 8자(:201) · 열 표시 5자 | 제안 = **그룹 키 = 팀**(둘째 토큰) · 방법 ⓐ `TMM_CAT_STRIP` 에 프로젝트 접두 추가(`FB_ ft- byz- kakao- rag-` — 빈 값 금지 · 기본 복원 함정) → 폴백이 둘째 토큰을 잡음 ⓑ `categories` 에 `byz-v65-*→v65` 식 글롭 행(팀 수만큼) · **어느 쪽이든 폰 화면 5자 라벨 = 팀** · 다른 프로젝트 팀명이 겹치면(`kakao-bot` vs `byz-bot`) 라벨에 프로젝트 1자 접두(Q6) |
| zombie-clean keep-last-2 | 계보 키 = **매핑표로 정규화한** `#` 앞 베이스명(구·신을 한 계보로) · nano 역할 면제(10-02 승인 그대로) | 정규화 없이는 구 2 + 신 1 을 다른 계보로 봐 3 을 남기거나, 신 1 만 보고 구를 지운다(DA r1 ③) |
| `ft-nano-slots.sh` | 변경 0 — 식별이 명부 role·정확 키라 이름 문법과 무관 · 단 명부 행 `role` 이 비면(v65 #135 실례) 안 보이므로 생성기(P1)가 role 을 채워야 한다 | DA r1 ① |

### 2-D. 이행 — 신규만 적용 · 기존 이름은 허용 목록
1. **지금 살아 있는 세션은 이름을 바꾸지 않는다**(rename·kill 0 · 승계 때 자연 교체). 이행 기간 동안 번호 배정·keep-last-2·명부 생성기·tmm 별칭은 **매핑표 1장**(2-C 첫 행)으로 구 이름을 신 베이스로 정규화해 읽는다 — 규칙 1줄이 아니라 표다(불규칙 7).
2. 새 역할 좌석은 승계 때부터 새 문법(`ft-role-spawn` 리터럴 1곳 + 매핑표 N 계승). **나노 접두 전환은 팀별로 「구 접두 나노 0」 뒤에**(2-C) — 역할 좌석과 나노의 전환 시점이 다르다.
3. 계보 번호는 이어 받는다: `ft-v65-master-claude#136` 의 후계 = `v65-master-claude#137` — 번호 배정이 매핑표의 구 베이스 N 을 같이 센다(2-C) · 명부 `_replaced_by` 가 구→신 다리 · keep-last-2 도 같은 표로 구·신을 한 계보로 센다.
4. 끝나는 조건 = 구 문법 세션 0 + 명부 전 행 새 문법 → 허용 목록·별칭 규칙 삭제(구조 커밋 1).

## 3. 오빠 값이 필요한 질문 (최대 5 · 추천안 첫째)
| # | 질문 | 추천 | 대안 |
|---|---|---|---|
| Q1 ✅ | 프로젝트 접두 | **오빠 값: `ft-`·`FB_` 없애고 맨 앞 프로젝트(주제) 토큰 필수**(byz·kakao·rag) | — |
| Q2 | 오케 역할명 | **`master` 통일**(planner 도 `planner-master`) | 팀별 호칭 유지(`ops`·`planner-arch`) |
| Q3 | 나노 토큰 | **`nano`**(temp 폐기) | `temp` 유지 |
| Q4 | 에이전트 꼬리 | **역할 좌석은 붙인다(`-claude`·`-codex`) · 나노는 slug 만** | 전부 생략(명부에만) |
| Q6 ✅ | tmm 탭(카테고리) 그룹 키 | **오빠 값(#57031): 팀 이름(둘째 토큰) · `TMM_CAT_STRIP` 접두 제거 목록에 `byz-`·`kakao-`·`rag-` 추가**(글롭 행 0) | 프로젝트(첫 토큰 · BYZ 전 팀 한 탭) / 프로젝트+팀 라벨(`b-v65` · 5자 한계) |
| Q5 | 이행 | **신규만 · 기존 허용 목록 · 승계 때 자연 교체** | 한 번에 rename(HIL · 세션 31 중단 위험) |

## 4. DA 요청 범위 (r2 = 수정 검토 1회 · 10분 · bounded)
r1 발견 4 반영 여부(§1-B 슬롯 행 · §2-A 꼬리 필수 · §2-C 매핑표·접두 전환 조건·N 계승·tmm 행 · §2-D 1~3) + 직접 회귀만. 이전 질문: §1~§2 만. 질문 1 「§1-A/1-B 사실이 명령·파일과 맞나(세션 31 · tmuxc·tmm 줄 번호)」 · 질문 2 「§2-A 문법이 §1-C 어긋남 6 을 전부 닫나 · 이행(2-D) 중 두 문법 공존이 keep-last-2·슬롯·tmm 을 깨는 자리」. HOLD 2회 = 직렬 DA 종료 → ops 통합 수락.
