"""
GenX: An Configurable Capacity Expansion Model
Copyright (C) 2021,  Massachusetts Institute of Technology
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
A complete copy of the GNU General Public License v2 (GPLv2) is available
in LICENSE.txt.  Users uncompressing this from an archive may not have
received this license file.  If not, see <http://www.gnu.org/licenses/>.
"""

@doc raw"""
	DAC
"""

function dac!(EP::Model, inputs::Dict, setup::Dict)

	println("DAC module")
    

	dfDac = inputs["dfDac"]
    
	T = inputs["T"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones

	hours_per_subperiod = inputs["hours_per_subperiod"]

    # load dac input data and coupling parameters
    dfDac = inputs["dfDac"]
    Dac_params = inputs["Dac_params"]

    DAC_ID = dfDac[!,:DAC_ID]  # collect ids
    G_DAC = length(collect(skipmissing(dfDac[!,:R_ID])))  # number of DAC types

    dfGen = inputs["dfGen"]   #generator data

    nuclear_dac = dfDac[dfDac.DAC_heat_resource.=="Nuclear", :R_ID]           #subset of nuclear dac facilities

    # fuel cost
    fuel_cost = inputs["fuel_costs"] 
    fuel_CO2 = inputs["fuel_CO2"]

    nuclear = inputs["nuclear"]              #subset of nuclear power plants

    Max_Steam_Diversion_Per_Plant = Dac_params["Max_Steam_Diversion_Per_Plant"]    #maximum allowed share of steam diverted
    Heat_extraction_per_percent_steam_diversion = Dac_params["Heat_extraction_per_percent_steam_diversion"]  #heat available from extraction
    power_heat_ratio = Dac_params["Power_Heat_Ratio"]   #penalty per gj of steam diversion
    MW_to_GJ_conversion = Dac_params["MW_to_GJ_conversion"]   #conversion factor 
    HX_cost_multiplier = Dac_params["HX_cost_multiplier"]   #from HX costing and steam extraction
    HX_cost_constant = Dac_params["HX_cost_constant"]   #from HX costing and steam extraction

    gj_to_mmbtu_conversion = 0.948

    #decision variables
    # vCO2_DAC: the amount of hourly capture by a DAC facility, metric ton CO2/h. 
    # vCAP_DAC: the ANNUAL removal capacity of a DAC facility, metric ton CO2
    @variables(EP, begin
    vCO2_DAC[y in DAC_ID,t = 1:T] >= 0
    vsteam_heat_DAC[t=1:T, z = 1:Z] >= 0   #MW thermal directed for DAC
    vHX_DAC[y in DAC_ID] >= 0         #Maximum heat exchanger capacity
    vCAP_DAC[y in DAC_ID] >= 0   
    end)

    # DAC facility will either take heat (from natural gas) and electricity (from grid) as input, and produce negative co2 as write_outputs
    # heat consumption from heat resources, MMBTU/t CO2
    @expression(EP, eDAC_heat_consumption[y in DAC_ID, t = 1:T], vCO2_DAC[y,t] * dfDac[y,:Heat_MMBTU_per_CO2_metric_ton])
    
    #nuclear heat available in GJ in each zone at each hour as a function of generation, this heat can be used for DAC
    for z in 1:Z
        nuke_dac = intersect(nuclear_dac, dfDac[dfDac[!,:Zone].==z,:R_ID])
        nuke_gen = intersect(nuclear, dfGen[dfGen[!,:Zone].==z,:R_ID])

        @constraints(EP, begin
            [t in 1:T], sum(EP[:eDAC_heat_consumption][y, t] for y in nuke_dac) == sum(vsteam_heat_DAC[t,zz] for zz in z)*MW_to_GJ_conversion
        end)

        @constraints(EP, begin
            [t = 1:T], sum(vsteam_heat_DAC[t, zz] for zz in z) .<= sum(vHX_DAC[y] for y in nuke_dac)   # heat exchanger maximum thermal capacity is max steam diversion you can do 
        end)

        @constraints(EP, begin
            [t in 1:T], sum(EP[:vP][y,t] for y in nuke_gen) + sum(vsteam_heat_DAC[t,zz] for zz in z)*power_heat_ratio  .<= sum(EP[:eTotalCap][yy] for yy in nuke_gen)
        end)

        # heat_nuclear = Max_Steam_Diversion_Per_Plant*Heat_extraction_per_percent_steam_diversion*MW_to_GJ_conversion*sum(EP[:eTotalCap][yy] for yy in nuke_gen)   #where TotalCap is the capacity of AP1000 plants built in that zone

        # @constraints(EP, begin
        #     [t in 1:T], sum(EP[:eDAC_heat_consumption][y, t] for y in nuke_dac) .<= heat_nuclear
        # end)
    end

    @constraint(EP, cDAC_steam_max, sum(vHX_DAC[y] for y in DAC_ID) .<= Max_Steam_Diversion_Per_Plant*sum(EP[:eTotalCap][yy] for yy in nuclear)*Heat_extraction_per_percent_steam_diversion)    #max heat exchanging is 40% steam diversion from all plants  

    # the use of heat resources (e.g., natural gas) may result in additional CO2 emissions as DAC may not capture the CO2 from the heat resources, the co2 content from heat resouces times (1 - capture rate) = emitted co2 from heat resource
    @expression(EP, eDAC_heat_CO2[y in DAC_ID, t = 1:T],  eDAC_heat_consumption[y,t]* fuel_CO2[dfDac[y,:DAC_heat_resource]] * (1 - dfDac[y, :DAC_Fuel_Capture_Rate]))  

    # the electricity consumption for DAC, MWh/t CO2
    @expression(EP, eDAC_power[y in DAC_ID, t = 1:T], vCO2_DAC[y,t] * dfDac[y,:Electricity_MWh_per_CO2_metric_ton])

    # the power used for DAC must also go into a power balance equation
	@expression(EP, ePowerBalanceDAC[t=1:T, z=1:Z], sum(eDAC_power[y,t] for y in intersect(dfDac[dfDac[!,:Zone].==z,:][!,:DAC_ID])))
    EP[:ePowerBalance] = EP[:ePowerBalance] - ePowerBalanceDAC
    
    # #but nuclear dac reduces nuclear generation accordingly if steam diverted 
    @expression(EP, ePowerReductionnuclearheat[t=1:T, z=1:Z], 
        power_heat_ratio*(1/MW_to_GJ_conversion)*sum(EP[:eDAC_heat_consumption][y, t] for y in intersect(nuclear_dac, dfDac[dfDac[!,:Zone].==z,:R_ID])))   #this is from the power loss to heat gain ratio from hongxi   
    
    # # ## make sure that this penalty is actually applied to the power plant at each hour
    # # @constraint(EP, cNuclearPenalty[t=1:T], sum(EP[:vP][y,t] for y in nuclear) .>= sum(EP[:ePowerReductionnuclearheat][t,z] for z in 1:Z))

    # #finally add it to power balance to reflect that additional load
    # EP[:ePowerBalance] = EP[:ePowerBalance] - ePowerReductionnuclearheat
    

    #---------------------------------- add up cost ---------------------------------------
    # Fixed Cost
    # Combine CAPEX and FOM into annualized Fixed Cost
    # Fixed cost for a DAC y 
	@expression(EP, eCFixed_DAC[y in DAC_ID], dfDac[y,:Fix_Cost_per_tCO2_yr] * vCAP_DAC[y])   #Annualized CAPEX cost 
	# total fixed costs for all the DAC
	@expression(EP, eTotalCFixedDAC, sum(eCFixed_DAC[y] for y in DAC_ID))
	EP[:eObj] += eTotalCFixedDAC

    # Fixed DAC cost for energy (this covers capex of heat pump and like heat exchangers for the nuclear coupling case)
    @expression(EP, eCFixed_DAC_Energy[y in DAC_ID], HX_cost_multiplier*vHX_DAC[y] + HX_cost_constant + dfDac[y, :Energy_Fix_Cost_per_yr])   #Annualized CAPEX cost 
	# total fixed costs for all the DAC
	@expression(EP, eTotalCFixedDAC_Energy, sum(eCFixed_DAC_Energy[y] for y in DAC_ID))
	EP[:eObj] += eTotalCFixedDAC_Energy


    #heatpump cost in case of solid sorbent grid based - THIS IS ALL INCORPORATED IN THE Fix_Cost_per_tCO2_yr IN THE DAC SHEET FOR ELECTRIC HEAT PUMP SORBENT DAC BUT SHOWN BELOW TO REFLECT HOW THE 14 NUMBER CAME ABOUT
    # heatpump_cost_perMW = 0.5e6  #half a million per MW of heat pump
    # heatpump_mw_pertco2 = 2.72 #2.72 MW thermal per tco2 which is based on 9.8 GJ per tco2 from young et al and conversion using 0.2778 gj to mw conversion
    # annuity factor = 0.0899
    # heatpump_cost = (1/8760)*heatpump_mw_pertco2*heatpump_cost_perMW*annuity  1/8760 because vcap dac is annual removal capacity so divide to get hourly removal

    #FOR LPT extraction
    # Ce = max 1253546  #for 0.4 max extraction
    # annuity factor = 0.0899
    # hx_capex = Ce*annuity to get per year capex which is in dac.csv

    # Variable cost
    omega = inputs["omega"]
    # the total variable cost (heat cost + non-fuel vom cost) for DAC y at time t, $/t CO2  
    @expression(EP, eCDAC_Variable[y in DAC_ID, t = 1:T],  (eDAC_heat_consumption[y,t]*fuel_cost[dfDac[y,:DAC_heat_resource]][t]*gj_to_mmbtu_conversion + dfDac[y,:Var_OM_Cost_per_tCO2]*vCO2_DAC[y,t]))  

    # Cost associated with variable costs for DAC for the whole year
    @expression(EP, eCTotalVariableDACT[y in DAC_ID], sum(omega[t] * eCDAC_Variable[y,t] for t in 1:T ))

    # Total variable cost for all DAC facilities across the year
    @expression(EP, eCTotalVariableDAC, sum(eCTotalVariableDACT[y] for y in DAC_ID ))

    EP[:eObj] += eCTotalVariableDAC

    # unit commitment variables for DAC
    
    if setup["UCommit"] > 0
        DAC_COMMIT = dfDac[dfDac[!,:DAC_COMMIT] .== 1, :R_ID]
        @variables(EP, begin
            vCOMMIT_DAC[y in DAC_COMMIT, t=1:T] >= 0 # commitment status
            vSTART_DAC[y in DAC_COMMIT, t=1:T] >= 0 # startup
            vSHUT_DAC[y in DAC_COMMIT, t=1:T] >= 0 # shutdown
        end)

         # set the unit commitment variables to integer is UC = 1
        for y in DAC_COMMIT
		    if setup["UCommit"] == 1
			    set_integer.(vCOMMIT_DAC[y,:])
			    set_integer.(vSTART_DAC[y,:])
			    set_integer.(vSHUT_DAC[y,:])
			    set_integer.(EP[:vCAP_DAC][y]/sum(omega[t] for t in 1:T))
		    end
	    end

        @constraints(EP, begin
		    [y in DAC_COMMIT, t=1:T], vCOMMIT_DAC[y,t] <= (EP[:vCAP_DAC][y]) / dfDac[y,:Cap_Size]  #number of dac plants committed
		    [y in DAC_COMMIT, t=1:T], vSTART_DAC[y,t] <= (EP[:vCAP_DAC][y]) / dfDac[y,:Cap_Size]
		    [y in DAC_COMMIT, t=1:T], vSHUT_DAC[y,t] <= (EP[:vCAP_DAC][y]) / dfDac[y,:Cap_Size]
	    end)

        #max
        @constraints(EP, begin
        # Minimum negative CO2 per DAC "y" at hour "t" > Min stable CO2 capture
            [y in DAC_COMMIT, t=1:T], EP[:vCO2_DAC][y,t] >= dfDac[y,:Min_DAC]*EP[:vCOMMIT_DAC][y,t]*(dfDac[y,:Cap_Size]/(dfDac[y, :CF]*sum(omega[t] for t in 1:T)))

        # Maximum negative CO2 per DAC "y"  "y" at hour "t" < Max capacity per hour
            [y in DAC_COMMIT, t=1:T], EP[:vCO2_DAC][y,t] <= (dfDac[y,:Cap_Size]/(dfDac[y, :CF]*sum(omega[t] for t in 1:T))) *EP[:vCOMMIT_DAC][y,t]

         end)


        	# Commitment state constraint linking startup and shutdown decisions (Constraint #4)
	    p = hours_per_subperiod
        @constraints(EP, begin
            [y in DAC_ID, t in 1:T], vCOMMIT_DAC[y,t] == vCOMMIT_DAC[y, hoursbefore(p, t, 1)] + vSTART_DAC[y,t] - vSHUT_DAC[y,t]
        end)

        	### Minimum up and down times (Constraints #9-10)
        
	    Up_Time = zeros(Int, nrow(dfDac))
	    Up_Time[DAC_COMMIT] .= Int.(floor.(dfDac[DAC_COMMIT,:Up_Time]))
	    @constraint(EP, [y in DAC_COMMIT, t in 1:T],
	    	EP[:vCOMMIT_DAC][y,t] >= sum(EP[:vSTART_DAC][y, hoursbefore(p, t, 0:(Up_Time[y] - 1))])  #minimum number of plants online are those that were online uptime hours before
	    )

	    Down_Time = zeros(Int, nrow(dfDac))
	    Down_Time[DAC_COMMIT] .= Int.(floor.(dfDac[DAC_COMMIT,:Down_Time]))
	    @constraint(EP, [y in DAC_COMMIT, t in 1:T],
        EP[:vCAP_DAC][y]/dfDac[y,:Cap_Size] - EP[:vCOMMIT_DAC][y,t] >= sum(EP[:vSHUT_DAC][y, hoursbefore(p, t, 0:(Down_Time[y] - 1))])  #minimum number of plants offline are those that were offline downtime hours before
	    )
    end

    #max annual capacity constraint for DAC
    # Constraint on maximum annual DAC removal (if applicable) [set input to -1 if no constraint on maximum capacity]
	# DEV NOTE: This constraint may be violated in some cases where Existing_Cap_MW is >= Max_Cap_MW and lead to infeasabilty
    @expression(EP, DAC_removals_hourly[y = 1:G_DAC], sum(vCO2_DAC[y, t] for t in 1:T))
    #@constraint(EP, cDAC_removal, sum(DAC_removals_hourly[y] for y in 1:G_DAC) ==  sum(dfDac[y, :Deployment] for y in 1:G_DAC))

    @constraint(EP, cDAC_CF, sum(DAC_removals_hourly[y] for y in 1:G_DAC) ==  sum(vCAP_DAC[y] * dfDac[y, :CF]  for y in 1:G_DAC))

    @constraint(EP, cDACRemoval, sum(DAC_removals_hourly[y] for y in 1:G_DAC) >=  sum(dfDac[y, :Deployment] for y in 1:G_DAC))

    #@constraint(EP, cDAC, sum(vCAP_DAC[y] for y in 1:G_DAC) >=  sum(dfDac[y, :Deployment] for y in 1:G_DAC))

    # get the CO2 balance 
    # the net negative CO2 for each DAC y at each hour t, CO2 emissions from heat consumption minus CO2 captured by DAC = net negative emissions
    @expression(EP, eCO2_DAC_net[y in DAC_ID, t = 1:T], (eDAC_heat_CO2[y,t] - vCO2_DAC[y,t]) )  
    # the net negative CO2 from all the DAC facilities
    @expression(EP, eCO2_DAC_net_ByZoneT[z = 1:Z, t = 1:T], 
        sum(eCO2_DAC_net[y, t] for y in dfDac[(dfDac[!, :Zone].==z), :DAC_ID]))  
    # the net negative CO2 from all DAC facilities during the whole year
    @expression(EP, eCO2_DAC_net_ByZone[z = 1:Z], 
        sum(eCO2_DAC_net_ByZoneT[z, t] for t in 1:T))
    # sum of net CO2 across all the zone
    @expression(EP, eCO2_ToT_DAC_net, sum(eCO2_DAC_net_ByZone[z] for z in 1:Z))


    # separately account for the amount of CO2 that is captured.
    # actually the eCO2_net should be the total sequestration carbon. since eCO2_DAC_net should be a negative value, put minus sign in front of it..
    # costs associated with co2 transport & storage ($/(t CO2/h)) = captured co2 (t CO2/h) * Co2 transport and storage cost ($/t CO2)
    @expression(EP, eCCO2_TS_ByPlant[y in DAC_ID, t = 1:T], vCO2_DAC[y, t]* dfDac[y, :CO2_Transport_Storage_Per_t]* omega[t])
    # the sequestrated CO2 from all DAC facilities 
    @expression(EP, eCCO2_TS_ByZoneT[z = 1:Z, t = 1:T], 
        sum(eCCO2_TS_ByPlant[y, t] for y in dfDac[(dfDac[!, :Zone].==z), :DAC_ID]))    
    # the sequestrated CO2 from all DAC facilities during the whole year ($/t CO2)
    @expression(EP, eCCO2_TS_ByZone[z = 1:Z], 
        sum(eCCO2_TS_ByZoneT[z, t] for t in 1:T))
    # sum of CO2 sequestration costs.
    @expression(EP, eCTotalCO2TS, sum(eCCO2_TS_ByZone[z] for z in 1:Z))


    EP[:eObj] += eCTotalCO2TS

    @expression(EP, eDACcostTOTAL, eCTotalVariableDAC + eTotalCFixedDAC + eTotalCFixedDAC_Energy + eCTotalCO2TS)

    return EP
end