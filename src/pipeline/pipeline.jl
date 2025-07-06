

const DEFAULT_CHUNK_TOKENS = 500_000


"""
    preprocess_corpus(sources; save_to = nothing,
                                  config = nothing,
                                  kwargs...) -> PreprocessBundle

End-to-end convenience wrapper that **loads raw texts, cleans them,
tokenises, builds a vocabulary, records offsets, and packs the result
into a [`PreprocessBundle`](@ref)**.

The routine can be invoked in **two mutually-exclusive ways**:

1. **Explicit configuration** - supply your own
   [`PreprocessConfiguration`](@ref) through the `config=` keyword.

2. **Ad-hoc keyword overrides** - omit `config` and pass any subset of the
   configuration keywords directly (e.g. `lowercase = false,
   tokenizer_name = :unicode`).  
   Internally a fresh `PreprocessConfiguration(; kwargs...)` is created
   from those overrides *plus* the documented defaults, so calling
   `preprocess_corpus(sources)` **with no keywords at all** runs the
   pipeline using the default settings.

note: Passing both `config=` **and** per-field keywords is an error because
    it would lead to ambiguous intent.

# Arguments
| name | type | description |
|------|------|-------------|
| `sources` | `AbstractString`, `Vector{<:AbstractString}`, or iterable | Either one or more **file paths/URLs** that will be read, **directories** (silently skipped), or **in-memory strings** treated as raw text. |
| `save_to` | `String` or `nothing` (default) | If a path is given the resulting bundle is serialised (JLD2) to disk *and* returned; otherwise nothing is written. |
| `config` | [`PreprocessConfiguration`](@ref) or `nothing` | Pre-constructed configuration object.  When `nothing` (default), a new one is built from `kwargs...`. |
| `kwargs...` | see [`PreprocessConfiguration`](@ref) | Per-field overrides that populate a fresh configuration when `config` is `nothing`. |

# Pipeline stages
1. **Loading** - files/URLs are fetched; directory entries are ignored.
2. **Cleaning** - controlled by the configuration's cleaning toggles.
3. **Tokenisation & segmentation** - produces token ids and offset tables.
4. **Vocabulary building** - applies `minimum_token_frequency` and inserts
   special tokens.
5. **Packaging** - returns a `PreprocessBundle`; if `save_to` was given,
   the same bundle is persisted to that path.

# Returns
A fully-populated `PreprocessBundle`.

# Examples
```julia
# 1. Quick start with defaults
bund = preprocess_corpus("corpus.txt")

# 2. Fine-grained control via keyword overrides
bund = preprocess_corpus(["doc1.txt", "doc2.txt"];
                         strip_html_tags = true,
                         tokenizer_name  = :unicode,
                         minimum_token_frequency = 3)

# 3. Supply a hand-crafted configuration object
cfg  = PreprocessConfiguration(strip_markdown = true,
                               record_sentence_offsets = false)
bund = preprocess_corpus("input/", config = cfg, save_to = "bundle.jld2")
```
"""
function preprocess_corpus(sources;
                            save_to::Union{Nothing,String}=nothing,
                            config::Union{Nothing,PreprocessConfiguration}=nothing,
                            kwargs...) #remaining keywords

    if config !== nothing && !isempty(kwargs)
        error("Pass either config= or per-field keywords, not both.")
    end
    
    cfg = config === nothing ? PreprocessConfiguration(; kwargs...) : config
    
    return _preprocess_core(sources, cfg; save_to)
end


"""
    preprocess_corpus(sources, cfg; save_to = nothing) - PreprocessBundle

Variant of [`preprocess_corpus`](@ref) that accepts an **already constructed**
[`PreprocessConfiguration`](@ref) and therefore **bypasses** all keyword
aliasing and default-override logic.

Use this when you have prepared a configuration object up-front
(e.g. loaded from disk, shared across jobs, or customised in a function)
and want to run the pipeline with those exact settings.

# Arguments
| name | type | description |
|------|------|-------------|
| `sources` | `AbstractString`, `Vector{<:AbstractString}`, iterable | One or more file paths, URLs, directories (ignored), or in-memory text strings. |
| `cfg` | `PreprocessConfiguration` | Fully-specified configuration controlling every cleaning/tokenisation option. |
| `save_to` | `String` or `nothing` (default) | If non-`nothing`, the resulting bundle is serialised (e.g. via JLD2) to the given file path **and** returned; otherwise nothing is written. |

# Pipeline (unchanged)
1. **Load** raw sources.
2. **Clean** text based on `cfg` flags.
3. **Tokenise & segment**; record requested offsets.
4. **Build vocabulary** obeying `minimum_token_frequency`, `special_tokens`, ...
5. **Pack** everything into a [`PreprocessBundle`](@ref).  Optionally persist.

# Returns
A `PreprocessBundle` populated with corpora, vocabularies, alignments,
metadata, and (by default) empty `extras`.

# Example
```julia
cfg  = PreprocessConfiguration(strip_markdown = true,
                               tokenizer_name  = :unicode)

bund = preprocess_corpus(["doc1.txt", "doc2.txt"], cfg;
                         save_to = "unicode_bundle.jld2")
```

note: If you do **not** have a configuration object yet, call the keyword-only version instead:  
    `preprocess_corpus(sources; kwargs...)` 
    which will create a default configuration and apply any overrides you provide.
"""
function preprocess_corpus(sources, cfg::PreprocessConfiguration;
                            save_to::Union{Nothing,String} = nothing)

    return _preprocess_core(sources, cfg; save_to)
end


function _preprocess_core(sources,
                          cfg::PreprocessConfiguration;
                          save_to::Union{Nothing,String}=nothing)

    # 1 load & clean
    docs          = _load_sources(sources)
    clean_docs    = clean_documents(docs, cfg)

    # 2 tokenise & segment
    tokens,offs   = tokenize_and_segment(clean_docs, cfg)

    # 3 vocab + bundle
    vocab         = build_vocabulary(tokens; cfg=cfg)
    bundle        = assemble_bundle(tokens, offs, vocab, cfg)
    build_ensure_alignments!(bundle) #build_alignments!(bundle)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


"""
    preprocess_corpus_streaming(srcs;
                                cfg           = PreprocessConfiguration(),
                                vocab         = nothing,
                                chunk_tokens  = DEFAULT_CHUNK_TOKENS) -> Channel{PreprocessBundle}

Low-memory, **two-pass** variant of [`preprocess_corpus`](@ref) that yields a
*stream* of [`PreprocessBundle`](@ref)s via a `Channel`.  
Each bundle covers *≈ `chunk_tokens`* worth of tokens, letting you pipeline
huge corpora through training code without ever loading the whole dataset into
RAM.

### Workflow
1. **Vocabulary pass** (optional)  
   *If* `vocab === nothing`, the function first computes global token-frequency
   counts in a constant-memory scan (`_streaming_counts`) and builds a
   vocabulary with `build_vocabulary(freqs; cfg)`.  
   If you already possess a fixed vocabulary (e.g. for fine-tuning), supply it
   through the `vocab` keyword to skip this pass.

2. **Chunking iterator**  
   A background task produced by `doc_chunk_iterator` groups raw source
   documents into slices whose *estimated* size does not exceed
   `chunk_tokens`.

3. **Per-chunk pipeline**  
   For every chunk the following steps mirror the standard pipeline:

   * `clean_documents`
   * `tokenize_and_segment`
   * `assemble_bundle`
   * `build_ensure_alignments!`

   The resulting bundle is `put!` onto the channel.

### Arguments
| name | type | description |
|------|------|-------------|
| `srcs` | iterable of `AbstractString` | File paths, URLs, or raw texts. |
| `cfg` | `PreprocessConfiguration` | Cleaning/tokenisation settings (default: fresh object). |
| `vocab` | `Vocabulary` or `nothing` | Pre-existing vocabulary; when `nothing` it is inferred in pass 1. |
| `chunk_tokens` | `Int` | Soft cap on tokens per chunk (default = `DEFAULT_CHUNK_TOKENS`). |

### Returns
A **channel of type `Channel{PreprocessBundle}`**.  
Consume it with `foreach`, `for bundle in ch`, or `take!(ch)`.

```julia
ch = preprocess_corpus_streaming("large_corpus/*";
                                 cfg = PreprocessConfiguration(strip_html_tags=true),
                                 chunk_tokens = 250_000)

for bund in ch                      # streaming training loop
    update_model!(bund)             # user-defined function
end
```

note: The channel is unbuffered (`Inf` capacity) so each bundle is produced only
    when the consumer is ready, minimising peak memory consumption.
"""
function preprocess_corpus_streaming(srcs;
                                     cfg   ::PreprocessConfiguration = PreprocessConfiguration(),
                                     vocab ::Union{Nothing,Vocabulary} = nothing,
                                     chunk_tokens::Int = DEFAULT_CHUNK_TOKENS)
    
    if vocab === nothing
        freqs = _streaming_counts(srcs, cfg; chunk_tokens = chunk_tokens)  # constant-memory pass
        vocab = build_vocabulary(freqs; cfg = cfg)
    end

    raw_chunks = doc_chunk_iterator(srcs, cfg; chunk_tokens = chunk_tokens)  # Pass - streaming memory

    return Channel{PreprocessBundle}(Inf) do ch
        for docs in raw_chunks
            clean_docs        = clean_documents(docs, cfg)
            tokens, offs      = tokenize_and_segment(clean_docs, cfg)
            bundle            = assemble_bundle(tokens, offs, vocab, cfg)
            build_ensure_alignments!(bundle) #build_alignments!(bundle)
            put!(ch, bundle)
        end
    end
 end


"Internal iterator used by the streaming pipeline."
function doc_chunk_iterator(srcs, cfg; chunk_tokens::Int = DEFAULT_CHUNK_TOKENS)
    est_tokens(doc) = count(isspace, doc) + 1

    return Channel{Vector{String}}() do ch
        buf, budget = String[], 0
        for doc in _load_sources(srcs)
            nt = est_tokens(doc)

            # if adding this doc would exceed the limit, flush first
            if budget + nt > chunk_tokens && !isempty(buf)
                put!(ch, buf)
                buf, budget = String[], 0
            end

            push!(buf, doc)
            budget += nt
        end
        !isempty(buf) && put!(ch, buf)
    end
end



"""
    _streaming_counts(srcs, cfg; chunk_tokens=DEFAULT_CHUNK_TOKENS) -> Dict{String,Int}

One pass over `srcs`, constant memory except for the Dict of token↦freq.
"""
function _streaming_counts(srcs, cfg; chunk_tokens=DEFAULT_CHUNK_TOKENS)
    freqs = Dict{String,Int}()

    for docs in doc_chunk_iterator(srcs, cfg; chunk_tokens = chunk_tokens)
        clean = clean_documents(docs, cfg)
        toks, _ = tokenize_and_segment(clean, cfg)

        for t in toks
            key = t isa UInt8 ? string(Char(t)) : String(t)
            freqs[key] = get(freqs, key, 0) + 1
        end
    end
    return freqs
end