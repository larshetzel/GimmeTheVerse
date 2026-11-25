# GimmeTheVerse

<img src="docs/icon.png" width="96">

A private macOS app that connects what is on your mind with relevant Bible verses and a short, pastoral encouragement. Write about anxiety, grief, gratitude, or a decision, then continue the conversation. Everything runs locally through Google Gemma 4 —no account, no cloud processing.

## Highlights
- 48 curated life situations combined with semantic search across 31,170 verses
- Verse text always comes directly from the local database, never from the language model
- Conversation history and favorite verses stored only on your Mac
- Crisis detection with contact information for Telefonseelsorge and emergency services

## Models
| Purpose | Default model |
|---|---|
| Analysis, verse selection, encouragement, and chat | `gemma4:12b` |
| Semantic verse embeddings | `embeddinggemma-2` |

Other Ollama chat models can be selected in **Settings (⌘,)**. On an M5 with 24 GB RAM, verses typically appear after about 13 seconds and the encouragement after about 20 seconds.

## How it works

1. `gemma4:12b` identifies up to three life situations and creates search queries.
2. The candidate pool combines curated passages and semantic results in equal parts. `embeddinggemma-2`, Reciprocal Rank Fusion, and a comfort-oriented prior rank the verses.
3. The model selects four passages from 32 candidates using their references and first 28 words.
4. It streams a short encouragement based on the selected verses. Follow-up messages can reference additional passages using markers such as `[[Psalm 23,4]]`.

## Requirements and build

- macOS 14+ on Apple Silicon
- [Ollama](https://ollama.com)

```sh
brew services start ollama
ollama pull gemma4:12b
ollama pull embeddinggemma-2
./build-app.sh --install
```

For development, use `swift run`. The app reads resources directly from `Resources/`.

## Development tools

```sh
# Rebuild themes and embeddings
uv run --with numpy tools/build_index.py

# Evaluate the full pipeline with one or more chat models
uv run --with numpy tools/eval.py gemma4:12b qwen3:14b

# Render real app screenshots with a temporary journal
.build/debug/GimmeTheVerse --snapshot /tmp/shots "Ich habe Angst vor morgen."
```

Edit `tools/themes.json` to add a life situation or curated passage, then rebuild the index. Psalm references use German numbering.

## Optional Hoffnung für alle import

Place a separately licensed file in getBible format at `tools/hoffnung-fuer-alle.json`, then run `tools/build_index.py`. The source and generated resources are excluded from Git. Missing individual verses fall back to Schlachter 1951. After rebuilding and installing, select the translation in **Settings**; both display and semantic search will use it.

Hoffnung für alle is copyrighted and is not included in this repository. Do not distribute it without permission.

## Local data

Journal and favorites: `~/Library/Application Support/GimmeTheVerse/journal.json`

Schlachter 1951 text comes from [getBible.net](https://getbible.net). Its source states “Copyrighted; Free non-commercial distribution”; the app is therefore intended for private, non-commercial use.

## Contributing

Issues, feedback, and pull requests are welcome—especially for SwiftUI, UX, retrieval quality, testing, accessibility, and pastoral sensitivity.
