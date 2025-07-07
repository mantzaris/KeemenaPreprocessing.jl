

# KeemenaPreprocessing.jl

KeemenaPreprocessing is a lightweight, **fully streaming** text-processing
pipeline for Julia.  It converts raw text into a compact, serialisable bundle
containing

* cleaned documents
* flattened token sequences (byte, char, word or custom)
* start-index offsets for sentences, paragraphs and documents
* a deterministic vocabulary with user-defined special tokens
* auxiliary metadata for downstream models

Memory usage stays predictable—even on huge corpora—because every stage can
run incrementally in fixed-size chunks.

---

## Key features

| Stage | Purpose |
|-------|---------|
| **Cleaning** | Lower-cases, strips accents, removes control characters, collapses whitespace and can replace URLs, e-mails or numbers with sentinel tokens. |
| **Tokenisation** | Built-in byte, Unicode-word, whitespace and character tokenisers plus a hook for your own function. |
| **Segmentation** | Optional paragraph and sentence splitters driven by regex. |
| **Vocabulary** | Frequency filtering, minimum counts, user-defined special tokens. |
| **Streaming mode** | Process arbitrarily large corpora via channels so nothing ever has to fit entirely in RAM. |
| **Bundles** | Pack everything into a single JLD2 file with `save_preprocess_bundle`. |

All stages are driven by one `PreprocessConfiguration` object, so the same
code works for quick prototypes and full production pipelines.

---

## Quick start

A **single call** runs the entire pipeline—load, clean, tokenise, build a
vocabulary, assemble offsets, pack a bundle, and optionally save to disk:

```julia
using KeemenaPreprocessing

bundle = preprocess_corpus("corpus/*.txt";
                           tokenizer_name = :unicode,            # override defaults
                           record_sentence_offsets = true,
                           minimum_token_frequency = 3,
                           save_to = "my_bundle.jld2")           # optional persistence
```

Prefer a pre-built configuration object? Pass it through `config =`:

```julia
cfg    = PreprocessConfiguration(tokenizer_name = :byte,
                                 record_byte_offsets = true)

bundle = preprocess_corpus("data/raw.txt"; config = cfg)
```

---

## Documentation map

* **Configuration** : every option in `PreprocessConfiguration`
* **Cleaning** : rules, sentinel tokens, customisation
* **Tokenisation** : built-in tokenisers and extensibility
* **Vocabulary** : frequency thresholds, specials, determinism
* **Streaming** : channels, chunk sizes, memory planning
* **Saving & loading** : JLD2 helpers for long-running jobs



*  See the [Guides](guides/quickstart.md) for worked examples  
*  Full API in the [reference](api/index.md)
