

module _BundleIO


using JLD2
using ..KeemenaPreprocessing: PreprocessBundle, PreprocessConfiguration


const _BUNDLE_VERSION = v"0.1.0"


"""
    save_preprocess_bundle(bundle, path; format = :jld2, compress = true)

Serialize `bundle::PreprocessBundle` to disk

- `format`: only `:jld2` supported for now
- `compress`: if true, JLD2 uses `compress=true` (gzip); disable for max speed

Returns the absolute path written.
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
        jld2_file["bundle"]             = bundle
    end

    return path_abs
end


"""
    load_preprocess_bundle(path; format = :jld2) -> PreprocessBundle

Read a bundle back from disk.  Throws `ArgumentError` if the on-disk version
is newer than the library knows how to handle.
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
        return jld2_file["bundle"]::PreprocessBundle
    end
end


end # module _BundleIO


import ._BundleIO: save_preprocess_bundle, load_preprocess_bundle