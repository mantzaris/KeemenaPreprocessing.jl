

# struct Preprocessor{Cfg,IdT}
#     cfg        :: Cfg              # the fitted configuration
#     vocabulary :: Vocabulary{IdT}  # frozen token-id map
# end

# function fit_preprocessor(train_sources; kwargs...)
#     # build a config from kwargs, run the full pipeline ONCE
#     bundle = preprocess_corpus(train_sources; kwargs...)
#     prep   = Preprocessor(bundle.pipeline_metadata.configuration,
#                           bundle.vocabulary)
#     return prep, bundle
# end

# function transform_with_preprocessor(prep::Preprocessor, new_sources;
#                                      offset_type::Type{<:Integer}=Int,
#                                      save_to::Union{Nothing,String}=nothing)
#     # reuse vocab & cfg, skip vocab building
#     docs, clean = _load_sources(new_sources), clean_documents(_, prep.cfg)
#     toks, offs  = tokenize_and_segment(clean, prep.cfg)
#     bundle      = assemble_bundle(toks, offs, prep.vocabulary, prep.cfg;
#                                   offset_type)
#     save_to !== nothing && save_preprocess_bundle(bundle, save_to)
#     return bundle
# end
