using Documenter, FlameGraphs

makedocs(;
    modules=[FlameGraphs],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/timholy/FlameGraphs.jl/blob/{commit}{path}#L{line}",
    sitename="FlameGraphs.jl",
    authors="Tim Holy <tim.holy@gmail.com>",
    assets=String[],
)

deploydocs(;
    repo="github.com/timholy/FlameGraphs.jl",
)
