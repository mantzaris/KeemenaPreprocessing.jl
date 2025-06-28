

export Vocabulary, CorpusStorage, PipelineMetadata,
       PreprocessBundle, haslevel, with_extras!,
       DEFAULT_LEVELS


struct Vocabulary{IdT<:Unsigned}
    id_to_token_strings  :: Vector{String}
    token_to_id_map      :: Dict{String,IdT}
    token_frequencies    :: Vector{Int64}
    special_tokens       :: Dict{Symbol,IdT}
end


struct CorpusStorage{IdT<:Unsigned, OffsetT<:Integer}
    token_ids         :: Vector{IdT}          # flat corpus
    document_offsets  :: Vector{OffsetT}           # length = D+1, 1-based, sentinel end
    paragraph_offsets :: Union{Vector{OffsetT},Nothing}
    sentence_offsets  :: Union{Vector{OffsetT},Nothing}
    character_offsets  :: Union{Vector{OffsetT},Nothing}
end


struct PipelineMetadata
    configuration :: Dict{Symbol,Any} #cleaning and tokeniser params
end
PipelineMetadata() = PipelineMetadata(Dict{Symbol,Any}())



"""
`PreprocessBundle{IdT,OffsetT,ExtraT}`

  * `IdT`    : unsigned integer type for token ids (e.g. `UInt32`)
  * `OffsetT`   : integer type for offsets  (e.g. `Int` or `UInt32`)
  * `ExtraT` : payload supplied by downstream packages (`Nothing` by default)
"""
struct PreprocessBundle{IdT<:Unsigned, OffsetT<:Integer, ExtraT}
    corpus_storage    :: CorpusStorage{IdT,OffsetT}
    vocabulary        :: Vocabulary{IdT}
    pipeline_metadata :: PipelineMetadata
    extras            :: ExtraT
    levels_present    :: Dict{Symbol,Bool}
end


##############
# Constructors


const DEFAULT_LEVELS = Dict(
    :character => false, :word => false, :sentence => false,
    :paragraph => false, :document => false)

    
function PreprocessBundle(corpus_storage::CorpusStorage{IdT,OffsetT},
                          vocabulary ::Vocabulary{IdT};
                          pipeline_metadata = PipelineMetadata(),
                          extras            = nothing,
                          levels_present    = DEFAULT_LEVELS) where {IdT,OffsetT}

    N = length(corpus_storage.token_ids)
    @assert corpus_storage.document_offsets[end] == N + 1
    if corpus_storage.sentence_offsets !== nothing
        @assert corpus_storage.sentence_offsets[end] == N + 1
    end
    if corpus_storage.paragraph_offsets !== nothing
        @assert corpus_storage.paragraph_offsets[end] == N + 1
    end

    PreprocessBundle{IdT,OffsetT,typeof(extras)}(
        corpus_storage, vocabulary, pipeline_metadata, extras, copy(levels_present))
end


"""
    with_extras!(bundle, new_extras; setlevel = nothing) -> new_bundle

Return a **new** `PreprocessBundle` sharing the same corpus & vocab but carrying
`new_extras`.  If `setlevel` is provided it toggles the corresponding
`levels_present` flag to `true`.
"""
function with_extras!(bundle::PreprocessBundle{IdT,OffsetT},
                      new_extras;
                      setlevel::Union{Symbol,Nothing}=nothing
                      ) where {IdT,OffsetT}

    new_levels = copy(bundle.levels_present)
    if setlevel !== nothing
        new_levels[setlevel] = true
    end

    return PreprocessBundle{IdT,OffsetT,typeof(new_extras)}(
        bundle.corpus_storage,
        bundle.vocabulary,
        bundle.pipeline_metadata,
        new_extras,
        new_levels)
end

haslevel(pb::PreprocessBundle, level::Symbol) =
    get(pb.levels_present, level, false)