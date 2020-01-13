module FlameGraphs

using Profile, LeftChildRightSiblingTrees
using Base.StackTraces: StackFrame
using Profile: StackFrameTree
using Colors, FixedPointNumbers, IndirectArrays

# AbstractTree interface for StackFrameTree:
using AbstractTrees
AbstractTrees.children(node::StackFrameTree) = node.down
AbstractTrees.printnode(io::IO, node::StackFrameTree) = print(io, node.frame)

export flamegraph, flamepixels, flametags, FlameColors, StackFrameCategory

include("graph.jl")
include("render.jl")
include("sfcategory.jl")

end # module
