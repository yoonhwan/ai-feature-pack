# DESIGN — 제안서 흐름(proposal flow) 표준 절차 (자료 → 나노 제안서 → 오빠 컨펌 → Issue → 구현)

> byz-harness-arch-claude#9 · 2026-10-08 · 판정 352(오빠 컨펌 · planner#8 → master#12 발주)
> 오빠 원문: 「내가 이런식으로 요청하면 나노워커 돌려 기획 및 제안서 작업하고 내가 제안서 읽고 컨펌」 · 「컨펌하면 이슈로 등록하는 과정을 하네스마스터 발주해 추가 랜딩」
> 「이런식」 = 슬랙 채널에 공유한 글(News-Links 등) + 한 줄 지시. 첫 사례 = 판정 351(한국어 줄바꿈 CSS → feature 팀 나노).

## ★골 원문 (GOAL-harness.md 복붙)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(요청 접수 → 사용자 협의 → 개선: 컨펌 게이트) + C(커밋·push·배포 발행: 랜딩). 닫는 증거: 랜딩 PR main sha + 첫 사례(판정 351) 1회 통과 기록(제안서 경로 · 슬랙 ts · 컨펌 판정 번호 · Issue 번호).

## §0 결론
- 흐름은 «5단계 + 상태 5개»로 고정한다. 상태는 **제안서 파일 머리줄 한 줄**이 정본이다(`- 상태: 초안 | 컨펌 대기 | 수정 요청 rN | 승인 — 판정 N | 폐기 — 판정 N`).
- 산출물 5: ①정본 `docs/rules/proposal_flow.md`(자동 로드 아님) ②템플릿 `docs/rules/proposal_template.md` ③보조 도구 3개(카드 만들기 · 슬랙 발행 · 승인 확인+등록 진입점) ④`main-team-governance.md` §2 진입로 ④행(홈 파일 → 리포 tracked 초안 → master cp 설치) ⑤랜딩 PR 1건 — **키트 bin 추가 0 → 라이브 bin 반영·드리프트 BLOCK 없음**.
- 슬랙 발행은 매거진 모듈(`mirror_lib`·`magazine_slack`)을 재사용한다. 요약 LLM 은 쓰지 않는다 — 3줄은 제안서의 «결론·오빠 결정·되돌림» 칸을 그대로 뽑는다(실패 경로 1개 감소).

## §1 흐름 5단계 · 역할 · 상태
| 단계 | 누가 | 하는 일 | 제안서 상태 | 금지 |
|---|---|---|---|---|
| 1 입력 | 오빠 → planner | 자료(슬랙 공유 글·URL·PDF)+한 줄 지시를 planner 에 · planner 가 팀 1곳 고르고 발주(골 3줄 + 축 1줄 + 오빠 원문 + 자료 링크) | — | planner 가 팀 2곳 이상 동시 발주 0(한 값은 한 좌석) |
| 2 기획 | 그 팀 master(+arch) → 나노 1석 `byz-<팀>-nano-<slug>` | 팀 master 가 `ft-proposal-card.sh` 로 카드 생성 → 나노 spawn → 나노가 자료 수집·현황 확인(**읽기 전용**) → `design/<팀>/PROPOSAL-<slug>-YYYYMMDD.md`(템플릿) 작성·커밋(팀 브랜치 · push 0) → 팀 master 가 `ft-proposal-publish` 로 슬랙 발행 | 초안 → 컨펌 대기 | 나노: 코드·설정 수정 0 · Issue 쓰기 0 · 외부 게시 0(슬랙 발행은 팀 master) |
| 3 컨펌 | planner → 오빠 | AskUserQuestion 1문: 「승인 / 수정 요청 / 폐기」 + 제안서 경로·슬랙 링크 · 오빠 값에 판정 번호 부여 | 승인 — 판정 N / 수정 요청 rN / 폐기 — 판정 N | 하위 좌석의 AskUserQuestion 0 |
| 4 등록 | 승인: planner → issues master | issues master 가 `ft-proposal-register.sh <제안서.md> --apply` «한 번»으로 등록 — 같은 실행 안에서 제안서를 1회 읽어 머리줄 「승인 — 판정 N」 확인 → 본문 생성(제안서 링크 + 판정 N + §검증 칸 복사) → Tank 래퍼 create → 라벨 `proposal`·`approved`. 확인 실패면 Tank 호출 0(DA HOLD-P1 교정) → 번호를 제안서 머리줄과 planner 에 회신 → **그 뒤에만** planner 가 구현 발주. 수정 요청: 같은 나노가 재작업 → 2단계 슬랙은 «같은 스레드 답글»(rN). 폐기: 카드 완성/ 이동(폐기 표시) + 같은 스레드 1줄 | 승인 — 판정 N · Issue #M | 제안서 Issue 는 register 진입점으로만(정본·governance 에 명시) · 확인 실패 → Tank 호출 0 |
| 5 종결 | 구현 팀 → issues master | 구현 랜딩 뒤 Issue close 증거 = 제안서 §검증 항목을 그대로 채운 줄 | (제안서 변경 없음 · Issue 가 정본) | §검증 칸이 빈 close 0 |

- 상태 머리줄을 고치는 손: 「컨펌 대기」·「수정 요청 rN」·「승인/폐기 — 판정 N」·「Issue #M」 = 팀 master(커밋 집행). 나노는 「초안」만.
- 한 제안서 = 슬랙 스레드 1개(뿌리 글 첫 줄 `*제안서 <팀>/<slug>*` 정확 일치 — 매거진 §5 교훈) = 카드 1장.

## §2 정본·템플릿 위치 (항상 로드되는 곳 피함)
- 정본 `docs/rules/proposal_flow.md`: §1 표 + 금지선 + 도구 사용법 + 첫 사례 적용 절차(§6). `.claude/rules/`·`CLAUDE.md` 에 넣지 않는다(#3 RULE 자동 로드 예산). 찾는 길 = governance §2 ④행 + `ft-harness-info.sh find 제안서`.
- 템플릿 `docs/rules/proposal_template.md` — 칸(순서 고정 · GUIDE-human-report 틀):
  `# 제안서 — <제목>` / `- 상태:` / `- 팀·나노:` / `- 오빠 원문:` / `- 자료:` 링크 /
  `## 결론`(1줄) / `## 오빠가 결정할 것`(질문 1개 + 선택지 2~3 · 추천 먼저) / `## 제안`(무엇을·어디를 · 3~7줄) / `## 영향 범위`(파일·서비스·사용자 화면) / `## 되돌림`(1줄) / `## 검증`(닫는 증거 칸 — 구현 뒤 Issue close 에 그대로 쓰일 문장 1~3개) / `## 근거`(조사 경로:줄 · 링크) / `## 각주표`(번호가 나오면).
- 한도: 제안서 1장 120줄 이하(오빠가 읽는 글). 넘으면 부록 파일로 나눈다.

## §3 보조 도구 3개 — 배치와 이유
| 도구 | 위치 | 하는 일 | 실패 |
|---|---|---|---|
| `ft-proposal-card.sh <팀> <slug> --origin "<오빠 원문>" --source <링크>… --signer <팀 arch 좌석>` | `scripts/harness-install/proposal/` | `$ROOT/.fable-team/bin-<팀>/<팀>-env.sh` 를 source(없으면 REJECT — ft-nano-spawn.sh:19 와 같은 규칙)해 `FT_GOAL_LEDGER`·`FT_GOAL_LINES_FILE` 을 읽고 `design/<팀>/indices/대기/proposal-<slug>.md` 카드 생성(카드 폴더는 팀 이름에서 정해진다 — 별도 env 없음): 골 3줄 · ## 배경(원문+자료) · 사전검증 면제(문서 전용) · 구현 범위 = 제안서 파일 1개 · 금지(코드 0·Issue 0·게시 0) · 완료 조건 = 템플릿 칸 전부 + 120줄 이하. 끝에 `ft-index-lint` 실행 | 팀 env 없음·slug 형식 오류(`^[a-z0-9-]{3,40}$`)·같은 카드 있음 → rc≠0 · lint REJECT → 파일 지우지 않고 rc≠0 + 사유 |
| `byz_proposal_publish.py <제안서.md> [--revision rN] [--dry-run]` | `scripts/harness-install/slack-mirror/` → `~/.hermes/scripts/` (`install-magazine.sh` 가 같이 복사) | 머리줄·`## 결론`·`## 오빠가 결정할 것` 첫 줄·`## 되돌림` 을 뽑아 뿌리 글(`*제안서 <팀>/<slug>*` + 3줄) → 스레드에 md 파일 첨부. `--revision rN` 이면 기존 뿌리 글(정확 첫 줄) 스레드에 답글(첫 줄 `*제안서 <팀>/<slug> rN*` 정확) + 새 md 첨부 | 칸 누락·120줄 초과·상태가 «초안/컨펌 대기/수정 요청» 아님 → raise(게시 0) · 슬랙 ok=false → raise · revision 인데 뿌리 글 없음 → raise · 단계 상태 «posting» + 원격 표식 없음 → ERROR·exit 1(자동 재게시 0 · `--force-post` 는 사람이 채널 확인 뒤) |
| `ft-proposal-register.sh <제안서.md> [--check] [--apply]` | `scripts/harness-install/proposal/` | ★확인과 생성을 한 실행으로 묶은 «제안서 Issue 등록 진입점»(DA HOLD-P1 교정)★: 제안서를 1회 읽어 ①머리줄이 정확히 `승인 — 판정 <숫자>` ②머리줄·본문에 `Issue #` 가 아직 없음 ③`## 검증` 칸 1줄 이상 — 셋 다 맞을 때만 본문 파일을 만들고 Tank 래퍼(`${FT_TANK_CMD:-ft-gh-as-tank.sh}`) `create` → `label --add proposal,approved` 를 부른다. `--check` = 확인만(rc) · `--apply` 없으면 Tank 를 dry-run 으로. 출력 = `REGISTERED #M 판정 N` | 확인 실패 → rc≠0 + 사유 · Tank 호출 0 · create 실패 → rc≠0(label 0) · label 실패 → rc≠0 + 「#M 등록됨 · 라벨 수동」 |

- **키트 bin(`scripts/harness-install/fable-team/bin`)에 넣지 않는다** — 드리프트 검사(Issue 816 ②③) 대상이라 랜딩 직후 모든 팀 라이브 bin cp 전까지 spawn·close 가 BLOCK 된다. 리포 경로로 호출(`$BYZ_ROOT/.worktrees/harness-ops/…` 아님 — 호출자 워크트리의 `scripts/harness-install/proposal/` · main 랜딩 뒤 각 팀이 main 을 받으면 생김). 라이브 설치 = `~/.hermes/scripts/byz_proposal_publish.py` 1개뿐(install-magazine.sh 재실행 — 장기 루프 아님).
- `magazine_slack.py` 변경 1곳: `_send_bytes(url, data, content_type="application/pdf")` 인자화 + `upload_file(t, thread_ts, path, title, content_type)` 추가(`upload_pdf` 는 그것을 부르는 1줄로). 뿌리 글 찾기는 `find_first_line(t, first_line, oldest_epoch)` 로 일반화하고 `find_root` 는 그것을 부르는 1줄로 — **매거진 동작·시험 변경 0**.
- ★상태·표식(DA HOLD-P2 교정 · 매거진 §5 와 같은 원리를 rN 마다)★: 상태 파일 `~/.hermes/state/byz_proposal_publish.json` = `{"<팀>/<slug>": {"root_ts", "revs": {"r0": {"phase", "ts"}, "r1": {…}}}}` · r0 = 뿌리 글 자신.
  - 원격 표식: r0 = 뿌리 글 첫 줄 `*제안서 <팀>/<slug>*` · rN(N≥1) = 그 스레드 답글 첫 줄 `*제안서 <팀>/<slug> rN*` — 둘 다 «정확 일치». 뿌리 첫 줄은 rN 완료 표식을 대신하지 않는다.
  - rN 단계: `posting`(원격 호출 «전» 기록) → `posted`(글 ts 받자마자 · 첨부 «전») → `done`(md 첨부 완료). 완료 = `done` 뿐.
  - 글 쓰기 «전» 항상 원격 확인: r0 은 `conversations.history`(정확 첫 줄 · 봇 글), rN 은 `conversations.replies(root_ts)`(정확 첫 줄 · 봇 글) → 있으면 그 ts 채택 → `posted` → 첨부만.
  - 원격 표식 없음 + 상태 `posting` → ERROR 「불명: <팀>/<slug> rN 글 확인 필요 — 채널 확인 뒤 --force-post」 + exit 1(자동 재게시 0). 없음 + 상태 없음 → `posting` → 글 → `posted` → 첨부 → `done`.
  - `posted`(첨부 없음) → 기존 ts 에 첨부만 재시도. `done` → skip.
  - 상태 쓰기 실패는 raise(원격 확인이 다음 실행에서 채택하므로 2중 0).

## §4 governance §2 ④행 (홈 파일 · master cp 설치)
- `~/.claude/skills/fable-team/references/main-team-governance.md` 는 리포 키트에 사본이 없다(실측: `git ls-files` 에 없음 · 키트 templates 에도 없음).
- 절차: 나노가 tracked 초안 `design/harness/drafts/proposal-flow/fable-team/references/main-team-governance.md` 를 만든다(= 홈 현재 파일 cp + §2 표에 ④행 1개 + 그 아래 1줄) → master 가 랜딩 뒤 `cp` → `cmp` 로 설치(.bak-1008-proposal). 다른 줄 변경 0.
- ④행 문안: `| ④ 제안서 | 오빠가 자료+한 줄 지시 → planner 가 팀 1곳 발주 → 팀 나노가 제안서(docs/rules/proposal_template.md) → 팀 master 슬랙 발행 → planner 인터뷰(승인/수정/폐기) → 승인이면 issues master 가 ft-proposal-register.sh 로 확인+등록(확인 실패 = 생성 0) → 그 뒤 구현 발주 · 정본 docs/rules/proposal_flow.md | 오빠 인터뷰 필수 · 컨펌 전 Issue·코드 0 |`

## §5 랜딩·라이브
- PR 1건(harness 브랜치 → main · CI → squash): 정본·템플릿·도구 3·시험·governance 초안·magazine_slack 인자화.
- 라이브: ①`install-magazine.sh`(복사만 · `--load` 없이 — launchd 재적재 불요)로 `byz_proposal_publish.py` + 바뀐 `magazine_slack.py` 를 ~/.hermes/scripts 에 ②governance 홈 cp. **키트 bin·.fable-team/bin 반영 0**.

## §6 첫 사례 적용 절차(판정 351 · 접점은 planner/feature 몫 — 여기엔 순서만)
1. 랜딩 «전»이면: feature master 가 리포 경로 도구로 카드 생성(`ft-proposal-card.sh feature ko-line-break-css …`) — 랜딩 전 도구는 harness-ops 워크트리 경로로 호출해도 된다(읽기·카드 생성만).
2. feature 나노 → 제안서 → feature master 커밋 → `byz_proposal_publish.py`(랜딩 전이면 harness-ops 경로 + `--dry-run` 먼저).
3. planner 인터뷰 → 판정 N → feature master 가 머리줄 갱신 → issues master `ft-proposal-register.sh <제안서> --apply` → Issue → 구현 발주.
4. 1회 통과 기록 = 정본 §첫 사례 줄(제안서 경로 · 슬랙 ts · 판정 · Issue 번호).

## §7 시험 목록
1. `tests/harness/test_proposal_card.sh` — 가짜 팀 env(임시 디렉터리) → 카드 생성 + lint OK · 같은 slug 두 번 → rc≠0 · 잘못된 slug → rc≠0 · env 없음 → rc≠0.
2. `tests/harness/test_proposal_register.sh` — 가짜 Tank(`FT_TANK_CMD` = 호출을 파일에 적는 스크립트): 머리줄 초안·컨펌 대기·수정 요청 r1·폐기 — 판정 9·「승인 — 판정 」(번호 없음)·승인인데 `Issue #12` 이미 있음·`## 검증` 빈 칸 → 각각 rc≠0 + ★Tank 호출 0회★ · `승인 — 판정 351` → create 1회 + label 1회 · create 실패 주입 → label 0회 · `--check` → 호출 0.
3. `tests/scripts/test_proposal_publish.py` — 가짜 Slack(매거진 `_magazine_fakes` 재사용): 뿌리 글 3줄 = 제안서 칸 그대로 · md 첨부 content-type text/markdown · `--revision r1` → 답글 + 새 첨부 · 같은 rN 재실행 → 게시 0 · 칸 누락·120줄 초과·상태 «승인» → raise 게시 0 · ★장애 주입(DA HOLD-P2)★: r0 뿌리 응답 유실 → 재실행 채택(뿌리 추가 0) · r1 답글 성공 뒤 응답 유실 → 재실행이 replies 정확 첫 줄로 채택(r1 추가 0) · r1 답글 성공 뒤 상태 쓰기 실패 → 같은 채택 · r1 답글 뒤 md 첨부 실패 → 재실행은 첨부만(답글 추가 0) · r1 `posting` + 원격 표식 없음 → ERROR 문구 + exit 1 + 게시 0 · 뿌리 첫 줄만 같은 r1 이 아닌 답글(`*제안서 x/y r2*`) 은 r1 로 채택 안 함.
4. 기존 `tests/scripts/test_magazine_*.py` 전부 그대로 통과(인자화 회귀 0).

## §8 나노 2석(원문 7 · 병행)
- `indices/대기/proposal-docs.md` — 정본·템플릿·governance 초안(문서 3 · 코드 0).
- `indices/대기/proposal-tools.md` — 도구 3·magazine_slack 인자화·시험 1~4.
- 계약 = §1 상태 머리줄 문자열 · §2 템플릿 칸 이름 · §3 명령 이름/인자. 이 셋은 두 나노가 같이 쓰므로 바꾸지 않는다.

## §9 금지선·되돌림
- 이 단위 자체: 원격 쓰기·kill·삭제·외부 게시 0(슬랙 시험은 가짜 서버 · 첫 사례 발행은 feature master 집행) · 라이브 서비스 재기동 0.
- 되돌림: PR revert + `~/.hermes/scripts/byz_proposal_publish.py` 삭제 + governance `.bak-1008-proposal` 복원.

## §10 DA 소환 판단
- r1(DA HOLD-1 · design/harness/DA-proposal-flow-20261008.md): P1 = 확인·생성을 한 진입점(ft-proposal-register.sh)으로 묶고 실패 시 Tank 0회 시험 · ★수락 범위 = «제안서 표준 진입점의 실패 차단»★ — raw Tank 경로(ft-gh-as-tank.sh create)의 전역 강제 차단은 이 단위 범위 밖(키트 래퍼·가드 변경 + 라이브 반영이 필요 · 완성 후 후보로 정본에 «선언» 표기) · P2 = rN 별 원격 표식(정확 첫 줄) + 단계 상태 posting→posted→done + 불명 차단 + 첨부만 재시도 · §7 시험 2·3 장애 주입. 같은 범위 교정 1회.
- **소환함(사전검증 1회 · 10분+10분 · 2 HOLD 면 중단)**. 볼 곳 2: ①«컨펌 전 Issue 0»이 선언뿐인가 — 집행 장치는 `ft-proposal-check.sh`(issues master 가 돌림)뿐이고 Tank 래퍼(`ft-gh-as-tank.sh create`)에는 걸지 않았다(키트 bin = 드리프트 BLOCK). 이 수준이 충분한가 ②슬랙 발행의 재게시 0 — 매거진과 달리 posting 단계 없이 «게시 전 채널 정확 첫 줄 확인»만 두는 것이 수동 실행 전제에서 충분한가.

---

# r2 — 판정 357 제안서 흐름 업그레이드 (byz-harness-arch-claude#11 · 2026-10-08 · master#13 #61756 · planner#8 원 발주)

★골 원문 (GOAL-harness.md 복붙)★ — 발주문 머리에는 v65 골 3줄이 붙어 왔다(planner 발주 템플릿 오류 · 판정 359 와 같은 함정). 이 설계의 골은 아래 3줄이다.
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(요청 접수 → 사용자 협의 → 개선). 오빠 원문(10-08 11:5x): 「제안서 프로세스에 지금 제안서는 풀 컨텍스트로 깃헙 이슈에 등록 작업시 참고하라 하고 · 역시 제안서도 내가 읽기 편하게 eli5 세트로 제안서 기반 작성 · 실험과 예측 시뮬도 포함하면 더 좋지 · 하네스 마스터 발주해 다음 제안서부터 반영 업그레이드」.
범위: 첫 사례(#887)는 r1 그대로 마감 · 다음 제안서부터. r1 §0~§10 의 상태 머리줄·명령 이름·뿌리 글 첫 줄은 바꾸지 않는다.

## §r2-0 결론
세 가지 모두 «기존 도구에 덧붙이기»로 된다. 새 파일은 eli5 판 2개(모듈 1 · 템플릿 1)뿐이고, 매거진 모듈은 «부르기만» 한다 — 매거진 파일 변경은 `magazine_attach.CONTENT_TYPES` 에 md 1키 추가뿐(매거진 동작 변경 0 — 매일 08:00 발행 위험 0).
| 요구 | 어디를 | 재사용 |
|---|---|---|
| ① Issue = 풀 컨텍스트 | `ft-proposal-register.sh` 본문 생성부(38-48행) + 분할 코멘트 | Tank 래퍼 `create`·`comment`(이미 있음) |
| ② 제안서 = md + eli5 HTML 세트 | 신규 `proposal_eli5.py` + `proposal_eli5_template.html` · `byz_proposal_publish.py` 에 HTML 첨부 단계 | `magazine_eli5_batches.explain`(묶음·검증·보이는 생략) · `magazine_eli5._skill`·`_h`·`Eli5HTML` · `magazine_summary.run_cmd` · `magazine_slack.upload_file` |
| ③ 실험·예측 시뮬 절 | `docs/rules/proposal_template.md` · `proposal_flow.md` · `ft-proposal-card.sh` 완료 조건 1줄 | — |

## §r2-1 Issue 본문 = 제안서 전문 (①)
- 본문 순서: ①머리말 1줄 「구현 시 이 본문을 참고 — 제안서 전문(판정 N 승인본)」 ②`제안서: <리포 상대경로> @ <파일의 마지막 commit sha 10자>` ③`오빠 컨펌: 판정 N (승인)` ④`증거 폴더: design/<팀>/evidence/proposal-<slug>/`(있을 때만 · 그 안 파일 목록 줄마다) ⑤`---` 뒤 제안서 «전문» 그대로(머리줄 포함 · 변형 0). 링크가 아니라 본문 — 브랜치가 push 전이어도 Issue 만 읽고 구현할 수 있게.
- 분할: GitHub 본문 한도 65,536자 → 안전 한도 60,000자. 넘으면 ①~④ + 전문 앞부분을 create, 나머지를 줄 경계에서 60,000자 이하 조각으로 나눠 `comment` 를 순서대로(각 조각 첫 줄 `(이어서 k/N)`). 120줄 한도 안에서는 사실상 분할 0 — 부록 파일이 붙을 때 대비.
- ★제안서 식별자(DA R2-A 교정)★: `ID = <리포>:<제안서 상대경로>@판정<N>#<제안서 파일 sha256 앞 16자>`. 본문 첫 줄 = `<!-- byz-proposal-id: <ID> -->`(숨은 표식) · 둘째 줄에 같은 값을 보이게. 제목은 검색 힌트일 뿐 동일성 근거가 아니다.
- ★시도 기록★: `~/.hermes/state/proposal_register.json` = `{"<ID>": {"phase": "creating|created|comment-k|labeled|done", "issue": M}}`. create «전» `creating` 기록(저장 실패면 Tank 0) → create 응답에서 #M 받자마자 `created` → 조각마다 `comment-k` → label 뒤 `done`.
- ★create 전 원격 확인(읽기 전용 · `${FT_GH_READ:-gh}` 주입 가능)★: 후보 = 표식 hash 본문 검색 ∪ 정확 제목 검색(열림·닫힘) → 후보마다 본문을 읽어 첫 줄 표식을 «완전 일치»로 대조.
  - 같은 ID 1건 → 「이미 등록됨 #M(채택) · 머리줄에 Issue #M 기입 · 남은 조각·라벨은 기록 phase 기준 수동」 · create 0.
  - 제목만 같고 ID 다름 → 「제목 충돌 #M — 다른 제안서」 rc≠0 · create 0(채택 0 · 제목을 바꿔 다시).
  - 없음 + 기록 없음 → `creating` → create. 없음 + 기록 `creating`(앞 실행 응답 유실·검색 지연 가능) → 「불명: <ID> 생성 결과 확인 필요 — GitHub 에서 표식 확인 뒤 --force-create」 rc≠0 · create 0(자동 새 create 0).
  - 조회 실패·불완전(오류·페이지 끝 미확인) → rc≠0 · Tank 0.
- 실패: create 가 «확실히 거절»(Tank rc≠0 + issue=# 없음 + 오류 응답) → 기록 삭제 · rc≠0 · label 0 · comment 0. 결과 불명(시간 초과·출력에 번호 없음) → `creating` 유지 · rc≠0(다음 실행은 위 «불명» 으로 막힌다). comment k 실패 → 즉시 멈춤 · `comment-(k-1)` 유지 · rc≠0 · 「#M 등록됨 · 조각 k 는 원격에 생겼을 수도 있음 — Issue #M 댓글을 확인한 뒤 k(또는 k+1)부터 수동」(자동 재시도 0). label 은 모든 comment 성공 뒤.
- 확인 3조건(승인 머리줄 · Issue # 없음 · 검증 칸)과 «확인 실패 = Tank 0» 은 r1 그대로.

## §r2-2 제안서 세트 = md + eli5 HTML (②)
- 나노 산출은 md 1개 그대로(나노는 LLM 호출·HTML 생성 0). HTML 은 팀 master 가 `byz_proposal_publish.py` 를 돌릴 때 만든다 — 매거진과 같은 «부가물» 지위(사실 = md · AI 풀이 = 보조).
- `proposal_eli5.py`(≤120줄) `build(md_path, cmd) -> Eli5HTML`:
  - 첫 화면 = 「오빠가 결정할 것」 박스 — 그 절 원문 그대로(AI 풀이 없음 · 선택지·추천 그대로) + 「되돌림」 원문 1줄.
  - 카드 = 절 단위 단위(unit): 결론 · 제안 · 영향 범위 · 검증 · 실험·예측 시뮬(있을 때). 각 카드 = 원문 영역(절 원문 줄 그대로 · scrub) + AI 풀이 영역(비유 1 + 풀이 1~3줄). unit path = `<팀>/<slug>#<절 이름>`.
  - AI 호출 = `magazine_eli5_batches.explain(units, cmd, _skill(), run_cmd)` 그대로(12개 묶음 · 180초 · 단위별 보이는 생략 · AI 0건이면 Eli5Error). 절 수 ≤6 이라 호출 1회.
  - 각주표 = 제안서 `## 각주표` 원문 그대로. 바닥 줄 = 매거진과 같은 「AI 풀이 N/전체 · 생략 M(사유별)」.
  - 템플릿 `proposal_eli5_template.html` = 매거진 eli5 템플릿 사본에서 제목·머리(`제안서 <팀>/<slug> — 쉬운 판`)와 결정 박스 1개로만 바꾼 것. ★매거진 템플릿을 인자화하지 않는다★ — 막 랜딩해 매일 도는 파일이라 공유보다 격리가 싸다(CSS 중복 약 40줄 수락).
- publish 순서(r1 상태 머신에 단계 1개 추가):
  1. 원문 고정(DA R2-B 교정): `md_hash` = 제안서 파일 sha256. rN 기록에 처음 `posting` 을 쓸 때 `md_hash` 를 같이 쓴다. 이미 rN 기록이 있는데 지금 md_hash 가 다르면 → raise 「<팀>/<slug> <rN> 은 <앞 hash> 원문으로 진행됨 — 바뀐 원문은 다음 rN(--revision)」(게시 0 · 캐시 채택 0).
  2. 글 쓰기 «전» HTML 생성 → 캐시 `~/.hermes/state/proposal/<팀>-<slug>-<rN>-<md_hash 16>.html`(이름에 원문 hash — 다른 원문의 HTML 채택 불가 · 있으면 LLM 재호출 0). Eli5Error → HTML 없음 + ERROR 줄 + 본문 끝 「쉬운 판 못 만들었어요 — <사유>」 1줄 + rN 기록 `html: {"phase": "omitted", "reason", "md_hash"}`(재실행이 침묵으로 바뀌지 않게 — omitted rN 은 HTML 재시도 0 · 다시 원하면 다음 rN). 사실 영역 오류(절 파싱·템플릿 없음)는 raise(발행 0).
  3. 글: r1 그대로(`posting` → 글 → `posted` · 원격 첫 줄 표식 · 불명 차단). 첨부: ★`magazine_attach.attach` 를 그대로 쓴다★(원격 파일 제목 정확 일치 채택 → 없는데 시도 기록 `sharing` 이면 «불명» AttachError · file_id 받자마자 시도 기록 → 전송 → 공유 · 확정 실패만 `failed`). 파일 제목 = `제안서 <팀>/<slug> <rN> MD <md_hash 8>` · `… HTML <md_hash 8>` — 원격 표식에 원문 hash 가 들어가 내용이 바뀐 파일을 채택하지 않는다. 시도 기록 = rN 기록의 `files.md`·`files.html`. 순서 md → html(omitted 면 생략) → `done`. `magazine_attach.CONTENT_TYPES` 에 `"md": "text/markdown"` 1키 추가(매거진 동작 변경 0) · 사람이 채널 확인 뒤 `--force-file <md|html>`.
  4. 재실행 수렴: `done` → skip · `posted` + files.md done → html 만 · 원격 제목 표식 있으면 채택(업로드 0) · `sharing` + 표식 없음 → 불명 차단(자동 새 파일 0).
- 파일 한도: publish 184줄 → 단계 추가로 200줄을 넘으면 상태 helper(`read_state`·`set_phase`)를 `proposal_state.py` 로 먼저 분리([structure] 커밋 · 동작 변경 0) 뒤 기능 커밋.
- 설치: `install-magazine.sh` COMPANION 에 `proposal_eli5.py`·`proposal_eli5_template.html` 추가(판정 49 의 누락 사례와 같은 함정 — 카드 완료 조건에 명시).

## §r2-3 템플릿 「## 실험·예측 시뮬」 (③)
- 위치: `## 검증` 다음 · `## 근거` 앞. 세 형식 중 하나만:
  - 실측 — 무엇을 돌렸나(명령·환경 1줄) · 결과 수치 · 산출물 경로 `design/<팀>/evidence/proposal-<slug>/…`(예: #887 제안서의 헤드리스 Chromium 렌더 실측).
  - 예측 — 모델(식·가정 1줄) · 입력 수치와 출처 · 결과 범위.
  - 「없음 — <사유>」(실측도 예측 근거도 없을 때).
  ★지어내기 0 — 출처 없는 수치는 쓰지 않는다★.
- 도구 강제: publish·register 는 이 절을 «필수 칸»으로 검사하지 않는다(r1 제안서·첫 사례 호환). 대신 `ft-proposal-card.sh` 완료 조건에 「템플릿 `## 실험·예측 시뮬` 칸을 세 형식 중 하나로 채운다 · 실측 산출물은 `design/<팀>/evidence/proposal-<slug>/`」 1줄. 나노 범위는 «읽기 전용 + 그 evidence 폴더 쓰기»로 넓힌다(코드·설정 수정 0 은 그대로).
- 120줄 한도는 그대로 — 실험 원자료는 evidence 폴더.

## §r2-4 시험
1. `test_proposal_register.sh` 추가: 본문 = 머리말·경로@sha·판정·전문 전체(제안서 바이트가 본문에 그대로) · 60,000자 초과 가짜 제안서 → create 1 + comment N-1(순서·「(이어서 k/N)」) · comment 2번째 실패 → rc≠0 · label 0 · 출력 「#M 등록됨 · 분할 2/N 부터 수동」 · 같은 ID Issue 있음 → 채택·create 0 · 같은 제목·다른 ID → 충돌 rc≠0·create 0 · 기록 creating + 원격 없음(응답 유실·검색 지연 흉내) → 불명 rc≠0·create 0 · `--force-create` 뒤에만 create · 조회 실패·불완전 → rc≠0·Tank 0 · create 확정 거절 → 기록 삭제 · 확인 실패 3종 → Tank 0(기존).
2. `test_proposal_publish.py` 추가(가짜 Slack · 가짜 LLM): md + HTML 두 첨부(text/markdown · text/html) · `md` 상태에서 재실행 → HTML 첨부만 · LLM 0건 성공(Eli5Error) → md 만 + 본문 끝 경고 줄 + ERROR 로그 + 기록 omitted(재실행 HTML 0) · HTML 캐시 있으면 LLM 호출 0 · ★md·html 각각: complete 성공 뒤 응답 유실 → 재실행이 제목 표식 채택(업로드 0) · 공유 뒤 상태 쓰기 실패 → 같은 채택 · sharing + 표식 없음 → 불명 차단★ · ★같은 rN 에서 md 내용 변경 → raise·게시 0 · 다른 hash 캐시 채택 0★ · 기존 장애 주입 전부 통과.
3. `test_proposal_eli5.py` 신규: 결정 박스 = 원문 바이트 · 절 카드 수 = 절 수 · 단위 하나 차단 단어 → 그 카드만 「AI 풀이 없음 — 차단 단어」 · 각주표 원문 그대로.
4. `test_proposal_card.sh` 1항: 완료 조건에 실험 절 줄 · 기존 28 그대로. 5. 매거진 시험 전부 그대로(매거진 파일 변경 = `git diff` 에 magazine_attach.py 1줄뿐 확인).

## §r2-5 나노·랜딩
- 나노 1석(`indices/대기/proposal-flow-r2.md`): 도구 3(register·publish·card) + eli5 2 + 문서 2(template·flow) + 시험. 정본 `docs/rules/proposal_flow.md` 에 §r2 요약(세트 · 풀 컨텍스트 · 실험 절).
- 랜딩 PR 1 → `install-magazine.sh`(복사만) WARN 0 확인 → 다음 제안서 1건에서 세트 2 첨부 + Issue 본문 전문 확인 = 닫는 증거.
- 되돌림: PR revert + `~/.hermes/scripts/proposal_eli5*` 삭제(나머지는 r1 파일 덮어쓰기 복원).

## §r2-6 DA 소환 판단
- r2 교정 1(DA HOLD-1 · DA-proposal-flow §r2 R2-A·R2-B): A = 본문 고정 식별자 + 시도 기록 + 불명 차단 + 제목 충돌 비채택 · B = magazine_attach 재사용(제목에 원문 hash) + rN md_hash 고정 + hash 이름 캐시 + omitted 기록. Eli5Error 저하는 DA 수락 그대로. — 소환함(사전검증 1회 · r2 범위만 · 10분+10분 · 2 HOLD 면 중단)
볼 곳 2 (둘 다 외부 부작용의 실패 상태): ①Issue 분할 comment 의 부분 실패 — «멈춤 + 수동 안내» + create 전 정확 제목 원격 조회로 중복 Issue 가 0 인가 · 같은 제목의 다른 제안서(제목 충돌)를 «이미 등록»으로 오판하는 경우의 처리 ②publish 의 `md` 단계 추가와 HTML 캐시 — 첨부 2중·누락 없이 재실행이 수렴하는가 · Eli5Error 일 때 md 발행을 계속하는 것이 #0 RULE 의 허용 형태(명시 표시 + ERROR)에 드는가.
