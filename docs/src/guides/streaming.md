

# Streaming Pre-processing API

KeemenaPreprocessing streaming pipeline lets you work with **corpora that do not fit in RAM**.  
Internally it runs in **two passes**:

1. **Vocabulary pass** - a constant-memory scan to count tokens and build the `Vocabulary`
   (skipped when you pass `vocab=`).
2. **Chunk pass** - documents are grouped into slices of *≈ `chunk_tokens`*
   and each slice becomes a `PreprocessBundle`.

Three helpers expose streaming-specific keywords and differ in how you consume
the results:

| Helper | Returns | Best when … |
| ------ | ------- | ----------- |
| `preprocess_corpus_streaming` | `Channel{PreprocessBundle}` | You want bounded prefetch plus back-pressure inside a training loop. |
| `preprocess_corpus_streaming_chunks` | `Vector{PreprocessBundle}` | You prefer materialised chunks (e.g. GPU sharding). |
| `preprocess_corpus_streaming_full` | `PreprocessBundle` | You need one big bundle but can't load the raw corpus at once. |

These helpers also support first-party subword configs via
`subword = SubwordOptions(...)`. In subword mode, the primary level is usually
`:subword` instead of `:word`.

---

## 1 - Stream through a `Channel` (more manual)

```julia
cfg = PreprocessConfiguration(tokenizer_name=:unicode,
                              record_document_offsets=true)

ch = preprocess_corpus_streaming("data/*"; cfg, chunk_tokens = 250_000)

for bund in ch                      # JIT production, O(1 chunk) RAM
    update_model!(bund)             # your training step
end
```

*The channel is **bounded** (default `channel_capacity = 1`): the producer can
stay at most one bundle ahead. Set `channel_capacity = 0` for strict
rendezvous semantics.*

---

## 2 · Collect chunks into a vector (more automatic)

```julia
bundles = preprocess_corpus_streaming_chunks("wiki_xml/*";
                                             cfg          = cfg,
                                             chunk_tokens = 250_000)

@info "produced (length(bundles)) bundles"
shuffle!(bundles)      # easy data-parallel sharding
```

Internally identical to `collect(preprocess_corpus_streaming(...))`.

---

## 3 · Merge chunks on the fly (automatic)

```julia
bundle = preprocess_corpus_streaming_full(["en.txt", "de.txt"];
                                        cfg          = cfg,
                                        chunk_tokens = 50_000)

@info "corpus length: (length(get_token_ids(bundle, :word)))"
```

If `cfg.subword !== nothing`, query `:subword` instead:
`length(get_token_ids(bundle, :subword))`.

* Merges each chunk into an accumulator in constant memory.  
* Verifies all chunks share the same `Vocabulary` and `cfg`.  
* Calls `build_ensure_alignments!` to regenerate byte/char <-> word maps when a
  `:word` level is present.

---

## Choosing `chunk_tokens`

| Corpus size | Suggested `chunk_tokens` |
|-------------|--------------------------|
| < 1 M words | 10 000 - 20 000 |
| 1-10 M words | 20 000 - 100 000 |
| > 10 M words | 100 000 + (benchmark) |

Aim for 'fits comfortably on GPU' rather than 'largest possible.'

---

## Sentinel conventions

Offset vectors follow one of two patterns:

* **`0 ... N`** - leading sentinel 0, trailing `N`
* **`1 ... N+1`** - leading 1, trailing `N+1`

The merge helper recognises both.  For any offset vector it guarantees:

```
issorted(offsets) == true
first(offsets) in (0, 1)
last(offsets)  >= n_tokens
```

---

## Common pitfalls

| Pitfall | Remedy |
|---------|--------|
| Producer stalls because channel is not consumed | Use `foreach` or collect-based helpers. |
| Mixing configs or vocabularies then concatenating by hand | Use `preprocess_corpus_streaming_full`, which throws on mismatch. |
| `subword.mode = :tokenizer_native` with custom `vocab` that is only same-size, not same id mapping | Provide the exact tokenizer-native vocabulary, or pass `vocab = nothing` and let streaming build it (accepted vocab keeps your frequencies, but mapping/special ids are normalized to tokenizer-native canonical values). |
| Chunk size too small (< 2 k tokens) | Causes task-switch overhead; start at 10 k. |
| Adding new levels with different sentinel rules | Extend the merge the helper sentinel logic and add a test. |

---

## Helper signatures (for reference)

```julia
preprocess_corpus_streaming_chunks(srcs;
    cfg           = PreprocessConfiguration(),
    vocab         = nothing,
    chunk_tokens  = DEFAULT_CHUNK_TOKENS,
    channel_capacity = 1
) -> Vector{PreprocessBundle}

preprocess_corpus_streaming_full(srcs;
    cfg           = PreprocessConfiguration(),
    vocab         = nothing,
    chunk_tokens  = DEFAULT_CHUNK_TOKENS,
    channel_capacity = 1
) -> PreprocessBundle

preprocess_corpus_streaming(srcs;
    cfg           = PreprocessConfiguration(),
    vocab         = nothing,
    chunk_tokens  = DEFAULT_CHUNK_TOKENS,
    channel_capacity = 1
) -> Channel{PreprocessBundle}
```

Only `cfg`, `vocab`, `chunk_tokens`, and `channel_capacity` are accepted
directly by the streaming entrypoints. Put
cleaning/tokenization/vocabulary options inside
`cfg = PreprocessConfiguration(...)`.


## Benchmarks (indicative)

Streaming mode is designed for bounded working memory during preprocessing by producing fixed-size
token chunks. It trades throughput for a bounded in-memory chunk bundle.

The repository contains a small reproducible benchmark script:

    julia --project bench/scalability_demo.jl


Setup:
- corpus: ~256 MiB (62 sharded text files built from 2 Project Gutenberg books)
- tokenizer_name: :whitespace
- record_sentence_offsets: true
- chunk_tokens (streaming): 250_000

| Scenario | Total tokens | Time (s) | Total allocations (MiB) | In-memory artifact size |
|---|---:|---:|---:|---:|
| preprocess_corpus (single bundle) | 43,037,600 | 41.77 | 11,457.84 | 657.28 MiB bundle |
| preprocess_corpus_streaming (consume + discard) | 43,037,600 | 79.67 | 24,381.64 | 11.25 MiB (max chunk bundle) |

Notes:
- Total allocations is cumulative allocation volume, not peak RSS.
- Bundle sizes are from Base.summarysize (approx).
- First run includes compilation; run twice to obtain steady-state timings.
