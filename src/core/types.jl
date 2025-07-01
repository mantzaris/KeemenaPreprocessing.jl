

export Vocabulary, Corpus, LevelBundle,
       CrossMap,
       PreprocessBundle, PipelineMetadata,
       PreprocessConfiguration,
       with_extras,
       LEVEL_TO_OFFSETS_FIELD,
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
    word_offsets       :: Union{Vector{OffsetT},Nothing}
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


struct CrossMap{IdxT<:Integer}
    source_level :: Symbol       #eg :byte
    destination_level :: Symbol  #eg :word
    alignment :: Vector{IdxT}    #length = length(src_level tokens)
end


"""
    CrossMap(src_level, dst_level, alignment::Vector)

A thin wrapper for a mapping from a **source** tokenisation level to a
**destination** level.  The `alignment[i]` entry gives the index of the
destination element that *contains* source element `i`.

Use the one-shot constructor if you already have the vector:
```julia
cm = CrossMap(:byte, :word, byte_to_word_vector)
```
"""
CrossMap(src::Symbol, dst::Symbol, align::AbstractVector{<:Integer}) = CrossMap{eltype(align)}(src, dst, collect(align)) # ensures concrete Vector


struct PreprocessBundle{IdT<:Integer,OffsetT<:Integer,ExtraT}
    levels     :: Dict{Symbol,LevelBundle{IdT,OffsetT}}
    metadata   :: PipelineMetadata
    alignments :: Dict{Tuple{Symbol,Symbol},CrossMap{IdT}} #default = Dict()
    extras     :: ExtraT  #user-defined data (eg NamedTuple)
end


##############
# Constructors


const LEVEL_TO_OFFSETS_FIELD = Dict(
    :byte      => :byte_offsets,
    :character => :character_offsets,
    :word      => :word_offsets,
    :sentence  => :sentence_offsets,
    :paragraph => :paragraph_offsets,
    :document  => :document_offsets
)


function PreprocessBundle(levels::Dict{Symbol,<:LevelBundle};
                          metadata   ::PipelineMetadata = PipelineMetadata(),
                          alignments ::Dict{Tuple{Symbol,Symbol},<:CrossMap} = nothing,
                          extras                       = nothing)

    isempty(levels) && error("At least one LevelBundle is required; for an empty shell, call the zero-arg constructor.")

    # infer IdT & OffsetT from the first bundle 
    first_lb  = first(values(levels))
    IdT       = eltype(first_lb.corpus.token_ids)
    OffsetT   = eltype(first_lb.corpus.document_offsets)
    ExtrasT   = typeof(extras)

    if alignments === nothing
        alignments = Dict{Tuple{Symbol,Symbol},CrossMap{IdT}}()
    else
        alignments = Dict{Tuple{Symbol,Symbol},CrossMap{IdT}}(alignments)
    end

    # validate
    for (lvl, lb) in levels
        validate_offsets(lb.corpus, lvl)
        @assert eltype(lb.corpus.token_ids)        === IdT
        @assert eltype(lb.corpus.document_offsets) === OffsetT
    end

    # validate alignments
    for ((src, dst), cm) in alignments
        #check that both source and destination levels exist
        haskey(levels, src) || error("Alignment source level :$src not found in bundle")
        haskey(levels, dst) || error("Alignment destination level :$dst not found in bundle")
        
        #check alignment length matches source
        n_src = length(levels[src].corpus.token_ids)
        length(cm.alignment) == n_src || error("Alignment $src→$dst length $(length(cm.alignment)) doesn't match source token count $n_src")
        
        #check CrossMap metadata consistency
        cm.source_level == src || error("CrossMap source_level $(cm.source_level) doesn't match key $src")
        cm.destination_level == dst || error("CrossMap destination_level $(cm.destination_level) doesn't match key $dst")
    end

    return PreprocessBundle{IdT,OffsetT,ExtrasT}(
        Dict(levels),          # own copy
        metadata,
        Dict(alignments),      # own copy
        extras,
    )
end


function PreprocessBundle(; id_type::Type{<:Integer}=Int,
                           offset_type::Type{<:Integer}=Int,
                           metadata::PipelineMetadata = PipelineMetadata(),
                           extras = nothing)

    levels     = Dict{Symbol,LevelBundle{id_type,offset_type}}()
    alignments = Dict{Tuple{Symbol,Symbol},CrossMap{id_type}}()
    return PreprocessBundle{ id_type,
                             offset_type,
                             typeof(extras) }(levels, metadata, alignments, extras)
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


function with_extras(original::PreprocessBundle, new_extras)
    PreprocessBundle(original.levels;
                     metadata   = original.metadata,
                     alignments = original.alignments,
                     extras     = new_extras)
end


Base.iterate(bundle::PreprocessBundle) = iterate(bundle.levels)
Base.iterate(bundle::PreprocessBundle, state) = iterate(bundle.levels, state)
Base.length(bundle::PreprocessBundle) = length(bundle.levels)
Base.keys(bundle::PreprocessBundle) = keys(bundle.levels)
Base.values(bundle::PreprocessBundle) = values(bundle.levels)


Base.length(cm::CrossMap)      = length(cm.alignment)
Base.getindex(cm::CrossMap, i) = cm.alignment[i]
Base.show(io::IO, cm::CrossMap) =
    print(io, "CrossMap ", cm.source_level, "→", cm.destination_level,
               " (", length(cm), " entries)")


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

