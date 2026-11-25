"""Baut den Index für GimmeTheVerse.

Liest tools/schlachter.json (Schlachter 1951, getbible.net) und tools/themes.json (kuratierte Lebenslagen), schreibt:
  Resources/verses.json      – [[buchIndex, kapitel, vers, text], ...]
  Resources/books.json       – deutsche Buchnamen (66)
  Resources/embeddings.f16   – N x 768 float16, L2-normalisiert, Zeilenreihenfolge = verses.json
  Resources/prior.f32        – N float32: wie sehr ein Vers nach Zusage/Trost/Gebet/Lob klingt (z-normalisiert)
  Resources/themes.json      – [{"name", "passages": [[start, end], ...]}] mit Vers-Indizes

Die Embeddings werden nur neu berechnet, wenn sie fehlen oder --reembed angegeben ist (~10 min).
Aufruf:  uv run --with numpy tools/build_index.py [--reembed]
"""
import json
import pathlib
import re
import sys
import time
import urllib.request

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "schlachter.json"
THEMES = ROOT / "tools" / "themes.json"
OUT = ROOT / "Resources"
OLLAMA = "http://localhost:11434/api/embed"
MODEL = "embeddinggemma-2"
BATCH = 64

BOOKS_DE = [
    "1. Mose", "2. Mose", "3. Mose", "4. Mose", "5. Mose", "Josua", "Richter", "Ruth",
    "1. Samuel", "2. Samuel", "1. Könige", "2. Könige", "1. Chronik", "2. Chronik",
    "Esra", "Nehemia", "Esther", "Hiob", "Psalm", "Sprüche", "Prediger", "Hohelied",
    "Jesaja", "Jeremia", "Klagelieder", "Hesekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadja", "Jona", "Micha", "Nahum", "Habakuk", "Zephanja", "Haggai", "Sacharja",
    "Maleachi", "Matthäus", "Markus", "Lukas", "Johannes", "Apostelgeschichte", "Römer",
    "1. Korinther", "2. Korinther", "Galater", "Epheser", "Philipper", "Kolosser",
    "1. Thessalonicher", "2. Thessalonicher", "1. Timotheus", "2. Timotheus", "Titus",
    "Philemon", "Hebräer", "Jakobus", "1. Petrus", "2. Petrus", "1. Johannes",
    "2. Johannes", "3. Johannes", "Judas", "Offenbarung",
]

# Anker für den Prior: Verse, die einem Menschen direkt etwas zusprechen, statt Erzählung oder Gesetz.
PRIOR_ANCHORS = [
    "Gott spricht Trost und Ermutigung zu: Fürchte dich nicht, ich bin bei dir.",
    "Eine Verheißung Gottes von Hoffnung, Frieden, Hilfe und Bewahrung.",
    "Ein Gebet in Not, Klage und Vertrauen auf Gott.",
    "Lob und Dank an Gott für seine Güte und Treue.",
    "Weisheit und Rat für das tägliche Leben.",
    "Gottes Liebe, Gnade und Vergebung für den Menschen.",
]


def clean(text: str) -> str:
    return " ".join(text.replace("`", "’").split())


def embed(inputs):
    body = json.dumps({"model": MODEL, "input": inputs}).encode()
    req = urllib.request.Request(OLLAMA, body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        v = np.asarray(json.load(r)["embeddings"], dtype=np.float32)
    return v / np.linalg.norm(v, axis=1, keepdims=True)


def load_verses():
    if not SRC.exists():
        print("Lade Schlachter 1951 von getbible.net …", file=sys.stderr)
        urllib.request.urlretrieve("https://api.getbible.net/v2/schlachter.json", SRC)
    data = json.loads(SRC.read_text())
    assert len(data["books"]) == 66
    verses = []
    for bi, book in enumerate(data["books"]):
        for ch in book["chapters"]:
            for v in ch["verses"]:
                verses.append([bi, ch["chapter"], v["verse"], clean(v["text"])])
    return verses


def build_embeddings(verses, force):
    path = OUT / "embeddings.f16"
    if path.exists() and not force and path.stat().st_size == len(verses) * 768 * 2:
        return np.fromfile(path, dtype="<f2").astype(np.float32).reshape(len(verses), 768)
    docs = [f"title: {BOOKS_DE[b]} {c},{v} | text: {t}" for b, c, v, t in verses]
    vecs = np.zeros((len(docs), 768), dtype=np.float32)
    t0 = time.time()
    for i in range(0, len(docs), BATCH):
        vecs[i:i + BATCH] = embed(docs[i:i + BATCH])
        done = min(i + BATCH, len(docs))
        rate = done / (time.time() - t0)
        print(f"\r{done}/{len(docs)}  ~{(len(docs) - done) / rate:.0f}s übrig", end="", file=sys.stderr)
    print(file=sys.stderr)
    vecs.astype("<f2").tofile(path)
    return vecs


def build_prior(vecs):
    anchors = embed([f"task: search result | query: {a}" for a in PRIOR_ANCHORS])
    prior = (vecs @ anchors.T).max(1)
    prior = (prior - prior.mean()) / prior.std()
    prior.astype("<f4").tofile(OUT / "prior.f32")


def build_themes(verses):
    index = {(b, c, v): i for i, (b, c, v, _) in enumerate(verses)}
    out = []
    for th in json.loads(THEMES.read_text()):
        passages = []
        for ref in th["verses"]:
            m = re.fullmatch(r"(.+) (\d+),(\d+)(?:-(\d+))?", ref)
            if not m or m.group(1) not in BOOKS_DE:
                sys.exit(f"Ungültige Stelle in themes.json: {ref}")
            b, c, v1 = BOOKS_DE.index(m.group(1)), int(m.group(2)), int(m.group(3))
            v2 = int(m.group(4) or v1)
            if (b, c, v1) not in index or (b, c, v2) not in index:
                sys.exit(f"Stelle nicht in der Schlachter gefunden: {ref}")
            passages.append([index[(b, c, v1)], index[(b, c, v2)]])
        out.append({"name": th["theme"], "passages": passages})
    (OUT / "themes.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    return out


def main():
    OUT.mkdir(exist_ok=True)
    verses = load_verses()
    (OUT / "books.json").write_text(json.dumps(BOOKS_DE, ensure_ascii=False))
    (OUT / "verses.json").write_text(json.dumps(verses, ensure_ascii=False, separators=(",", ":")))
    vecs = build_embeddings(verses, force="--reembed" in sys.argv)
    build_prior(vecs)
    themes = build_themes(verses)
    print(f"{len(verses)} Verse, {len(themes)} Lebenslagen, {sum(len(t['passages']) for t in themes)} Stellen")


if __name__ == "__main__":
    main()
