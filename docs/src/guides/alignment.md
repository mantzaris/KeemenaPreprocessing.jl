

# Alignment helpers

Many downstream tasks need to **project annotations or errors between tokenisation levels**: eg "Which **word** does byte 123 belong to?".
For the sentinel and monotonicity rules that alignment assumes, see [Offsets: sentinel conventions by level](@ref offsets_sentinels).

KeemenaPreprocessing encapsulates these look-ups in a small record:

```julia
struct CrossMap
    source_level      :: Symbol   # :byte, :character, ...
    destination_level :: Symbol   # :word, ...
    alignment         :: Vector{Int}   # 1-based destination index per source
end
```

For every `source` token index `i` you obtain the corresponding
`destination` token as `map.alignment[i]`.

---

## Low-level constructors

| Function | Produces | Preconditions |
|----------|----------|---------------|
| `alignment_byte_to_word(byte_c, word_c)` | `:byte -> :word` | each corpus has `byte_offsets` / `word_offsets` and both share the same span. |
| `alignment_char_to_word(char_c, word_c)` | `:character -> :word` | ditto, but via character offsets. |
| `alignment_byte_to_char(byte_c, char_c)` | `:byte -> :character` | ditto. |

Example:

```julia
b2w = alignment_byte_to_word(byte_corpus, word_corpus)
word_of_42nd_byte = b2w.alignment[42]
```

Errors:

* `ArgumentError` if the required offset vectors are missing or
* the two corpora cover different spans
  (`byte_offsets[end] != word_offsets[end]`).

---

## Bundle-level helpers

### `_ensure_lower_levels!(bundle)`

```julia
bundle = _ensure_lower_levels!(bundle)
```

*If* the bundle has a **`:word` level** _and_ that word corpus already stores
`character_offsets` and/or `byte_offsets`, this function:

1. synthesises dummy **`:character`** / **`:byte`** corpora  
   *token-ids are filled with `<UNK>`*,
2. adds them as levels (vocabulary = 1-token dummy),
3. leaves existing levels untouched,
4. returns the *same* bundle (mutated in place).

Idempotent: calling it again is a no-op.

### `build_alignments!(bundle; pairs = [(:byte,:word), ...])`

Creates the requested `CrossMap`s **iff** the corresponding levels exist and
the map is not already present.

```julia
build_alignments!(bundle)          # default three maps
build_alignments!(bundle; pairs=[(:character,:word)])
```

### `build_ensure_alignments!(bundle)`

One-stop convenience:

```julia
build_ensure_alignments!(bundle)
```

1. Calls `_ensure_lower_levels!`,  
2. Calls `build_alignments!` with the default trio,  
3. Returns the bundle (mutated).

---

## Typical workflow

```julia
bund = preprocess_corpus("alice.txt", config = cfg)

# guarantee byte/char levels + alignments
build_ensure_alignments!(bund)

word_of_first_byte = bund.alignments[(:byte,:word)].alignment[1]
```

Inside the high-level pipelines:

* **`preprocess_corpus`** creates all three levels + alignments by default.
* **`preprocess_corpus_streaming` / `_chunks` / `_full`** call
  `build_ensure_alignments!` for every chunk (and again after merging), so the
  resulting bundles are always fully aligned.

---

## Sentinel assumptions

Offset vectors must satisfy:

```
issorted(offsets) == true
first(offsets) in (0,1)         # leading sentinel
last(offsets)  >=  n_tokens     # trailing sentinel
```

`alignment_*` functions interpret **every index in
`offsets[i] : offsets[i+1]-1`** as belonging to token `i`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ArgumentError: byte and word corpora cover different span` | Word corpus was trimmed during cleaning but byte corpus was not. | Re-run the pipeline; byte and word corpora must originate from the **same cleaned text**. |
| `KeyError` when accessing `bundle.alignments[(src,dst)]` | Map not built (levels missing or function not called). | Call `build_ensure_alignments!(bundle)` or ensure both levels exist before `build_alignments!`. |
| Dummy vocabularies contain only `<UNK>` | Expected - lower levels are placeholders used solely for alignment. |

---

### Helper signatures (for reference)

```julia
alignment_byte_to_word(byte_c::Corpus, word_c::Corpus)       -> CrossMap
alignment_char_to_word(char_c::Corpus, word_c::Corpus)       -> CrossMap
alignment_byte_to_char(byte_c::Corpus, char_c::Corpus)       -> CrossMap

_ensure_lower_levels!(bundle::PreprocessBundle)              -> PreprocessBundle
build_alignments!(bundle::PreprocessBundle; pairs = ...)     -> PreprocessBundle
build_ensure_alignments!(bundle::PreprocessBundle)           -> PreprocessBundle
```

Once you have called `build_ensure_alignments!`, every bundle is guaranteed to
contain the canonical **`:byte -> :character -> :word`** chain.

