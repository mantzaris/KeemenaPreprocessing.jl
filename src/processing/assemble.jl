module _Assemble

using ..KeemenaPreprocessing: PreprocessConfiguration,
                               Vocabulary,
                               CorpusStorage,
                               PipelineMetadata,
                               PreprocessBundle,
                               DEFAULT_LEVELS

"""
    assemble_bundle(tokens, offsets, vocab, cfg; offset_type = Int) -> PreprocessBundle

* `tokens`        : flat `Vector{String}`
* `offsets`       : Dict returned by `tokenize_and_segment`
* `vocab`         : frozen `Vocabulary`
* `cfg`           : the same `PreprocessConfiguration`
* `offset_type`   : integer type for offset vectors (`Int` by default)


1. Map every token to its numeric ID (OOV → `<UNK>`)
2. Convert each offset vector to `Vector{offset_type}`; fabricate document
   offsets if they were not recorded
3. Build a `levels_present` map
4. Return an immutable `PreprocessBundle` (extras = `nothing` for now)
"""
function assemble_bundle(tokens::Vector{String},
                         offsets::Dict{Symbol,Vector{Int}},
                         vocab::Vocabulary{IdT},
                         cfg::PreprocessConfiguration;
                         offset_type::Type{<:Integer}=Int) where {IdT<:Unsigned}

    # 0. Ensure we have an <UNK> ID for out-of-vocabulary tokens
    unk_id = get(vocab.special_tokens, :unk, nothing)
    unk_id === nothing && throw(ArgumentError("Vocabulary lacks :unk token"))

    # 1. Token -> ID, mapping unknowns to <UNK>
    token_ids = Vector{IdT}(undef, length(tokens))
    for (i, tok) in pairs(tokens)
        token_ids[i] = get(vocab.token_to_id_map, tok, unk_id)
    end

    # 2. Offset vectors (document offsets always present)
    OffsetT     = offset_type
    convert_vec = v::Vector{Int} -> OffsetT.(v)

    doc_offs = haskey(offsets, :document) ?
                 convert_vec(offsets[:document]) :
                 OffsetT[1, length(tokens) + 1]

    par_offs = haskey(offsets, :paragraph) ? convert_vec(offsets[:paragraph]) : nothing
    sen_offs = haskey(offsets, :sentence)  ? convert_vec(offsets[:sentence])  : nothing
    char_offs= haskey(offsets, :character) ? convert_vec(offsets[:character]) : nothing
    # char_offs reserved for future support

    corpus = CorpusStorage{IdT,OffsetT}(token_ids, doc_offs, par_offs, sen_offs, char_offs)

    # 3. levels_present map
    levels = copy(DEFAULT_LEVELS)
    levels[:word]      = true
    levels[:document]  = true                # guaranteed after this layer
    levels[:paragraph] = par_offs !== nothing
    levels[:sentence]  = sen_offs !== nothing
    levels[:character] = char_offs !== nothing
    # :character remains false

    # 4. Pipeline metadata (store full configuration for provenance)
    meta = PipelineMetadata(Dict(:configuration => cfg))

    # 5. Assemble bundle (extras = nothing for v0.1)
    return PreprocessBundle(corpus, vocab, meta, nothing, levels)
end

end # module _Assemble

# Re-export for pipeline use
import ._Assemble: assemble_bundle
