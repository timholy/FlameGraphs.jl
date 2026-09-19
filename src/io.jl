const JLPROF_MAGIC = UInt8.(b"JLPROF\x01\x00")

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
function save(filename::AbstractString, data::AbstractVector{<:Unsigned}, lidict::Profile.LineInfoDict)
    open(filename, "w") do io
        save(io, data, lidict)
    end
end

function save(io::IO, data::AbstractVector{<:Unsigned}, lidict::Profile.LineInfoDict)
    data_u64 = convert(AbstractVector{UInt64}, data)
    write(io, JLPROF_MAGIC)
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
            sfwrite(io, sf)
        end
    end
    return nothing
end

function save(filename::AbstractString, g::Node{NodeData})
    open(filename, "w") do io
        save(io, g)
    end
end

function save(io::IO, g::Node{NodeData})
    queue = Union{Nothing,typeof(g)}[]
    write(io, JLPROF_MAGIC)
    # Write an endianness revealer
    write(io, 0x01020304)
    # Write an indicator that this is node format
    write(io, 0x02)
    push!(queue, g)
    savedfs!(io, queue)
    return nothing
end

function savedfs!(io, queue)
    isempty(queue) && return nothing
    node = pop!(queue)
    if node === nothing
        write(io, 0x00)    # leaf-terminator
    else
        write(io, 0xff)   # node
        data = node.data
        sfwrite(io, data.sf)
        write(io, data.status)
        write(io, data.span.start)
        write(io, data.span.stop)
        push!(queue, nothing)
        for child in reverse(collect(node))
            push!(queue, child)
        end
    end
    savedfs!(io, queue)
    return nothing
end

save(filename::AbstractString) = save(filename, Profile.retrieve()...)

"""
    data, lidict = load(f::FileIO.File)
    data, lidict = load(filename::AbstractString)
    g = load(...)

Load profiling data. You can reconstruct the flame graph from `flamegraph(data; lidict=lidict)`.
Some files may already store the data in graph format, and return a single argument `g`.
"""
function load(filename::AbstractString)
    open(load, filename)
end


function load(io::IO)
    b0 = peek(io)
    if b0 === JLPROF_MAGIC[1]
        magic = read(io, length(JLPROF_MAGIC))
        magic == JLPROF_MAGIC || error("invalid magic")
    end
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
    if fmt == 0x02
        tag = read(io, UInt8)
        tag == 0xff || error("first entry must be a node")
        sf = sfread(io)
        status = read(io, UInt8)
        start, stop = read(io, Int), read(io, Int)
        span = start:stop
        root = Node(NodeData(sf, status, span))
        loadbfs!(io, root)
        return root
    end
    error("format ", fmt, " not recognized")
end

function loadbfs!(io, parent)
    eof(io) && return nothing
    tag = read(io, UInt8)
    tag == 0x00 && return loadbfs!(io, parent.parent)
    tag == 0xff || error("expected leaf-terminator or node, got $tag")
    sf = sfread(io)
    status = read(io, UInt8)
    start, stop = read(io, Int), read(io, Int)
    span = start:stop
    child_data = NodeData(sf, status, span)
    child = addchild(parent, child_data)
    loadbfs!(io, child)
    return nothing
end

function sfwrite(io, sf::StackFrame)
    symwrite(io, sf.func)
    symwrite(io, sf.file)
    write(io, sf.line)
    write(io, sf.from_c)
    write(io, sf.inlined)
    return nothing
end

function sfread(io)
    func    = symread(io)
    file    = symread(io)
    line    = read(io, Int)
    from_c  = read(io, Bool)
    inlined = read(io, Bool)
    return StackFrame(func, file, line, nothing, from_c, inlined, 0x0)
end

function symwrite(io, sym::Symbol)
    str = string(sym)
    write(io, Int32(ncodeunits(str)))
    write(io, str)
    return nothing
end

function symread(io)
    n = read(io, Int32)
    b = read(io, n)
    return Symbol(String(b))
end
