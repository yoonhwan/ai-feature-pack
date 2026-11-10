# 명부 파일 고르기 «한 함수» — recv 계보(mbox_lineage.py)와 send 수신자 판정(mbox_guard.sh)이 함께 부른다(두 곳이 갈라지지 않게 · r745).
#   규칙: 이름의 팀 글자 → seats-<팀>.json · 그 파일이 명부 목록(docs ∪ 읽기 실패 bad)에 «없을 때만» `_renamed_from == <팀>` 인 명부를
#   «정확히 1개» 찾아 쓴다(팀 개명은 행 이름을 그대로 두고 명부 파일 이름만 바꾸므로 옛 이름의 tfile 이 사라진다 · r745 원인).
#   원 명부 파일이 있으면 그 파일이 이긴다 · 별칭 0개·2개+ 면 지금과 같이 "" (2개+ 는 경고 1줄) · 여러 단 개명은 범위 밖.
import os, re


def teamfile(d, name, docs, bad):
    """(authoritative 명부 파일, 경고 또는 "") — 파일을 못 고르면 ("", "") 이고 부르는 쪽은 지금과 같이 동작한다."""
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", name)
    if not m:
        return "", ""
    team = m.group(1)
    direct = d + ("/seats.json" if team == "v65" else "/seats-" + team + ".json")
    if direct in docs or direct in bad:
        return direct, ""
    alias = [f for f, v in docs.items() if v.get("_renamed_from") == team]
    if len(alias) == 1:
        return alias[0], ""
    if len(alias) > 1:
        return "", "명부 별칭 충돌 " + team + " — " + " ".join(sorted(os.path.basename(f) for f in alias)) + " (별칭 안 씀)"
    return "", ""
