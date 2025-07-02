

struct PipelineMetadata
    configuration :: PreprocessConfiguration #cleaning and tokeniser params
    schema_version:: VersionNumber
end

PipelineMetadata() = PipelineMetadata(PreprocessConfiguration(), v"1.0.0")


struct Vocabulary
    id_to_token_strings :: Vector{String}
    token_to_id_map     :: Dict{String,Int}
    token_frequencies   :: Vector{Int}
    special_tokens      :: Dict{Symbol,Int}
end


struct Corpus
    token_ids          :: Vector{Int}
    document_offsets   :: Vector{Int}
    paragraph_offsets  :: Union{Vector{Int},Nothing}
    sentence_offsets   :: Union{Vector{Int},Nothing}
    word_offsets       :: Union{Vector{Int},Nothing}
    character_offsets  :: Union{Vector{Int},Nothing}
    byte_offsets       :: Union{Vector{Int},Nothing}
end


struct LevelBundle
    corpus     :: Corpus
    vocabulary :: Vocabulary
    
    #inner constructor for validation
    function LevelBundle(corp::Corpus, vocab::Vocabulary)
        if !isempty(corp.token_ids)
            max_id = maximum(corp.token_ids)
            max_id > length(vocab.id_to_token_strings) &&
                error("Corpus contains token ID $max_id but vocabulary has only $(length(vocab.id_to_token_strings)) tokens")
            minimum(corp.token_ids) < 1 &&
                error("Token IDs must be ≥ 1")
        end
        new(corp, vocab)
    end
end


struct CrossMap
    source_level      :: Symbol
    destination_level :: Symbol
    alignment         :: Vector{Int}
end


function CrossMap(src::Symbol,
                  dst::Symbol,
                  align::AbstractVector{<:Integer})

    vec = align isa Vector{Int} ? align : Vector{Int}(align) # 1 time copy and convert

    # call the automatically generated constructor for (Symbol, Symbol, Vector{Int})
    return Base.@invoke CrossMap(::Symbol, ::Symbol, ::Vector{Int})(src, dst, vec)
end


struct PreprocessBundle{ExtraT}
    levels     :: Dict{Symbol,LevelBundle}
    metadata   :: PipelineMetadata
    alignments :: Dict{Tuple{Symbol,Symbol},CrossMap}
    extras     :: ExtraT
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
                          metadata   :: PipelineMetadata = PipelineMetadata(),
                          alignments :: Dict{Tuple{Symbol,Symbol},<:CrossMap} = Dict{Tuple{Symbol,Symbol},CrossMap}(),
                          extras = nothing)

    isempty(levels) && error("At least one LevelBundle is required")

    # level-wise validation
    for (lvl, lb) in levels
        validate_offsets(lb.corpus, lvl)
    end

    # alignment validation
    for ((src,dst), cm) in alignments
        haskey(levels, src) || error("Alignment source :$src not found")
        haskey(levels, dst) || error("Alignment destination :$dst not found")
        length(cm.alignment) == length(levels[src].corpus.token_ids) ||
            error("Alignment $src→$dst length mismatch")
        cm.source_level == src || error("CrossMap source_level mismatch")
        cm.destination_level == dst || error("CrossMap destination_level mismatch")
    end

    PreprocessBundle{typeof(extras)}(
        Dict(levels), metadata, Dict(alignments), extras
    )
end


PreprocessBundle(; metadata = PipelineMetadata(), extras = nothing) =
    PreprocessBundle{typeof(extras)}(Dict(), metadata, Dict{Tuple{Symbol,Symbol},CrossMap}(), extras)


function validate_offsets(corpus::Corpus, level_name::Symbol)
    # Skip strict checks for aggregate levels that do not satisfy
    # 1-token-per-offset invariants
    level_name === :document && return

    field = get(LEVEL_TO_OFFSETS_FIELD, level_name, nothing)
    field === nothing && return                    # level has no dedicated offsets field

    offsets = getfield(corpus, field)
    offsets === nothing && return                  # offsets not recorded for this level

    expected_len = length(corpus.token_ids) + 1    # one entry per token + sentinel

    length(offsets) == expected_len ||
        error("Offsets for level $level_name must have length $expected_len, got $(length(offsets))")

    offsets[end] == expected_len ||
        error("Offsets sentinel should be $expected_len, got $(offsets[end])")

    issorted(offsets, lt = <) ||                   # strict increase
        error("Offsets for level $level_name must be strictly increasing")
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


function add_level!(bundle::PreprocessBundle, level::Symbol, lb::LevelBundle)
    haskey(bundle.levels, level) && error("Level :$level already exists")
    validate_offsets(lb.corpus, level)
    bundle.levels[level] = lb
    return bundle
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

