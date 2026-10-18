# staged-514 — 루트 지침(판정 514) + 511(§8·BOOT 18) + 532 합본 · 정본 설치용 완성본 (byz-harness-arch-claude#18 · 2026-10-08 · master#18 #65219)

| 설치 대상(라이브) | 이 폴더 파일 | 라이브 sha256 앞16(만든 때) | 완성본 sha256 앞16 |
|---|---|---|---|
| `~/.claude/skills/fable-team/references/main-team-governance.md` | `main-team-governance.md` | `d5941acd2db653bb` | `c5d73fff80291434` |
| `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` | `COMM-GUIDE-BOOT.md` | `9573c463baa968a2` | `01cddacdb2b070d8` |

## 만든 법 (라이브 대비 «더하기만» · 삭제 줄 0)
1. 바탕 = `design/teams/harness/staged-511/` 두 파일 — 라이브 대비 더하기만 확인(governance `## 8.` 8줄 · BOOT 18 + 머리 숫자). 511 교정본(DA-511 r2 · 「HIL/외부 대기 확인」 경계 포함).
2. governance 끝에 `## 9.` = 루트 지침 초안 `nano/root-guideline-514` 커밋 `6fdb732e1f` §6-1 코드블록 «글자 그대로» + 한 줄 추가(아래 3).
3. BOOT 18 뒤에 19 = 같은 커밋 §6-2 코드블록 글자 그대로 + 한 구절 추가(아래 3) · 머리 「17줄」→「19줄」.
4. ★§6 코드블록 밖에서 더한 것 = 판정 532(같은 턴 규칙) 하나뿐★ — r4 가 §3-2·방송문에만 넣고 §6-1·§6-2 코드블록엔 안 넣어서, 정본에 빠지지 않게 arch 가 §3-2 원문에서 옮김:
   - governance §9 「끝낸 좌석은 상위 1단에…」 줄 바로 뒤 1줄: 「같은 턴 규칙(오빠 판정 532): … 미이행은 받는 쪽 master 가 ②정지·미완으로 처리한다(깨움·반송).」
   - BOOT 19 「…을 보내고 쉰다」 뒤 괄호 1구: 「(완료 조건 충족 = 그 턴에 증거 줄 + 발신 · 미루면 ② — 판정 532)」

## 검증 (만든 때)
- `diff <라이브> <완성본>`: governance 삭제 0 · 추가 17줄 / BOOT 머리 1줄 교체(17→19) + 추가 2줄(18·19). UTF-8 BOM 없음.

## 설치 순서 (master 집행 · 루트 지침 §6-6)
① 라이브 sha 가 위 표 «만든 때» 값과 같은지 확인(다르면 설치 중지 · arch 에 재합본 요청) → ② 백업 → ③ cp + cmp 두 파일 → ④ `ft-version.sh check`(BOOT sha 갱신) → ⑤ 루트 지침 §7 방송 1통(511 정정 절 포함) → ⑥ 상태판 칸(§6-3)은 별 카드(코드 = 나노).
- 선택 항목(§6-4 closeout-policy · §6-5 SEATBELT)은 이 폴더에 없음 — 넣을지는 master/planner 판단.
- `staged-511/` 는 이 폴더로 대체(설치 금지 · HOLD-516 유지).
