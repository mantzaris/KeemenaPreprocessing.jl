

module _Assemble


using ..KeemenaPreprocessing:  PreprocessConfiguration,
                               Vocabulary, Corpus, LevelBundle,
                               PipelineMetadata, PreprocessBundle


"""
    assemble_bundle(tokens, offsets, vocab, cfg) -> PreprocessBundle

Convert the **token-level artefacts** produced by
`tokenize_and_segment` into a minimal yet fully valid
`PreprocessBundle`.  The function

1. Projects each token to its **integer id** using `vocab`; unknown strings are
   mapped to the `:unk` special (throws if the vocabulary lacks one).
2. Packs the id sequence together with the requested offset tables into a
   `Corpus`.
3. Wraps that corpus and its vocabulary in a `LevelBundle` whose key is
   inferred from `cfg.tokenizer_name`:

   | `tokenizer_name` value | level symbol stored |
   |------------------------|---------------------|
   | `:byte`                | `:byte`             |
   | `:char`                | `:character`        |
   | `:unicode`, `:whitespace` | `:word`        |
   | `Function`             | `Symbol(typeof(fn))`|
   | any other `Symbol`     | same symbol         |

4. Builds a default `PipelineMetadata` header
   (`PipelineMetadata(cfg, v"1.0.0")`).
5. Returns a `PreprocessBundle` containing *exactly one* level, empty
   `alignments`, and `extras = nothing`.

### Arguments
| name | type | description |
|------|------|-------------|
| `tokens`  | `Vector{<:Union{String,UInt8}}` | Flattened token stream. |
| `offsets` | `Dict{Symbol,Vector{Int}}` | Start indices for each recorded level (as returned by `tokenize_and_segment`). |
| `vocab`   | `Vocabulary` | Token <-> id mapping (must contain `:unk`). |
| `cfg`     | `PreprocessConfiguration` | Determines the level key and special-token requirements. |

### Returns
`PreprocessBundle` with

```julia
bundle.levels       == Dict(level_key => LevelBundle(corpus, vocab))
bundle.metadata     == PipelineMetadata(cfg, v"1.0.0")
bundle.alignments   == Dict{Tuple{Symbol,Symbol},CrossMap}()   # empty
bundle.extras       == nothing
```

### Errors
* Throws `ArgumentError` if `vocab` lacks the `:unk` special.
* Propagates any error raised by the inner constructors of `Corpus` or
  `LevelBundle` (e.g. offset inconsistencies).

### Example
```julia
tokens, offs = tokenize_and_segment(docs, cfg)
vocab         = build_vocabulary(tokens; cfg = cfg)
bund          = assemble_bundle(tokens, offs, vocab, cfg)

@info keys(bund.levels)  # (:word,) for whitespace tokenizer
```
"""
function assemble_bundle(tokens::AbstractVector,
                         offsets::Dict{Symbol,Vector{Int}},
                         vocab::Vocabulary,
                         cfg::PreprocessConfiguration)

    level = cfg.tokenizer_name === :byte       ? :byte  :
            cfg.tokenizer_name === :char       ? :character  :
            cfg.tokenizer_name === :unicode    ? :word  :      # unicode tokenizer -> words
            cfg.tokenizer_name === :whitespace ? :word  :
            isa(cfg.tokenizer_name, Function)  ? Symbol(typeof(cfg.tokenizer_name))  :
            cfg.tokenizer_name isa Symbol      ? cfg.tokenizer_name  :
            :word

    # 0 Ensure we have an <UNK> ID for out-of-vocabulary tokens
    unk_id = get(vocab.special_tokens, :unk, nothing)
    unk_id === nothing && throw(ArgumentError("Vocabulary lacks :unk token"))

    # 1 Token -> ID, mapping unknowns to <UNK>
    token_ids = Vector{Int}(undef, length(tokens))
    for (i, tok) in pairs(tokens)
        tok_str = tok isa UInt8 ? string(Char(tok)) : string(tok)
        token_ids[i] = get(vocab.token_to_id_map, tok_str, unk_id)
    end

    # 2 Offset vectors (document offsets always present)
    convert_vec(v::Vector{Int}) = v

    doc_offs  = haskey(offsets, :document)  ? convert_vec(offsets[:document])  :
                                             Int[1, length(tokens)+1]
    par_offs  = haskey(offsets, :paragraph) ? convert_vec(offsets[:paragraph]) : nothing
    sen_offs  = haskey(offsets, :sentence)  ? convert_vec(offsets[:sentence])  : nothing
    word_offs = haskey(offsets, :word)      ? convert_vec(offsets[:word])      : nothing
    char_offs = haskey(offsets, :character) ? convert_vec(offsets[:character]) : nothing
    byte_offs = haskey(offsets, :byte)      ? convert_vec(offsets[:byte])      : nothing

    corpus = Corpus(token_ids, doc_offs, par_offs,
                                 sen_offs, word_offs, char_offs, byte_offs)

    lb     = LevelBundle(corpus, vocab)
    lvls   = Dict(level => lb)                 # present levels only

    meta = PipelineMetadata(cfg, v"1.0.0")

    return PreprocessBundle(lvls; metadata = meta, extras = nothing)

end


end # module _Assemble


# Re-export for pipeline use
import ._Assemble: assemble_bundle
