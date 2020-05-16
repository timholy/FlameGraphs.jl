"""
    data = NodeData(sf::StackFrame, status::UInt8, span::UnitRange{Int})

Data associated with a single node in a flamegraph. `sf` is the stack frame
(see `?StackTraces.StackFrame`). `status` is a bitfield with information about this
node or any "suppressed" nodes immediately called by this one:

- `status & 0x01` is nonzero for runtime dispatch
- `status & 0x02` is nonzero for garbage collection

By default, C-language stackframes are omitted, but information about
their identity is accumulated into their caller's `status`.

`length(span)` is the number of times this stackframe was captured at this
depth and location in the flame graph. The starting index begins with the caller's
starting `span` but increments to ensure each child's `span` occupies a distinct
subset of the caller's `span`. Concretely, `span` is the range of indexes
that will be occupied by this stackframe when the flame graph is rendered.
"""
struct NodeData
    sf::StackFrame
    status::UInt8             # a bitfield, see below
    span::UnitRange{Int}
end

# status bitfield values
const runtime_dispatch = UInt8(1)
const gc_event         = UInt8(2)
const repl             = UInt8(4)

const defaultpruned = Tuple{Symbol,Symbol}[]

# This allows Revise to correct the location information in profiles
if VERSION >= v"1.5.0-DEV.9"
    # ref https://github.com/JuliaLang/julia/pull/34235
    lineinfodict(data::Vector{<:Unsigned}) = Profile.getdict(data)
else
    # Use the definition of Profile.getdict from Julia 1.5.0-DEV.9+
    function lineinfodict(data::Vector{<:Unsigned})
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

"""
    g = flamegraph(data=Profile.fetch(); lidict=nothing, C=false, combine=true, recur=:off, norepl=true, pruned=[], filter=nothing)

Compute a graph representing profiling data. To compute it for the currently-collected
profiling information, omit both `data` and `lidict`; if you are computing it for saved
profiling data, supply both. (`data` and `lidict` must be a matched pair from `Profile.retrieve()`.)

You can control the strategy with the following keywords:

- `C`: if `true`, include stackframes collected from `ccall`ed code.
- `recur` (supported on Julia 1.4+): represent recursive calls as if they corresponded to
  iteration.
- `norepl`: if true, the portions of stacktraces deeper than `REPL.eval_user_input` are discarded.
- `pruned`: a list of `(funcname, filename)` pairs that trigger the termination of this branch
  of the flame graph. You can use this to prevent very "tall" graphs from deeply-recursive
  calls, e.g., `pruned = [("sort!", "sort.jl")]` would omit nodes corresponding to Julia's
  `sort!` function and anything called by it. See also `recur` for an alternative strategy.
- `combine`: if true, instruction pointers that correspond to the same line of code are
  combined into a single stackframe
- `filter`: drop all branches that do not satisfy the filter condition. `Condition` can be `string`, `regex`
  or any function, that can be applied to `NodeData`. For example, `filter = "mapslices"` or equivalently
  `filter = x -> (x.sf.func == :mapslices)` removes all branches that do not contain `mapslices` Node as a child
  or ancestor.

`g` can be inspected using [`AbstractTrees.jl`'s](https://github.com/JuliaCollections/AbstractTrees.jl)
`print_tree`.
"""
function flamegraph(data=Profile.fetch(); lidict=nothing, C=false, combine=true,
        recur=:off, norepl=true, pruned=defaultpruned, filter=nothing)
    if lidict === nothing
        lidict = lineinfodict(unique(data))
    end
    data_u64 = convert(Vector{UInt64}, data)
    root = combine ? StackFrameTree{StackFrame}() : StackFrameTree{UInt64}()
    # Build the tree with C=true, regardless of user setting. This is because
    # we need the C frames to set the status flag. They will be omitted by `flamegraph!`
    # as needed.
    if VERSION >= v"1.4.0-DEV.128"
        root = Profile.tree!(root, data_u64, lidict, #= C =# true, recur)
    else
        root = Profile.tree!(root, data_u64, lidict, #= C =# true)
    end
    if isempty(root.down)
        Profile.warning_empty()
        return nothing
    end
    root.count = sum(pr->pr.second.count, root.down)  # root count seems borked
    g = flamegraph!(Node(NodeData(root.frame, status(root, C), 1:root.count)), root; C=C, pruned=pruned)
    if norepl
        prunerepl!(g)
    end

    if filter != nothing
        filtergraph!(g, filter)
    end

    return g
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
    if !sf.from_c && sf.func === :eval_user_input && endswith(String(sf.file), "REPL.jl")
        st |= repl
    end
    return st
end

function nodematches(needle::Union{AbstractString,Regex,AbstractChar}, g::Node)
    return occursin(needle, string(g.data.sf))
end

function nodematches(needle::Function, g::Node)
    return needle(g.data)
end

function canfind(needle, g::Node, memo = Dict{Node, Bool}())
    haskey(memo, g) && return memo[g]
    if nodematches(needle, g)
        memo[g] = true
    else
        memo[g] = any(canfind(needle, child, memo) for child in g)
    end
    return memo[g]
end

function filtergraph!(g::Node, filter, memo = Dict{Node, Bool}())
    if !canfind(filter, g, memo)
        if isroot(g)
            @warn "The filter condition results in the root node pruning, so the filter is ignored"
        else
            prunebranch!(g)
        end
    else
        for child in g
            nodematches(filter, child) && continue
            filtergraph!(child, filter, memo)
        end
    end
end

function flamegraph!(graph, ptree; C=false, pruned=defaultpruned, hstart=first(graph.data.span))
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

function prunerepl!(node)
    for c in node
        if c.data.status & repl != 0
            # Add children directly to the root node
            root = node
            replchild = c
            while !isroot(root)
                root = root.parent
                replchild = replchild.parent
            end
            graftchildren!(root, c)
            # Eliminate all nodes in between. This might include some that don't
            # call REPL code, but as this is also internal it seems OK.
            prunebranch!(replchild)
            return true
        else
            prunerepl!(c) && return true
        end
    end
    return false
end
