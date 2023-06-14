# script to parse CUDA headers and generate Julia wrappers

using Clang
using Clang.Generators

using JuliaFormatter

using libNVVM_jll

function wrap(name, headers; targets=headers, defines=[], include_dirs=[])
    args = get_default_args()
    append!(args, map(dir->"-I$dir", include_dirs))
    for define in defines
        if isa(define, Pair)
            append!(args, ["-D", "$(first(define))=$(last(define))"])
        else
            append!(args, ["-D", "$define"])
        end
    end

    # create context
    options = load_options(joinpath(@__DIR__, "wrap.toml"))
    ctx = create_context([headers...], args, options)

    # run generator
    build!(ctx, BUILDSTAGE_NO_PRINTING)

    # only keep the wrapped headers
    # NOTE: normally we'd do this by using `-isystem` instead of `-I` above,
    #       but in the case of CUDA most headers are in a single directory.
    replace!(get_nodes(ctx.dag)) do node
        path = normpath(Clang.get_filename(node.cursor))
        should_wrap = any(targets) do target
            occursin(target, path)
        end
        if !should_wrap
            return ExprNode(node.id, Generators.Skip(), node.cursor, Expr[], node.adj)
        end
        return node
    end

    build!(ctx, BUILDSTAGE_PRINTING_ONLY)

    format_file(options["general"]["output_file_path"], YASStyle())

    return
end

function main(name="all")
    @assert libNVVM_jll.is_available()
    nvvm = joinpath(libNVVM_jll.artifact_dir, "include")
    wrap("nvvm", ["$nvvm/nvvm.h"])
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
