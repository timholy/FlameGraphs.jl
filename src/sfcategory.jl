"""
    StackFrameCategory(modcat=FlameGraphs.default_modcat,
                       loccat=FlameGraphs.default_loccat,
                       colorbg=colorant"white",
                       colorfont=colorant"black")

Colorize stackframes based on their category.

`modcat(mod::Module)` should return a color based on the stackframe's module, or `nothing`
if it cannot categorize the stack frame based on the module.

`loccat(sf::StackFrame)` must return a color. It can use any of the fields of the stackframe,
but `func`, `file`, `line`, and `from_c` might be common choices.

`colorbg` is the background color, and `colorfont` stores the choice of font color.

# Example

```julia
using Plots, Profile, FlameGraphs
@profile plot(rand(5))    # "time to first plot"
g = flamegraph(C=true)
img = flamepixels(StackFrameCategory(), g)
```
"""
struct StackFrameCategory
    modcat   # categorization based on module (color if categorized, otherwise `nothing`)
    loccat   # categorization based on location
    colorbg::RGB{N0f8}
    colorfont::RGB{N0f8}
end

"""
    default_modcat(mod::Module)

Returns dark gray for `Core.Compiler`, light gray for `Core`, light blue for `Base`,
and otherwise returns `nothing`.
"""
function default_modcat(mod::Module)
    (mod === Core.Compiler || pm(mod) === Core.Compiler) && return colorant"gray60"
    (mod === Core || pm(mod) === Core) && return colorant"gray30"
    (mod === Base || pm(mod) === Base) && return colorant"lightblue"
    return nothing
end

"""
    default_loccat(sf::StackFrame)

Returns yellow for LLVM, orange for any other `ccall`, dark gray for anything in `./compiler`,
light blue for Base code, and red for anything else.
"""
function default_loccat(sf::StackFrame)
    file = String(sf.file)
    occursin("LLVM", file) && return colorant"yellow"
    sf.from_c && return colorant"orange"
    occursin("compiler", file) && return colorant"gray60"
    startswith(file, "./") && return colorant"lightblue"
    return colorant"red"   # uncategorized
end

StackFrameCategory(modcat = default_modcat,
                   loccat = default_loccat) =
    StackFrameCategory(modcat, loccat, colorant"white", colorant"black")

# Background color
(sfc::StackFrameCategory)() = sfc.colorbg

function (sfc::StackFrameCategory)(nextidx, j, nodedata)
    sf = nodedata.sf
    if isdefined(sf, :linfo)
        mi = sf.linfo
        if isa(mi, Core.MethodInstance)
            def = mi.def
            if isa(def, Module)
                mod = def
            else
                mod = def.module
            end
            col = sfc.modcat(mod)
            col !== nothing && return col
        end
    end
    return sfc.loccat(sf)
end

function pm(mod)
    pmod = parentmodule(mod)
    while mod !== pmod && mod !== Base && mod !== Core && mod !== Core.Compiler
        mod = pmod
        pmod = parentmodule(mod)
    end
    return mod
end
