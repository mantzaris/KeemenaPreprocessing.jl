

const _EOL_RE = r"\r\n|\r" # normalise to LF


"""
    _load_sources(src) -> Vector{String}

Get string text from one or many sources into UTF-8 text with `\\n` line endings.

`src` may be

  - a single `AbstractString`, or
  - any iterable of `AbstractString`s


1. `isfile(elem)` -> read it as a file (UTF-8, line endings normalised)
2. `isdir(elem)` -> **ignored** (skipped, produces no output)
3. otherwise -> treated as raw text (line endings normalised)

Returns: `Vector{String}` containing one entry per **kept** element, in order

Errors: 

- `IOError`        : file exists but cannot be opened or decoded
- `ArgumentError`  : element is not an `AbstractString`

Examples

```julia
using Glob

_load_sources("doc.txt")                       # -> ["...file contents..."]
_load_sources("inline text")                   # -> ["inline text"]
_load_sources(["a.txt", "notes"])              # -> ["...", "notes"]
_load_sources(Glob.glob("/home/*.txt"))        # glob iterator -> all files
_load_sources(["/tmp", "b.txt"])               # /tmp is a dir -> skipped
```
"""
function _load_sources(src)::Vector{String}
    xs = isa(src, AbstractString) ? (src,) : src # promote scalar
    docs = String[]

    for item in xs
        isa(item, AbstractString) || throw(ArgumentError(
            "unsupported element $(repr(item)) of type $(typeof(item))"))

        if isfile(item)                     # real file
            push!(docs, _read_file(item))           # may throw IOError
        elseif isdir(item)                  #  directory - skip
            @warn "Ignoring directory: $item"
            continue                        
        else                                # raw text (or non-existent path)
            push!(docs, replace(item, _EOL_RE => "\n"))
        end
    end
    return docs

end


function _read_file(path::AbstractString)::String
    open(path, "r", encoding="UTF-8") do io
        read(io, String) |> x -> replace(x, _EOL_RE => "\n")
    end
end
