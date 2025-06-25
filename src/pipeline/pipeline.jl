

"""
    preprocess_corpus(sources; kwargs...) -> PreprocessBundle

High-level helper that takes raw text (already loaded or file-paths) and
returns a fully populated `PreprocessBundle`.  Its a convenience wrapper
around the individual steps

1 load -> 2 clean -> 3 segment & tokenise -> 4 build vocabulary  
5 vectorise -> 6 assemble bundle -> 7 (optional) save to disk

`kwargs` are automatically split into *pipeline* keywords and
*configuration* keywords:

┌─────────────┬──────────────────────────────────────────────────────────────┐
│ Pipeline    │ `save_to`, `id_type`, `offset_type`, `config`               │
│ keywords    │ (see below)                                                 │
├─────────────┼──────────────────────────────────────────────────────────────┤
│ Config      │ Every field of [`PreprocessConfiguration`] - e.g.           │
│ keywords    │ `lowercase`, `tokenizer_name`, `minimum_token_frequency`, ... │
└─────────────┴──────────────────────────────────────────────────────────────┘

    *Pass **either** a full `config = cfg` or individual configuration
    keywords, not both.*  Mixing the two throws an error so that typos never
    slip through silently.

### Arguments
`sources`  
: A `Vector{String}` *of* **either**

  * file-paths ending in `.txt` (they are read with UTF-8),
  * or in-memory document strings.

### Pipeline-level keyword arguments
`save_to`         :: `String` | `nothing`  
: If given, the resulting bundle is also persisted to that path
  via `save_preprocess_bundle`.

`id_type`         :: `Type{<:Unsigned}` (default `UInt32`)  
`offset_type`     :: `Type{<:Integer}`  (default `Int` = `Int64`/`Int32`)  
: Integer widths used for token IDs and offset tables.

`config`          :: `PreprocessConfiguration`  
: Supply a *ready* configuration object instead of per-field keywords.

### Examples
```julia
using KeemenaPreprocessing

#one-liner with defaults
bundle = preprocess_corpus("data/corpus.txt")

#tweak a few cleaning knobs via keywords
bundle = preprocess_corpus(glob("books/*.txt");
                           lowercase=false,
                           tokenizer_name=:unicode,
                           minimum_token_frequency=5)

#fit once, reuse configuration object
cfg = PreprocessConfiguration(strip_accents=false,
                              tokenizer_name=:unicode)
train = preprocess_corpus(train_files; config=cfg, save_to="train.jld2")
test  = preprocess_corpus(test_files;  config=cfg)

#returns a PreprocessBundle whose levels_present flags match the record_*_offsets fields requested in the configuration.
```
"""
function preprocess_corpus(sources; kwargs...)
    pipe_kw, cfg_kw = _split_kwargs(kwargs)

    if haskey(pipe_kw, :config) && !isempty(cfg_kw)
        error("pass either `config =...` or per-field keywords, not both")
    end

    cfg = get(pipe_kw, :config, nothing)
    cfg === nothing && (cfg = PreprocessConfiguration(; cfg_kw...))

    id_type     = get(pipe_kw, :id_type,  UInt32)
    offset_type = get(pipe_kw, :offset_type, Int)
    save_to     = get(pipe_kw, :save_to, nothing)

    # --- pipeline core (pseudo-code) ---
    docs               = _load_sources(sources)
    clean_docs         = clean_documents(docs, cfg)
    tokens, offsets    = tokenize_and_segment(clean_docs, cfg)

    vocab  = build_vocabulary(tokens; cfg = cfg, id_type = id_type)
    
    bundle = assemble_bundle(tokens, offsets, vocab, cfg;
                         offset_type = offset_type)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


const _PIPELINE_KEYS = (:save_to, :id_type, :offset_type, :config)

function _split_kwargs(kwargs::NamedTuple)
    pipeline_pairs      = Pair[]
    configuration_pairs = Pair[]
    for (k,v) in pairs(kwargs)
        if k in _PIPELINE_KEYS
            push!(pipeline_pairs, k => v)
        elseif k in fieldnames(PreprocessConfiguration) #hasfield(PreprocessConfiguration, k)
            push!(configuration_pairs, k => v)
        else
            throw(ArgumentError("Unknown keyword $(k) to preprocess_corpus"))
        end
    end
    return (NamedTuple(pipeline_pairs), NamedTuple(configuration_pairs))
end

