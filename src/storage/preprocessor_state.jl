

module _PreprocessorState


using ..KeemenaPreprocessing:
        PreprocessBundle, Vocabulary, PreprocessConfiguration,
        preprocess_corpus, assemble_bundle,
        _load_sources, clean_documents, tokenize_and_segment,
        save_preprocess_bundle,
        get_vocabulary


"""
    Preprocessor(cfg, vocab)

Frozen state: the exact cleaning/tokenisation rules *and* the fixed
token-to-ID map.  Parameterised on `IdT` to keep ID width.

Note: passing a bundle keeps its large arrays in RAM; for big corpora prefer the Preprocessor signature
"""
struct Preprocessor{CfgT<:PreprocessConfiguration,IdT<:Integer}
    cfg        :: CfgT
    vocabulary :: Vocabulary{IdT}
end


# build_preprocessor
"""
    build_preprocessor(train_sources; kwargs...) -> (Preprocessor, train_bundle)

Runs the full pipeline on `train_sources`, building the vocabulary once
Keyword arguments are forwarded exactly like in `preprocess_corpus`
"""
function build_preprocessor(sources; kwargs...)
    train_bundle = preprocess_corpus(sources; kwargs...)
    cfg = train_bundle.metadata.configuration 
    vocab = get_vocabulary(train_bundle, :word)
    
    return Preprocessor(cfg, vocab), train_bundle
end


"""
    encode_corpus(prep, new_sources;
                                offset_type = Int, save_to = nothing)
            -> PreprocessBundle

Re-runs cleaning + tokenisation on `new_sources` without rebuilding the
vocabulary.  OOV tokens map to the stored `<UNK>` ID.
"""
function encode_corpus(prep::Preprocessor, sources;
                       offset_type::Type{<:Integer}=Int,
                       save_to::Union{Nothing,String}=nothing)

    cfg, vocab = prep.cfg, prep.vocabulary
    docs         = _load_sources(sources) #TODO: use chunks
    clean_docs   = clean_documents(docs, cfg)
    tokens, offs = tokenize_and_segment(clean_docs, cfg)

    bundle = assemble_bundle(tokens, offs, vocab, cfg; offset_type)
    save_to !== nothing && save_preprocess_bundle(bundle, save_to)
    return bundle
end


function encode_corpus(bundle::PreprocessBundle, new_sources; kwargs...)
    cfg  = bundle.metadata.configuration
    vocab = get_vocabulary(bundle, :word)
    prep = Preprocessor(cfg, vocab)
    return encode_corpus(prep, new_sources; kwargs...)
end


end # module _PreprocessorState


import ._PreprocessorState:
       Preprocessor, build_preprocessor, encode_corpus