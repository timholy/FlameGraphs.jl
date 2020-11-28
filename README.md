# FlameGraphs

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://timholy.github.io/FlameGraphs.jl/stable)
[![Build Status](https://travis-ci.com/timholy/FlameGraphs.jl.svg?branch=master)](https://travis-ci.com/timholy/FlameGraphs.jl)
[![PkgEval][pkgeval-img]][pkgeval-url]
[![Codecov](https://codecov.io/gh/timholy/FlameGraphs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/timholy/FlameGraphs.jl)

FlameGraphs is a package that adds functionality to Julia's `Profile` standard library. It is directed primarily at the algorithmic side of producing [flame graphs](http://www.brendangregg.com/flamegraphs.html), but includes some "format agnostic" rendering code.

You might use FlameGraphs on its own, but users should consider one of its downstream packages:

- [ProfileView](https://github.com/timholy/ProfileView.jl), a graphical user interface (GUI) based on [Gtk](https://github.com/JuliaGraphics/Gtk.jl) for displaying and interacting with flame graphs
- [Juno](https://junolab.org/), a development environment that supports profile visualization
- [ProfileVega](https://github.com/davidanthoff/ProfileVega.jl), the recommended package for display in Jupyter notebooks
- [ProfileSVG](https://github.com/timholy/ProfileSVG.jl), a package for writing flame graphs to SVG format
- [PProf](https://github.com/JuliaPerf/PProf.jl), an interactive, web-based profile GUI explorer, implemented as a wrapper around [`google/pprof`](https://github.com/google/pprof). Has excellent support for interaction, filtering, aggregation, and viewing source code. But note that it loses the sample ordering information captured in FlameGraphs.

See the documentation for details.

[pkgeval-img]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/F/FlameGraphs.svg
[pkgeval-url]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html
