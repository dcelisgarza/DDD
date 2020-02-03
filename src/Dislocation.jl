"""
    DislocationP{
        T1<:Union{AbstractFloat,Vector{<:AbstractFloat}},
        T2<:Union{Integer,Vector{<:Integer}},
        T3<:Union{Bool,Vector{Bool}},
        T4<:Union{String,Vector{String},Symbol,Vector{Symbol}},
    }(
        coreRad::T1
        coreRadMag::T1
        minSegLen::T1
        maxSegLen::T1
minArea::T1
        maxArea::T1
        maxConnect::T2
        remesh::T3
        collision::T3
        separation::T3
        virtualRemesh::T3
        edgeDrag::T1
        screwDrag::T1
        climbDrag::T1
        lineDrag::T1
        mobility::T4
    )

This structure defines dislocation parameters. Allows for the defnumInition of multiple materials in a single invocation by giving the arguments as Vectors (1D arrays) of the relevant type.

# Arguments

## Size
```
coreRad     # Core radius.
coreRadMag # Magnitude of core Radius.
```
## Connectivity
```
minSegLen      # Minimum line length.
maxSegLen      # Maximum line length.
minArea        # Minimum area for remeshing.
maxArea        # Maximum area for remeshing.
maxConnect # Maximum number of connections to a node.
remesh          # Flag for remeshing.
collision       # Flag for collision handling.
separation      # Flag for separation handling.
virtualRemesh  # Flag for virtual remeshing.
```
## Mobility
```
edgeDrag      # Drag coefficient edge dislocation.
screwDrag     # Drag coefficient screw dislocation.
climbDrag     # Drag coefficient climb.
lineDrag      # Drag coefficient line.
mobility    # Mobility law.
```

# Examples

## Correct Declaration

### Single material

```jldoctest
julia> sample_dislocation = DislocationP(0.5, 1e5, 5., 6., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
DislocationP{Float64,Int64,Bool,String}(0.5, 100000.0, 5.0, 6.0, 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
```

### Multiple (two) materials

```jldoctest
julia> sample_dislocation = DislocationP([0.5, 0.6], [1e5, 1e4], [5., 3.], [6., 8.], [50.3, 48.], [75.3, 73.] , [4, 6], [true, false], [true, true], [false, true], [false,false], [1.0,2], [2.0,5], [3.0,6], [4.0,10], ["bcc","hcp"])
DislocationP{Array{Float64,1},Array{Int64,1},Array{Bool,1},Array{String,1}}([0.5, 0.6], [100000.0, 10000.0], [5.0, 3.0], [6.0, 8.0], [50.3, 48.0], [75.3, 73.0], [4, 6], Bool[1, 0], Bool[1, 1], Bool[0, 1], Bool[0, 0], [1.0, 2.0], [2.0, 5.0], [3.0, 6.0], [4.0, 10.0], ["bcc", "hcp"])
```

## Incorrect declaration

```jldoctest
julia> sample_dislocation = DislocationP(0.5, 1e5, 5e-2, 6., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
ERROR: AssertionError: coreRad < minSegLen

julia> sample_dislocation = DislocationP(0.5, 1e5, 5., 3., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
ERROR: AssertionError: minSegLen < maxSegLen

julia> dislocation = DislocationP(0.5, 1e5, 5., 6., 500.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
ERROR: AssertionError: minArea < maxArea

julia> sample_dislocation = DislocationP([0.5, 0.3], 1e5, 5., 6., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
ERROR: AssertionError: size(coreRad) == size(coreRadMag) == size(minSegLen) == size(maxSegLen) == size(minArea) == size(maxArea) == size(maxConnect) == size(remesh) == size(collision) == size(separation) == size(virtualRemesh) == size(edgeDrag) == size(screwDrag) == size(climbDrag) == size(lineDrag) == n_mob

julia> sample_dislocation = DislocationP([0.5, 0.6], [1e5, 1e4], [5., 3e-1], [6., 8.], [50.3, 48.], [75.3, 73.] , [4, 6], [true, false], [true, true], [false, true], [false,false], [1.0,2], [2.0,5], [3.0,6], [4.0,10], ["bcc","hcp"])
ERROR: AssertionError: coreRad[2] < minSegLen[2]
```

## Immutability

```jldoctest
julia> sample_dislocation = DislocationP(0.5, 1e5, 5., 6., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
DislocationP{Float64,Int64,Bool,String}(0.5, 100000.0, 5.0, 6.0, 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")

julia> sample_dislocation.coreRad = 0.3
ERROR: setfield! immutable struct of type DislocationP cannot be changed

julia> sample_dislocation = DislocationP(0.3, 1e5, 5., 6., 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
DislocationP{Float64,Int64,Bool,String}(0.3, 100000.0, 5.0, 6.0, 50.3, 75.3, 4, true, true, true, true, 1.0, 2.0, 3.0, 4.0, "bcc")
```
"""
struct DislocationP{
    T1<:AbstractFloat,
    T2<:Integer,
    T3<:Bool,
    T4<:Union{String,Symbol},
    T5<:Union{Integer,AbstractArray{<:Integer}},
    T6<:Union{AbstractFloat,AbstractArray{<:AbstractFloat}},
}
    # Size.
    coreRad::T1 # Core radius.
    coreRadMag::T1 # Magnitude of core Radius.
    # Connectivity.
    minSegLen::T1 # Minimum line length.
    maxSegLen::T1 # Maximum line length.
    minArea::T1 # Minimum area for remeshing.
    maxArea::T1 # Maximum area for remeshing.
    maxConnect::T2 # Maximum number of connections to a node.
    remesh::T3 # Flag for remeshing.
    collision::T3 # Flag for collision handling.
    separation::T3 # Flag for separation handling.
    virtualRemesh::T3 # Flag for virtual remeshing.
    # Mobility.
    edgeDrag::T1 # Drag coefficient edge dislocation.
    screwDrag::T1 # Drag coefficient screw dislocation.
    climbDrag::T1 # Drag coefficient climb.
    lineDrag::T1 # Drag coefficient line.
    mobility::T4 # Mobility law.
    # Sources
    numSources::T5
    slipSystems::T5
    distSource::T6
    # Fool-proof constructor.
    function DislocationP(
        coreRad,
        coreRadMag,
        minSegLen,
        maxSegLen,
        minArea,
        maxArea,
        maxConnect,
        remesh,
        collision,
        separation,
        virtualRemesh,
        edgeDrag,
        screwDrag,
        climbDrag,
        lineDrag,
        mobility,
        numSources = 0,
        slipSystems = 0,
        distSource = 0.0,
    )
        coreRad == minSegLen == maxSegLen == 0 ? nothing :
        @assert coreRad < minSegLen < maxSegLen
        minArea == maxArea == 0 ? nothing : @assert minArea < maxArea
        @assert length(numSources) == length(slipSystems) == length(distSource)
        new{
            typeof(coreRad),
            typeof(maxConnect),
            typeof(remesh),
            typeof(mobility),
            typeof(numSources),
            typeof(distSource),
        }(
            coreRad,
            coreRadMag,
            minSegLen,
            maxSegLen,
            minArea,
            maxArea,
            maxConnect,
            remesh,
            collision,
            separation,
            virtualRemesh,
            edgeDrag,
            screwDrag,
            climbDrag,
            lineDrag,
            mobility,
            numSources,
            slipSystems,
            distSource,
        )
    end # constructor
end # DislocationP

# function zero(::Type{DislocationP})
#     return DislocationP(
#         0.0,
#         0.0,
#         0.0,
#         0.0,
#         0.0,
#         0.0,
#         0,
#         false,
#         false,
#         false,
#         false,
#         0.0,
#         0.0,
#         0.0,
#         0.0,
#         :empty,
#     )
# end

mutable struct DislocationNetwork{
    T1<:AbstractArray{<:Integer},
    T2<:AbstractArray{<:Real},
    T3<:AbstractArray{<:Real},
    T4<:AbstractVector{<:Integer},
    T5<:Integer,
}
    links::T1 # Links.
    bVec::T2 # Burgers vectors.
    slipPlane::T2 # Slip planes.
    coord::T3 # Node coordinates.
    label::T4 # Node labels.
    numNode::T5 # Number of dislocations.
    numSeg::T5 # Number of segments.
    function DislocationNetwork(
        links,
        bVec,
        slipPlane,
        coord,
        label,
        numNode = 0,
        numSeg = 0,
        blank::Bool = false,
        numInit::Integer = 0,
    )
        if blank
            numNode = 0
            numSeg = 0
            links = zeros(typeof(links), numInit)
            bVec = zeros(typeof(bVec), numInit, 3)
            slipPlane = zeros(typeof(slipPlane), numInit, 3)
        else
            @assert size(links, 2) == 2
            @assert size(bVec, 2) == size(slipPlane, 2) == size(coord, 2) == 3
            @assert size(links, 1) == size(bVec, 1) == size(slipPlane, 1) ==
                    size(coord, 1) == size(label, 1)
        end
        new{
            typeof(links),
            typeof(bVec),
            typeof(coord),
            typeof(label),
            typeof(numNode),
        }(
            links,
            bVec,
            slipPlane,
            coord,
            label,
            numNode,
            numSeg,
        )
    end # Constructor
end # DislocationNetwork

# function zero(::Type{DislocationNetwork})
#     DislocationNetwork(
#         zeros(Integer, 0, 2),
#         zeros(0, 3),
#         zeros(0, 3),
#         zeros(0, 3),
#         zeros(Integer, 0),
#         0,
#         0,
#         0,
#     )
# end

function getIndex(network::DislocationNetwork, label::Real)
    return findall(x -> x == label, network.label)
end

function getIndex(
    network::DislocationNetwork,
    fieldname::Symbol,
    condition::Function,
    val::Real,
)
    data = getproperty(network, fieldname)
    return findall(x -> condition.(x, val), data)
end

function getIndex(
    network::DislocationNetwork,
    fieldname::Symbol,
    idxComp::Integer, # index of fieldname to compare
    condition::Function,
    val::Real,
)
    data = getproperty(network, fieldname)
    return findall(x -> condition.(x, val), data[:, idxComp])
end

function getData(
    network::DislocationNetwork,
    dataField::Symbol, # Field of data to be obtained.
    condField::Symbol, # Field to which the conditioned will be applied.
    idxComp::Integer, # index of condfield to compare
    condition::Function,
    val::Real,
)
    idx = getIndex(network, condField, idxComp, condition, val)
    data = getproperty(network, dataField)
    return data[idx, :]
end

function getData(
    network::DislocationNetwork,
    dataField::Symbol, # Field of data to be obtained.
    condField::Symbol, # Field to which the conditioned will be applied.
    condition::Function,
    val::Real,
)
    idx = getIndex(network, condField, condition, val)
    data = getproperty(network, dataField)
    dims = ndims(data)
    if dims > 1
        if ndims(getproperty(network, condField)) > 1
            idx = Integer(floor(LinearIndices(data)[idx] ./ dims))
        end
        return data[idx, :]
    else
        return data[idx]
    end
end


function getCoord(network::DislocationNetwork, label::Real)
    return network.coord[getIndex(network, label), :]
end
function getCoord(network::DislocationNetwork, index::Vector{Real})
    return network.coord[index, :]
end

abstract type dlnSegment end
struct dlnEdge end
struct dlnScrew end
struct dlnMixed end

# Edge
function makeSegment!(segType::dlnEdge, slipSys::Integer, df::DataFrame)
    slipPlane = convert.(Float64, Vector(df[slipSys, 1:3]))
    bVec = convert.(Float64, Vector(df[slipSys, 4:6]))

    edgeSeg = cross(slipPlane, bVec)
    edgeSeg ./= norm(edgeSeg)

    return edgeSeg
end

# Screw
function makeSegment!(segType::dlnScrew, slipSys::Integer, df::DataFrame)
    screwSeg = convert.(Float64, Vector(df[slipSys, 4:6]))
    screwSeg ./= norm(screwSeg)
    return screwSeg
end
