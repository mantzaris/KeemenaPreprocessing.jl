
struct PreprocessConfiguration
    chunk_size                :: Int

    # Cleaning
    lowercase                 :: Bool
    strip_accents             :: Bool
    remove_control_characters :: Bool
    remove_punctuation        :: Bool
    normalise_whitespace      :: Bool
    trim_edges                :: Bool

    # Tokenisation
    tokenizer_name            :: Union{Symbol,Function}
    preserve_empty_tokens     :: Bool

    # Vocabulary
    minimum_token_frequency   :: Int
    special_tokens            :: Dict{Symbol,String}

    # Segmentation levels
    record_byte_offsets       :: Bool
    record_character_offsets  :: Bool
    record_word_offsets       :: Bool
    record_sentence_offsets   :: Bool
    record_paragraph_offsets  :: Bool
    record_document_offsets   :: Bool
end


const TOKENIZERS = (:whitespace, :unicode, :byte, :char)


function PreprocessConfiguration(;  # all kwargs are optional
        chunk_size                = 250_000,
        lowercase                 = true,
        strip_accents             = true,
        remove_control_characters = true,
        remove_punctuation        = true,
        normalise_whitespace      = true,
        trim_edges                = true,

        tokenizer_name            = :whitespace,
        preserve_empty_tokens     = false,

        minimum_token_frequency   = 1,
        special_tokens            = Dict(:unk => "<UNK>", :pad => "<PAD>"), #TODO: expand!!!

        record_byte_offsets      = false,
        record_character_offsets = false,
        record_word_offsets      = true,
        record_sentence_offsets  = true,
        record_paragraph_offsets = false,
        record_document_offsets  = true)

    @assert minimum_token_frequency >= 1 "minimum_token_frequency must be >= 1"

    @assert (tokenizer_name in TOKENIZERS) || (tokenizer_name isa Function)  "tokenizer_name must be one of $(TOKENIZERS) or a callable."

    specials_dict = copy(special_tokens)

    return PreprocessConfiguration(
        chunk_size,
        lowercase, strip_accents, remove_control_characters,
        remove_punctuation, normalise_whitespace, trim_edges,
        tokenizer_name, preserve_empty_tokens,
        minimum_token_frequency, specials_dict,
        record_byte_offsets, record_character_offsets, record_word_offsets, record_sentence_offsets, record_paragraph_offsets, record_document_offsets)
end


byte_cfg(; kwargs...) = PreprocessConfiguration(
    tokenizer_name = :byte,
    record_byte_offsets = true,
    record_character_offsets = false,
    record_word_offsets = false;
    kwargs...)