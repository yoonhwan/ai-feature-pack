# r963 실측 — push 안 된 커밋 수를 «로컬 ref 만» 으로 세기 (구현 범위 0)

결론: 원격 조회 없이 로컬 추적 ref 만으로 충분히 센다. 이 맥의 두 리포 1,005 워크트리(465 + 540)를 19초 / 15초에 한 바퀴 돌았고, 7초를 넘긴 워크트리는 0곳이었다.

측정 조건: 읽기 전용(git 쓰기 0 · fetch 0 · ls-remote 0) · `timeout 7` 로 git 호출마다 상한 · 측정 스크립트 = `/tmp/r963-measure.sh`(아래 전문) · 시각 2026-10-26 · 이 카드의 `ft-unpushed-summary.sh --dry-run` 으로 같은 값을 다시 냈다(교차확인).

## 표 1 — 리포별 (측정 스크립트 · 로컬 ref 만)

| 리포 | 워크트리 | 한 바퀴 소요 | 7초 넘는 워크트리 | 로컬 추적 ref 없는 가지 | HEAD 분리 | 셈 성공 |
|---|---|---|---|---|---|---|
| BYZ-Agents | 465 | 19초 | 0곳 | 117가지 | 130곳 | 335곳 |
| ai-feature-pack | 540 | 15초 | 0곳 | 192가지 | 114곳 | 426곳 |

## 표 2 — 같은 값을 `ft-unpushed-summary.sh --dry-run` 으로 (교차확인)

| 리포 | 소요 | 로컬 추적 ref=있음 | 원격 가지 없음 | HEAD 분리 | 문턱(50) 넘는 곳 | 최대 커밋 수 |
|---|---|---|---|---|---|---|
| BYZ-Agents | 16.5초 | 218 | 112 | 130 | 65곳 | 5073 (`lecture-nano-l63-l39-readout-number-normalize-best-ma`) |
| ai-feature-pack | 14.7초 | 234 | 193 | 126 | 7곳 | 534 (`rag-transplant`) |

- 표1과 표2의 «HEAD 분리» 가 다른 이유: 표1은 워크트리마다 `rev-parse` 를 돌려 실패(폴더가 사라진 등록)를 «분리» 로 못 세고, 표2는 `git worktree list --porcelain` 의 `detached` 줄을 그대로 센다. 표2가 정확하다(그래서 도구는 porcelain 을 쓴다).
- 표1의 «셈 성공» = `rev-list --count` 가 숫자를 낸 워크트리 수. 나머지는 폴더가 사라졌거나 `rev-parse` 가 실패한 등록이다.

## 측정 스크립트 전문 (`/tmp/r963-measure.sh`)

```bash
#!/bin/bash
set -uo pipefail
REPO="${1:?repo}"; TB="$(command -v timeout || command -v gtimeout)"; BR_MAIN="${2:-origin/main}"
start=$(date +%s)
wlist="$(git -C "$REPO" worktree list --porcelain)" || { echo "ERROR list"; exit 4; }
seen=0; detached=0; noref=0; slow=0; total=0; over=""
paths=$(printf '%s\n' "$wlist" | sed -n 's/^worktree //p')
while IFS= read -r p; do
  [ -n "$p" ] || continue; seen=$((seen+1)); [ -d "$p" ] || continue
  t0=$(date +%s)
  br="$("$TB" 7 git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  case "$br" in
    '') ;;
    HEAD) detached=$((detached+1));;
    *) if "$TB" 7 git -C "$p" rev-parse --verify -q "refs/remotes/origin/$br" >/dev/null 2>&1; then
         n="$("$TB" 7 git -C "$p" rev-list --count "refs/remotes/origin/$br..HEAD" 2>/dev/null)"; kind=L
       else noref=$((noref+1)); n="$("$TB" 7 git -C "$p" rev-list --count "$BR_MAIN..HEAD" 2>/dev/null)"; kind=N; fi;;
  esac
  dt=$(( $(date +%s) - t0 )); [ "$dt" -gt 7 ] && { slow=$((slow+1)); over="$over $p($dt s)"; }
  case "$n" in ''|*[!0-9]*) ;; *) total=$((total+1)); printf '%s\t%s\t%s\t%s\n' "$n" "$kind" "$br" "$p" >> /tmp/r963-counts.txt;; esac
done <<< "$paths"
echo "REPO=$REPO seen=$seen detached=$detached noref=$noref slow=$slow counted=$total secs=$(( $(date +%s) - start ))"
[ -n "$over" ] && echo "over7:$over"
```

## 조사 2 — 원격 접촉 없이 «같은 답» 이 나오는 근거

- `@{upstream}`·`ls-remote`·`fetch` 는 원격에 묻는다. 로컬 `refs/remotes/origin/<가지>` 는 이미 디스크에 있는 «마지막으로 본 원격» 이다.
- 그 ref 가 있으면 `rev-list --count refs/remotes/origin/<가지>..HEAD` 는 원격에 묻지 않고 «push 안 된 커밋 수» 를 낸다. 없으면 가질 수 있는 답은 «원격 가지 없음» 이고, 그때는 `origin/main..HEAD` 로 «main 에 없는 커밋» 을 낸다(이름을 그렇게 붙인다).
- 다른 점 하나: 로컬 추적 ref 는 «낡을 수 있다». 낡으면 숫자가 실제보다 커진다(그만큼 덜 push 됐다는 뜻이므로 안전한 쪽이다). 반대로 «원격에 새로 생긴 가지» 는 ref 가 생기기 전까지 «없음» 으로 보인다 — 이 카드는 원격을 안 보므로 그 한계를 받아들인다.

## 남는 위험

- 워크트리 1,005곳에서 19초. 워크트리가 몇 배로 늘면 70초 마감을 넘겨 «미완주» 가 잦아질 수 있다. 그때는 그날 표식이 안 서고 ERROR 1줄만 남는다(«문제없음» 오보는 안 난다).
- 폴더가 사라진 등록(`git worktree prune` 대상)은 공용 repo 의 가지 ref 로 센다. 가지 ref 까지 사라졌으면 «이미 사라진 등록 N곳» WARN 으로만 남기고 셈에서 뺐다.
