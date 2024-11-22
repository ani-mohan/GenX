### load speed limits_in
@doc raw"""
	load_speed_limits(setup::Dict,path::AbstractString)

Loads various data inputs from multiple input .csv files in policies directory and stores variables in a Dict (dictionary) object for use in model() function

inputs:
setup - dict object containing setup parameters
inputs - dict object containing relevant inputs for model 
path - string path to working directory

"""
function load_speed_limits!(setup::Dict, path::AbstractString, inputs::Dict)

    filename = "Speed_Limits.csv"
    df = load_dataframe(joinpath(path, filename))

    scale_factor = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1 # Million $/kton if scaled, $/ton if not scaled

    if "Limit" in names(df)
        df.Limit = df.Limit ./ scale_factor
    end

    inputs["Speed_Limits"] = df

    println(filename * " Successfully Read!")
end