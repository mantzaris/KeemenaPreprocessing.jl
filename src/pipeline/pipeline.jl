

const DEFAULT_CHUNK_TOKENS = 500_000


function preprocess_corpus(sources;
                            save_to::Union{Nothing,String}=nothing,
                            config::Union{Nothing,PreprocessConfiguration}=nothing,
                            kwargs...) #remaining keywords

    if config !== nothing && !isempty(kwargs)
        error("Pass either config= or per-field keywords, not both.")
    end
    
    cfg = config === nothing ? PreprocessConfiguration(; kwargs...) : config
    
    return _preprocess_core(sources, cfg; save_to)
end


function preprocess_corpus(sources, cfg::PreprocessConfiguration;
                            save_to::Union{Nothing,String} = nothing)

    return _preprocess_core(sources, cfg; save_to)
end



function _preprocess_core(sources,
                          cfg::PreprocessConfiguration;
                          save_to::Union{Nothing,String}=nothing)

    # 1 load & clean
    docs          = _load_sources(sources)
    clean_docs    = clean_documents(docs, cfg)

    # 2 tokenise & segment
    tokens,offs   = tokenize_and_segment(clean_docs, cfg)

    # 3 vocab + bundle
    vocab         = build_vocabulary(tokens; cfg=cfg)
    bundle        = assemble_bundle(tokens, offs, vocab, cfg)
    build_alignments!(bundle)

    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


function preprocess_corpus_streaming(srcs;
                                     cfg   ::PreprocessConfiguration = PreprocessConfiguration(),
                                     vocab ::Union{Nothing,Vocabulary} = nothing,
                                     chunk_tokens::Int = DEFAULT_CHUNK_TOKENS)
    
    if vocab === nothing
        freqs = _streaming_counts(srcs, cfg; chunk_tokens = chunk_tokens)  # constant-memory pass
        vocab = build_vocabulary(freqs; cfg = cfg)
    end

    raw_chunks = doc_chunk_iterator(srcs, cfg; chunk_tokens = chunk_tokens)  # Pass - streaming memory

    return Channel{PreprocessBundle}(Inf) do ch
        for docs in raw_chunks
            clean_docs        = clean_documents(docs, cfg)
            tokens, offs      = tokenize_and_segment(clean_docs, cfg)
            bundle            = assemble_bundle(tokens, offs, vocab, cfg)
            build_alignments!(bundle)
            put!(ch, bundle)
        end
    end
 end


function doc_chunk_iterator(srcs, cfg; chunk_tokens::Int = DEFAULT_CHUNK_TOKENS)
    est_tokens(doc) = count(isspace, doc) + 1

    return Channel{Vector{String}}() do ch
        buf, budget = String[], 0
        for doc in _load_sources(srcs)
            nt = est_tokens(doc)

            # if adding this doc would exceed the limit, flush first
            if budget + nt > chunk_tokens && !isempty(buf)
                put!(ch, buf)
                buf, budget = String[], 0
            end

            push!(buf, doc)
            budget += nt
        end
        !isempty(buf) && put!(ch, buf)
    end
end



"""
    _streaming_counts(srcs, cfg; chunk_tokens=DEFAULT_CHUNK_TOKENS) -> Dict{String,Int}

One pass over `srcs`, constant memory except for the Dict of token↦freq.
"""
function _streaming_counts(srcs, cfg; chunk_tokens=DEFAULT_CHUNK_TOKENS)
    freqs = Dict{String,Int}()

    for docs in doc_chunk_iterator(srcs, cfg; chunk_tokens = chunk_tokens)
        clean = clean_documents(docs, cfg)
        toks, _ = tokenize_and_segment(clean, cfg)

        for t in toks
            key = t isa UInt8 ? string(Char(t)) : String(t)
            freqs[key] = get(freqs, key, 0) + 1
        end
    end
    return freqs
end