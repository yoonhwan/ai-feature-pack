"""ft_roster_lib.py — 명부(seats*.json) 읽기·원자 쓰기·라우팅 칸 쓸기 공용 (ft-seat-retire.sh · ft-seat-close.sh 가 같은 폴더에서 import).
r429 묶음: 두 도구에 같은 글자로 있던 load/쓰기와 retire 의 라우팅 칸 쓸기를 한 곳으로 옮겼다(동작 불변 · 줄 수 상한)."""
import collections, glob, json, os, shutil

ROUTE = ("_hil_route", "_planner", "_desk_route")   # r429 라우팅 칸(+ 이름이 _route 로 끝나는 칸) — 남의 명부에서도 바꾼다 · 역할 칸(_master·_arch…)은 자기 팀 명부만


def is_route(k): return k in ROUTE or k.endswith("_route")


def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None


def dump(f, dd):   # 쓰기 중 죽어도 원본 무손상 — tmp 에 다 쓴 뒤 한 번에 교체(N3 · D3 승계 원자성)
    tmp = f + ".tmp-" + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh: json.dump(dd, fh, ensure_ascii=False, indent=2); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    shutil.copymode(f, tmp); os.replace(tmp, f)


def scan_routes(p, old):   # r429 같은 폴더(루트 .fable-team) 다른 명부 전부 → (others{파일: 명부}, routes{파일: [칸…]} 바꿀 것 있는 파일만, bad[손상 파일 이름])
    others = {f: load(f) for f in sorted(glob.glob(os.path.dirname(os.path.abspath(p)) + "/seats*.json")) if os.path.abspath(f) != os.path.abspath(p)}
    bad = [os.path.basename(f) for f, v in others.items() if not isinstance(v, dict)]
    routes = {} if bad else {f: ks for f, ks in ((f, [k for k, v in dd.items() if is_route(k) and v == old]) for f, dd in others.items()) if ks}
    return others, routes, bad


def apply_routes(others, routes, new, ts):   # r429 남의 명부 = 라우팅 칸만 · 파일마다 .bak-retire-<ts> → 출력용 [파일:칸…]
    for f, ks in routes.items():
        shutil.copy(f, f + ".bak-retire-" + ts); others[f].update((k, new) for k in ks); dump(f, others[f])
    return [os.path.basename(f) + ":" + k for f, ks in routes.items() for k in ks]
