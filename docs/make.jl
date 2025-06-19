using KeemenaPreprocessing
using Documenter

DocMeta.setdocmeta!(KeemenaPreprocessing, :DocTestSetup, :(using KeemenaPreprocessing); recursive=true)

makedocs(;
    modules=[KeemenaPreprocessing],
    authors="Alexander V. Mantzaris",
    sitename="KeemenaPreprocessing.jl",
    format=Documenter.HTML(;
        canonical="https://mantzaris.github.io/KeemenaPreprocessing.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mantzaris/KeemenaPreprocessing.jl",
    devbranch="main",
)
