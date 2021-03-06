#==========================================================================================#

# TYPE

mutable struct Probit <: MLE

    sample::Microdata
    β::Vector{Float64}
    V::Matrix{Float64}

    Probit() = new()
end

#==========================================================================================#

# CONSTRUCTOR

function Probit(MD::Microdata)
    obj        = Probit()
    obj.sample = MD
    return obj
end

#==========================================================================================#

# ESTIMATION

function _fit!(obj::Probit, w::UnitWeights)

    y  = getvector(obj, :response)
    x  = getmatrix(obj, :control)

    p  = mean(y)
    p  = 1.0 / normpdf(norminvcdf(p))
    β₀ = scale!(p, x \ y)

    μ  = x * β₀
    r  = similar(y)
    v  = similar(μ)

    function L(β::Vector)

        A_mul_B!(μ, x, β)
        ll = 0.0

        @inbounds for (yi, μi) in zip(y, μ)
            ll += (iszero(yi) ? normlogccdf(μi) : normlogcdf(μi))
        end

        return - ll
    end

    function G!(g::Vector, β::Vector)

        A_mul_B!(μ, x, β)

        @inbounds for (i, (yi, μi)) in enumerate(zip(y, μ))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            r[i] = - normpdf(μi) / ηi
        end

        g[:] = x' * r

    end

    function LG!(g::Vector, β::Vector)

        A_mul_B!(μ, x, β)
        ll = 0.0

        @inbounds for (i, (yi, μi)) in enumerate(zip(y, μ))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            r[i] = - normpdf(μi) / ηi
            ll  += (iszero(yi) ? log(- ηi) : log(ηi))
        end

        g[:] = x' * r

        return - ll
    end

    function H!(h::Matrix, β::Vector)

        A_mul_B!(μ, x, β)

        @inbounds for (i, (yi, μi)) in enumerate(zip(y, μ))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            ηi   = normpdf(μi) / ηi
            v[i] = abs2(ηi) + μi * ηi
        end

        h[:, :] = crossprod(x, v)
    end

    res = optimize(TwiceDifferentiable(L, G!, LG!, H!, β₀), β₀, Newton())

    if Optim.converged(res)
        obj.β = Optim.minimizer(res)
    else
        throw("likelihood maximization did not converge")
    end
end

function _fit!(obj::Probit, w::AbstractWeights)

    y  = getvector(obj, :response)
    x  = getmatrix(obj, :control)
    w  = values(w)

    p  = mean(y)
    p  = 1.0 / normpdf(norminvcdf(p))
    β₀ = scale!(p, x \ y)

    μ  = x * β₀
    r  = similar(y)
    v  = similar(μ)

    function L(β::Vector)

        A_mul_B!(μ, x, β)
        ll = 0.0

        @inbounds for (yi, μi, wi) in zip(y, μ, w)
            ll += wi * (iszero(yi) ? normlogccdf(μi) : normlogcdf(μi))
        end

        return - ll
    end

    function G!(g::Vector, β::Vector)

        A_mul_B!(μ, x, β)

        @inbounds for (i, (yi, μi, wi)) in enumerate(zip(y, μ, w))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            r[i] = - wi * normpdf(μi) / ηi
        end

        g[:] = x' * r

    end

    function LG!(g::Vector, β::Vector)

        A_mul_B!(μ, x, β)
        ll = 0.0

        @inbounds for (i, (yi, μi, wi)) in enumerate(zip(y, μ, w))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            r[i] = - wi * normpdf(μi) / ηi
            ll  += wi * (iszero(yi) ? log(- ηi) : log(ηi))
        end

        g[:] = x' * r

        return - ll
    end

    function H!(h::Matrix, β::Vector)

        A_mul_B!(μ, x, β)

        @inbounds for (i, (yi, μi, wi)) in enumerate(zip(y, μ, w))
            ηi   = (iszero(yi) ? (normcdf(μi) - 1.0) : normcdf(μi))
            ηi   = normpdf(μi) / ηi
            v[i] = wi * (abs2(ηi) + μi * ηi)
        end

        h[:, :] = crossprod(x, v)
    end

    res = optimize(TwiceDifferentiable(L, G!, LG!, H!, β₀), β₀, Newton())

    if Optim.converged(res)
        obj.β = Optim.minimizer(res)
    else
        throw("likelihood maximization did not converge")
    end
end

#==========================================================================================#

# SCORE (DERIVATIVE OF THE LIKELIHOOD FUNCTION)

function score(obj::Probit)

    y = getvector(obj, :response)
    x = getmatrix(obj, :control)
    v = x * obj.β

    @inbounds for (i, (yi, vi)) in enumerate(zip(y, v))
        ηi   = (iszero(yi) ? (normcdf(vi) - 1.0) : normcdf(vi))
        v[i] = normpdf(vi) / ηi
    end

    return scale!(v, copy(x))
end

# EXPECTED JACOBIAN OF SCORE × NUMBER OF OBSERVATIONS

function jacobian(obj::Probit, w::UnitWeights)

    y = getvector(obj, :response)
    x = getmatrix(obj, :control)
    v = x * obj.β

    @inbounds for (i, (yi, vi)) in enumerate(zip(y, v))
        ηi   = (iszero(yi) ? (normcdf(vi) - 1.0) : normcdf(vi))
        ηi   = normpdf(vi) / ηi
        v[i] = abs2(ηi) + vi * ηi
    end

    return crossprod(x, v, neg = true)
end

function jacobian(obj::Probit, w::AbstractWeights)

    y = getvector(obj, :response)
    x = getmatrix(obj, :control)
    v = x * obj.β

    @inbounds for (i, (yi, vi, wi)) in enumerate(zip(y, v, values(w)))
        ηi   = (iszero(yi) ? (normcdf(vi) - 1.0) : normcdf(vi))
        ηi   = normpdf(vi) / ηi
        v[i] = wi * (abs2(ηi) + vi * ηi)
    end

    return crossprod(x, v, neg = true)
end

#==========================================================================================#

# LINEAR PREDICTOR

predict(obj::Probit) = getmatrix(obj, :control) * obj.β

# FITTED VALUES

fitted(obj::Probit) = normcdf.(predict(obj))

# DERIVATIVE OF FITTED VALUES

function jacobexp(obj::Probit)
    x  = copy(getmatrix(obj, :control))
    ϕ  = x * obj.β
    ϕ .= normpdf.(ϕ)
    return scale!(ϕ, x)
end

#==========================================================================================#

# UTILITIES

coefnames(obj::Probit) = getnames(obj, :control)

# LIKELIHOOD FUNCTION

function _loglikelihood(obj::Probit, w::UnitWeights)

    y  = getvector(obj, :response)
    μ  = predict(obj)
    ll = 0.0

    @inbounds for (yi, μi) in zip(y, μ)
        ll += (iszero(yi) ? normlogccdf(μi) : normlogcdf(μi))
    end

    return ll
end

function _loglikelihood(obj::Probit, w::AbstractWeights)

    y  = getvector(obj, :response)
    μ  = predict(obj)
    ll = 0.0

    @inbounds for (yi, μi, wi) in zip(y, μ, values(w))
        ll += wi * (iszero(yi) ? normlogccdf(μi) : normlogcdf(μi))
    end

    return ll
end

# LIKELIHOOD FUNCTION UNDER NULL MODEL

function _nullloglikelihood(obj::Probit, w::AbstractWeights)
    y = getvector(obj, :response)
    μ = mean(y, w)
    return nobs(obj) * (μ * log(μ) + (1.0 - μ) * log(1.0 - μ))
end

# DEVIANCE

deviance(obj::Probit) = - 2.0 * _loglikelihood(obj, getweights(obj))

# DEVIANCE UNDER NULL MODEL

nulldeviance(obj::Probit) = - 2.0 * _nullloglikelihood(obj, getweights(obj))
