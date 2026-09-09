# tmm — 모바일(SSH) tmux 좌석 TUI

`tmm`은 폰(Termius 등 SSH 클라이언트)에서 수십 개의 tmux 에이전트 세션("좌석")을 **커서로 고르고, 붙지 않고 미리보고, 메시지를 보내는** 한 화면짜리 TUI입니다. `tmuxc`로 띄운 Claude Code·Codex·OMX 좌석 운영을 전제로 만들었지만 일반 tmux 세션에도 그대로 씁니다.

```
─────────────────────────────────────────────────────────────── tmm 0.4.1 ──
  이동 ⏎ attach  ^S 메시지  ^D 종료뷰  ^X 끝
  정렬 ^T 최근  ^W 대기  ^G 분류  ^H 대기만  ^A 전체
  화면 ^P/^O 미리보기  ^U 자동  ^R 갱신  ^/ 도움
  상태 pane 5s · 전체 20s · 12:34 완료 12~34 출력
좌석> v65 impl                                                            2/65
──────────────────────────────────────────────────────────────────────────────
▶ CFO   ● FB_CFO#6               HUMAN 12:33 26m c-level-planni
  CFO   ● CFO_TOWNHALL_REVIEW#0  HUMAN 12:32 27m howto-talk-h2-
  v65   ● ft-v65-impl-cc#26      BUSY  12:52  6m v6-realtime-li
  VEC   ● FB_VEC_IMPL#5          IDLE  12:53  5m vector-pgvecto
───────────────────────────────── pane ───────────────────────────────────────
⏺ 확인 완료 — push됨, 내 커밋들 전부 origin에 반영. 별도 조치 불요, 계속 대기.
✻ Cooked for 26s · done 오후 12:09
```

## 왜 필요한가

- 좌석이 60개를 넘으면 `tmux ls`는 읽을 수 없고, 세션명을 폰 키보드로 치는 건 고통입니다.
- 진짜 급한 건 **사람 입력을 기다리는 좌석**(인터뷰·승인 프롬프트)인데 tmux는 그걸 표시하지 않습니다.
- "어느 좌석이 가장 최근에 뭔가 말했나"가 폰에서 제일 먼저 보고 싶은 정보입니다.

## 한 줄 = 한 좌석

| 열 | 뜻 |
|---|---|
| `CFO` | 카테고리 (`~/.tmm/categories` 규칙, 없으면 세션명 첫 토큰) |
| `●` / `○` | 에이전트 실행 중 / 셸만 있음 |
| 세션명 | tmux 세션명 (22자까지) |
| `HUMAN` `BLOCK` `STUCK` `IDLE` `BUSY` | seat-scan 판정. HUMAN=사람 입력 대기, BLOCK=API 오류로 멈춤, STUCK=미제출 입력 잔류 |
| `opus5·1m` `sonn5` `fabl51` `luna` `astra` | 사용 모델(축약). Claude는 프로세스 argv, Codex는 argv 없으면 pane 하단에서. `·1m`=1M 창. 종료 뷰는 복구 시 붙을 모델(fable 제외 `·1m`) |
| `12:33` / `12~33` | 마지막 메시지 시각. `:`=Claude 완료 마커에서 읽음, `~`=마커가 없어 tmux 마지막 출력 시각 |
| `26m` | 지금 기준 경과 (m/h/d) |
| 폴더 | pane cwd 마지막 디렉터리 |

**정렬**: 기본(`^T`)은 마지막 응답 시각 역순이라 진입하자마자 가장 최근에 말한 좌석이 맨 위. `^W`는 HUMAN·BLOCK·STUCK을 상단에 고정한 뒤 최근순. `^G`는 카테고리 묶음 안에서 최근순. `^H`는 대기 좌석만 남김.

## 키

| 키 | 동작 |
|---|---|
| ↑↓ / 타이핑 | 커서 이동 / 퍼지 필터 (`v65 impl`, `HUMAN`, `CFO` …) |
| Enter, `^E`, 더블탭 | attach. `C-a d`(prefix d)로 떼면 피커로 복귀 |
| `^S` | 커서 좌석에 메시지. `[mobile→세션명] …` 접두 + 2초 뒤 도달 확인. 에이전트 없는 좌석은 차단 |
| `^H` / `^A` | 대기 좌석만 / 전체 |
| `^T` / `^W` / `^G` | 최근순(기본) / 대기우선 / 카테고리순 |
| `^R` | 상태 재스캔 (캐시 무시). 현재 정렬·필터 모드 유지 |
| `^U` | 미리보기 자동 갱신 순환 5 → 10 → 15초. 헤더 3행에 `pane:5s all:20s` |
| `^P` / `^O` | 미리보기 끄기·켜기 / 크게·작게 |
| `^D` / `^A` | **종료된 세션 뷰** ↔ 살아있는 좌석 뷰 (완전 전환, 아래 절) |
| `^/` | 도움말(헤더) 다시 그림. `?`는 필터 문자로 그냥 타이핑 |
| `^X` | 종료 |

**헤더**는 이동·정렬·화면·상태 4섹션으로 나뉘고 키는 청록, 설명은 회색, 상태는 노랑입니다. 우상단에 버전이 붙습니다. 터미널 폭이 120열 이상이면 미리보기가 오른쪽(55%, `^O`로 75%)에, 그보다 좁으면 아래(50%, `^O`로 80%)에 붙습니다. 창 크기를 바꾸면 즉시 따라갑니다.

## 종료된 세션 뷰 (`^D`) — 재부팅·kill 후 복구

`^D`를 누르면 목록이 **지금 tmux에 없는 에이전트 세션**으로 통째로 바뀝니다. tmuxc로 띄운 것이든 터미널에서 직접 돌린 것이든, 트랜스크립트가 남아 있으면 전부 잡습니다.

```
  복구 ⏎ 1건  ^B 창전체  ^A 좌석뷰  ^X 끝
  창 ^] +12h  ^\ -12h  ^L 계보  ^R 갱신
  정렬 ^T 최근  ^W SNAP  ^G 분류  ^P/^O 미리보기
  상태 창 12h · 43건 · 계보 최신 · SNAP/CC/CDX/CMD/OC
종료>                                                        43/43
▶ kakao ◌ ft-kakao-implementer#1 CC    08:18 40m bootstrap
  v65   ◌ ft-v65-arch-astra#0    CDX   09:29 41m v6-realtime-li
  CFO   ◌ CFO_PM_CC#0            SNAP  18:19  1h c-level-planni
──────────────────────────────── pane ────────────────────────────────
[CC] ft-kakao-implementer#1 · bootstrap · 마지막 08:18 · claude-sonnet-5
⏺ 712 passed(카운트 불변, 문구/테스트 정정만). 리포트 갱신 후 IMPL_DONE 보고합니다.
✻ done 08:18
```

| 열 | 뜻 |
|---|---|
| `◌` | 종료됨 (살아있는 뷰의 `●/○` 자리) |
| 배지 | 어디서 찾았나 = 복구 정확도. **SNAP** `tmuxc save` 스냅샷에 있음 → 저장 시점 argv 그대로(모델·`[1m]`·effort 정확). **CC** Claude 트랜스크립트, **CDX** Codex, **CMD** Command Code, **OC** opencode |
| 시각 / 나이 | 마지막 대화 레코드 시각 / 파일이 마지막으로 쓰인 뒤 경과 |

- **창**: 진입 시 최근 12시간. `^]`로 12시간씩 넓히고 `^\`로 좁힙니다(최소 12). 판정은 트랜스크립트 파일의 mtime.
- **계보**: 증류로 `#31 → #32`처럼 이어진 세션은 기본 **최신 세대만**. `^L`로 전체 세대를 봅니다(구세대 복구는 대개 잘못된 선택이라 숨김이 기본).
- **정렬**: `^T` 최근순(기본) / `^W` SNAP 우선(정확한 것부터) / `^G` 카테고리. 타이핑 필터 동일.
- **미리보기**: 그 세션의 **마지막 user/assistant 메시지**를 Claude 화면과 비슷한 모양으로 보여줍니다. 붙기 전에 "어디까지 했나"를 읽는 용도.
- **Enter = 복구**: tmux 세션을 원래 cwd에 만들고 `--resume <session_id>`로 에이전트를 다시 띄운 뒤 attach 합니다. 부팅을 최대 60초 기다리고, Claude면 "복원된 세션이다, 직전 컨텍스트를 확인하고 이어가라"를 주입합니다. `C-a d`로 떼면 종료 뷰로 돌아오고 그 행은 목록에서 사라집니다(살아있으니).
- **`^B` = 창 안 전부 일괄 복구**: 지금 보이는 창(12h)의 종료 세션을 위에서부터 차례로 resume 합니다. 확인 `y` 후 진행, attach 는 하지 않고 끝나면 `✅ n ❌ m / 총` 집계를 보여줍니다. **창을 `^]`로 넓힌 뒤 `^B`를 다시 누르면 새로 드러난 것만 이어서** 복구됩니다(이미 살아있는 것은 목록에서 빠져 있음). `tmuxc restore --scan --loose --select all --go`의 폰판입니다. **5개씩 배치 병렬**로 돕니다(`TMM_RESTORE_BATCH`). 한 배치의 부팅이 다 끝나야 다음 배치라 헤드룸·API 동시 부하가 5를 넘지 않고, 40건이면 8배치 × 최대 60초 = 8분 안팎. 결과는 `$RUN/restore-<시각>.log`에 `ok|fail<TAB>세션명<TAB>사유` 한 줄씩 남고, 끝나면 실패 목록을 같이 보여줍니다.
- `^S`(메시지)는 종료 뷰에서 비활성입니다. 먼저 복구하세요.

**복구 모델 규칙**: SNAP이면 스냅샷 argv 그대로. 아니면 트랜스크립트의 `model` + `--effort high`. **`fable` 계열이 아니면 무조건 `[1m]`을 붙입니다** — 200K 창으로 되살아난 세션이 곧 다시 증류 대상이 되는 것을 막기 위한 확정 규칙입니다(2026-09-09). headroom 래퍼(`~/.headroom/claude-hr.sh`)가 있으면 그것을 경유합니다.

**tmuxc restore 와의 관계**: `tmuxc restore`는 데스크탑용 일괄 복구(표 → `--select` → `--go`)이고 스냅샷을 우선합니다. tmm 종료 뷰는 폰용 개별 복구이고 **트랜스크립트를 우선**합니다 — 2026-09-09 재부팅 때 직전 살아있던 54세션 중 스냅샷에 있는 것이 0개였기 때문입니다. 스냅샷은 있을 때 `resume_cmd`를 빌려 쓰는 보조 인덱스로만 씁니다. 발견 규칙(세션명 복원·노이즈 필터·계보 dedupe)은 `tmuxc-restore-scan.py`에서 옮겨 왔고, assistant 메시지 파서와 opencode/cmd 지원은 tmm 쪽에만 있습니다.

CLI: `tmm dead [PAT] [--since H] [--all]` · `tmm dp NAME [N]` · `tmm restore NAME [--dry-run]` · `tmm restore-all [--since H] [--dry-run] [--yes]`

## pane 미리보기가 보여주는 것

미리보기는 `capture-pane` 원문이 아니라 **대화만** 보이게 손질한 것입니다.

- **색을 살립니다** (`-e`). Claude Code 는 응답=굵게·도구 출력=회색·완료 마커=초록이라 색이 곧 구조입니다. 0.2.0 까지는 색을 버려서 응답·도구 출력·상태줄이 한 덩어리로 보였습니다.
- **바닥의 입력박스(`──── ❯ ────`)와 statusline(branch·OMC·게이지 5~6줄)을 잘라냅니다.** 폰 12행 미리보기에서 그 줄들이 절반을 먹었습니다. Codex 좌석은 `› Ask Codex …` 이하를 자릅니다. 응답 본문 속 표 구분선은 뒤에 `❯` 가 없으므로 안 잘립니다.
- **최신이 먼저** — 미리보기를 바닥(`follow`)에 맞춥니다. 전에는 40줄 중 1행부터 보여서 가장 오래된 내용이 먼저 보였습니다.
- 연속 빈 줄은 1줄로.
- **한 문장이 두 번 끊기는 것은 남습니다.** 데스크탑 pane(216열)에서 Claude TUI 가 문단을 자기 폭에 맞춰 «하드» 줄바꿈해 두기 때문에, 폰 60열에서 fzf 가 한 번 더 접으면 `↳` 조각이 생깁니다. tmux `-J` 는 tmux 소프트랩만 되돌리므로 이건 못 고칩니다(실측: 34줄 → 60열 74행, `-J` 유무 동일). 근본 해법은 좌석의 pane 폭을 줄이는 것뿐입니다.
- 비대화 `tmm p NAME` 은 그대로 평문(색 없음·빈 줄 제거)입니다 — 스크립트에서 grep 하기 좋게.

## 자동 갱신 (2단)

폰은 화면을 켜 두고 보는 물건이라 갱신은 자동입니다. 부하가 다른 두 가지를 따로 돕니다.

| 단 | 무엇을 | 기본 주기 | 비용 |
|---|---|---|---|
| pane | 커서 좌석 미리보기만 다시 그림 | 5초 (`^U`로 5/10/15 순환, `TMM_AUTO_PREVIEW`) | `capture-pane` 1회 |
| 전좌석 | 상태(HUMAN/BUSY…)·마지막 시각·정렬 다시 계산 | 20초 고정 (`TMM_AUTO`) | seat-scan 1회 (65좌석 2~3초) |

- **attach 중엔 멈추고, `C-a d`로 떼면 재개**됩니다. 갱신기는 피커(fzf) 한 번의 수명에 묶여 있어서 붙어 있는 동안은 아무것도 돌지 않습니다.
- 갱신돼도 **커서는 보고 있던 좌석을 따라갑니다**(`--track`). 타이핑한 필터도 유지.
- **새로 HUMAN/BLOCK/STUCK이 된 좌석이 생기면 터미널 벨**이 울립니다(Termius가 알림으로 올림). 진입 시점에 이미 대기 중이던 좌석으로는 울리지 않습니다. `TMM_BELL=0`으로 끔.
- `^U`는 **미리보기 주기만** 돌립니다(off 없음 — 폰에서 실수로 꺼져 "갱신이 안 된다"가 되지 않게). 전좌석 20초는 seat-scan 부하 상한이라 키로 못 줄이고 `TMM_AUTO=N`으로만 바꿉니다. 미리보기를 끄려면 `TMM_AUTO_PREVIEW=0`, 프리셋 밖 초는 `tmm --auto N`.

## CLI 서브명령

```bash
tmm                 # TUI
tmm --auto N        # TUI, 미리보기 자동 갱신 N초 (0=off)
tmm ls [PAT]        # 텍스트 목록 (필터)
tmm h               # HUMAN/BLOCK/STUCK 좌석만
tmm p NAME [N]      # pane 최근 N줄
tmm s NAME "msg"    # 메시지 (가드 + 도달확인)
tmm a NAME [-i]     # attach (-i: 데스크탑 창 크기 고정 — 폰 화면 남는 곳은 점으로 채워짐)
tmm ss              # seat-scan 원본 출력
tmm save            # tmuxc save (tmuxc 필요)
tmm doctor          # 의존성·환경 점검
tmm menu            # fzf 없을 때 숫자 메뉴
tmm dead [PAT] [--since H] [--all]   # 종료된 세션 목록
tmm dp NAME|SID [N] # 종료 세션의 마지막 대화 N줄
tmm restore NAME [--dry-run]         # 종료 세션 1건 복구 → attach
tmm restore-all [--since H] [--dry-run] [--yes]   # 창 안 전부 복구 (attach 없음)
```

## 설정

| 항목 | 위치 / 변수 | 기본 |
|---|---|---|
| 카테고리 규칙 | `~/.tmm/categories` (`TMM_CATEGORIES`) | 설치 시 예시 복사. `글롭<TAB>라벨` 한 줄씩 |
| 상태 스캔 캐시 | `TMM_CACHE_TTL` | 20초. 필터·재정렬 연타 시 재스캔 방지. `^R`은 무시 |
| seat-scan 경로 | `TMM_SCAN` | 설치본 `libexec/seat-scan.sh` → `~/.claude/skills/tmuxc/scripts/seat-scan.sh` |
| 미리보기 줄 수 | `TMM_PREVIEW_LINES` | 40 |
| pane 자동 갱신 | `TMM_AUTO_PREVIEW` / `tmm --auto N` / `^U` | 5초. `^U`는 5/10/15 순환. 0=off |
| 전좌석 자동 갱신 | `TMM_AUTO` | 20초 고정(키로 안 바뀜). 0=off |
| 새 대기 좌석 벨 | `TMM_BELL` | 1 (0=끔) |
| 종료 뷰 진입 창 | `TMM_DEAD_SINCE` | 12 (시간) |
| 라이브 판정 여유 | `TMM_LIVE_GRACE` | 90초 — 이 안에 쓰인 트랜스크립트는 살아있다고 보고 제외 |
| 복구 부팅 대기 | `TMM_RESTORE_TRIES` | 20 (×3초) |

## 모바일 접속 (Termius)

1. Mac에서 원격 로그인(sshd) 켜기. 집 밖에서는 Tailscale IP 권장.
2. 전용 키 만들기: `ssh-keygen -t ed25519 -f ~/.ssh/mobile_ed25519` → 공개키를 `~/.ssh/authorized_keys`에 추가. 개인키는 1Password 등에 보관 후 폰 Termius Keychain에 붙여넣기.
3. Termius 호스트: 주소·22·사용자·키, **Startup command = `tmm`**. 접속 즉시 피커.
4. 폰 키보드 툴바의 Ctrl로 `^S` 등을 누릅니다. tmux prefix가 `C-a`면 Ctrl → a → d 로 떼기.

## 설계 메모 (함정)

- **attach는 fzf 밖에서**: fzf `execute()` 안에서 `tmux attach`를 하면 `open terminal failed: can't use /dev/tty`. fzf는 `--expect`로 (키, 선택)만 돌려주고 본체 루프가 attach → detach → 재진입.
- **`--sync`**: 목록이 다 만들어진 뒤 첫 화면을 그립니다. 안 그러면 로딩 중(`0/0`) Enter가 빈 선택으로 흡수돼 "Enter가 안 먹는" 것처럼 보입니다.
- **좌석별 tmux 루프 금지**: 65좌석에 `display`/`list-panes`를 좌석마다 부르면 6초. `list-panes -a -F` 한 번 + seat-scan 한 번(20초 캐시) + 시각용 `capture-pane`은 8병렬. 부하 30에서도 4초, 캐시 히트면 1초 안.
- **`tmuxc send`엔 에이전트 가드가 없습니다**: 셸만 있는 pane에 그대로 타이핑됩니다. tmm은 `pane_current_command`가 셸이면 차단. `pgrep -P`는 zsh 플러그인 자식(gitstatusd)을 에이전트로 오판하므로 쓰지 않습니다.
- **capture-pane 타깃은 `=NAME:`**: `=NAME`만 쓰면 pane을 못 찾습니다. `has-session`/`display`는 `=NAME`으로 됩니다.
- **`-f ignore-size` attach**는 데스크탑 창 크기를 지키는 대신 폰 화면이 점(…)으로 채워집니다. 기본은 일반 attach(`window-size latest`라 데스크탑에서 키를 치면 즉시 복귀).
- **붙었는데 창이 80x24 등 작은 크기에 갇히고 나머지가 점으로 채워지면 `window-size manual`입니다.** 원인은 스폰이 아니라 **좌석들이 ctx 게이지를 읽으려고 `tmux resize-window -x 200` 후 원복하는 관행** — `resize-window`는 창 옵션을 `manual`로 박고, 그 뒤엔 어떤 클라이언트가 붙어도 안 커집니다(격리 재현: 원복 후 64x66 attach → 80x24 유지). 0.4.8부터 tmm은 **attach 직전에 그 옵션을 풉니다**(`set -wu window-size`, `-i`는 제외). 수동 확인: `tmux show -wv -t '=NAME:' window-size`가 `manual`이면 그것.
- **셸 alias 충돌**: `alias tm=…` 같은 짧은 alias가 있으면 그게 우선됩니다. 그래서 이름이 `tmm`입니다.
- **tmuxc 는 필수 세트**입니다(0.4.1부터 `install.sh`가 없으면 중단). send 도달확인·`tmm save`·복구 규약(COMM-GUIDE 안내 주입·부팅 대기)·seat-scan 원본이 tmuxc 쪽에 있습니다.
- **전체 폭은 `FZF_COLUMNS + FZF_PREVIEW_COLUMNS`**로 계산합니다. fzf 자식에서 `tput cols`는 80으로 고정이고(실측), `FZF_COLUMNS`는 목록 폭이라 오른쪽 미리보기가 켜지면 절반이 됩니다. 마지막 값을 상태 파일에 남겨 폭을 못 받는 호출도 따릅니다.
- **fzf 0.74에는 `transform-preview-window`가 없습니다.** `transform()`으로 `change-preview-window(...)` 액션 문자열을 만들어 넘깁니다.
- **자동 갱신은 fzf `--listen` 소켓**으로 합니다. fzf에 타이머가 없어서 tmm이 백그라운드 핑거를 하나 띄우고 N초마다 `refresh-preview` / `reload(...)` / `bell` 액션을 소켓에 POST합니다. 핑거는 fzf가 뜨기 직전에 시작해 fzf가 끝나면 죽입니다 — 그래서 attach 중엔 자연히 멈춥니다. fzf ≥ 0.54 (`bell` 액션) + `curl` 필요.
- **정렬 모드는 상태 파일에 있습니다.** 0.1.0은 `^R`이 늘 최근순으로 되돌렸습니다(프롬프트는 "대기우선>"인데 목록은 최근순). 이제 `^W`/`^G`/`^H`가 모드를 `run-<pid>/mode`에 적고, `^R`과 자동 갱신은 그 모드로 다시 그립니다. 상태 디렉터리는 **TUI 인스턴스별**(폰·데스크탑에서 동시에 띄워도 서로의 `^U`가 안 섞임).
- **미리보기 렌더러(`render_pane`)는 macOS awk 의 바이트 `length()` 를 전제로 씁니다.** `─` 는 3바이트라 `(─)+` 정규식이 안 걸립니다 — 구분선 판정은 «`─` 를 지운 나머지가 원문의 1/4 미만»으로 합니다(첫 구분선엔 세션명이 박혀 있어 완전 일치로는 못 잡습니다). 입력박스는 «구분선 다음 줄이 `❯` 로 시작»하는 쌍으로만 자릅니다. `verify.sh` (k) 가 골든으로 잽니다.
- **헤더는 폰 60열에서 잘립니다.** fzf는 헤더를 줄바꿈하지 않고 자르므로 한 줄에 60열(한글=2열)을 넘기면 뒤쪽 키 안내가 폰에서 보이지 않습니다. `verify.sh`가 각 줄 표시폭을 잽니다.
- **종료 세션의 «살아있음» 판정은 3중**입니다: `ps` argv의 session uuid(`--resume`로 뜬 것) · tmux 세션명 · 트랜스크립트 mtime이 90초 이내. Claude는 트랜스크립트를 append로만 열어 `lsof`에 잡히지 않고(실측 0건), 재부팅 후 새로 뜬 세션은 argv에 uuid가 없으므로 mtime 여유가 필수입니다.
- **스캐너는 `python3` 표준 라이브러리만** 씁니다. opencode DB(26GB)는 `mode=ro&immutable=1`로만 엽니다.
- **완료 마커는 시:분만** 있어 날짜가 없습니다. 미래면 어제로 계산하므로 이틀 넘게 방치된 좌석은 나이가 작게 보일 수 있습니다.

## 설치

에이전트에게:

```text
feature-pack/tmm/INSTALL.md 읽고 설치해줘
```

수동:

```bash
brew install tmux fzf          # 없으면
bash feature-pack/tmm/install.sh
tmm doctor
```

제거: `bash feature-pack/tmm/uninstall.sh` (카테고리 규칙 파일은 보존)

검증: `bash feature-pack/tmm/test/verify.sh` (격리 tmux 소켓에서 실행 — 기존 세션 무접촉)
