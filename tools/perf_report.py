#!/usr/bin/env python3
"""Builds docs/perf/city_bench.md from the city benchmark JSON files.

Usage: tools/perf_report.py docs/perf/city_bench_before.json docs/perf/city_bench_after.json [docs/perf/city_bench_after_dcq.json]
"""
import json
import sys

PHASES = {"empty": "Пустой город", "walk": "Прогулка по городу", "npcs": "Появились 24 NPC", "battle": "Массовая битва",
          "magic": "Обмен магией", "explosion": "Крупные взрывы (ультимейты)",
          "resonance": "Резонансы и буря ковенов", "boss": "Бой с боссом в городе (смена фаз)"}


def load(p):
    with open(p) as f:
        return json.load(f)["results"]


def g(r, path, default=0.0):
    cur = r
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def pct(a, b):
    if a == 0:
        return ""
    return "%+.0f%%" % ((b - a) / a * 100.0)


def main():
    files = sys.argv[1:]
    runs = [load(p) for p in files]
    names = ["до", "после"] + (["после + DCQ"] if len(runs) > 2 else [])
    rows = [
        ("Физика: шаг (мс, среднее)", ("physics_ms", "avg")),
        ("Физика: шаг (мс, p95)", ("physics_ms", "p95")),
        ("Физика существ за кадр (мс)", ("sub_ms", "actor_phys", "avg")),
        ("ИИ ботов за кадр (мс)", ("sub_ms", "ai", "avg")),
        ("Анимация гуманоидов за кадр (мс)", ("sub_ms", "rig", "avg")),
        ("Вызовы отрисовки (среднее)", ("draw_calls", "avg")),
        ("Вызовы отрисовки (макс.)", ("draw_calls", "max")),
        ("Объектов в кадре (среднее)", ("objects", "avg")),
        ("Примитивов в кадре, тыс.", ("primitives", "avg")),
        ("Излучателей частиц (пик)", ("peak", "particles")),
        ("Частиц в излучателях (пик)", ("peak", "particle_amount")),
        ("Источников света в сцене (пик)", ("peak", "lights")),
        ("Существ (пик)", ("peak", "actors")),
    ]
    out = ["# Замер городского сражения", "",
           "Сценарий `tests/city_bench.tscn`: столица, шесть фаз; одинаковый мир (seed 777001) до и после.",
           "Среда: Linux-контейнер, программный рендер (llvmpipe, OpenGL). **Реальные FPS и время GPU здесь не",
           "показательны** — сравниваются время CPU (физика, ИИ, анимация), число отрисовок, объектов, частиц и",
           "источников света. На Android-устройствах замер не проводился.", ""]
    for ph, title in PHASES.items():
        out.append("## " + title)
        out.append("")
        out.append("| Показатель | " + " | ".join(names) + " | изменение |")
        out.append("|---|" + "---|" * len(names) + "---|")
        for label, path in rows:
            vals = []
            for r in runs:
                v = g(r.get(ph, {}), path)
                if "Примитивов" in label:
                    v = v / 1000.0
                vals.append(v)
            fmt = ["%.2f" % v if isinstance(v, float) and v < 100 else "%.0f" % v for v in vals]
            out.append("| %s | %s | %s |" % (label, " | ".join(fmt), pct(vals[0], vals[1])))
        out.append("")
    with open("docs/perf/city_bench.md", "w") as f:
        f.write("\n".join(out) + "\n")
    print("\n".join(out))


def levels(files, out_path="docs/perf/city_bench_0110.md"):
    """Same scenario at different quality levels (0.11.0): one table per phase."""
    runs = [load(p) for p in files]
    names = [p.split("_")[-1].replace(".json", "").upper() for p in files]
    rows = [
        ("Физика: шаг (мс, среднее)", ("physics_ms", "avg")),
        ("Физика: шаг (мс, p95)", ("physics_ms", "p95")),
        ("Физика существ за кадр (мс)", ("sub_ms", "actor_phys", "avg")),
        ("ИИ за кадр (мс)", ("sub_ms", "ai", "avg")),
        ("Вызовы отрисовки (среднее)", ("draw_calls", "avg")),
        ("Объектов в кадре (среднее)", ("objects", "avg")),
        ("Излучателей частиц (пик)", ("peak", "particles")),
        ("Источников света в кадре (пик, все)", ("peak", "lights")),
        ("Существ (пик)", ("peak", "actors")),
    ]
    out = ["# Замер 0.11.0: город, резонанс, босс — низкие и высокие настройки", "",
           "Сценарий `tests/city_bench.tscn` (8 фаз, столица, seed 777001), динамическое качество включено.",
           "Среда: Linux-контейнер, программный рендер (llvmpipe, OpenGL), поэтому FPS и время GPU",
           "**не показательны**. Сравниваются CPU-время, отрисовки, объекты, частицы и свет. На телефонах замер",
           "**не проводился**.", ""]
    for ph, title in PHASES.items():
        out.append("## " + title)
        out.append("")
        out.append("| Показатель | " + " | ".join(names) + " |")
        out.append("|---|" + "---|" * len(names))
        for label, path in rows:
            vals = [g(r.get(ph, {}), path) for r in runs]
            fmt = ["%.0f" % v if ("пик" in label or not isinstance(v, float) or v >= 100) else "%.2f" % v for v in vals]
            out.append("| %s | %s |" % (label, " | ".join(fmt)))
        rs = [r.get(ph, {}).get("resonance_stats") for r in runs]
        if any(rs):
            out.append("")
            out.append("Резонанс за фазу: " + "; ".join("%s — реакций %s, катастроф %s, отсечено лимитом %s, перезарядкой %s" % (
                n, x.get("reactions"), x.get("catastrophes"), x.get("blocked_limit"), x.get("blocked_cd")) for n, x in zip(names, rs) if x))
        out.append("")
    with open(out_path, "w") as f:
        f.write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--levels":
        levels(sys.argv[2:])
    else:
        main()
