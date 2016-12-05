export KroneckerOperator



##########
# KroneckerOperator gives the kronecker product of two 1D operators
#########

immutable KroneckerOperator{S,V,DS,RS,DI,RI,T} <: Operator{T}
    ops::Tuple{S,V}
    domainspace::DS
    rangespace::RS
    domaintensorizer::DI
    rangetensorizer::RI
end


KroneckerOperator(A,B,ds::Space,rs::Space,di,ri) =
    KroneckerOperator{typeof(A),typeof(B),typeof(ds),typeof(rs),typeof(di),typeof(ri),
                        promote_type(eltype(A),eltype(B))}((A,B),ds,rs,di,ri)

KroneckerOperator(A,B,ds::Space,rs::Space) = KroneckerOperator(A,B,ds,rs,
                    CachedIterator(tensorizer(ds)),CachedIterator(tensorizer(rs)))
function KroneckerOperator(A,B)
    ds=domainspace(A)⊗domainspace(B)
    rs=rangespace(A)⊗rangespace(B)
    KroneckerOperator(A,B,ds,rs)
end
KroneckerOperator(A::UniformScaling,B::UniformScaling) =
    KroneckerOperator(ConstantOperator(A.λ),ConstantOperator(B.λ))
KroneckerOperator(A,B::UniformScaling) = KroneckerOperator(A,ConstantOperator(B.λ))
KroneckerOperator(A::UniformScaling,B) = KroneckerOperator(ConstantOperator(A.λ),B)
KroneckerOperator(A::Fun,B::Fun) = KroneckerOperator(Multiplication(A),Multiplication(B))
KroneckerOperator(A::UniformScaling,B::Fun) = KroneckerOperator(ConstantOperator(A.λ),Multiplication(B))
KroneckerOperator(A::Fun,B::UniformScaling) = KroneckerOperator(Multiplication(A),ConstantOperator(B.λ))
KroneckerOperator(A,B::Fun) = KroneckerOperator(A,Multiplication(B))
KroneckerOperator(A::Fun,B) = KroneckerOperator(Multiplication(A),B)



function promotedomainspace(K::KroneckerOperator,ds::TensorSpace)
    A=promotedomainspace(K.ops[1],ds[1])
    B=promotedomainspace(K.ops[2],ds[2])
    KroneckerOperator(A,B,ds,rangespace(A)⊗rangespace(B))
end

function promoterangespace(K::KroneckerOperator,rs::TensorSpace)
    A=promoterangespace(K.ops[1],rs[1])
    B=promoterangespace(K.ops[2],rs[2])
    KroneckerOperator(A,B,domainspace(K),rs)
end


function Base.convert{T<:Number}(::Type{Operator{T}},K::KroneckerOperator)
    if T == eltype(K)
        K
    else
        ops=Operator{T}(K.ops[1]),Operator{T}(K.ops[2])
        KroneckerOperator{typeof(ops[1]),typeof(ops[2]),typeof(K.domainspace),typeof(K.rangespace),
                            typeof(K.domaintensorizer),typeof(K.rangetensorizer),T}(ops,
              K.domainspace,K.rangespace,
              K.domaintensorizer,K.rangetensorizer)
    end
end


function colstart(A::KroneckerOperator,k::Integer)
    K=block(A.domaintensorizer,k)
    blockstart(A.rangetensorizer,max(1,K-blockbandwidth(A,2)))
end

function colstop(A::KroneckerOperator,k::Integer)
    inds = A.domaintensorizer[k]
    # first block with all zeros
    css=map(colstop,A.ops,inds)
    blk=sum(css)
    cs=blockstart(A.rangetensorizer,blk-1)+css[1]-1
end

function rowstart(A::KroneckerOperator,k::Integer)
    K=block(rangespace(A),k)
    blockstart(domainspace(A),max(1,K-blockbandwidth(A,1)))
end

function rowstop(A::KroneckerOperator,k::Integer)
    K=block(rangespace(A),k)
    st=blockstop(domainspace(A),K+blockbandwidth(A,2))
    # zero indicates above dimension
    st==0?size(A,2):min(size(A,2),st)
end


bandinds(K::KroneckerOperator) = (-∞,∞)

isbandedblock(K::KroneckerOperator) = all(isbandedblock,K.ops)
isbandedblockbanded(K::KroneckerOperator) =
    all(op->isbanded(op) && isinf(size(op,1)) && isinf(size(op,2)),K.ops)
israggedbelow(K::KroneckerOperator) = all(israggedbelow,K.ops)


blockbandinds(K::KroneckerOperator) =
    (blockbandinds(K.ops[1],1)+blockbandinds(K.ops[2],1),
    blockbandinds(K.ops[1],2)+blockbandinds(K.ops[2],2))

# If each block were in turn BlockBandedMatrix, these would
# be the    bandinds
subblock_blockbandinds(K::KroneckerOperator) =
    (min(blockbandinds(K.ops[1],1),-blockbandinds(K.ops[2],2)) ,
           max(blockbandinds(K.ops[1],2),-blockbandinds(K.ops[2],1)))


# If each block were in turn BandedMatrix, these are the bandinds
function subblockbandinds(K::KroneckerOperator)
    if all(hastrivialblocks,domainspace(K).spaces) &&
            all(hastrivialblocks,rangespace(K).spaces)
        subblock_blockbandinds(K)
    else
        dt = domaintensorizer(K).iterator
        rt = rangetensorizer(K).iterator
        # assume block size is repeated and square
        @assert all(b->isa(b,Repeated),dt.blocks)
        @assert rt.blocks == dt.blocks



        sb = subblock_blockbandinds(K)
        # divide by the size of each block
        sb_sz = mapreduce(value,*,dt.blocks)
        # spread by sub block szie
        (sb[1]-1)*sb_sz+1,(sb[2]+1)*sb_sz-1
    end
end

subblockbandinds(K::KroneckerOperator,k::Integer) = subblockbandinds(K)[k]

subblockbandinds(::Union{ConstantOperator,ZeroOperator},::Integer) = 0


typealias Wrappers Union{ConversionWrapper,MultiplicationWrapper,DerivativeWrapper,LaplacianWrapper,
                       SpaceOperator,ConstantTimesOperator}



isbandedblockbanded(P::Union{PlusOperator,TimesOperator}) = all(isbandedblockbanded,P.ops)



blockbandinds(P::PlusOperator,k::Int) =
    mapreduce(op->blockbandinds(op,k),k==1?min:max,P.ops)
blockbandinds(P::PlusOperator) = blockbandinds(P,1),blockbandinds(P,2)
subblockbandinds(K::PlusOperator,k::Integer) =
    mapreduce(v->subblockbandinds(v,k),k==1?min:max,K.ops)

blockbandinds(P::TimesOperator,k::Int) = mapreduce(op->blockbandinds(op,k),+,P.ops)
subblockbandinds(P::TimesOperator,k::Int) = mapreduce(op->subblockbandinds(op,k),+,P.ops)
blockbandinds(P::TimesOperator) = blockbandinds(P,1),blockbandinds(P,2)

domaintensorizer(R::Operator) = tensorizer(domainspace(R))
rangetensorizer(R::Operator) = tensorizer(rangespace(R))

domaintensorizer(P::PlusOperator) = domaintensorizer(P.ops[1])
rangetensorizer(P::PlusOperator) = rangetensorizer(P.ops[1])

domaintensorizer(P::TimesOperator) = domaintensorizer(P.ops[end])
rangetensorizer(P::TimesOperator) = rangetensorizer(P.ops[1])


subblockbandinds(K::Wrappers,k::Integer) = subblockbandinds(K.op,k)
for FUNC in (:blockbandinds,:isbandedblockbanded,:domaintensorizer,:rangetensorizer)
    @eval $FUNC(K::Wrappers) = $FUNC(K.op)
end



function subblockbandindssum(P,k)
    ret=0
    for op in P
        ret+=subblockbandinds(op,k)::Int
    end
    ret
end

subblockbandinds(P::TimesOperator,k) = subblockbandindssum(P.ops,1)



domainspace(K::KroneckerOperator) = K.domainspace
rangespace(K::KroneckerOperator) = K.rangespace

domaintensorizer(K::KroneckerOperator) = K.domaintensorizer
rangetensorizer(K::KroneckerOperator) = K.rangetensorizer


# we suport 4-indexing with KroneckerOperator
# If A is K x J and B is N x M, then w
# index to match KO=reshape(kron(B,A),N,K,M,J)
# that is
# KO[k,n,j,m] = A[k,j]*B[n,m]
# TODO: arbitrary number of ops

getindex(KO::KroneckerOperator,k::Integer,n::Integer,j::Integer,m::Integer) =
    KO.ops[1][k,j]*KO.ops[2][n,m]

function getindex(KO::KroneckerOperator,kin::Integer,jin::Integer)
    j,m=KO.domaintensorizer[jin]
    k,n=KO.rangetensorizer[kin]
    KO[k,n,j,m]
end

function getindex(KO::KroneckerOperator,k::Integer)
    if size(KO,1) == 1
        KO[1,k]
    elseif size(KO,2) == 1
        KO[k,1]
    else
        throw(ArgumentError("[k] only defined for 1 x ∞ and ∞ x 1 operators"))
    end
end


*(A::KroneckerOperator,B::KroneckerOperator) =
    KroneckerOperator(A.ops[1]*B.ops[1],A.ops[2]*B.ops[2])



## Shorthand


⊗(A,B) = kron(A,B)

Base.kron(A::Operator,B::Operator) = KroneckerOperator(A,B)
Base.kron(A::Operator,B) = KroneckerOperator(A,B)
Base.kron(A,B::Operator) = KroneckerOperator(A,B)
Base.kron{T<:Operator}(A::Vector{T},B::Operator) =
    Operator{promote_type(eltype(T),eltype(B))}[kron(a,B) for a in A]
Base.kron{T<:Operator}(A::Operator,B::Vector{T}) =
    Operator{promote_type(eltype(T),eltype(A))}[kron(A,b) for b in B]
Base.kron{T<:Operator}(A::Vector{T},B::UniformScaling) =
    Operator{promote_type(eltype(T),eltype(B))}[kron(a,1.0B) for a in A]
Base.kron{T<:Operator}(A::UniformScaling,B::Vector{T}) =
    Operator{promote_type(eltype(T),eltype(A))}[kron(1.0A,b) for b in B]






## transpose


Base.transpose(K::KroneckerOperator)=KroneckerOperator(K.ops[2],K.ops[1])

for TYP in (:ConversionWrapper,:MultiplicationWrapper,:DerivativeWrapper,:IntegralWrapper,:LaplacianWrapper),
    FUNC in (:domaintensorizer,:rangetensorizer)
    @eval $FUNC(S::$TYP) = $FUNC(S.op)
end


Base.transpose(S::SpaceOperator) =
    SpaceOperator(transpose(S.op),domainspace(S).',rangespace(S).')
Base.transpose(S::ConstantTimesOperator) = sp.c*S.op.'



### Calculus

#TODO: general dimension
function Derivative{SV,TT,DD}(S::TensorSpace{SV,TT,DD,2},order::Vector{Int})
    @assert length(order)==2
    if order[1]==0
        Dy=Derivative(S[2],order[2])
        K=eye(S[1])⊗Dy
        T=eltype(Dy)
    elseif order[2]==0
        Dx=Derivative(S[1],order[1])
        K=Dx⊗eye(S[2])
        T=eltype(Dx)
    else
        Dx=Derivative(S[1],order[1])
        Dy=Derivative(S[2],order[2])
        K=Dx⊗Dy
        T=promote_type(eltype(Dx),eltype(Dy))
    end
    # try to work around type inference
    DerivativeWrapper{typeof(K),typeof(domainspace(K)),Vector{Int},T}(K,order)
end





### Copy

# finds block lengths for a subrange
function blocklengthrange(rt,kr)
    KR=block(rt,first(kr)):block(rt,last(kr))
    Klengths=Array(Int,length(KR))
    for ν in eachindex(KR)
        Klengths[ν]=blocklength(rt,KR[ν])
    end
    Klengths[1]+=blockstart(rt,KR[1])-kr[1]
    Klengths[end]+=kr[end]-blockstop(rt,KR[end])
    Klengths
end

function Base.convert(::Type{BandedBlockBandedMatrix},S::SubOperator)
    kr,jr=parentindexes(S)
    KO=parent(S)
    l,u=blockbandinds(KO)
    λ,μ=subblockbandinds(KO)

    rt=rangetensorizer(KO)
    dt=domaintensorizer(KO)
    ret=bbbzeros(S)

    Kshft = block(rt,kr[1])-1
    Jshft = block(dt,jr[1])-1



    for J=Block(1):Block(blocksize(ret,2))
        jshft = (J==Block(1) ? jr[1] : blockstart(dt,J+Jshft)) - 1
        for K=blockcolrange(ret,J)
            Bs=view(ret,K,J)
            kshft = (K==Block(1) ? kr[1] : blockstart(rt,K+Kshft)) - 1
            for ξ=1:size(Bs,2),κ=colrange(Bs,ξ)
                Bs[κ,ξ]=KO[κ+kshft,ξ+jshft]
            end
        end
    end

    ret
end


function Base.convert{KKO<:KroneckerOperator,T}(::Type{BandedBlockBandedMatrix},S::SubOperator{T,KKO})
    kr,jr=parentindexes(S)
    KO=parent(S)
    l,u=blockbandinds(KO)
    λ,μ=subblockbandinds(KO)

    rt=rangetensorizer(KO)
    dt=domaintensorizer(KO)
    ret=bbbzeros(S)

    A,B=KO.ops
    K=block(rt,kr[end]);J=block(dt,jr[end])
    AA=A[Block(1):Block(K),Block(1):Block(J)]
    BB=B[Block(1):Block(K),Block(1):Block(J)]


    Jsh=block(dt,jr[1])-1
    Ksh=block(rt,kr[1])-1


    for J=Block(1):Block(blocksize(ret,2))
        # only first block can be shifted inside block
        jsh = J==Block(1)?jr[1]-blockstart(dt,J+Jsh):0
        for K=blockcolrange(ret,J)
            Bs=view(ret,K,J)
            ksh=K==Block(1)?kr[1]-blockstart(dt,K+Ksh):0
            for j=1:size(Bs,2),k=colrange(Bs,j)
                κ,ν=subblock2tensor(rt,K+Ksh,k+ksh)
                ξ,μ=subblock2tensor(dt,J+Jsh,j+jsh)
                Bs[k,j]=AA[κ,ξ]*BB[ν,μ]
            end
        end
    end

    ret
end



## TensorSpace operators


## Conversion




conversion_rule(a::TensorSpace,b::TensorSpace) = conversion_type(a[1],b[1])⊗conversion_type(a[2],b[2])
maxspace(a::TensorSpace,b::TensorSpace) = maxspace(a[1],b[1])⊗maxspace(a[2],b[2])

# TODO: we explicetly state type to avoid type inference bug in 0.4

ConcreteConversion(a::BivariateSpace,b::BivariateSpace) =
    ConcreteConversion{typeof(a),typeof(b),
                        promote_type(eltype(a),eltype(b),real(eltype(eltype(domain(a)))),real(eltype(eltype(domain(b)))))}(a,b)

Conversion(a::TensorSpace,b::TensorSpace) = ConversionWrapper(promote_type(eltype(a),eltype(b)),
                KroneckerOperator(Conversion(a[1],b[1]),Conversion(a[2],b[2])))



function Multiplication{TS<:TensorSpace}(f::Fun{TS},S::TensorSpace)
    lr=LowRankFun(f)
    ops=map(kron,map(a->Multiplication(a,S[1]),lr.A),map(a->Multiplication(a,S[2]),lr.B))
    MultiplicationWrapper(f,+(ops...))
end

## Functionals
Evaluation(sp::TensorSpace,x::Vec) = EvaluationWrapper(sp,x,zeros(Int,length(x)),⊗(map(Evaluation,sp.spaces,x)...))
Evaluation(sp::TensorSpace,x::Tuple) = Evaluation(sp,Vec(x...))
