

const _EOL_RE = r"\r\n|\r" # normalise to LF



function _load_sources(src)::Vector{String}
    xs   = isa(src, AbstractString) ? (src,) : src  # promote scalar
    docs = String[]
    for item in xs
        isa(item, AbstractString) || throw(ArgumentError(
            "unsupported element $(repr(item)) of type $(typeof(item))"))


        is_path = false
        if sizeof(item) <= 4_096        # cheap fast-path; most OS PATH_MAX <= 4096
            try
                is_path = isfile(item) || isdir(item)
            catch e
                if e isa IOError && (e.code == Base.UV_ENAMETOOLONG ||
                                     e.code == Base.UV_ENOENT)
                    is_path = false     # treat as raw text
                else
                    rethrow(e)          # genuine I/O failure on a real path
                end
            end
        end

        if is_path && isfile(item)
            push!(docs, _read_file(item))          # may throw if unreadable
        elseif is_path && isdir(item)
            @warn "Ignoring directory: $item"
        else                                       # raw text
            push!(docs, replace(item, _EOL_RE => "\n"))
        end
    end
    return docs
end


function _read_file(path::AbstractString)::String
    open(path, "r") do io
        read(io, String) |> x -> replace(x, _EOL_RE => "\n")
    end
end


# ----


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
