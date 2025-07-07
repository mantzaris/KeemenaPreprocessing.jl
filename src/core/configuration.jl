


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


"""
`TOKENIZERS`

A constant `Tuple{Symbol}` listing the names of built-in tokenizers that can be
passed to the `tokenizer_name` keyword of `PreprocessConfiguration`.

Currently supported values are

* `:whitespace` - split on Unicode whitespace;
* `:unicode`    - iterate user-perceived graphemes (`eachgrapheme`);
* `:byte`       - treat the text as raw bytes (byte-level models);
* `:char`       - split on individual UTF-8 code units.

You may also supply any **callable** that implements
`mytokens = f(string)` in place of one of these symbols.
"""
const TOKENIZERS = (:whitespace, :unicode, :byte, :char)



"""
    PreprocessConfiguration(; kwargs...) -> PreprocessConfiguration

Create a fully-specified preprocessing configuration.

All keyword arguments are optional; sensible defaults are provided so that
`cfg = PreprocessConfiguration()` already yields a working pipeline.  Options
are grouped below by the stage they affect.

# Cleaning stage toggles
| keyword | default | purpose |
|---------|---------|---------|
| `lowercase` | `true` | Convert letters to lower-case. |
| `strip_accents` | `true` | Remove combining accent marks. |
| `remove_control_characters` | `true` | Drop Unicode Cc/Cf code-points. |
| `remove_punctuation` | `true` | Strip punctuation & symbol characters. |
| `normalise_whitespace` | `true` | Collapse consecutive whitespace. |
| `remove_zero_width_chars` | `true` | Remove zero-width joiners, etc. |
| `preserve_newlines` | `true` | Keep explicit line breaks. |
| `collapse_spaces` | `true` | Collapse runs of spaces/tabs. |
| `trim_edges` | `true` | Strip leading/trailing whitespace. |

## URL, e-mail & numbers
| keyword | default | purpose |
|---------|---------|---------|
| `replace_urls`  | `true`  | Replace URLs with `url_sentinel`. |
| `replace_emails`| `true`  | Replace e-mails with `mail_sentinel`. |
| `keep_url_scheme` | `false` | Preserve `http://` / `https://` prefix. |
| `url_sentinel` | `"<URL>"` | Token inserted for each URL. |
| `mail_sentinel` | `"<EMAIL>"` | Token inserted for each e-mail. |
| `replace_numbers` | `false` | Replace numbers with `number_sentinel`. |
| `number_sentinel` | `"<NUM>"` | Token used when replacing numbers. |
| `keep_number_decimal` | `false` | Preserve decimal part. |
| `keep_number_sign`    | `false` | Preserve ± sign. |
| `keep_number_commas`  | `false` | Preserve thousands separators. |

## Mark-up & HTML
| keyword | default | purpose |
|---------|---------|---------|
| `strip_markdown`  | `false` | Remove Markdown formatting. |
| `preserve_md_code`| `true`  | Keep fenced/inline code while stripping. |
| `strip_html_tags` | `false` | Remove HTML/XML tags. |
| `html_entity_decode` | `true` | Decode `&amp;`, `&quot;`, etc. |

## Emoji & Unicode
| keyword | default | purpose |
|---------|---------|---------|
| `emoji_handling` | `:keep` | `:keep`, `:remove`, or `:sentinel`. |
| `emoji_sentinel` | `"<EMOJI>"` | Used when `emoji_handling == :sentinel`. |
| `squeeze_repeat_chars` | `false` | Limit repeated character runs. |
| `max_char_run`    | `3` | Maximum run length when squeezing. |
| `map_confusables` | `false` | Map visually-confusable chars. |
| `unicode_normalisation_form` | `:none` | `:NFC`, `:NFD`, `:NFKC`, `:NFKD`, or `:none`. |
| `map_unicode_punctuation` | `false` | Replace Unicode punctuation with ASCII. |

# Tokenisation
| keyword | default | purpose |
|---------|---------|---------|
| `tokenizer_name` | `:whitespace` | One of `TOKENIZERS` **or** a callable. |
| `preserve_empty_tokens` | `false` | Keep zero-length tokens. |

# Vocabulary construction
| keyword | default | purpose |
|---------|---------|---------|
| `minimum_token_frequency` | `1` | Discard rarer tokens / map to `<UNK>`. |
| `special_tokens` | `Dict(:unk=>"<UNK>", :pad=>"<PAD>")` | Role ⇒ literal mapping. |

# Offset recording
| keyword | default | purpose |
|---------|---------|---------|
| `record_byte_offsets`      | `false` | Record byte-level spans. |
| `record_character_offsets` | `false` | Record Unicode-char offsets. |
| `record_word_offsets`      | `true`  | Record word offsets. |
| `record_sentence_offsets`  | `true`  | Record sentence offsets. |
| `record_paragraph_offsets` | `false` | Record paragraph offsets (forces `preserve_newlines = true`). |
| `record_document_offsets`  | `true`  | Record document offsets. |

# Returns
A fully-initialised `PreprocessConfiguration` instance.  Invalid combinations
raise `AssertionError` (e.g. unsupported tokenizer) and certain settings emit
warnings when they imply other flags (e.g. paragraph offsets -> `preserve_newlines`).

See also: `TOKENIZERS` and `byte_cfg` for a pre-canned byte-level configuration.
"""
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

        emoji_handling            = :keep,
        emoji_sentinel            = "<EMOJI>",

        squeeze_repeat_chars      = false,
        max_char_run              = 3,

        map_confusables           = false,

        unicode_normalisation_form = :none,
        map_unicode_punctuation   = false,        

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
        @warn "record_paragraph_offsets=true but preserve_newlines=false; enabling preserve_newlines to keep paragraph boundaries."
        preserve_newlines = true
    end

    @assert emoji_handling in (:keep, :remove, :sentinel) "emoji_handling must be :keep, :remove, or :sentinel"
    @assert unicode_normalisation_form in (:none, :NFC, :NFD, :NFKC, :NFKD)

    specials_dict = copy(special_tokens)

    if emoji_handling == :sentinel && !haskey(specials_dict, :emoji)
        specials_dict[:emoji] = emoji_sentinel
    end

    return PreprocessConfiguration(
        # Cleaning toggles (1-9)
        lowercase, strip_accents, remove_control_characters, remove_punctuation,
        normalise_whitespace, remove_zero_width_chars, preserve_newlines,
        collapse_spaces, trim_edges,
        # URL / e-mail replacement (10-14)
        replace_urls, replace_emails, keep_url_scheme, url_sentinel, mail_sentinel,
        # Numbers (15-19)
        replace_numbers, number_sentinel, keep_number_decimal,
        keep_number_sign, keep_number_commas,
        # Markdown / HTML (20-23)
        strip_markdown, preserve_md_code, strip_html_tags, html_entity_decode,
        # Emoji (24-25)
        emoji_handling, emoji_sentinel,
        # Char-run squeezing & confusables (26-28)
        squeeze_repeat_chars, max_char_run, map_confusables,
        # Unicode & punctuation (29-30)
        unicode_normalisation_form, map_unicode_punctuation,
        # Tokeniser (31-32)
        tokenizer_name, preserve_empty_tokens,
        # Vocabulary (33-34)
        minimum_token_frequency, specials_dict,
        # Off-set recording (35-40)
        record_byte_offsets, record_character_offsets, record_word_offsets,
        record_sentence_offsets, record_paragraph_offsets, record_document_offsets
    )
end


"""
    byte_cfg(; kwargs...) -> PreprocessConfiguration

Shorthand constructor that returns a `PreprocessConfiguration`
pre-configured for **byte-level** tokenisation.

The wrapper fixes the following fields

* `tokenizer_name = :byte`
* `record_byte_offsets      = true`
* `record_character_offsets = false`
* `record_word_offsets      = false`

while forwarding every other keyword argument to `PreprocessConfiguration`.
Use it when building byte-level language-model corpora but still needing the
full flexibility to tweak cleaning, vocabulary, or segmentation options:

```julia
cfg = byte_cfg(strip_html_tags = true,
               minimum_token_frequency = 5)
```
"""
byte_cfg(; kwargs...) = PreprocessConfiguration(
    tokenizer_name = :byte,
    record_byte_offsets = true,
    record_character_offsets = false,
    record_word_offsets = false;
    kwargs...)