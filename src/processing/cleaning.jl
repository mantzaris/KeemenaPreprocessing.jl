

module _Cleaning   # private to avoid name clashes


using Unicode
using Unicode: graphemes
using ..KeemenaPreprocessing: PreprocessConfiguration


const _CTRL_RE   = r"[\p{Cc}\p{Cf}]"
const _PUNCT_RE = r"[\p{P}\p{S}]"     # Unicode punctuation & symbols
const _WS_RE = r"[ \t\n\v\f\r]+"      # explicit space first for readability

const _COMBINING_RE = r"\p{Mn}"


# --- helpers ---------------------------------------------------------------
@inline function normalize_unicode(text::AbstractString; form::Symbol = :NFC)
    form == :none && return text
    form in (:NFC, :NFD, :NFKC, :NFKD) ||
        throw(ArgumentError("Unsupported normalization form: $form"))
    return Unicode.normalize(text, form)
end

"""
    _strip_accents(s) -> String

Return a copy of `s` with all combining accents (Unicode category `Mn`)
removed.  Works on all supported Julia versions.
"""
function _strip_accents(s::AbstractString)
    nfd      = Unicode.normalize(s, :NFD)          # 1. decompose
    stripped = replace(nfd, _COMBINING_RE => "")   # 2. drop accents
    return Unicode.normalize(stripped, :NFC)       # 3. recompose
end


"""
    normalize_whitespace(text; strip_ends        = true,
                              preserve_newlines = false,
                              remove_zero_width = false,
                              collapse_spaces   = true)

* Collapses runs of whitespace.
* Optionally keeps paragraph/new-line structure.
* Optionally converts zero-width separators (ZWSP, ZWNJ, ZWJ, BOM) to a
  **regular ASCII space** so that word boundaries stay visible.
"""
function normalize_whitespace(text::AbstractString;
                              strip_ends::Bool        = true,
                              preserve_newlines::Bool = false,
                              remove_zero_width::Bool = false,
                              collapse_spaces::Bool   = true)

    isempty(text) && return text

    # deal with zero-widths first, turning them into *real* blanks so that
    #      later collapsing treats them like ordinary spaces.
    if remove_zero_width
        # ZWSP U+200B, ZWNJ U+200C, ZWJ U+200D, BOM U+FEFF
        text = replace(text, r"[\u200B\u200C\u200D\uFEFF]+" => " ")
    end

    #if we do not want any collapsing, we're essentially done
    collapse_spaces || (strip_ends && return strip(text); return text)

    if preserve_newlines
        # collapse printable blanks except the hard newline
        text = replace(text, r"[ \t\f\r]+" => " ")

        # trim blanks *around* the newline
        text = replace(text, r" +\n" => "\n")   # before
        text = replace(text, r"\n +" => "\n")   # after
    else
        #full collapse (but keep leading/trailing runs for tests)
        leading  = match(r"^\s+", text)
        trailing = match(r"\s+$", text)

        core = replace(strip(text), r"\s+" => " ")
        text = (leading === nothing ? "" : leading.match) *
               core *
               (trailing === nothing ? "" : trailing.match)
    end

    strip_ends && (text = strip(text))
    return text
end



if !@isdefined(_UNICODE_PUNCT_TABLE)
    const _UNICODE_PUNCT_TABLE = Dict(
        '“' => "\"",  '”' => "\"",
        '‘' => "\'",  '’' => "\'",
        '«' => "\"",  '»' => "\"",
        '‐' => "-",   '-' => "-",   # hyphen & non-breaking hyphen
        '–' => "-",   '—' => "-",   '―' => "-",   # en / em / horiz. bar
        '…' => "...",
        '‹' => "<",   '›' => ">"
    )
end

"""
    map_unicode_punctuation(text) -> String

Replace curly quotes, long dashes, ellipsis, guillemets, and other
“fancy” Unicode punctuation with plain-ASCII equivalents.
Runs in O(n) and allocates once.
"""
@inline function map_unicode_punctuation(text::AbstractString)::String
    isempty(text) && return text           # fast-path

    buf = IOBuffer()
    for c in text
        if haskey(_UNICODE_PUNCT_TABLE, c)
            write(buf, _UNICODE_PUNCT_TABLE[c])
        else
            write(buf, c)
        end
    end
    return String(take!(buf))
end


#TODO: \p{Emoji} JuliaLang Base.Unicode 1.11 has :Emoji
if !@isdefined(EMOJI_RANGES)
    const EMOJI_RANGES = Tuple{UInt32,UInt32}[
        (0x1F300, 0x1F5FF),
        (0x1F600, 0x1F64F),
        (0x1F680, 0x1F6FF),
        (0x1F700, 0x1F77F),
        (0x1F900, 0x1F9FF),
        (0x1FA70, 0x1FAFF),
        (0x2600,  0x26FF),
        (0x2700,  0x27BF),
        (0x1F1E6, 0x1F1FF),
        (0x1F3FB, 0x1F3FF),
        (0xFE0F,  0xFE0F),   #VS-16
        (0x200D,  0x200D),   #ZWJ
    ]
end


@inline in_emoji_codepoint(c::Char) = begin
    cp = UInt32(c)
    any(lo <= cp <= hi for (lo,hi) in EMOJI_RANGES)
end
  
"""
    isEmoji(grapheme::AbstractString) -> Bool

True if **all** code-points in the grapheme cluster are emoji-range or
emoji modifiers (VS-16, ZWJ, etc)
"""
function isEmoji(g::AbstractString)
    for c in g
        cp = UInt32(c)
        if cp == 0xFE0F || cp == 0x200D  # VS-16 or ZWJ -> modifier
            continue
        end
        in_emoji_codepoint(c) || return false
    end
    return true
end  

function _rewrite_emojis(text::String, cfg::PreprocessConfiguration)
    eh = cfg.emoji_handling
    eh === :keep && return text

    buf = IOBuffer()
    in_run = false

    for g in graphemes(text)
        if isEmoji(g)
            in_run = true
        else
            if in_run && eh === :sentinel
                write(buf, cfg.emoji_sentinel)
            end
            in_run = false
            write(buf, g)
        end
    end
    if in_run && eh === :sentinel
        write(buf, cfg.emoji_sentinel)
    end
    return String(take!(buf))     # :remove path writes nothing
end


"""
    replace_urls_emails(text;
                        url_sentinel   = "<URL>",
                        mail_sentinel  = "<EMAIL>",
                        keep_scheme    = false) -> String

Replace every HTTP/HTTPS URL and every e-mail address with a sentinel token
so the vocabulary is not polluted by arbitrary host names, query strings, or
usernames.

* `url_sentinel` - token that replaces each URL.
* `mail_sentinel` - token that replaces each e-mail address.
* `keep_scheme = true` - if set, keeps the leading `http://` or `https://`
  and replaces only the remainder.  Useful when you want to distinguish
  secure (`https`) from plain (`http`) links while still shielding the rest
  of the text.

Returns a new `String`; original text is unchanged.
"""
function replace_urls_emails(text::AbstractString;
                             url_sentinel::AbstractString = "<URL>",
                             mail_sentinel::AbstractString = "<EMAIL>",
                             keep_scheme::Bool = false)::String

    URL_RE  = r"(https?://)?[A-Za-z0-9\-_]+(\.[A-Za-z0-9\-_]+)+(/[^\s]*)?"
    MAIL_RE = r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"

    # Step 1 - e-mails (do first so mail-like URLs aren't double-substituted)
    out = replace(text, MAIL_RE => mail_sentinel)

    # Step 2 - URLs
    if keep_scheme
        out = replace(out, URL_RE => function(matched_str)
            # Re-match to get captures
            m = match(URL_RE, matched_str)
            scheme = m.captures[1]        # nothing or "http://"/"https://"
            isnothing(scheme) ? url_sentinel : string(scheme, url_sentinel)
        end)
    else
        out = replace(out, URL_RE => url_sentinel)
    end

    return out
end



if !@isdefined(_THOUSANDS_RE)
    const _THOUSANDS_RE = r"(?<=\d),(?=\d\d\d\b)"   # 1,234 -> 1234
end
if !@isdefined(_NUM_RE)
    const _NUM_RE       = r"[0-9]+"  # core digits
end
if !@isdefined(NUM_PAT)
    const NUM_PAT       = r"""
        (?:
            (?P<sign>[+-])?                    # optional sign
            (?P<int>\d+)                       # integer part
            (?:\.(?P<frac>\d+))?               # optional .fraction
        )
    """x
end

@inline function replace_numbers(text::AbstractString;
        sentinel::AbstractString = "<NUM>",
        keep_decimal::Bool       = false,
        keep_sign::Bool          = false,
        keep_commas::Bool        = false)::String

    isempty(text) && return text   # fast-path

    # 1 standardise separators if requested
    t = keep_commas ? replace(text, _THOUSANDS_RE => "") : text

    # 2 main pass - a single replace with captured groups    
    return replace(t, NUM_PAT => function(matched_str)              # matched_str :: SubString
            # Re-match to get named captures
            rm = match(NUM_PAT, matched_str)
            io = IOBuffer()

            # sign
            if keep_sign && !isnothing(rm["sign"]) && !isempty(rm["sign"])
                write(io, rm["sign"])
            end

            # sentinel
            write(io, sentinel)

            # decimal part
            if keep_decimal && !isnothing(rm["frac"]) && !isempty(rm["frac"])
                write(io, '.' * rm["frac"])
            end

            String(take!(io))
        end)
end



"""
    strip_html(text;
               decode_entities = true) -> String

Remove HTML/XML tags (`<...>`) and, optionally, replace the most common HTML
entities with their Unicode characters.  The regex is safe for well-formed
markup and tolerates attributes and self-closing tags.

Examples
--------
julia> strip_html("<div>Hello&nbsp;world&#33;</div>")
"Hello world!"

The function is dependency-free and UTF-8-safe.  It makes **no** attempt to
preserve inline images, styles, or scripts; those are dropped entirely.
"""
function strip_html(text::AbstractString; decode_entities::Bool = true)
    #zap tags (`<tag attr="...">`, `</tag>`, `<!-- comments -->`)
    cleaned = replace(text, r"<[^>]*>" => "")

    # optionally decode entities
    if decode_entities
    
        cleaned = replace(cleaned, "&nbsp;" => "\u00A0")
        cleaned = replace(cleaned, "&lt;"   => "<")
        cleaned = replace(cleaned, "&gt;"   => ">")
        cleaned = replace(cleaned, "&amp;"  => "&")
        cleaned = replace(cleaned, "&quot;" => "\"")
        cleaned = replace(cleaned, "&apos;" => "'")
        cleaned = replace(cleaned, "&#39;"  => "'")
        cleaned = replace(cleaned, "&#34;"  => "\"")
        
    end
    return cleaned
end


"""
    strip_markdown(text;
                   preserve_code = true,
                   code_sentinel = "<CODE>") -> String

Remove common Markdown formatting:

* Fenced code blocks  ```lang ... ```  and inline code  `code`
* Images  ![alt](url)  ->  `alt`  (or sentinel if no alt)
* Links   [text](url)  ->  `text`
* Bold / italic markers **text**, __text__, *text*, _text_
* Headings (#, ##, ...), horizontal rules, blockquotes, list bullets

If `preserve_code = true`, code blocks/inlines are replaced by `code_sentinel`;
otherwise they are removed entirely.
"""
function strip_markdown(text::AbstractString;
                        preserve_code::Bool = true,
                        code_sentinel::AbstractString = "<CODE>")::String
    t = text

    #images ![alt](url)  -> alt or sentinel
    t = replace(t, r"!\[([^\]]*)\]\([^\)]*\)" => function(matched_str)
        #re-match to get captures
        m = match(r"!\[([^\]]*)\]\([^\)]*\)", matched_str)
        isempty(m.captures[1]) ? "" : m.captures[1]
    end)

    #links [text](url) -> text
    t = replace(t, r"\[([^\]]+)\]\([^\)]*\)" => function(matched_str)
        #re-match to get captures
        m = match(r"\[([^\]]+)\]\([^\)]*\)", matched_str)
        m.captures[1]
    end)

    # fenced code blocks ``` ``` (lazy, non-greedy)
    fence_re = r"```[\s\S]*?```"
    t = preserve_code ? replace(t, fence_re => code_sentinel) : replace(t, fence_re => "")

    # inline code `code`
    inline_re = r"`[^`]+`"
    t = preserve_code ? replace(t, inline_re => code_sentinel) : replace(t, inline_re => "")

    # bold/italic, headings, hrules, blockquotes, lists
    t = replace(t, r"[*_]{1,3}([^*_]+)[*_]{1,3}" => function(matched_str)
        #re-match to get captures
        m = match(r"[*_]{1,3}([^*_]+)[*_]{1,3}", matched_str)
        m.captures[1]
    end)   # bold / italic
    t = replace(t, r"^#+\s*"m => "")          # headings
    t = replace(t, r"^>+\s*"m  => "")         # blockquotes
    t = replace(t, r"^[-*+]\s+"m => "")       # bullets
    t = replace(t, r"^\s*[-*_]{3,}\s*$"m => "") # hrule

    return t
end


# Collapse any run of the same code-point to ≤ max_run
@inline function squeeze_char_runs(text::AbstractString; max_run::Int = 3)
    isempty(text) && return text
    buf  = IOBuffer()
    prev = '\0'; run = 0
    for c in text
        if c == prev
            run += 1
            run ≤ max_run && write(buf, c)
        else
            run = 1
            write(buf, c)
            prev = c
        end
    end
    return String(take!(buf))
end

# Minimal confusable map (Latin look-alikes); extend as needed.
if !@isdefined(_CONFUSABLES)
    const _CONFUSABLES = Dict(
        'Α'=>'A','Β'=>'B','Ε'=>'E','Η'=>'H','Ι'=>'I','Κ'=>'K','Μ'=>'M','Ν'=>'N',
        'Ο'=>'O','Ρ'=>'P','Τ'=>'T','Υ'=>'Y','Χ'=>'X','а'=>'a','е'=>'e','о'=>'o',
        'р'=>'p','с'=>'c','х'=>'x','ї'=>'i','і'=>'i','ӏ'=>'l'
    )
end

@inline function normalize_confusables(txt::AbstractString)::String
    isempty(txt) && return txt                     # fast-path

    buf = IOBuffer()
    for c in txt
        write(buf, get(_CONFUSABLES, c, c))        # fallback to original char
    end
    return String(take!(buf))
end



"""
    clean_documents(docs, cfg) → Vector{String}

Apply the **text-cleaning stage** of the Keemena pipeline to every document in
`docs` according to the options held in `cfg`
([`PreprocessConfiguration`](@ref)).  
The returned vector has the *same length and order* as `docs`.

### Arguments
| name | type | description |
|------|------|-------------|
| `docs` | `Vector{String}` | Raw, unprocessed documents. |
| `cfg`  | `PreprocessConfiguration` | Cleaning directives (lower-casing, URL replacement, emoji handling, …). |

### Processing steps
The function runs a *fixed* sequence of transformations, each guarded by the
corresponding flag in `cfg`:

1. **Unicode normalisation** `normalize_unicode` (`unicode_normalisation_form`).
2. **HTML stripping** `strip_html` + entity decoding (`strip_html_tags`,
   `html_entity_decode`).
3. **Markdown stripping** `strip_markdown` (`strip_markdown`,
   `preserve_md_code`).
4. **Repeated-character squeezing** `squeeze_char_runs`
   (`squeeze_repeat_chars`, `max_char_run`).
5. **Unicode confusable mapping** `normalize_confusables`
   (`map_confusables`).
6. **Emoji handling** `_rewrite_emojis` (`emoji_handling`, `emoji_sentinel`).
7. **Number replacement** `replace_numbers` (`replace_numbers`, plus the
   `keep_*` sub-flags and `number_sentinel`).
8. **Unicode-to-ASCII punctuation mapping** `map_unicode_punctuation`
   (`map_unicode_punctuation`).
9. **URL / e-mail replacement** `replace_urls_emails`
   (`replace_urls`, `replace_emails`, `url_sentinel`, `mail_sentinel`,
   `keep_url_scheme`).
10. **Lower-casing** `lowercase` (`lowercase`).
11. **Accent stripping** `_strip_accents` (`strip_accents`).
12. **Control-character removal** regex replace with `_CTRL_RE`
    (`remove_control_characters`).
13. **Whitespace normalisation** `normalize_whitespace`
    (`normalise_whitespace`, `remove_zero_width_chars`, `collapse_spaces`,
    `trim_edges`, `preserve_newlines`).  Falls back to `strip` when only
    `trim_edges` is requested.
14. **Punctuation removal** regex replace with `_PUNCT_RE`
    (`remove_punctuation`).

Every transformation returns a *new* string; the original input remains
unchanged.

### Returns
`Vector{String}` — cleaned documents ready for tokenisation.

### Example
```julia
cfg  = PreprocessConfiguration(strip_html_tags = true,
                               replace_urls    = true)
clean = clean_documents(["Visit https://example.com!"], cfg)
@info clean[1]   # -> "Visit <URL>"
```
"""
function clean_documents(docs::Vector{String}, cfg::PreprocessConfiguration)
    out = similar(docs)
    
    for (i, doc) in pairs(docs)
        s = doc

        s = normalize_unicode(s; form = cfg.unicode_normalisation_form)

        if cfg.strip_html_tags
            s = strip_html(s; decode_entities = cfg.html_entity_decode)
        end

        if cfg.strip_markdown
            s = strip_markdown(s;
                    preserve_code = cfg.preserve_md_code,
                    code_sentinel = "<CODE>")
        end

        if cfg.squeeze_repeat_chars
            s = squeeze_char_runs(s; max_run = cfg.max_char_run)
        end

        if cfg.map_confusables
            s = normalize_confusables(s)
        end

        s = _rewrite_emojis(s, cfg)

        if cfg.replace_numbers
        s = replace_numbers(
                s;
                sentinel     = cfg.number_sentinel,
                keep_decimal = cfg.keep_number_decimal,
                keep_sign    = cfg.keep_number_sign,
                keep_commas  = cfg.keep_number_commas)
        end


        if cfg.map_unicode_punctuation
            s = map_unicode_punctuation(s)
        end

        if cfg.replace_urls || cfg.replace_emails
            s = replace_urls_emails(s;
                url_sentinel  = cfg.url_sentinel,
                mail_sentinel = cfg.mail_sentinel,
                keep_scheme   = cfg.keep_url_scheme)
        end

        cfg.lowercase                 && (s = lowercase(s))
        cfg.strip_accents             && (s = _strip_accents(s))
        cfg.remove_control_characters && (s = replace(s, _CTRL_RE => ""))
        
        
        # whitespace, zero-width, edges (all via your helper)
        if cfg.normalise_whitespace || cfg.remove_zero_width_chars
            s = normalize_whitespace(s;
                    strip_ends        = cfg.trim_edges,
                    preserve_newlines = cfg.preserve_newlines,
                    remove_zero_width = cfg.remove_zero_width_chars,
                    collapse_spaces   = cfg.collapse_spaces)
        elseif cfg.trim_edges
            s = strip(s)
        end

        cfg.remove_punctuation && (s = replace(s, _PUNCT_RE => ""))

        out[i] = s
    end
    return out
end


end # module _Cleaning


# re-export into main namespace
import ._Cleaning: clean_documents
