module FlameGraphs

using Profile, LeftChildRightSiblingTrees
using Base.StackTraces: StackFrame
using Profile: StackFrameTree
using Colors, FixedPointNumbers, IndirectArrays
using FileIO

# AbstractTree interface for StackFrameTree:
using AbstractTrees
AbstractTrees.children(node::StackFrameTree) = node.down
AbstractTrees.printnode(io::IO, node::StackFrameTree) = print(io, node.frame)

export flamegraph, flamepixels, flametags, FlameColors, StackFrameCategory

include("graph.jl")
include("render.jl")
include("sfcategory.jl")
include("io.jl")

function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(flametags, (Node{NodeData}, Matrix{RGB{N0f8}}))
    precompile(flamegraph, ())
    precompile(NodeData, (StackTraces.StackFrame, UInt8, UnitRange{Int64}))
    if isdefined(Base, :bodyfunction)
        m = which(flamegraph, (Vector{UInt64},))
        f = Base.bodyfunction(m)
        precompile(f, (Dict{UInt64,Vector{Base.StackTraces.StackFrame}}, Bool, Bool, Symbol, Bool, Vector{Tuple{Symbol,Symbol}}, Nothing, Nothing, Nothing, typeof(flamegraph), Vector{UInt64}))
        m = which(flamepixels, (FlameColors, Node))
        f = Base.bodyfunction(m)
        precompile(f, (Nothing, typeof(flamepixels), FlameColors, Node{NodeData}))
    end
end
_precompile_()

end # module
