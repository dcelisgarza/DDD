"""
```
JSON.lower(
    t::T,
) where {
    T <: Union{
        AbstractCrystalStruct,
        AbstractMobility,
        AbstractIntegrator,
        AbstractDlnSeg,
        AbstractDlnStr,
        AbstractDistribution,
    },
}

JSON.lower(t::nodeTypeDln)
```
Extensions to `JSON.lower` for custom types. Allows these variables to be serialised properly.
"""
function JSON.lower(
    t::T,
) where {
    T <: Union{
        AbstractCrystalStruct,
        AbstractMobility,
        AbstractIntegrator,
        AbstractDlnSeg,
        AbstractDlnStr,
        AbstractDistribution,
        DispatchRegularCuboidMesh,
        LinearElement,
        CantileverLoad,
    },
}
    return string(t)
end
JSON.lower(t::nodeTypeDln) = Int(t)
JSON.lower(t::nodeTypeFE) = Int(t)
JSON.lower(t::Ptr{SuiteSparse.CHOLMOD.C_Factor{Float64}}) = nothing
"""
```
saveJSON(filename::AbstractString, args...; mode::AbstractString = "w")
```
Wrapper for `JSON.print`.
"""
function saveJSON(filename::AbstractString, args...; mode::AbstractString = "w")
    open(filename, mode) do io
        return length(args) == 1 ? JSON.print(io, args...) : JSON.print(io, args)
    end
    return nothing
end
