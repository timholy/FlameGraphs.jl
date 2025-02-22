using FlameGraphs, AbstractTrees, Colors, FileIO
using Base.StackTraces: StackFrame
using Test, Profile, InteractiveUtils

# useful for testing
stackframe(func, file, line; C=false) = StackFrame(Symbol(func), Symbol(file), line, nothing, C, false, 0)

@testset "flamegraph" begin
    backtraces = UInt64[   4, 3, 2, 1,   # order: callees then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    dummy_thread = 1
    dummy_task = UInt(0xf0f0f0f0)
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces, threadid = dummy_thread, taskid = dummy_task)
    end
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    for threads in [nothing, dummy_thread], tasks in [nothing, dummy_task]
        VERSION < v"1.8.0-DEV.460" && threads !== nothing && tasks !== nothing && continue # skip if threads not available
        @testset "Threads: $(repr(threads)), Tasks: $(repr(tasks))" begin
            g = if VERSION >= v"1.8.0-DEV.460"
                flamegraph(backtraces; lidict=lidict, threads=threads, tasks=tasks)
            else
                flamegraph(backtraces; lidict=lidict)
            end
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
NodeData(ip:0x0, 0x00, 1:4)
├─ NodeData(f1 at file1:1, 0x00, 1:3)
│  ├─ NodeData(f2 at file1:5, 0x00, 1:2)
│  │  └─ NodeData(f3 at file2:1, 0x00, 1:2)
│  │     └─ NodeData(f2 at file1:15, 0x00, 1:2)
│  └─ NodeData(f4 at file1:20, 0x00, 3:3)
│     └─ NodeData(f5 at file3:1, 0x00, 3:3)
└─ NodeData(f1 at file1:2, 0x00, 4:4)
   └─ NodeData(f6 at file3:10, 0x00, 4:4)
"""
        end
    end

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

@testset "flamegraph string filtering" begin
    backtraces = UInt64[   4, 3, 2, 1,   # order: callees then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces)
    end
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict, filter = "f2")
    level1 = collect(g)
    @test length(level1) == 1
    n1 = level1[1]
    @test n1.data.sf.func == :f1
    @test n1.data.sf.line == 1
    @test n1.data.span == 1:3
    level2 = collect(n1)
    @test length(level2) == 1
    n2 = level2[1]
    @test n2.data.sf.func == :f2
    @test n2.data.sf.line == 5
    @test n2.data.span == 1:2
    level3 = collect(n2)
    @test length(level3) == 1
    n3 = level3[1]
    @test n3.data.sf.func == :f3
    @test n3.data.sf.line == 1
    @test n3.data.span == 1:2
    level4 = collect(n3)
    @test length(level4) == 1
    n4 = level4[1]
    @test n4.data.sf.func == :f2
    @test n4.data.sf.line == 15
    @test n4.data.span == 1:2
    @test isempty(collect(n4))
end

@testset "flamegraph function filtering" begin
    backtraces = UInt64[   4, 3, 2, 1,   # order: callees then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces)
    end
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))

    g = flamegraph(backtraces; lidict=lidict, filter = x -> (x.sf.func == :f1) & (x.sf.line == 1))
    level1 = collect(g)
    @test length(level1) == 1
    n1 = level1[1]
    @test n1.data.sf.func == :f1
    @test n1.data.sf.line == 1
    @test n1.data.span == 1:3
    level2 = collect(n1)
    @test length(level2) == 2
    n2, n2b = level2
    @test n2.data.sf.func == :f2
    @test n2.data.sf.line == 5
    @test n2.data.span == 1:2
    @test n2b.data.sf.func == :f4
    @test n2b.data.sf.line == 20
    @test n2b.data.span == 3:3

    level3 = collect(n2)
    @test length(level3) == 1
    n3 = level3[1]
    @test n3.data.sf.func == :f3
    @test n3.data.sf.line == 1
    @test n3.data.span == 1:2
    level3b = collect(n2b)
    @test length(level3b) == 1
    n3b = level3b[1]
    @test n3b.data.sf.func == :f5
    @test n3b.data.sf.line == 1
    @test n3b.data.span == 3:3
    @test isempty(collect(n3b))

    level4 = collect(n3)
    @test length(level4) == 1
    n4 = level4[1]
    @test n4.data.sf.func == :f2
    @test n4.data.sf.line == 15
    @test n4.data.span == 1:2
    @test isempty(collect(n4))
end

@testset "flamegraph wrong filtering is ignored" begin
    backtraces = UInt64[   4, 3, 2, 1,   # order: callees then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces)
    end

    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))

    g = (@test_logs (:warn, "The filter condition results in the root node pruning, so the filter is ignored") flamegraph(backtraces; lidict=lidict, filter = "f7"))
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
end

@testset "flamepixels" begin
    backtraces = UInt64[   4, 3, 2, 1,   # order: callees then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces)
    end
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
    fc = FlameColors()
    @test fc(:bg) === fc.colorbg
    @test_throws ArgumentError fc(:unknown)

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
                                     4=>stackframe(:_ZL, Symbol("libLLVM-8.0.so"), 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:copy, Symbol(".\\expr.jl"), 1), # on Windows
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:typeinf, Symbol("./compiler/typeinfer.jl"), 10))
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

    # dark mode
    fc3 = FlameColors(; darkmode = true)

    sfc = StackFrameCategory()
    @test sfc(:bg) == sfc.colorbg
    @test_throws ArgumentError sfc(:unknown)

    img = flamepixels(sfc, g)
    @test all(img[:,1] .== colorant"orange")
    @test all(img[1:3,2] .== colorant"red")
    @test img[4,2] == colorant"red"
    @test img[1,3] == colorant"red"
    @test all(img[2:3,3] .== colorant"yellow")
    @test img[4,3] == colorant"gray60"
    @test img[1,4] == colorant"lightblue"
    @test all(img[2:4,4] .== colorant"white")
end

@testset "Profiling" begin
    A = randn(100, 100, 200)
    Profile.clear()
    mapslices(sum, A; dims=2)  # compile it so we don't end up profiling inference
    while Profile.len_data() == 0
        @profile mapslices(sum, A; dims=2)
    end
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

@testset "Runtime dipatch detection" begin
    # Test is from SnoopCompile
    mappushes!(f, dest, src) = (for item in src push!(dest, f(item)) end; return dest)
    function spell_spec(::Type{T}) where T
        name = Base.unwrap_unionall(T).name.name
        str = ""
        for c in string(name)
            str *= c
        end
        return str
    end
    Ts = subtypes(Any)[1:20]   # we don't need all of them
    mappushes!(spell_spec, [], Ts)
    rtds = []
    for _ in 1:10 # try to get a runtime dispatch on unfortunately flaky profiling
        @profile for i = 1:10000
            mappushes!(spell_spec, [], Ts)
        end
        _, sfdict = Profile.retrieve()
        for sfs in values(sfdict)
            for sf in sfs
                if (FlameGraphs.status(sf) & FlameGraphs.runtime_dispatch) != 0
                    push!(rtds, sfs)
                    break
                end
            end
        end
        isempty(rtds) || break
    end
    @test !isempty(rtds)
end

@testset "IO" begin
    function nodeeq(a::FlameGraphs.Node, b::FlameGraphs.Node)
        nodeeq(a.data, b.data) || return false
        reta, retb = iterate(a), iterate(b)
        while true
            reta === retb === nothing && return true
            (reta === nothing) || (retb === nothing) && return false
            childa, statea = reta
            childb, stateb = retb
            nodeeq(childa, childb) || return false
            reta, retb = iterate(a, statea), iterate(b, stateb)
        end
    end
    nodeeq(a::FlameGraphs.NodeData, b::FlameGraphs.NodeData) =
        nodeeq(a.sf, b.sf) &&
        a.status == b.status &&
        a.span == b.span
    nodeeq(a::Base.StackFrame, b::Base.StackFrame) =
        a.func == b.func &&
        a.file == b.file &&
        a.line == b.line &&
        a.from_c == b.from_c &&
        a.inlined == b.inlined

    A = randn(100, 100, 200)
    Profile.clear()
    while Profile.len_data() == 0
        @profile mapslices(sum, A; dims=2)
    end
    fn = tempname()*".jlprof"
    f = File{format"JLPROF"}(fn)
    FlameGraphs.save(f)
    data, lidict = FlameGraphs.load(f)
    datar, lidictr = Profile.retrieve()
    @test data == datar
    @test lidictr == lidict
    rm(fn)
    fn = tempname()*".jlprof"
    f = File{format"JLPROF"}(fn)
    g = flamegraph(data; lidict=lidict)
    FlameGraphs.save(f, g)
    gr = FlameGraphs.load(f)
    @test nodeeq(g, gr)
    rm(fn)
end
