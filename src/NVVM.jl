module NVVM

using CEnum: @cenum

import LLVMDowngrader_jll

# libNVVM comes from the same toolkit as the rest of the CUDA compiler (e.g. `ptxas`), which
# CUDA_Compiler_jll selects, or which is discovered locally when that JLL is configured so
import CUDA_Compiler_jll
const local_toolkit = CUDA_Compiler_jll.host_platform["cuda_local"] == "true"
if local_toolkit
    import CUDA_Runtime_Discovery
    const CUDA_Compiler = CUDA_Runtime_Discovery
else
    const CUDA_Compiler = CUDA_Compiler_jll
end

global libnvvm::String = ""

"""
    NVVM.is_available()

Whether libNVVM is available, i.e., whether a CUDA toolkit was selected or discovered.
"""
is_available() = !isempty(libnvvm)

function check_available()
    is_available() && return
    if local_toolkit
        error("libNVVM is not available: no local CUDA toolkit was discovered.")
    else
        error("""libNVVM is not available: CUDA_Compiler_jll did not select a CUDA toolkit.
                 Without a CUDA driver, select one with its `version` preference.""")
    end
end

include("libnvvm.jl")
include("wrappers.jl")

function __init__()
    if CUDA_Compiler.is_available()
        global libnvvm = CUDA_Compiler.libnvvm
    end
end

end
