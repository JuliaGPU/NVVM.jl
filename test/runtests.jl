using NVVM, Test

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

@testset "smoke test" begin
    prog = Program()
    add!(prog, dummy_ir)
    verify(prog)
    ptx = compile(prog)
    @test contains(ptx, ".visible .entry kernel")
end

@testset "errors" begin
    prog = Program()
    add!(prog, "wat")

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

    # unofficial ones
    @test contains(compile(prog; isa=v"6.0"), ".version 6.0")
    @test contains(compile(prog; isa=v"6.1"), ".version 6.1")
end

end
