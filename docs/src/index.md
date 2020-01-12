# FlameGraphs.jl

FlameGraphs is a package that adds functionality to Julia's `Profile` standard library. It is directed at the algorithmic side of producing [flame graphs](http://www.brendangregg.com/flamegraphs.html), but includes some "format agnostic" rendering code.
FlameGraphs is used by visualization packages like [ProfileView](https://github.com/timholy/ProfileView.jl) and
[ProfileSVG](https://github.com/timholy/ProfileSVG.jl).

## Computing a flame graph

The core function of FlameGraphs is to compute a tree representation of a set of backtraces collected by Julia's [sampling profiler](https://docs.julialang.org/en/latest/manual/profile/). For a demonstration we'll use the following function:

```julia
function profile_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = maximum(A)
        Am = mapslices(sum, A; dims=2)
        B = A[:,:,5]
        Bsort = mapslices(sort, B; dims=1)
        b = rand(100)
        C = B.*b
    end
end

julia> profile_test(1)              # run once to compile

julia> @profile profile_test(10)    # collect profiling data

julia> using FlameGraphs

julia> g = flamegraph()
Node(FlameGraphs.NodeData(ip:0x0, 0x01, 1:125))
```

This may not be very informative on its on; the only this this communicates clearly is that 125 samples (separate backtraces) were collected during profiling.  It becomes more meaningful with

```julia
julia> using AbstractTrees

julia> print_tree(g)
FlameGraphs.NodeData(ip:0x0, 0x01, 1:125)
├─ FlameGraphs.NodeData((::Revise.var"#85#87"{REPL.REPLBackend})() at task.jl:333, 0x00, 2:116)
│  └─ FlameGraphs.NodeData(run_backend(::REPL.REPLBackend) at Revise.jl:1057, 0x00, 2:116)
│     └─ FlameGraphs.NodeData(eval_user_input(::Any, ::REPL.REPLBackend) at REPL.jl:86, 0x01, 2:116)
│        └─ FlameGraphs.NodeData(eval(::Module, ::Any) at boot.jl:330, 0x01, 2:116)
│           ├─ FlameGraphs.NodeData(profile_test(::Int64) at proftest.jl:3, 0x00, 2:32)
│           │  └─ FlameGraphs.NodeData(randn at normal.jl:190 [inlined], 0x00, 2:32)
│           │     └─ FlameGraphs.NodeData(randn(::Random.MersenneTwister, ::Type{Float64}, ::Int64, ::Int64, ::Vararg{Int64,N} where N) at normal.jl:184, 0x01, 2:32)
│           │        ├─ FlameGraphs.NodeData(Array{Float64,N} where N(::UndefInitializer, ::Int64, ::Int64, ::Int64) at boot.jl:420, 0x00, 2:8)
│           │        │  └─ FlameGraphs.NodeData(Array at boot.jl:408 [inlined], 0x02, 2:8)
│           │        ├─ FlameGraphs.NodeData(randn!(::Random.MersenneTwister, ::Array{Float64,3}) at normal.jl:0, 0x00, 9:9)
│           │        └─ FlameGraphs.NodeData(randn!(::Random.MersenneTwister, ::Array{Float64,3}) at normal.jl:173, 0x00, 10:32)
│           │           ├─ FlameGraphs.NodeData(randn(::Random.MersenneTwister, ::Type{Float64}) at gcutils.jl:91, 0x00, 10:12)
...
```

Each node of the tree consists of a `StackFrame` indicating the file, function, and line number of a particular entry in one or more backtraces, a status flag, and a range that corresponds to the horizontal span of a particular node when the graph is rendered.  See [`FlameGraphs.NodeData`](@ref) for more information.

[`flamegraph`](@ref) has several options that can be used to control how it computes the graph.

## Rendering a flame graph

You can create a "bitmap" representation of the flame graph with [`flamepixels`](@ref):

```julia
julia> img = flamepixels(g)
125×20 Array{RGB{N0f8},2} with eltype ColorTypes.RGB{FixedPointNumbers.Normed{UInt8,8}}:
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)      …  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)   …  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)      RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 ⋮                                                   ⋱                                                                        
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.62,0.62,0.62)   …  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.659,0.635,0.0)  …  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(1.0,1.0,1.0)         RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.804,0.725,1.0)     RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
 RGB{N0f8}(1.0,0.0,0.0)  RGB{N0f8}(0.804,0.725,1.0)     RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)  RGB{N0f8}(1.0,1.0,1.0)
```

You can display this in an image viewer, but for interactive exploration `ProfileView.jl` adds additional features.

The coloration scheme can be customized as described in the documentation for [`flamepixels`](@ref), with the default coloration provided by [`FlameColors`](@ref).
This default chooses cycling colors to distinguish different stack frames, while coloring runtime dispatch red and garbage-collection orange.
If we profile "time to first plot,"

```
using Plots, Profile, FlameGraphs
@profile plot(rand(5))    # "time to first plot"
g = flamegraph(C=true)
img = flamepixels(g)
```

we might get something like this:

![default_colors](assets/ttfp.png)

An alternative is to color frames by their category:

```julia
img = flamepixels(StackFrameCategory(), g)
```

in which case we might get something like this:

![default_colors](assets/categorize_ttfp.png)

In this plot, dark gray indicates time spent in `Core.Compiler` (mostly inference), yellow in [LLVM](https://en.wikipedia.org/wiki/LLVM), orange other `ccall`s, light blue in `Base`,
and red is uncategorized (mostly package code).

[`StackFrameCategory`](@ref) allows you to customize these choices and recognize arbitrary modules.
