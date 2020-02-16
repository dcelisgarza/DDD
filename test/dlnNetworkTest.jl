using DDD
using Test

import DelimitedFiles: readdlm
import LinearAlgebra: dot, cross, norm
import Statistics: mean
import Random: seed!
cd(@__DIR__)

@testset "Generate single segments" begin
    inFilename = "../data/slipSystems/bcc.csv"
    data = readdlm(inFilename, ',', Float64)
    slipSysInt = 1
    slipPlane = data[slipSysInt, 1:3]
    bVec = data[slipSysInt, 4:6]
    edge = makeSegment(segEdge(), slipPlane, bVec)
    edgeN = makeSegment(segEdgeN(), slipPlane, bVec)
    screw = makeSegment(segScrew(), slipPlane, bVec)
    @test abs(dot(edge, screw)) < eps(Float64)
    @test abs(dot(edgeN, screw)) < eps(Float64)
    @test abs(dot(edge, bVec)) < eps(Float64)
    @test abs(dot(edgeN, bVec)) < eps(Float64)
    @test isapprox(
        edge,
        cross(slipPlane, bVec) ./ norm(cross(slipPlane, bVec)),
    )
    @test isapprox(norm(edge), norm(screw))
    @test isapprox(norm(edge), 1.0)
end

@testset "Dislocation indexing functions" begin
    cnd = [==, >=, <=, <, >, !=]
    numNode = 10
    numSeg = 20
    links = zeros(Int64, numSeg, 2)
    bVec = zeros(Float64, numSeg, 3)
    slipPlane = zeros(Float64, numSeg, 3)
    coord = zeros(numNode, 3)
    label = zeros(nodeType, numNode)
    lenLinks = size(links, 1)
    [links[i, :] = [i, i + lenLinks] for i = 1:lenLinks]
    [bVec[i, :] = [i, i + lenLinks, i + 2 * lenLinks] for i = 1:lenLinks]
    [slipPlane[i, :] = -[i, i + lenLinks, i + 2 * lenLinks] for i = 1:lenLinks]
    lenLabel = length(label)
    [label[i+1] = mod(i, 6) - 1 for i = 0:lenLabel-1]
    [coord[i, :] = convert.(Float64, [i, i + lenLabel, i + 2 * lenLabel]) for i = 1:length(label)]
    network = DislocationNetwork(
        links,
        slipPlane,
        bVec,
        coord,
        label,
        convert(Int64, numNode),
        convert(Int64, numSeg),
    )
    @test isequal(network.label[1], -1)
    @test isequal(-1, network.label[1])
    @test -1 == network.label[1]
    @test -2.0 < network.label[1]
    rnd = rand(-1:numNode)
    @test idxLabel(network, rnd) == findall(x -> x == rnd, label)
    @test coordLbl(network, rnd) == coord[findall(x -> x == rnd, label), :]
    @test idxCond(network, :label, inclusiveComparison, 0, 1) == [2; 3; 8; 9]
    @test idxCond(network, :label, rnd; condition = <=) == findall(
        x -> x <= rnd,
        label,
    )
    rnd = rand(1:numSeg)
    @test idxCond(network, :bVec, rnd; condition = cnd[1]) == findall(
        x -> cnd[1](x, rnd),
        bVec,
    )
    @test dataCond(
        network,
        :slipPlane,
        rnd;
        condition = cnd[2],
    ) == slipPlane[findall(x -> cnd[2](x, rnd), slipPlane)]
    rnd = rand(-1:1)
    @test dataCond(
        network,
        :slipPlane,
        :bVec,
        rnd;
        condition = cnd[3],
    ) == slipPlane[findall(x -> cnd[3](x, rnd), bVec)]
    rnd = rand(1:numNode)
    @test dataCond(network, :coord, :label, rnd; condition = cnd[4]) == coord[
        findall(x -> cnd[4](x, rnd), label),
        :,
    ]
    col = rand(1:3)
    @test idxCond(network, :bVec, col, rnd; condition = cnd[5]) == findall(
        x -> cnd[5](x, rnd),
        bVec[:, col],
    )
    @test dataCond(network, :bVec, col, rnd; condition = cnd[6]) == bVec[
        findall(x -> cnd[6](x, rnd), bVec[:, col]),
        :,
    ]
    rnd = rand(-1:1)
    @test dataCond(
        network,
        :slipPlane,
        :bVec,
        col,
        rnd;
        condition = cnd[1],
    ) == slipPlane[findall(x -> cnd[1](x, rnd), bVec[:, col]), :]
    rnd = rand(1:numNode)
    @test coordIdx(network, rnd) == coord[rnd, :]
    rnd = rand(1:numNode, numNode)
    @test coordIdx(network, rnd) == coord[rnd, :]
end

@testset "Loop generation" begin
    slipfile = "../data/slipSystems/bcc.csv"
    loopfile = "../inputs/dln/sampleDln.csv"
    slipSystems = readdlm(slipfile, ',')
    df = loadCSV(loopfile; header = 1, transpose = true)
    loops = loadDln(df, slipSystems)
    # Check that the midpoint of the loops is at (0,0,0)
    for i in eachindex(loops)
        @test mean(loops[i].coord) < maximum(abs.(loops[i].coord)) *
                                     eps(Float64)
    end
    # Populate a dislocation network with the loops.
    # Test one branch of memory allocation.
    network = zero(DislocationNetwork)
    makeNetwork!(network, loops[1])
    @test network.numNode == loops[1].numSides * loops[1].nodeSide *
                             loops[1].numLoops
    # Test other branch of memory allocation.
    network = DislocationNetwork(
        zeros(Int64, 15, 2),
        zeros(Float64, 15, 3),
        zeros(Float64, 15, 3),
        zeros(Float64, 15, 3),
        zeros(nodeType, 15),
        convert(Int64, 0),
        convert(Int64, 0),
    )
    makeNetwork!(network, loops)
    function sumNodes(loops)
        totalNodes = 0
        for i in eachindex(loops)
            totalNodes += loops[i].numSides * loops[i].nodeSide *
                          loops[i].numLoops
        end
        return totalNodes
    end
    # Check that the memory was allocated correctly. Only need to check the first and last, they are transfered sequentially so if both pass, the rest have to have been transfered correctly.
    totalNodes = sumNodes(loops)
    @test totalNodes == network.numNode == network.numSeg ==
          size(network.links, 1) == size(network.slipPlane, 1) ==
          size(network.bVec, 1) == size(network.coord, 1) ==
          size(network.label, 1)
    # Check that the first loop was transfered correctly.
    nodeLoop = loops[1].numSides * loops[1].nodeSide * loops[1].numLoops
    @test network.links[1:nodeLoop, :] == loops[1].links
    @test network.slipPlane[1:nodeLoop, :] == loops[1].slipPlane
    @test network.bVec[1:nodeLoop, :] == loops[1].bVec
    @test network.coord[1:nodeLoop, :] == loops[1].coord
    @test network.label[1:nodeLoop] == loops[1].label
    # Check that the last loop was transfered correctly.
    nodeLoop = loops[end].numSides * loops[end].nodeSide * loops[end].numLoops
    @test network.links[1+end-nodeLoop:end, :] == loops[end].links .+
                                                  (totalNodes - nodeLoop)
    @test network.slipPlane[1+end-nodeLoop:end, :] == loops[end].slipPlane
    @test network.bVec[1+end-nodeLoop:end, :] == loops[end].bVec
    @test network.coord[1+end-nodeLoop:end, :] == loops[end].coord
    @test network.label[1+end-nodeLoop:end] == loops[end].label
    # Test distributions.
    n = 5
    seed!(1234)
    randArr = loopDistribution(Rand(), n)
    seed!(1234)
    test = rand(n, 3)
    @test randArr == test
    seed!(1234)
    randArr = loopDistribution(Randn(), n)
    seed!(1234)
    test = randn(n, 3)
    @test randArr == test
    @test_throws ErrorException loopDistribution(Regular(), n)
end

@testset "Overloaded type functions" begin
    @test isequal(4, loopSides(4))
    @test isequal(loopSides(4), 4)
    @test isless(5, loopSides(6))
    @test isless(loopSides(6), 5) == false
    @test ==(4, loopSides(4))
    @test ==(loopSides(6), 7) == false
    @test convert(loopSides, 6) == loopSides(6)
    @test *(loopSides(4), 3) == 12
    @test /(loopSides(6), 6) == 1
    var = segEdge()
    @test length(var) == 1
end
