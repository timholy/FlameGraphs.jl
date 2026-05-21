using Documenter, FlameGraphs

makedocs(;
    modules=[FlameGraphs],
    format=Documenter.HTML(;
        assets = ["assets/favicon.ico"],
        canonical = "https://timholy.github.io/FlameGraphs.jl/stable/",
    ),
    pages=[
        "Home" => "index.md",
        "Reference" => "reference.md",
    ],
    sitename="FlameGraphs.jl",
    authors="Tim Holy <tim.holy@gmail.com>",
    checkdocs=:exported,
)

deploydocs(;
    repo="github.com/timholy/FlameGraphs.jl",
    push_preview=true,
)
