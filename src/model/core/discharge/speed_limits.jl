# speed_limits.jl - Defines shadow investment constraints for phased capacity additions

function shadow_investment_constraints!(EP::Model, inputs::Dict, setup::Dict)
    println("Applying shadow investment constraints")

    # load inputs
    settings_d = setup["MultiStageSettingsDict"]   
    NumStages = settings_d["NumStages"]  # Number of planning stages
    gen = inputs["RESOURCES"]  # Generators dictionary

    # Load NumInvStages and investment share directly using helper functions
    NumInvStages = Dict(y => num_inv_stages(gen[y]) for y in inputs["NEW_CAP"])   # not working at the moment in load resources, it defaults to 2
    
    # Feasibility check: Ensure NumInvStages[y] < NumStages for each generator
    for y in inputs["NEW_CAP"]
        if NumInvStages[y] >= NumStages
            error("The number of investment stages for generator $(y) must be less than the number of planning stages to allow capacity additions.")
        end
    end  

    # Define new shadow investment variable and shadow investment stage variable for each generator 
    @variable(EP, vShadow_New[y in inputs["NEW_CAP"]] >=0)   #tracks shadow capacity 
    @variable(EP, vShadow_StageNew[y in inputs["NEW_CAP"]] >=0)   #tracks new shadow stage

    # constraint such that only one stage at a time can be unlocked.
    @constraint(EP, cShadowStageYear[y in inputs["NEW_CAP"]], EP[:vShadow_StageNew][y] <= 1) 

    #Updated count of investment stages met
    @expression(EP, eTotalShadowStage[y in inputs["NEW_CAP"]], EP[:vShadow_Stage_Tracking][y] + vShadow_StageNew[y] )   

    ### TOTAL SHADOW CAPACITY REMAINING which currently is formulated in a way that it depletes if new capacity has been built.
    @expression(EP, eTotalShadowCap[y in inputs["NEW_CAP"]], (EP[:vShadow_Existing][y]) + vShadow_New[y] - EP[:vCAP][y] )   #if you use vcap you deplete existing shadow capacity too 
    
    # constraint that you can only go up to the max number of investment stages for a generator
    @constraint(EP, cTotalShadowStages[y in inputs["NEW_CAP"]], eTotalShadowStage[y]  <= NumInvStages[y]) # 

    # this is the key constraint that forces the model to build shadow capacity, because without it you cannot build actual new capacity 
    @constraint(EP, cNewTech1[y in inputs["NEW_CAP"]], EP[:vCAP][y] <= EP[:vShadow_Existing][y])   
    
    # this needs to be refined, essentially we want new capacity to only be possible when all the shadow investment stages have been met
    @constraint(EP, cNewTech2[y in inputs["NEW_CAP"]], EP[:vCAP][y] <= eTotalShadowStage[y])  
    
    
    # Expression to include shadow investment costs in the objective function
    @expression(EP, eShadowCost, sum(inv_cost_per_mwyr(gen[y])/100 * vShadow_StageNew[y] for y in inputs["NEW_CAP"]) + 
                                sum(inv_cost_per_mwyr(gen[y])/10 * vShadow_New[y] for y in inputs["NEW_CAP"]))
    # each time new investment stage unlocked, you need to pay for it. upto a max of total investment stages, which is constrained by cTotalShadowStages above  
    # These parameters need to be loaded from the input files and not hard coded here. at the moment it's parametrized such that each stage is 1% of the capex and each unit of shadow capacity is 10% of the capex.   

    # Add shadow costs to the overall objective function
    add_to_expression!(EP[:eObj], eShadowCost)
end
