using FlameGraphs, AbstractTrees, Colors
using Base.StackTraces: StackFrame
using Test, Profile

# useful for testing
stackframe(func, file, line; C=false) = StackFrame(Symbol(func), Symbol(file), line, nothing, C, false, 0)

@testset "flamegraph" begin
    backtraces = UInt64[0, 4, 3, 2, 1,   # order: calles then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    @test all(node->node.data.status == 0, PostOrderDFS(g))
    level1 = collect(g)
    @test length(level1) == 2
    n1, n2 = level1
    @test n1.data.sf.func === :f1
    @test n1.data.sf.line == 1
    @test n1.data.span == 1:3
    @test n2.data.sf.func === :f1
    @test n2.data.sf.line == 2
    @test n2.data.span == 4:4
    level2a = collect(n1)
    @test length(level2a) == 2
    n3, n4 = level2a
    @test n3.data.sf.func === :f2
    @test n3.data.sf.line == 5
    @test n3.data.span == 1:2
    @test n4.data.sf.func === :f4
    @test n4.data.sf.line == 20
    @test n4.data.span == 3:3
    level2b = collect(n2)
    @test length(level2b) == 1
    n5 = level2b[1]
    @test n5.data.sf.func === :f6
    @test n5.data.sf.line == 10
    @test n5.data.span == 4:4
    level3a = collect(n3)
    @test length(level3a) == 1
    n6 = level3a[1]
    @test n6.data.sf.func === :f3
    @test n6.data.sf.line == 1
    @test n6.data.span == 1:2
    level3b = collect(n4)
    @test length(level3b) == 1
    n7 = level3b[1]
    @test n7.data.sf.func === :f5
    @test n7.data.sf.line == 1
    @test n7.data.span == 3:3
    @test isempty(n5)
    level4a = collect(n6)
    @test length(level4a) == 1
    n8 = level4a[1]
    @test n8.data.sf.func === :f2
    @test n8.data.sf.line == 15
    @test n8.data.span == 1:2
    @test isempty(n7)
    @test isempty(n8)

    io = IOBuffer()
    print_tree(io, g)
    str = String(take!(io))
    @test str == """
FlameGraphs.NodeData(ip:0x0, 0x00, 1:4)
├─ FlameGraphs.NodeData(f1 at file1:1, 0x00, 1:3)
│  ├─ FlameGraphs.NodeData(f2 at file1:5, 0x00, 1:2)
│  │  └─ FlameGraphs.NodeData(f3 at file2:1, 0x00, 1:2)
│  │     └─ FlameGraphs.NodeData(f2 at file1:15, 0x00, 1:2)
│  └─ FlameGraphs.NodeData(f4 at file1:20, 0x00, 3:3)
│     └─ FlameGraphs.NodeData(f5 at file3:1, 0x00, 3:3)
└─ FlameGraphs.NodeData(f1 at file1:2, 0x00, 4:4)
   └─ FlameGraphs.NodeData(f6 at file3:10, 0x00, 4:4)
"""

    # pruning
    c = g.child.child
    @test c.child != c
    g = flamegraph(backtraces; lidict=lidict, pruned=[(:f3, "file2")])
    c = g.child.child
    @test c.child == c

    # Now make some of them C calls
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:jl_f, :filec, 55; C=true),
                                     3=>stackframe(:jl_invoke, :file2, 1; C=true),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    level1 = collect(g)
    @test length(level1) == 2
    n1, n2 = level1
    @test n1.data.sf.func === :f1
    @test n1.data.sf.line == 1
    @test n1.data.span == 1:3
    # Note: only span 2:3 contributes to the rt dispatch, but since we mark the caller
    # rather than the callee, and 1:3 all are the same caller, the whole thing gets marked.
    @test n1.data.status == FlameGraphs.runtime_dispatch
    @test n2.data.sf.func === :f1
    @test n2.data.sf.line == 2
    @test n2.data.span == 4:4
    @test n2.data.status == 0
    level2a = collect(n1)
    @test length(level2a) == 2
    n3, n4 = level2a
    @test n3.data.sf.func === :f4
    @test n3.data.sf.line == 20
    @test n3.data.span == 1:1
    @test n4.data.sf.func === :f2
    @test n4.data.sf.line == 15
    @test n4.data.span == 2:3
    level2b = collect(n2)
    @test length(level2b) == 1
    n5 = level2b[1]
    @test n5.data.sf.func === :f6
    @test n5.data.sf.line == 10
    @test n5.data.span == 4:4
    level3a = collect(n3)
    @test length(level3a) == 1
    n6 = level3a[1]
    @test n6.data.sf.func === :f5
    @test n6.data.sf.line == 1
    @test n6.data.span == 1:1
    @test isempty(n4)
    @test isempty(n5)
    @test isempty(n6)

    # Pruning REPL code
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:eval_user_input, "REPL.jl", 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    sfc = [c.data.sf for c in g]
    @test lidict[3] ∈ sfc
    @test lidict[1] ∉ sfc
end

@testset "flamepixels" begin
    backtraces = UInt64[0, 4, 3, 2, 1,   # order: calles then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    img = flamepixels(g)
    fc = FlameGraphs.FlameColors()
    @test all(img[:,1] .== fc.colors[1])
    @test all(img[1:3,2] .== fc.colors[3])
    @test img[4,2] == fc.colors[4]
    @test all(img[1:2,3] .== fc.colors[1])
    @test img[3,3] == fc.colors[2]
    @test img[4,3] == fc.colors[1]
    @test all(img[1:2,4] .== fc.colors[3])
    @test img[3,4] == fc.colors[4]
    @test img[4,4] == fc.colorbg
    @test all(img[1:2,5] .== fc.colors[1])
    @test all(img[3:4,5] .== fc.colorbg)
    imgtags = flametags(g, img)
    @test axes(imgtags) == axes(img)
    @test imgtags[1,2] == lidict[1]
    @test imgtags[4,2] == lidict[7]
    @test imgtags[4,end] == StackTraces.UNKNOWN

    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:jl_f, :filec, 55; C=true),
                                     3=>stackframe(:jl_invoke, :file2, 1; C=true),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    img = flamepixels(g)
    @test all(img[:,1] .== fc.colors[1])
    # Note: only span 2:3 contributes to the rt dispatch, but since we mark the caller
    # rather than the callee, and 1:3 all are the same caller, the whole thing gets marked.
    @test all(img[1:3,2] .== fc.colorsrt[3])
    @test img[4,2] == fc.colors[4]
    @test img[1,3] == fc.colors[1]
    @test all(img[2:3,3] .== fc.colors[2])
    @test img[4,3] == fc.colors[1]
    @test img[1,4] == fc.colors[3]
    @test all(img[2:4,4] .== fc.colorbg)

    # Customizing FlameColors
    # the classic colors which were used in FlameGraphs v0.1 or ProfileView v0.5
    fc2 = FlameColors(
        parse.(RGB, ["#E870DD", "#32B44E", "#1AA2FF", "#00DEE6", "#FFA49C",
                     "#9E9E9E", "#A8A200", "#CDB9FF", "#00E5B2", "#FF5F82"]),
        colorant"white", colorant"black", [colorant"red"], [colorant"orange"])
    img = flamepixels(fc2, g)
    @test all(img[:,1] .== fc2.colors[1])
    @test all(img[1:3,2] .== fc2.colorsrt[1])
    @test img[4,2] == fc2.colors[7]
    @test img[1,3] == fc2.colors[1]
    @test all(img[2:3,3] .== fc2.colors[2])
    @test img[4,3] == fc2.colors[3]
    @test img[1,4] == fc2.colors[6]
    @test all(img[2:4,4] .== fc2.colorbg)
end

@testset "Profiling" begin
     A = randn(100, 100, 200)
     Profile.clear()
     @profile mapslices(sum, A; dims=2)
     g = flamegraph()
     @test FlameGraphs.depth(g) > 10
     img = flamepixels(StackFrameCategory(), flamegraph(C=true))
     @test any(img .== colorant"orange")
     A = [1,2,3]
     sum(A)
     Profile.clear()
     @profile sum(A)
     Sys.islinux() && @test_logs (:warn, r"There were no samples collected.") flamegraph() === nothing
end
