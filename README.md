# GimmeTheVerse

Kleine, lokale macOS-App: Du schreibst auf, was dich bewegt, also Sorgen, Ängste, Dankbarkeit oder eine Entscheidung, und bekommst passende Bibelverse aus der **Schlachter 1951** mit einem kurzen, seelsorgerlichen Zuspruch. Alles läuft lokal über Ollama, kein Text verlässt den Mac.

<img src="docs/icon.png" width="96">

## So funktioniert es

1. **Analyse** (LLM, Standard `gemma4:12b`): ordnet dein Anliegen 1–3 von 48 kuratierten **Lebenslagen** zu (`tools/themes.json`, z. B. „Trauer um einen Menschen“ oder „Einsamkeit“). Dazu formuliert es Suchsätze, eine Überschrift und eine Krisen-Einschätzung.
2. **Kandidaten:** zuerst die bewährten Stellen dieser Lebenslagen, dann semantische Treffer aus allen 31.170 Versen. Dafür nutzt die App `embeddinggemma-2`, Reciprocal Rank Fusion über die Suchsätze und einen „Trost-Prior“, der Zusagen, Gebete und Lob leicht bevorzugt.
3. **Auswahl** (LLM): wählt 4 Stellen aus maximal 32 Kandidaten. Im Prompt stehen nur Stellenangabe und Anfang, denn der Prefill ist der Engpass.
4. **Zuspruch** (LLM, gestreamt): 3–5 Sätze in der Du-Form, warm und seelsorgerlich.

Die angezeigten Verstexte kommen **immer wortgetreu aus der Datenbank**. Das Modell wählt nur Nummern aus und erzeugt nie selbst Bibeltext.

Warum der Lebenslagen-Index? Die reine Embedding-Suche fand kaum die Verse, die ein Seelsorger nennen würde. Die Schlachter sagt „Leidtragende“ und „zürnen“, wo man heute „Trauer“ und „Wut“ schreibt. Mit dem Index enthält der Kandidatenpool die klassischen Stellen. Das Messskript dazu ist `tools/eval.py`.

Laufzeit auf einem M5 (24 GB): Die Verse stehen nach ~13 s, der Zuspruch ist nach ~20 s fertig. `gemma4:12b` kann in Ollama (MLX) keine Structured Outputs, deshalb gibt es einen JSON-Fallback in `Ollama.swift`.

Wenn das Modell oder eine Stichwortliste Hinweise auf Suizidgedanken oder Selbstverletzung erkennt, zeigt die App die Kontakte der Telefonseelsorge an, und der Zuspruch weist behutsam darauf hin.

## Voraussetzungen

- macOS 14+, Apple Silicon
- [Ollama](https://ollama.com) läuft (`brew services start ollama`)
- Modelle: `ollama pull embeddinggemma-2` und `ollama pull gemma4:12b`. Andere Chat-Modelle lassen sich unter *Einstellungen* (⌘,) wählen.

## Bauen

```sh
./build-app.sh --install     # baut build/GimmeTheVerse.app und kopiert sie nach ~/Applications
swift run                    # zum Entwickeln, liest Resources/ direkt aus dem Repo
```

Index neu bauen, z. B. nach einem Wechsel des Embedding-Modells (dauert ein paar Minuten):

```sh
uv run --with numpy tools/build_index.py
```

Pipeline testen bzw. Modelle vergleichen (liest die Prompts direkt aus `Engine.swift`):

```sh
uv run --with numpy tools/eval.py gemma4:12b qwen3:14b
```

Oberfläche ohne Bildschirmaufnahme-Rechte rendern. Das läuft durch die echte Pipeline mit einem temporären Journal und schreibt PNGs in Hell und Dunkel:

```sh
.build/debug/GimmeTheVerse --snapshot /tmp/shots "Ich habe Angst vor morgen."
```

Neue Lebenslage oder Stelle: `tools/themes.json` bearbeiten, dann `tools/build_index.py` ausführen. Das Skript bricht ab, wenn eine Stelle in der Schlachter nicht existiert. Achtung: Die Psalmen folgen der deutschen Zählung (Psalm 34,19 statt 34:18).

## Daten

- Verlauf und Lieblingsverse: `~/Library/Application Support/GimmeTheVerse/journal.json`
- Bibeltext: Schlachter 1951 über [getbible.net](https://getbible.net). Laut Quelle *„Copyrighted; Free non-commercial distribution“*, deshalb ist die App nur für den privaten, nicht-kommerziellen Gebrauch gedacht.

## Aufbau

| Datei | Inhalt |
|---|---|
| `BibleStore.swift` | Verse, Abschnitte, Lebenslagen, Embeddings und Prior; Vektorsuche (Accelerate), Kandidatenpool |
| `Ollama.swift` | Embed, Chat mit JSON (Structured Outputs oder Fallback), gestreamter Chat |
| `Engine.swift` | Pipeline, Prompts, Krisenerkennung |
| `Snapshot.swift` | `--snapshot`-Modus für Screenshots |
| `Journal.swift` | Verlauf und Favoriten, Persistenz |
| `Theme.swift` | Farben (Papier, Tinte, Ochsenblut), Typografie (New York Serif) |
| `*View.swift` | Oberfläche (eigene Seitenleiste statt NavigationSplitView, damit unter macOS 26 kein Liquid-Glass-Panel entsteht) |
