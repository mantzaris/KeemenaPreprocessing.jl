

struct PreprocessConfiguration
    # Cleaning
    lowercase                 :: Bool
    strip_accents             :: Bool
    remove_control_characters :: Bool
    remove_punctuation        :: Bool
    normalise_whitespace      :: Bool

    # Tokenisation
    tokenizer_name            :: Union{Symbol,Function}
    preserve_empty_tokens     :: Bool

    # Vocabulary
    minimum_token_frequency   :: Int
    special_tokens            :: Dict{Symbol,String}

    # Segmentation levels
    record_character_offsets :: Bool
    record_word_offsets      :: Bool
    record_sentence_offsets   :: Bool
    record_paragraph_offsets  :: Bool
    record_document_offsets  :: Bool
end

const TOKENIZERS = (:whitespace, :unicode)


"""
    PreprocessConfiguration(; kwargs...) -> PreprocessConfiguration

Build a fully-typed, immutable configuration object that controls every
step of `preprocess_corpus`.  All keyword arguments are optional; the
defaults shown below reproduce the behaviour of a 'typical' English-language
pipeline.

If you mistype a keyword, or supply an illegal value, the constructor throws an
`AssertionError` or `ArgumentError` immediately—so your downstream workflow
can never run with hidden mistakes.

──────────────────────────────────────────────────────────────────────────────
Cleaning options
────────────────
`lowercase`                 = **true** &nbsp;&nbsp;→ convert text to lowercase  
`strip_accents`             = **true** &nbsp;&nbsp;→ remove Unicode accents/diacritics  
`remove_control_characters` = **true**  
`remove_punctuation`        = **true**  
`normalise_whitespace`      = **true** &nbsp;&nbsp;→ collapse runs of ␠, \\t, \\n into one space  

──────────────────────────────────────────────────────────────────────────────
Tokenisation
────────────
`tokenizer_name`            = **:whitespace** \\| **:unicode** \\| *callable*

* **:whitespace** - `split(str)` on ASCII whitespace.  
* **:unicode**    - splits on Unicode *word-break* boundaries (UAX #29).  
* **Function**    - any `f(::AbstractString)::Vector{String}` you supply
  (e.g. a SentencePiece processor).

`preserve_empty_tokens`     = **false** - keep empty strings that may arise
from consecutive delimiters.

──────────────────────────────────────────────────────────────────────────────
Vocabulary building
───────────────────
`minimum_token_frequency`   = **1**   -> discard tokens with lower frequency
`special_tokens`            = `Dict(:unk => "<UNK>", :pad => "<PAD>")`

The dictionary is **copied** internally, so later mutation will not affect
existing configurations.

──────────────────────────────────────────────────────────────────────────────
Segmentation levels to record (booleans)
────────────────────────────────────────
`record_character_offsets`  = false  
`record_word_offsets`       = true  
`record_sentence_offsets`   = true  
`record_paragraph_offsets`  = true  
`record_document_offsets`   = true  

These flags request which offset tables should appear in the resulting
`PreprocessBundle`.  After processing you can inspect
`bundle.levels_present[:sentence]` etc. to see which ones were actually
populated.

──────────────────────────────────────────────────────────────────────────────
Examples
────────

*Minimal default config*

```julia
cfg = PreprocessConfiguration()

#custom Unicode tokenizer and higher frequency cut-off

cfg = PreprocessConfiguration(tokenizer_name          = :unicode,
                              minimum_token_frequency = 5,
                              lowercase               = false)
                              
#plug-in your own callable tokenizer (passing a function)

unicode_tokenizer(s) = collect(eachmatch(r"\\b\\p{L}[\\p{L}\\p{Mn}\\p{Pc}\\p{Nd}]*\b", s)) .|> string

cfg = PreprocessConfiguration(tokenizer_name = unicode_tokenizer,
                              remove_punctuation = false)
                              
#you can pass cfg straight to preprocess_corpus:

bundle = preprocess_corpus(text_files; config = cfg, save_to = "bundle.jld2")
```
"""                              
function PreprocessConfiguration(;  # all kwargs are optional
        lowercase                 = true,
        strip_accents             = true,
        remove_control_characters = true,
        remove_punctuation        = true,
        normalise_whitespace      = true,

        tokenizer_name            = :whitespace,
        preserve_empty_tokens     = false,

        minimum_token_frequency   = 1,
        special_tokens            = Dict(:unk => "<UNK>", :pad => "<PAD>"),

        record_character_offsets = false,
        record_word_offsets      = true,
        record_sentence_offsets  = true,
        record_paragraph_offsets = true,
        record_document_offsets  = true)

    @assert minimum_token_frequency >= 1 "minimum_token_frequency must be >= 1"

    @assert (tokenizer_name in TOKENIZERS) || (tokenizer_name isa Function)  "tokenizer_name must be one of $(TOKENIZERS) or a callable."

    specials_dict = copy(special_tokens)

    return PreprocessConfiguration(
        lowercase, strip_accents, remove_control_characters,
        remove_punctuation, normalise_whitespace,
        tokenizer_name, preserve_empty_tokens,
        minimum_token_frequency, specials_dict,
        record_character_offsets, record_word_offsets, record_sentence_offsets, record_paragraph_offsets, record_document_offsets)
end
