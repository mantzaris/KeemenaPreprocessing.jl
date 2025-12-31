

# [Offset Vectors & Segmentation Levels](@id offsets_top)

Keemena stores every corpus as a **flat vector of token-ids** plus one or more  
*offset vectors* that mark the boundaries of higher-level units  
(bytes -> characters -> words -> sentences -> paragraphs -> documents).

Understanding these vectors lets you

* slice substrings for data augmentation,
* project annotations between levels,
* and validate or extend the pipeline.

---

## Anatomy of an offset vector

```
offsets = [s0, s1, ..., sn]        # length = n_tokens   or   n_tokens + 1
                                   # 1-based indices into corpus.token_ids
```

| entry | meaning |
|-------|---------|
| `s0`  | **leading sentinel** - `0` **or** `1` (optional) |
| `s1`  | inclusive *start* index of token **i**            |
| `sn`  | **trailing sentinel** - `n_tokens` **or** `n_tokens+1` (optional) |

```julia
start = offsets[i]
stop  = offsets[i+1] - 1           # inclusive index range of token i
```

> **`validate_offsets` guarantees**
> * `issorted(offsets, lt = <)`  
> * `first(offsets) in (0, 1)` (if a leading sentinel exists)  
> * `last(offsets) >= n_tokens`  
> * `length(offsets) >= n_tokens`  
>
> When sentinel recording is disabled for a level the vector length equals
> `n_tokens` and the sentinel checks are skipped.

---

## [Sentinel conventions by level](@id offsets_sentinels)

| Level symbol | Default sentinel style | Typical unit |
|--------------|-----------------------|--------------|
| `:byte`      | `[0 ... n]`             | UTF-8 byte |
| `:character` | `[0 ... n]`             | Unicode scalar |
| `:word`      | `[1 ... n+1]`           | whitespace / tokenizer word |
| `:sentence`  | `[1 ... n+1]`           | heuristic sentence |
| `:paragraph` | `[1 ... n+1]`           | blank-line span |
| `:document`  | `[1 ... n+1]`           | source document |

Trailing sentinels may be either the last token index `n_tokens`
(*inclusive style*) or `n_tokens + 1` (*exclusive style*).  
The streaming merge helper accepts both and deduplicates them, so every offset
vector in a merged bundle ends with **exactly one** sentinel.

---

## Mapping symbols -> vectors

Keemena keeps an internal lookup table

```
KeemenaPreprocessing.LEVEL_TO_OFFSETS_FIELD
```

that translates a segmentation symbol to the corresponding field name inside
`Corpus`:

| Symbol       | `Corpus` field      |
|--------------|---------------------|
| `:byte`      | `:byte_offsets`     |
| `:character` | `:character_offsets`|
| `:word`      | `:word_offsets`     |
| `:sentence`  | `:sentence_offsets` |
| `:paragraph` | `:paragraph_offsets`|
| `:document`  | `:document_offsets` |

```julia
field = KeemenaPreprocessing.LEVEL_TO_OFFSETS_FIELD[:sentence]
sent  = getfield(corpus, field)          # Vector{Int} or `nothing`
```

> **Advanced only**  
> The table is *accessible* but **not exported**; ordinary users do **not**
> modify it directly.  To register a new level use  
> `add_level!(bundle, :my_level, lb)` which both validates offsets *and*
> updates the lookup table behind the scenes.

---

## Cross-level alignment

When two levels share the same span (e.g. bytes & characters) Keemena derives a
`CrossMap`:

```julia
cm = alignment_byte_to_word(byte_corp, word_corp)
dst_word_idx = cm.alignment[src_byte_idx]     # O(1) lookup
```

`build_ensure_alignments!` automatically adds three canonical maps to every
bundle:

```
(:byte      , :character)
(:byte      , :word)
(:character , :word)
```

---

## Practical snippets

###  Extract raw text for the 42-nd word

```julia
wc   = bundle.levels[:word].corpus
span = wc.word_offsets[42] : wc.word_offsets[43] - 1
raw  = String(codeunits(bundle.extras.raw_text)[span])
```

###  Sentence lengths (words per sentence)

```julia
wc  = bundle.levels[:word].corpus
snt = wc.sentence_offsets                       # requires record_sentence_offsets=true
lengths = diff(snt)                             # Vector{Int}
```

### Shuffle paragraph spans

```julia
pc = bundle.levels[:paragraph].corpus
spans = [pc.paragraph_offsets[i] : pc.paragraph_offsets[i+1] - 1
         for i in 1:length(pc.paragraph_offsets)-1]
shuffle!(spans)
```

---

## Add a custom level (advanced workflow)

```julia
#  build monotone offset vector (leading 1, trailing n+1)
my_offs = [1, 8, 15, 22, n_tokens + 1]

#  clone an existing corpus and attach new offsets
corpus = deepcopy(bundle.levels[:word].corpus)
setfield!(corpus, :my_offsets, my_offs)

#  wrap & insert; add_level! validates and registers lookup entry
my_lvl = LevelBundle(corpus,
                     bundle.levels[:word].vocabulary)
add_level!(bundle, :my_level, my_lvl)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| *'offsets define k segments but corpus has n tokens'* | duplicate or missing trailing sentinel | regenerate offsets or let streaming merge rebuild them |
| *'Offsets must be strictly increasing'* | offsets edited out of order | sort or recreate |
| Alignment length mismatch | corpora built from different cleaned text | re-process both levels in the same pipeline |

Following these rules keeps all built-in helpers—slicing utilities, streaming
merge, alignment builders—working seamlessly and lets your custom levels
interoperate with the rest of KeemenaPreprocessing.
