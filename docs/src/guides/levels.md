

# Segmentation Levels inside a `PreprocessBundle`

A **`PreprocessBundle`** stores the same corpus at multiple
*segmentation levels* so that any downstream component can choose the most
convenient granularity:

```
byte  ->  character  ->  word  ->  sentence  ->  paragraph  ->  document
```

Each level is wrapped in a `LevelBundle`; all bundles live in the dictionary
`bundle.levels`.

```julia
struct PreprocessBundle{ExtraT}
    levels     :: Dict{Symbol,LevelBundle}             # the stack
    metadata   :: PipelineMetadata                     # conf + schema
    alignments :: Dict{Tuple{Symbol,Symbol},CrossMap}  # level-to-level
    extras     :: ExtraT                               # user payload
end
```

---

## Level cheat-sheet

| Level symbol | Token example | Offset vector inside `Corpus` |
|--------------|-----------------|-------------------------------|
| `:byte`      | one UTF-8 byte  | `byte_offsets`      |
| `:character` | Unicode scalar value | `character_offsets` |
| `:word`      | whitespace/unicode-split word | `word_offsets` |
| `:sentence`  | heuristic sentence span | `sentence_offsets` |
| `:paragraph` | blank-line span | `paragraph_offsets` |
| `:document`  | whole source file | `document_offsets` |

Use the lookup table **`LEVEL_TO_OFFSETS_FIELD`** to get the field name
programmatically:

```julia
field = LEVEL_TO_OFFSETS_FIELD[:sentence]   # :sentence_offsets
spans = getfield(corpus, field)
```

---

## Creating or guaranteeing levels

### Built-in pipelines

| Pipeline call | Levels you always get |
|---------------|-----------------------|
| `preprocess_corpus` | `:byte`, `:character`, `:word` (+ optional sentence/paragraph) |
| `preprocess_corpus_streaming*` | same per chunk; merge helper rebuilds alignments |

### Helper functions

```julia
_ensure_lower_levels!(bundle)      # synthesise :character / :byte if missing
build_alignments!(bundle)          # create cross-maps already available levels
build_ensure_alignments!(bundle)   # do both, idempotent
```

---

## Quick examples

### Inspect the word vocabulary

```julia
bund   = preprocess_corpus("books/*")
wvocab = bund.levels[:word].vocabulary
println("vocab size = ", length(wvocab.id_to_token_strings))
```

### Map byte 123 to its word index

```julia
build_ensure_alignments!(bund)            # guarantee maps exist
word_idx = bund.alignments[(:byte,:word)].alignment[123]
```

### Add a custom feature matrix as `extras`

```julia
feats = rand(Float32, length(get_token_ids(bund,:word)), 128)
bund  = PreprocessBundle(bund.levels;
                         metadata   = bund.metadata,
                         alignments = bund.alignments,
                         extras     = feats)
```

---

## Offset-vector convention

Every offset vector satisfies

```
issorted(vec) == true
vec[1]        ∈ (0, 1)        # leading sentinel
vec[end]      ≥ n_tokens      # trailing sentinel (n  or  n+1)
```

The streaming merge helper recognises both sentinel styles.

---

## Common pitfalls

| Pitfall | Remedy |
|---------|--------|
| Missing `:byte` / `:character` levels after custom manipulation | Call `build_ensure_alignments!(bundle)` once more. |
| Accessing an alignment that isn’t there → `KeyError` | Check `keys(bundle.alignments)` or call `build_alignments!`. |
| Offset validation failure when you inject your own `Corpus` | Run `validate_offsets(corpus, :level)` before constructing `LevelBundle`. |

---

## APIs at a glance

```julia
_ensure_lower_levels!(bundle::PreprocessBundle)          -> PreprocessBundle
build_alignments!(bundle; pairs=[...])                   -> PreprocessBundle
build_ensure_alignments!(bundle)                         -> PreprocessBundle
LEVEL_TO_OFFSETS_FIELD::Dict{Symbol,Symbol}
```

With these utilities your bundles are always **multi-level, aligned, and
self-describing**.
