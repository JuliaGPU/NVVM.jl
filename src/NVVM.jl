module NVVM

using libNVVM_jll

using CEnum: @cenum

using LLVMDowngrader_jll

include("libnvvm.jl")
include("wrappers.jl")

end
