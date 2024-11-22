function speed_limits!(EP::Model, inputs::Dict, setup::Dict)
    println("Speed Limits Module")

    gen = inputs["RESOURCES"]

    T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones
    G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)

    VRE = inputs["VRE"]
    STOR_ALL = inputs["STOR_ALL"]
    THERM_ALL = inputs["THERM_ALL"]
    NEW_CAP = inputs["NEW_CAP"] # Set of all resources eligible for new capacity
    RET_CAP = inputs["RET_CAP"] # Set of all resources eligible for capacity retirements

    speedlimits = inputs["Speed_Limits"]

    vre_new = intersect(VRE, NEW_CAP)
    
    # new capacity variable is less than new capacity specified..
    @constraint(EP, cNewCapSpeedLimits, sum(EP[:vCAP][y] for y in vre_new).<= speedlimits[1,:Limit])    # sum of vre should be less than max capacity addition it can ramp up to 
    #@constraint(EP, cNewCapSpeedLimits[y in vre_new], EP[:vCAP][y].>= speedlimits[y, :Min])    # min capacity addition it can ramp down to - this prevents sudden drop off with subsidy fallout
end