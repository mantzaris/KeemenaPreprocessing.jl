

module _BundleIO


using JLD2
using ..KeemenaPreprocessing: PreprocessBundle, PreprocessConfiguration


const _BUNDLE_VERSION = v"1.0.0"


function save_preprocess_bundle(bundle::PreprocessBundle,
                                path::AbstractString;
                                format::Symbol = :jld2,
                                compress::Bool = true)

    format == :jld2 || error("Only :jld2 format is currently supported")

    path_abs = abspath(path)
    mkpath(dirname(path_abs))

    jldopen(path_abs, "w"; compress = compress) do jld2_file
        jld2_file["__bundle_version__"] = string(_BUNDLE_VERSION)
        jld2_file["__schema_version__"] = string(bundle.pipeline_metadata.schema_version)
        jld2_file["bundle"]             = bundle
    end

    return path_abs
end


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