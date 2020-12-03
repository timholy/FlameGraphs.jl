"""
    save(f::FileIO.File)
    save(f::FileIO.File, data, lidict)
    save(filename::AbstractString, data, ldict)

Save profiling data to a file. If `data` and `lidict` are not supplied, they are obtained
from

    data, lidict = Profile.retrieve()

Note that the data saved to the file discard some system-specific information to allow portability.
Some visualization modes, like [`StackFrameCategory`](@ref), are not available for data loaded from
such files.

These files conventionally have the extension ".jlprof".
If you just supply a string filename ending with this extension,
you must pass `data` and `lidict` explicitly, because
FileIO has its own interpretation of the meaning of `save` with no arguments.

# Example

For this to work, you need to `pkg> add FileIO FlameGraphs`.

```julia
julia> using Profile, FileIO    # you don't even need to explicitly use `FlameGraphs`

julia> @profile mapslices(sum, rand(3,3,3,3), dims=[1,2]);

julia> save("/tmp/myprof.jlprof", Profile.retrieve()...)
```
"""
function save(f::File{format"JLPROF"}, data::AbstractVector{<:Unsigned}, lidict::Profile.LineInfoDict)
    data_u64 = convert(AbstractVector{UInt64}, data)
    open(f, "w") do io
        write(io, magic(format"JLPROF"))
        # Write an endianness revealer
        write(io, 0x01020304)
        # Write an indicator that this is data/lidict format
        write(io, 0x01)
        write(io, Int64(length(data_u64)))
        write(io, data_u64)
        write(io, Int64(length(lidict)))
        for (k, v) in lidict
            write(io, k)
            write(io, Int32(length(v)))
            for sf in v
                symwrite(io, sf.func)
                symwrite(io, sf.file)
                write(io, sf.line)
                write(io, sf.from_c)
                write(io, sf.inlined)
            end
        end
    end
    return nothing
end

# Note: this doesn't work from FileIO because it returns an anonymous function for saving data
save(f::File{format"JLPROF"}) = save(f, Profile.retrieve()...)

"""
    data, lidict = load(f::FileIO.File)
    data, lidict = load(filename::AbstractString)

Load profiling data. You can reconstruct the flame graph from `flamegraph(data; lidict=lidict)`.
"""
function load(f::File{format"JLPROF"})
    open(f) do io
        skipmagic(io)
        load(io)
    end
end

function load(io::Stream{format"JLPROF"})
    endian = read(io, UInt32)
    endian == 0x01020304 || error("bswap not yet supported, please report as an issue to FlameGraphs.jl")
    fmt = read(io, UInt8)
    if fmt == 0x01
        # This is data/lidict format
        n = read(io, Int64)
        data = Vector{UInt64}(undef, n)
        read!(io, data)
        n = read(io, Int64)
        lidict = Profile.LineInfoDict()
        for i = 1:n
            k = read(io, UInt64)
            nsf = read(io, Int32)
            sfs = StackFrame[]
            for j = 1:nsf
                func    = symread(io)
                file    = symread(io)
                line    = read(io, Int)
                from_c  = read(io, Bool)
                inlined = read(io, Bool)
                push!(sfs, StackFrame(func, file, line, nothing, from_c, inlined, 0x0))
            end
            lidict[k] = sfs
        end
        return data, lidict
    end
    error("format ", fmt, " not recognized")
end

function symwrite(io, sym::Symbol)
    str = string(sym)
    write(io, Int32(ncodeunits(str)))
    write(io, str)
end

function symread(io)
    n = read(io, Int32)
    b = read(io, n)
    return Symbol(String(b))
end
