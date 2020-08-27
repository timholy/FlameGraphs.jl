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
    @assert precompile(flametags, (Node{NodeData}, Matrix{RGB{N0f8}}))
    @assert precompile(flamegraph, ())
    if isdefined(Base, :bodyfunction)
        m = which(flamegraph, (Vector{UInt64},))
        f = Base.bodyfunction(m)
        @assert precompile(f, (Dict{UInt64,Vector{Base.StackTraces.StackFrame}}, Bool, Bool, Symbol, Bool, Vector{Tuple{Symbol,Symbol}}, Nothing, typeof(FlameGraphs.flamegraph), Vector{UInt64}))
        m = which(flamepixels, (FlameColors, Node))
        f = Base.bodyfunction(m)
        @assert precompile(f, (Nothing, typeof(flamepixels), FlameColors, Node{NodeData}))
    end
end
VERSION >= v"1.4.2" && _precompile_() # https://github.com/JuliaLang/julia/pull/35378

end # module
