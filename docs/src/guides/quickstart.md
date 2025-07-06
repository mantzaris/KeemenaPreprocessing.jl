

# Quick Start

```julia
using KeemenaPreprocessing
cfg = PreprocessConfiguration(
        language  = "en",
        min_freq  = 3,
        tokenizer_name = :whitespace)

bundle = preprocess_corpus("my_corpus.txt"; config = cfg)
@show bundle.vocab_size
```

See [Configuration](configuration.md) for all keyword options.
