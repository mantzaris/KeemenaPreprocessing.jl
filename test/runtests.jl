

using KeemenaPreprocessing
using Test
using StatsBase, Random
using JLD2
using Downloads


include("test_usecases1.jl")

include("test_cleaning.jl")
include("test_types.jl")
include("test_configuration.jl")
include("test_vocabulary.jl")
include("test_tokenization.jl")
include("test_alignment.jl")
include("test_alignment2.jl")
include("test_assemble.jl")
include("test_bundle_io.jl")
include("test_raw_readers.jl")
include("test_pipeline.jl")
include("test_pipeline_streaming.jl")
include("test_preprocessor_state.jl")


