# Support for Julia's allocation profiler, `Profile.Allocs`.
# Implements issues #52 and #70. The allocation profiler hands back already-decoded
# stack traces (rather than instruction pointers), so the tree is built directly
# instead of going through `Profile.tree!`.

# An intermediate tree used while accumulating allocation weights. Identical
# stackframes are merged, keyed by `framekey`.
const AllocKey = Tuple{Symbol,Symbol,Int,Bool}

mutable struct AllocTreeNode
    const sf::StackFrame
    status::UInt8
    weight::Int
    const children::Dict{AllocKey,AllocTreeNode}
end
AllocTreeNode(sf::StackFrame) = AllocTreeNode(sf, UInt8(0), 0, Dict{AllocKey,AllocTreeNode}())

framekey(sf::StackFrame) = (sf.func, sf.file, sf.line, sf.from_c)

# The leaf of each allocation branch names the type of the allocated object.
# `Profile.Allocs` reports unknown types as `Profile.Allocs.UnknownType`; strip
# the module qualifier so the leaf reads simply as `UnknownType`. Type names can
# occasionally be enormous (deeply parametric types, large `NamedTuple`s); keep
# the label bounded, retaining head and tail, so it stays readable in
# `print_tree` and other renderers.
const alloctypename_maxlen = 120

function alloctypename(@nospecialize(T))
    name = replace(string(T), "Profile.Allocs." => "")
    if length(name) > alloctypename_maxlen
        head = alloctypename_maxlen ÷ 2 - 1
        tail = alloctypename_maxlen - head - 1
        name = string(first(name, head), '…', last(name, tail))
    end
    return name
end

"""
    g = flamegraph(allocs::Profile.Allocs.AllocResults; C=false, mode=:bytes, pruned=[], norepl=true, filter=nothing)

Compute a flame graph from data collected by Julia's allocation profiler,
`Profile.Allocs`. Collect the data with `Profile.Allocs.@profile`, then pass the
result of `Profile.Allocs.fetch()`:

```julia
Profile.Allocs.@profile my_computation()
g = flamegraph(Profile.Allocs.fetch())
```

The width of each node measures memory allocation. With `mode=:bytes` (the
default) widths are the number of bytes allocated; with `mode=:count` they are
the number of allocations. The leaf of each branch names the type of the
allocated object.

The keywords `C`, `pruned`, `norepl`, and `filter` behave as in the
time-profiling [`flamegraph`](@ref) method.
"""
function flamegraph(allocs::Profile.Allocs.AllocResults; C::Bool=false, mode::Symbol=:bytes,
        pruned=defaultpruned, norepl::Bool=true, filter=nothing)
    weightfun = if mode === :bytes
        alloc -> Int(alloc.size)
    elseif mode === :count
        alloc -> 1
    else
        error("`mode` must be `:bytes` or `:count`, got ", repr(mode))
    end

    root = AllocTreeNode(StackFrame(Symbol("root"), Symbol(""), 0))
    for alloc in allocs.allocs
        w = weightfun(alloc)
        root.weight += w
        node = root
        pruned_here = false
        # `stacktrace` runs leaf-to-root; reverse it so we descend from the root.
        for sf in Iterators.reverse(alloc.stacktrace)
            if !C && sf.from_c
                # Suppressed C frames still contribute their status to the caller.
                node.status |= status(sf)
                continue
            end
            if ispruned(sf, pruned)
                pruned_here = true
                break
            end
            child = get!(() -> AllocTreeNode(sf), node.children, framekey(sf))
            child.status |= status(sf)
            child.weight += w
            node = child
        end
        pruned_here && continue
        tname = alloctypename(alloc.type)
        leaf = get!(() -> AllocTreeNode(StackFrame(Symbol(tname), Symbol(""), 0)),
                    node.children, (Symbol(tname), Symbol(""), 0, false))
        leaf.weight += w
    end

    if root.weight == 0
        Profile.warning_empty()
        return nothing
    end

    g = Node(NodeData(root.sf, root.status, 1:root.weight))
    flamegraph_allocs!(g, root)
    norepl && prunerepl!(g)
    filter !== nothing && filtergraph!(g, filter)
    return g
end

function flamegraph_allocs!(graph, atn::AllocTreeNode)
    childnodes = collect(values(atn.children))
    isempty(childnodes) && return graph
    # Order siblings as the time-profiling flamegraph does, by location info.
    p = Profile.liperm(StackFrame[c.sf for c in childnodes])
    hstart = first(graph.data.span)
    for i in p
        child = childnodes[i]
        cnode = addchild(graph, NodeData(child.sf, child.status, hstart:hstart+child.weight-1))
        flamegraph_allocs!(cnode, child)
        hstart += child.weight
    end
    return graph
end
