

# Streaming Pre-processing

When your corpus is **larger than the RAM available on the machine** (eg 100 GB of text on a 32 GB laptop) the regular `preprocess_corpus` call will eventually OOM.  
Use the **streaming** variant instead:

```julia
preprocess_corpus_streaming(srcs;
                            cfg   = PreprocessConfiguration(),
                            vocab = nothing,
                            chunk_tokens = 500_000)  # default
      -> Channel{PreprocessBundle}
```

---  

## How it works

| Phase | What happens | Memory cost |
|-------|--------------|-------------|
| **Vocabulary pass** <br>(optional) | *If* you do **not** supply `vocab`, the function first scans the entire corpus and counts tokens. | O( \|vocab\|) - constant w.r.t. corpus size. |
| **Chunk iterator** | Documents are grouped until their *estimated* size reaches `chunk_tokens`. | Only filenames + a few counters. |
| **Per-chunk pipeline** | Each chunk is loaded, cleaned, tokenised, aligned, bundled, optionally persisted, then immediately garbage-collected. | around *40 B times chunk_tokens* (safe upper bound). |
| **Unbuffered `Channel`** | Producer waits for the consumer to `take!`, so at peak only *one* bundle and its temporaries exist in memory. | Same as above. |

 **Rule of thumb:**  : `chunk_tokens ≈ available_RAM_bytes / 40`

This comes from (UTF-8 text + token vec + offsets + metadata) approx 40 bytes per token in the worst case.

---  

## Basic recipe (32 GB RAM, 100 GB corpus)

```julia
using KeemenaPreprocessing

cfg = PreprocessConfiguration(strip_html_tags = true,
                              tokenizer_name   = :whitespace)

chunk_tokens = 250_000          # fits comfortably in <1 GB

ch = preprocess_corpus_streaming("data/wiki_dump/*";
                                 cfg          = cfg,
                                 chunk_tokens = chunk_tokens)

for bund in ch
    train_step!(bund)           # user-defined training loop
    GC.gc()                     # optional but keeps footprint flat
end
```

---

## Supplying a fixed vocabulary

When fine-tuning, you often want to **reuse** a vocabulary:

```julia
vocab = load_preprocess_bundle("baseline_vocab.jld2")
          .levels[:word].vocabulary

ch = preprocess_corpus_streaming("openwebtext/*.txt";
                                 cfg          = cfg,
                                 vocab        = vocab,
                                 chunk_tokens = 300_000)

for bund in ch
    fine_tune!(bund)
end
```

Because the counting pass is skipped, the stream begins almost instantly.

---

## Measuring memory before the full run

```julia
using BenchmarkTools

cfg = PreprocessConfiguration(tokenizer_name = :unicode)

@benchmark begin
    ch = preprocess_corpus_streaming("sample/*";
                                     cfg          = cfg,
                                     chunk_tokens = 200_000)
    take!(ch)                      # process exactly one bundle
end
```

Adjust `chunk_tokens` until the *maximum* `memory` reported by `@benchmark` is well below your physical RAM.

---

## Persisting each bundle on the fly

```julia
out_dir = "./bundles"

isdir(out_dir) || mkpath(out_dir)

i = 1
for bund in preprocess_corpus_streaming("books/*.txt";
                                        cfg          = cfg,
                                        chunk_tokens = 400_000)
    save_preprocess_bundle(bund, joinpath(out_dir, "chunk_$i.jld2"))
    i += 1
end
```

This pipeline never keeps more than one bundle **or** its JLD2 file in memory at once.

---

## Tips & gotchas

* **Disk speed matters** - SSD recommended; HDD will bottleneck large corpora.  
* **GC tuning** - If you notice memory creeping upward, insert `GC.gc()` inside the loop.  
* **Chunk too large?** - Lower `chunk_tokens` until `htop` shows stable memory.  
* **Chunk too small?** - Higher overhead; increase `chunk_tokens` to improve throughput.  
* **Offsets & `CrossMap`** - Every streamed bundle is fully aligned just like the non-streaming API, so you can concatenate corpora later without losing byte/char/word mapping information.  

---

### API recap

```julia
ch = preprocess_corpus_streaming(srcs;
                                 cfg          = PreprocessConfiguration(),
                                 vocab        = nothing,
                                 chunk_tokens = 500_000)

for bund in ch
    # bund :: PreprocessBundle (with CrossMap + offsets)
end
```

Use the streaming API whenever the corpus size x 40 B per token would exceed RAM, or when you want to pipeline data directly into a training loop without intermediate mega-bundles.

