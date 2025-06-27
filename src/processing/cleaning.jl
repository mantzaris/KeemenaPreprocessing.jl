# TODO: add more cleaning like emojis removal etc


module _Cleaning   # private to avoid name clashes


using Unicode
using ..KeemenaPreprocessing: PreprocessConfiguration


const _CTRL_RE   = r"[\p{Cc}\p{Cf}]"
const _PUNCT_RE = r"[\p{P}\p{S}]"     # Unicode punctuation & symbols
const _WS_RE = r"[ \t\n\v\f\r]+"      # explicit space first for readability


# helper: strip accents
_strip_accents!(s::String) =
    (replace!(s, '\u0300':'\u036F' => ""); s)  # remove combining diacritics

# main public function
"""
    clean_documents(docs, cfg) -> Vector{String}

Apply the five cleaning toggles in `cfg` to each document string **in-place**.

The returned vector re-uses the original strings (no re-allocation unless a
transformation occurs).
"""
function clean_documents(docs::Vector{String}, cfg::PreprocessConfiguration)
    out = similar(docs)
    for (i, doc) in pairs(docs)
        s = doc

        cfg.lowercase                 && (s = lowercase(s))
        cfg.strip_accents             && (_strip_accents!(s))
        cfg.remove_control_characters && (s = replace(s, _CTRL_RE => ""))
        cfg.remove_punctuation        && (s = replace(s, _PUNCT_RE => ""))
        cfg.normalise_whitespace      && (s = replace(s, _WS_RE => " "))

        out[i] = s
    end
    return out
end


end # module _Cleaning


# re-export into main namespace
import ._Cleaning: clean_documents
