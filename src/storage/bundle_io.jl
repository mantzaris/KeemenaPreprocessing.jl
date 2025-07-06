

module _BundleIO


using JLD2
using ..KeemenaPreprocessing: PreprocessBundle, PreprocessConfiguration


const _BUNDLE_VERSION = v"1.0.0"


"""
    save_preprocess_bundle(bundle, path; format = :jld2, compress = true) -> String

Persist a [`PreprocessBundle`](@ref) to disk and return the **absolute** file
path written.

Currently the only supported `format` is `:jld2`; an error is raised for any
other value.

### Arguments
| name | type | description |
|------|------|-------------|
| `bundle` | `PreprocessBundle` | Object produced by `preprocess_corpus`. |
| `path`   | `AbstractString`   | Destination file name (relative or absolute).  Parent directories are created automatically. |
| `format` | `Symbol` (keyword) | Serialization format. **Must be `:jld2`**. |
| `compress` | `Bool` (keyword) | When `true` (default) the JLD2 file is written with zlib compression; set to `false` for fastest write speed. |

### File structure
The JLD2 file stores three top-level keys

| key | value |
|-----|-------|
| `"__bundle_version__"`  | String denoting the package's internal bundle spec. |
| `"__schema_version__"`  | `string(bundle.metadata.schema_version)` |
| `"bundle"` | The full `PreprocessBundle` instance. |

These headers enable future schema migrations or compatibility checks.

### Returns
`String` - absolute path of the file just written.

### Example
```julia
p = save_preprocess_bundle(bund, "artifacts/train_bundle.jld2"; compress = false)
@info "bundle saved to p"
```
"""
function save_preprocess_bundle(bundle::PreprocessBundle,
                                path::AbstractString;
                                format::Symbol = :jld2,
                                compress::Bool = true)

    format == :jld2 || error("Only :jld2 format is currently supported")

    path_abs = abspath(path)
    mkpath(dirname(path_abs))

    jldopen(path_abs, "w"; compress = compress) do jld2_file
        jld2_file["__bundle_version__"] = string(_BUNDLE_VERSION)
        jld2_file["__schema_version__"] = string(bundle.metadata.schema_version)
        jld2_file["bundle"]             = bundle
    end

    return path_abs
end


"""
    load_preprocess_bundle(path; format = :jld2) -> PreprocessBundle

Load a previously-saved [`PreprocessBundle`](@ref) from disk.

The function currently understands the **JLD2** wire-format written by
[`save_preprocess_bundle`](@ref).  It performs a lightweight header check to
ensure the on-disk bundle version is **not newer** than the library version
linked at run-time, helping you avoid silent incompatibilities after package
upgrades.

# Arguments
| name    | type                | description |
|---------|---------------------|-------------|
| `path`  | `AbstractString`    | File name (relative or absolute) pointing to the bundle on disk. |
| `format` | `Symbol` (keyword) | Serialization format.  Only `:jld2` is accepted—any other value raises an error. |

# Returns
`PreprocessBundle` - the exact object originally passed to
`save_preprocess_bundle`, including all levels, alignments, metadata, and
extras.

# Errors
* `ArgumentError` &nbsp;- if `path` does **not** exist.
* `ArgumentError` &nbsp;- if `format ≠ :jld2`.
* `ErrorException` &nbsp;- when the bundle's persisted version is **newer**
  than the library's internal `_BUNDLE_VERSION`, signalling that your local
  code may be too old to read the file safely.

# Example
```julia
bund = load_preprocess_bundle("artifacts/train_bundle.jld2")

@info "levels available: keys(bund.levels))"
```
"""
function load_preprocess_bundle(path::AbstractString; format::Symbol = :jld2)
    
    path = abspath(path)
    format == :jld2 || error("only :jld2 format is currently supported")

    isfile(path) || throw(ArgumentError("File does not exist: $path"))

    jldopen(path, "r") do jld2_file
        stored = VersionNumber(jld2_file["__bundle_version__"])
        if stored > _BUNDLE_VERSION
            error("Bundle version $stored is newer than library $_BUNDLE_VERSION")
        end
        return jld2_file["bundle"]
    end
end


end # module _BundleIO


import ._BundleIO: save_preprocess_bundle, load_preprocess_bundle