

module KeemenaPreprocessing
__precompile__()


using Glob


#core data types
include(joinpath(@__DIR__, "core", "configuration.jl"))

export PreprocessConfiguration, TOKENIZERS, byte_cfg


include(joinpath(@__DIR__, "core", "types.jl"))

export Vocabulary, Corpus, LevelBundle, CrossMap,
        PreprocessBundle, PipelineMetadata,
        with_extras, #LEVEL_TO_OFFSETS_FIELD,  #validate_offsets,
        get_token_ids, get_vocabulary, get_corpus,
        get_level, has_level, add_level!


#processing
for f in ("cleaning.jl","tokenization.jl",
          "vocabulary.jl","assemble.jl","alignment.jl")
    include(joinpath("processing", f))
end

export clean_documents #cleaning.jl
export tokenize_and_segment #tokenization.jl
export build_vocabulary #vocabulary.jl
export assemble_bundle #assemble.jl
export alignment_byte_to_word #alignment : alignment_char_to_word, alignment_byte_to_char, build_alignments! #alignment


include(joinpath(@__DIR__, "pipeline", "pipeline.jl"))

export preprocess_corpus, preprocess_corpus_streaming #pipeline.jl


#storage
include("storage/raw_readers.jl")
include("storage/bundle_io.jl")
include("storage/preprocessor_state.jl")

export save_preprocess_bundle, load_preprocess_bundle


end
