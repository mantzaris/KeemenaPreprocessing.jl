
const Offset = Int

struct Vocabulary{ID<:Unsigned}
    id_to_token     :: Vector{String}
    token_to_id     :: Dict{String,ID}
    token_frequencies :: Vector{Int64}
    specials        :: Dict{Symbol,ID}
end

struct CorpusStorage{ID<:Unsigned}
    token_ids          :: Vector{ID}            # flattened
    document_offsets   :: Vector{Offset}        # len = n_docs + 1
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