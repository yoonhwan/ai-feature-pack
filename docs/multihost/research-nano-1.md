# research-nano-1 — DA HOLD 해소용 사실 수집 (읽기 전용)

좌석: `aifp-multihost-nano-pi#0` · 발주 #2992 · 2026-10-21
범위: ① `feature-pack/fable-team/skill/scripts/ft-mbox.py` L560–640 (+ 잠금 프리미티브 정의역) ② 로컬 `man sshd` authorized_keys 옵션 ③ `tailscale up --help`
금지 준수: 원격 접속 0 · 설치 0 · 커밋 0 · tailscale up/set 0 · 비밀값 0

---

## 1) ft-mbox.py 잠금 지도 — recv 조회/삭제가 **두 번** 잠근다

### 1.1 잠금 프리미티브

| 심볼 | 줄 | 내용 |
|---|---|---|
| `_locked(d, fn)` | **316–324** | `mailbox.lock` 열고 `fcntl.flock(f, LOCK_EX)` (**318**) → `fn()` → `LOCK_UN` (**322**). **배타 락 단일 종류뿐** — 공유(LOCK_SH)·읽기 락 없음. 블로킹. |
| `_load(d)` | 296–307 | `mailbox.jsonl` 전량 파싱. **자체 락 없음**(호출자 락 가정). |
| `_save(d, rows)` | 309–313 | **파일 전체 재작성**(`open(..., "w")`). 부분 append 아님 → read-modify-write 필수. |
| `_next_seq(rows)` | 262–287 | 락 안에서만 호출(L263 주석). `.seq` 카운터는 `os.replace` 로 원자 교체(**282–286**). 락 새로 안 걺(의도적, L265). |
| `send.op` | 454–501, 감싸는 락 **503** | load→가드→seq→stash→save→log→guard_record **전 구간이 한 락**. 락 획득 1회. |
| `_rows_for` | 571–572 | 순수 필터. 락 없음(호출자 보유). |
| `_consume` | 575–582 | `op()`(576–580) load→`seq not in seqs` 필터→`_save`. 감싸는 락 **582 `_locked(d, op)`**. |

### 1.2 recv — 조회 락 / 삭제 락 분리

| 구간 | 줄 | 락 |
|---|---|---|
| 조회(READ) | **592** — `_locked(d, lambda: _rows_for(d, me, frm))` | LOCK_EX 획득→해제. **행 목록만 받고 즉시 반납** |
| 정렬·보관(HELD) 분할 | 593–605 | **락 없음**(메모리) |
| 삭제(CONSUME) | **607** — `_consume(d, seqs)` → 내부 락 **582** | **두 번째로 LOCK_EX 획득** |
| 표시(print) | 608–617 | 락 없음 |

**⇒ 조회 락과 삭제 락 사이에 무방비 구간(L593–605)이 있다.** `recv` 는 원자적 read-then-delete 가 아니다(TOCTOU). 현재 로컬 단일 호스트에서 관측되는 창은 마이크로초지만, 삭제는 `seq` 집합으로 필터하므로(578) 같은 seq 가 두 프로세스에 동시 표시될 수 있고(이중 배달), `_save` 가 전량 재작성이므로 사이에 들어온 `send` 는 `_consume` 의 새 `_load`(577)에 의해 보존된다(유실은 아님).

### 1.3 peek

| 구간 | 줄 | 락 |
|---|---|---|
| 스냅샷 | **625** `_locked(d, lambda: _load(d))` | LOCK_EX 획득→해제 |
| `to==me` 필터 | 625 (리스트 컴프리헨션 — `_locked` 반환 **후** 평가), 정렬 626 | 락 없음(스냅샷) |

`peek` 는 **소비하지 않음** → 삭제 락 없음. 락 획득 1회.

### 1.4 ring — **ft-mbox.py 에 없다**

`grep -n ring ft-mbox.py` 결과 4건은 전부 **링버퍼 상한(MAX_PER_TO) 개념**이며 서브커맨드가 아니다(L2 도크스트링, L29, L485, L525 `DROPPED … ring=%d 포화`).

실제 `ring` 은 **`ft-mbox.sh` L337–339**:

```
337  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1
338         _rc_md="$(_mbox_dir)"; _rc_md="$( [ -n "$_rc_md" ] && cd "$_rc_md" && pwd )"
339         db="$(doorbell "$sess" 1 "${2:-}" "$_rc_md")"; echo "RING $sess doorbell=$db"
```

* **우편함 락 0회.** L332 주석이 설계 의도 명시: 「ring — ★큐를 건드리지 않고 doorbell 만 울린다★」.
* `--force=1`(doorbell 2번째 인자)로 시간·outstanding 억제를 뚫는다(L335–336 주석).
* seq 를 payload 로 실어 «1차 발주 번호 그대로» 재울린다(L333–334).

**⇒ 멀티호스트 함의(설계 판단용, 사실만):** `recv`/`send`/`peek` 는 **로컬 파일 flock + 파일 전량 재작성**에 의존한다. `mailbox.jsonl` 을 네트워크 공유(NFS/SMB)에 두면 ① flock 이 파일시스템 구현에 따라 신뢰 불가 ② `_save` 전량 재작성이 네트워크 RTT 만큼 창을 벌려 lost-update 위험 ③ `_legacy_dirs()`(L135) union 조회로 호스트마다 `CANON` 해석이 갈리면 split-brain 우편함. `ring` 만은 락·큐 무관이라 **호스트 간 doorbell 전송로만 확보하면 그대로 이식 가능**.

---

## 2) `man sshd` (macOS `/usr/share/man/man8/sshd.8`, 2024-10-01) — authorized_keys 옵션

옵션 목록 시작 **L489–493** (콤마 구분, 스페이스 금지 — 큰따옴표 안 제외, 키워드 대소문자 무시).

| 옵션 | 줄 | 인용 |
|---|---|---|
| `command="command"` | **506–536** | 「Specifies that the command is executed whenever this key is used for authentication. **The command supplied by the user (if any) is ignored.** The command is run on a pty if the client requests a pty; otherwise it is run without a tty.」(510–511) · 「This option might be useful to restrict certain public keys to perform just a specific operation.」(517–518) · 「**the client may specify TCP and/or X11 forwarding unless they are explicitly prohibited**, e.g. using the `restrict` key option.」(520–523) ← **command= 단독으로는 포워딩·PTY 를 못 막는다** · 「The command originally supplied by the client is available in the `SSH_ORIGINAL_COMMAND` environment variable.」(525–527) · 「may be superseded by … `ForceCommand`」(529–532) |
| `restrict` | **662–668** | 「Enable all restrictions, i.e. disable port, agent and X11 forwarding, **as well as disabling PTY allocation and execution of `~/.ssh/rc`**. If any future restriction capabilities are added to authorized_keys files, they will be included in this set.」← **전방 안전(fail-closed) 기본값** |
| `pty` | **644–647** | 「Permits tty allocation previously disabled by the `restrict` option.」← **restrict 를 되돌리는 쪽** |
| `no-pty` | **581–582** | 「Prevents tty allocation (a request to allocate a pty will fail).」 |
| `port-forwarding` | **629–632** | 「Enable port forwarding previously disabled by the `restrict` option.」 |
| `no-port-forwarding` | **575–580** | 「Forbids TCP forwarding … Any port forward requests by the client will return an error. **This might be used, e.g. in connection with the `command` option.**」 |
| `permitopen="host:port"` | **615–628** | `ssh -L` 목적지 제한. 「**No pattern matching or name lookup is performed on the specified hostnames, they must be literal host names and/or addresses.**」「A port specification of `*` matches any port.」 복수 지정 가능. |
| `permitlisten="[host:]port"` | **589–614** | `ssh -R` 리스너 제한. 호스트 와일드카드 허용. 「`GatewayPorts` may further restrict」 |
| `agent-forwarding` / `no-agent-forwarding` | 495–498 / 572–574 | |
| `X11-forwarding` / `no-X11-forwarding` | 681–684 / 586–588 | |
| `from="pattern-list"` | **552–571** | 키 도난 대비 출발지 제한(CIDR 가능) |
| `expiry-time="timespec"` | **547–551** | `YYYYMMDD[Z]` / `YYYYMMDDHHMM[SS][Z]`. **키 자체 만료** |
| `environment="NAME=value"` | 537–546 | 「Environment processing is disabled by default and is controlled via `PermitUserEnvironment`」 |
| `cert-authority` | 499–505 | 「If both certificate restrictions and key options are present, **the most restrictive union of the two is applied.**」 |

### 2.1 「키별 PTY 허용 + 우편함 명령만」 구성 가능 여부 → **가능**

man 페이지의 **정확히 그 조합의 공식 예시**가 있다 (L700–701):

```
restrict,pty,command="nethack" ssh-rsa ...
# Override of restriction to allow PTY allocation
```

메커니즘: `restrict` 로 전부 닫고(fail-closed) → **필요한 최소만 되연다**. `restrict` 가 PTY 를 끄므로(L663–665) PTY 가 필요하면 **`pty` 를 명시적으로 추가**해야 하고, 때문에 `no-pty` 가 아니라 `restrict,pty` 를 쓴다(둘은 같은 축, `pty` 가 restrict 를 덮는다).

멀티호스트 우편함 용도로 읽히는 사실:

1. **PTY 허용 + `command=` 강제**는 공식 지원 조합(L700–701). 단 `command=` 는 PTY 로 돌릴 때도 그대로 실행되고(L510–511), 사용자가 준 명령은 `SSH_ORIGINAL_COMMAND` 로만 남는다(L525–527) → **봉투(envelope) 강제가 서버측에서 성립**.
2. `command=` **만으로는 부족** — L520–523 이 명시적으로 경고한다. 포워딩·PTY 는 `restrict` 로 별도로 닫아야 한다.
3. `permitopen` 은 **와일드카드 불가**(L624–625) → 목적지가 가변인 경로에는 부적합. 반대로 `permitlisten` 은 와일드카드 허용(L597–599).
4. `restrict` 는 **미래 옵션까지 자동 포함**(L667–668) → 세대가 섞인 멀티호스트에서 **구버전이 신규 제한을 못 거는 비대칭**은 생기되, 신버전은 자동으로 fail-closed.
5. `expiry-time`(L547–551)은 **키 회수 절차 없이 만료**시킬 수 있는 유일한 키 단위 수단으로 읽힌다.
6. 터널링 조합 예시도 존재(L698–699): `tunnel="0",command="sh /etc/netstart tun0"`.

버전 확인: macOS 15.0.1 (24A348) 제공 `sshd.8` (mtime 2024-10-01) · `ssh -V` = **OpenSSH_9.8p1, LibreSSL 3.3.6** — 위 옵션 집합(`expiry-time`, `permitlisten`)은 9.8 실측과 일치.

---

## 3) `tailscale up --help` — `--auth-key=file:` 지원 여부 → **지원**

`tailscale` = `/usr/local/bin/tailscale` · **1.102.2**. **읽기 명령(`--help`, `version`)만 실행. `up`/`set` 미실행.**

```
  --auth-key value
    	node authorization key; if it begins with "file:", then it's a path to a file containing the authkey
```

* **문자 그대로 `file:` 접두사 파일 경로를 지원** — 비밀값을 argv/셸 히스토리에 노출하지 않는 유일한 경로.
* 같은 규약이 `--client-secret` 에도 적용:
  ```
  --client-secret value
    	Client Secret used to generate authkeys via OAuth; if it begins with "file:", then it's a path to a file containing the secret
  ```

### 3.1 부팅 자동화에 직결되는 인접 플래그(help 원문)

| 플래그 | 원문 요지 |
|---|---|
| `--auth-key value` | (위) `file:` 지원 |
| `--audience value` / `--client-id` / `--client-secret` / `--id-token value` | **workload identity federation** — OAuth 로 authkey 를 «생성»하는 경로. `--id-token` 도 `file:` 지원. **장기 authkey 를 디스크에 두지 않는 방향** |
| `--accept-risk value` | 「accept risk and skip confirmation for risk types: **lose-ssh**, mac-app-connector, all」 ← `lose-ssh` 가 위험 유형으로 명시 = **up 재실행이 원격 SSH 를 끊을 수 있음** |
| `--force-reauth` | 「force reauthentication (**WARNING: this may bring down the Tailscale connection and thus should not be done remotely over SSH or RDP**)」 |
| `--hostname value` | OS 제공 이름 대신 지정 → 다중 호스트 명명 규칙 제어 |
| `--advertise-tags value` | `tag:` ACL 태그 요청(접두사 생략 가능) |
| `--accept-routes` (default false) | 서브넷 라우트 수용 |
| `--accept-dns` (default **true**) | **기본값이 켜짐** — 관리 콘솔 DNS 가 호스트 해석을 바꾼다 |
| `--ssh` (default false) | 「run an SSH server, permitting access per **tailnet admin's declared policy**」 ← tailnet ACL 로 SSH 접근을 통제하는 별도 경로 (sshd/authorized_keys 와 다른 축) |
| `--reset` | 미지정 설정을 기본값으로 — `up` 은 「flags must be the complete set of desired settings」이므로 부분 플래그 재실행이 **오류**가 된다 |
| `--timeout value` | 기본 `0s` = 무한 대기 → 부팅 스크립트에서 hang 위험 |

### 3.2 설계 판정에 필요한 부작용 사실 2건

1. **`up` 플래그는 «완전 집합»** — 일부만 주면 오류(help 본문). 자동화는 매번 전체 플래그를 재현하거나 `--reset` 필요 → 호스트별 프로파일 파일을 단일 출처로 두어야 한다.
2. **`--accept-dns` 기본 true** — 멀티호스트에서 각 노드가 관리 콘솔 DNS 를 받으면 `CANON`/`_legacy_dirs()` 경로 해석·호스트명 해석이 tailnet 정책에 종속된다(§1.4 의 `CANON` 불일치 리스크와 접점).

---

## 4. 요약 — DA HOLD 해소에 직접 답하는 3문장

1. `ft-mbox.py` 의 `recv` 는 **조회 락(L592)과 삭제 락(L582 경유 L607)이 분리**되어 있고 그 사이(L593–605)가 무방비다. `_save` 는 전량 재작성(L309–313)이라 우편함 디렉터리를 네트워크 공유로 옮기는 설계는 이 무방비 구간과 파일시스템 flock 신뢰도 문제를 동시에 떠안는다.
2. `ring` 은 `ft-mbox.py` 에 **없고** `ft-mbox.sh` L337–339 에 있으며 **우편함 락을 0회** 잡는다 — 큐·락 계약은 그대로 두고 **doorbell 전송로만 호스트 간으로 확장**하면 된다.
3. 「키별 PTY 허용 + 우편함 명령만」은 **공식 예시 조합**(`restrict,pty,command="…"`, sshd.8 L700–701)이고, 자동 부팅은 `tailscale up --auth-key=file:</path>`(help 원문 확인) + 플래그 «완전 집합» 제약 + `--accept-dns` 기본 true 를 전제로 설계해야 한다.
