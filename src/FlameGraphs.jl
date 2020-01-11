module FlameGraphs

using Profile, LeftChildRightSiblingTrees
using Base.StackTraces: StackFrame
using Profile: StackFrameTree

# AbstractTree interface for StackFrameTree:
using AbstractTrees
AbstractTrees.children(node::StackFrameTree) = node.down
AbstractTrees.printnode(io::IO, node::StackFrameTree) = print(io, node.frame)

export flamegraph

struct NodeData
    sf::StackFrame
    status::UInt8             # a bitfield, see below
    hspan::UnitRange{Int}
end

# status bitfield values
const runtime_dispatch = UInt8(1)
const gc_event         = UInt8(2)

const unpruned = []

# This allows Revise to correct the location information in profiles
if VERSION >= v"1.5.0-DEV.9"
    # ref https://github.com/JuliaLang/julia/pull/34235
    lineinfodict(data::Vector{UInt64}) = Profile.getdict(data)
else
    # Use the definition of Profile.getdict from Julia 1.5.0-DEV.9+
    function lineinfodict(data::Vector{UInt64})
        # Lookup is expensive, so do it only once per ip.
        udata = unique(data)
        dict = Profile.LineInfoDict()
        for ip in udata
            st = Profile.lookup(convert(Ptr{Cvoid}, ip))
            # To correct line numbers for moving code, put it in the form expected by
            # Base.update_stackframes_callback[]
            stn = map(x->(x, 1), st)
            try Base.invokelatest(Base.update_stackframes_callback[], stn) catch end
            dict[UInt64(ip)] = map(first, stn)
        end
        return dict
    end
end

"""
    lidict = lineinfodict(uips)

Look up location information for each instruction pointer in `uips`.
This is a `Dict(UInt64=>Vector{StackFrame})`, where the `UInt64` is the instruction pointer.
The reason a single instruction pointer gives a `Vector{StackFrame}` is because
of inlining; the first entry corresponds to the instruction that actually ran,
and the later entries correspond to the call chain.

See also [`unique_ips`](@ref).
"""
lineinfodict(s::Set) = lineinfodict(collect(s))

function flamegraph(data = Profile.fetch(); lidict=nothing, C=false, combine=true, recur=:off, pruned=unpruned)
    if lidict === nothing
        lidict = lineinfodict(unique(data))
    end
    root = combine ? StackFrameTree{StackFrame}() : StackFrameTree{UInt64}()
    # Build the tree with C=true, regardless of user setting. This is because
    # we need the C frames to set the status flag. They will be omitted by `flamegraph!`
    # as needed.
    if VERSION >= v"1.4.0-DEV.128"
        root = Profile.tree!(root, data, lidict, #= C =# true, recur)
    else
        root = Profile.tree!(root, data, lidict, #= C =# true)
    end
    if isempty(root.down)
        Profile.warning_empty()
        return nothing
    end
    root.count = sum(pr->pr.second.count, root.down)  # root count seems borked
    return flamegraph!(Node(NodeData(root.frame, status(root, C), 1:root.count)), root; C=C, pruned=pruned)
end

function status(node, C::Bool)
    st = status(node.frame)
    C && return st
    # If we're suppressing C frames, check all C-frame children
    for child in values(node.down)
        child.frame.from_c || continue
        st |= status(child, C)
    end
    return st
end

function status(sf::StackFrame)
    st = UInt8(0)
    if sf.from_c && (sf.func === :jl_invoke || sf.func === :jl_apply_generic)
        st |= runtime_dispatch
    end
    if sf.from_c && startswith(String(sf.func), "jl_gc_")
        st |= gc_event
    end
    return st
end

function flamegraph!(graph, ptree; C=false, pruned=unpruned, hstart=first(graph.data.hspan))
    nexts = collect(values(ptree.down))
    lilist = collect(frame.frame for frame in nexts)
    p = Profile.liperm(lilist)
    for i in p
        down = nexts[i]
        frame, count = down.frame, down.count
        ispruned(frame, pruned) && continue
        if !C && frame.from_c
            flamegraph!(graph, down; C=C, pruned=pruned, hstart=hstart)
        else
            child = addchild(graph, NodeData(frame, status(down, C), hstart:hstart+count-1))
            flamegraph!(child, down; C=C, pruned=pruned)
        end
        hstart += count
    end
    return graph
end

function ispruned(frame, (fname, file)::Tuple{Any,Any})
    return frame.func == Symbol(fname) && frame.file == Symbol(file)
end

ispruned(frame, pruned) = any(t->ispruned(frame, t), pruned)

end # module
