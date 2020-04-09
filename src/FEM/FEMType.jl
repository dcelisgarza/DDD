"""
```
abstract type AbstractMesh end
```
Abstract mesh type.
"""
abstract type AbstractMesh end

"""
```
abstract type AbstractShapeFunction end
abstract type AbstractShapeFunction3D <: AbstractShapeFunction end
abstract type AbstractShapeFunction2D <: AbstractShapeFunction end
struct LinearQuadrangle3D <:AbstractShapeFunction3D end
struct LinearQuadrangle2D <:AbstractShapeFunction2D end
```
Abstract types for different shape functions.
"""
abstract type AbstractShapeFunction end
abstract type AbstractShapeFunction3D <: AbstractShapeFunction end
abstract type AbstractShapeFunction2D <: AbstractShapeFunction end
struct LinearQuadrangle3D <: AbstractShapeFunction3D end
struct LinearQuadrangle2D <: AbstractShapeFunction2D end

struct RegularCuboidMesh{
    T1 <: AbstractArray{<:Int64, N} where {N},
    T2 <: AbstractArray{<:Float64, N} where {N},
}
    numElem::T1
    sizeElem::T2
    sizeMesh::T2
    stiffTensor::T2
    label::T1
    coord::T2
end

# """
# # Cuboid mesh structure. Incomplete.
# mutable struct CuboidMesh{
#     T1<:AbstractArray{<:Float64,N} where {N},
#     T2<:AbstractArray{<:Float64,N} where {N},
# }
#     elem::T1
#     vertices::T2
#     coord::T2
#     label::T1
#
#     function CuboidMesh(
#         elem,
#         vertices = nothing,
#         coord = nothing,
#         label = nothing,
#     )
#         if vertices == nothing
#             vertices = zeros(typeof(elem[1]), 8, 3)
#         else
#             @assert length(vertices) == 3
#         end
#         vertices[2:2:end, 1] .= elem[1]
#         vertices[3:4, 2] .= elem[2]
#         vertices[7:end, 2] .= elem[2]
#         vertices[5:end, 3] .= elem[3]
#
#         if !(coord == nothing && label == nothing)
#             @assert length(elem) == size(coord, 2)
#             @assert length(label) == size(coord, 1)
#             new{typeof(elem),typeof(vertices)}(elem, vertices, coord, label)
#         else
#             new{typeof(elem),typeof(vertices)}(elem, vertices)
#         end
#     end #constructor
# end #CuboidMesh
# """
