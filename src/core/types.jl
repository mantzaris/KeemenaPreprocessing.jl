

export Vocabulary, VocabularyStore,
       CorpusStorage, PipelineMetadata,
       PreprocessBundle, 
       with_extras!,
       DEFAULT_LEVELS,
       get_token_ids, get_vocabulary, has_level


struct Vocabulary{IdT<:Integer}
    id_to_token_strings  :: Vector{String}
    token_to_id_map      :: Dict{String,IdT}
    token_frequencies    :: Vector{Int64}
    special_tokens       :: Dict{Symbol,IdT}
end


struct VocabularyStore
    vocabularies :: Dict{Symbol, Vocabulary{<:Integer}} # align with token_ids_by_level
end


struct CorpusStorage{OffsetT<:Integer}
    token_ids_by_level :: Dict{Symbol, Vector{<:Integer}}   # :word, :char, etc
    document_offsets   :: Vector{OffsetT}           # length = D+1, 1-based, sentinel end
    paragraph_offsets  :: Union{Vector{OffsetT},Nothing}
    sentence_offsets   :: Union{Vector{OffsetT},Nothing}
    character_offsets  :: Union{Vector{OffsetT},Nothing}
    byte_offsets       :: Union{Vector{OffsetT},Nothing}
end


struct PipelineMetadata
    configuration :: PreprocessConfiguration #cleaning and tokeniser params
    schema_version:: VersionNumber
end

PipelineMetadata() = PipelineMetadata(PreprocessConfiguration(), v"1.0.0")



struct PreprocessBundle{OffsetT<:Integer, ExtraT}
    corpus_storage    :: CorpusStorage{OffsetT}
    vocabulary_store  :: VocabularyStore
    pipeline_metadata :: PipelineMetadata
    extras            :: ExtraT
    levels_present    :: Dict{Symbol,Bool}
end


##############
# Constructors


const DEFAULT_LEVELS = Dict(
    :byte => false,
    :character => false, 
    :word => false, 
    :bpe => false, 
    :wordpiece => false,
    :unigram => false,
    :sentence => false, 
    :sentencepiece => false, 
    :paragraph => false, 
    :document => false
)


const LEVEL_TO_OFFSETS_FIELD = Dict(
    :byte      => :byte_offsets,
    :character => :character_offsets,
    :sentence  => :sentence_offsets,
    :paragraph => :paragraph_offsets,
    :document  => :document_offsets
)


function PreprocessBundle(corpus_storage::CorpusStorage{OffsetT},
                          vocabulary_store ::VocabularyStore;
                          pipeline_metadata = PipelineMetadata(),
                          extras            = nothing,
                          levels_present    = DEFAULT_LEVELS) where {OffsetT}

    for (lvl, ids) in corpus_storage.token_ids_by_level
        field = get(LEVEL_TO_OFFSETS_FIELD, lvl, nothing)
        if field !== nothing
            offs = getfield(corpus_storage, field)
            @assert offs === nothing || offs[end] == length(ids) + 1
        end
    end

    PreprocessBundle{OffsetT,typeof(extras)}(
        corpus_storage, vocabulary_store, pipeline_metadata, extras, copy(levels_present))
end


"""
    with_extras!(bundle, new_extras; setlevel = nothing) -> new_bundle

Return a **new** `PreprocessBundle` sharing the same corpus & vocab but carrying
`new_extras`.  If `setlevel` is provided it toggles the corresponding
`levels_present` flag to `true`.
"""
function with_extras!(bundle::PreprocessBundle{OffsetT,ExtraT},
                      new_extras;
                      setlevel::Union{Symbol,Nothing}=nothing
                      ) where {OffsetT,ExtraT}

    new_levels = copy(bundle.levels_present)
    if setlevel !== nothing
        new_levels[setlevel] = true
    end

    return PreprocessBundle{OffsetT,typeof(new_extras)}(
        bundle.corpus_storage,
        bundle.vocabulary_store,
        bundle.pipeline_metadata,
        new_extras,
        new_levels)
end


has_level(pb::PreprocessBundle, level::Symbol) =
    get(pb.levels_present, level, false)


get_token_ids(bundle::PreprocessBundle, level::Symbol) =
    get(bundle.corpus_storage.token_ids_by_level, level) do
        error("Token IDs for level $level are not stored in this bundle.")
    end


get_vocabulary(bundle::PreprocessBundle, level::Symbol) =
    get(bundle.vocabulary_store.vocabularies, level) do
        error("Vocabulary for level $level is not stored.")
    end