## error hanlding

export NVVMError

struct NVVMError <: Exception
    code::nvvmResult
    details::Union{Nothing,AbstractString}
end

Base.convert(::Type{nvvmResult}, err::NVVMError) = err.code

function Base.showerror(io::IO, err::NVVMError)
    print(io, "NVVMError: ", description(err), " (code $(reinterpret(Int32, err.code)))")
    if err.details !== nothing
        print(io, "\n", err.details)
    end
end

description(err::NVVMError) = unsafe_string(nvvmGetErrorString(err))
details(err::NVVMError) = err.details

# check an API call
function check(res)
    if res != NVVM_SUCCESS
        throw(NVVMError(res, nothing))
    end
    return
end
# ... with the option to get additional details on what went wrong (i.e. fetch the log)
function check(get_details, res)
    if res != NVVM_SUCCESS
        throw(NVVMError(res, get_details(res)))
    end
    return
end


## general

function version()
    major = Ref{Cint}()
    minor = Ref{Cint}()
    check(nvvmVersion(major, minor))
    return VersionNumber(major[], minor[])
end

function ir_version()
    majorIR = Ref{Cint}()
    minorIR = Ref{Cint}()
    majorDbg = Ref{Cint}()
    minorDbg = Ref{Cint}()
    check(nvvmIRVersion(majorIR, minorIR, majorDbg, minorDbg))
    return (ir=VersionNumber(majorIR[], minorIR[]),
            dbg=VersionNumber(majorDbg[], minorDbg[]))
end


## compilation

export Program, add!, verify, compile

"""
    Program()

Create a new program.
"""
mutable struct Program
    handle::nvvmProgram

    function Program()
        handle_ref = Ref{nvvmProgram}()
        check(nvvmCreateProgram(handle_ref))
        obj = new(handle_ref[])
        finalizer(unsafe_destroy!, obj)
        return obj
    end
end

Base.unsafe_convert(::Type{nvvmProgram}, prog::Program) = prog.handle

function unsafe_destroy!(prog::Program)
    GC.@preserve prog begin
        check(nvvmDestroyProgram(Ref(prog.handle)))
    end
end

function downgrade_ir(ir::String, version::VersionNumber)
    input_io = Pipe()
    output_io = Pipe()
    error_io = Pipe()

    cmd = `$(llvm_as()) --bitcode-version=$(version.major).$(version.minor) -o -`
    proc = run(pipeline(cmd, stdout=output_io, stderr=error_io, stdin=input_io); wait=false)
    close(output_io.in)
    close(error_io.in)

    writer = @async begin
        write(input_io, ir)
        close(input_io)
    end
    output_reader = @async read(output_io)

    if !success(proc)
        error_reader = @async read(error_io, String)
        errors = fetch(error_reader)
        error("Failed to downgrade IR:\n$(errors)")
    end
    fetch(output_reader)
end

"""
    add!(prog::Program, ir::String,         [name]; lazy=false, downgrade=true)
    add!(prog::Program, bitcode::Vector,    [name]; lazy=false)

Add IR to the NVVM program `prog`. The module can be provided as a string containing textual
IR, or a byte vector containing bitcode. If `name` is specified, it will be used as the name
of the module. If `lazy` is set, only symbols that are required by non-lazy modules will be
included in the linked IR program. If `downgrade` is set, the IR will be downgraded to an
appropriate version before being added.
"""
add!

function add!(prog::Program, ir::String, name=nothing; lazy::Bool=false, downgrade::Bool=true)
    api = lazy ? nvvmLazyAddModuleToProgram : nvvmAddModuleToProgram

    # downgrade the module to NVVM IR
    if downgrade
        bitcode = downgrade_ir(ir, v"7.0")
        api(prog, bitcode, sizeof(bitcode), something(name, C_NULL))
    else
        api(prog, ir, sizeof(ir), something(name, C_NULL))
    end
end
function add!(prog::Program, bitcode::Vector, name=nothing; lazy::Bool=false)
    api = lazy ? nvvmLazyAddModuleToProgram : nvvmAddModuleToProgram
    api(prog, bitcode, sizeof(bitcode), something(name, C_NULL))
end

# support specifying compiler options in a more user-friendly manner
function kwargs_to_options(kwargs)
    options = String[]
    for (k, v) in kwargs
        # -g doesn't take a 1/0
        if k in (:debug, :g)
            v && push!(options, "-g")
            continue
        end

        # -isa is not supported and bypasses the official API
        if k == :isa
            for phase in ("opt", "llc")
                # XXX: also lnk on libNVVM from CUDA 12.4
                push!(options, "-X$phase", "-mattr=+ptx$(v.major)$(v.minor)")
            end
            continue
        end

        # support version numbers for specifying the compute architecture
        if k == :arch && v isa VersionNumber
            v = "compute_$(v.major)$(v.minor)"
        end

        # support booleans
        if v isa Bool
            v = v ? "1" : "0"
        end

        # replace underscores with dashes
        k = replace(String(k), "_" => "-")

        push!(options, "-$(k)=$(v)")
    end
    return options
end

"""
    verify(prog::Program; kwargs...)

Verify the NVVM program.

The same compiler options as for [`compile`](@ref) are supported.
"""
function verify(prog::Program; kwargs...)
    options = kwargs_to_options(kwargs)
    check(nvvmVerifyProgram(prog, length(options), options)) do _
        log(prog)
    end
end

"""
    compile(prog::Program; kwargs...)

Link and compile all NVVM IR modules added to the NVVM program `prog` to PTX code.
The target datalayout in the linked IR program is used to determine the address size.

The following compiler options are supported by NVVM
- `debug` or `g`: whether to enable debug information
- `opt`: the optimization level to use
- `arch`: the compute architecture to target, e.g. `compute_75` or `v"7.5"`
- `ftz`: flush denormal values to zero
- `prec_sqrt`: whether to use use IEEE round-to-nearest sqrt, or an approximation
- `prec_div`: whether to use IEEE round-to-nearest division, or an approximation
- `fma`: enable FMA contraction

The following options are not officially supported by NVVM:
- `isa`: which PTX instruction set to use, e.g., `v"6.1"`
"""
function compile(prog::Program; kwargs...)
    options = kwargs_to_options(kwargs)
    check(nvvmCompileProgram(prog, length(options), options)) do _
        log(prog)
    end

    # get result
    result_size = Ref{Csize_t}()
    check(nvvmGetCompiledResultSize(prog, result_size))
    result = Vector{UInt8}(undef, result_size[])
    GC.@preserve result begin
        check(nvvmGetCompiledResult(prog, pointer(result)))
        unsafe_string(pointer(result))
    end
end

function log(prog::Program)
    log_size = Ref{Csize_t}()
    check(nvvmGetProgramLogSize(prog, log_size))
    log = Vector{UInt8}(undef, log_size[])
    GC.@preserve log begin
        check(nvvmGetProgramLog(prog, pointer(log)))
        unsafe_string(pointer(log))
    end
end
