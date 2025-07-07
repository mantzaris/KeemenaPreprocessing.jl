

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

@doc (@doc _Cleaning.clean_documents) clean_documents
export clean_documents #cleaning.jl

@doc (@doc _Assemble.tokenize_and_segment) tokenize_and_segment
export tokenize_and_segment #tokenization.jl

@doc (@doc _Vocabulary.build_vocabulary) build_vocabulary
export build_vocabulary #vocabulary.jl

@doc (@doc _Assemble.assemble_bundle) assemble_bundle
export assemble_bundle #assemble.jl

@doc (@doc _Alignment.alignment_byte_to_word) alignment_byte_to_word
export alignment_byte_to_word #alignment : alignment_char_to_word, alignment_byte_to_char, build_alignments! #alignment


include(joinpath(@__DIR__, "pipeline", "pipeline.jl"))

export preprocess_corpus, preprocess_corpus_streaming #pipeline.jl
export preprocess_corpus_streaming_chunks
export preprocess_corpus_streaming_full


#storage
include("storage/raw_readers.jl")
include("storage/bundle_io.jl")
include("storage/preprocessor_state.jl")

@doc (@doc _BundleIO.save_preprocess_bundle) save_preprocess_bundle
export save_preprocess_bundle

@doc (@doc _BundleIO.load_preprocess_bundle) load_preprocess_bundle
export load_preprocess_bundle


 


const TOKENIZERS          = TOKENIZERS
const validate_offsets    = validate_offsets
const doc_chunk_iterator  = doc_chunk_iterator




end
