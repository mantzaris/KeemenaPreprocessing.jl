

module KeemenaPreprocessing
__precompile__()


using Glob


#core data types
include(joinpath(@__DIR__, "core", "configuration.jl"))

export PreprocessConfiguration, byte_cfg


include(joinpath(@__DIR__, "core", "types.jl"))

export Vocabulary, Corpus, LevelBundle,
        PreprocessBundle, PipelineMetadata,
        with_extras,
        LEVEL_TO_OFFSETS_FIELD,
        get_token_ids, get_vocabulary, get_corpus,
        get_level, has_level, add_level!,
        validate_offsets


#processing
for f in ("cleaning.jl","tokenization.jl",
          "vocabulary.jl","assemble.jl","alignment.jl")
    include(joinpath("processing", f))
end

export clean_documents #cleaning.jl
export tokenize_and_segment #tokenization.jl
export build_vocabulary #vocabulary.jl
export assemble_bundle, assemble_multi #assemble.jl
export alignment_byte_to_word, alignment_char_to_word, alignment_byte_to_char #alignment


include(joinpath(@__DIR__, "pipeline", "pipeline.jl"))

export preprocess_corpus, preprocess_corpus_streaming #pipeline.jl


#storage
include("storage/raw_readers.jl")
include("storage/bundle_io.jl")
include("storage/preprocessor_state.jl")

export stream_chunks #raw_readers.jl
export Preprocessor, encode_corpus, build_preprocessor #preprocessor_state.jl

export fit_preprocessor,         # returns a reusable preprocessor
       transform_with_preprocessor


export save_preprocess_bundle, load_preprocess_bundle


end
