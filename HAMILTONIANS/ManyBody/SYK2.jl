module SYK2
    using SparseArrays;
    using Distributions;
    using LinearAlgebra;
    using StaticArrays;

    include("../FermionAlgebra.jl");
    using .FermionAlgebra;


    struct Params
        L:: Int64;
        t:: Matrix{Float64};
        S:: Real;
        μ:: Float64;
        deviation:: Real;
        mean:: Real;

        function Params(L:: Int64, t̲::Union{Matrix{Float64}, Missing} = missing , S::Real = 1/2, μ:: Real = 0., mean::Real=0, deviation::Real=1.)
            
            if isequal(t̲, missing)
                t = Matrix{Float64}(undef, (L,L))
                for i=1:L, j=1:i
                    t[i,j] = rand(Normal(mean, deviation));
                    
                    if i!=j
                        t[j,i] = t[i,j];
                    end
                end
            else
                t = t̲[1:L,1:L];
            end      

            new(L, t, S, μ, deviation, mean)
        end
    end

    function GetTypeOfOperatorOnSite(position:: String)
        typeOfOperatorOnSite = Dict{String,String}(
            "i" => "c⁺", 
            "j" => "c",
        );

        return typeOfOperatorOnSite[position]
    end


    function AnaliticalNormOfHamiltonian(params)
        function AnaliticalExpressionForAverageOfSqueredHamiltonian(params)
            stateNumbers = FermionAlgebra.IndecesOfSubBlock(params.L) .- 1;
            states = FermionAlgebra.WriteStateInFockSpace.(stateNumbers, params.L, params.S);

            t = params.t
            D = binomial(params.L, Int(params.L/2));
            norm = 0.

            # Covers first term of equation
            for state in states
                positionsOfParticles = findall(x -> x==1 ,state);

                for i in positionsOfParticles
                    for k in positionsOfParticles
                        norm  += t[i,i]*t[k,k]
                    end
                end
            end 

            # Covers second term of a equation
            for state in states
                positionsOfParticles = findall(x -> x==1 ,state);

                for i in positionsOfParticles
                    for j in 1:params.L
                        if i != j
                            norm  += t[i,j]*t[j,i]
                        end
                    end
                end
            end


            # Covers third term of a equation
            for state in states
                positionsOfParticles = findall(x -> x==1 ,state);

                for i in positionsOfParticles
                    for j in positionsOfParticles
                        if i != j
                            norm  -= t[i,j]*t[j,i]
                        end
                    end
                end
            end 

            return norm / (D*params.L);
        end

        function AnaliticalExpressionForSquaredAverageOfHamiiltonian(params)
            stateNumbers = FermionAlgebra.IndecesOfSubBlock(params.L) .- 1;
            states = FermionAlgebra.WriteStateInFockSpace.(stateNumbers, params.L, params.S);

            t = params.t
            D = binomial(params.L, Int(params.L/2));
            norm = 0.

            for state in states
                positionsOfParticles = findall(x -> x==1 ,state);

                for i in positionsOfParticles
                    norm += t[i,i]
                end
            end

            return ( norm / (D*√params.L) )^2
        end

        H²_avg =  AnaliticalExpressionForAverageOfSqueredHamiltonian(params);
        H_avg² =  AnaliticalExpressionForSquaredAverageOfHamiiltonian(params);

        # println("AnaliticalNormOfHamiltonian: ", params.L, " ", params.deviation)
        # println("   ",H²_avg, " - ", H_avg²)
        return H²_avg - H_avg²;
    end


    function AnaliticalNormOfHamiltonianAveraged(params:: Params, N::Int64 = Int(params.L÷2))
        if N==0 || N==params.L
            return 1.
        end
        norm = params.deviation^2 * N * (params.L - N + 1 - N/params.L);
        # norm = params.deviation^2 * params.L *(params.L + 1)/4 ;
        return √(norm);
    end



    function GetSignOfOperatorPermutation1(i_cre, j_inh, state)
        # println("($(i_cre), $(j_inh)):", state)
        sign_inh = isodd(sum(state[1:j_inh-1])) ? -1 : 1;
        state[j_inh] = 0;
        sign_cre = isodd(sum(state[1:i_cre-1])) ? -1 : 1;

        return sign_inh*sign_cre;
    end

    function sign1(ket:: Int64, opPos_i:: Int64, opPos_j:: Int64, params:: Params)
        ket_fockSpace = FermionAlgebra.WriteStateInFockSpace(ket, params.L, params.S);
        # We need to reverse "ket_fockSpace" because program starts counting postions from left to right 
        sign = GetSignOfOperatorPermutation1(opPos_i, opPos_j, reverse(ket_fockSpace));
        return sign;
    end



    function GetSignOfOperatorPermutation2(i_cre, j_inh, state)
        return isodd(sum(@view(state[i_cre+1 : j_inh-1]))) ? -1 : 1;
    end

    function sign2(ket:: Int64, opPos_i:: Int64, opPos_j:: Int64, ket_fockSpace::Vector{Int}, S)
        FermionAlgebra.WriteStateInFockSpace!(ket, ket_fockSpace, S);
        # We need to reverse "ket_fockSpace" because program starts counting postions from left to right 
        reverse!(ket_fockSpace)

        sign = GetSignOfOperatorPermutation2(opPos_i, opPos_j, ket_fockSpace);
        return sign;
    end
    

    global function Ĥ1(params:: Params, N::Int64 =Int(params.L÷2),  isSparse:: Bool = true) 
        L = params.L;
        D = binomial(L,N)

        opᵢ = FermionAlgebra.GetMatrixRepresentationOfOperator(GetTypeOfOperatorOnSite("i"), params.S, isSparse);
        opⱼ = FermionAlgebra.GetMatrixRepresentationOfOperator(GetTypeOfOperatorOnSite("j"), params.S, isSparse);
        id = FermionAlgebra.GetMatrixRepresentationOfOperator("id", params.S, isSparse);
        
        normalization = AnaliticalNormOfHamiltonianAveraged(params, N);
        ind = FermionAlgebra.IndecesOfSubBlock(L,N);

        rows = Vector{Int64}();
        cols = Vector{Int64}();
        vals = Vector{Float64}();
    
        # Hopping term
        cᵢ⁺cⱼ= fill(id, L); 
        for i=1:L, j=i:L

            # Order of those products of operators oisimporattn so dont change it!
            cᵢ⁺cⱼ[i] *= opᵢ;
            cᵢ⁺cⱼ[j] *= opⱼ;

            # println("-----------");
            matrixElements = findall(x -> x==1 , foldl(kron, cᵢ⁺cⱼ)[ind,ind] );  
            # println()
            rows_ij = map(elm -> elm[1], matrixElements); 
            cols_ij = map(elm -> elm[2], matrixElements); 
            vals_ij = map(elm -> sign1(ind[elm[2]]-1, i, j, params) * params.t[L+1-i,L+1-j] / normalization, matrixElements); 
            # println()
            append!(rows, i==j ? rows_ij : vcat(rows_ij, cols_ij));
            append!(cols, i==j ? cols_ij : vcat(cols_ij, rows_ij));
            append!(vals, i==j ? vals_ij : vcat(vals_ij, conj.(vals_ij)));

            cᵢ⁺cⱼ[i] = cᵢ⁺cⱼ[j] = id;
        end
        
        
        return isSparse ? sparse(rows, cols, vals, D, D) : Matrix(sparse(rows, cols, vals, D, D));
    end


    global function Ĥ2(params:: Params, N::Int64 =Int(params.L÷2),  isSparse:: Bool = true) 
        L = params.L;
        D = binomial(L,N)

        opᵢ = FermionAlgebra.GetMatrixRepresentationOfOperator(GetTypeOfOperatorOnSite("i"), params.S, isSparse);
        opⱼ = FermionAlgebra.GetMatrixRepresentationOfOperator(GetTypeOfOperatorOnSite("j"), params.S, isSparse);
        id = FermionAlgebra.GetMatrixRepresentationOfOperator("id", params.S, isSparse);

        ind = FermionAlgebra.IndecesOfSubBlock(L,N);

        rows = Vector{Int64}();
        cols = Vector{Int64}();
        vals = Vector{Float64}();

        tmp_storingVector = Vector{Int}(undef,L);
    
        # Hopping term
        cᵢ⁺cⱼ= fill(id, L); 
        for i=1:L, j=i:L
            # Order of those products of operators is importana so dont change it!
            cᵢ⁺cⱼ[i] *= opᵢ;
            cᵢ⁺cⱼ[j] *= opⱼ;

            # println("-----------");
            matrixElements = findall(x -> x==1 ,foldl(kron, cᵢ⁺cⱼ)[ind,ind] );  
            # println()
            
            rows_ij = map(elm -> elm[1], matrixElements); 
            cols_ij = map(elm -> elm[2], matrixElements); 
            vals_ij = map(elm -> sign2(ind[elm[2]]-1, i, j, tmp_storingVector, params.S)*params.t[L+1-i,L+1-j] , matrixElements); 

            append!(rows, i==j ? rows_ij : vcat(rows_ij, cols_ij));
            append!(cols, i==j ? cols_ij : vcat(cols_ij, rows_ij));
            append!(vals, i==j ? vals_ij : vcat(vals_ij, conj.(vals_ij)));

            cᵢ⁺cⱼ[i] = cᵢ⁺cⱼ[j] = id;
        end
        
        normalization = AnaliticalNormOfHamiltonianAveraged(params, N);
        vals ./= normalization

        return isSparse ? sparse(rows, cols, vals, D, D) : Matrix(sparse(rows, cols, vals, D, D));
    end



end
