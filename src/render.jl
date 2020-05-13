struct FlameColors
    colors::Vector{RGB{N0f8}}
    colorbg::RGB{N0f8}
    colorfont::RGB{N0f8}
    colorsrt::Vector{RGB{N0f8}}
    colorsgc::Vector{RGB{N0f8}}
end

"""
    fcolor = FlameColors(n::Integer=2;
                         colorbg=colorant"white", colorfont=colorant"black",
                         colorsrt=colorant"crimson", colorsgc=colorant"orange")

Choose a set of colors for rendering a flame graph. There are several special colors:

- `colorbg` is the background color
- `colorfont` is used when annotating stackframes with text
- `colorsrt` highlights [runtime dispatch](https://discourse.julialang.org/t/dynamic-dispatch/6963), typically a costly process
- `colorsgc` highlights garbage-collection events

`n` specifies the number of "other" colors to choose when one of the above is not relevant.
`FlameColors` chooses `2n` colors: the first `n` colors for odd depths in the stacktrace and
the last `n` colors for even depths in the stacktrace. Consequently, different stackframes will typically
be distinguishable from one another by color.

The highlighting can be disabled by passing `nothing` or a zero-element vector
for `colorsrt` or `colorsgc`. When a single color is passed for `colorsrt` or
`colorsgc`, this method generates four variant colors slightly different from
the specified color. `colorsrt` or `colorsgc` can also be specified as multiple
colors with a vector. The first half of the vector is for odd depths and the
second half is for even depths. By using a one-element vector instead of a
single color, the specified color is always used.

While the return value is a `struct`, it is callable and can be used as the
`fcolor` input for `flamepixels`.
"""
function FlameColors(n::Integer=2;
                     colorbg=colorant"white", colorfont=colorant"black",
                     colorsrt=colorant"crimson", colorsgc=colorant"orange")
    seeds = [colorbg, colorfont]
    function make_variations(color)
        color === nothing && return RGB{N0f8}[]
        isa(color, AbstractVector) && return color
        c = convert(LCHab, color)
        a = LCHab(min(c.l+2.5, 100.0), c.c+10.0, c.h-7.5)
        b = LCHab(max(c.l-2.5, 0.0), max(c.c-10.0, 0.0), c.h+7.5)
        RGB{N0f8}.(range(a, stop=b, length=4))
    end
    colorsrt = make_variations(colorsrt)
    colorsgc = make_variations(colorsgc)
    append!(seeds, colorsrt)
    append!(seeds, colorsgc)
    nseeds = length(seeds)
    colors = distinguishable_colors(2n+nseeds, seeds,
                                    transform=c->deuteranopic(c, 0.95),
                                    lchoices=Float64[65, 80],
                                    cchoices=Float64[10, 55],
                                    hchoices=range(10, stop=350, length=18))[nseeds+1:end]
    sort!(colors, by=c->colordiff(c, colorbg))
    return FlameGraphs.FlameColors(colors, colorbg, colorfont, colorsrt, colorsgc)
end

const default_colors = FlameColors()

function (colors::FlameColors)(s::Symbol)
    s === :bg && return colors.colorbg
    s === :font && return colors.colorfont
    throw(ArgumentError("unrecognized color id :$s"))
end

function (colors::FlameColors)(nextidx, j::Integer, data)
    idx = nextidx[j]
    nextidx[j] = idx + 1
    if length(colors.colorsrt) > 0 && (data.status & runtime_dispatch) != 0
        colorvec = colors.colorsrt
    elseif length(colors.colorsgc) > 0 && (data.status & gc_event) != 0
        colorvec = colors.colorsgc
    else
        colorvec = colors.colors
    end
    n = length(colorvec)
    m = (n + 1)÷2
    return colorvec[mod1(mod1(idx, m) + iseven(j) * m, n)]
end

"""
    img = flamepixels(g; kwargs...)

Return a flamegraph as a matrix of RGB colors. The first dimension corresponds to cost,
the second dimension to depth in the call stack.

See also [`flametags`](@ref).
"""
flamepixels(g::Node; kwargs...) = flamepixels(default_colors, g; kwargs...)

"""
    img = flamepixels(fcolor, g; costscale=nothing)

Return a flamegraph as a matrix of RGB colors, customizing the color choices.

## fcolor

`fcolor` is a function that returns the
color used for the current item in the call stack.
See [`FlameColors`](@ref) for the default implementation of `fcolor`.

If you provide a custom `fcolor`, it must support the following API:

    colorbg = fcolor(:bg)
    colorfont = fcolor(:font)

must return the background and font colors.

    colornode = fcolor(nextidx::Vector{Int}, j, data::NodeData)

chooses the color for the node represented by `data` (see [`NodeData`](@ref)).
`j` corresponds to depth in the call stack and `nextidx[j]` holds the state for the next
color choice.
In general, if you have a list of colors, `fcolor` should cycle `nextidx[j]` to ensure that
the next call to `fcolor` with this `j` moves on to the next color.
(However, you may not want to increment `nextidx[j]` if you are choosing the color by some
means other than cycling through a list.)

By accessing `data.sf`, you can choose to color individual nodes based on the identity of
the stackframe.

## costscale

`costscale` can be used to limit the size of `img` when profiling collected a large number of stacktraces.
The size of the first dimension of `img` is proportional to the total number of
stacktraces collected during profiling. `costscale` is the constant of proportionality;
for example, setting `costscale=0.2` would mean that `size(img, 1)` would be approximately
1/5 the number of stacktraces collected by the profiler. The default value of `nothing`
imposes an upper bound of approximately 1000 pixels along the first dimension, with
`costscale=1` chosen if the number of samples is less than 1000.
"""
function flamepixels(fcolor, g::Node; costscale=nothing)
    ndata = g.data
    w = length(ndata.span)
    if costscale === nothing
        costscale = w < 10^3 ? 1.0 : 10^3/w
    end
    h = depth(g)
    img = fill(fcolor(:bg), round(Int, w*costscale), h)
    nextidx = fill(1, h)
    img[scale(ndata.span, costscale), 1] .= fcolor(nextidx, 1, ndata)
    return flamepixels!(fcolor, img, g, 2, nextidx, costscale)
end

function flamepixels!(fcolor, img, g, j, nextidx, costscale)
    for c in g
        ndata = c.data
        img[scale(ndata.span, costscale), j] .= fcolor(nextidx, j, ndata)
        flamepixels!(fcolor, img, c, j+1, nextidx, costscale)
    end
    return img
end

"""
    tagimg = flametags(g, img)

From a flame graph `g`, generate an array `tagimg` with the same axes as `img`,
encoding the stackframe represented by each pixel of `img`.

See [`flamepixels`](@ref) to generate `img`.
"""
function flametags(g, img)
    tags = fill(1, axes(img))
    ndata = g.data
    sflist = StackFrame[StackTraces.UNKNOWN]
    sf2tag = Dict{StackFrame,Int}(StackTraces.UNKNOWN=>1)
    tags[:,1] .= tagidx(ndata.sf, sf2tag, sflist)
    costscale = size(img, 1) / length(ndata.span)
    flametags!(tags, g, sf2tag, sflist, 2, costscale)
    return IndirectArray(tags, sflist)
end

function flametags!(tags, parent, sf2tag, sflist, level, costscale)
    for c in parent
        ndata = c.data
        tags[scale(ndata.span, costscale), level] .= tagidx(ndata.sf, sf2tag, sflist)
        flametags!(tags, c, sf2tag, sflist, level+1, costscale)
    end
end

scale(rng::UnitRange, costscale) = max(1, round(Int, costscale*first(rng))):round(Int, costscale*last(rng))

function tagidx(sf, sf2tag, sflist)
    idx = get(sf2tag, sf, length(sflist)+1)
    if idx > length(sflist)
        sf2tag[sf] = idx
        push!(sflist, sf)
    end
    return idx
end
