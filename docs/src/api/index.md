

```@meta
CurrentModule = KeemenaPreprocessing
```

# Public API

```@autodocs
Modules = [KeemenaPreprocessing]
Private = false   # 'public' == exported (≤ Julia 1.10) :contentReference[oaicite:1]{index=1}
Order   = [:type, :function]
```

## Power-user helpers

```@autodocs
Modules = [KeemenaPreprocessing]
Filter  = name -> name in (:save_preprocess_bundle,
                           :load_preprocess_bundle)
Order   = [:function]
```
