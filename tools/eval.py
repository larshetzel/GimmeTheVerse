"""Testet die komplette Pipeline (Analyse → Kandidaten → Auswahl → Zuspruch) wie in der App.

Prompts und Beispiele werden direkt aus Sources/GimmeTheVerse/Engine.swift gelesen, damit App und Eval gleich bleiben.
Aufruf:  uv run --with numpy tools/eval.py [modell ...]
"""
import json
import pathlib
import re
import sys
import textwrap
import time
import urllib.error
import urllib.request

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "Resources"
SWIFT = (ROOT / "Sources/GimmeTheVerse/Engine.swift").read_text()

CASES = [
    "Ich habe morgen eine wichtige Prüfung und kann vor Angst nicht schlafen.",
    "Mein Vater ist vor drei Wochen gestorben und ich weiß nicht, wie ich weitermachen soll.",
    "Ich fühle mich in meiner neuen Stadt total einsam, niemand meldet sich.",
    "Ich bin so wütend auf meinen Kollegen, er hat mich vor allen bloßgestellt.",
    "Ich muss mich entscheiden, ob ich den Job wechsle, und habe Angst, das Falsche zu tun.",
    "Ich bin einfach dankbar heute, unser Kind ist gesund zur Welt gekommen.",
    "Unser Hund ist heute eingeschläfert worden. Er war 14 Jahre bei uns.",
    "Ich kann nicht mehr. Manchmal denke ich, es wäre besser, wenn ich einfach nicht mehr da wäre.",
]


def swift_block(start):
    """Inhalt eines Swift-Multiline-Strings, der nach `start` beginnt, eingerückt wie im Quelltext entfernt."""
    m = re.search(re.escape(start) + r'.*?"""\n(.*?)\n\s*"""', SWIFT, re.S)
    return textwrap.dedent(m.group(1))


def swift_example(struct):
    return re.search(r"struct " + struct + r'\b.*?static let example = #"(.*?)"#', SWIFT, re.S).group(1)


BOOKS = json.loads((RES / "books.json").read_text())
VERSES = json.loads((RES / "verses.json").read_text())
THEMES = json.loads((RES / "themes.json").read_text())
VECS = np.fromfile(RES / "embeddings.f16", dtype="<f2").astype(np.float32).reshape(len(VERSES), 768)
PRIOR = np.fromfile(RES / "prior.f32", dtype="<f4")

ANALYSE = re.sub(r"^\\\(themes\.map.*$", "\n".join(f"- {t['name']}" for t in THEMES),
                 swift_block("static func analyseSystem"), flags=re.M)
SELECT = swift_block("static let selectSystem")
COMFORT = swift_block("static func comfortSystem")
CRISIS_ADD = swift_block("if crisis {")
EX_ANALYSE, EX_PICK = swift_example("Analysis"), swift_example("Pick")


def post(path, body):
    req = urllib.request.Request("http://localhost:11434/" + path, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def chat_json(model, system, user, example):
    # wie Ollama.swift ohne Structured Outputs (gemma4 kann sie nicht; für qwen3 genügt das auch)
    system += "\n\nAntworte ausschließlich mit einem einzigen JSON-Objekt in genau dieser Form, ohne weiteren Text:\n" + example
    r = post("api/chat", {"model": model, "stream": False, "think": False, "keep_alive": "30m",
                          "options": {"temperature": 0.2, "num_ctx": 8192},
                          "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]})
    c = r["message"]["content"]
    return json.loads(c[c.index("{"):c.rindex("}") + 1])


def chat(model, system, user):
    r = post("api/chat", {"model": model, "stream": False, "think": False, "keep_alive": "30m",
                          "options": {"temperature": 0.7, "num_ctx": 8192},
                          "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]})
    return r["message"]["content"].strip()


def ref(p):
    a, b = VERSES[p[0]], VERSES[p[1]]
    base = f"{BOOKS[a[0]]} {a[1]},{a[2]}"
    return base if p[0] == p[1] else f"{base}–{b[2]}"


def text(p):
    return " ".join(VERSES[i][3] for i in range(p[0], p[1] + 1))


def preview(p, words=28):
    w = text(p).split()
    return " ".join(w) if len(w) <= words else " ".join(w[:words]) + " …"


def semantic(queries, k=45, per_query=60, w=0.01):
    q = np.asarray(post("api/embed", {"model": "embeddinggemma-2",
                                      "input": [f"task: search result | query: {x}" for x in queries]})["embeddings"],
                   np.float32)
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    fused = {}
    for col in (VECS @ q.T + w * PRIOR[:, None]).T:
        for rank, i in enumerate(np.argsort(-col)[:per_query]):
            fused[int(i)] = fused.get(int(i), 0) + 1 / (10 + rank)
    return [i for i, _ in sorted(fused.items(), key=lambda x: -x[1])[:k]]


def pool(names, sem, limit=45):
    groups = [th["passages"] for name in names for th in THEMES if th["name"] == name]
    curated, known = [], set()
    position = 0
    while True:
        added = False
        for group in groups:
            if position < len(group):
                s, e = group[position]
                if s not in known:
                    curated.append((s, e))
                    known.update(range(s, e + 1))
                    added = True
        if not added and all(position >= len(group) for group in groups):
            break
        position += 1

    out = curated[:limit // 2]
    covered = {i for s, e in out for i in range(s, e + 1)}
    for i in sem:
        if len(out) >= limit:
            break
        if i not in covered:
            out.append((i, i))
            covered.add(i)
    for s, e in curated:
        if len(out) >= limit:
            break
        if s not in covered:
            out.append((s, e))
            covered.update(range(s, e + 1))
    return out


def run(model, case):
    t0 = time.time()
    an = chat_json(model, ANALYSE, case, EX_ANALYSE)
    t1 = time.time()
    cands = pool(an["themes"][:3], semantic([case] + an["queries"][:4]), limit=32)
    listing = "\n".join(f"[{n + 1}] {ref(p)}: {preview(p)}" for n, p in enumerate(cands))
    pick = chat_json(model, SELECT, f"Anliegen:\n{case}\n\nKandidaten:\n{listing}", EX_PICK)
    chosen = list(dict.fromkeys(cands[n - 1] for n in pick["numbers"] if 1 <= n <= len(cands)))[:5]
    t2 = time.time()
    system = COMFORT + ("\n\n" + CRISIS_ADD if an["crisis"] else "")
    passages = "\n".join(f"- {ref(p)}: {text(p)}" for p in chosen)
    comfort = chat(model, system, f"Was mich bewegt:\n{case}\n\nAusgewählte Bibelstellen:\n{passages}")
    t3 = time.time()
    return an, chosen, comfort, (t1 - t0, t2 - t1, t3 - t2)


def main():
    models = sys.argv[1:] or ["gemma4:12b"]
    for case in CASES:
        print("=" * 100 + "\nANLIEGEN:", case)
        for model in models:
            an, chosen, comfort, (ta, ts, tc) = run(model, case)
            print(f"\n--- {model}  Analyse {ta:.1f}s · Auswahl {ts:.1f}s · Zuspruch {tc:.1f}s")
            print(f"    Titel {an['title']!r} · Lebenslagen {an['themes']} · Krise {an['crisis']}")
            for p in chosen:
                print(f"    {ref(p)}: {text(p)}")
            print("\n" + textwrap.fill(comfort, 100, initial_indent="    ", subsequent_indent="    "))


if __name__ == "__main__":
    main()
