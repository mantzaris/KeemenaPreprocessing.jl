

function preprocess_corpus(sources; id_type::Type{<:Unsigned}=UInt32,
                            offset_type::Type{<:Integer}=Int,
                            save_to::Union{Nothing,String}=nothing,
                            config::Union{Nothing,PreprocessConfiguration}=nothing,
                            kwargs...) #remaining keywords

    if config !== nothing && !isempty(kwargs)
        error("Pass either config= or per-field keywords, not both.")
    end
    
    cfg = config === nothing ? PreprocessConfiguration(; kwargs...) : config
    
    return _preprocess_core(sources, cfg; id_type, offset_type, save_to)
end


function preprocess_corpus(sources, cfg::PreprocessConfiguration;
                            id_type::Type{<:Unsigned}=UInt32,
                            offset_type::Type{<:Integer}=Int,
                            save_to::Union{Nothing,String}=nothing)

    return _preprocess_core(sources, cfg; id_type, offset_type, save_to)
end


function _preprocess_core(sources,
                          cfg::PreprocessConfiguration;
                          id_type::Type{<:Unsigned}=UInt32,
                          offset_type::Type{<:Integer}=Int,
                          save_to::Union{Nothing,String}=nothing)

    # 1. load & clean
    docs          = _load_sources(sources)
    clean_docs    = clean_documents(docs, cfg)

    # 2. tokenise & segment
    tokens,offs   = tokenize_and_segment(clean_docs, cfg)

    # 3. vocab + bundle
    vocab         = build_vocabulary(tokens; cfg=cfg, id_type=id_type)
    bundle        = assemble_bundle(tokens, offs, vocab, cfg; offset_type)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end

