module FlameGraphsFileIOExt

isdefined(Base, :get_extension) ? (using FileIO) : (using ..FileIO)
using Profile

using FlameGraphs
using FlameGraphs: Node, NodeData

import FlameGraphs: save, load

function save(f::File{format"JLPROF"}, data::AbstractVector{<:Unsigned}, lidict::Profile.LineInfoDict)
    open(f, "w") do s
        save(stream(s), data, lidict)
    end
end

function save(f::File{format"JLPROF"}, g::Node{NodeData})
    open(f, "w") do s
        save(stream(s), g)
    end
end

# Note: this may not work from FileIO because it returns an anonymous function for saving data
save(f::File{format"JLPROF"}) = save(filename(f))


function load(f::File{format"JLPROF"})
    open(f) do s
        skipmagic(s)
        load(s)
    end
end

function load(s::Stream{format"JLPROF"})
    load(stream(s))
end

end # module FlameGraphsFileIOExt
