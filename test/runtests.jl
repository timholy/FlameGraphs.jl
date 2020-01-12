using FlameGraphs, AbstractTrees
using Base.StackTraces: StackFrame
using Test

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
    @test all(img[:,1] .== fc.colorsodd[1])
    @test all(img[1:3,2] .== fc.colorseven[1])
    @test img[4,2] == fc.colorseven[2]
    @test all(img[1:2,3] .== fc.colorsodd[1])
    @test img[3,3] == fc.colorsodd[2]
    @test img[4,3] == fc.colorsodd[3]
    @test all(img[1:2,4] .== fc.colorseven[1])
    @test img[3,4] == fc.colorseven[2]
    @test img[4,4] == fc.colorbg
    @test all(img[1:2,5] .== fc.colorsodd[1])
    @test all(img[3:4,5] .== fc.colorbg)

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
    @test all(img[:,1] .== fc.colorsodd[1])
    # Note: only span 2:3 contributes to the rt dispatch, but since we mark the caller
    # rather than the callee, and 1:3 all are the same caller, the whole thing gets marked.
    @test all(img[1:3,2] .== fc.colorrt)
    @test img[4,2] == fc.colorseven[1]
    @test img[1,3] == fc.colorsodd[1]
    @test all(img[2:3,3] .== fc.colorsodd[2])
    @test img[4,3] == fc.colorsodd[3]
    @test img[1,4] == fc.colorseven[1]
    @test all(img[2:4,4] .== fc.colorbg)
end
