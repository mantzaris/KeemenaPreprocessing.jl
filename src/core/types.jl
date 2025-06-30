

export Vocabulary, Corpus, LevelBundle,
       PreprocessBundle, PipelineMetadata,
       PreprocessConfiguration,
       with_extras, with_extras!,
       DEFAULT_LEVELS, LEVEL_TO_OFFSETS_FIELD,
       get_token_ids, get_vocabulary, get_corpus,
       get_level, has_level, add_level!,
       validate_offsets
       

struct PipelineMetadata
    configuration :: PreprocessConfiguration #cleaning and tokeniser params
    schema_version:: VersionNumber
end

PipelineMetadata() = PipelineMetadata(PreprocessConfiguration(), v"1.0.0")


struct Vocabulary{IdT<:Integer}
    id_to_token_strings  :: Vector{String}
    token_to_id_map      :: Dict{String,IdT}
    token_frequencies    :: Vector{Int64}
    special_tokens       :: Dict{Symbol,IdT}
end


struct Corpus{IdT<:Integer, OffsetT<:Integer}
    token_ids          :: Vector{IdT}
    document_offsets   :: Vector{OffsetT} # length = D+1, 1-based, sentinel end
    paragraph_offsets  :: Union{Vector{OffsetT},Nothing}
    sentence_offsets   :: Union{Vector{OffsetT},Nothing}
    character_offsets  :: Union{Vector{OffsetT},Nothing}
    byte_offsets       :: Union{Vector{OffsetT},Nothing}
end


struct LevelBundle{IdT<:Integer,OffsetT<:Integer}
    corpus     :: Corpus{IdT,OffsetT}
    vocabulary :: Vocabulary{IdT}
    
    #inner constructor for validation
    function LevelBundle(corpus::Corpus{IdT,OffsetT}, vocab::Vocabulary{IdT}) where {IdT,OffsetT}
        #validate that all token IDs in corpus are valid for the vocabulary
        max_id = maximum(corpus.token_ids; init=0)
        if max_id > length(vocab.id_to_token_strings)
            error("Corpus contains token ID $max_id but vocabulary only has $(length(vocab.id_to_token_strings)) tokens")
        end
        new{IdT,OffsetT}(corpus, vocab)
    end
end


struct PreprocessBundle{IdT<:Integer,OffsetT<:Integer,ExtraT}
    levels :: Dict{Symbol,LevelBundle{IdT,OffsetT}}
    metadata   :: PipelineMetadata
    extras :: ExtraT  #user-defined data (eg NamedTuple)
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


function PreprocessBundle(levels::Dict{Symbol,LevelBundle{IdT,OffsetT}};
                          metadata::PipelineMetadata = PipelineMetadata(),
                          extras = nothing) where {IdT,OffsetT}
    
    # Validate offset consistency for each level
    for (level_name, bundle) in levels
        validate_offsets(bundle.corpus, level_name)
    end
    
    PreprocessBundle{IdT,OffsetT,typeof(extras)}(levels, metadata, extras)
end


function PreprocessBundle(IdT::Type=Int32, OffsetT::Type=Int32;
                          metadata::PipelineMetadata = PipelineMetadata(),
                          extras = nothing)

    PreprocessBundle{IdT,OffsetT,typeof(extras)}(
        Dict{Symbol,LevelBundle{IdT,OffsetT}}(),
        metadata,
        extras
    )
end


function validate_offsets(corpus::Corpus, level_name::Symbol)
    
    field = get(LEVEL_TO_OFFSETS_FIELD, level_name, nothing)

    if field !== nothing
        offsets = getfield(corpus, field)
    
        if offsets !== nothing && offsets[end] != length(corpus.token_ids) + 1
            error("Invalid offsets for level $level_name: expected $(length(corpus.token_ids) + 1), got $(offsets[end])")
        end
    end
end


has_level(bundle::PreprocessBundle, level::Symbol) = haskey(bundle.levels, level)


function get_level(bundle::PreprocessBundle, level::Symbol)
    if !has_level(bundle, level)
        error("Level $level is not present in this bundle. Available levels: $(keys(bundle.levels))")
    end
    bundle.levels[level]
end


get_corpus(bundle::PreprocessBundle, level::Symbol) = get_level(bundle, level).corpus


get_vocabulary(bundle::PreprocessBundle, level::Symbol) = get_level(bundle, level).vocabulary


get_token_ids(bundle::PreprocessBundle, level::Symbol) = get_corpus(bundle, level).token_ids


function add_level!(bundle::PreprocessBundle{IdT,OffsetT}, 
                    level::Symbol, 
                    level_bundle::LevelBundle{IdT,OffsetT}) where {IdT,OffsetT}
    validate_offsets(level_bundle.corpus, level)
    bundle.levels[level] = level_bundle
    bundle
end


function with_extras(bundle::PreprocessBundle{IdT,OffsetT}, new_extras) where {IdT,OffsetT}
    PreprocessBundle{IdT,OffsetT,typeof(new_extras)}(
        bundle.levels,  # Shared reference
        bundle.metadata,
        new_extras
    )
end


with_extras!(bundle::PreprocessBundle, new_extras; kwargs...) = with_extras(bundle, new_extras)


Base.iterate(bundle::PreprocessBundle) = iterate(bundle.levels)
Base.iterate(bundle::PreprocessBundle, state) = iterate(bundle.levels, state)
Base.length(bundle::PreprocessBundle) = length(bundle.levels)
Base.keys(bundle::PreprocessBundle) = keys(bundle.levels)
Base.values(bundle::PreprocessBundle) = values(bundle.levels)


function Base.show(io::IO, bundle::PreprocessBundle)
    print(io, "PreprocessBundle with $(length(bundle.levels)) level(s): ")
    print(io, join(keys(bundle.levels), ", "))
end


function Base.show(io::IO, ::MIME"text/plain", bundle::PreprocessBundle)
    println(io, "PreprocessBundle:")
    println(io, "  Levels: ", join(keys(bundle.levels), ", "))
    println(io, "  Schema: ", bundle.metadata.schema_version)
    if bundle.extras !== nothing
        println(io, "  Extras: ", typeof(bundle.extras))
    end
    
    for (level, lb) in bundle.levels
        println(io, "\n  Level :$level")
        println(io, "    Tokens: ", length(lb.corpus.token_ids))
        println(io, "    Vocabulary size: ", length(lb.vocabulary.id_to_token_strings))
        println(io, "    Documents: ", length(lb.corpus.document_offsets) - 1)
    end
end

