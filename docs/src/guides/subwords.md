# [Subwords via KeemenaPreprocessing](@id guide_subwords)

This guide covers the first-party subword path in KeemenaPreprocessing.

Phase 1 supports a native tokenizer-id flow through
`PreprocessConfiguration(subword = SubwordOptions(...))`.
In this mode, KeemenaPreprocessing delegates tokenization to KeemenaSubwords,
stores tokenizer-native ids under a level (default `:subword`), and stores
offset/mask artifacts in bundle `extras`.

---

## One-package usage

```julia
using KeemenaPreprocessing

docs = [
    "Subword tokenization helps with rare compounds and morphology.",
    "Tokenizer-native ids are preserved for downstream model compatibility.",
]

cfg = PreprocessConfiguration(
    subword = SubwordOptions(
        source = :core_bpe_en,          # model key, path, FilesSpec, NamedTuple, or tokenizer object
        mode = :native,                 # Phase 1: native ids
        level_name = :subword,          # default
        add_special_tokens = true,
        apply_tokenization_view = true,
        return_offsets = true,
        return_masks = true,
    ),
)

bundle = preprocess_corpus(docs; config = cfg)

ids      = get_token_ids(bundle, :subword)
offsets  = get_subword_offsets(bundle)
attn     = get_subword_attention_mask(bundle)
specials = get_subword_special_tokens_mask(bundle)
meta     = get_subword_metadata(bundle)
```

---

## What gets stored where

- `bundle.levels[:subword]`:
  - tokenizer-native token ids (flattened across documents),
  - vocabulary built from the tokenizer's id/token table,
  - document offsets for token slicing.
- `bundle.extras` (via accessor helpers):
  - per-document subword offsets,
  - attention masks,
  - special token masks,
  - tokenizer metadata and tokenization texts.

`get_subword_metadata(bundle).tokenization_texts` stores the tokenizer-view
text used as the offset reference (tokenizer-normalized text).

Use accessors instead of reading `extras` directly:

```julia
get_subword_offsets(bundle)
get_subword_attention_mask(bundle)
get_subword_special_tokens_mask(bundle)
get_subword_metadata(bundle)
```

---

## Source forms for `SubwordOptions(source = ...)`

`source` accepts:

- `Symbol` model key (e.g. `:core_bpe_en`)
- local path `String`
- `NamedTuple` model/file specification
- `KeemenaSubwords.FilesSpec`
- preloaded `KeemenaSubwords.AbstractSubwordTokenizer`

`format` is forwarded for path-based loading (for example
`format = :hf_tokenizer_json`).

---

## Realistic paragraph checks (recommended pattern)

For production-like validation, run pipeline parity on a multi-sentence
paragraph:

1. Clean raw docs with `clean_documents`.
2. Run `preprocess_corpus` on raw docs and cleaned docs.
3. Assert token ids and offsets match between both runs.
4. Compare each document's ids/offsets/masks against
   direct `KeemenaSubwords.encode_result(...)` output.

This is the same pattern used in package tests for long-text subword coverage
and alignment sanity.

---

## Legacy callable bridge (still supported)

If you want full manual control through a callable tokenizer adapter,
the existing path remains valid:

```julia
using KeemenaPreprocessing
using KeemenaSubwords

tok = load_tokenizer(:core_bpe_en)
cfg = PreprocessConfiguration(tokenizer_name = keemena_callable(tok))
bundle = preprocess_corpus(["hello world"]; config = cfg)
```

In this legacy callable path, the primary token stream remains under `:word`.

---

## Current Phase 1 constraints

- `SubwordOptions(mode = :native)` is supported.
- Streaming entrypoints do not yet support `subword = SubwordOptions(...)`.
  Use `preprocess_corpus` for now.
