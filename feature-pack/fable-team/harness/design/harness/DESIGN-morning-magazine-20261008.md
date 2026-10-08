# DESIGN — 아침 매거진 (매일 08:00 KST · 24시간 작업 정리 → md·슬랙·PDF · launchd)

> byz-harness-arch-claude#9 · 2026-10-08 · 판정 347(오빠 컨펌 · planner#8 → master#12 발주)
> 오빠 원문: 「하네스마스터발주. 아침. 8시마다. 전날부터아침까지한 24시간 작업정리. 매거진. 발행. 슬랙. 전송메세지요약 및 pdf발행. 반복작업등록」

## ★골 원문 (GOAL-harness.md 복붙)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: C(배포 발행 — 슬랙) + 원문 7(쪼개 동시에 — 나노 2석 병행). 닫는 증거: 수동 1회 발행(슬랙 ts + PDF 경로 + md sha) + launchd 다음 발사 시각.

## §0 결론 (한 장)
- 스크립트 1개(`byz_morning_magazine.py`)가 **창 = 예정일 전날 08:00 ~ 당일 08:00 KST** 의 자료 6종을 모아 «구조 모델» 1개를 만들고, 거기서 **md·html 을 같이** 그린다(md 파서 0).
- PDF = html 을 **playwright chromium** 으로 인쇄. 슬랙 = 기존 미러 채널에 **뿌리 글(요약 3줄 + 본문 링크) + 스레드에 PDF 첨부**.
- 요약 LLM = **R25 와 같은 cc 경로 1개**(`mirror_summary.DEFAULT_CMD` + `SUMMARY_ENV` 재사용 · 모델 1개 · 폴백 모델 0).
- 실패 = raise. 자료 하나라도 못 모으면 **반쪽 매거진을 내지 않고** 슬랙에 「발행 실패: <자료>: <원인>」 1줄 + ERROR 로그 + exit 1.
- launchd `com.byz.ft-magazine` = `StartCalendarInterval` 08:00(잠들어 있었으면 깨어난 직후 1회 · 예정일 = «마지막으로 닫힌 08:00»). 같은 날 두 번 게시 0(게시 전 채널 표식 확인 + 단계별 상태 파일 · §5 · DA HOLD-M1 교정).

## §1 자료 6종 — 수집 방법·형식·실패 처리
창 경계: `start = D-1 08:00 KST`, `end = D 08:00 KST`, D = «예정 발행일». ★D 고르기(DA HOLD-M2 교정)★: ①`--date` 없음(예약·기본) = **마지막으로 닫힌 08:00 경계의 날짜** — 지금 ≥ 08:00 이면 오늘, < 08:00 이면 어제(예: 10-08 07:00 잠듦 → 10-09 07:30 잠 깸 → D=10-08 · 창 10-07 08:00~10-08 08:00). ②`--date D` 명시(수동) = 그 날짜 그대로 · `end` 가 지금보다 뒤면 raise(창이 안 닫혔다 — 미래 날짜 거부). 수동 시험 = `--date 2026-10-08`.
여러 날 잠든 경우: launchd 가 놓친 발사를 1회로 합치므로 **최신 닫힌 창 하나만** 발행한다(자동 보충 0). 상태 파일의 마지막 발행일과 D 사이에 빈 날이 있으면 본문 «근거»에 `건너뛴 날: …(수동 --date 로 발행 가능)` 을 적고 ERROR 로그 1줄 — 빠진 날을 숨기지 않는다.

| # | 자료 | 수집 | 형식(구조 모델 칸) | 실패 |
|---|---|---|---|---|
| 1 | main 머지 | `git -C $REPO fetch origin main` → `git log origin/main --first-parent --since=<start> --until=<end> --format=%H%x09%cI%x09%s` | `merges[]`: sha·시각·제목·PR번호(제목 끝 `(#N)` · 없으면 null)·꼬리표(`[feature]` 등 첫 대괄호) | fetch·log rc≠0 → raise |
| 2 | Issue 열림·닫힘 | `gh issue list --repo $GH_REPO --state all --search "created:<startZ>..<endZ>" --json number,title,state,url --limit 300` · 닫힘은 `--state closed --search "closed:…"` | `issues_opened[]`·`issues_closed[]` | gh rc≠0·JSON 아님 → raise · 300건 도달 → raise(조용히 자르지 않음) |
| 3 | 판정 번호 | mbox 사본(#4) 본문에서 `판정 (\d{2,4})` · 보낸 좌석이 `byz-planner-` 인 것만 | `verdicts`: 번호 목록(중복 제거·오름차순) + 각 번호 첫 언급 줄 | 정규식 0건이면 0건으로 표시(실패 아님 — «없었다»와 «못 읽었다»는 #4 의 성공 여부가 가른다). 깨진 줄이 있으면 문구 = `유효 줄에서 판정 0건 · 깨진 줄 N건`(완전한 부재로 단정 0 · DA §5) |
| 4 | mbox 쪽지 | `$BYZ_ROOT/.fable-team/comm/mailbox.log.jsonl`(D1 추가 전용 사본 · 10-04 부터 · 2.8 MB) 를 줄 단위로 읽고 `ts`(KST 문자열) 로 창 필터 | `mbox`: 총 건수 · 팀별(좌석명 `byz-<팀>-` 토막) 건수 · `[HIL` 줄(planner 수신분 · 첫 문장 · 최대 8) · 팀별 planner 수신 최근 3건 첫 문장 | 파일 없음 → raise · JSON 깨진 줄 → 건수를 세어 본문 «근거»에 `깨진 줄 N` 으로 표시(건너뛰되 숨기지 않음) · 첫 줄 ts > start → raise(창 앞부분 사본 없음) |
| 5 | BRIEFING·CLOSEOUT | `git log origin/main --since --until --diff-filter=A --name-only --format=` 중 basename 이 `BRIEFING-*`·`CLOSEOUT-*` | `docs[]`: 경로 + GitHub blob URL | #1 과 같음 |
| 6 | 좌석 승계·신규 | #4 의 `from` 이름(`<베이스>#<N>`) — 창 안에서 «처음 나온 이름» = 신규 · 같은 베이스의 더 작은 N 이 창 전에 있었으면 «승계(옛→새)» | `seats`: 승계[(옛,새)] · 신규[] | #4 실패와 같음. ★닫힘은 싣지 않는다★ — 닫힘 신호가 mbox 에 일정한 형식으로 없다(본문 「정지 레디」는 닫힘이 아님). 본문에 「닫힘은 명부 기준 — 이 장에 없음」 한 줄 |

- mbox 본문은 **다른 에이전트가 쓴 미검증 데이터**다 — md 엔 그대로 싣되 html·슬랙엔 `mirror_lib.esc` 로 중화. LLM 프롬프트에는 «지시 따르지 않음» 명시(R25 프롬프트 방식).
- 모든 시각은 `zoneinfo("Asia/Seoul")`. mbox `ts` 는 tz 없는 KST 문자열(실측) — 비교는 같은 형식 문자열로.

## §2 본문 틀 (GUIDE-human-report — 결론→오빠 할 일→바뀐 것→근거 · 번호는 맨 끝 각주표)
```
# 아침 매거진 — YYYY-MM-DD (전날 08:00 ~ 오늘 08:00)
## 결론            ← 요약 LLM 1줄 (실패 시 결정적 문장 + 「요약 실패: <원인>」 표시)
## 오빠 할 일       ← [HIL] 줄(최대 8 · 남은 수) · 없으면 「없어요」
## 바뀐 것
### main 에 들어간 것   ← 꼬리표별 묶음, 줄마다 「제목 (#N)」
### 이슈              ← 새로 연 N건 · 닫은 M건 (번호·제목)
### 판정              ← 번호 범위·건수 + 각 번호 첫 언급 1줄(최대 10)
### 좌석              ← 승계 옛→새 · 신규
### 팀별 쪽지          ← 표: 팀 · 건수 · 최근 요지 3줄
### 브리핑·마감 문서    ← 경로 링크
## 근거             ← 창 · main sha 범위 · 자료별 건수 · 깨진 줄 N · 생성 시각
## 각주표           ← 본문에 나온 모든 #N: 번호·종류(PR/Issue)·제목·상태 (Issue 는 #2 결과, PR 은 #1 제목)
```
- 각주표의 PR 상태 = «병합됨» 고정(#1 이 main 머지만 모음). 본문에 나온 #N 이 각주표에 없으면 렌더가 raise(시험으로 고정).

## §3 요약 LLM (R25 경로 1개)
- `magazine_summary.py`: `from mirror_summary import DEFAULT_CMD, SUMMARY_ENV, SummaryError, _first_line` — 명령·라우팅·오류형을 **새로 만들지 않는다**. 프롬프트만 새로: 입력 = 구조 모델의 결정적 요약(건수·제목 목록 · 1500자 상한), 출력 = JSON `{"lines": [3문장]}`(해요체 · 각 90자 · 기호·sha·경로 금지).
- 실패(SummaryError) → 슬랙 3줄은 결정적 문장(「main 에 N건, 이슈 열림 a·닫힘 b, 판정 k건이 있었어요」 등)으로 내고 **첫 줄 끝에 「(요약 실패: 원인)」 + ERROR 로그** — 미러의 「원문 첫 문장 게시」와 같은 «보이는» 처리(opt-in 아님: 자료는 다 모였고 LLM 은 문장만 바꾼다 · 원인이 화면에 남는다).

## §4 PDF — 도구 선택과 근거
| 후보 | 실측(이 Mac · 10-08) | 판정 |
|---|---|---|
| weasyprint CLI(`~/.local/bin`) | `libgobject-2.0-0` dlopen 실패 — pango 미설치 | ✗ (brew 설치 = 새 의존성) |
| Chrome `--headless=new --print-to-pdf` | PDF 는 1초에 나오나 **프로세스가 60초 timeout 까지 안 끝남**(updater 깨움) | ✗ (종료 판정 불가) |
| **playwright chromium**(`/opt/homebrew/bin/python3` 에 playwright + `~/Library/Caches/ms-playwright/chromium-*`) | `page.pdf(A4)` **0.9 초 · 정상 종료 · 한글 OK**(pdftotext 로 「아침 매거진 시험」 확인) | ✓ |
| pandoc·typst·xelatex | 미설치 | ✗ |

- 별도 브라우저 프로세스라 **공유 Chrome :9333(press 탭)과 무관**. 폰트 = `Apple SD Gothic Neo`(시스템 기본). playwright import 실패·브라우저 없음 → raise(설치 안내 문구).
- PDF 경로 = `~/.hermes/magazine/MAGAZINE-YYYYMMDD.pdf`(git 밖 · 바이너리 커밋 0). html 도 옆에 남긴다(디버그).

## §5 슬랙 게시
- 채널 = 기존 미러 채널 `C0C6MJGRR89`(새 채널 0) · 토큰 = `~/.hermes/secrets/yoonhwan_bot.env`(`mirror_lib.read_token`) · 스코프 실측: `chat:write files:write` 있음.
- ①뿌리 글 `chat.postMessage`: `*아침 매거진 YYYY-MM-DD*` + 3줄 + 본문 링크(§6) + (오빠 할 일 ≥1 이면 `<@U0AC2JF0M7D>`). ②같은 스레드에 PDF: `files.getUploadURLExternal` → 업로드 URL 에 바이트 POST → `files.completeUploadExternal(channel_id, thread_ts)`. 각 단계 ok=false → `MirrorError` raise.
- ★같은 날 재게시 0 — 원격 성공과 로컬 상태 사이의 불확정 구간까지(DA HOLD-M1 교정)★:
  - 뿌리 글 첫 줄에 날짜 표식 `아침 매거진 YYYY-MM-DD` 를 고정으로 넣는다(봇이 쓴 글 중 이 문자열 = 그날 뿌리 글의 유일 식별자).
  - 상태 `~/.hermes/state/byz_morning_magazine.json` 의 날짜 칸은 단계 3개: `posting`(게시 «전»에 기록 · 시각) → `posted`(ts 받자마자 PDF «전»에 기록 · ts) → `done`(PDF 완료 · ts·pdf·sha).
  - 뿌리 글을 쓰기 «전» 항상: `conversations.history(channel, oldest = D 07:00 KST)` 에서 봇 글 중 표식이 있는 것을 찾는다 → 있으면 그 ts 를 채택해 `posted` 로 적고 뿌리 글을 «쓰지 않는다». (응답 유실·상태 쓰기 실패·상태 파일 분실 셋 다 이 한 길로 복구된다.)
  - 없음 + 상태가 `posting`(앞 실행이 게시를 시도했는데 흔적이 안 보임) → **자동 재게시 0** · ERROR 「불명 상태: YYYY-MM-DD 뿌리 글 확인 필요 — 채널 확인 뒤 --force-root」 + exit 1(사람이 채널을 보고 결정).
  - 없음 + 상태 없음 → `posting` 기록 → `chat.postMessage` → `posted` 기록 → PDF.
  - 우선순위: `done` = 건너뜀(`--force` 로만 전체 재게시) · `posted`(pdf 없음) = «미완료» — 기존 ts 로 PDF 만 재시도 · `posting` = 위 표식 확인부터.

## §6 md 를 어디에 두나 — ★확정: 오빠 판정 348 (가) — ops/magazine 전용 브랜치에만 push · main 0★
본문은 tracked 경로 `design/harness/magazine/MAGAZINE-YYYYMMDD.md` 에 쓰고, 슬랙 «본문 링크»는 GitHub URL 이어야 한다. 그러려면 **launchd 잡이 매일 커밋·push** 해야 한다.
- **확정 (가)** (판정 348): 전용 워크트리 `.worktrees/ops-magazine`(브랜치 `ops/magazine`, origin/main 기준) 에서 잡이 md 1개만 커밋하고 **그 브랜치만** push(main push 0). 링크 = `github.com/<repo>/blob/ops/magazine/design/harness/magazine/MAGAZINE-….md`. main 반영은 master 가 마감 때 모아서. 커밋 메시지 `[docs] 아침 매거진 YYYY-MM-DD (자동)`. push 실패 → raise(슬랙 게시 전 — 링크가 깨진 글을 내지 않는다).
- 기각 (나) push 0 상시 — 수동 1회 시험에만 쓴다(판정 348: 「수동 1회 시험은 push 0」 = `--no-push`).
- push 계약(구현): 워크트리 `.worktrees/ops-magazine` 은 `install-magazine.sh` 가 «없을 때만» 만든다(`git worktree add -b ops/magazine <경로> origin/main` · 있으면 그대로). 잡은 그 워크트리에서만 `git add design/harness/magazine/MAGAZINE-YYYYMMDD.md` → commit → `git push origin ops/magazine`(★force 0 · 다른 브랜치 push 0 · main 체크아웃 0★). 그 브랜치는 rebase·merge 하지 않고 매거진 커밋만 쌓는다(main 반영은 master 가 마감 때). 워크트리 없음·브랜치가 ops/magazine 이 아님·미커밋 남은 파일 있음·push 거부 → raise(슬랙 게시 전).
- CLI 기본: 예약 모드(`--date` 없음) = push 켬 · `--no-push` = 끔(수동 시험). 링크는 push 성공 sha 기준 blob URL(`…/blob/<sha>/design/harness/magazine/MAGAZINE-….md` — 브랜치 이름보다 고정).

## §7 실행·등록
- CLI: `byz_morning_magazine.py [--date D] [--dry-run] [--force] [--force-root] [--no-push]`(`--date` 없음 = 예약 모드 · §1 D 고르기) — `--dry-run` = md·html·PDF 를 만들고 슬랙 글을 stdout 에만(게시·push·상태 쓰기 0).
- 설치: `scripts/harness-install/slack-mirror/install-magazine.sh` — 미러 install.sh 와 같은 방식(~/.hermes/scripts 복사 + .bak · plist 템플릿 치환 · `plutil -lint`). **launchctl bootstrap 은 `--load` 를 줄 때만**(금지선: 수동 1회 OK + planner 보고 뒤).
- plist `com.byz.ft-magazine`: `StartCalendarInterval {Hour 8, Minute 0}` · `RunAtLoad false` · KeepAlive 없음 · 로그 `~/.hermes/logs/byz_morning_magazine.{out,err}` · PATH 에 `/opt/homebrew/bin`(gh·git) · `BYZ_ROOT`·`GH_REPO`·`MAGAZINE_CHANNEL` 은 EnvironmentVariables.
- 재적재 절차(문서화 대상 · install-magazine.sh 머리 주석): `launchctl bootout gui/$UID/com.byz.ft-magazine; launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.byz.ft-magazine.plist; launchctl print gui/$UID/com.byz.ft-magazine | grep -E 'state|next'`. 모듈을 바꾸면 cp 만으로 다음 08:00 에 반영된다(장기 루프 아님 — ft-tick 함정 해당 없음).

## §8 파일 배치 (200줄·함수 40줄 한도)
| 파일 | 내용 |
|---|---|
| `scripts/harness-install/slack-mirror/magazine_window.py` | 창 계산(예약 = 마지막 닫힌 08:00 · 수동 --date 의 미래 창 거부 · 건너뛴 날 · §1 D 고르기) |
| `…/magazine_collect.py` | 자료 #1~#6 → 구조 모델 dict(§1 칸 이름 그대로) · `MagazineError` |
| `…/magazine_render.py` | 구조 모델 → md · html(같은 순서 · 각주표 검사) |
| `…/magazine_summary.py` | 3줄 요약(R25 경로 재사용) |
| `…/magazine_publish.py` | PDF(playwright) · 슬랙 뿌리 글 + 파일 업로드 · 상태 파일 · git 커밋/push(§6 값에 따라) |
| `…/byz_morning_magazine.py` | CLI · 순서: 창 → 상태 읽기(`done` 이면 끝) → 수집 → 렌더 → 요약 → PDF 파일 → (push) → 표식 확인 → `posting` → 뿌리 글 → `posted` → PDF 업로드 → `done` |
| `…/com.byz.ft-magazine.plist.template` · `install-magazine.sh` | §7 |

구조 모델(나노 2석 사이 계약 · 이 칸 이름을 바꾸지 않는다):
`{"date","start","end","main":{"from_sha","to_sha"},"merges":[{"sha","at","title","pr","tag"}],"issues_opened":[{"number","title","state","url"}],"issues_closed":[…],"verdicts":[{"n","line"}],"mbox":{"total","bad_lines","by_team":{team:{"count","recent":[str]}},"hil":[str]},"docs":[{"path","url"}],"seats":{"succession":[[old,new]],"new":[str]}}`

## §9 시험 목록 (tests/scripts/ · pytest · 네트워크 0)
1. `test_magazine_window.py` — `--date 2026-10-08` → 10-07T08:00+09:00 ~ 10-08T08:00+09:00 · 예약 모드 10-08 09:30 → D=10-08 · ★예약 모드 10-09 07:30(날짜 넘김 잠 깸) → D=10-08 · 같은 창★ · 수동 `--date 2026-10-09` 를 10-09 07:59 에 → raise(미래 창) · 빈 날 감지(마지막 발행 10-06 · D=10-08 → 건너뛴 날 [10-07]).
2. `test_magazine_collect_mbox.py` — 가짜 jsonl: 창 경계 포함/제외 · 팀 토막 · `[HIL` 추출 · 판정 번호(planner 발신만) · 승계(옛 #N<새 #M) · 깨진 줄 N 표시 · 첫 줄 ts>start → raise.
3. `test_magazine_collect_git.py` — 임시 리포 + 가짜 origin: first-parent 머지 · `(#N)`·꼬리표 파싱 · BRIEFING/CLOSEOUT 추가만 · fetch 실패 → raise.
4. `test_magazine_collect_gh.py` — PATH 가짜 `gh`: 열림/닫힘 · rc≠0 → raise · 300건 → raise.
5. `test_magazine_render.py` — 절 순서(결론→오빠 할 일→바뀐 것→근거→각주표) · 본문 #N 전부 각주표에 · 각주표에 없는 #N → raise · html 에 `<`·`<@` 중화.
6. `test_magazine_summary.py` — 가짜 명령: JSON 3줄 · rc≠0 원인 문구 · 출력이 cc 래퍼 경로(`DEFAULT_CMD` 동일 객체) · SUMMARY_ENV 가 하위 프로세스에만.
7. `test_magazine_publish.py` — 가짜 Slack HTTP 서버(로컬 포트): postMessage → getUploadURLExternal → 업로드 → completeUploadExternal(thread_ts 일치) · ok=false → raise · ★장애 주입 3종 — 다음 실행의 뿌리 게시 «추가 횟수 = 0»★: ①가짜 Slack 이 글을 만든 뒤 응답 유실(연결 끊김) → 다음 실행이 history 표식으로 ts 채택 ②뿌리 성공 뒤 상태 쓰기 실패(쓰기 경로를 읽기 전용으로) → 같은 복구 ③`posted` 뒤 PDF 실패 → 다음 실행은 PDF 만 · 그리고 ④`posting` + 표식 없음 → ERROR 문구 + exit 1 + 게시 0 · `done` 은 건너뜀.
8. `test_magazine_pdf.py` — playwright 로 PDF 생성 → `pdftotext` 에 제목 포함(이 Mac 실측용 · playwright 없으면 «실패»로 둔다 — 건너뛰기 0).
9. `tests/harness/test_magazine_plist.sh` — 템플릿 치환 뒤 `plutil -lint` · Hour 8 Minute 0 · KeepAlive 없음 · RunAtLoad false.

## §10 나노 2석 (원문 7 · 병행) — 카드
- `indices/대기/magazine-collect.md` — §8 의 window·collect + 시험 1~4.
- `indices/대기/magazine-publish.md` — §8 의 render·summary·publish·CLI·plist·install + 시험 5~9. 구조 모델은 §8 계약값으로 가짜를 만들어 시험(수집 나노를 기다리지 않음).
- 둘 다 끝나면: master 가 두 브랜치를 한 세트로 합친 뒤 → `--date 2026-10-08 --dry-run` → (§6 값에 따라) 실제 1회 → planner 보고 → `install-magazine.sh --load`.

## §11 금지선·되돌림
- launchd 등록은 «수동 1회 OK + planner 에 설계 경로·결과 1줄» 뒤에만. 원격 머신 쓰기·kill·삭제 0. 라이브 미러 재기동 0(매거진은 미러 프로세스와 별개 — 모듈 파일만 공유, 미러 모듈은 바꾸지 않는다).
- 되돌림: `launchctl bootout gui/$UID/com.byz.ft-magazine` + plist 삭제 · ~/.hermes/scripts 의 magazine_* 삭제(.bak 없음 — 신규) · 슬랙 글은 남는다(삭제는 사람).

## §12 DA 소환 판단
- r1(DA HOLD-1 · design/harness/DA-magazine-20261008.md): M1 = §5 단계 상태 + 게시 전 표식 확인 + 불명 차단 · M2 = §1 «마지막 닫힌 08:00» 예정일 + 미래 날짜 거부 + 빈 날 표시 · §9 시험 1·7 보강. 같은 범위 교정 1회.
- **소환함(사전검증 1회 · 범위 고정 10분+10분 · 2 HOLD 면 중단 — bounded_da_review)**: 바깥으로 나가는 자동 게시·자동 push 가 매일 돌고, 미검증 mbox 본문이 LLM·슬랙에 들어간다. 볼 곳 3: ①§1 실패 처리가 «반쪽 매거진»을 내는 길이 없는가 ②§5 재게시 0·PDF 재시도가 뿌리 글을 2중으로 내지 않는가 ③§3 «보이는» 요약 실패 처리가 #0 RULE(조용한 폴백 0)에 맞는가.
