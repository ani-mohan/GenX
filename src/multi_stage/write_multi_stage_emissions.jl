@doc raw"""
	write_multi_stage_emissions(outpath::String, settings_d::Dict)

This function writes the file emissions\_multi\_stage.csv to the Results directory. This file contains total emissions from the first model stage and new resource capacities for each of the first and all subsequent model stages.

inputs:

  * outpath – String which represents the path to the Results directory.
  * settings\_d - Dictionary containing settings dictionary configured in the multi-stage settings file multi\_stage\_settings.yml.
"""
function write_multi_stage_emissions(outpath::String, settings_d::Dict)
    num_stages = settings_d["NumStages"] # Total number of investment planning stages
    emissions_d = Dict()

    for p in 1:num_stages
        inpath = joinpath(outpath, "results_p$p")
        emissions_d[p] = load_dataframe(joinpath(inpath, "emissions.csv"))
    end

    # Set first column of DataFrame as resource names from the first stage
    df_emissions = DataFrame(Total = 0.0)

    sum_emissions = 0.0
    p=1
    while p<=num_stages
        sum_emissions = sum_emissions + emissions_d[p][!, :Total][1] 
        p=p+1
    end

    df_emissions[!, :Total][1] = sum_emissions

    for s in 1:num_stages
        df_emissions[!, Symbol("Total_p$s")] .= emissions_d[s][!, :Total][1]
    end

    CSV.write(joinpath(outpath, "emissions_multi_stage.csv"), df_emissions)
end
