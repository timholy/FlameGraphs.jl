# FlameGraphs

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://timholy.github.io/FlameGraphs.jl/stable)
[![Build Status](https://travis-ci.com/timholy/FlameGraphs.jl.svg?branch=master)](https://travis-ci.com/timholy/FlameGraphs.jl)
[![Codecov](https://codecov.io/gh/timholy/FlameGraphs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/timholy/FlameGraphs.jl)

FlameGraphs is a package that adds functionality to Julia's `Profile` standard library. It is directed primarily at the algorithmic side of producing [flame graphs](http://www.brendangregg.com/flamegraphs.html), but includes some "format agnostic" rendering code.

You might use FlameGraphs on its own, but users should consider one of its downstream packages:

- [ProfileView](https://github.com/timholy/ProfileView.jl), a graphical user interface (GUI) based on [Gtk](https://github.com/JuliaGraphics/Gtk.jl) for displaying and interacting with flame graphs
- [ProfileSVG](https://github.com/timholy/ProfileSVG.jl), a package for writing flame graphs to SVG format, and which can also be used interactively in Jupyter notebooks.

See the documentation for details.
