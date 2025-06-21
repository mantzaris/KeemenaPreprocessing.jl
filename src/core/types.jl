
const Offset = Int

struct Vocabulary{ID<:Unsigned}
    id_to_token     :: Vector{String}
    token_to_id     :: Dict{String,ID}
    token_frequencies :: Vector{Int64}
    specials        :: Dict{Symbol,ID}
end

struct CorpusStorage{ID<:Unsigned}
    token_ids          :: Vector{ID} 
    document_offsets   :: Vector{Offset}
    sentence_offsets   :: Union{Vector{Offset},Nothing}
    paragraph_offsets  :: Union{Vector{Offset},Nothing}
end

struct PipelineMetadata
    configuration :: Dict{Symbol,Any} #cleaning and tokeniser params
    # any extras
end

struct ExtraArrays
    token_length :: Union{Vector{UInt16},Nothing}
    ngram_hash   :: Union{Vector{UInt64},Nothing}
end

struct PreprocessBundle{ID<:Unsigned}
    corpus    :: CorpusStorage{ID}
    vocabulary:: Vocabulary{ID}
    metadata  :: PipelineMetadata
    extras    :: Union{ExtraArrays,Nothing}
    levels    :: Dict{Symbol,Bool}
end



##############
# Constructors

const DEFAULT_LEVELS = Dict(
    :character => false, :word => false, :sentence => false,
    :paragraph => false, :document => false)

function PreprocessBundle(corpus::CorpusStorage{ID},
                          vocab :: Vocabulary{ID};
                          metadata = PipelineMetadata(Dict()),
                          extras   = nothing,
                          levels   = DEFAULT_LEVELS) where {ID}

    @assert corpus.document_offsets[end] == length(corpus.token_ids) + 1

    if corpus.sentence_offsets !== nothing
        @assert corpus.sentence_offsets[end] == length(corpus.token_ids) + 1
    end

    if corpus.paragraph_offsets !== nothing
        @assert corpus.paragraph_offsets[end] == length(corpus.token_ids) + 1
    end

    PreprocessBundle{ID}(corpus, vocab, metadata, extras, copy(levels))
end

haslevel(pb::PreprocessBundle, lvl::Symbol) =
    get(pb.levels, lvl, false)