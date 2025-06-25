

module KeemenaPreprocessing


#core data types
include(joinpath(@__DIR__, "core", "types.jl"))
include(joinpath(@__DIR__, "core", "configuration.jl"))


include(joinpath(@__DIR__, "pipeline", "pipeline.jl"))


export Vocabulary, CorpusStorage, PipelineMetadata,
       PreprocessBundle, with_extras!, haslevel,
       DEFAULT_LEVELS


export PreprocessConfiguration,
       preprocess_corpus,        # one-shot convenience
       fit_preprocessor,         # returns a reusable preprocessor
       transform_with_preprocessor,
       save_preprocess_bundle,
       load_preprocess_bundle


end
