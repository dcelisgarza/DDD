module DDD

using LinearAlgebra,
    SparseArrays, Plots, Statistics, InteractiveUtils, JSON, StaticArrays, FileIO, LazySets, FastGaussQuadrature

# Miscelaneous.
include("./Misc/Misc.jl")
export makeTypeDict, compStruct, intAngle, externalAngle, rot3D, makeInstanceDict
export inclusiveComparison, ⊗, linePlaneIntersect, gausslegendre

include("./Type/TypeBase.jl")
export AbstractDlnSeg,
    AbstractCrystalStruct,
    BCC,
    FCC,
    HCP,
    loopDln,
    loopPrism,
    loopShear,
    loopPure,
    loopImpure,
    AbstractShapeFunction,
    AbstractShapeFunction2D,
    AbstractShapeFunction3D,
    LinearQuadrangle2D,
    LinearQuadrangle3D,
    LinearElement,
    AbstractMesh,
    AbstractRegularCuboidMesh,
    DispatchRegularCuboidMesh,
    RegularCuboidMesh,
    buildMesh,
    FEMParameters,
    ForceDisplacement,
    AbstractMobility,
    mobBCC,
    mobFCC,
    mobHCP,
    AbstractDlnStr,
    AbstractDistribution,
    limits!,
    translatePoints!,
    makeNetwork!,
    makeSegment,
    AbstractElementOrder,
    AbstractIntegrator,
    BoundaryCondition,
    AbstractModel,
    AbstractCantileverBend,
    CantileverLoad
export MaterialParameters
export nodeType,
    SlipSystem,
    DislocationParameters,
    DislocationLoop,
    DislocationNetwork,
    DislocationNetwork!,
    checkNetwork,
    getSegmentIdx,
    getSegmentIdx!,
    makeConnect,
    makeConnect!
export IntegrationParameters, IntegrationTime, AbstractIntegrator, AdaptiveEulerTrapezoid
export Rand, Randn, Zeros, Regular, loopDistribution

include("./Processing/ProcessingBase.jl")
export calcSegForce,
    calcSegForce!,
    calcSelfForce,
    calcSelfForce!,
    calcSegSegForce,
    calcSegSegForce!,
    calc_σHat,
    calcPKForce,
    calcPKForce!,
    remeshSurfaceNetwork!
export dlnMobility, dlnMobility!
export mergeNode!, splitNode!, coarsenNetwork!, refineNetwork!, makeSurfaceNode!
export shapeFunction, shapeFunctionDeriv

include("./PostProcessing/Plotting.jl")
export plotNodes, plotNodes!

include("./IO/IOBase.jl")
export loadJSON,
    loadDislocationParametersJSON, loadMaterialParametersJSON, loadIntegrationParametersJSON
export loadSlipSystemJSON, loadDislocationLoopJSON, loadParametersJSON
export loadDislocationLoopJSON, loadNetworkJSON, loadIntegrationTimeJSON
export loadFEMParametersJSON
export saveJSON

end # module
