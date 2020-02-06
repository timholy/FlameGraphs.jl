using Documenter, FlameGraphs, FileIO

makedocs(;
    modules=[FlameGraphs],
    format=Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    pages=[
        "Home" => "index.md",
        "reference.md"
    ],
    repo="https://github.com/timholy/FlameGraphs.jl/blob/{commit}{path}#L{line}",
    sitename="FlameGraphs.jl",
    authors="Tim Holy <tim.holy@gmail.com>",
)

deploydocs(;
    repo="github.com/timholy/FlameGraphs.jl",
)
