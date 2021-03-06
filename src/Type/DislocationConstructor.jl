"""
```
SlipSystem(;
    crystalStruct::AbstractCrystalStruct,
    slipPlane::AbstractArray,
    bVec::AbstractArray
)
```
Creates a [`SlipSystem`](@ref).

Ensures `slipPlane ⟂ bVec`.
"""
function SlipSystem(;
    crystalStruct::AbstractCrystalStruct,
    slipPlane::AbstractArray,
    bVec::AbstractArray,
)
    if sum(slipPlane .!= 0) != 0 && sum(bVec .!= 0) != 0
        if ndims(slipPlane) == 1
            @assert slipPlane ⋅ bVec ≈ 0 "SlipSystem: slip plane, n == $(slipPlane), and Burgers vector, b = $(bVec), must be orthogonal."
        else
            idx = findall(x -> !(x ≈ 0), vec(sum(slipPlane .* bVec, dims = 1)))
            @assert isempty(idx) "SlipSystem: entries of the slip plane, n[:, $idx] = $(slipPlane[:, idx]), and Burgers vector, b[:, $idx] = $(bVec[:, idx]), are not orthogonal."
        end
    end

    return SlipSystem(crystalStruct, slipPlane, bVec)
end

"""
```
DislocationParameters(;
    mobility::AbstractMobility,
    dragCoeffs = (edge = 1.0, screw = 2.0, climb = 1e9),
    coreRad = 1.0,
    coreRadMag = 1.0,
    coreEnergy = 1 / (4 * π) * log(coreRad / 0.1),
    minSegLen = 2 * coreRad,
    maxSegLen = 20 * coreRad,
    minArea = minSegLen^2 / sqrt(2),
    maxArea = 100 * minArea,
    collisionDist = minSegLen / 2,
    slipStepCritLen = maxSegLen / 2,
    slipStepCritArea = 0.5 * (slipStepCritLen^2) * sind(1),
    remesh = true,
    collision = true,
    separation = true,
    virtualRemesh = true,
    parCPU = false,
    parGPU = false,
)
```
Creates [`DislocationParameters`](@ref). Automatically calculates derived values, asserts values are reasonable and provides sensible default values.
"""
function DislocationParameters(;
    mobility::AbstractMobility,
    dragCoeffs = (edge = 1.0, screw = 2.0, climb = 1e9),
    coreRad = 1.0,
    coreRadMag = 1.0,
    coreEnergy = 1 / (4 * π) * log(coreRad / 0.1),
    minSegLen = 2 * coreRad,
    maxSegLen = 20 * coreRad,
    minArea = minSegLen^2 / sqrt(2),
    maxArea = 100 * minArea,
    collisionDist = minSegLen / 2,
    slipStepCritLen = maxSegLen / 2,
    slipStepCritArea = 0.5 * (slipStepCritLen^2) * sind(1),
    remesh = true,
    collision = true,
    separation = true,
    virtualRemesh = true,
    parCPU = false,
    parGPU = false,
)
    coreRad == minSegLen == maxSegLen == 0 ? nothing :
    @assert coreRad < minSegLen < maxSegLen
    minArea == maxArea == 0 ? nothing : @assert minArea < maxArea

    return DislocationParameters(
        mobility,
        dragCoeffs,
        coreRad,
        coreRad^2,
        coreRadMag,
        coreEnergy,
        minSegLen,
        maxSegLen,
        minSegLen * 2,
        minSegLen^2,
        minArea,
        maxArea,
        minArea^2,
        maxArea^2,
        collisionDist,
        collisionDist^2,
        slipStepCritLen,
        slipStepCritArea,
        remesh,
        collision,
        separation,
        virtualRemesh,
        parCPU,
        parGPU,
    )
end

"""
```
DislocationLoop(
    loopType::AbstractDlnStr,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystem,
    _slipPlane,
    _bVec,
    label,
    buffer,
    range,
    dist,
)
```
Fallback for creating a generic [`DislocationLoop`](@ref).
"""
function DislocationLoop(
    loopType::AbstractDlnStr,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystemIdx,
    slipSystem,
    label,
    buffer,
    range,
    dist,
)
    nodeTotal::Int = 0
    links = zeros(MMatrix{2, nodeTotal, Int})
    coord = zeros(MMatrix{3, nodeTotal})
    slipPlane = zeros(MMatrix{3, 0})
    bVec = zeros(MMatrix{3, 0})

    return DislocationLoop(
        loopType,
        numSides,
        nodeSide,
        numLoops,
        segLen,
        0,
        label,
        links,
        slipPlane,
        bVec,
        coord,
        buffer,
        range,
        dist,
    )
end
"""
```
DislocationLoop(
    loopType::loopPure,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystem,
    _slipPlane::AbstractArray,
    _bVec::AbstractArray,
    label::AbstractVector{nodeTypeDln},
    buffer,
    range,
    dist::AbstractDistribution,
)
```
Constructor for `loopPure` [`DislocationLoop`](@ref)s.

# Inputs

- `loopType::loopPure`: can be either `loopPrism()` or `loopShear()` to make prismatic or shear loops.
- `numSides`: number of sides in the loop
- `nodeSide`: nodes per side of the loop
- `numLoops`: number of loops to generate when making the dislocation network
- `segLen`: length of each initial dislocation segment
- `slipSystem`: slip system from [`SlipSystem`](@ref) the loop belongs to
- `_slipPlane`: slip plane vector
- `_bVec`: Burgers vector
- `label`: node labels of type [`nodeTypeDln`](@ref)
- `buffer`: buffer for increasing the spread of the generated dislocation loops in the network
- `range`: range on which the loops will be distributed in the network
- `dist`: distribution used to generate the network
"""
function DislocationLoop(
    loopType::loopPure,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystemIdx,
    slipSystem::SlipSystem,
    label::AbstractVector{nodeTypeDln},
    buffer,
    range,
    dist::AbstractDistribution,
)
    nodeTotal = numSides * nodeSide # Calculate total number of nodes for memory allocation.
    numSegLen = length(segLen) # Number of segment lengths.

    # Validate input.
    @assert length(label) == nodeTotal "DislocationLoop: All $nodeTotal nodes must be labelled. There are $(length(label)) labels currently defined."
    @assert numSegLen == nodeTotal "DislocationLoop: All $nodeTotal segments must have their lengths defined. There are $numSegLen lengths currently defined."

    _slipPlane = slipSystem.slipPlane[:, slipSystemIdx]
    _bVec = slipSystem.bVec[:, slipSystemIdx]
    # Normalise vectors.
    elemT = eltype(_slipPlane)
    _slipPlane = _slipPlane / norm(_slipPlane)
    _bVec = _bVec / norm(_bVec)

    # Pick rotation axis for segments.
    # Shear loops rotate around slip plane vector. They have screw, mixed and edge segments.
    if typeof(loopType) == loopShear
        rotAxis = SVector{3, elemT}(_slipPlane[1], _slipPlane[2], _slipPlane[3])
        # Prismatic loops rotate around Burgers vector. All segments are edge.
    else
        rotAxis = SVector{3, elemT}(_bVec[1], _bVec[2], _bVec[3])
        # Catch all.
    end

    # Allocate arrays.
    links = zeros(MMatrix{2, nodeTotal, Int})
    coord = zeros(MMatrix{3, nodeTotal})
    slipPlane = MMatrix{3, nodeTotal}(repeat(_slipPlane, inner = (1, numSegLen)))
    bVec = MMatrix{3, nodeTotal}(repeat(_bVec, inner = (1, numSegLen)))
    seg = zeros(MMatrix{3, numSegLen})

    # Create initial segments.
    staticSlipPlane = SVector{3, elemT}(_slipPlane[1], _slipPlane[2], _slipPlane[3])
    staticBVec = SVector{3, elemT}(_bVec[1], _bVec[2], _bVec[3])
    @inbounds @simd for i in eachindex(segLen)
        seg[:, i] = makeSegment(segEdge(), staticSlipPlane, staticBVec) * segLen[i]
    end

    θ = externalAngle(numSides)  # External angle of a regular polygon with numSides.

    # Loop over polygon's sides.
    origin = SVector{3, elemT}(0, 0, 0)
    @inbounds for i in 1:numSides
        # Index for side i.
        idx = (i - 1) * nodeSide
        # Rotate segments by external angle of polygon to make polygonal loop.
        modIdx = mod(i - 1, numSegLen) + 1
        staticSeg = SVector{3, elemT}(seg[1, modIdx], seg[2, modIdx], seg[3, modIdx])
        rseg = rot3D(staticSeg, rotAxis, origin, θ * (i - 1))
        # DO NOT add @simd, this loop works by adding rseg to the previous coordinate to make the loop. Loop over the nodes per side.
        for j in 1:nodeSide
            # Count first node once.
            if i == j == 1
                coord[:, 1] .= 0 # Initial coordinate is on the origin.
                continue
            end
            if idx + j <= nodeTotal
                # Add segment vector to previous coordinate.
                coord[:, idx + j] += @views coord[:, idx + j - 1] + rseg
            end
        end
    end

    # Find centre of the loop and make it zero.
    meanCoord = mean(coord, dims = 2)
    coord .-= meanCoord

    # Create links matrix.
    @inbounds @simd for j in 1:(nodeTotal - 1)
        links[:, j] .= (j, j + 1)
    end
    links[:, nodeTotal] .= (nodeTotal, 1)

    return DislocationLoop(
        loopType,
        numSides,
        nodeSide,
        numLoops,
        segLen,
        slipSystemIdx,
        label,
        links,
        slipPlane,
        bVec,
        coord,
        buffer,
        range,
        dist,
    )
end
"""
```
DislocationLoop(
    loopType::loopImpure,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystem,
    _slipPlane::AbstractArray,
    _bVec::AbstractArray,
    label::AbstractVector{nodeTypeDln},
    buffer,
    range,
    dist::AbstractDistribution,
)
```
Fallback [`DislocationLoop`](@ref) constructor for other as of yet unimplemented `loopImpure`.
"""
function DislocationLoop(
    loopType::loopImpure,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystemIdx,
    slipSystem::SlipSystem,
    label::AbstractVector{nodeTypeDln},
    buffer,
    range,
    dist::AbstractDistribution,
)
    @warn "DislocationLoop: Constructor for $(typeof(loopType)) not defined, defaulting to prismatic loop."
    return DislocationLoop(
        loopPrism(),
        numSides,
        nodeSide,
        numLoops,
        segLen,
        slipSystemIdx,
        slipSystem,
        label,
        buffer,
        range,
        dist,
    )
end
"""
```
DislocationLoop(;
    loopType::AbstractDlnStr,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystem,
    _slipPlane,
    _bVec,
    label,
    buffer,
    range,
    dist,
)
```
Create a [`DislocationLoop`](@ref).
"""
function DislocationLoop(;
    loopType::AbstractDlnStr,
    numSides,
    nodeSide,
    numLoops,
    segLen,
    slipSystemIdx,
    slipSystem::SlipSystem,
    label,
    buffer,
    range,
    dist,
)
    return DislocationLoop(
        loopType,
        numSides,
        nodeSide,
        numLoops,
        segLen,
        slipSystemIdx,
        slipSystem,
        label,
        buffer,
        range,
        dist,
    )
end

"""
```
DislocationNetwork(;
    links::AbstractArray,
    slipPlane::AbstractArray,
    bVec::AbstractArray,
    coord::AbstractArray,
    label::AbstractVector{nodeTypeDln},
    nodeVel::AbstractArray,
    nodeForce::AbstractArray,
    numNode = length(label),
    numSeg = size(links, 2),
    maxConnect = 4,
    connectivity::AbstractArray = zeros(Int, 1 + 2 * maxConnect, length(label)),
    linksConnect::AbstractArray = zeros(Int, 2, size(links, 2)),
    segIdx::AbstractArray = zeros(Int, size(links, 2), 3),
    segForce::AbstractArray = zeros(3, 2, size(links, 2)),
)
```
Create a [`DislocationNetwork`](@ref). We recommend generating networks from [`DislocationLoop`](@ref) unless you want a special case.
"""
function DislocationNetwork(;
    links::AbstractArray,
    slipPlane::AbstractArray,
    bVec::AbstractArray,
    coord::AbstractArray,
    label::AbstractVector{nodeTypeDln},
    nodeVel::AbstractArray,
    nodeForce::AbstractArray,
    numNode = length(label),
    numSeg = size(links, 2),
    maxConnect = 4,
    connectivity::AbstractArray = zeros(Int, 1 + 2 * maxConnect, length(label)),
    linksConnect::AbstractArray = zeros(Int, 2, size(links, 2)),
    extSeg::AbstractArray = zeros(Bool, size(links, 2)),
    segIdx::AbstractArray = zeros(Int, size(links, 2), 3),
    segForce::AbstractArray = zeros(3, 2, size(links, 2)),
)
    @assert size(links, 1) == size(segForce, 2) == 2
    @assert size(bVec, 1) == size(slipPlane, 1) == size(coord, 1) size(segForce, 1) == 3
    @assert size(links, 2) == size(bVec, 2) == size(slipPlane, 2) == size(segForce, 3)
    @assert size(coord, 2) == length(label)
    @assert length(numNode) == length(numSeg) == 1

    typeof(numNode) <: AbstractVector ? numNodeArr = numNode : numNodeArr = [numNode]
    typeof(numSeg) <: AbstractVector ? numSegArr = numSeg : numSegArr = [numSeg]

    return DislocationNetwork(
        numNodeArr,
        numSegArr,
        maxConnect,
        label,
        links,
        connectivity,
        linksConnect,
        slipPlane,
        extSeg,
        segIdx,
        bVec,
        coord,
        nodeVel,
        nodeForce,
        segForce,
    )
end
"""
```
DislocationNetwork(
    sources::DislocationLoopCollection,
    maxConnect = 4,
    args...;
    memBuffer = nothing,
    checkConsistency = true,
    kw...,
)
```
Creates a [`DislocationNetwork`](@ref) out of a [`DislocationLoopCollection`](@ref).

# Inputs

- `args...` are optional arguments that will be passed on to the [`loopDistribution`](@ref) function which distributes the loops in `sources` according to the type of their `dist` variable.
- `kw...` are optional keyword arguments that will also be passed to `loopDistribution`.
- `memBuffer` is the numerical value for allocating memory in advance. The quantity, `memBuffer × N`, where `N` is the total number of nodes in `sources`, will be the initial number of entries allocated in the matrices that keep the network's data. If no `memBuffer` is provided, the number of entries allocated will be `round(N*log2(N)).
"""
function DislocationNetwork(
    sources::DislocationLoopCollection,
    maxConnect = 4,
    args...;
    memBuffer = nothing,
    checkConsistency = true,
    kw...,
)
    # Initialisation.
    nodeTotal::Int = 0
    lims = zeros(MMatrix{3, 2})
    # Calculate node total.
    for i in eachindex(sources)
        nodeTotal += sources[i].numLoops * length(sources[i].label)
    end
    # Memory buffer.
    isnothing(memBuffer) ? nodeBuffer = Int(round(nodeTotal * log2(nodeTotal))) :
    nodeBuffer = nodeTotal * Int(memBuffer)

    # Allocate memory.
    links = zeros(Int, 2, nodeBuffer)
    slipPlane = zeros(3, nodeBuffer)
    bVec = zeros(3, nodeBuffer)
    coord = zeros(3, nodeBuffer)
    label = zeros(nodeTypeDln, nodeBuffer)
    nodeVel = zeros(Float64, 3, nodeBuffer)
    nodeForce = zeros(Float64, 3, nodeBuffer)
    numNode = nodeTotal
    numSeg = nodeTotal
    segForce = zeros(Float64, 3, 2, nodeBuffer)

    initIdx = 1
    # Fill the matrices that will make up the network.
    makeNetwork!(
        links,
        slipPlane,
        bVec,
        coord,
        label,
        sources,
        lims,
        initIdx,
        args...;
        kw...,
    )

    # Calculate number of segments and indexing matrix.
    segIdx, extSeg = getSegmentIdx(links, label)
    # Generate connectivity and linksConnect matrix.
    connectivity, linksConnect = makeConnect(links, maxConnect)

    # Create network.
    network = DislocationNetwork(
        [numNode],
        [numSeg],
        maxConnect,
        label,
        links,
        connectivity,
        linksConnect,
        slipPlane,
        extSeg,
        segIdx,
        bVec,
        coord,
        nodeVel,
        nodeForce,
        segForce,
    )

    # Check that the network is generated properly.
    checkConsistency ? checkNetwork(network) : nothing

    return network
end
"""
```
DislocationNetwork!(
    network::DislocationNetwork,
    sources::DislocationLoopCollection,
    args...;
    memBuffer = nothing,
    checkConsistency = true,
    kw...,
)
```
Adds a [`DislocationLoopCollection`](@ref) to an existing [`DislocationNetwork`](@ref).
"""
function DislocationNetwork!(
    network::DislocationNetwork,
    sources::DislocationLoopCollection,
    args...;
    memBuffer = nothing,
    checkConsistency = true,
    kw...,
)
    # For comments see DislocationNetwork. It is a 1-to-1 translation except that this one modifies the network in-place.

    iszero(network) && return DislocationNetwork(
        sources,
        args...;
        checkConsistency = checkConsistency,
        kw...,
    )

    nodeTotal::Int = 0
    lims = zeros(MMatrix{3, 2})
    for i in eachindex(sources)
        nodeTotal += sources[i].numLoops * length(sources[i].label)
    end
    numNode = nodeTotal

    # Allocate memory.
    available = length(findall(x -> x == noneDln, network.label))
    if nodeTotal > available
        newEntries = Int(round(nodeTotal * log2(nodeTotal)))
        network = push!(network, newEntries)
    end

    links = network.links
    slipPlane = network.slipPlane
    bVec = network.bVec
    coord = network.coord
    label = network.label

    # Since the network has already been created, initIdx is the next available index to store new data.
    initIdx::Int = 1
    first = findfirst(x -> x == noneDln, label)
    isnothing(first) ? initIdx = 1 : initIdx = first
    makeNetwork!(
        links,
        slipPlane,
        bVec,
        coord,
        label,
        sources,
        lims,
        initIdx,
        args...;
        kw...,
    )
    network.numNode[1] += numNode
    network.numSeg[1] += numNode

    getSegmentIdx!(network)
    makeConnect!(network)

    checkConsistency ? checkNetwork(network) : nothing
    return network
end

"""
```
makeNetwork!(
    links,
    slipPlane,
    bVec,
    coord,
    label,
    sources,
    lims,
    initIdx,
    args...;
    kw...,
)
```
Internal function called by [`DislocationNetwork`](@ref) to fill the arrays that define the network.
"""
function makeNetwork!(
    links,
    slipPlane,
    bVec,
    coord,
    label,
    sources,
    lims,
    initIdx,
    args...;
    kw...,
)
    nodeTotal::Int = 0
    elemT = eltype(coord)
    @inbounds @simd for i in eachindex(sources)
        idx = initIdx + nodeTotal
        nodesLoop = length(sources[i].label)
        numLoops = sources[i].numLoops
        numNodes = numLoops * nodesLoop
        # Calculate the normalised displacements for all loops in sources[i] according to their distribution.
        disp = loopDistribution(sources[i].dist, numLoops, args...; kw...)
        # Calculate the real spatial limits of the distributions.
        limits!(lims, mean(sources[i].segLen), sources[i].range, sources[i].buffer)
        # Fill out the data for all loops specified in sources[i].
        for j in 1:numLoops
            # The number of nodes in the loop is nodesLoop, so that's our stride inside sources[i]
            idxi = idx + (j - 1) * nodesLoop
            idxf = idxi + nodesLoop - 1
            # Links are numbered sequentially in network so we have to account for previously assigned links.
            links[:, idxi:idxf] .=
                sources[i].links[:, 1:nodesLoop] .+ (nodeTotal + initIdx - 1)
            slipPlane[:, idxi:idxf] = sources[i].slipPlane[:, 1:nodesLoop]
            bVec[:, idxi:idxf] = sources[i].bVec[:, 1:nodesLoop]
            coord[:, idxi:idxf] = sources[i].coord[:, 1:nodesLoop]
            label[idxi:idxf] = sources[i].label[1:nodesLoop]
            # Map the normalised displacements to real space using the real limits and translate the nodes' coordinates accordingly.
            staticDisp = SVector{3, elemT}(disp[1, j], disp[2, j], disp[3, j])
            viewCoord = @view coord[:, idxi:idxf]
            translatePoints!(viewCoord, lims, staticDisp)
            nodeTotal += nodesLoop
        end
    end
    return nothing
end
