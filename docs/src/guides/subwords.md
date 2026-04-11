# [Subwords via KeemenaPreprocessing](@id guide_subwords)

This guide explains how to use subwords from the perspective of a real
project, not only from an API surface perspective.

In plain terms, KeemenaPreprocessing lets you keep your usual corpus-cleaning
and bundling flow, while still getting modern subword tokenization via
KeemenaSubwords.

If you are deciding between multiple integration styles, start with the chooser
below and then jump to the relevant section.

`PreprocessConfiguration(subword = SubwordOptions(...))` supports two canonical
modes:

* `:tokenizer_native` - keep tokenizer-native ids.
* `:bundle_reindexed` - segment with tokenizer pieces, then rebuild ids/vocab
  inside KeemenaPreprocessing.

Compatibility aliases:

* `:native` -> `:tokenizer_native`
* `:corpus` -> `:bundle_reindexed`
* `:tokenizer` -> `:tokenizer_native`
* `:bundle` -> `:bundle_reindexed`

Both modes store subword artifacts (offsets/masks/metadata) in bundle `extras`.

---

## Which call path should you use?

Most users should start with the first row, then move to the others only if
they need more direct tokenizer control.

| User goal | Recommended call path | Why |
|---|---|---|
| I want one package for preprocessing + subwords (default user path). | `using KeemenaPreprocessing` then `preprocess_corpus(...; config = PreprocessConfiguration(subword = SubwordOptions(...)))` | Single import, corpus bundle outputs, stable accessor helpers. |
| I want integrated preprocessing but explicit tokenizer control. | `using KeemenaPreprocessing` + `using KeemenaSubwords`, then pass `SubwordOptions(source = tokenizer, ...)` | Keep bundle workflow while controlling tokenizer loading/selection directly. |
| I want full manual tokenizer workflows without bundle/vocabulary assembly. | `using KeemenaSubwords` then `load_tokenizer(...)` + `encode_result(...)` / `quick_encode_batch(...)` | Lowest-level control for model-facing tokenization pipelines. |
| I already have a callable-tokenizer integration and want to keep it unchanged. | `PreprocessConfiguration(tokenizer_name = keemena_callable(tokenizer))` | Backward-compatible legacy bridge; primary level remains `:word`. |

Mode guidance inside the first-party subword path:

* Use `mode = :tokenizer_native` for pretrained-tokenizer-compatible ids.
* Use `mode = :bundle_reindexed` when KeemenaPreprocessing should own ids/vocab.
* Use `cleaning_profile = :subword_cooperative` (aliases: `:subword_safe`,
  `:cooperative`) when you want conservative cleaning before tokenizer
  normalization.

---

## Typical user scenarios

If you are fine-tuning or evaluating a pretrained model and need tokenizer id
compatibility, use:

- `subword = SubwordOptions(..., mode = :tokenizer_native)`

You keep ids exactly as the tokenizer defines them, which makes it safer to
feed outputs into model code that expects that id space.

If you are building a corpus-specific vocabulary and want KeemenaPreprocessing
to own the id mapping, use:

- `subword = SubwordOptions(..., mode = :bundle_reindexed)`

In this mode, KeemenaSubwords still does segmentation, but the final ids and
vocabulary are rebuilt by KeemenaPreprocessing (honoring settings like
`minimum_token_frequency` and `special_tokens`).

If you need full low-level control over tokenizers (for example, standalone
batch encoding utilities without bundle assembly), use KeemenaSubwords directly.

---

## Mode choice in plain language

### `:tokenizer_native`

Choose this when your downstream stack already "speaks tokenizer-native ids".

You get:

- ids that match direct `KeemenaSubwords.encode_result(...)`,
- offsets/masks stored in bundle extras,
- easier parity checks between integrated and direct-tokenizer workflows.

### `:bundle_reindexed`

Choose this when your downstream stack should use a corpus-owned vocabulary
inside KeemenaPreprocessing.

You get:

- tokenizer-quality segmentation,
- bundle-owned vocabulary + ids,
- frequency filtering and special-token policy controlled by
  `PreprocessConfiguration`.

---

## One-package usage

```julia
using KeemenaPreprocessing

docs = [
    "Subword tokenization helps with rare compounds and morphology.",
    "Tokenizer-native ids are preserved for downstream model compatibility.",
]

cfg = PreprocessConfiguration(
    cleaning_profile = :subword_cooperative,
    subword = SubwordOptions(
        source = :core_bpe_en,          # model key, path, FilesSpec, NamedTuple, or tokenizer object
        mode = :tokenizer_native,       # keep tokenizer-native ids
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

For bundle-owned ids:

```julia
cfg = PreprocessConfiguration(
    cleaning_profile = :subword_cooperative,
    subword = SubwordOptions(
        source = :core_bpe_en,
        mode = :bundle_reindexed,   # rebuild ids/vocab inside KeemenaPreprocessing
        level_name = :subword,
    ),
    minimum_token_frequency = 2,
)
```

---

## Integrated workflow with explicit tokenizer control

Use this when you want KeemenaPreprocessing bundles, but you also want to
control tokenizer loading directly (for example pinned local files or a
preloaded tokenizer object):

```julia
using KeemenaPreprocessing
using KeemenaSubwords

tok = load_tokenizer(:core_bpe_en)

cfg = PreprocessConfiguration(
    cleaning_profile = :subword_cooperative,
    subword = SubwordOptions(
        source = tok,
        mode = :tokenizer_native,
        level_name = :subword,
    ),
)

bundle = preprocess_corpus(["A realistic paragraph goes here."]; config = cfg)
```

---

## KeemenaSubwords-only workflow (no bundle layer)

If you do not need `PreprocessBundle`, you can call KeemenaSubwords directly:

```julia
using KeemenaSubwords

tok = load_tokenizer(:core_bpe_en)
result = encode_result(tok, "Some text"; return_offsets = true, return_masks = true)
```

This path is useful when you want raw tokenizer-centric workflows without
corpus vocabulary construction.

---

## Cleaning cooperation with subwords

`cleaning_profile = :subword_cooperative` is the recommended profile for most
subword model workflows.

With `subword !== nothing`, this profile keeps the existing cleaning pipeline
but disables aggressive edits that often hurt tokenizer-native parity:

- `lowercase = false`
- `strip_accents = false`
- `remove_punctuation = false`
- `replace_urls = false`
- `replace_emails = false`
- `replace_numbers = false`

The rest of the hygiene pipeline (control-character handling, whitespace
normalization, etc.) still runs as configured.

If you want the original behavior, set `cleaning_profile = :classic`.
If cooperative cleaning is requested without `subword`, configuration falls
back to `:classic` with a warning.

---

## What gets stored where

- `bundle.levels[:subword]`:
  - token ids (tokenizer-native in `:tokenizer_native`, bundle-reindexed in
    `:bundle_reindexed`),
  - level vocabulary matching the selected mode,
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

## Current constraints

- Streaming entrypoints do not yet support `subword = SubwordOptions(...)`.
  Use `preprocess_corpus` for now.
