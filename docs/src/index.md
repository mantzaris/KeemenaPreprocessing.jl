

# KeemenaPreprocessing.jl  


**Clean → Tokenise/Segment → Bundle**


```julia
using KeemenaPreprocessing
cfg    = PreprocessConfiguration()
bundle = preprocess_corpus("data/alice.txt"; config = cfg)
```

* 👉 See the [Guides](guides/quickstart.md) for worked examples  
* 👉 Full API in the [reference](api/index.md)
