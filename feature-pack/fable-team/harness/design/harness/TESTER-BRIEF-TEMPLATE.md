# tester 부팅 발주 템플릿 (시험 묶음 · C10-라이트)

> 오케가 묶음 tester 를 열 때 첫 발주 본문으로 쓴다. `<…>` 자리를 채운 뒤 mbox 로 보낸다.
> 정본: `design/harness/issue-improvement/SPEC-team-essentials-20261005.md` §1-B·§1-C · `MERGED-20261005.md` 행 C10.
> 묶음은 카드 1개당 1개다. 같은 카드가 활성인 동안 다시 열지 않는다(멱등).

---

## 골 원문 (항상 이 3줄 — 바이트 일치)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 이 묶음
- 카드: `<카드#>` · 묶음 좌석: `<tester 세션명>`
- 시험 프로필(`test_bundle.mode`): `<press-mic | press-api | press-inject | alt>` — `alt` 면 대체 축 `<alt_axes 목록>` 으로 시험한다(press 없음)
- 열린 계기(`open_event`): `<mbox seq>`

## 보고 수신
- ★보고 수신 = architect(`<architect 세션명>`)★ — 묶음 결과는 architect 에게 직접 보낸다.
- master 로는 두 가지만: 집행 요청(좌석·커밋·push) · 사람 판정이 필요한 것.
- 보고는 mbox 3~5줄 + 4자 표 파일 경로. 긴 본문은 파일에 두고 relay 한다.

## 보고 형식 (한 건)
1. **4자 표**: 열 = `축 | 사실 | 시간` · 행 = 아키텍처 문서 / 코드 / 로그(worker) / 화면(poller). 「관측 0」을 「정상」이라 쓰지 않는다.
2. **분모**: 유효 회차 n/m.
3. **회차 세트**: 후보 sha · 러너 시작 시각 1줄.
4. **증거 등급 1칸 — 2값만**: `E2E 통과` | `미측정`. (byz-e2e Hard Rule #0-1·#2 그대로: 마이크 경유 E2E/BTS 통과만 `E2E 통과` · 그 밖은 `미측정`.)
5. **FE Next.js 이슈 칸**: 에러 오버레이 · console.error 건수.
6. 결과 분류는 tester 가 하지 않는다 — architect 가 PASS 수락 / FAIL·미측정 → reopen 으로 분류한다.

## 허가 획득 (press-* 프로필만 — 순서 고정)
명령 정본은 `scripts/fable-team-bin/ft-press-permit.sh` 다. 인자·사유는 그 스크립트 머리 주석을 읽는다. 순서만 적는다:
1. `join <세트> <멤버>` — 세트 가입(멤버 상한 안에서만)
2. `device-acquire <멤버>` — 오디오 장치 허가(머신당 1) — `press-mic` 만
3. 시험 실행
4. `device-release <멤버>` → `leave <세트> <멤버>`

허가를 못 얻으면 대기이지 우회가 아니다. 장치 허가 없이 마이크 시험을 시작하지 않는다.

## 금지
- 오케·나노는 press 하지 않는다 — press 는 묶음 tester 만.
- 시험 중 `:9333` 탭 개폐 0.
- 소리 직접 재생·디버그 주입 결과를 `E2E 통과` 로 쓰지 않는다(`미측정`).
- 결과 판정 라벨(PASS/FAIL) 을 보고에 쓰지 않는다 — 사실과 증거 등급만.

## 상태 전이 (오케·architect 가 기록)
`bash scripts/fable-team-bin/ft-bundle-state.sh <seats-x.json> <카드#> <상태> [--result PASS|FAIL|UNMEASURED] [--event <seq>]`
open → reported → classified → closed, FAIL·미측정이면 classified → reopen(묶음당 1회) → reported. 허용 밖 전이는 exit 1.
