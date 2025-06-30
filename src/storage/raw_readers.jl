

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


# ----


"""
    stream_chunks(sources; chunk_bytes = 1<<20) → iterator

Yields each source as **UTF-8**, split into at-most-`chunk_bytes` chunks
Every chunk is a pair `(data::String, is_doc_terminal::Bool)`:

* `is_doc_terminal = true`  -> this chunk ends the current document
* `false`                  -> more chunks of the same document follow

`split(txt) == r"\r\n|\r"` is still normalised to `'\n'`
"""
function stream_chunks(sources; chunk_bytes::Int = 1 << 20)
    files = isa(sources, AbstractString) ? (sources,) : sources

    return Channel{Tuple{String,Bool}}() do ch
        for path in files
            if isfile(path)
                open(path, "r"; encoding = "UTF-8") do io
                    while !eof(io)
                        raw = read(io, UInt8, chunk_bytes)      # mutable bytes
                        # ensure we end on a UTF-8 code-point boundary
                        while !isempty(raw) &&
                              (raw[end] & 0b1100_0000 == 0b1000_0000)
                            pop!(raw)
                            seek(io, -1, Base.Current)
                        end
                        str = replace(String(raw), _EOL_RE => "\n")
                        put!(ch, (str, eof(io)))
                    end
                end

            elseif isdir(path)
                @warn "Ignoring directory $path"
            else
                put!(ch, (replace(path, _EOL_RE => "\n"), true))
            end
        end
    end
end
