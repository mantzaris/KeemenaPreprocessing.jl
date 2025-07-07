

using KeemenaPreprocessing
using Documenter


DocMeta.setdocmeta!(KeemenaPreprocessing, :DocTestSetup, :(using KeemenaPreprocessing); recursive=true)


makedocs(
    modules   = [KeemenaPreprocessing],
    sitename  = "KeemenaPreprocessing.jl",
    authors   = "Alexander V. Mantzaris",
    format    = Documenter.HTML(;
                  canonical = "https://mantzaris.github.io/KeemenaPreprocessing.jl",
                  edit_link = "main"),
    checkdocs = :exports,              # complain only for *exported* names :contentReference[oaicite:0]{index=0}
    pages = [
        "Home"          => "index.md",
        "Guides"        => [
            "Quick Start"        => "guides/quickstart.md",
            "Configuration"      => "guides/configuration.md",
            "Streaming Pipeline" => "guides/streaming.md",
            "Alignment"          => "guides/alignment.md",
            "Levels"             => "guides/levels.md",
            "Offsets"            => "guides/offsets.md"
        ],
        "API Reference" => "api/index.md",
    ],
)


deploydocs(repo      = "github.com/mantzaris/KeemenaPreprocessing.jl",
           devbranch = "main")


# makedocs(;
#     modules=[KeemenaPreprocessing],
#     authors="Alexander V. Mantzaris",
#     sitename="KeemenaPreprocessing.jl",
#     format=Documenter.HTML(;
#         canonical="https://mantzaris.github.io/KeemenaPreprocessing.jl",
#         edit_link="main",
#         assets=String[],
#     ),
#     pages=[
#         "Home" => "index.md",
#     ],
# )

# deploydocs(;
#     repo="github.com/mantzaris/KeemenaPreprocessing.jl",
#     devbranch="main",
# )
