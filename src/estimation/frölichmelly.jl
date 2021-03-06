#==========================================================================================#

# TYPE

mutable struct FrölichMelly <: TwoStageModel

    first_stage::Micromodel
    second_stage::OLS
    pscore::Vector{Float64}
    weights::PWeights

    FrölichMelly() = new()
end

#==========================================================================================#

# FIRST STAGE

function first_stage(
        ::Type{FrölichMelly}, ::Type{M}, MD::Microdata; kwargs...
    ) where {M <: Micromodel}

    FSD                = Microdata(MD)
    FSD.map[:response] = FSD.map[:instrument]
    pop!(FSD.map, :treatment)
    pop!(FSD.map, :instrument)

    return fit(M, FSD; kwargs...)
end

#==========================================================================================#

# ESTIMATION

function fit(
        ::Type{FrölichMelly},
        ::Type{M},
        MD::Microdata;
        novar::Bool = false,
        kwargs...
    ) where {M <: Micromodel}

    m = first_stage(FrölichMelly, M, MD; novar = novar)
    return fit(FrölichMelly, m, MD; novar = novar, kwargs...)
end

function fit(
        ::Type{FrölichMelly},
        MM::Micromodel,
        MD::Microdata;
        novar::Bool = false,
        trim::AbstractFloat = 0.0,
    )

    w = getweights(MD)
    d = getvector(MD, :treatment)
    z = getvector(MD, :instrument)
    π = fitted(MM)
    v = [(2.0 * di - 1.0) * (zi - πi) / (πi * (1.0 - πi)) for (di, zi, πi) in zip(d, z, π)]

    v[find((trim .> π) .| (1.0 - trim .< π))] .= 0.0

    SSD               = Microdata(MD)
    SSD.map[:control] = vcat(SSD.map[:treatment], 1)
    obj               = FrölichMelly()
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

score(obj::FrölichMelly) = scale!(obj.weights, score(second_stage(obj)))

# EXPECTED JACOBIAN OF SCORE × NUMBER OF OBSERVATIONS

jacobian(obj::FrölichMelly, w::UnitWeights) = jacobian(second_stage(obj), obj.weights)

function jacobian(obj::FrölichMelly, w::AbstractWeights)
    return jacobian(second_stage(obj), reweight(w, obj.weights))
end

# EXPECTED JACOBIAN OF SCORE W.R.T. FIRST-STAGE PARAMETERS × NUMBER OF OBSERVATIONS

function crossjacobian(obj::FrölichMelly, w::UnitWeights)

    d = getvector(obj, :treatment)
    z = getvector(obj, :instrument)
    π = obj.pscore
    D = [- (2.0 * di - 1.0) * (zi / abs2(πi) + (1.0 - zi) / abs2(1.0 - πi))
         for (di, zi, πi) in zip(d, z, π)]

    D[find(obj.weights .== 0)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * scale!(D, g₁)
end

function crossjacobian(obj::FrölichMelly, w::AbstractWeights)

    d = getvector(obj, :treatment)
    z = getvector(obj, :instrument)
    π = obj.pscore
    D = [- wi * (2.0 * di - 1.0) * (zi / abs2(πi) + (1.0 - zi) / abs2(1.0 - πi))
         for (di, zi, πi, wi) in zip(d, z, π, w)]

    D[find(obj.weights .== 0)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * scale!(D, g₁)
end

#==========================================================================================#

# LINEAR PREDICTOR

predict(obj::FrölichMelly) = predict(second_stage(obj))

# FITTED VALUES

fitted(obj::FrölichMelly) = fitted(second_stage(obj))

# DERIVATIVE OF FITTED VALUES

jacobexp(obj::FrölichMelly) = jacobexp(second_stage(obj))

#==========================================================================================#

# UTILITIES

coefnames(obj::FrölichMelly) = coefnames(second_stage(obj))
