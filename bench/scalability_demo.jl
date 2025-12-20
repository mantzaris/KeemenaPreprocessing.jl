
using Downloads
using Printf
using Random
using KeemenaPreprocessing

function download_if_missing(url::String, destination_path::String)::String
    if isfile(destination_path)
        return destination_path
    end
    mkpath(dirname(destination_path))
    @info "Downloading" url destination_path
    Downloads.download(url, destination_path)
    return destination_path
end

function build_sharded_corpus!(
    corpus_directory::String;
    base_text_paths::Vector{String},
    target_megabytes::Int = 256,
    shard_megabytes::Int = 4,
)::Vector{String}
    mkpath(corpus_directory)

    # Clean out old shards (optional but avoids mixing runs)
    for filename in readdir(corpus_directory)
        if startswith(filename, "shard_") && endswith(filename, ".txt")
            rm(joinpath(corpus_directory, filename))
        end
    end

    base_texts = String[read(path, String) for path in base_text_paths]
    base_text = join(base_texts, "\n\n")

    target_bytes = Int64(target_megabytes) * 1024^2
    shard_bytes  = Int64(shard_megabytes)  * 1024^2

    bytes_written_total = Int64(0)
    shard_index = 1
    shard_paths = String[]

    current_path = joinpath(corpus_directory, @sprintf("shard_%05d.txt", shard_index))
    current_io = open(current_path, "w")
    push!(shard_paths, current_path)
    bytes_written_current = Int64(0)

    # Write whole copies of base_text to keep valid UTF-8 boundaries.
    while bytes_written_total < target_bytes
        write(current_io, base_text)
        write(current_io, "\n")
        bytes_written_current += sizeof(base_text) + 1
        bytes_written_total   += sizeof(base_text) + 1

        if bytes_written_current >= shard_bytes && bytes_written_total < target_bytes
            close(current_io)
            shard_index += 1
            current_path = joinpath(corpus_directory, @sprintf("shard_%05d.txt", shard_index))
            current_io = open(current_path, "w")
            push!(shard_paths, current_path)
            bytes_written_current = Int64(0)
        end
    end

    close(current_io)

    return shard_paths
end

function format_megabytes(bytes::Integer)::String
    return @sprintf("%.2f", bytes / 1024^2)
end

function run_non_streaming(paths::Vector{String}, configuration::PreprocessConfiguration)
    GC.gc()
    timed = @timed begin
        preprocess_corpus(paths; config = configuration)
    end
    bundle = timed.value
    bundle_size_bytes = Base.summarysize(bundle)
    token_count = length(get_token_ids(bundle, :word))
    return (
        seconds = timed.time,
        allocated_bytes = timed.bytes,
        output_bundle_bytes = bundle_size_bytes,
        total_tokens = token_count,
    )
end

function run_streaming_consumption(paths::Vector{String}, configuration::PreprocessConfiguration; chunk_tokens::Int)
    GC.gc()

    maximum_chunk_bundle_bytes = 0
    total_tokens = 0

    timed = @timed begin
        channel = preprocess_corpus_streaming(paths; cfg = configuration, chunk_tokens = chunk_tokens)

        for chunk_bundle in channel
            maximum_chunk_bundle_bytes = max(maximum_chunk_bundle_bytes, Base.summarysize(chunk_bundle))
            total_tokens += length(get_token_ids(chunk_bundle, :word))

            # Encourage prompt reclamation in long runs
            GC.gc(false)
        end
    end

    return (
        seconds = timed.time,
        allocated_bytes = timed.bytes,
        max_chunk_bundle_bytes = maximum_chunk_bundle_bytes,
        total_tokens = total_tokens,
    )
end

function main()
    Random.seed!(1)

    urls = [
        ("https://www.gutenberg.org/files/11/11-0.txt", "bench/data/alice.txt"),
        ("https://www.gutenberg.org/files/35/35-0.txt", "bench/data/time_machine.txt"),
    ]

    downloaded_paths = String[]
    for (url, local_path) in urls
        push!(downloaded_paths, download_if_missing(url, local_path))
    end

    corpus_directory = "bench/corpus_shards"
    shard_paths = build_sharded_corpus!(
        corpus_directory;
        base_text_paths = downloaded_paths,
        target_megabytes = 256,
        shard_megabytes = 4,
    )

    configuration = PreprocessConfiguration(
        tokenizer_name = :whitespace,
        record_sentence_offsets = true,
        minimum_token_frequency = 2,
    )

    chunk_tokens = 250_000

    @info "Running non-streaming (single bundle)"
    non_streaming = run_non_streaming(shard_paths, configuration)

    @info "Running streaming consumption (channel, discard chunks)"
    streaming = run_streaming_consumption(shard_paths, configuration; chunk_tokens = chunk_tokens)

    println()
    println("## KeemenaPreprocessing scalability demo (indicative)")
    println()
    println("- corpus size:   (sharded files built from 2 Gutenberg texts)")
    println("- tokenizer_name: :whitespace")
    println("- record_sentence_offsets: true")
    println("- chunk_tokens (streaming): $(chunk_tokens)")
    println()
    println("| Scenario | Total tokens | Time (s) | Allocated (MiB) | Bundle size (MiB) |")
    println("|---|---:|---:|---:|---:|")

    println(@sprintf(
        "| preprocess_corpus (single bundle) | %d | %.2f | %s | %s |",
        non_streaming.total_tokens,
        non_streaming.seconds,
        format_megabytes(non_streaming.allocated_bytes),
        format_megabytes(non_streaming.output_bundle_bytes),
    ))

    println(@sprintf(
        "| preprocess_corpus_streaming (consume + discard) | %d | %.2f | %s | %s (max chunk) |",
        streaming.total_tokens,
        streaming.seconds,
        format_megabytes(streaming.allocated_bytes),
        format_megabytes(streaming.max_chunk_bundle_bytes),
    ))

    println()
    println("Note: Bundle sizes are from Base.summarysize (approx). First run includes compilation.")
end

main()
