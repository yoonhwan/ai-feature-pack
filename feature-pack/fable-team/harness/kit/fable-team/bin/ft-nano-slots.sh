#!/usr/bin/env bash
# ft-nano-slots.sh — 나노 슬롯 채움 상태 1블록 (오빠 2026-10-02 16:2x 「나노가 또 놀고있네? … 열었다 닫고 다음거 안시키고 슬롯을 비워두네」)
#   규칙: 메인(master)이 정한 나노 슬롯(FT_NANO_SLOTS · 기본 5)은 «항상 채운다» — 닫는 같은 턴에 대기/ 카드로 spawn.
#   arch 지정을 기다리지 않는다. 예외(시험 겹침 · 최우선 작업이 슬롯을 요구)는 그 사유를 보고에 한 줄로 쓴다.
#   C6(SPEC-roles P3-1·2·5·7): 점유 = 살아 있는 석 전부(일하는 석 + 노는 석) · 빈 석 = 상한 − 점유 — 노는 석은 «푸는 대상»이지 빈 석이 아니다.
#     후보 = 대기/ 중 머리줄 4줄(Issue:·상태:·선행:·시험 입력:)이 있는 카드(FT_ACTIVE_ISSUES="#12,#13" 이면 그 Issue 카드만) — 모자란 카드는 REJECT 없이 후보에서 «제외» + 사유 1줄.
#     예약석 +1(상한 밖 · 라이브 카드 전용): seats 행 `"reserved": true` 가 점유자 · 카드 `상태:` 에 «라이브» 가 든 카드만 예약석 후보.
#   --inventory = 미랜딩 nano/* 브랜치 전수 행(M7 범위 5 · single_set_testing §3 말미 «간과 금지»): 매 틱 호출용이라 브랜치별 git cherry 금지(590개에 120 s+).
#     분모 = `for-each-ref --no-merged=<feat> refs/heads/nano/`(조상 미포함) − 랜딩 원장(FT_NANO_LANDING_LEDGER jsonl {branch,tip,squash_sha}) 중 tip 이 현재 tip 과 같은 것.
#     squash 는 조상 관계를 안 만들어 원장 없이는 랜딩된 브랜치가 영원히 «미랜딩» 으로 남는다. 행: 브랜치\t마지막 커밋 날짜\t미랜딩 커밋 수\t카드 상태(대기|진행|완성|없음).
#   출력만 한다(판정·spawn 은 master). ft-nano-close.sh 가 CLOSED 직후 부른다 · ft-news-tick 에서도 부를 수 있다.
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
MAX="${FT_NANO_SLOTS:-5}"
if [ -n "${FT_INDEX_DIR:-}" ]; then IDX_DIR="$FT_INDEX_DIR"
else   # R416: «명단 = ref · 폴더 = WT 실재»(R400 r3·R406 과 같은 함수) — 공유 루트의 옛 TEAMS.md 사본을 믿지 않는다 · ref 못 읽음 = ERROR(cwd 명단 후퇴 0)
  . "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-team-lib.sh" || { echo "ERROR ft-team-lib.sh 를 못 읽었다" >&2; exit 1; }
  _ref="${FT_TEAMS_REF:-origin/main}"
  _cands="$(ft_team_cands_ref "$WT" v65 "$_ref")" || { echo "ERROR v65 팀 폴더를 못 풀었다(명단 $_ref:design/TEAMS.md · 폴더 = $WT)" >&2; exit 1; }
  IDX_DIR="$(printf '%s\n' "$_cands" | head -1)/indices"
  for _c in $_cands; do [ -d "$_c/indices" ] && { IDX_DIR="$_c/indices"; break; }; done
fi
if [ "${1:-}" = "--inventory" ]; then
  FEAT="${FT_NANO_FEAT:-feat/v6-realtime-live}"; LANDING="${FT_NANO_LANDING_LEDGER:-$ROOT/.fable-team/state/nano-landing.jsonl}"
  refs="$(git -C "$WT" for-each-ref --no-merged="$FEAT" --format='%(refname:short)|%(committerdate:short)|%(objectname)|%(ahead-behind:'"$FEAT"')' refs/heads/nano/)" \
    || { echo "FAIL ft-nano-slots --inventory — git for-each-ref 실패(feat=$FEAT)" >&2; exit 1; }
  python3 - "$LANDING" "$IDX_DIR" "$FEAT" "$refs" <<'PY'
import json, os, sys
ledger, idx, feat, refs = sys.argv[1:5]
landed = {}
if os.path.isfile(ledger):
    for ln in open(ledger, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            r = json.loads(ln)
            landed[r["branch"]] = r["tip"]
rows, total = [], 0
for ln in refs.splitlines():
    name, date, tip, ab = ln.split("|", 3)
    total += 1
    if landed.get(name) == tip:
        continue
    ahead = ab.split()[0] if ab.strip() else "?"
    slug = name.split("/", 1)[1]
    card = next((st for st in ("진행", "대기", "완성") if os.path.isfile(os.path.join(idx, st, slug + ".md"))), "없음")
    rows.append((date, name, ahead, card))
rows.sort()
print(f"INVENTORY unlanded={len(rows)} (분모: 조상 미포함 {feat} --no-merged nano/* {total}개 − 랜딩 원장 tip 일치 {total - len(rows)}개 · 오래된 순)")
for date, name, ahead, card in rows:
    print(f"{name}\t{date}\t{ahead}\t{card}")
PY
  exit $?
fi
LIVE="$(tmux ls -F '#S' 2>/dev/null)"
IDLE_MIN="${FT_NANO_IDLE_MIN:-10}"
# 좌석별 턴 상태(WORKING/IDLE …) + 마지막 활동 초 — 「press·DA 대기로 노는 석」도 슬롯을 먹는다(오빠 10-02 실측: 9석 중 3석 대기)
TURNS="$(python3 -c "
import json,sys
d=json.load(open('$SEATS',encoding='utf-8'))
print('\n'.join(k for k,v in d.items() if isinstance(v,dict) and v.get('role')=='nano' and not v.get('_replaced_by')))" \
  | while read -r s; do printf '%s\n' "$LIVE" | grep -qxF "$s" || continue
      printf '%s\t%s\n' "$s" "$(bash "$(dirname "$0")/ft-seat-status.sh" turn "$s" 2>/dev/null | head -1)"; done)"
python3 - "$MAX" "$IDX_DIR" "$IDLE_MIN" "$TURNS" "$SEATS" "${FT_ACTIVE_ISSUES:-}" <<'PY'
import json, os, re, sys
mx, idx, idle_min, turns = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
seats_path, active = sys.argv[5], {t for t in re.split(r"[,\s]+", sys.argv[6]) if t}
rows = [l.split("\t", 1) for l in turns.splitlines() if "\t" in l]
def idle_s(st):  # turn 출력 = STATE <턴 끝 UTC ISO> … — 턴 끝에서 지금까지 초
    import datetime as dt
    f = st.split()
    try: end = dt.datetime.fromisoformat(f[1].replace("Z", "+00:00"))
    except (IndexError, ValueError): return 0
    return int((dt.datetime.now(dt.timezone.utc) - end).total_seconds())
working = [s for s, st in rows if not (st.startswith("IDLE") and idle_s(st) >= idle_min * 60)]
idle = [(s, st) for s, st in rows if s not in working]
seats = json.load(open(seats_path, encoding="utf-8"))
reserved = [s for s, _ in rows if isinstance(seats.get(s), dict) and seats[s].get("reserved")]
occupied = len(rows) - len(reserved)   # 점유 = 살아 있는 석 전부(노는 석 포함) · 예약석은 상한 밖
empty = max(mx - occupied, 0)
print(f"SLOTS nano 점유 {occupied}/{mx} (일하는 석 {len(working)} · 노는 석 {len(idle)}) · 빈 석 {empty} · 예약석 {'점유 ' + reserved[0] if reserved else '비어 있음'}(+1 · 라이브 카드 전용)")
for s in working: print(f"  · {s}")
for s, st in idle:
    print(f"  ✗ 노는 석 {s} ({st.split()[0]} {idle_s(st)//60}분) → ★master 가 막힌 것을 푼다★(무엇을 기다리나 = 랜딩·DA 소환 요청·press 순번·판정 → 그 턴에 집행·요청) → 완성 → 테스트 끝나면 ft-nano-close(워크트리 정리·브랜치 보존)")
wait = os.path.join(idx, "대기")
cands, live, skipped = [], [], []
for f in sorted(os.listdir(wait)) if os.path.isdir(wait) else []:
    if not f.endswith(".md") or f.startswith("SB-"): continue
    try: t = open(os.path.join(wait, f), encoding="utf-8").read()
    except OSError: continue
    head = re.split(r"^##\s", t, maxsplit=1, flags=re.M)[0]   # 머리줄 = 첫 «## » 절 앞
    val = {k: (re.search(rf"^\s*[-*]?\s*{k}:[ \t]*(\S.*)$", head, re.M) or [None, None])[1] for k in ("Issue", "상태", "선행", "시험 입력")}
    miss = [k for k, v in val.items() if not v]
    if miss: skipped.append(f"{f}(머리줄 없음: {'·'.join(miss)})"); continue
    if active and val["Issue"].split()[0] not in active: skipped.append(f"{f}(비활성 Issue {val['Issue'].split()[0]})"); continue
    (live if "라이브" in val["상태"] else cands).append(f)
if skipped: print(f"  후보 제외 {len(skipped)}장(REJECT 아님): " + " · ".join(skipped))
if not reserved and live:
    print(f"  예약석(+1 · 라이브 전용) 후보 {len(live)}장:")
    for f in live[:1]: print(f"    bash .fable-team/bin/ft-nano-spawn.sh {os.path.relpath(wait, os.getcwd())}/{f}")
if not empty: sys.exit(0)
print(f"★빈 석 {empty} — 이 턴에 spawn 한다(arch 지정 대기 금지 · 예외는 사유 한 줄)★")
print(f"  후보(대기/ · 머리줄 4줄 충족{' · 활성 Issue ' + ','.join(sorted(active)) if active else ''} {len(cands)}장 · 앞 {min(len(cands), empty * 2)}):")
for f in cands[: empty * 2]: print(f"    bash .fable-team/bin/ft-nano-spawn.sh {os.path.relpath(wait, os.getcwd())}/{f}")
PY
