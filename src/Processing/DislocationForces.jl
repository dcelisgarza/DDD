"""
```
calcSegForce(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    mesh::AbstractMesh,
    forceDisplacement::ForceDisplacement,
    network::DislocationNetwork,
    idx = nothing,
)

calcSegForce!(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    mesh::AbstractMesh,
    forceDisplacement::ForceDisplacement,
    network::DislocationNetwork,
    idx = nothing,
)
```
Compute total force on dislocation segments.
"""
function genSegForce(mutating)
    if !mutating
        name = :calcSegForce
        body = quote
            isnothing(idx) ? numSeg = network.numSeg[1] : numSeg = length(idx)

            PKForce = calcPKForce(mesh, forceDisplacement, network, idx)
            selfForce = calcSelfForce(dlnParams, matParams, network, idx)
            segForce = calcSegSegForce(dlnParams, matParams, network, idx)

            @inbounds for i in 1:numSeg
                for j in 1:2
                    @simd for k in 1:3
                        segForce[k, j, i] += selfForce[j][k, i] + 0.5 * PKForce[k, i]
                    end
                end
            end

            return segForce
        end
    else
        name = :calcSegForce!
        body = quote
            if isnothing(idx)
                # If no index is provided, calculate forces for all segments.
                numSeg = network.numSeg[1]
                range = 1:numSeg
            else
                # Else, calculate forces only on idx.
                range = idx
            end
            network.segForce[:, :, range] .= 0

            calcPKForce!(mesh, forceDisplacement, network, idx)
            calcSelfForce!(dlnParams, matParams, network, idx)
            calcSegSegForce!(dlnParams, matParams, network, idx)

            return nothing
        end
    end

    ex = quote
        function $name(
            dlnParams::DislocationParameters,
            matParams::MaterialParameters,
            mesh::AbstractMesh,
            forceDisplacement::ForceDisplacement,
            network::DislocationNetwork,
            idx = nothing,
        )
            return $body
        end
    end
    return ex
end
# Generate calcSegForce!(dlnParams::DislocationParameters, matParams::MaterialParameters, mesh::AbstractMesh, forceDisplacement::ForceDisplacement, network::DislocationNetwork, idx = nothing)
eval(genSegForce(true))
# Generate calcSegForce(dlnParams::DislocationParameters, matParams::MaterialParameters, mesh::AbstractMesh, forceDisplacement::ForceDisplacement, network::DislocationNetwork, idx = nothing)
eval(genSegForce(false))

"""
```
calc_σHat(
    mesh::RegularCuboidMesh{T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14} where {T1 <: LinearElement,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14},
    forceDisplacement::ForceDisplacement,
    x0,
)
```
Compute the stress, `̂σ`, on a dislocation segment `x0` as a result of body forces on a [`RegularCuboidMesh`](@ref) composed of `LinearElement()`(@ref). Used by [`calcPKForce`](@ref).

## Returns
```
σ = [
        σxx σxy σxz
        σxy σyy σyz
        σxz σyz σzz
    ]
```
"""
function calc_σHat(
    mesh::RegularCuboidMesh{
        T1,
        T2,
        T3,
        T4,
        T5,
        T6,
        T7,
        T8,
        T9,
        T10,
        T11,
        T12,
        T13,
        T14,
    } where {T1 <: LinearElement, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14},
    forceDisplacement::ForceDisplacement,
    x0,
)
    C = mesh.C
    connectivity = mesh.connectivity
    coord = mesh.coord
    elemT = eltype(coord)
    uHat = forceDisplacement.uHat

    # Unroll structure.
    mx = mesh.mx        # num elem in x
    my = mesh.my        # num elem in y
    mz = mesh.mz        # num elem in z
    wInv = 1 / mesh.w   # 1 / width
    hInv = 1 / mesh.h   # 1 / height
    dInv = 1 / mesh.d   # 1 / depth

    x, y, z = x0

    # Find element index closest to the coordinate.
    i::Int = clamp(ceil(x * wInv), 1, mx)
    j::Int = clamp(ceil(y * hInv), 1, my)
    k::Int = clamp(ceil(z * dInv), 1, mz)

    # Calculate index of the elements.
    idx = i + (k - 1) * mx + (j - 1) * mx * mz

    # Diametrically opposed points in a cubic element.
    n1 = connectivity[1, idx]
    n7 = connectivity[7, idx]

    # Find element midpoints.
    xc = 0.5 * (coord[1, n1] + coord[1, n7])
    yc = 0.5 * (coord[2, n1] + coord[2, n7])
    zc = 0.5 * (coord[3, n1] + coord[3, n7])

    # Setting up Jacobian.
    ds1dx = 2 * wInv
    ds2dy = 2 * hInv
    ds3dz = 2 * dInv

    s1 = (x - xc) * ds1dx
    s2 = (y - yc) * ds2dy
    s3 = (z - zc) * ds3dz

    pm1 = (-1, 1, 1, -1, -1, 1, 1, -1)
    pm2 = (1, 1, 1, 1, -1, -1, -1, -1)
    pm3 = (-1, -1, 1, 1, -1, -1, 1, 1)

    ds1dx /= 8
    ds2dy /= 8
    ds3dz /= 8

    B = zeros(elemT, 6, 24)
    U = MVector{24, elemT}(zeros(24))
    @inbounds @simd for i in 1:8
        dNdS1 = pm1[i] * (1 + pm2[i] * s2) * (1 + pm3[i] * s3) * ds1dx
        dNdS2 = (1 + pm1[i] * s1) * pm2[i] * (1 + pm3[i] * s3) * ds2dy
        dNdS3 = (1 + pm1[i] * s1) * (1 + pm2[i] * s2) * pm3[i] * ds3dz
        # Indices calculated once for performance.
        idx1 = 3 * i
        idx2 = 3 * (i - 1)
        # Linear index of the z-coordinate of node i of the idx'th FE element.
        idx3 = 3 * connectivity[i, idx]

        # Constructing the Jacobian for node i.
        B[1, idx2 + 1] = dNdS1
        B[2, idx2 + 2] = dNdS2
        B[3, idx2 + 3] = dNdS3

        B[4, idx2 + 1] = B[2, idx2 + 2]
        B[4, idx2 + 2] = B[1, idx2 + 1]

        B[5, idx2 + 1] = B[3, idx1 + 0]
        B[5, idx1 + 0] = B[1, idx2 + 1]

        B[6, idx2 + 2] = B[3, idx1 + 0]
        B[6, idx1 + 0] = B[2, idx2 + 2]

        # Building uhat for the nodes of the finite element closest to the point of interest. From idx3, the finite element is the i2'th element and the the node we're looking at is the j'th node. The node index is idx3 = label[i2,j].
        U[idx1 - 2] = uHat[idx3 - 2]
        U[idx1 - 1] = uHat[idx3 - 1]
        U[idx1 - 0] = uHat[idx3 - 0]
    end

    # Isotropic stress tensor in vector form.
    # σ_vec[1] = σ_xx
    # σ_vec[2] = σ_yy
    # σ_vec[3] = σ_zz
    # σ_vec[4] = σ_xy = σ_yx
    # σ_vec[5] = σ_xz = σ_xz
    # σ_vec[6] = σ_yz = σ_zy
    # B*U transforms U from the nodes of the closest finite element with index i2=idx[i] to the point of interest [s1, s2, s3].
    σ_vec = C * B * U
    σ = SMatrix{3, 3, elemT}(
        σ_vec[1],
        σ_vec[4],
        σ_vec[5],
        σ_vec[4],
        σ_vec[2],
        σ_vec[6],
        σ_vec[5],
        σ_vec[6],
        σ_vec[3],
    )

    return σ
end

"""
```
calcPKForce(
    mesh::AbstractMesh,
    forceDisplacement::ForceDisplacement,
    network::DislocationNetwork,
    idx = nothing,
)

calcPKForce!(
    mesh::AbstractMesh,
    forceDisplacement::ForceDisplacement,
    network::DislocationNetwork,
    idx = nothing,
)
```
Compute the Peach-Koehler force on segments by using [`calc_σHat`](@ref).

``
f = (\\hat{\\mathbb{\\sigma}} \\cdot \\overrightarrow{b}) \\times \\overrightarrow{t}
``
"""
function genPKForce(mutating)
    if !mutating
        name = :calcPKForce

        ifIdx = quote
            if isnothing(idx)
                # If no index is provided, calculate forces for all segments.
                numSeg = network.numSeg[1]
                idx = 1:numSeg
            else
                # Else, calculate forces only on idx.
                numSeg = length(idx)
            end
        end

        accumulator = quote
            PKForce = zeros(elemT, 3, numSeg)      # Vector of PK force.
        end

        accumulate = quote
            @inbounds @simd for j in 1:3
                PKForce[j, i] = pkForce[j]
            end
        end

        retVal = quote
            return PKForce
        end
    else
        name = :calcPKForce!

        ifIdx = quote
            # Indices for self force.
            if isnothing(idx)
                # If no index is provided, calculate forces for all segments.
                numSeg = network.numSeg[1]
                idx = 1:numSeg
            end
        end

        accumulator = quote
            segForce = network.segForce
        end

        accumulate = quote
            idxi = idx[i]
            for j in 1:3
                segForce[j, 1, idxi] += pkForce[j] / 2
                segForce[j, 2, idxi] += pkForce[j] / 2
            end
        end

        retVal = quote
            return nothing
        end
    end

    ex = quote
        function $name(
            mesh::AbstractMesh,
            forceDisplacement::ForceDisplacement,
            network::DislocationNetwork,
            idx = nothing,
        )
            # Unroll constants.
            numSeg = network.numSeg[1]
            segIdx = network.segIdx
            bVec = network.bVec
            coord = network.coord
            elemT = eltype(network.coord)

            $ifIdx

            idxBvec = @view segIdx[idx, 1]
            idxNode1 = @view segIdx[idx, 2]
            idxNode2 = @view segIdx[idx, 3]
            # Un normalised segment vectors. Use views for speed.
            bVec = @view bVec[:, idxBvec]
            tVec = @views coord[:, idxNode2] - coord[:, idxNode1]
            midNode = @views (coord[:, idxNode2] + coord[:, idxNode1]) / 2

            $accumulator
            # Loop over segments.
            @inbounds @simd for i in eachindex(idx)
                x0 = SVector{3, elemT}(midNode[1, i], midNode[2, i], midNode[3, i])
                b = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
                t = SVector{3, elemT}(tVec[1, i], tVec[2, i], tVec[3, i])
                σHat = calc_σHat(mesh, forceDisplacement, x0)
                pkForce = (σHat * b) × t
                $accumulate
            end
            $retVal
        end
    end
    return ex
end
# Generate calcPKForce!(mesh::AbstractMesh, forceDisplacement::ForceDisplacement, network::DislocationNetwork, idx = nothing)
eval(genPKForce(true))
# Generate calcPKForce(mesh::AbstractMesh, forceDisplacement::ForceDisplacement, network::DislocationNetwork, idx = nothing)
eval(genPKForce(false))

"""
```
calcSelfForce(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)

calcSelfForce!(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)
```
Compute the self-interaction force on dislocation segments. `calcSelfForce!` for its mutating form.
"""
function genSelfForce(mutating)
    if !mutating
        name = :calcSelfForce

        ifIdx = quote
            if isnothing(idx)
                # If no index is provided, calculate forces for all segments.
                numSeg = network.numSeg[1]
                idx = 1:numSeg
            else
                # Else, calculate forces only on idx.
                numSeg = length(idx)
            end
        end

        accumulator = quote
            selfForceNode2 = zeros(3, numSeg)
        end

        accumulate = quote
            selfForceNode2[:, i] = torTot * bEdgeVec - lonCore * tVecI
        end

        retVal = quote
            selfForceNode1 = -selfForceNode2
            return selfForceNode1, selfForceNode2
        end

    else
        name = :calcSelfForce!

        ifIdx = quote
            if isnothing(idx)
                # If no index is provided, calculate forces for all segments.
                numSeg = network.numSeg[1]
                idx = 1:numSeg
            end
        end

        accumulator = quote
            segForce = network.segForce
        end

        accumulate = quote
            idxi = idx[i]
            selfForce = torTot * bEdgeVec - lonCore * tVecI

            @inbounds @simd for j in 1:3
                segForce[j, 1, idxi] -= selfForce[j]
                segForce[j, 2, idxi] += selfForce[j]
            end
        end

        retVal = quote
            return nothing
        end
    end

    ex = quote
        function $name(
            dlnParams::DislocationParameters,
            matParams::MaterialParameters,
            network::DislocationNetwork,
            idx = nothing,
        )
            μ = matParams.μ
            ν = matParams.ν
            omNuInv = matParams.omνInv
            nuOmNuInv = matParams.νomνInv
            μ4π = matParams.μ4π
            a = dlnParams.coreRad
            aSq = dlnParams.coreRadSq
            Ec = dlnParams.coreEnergy
            bVec = network.bVec
            coord = network.coord
            segIdx = network.segIdx
            elemT = eltype(network.bVec)

            # Indices
            $ifIdx

            idxBvec = @view segIdx[idx, 1]
            idxNode1 = @view segIdx[idx, 2]
            idxNode2 = @view segIdx[idx, 3]
            # Un normalised segment vectors. Use views for speed.
            bVec = @view bVec[:, idxBvec]
            tVec = @views coord[:, idxNode2] - coord[:, idxNode1]

            # Allocate memory if necessary.
            $accumulator

            @inbounds @simd for i in eachindex(idx)
                # Finding the norm of each line vector.
                tVecI = SVector{3, elemT}(tVec[1, i], tVec[2, i], tVec[3, i])
                tVecSq = tVecI ⋅ tVecI
                L = sqrt(tVecSq)
                Linv = 1 / L
                tVecI *= Linv
                # Finding the non-singular norm.
                La = sqrt(tVecSq + aSq)
                bVecI = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
                # Normalised the dislocation network vector, the sum of all the segment vectors has norm 1.
                # Screw component, scalar projection of bVec onto t.
                bScrew = tVecI ⋅ bVecI
                # Edge component, vector rejection of bVec onto t.
                bEdgeVec = bVecI - bScrew * tVecI
                # Finding the norm squared of each edge component.
                bEdgeSq = bEdgeVec ⋅ bEdgeVec
                #= 
                A. Arsenlis et al, Modelling Simul. Mater. Sci. Eng. 15 (2007)
                553?595: gives this expression in appendix A p590
                f^{s}_{43} = -(μ/(4π)) [ t × (t × b)](t ⋅ b) { v/(1-v) ( ln[
                (L_a + L)/a] - 2*(L_a - a)/L ) - (L_a - a)^2/(2La*L) }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
                tVec × (tVec × bVec)    = tVec (tVec ⋅ bVec) - bVec (tVec ⋅ tVec)
                = tVec * bScrew - bVec
                = - bEdgeVec =#
                # Torsional component of the elastic self interaction force. This is the scalar component of the above equation.
                LaMa = La - a
                # Torsional component of core self interaction.
                tor =
                    μ4π *
                    bScrew *
                    (
                        nuOmNuInv * (log((La + L) / a) - 2 * LaMa * Linv) -
                        LaMa^2 / (2 * La * L)
                    )
                torCore = 2 * Ec * nuOmNuInv * bScrew
                torTot = tor + torCore
                # Longitudinal component of core self interaction.
                lonCore = (bScrew^2 + bEdgeSq * omNuInv) * Ec
                # Force calculation.
                $accumulate
            end

            # Return value.
            return $retVal
        end
    end
    return ex
end
# Generate calcSelfForce!(dlnParams::DislocationParameters, matParams::MaterialParameters, network::DislocationNetwork, idx = nothing)
eval(genSelfForce(true))
# Generate calcSelfForce(dlnParams::DislocationParameters, matParams::MaterialParameters, network::DislocationNetwork, idx = nothing)
eval(genSelfForce(false))

"""
```
calcSegSegForce(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)
```
Compute the segment-segment forces for every dislocation segment.

Details found in Appendix A.1. in ["Enabling Strain Hardening Simulations with Dislocation Dynamics" by A. Arsenlis et al.](https://doi.org/10.1088%2F0965-0393%2F15%2F6%2F001)
"""
function calcSegSegForce(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)
    # Constants.
    μ = matParams.μ
    μ4π = matParams.μ4π
    μ8π = matParams.μ8π
    μ4πν = matParams.μ4πν
    aSq = dlnParams.coreRadSq
    μ8πaSq = aSq * μ8π
    μ4πνaSq = aSq * μ4πν

    bVec = network.bVec
    coord = network.coord
    segIdx = network.segIdx
    elemT = eltype(network.bVec)

    # Un normalised segment vectors. Views for speed.
    numSeg = network.numSeg[1]
    idxBvec = @view segIdx[1:numSeg, 1]
    idxNode1 = @view segIdx[1:numSeg, 2]
    idxNode2 = @view segIdx[1:numSeg, 3]
    bVec = @view bVec[:, idxBvec]
    node1 = @view coord[:, idxNode1]
    node2 = @view coord[:, idxNode2]
    # Calculate segseg forces on every segment.
    if isnothing(idx)
        if dlnParams.parCPU
            # Threadid parallelisation + parallelised reduction.
            nthreads = Threads.nthreads()
            parSegSegForce =
                [Threads.Atomic{elemT}(0) for i in 1:3, j in 1:2, k in 1:numSeg]
            @sync for tid in 1:nthreads
                Threads.@spawn begin
                    start = 1 + ((tid - 1) * numSeg) ÷ nthreads
                    stop = (tid * numSeg) ÷ nthreads
                    @inbounds for i in start:stop
                        b1 = SVector(bVec[1, i], bVec[2, i], bVec[3, i])
                        n11 = SVector(node1[1, i], node1[2, i], node1[3, i])
                        n12 = SVector(node2[1, i], node2[2, i], node2[3, i])
                        for j in (i + 1):numSeg
                            b2 = SVector(bVec[1, j], bVec[2, j], bVec[3, j])
                            n21 = SVector(node1[1, j], node1[2, j], node1[3, j])
                            n22 = SVector(node2[1, j], node2[2, j], node2[3, j])

                            Fnode1, Fnode2, Fnode3, Fnode4 = calcSegSegForce(
                                aSq,
                                μ4π,
                                μ8π,
                                μ8πaSq,
                                μ4πν,
                                μ4πνaSq,
                                b1,
                                n11,
                                n12,
                                b2,
                                n21,
                                n22,
                            )

                            @simd for k in 1:3
                                Threads.atomic_add!(parSegSegForce[k, 1, i], Fnode1[k])
                                Threads.atomic_add!(parSegSegForce[k, 2, i], Fnode2[k])
                                Threads.atomic_add!(parSegSegForce[k, 1, j], Fnode3[k])
                                Threads.atomic_add!(parSegSegForce[k, 2, j], Fnode4[k])
                            end
                        end
                    end
                end
            end
            return getproperty.(parSegSegForce, :value)
        else
            segSegForce = zeros(3, 2, numSeg)
            # Serial execution.
            @inbounds for i in 1:numSeg
                b1 = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
                n11 = SVector{3, elemT}(node1[1, i], node1[2, i], node1[3, i])
                n12 = SVector{3, elemT}(node2[1, i], node2[2, i], node2[3, i])
                for j in (i + 1):numSeg
                    b2 = SVector{3, elemT}(bVec[1, j], bVec[2, j], bVec[3, j])
                    n21 = SVector{3, elemT}(node1[1, j], node1[2, j], node1[3, j])
                    n22 = SVector{3, elemT}(node2[1, j], node2[2, j], node2[3, j])

                    Fnode1, Fnode2, Fnode3, Fnode4 = calcSegSegForce(
                        aSq,
                        μ4π,
                        μ8π,
                        μ8πaSq,
                        μ4πν,
                        μ4πνaSq,
                        b1,
                        n11,
                        n12,
                        b2,
                        n21,
                        n22,
                    )

                    @simd for k in 1:3
                        segSegForce[k, 1, i] += Fnode1[k]
                        segSegForce[k, 2, i] += Fnode2[k]
                        segSegForce[k, 1, j] += Fnode3[k]
                        segSegForce[k, 2, j] += Fnode4[k]
                    end
                end
            end
        end
        return segSegForce
    else # Calculate segseg forces only on segments provided
        lenIdx = length(idx)
        segSegForce = zeros(3, 2, lenIdx)
        @inbounds for (k, i) in enumerate(idx)
            b1 = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
            n11 = SVector{3, elemT}(node1[1, i], node1[2, i], node1[3, i])
            n12 = SVector{3, elemT}(node2[1, i], node2[2, i], node2[3, i])
            for j in 1:numSeg
                i == j && continue
                b2 = SVector{3, elemT}(bVec[1, j], bVec[2, j], bVec[3, j])
                n21 = SVector{3, elemT}(node1[1, j], node1[2, j], node1[3, j])
                n22 = SVector{3, elemT}(node2[1, j], node2[2, j], node2[3, j])

                Fnode1, Fnode2, missing, missing = calcSegSegForce(
                    aSq,
                    μ4π,
                    μ8π,
                    μ8πaSq,
                    μ4πν,
                    μ4πνaSq,
                    b1,
                    n11,
                    n12,
                    b2,
                    n21,
                    n22,
                )
                @simd for m in 1:3
                    segSegForce[m, 1, k] += Fnode1[m]
                    segSegForce[m, 2, k] += Fnode2[m]
                end
            end
        end
        return segSegForce
    end
end

"""
```
calcSegSegForce!(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)
```
In-place computation of the segment-segment forces for every dislocation segment.

Details found in Appendix A.1. in ["Enabling Strain Hardening Simulations with Dislocation Dynamics" by A. Arsenlis et al.](https://doi.org/10.1088%2F0965-0393%2F15%2F6%2F001)
"""
function calcSegSegForce!(
    dlnParams::DislocationParameters,
    matParams::MaterialParameters,
    network::DislocationNetwork,
    idx = nothing,
)
    # Constants.
    μ = matParams.μ
    μ4π = matParams.μ4π
    μ8π = matParams.μ8π
    μ4πν = matParams.μ4πν
    aSq = dlnParams.coreRadSq
    μ8πaSq = aSq * μ8π
    μ4πνaSq = aSq * μ4πν

    bVec = network.bVec
    coord = network.coord
    segIdx = network.segIdx
    elemT = eltype(network.bVec)

    # Un normalised segment vectors. Views for speed.
    numSeg = network.numSeg[1]
    idxBvec = @view segIdx[1:numSeg, 1]
    idxNode1 = @view segIdx[1:numSeg, 2]
    idxNode2 = @view segIdx[1:numSeg, 3]
    bVec = @view bVec[:, idxBvec]
    node1 = @view coord[:, idxNode1]
    node2 = @view coord[:, idxNode2]
    segForce = network.segForce

    # Calculate segseg forces on every segment.
    if isnothing(idx)
        if dlnParams.parCPU
            # Threadid parallelisation + parallelised reduction.
            nthreads = Threads.nthreads()
            parSegSegForce =
                [Threads.Atomic{elemT}(0) for i in 1:3, j in 1:2, k in 1:numSeg]
            @sync for tid in 1:nthreads
                Threads.@spawn begin
                    start = 1 + ((tid - 1) * numSeg) ÷ nthreads
                    stop = (tid * numSeg) ÷ nthreads
                    @inbounds for i in start:stop
                        b1 = SVector(bVec[1, i], bVec[2, i], bVec[3, i])
                        n11 = SVector(node1[1, i], node1[2, i], node1[3, i])
                        n12 = SVector(node2[1, i], node2[2, i], node2[3, i])
                        for j in (i + 1):numSeg
                            b2 = SVector(bVec[1, j], bVec[2, j], bVec[3, j])
                            n21 = SVector(node1[1, j], node1[2, j], node1[3, j])
                            n22 = SVector(node2[1, j], node2[2, j], node2[3, j])

                            Fnode1, Fnode2, Fnode3, Fnode4 = calcSegSegForce(
                                aSq,
                                μ4π,
                                μ8π,
                                μ8πaSq,
                                μ4πν,
                                μ4πνaSq,
                                b1,
                                n11,
                                n12,
                                b2,
                                n21,
                                n22,
                            )

                            @simd for k in 1:3
                                Threads.atomic_add!(parSegSegForce[k, 1, i], Fnode1[k])
                                Threads.atomic_add!(parSegSegForce[k, 2, i], Fnode2[k])
                                Threads.atomic_add!(parSegSegForce[k, 1, j], Fnode3[k])
                                Threads.atomic_add!(parSegSegForce[k, 2, j], Fnode4[k])
                            end
                        end
                    end
                end
            end
            # This allows type inference and reduces memory allocation.
            segForce[:, :, 1:numSeg] += getproperty.(parSegSegForce, :value)
        else
            # Serial execution.
            @inbounds for i in 1:numSeg
                b1 = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
                n11 = SVector{3, elemT}(node1[1, i], node1[2, i], node1[3, i])
                n12 = SVector{3, elemT}(node2[1, i], node2[2, i], node2[3, i])
                for j in (i + 1):numSeg
                    b2 = SVector{3, elemT}(bVec[1, j], bVec[2, j], bVec[3, j])
                    n21 = SVector{3, elemT}(node1[1, j], node1[2, j], node1[3, j])
                    n22 = SVector{3, elemT}(node2[1, j], node2[2, j], node2[3, j])

                    Fnode1, Fnode2, Fnode3, Fnode4 = calcSegSegForce(
                        aSq,
                        μ4π,
                        μ8π,
                        μ8πaSq,
                        μ4πν,
                        μ4πνaSq,
                        b1,
                        n11,
                        n12,
                        b2,
                        n21,
                        n22,
                    )

                    @simd for k in 1:3
                        segForce[k, 1, i] += Fnode1[k]
                        segForce[k, 2, i] += Fnode2[k]
                        segForce[k, 1, j] += Fnode3[k]
                        segForce[k, 2, j] += Fnode4[k]
                    end
                end
            end
        end
    else # Calculate segseg forces only on segments provided
        @inbounds for i in idx
            b1 = SVector{3, elemT}(bVec[1, i], bVec[2, i], bVec[3, i])
            n11 = SVector{3, elemT}(node1[1, i], node1[2, i], node1[3, i])
            n12 = SVector{3, elemT}(node2[1, i], node2[2, i], node2[3, i])
            for j in 1:numSeg
                i == j && continue
                b2 = SVector{3, elemT}(bVec[1, j], bVec[2, j], bVec[3, j])
                n21 = SVector{3, elemT}(node1[1, j], node1[2, j], node1[3, j])
                n22 = SVector{3, elemT}(node2[1, j], node2[2, j], node2[3, j])

                Fnode1, Fnode2, missing, missing = calcSegSegForce(
                    aSq,
                    μ4π,
                    μ8π,
                    μ8πaSq,
                    μ4πν,
                    μ4πνaSq,
                    b1,
                    n11,
                    n12,
                    b2,
                    n21,
                    n22,
                )

                @simd for m in 1:3
                    segForce[m, 1, i] += Fnode1[m]
                    segForce[m, 2, i] += Fnode2[m]
                end
            end
        end
    end
    return nothing
end

function calcSegSegForce(aSq, μ4π, μ8π, μ8πaSq, μ4πν, μ4πνaSq, b1, n11, n12, b2, n21, n22)
    t2 = n22 - n21
    t2N = 1 / norm(t2)
    t2 = t2 * t2N

    t1 = n12 - n11
    t1N = 1 / norm(t1)
    t1 = t1 * t1N

    c = t1 ⋅ t2
    cSq = c * c
    omcSq = 1 - cSq

    if omcSq > sqrt(eps(typeof(omcSq)))
        omcSqI = 1 / omcSq

        # Single cross products.
        t2ct1 = t2 × t1
        t1ct2 = -t2ct1
        b2ct2 = b2 × t2
        b1ct1 = b1 × t1

        # Dot products.
        t2db2 = t2 ⋅ b2
        t2db1 = t2 ⋅ b1
        t1db2 = t1 ⋅ b2
        t1db1 = t1 ⋅ b1

        # Cross dot products.
        t2ct1db2 = t2ct1 ⋅ b2
        t1ct2db1 = t1ct2 ⋅ b1
        b1ct1db2 = b1ct1 ⋅ b2
        b2ct2db1 = b2ct2 ⋅ b1

        # Double cross products.
        t2ct1ct2 = t1 - c * t2
        t1ct2ct1 = t2 - c * t1
        t2cb1ct2 = b1 - t2db1 * t2
        t1cb2ct1 = b2 - t1db2 * t1
        b1ct1ct2 = t2db1 * t1 - c * b1
        b2ct2ct1 = t1db2 * t2 - c * b2

        # Double cross product dot product.
        t2ct1cb1dt1 = t2db1 - t1db1 * c
        t1ct2cb2dt2 = t1db2 - t2db2 * c
        t2ct1cb1db2 = t2db1 * t1db2 - t1db1 * t2db2

        # Integration limits for local coordinates.
        R1 = n21 - n11
        R2 = n22 - n12
        d = (R2 ⋅ t2ct1) * omcSqI

        μ4πd = μ4π * d
        μ4πνd = μ4πν * d
        μ4πνdSq = μ4πνd * d
        μ4πνdCu = μ4πνdSq * d
        μ4πνaSqd = μ4πνaSq * d
        μ8πaSqd = μ8πaSq * d

        lim11 = R1 ⋅ t1
        lim12 = R1 ⋅ t2
        lim21 = R2 ⋅ t1
        lim22 = R2 ⋅ t2

        x1 = (lim12 - c * lim11) * omcSqI
        x2 = (lim22 - c * lim21) * omcSqI
        y1 = (lim11 - c * lim12) * omcSqI
        y2 = (lim21 - c * lim22) * omcSqI

        integ = SegSegInteg(aSq, d, c, cSq, omcSq, omcSqI, x1, y1)
        integ = integ .- SegSegInteg(aSq, d, c, cSq, omcSq, omcSqI, x1, y2)
        integ = integ .- SegSegInteg(aSq, d, c, cSq, omcSq, omcSqI, x2, y1)
        integ = integ .+ SegSegInteg(aSq, d, c, cSq, omcSq, omcSqI, x2, y2)

        # Seg 1, nodes 2-1
        tmp1 = t1db2 * t2db1 + t2ct1cb1db2
        V1 = tmp1 * t2ct1
        V2 = b1ct1 * t1ct2cb2dt2
        V3 = t1ct2 * b1ct1db2 - t1cb2ct1 * t2db1
        V4 = -b1ct1 * t2ct1db2
        V5 = b2ct2ct1 * t2db1 - t1ct2 * b2ct2db1

        tmp1 = μ4πνd * t1ct2db1
        tmp2 = μ4πνd * b2ct2db1
        V7 = μ4πd * V1 - μ4πνd * V2 + tmp1 * b2ct2ct1 + tmp2 * t1ct2ct1

        tmp1 = μ4πν * t2db1
        tmp2 = μ4πν * b2ct2db1
        V8 = μ4π * V5 - tmp1 * b2ct2ct1 + tmp2 * t1ct2

        tmp1 = μ4πν * t1db1
        V9 = -tmp1 * b2ct2ct1 + μ4π * V3 - μ4πν * V4

        tmp1 = μ4πνdCu * t1ct2cb2dt2 * t1ct2db1
        V10 = μ8πaSqd * V1 - μ4πνaSqd * V2 - tmp1 * t1ct2ct1

        tmp1 = μ4πνdSq * t1ct2cb2dt2 * t2db1
        tmp2 = μ4πνdSq * t1ct2cb2dt2 * t1ct2db1
        V11 = μ8πaSq * V5 + tmp1 * t1ct2ct1 - tmp2 * t1ct2

        tmp1 = μ4πνdSq * (t2ct1db2 * t1ct2db1 + t1ct2cb2dt2 * t1db1)
        V12 = μ8πaSq * V3 - μ4πνaSq * V4 + tmp1 * t1ct2ct1

        tmp1 = μ4πνd * (t1ct2cb2dt2 * t1db1 + t2ct1db2 * t1ct2db1)
        tmp2 = μ4πνd * t2ct1db2 * t2db1
        V13 = tmp1 * t1ct2 - tmp2 * t1ct2ct1

        tmp1 = μ4πνd * t1ct2cb2dt2 * t2db1
        V14 = tmp1 * t1ct2

        tmp1 = μ4πνd * t2ct1db2 * t1db1
        V15 = -tmp1 * t1ct2ct1

        tmpVec1 = μ4πν * t2ct1db2 * t1ct2
        V16 = -tmpVec1 * t2db1
        V17 = -tmpVec1 * t1db1

        Fint1 = integ[3] - y2 * integ[1]
        Fint2 = integ[4] - y2 * integ[2]
        Fint3 = integ[6] - y2 * integ[3]
        Fint4 = integ[9] - y2 * integ[7]
        Fint5 = integ[10] - y2 * integ[8]
        Fint6 = integ[12] - y2 * integ[9]
        Fint7 = integ[14] - y2 * integ[10]
        Fint8 = integ[13] - y2 * integ[11]
        Fint9 = integ[17] - y2 * integ[12]
        Fint10 = integ[15] - y2 * integ[13]
        Fint11 = integ[19] - y2 * integ[14]

        Fnode1 =
            (
                V7 * Fint1 +
                V8 * Fint2 +
                V9 * Fint3 +
                V10 * Fint4 +
                V11 * Fint5 +
                V12 * Fint6 +
                V13 * Fint7 +
                V14 * Fint8 +
                V15 * Fint9 +
                V16 * Fint10 +
                V17 * Fint11
            ) * t1N

        Fint1 = y1 * integ[1] - integ[3]
        Fint2 = y1 * integ[2] - integ[4]
        Fint3 = y1 * integ[3] - integ[6]
        Fint4 = y1 * integ[7] - integ[9]
        Fint5 = y1 * integ[8] - integ[10]
        Fint6 = y1 * integ[9] - integ[12]
        Fint7 = y1 * integ[10] - integ[14]
        Fint8 = y1 * integ[11] - integ[13]
        Fint9 = y1 * integ[12] - integ[17]
        Fint10 = y1 * integ[13] - integ[15]
        Fint11 = y1 * integ[14] - integ[19]

        Fnode2 =
            (
                V7 * Fint1 +
                V8 * Fint2 +
                V9 * Fint3 +
                V10 * Fint4 +
                V11 * Fint5 +
                V12 * Fint6 +
                V13 * Fint7 +
                V14 * Fint8 +
                V15 * Fint9 +
                V16 * Fint10 +
                V17 * Fint11
            ) * t1N

        # Seg 2 (nodes 4-3)
        tmp1 = t2db1 * t1db2 + t2ct1cb1db2
        V1 = tmp1 * t1ct2
        V2 = b2ct2 * t2ct1cb1dt1
        V3 = t2ct1 * b1ct1db2 - b1ct1ct2 * t1db2
        V5 = t2cb1ct2 * t1db2 - t2ct1 * b2ct2db1
        V6 = b2ct2 * t1ct2db1

        tmp1 = μ4πνd * t2ct1db2
        tmp2 = μ4πνd * b1ct1db2
        V7 = μ4πd * V1 - μ4πνd * V2 + tmp1 * b1ct1ct2 + tmp2 * t2ct1ct2

        tmp1 = μ4πν * t2db2
        V8 = tmp1 * b1ct1ct2 + μ4π * V5 - μ4πν * V6

        tmp1 = μ4πν * t1db2
        tmp2 = μ4πν * b1ct1db2
        V9 = μ4π * V3 + tmp1 * b1ct1ct2 - tmp2 * t2ct1

        tmp1 = μ4πνdCu * t2ct1cb1dt1 * t2ct1db2
        V10 = μ8πaSqd * V1 - μ4πνaSqd * V2 - tmp1 * t2ct1ct2

        tmp1 = μ4πνdSq * (t1ct2db1 * t2ct1db2 + t2ct1cb1dt1 * t2db2)
        V11 = μ8πaSq * V5 - μ4πνaSq * V6 - tmp1 * t2ct1ct2

        tmp1 = μ4πνdSq * t2ct1cb1dt1 * t1db2
        tmp2 = μ4πνdSq * t2ct1cb1dt1 * t2ct1db2
        V12 = μ8πaSq * V3 - tmp1 * t2ct1ct2 + tmp2 * t2ct1

        tmp1 = μ4πνd * (t2ct1cb1dt1 * t2db2 + t1ct2db1 * t2ct1db2)
        tmp2 = μ4πνd * t1ct2db1 * t1db2
        V13 = tmp1 * t2ct1 - tmp2 * t2ct1ct2

        tmp1 = μ4πνd * t1ct2db1 * t2db2
        V14 = -tmp1 * t2ct1ct2

        tmp1 = μ4πνd * t2ct1cb1dt1 * t1db2
        V15 = tmp1 * t2ct1

        tmpVec1 = μ4πν * t1ct2db1 * t2ct1
        V16 = tmpVec1 * t2db2
        V17 = tmpVec1 * t1db2

        Fint1 = x2 * integ[1] - integ[2]
        Fint2 = x2 * integ[2] - integ[5]
        Fint3 = x2 * integ[3] - integ[4]
        Fint4 = x2 * integ[7] - integ[8]
        Fint5 = x2 * integ[8] - integ[11]
        Fint6 = x2 * integ[9] - integ[10]
        Fint7 = x2 * integ[10] - integ[13]
        Fint8 = x2 * integ[11] - integ[16]
        Fint9 = x2 * integ[12] - integ[14]
        Fint10 = x2 * integ[13] - integ[18]
        Fint11 = x2 * integ[14] - integ[15]

        Fnode3 =
            (
                V7 * Fint1 +
                V8 * Fint2 +
                V9 * Fint3 +
                V10 * Fint4 +
                V11 * Fint5 +
                V12 * Fint6 +
                V13 * Fint7 +
                V14 * Fint8 +
                V15 * Fint9 +
                V16 * Fint10 +
                V17 * Fint11
            ) * t2N

        Fint1 = integ[2] - x1 * integ[1]
        Fint2 = integ[5] - x1 * integ[2]
        Fint3 = integ[4] - x1 * integ[3]
        Fint4 = integ[8] - x1 * integ[7]
        Fint5 = integ[11] - x1 * integ[8]
        Fint6 = integ[10] - x1 * integ[9]
        Fint7 = integ[13] - x1 * integ[10]
        Fint8 = integ[16] - x1 * integ[11]
        Fint9 = integ[14] - x1 * integ[12]
        Fint10 = integ[18] - x1 * integ[13]
        Fint11 = integ[15] - x1 * integ[14]

        Fnode4 =
            (
                V7 * Fint1 +
                V8 * Fint2 +
                V9 * Fint3 +
                V10 * Fint4 +
                V11 * Fint5 +
                V12 * Fint6 +
                V13 * Fint7 +
                V14 * Fint8 +
                V15 * Fint9 +
                V16 * Fint10 +
                V17 * Fint11
            ) * t2N

    else
        Fnode1, Fnode2, Fnode3, Fnode4 = calcParSegSegForce(
            aSq,
            μ4π,
            μ8π,
            μ8πaSq,
            μ4πν,
            μ4πνaSq,
            b1,
            n11,
            n12,
            b2,
            n21,
            n22,
        )
    end

    return Fnode1, Fnode2, Fnode3, Fnode4
end

function calcParSegSegForce(
    aSq,
    μ4π,
    μ8π,
    μ8πaSq,
    μ4πν,
    μ4πνaSq,
    b1,
    n11,
    n12,
    b2,
    n21,
    n22,
)
    flip::Bool = false

    t2 = n22 - n21
    t2N = 1 / norm(t2)
    t2 = t2 * t2N

    t1 = n12 - n11
    t1N = 1 / norm(t1)
    t1 = t1 * t1N

    c = t2 ⋅ t1

    # half of the cotangent of critical θ
    hCotanθc = sqrt((1 - sqrt(eps(typeof(c))) * 1.01) / (sqrt(eps(typeof(c))) * 1.01)) / 2

    # If c is negative we do a swap of n11 and n12 to keep notation consistent and avoid
    if c < 0
        flip = true
        n12, n11 = n11, n12
        t1 = -t1
        b1 = -b1
    end

    # Vector projection and rejection.
    tmp = (n22 - n21) ⋅ t1
    n22m = n21 + tmp * t1
    diff = n22 - n22m
    magDiff = norm(diff)

    tmpVec1 = 0.5 * diff
    tmpVec2 = hCotanθc * magDiff * t1
    n21m = n21 + tmpVec1 + tmpVec2
    n22m = n22m + tmpVec1 - tmpVec2

    # Dot products.
    R = n21m - n11
    Rdt1 = R ⋅ t1

    nd = R - Rdt1 * t1
    ndb1 = nd ⋅ b1
    dSq = nd ⋅ nd
    aSq_dSq = aSq + dSq
    aSq_dSqI = 1 / aSq_dSq

    x1 = n21m ⋅ t1
    x2 = n22m ⋅ t1
    y1 = -n11 ⋅ t1
    y2 = -n12 ⋅ t1

    t1db2 = t1 ⋅ b2
    t1db1 = t1 ⋅ b1
    nddb1 = nd ⋅ b1

    # Cross products.
    b2ct1 = b2 × t1
    b1ct1 = b1 × t1
    ndct1 = nd × t1

    # Cross dot products
    b2ct1db1 = b2ct1 ⋅ b1
    b2ct1dnd = b2ct1 ⋅ nd

    # Double cross products
    b2ct1ct1 = t1db2 * t1 - b2

    integ = ParSegSegInteg(aSq_dSq, aSq_dSqI, x1, y1)
    integ = integ .- ParSegSegInteg(aSq_dSq, aSq_dSqI, x1, y2)
    integ = integ .- ParSegSegInteg(aSq_dSq, aSq_dSqI, x2, y1)
    integ = integ .+ ParSegSegInteg(aSq_dSq, aSq_dSqI, x2, y2)

    tmp = t1db1 * t1db2
    tmpVec1 = tmp * nd
    tmpVec2 = b2ct1dnd * b1ct1
    V1 = μ4πν * (nddb1 * b2ct1ct1 + b2ct1db1 * ndct1 - tmpVec2) - μ4π * tmpVec1

    tmp = (μ4πν - μ4π) * t1db1
    V2 = tmp * b2ct1ct1

    tmp = μ4πν * b2ct1dnd * nddb1
    V3 = -μ8πaSq * tmpVec1 - μ4πνaSq * tmpVec2 - tmp * ndct1

    tmp = μ8πaSq * t1db1
    tmp2 = μ4πν * b2ct1dnd * t1db1
    V4 = -tmp * b2ct1ct1 - tmp2 * ndct1

    # Node 2, n12
    Fint1 = integ[3] - y1 * integ[1]
    Fint2 = integ[6] - y1 * integ[4]
    Fint3 = integ[9] - y1 * integ[7]
    Fint4 = integ[12] - y1 * integ[10]
    Fnode2 = (V1 * Fint1 + V2 * Fint2 + V3 * Fint3 + V4 * Fint4) * t1N

    # Node 1, n11
    Fint1 = y2 * integ[1] - integ[3]
    Fint2 = y2 * integ[4] - integ[6]
    Fint3 = y2 * integ[7] - integ[9]
    Fint4 = y2 * integ[10] - integ[12]
    Fnode1 = (V1 * Fint1 + V2 * Fint2 + V3 * Fint3 + V4 * Fint4) * t1N

    magDiffSq = diff ⋅ diff
    magn21mSq = n21m ⋅ n21m
    magn22mSq = n22m ⋅ n22m

    if magDiffSq > sqrt(eps(typeof(magDiffSq))) * (magn21mSq + magn22mSq)
        nothing, nothing, Fnode1Core, Fnode2Core = calcSegSegForce(
            aSq,
            μ4π,
            μ8π,
            μ8πaSq,
            μ4πν,
            μ4πνaSq,
            b2,
            n21,
            n21m,
            b1,
            n11,
            n12,
        )
        Fnode1 += Fnode1Core
        Fnode2 += Fnode2Core

        nothing, nothing, Fnode1Core, Fnode2Core = calcSegSegForce(
            aSq,
            μ4π,
            μ8π,
            μ8πaSq,
            μ4πν,
            μ4πνaSq,
            b2,
            n22m,
            n22,
            b1,
            n11,
            n12,
        )
        Fnode1 += Fnode1Core
        Fnode2 += Fnode2Core
    end

    # Segment 2
    # Scalar projection of seg1 (n12-n11) onto t2, not normalised because we need the length.
    tmp = (n12 - n11) ⋅ t2
    # Vector projection of seg 1 to seg 2.
    n12m = n11 + tmp * t2
    # Vector rejection and its magnitude.
    diff = n12 - n12m
    magDiff = norm(diff)

    tmpVec1 = 0.5 * diff
    tmpVec2 = hCotanθc * magDiff * t2
    n11m = n11 + tmpVec1 + tmpVec2
    n12m = n12m + tmpVec1 - tmpVec2

    # Dot products.
    R = n21 - n11m
    Rdt2 = R ⋅ t2

    nd = R - Rdt2 * t2
    dSq = nd ⋅ nd
    aSq_dSq = aSq + dSq
    aSq_dSqI = 1 / aSq_dSq

    x1 = n21 ⋅ t2
    x2 = n22 ⋅ t2
    y1 = -n11m ⋅ t2
    y2 = -n12m ⋅ t2

    t2db2 = t2 ⋅ b2
    t2db1 = t2 ⋅ b1
    nddb2 = nd ⋅ b2

    # Cross products.
    b2ct2 = b2 × t2
    b1ct2 = b1 × t2
    ndct2 = nd × t2

    # Cross dot producs.
    b1ct2db2 = b1ct2 ⋅ b2
    b1ct2dnd = b1ct2 ⋅ nd

    # Double cross products.
    b1ct2ct2 = t2db1 * t2 - b1

    integ = ParSegSegInteg(aSq_dSq, aSq_dSqI, x1, y1)
    integ = integ .- ParSegSegInteg(aSq_dSq, aSq_dSqI, x1, y2)
    integ = integ .- ParSegSegInteg(aSq_dSq, aSq_dSqI, x2, y1)
    integ = integ .+ ParSegSegInteg(aSq_dSq, aSq_dSqI, x2, y2)

    tmp = t2db2 * t2db1
    tmpVec1 = tmp * nd
    tmpVec2 = b1ct2dnd * b2ct2
    V1 = μ4πν * (nddb2 * b1ct2ct2 + b1ct2db2 * ndct2 - tmpVec2) - μ4π * tmpVec1

    tmp = (μ4πν - μ4π) * t2db2
    V2 = tmp * b1ct2ct2

    tmp = μ4πν * b1ct2dnd * nddb2
    V3 = -μ8πaSq * tmpVec1 - μ4πνaSq * tmpVec2 - tmp * ndct2

    tmp = μ8πaSq * t2db2
    tmp2 = μ4πν * b1ct2dnd * t2db2
    V4 = -tmp * b1ct2ct2 - tmp2 * ndct2

    Fint1 = integ[2] - x1 * integ[1]
    Fint2 = integ[5] - x1 * integ[4]
    Fint3 = integ[8] - x1 * integ[7]
    Fint4 = integ[11] - x1 * integ[10]
    Fnode4 = (V1 * Fint1 + V2 * Fint2 + V3 * Fint3 + V4 * Fint4) * t2N

    Fint1 = x2 * integ[1] - integ[2]
    Fint2 = x2 * integ[4] - integ[5]
    Fint3 = x2 * integ[7] - integ[8]
    Fint4 = x2 * integ[10] - integ[11]
    Fnode3 = (V1 * Fint1 + V2 * Fint2 + V3 * Fint3 + V4 * Fint4) * t2N

    magDiffSq = magDiff^2
    magn11mSq = n11m ⋅ n11m
    magn12mSq = n12m ⋅ n12m

    if magDiffSq > sqrt(eps(typeof(magDiffSq))) * (magn11mSq + magn12mSq)
        nothing, nothing, Fnode3Core, Fnode4Core = calcSegSegForce(
            aSq,
            μ4π,
            μ8π,
            μ8πaSq,
            μ4πν,
            μ4πνaSq,
            b1,
            n11,
            n11m,
            b2,
            n21,
            n22,
        )
        Fnode3 += Fnode3Core
        Fnode4 += Fnode4Core

        nothing, nothing, Fnode3Core, Fnode4Core = calcSegSegForce(
            aSq,
            μ4π,
            μ8π,
            μ8πaSq,
            μ4πν,
            μ4πνaSq,
            b1,
            n12m,
            n12,
            b2,
            n21,
            n22,
        )
        Fnode3 += Fnode3Core
        Fnode4 += Fnode4Core
    end

    # If we flipped the first segment originally, flip the forces round.
    if flip
        Fnode1, Fnode2 = Fnode2, Fnode1
    end

    return Fnode1, Fnode2, Fnode3, Fnode4
end

function ParSegSegInteg(aSq_dSq, aSq_dSqI, x, y)
    xpy = x + y
    xmy = x - y
    Ra = sqrt(aSq_dSq + xpy * xpy)
    RaInv = 1 / Ra
    Log_Ra_ypz = log(Ra + xpy)

    tmp = xmy * Ra * aSq_dSqI

    integ1 = Ra * aSq_dSqI
    integ2 = -0.5 * (Log_Ra_ypz - tmp)
    integ3 = -0.5 * (Log_Ra_ypz + tmp)
    integ4 = -Log_Ra_ypz
    integ5 = y * Log_Ra_ypz - Ra
    integ6 = x * Log_Ra_ypz - Ra
    integ7 = aSq_dSqI * (2 * aSq_dSqI * Ra - RaInv)
    integ8 = aSq_dSqI * (tmp - x * RaInv)
    integ9 = -aSq_dSqI * (tmp + y * RaInv)
    integ10 = -aSq_dSqI * xpy * RaInv
    integ11 = RaInv - y * integ10
    integ12 = RaInv - x * integ10

    return integ1,
    integ2,
    integ3,
    integ4,
    integ5,
    integ6,
    integ7,
    integ8,
    integ9,
    integ10,
    integ11,
    integ12
end

function SegSegInteg(aSq, d, c, cSq, omcSq, omcSqI, x, y)
    aSq_dSq = aSq + d^2 * omcSq
    xSq = x^2
    ySq = y^2
    Ra = sqrt(aSq_dSq + xSq + ySq + 2 * x * y * c)
    RaInv = 1 / Ra

    Ra_Rd_t1 = Ra + y + x * c
    Ra_Rd_t2 = Ra + x + y * c

    log_Ra_Rd_t1 = log(Ra_Rd_t1)
    xlog_Ra_Rd_t1 = x * log_Ra_Rd_t1

    log_Ra_Rd_t2 = log(Ra_Rd_t2)
    ylog_Ra_Rd_t2 = y * log_Ra_Rd_t2

    RaSq_R_t1_I = RaInv / Ra_Rd_t1
    xRaSq_R_t1_I = x * RaSq_R_t1_I
    xSqRaSq_R_t1_I = x * xRaSq_R_t1_I

    RaSq_R_t2_I = RaInv / Ra_Rd_t2
    yRaSq_R_t2_I = y * RaSq_R_t2_I
    ySqRaSq_R_t2_I = y * yRaSq_R_t2_I

    den = 1 / sqrt(omcSq * aSq_dSq)

    integ1 = -2 * den * atan((1 + c) * (Ra + x + y) * den)

    c_1 = aSq_dSq * integ1
    c_5_6 = (c * Ra - c_1) * omcSqI

    integ2 = (c * log_Ra_Rd_t2 - log_Ra_Rd_t1) * omcSqI
    integ3 = (c * log_Ra_Rd_t1 - log_Ra_Rd_t2) * omcSqI
    integ4 = (c * c_1 - Ra) * omcSqI
    integ5 = ylog_Ra_Rd_t2 + c_5_6
    integ6 = xlog_Ra_Rd_t1 + c_5_6

    c_11_12 = integ1 - c * RaInv
    c_15_18 = c * xRaSq_R_t1_I - RaInv
    x_13_14 = x * c_15_18
    c_19 = c * yRaSq_R_t2_I - RaInv
    y_13_14 = y * c_19
    c_16 = log_Ra_Rd_t2 - (x - c * y) * RaInv - cSq * ySqRaSq_R_t2_I
    z_15_18 = y * c_16
    c_17_19 = log_Ra_Rd_t1 - (y - c * x) * RaInv - cSq * xSqRaSq_R_t1_I

    c15_18_19 = 2 * integ4

    integ7 = (integ1 - xRaSq_R_t1_I - yRaSq_R_t2_I) / (aSq_dSq)
    integ8 = (RaSq_R_t1_I - c * RaSq_R_t2_I) * omcSqI
    integ9 = (RaSq_R_t2_I - c * RaSq_R_t1_I) * omcSqI
    integ10 = (RaInv - c * (xRaSq_R_t1_I + yRaSq_R_t2_I + integ1)) * omcSqI
    integ11 = (xRaSq_R_t1_I + cSq * yRaSq_R_t2_I + c_11_12) * omcSqI
    integ12 = (yRaSq_R_t2_I + cSq * xRaSq_R_t1_I + c_11_12) * omcSqI
    integ13 = (integ3 - x_13_14 + c * (y_13_14 - integ2)) * omcSqI
    integ14 = (integ2 - y_13_14 + c * (x_13_14 - integ3)) * omcSqI
    integ15 = (integ5 - z_15_18 + c * (xSq * c_15_18 - c15_18_19)) * omcSqI
    integ16 = (xSqRaSq_R_t1_I + c * c_16 + 2 * integ2) * omcSqI
    integ17 = (ySqRaSq_R_t2_I + c * c_17_19 + 2 * integ3) * omcSqI
    integ18 = (c15_18_19 - xSq * c_15_18 + c * (z_15_18 - integ5)) * omcSqI
    integ19 = (c15_18_19 - ySq * c_19 + c * (x * c_17_19 - integ6)) * omcSqI

    return integ1,
    integ2,
    integ3,
    integ4,
    integ5,
    integ6,
    integ7,
    integ8,
    integ9,
    integ10,
    integ11,
    integ12,
    integ13,
    integ14,
    integ15,
    integ16,
    integ17,
    integ18,
    integ19
end
