

module KeemenaPreprocessing
__precompile__()


using Glob


#core data types
include(joinpath(@__DIR__, "core", "configuration.jl"))
include(joinpath(@__DIR__, "core", "types.jl"))


#processing
for f in ("cleaning.jl","tokenization.jl",
          "vocabulary.jl","assemble.jl")
    include(joinpath("processing", f))
end

export clean_documents #cleaning.jl
export tokenize_and_segment #tokenization.jl
export build_vocabulary #vocabulary.jl
export assemble_bundle #assemble.jl


include(joinpath(@__DIR__, "pipeline", "pipeline.jl"))

export preprocess_corpus, preprocess_corpus_streaming #pipeline.jl


#storage
include("storage/raw_readers.jl")
include("storage/bundle_io.jl")
include("storage/preprocessor_state.jl")

export stream_chunks #raw_readers.jl
export Preprocessor, encode_corpus, build_preprocessor #preprocessor_state.jl

export Vocabulary, CorpusStorage, PipelineMetadata,
       PreprocessBundle, with_extras!, haslevel,
       DEFAULT_LEVELS


export PreprocessConfiguration,
       fit_preprocessor,         # returns a reusable preprocessor
       transform_with_preprocessor,
       save_preprocess_bundle,
       load_preprocess_bundle

export save_preprocess_bundle, load_preprocess_bundle


end
