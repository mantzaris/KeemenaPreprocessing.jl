
# Core Types Introduction

This page gives a practical introduction to the small set of types that underline **KeemenaPreprocessing.jl**. It is aimed at users who want to understand the data model well enough to slice, align, and feed text into downstream models without reading the entire API reference.

---

## Basic Concept

Keemena represents a corpus as a **flat vector of token identifiers** plus **offset vectors** that mark the starts of higher‑level units:

```
bytes -> characters -> words -> sentences -> paragraphs -> documents
```

Each segmentation level is packaged as a `LevelBundle` (a `Corpus` + its `Vocabulary`). A `PreprocessBundle` is the top‑level structure that stores all levels, cross‑level alignment tables, a reproducibility header, and optional user payload ('extras').

---

## `PreprocessBundle{ExtraT}`

Top‑level structure returned by `preprocess_corpus` (and the streaming variants).

**Fields**

- `levels :: Dict{Symbol,LevelBundle}` - the available segmentation levels (e.g. `:byte`, `:character`, `:word`, `:sentence`, `:paragraph`, `:document`).
- `metadata :: PipelineMetadata` - reproducibility header (configuration + on‑disk schema version).
- `alignments :: Dict{Tuple{Symbol,Symbol},CrossMap}` - cross‑level projections keyed as `(source, destination)`, eg. `(:byte, :word)`
- `extras :: ExtraT` - optional user payload (feature matrices, raw text, tags, etc.).

**Common operations**
```julia
using KeemenaPreprocessing

# Load or create a bundle
bundle = preprocess_corpus("corpus/*.txt")

# Inspect available levels
available_levels = collect(keys(bundle.levels))  # eg., [:byte, :character, :word]

# Access a level's vocabulary
word_vocabulary = bundle.levels[:word].vocabulary
println("vocabulary size: ", length(word_vocabulary.id_to_token_strings))

# Ensure canonical cross-level maps (:byte -> :character -> :word)
build_ensure_alignments!(bundle)

# Membership query: which word contains byte index i?
# (requires the canonical alignments, ensured above)
byte_index = 1
word_index_of_byte1 = bundle.alignments[(:byte, :word)].alignment[byte_index]
```

---

## `LevelBundle`

Pairing of a `Corpus` with its companion `Vocabulary` for **one** segmentation level:

**Fields**
- `corpus     :: Corpus`
- `vocabulary :: Vocabulary`

Integrity checks ensure all token identifiers in `corpus.token_ids` are valid for the vocabulary:

**Example**
```julia
word_level  = bundle.levels[:word]
word_corpus = word_level.corpus
word_vocab  = word_level.vocabulary
```

---

## `Corpus`

A compact container for all token identifiers at a level and optional offset tables that recover structure:

**Fields**
- `token_ids          :: Vector{Int}` (always present)
- `document_offsets   :: Vector{Int}` (always present)
- `paragraph_offsets  :: Union{Vector{Int},Nothing}`
- `sentence_offsets   :: Union{Vector{Int},Nothing}`
- `word_offsets       :: Union{Vector{Int},Nothing}`
- `character_offsets  :: Union{Vector{Int},Nothing}`
- `byte_offsets       :: Union{Vector{Int},Nothing}`

Each offset vector marks **start positions** (1‑based, inclusive). When present, it is sentinel‑terminated so that
`view(token_ids, offsets[i] : offsets[i+1]-1)` yields the `i`‑th unit.

### Offset invariants (what 'valid' means)

Offset vectors are monotone, begin with a leading sentinel `0` or `1`, and end with `n_tokens` or `n_tokens+1` depending on level. The streaming merge helper normalizes both styles. See **Guides -> Offsets** for the per‑level conventions and the `LEVEL_TO_OFFSETS_FIELD` lookup.

### Practical slices
```julia
# Word-level corpus
word_corpus = bundle.levels[:word].corpus

# First document as a view of token_ids
doc1_rng    = word_corpus.document_offsets[1] : word_corpus.document_offsets[2]-1
doc1_ids    = view(word_corpus.token_ids, doc1_rng)

# First sentence tokens (if recorded)
if word_corpus.sentence_offsets !== nothing
    s1 = view(word_corpus.token_ids,
              word_corpus.sentence_offsets[1] : word_corpus.sentence_offsets[2]-1)
end
```

---

## `Vocabulary`

An immutable bidirectional mapping between strings and integer token identifiers, plus frequency information and special tokens.

**Fields**
- `id_to_token_strings :: Vector{String}`
- `token_to_id_map     :: Dict{String,Int}`
- `token_frequencies   :: Vector{Int}`
- `special_tokens      :: Dict{Symbol,Int}` (e.g., `:unk`, `:pad`, `:bos`, `:eos`)

**Typical lookups**
```julia
word_vocabulary = bundle.levels[:word].vocabulary

# id -> string
first_10_strings = word_vocabulary.id_to_token_strings[1:10]

# string -> id (falls back to :unk if absent)
unknown_id  = word_vocabulary.special_tokens[:unk]
hello_id    = get(word_vocabulary.token_to_id_map, "hello", unknown_id)
```

---

## `CrossMap` (alignment between levels)

`CrossMap` is a lightweight record for level‑to‑level lookup. In practice you will encounter **membership maps** for the canonical chain

```
(:byte -> :character), (:byte -> :word), (:character -> :word)
```

this can answer *'which destination unit contains this source index?'* in O(1) lookups.

**Fields**
- `source_level      :: Symbol`
- `destination_level :: Symbol`
- `alignment         :: Vector{Int}`

### Membership maps (fine -> coarse)

The default alignments built by `build_ensure_alignments!` are **membership** maps:

```julia
build_ensure_alignments!(bundle)  # guarantees the canonical trio exists

# Byte 123 -> word index (O(1))
word_index = bundle.alignments[(:byte, :word)].alignment[123]

# Character 42 -> word index
char_to_word = bundle.alignments[(:character, :word)]
word_ix      = char_to_word.alignment[42]
```

These membership maps have `length(alignment) == n_source_tokens` (no sentinel): each fine‑grained token is labeled with its containing coarse unit.

### Range maps (coarse -> fine)

For some tasks you want the *span* of fine tokens that make up a coarse unit. You can derive those spans directly from the coarse level's offsets:

```julia
# Word-level spans of the k-th sentence:
wc          = bundle.levels[:word].corpus
k           = 1
sent_word_i = wc.sentence_offsets[k] : wc.sentence_offsets[k+1] - 1
```

(If you construct a 'range' `CrossMap` yourself, its `alignment` uses sentinel style:
`length(alignment) == n_destination + 1`, and
`alignment[i] : alignment[i+1]-1` is the source span of destination unit `i`.)

---

## Some recipes

**Words per sentence**
```julia
wc = bundle.levels[:word].corpus
sentence_lengths = diff(wc.sentence_offsets)  # requires recorded sentence offsets
```

**Per‑document token views**
```julia
wc = bundle.levels[:word].corpus
doc_offs = wc.document_offsets
doc_views = [view(wc.token_ids, doc_offs[i] : doc_offs[i+1]-1)
             for i in 1:length(doc_offs)-1]
```

**Round‑trip: word -> raw‑text span**  
(assuming the raw text is stored in `bundle.extras.raw_text`)
```julia
wc      = bundle.levels[:word].corpus
w_idx   = 42
span    = wc.word_offsets[w_idx] : wc.word_offsets[w_idx+1]-1
raw_str = String(codeunits(bundle.extras.raw_text)[span])
```

---

## Summary

- `get_corpus(bundle, :word)` - convenience accessor for level corpora (used throughout the guides).
- `get_token_ids(bundle, :word)` - direct access to the flattened id sequence for a level.
- `build_ensure_alignments!(bundle)` - guarantees the canonical membership maps exist.
- `LEVEL_TO_OFFSETS_FIELD` -> symbol -> field lookup for offset vectors (e.g., `:sentence` -> `:sentence_offsets`).



