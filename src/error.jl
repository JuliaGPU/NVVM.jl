export NVVMError

struct NVVMError <: Exception
    code::nvvmResult
end

Base.convert(::Type{nvvmResult}, err::NVVMError) = err.code

Base.showerror(io::IO, err::NVVMError) =
    print(io, "NVVMError: ", description(err), " (code $(reinterpret(Int32, err.code)))")

description(err::NVVMError) = unsafe_string(nvvmGetErrorString(err))
