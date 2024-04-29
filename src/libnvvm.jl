using CEnum

@cenum nvvmResult::UInt32 begin
    NVVM_SUCCESS = 0
    NVVM_ERROR_OUT_OF_MEMORY = 1
    NVVM_ERROR_PROGRAM_CREATION_FAILURE = 2
    NVVM_ERROR_IR_VERSION_MISMATCH = 3
    NVVM_ERROR_INVALID_INPUT = 4
    NVVM_ERROR_INVALID_PROGRAM = 5
    NVVM_ERROR_INVALID_IR = 6
    NVVM_ERROR_INVALID_OPTION = 7
    NVVM_ERROR_NO_MODULE_IN_PROGRAM = 8
    NVVM_ERROR_COMPILATION = 9
end

function nvvmGetErrorString(result)
    @ccall libnvvm.nvvmGetErrorString(result::nvvmResult)::Ptr{Cchar}
end

function nvvmVersion(major, minor)
    @ccall libnvvm.nvvmVersion(major::Ptr{Cint}, minor::Ptr{Cint})::nvvmResult
end

function nvvmIRVersion(majorIR, minorIR, majorDbg, minorDbg)
    @ccall libnvvm.nvvmIRVersion(majorIR::Ptr{Cint}, minorIR::Ptr{Cint},
                                 majorDbg::Ptr{Cint}, minorDbg::Ptr{Cint})::nvvmResult
end

mutable struct _nvvmProgram end

const nvvmProgram = Ptr{_nvvmProgram}

function nvvmCreateProgram(prog)
    @ccall libnvvm.nvvmCreateProgram(prog::Ptr{nvvmProgram})::nvvmResult
end

function nvvmDestroyProgram(prog)
    @ccall libnvvm.nvvmDestroyProgram(prog::Ptr{nvvmProgram})::nvvmResult
end

function nvvmAddModuleToProgram(prog, buffer, size, name)
    @ccall libnvvm.nvvmAddModuleToProgram(prog::nvvmProgram, buffer::Ptr{Cchar},
                                          size::Csize_t, name::Ptr{Cchar})::nvvmResult
end

function nvvmLazyAddModuleToProgram(prog, buffer, size, name)
    @ccall libnvvm.nvvmLazyAddModuleToProgram(prog::nvvmProgram, buffer::Ptr{Cchar},
                                              size::Csize_t, name::Ptr{Cchar})::nvvmResult
end

function nvvmCompileProgram(prog, numOptions, options)
    @ccall libnvvm.nvvmCompileProgram(prog::nvvmProgram, numOptions::Cint,
                                      options::Ptr{Ptr{Cchar}})::nvvmResult
end

function nvvmVerifyProgram(prog, numOptions, options)
    @ccall libnvvm.nvvmVerifyProgram(prog::nvvmProgram, numOptions::Cint,
                                     options::Ptr{Ptr{Cchar}})::nvvmResult
end

function nvvmGetCompiledResultSize(prog, bufferSizeRet)
    @ccall libnvvm.nvvmGetCompiledResultSize(prog::nvvmProgram,
                                             bufferSizeRet::Ptr{Csize_t})::nvvmResult
end

function nvvmGetCompiledResult(prog, buffer)
    @ccall libnvvm.nvvmGetCompiledResult(prog::nvvmProgram, buffer::Ptr{Cchar})::nvvmResult
end

function nvvmGetProgramLogSize(prog, bufferSizeRet)
    @ccall libnvvm.nvvmGetProgramLogSize(prog::nvvmProgram,
                                         bufferSizeRet::Ptr{Csize_t})::nvvmResult
end

function nvvmGetProgramLog(prog, buffer)
    @ccall libnvvm.nvvmGetProgramLog(prog::nvvmProgram, buffer::Ptr{Cchar})::nvvmResult
end
