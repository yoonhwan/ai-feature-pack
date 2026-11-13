"""ft 2.0 keeper — B1 complete 누락 잡기 · B1r 카드 resolver · 착지 판정 (r1812 · keeper.py 가 섞어 쓴다 · B1·B2 가 같은 결과를 쓴다).

카드 후보 = TEAMS.md 의 팀 폴더(쌍둥이 포함) × indices/{진행,대기,완성} × BYZ ref(ops/main-base → main).
읽기는 `git ls-tree`·`git show` 뿐(작업 트리 0). 착지 = 마지막 `- 착지: <sha40>` 줄 → 팩 origin/main ∨ BYZ 두 ref 의 조상.
"""
import importlib.util
import os
import re

FT2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_SPEC = importlib.util.spec_from_file_location("ft2_keeper_land_cli", os.path.join(FT2, "core", "cli.py"))
cli = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(cli)
OK = "접수 성공"

REFS = ("origin/ops/main-base", "origin/main")       # BYZ 카드·착지 ref (B1r 순서)
STAGES = ("진행", "대기", "완성")
LAND = re.compile(r"^- 착지: ([0-9a-f]{40})(?=\s|$)", re.M)   # r1817 D2 — 40hex 뒤 공백(괄호 꼬리)·줄 끝만 · 짧은·41자·앞 글자 = 없음


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

    def landing(self, team, work):
        """(sha, ref, 사유) — 후보 0·충돌 = 판정 불가 · 착지 줄 없음 · 어느 ref 에도 조상 아님 = 미도달."""
        cards, hits = self.cards(team), {}
        if isinstance(cards, str):
            return None, None, cards
        for ref, path in cards:
            if not (os.path.basename(path).startswith(work + "-") and path.endswith(".md")):
                continue
            rc, body, _ = self.git(self.root, "show", "%s:%s" % (ref, path))
            if rc != 0:
                return None, None, "판정 불가 · git show %s rc %s" % (path, rc)
            hits[(ref, path)] = (LAND.findall(body) or [None])[-1]
        shas = sorted({sha for sha in hits.values() if sha})
        if not hits:
            return None, None, "판정 불가 · 카드 후보 0"
        if len(shas) > 1:
            return None, None, "판정 불가 · 착지 줄 충돌 " + " ".join(shas)
        if not shas:
            return None, None, "착지 줄 없음"
        sha = shas[0]
        for repo, ref in ((self.pack, "origin/main"), (self.root, REFS[0]), (self.root, REFS[1])):
            if self.git(repo, "merge-base", "--is-ancestor", sha, ref)[0] == 0:
                return sha, ("pack:" if repo == self.pack else "byz:") + ref, ""
        return sha, None, "미도달"

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
        if not self.done(team, work):
            return self.log("판정 불가", team, "%s complete 뒤 done 확인 못 함(%s) — B2 0" % (work, out.get("result")))
        self.log("COMPLETED", team, "%s 착지 %s ref %s" % (work, sha, ref))
        return True
