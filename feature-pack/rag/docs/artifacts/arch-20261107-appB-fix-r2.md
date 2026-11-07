최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — C12(consumer 상시 서비스 회복) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 — C12. 안 B 서명 인증서(h-S1 = h8) 결과가 사전 약속 표 밖 행 → 설계 보정 r2 1장.

# AIRAG.app 설계 보정 2회차: 신뢰 설정 누락 (arch-20261107-appB-fix-r2)

- 작성: aifp-airag-arch-claude#3 (Opus 5.5) · 발주 #3594 (aifp-airag-master-claude#12) · 2026-11-07
- 정본 경로: `feature-pack/rag/docs/artifacts/arch-20261107-appB-fix-r2.md`. architect 쓰기 허용 경로(ft-worker-guard: designs·state)가 아니라서 이 파일을 `.fable-team/state/airag/` 에 썼다. master 가 정본 경로로 옮겨 싣는다.
- 입력: planner 판정 `verdict-h8-h9-h10-arch43-20261107.md` §h8 · 사실 팩 `facts-h8-h9-20261107.md` · `/tmp/h8.out` · 설계 `arch-20261029-appB-fix-r1.md` §3-1·§10-2·§10-7 · `arch-20261029-appB.md` §3-3·§5·§6 · 코드 `feature-pack/rag-consumer/macos/build.sh` (읽기만, HEAD 5130185e)
- 이 문서가 한 실행: 파일 읽기뿐이다. 키체인, 신원, codesign, security 쓰기, op, 설치는 0회다.

## 0. 결론

1. **고른 안 = 선택지 1 («서명만 h» 1개, 이름 h-S2).** 코드 변경은 0이다. h-S1 이 만든 신원을 그대로 쓴다.
2. 원인: 설계에 신뢰 설정 단계가 없다. 이것은 맞다. 하지만 이것이 «결함»인지는 아직 모른다. §10-7 의 통과 측정(`find-identity -v`)이 실제 요구보다 강했다. 요구(§3-1)는 «같은 키로 창 없이 서명»이지, «시스템이 신뢰하는 신원»이 아니다.
3. 선택지 2(`add-trusted-cert`)는 지금 고르지 않는다. 사용자 신뢰 설정을 바꾸면 인증 창이 뜬다고 알려져 있다. 그러면 오빠가 로그인 비밀번호를 쳐야 한다. 이것은 §3-1 «창 0» 과 §10-7 «창 = 실패» 를 바꾸는 일이다. 그래서 h-S2 가 `NOT_TRUSTED` 로 실패할 때만 오빠 결정을 거쳐 연다(§4).
4. h-S2 사전 약속 표는 14행이다(§3). 위에서부터 처음 맞는 행 하나만 쓴다. 마지막 행이 나머지 전부를 받으므로 표 밖 행은 없다.
5. 나노 범위: h 계획 파일 1개 작성과 사전 측정 2개(§5). build.sh 와 시험 코드는 바꾸지 않는다.
6. DA 소환 = 아니오. 이유: 행위 변경 0 이고, 판정은 사전 약속 표와 실측이 한다(§6).

## 1. 원인 확인

| # | 사실 | 근거 |
|---|---|---|
| F1 | h-S1 rc 0. 신원 «AIRAG Local Signing» 이 전용 키체인에 생겼다. | `/tmp/h8.out` 1행 |
| F2 | `-v`(유효만) 개수 0, `-v` 없이 1개, 사유 `CSSMERR_TP_NOT_TRUSTED` | 사실 팩 master 실측 |
| F3 | build.sh 단계 5 는 create-keychain, unlock, import(`-T /usr/bin/codesign`), set-key-partition-list 넷이다. 신뢰 설정은 없다. | `build.sh:291-305` |
| F4 | 인증서는 자체 서명 잎이다. `extendedKeyUsage=critical,codeSigning`, `CA:false`. 그래서 신뢰 평가에서 «뿌리를 신뢰하지 않음» 이 나오는 것이 정상이다. | `build.sh:211-232` |
| F5 | 서명 경로(`sign_app`)는 `find-identity` 를 부르지 않는다. 이름과 `--keychain` 으로 codesign 을 바로 부르고 `codesign --verify --strict` 로 끝난다. | `build.sh:197-206` |
| F6 | 설계 요구는 «같은 개인키·인증서로 서명 → 지정 요건이 같음 → TCC 허용 유지» 와 «창 0» 이다. 신뢰는 요구에 없다. | fix-r1 §3-1 · appB §3-3 |
| F7 | h-S1 때 창이 떴는지 기록이 없다. | 사실 팩 «[확인 필요: 오빠께 창이 떴는지]» |

판단:
- 「신뢰 단계가 설계에 없다」는 사실이다(F3). 구현은 설계대로다.
- 그러나 `-v` 0 이 «서명 불가» 를 뜻하는지는 모른다. `-v` 는 신뢰 평가를 통과한 신원만 센다(F2). codesign 이 신뢰 안 된 자체 서명 신원으로 서명하는지는 이 맥에서 실측 0 이다 [확인 필요: h-S2 가 가른다].
- 그래서 원인은 둘로 나눠 적는다. ① §10-7 의 통과 측정이 요구(F6)보다 강했다(측정 정의 누락). ② 서명에 신뢰가 실제로 필요하면 단계 5 에 신뢰 단계가 빠진 것이다(설계 누락). ①은 이 문서가 고친다(§2-1). ②는 h-S2 결과로만 정한다.
- TCC 가 신뢰 여부를 보는지도 모른다 [확인 필요]. 이것은 h-S2 범위가 아니다. appB §5 의 h-A·h-B 가 원래 가르는 질문이고, 그 표는 그대로 둔다.

## 2. 선택지 비교와 선택

| 항목 | 선택지 1: h-S2 «서명만» | 선택지 2: make-identity 에 `add-trusted-cert -p codeSign` |
|---|---|---|
| 코드 변경 | 0 | build.sh 새 단계 + 시험 단언 추가 |
| 창 | 0 예상(키 접근은 partition-list, op 는 R-H) | 신뢰 설정 인증 창 1회가 뜬다고 알려짐 [확인 필요: macOS 15.0.1 실측 0] |
| 오빠 손 | `!` 한 줄 1번 | `!` 한 줄 1번 + 로그인 비밀번호 입력(창) |
| 바뀌는 시스템 상태 | 없음(임시 폴더의 빌드 결과물만) | 사용자 신뢰 설정에 이 인증서가 «코드 서명용 신뢰» 로 들어간다 |
| 기존 규칙과 충돌 | 없음 | §3-1 «어떤 경로에서도 창 0», §10-7 «창 = 실패», appB K6 |
| 얻는 정보 | 신뢰 없이 서명되는지 직접 답한다. h-A 빌드 단계를 미리 검증한다. | 신뢰가 필요 없었다면 비용만 늘린다 |

**선택 = 선택지 1.** 신뢰가 필요한지 먼저 재고, 필요할 때만 창을 감수한다. h-S2 가 통과하면 h-A 의 빌드·서명 단계가 이미 검증된 셈이라 버려지는 일이 없다.

### 2-1. §10-7 표 보정 (h-S1 의 판정)

§10-7 1행의 «신원 1개» 측정을 `-v` 없는 개수(생성 확인)로 바꾼다. «쓸 수 있음» 판정은 h-S2 로 넘긴다. h8 결과를 표에 사전 약속 행으로 넣는다.

| 결과 | 판정 | 다음 |
|---|---|---|
| (기존 1행 대체) rc 0, `-v` 없는 신원 1개, `-v` 신원 1개, 창 0 | 생성 통과 | h-S2 |
| **(새 행 · h8)** rc 0, `-v` 없는 신원 1개(`NOT_TRUSTED`), `-v` 신원 0개, 창 0 | 생성 통과 · 사용 가능 여부 미정 | h-S2 |
| rc 0, `-v` 없는 신원 0개 | 실패 | 원문 → master → 보정 r3 |
| 나머지 기존 행(rc 33·31·34·35·36, 창) | 그대로 | 그대로 |

- 전제: h8 때 창이 0 이었어야 위 새 행이 맞다(F7). master 는 h-S2 를 드리는 같은 메시지에서 «h8 때 창이 떴었나요» 를 함께 확인한다. 떴다면 기존 «창 = 실패» 행이 먼저 적용되고 h-S2 는 보류한다.

## 3. h-S2 사전 약속 표

측정 항목(h 가 출력):

| 이름 | 뜻 | 얻는 법 |
|---|---|---|
| `rc` | `build.sh build` 의 종료 코드. 바깥 시간 상한에 걸리면 124 | 그대로 |
| `built` | 실행 파일 `AIRAG.app/Contents/MacOS/AIRAG` 이 있고 실행 가능하면 1 | `-x` 검사 |
| `class` | stderr 분류: `not_trusted`(`CSSMERR_TP_NOT_TRUSTED` 또는 `not trusted`), `not_found`(`no identity found`), `ambiguous`, `internal`(`errSecInternalComponent`), `word:<build.sh 고정 낱말>`, `other`, `none`(stderr 빔) | stderr 임시 파일 grep. 이 순서로 처음 맞는 것 |
| `authority` | 서명의 첫 Authority 가 «AIRAG Local Signing» 이면 1, 아니면 0 | `codesign -dvv <app>` |
| `verify` | h 가 따로 다시 돈 `codesign --verify --strict <app>` 의 rc | 그대로 |
| `dr` | 지정 요건이 인증서에 묶였으면 `cert`(`certificate root = H"` 또는 `certificate leaf = H"`), cdhash 만이면 `cdhash`, 없으면 `none` | `codesign -d -r- <app>` |
| `valid`·`matching` | airag 키체인의 `N valid identities found` 와 `N identities found` 의 N | `security find-identity -p codesigning <kc>` 1회(`-v` 없이 두 숫자가 다 나온다) |
| `win` | 창 여부와 종류(1Password·키체인 접근·TCC·그 밖) | 오빠 답 |
| `sec` | 걸린 초 | `$SECONDS` |

판정표 (위에서부터 처음 맞는 1행만 쓴다):

| # | 결과 | 판정 | 다음 |
|---|---|---|---|
| 1 | `win` ≥ 1 (종류 무관) | 실패 | 오빠는 «허용 안 함». 종류가 키체인 접근이면 K6 깨짐, 1Password·TCC 면 R-H 깨짐. 원문 → master → 새 카드 |
| 2 | `rc` 124 (바깥 상한 65초) | 판정 불가 | 원문과 `sec` → master. 나노가 빌드 초를 다시 재고 h 상한을 보정한 뒤 1회 |
| 3 | `rc` 32 | 판정 불가 | 토큰이 그 셸에 없다. 빌드 0 이다. 오빠 셸 확인 뒤 같은 h 1회 |
| 4 | `rc` 31 또는 34 | 판정 불가 | 같은 h 1회만 다시. 또 같으면 원문 → master |
| 5 | `rc` 35 | 실패 | 볼트 값으로 키체인이 안 열린다. 원문 → master → 보정 r3. 키체인 재생성은 HIL |
| 6 | `rc` 36 | 실패 | ID 파일·키체인 상태가 깨졌다. 원문 → master → 보정 r3 |
| 7 | `rc` ≠ 0, `built` 0 | 판정 불가 | 서명 전 빌드 실패라 신뢰와 무관하다. 빌드 원문 → 나노 진단 |
| 8 | `rc` ≠ 0, `class` = `not_trusted` | **신뢰 필요 확정** | §4 로 간다. master 가 오빠 인터뷰를 연다 |
| 9 | `rc` ≠ 0, `class` = `not_found` | 판정 보류 | 이름 검색이 유효 신원만 볼 수 있다. h-S2b 1회: `build.sh sign`(재빌드 0)을 `AIRAG_SIGN_IDENTITY=<SHA-1>` 로. 결과는 이 표로 판정하되, 9행에 또 걸리면 8행과 같이 §4 로 |
| 10 | `rc` ≠ 0, `class` = `internal` 또는 `ambiguous` | 실패 | 신뢰가 아니라 키 접근·중복 문제다. 원문 → master → 보정 r3 |
| 11 | `rc` 0, (`valid`,`matching`) ≠ (0,1) | 판정 보류 | h8 뒤 키체인 상태가 바뀌었다. master 가 읽기 실측 뒤 판정 |
| 12 | `rc` 0, `authority` 0 또는 `verify` ≠ 0 또는 `dr` ≠ `cert` | 실패 | 서명은 됐지만 우리 신원에 묶이지 않았다(K3 미충족). 원문 → master → 보정 r3 |
| 13 | `rc` 0, `authority` 1, `verify` 0, `dr` = `cert`, `valid` 0, `matching` 1, 창 0 | **통과** | 신뢰 없이 서명된다. 신뢰 단계는 넣지 않는다. 다음 = h10 설치본 교체 h → h-A(planner 판정 순서) |
| 14 | 위 어디에도 안 맞음 | 실패 | 원문 4줄 → master → 보정 r3 |

- 13행은 `valid` 0 을 통과 조건에 넣는다. 신뢰 없이도 된다는 것을 증명하는 행이기 때문이다.
- 9행의 h-S2b 는 같은 표를 다시 쓴다. h-S2b 에서는 9행의 «다음» 만 «§4» 로 바뀐다. 반복은 최대 1회다.
- 13행 뒤에도 TCC 가 신뢰를 보는지는 남는다. 그것은 appB §5 h-A·h-B 표가 그대로 가른다(4행 «책임 주체가 python·op» 등).

## 4. 8행이 나올 때: 선택지 2 와 «창 = 실패» 충돌 풀기

8행은 «신뢰 없이는 서명이 안 된다» 를 확정한다. 그때만 선택지 2 를 연다. 오빠 결정이 먼저다.

충돌 풀이:
- §10-7 «창 = 실패» 는 R-H 와 K6 이 깨졌는지 잡으려는 행이다. 대상은 1Password, 키체인 접근, TCC 창이다.
- 신뢰 설정 인증 창은 다른 종류다. 우리가 일부러 부른 단계 하나가 원인이고, 신원마다 1번만 뜬다. 빌드·서명 때는 뜨지 않는다.
- 그래서 규칙을 이렇게 나눈다. «빌드·서명 경로 창 0» 은 그대로 둔다. «신원 신뢰 단계 1회에 예고된 인증 창 최대 1개» 를 허용한다. 이 창에서만 오빠가 로그인 비밀번호를 친다. 다른 종류의 창은 여전히 실패다.
- 이렇게 바꾸면 오빠 손이 늘고, 사용자 신뢰 설정이 바뀐다. 그래서 master 가 오빠 인터뷰로 묻는다. 선택지: ① 신뢰 단계 허용(비밀번호 1회) ② 안 1C 로(로그인 키체인, fix-r1 §3-2) ③ Apple Developer ID(appB §3-3, 연 99달러).

①을 고르면 나노 카드(이 문서에서는 범위만 적는다):
- 새 하위 명령 `build.sh trust-identity`. make-identity 를 다시 돌리지 않는다. 지금 신원을 그대로 쓴다(볼트 항목·키체인 재생성 0).
- 동작: airag 키체인에서 인증서를 PEM 으로 꺼낸다(`security find-certificate -c "AIRAG Local Signing" -p <kc>`) → `security add-trusted-cert -r trustRoot -p codeSign -k <kc> <pem>` (사용자 도메인, `-d` 0). 실패면 새 rc 37 `trust_failed`.
- 시험: 가짜 `security` 가 인자를 기록한다. 단언은 `-p codeSign` 있음, `-d` 없음, 정책이 codeSign 하나뿐, 실패 시 rc 37, 값 출력 0(A1·A2 유지).
- DA 소환 = 예(시스템 신뢰 저장소를 바꾸는 행위).
- 그 뒤 h-S3(신뢰 설정 + h-S2 와 같은 측정)의 표는 그때 쓴다. 이번 범위가 아니다.

## 5. 사람 손 h-S2 와 나노 범위

### 5-1. h-S2 내용 (스크립트는 나노가 쓴다)

- 위치: `.fable-team/state/airag/h-s2-sign-only.sh` (rag-transplant 워크트리). master 가 `ft-hil.sh --add` 로 `! bash /tmp/h<N>` 한 줄로 드린다.
- 순서
  1. `set -u`. macos 폴더로 cd. 실패면 `h-S2 rc=2 cd_failed`.
  2. `OP_SERVICE_ACCOUNT_TOKEN_DEVELOP` 이 비면 `h-S2 rc=32 op_token_missing` 을 내고 끝낸다(빌드 0).
  3. 안내 1줄: «창이 뜨면 "허용 안 함" 을 누르고 결과 줄과 함께 알려 주세요».
  4. `AIRAG_SIGN_IDENTITY='AIRAG Local Signing'` 를 그 명령 앞 대입으로 주고 `timeout 65 bash ./build.sh build` 를 한 번 부른다. stderr 는 mktemp 파일로 받는다. `timeout` 이 없으면 `gtimeout`, 둘 다 없으면 상한 없이 부르고 결과 줄에 `nocap=1` 을 붙인다.
  5. §3 측정 항목을 읽기 명령으로 잰다.
  6. 결과 1줄: `h-S2 rc=<> built=<> class=<> authority=<> verify=<> dr=<> valid=<> matching=<> sec=<>`
  7. 원문 1줄: `h-S2 err: <stderr 첫 줄 200자 또는 ->`. build.sh 의 op 줄은 이미 scrub 을 거친다. codesign 문구에는 값이 없다.
  8. stderr 임시 파일을 지운다. `exit $rc`.
- 출력 줄: 안내 1 + build.sh 표준 출력 최대 1(`signed with identity: …`) + 결과 1 + 원문 1 = 최대 4줄.
- 예상 초: 빌드(`swiftc -O` 1파일) + op read 1회(최대 21초, build.sh `op_call` 이 아직 10.5×2) + codesign·측정 2초 안팎. 빌드 초는 실측이 없다 [확인 필요: 나노 사전 측정 P1]. 바깥 상한 65초 + 측정 = 70초 이내.
- 금지(스크립트에 없어야 함): `install`, `open`, `~/Applications` 변경, `make-identity`, `add-trusted-cert`, `security` 의 쓰기 명령(create·delete·import·set-*·unlock 직접 호출), `launchctl`, tick 실행. `rm` 대상은 자기 mktemp 파일 하나뿐이다.

### 5-2. 나노 발주 범위

| # | 일 | 파일·줄 | 확인 |
|---|---|---|---|
| N1 | h-S2 계획 파일 작성(§5-1 그대로) | 새 파일 `.fable-team/state/airag/h-s2-sign-only.sh` 1개 · 약 40줄 | `bash -n` · shellcheck(있으면) |
| N2 | 금지 명령 grep 단언 | 같은 파일 | §5-1 금지 목록 낱말이 0회 |
| P1 | 빌드 초 사전 측정 1회 | 실행만: `AIRAG_BUILD_DIR=<나노 scratch> AIRAG_SIGN_IDENTITY=- bash build.sh build` (ad-hoc · 키체인·op 0) | `sec` 값. 40초를 넘으면 master 에 알리고 h 상한 배분을 다시 묻는다 |
| P2 | 토큰 없는 경로 1회 | `env -u OP_SERVICE_ACCOUNT_TOKEN_DEVELOP bash h-s2-sign-only.sh` | 출력 `h-S2 rc=32 op_token_missing` 1줄, 빌드 폴더 변화 0 |

- 바꾸지 않는 것: `build.sh`, `AIRAG.swift`, `tests/`, `AIRAGTests/`. 커밋은 h 계획 파일 1개뿐이다(master 가 싣는다).
- 나노도 하지 않는 것: 실제 신원으로 서명, `security` 쓰기, op, 설치, h-S2 실행 자체(오빠 손).

## 6. DA 소환 여부

- 이번(선택지 1): **아니오.** 이유: 코드·행위 변경이 0 이고, 결과 해석은 위 14행 사전 약속 표가 정한다.
- §4 ①로 갈 때: **예**, 구현 뒤 코드 DA 1회(신뢰 저장소 변경 + 새 rc).

## 7. 범위 밖 (카드 넓히지 않음)

- `build.sh:123-148` 의 `op_call` 상한이 아직 10.5초·21초다. tick 은 7.0·14.0 으로 바뀌었다(069e64a8). planner 판정의 «별도 카드 후보» 그대로다. h-S2 는 지금 값(최대 21초)으로 시간을 잡았다.
- h10(tick 7초) 설치본 교체 h 와 h-S2 는 서로 독립이다. 순서는 master 판단이다. 다만 h-A 는 둘 다 끝난 뒤다.
