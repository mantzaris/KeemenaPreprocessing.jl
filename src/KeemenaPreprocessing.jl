

module KeemenaPreprocessing
__precompile__()

using Glob


#core data types
include(joinpath(@__DIR__, "core", "types.jl"))
include(joinpath(@__DIR__, "core", "configuration.jl"))


#processing
for f in ("cleaning.jl","segmentation.jl","tokenization.jl",
          "vocabulary.jl","assemble.jl")
    include(joinpath("processing", f))
end


#storage
include("storage/raw_readers.jl")
include("storage/bundle_io.jl")
include("storage/preprocessor_state.jl")


#public api facing
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

export save_preprocess_bundle, load_preprocess_bundle


end
