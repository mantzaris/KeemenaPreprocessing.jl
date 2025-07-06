

# Configuration

`PreprocessConfiguration` is a **single struct that controls every stage** of the preprocessing pipeline:

| Stage | What it governs |
|-------|-----------------|
| **Cleaning** | Unicode normalisation, punctuation stripping, URL / e-mail / number replacement, Markdown & HTML removal, emoji handling, repeated-character squeezing, confusable mapping … |
| **Tokenisation** | Choice of built-in or custom tokenizer; whether to keep zero-length tokens. |
| **Vocabulary** | Minimum token frequency cutoff; special-token mapping. |
| **Segmentation** | Which offset levels (byte, char, word, sentence, paragraph, document) should be recorded. |

A brand-new configuration with **all defaults** is just:

```julia
using KeemenaPreprocessing
cfg = PreprocessConfiguration()     # ready to go
```

---

## Keyword reference

Below is an exhaustive table of every keyword accepted by `PreprocessConfiguration(; kwargs...)`.  
Arguments are grouped by stage; omit any keyword to keep its default.

### Cleaning toggles

| keyword | default | description |
|---------|---------|-------------|
| `lowercase` | `true` | Convert letters to lower-case. |
| `strip_accents` | `true` | Remove combining accent marks. |
| `remove_control_characters` | `true` | Drop Unicode Cc / Cf code-points. |
| `remove_punctuation` | `true` | Strip punctuation & symbol characters. |
| `normalise_whitespace` | `true` | Collapse consecutive whitespace to a single space. |
| `remove_zero_width_chars` | `true` | Remove zero-width joiners, etc. |
| `preserve_newlines` | `true` | Keep explicit `\n`; needed for paragraph offsets. |
| `collapse_spaces` | `true` | Collapse runs of spaces / tabs. |
| `trim_edges` | `true` | Strip leading / trailing whitespace. |

#### URL, e-mail & number replacement

| keyword | default | purpose |
|---------|---------|---------|
| `replace_urls`            | `true`  | Replace URLs with `url_sentinel`. |
| `replace_emails`          | `true`  | Replace e-mails with `mail_sentinel`. |
| `keep_url_scheme`         | `false` | Preserve `http://` / `https://` prefix. |
| `url_sentinel`            | `"<URL>"` | Literal token replacing each URL. |
| `mail_sentinel`           | `"<EMAIL>"` | Literal token replacing each e-mail. |
| `replace_numbers`         | `false` | Replace numbers with `number_sentinel`. |
| `number_sentinel`         | `"<NUM>"` | Token used when replacing numbers. |
| `keep_number_decimal`     | `false` | Preserve decimal part. |
| `keep_number_sign`        | `false` | Preserve `+` / `-` sign. |
| `keep_number_commas`      | `false` | Preserve thousands separators. |

#### Mark-up & HTML

| keyword | default | description |
|---------|---------|-------------|
| `strip_markdown`  | `false` | Remove Markdown formatting. |
| `preserve_md_code`| `true`  | Keep fenced / inline code while stripping. |
| `strip_html_tags` | `false` | Remove HTML / XML tags. |
| `html_entity_decode` | `true` | Decode `&amp;`, `&quot;`, … |

#### Emoji & Unicode normalisation

| keyword | default | description |
|---------|---------|-------------|
| `emoji_handling` | `:keep` | `:keep`, `:remove`, or `:sentinel`. |
| `emoji_sentinel` | `"<EMOJI>"` | Used when `emoji_handling == :sentinel`. |
| `squeeze_repeat_chars` | `false` | Limit repeated characters (`sooooo → sooo`). |
| `max_char_run` | `3` | Max run length when squeezing. |
| `map_confusables` | `false` | Map visually confusable Unicode chars to ASCII. |
| `unicode_normalisation_form` | `:none` | `:NFC`, `:NFD`, `:NFKC`, `:NFKD`, or `:none`. |
| `map_unicode_punctuation` | `false` | Replace fancy punctuation with ASCII analogues. |

### Tokenisation

| keyword | default | description |
|---------|---------|-------------|
| `tokenizer_name` | `:whitespace` | One of [`TOKENIZERS`](#built-in-tokenizers) **or** a custom `f(::String)` callable. |
| `preserve_empty_tokens` | `false` | Keep zero-length tokens if the tokenizer returns them. |

### Vocabulary construction

| keyword | default | purpose |
|---------|---------|---------|
| `minimum_token_frequency` | `1` | Tokens below this frequency map to `<UNK>`. |
| `special_tokens` | `Dict(:unk=>"<UNK>", :pad=>"<PAD>")` | Role ⇒ literal token mapping. |

### Offset recording

| keyword | default | description |
|---------|---------|-------------|
| `record_byte_offsets`      | `false` | Record byte-level spans. |
| `record_character_offsets` | `false` | Record Unicode-character offsets. |
| `record_word_offsets`      | `true`  | Record word offsets. |
| `record_sentence_offsets`  | `true`  | Record sentence offsets. |
| `record_paragraph_offsets` | `false` | Record paragraph offsets (forces `preserve_newlines = true`). |
| `record_document_offsets`  | `true`  | Record document offsets. |

---

## Built-in tokenizers 

```julia
const TOKENIZERS = (:whitespace, :unicode, :byte, :char)
```

| name | behaviour | typical use |
|------|-----------|-------------|
| `:whitespace` | `split(text)` on Unicode whitespace | Most word-level corpora. |
| `:unicode` | Iterate *grapheme clusters* (`eachgrapheme`) | Languages with complex scripts, emoji, accents. |
| `:byte` | Raw UTF-8 bytes (`UInt8`) | Byte-level LLM pre-training. |
| `:char` | Individual UTF-8 code-units | Character-level models / diagnostics. |

You may pass **any callable** that returns a `Vector{<:AbstractString}`:

```julia
mytok(text) = split(lowercase(text), r"[ \-]+")

cfg = PreprocessConfiguration(tokenizer_name = mytok)
```

---

## Helper: `byte_cfg`

```julia
cfg = byte_cfg(strip_html_tags = true,
               minimum_token_frequency = 5)
```

`byte_cfg` is a thin wrapper that pre-sets  
`tokenizer_name = :byte`, `record_byte_offsets = true`, and disables char / word offsets.  
All other keywords are forwarded unchanged.

---

## Examples

### Language-agnostic, emoji-masked corpus

```julia
cfg = PreprocessConfiguration(
          strip_html_tags         = true,
          emoji_handling          = :sentinel,
          minimum_token_frequency = 3)

bund = preprocess_corpus("multilang_news/*"; config = cfg)
```

### Paragraph-level offsets for document classification

```julia
cfg = PreprocessConfiguration(
          record_paragraph_offsets = true,   # auto-enables preserve_newlines
          tokenizer_name            = :unicode)

bund = preprocess_corpus("reports/*.txt"; config = cfg)
```

### Extreme byte-level pre-training

```julia
cfg = byte_cfg(
          squeeze_repeat_chars    = true,
          max_char_run            = 5,
          minimum_token_frequency = 10)

bund = preprocess_corpus("c4_dump/*"; config = cfg, save_to = "byte_bundle.jld2")
```

---

## Notes & assertions

* `minimum_token_frequency` **must be ≥ 1**.  
* `tokenizer_name` must be one of `TOKENIZERS` **or** a callable.  
* Enabling `record_paragraph_offsets = true` automatically sets `preserve_newlines = true` (with a warning).  
* `emoji_handling` must be `:keep`, `:remove`, or `:sentinel`.  
* `unicode_normalisation_form` must be `:none`, `:NFC`, `:NFD`, `:NFKC`, or `:NFKD`.

Invalid combinations raise `AssertionError`, so mistakes fail fast during configuration construction rather than deep inside the pipeline.

---

### Return value

`PreprocessConfiguration(… )` always yields a **fully-populated, immutable struct** ready to be stored in bundle metadata or reused across jobs.

