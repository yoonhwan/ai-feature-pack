"""ft 2.0 keeper — B1 complete 누락 잡기 · B1r 카드 resolver · 착지 판정 (r1812 · keeper.py 가 섞어 쓴다 · B1·B2 가 같은 결과를 쓴다).

카드 후보 = TEAMS.md 의 팀 폴더(쌍둥이 포함) × indices/{진행,대기,완성} × BYZ ref(ops/main-base → main).
읽기는 `git ls-tree`·`git show` 뿐(작업 트리 0). 착지 = 마지막 `- 착지: <sha40>` 줄 → 팩 origin/main ∨ BYZ 두 ref 의 조상.
"""
import datetime
import importlib.util
import os
import re

FT2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_SPEC = importlib.util.spec_from_file_location("ft2_keeper_land_cli", os.path.join(FT2, "core", "cli.py"))
cli = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(cli)
PROJ = cli._load("projection")   # r1893 최신 dispatch attempt · launch intent 경로
OK = "접수 성공"

REFS = ("origin/ops/main-base", "origin/main")       # BYZ 카드·착지 ref (B1r 순서)
STAGES = ("진행", "대기", "완성")
LAND = re.compile(r"^- 착지: ([0-9a-f]{40})(?=\s|$)", re.M)   # r1817 D2 — 40hex 뒤 공백(괄호 꼬리)·줄 끝만 · 짧은·41자·앞 글자 = 없음
CARDMAP = os.path.join(".fable-team", "teams", "%s", "runtime", "cards.tsv")   # r1819 F2 짝 표 · 팀장 append · keeper 읽기만
MAPPED = re.compile(r"^(design/.+)/indices/(?:진행|대기|완성)/([^/]+\.md)$")


def team_row(md, team):
    """TEAMS.md 표에서 팀 행(칸 목록) 1개 · 없으면 None."""
    for line in md.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) > 1 and cells[0] == team:
            return cells
    return None


def folders(cell):
    """팀 폴더 칸 → [명단 꼴, 쌍둥이] (design/<팀> ↔ design/teams/<팀>)."""
    base = cell.strip("`").replace("$FT_HARNESS_ROOT/", "").strip("/")
    if "/teams/" in base:
        twin = base.replace("design/teams/", "design/", 1)
    else:
        twin = base.replace("design/", "design/teams/", 1)
    return list(dict.fromkeys([base, twin]))


def staged(folder, names):
    """ls-tree 이름 중 <폴더>/indices/<진행|대기|완성>/<파일> 꼴만."""
    head = folder + "/indices/"
    return [path for path in names.splitlines() if path.startswith(head)
            and path[len(head):].partition("/")[0] in STAGES and path.count("/") == folder.count("/") + 3]


class Landing:
    def cards(self, team):
        """(ref, 경로) 목록 · 판독 실패 = 판정 불가 문자열. 바퀴 안 팀마다 1회(캐시)."""
        if team not in self.cache:
            self.cache[team] = self._cards(team)
        return self.cache[team]

    def _cards(self, team):
        out = []
        for ref in REFS:
            rc, md, _ = self.git(self.root, "show", ref + ":design/TEAMS.md")
            row = team_row(md, team) if rc == 0 else None
            if row is None:
                return "판정 불가 · %s:design/TEAMS.md rc %s 팀 행 없음" % (ref, rc)
            for folder in folders(row[1]):
                rc, names, _ = self.git(self.root, "ls-tree", "-r", "--name-only", ref, "--", folder + "/indices")
                if rc != 0:
                    return "판정 불가 · ls-tree %s rc %s" % (ref, rc)
                out += [(ref, path) for path in staged(folder, names)]
        return out

    def cardmap(self, team):
        """r1819 F2·F4 짝 표 {work: [경로…]} · 없음 = {} · 판독 실패 = 판정 불가 문자열 · 탭 없는 줄 = 무시 + 경고 1줄 · 팀마다 1회."""
        if ("map", team) not in self.cache:
            lines, rows = [], {}
            try:
                with open(os.path.join(self.root, CARDMAP % team), encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            except FileNotFoundError:
                pass
            except (OSError, ValueError) as exc:
                rows = "판정 불가 · 짝 표 판독 실패 %s" % type(exc).__name__
            for work, tab, path in (line.partition("\t") for line in lines if line.strip()):
                if not tab:
                    self.log("경고", team, "짝 표 탭 없는 줄 무시 · " + work[:40])
                rows.setdefault(work.strip(), []).append(path.strip()) if tab else None
            self.cache[("map", team)] = rows
        return self.cache[("map", team)]

    def mapped_cards(self, team, path):
        """짝 표 경로 → 두 ref × 단계(진행·대기·완성)의 같은 이름 카드 · 팀 폴더 밖 허용."""
        m, out = MAPPED.match(path), []
        for ref in REFS if m else ():
            rc, names, _ = self.git(self.root, "ls-tree", "-r", "--name-only", ref, "--", m.group(1) + "/indices")
            if rc != 0:
                return "판정 불가 · ls-tree %s rc %s" % (ref, rc)
            out += [(ref, p) for p in staged(m.group(1), names) if os.path.basename(p) == m.group(2)]
        return out or "판정 불가 · 짝 표 카드 없음 " + path

    def landing(self, team, work):
        """(sha, ref, 사유) — 후보 0·충돌 = 판정 불가 · 착지 줄 없음 · 어느 ref 에도 조상 아님 = 미도달."""
        cards, hits = self.cardmap(team), {}
        mapped = cards.get(work) if isinstance(cards, dict) else None
        name = os.path.basename(mapped[0]) if mapped else work + ".md"
        own = name == work + ".md" or name.startswith(work + "-")   # F3 자기 카드 · 그 밖 = 부모(행 수 무관 «착지(<work>)» 줄)
        if mapped:   # F2 짝 표 먼저
            cards = "판정 불가 · 짝 표 같은 work %d줄" % len(mapped) if len(mapped) > 1 else self.mapped_cards(team, mapped[0])
        elif isinstance(cards, dict):
            cards = self.cards(team)
        if isinstance(cards, str):
            return None, None, cards
        names = {os.path.basename(path) for _, path in cards}
        exact = work + ".md" in names   # F1 정확한 stem 먼저 · 없으면 «work-» 접두
        land = LAND if own else re.compile(LAND.pattern.replace("착지:", "착지\\(%s\\):" % re.escape(work)), re.M)
        for ref, path in cards:
            base = os.path.basename(path)
            if not mapped and not (base == work + ".md" if exact else base.startswith(work + "-") and base.endswith(".md")):
                continue
            rc, body, _ = self.git(self.root, "show", "%s:%s" % (ref, path))
            if rc != 0:
                return None, None, "판정 불가 · git show %s rc %s" % (path, rc)
            hits[(ref, path)] = (land.findall(body) or [None])[-1]
        shas = sorted({sha for sha in hits.values() if sha})
        if not hits:
            return None, None, "판정 불가 · 카드 후보 0"
        if len(shas) > 1:
            return None, None, "판정 불가 · 착지 줄 충돌 " + " ".join(shas)
        if not shas:
            return None, None, "착지 줄 없음" if own else "판정 불가 · 조각 착지 줄 없음"
        sha = shas[0]
        for repo, ref in ((self.pack, "origin/main"), (self.root, REFS[0]), (self.root, REFS[1])):
            if repo not in self.stale and self.git(repo, "merge-base", "--is-ancestor", sha, ref)[0] == 0:   # r1963 낡은 리포 ref = 조상으로도 «조상 아님» 으로도 안 셈
                old = self.pre_attempt(team, work, repo, sha)
                return (None, None, old) if old else (sha, ("pack:" if repo == self.pack else "byz:") + ref, "")
        return (None, None, "판정 불가 · 팩 fetch 실패") if self.stale else (sha, None, "미도달")   # 낡음이 있으면 미도달 알림 0

    def pre_attempt(self, team, work, repo, sha):
        """r1893 — 최신 dispatch attempt intent base_sha 대조 · rc0 = 옛 줄 · rc1 = 조상 아님(진행) · 그 밖 = 판정 불가 · intent·base_sha 없음 = ""."""
        runtime = PROJ.runtime_path(self.root, team)
        recs = PROJ.journal.Journal(runtime, rec=PROJ.record).records()
        att = ([r.get("attempt") for r in recs if r.get("kind") == "dispatch" and r.get("work") == work] or [None])[-1]
        intent = self.read_json(os.path.join(runtime, "launch", "%s@%s.intent" % (work, att))) if att else {}
        base = intent.get("base_sha")
        have = self.git(repo, "cat-file", "-e", base)[0] if base else 0   # r1910 rc1 = 명시적 missing(다른 repo) · 그 밖 = git 실패
        if have == 1:
            return self.pre_attempt_time(repo, sha, intent.get("at"))
        if have != 0:
            return "판정 불가 · 옛 착지 대조 cat-file rc %s" % have
        rc = self.git(repo, "merge-base", "--is-ancestor", sha, base)[0] if base else 1
        return "옛 착지 줄(attempt 전) " + sha[:8] if rc == 0 else "" if rc == 1 else "판정 불가 · 옛 착지 대조 git rc %s" % rc

    def pre_attempt_time(self, repo, sha, at):
        """r1910 — 다른 repo base · 착지 committer 시각(%cI) vs intent at(로컬 naive → 로컬 aware) 순간 비교 · 착지 ≥ at = 진행."""
        rc, out, _ = self.git(repo, "log", "-1", "--format=%cI", sha)
        try:
            landed, opened = (datetime.datetime.fromisoformat(v) for v in (out.strip() if rc == 0 else None, at))
            old = landed < opened.astimezone()   # naive at = 로컬 시각 → aware · 문자열 비교 0
        except (TypeError, ValueError):
            return "판정 불가 · 옛 착지 시각 대조 git rc %s · at %r" % (rc, at)
        return "옛 착지 줄(attempt 전 · 다른 repo 시각) " + sha[:8] if old else ""

    def done(self, team, work):
        proj = self.project(self.root, team)
        return proj.get("result") == OK and bool((proj.get("works", {}).get(work) or {}).get("done"))

    def complete(self, team, work, attempt, landed):
        """B1 — 착지 sha 가 조상일 때만 complete 1회 → 투영 done 재확인 뒤에만 참(= B2 로 간다 · Q1)."""
        sha, ref, why = landed
        if why == "미도달":
            body = "[크리티컬] 착지 줄 sha 미도달 %s %s %s" % (team, work, sha)
            self.notify(team, "unreached|%s|%s|%s" % (team, work, sha), body)
        if why:
            return self.log("HELD", team, "%s %s" % (work, why))
        argv = ["complete", "--root", self.root, "--team", team, "--work", work, "--attempt", attempt]
        out, _rc = cli.run(argv)
        self.fa.journal(self.root, team, out, work)   # r1886 ⓓ 쓰기 거절·성공 둘 다
        if not self.done(team, work):
            return self.log("판정 불가", team, "%s complete 뒤 done 확인 못 함(%s) — B2 0" % (work, out.get("result")))
        self.log("COMPLETED", team, "%s 착지 %s ref %s" % (work, sha, ref))
        return True
