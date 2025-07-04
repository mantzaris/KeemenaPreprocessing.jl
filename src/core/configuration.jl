
struct PreprocessConfiguration

    # Cleaning
    lowercase                 :: Bool
    strip_accents             :: Bool
    remove_control_characters :: Bool
    remove_punctuation        :: Bool
    normalise_whitespace      :: Bool
    remove_zero_width_chars   :: Bool
    preserve_newlines         :: Bool
    collapse_spaces           :: Bool
    trim_edges                :: Bool

    replace_urls              :: Bool
    replace_emails            :: Bool
    keep_url_scheme           :: Bool
    url_sentinel              :: String
    mail_sentinel             :: String

    replace_numbers           :: Bool
    number_sentinel           :: String
    keep_number_decimal       :: Bool
    keep_number_sign          :: Bool
    keep_number_commas        :: Bool

    strip_markdown            :: Bool
    preserve_md_code          :: Bool # keeps fenced or inline code blocks

    strip_html_tags           :: Bool
    html_entity_decode        :: Bool

    emoji_handling            :: Symbol#:keep|:remove|:sentinel
    emoji_sentinel            :: String   # only used if :sentinel

    squeeze_repeat_chars      :: Bool
    max_char_run              :: Int   # used only if the flag above

    map_confusables           :: Bool

    unicode_normalisation_form :: Symbol  # :none | :NFC | :NFKC | :NFD | :NFKD
    map_unicode_punctuation   :: Bool

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
        lowercase                 = true,
        strip_accents             = true,
        remove_control_characters = true,
        remove_punctuation        = true,
        normalise_whitespace      = true,
        remove_zero_width_chars   = true,
        preserve_newlines         = true,
        collapse_spaces           = true,
        trim_edges                = true,

        replace_numbers           = false,
        number_sentinel           = "<NUM>",
        keep_number_decimal       = false,
        keep_number_sign          = false,
        keep_number_commas        = false,

        strip_markdown            = false,
        preserve_md_code          = true,

        replace_urls              = true,
        replace_emails            = true,
        keep_url_scheme           = false,
        url_sentinel              = "<URL>",
        mail_sentinel             = "<EMAIL>",

        strip_html_tags           = false,
        html_entity_decode        = true,

        emoji_handling            = :sentinel,
        emoji_sentinel            = "<EMOJI>",

        squeeze_repeat_chars      = false,
        max_char_run              = 3,

        map_confusables           = false,

        unicode_normalisation_form = :none,
        map_unicode_punctuation = true,        

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

    if record_paragraph_offsets && !preserve_newlines
        @warn "record_paragraph_offsets=true but preserve_newlines=false; \
               enabling preserve_newlines to keep paragraph boundaries."
        preserve_newlines = true
    end

    @assert emoji_handling in (:keep, :remove, :sentinel) "emoji_handling must be :keep, :remove, or :sentinel"
    @assert unicode_normalisation_form in (:none, :NFC, :NFD, :NFKC, :NFKD)

    specials_dict = copy(special_tokens)

    if emoji_handling == :sentinel && !haskey(specials_dict, :emoji)
        specials_dict[:emoji] = emoji_sentinel
    end

    return PreprocessConfiguration(
        lowercase, strip_accents, remove_control_characters,
        remove_punctuation, normalise_whitespace, remove_zero_width_chars,
        preserve_newlines, collapse_spaces, trim_edges,
        replace_numbers, number_sentinel, keep_number_decimal, keep_number_sign, keep_number_commas,
        strip_markdown, preserve_md_code,
        replace_urls, replace_emails, keep_url_scheme, url_sentinel, mail_sentinel,
        strip_html_tags, html_entity_decode,
        emoji_handling, emoji_sentinel,
        squeeze_repeat_chars, max_char_run,
        map_confusables,
        unicode_normalisation_form, map_unicode_punctuation,
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