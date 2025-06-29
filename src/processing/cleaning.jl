# TODO: add more cleaning like emojis removal etc


module _Cleaning   # private to avoid name clashes


using Unicode
using ..KeemenaPreprocessing: PreprocessConfiguration


const _CTRL_RE   = r"[\p{Cc}\p{Cf}]"
const _PUNCT_RE = r"[\p{P}\p{S}]"     # Unicode punctuation & symbols
const _WS_RE = r"[ \t\n\v\f\r]+"      # explicit space first for readability

const _COMBINING_RE = r"\p{Mn}"


# --- helpers ---------------------------------------------------------------

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


# --- public API ------------------------------------------------------------


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
        cfg.strip_accents             && (s = _strip_accents(s))
        cfg.remove_control_characters && (s = replace(s, _CTRL_RE => ""))
        cfg.remove_punctuation        && (s = replace(s, _PUNCT_RE => ""))
        cfg.normalise_whitespace      && (s = replace(s, _WS_RE => " "))
        cfg.trim_edges                && (s = strip(s))

        out[i] = s
    end
    return out
end


end # module _Cleaning


# re-export into main namespace
import ._Cleaning: clean_documents
