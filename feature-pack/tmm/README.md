# tmm — 모바일(SSH) tmux 좌석 TUI

`tmm`은 폰(Termius 등 SSH 클라이언트)에서 수십 개의 tmux 에이전트 세션("좌석")을 **커서로 고르고, 붙지 않고 미리보고, 메시지를 보내는** 한 화면짜리 TUI입니다. `tmuxc`로 띄운 Claude Code·Codex·OMX 좌석 운영을 전제로 만들었지만 일반 tmux 세션에도 그대로 씁니다.

```
⏎ attach ^S 메시지 ^H 대기만 ^A 전체 ^U 자동 ^R 갱신 ^X 끝
^T 최근순 ^W 대기우선 ^G 카테고리 ^P/^O 미리보기 ?=도움
auto:30s pane:10s · 12:34 완료시각 12~34 출력시각
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
| `^U` | 자동 갱신 순환 off → 15 → 30 → 60초. 헤더 3행에 `auto:30s pane:10s` |
| `^P` / `^O` | 미리보기 끄기·켜기 / 크게·작게 |
| `^X` | 종료 |

## 자동 갱신 (2단)

폰은 화면을 켜 두고 보는 물건이라 갱신은 자동입니다. 부하가 다른 두 가지를 따로 돕니다.

| 단 | 무엇을 | 기본 주기 | 비용 |
|---|---|---|---|
| pane | 커서 좌석 미리보기만 다시 그림 | 10초 (`TMM_AUTO_PREVIEW`) | `capture-pane` 1회 |
| 전좌석 | 상태(HUMAN/BUSY…)·마지막 시각·정렬 다시 계산 | 30초 (`TMM_AUTO`, `^U`) | seat-scan 1회 (65좌석 2~3초) |

- **attach 중엔 멈추고, `C-a d`로 떼면 재개**됩니다. 갱신기는 피커(fzf) 한 번의 수명에 묶여 있어서 붙어 있는 동안은 아무것도 돌지 않습니다.
- 갱신돼도 **커서는 보고 있던 좌석을 따라갑니다**(`--track`). 타이핑한 필터도 유지.
- **새로 HUMAN/BLOCK/STUCK이 된 좌석이 생기면 터미널 벨**이 울립니다(Termius가 알림으로 올림). 진입 시점에 이미 대기 중이던 좌석으로는 울리지 않습니다. `TMM_BELL=0`으로 끔.
- `^U`로 off로 두면 pane 단도 같이 멈춥니다. 정확한 초는 `TMM_AUTO=45 tmm` 또는 `tmm --auto 45`.

## CLI 서브명령

```bash
tmm                 # TUI
tmm --auto N        # TUI, 전좌석 자동 갱신 N초 (0=off)
tmm ls [PAT]        # 텍스트 목록 (필터)
tmm h               # HUMAN/BLOCK/STUCK 좌석만
tmm p NAME [N]      # pane 최근 N줄
tmm s NAME "msg"    # 메시지 (가드 + 도달확인)
tmm a NAME [-i]     # attach (-i: 데스크탑 창 크기 고정 — 폰 화면 남는 곳은 점으로 채워짐)
tmm ss              # seat-scan 원본 출력
tmm save            # tmuxc save (tmuxc 필요)
tmm doctor          # 의존성·환경 점검
tmm menu            # fzf 없을 때 숫자 메뉴
```

## 설정

| 항목 | 위치 / 변수 | 기본 |
|---|---|---|
| 카테고리 규칙 | `~/.tmm/categories` (`TMM_CATEGORIES`) | 설치 시 예시 복사. `글롭<TAB>라벨` 한 줄씩 |
| 상태 스캔 캐시 | `TMM_CACHE_TTL` | 20초. 필터·재정렬 연타 시 재스캔 방지. `^R`은 무시 |
| seat-scan 경로 | `TMM_SCAN` | 설치본 `libexec/seat-scan.sh` → `~/.claude/skills/tmuxc/scripts/seat-scan.sh` |
| 미리보기 줄 수 | `TMM_PREVIEW_LINES` | 40 |
| 전좌석 자동 갱신 | `TMM_AUTO` / `tmm --auto N` / `^U` | 30초. 0=off |
| pane 자동 갱신 | `TMM_AUTO_PREVIEW` | 10초. `TMM_AUTO`가 0이면 같이 멈춤 |
| 새 대기 좌석 벨 | `TMM_BELL` | 1 (0=끔) |

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
- **셸 alias 충돌**: `alias tm=…` 같은 짧은 alias가 있으면 그게 우선됩니다. 그래서 이름이 `tmm`입니다.
- **자동 갱신은 fzf `--listen` 소켓**으로 합니다. fzf에 타이머가 없어서 tmm이 백그라운드 핑거를 하나 띄우고 N초마다 `refresh-preview` / `reload(...)` / `bell` 액션을 소켓에 POST합니다. 핑거는 fzf가 뜨기 직전에 시작해 fzf가 끝나면 죽입니다 — 그래서 attach 중엔 자연히 멈춥니다. fzf ≥ 0.54 (`bell` 액션) + `curl` 필요.
- **정렬 모드는 상태 파일에 있습니다.** 0.1.0은 `^R`이 늘 최근순으로 되돌렸습니다(프롬프트는 "대기우선>"인데 목록은 최근순). 이제 `^W`/`^G`/`^H`가 모드를 `run-<pid>/mode`에 적고, `^R`과 자동 갱신은 그 모드로 다시 그립니다. 상태 디렉터리는 **TUI 인스턴스별**(폰·데스크탑에서 동시에 띄워도 서로의 `^U`가 안 섞임).
- **헤더는 폰 60열에서 잘립니다.** fzf는 헤더를 줄바꿈하지 않고 자르므로 한 줄에 60열(한글=2열)을 넘기면 뒤쪽 키 안내가 폰에서 보이지 않습니다. `verify.sh`가 각 줄 표시폭을 잽니다.
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
