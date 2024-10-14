@doc raw"""
	write_multi_stage_new_capacities_discharge(outpath::String, settings_d::Dict)

This function writes the file new\_capacities\_multi\_stage.csv to the Results directory. This file contains starting resource capacities from the first model stage and new resource capacities for each of the first and all subsequent model stages.

inputs:

  * outpath – String which represents the path to the Results directory.
  * settings\_d - Dictionary containing settings dictionary configured in the multi-stage settings file multi\_stage\_settings.yml.
"""
function write_multi_stage_new_capacities_discharge(outpath::String, settings_d::Dict)
    num_stages = settings_d["NumStages"] # Total number of investment planning stages
    capacities_d = Dict()

    for p in 1:num_stages
        inpath = joinpath(outpath, "results_p$p")
        capacities_d[p] = load_dataframe(joinpath(inpath, "capacity.csv"))
    end

    # Set first column of DataFrame as resource names from the first stage
    df_cap = DataFrame(Resource = capacities_d[1][!, :Resource],
        Zone = capacities_d[1][!, :Zone])

    # Store starting capacities from the first stage
    df_cap[!, Symbol("StartCap_p1")] = capacities_d[1][!, :StartCap]

    # Store end capacities for all stages
    for p in 1:num_stages
        if p==1
            df_cap[!, Symbol("NewCap_p$p")] = capacities_d[p][!, :EndCap] .- capacities_d[1][!, :StartCap]
        else
            df_cap[!, Symbol("NewCap_p$p")] = capacities_d[p][!, :EndCap] .- capacities_d[p-1][!, :EndCap]
        end
    end

    CSV.write(joinpath(outpath, "capacities_new_multi_stage.csv"), df_cap)
end
