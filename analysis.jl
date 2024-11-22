###### plot capacities year on year in multi stage model ###

using DataFrames 
using CSV
using Plots

#### base files ###################
path_in = "/Users/am0271/Princeton Dropbox/Aniruddh Mohan/Speed Limits/ERCOT-System-New/ERCOT_Multi_stage-IRA"
texas_codebook = CSV.read(joinpath(path_in, "texas_codebook.csv"), DataFrame)


# result files 
path_in = "/Users/am0271/Princeton Dropbox/Aniruddh Mohan/Speed Limits/ERCOT-System-New/ERCOT_Multi_stage-noIRA/results_myopic"
capacities_new_multistage = CSV.read(joinpath(path_in, "capacities_new_multi_stage.csv"), DataFrame)

#### we need to identify vre, fossil, nuclear resources
### then for each, group together how much new capacity (positive or negative), gets done every year
### then smooth those to create Speed Limits
## then include these Speed Limits as an input file in GenX

