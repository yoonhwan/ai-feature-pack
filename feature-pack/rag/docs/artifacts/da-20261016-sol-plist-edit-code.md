골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **REJECT — blocker 0 / major 2 / minor 3 / note 1**

검토: `ft-airag-da-codex#1` · 2026-10-16 · 발주 #2665, 회신 `ft-airag-master-claude#5`. 기준 HEAD **`9842d92b5dc94f01ad56e6c5aa200f649fdba293`**. 대상 `b635d77`·`12bae9c`·`f306b39`·`9842d92`의 `ops/plist-edit/plist_edit.py/.sh`, `tests/test_plist_edit.py`, `_plist_fake_launchctl.py`다. 정본은 r15 정오표 §2 인수 12항 및 DA r15 §4다.

기존 **107개 시험은 통과**하지만, 독립 fixture에서 게시 후 신호가 복원 경로를 벗어나는 경우와 selftest 보호 경로의 교차 사용을 재현했다. **현재 구현으로 운영 집행을 진행할 수 없다.** 이 판정은 운영 plist 변경·적재/해제·재개 승인이 아니다.

Serena 정의·참조와 전체 소스/변경 diff, 합성 실행을 대조했다. 실제 운영 plist·백업 경로·설치본·runtime.json 변경, 실제 launchctl/op·네트워크/DB 접촉, 제품 코드/기존 시험 수정, 서브에이전트 사용 0. 모든 변경 재현은 임시 fixture HOME과 파일에서만 했다. 아래 P:N은 `feature-pack/rag-consumer/ops/plist-edit/plist_edit.py`의 1-based 줄 번호다.

## 1. 인수 12항 대조

| # | 인수 조건 | 코드·시험 확인 및 판단 |
|---|---|---|
| 1 | 직전 미적재·disabled 확인 | P:292–310 require_stopped가 list 헤더/정확한 Label 부재와 print-disabled의 disabled/true를 확인. 정상 편집은 백업보다 앞에서 실행. 이미 키 없음은 편집·백업 없는 성공 경로. loaded/enabled/부재/조회 실패/지연 fixture는 편집 0 |
| 2 | 전제 미확인/변경 시 S2 진입 0 | 정상 전제 이외는 STATE=4, 백업/후보 생성 없음. 게시 직전 원본 해시 변화도 PUBLISH=7로 거부. 현재 구현을 운영 launchd에서 실행해 검증한 것은 아님 |
| 3 | launchctl 허용 동사·시간 | READ_VERBS는 list/print-disabled 두 개. dispatch에서 허용 목록 확인. 각 호출 timeout=min(7.0, 남은 예산), stdin DEVNULL, 재시도 없음. 변경 동사 실행 경로 없음. 전체 회귀와 별개로 관련 fixture 검사 통과 |
| 4 | Background/이미 없음 입력 | XML 파싱·최상위 dict·문자열 Background만 편집, 없으면 무변경/백업 0. 그 외 값/형 거부. 현재 기본 코드의 비-dict 거부는 맞음. 다만 root_unchecked 동치 주장은 m3 |
| 5 | 거부 5종·중첩 오인 금지 | ProcessType 중복·다른 값/형·루트 비-dict·파싱 실패 및 비일반/심링크 거부. 중첩 키를 top-level로 제거하지 않는 기존 시험 통과. selftest 경로 보호는 M2 |
| 6 | 최상위 항목 하나·다른 바이트 보존 | 원본 바이트 span을 잘라 나머지 키/값/순서 보존. **key와 value 사이 주석도 함께 지워지는 예외**를 독립 재현(m1) |
| 7 | 실제 백업·sha256 선행 | make_backup은 O_EXCL/O_NOFOLLOW 복사·flush/fsync, 원본/백업 sha 일치 확인 뒤 후보 생성. 변경 중 원본 해시 검사 포함. 백업 실패/오염이면 편집 0. 디렉터리 700·백업 파일 600은 Nano 구현 발주의 명시 정책 |
| 8 | 후보에서 lint/키/값 검증 | 같은 디렉터리 .tmp 후보에 기록 후 plutil -lint, 정확한 키 이름/순서·나머지 값 해시·mode/uid/gid 검증. 외부 도구 stdout/stderr를 반사하지 않음. 실패 fixture에서 원본 불변 |
| 9 | 원자 게시·신호 안전 | os.replace 한 번, rename과 published 플래그를 deferred 구간으로 묶음. 후보/rename 구간의 기존 신호 시험 통과. **사후 검증 뒤 정상 메시지 구간의 신호는 복원 누락(M1)** |
| 10 | 메타데이터 | 후보 생성 때 원본 mode/uid/gid 설정, 게시 후 동일 tuple 확인, 복원 후 hash/meta 확인. 불일치 시험 통과. 백업 파일 600은 앞의 별도 명시 정책이며 원본과 같은 mode라고 보고하지 않음 |
| 11 | 사후 재검증/원자 복원/실패 | 게시 바이트의 candidate sha·shape·metadata 재검증, 실패 시 백업 hash 확인→별도 temp→replace→최종 hash/meta 확인. 복원 실패 9·백업 위치 표시. 통상 실패 주입은 통과하나 **모든 게시 후 종료 경로를 감싸지는 못함(M1)** |
| 12 | 키 이름·PASS/FAIL, 값 비출력 | 입력 내부 값/도구 원문/오류 객체 값은 반사하지 않음. **정상 성공에서 백업 절대 경로를 출력(m2)**. 실패 9에서 위치 표시는 정본의 명시 예외 |

## 2. Major 2건

**M1 — 사후 검증 성공 직후 신호가 들어오면 복원하지 않고 «운영 파일 불변»이라고 보고한다.** P:439–468은 rename과 사후 검사 중의 Interrupted를 잡지만, P:469–472의 성공 출력/반환은 그 보호 구간 밖이다. 여기서 INT/TERM을 받으면 P:501–503으로 빠져 **130/143을 반환하고 백업을 복원하지 않는다**. finally는 임시 파일만 정리한다. 결과는 «중단·운영 파일 불변» 메시지와 달리 ProcessType이 이미 제거된 상태다.

독립 재현은 실제 신호 handler를 사용했다. fixture에서 `say("사후 재검증: PASS…")`가 호출되는 정확한 순간에 자신에게 INT 또는 TERM을 보내도록 관찰기를 감쌌다. 제품 소스는 수정하지 않았다.

| 신호 | 실제 종료코드 | 원본 복원 | 최종 fixture |
|---|---|---|---|
| INT | 130 | **아니오** | ProcessType 제거됨 |
| TERM | 143 | **아니오** | ProcessType 제거됨 |

이는 rename 자체의 원자성 문제가 아니라 **게시 후 전체 수명주기의 종료/복원 범위 누락**이다. 성공 출력이 진행 중인 단계는 실제 신호가 올 수 있는 경로다. 같은 계열로, 사후 오류 뒤 복원 rename 중 TERM이 오면 defer에 기록되지만 성공 복원 반환에서 pending을 보지 않아 **143 대신 8**로 끝나는 경우도 재현했다(이 경우 원본은 복원됨).

**수정 요구:** 게시 후의 중단/예외/최종 출력까지 종료 처리를 한 곳에서 결정하고, 문서의 신호 계약대로 원본 복원·검증을 마친 뒤 상태와 코드를 출력한다. 완료 확정 경계를 별도로 두려면 확정 이후의 파일 상태·코드·메시지 계약을 명확히 해야 하며, 적용된 편집을 «불변»이라고 표시해서는 안 된다. 마지막 두 성공 출력 지점, rename 직후, 사후 검사 전후, 복원 중 신호의 결정적 시험을 추가한다. 복원 실패 9를 신호 성공/정상 완료로 숨기지 않는다.

**M2 — selftest의 두 경로 인자를 바꾸어 쓰면 보호 대상 공간에 쓸 수 있다.** P:162–167은 **plist 인자만 LaunchAgents 안인지**, **backup-dir 인자만 airag-plist-backup 안인지** 검사한다. 두 보호 공간을 모든 쓰기 인자에 공통 적용하지 않는다.

실제 홈을 건드리지 않고 fixture HOME에 두 보호 트리를 만들어 재현했다.

| selftest 입력 | 결과 |
|---|---|
| plist=일반 fixture, backup-dir=`<fixture HOME>/Library/LaunchAgents` | rc=0. 보호 디렉터리가 **755→700으로 변경**되고 그 안에 백업 생성 |
| plist=`<fixture HOME>/.local/share/airag-plist-backup/old-copy.bak`, backup-dir=일반 fixture | rc=0. 보호 백업 파일의 **ProcessType 제거** |

같은 검사는 계정 DB 홈에도 적용되므로 이 빈틈은 실제 보호 경로를 역할 교차로 지정해도 차단하지 못한다. HOME 변경으로 생산 경로를 바꾸는 문제와는 별개다. 운영 경로 접촉 0을 보장한다는 시험 모드 계약이 성립하지 않는다.

**수정 요구:** plist와 backup-dir 양쪽을 모두 계정 DB/HOME의 **LaunchAgents 및 운영 백업 공간 양쪽**에 대조한다(resolve 및 symlink 경로 포함). 인자 거부 시 launchctl·mkdir/chmod·파일 쓰기 이전에 끝나야 한다. 역할 교차 2종과 그 symlink 형태를 fixture HOME으로 시험한다. 생산 경로를 사용한 부정 시험을 실제 쓰기로 검증하지 않는다.

## 3. Minor 3건

**m1 — key/value 사이 주석을 삭제한다(P:241·244–257).** 유효 XML인 `<key>ProcessType</key><!-- KEEP_BETWEEN_KEY_AND_VALUE --><string>Background</string>`을 넣은 fixture가 rc=0으로 편집되면서 주석도 사라졌다. cut이 key 시작부터 value 끝까지의 연속 span을 지우기 때문이다. 정본 6항·모듈 설명의 «다른 주석/바이트 보존»과 다르다. 두 요소 외의 주석을 보존하거나 이 배치를 명시적으로 거부하는 정책/시험이 필요하다. 현재의 통상 줄 배치 시험만으로 모든 주석 보존을 주장하지 않는다.

**m2 — 정상 백업 출력이 경로 비출력 계약과 다르다(P:413).** 정상 편집에서 `백업: PASS … 위치: <absolute backup path>`를 출력한다. backup-dir에 경로 센티넬을 넣은 fixture의 정상 rc=0 stdout에 그 경로가 그대로 나왔다. 기존 no_sentinel 시험은 plist 내부의 환경/인자/출력 경로만 센티넬로 만들고 백업 인자의 경로는 센티넬로 만들지 않아 이 경우를 놓친다. 정본은 경로값 비출력이고 **복원 실패 9에서만 백업 위치 출력이 명시**되어 있다. 정상 출력은 키 이름/PASS·고정 문구로 제한하거나, 정상 위치 출력도 허용할지 설계 계약에서 명시한다. 실패 9의 필요한 위치 표시는 유지한다.

**m3 — root_unchecked는 동치가 아니라 입력 시험의 빈틈이다.** Nano의 실제 mutate_plist.py에서 이 변이는 `if root != "dict" or not isinstance(document, dict):`를 `if False:`로 바꾼다. **유효한 빈 array 루트**를 주면 기본 소스는 종료 **3**, 변이는 `document.items()` 등의 오류로 **1**을 반환한다. 원본 fixture는 둘 다 불변이지만 문서화한 입력 거부 코드가 달라 **동치가 아니다**. 기존 root-array fixture는 array 안에 key를 넣은 형태라 파싱 자체가 먼저 실패하여 이 변이를 탐지하지 못한다.

유효한 empty/nonempty array·string·integer 등 비-dict plist를 추가해 입력 거부 3을 고정한다. 이 변이는 생존 시험 부족으로 재분류하고 탐지/동치/패턴 실패를 구분한 변이 원장을 갱신한다. Nano의 전체 78종 수치는 이 DA의 독립 실행 수치로 합산하지 않는다.

## 4. 9842d92의 코드 변경·동치 3건 처분

새 4개 훅 plist_changes/restore_corrupt/post_comment/post_error는 기존 ctx.hook을 거치며 **selftest=false이면 단락 평가로 꺼진다**. 생산 Context를 실행하지 않고 14개 훅 이름과 PLIST_EDIT_CALL_S/PAUSE_FILE을 환경에 넣어 확인했다: 활성 훅 **0**, call cap **7.0초**, pause 파일 생성 0. Python 본체는 -I로 실행된다. M2는 이 생산 훅 분리의 실패가 아니라 selftest 쓰기 대상 공간의 분리 실패다.

삭제된 backup_dir mode 재검사는 chmod 700 성공 직후의 순차 POSIX 경로에서는 중복이다. chmod 호출·실패 예외 처리와 디렉터리/UID 검사는 남아 있고 권한 시험도 있다. 이 삭제 자체를 새 결함으로 판단하지 않는다. 별도 구현 발주가 디렉터리 700/백업 600을 명시하므로, 백업까지 원본 mode와 같아야 한다는 정오표 문구로 이 정책을 뒤집지 않는다.

| Nano 동치 이름 | 정확한 변경과 판단 |
|---|---|
| root_unchecked | 루트/문서 dict guard 둘 다 제거. valid array에서 3→1이므로 **동치 반박**, m3 |
| nested_keys_seen_as_top_level | start handler의 depth==3을 depth>=3으로 변경. append/text 수집은 여전히 depth==3이고, 정상 dict의 top-level key 짝·document의 값 형 검사가 남아 최상위 ProcessType 아닌 값을 제거하지 못함. **현재 다른 검사들이 유지되는 단일 변이 범위에서 중복 방어라는 판단 수용**. 이름만 보고 모든 중첩 처리를 검증했다고 확대하지 않음 |
| post_shape_skipped | post의 shape만 생략하고 검증된 후보와의 **정확한 바이트 sha 일치 및 metadata 비교**는 유지. 동일 bytes에 대한 순수 shape 검사는 같은 결과이므로 현 경로·단일 변이 및 sha의 무결성 가정 아래 **동치 수용** |

독립 임시 복사본 변이 8종에서는 전제 제거·백업 sha 제거·사후 오류 처리 무력화·생산 훅 활성화·temp 정리 제거 **5종이 assertion 실패로 탐지**됐다. Nano 동치 3종은 선택한 기존 시험에서 모두 생존했고, 그중 root 변이만 위 새 유효 입력으로 비동치를 입증했다. 수집/setup 오류는 없었다. repository 파일을 변이하지 않았다.

## 5. 시험·회귀 증거

- 이 DA의 직접 실행: `../rag/.venv/bin/python -B -m pytest tests/test_plist_edit.py -q -p no:cacheprovider`(cwd=`feature-pack/rag-consumer`) → **107 passed in 18.13s, rc=0**.
- 독립 경계 재현 `/tmp/airag-plist-da-independent.py` → **rc=0**. 이 rc는 반례 상태를 관찰·기록한 검사 성공이지 제품의 안전 계약 통과라는 뜻이 아니다. INT/TERM 복원 누락, 보호 경로 교차 2종, 주석 삭제·경로 출력, 복원 중 신호 코드, valid root 변이와 생산 훅 비활성을 기록했다.
- 독립 변이 `/tmp/airag-plist-da-mutations.py` → **rc=0**, 8종/5탐지/3선택 시험 생존. 독립 반례 summary는 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-plist-da-independent-zx0w9nrk/summary.json`, 변이별 assertion 로그/summary는 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-plist-da-mutations-9_ix9900/`.

**note 1 — 전체 회귀는 1실패를 그대로 병기한다.** Master 로그 `regress-9842d92-20261016.log`의 말미를 확인했다: **1 failed, 1055 passed in 1129.15s, exit=1**. 실패는 기존 N4의 test_p0only_runs_p4_and_p0_and_never_the_account_steps이며 이번 plist 파일은 아니다. Master가 제공한 사실은 probe selftest의 rc=4/unknown_check_required/잔존, printf Broken pipe, 높은 동시 부하, 단독 재실행 3/3 통과, 관련 probe/N4 코드 변경 0이다. **부하 의존 불안정 후보**로만 기록하며 원인을 단정하거나 전체 회귀 통과로 바꾸지 않는다. 이 DA는 원인 규명·기존 N4 수정·단독 3회 재실행을 다시 수행하지 않았다.

## 6. 재심 범위

M1의 게시 후 종료/복원 경계와 M2의 selftest 보호 공간을 먼저 고치고, minor의 바이트/출력 계약·입력 시험 및 변이 분류를 보강하면 된다. 기존 107개에 이 반례들을 더해 검증하고, 전제·백업·후보·metadata·7초·복원 실패 9의 통과 계약은 유지한다. 운영 파일로 재현하거나 실제 op/launchd 집행을 섞을 필요는 없다. 수정·구현 DA가 끝나도 운영 편집은 별도 HIL이고 재개 R-4는 별개다.
