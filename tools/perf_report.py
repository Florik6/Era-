#!/usr/bin/env python3
"""Builds docs/perf/city_bench.md from the city benchmark JSON files.

Usage: tools/perf_report.py docs/perf/city_bench_before.json docs/perf/city_bench_after.json [docs/perf/city_bench_after_dcq.json]
"""
import json
import sys

PHASES = {"empty": "Пустой город", "walk": "Прогулка по городу", "npcs": "Появились 24 NPC", "battle": "Массовая битва",
          "magic": "Обмен магией", "explosion": "Крупные взрывы (ультимейты)"}


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


if __name__ == "__main__":
    main()
