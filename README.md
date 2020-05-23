# DDD

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://dcelisgarza.github.io/DDD.jl/stable) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://dcelisgarza.github.io/DDD.jl/dev)
[![Build Status](https://travis-ci.com/dcelisgarza/DDD.jl.svg?branch=master)](https://travis-ci.com/dcelisgarza/DDD.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/dcelisgarza/DDD.jl?svg=true)](https://ci.appveyor.com/project/dcelisgarza/DDD-jl)
[![Codecov](https://codecov.io/gh/dcelisgarza/DDD.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dcelisgarza/DDD.jl)
[![Coveralls](https://coveralls.io/repos/github/dcelisgarza/DDD.jl/badge.svg?branch=master)](https://coveralls.io/github/dcelisgarza/DDD.jl?branch=master)

New generation of 3D Discrete Dislocation Dynamics codes.

Dislocation dynamics is a complex field with an enormous barrier to entry. The aim of this project is to create a codebase that is:

- Easy to use.
- Easy to maintain.
- Easy to develop for.
- Modular.
- Idiot proof.
- Well documented and tested.
- Performant.
- Easily parallelisable.

## Current TODO:
- [ ] Custom 3-vec type, place x,y,z coordinates in contiguous memory instead of columns, ie [x1 y1 z1; x2 y2 z2] -> [x1;y1;z1;x2;y2;z2], have to define custom array type, `getindex(arr, (a,b)) = arr[3*(a-1)+b]`, out of bounds and all the rest. Watch [this](https://www.youtube.com/watch?v=jS9eouMJf_Y).
- [x] Generate docs
  - [x] Documented Misc
  - [ ] Upload docs
- [ ] Optimise
- [ ] Specialised integrator
  - [ ] Perhaps later make use of [DifferentialEquations.jl](https://github.com/SciML/DifferentialEquations.jl) for their stepping and event handling routines.
- [ ] Calculate segment-segment interactions.
- [ ] Mobility laws
  - [ ] BCC
  - [ ] FCC
- [ ] Topology operations
  - [ ] Split
  - [ ] Merge
- [ ] Couple to FEM, perhaps use a package from [JuliaFEM](http://www.juliafem.org/).
  - [ ] Boundary conditions
    - [ ] Neuman
    - [ ] Dirichlet
  - [ ] Displacements
  - [ ] Tractions

# Example

## Initialisation

Before running a simulation we need to initialise the simulation. For this example, we will use the keyword initialisers because they automatically calculate derived quantities, perform input validations, provide default values, and are make for self-documenting code.

Dislocations live in a material, as such we need a few constants that describe it. These are encapsulated in the immutable^[1] structure `MaterialP`. Note that we use unicode to denote variables as per convention written `\mu -> μ` and `\nu -> ν`. Here we create a basic material.
```julia
julia> materialP = MaterialP(;
          μ = 1.0,                  # Shear modulus.
          μMag = 145e3,             # Shear modulus magnitude, MPa.
          ν = 0.28,                 # Poisson ratio.
          E = 1.0,                  # Young's modulus, MPa.
          crystalStruct = BCC()     # Crystal structure.
        )
MaterialP{Float64,BCC}(1.0, 145000.0, 0.28, 1.0, 1.3888888888888888, 0.3888888888888889, 0.07957747154594767, 0.039788735772973836, 0.11052426603603843, BCC())
```
Note that a few extra constants have been automatically calculated by the constructor. We find what these correspond to using the `fieldnames()` on the type of `materialP`, which is `MaterialP`.
```julia
julia> fieldnames(typeof(materialP))
(:μ, :μMag, :ν, :E, :omνInv, :νomνInv, :μ4π, :μ8π, :μ4πν, :crystalStruct)
```
Where `omνInv = 1/(1-ν)`, `νomνInv = v/(1-ν)`, `μ4π = μ / (4π)`, `μ8π = μ / (8π)`, `μ4πν = μ/[4π(1-ν)]`. These precomputed variables are used in various places and are there to avoid recalculating them later.

Our dislocations also have certain constant characteristics that are encapsulated in their own immutable structure, `DislocationP`. These parameters are somewhat arbitrary as long as they approximately hold certain proportions.
```julia
julia> dislocationP = DislocationP(;
          coreRad = 90.0,       # Dislocation core radius, referred to as a.
          coreRadMag = 3.2e-4,  # Magnitude of the core radius.
          minSegLen = 320.0,    # Minimum segment length.
          maxSegLen = 1600.0,   # Maximum segment length.
          minArea = 45000.0,    # Minimum allowable area enclosed by two segments.
          maxArea = 20*45000.0, # Maximum allowable area enclosed by two segments.
          maxConnect = 4,       # Maximum number of connections a node can have.
          remesh = true,        # Flag for remeshing.
          collision = true,     # Flag for collision checking.
          separation = true,    # Flag for node separation.
          virtualRemesh = true, # Flag for remeshing virtual nodes.
          edgeDrag = 1.0,       # Drag coefficient for edge segments.
          screwDrag = 2.0,      # Drag coefficient for screw segments.
          climbDrag = 1e10,     # Drag coefficient along the climb direction.
          lineDrag = 0.0,       # Drag coefficient along the line direction.
          mobility = mobBCC(),  # Mobility type for mobility function specialisation.
        )
DislocationP{Float64,Int64,Bool,mobBCC}(90.0, 8100.0, 0.00032, 320.0, 1600.0, 45000.0, 900000.0, 4, true, true, true, true, 1.0, 2.0, 1.0e10, 0.0, mobBCC())
```

The integration parameters are placed into the following mutable structure.
```julia
julia> integrationP = IntegrationP(;
          dt = 1e3,
          tmin = 0.0,
          tmax = 1e10,
          method = CustomTrapezoid(),
          abstol = 1e-6,
          reltol = 1e-6,
          time = 0.0,
          step = 0,
        )
IntegrationP{Float64,CustomTrapezoid,Int64}(1000.0, 0.0, 1.0e10, CustomTrapezoid(), 1.0e-6, 1.0e-6, 0.0, 0)
```
!!! warning "This will change"

    `IntegrationP` will undergo revisions. Probably be split into two, or perhaps eliminated completely in order to use/extend the state of the art `DifferentialEquations.jl` framework.

Within a given material, we have multiple slip systems, which can be loaded into their own immutable structure. Here we only define a single slip system, but we have the capability of adding more by making the `slipPlane` and `bVec` arguments `n × 3` matrices rather than vectors.
```julia
julia> slipSystems = SlipSystem(;
          crystalStruct = BCC(),
          slipPlane = [1.0; 1.0; 1.0],  # Slip plane.
          bVec = [1.0; -1.0; 0.0]       # Burgers vector.
       )
SlipSystem{BCC,Array{Float64,1}}(BCC(), [1.0, 1.0, 1.0], [1.0, -1.0, 0.0])
```
!!! warning "This may change"

    This may change to perform validity checks regarding the relationship between burgers vector and slip plane.

We also need dislocation sources. We make use of Julia's type system to create standard functions for loop generation. We provide a way of easily and quickly generating loops whose segments inhabit the same slip system. However, new `DislocationLoop()` methods can be made by subtyping `AbstractDlnStr`, and dispatching on the new type. One may of also course also use the default constructor and build the initial structures manually.

Here we make a regular pentagonal prismatic dislocation loop, and a regular hexagonal prismatic dislocation loop. Note that the segments may be of arbitrary length, but having asymmetric sides may result in a very ugly and irregular dislocations that may be unphysical or may end up remeshing once the simulation gets under way. As such we recommend making the segment lengths symmetric.
```julia
julia> prisPentagon = DislocationLoop(
          loopPrism();    # Prismatic loop, all segments are edge segments.
          numSides = 5,   # 5-sided loop.
          nodeSide = 1,   # One node per side, if 1 nodes will be in the corners.
          numLoops = 20,  # Number of loops of this type to generate when making a network.
          segLen = 10 * ones(5),  # Length of each segment between nodes, equal to the number of nodes.
          slipSystem = 1, # Slip System (assuming slip systems are stored in a file, this is the index).
          _slipPlane = slipSystem.slipPlane,  # Slip plane of the segments.
          _bVec = slipSystem.bVec,            # Burgers vector of the segments.
          label = nodeType[1; 2; 1; 2; 1],    # Node labels, has to be equal to the number of nodes.
          buffer = 0.0,   # Buffer to increase the dislocation spread.
          range = Float64[-100 -100 -100;   # Distribution range
                            100 100 100],   # [xmin, ymin, zmin; xmax, ymax, zmax].
          dist = Rand(),  # Loop distribution.
      )
DislocationLoop{loopPrism,Int64,Array{Float64,1},Int64,Array{Int64,2},Array{Float64,2},Array{nodeType,1},Float64,Rand}(loopPrism(), 5, 1, 20, [10.0, 10.0, 10.0, 10.0, 10.0], 1, [1 2; 2 3; … ; 4 5; 5 1], [0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258; … ; 0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258], [0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0; … ; 0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0], [-1.932030909139515 -1.932030909139515 -8.055755266097462; 4.820453044614565 4.820453044614565 -5.087941102678986; … ; -1.785143053581134 -1.785143053581134 8.123251093712414; -6.014513813778146 -6.014513813778146 0.10921054317980072], nodeType[DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob], 0.0, [-100.0 -100.0 -100.0; 100.0 100.0 100.0], Rand())

julia> shearHexagon = DislocationLoop(
          loopShear();    # Shear loop
          numSides = 6,
          nodeSide = 3,   # 3 nodes per side, it devides the side into equal segments.
          numLoops = 20,
          segLen = 10 * ones(3 * 6) / 3,  # The hexagon's side length is 10, each segment is 10/3.
          slipSystem = 1,
          _slipPlane = slipSystem.slipPlane,
          _bVec = slipSystem.bVec,
          label = nodeType[1; 2; 1; 2; 1; 2; 1; 2; 1; 2; 1; 2; 1; 2; 1; 2; 1; 2],
          buffer = 0.0,
          range = Float64[-100 -100 -100; 100 100 100],
          dist = Rand(),
      )
DislocationLoop{loopShear,Int64,Array{Float64,1},Int64,Array{Int64,2},Array{Float64,2},Array{nodeType,1},Float64,Rand}(loopShear(), 6, 3, 20, [3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335, 3.3333333333333335], 1, [1 2; 2 3; … ; 17 18; 18 1], [0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258; … ; 0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258], [0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0; … ; 0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0], [5.4433105395181745 -6.804138174397717 1.3608276348795434; 6.804138174397718 -5.443310539518174 -1.3608276348795434; … ; 1.360827634879545 -6.804138174397715 5.443310539518167; 4.082482904638632 -8.164965809277255 4.0824829046386215], nodeType[DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix], 0.0, [-100.0 -100.0 -100.0; 100.0 100.0 100.0], Rand())
```
The dislocation loops will be centred about the origin, but the `range`, `buffer` and `dist` parameters will distribute the dislocations about the simulation domain once the dislocation network is generated. The type of `dist` must be a concrete subtype of `AbstractDistribution` and `loopDistribution()` method should dispatch on this concrete subtype. If a non-suported distribution is required, you only need to create a concrete subtype of `AbstractDistribution` and a new method of `loopDistribution()` to dispatch on the new type. This is all the reworking needed, since multiple dispatch will take care of any new distributions when generating the dislocation network.

Note also the array of `nodeType`, this is an enumerated type which ensures node types are limited to only those supported by the model, lowers memory footprint and increases performance.

We can then plot our loops to see our handy work. We use `plotlyjs()` because it provides a nice interactive experience, but of course, since this is Julia any plotting backend will work. Note that since they have the same slip system but one is a shear and the other a prismatic loop, they are orthogonal to each other.
```julia
julia> using Plots
julia> plotlyjs()
julia> fig1 = plotNodes(
          shearHexagon,
          m = 1,
          l = 3,
          linecolor = :blue,
          markercolor = :blue,
          legend = false,
          size = (750, 750),
        )
julia> plotNodes!(fig1, prisPentagon, m = 1, l = 3,
                  linecolor = :red, markercolor = :red, legend = false)
julia> plot!(fig1, camera=(100,35))
```
![loops](/examples/loops.png)

After generating our primitive loops, we can create a network using either a vector of dislocation loops or a single dislocation loop. The network may also be created manually, and new constructor methods may be defined for bespoke cases. For our purposes, we use the constructor that dispatches on `Union{DislocationLoop, AbstractVector{<:DislocationLoop}}`, meaning a single variable whose type is `DislocationLoop` or a vector of them. Here we use a vector with both our loop structures.

Since the dislocation network is a constantly evolving entity, this necessarily means this is a mutable structure.
```julia
julia> network = DislocationNetwork(
          [shearHexagon, prisPentagon]; # Dispatch type, bespoke functions dispatch on this.
          memBuffer = 1 # Buffer for memory allocation.
       )
DislocationNetwork{Array{Int64,2},Array{Float64,2},Array{nodeType,1},Int64,Array{Int64,2}}([1 2; 2 3; … ; 459 460; 460 456], [0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258; … ; 0.5773502691896258 0.5773502691896258 0.5773502691896258; 0.5773502691896258 0.5773502691896258 0.5773502691896258], [0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0; … ; 0.7071067811865475 -0.7071067811865475 0.0; 0.7071067811865475 -0.7071067811865475 0.0], [41.91082711407302 54.62017549955427 30.676858569059906; 43.27165474895257 55.98100313443381 27.955203299300816; … ; -28.839667409599297 -72.8714555754737 -31.14471190957846; -33.06903816979631 -77.10082633567072 -39.158752460111074], nodeType[DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix  …  DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intMob, DDD.intFix, DDD.intMob, DDD.intFix, DDD.intMob], [0.0 0.0 0.0; 0.0 0.0 0.0; … ; 0.0 0.0 0.0; 0.0 0.0 0.0], [0.0 0.0 0.0; 0.0 0.0 0.0; … ; 0.0 0.0 0.0; 0.0 0.0 0.0], 460, 460, 4, [2 1 … 0 0; 2 1 … 0 0; … ; 2 458 … 0 0; 2 459 … 0 0], [1 1; 2 1; … ; 2 1; 2 2], [1 1 2; 2 2 3; … ; 459 459 460; 460 460 456])
```
This method automatically takes the previously defined loops and scatters them according to the parameters provided in the `DislocationLoop` structure. Furthermore, the `memBuffer` defaults to 10. The number of entries allocated for the matrices is the total number of nodes in the network times `memBuffer`. Here we allocate enough memory for all the nodes but no more. Since julia is dynamic we can allocate memory when needed. However for performance reasons it is advisable to minimise memory management as much as possible.

This function will also automatically calculate other quantities to keep track of the network's links, nodes and segments.
```julia
julia> fieldnames(typeof(network))
(:links, :slipPlane, :bVec, :coord, :label, :segForce, :nodeVel, :numNode, :numSeg, :maxConnect, :connectivity, :linksConnect, :segIdx)
```

We can view our network with special plotting functions, here we use `plotlyjs()` because it provides a nice interactive viewing environment.
```julia
julia> fig2 = plotNodes(
          network,
          m = 1,
          l = 3,
          linecolor = :blue,
          markercolor = :blue,
          legend = false,
          size = (750, 750),
        )
julia> plot!(fig2, camera=(110,40))
```
![network](/examples/network.png)

[^1]: Immutability is translated into code performance.

## IO

The package provides a way to load and save its parameters using `JSON` files. While this is *not* the most performant format for IO, it is a popular and portable, web-friendly file format that is very human readable (and therefore easy to manually create).

This is a sample `JSON` file for a loop type. They can be compactified by editors to decrease storage space by removing unnecessary line breaks and spaces. Here we show a somewhat longified view which is very human readable and fairly easy to create manually.
```JSON
[
  {
    "loopType": "DDD.loopPrism()",
    "numSides": 4,
    "nodeSide": 2,
    "numLoops": 1,
    "segLen": [1, 1, 1, 1, 1, 1, 1, 1],
    "slipSystem": 1,
    "label": [2, 1, 2, 1, 2, 1, 2, 1],
    "buffer": 0,
    "range": [[0, 0], [0, 0], [0, 0]],
    "dist": "DDD.Zeros()"
  }
]
```
`JSON` files are representations of dictionaries with `(key, value)` pairs, which are analogous to the `(key, value)` pair of structures. This makes it so any changes to any structure will automatically be taken care of by the `JSON` library, even preserving array shapes regardless of whether they are column- or row-major. It also guarantees portability between ecosystems since they can easily be loaded into dictionaries.

They also have the added advantage of being designed for sending over the web, so they have good compression ratios and enable open science by not requiring specialised IO to view.

For the sake of open, reproducible and portable science it is recommended users make use of `JSON` or a standard delimited file format for their IO. If IO is a performance bottleneck these are some incremental steps one should take to improve it before creating a custom IO format.
1. Use buffered IO.
1. Use Julia's in-built task and asyncronous functionality via `tasks` and `async` for either multiple IO streams or an asyncronous IO process while the other threads/cores carry on with the simulation.
1. Use `BSON`, `JSON`'s binary counterpart, though this may break compatibility with other systems, particularly those with different word size and architecture.
1. Use `DelimitedFiles`.
1. Use binary streams.
1. Create your own format and IO stream.
