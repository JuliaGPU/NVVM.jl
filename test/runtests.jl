using NVVM, Test
import LLVM

@testset "NVVM" begin

ir_header = """
    target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-i128:128:128-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"
    target triple = "nvptx64-nvidia-cuda"
    """

dummy_ir = """
    $ir_header

    define void @kernel() {
    entry:
        ret void
    }

    !nvvm.annotations = !{!0}
    !0 = !{void ()* @kernel, !"kernel", i32 1}

    !nvvmir.version = !{!1}
    !1 = !{i32 2, i32 0}"""

dummy_bitcode = LLVM.Context() do ctx
    mod = parse(LLVM.Module, dummy_ir)
    convert(Vector{UInt8}, mod)
end

@testset "smoke test" begin
    let prog = Program()
        add!(prog, dummy_ir)
        verify(prog)
        ptx = compile(prog)
        @test contains(ptx, ".visible .entry kernel")
    end

    # bitcode from LLVM.jl needs the current reader, which Blackwell uses by default
    let prog = Program()
        add!(prog, dummy_bitcode)
        verify(prog; arch=v"10.0")
        ptx = compile(prog; arch=v"10.0")
        @test contains(ptx, ".visible .entry kernel")
    end
    let prog = Program()
        add!(prog, dummy_bitcode)
        verify(prog; arch=v"9.0", nvvm_latest=true)
        ptx = compile(prog; arch=v"9.0", nvvm_latest=true)
        @test contains(ptx, ".visible .entry kernel")
    end

    # ... or to be downgraded
    let prog = Program()
        add!(prog, dummy_bitcode; downgrade=true)
        verify(prog; arch=v"7.5")
        ptx = compile(prog; arch=v"7.5")
        @test contains(ptx, ".visible .entry kernel")
    end

    # current IR, with opaque pointers and the PTX kernel calling convention
    let prog = Program()
        add!(prog, """
            $ir_header
            define ptx_kernel void @kernel(ptr addrspace(1) %out, i64 %i) {
                %p = getelementptr inbounds float, ptr addrspace(1) %out, i64 %i
                %v = load float, ptr addrspace(1) %p
                %w = call float @llvm.fma.f32(float %v, float 2.0, float 1.0)
                store float %w, ptr addrspace(1) %p
                ret void
            }
            declare float @llvm.fma.f32(float, float, float)
            !nvvmir.version = !{!0}
            !0 = !{i32 2, i32 0}""")
        ptx = String(compile(prog; arch=v"7.5"))
        @test contains(ptx, ".visible .entry kernel")
        @test contains(ptx, "fma.rn.f32")
    end

    # downgraded textual IR is bitcode, so it can be added lazily
    let prog = Program()
        add!(prog, dummy_ir)
        add!(prog, "$ir_header\ndefine void @unused() {\n  ret void\n}"; lazy=true)
        ptx = compile(prog)
        @test contains(ptx, ".visible .entry kernel")
        @test !contains(ptx, "unused")
    end
end

@testset "errors" begin
    @test_throws ArgumentError add!(Program(), dummy_ir; lazy=true, downgrade=false)
    @test_throws "Failed to downgrade IR" add!(Program(), "wat")

    prog = Program()
    add!(prog, "wat"; downgrade=false)

    @test_throws NVVMError verify(prog)
    try
        verify(prog)
    catch err
        @test NVVM.description(err) == "NVVM_ERROR_INVALID_IR"
        @test contains(NVVM.details(err), "parse expected top-level entity")
    end

    @test_throws NVVMError compile(prog)
    try
        compile(prog)
    catch err
        @test NVVM.description(err) == "NVVM_ERROR_COMPILATION"
        @test contains(NVVM.details(err), "parse expected top-level entity")
    end
end

@testset "options" begin
    prog = Program()
    add!(prog, dummy_ir)

    @test contains(compile(prog; arch=v"8.0"), ".target sm_80")
    @test contains(compile(prog; arch=v"9.0"), ".target sm_90")
    compile(prog; debug=true)
    compile(prog; opt=0)
    compile(prog; ftz=false)
    compile(prog; prec_sqrt=true)

    @test contains(compile(prog, ["-arch=compute_90"]), ".target sm_90")
    compile(prog; generate_line_info=true)

    # unofficial ones
    @test contains(compile(prog; isa=v"6.0"), ".version 6.0")
    @test contains(compile(prog; isa=v"6.1"), ".version 6.1")
end

end
