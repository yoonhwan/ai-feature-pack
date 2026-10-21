# tmm — 작업 지침 (이 폴더에서 세션을 열면 자동 로드)

> 정본은 이 파일. `AGENTS.md`는 심링(codex/기타 에이전트용). 둘을 따로 고치지 말 것.

## 이게 뭔가

폰(Termius/SSH)에서 수십 개 tmux 에이전트 좌석을 커서로 고르고 붙는 fzf TUI. 사용자는 iPhone Termius의
Startup command `tmm`으로 진입한다. **폰 화면 60~80열, Ctrl 키는 툴바 탭**이 모든 UI 판단의 전제다.

- 본체: `core/bin/tmm` (bash, 단일 파일). 상태 판정은 `core/libexec/seat-scan.sh`(tmuxc 스킬 사본, 수정 금지 — 원본은 `~/.claude/skills/tmuxc/scripts/seat-scan.sh`, 바뀌면 여기 다시 복사). 트랜스크립트 인덱스 해석·fork 발췌는 `core/libexec/tmm-dead-scan.py`(`resolve`/`excerpt` 서브커맨드).
- 설치본: `~/.tmm/versions/<VERSION>/` → `~/.tmm/current` → `~/.local/bin/tmm` 심링. 카테고리 규칙 `~/.tmm/categories`, fork 모델 별칭 `~/.tmm/models`, fork 발췌 `~/.tmm/forks/`.
- 사용자 문서: `README.md`(기능·키·함정) · `INSTALL.md`(설치·트러블슈팅). 코드를 바꾸면 이 둘도 같은 커밋에서 맞춘다.

## 개선 작업 절차 (매번 이 순서)

1. `bash test/verify.sh` 먼저 — 격리 tmux 소켓에서 돈다. 통과 못 하면 시작하지 않는다.
2. 코드 수정 → `bash -n core/bin/tmm` → `bash test/verify.sh` 재통과.
3. **폰 경로로 실측** (아래 "검증 방법"). 로컬 pty나 tmux 안에서 돌린 결과는 폰 결과가 아니다 — `/dev/tty` 오류가 그렇게 새어 나갔다.
4. `core/VERSION` 올리고 `bash install.sh` 로 로컬 설치본 갱신 → `tmm doctor`.
5. README/INSTALL 반영 → 커밋(`[feat]`/`[fix]`/`[test]` 접두, main 직접) → push.

## 검증 방법 (폰과 같은 경로)

```bash
# 데스크탑 자가 테스트 alias (~/.ssh/config `mac-mobile-test`, 키 ~/.ssh/termius_mobile_ed25519)
ssh -i ~/.ssh/termius_mobile_ed25519 -o IdentitiesOnly=yes 100.92.216.120 -t 'zsh -ilc tmm'

# 키 주입 자동화 — stdin 파이프 + ssh -tt (expect 는 pty 0x0 이라 fzf 가 안 그린다)
( sleep 8; printf 'diag'; sleep 1.5; printf '\r'; sleep 3; printf '\001d'; sleep 3; printf '\030' ) \
  | ssh -tt -o BatchMode=yes mac-mobile-test 'export TERM=xterm-256color; stty cols 60 rows 24; zsh -ilc tmm'
```

판독은 ANSI 제거 후 마커 순서로: `좌석>` → `git:(`(attach 성공) → `좌석>`(복귀) → exit 0. `can't use /dev/tty` 가 한 번이라도 보이면 실패.
실험 대상 좌석은 **셸만 있는 좌석**(`tmm ls | grep ○`)을 쓴다. 에이전트 좌석에 키를 흘리면 진행 중 작업을 깬다.

## 절대 규칙

- **기본 tmux 서버의 좌석에 send/kill/detach 하지 않는다.** 테스트는 `TMUX_TMPDIR` 격리 소켓(verify.sh 방식) 또는 셸-only 좌석으로만.
- **좌석별 tmux 호출 루프 금지.** 65좌석 × 3호출 = 6초였다. `list-panes -a -F` 한 번으로 받고, 좌석당 꼭 필요한 capture는 `xargs -P 8`.
- **attach/메시지 입력은 fzf 밖에서.** `--bind execute()` 안에서는 tty가 없다. `--expect` 로 (키, 선택) 만 받아 본체 루프가 처리한다.
- **`--sync` 유지.** 빼면 로딩 중 Enter 가 빈 선택으로 흡수돼 "Enter 가 안 먹는다"로 보고된다.
- **`capture-pane -t "=NAME:"`** (콜론 필수). `has-session`/`display` 는 `=NAME`.
- **에이전트 판정은 `pane_current_command`.** `pgrep -P pane_pid` 는 zsh 플러그인 자식(gitstatusd)을 에이전트로 오판한다.
- **`tmuxc send` 는 무가드**다. 셸 pane 에 그대로 타이핑된다. tmm 의 가드를 우회하는 경로를 만들지 않는다.
- 이름을 `tm` 으로 바꾸지 않는다 — 사용자 zshrc 의 `alias tm=` 이 가로챈다.
- 시각 마커 정규식은 한국어(`done 오후 12:56`)·영어(`done 12:56 PM`) 둘 다 유지.
- **attach 직전 `set -wu window-size`** (`cmd_attach`, `-i` 제외). `window-size manual` 의 출처는 `new-session -d` 가 아니라 좌석들의 `resize-window -x 200 → 원복`(ctx 읽기) 관행이다 — 격리 실측 2026-09-09. 스폰 경로의 `set -wu` 는 보험일 뿐 근본 방어가 아니다. verify (p).
- **복구 커맨드는 fable 계열 제외 전부 `[1m]`** (`with_1m`). 사용자 확정 2026-09-09 — «작은 창으로 절대 열지 않는다». 스냅샷 `resume_cmd` 는 그대로 존중.
- **종료 세션 스캐너(`tmm-dead-scan.py`)는 읽기 전용**. 트랜스크립트·스냅샷·opencode DB 를 쓰지 않는다. 라이브 세션 제외 3중(ps argv uuid · tmux 세션명 · mtime 90초)을 빼지 않는다 — 빼면 살아있는 세션을 «종료» 로 보여 주고 복구가 동명 세션 생성으로 실패한다.
- **`rows-cur` 는 `$RUN/view` 를 따른다.** ^R·20초 자동 갱신이 이것만 부르므로, dead 뷰 분기를 여기서 빼면 20초 뒤 살아있는 목록으로 되돌아간다.
- **헤더는 4섹션(이동/정렬/화면/상태 · dead 는 복구/창/정렬/상태) + 색(키 청록·설명 회색·섹션 노랑)**. 각 줄 표시폭 ≤58(fzf 들여쓰기 2). 새 키는 해당 섹션에 넣고 verify (j) 로 잰다. `?` 는 필터 문자 — 바인드 금지(도움말은 `^/`).
- **레이아웃 폭 판정은 `term_cols`** (= FZF_COLUMNS + FZF_PREVIEW_COLUMNS). `tput cols` 는 fzf 자식에서 80 고정이라 쓰지 않는다. fzf 0.74 에 `transform-preview-window` 없음 → `transform($SELF pw-action)`.
- **tmuxc 는 필수 세트** — install.sh 가드·doctor·manifest required 를 같이 유지. **fork 는 tmuxc >= 0.4.0 필요**(`tmuxc fork` 네이티브).
- **fork 는 «소스 대화를 새 에이전트 세션으로 이어받기»다** (기능2, 0.6.0). 동일 엔진은 `tmuxc fork`(네이티브 — 전체 히스토리·부모 불변·새 conversation id), 크로스 엔진은 `tmuxc open` + 트랜스크립트 경로·발췌 주입. **스폰·창옵션·COMM-GUIDE 주입을 tmm 이 재구현하지 않는다** — 전부 tmuxc 위임. 이름 기본=소스 `#N`→`#N+1`, 충돌 시 자동 증가. 모델 별칭은 `~/.tmm/models`(사용자) + `~/.tmm/models.generated`(생성본) 병합 — **사용자 우선**. `tmm models refresh`가 라이브 목록에서 생성본을 만든다. claude 는 fable 제외 `--ctx 1m` 자동. 크로스엔진 발췌는 `~/.tmm/forks/`에 영속(피커 종료 후에도 새 에이전트가 읽음).
- **opencode 의 `--model` 접두사가 곧 프로바이더다** — `opencode/`=zen(자체 게이트웨이), `openrouter/`=OpenRouter. 크레딧이 OpenRouter 에 있으면 반드시 `openrouter/...`. `TMM_MODELS_PROVIDER`(기본 `openrouter`)로 refresh 생성본의 접두사를 정한다. `opencode/deepseek-v4.1-flash` 는 없고 `openrouter/deepseek/deepseek-v4.1-flash` 에 있다.
- **`^F` fork 흐름은 «취소 가능»해야 한다**(사용자 요구 2026-09-19): 각 프롬프트에서 `^C`(또는 이름/에이전트/모델에서 `q`), 생성 중 아무 키=취소 → 피커 복귀. 취소 시 백그라운드 프로세스·자식(tmuxc)·이미 만들어진 `$name` 세션을 정리한다. `trap INT` 는 함수 끝에서 반드시 해제(`trap - INT`). 모델 선택은 fzf(검색) — 600+ 별칭 대응.
- **대화 기록 인덱스**(기능1, 0.6.0): `tmm idx NAME|SID [--json|--path]` + TUI `^Y`. 라이브는 `cwd` 슬러그 + `agentName` 정확매치(exact) → 최근 활성 파일(fallback), 종료는 sid. codex/cmd 는 cwd, opencode 는 DB. `tmm-dead-scan.py resolve`가 2패스(exact 먼저)로 «같은 cwd 혼재» 오탐을 막는다. `^Y`는 fzf `execute`(정보화면, 커서 유지), `^F`는 `--expect`로 fzf 밖에서 처리.
- **`resolve` 의 cwd 비교는 `_cwd_eq`(realpath)** — tmux `pane_current_path`는 심링크를 해석(`/private/var/…`)하므로 cwd 슬러그는 원본·realpath 후보를 모두 시도한다.
- **TUI 는 tmux 세션 안에서 돈다**(`tui_wrap`, 0.5.0). 터미널이 창 드래그 중 pty 를 회수하면 그 pty 에 직접 붙은 프로세스는 SIGHUP 으로 즉사한다 — A/B 실측: 래핑 없으면 피커 소멸, 래핑하면 세션·피커 생존. **비대화 서브명령은 래핑하지 않는다**(ls/dead/restore 가 tmux 세션을 만들면 안 된다). 끄기 `TMM_NO_WRAP=1`.
- **스캔 캐시는 tmux 서버별**(`socket_path` 해시). 격리 소켓 테스트가 실사용 캐시를 덮어써 전 좌석 상태가 `?` 가 된 사고(2026-09-14) 재발 방지 — 수동 격리 테스트 때 `TMPDIR` 도 같이 갈아끼운다.
- **피커 세션은 tmux 프리픽스를 끈다**(`tui_wrap`, `prefix None`). 전역 프리픽스가 `C-a` 면 피커의 `^A` 가 fzf 에 안 닿고, 이어 `^D` 가 «프리픽스+d» 로 detach → tmm 종료(2026-09-30). 좌석 세션의 `C-a d` 는 그대로(`cmd_dkey` 가 출발 피커 → 직전 → 빈 피커 순 복귀). verify (x)(y).
- **키워드는 뷰별**(`$RUN/query.live`·`query.dead`)이다 — 뷰 전환은 fzf 안 `vswitch` 로 저장·복원한다. `change-query:` 는 콜론 형식이며 액션 체인의 «마지막»이어야 질의 속 `)`·`+` 가 구문을 안 깬다.
- **분할 화면(0.8.0, 기본)**: 왼쪽 분류 칸 = 별도 fzf(tmux pane, `split_open`/`cmd_catpane`) · 오른쪽 = 목록 fzf. 키는 ↑↓ + ⏎(분류→목록) + Esc·⌫(목록→분류, `esckey`/`bskey`) — ←/→ 는 별칭, Tab/S-Tab 회전은 분할에서 `ignore`(사용자 2026-10-12 「상하만 사용」· master 조건 「←→ 를 필수 키로 두지 말 것」). 분류 칸 → 목록은 focus → `cmd_post fzf.sock "transform($SELF tabgo '<cat>' {2})"`({2} 는 목록 fzf 가 푼다 — 분류 fzf 의 바인드 문자열에 `{q}`·`{2}` 를 직접 쓰면 분류 fzf 가 먼저 펼친다). 목록 → 분류 칸은 핑거가 `$RUN/tabs` 갱신마다 `cat.sock` 에 reload(단 0.8.4부터 «내용이 바뀐 때만» — 아래 갱신 규칙 ⑤). ★라이브 focus 는 tmm 을 스폰하지 않는다(0.8.4)★ — `cmd_catpane` 의 focus 바인드가 인라인 sh 로 `$RUN/tabreq` 에 요청 번호를 쓰고 `( sleep 0.12; 내 번호면 curl 로 fzf.sock 에 transform(tabgo {1} \{2} 번호) POST ) & ` 를 배경에 던진다(부하 20 에서 포커스마다 tmm 전체를 새로 띄우면 40~120ms 가 직렬로 밀려 «완전히 밀림»). `{1}` 은 분류 fzf 가 인용해 펼치고, 목록으로 보낼 `{2}` 는 백슬래시 `\{2}`(fzf 이스케이프 — 격리 실측으로 `'{'2'}'` 는 curl 이중따옴표 안에서 리터럴로 남아 실패) 로 분류 fzf 가 안 펼치게 둬 목록 fzf 가 푼다. 0.12초 디바운스는 연타만 접고 마지막 focus 는 늘 쏜다(perf (d3) 의 «같아도 쏜다» 계약 유지 — `cmd_catfocus` 서브명령이 그 계약의 시험 경로로 남는다). ★분류 칸 진입 직후 `stty -echo -icanon` 로 키 에코를 끈다(0.8.4)★ — fzf 기동 전·재시작 틈(`sleep 0.3`)에 누른 ↑↓ 가 cooked tty 에 `^[[A` 로 새는 걸 막는다. 분류 칸의 다른 키는 `catfwd`(우리 피커 pane 에만 send-keys — 좌석 아님). 미리보기 방향은 «목록 칸 폭»(전체 − catw − 1) ≥120 일 때만 오른쪽 · 목록 칸 <60 이면 좁은 헤더(`hdr_live narrow`) — fzf 헤더 들여쓰기 2 때문에 58 짜리 줄은 60 미만에서 잘린다(70열 실측). `pane_current_command` 로 분류 칸 fzf 를 판정하지 않는다(bash 와 같은 pgrp → bash 로 나옴) — 화면 캡처로. verify (sp).
- **피커 이어받기 = `picker_free`(0.8.0)**: 붙은 클라이언트 0 ∧ 살아 있는 클라이언트의 `@tmm_home_<tty>`·`client_last_session` 이 그 피커가 아닐 때만. «클라이언트 0» 만 보면 폰이 좌석에 가 있는 동안 데스크탑이 같은 피커에 붙어 한 fzf 를 둘이 본다(커서 공유의 실제 원인 2026-10-12). 상태 파일은 이미 `run-<pid>` 별이라 파일 분리로는 안 고쳐진다. verify (pk).
- **+ 버전 축 = `picker_stale`(0.8.5)**: 피커 세션은 `@tmm_ver` 에 자기 `TMM_VERSION` 을 남긴다. `picker_free` 이고 버전이 다르면(=옛 피커는 옵션이 없으니 포함) **좀비**로 보고 죽인 뒤 그 이름을 다시 쓴다. 붙은 클라이언트가 있으면 남의 화면이라 건드리지 않고 `tmm-2` 로 새로 연다. 근거(2026-10-18 실사고): 0.8.4 설치(21:29) 전에 뜬 0.8.3 피커가 살아남아 폰이 `@tmm_home` 으로 매번 거기 붙었고, 그 피커의 `run-<pid>/fzf.sock`(옛 `$TMPDIR`)이 죽어 화면만 남고 키·탭 전환·갱신이 조용히 사라졌다(«원격에서만 아무 키도 안 먹는다»). verify (pv).
- **탭 줄(분류 칸을 숨겼을 때·tmux 밖·TMM_SPLIT=0)**: 탭 줄은 헤더의 «마지막» 줄(프롬프트 바로 위), `전체`(`*`)는 «마지막 탭», 시작 탭은 «첫 카테고리»(전체는 가장 무겁다 — 사용자 지정 2026-09-30). `Tab`/`S-Tab` 과 `→`/`←` 는 탭 뷰에서만 가로챈다(목록·종료 뷰는 Tab=toggle, 방향키=forward/backward-char — `arrowkey`). `cmd_header` 를 `cmd && x` 로 끝내지 않는다 — 탭이 꺼져 있으면 종료코드 1.
- **카테고리는 일반화 폴백이 정본**(`cat_of`): 역할 접두(`FB_ ft-`)를 떼고 첫 토큰, ★라벨은 전부 소문자·그룹 키 8자(열 표시만 5자)★. 규칙 파일에 프로젝트별 줄을 늘리지 않는다. verify (z).
- **분류 칸은 프로젝트 → 팀 트리다(0.9.0)**: 행 3열 = `cat_of <세션> key` = `프로젝트/팀`(P6 이름이고 구 접두가 아닐 때) · 그 밖(구 접두·규칙 라벨·폴백)은 «/ 없는 leaf». `tab_rows` 가 tabs 키를 만든다 — 팀 2개 이상인 프로젝트 = 프로젝트 줄 `byz` + 팀 줄 `byz/harness` · 팀 1개뿐·leaf = 한 줄. 선택 규칙 = «키가 3열과 같거나 3열이 `키/` 로 시작». ★프로젝트 줄에서만 카테고리 열(팀)을 남긴다★ · 옛 평면 키(`harness`)는 leaf 로 통한다(호환 — verify (v)(sp) 가 안 깨진다). 분류 칸 라벨 = 프로젝트 줄 굵게 `이름5 수` · 팀 줄 `·한 칸 들여쓰기 + 4자 + 수`(넓은 칸 2칸·6자). 새 키 0 — 접기/펴기는 만들지 않았다(↑↓ 만, 사용자 2026-10-12 「상하만 사용」). 충돌 접두(`b-`)는 `cat_of` 일반 모드에만 남는다(목록 열·dead 뷰). verify (hd).
- **Pi 에이전트 지원(0.9.1)**: 에이전트 목록은 `claude|codex|opencode|cmd|pi` 다섯. `live_agent_of` 는 args 가 `pi`·`*/pi`·`pi *`·`*pi-coding-agent*` 일 때 pi. 종료 뷰(`tmm-dead-scan.py`)는 tmuxc snapshot env(`TMUXC_PI_*`)와 `~/.pi/agent/sessions` 를 읽고(읽기 전용 그대로), 복구 커맨드는 `pi --name <이름> --session <sid>`(`restore_cmd_for`). 라이브 pi 좌석의 sid·경로는 `tmuxc probe <이름>` 의 `sid=` 줄로 얻는다(tmuxc 0.4.2 필수). `^F` fork 의 에이전트 선택에 `5 pi`. pi 는 `[1m]` 접미를 쓰지 않는다(`with_1m_if_claude`). 새 에이전트를 추가할 때는 위 5곳(live_agent_of · restore_cmd_for · fork 지원 목록 · dead-scan · models) 을 같이 본다. verify (pi) 는 순수 함수(복구 커맨드·지원 목록 문자열)만 잰다 — 좌석 프로세스 판정은 tmux 가 필요해 자동시험 밖(갭).
- **pi 좌석 표시(0.9.2)**: ①모델 칸 — pi 는 프로세스 이름이 `pi` 로 바뀌어 `ps` argv 에 `--model` 이 없다 → `live_model_of` 가 tmux 세션 환경 `TMUXC_PI_MODEL`(tmuxc open 이 심음 · ft-nano-spawn 도 같음)을 먼저, 없으면 하단 줄(`pi_footer_model` — 폭에 잘릴 수 있음). `model_short` 는 프로바이더 경로를 떼고 `deepseek-v<버전>-<결>` 을 `ds<버전점제거><결 머리글자>`(ds41fu · ds4p · ds4f)로 줄인다. ②상태 — `seat-scan.sh` 는 Claude 하단 줄(`⏵⏵ … bypass permissions`)이 있어야 IDLE 이라 pi 는 영영 BUSY 였다 → pi 하단 줄(`…%/1.0M (auto)`)이 보이면 pi 로 보고 «점자 스피너 + Working»(`── ⠦ Working ───`)만 BUSY, 아니면 IDLE. ③`ep-<버전>.cache` — 좌석별 캐시 파일 이름에 버전을 넣었다(표시 규칙이 바뀌어도 활동이 없는 좌석에 옛 «?» 가 남지 않게). ★seat-scan.sh 의 «원본» `~/.claude/skills/tmuxc/scripts/seat-scan.sh` 는 더 이상 없다 — 이 사본이 유일본이다★. **pi HUMAN·BLOCK 판독(0.9.3)**: 0.9.2 의 알려진 갭이던 두 상태를 채웠다 — ①**BLOCK** = pi TUI 오류 렌더 ` Error: <3자리>: {…}`(실측 400 model_not_found) 또는 재시도 대기 `Retrying (n/m) in Ns... (esc to cancel)`(`status-indicator.js` RetryStatusIndicator) → «줄 시작 앵커(`^ ?`)» 로만 매치하고 스크롤백은 `tail -40` 만 본다 — 도구 출력에 인용된 «Error: 400: …»(남의 로그)를 좌석 정지로 오판하지 않기 위해서다(Claude 쪽이 «오류 이름» 매치로 멀쩡한 좌석 3건을 BLOCK 으로 잡은 실측과 같은 함정). ②**HUMAN** = pi 선택기 화면(`/model`·`/resume`)의 `Enter to select · … Escape/Ctrl+C to cancel` — 상단 공통 HUMAN 식이 이미 잡는다(pi 전용 추가 없음, 시험으로만 고정). pi 는 에이전트 측 «인터뷰·승인» 도구가 없다(내장 도구 8종에 ask/permission 계열 0 — 실측) → pi 의 HUMAN 은 «사람이 고르는 화면» 이다. 픽스처 = `test/fixtures-pi/pi-{error400,selector,working,idle}.txt`(2026-10-20 실 pi 1.3.0 `tmux capture-pane -p` 원문). verify (pi3).
- **탭 전환 후 커서는 `reload-sync(...)+pos/first` 로 못 준다** — `--track` 이 reload 뒤 «이전 줄 번호» 로 되돌려 덮는다(최소 예제 실측 2026-10-02). `$RUN/wantpos` 에 줄 번호를 적고 `reload(cat …)` → fzf `load` 이벤트(`cmd_onload`)가 `pos(N)`. ★목록 fzf 에 `--id-nth` 를 다시 넣지 않는다(0.8.2)★ — fzf 0.74.3 은 `--id-nth` 가 있으면 reload 가 끝날 때까지 키 입력을 버리고 reload 뒤에 이은 액션도 버린다(^D 헤더 안 바뀜·^] 증발·20초마다 입력 막힘 — 0.7.3 에 내가 넣은 회귀, 최소 예제 실측 2026-10-15). 커서 고정은 `reload(TMM_CUR={2} TMM_Q={q} … rows-cur)` → `screen_pos`(질의가 있으면 같은 옵션의 `fzf --filter`)가 `$RUN/wantpos` → load 가 `pos(N)`. rows-cur 를 reload 하는 새 지점은 반드시 TMM_CUR/TMM_Q 를 넘긴다. 탭별 마지막 세션은 `$RUN/tabcur`. verify (zc)(rl)(wp).
- **종료 뷰 속도(0.8.2)**: ① 헤더는 스캔하지 않는다(`$RUN/dead.tsv` 개수만, 없으면 «…», 창·계보 변경 때 지움 → load 가 다시 그림) ② `tmm-dead-scan.py` 는 파일별 파싱 캐시(키 = mtime_ns·size·inode, 창 밖 항목도 유지, 위치 `$TMPDIR/tmm-<uid>/` — 트랜스크립트는 계속 읽기 전용) ③ `cmd_dead_rows` 는 행마다 fork 하지 않는다(탭→`\037` 후 read 한 번 — 탭은 IFS 공백이라 빈 칸이 접힌다). ④ 분류 칸은 `^]`·`^\`·`^L` 도 `catfwd`(바이트는 `hex:1d`·`hex:1c`). verify (dh)(dc)(cf).
- **부팅 속도 3종을 빼지 않는다**: ① `rows-boot`(직전 스냅샷 즉시 + `boot-reload`) ② `ep.cache`(좌석별 `(window_activity,pane_pid)` 키) ③ dead-scan 의 `lsof -c …` 범위 축소(전체 `lsof` 는 5초). verify (zz).
- **갱신·탭 전환 규칙(0.8.1)**: ① 탭 전환(`tab_switch_to`/`tabgo`)은 tmux·scan 호출 0 — `$RUN/rowsfull`(cmd_rows_cur·rows_boot 가 남기는 «필터 전 전체 목록»)을 `tab_rows` 로 거를 뿐, `cmd_rows_cur` 를 여기서 동기로 부르지 않는다(스냅샷이 없을 때만 옛 경로). ② 20초 자동 갱신(`auto_loop`)은 `fresh` 를 쓰지 않는다 — `fresh` 는 인스턴스 공용 캐시를 지워 피커가 여럿이면 서로의 TTL 을 무력화한다. `^R` 만 fresh. 낡은 캐시는 `scan_cached` 의 mkdir 락을 잡은 한 인스턴스만 재스캔한다(TTL 0 은 락 없음). ③ 분류 칸 focus(`cmd_catfocus`)는 `$RUN/tabreq` 에 요청 번호를 «먼저» 쓰고 `tabgo` 4번째 인자로 넘긴다 — 최신이 아니면 `tabgo` 가 버린다. ★지금 탭과 같아도 쏜다★ — 안 쏘면 이미 검사를 통과해 적용 중인 낡은 요청이 tabsel 을 쓴 뒤 최신 focus 를 바로잡을 요청이 없다(DA⑥ H1 · perf (d3)). 같은 탭 요청은 `tabgo` 가 ignore. ④ `cat_of` 는 세션 목록을 프로세스당 1회(`cat_prep` → `CAT_LIST`·`CAT_TEAMS` 표)만 받는다 — 세션마다 `tmux list-sessions` 금지. ⑤ 핑거의 분류 칸 reload 는 «행이 바뀐 때만»(0.8.4) — `tabs` 는 rows-cur 가 돌 때마다 같은 내용으로 다시 쓰여 catseen 보다 새로워진다. 그때마다 reload 하면 분류 fzf 가 reload 동안 키 입력을 버려 «밀림» 이 됐다. `cat_sync`(스폰 0 — `cmd_catrows` 함수 호출)가 `$RUN/catrows.new` 를 만들어 `$RUN/catrows` 와 `cmp` 로 다를 때만 mv + `reload(cat $RUN/catrows)`(파일 읽기 — 여기서도 tmm 스폰 0), 같으면 catseen 만 찍어 다음 변화까지 쉰다. verify (sp) cat_sync. ⑥ `tab_switch_to` 는 header 를 그리지 않는다(0.8.4) — 출력에서 `+transform-header` 를 빼 header(160ms) 2중을 없앴다. 호출 경로(tabgo·tabkey)가 모두 tab_on 가드 뒤라 reload 의 load 이벤트(`cmd_onload`)가 tab_on 이면 탭 줄을 다시 그린다. 시험 `test/perf.sh`(골든 `test/golden/cat-N*.tsv` 는 카테고리 규칙을 «의도해서» 바꿀 때만 `PERF_WRITE_GOLDEN=1` 로 갱신).
- `SELF`/`HERE` 는 `$0` 기준(심링 해석). `command -v tmm` 으로 잡으면 소스 트리 실행이 설치본 libexec 를 본다.

## 현재 설계 결정 (사용자 확정)

- 종료 뷰(`^D`) = 완전 전환. 기본 12h 창, `^]`/`^\` ±12h, `^L` 계보 전체↔최신. 상태 열 = 출처 배지(SNAP/CC/CDX/CMD/OC). Enter = resume 복구.
- 기본 정렬 = **마지막 응답 시각 역순**. 진입 시 최신 대화가 맨 위. 대기 우선은 `^W`, 카테고리 `^G`, 대기만 `^H`.
- Enter = attach (별도 명령 아님). 떼면(`C-a d`) 피커로 복귀.
- Termius 스니펫(Pro 유료) 대신 서버측 서브명령(`tmm ls/h/p/s/a/save`).
- attach 기본은 폰 크기 추종. `-i`(ignore-size)는 옵션 — 폰 화면이 점으로 채워져 사용자가 거부했다.

## 알려진 한계 (다음 개선 후보)

- 완료 마커에 날짜가 없다. 이틀 넘게 방치된 좌석은 경과가 작게 보일 수 있다 (`~` 폴백이 더 정확).
- 첫 로딩은 seat-scan 시간(65좌석 2~3초, 부하 시 더)에 묶인다. 캐시 TTL 20초로 재진입만 빠르다. TUI 가 떠 있는 동안은 전좌석 자동 갱신(20초 고정, `^U`는 미리보기 5/10/15초만)이 캐시를 갱신하지만 첫 진입은 여전히 스캔을 기다린다.
- 헤더는 fzf 가 폭에 맞춰 «자른다»(줄바꿈 없음). 각 줄 표시폭 ≤ 60 을 verify.sh 가 재고, 넘기면 폰에서 뒤쪽 키가 안 보인다.
- 자동 갱신은 fzf `--listen` 소켓 + 백그라운드 핑거(1초 틱). 핑거 수명 = fzf 한 번 — attach 중 정지는 이 구조에서 나온다. 상태 파일은 `$TMPDIR/tmm-<uid>/run-<pid>/` 인스턴스별.
- 미리보기 렌더러(`render_pane`)도 TUI 모양에 의존한다 — Claude 입력박스 «구분선→`❯`», Codex «`› Ask Codex`». macOS awk `length()` 는 바이트라 멀티바이트 정규식(`(─)+`)을 쓰지 않는다. 골든은 `verify.sh` (k).
- seat-scan 은 Claude Code TUI 문자열(`Enter to select`, `API Error`)에 의존한다. Claude Code 가 문구를 바꾸면 상태 열이 틀어진다.
 **pi effort 축(0.9.4)**: ①모델 칸에 effort 2칸 약어를 붙인다 — `ds41f·md`(모델 5칸 + `·` + off/minimal/low/medium/high/xhigh/max → of/mi/lo/md/hi/xh/mx, 총 8칸). 인자 없는 `model_short` 호출은 종전과 문자 단위 동일(회귀 0). ②라이브 행 effort 출처 = pi 면 tmuxc 세션 env `TMUXC_PI_THINKING`(process.title 이 argv `--thinking` 을 가린다), 그 밖은 argv `--effort`/`codex -c model_reasoning_effort`. `ep-<버전>.cache` 에 effort 칸을 더했다(6→7필드 · 버전 태그라 옛 캐시와 안 섞인다). ③죽은 좌석 effort = tmuxc 스냅샷 `effort`(dead-scan tsv 7번 칸) → ④pi 복구 커맨드가 `--thinking <effort>` 를 «남긴다» — 0.9.3 까지는 레벨이 사라져 settings 기본(medium)으로 조용히 떨어졌다. 실측 근거: 같은 프롬프트에서 off 1.25s vs high 2.08s(약 1.7배) — 레벨이 바뀌면 좌석 성격이 바뀐다. verify (pi3b).
