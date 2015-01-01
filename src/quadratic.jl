immutable QuadraticDegree <: Degree{2} end
immutable Quadratic{BC<:BoundaryCondition,GR<:GridRepresentation} <: InterpolationType{QuadraticDegree,BC,GR} end

Quadratic{BC<:BoundaryCondition,GR<:GridRepresentation}(::BC, ::GR) = Quadratic{BC,GR}()

function define_indices(q::Quadratic, N)
    quote
        pad = padding(TCoefs, $q)
        @nexprs $N d->begin
            ix_d = clamp(round(x_d), 1, size(itp,d)) + pad
            ixp_d = ix_d + 1
            ixm_d = ix_d - 1

            fx_d = x_d - (ix_d - pad)
        end
    end
end
function define_indices(q::Quadratic{Periodic}, N)
    quote
        pad = padding(TCoefs, $q)
        @nexprs $N d->begin
            ix_d = clamp(round(x_d), 1, size(itp,d)) + pad
            ixp_d = mod1(ix_d + one(typeof(ix_d)), size(itp,d))
            ixm_d = mod1(ix_d - one(typeof(ix_d)), size(itp,d))

            fx_d = x_d - (ix_d - pad)
        end
    end
end

function coefficients(q::Quadratic, N)
    :(@nexprs $N d->($(coefficients(q, N, :d))))
end

function coefficients(q::Quadratic, N, d)
    symm, sym, symp =  symbol(string("cm_",d)), symbol(string("c_",d)), symbol(string("cp_",d))
    symfx = symbol(string("fx_",d))
    quote
        $symm = convert(TCoefs, .5) * ($symfx - convert(TCoefs, .5))^2
        $sym  = convert(TCoefs, .75) - $symfx^2
        $symp = convert(TCoefs, .5) * ($symfx + convert(TCoefs, .5))^2
    end
end

function gradient_coefficients(q::Quadratic, N, d)
    symm, sym, symp =  symbol(string("cm_",d)), symbol(string("c_",d)), symbol(string("cp_",d))
    symfx = symbol(string("fx_",d))
    quote
        $symm = $symfx - convert(TCoefs, .5)
        $sym = -convert(TCoefs, 2) * $symfx
        $symp = $symfx + convert(TCoefs, .5)
    end
end

# This assumes integral values ixm_d, ix_d, and ixp_d,
# coefficients cm_d, c_d, and cp_d, and an array itp.coefs
function index_gen(degree::QuadraticDegree, N::Integer, offsets...)
    if length(offsets) < N
        d = length(offsets)+1
        symm, sym, symp =  symbol(string("cm_",d)), symbol(string("c_",d)), symbol(string("cp_",d))
        return :($symm * $(index_gen(degree, N, offsets...,-1)) + $sym * $(index_gen(degree, N, offsets..., 0)) +
                 $symp * $(index_gen(degree, N, offsets..., 1)))
    else
        indices = [offsetsym(offsets[d], d) for d = 1:N]
        return :(itp.coefs[$(indices...)])
    end
end

# Quadratic interpolation has 1 extra coefficient at each boundary
# Therefore, make the coefficient array 1 larger in each direction,
# in each dimension.
padding{T}(::Type{T}, ::Quadratic) = one(T)
# For periodic boundary conditions, we don't pad - instead, we wrap the
# the coefficients
padding{T}(::Type{T}, ::Quadratic{Periodic}) = zero(T)

function inner_system_diags{T}(::Type{T}, n::Int, ::Quadratic)
    du = fill(convert(T,1/8), n-1)
    d = fill(convert(T,3/4),n)
    dl = copy(du)
    (dl,d,du)
end

function prefiltering_system{T,BC<:Union(Flat,Reflect)}(::Type{T}, n::Int, q::Quadratic{BC,OnCell})
    dl,d,du = inner_system_diags(T,n,q)
    d[1] = d[end] = -1
    du[1] = dl[end] = 1
    lufact!(Tridiagonal(dl, d, du)), zeros(T, n)
end

function prefiltering_system{T,BC<:Union(Flat,Reflect)}(::Type{T}, n::Int, q::Quadratic{BC,OnGrid})
    dl,d,du = inner_system_diags(T,n,q)
    d[1] = d[end] = convert(T, -1)
    du[1] = dl[end] = convert(T, 0)

    rowspec = zeros(T,n,2)
    # first row     last row
    rowspec[1,1] = rowspec[n,2] = convert(T, 1)
    colspec = zeros(T,2,n)
    # third col     third-to-last col
    colspec[1,3] = colspec[2,n-2] = convert(T, 1)
    valspec = zeros(T,2,2)
    # val for [1,3], val for [n,n-2]
    valspec[1,1] = valspec[2,2] = convert(T, 1)

    Woodbury(lufact!(Tridiagonal(dl, d, du)), rowspec, valspec, colspec), zeros(T, n)
end

function prefiltering_system{T}(::Type{T}, n::Int, q::Quadratic{Line})
    dl,d,du = inner_system_diags(T,n,q)
    d[1] = d[end] = convert(T, 1)
    du[1] = dl[end] = convert(T, -2)

    rowspec = zeros(T,n,2)
    # first row     last row
    rowspec[1,1] = rowspec[n,2] = convert(T, 1)
    colspec = zeros(T,2,n)
    # third col     third-to-last col
    colspec[1,3] = colspec[2,n-2] = convert(T, 1)
    valspec = zeros(T,2,2)
    # val for [1,3], val for [n,n-2]
    valspec[1,1] = valspec[2,2] = convert(T, 1)

    Woodbury(lufact!(Tridiagonal(dl, d, du)), rowspec, valspec, colspec), zeros(T, n)
end

function prefiltering_system{T}(::Type{T}, n::Int, q::Quadratic{Free})
    dl,d,du = inner_system_diags(T,n,q)
    d[1] = d[end] = convert(T, 1)
    du[1] = dl[end] = convert(T, -3)

    rowspec = zeros(T,n,4)
    rowspec[1,1] = rowspec[1,2] = rowspec[n,3] = rowspec[n,4] = convert(T,1)
    colspec = zeros(T,4,n)
    colspec[1,3] = colspec[2,4] = colspec[3,n-2] = colspec[4,n-3] = convert(T,1)
    valspec = zeros(T,4,4)
    valspec[1,1] = valspec[3,3] = convert(T, 3)
    valspec[2,2] = valspec[4,4] = convert(T, -1)

    Woodbury(lufact!(Tridiagonal(dl, d, du)), rowspec, valspec, colspec), zeros(T, n)
end

function prefiltering_system{T}(::Type{T}, n::Int, q::Quadratic{Periodic})
    dl,d,du = inner_system_diags(T,n,q)

    rowspec = zeros(T,n,2)
    rowspec[1,1] = rowspec[n,2] = convert(T,1)
    colspec = zeros(T,2,n)
    colspec[1,n] = colspec[2,1] = convert(T,1)
    valspec = zeros(T,2,2)
    valspec[1,1] = convert(T, 1/8)
    valspec[2,2] = convert(T, 1/8)

    Woodbury(lufact!(Tridiagonal(dl, d, du)), rowspec, valspec, colspec), zeros(T, n)
end
