module FlameGraphs

using Profile, LeftChildRightSiblingTrees
using Base.StackTraces: StackFrame
using Profile: StackFrameTree
using Colors, FixedPointNumbers

# AbstractTree interface for StackFrameTree:
using AbstractTrees
AbstractTrees.children(node::StackFrameTree) = node.down
AbstractTrees.printnode(io::IO, node::StackFrameTree) = print(io, node.frame)

export flamegraph, flamepixels, flamesvg

include("graph.jl")
include("render.jl")

end # module
