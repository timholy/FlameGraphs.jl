"""
    data = NodeDiffData(sf::StackFrame, status::UInt8, span::UnitRange{Int}, delta::Int)

Data associated with a single node in a differential flamegraph. `sf` is the stack frame
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

`delta` is difference between `target` and `baseline` span length. If there is no similar node
in baseline flamegraph, then it equals zero.
"""
struct NodeDiffData
    sf::StackFrame
    status::UInt8             # a bitfield, see below
    span::UnitRange{Int}
    delta::Int
end

NodeDiffData(node::Node{NodeData}) = NodeDiffData(node.data.sf, node.data.status, node.data.span, 0)
NodeDiffData(node1::Node{NodeData}, node2::Node{NodeData}) = NodeDiffData(node1.data.sf, node1.data.status, node1.data.span, delta(node1, node2))
span(node::Node) = length(node.data.span)
delta(node1::Node, node2::Node) = span(node1) - span(node2)
sf(node::Node) = string(node.data.sf)

"""
    LCS{T}(v::Vector{Tuple{T, T}}, l:Int)

Struct which holds common sequence of two sequences. Each tuple in `v` contains common elements from first and second
sequence correspondingly. `l` is the length of the `LCS`, which is constructed as the sum of length of
common nodes and lengths of wildcard nodes (look also definition of the `lcs` function).
"""
struct LCS{T}
    v::Vector{Tuple{T, T}}
    l::Int
end

LCS(t::Tuple{T, T}, l::Int) where T = LCS{T}([t], l)
Base.:isless(seq1::LCS, seq2::LCS) = seq1.l < seq2.l
Base.:(*)(seq1::LCS{T}, seq2::LCS{T}) where T = LCS{T}(vcat(seq1.v, seq2.v), seq1.l + seq2.l)

"""
    lcs(node1::Node, node2::Node, eq::Function, is_wildcard::Function, memo)

For two given nodes, `lcs` greedily constructs longest common sequence of their siblings. Siblings are divided
into two categories, common nodes which are compared with the help of `eq` function and
`wildcard` nodes, defined by function `is_wildcard`. `Wildcard` nodes are compared by the length
of the longest common sequence of their children, so length of the common sequence is defined by
the sum of the count of equal common nodes and lcs of the wildcard nodes.
"""
function lcs(node1::T, node2::T,
    eq = (x, y) -> x == y, is_wildcard = x -> false,
    memo = Dict{Tuple{T, T}, LCS{T}}()) where {T <: Node}

    init = (node1, node2)
    init in keys(memo) && return memo[init]

    if (!is_wildcard(node1) && !is_wildcard(node2) && !eq(node1, node2)) ||
            (!is_wildcard(node1) && is_wildcard(node2)) ||
            (is_wildcard(node1) && !is_wildcard(node2))

        seq1 = islastsibling(node2) ? LCS{T}([], 0) : lcs(node1, node2.sibling, eq, is_wildcard, memo)
        seq2 = islastsibling(node1) ? LCS{T}([], 0) : lcs(node1.sibling, node2, eq, is_wildcard, memo)
        memo[init] = max(seq1, seq2)
   elseif !is_wildcard(node1) && !is_wildcard(node2) && eq(node1, node2)
       if islastsibling(node1) || islastsibling(node2)
           memo[init] = LCS((node1, node2), 1)
       else
           memo[init] = LCS((node1, node2), 1) * lcs(node1.sibling, node2.sibling, eq, is_wildcard, memo)
       end
   else
       seq1 = islastsibling(node2) ? LCS{T}([], 0) : lcs(node1, node2.sibling, eq, is_wildcard, memo)
       seq2 = islastsibling(node1) ? LCS{T}([], 0) : lcs(node1.sibling, node2, eq, is_wildcard, memo)

       seq3 = if isleaf(node1) || isleaf(node2)
                  LCS((node1, node2), 1)
              else
                  subseq3 = lcs(node1.child, node2.child, eq, is_wildcard, memo)
                  LCS((node1, node2), subseq3.l + 1)
              end
       seq4 = islastsibling(node1) || islastsibling(node2) ? LCS{T}([], 0) : lcs(node1.sibling, node2.sibling, eq, is_wildcard, memo)

       memo[init] = max(seq3*seq4, seq1, seq2)
   end

   return memo[init]
end

# sometimes root node has random narrow branches, in order to compare
# profiles it's easier to remove this spurious branches
function simplify!(node::Node)
    children = collect(node)
    sort!(children, by = x -> length(x.data.span), rev = true)
    for i in 2:length(children)
        prunebranch!(children[i])
    end

    node
end

function diffflamegraph(target::Node, baseline::Node; negate = false, simplify = true)
    if negate
        target, baseline = baseline, target
    end

    if simplify
        simplify!(target)
        simplify!(baseline)
    end

    graph = Node(NodeDiffData(target, baseline))
    diffflamegraph!(graph, target, baseline)
end

function diffflamegraph!(diffnode::Node{NodeDiffData}, target::Node{NodeData}, baseline::Node{NodeData})
    if target === baseline
        for child in target
            diffchild = addchild(diffnode, NodeDiffData(child))
            diffflamegraph!(diffchild, child, child)
        end
    else
        seq = lcs(target.child, baseline.child, (x, y) -> sf(x) == sf(y), x -> occursin(r"\[\d+\]:\d+$", sf(x)))
        seq = Dict(seq.v)
        for child in target
            diffchild = addchild(diffnode, NodeDiffData(child, get(seq, child, child)))
            diffflamegraph!(diffchild, child, get(seq, child, child))
        end
    end

    diffnode
end
