#==========================================================================================#

# TYPE

mutable struct IPW <: TwoStageModel

    first_stage::Micromodel
    second_stage::OLS
    pscore::Vector{Float64}
    weights::PWeights

    IPW() = new()
end

#==========================================================================================#

# FIRST STAGE

function first_stage(
        ::Type{IPW}, ::Type{M}, MD::Microdata; kwargs...
    ) where {M <: Micromodel}

    FSD                = Microdata(MD)
    FSD.map[:response] = FSD.map[:treatment]
    pop!(FSD.map, :treatment)

    return fit(M, FSD; kwargs...)
end

#==========================================================================================#

# ESTIMATION

function fit(
        ::Type{IPW},
        ::Type{M},
        MD::Microdata;
        novar::Bool = false,
        kwargs...
    ) where {M <: Micromodel}

    m = first_stage(IPW, M, MD; novar = novar)
    return fit(IPW, m, MD; novar = novar, kwargs...)
end

function fit(
        ::Type{IPW},
        MM::Micromodel,
        MD::Microdata;
        novar::Bool = false,
        trim::AbstractFloat = 0.0,
    )

    w = getweights(MD)
    d = getvector(MD, :treatment)
    π = fitted(MM)
    v = [(1.0 - di) / (1.0 - πi) + di / πi for (di, πi) in zip(d, π)]

    v[find((trim .> π) .| (1.0 - trim .< π))] .= 0.0

    SSD               = Microdata(MD)
    SSD.map[:control] = vcat(SSD.map[:treatment], 1)
    obj               = IPW()
    obj.first_stage   = MM
    obj.second_stage  = OLS(SSD)
    obj.pscore        = π
    obj.weights       = pweights(v)

    _fit!(second_stage(obj), reweight(w, obj.weights))
    novar || _vcov!(obj, getcorr(obj), w)

    return obj
end

#==========================================================================================#

# SCORE (MOMENT CONDITIONS)

score(obj::IPW) = scale!(obj.weights, score(second_stage(obj)))

# EXPECTED JACOBIAN OF SCORE × NUMBER OF OBSERVATIONS

jacobian(obj::IPW, w::UnitWeights) = jacobian(second_stage(obj), obj.weights)

function jacobian(obj::IPW, w::AbstractWeights)
    return jacobian(second_stage(obj), reweight(w, obj.weights))
end

# EXPECTED JACOBIAN OF SCORE W.R.T. FIRST-STAGE PARAMETERS × NUMBER OF OBSERVATIONS

function crossjacobian(obj::IPW, w::UnitWeights)

    d = getvector(obj, :treatment)
    π = obj.pscore
    D = [(1.0 - di) / abs2(1.0 - πi) - di / abs2(πi) for (di, πi) in zip(d, π)]

    D[find(obj.weights .== 0)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * scale!(D, g₁)
end

function crossjacobian(obj::IPW, w::AbstractWeights)

    d = getvector(obj, :treatment)
    π = obj.pscore
    D = [wi * ((1.0 - di) / abs2(1.0 - πi) - di / abs2(πi)) for (di, πi, wi)
         in zip(d, π, w)]

    D[find(obj.weights .== 0)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * scale!(D, g₁)
end

#==========================================================================================#

# LINEAR PREDICTOR

predict(obj::IPW) = predict(second_stage(obj))

# FITTED VALUES

fitted(obj::IPW) = fitted(second_stage(obj))

# DERIVATIVE OF FITTED VALUES

jacobexp(obj::IPW) = jacobexp(second_stage(obj))

#==========================================================================================#

# UTILITIES

coefnames(obj::IPW) = coefnames(second_stage(obj))
