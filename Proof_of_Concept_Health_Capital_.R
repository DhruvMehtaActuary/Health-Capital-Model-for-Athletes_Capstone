###############################################################
# Health Capital Model for Athletes
# Version 0.1
# Author: Dhruv Mehta
#
# Independent Research Project
# A simplified stochastic framework for modelling athlete
# health, workload, recovery and injury risk.
###############################################################

# ==========================
# Load Libraries
# ==========================

library(ggplot2)
library(dplyr)
library(reticulate)

# ==========================
# Python Integration
# ==========================

# Small demonstration of Python usage within R
py_run_string("
import numpy as np

def calculate_mean(x):
    return float(np.mean(x))

def calculate_std(x):
    return float(np.std(x))
")

# ==========================
# Simulation Parameters
# ==========================

days <- 365

set.seed(123)

# ==========================
# Athlete Information
# ==========================

athlete <- list(
  
  Name = "Sample Athlete",
  
  Age = 24,
  
  Position = "All-Rounder"
  
)

# ==========================
# Initial Health State
# ==========================

health <- 90

structural_integrity <- 95

fatigue <- 15

recovery_capacity <- 90

micro_damage <- 5

availability <- 100

# ==========================
# Create Storage Vectors
# ==========================

Health <- numeric(days)

Integrity <- numeric(days)

Fatigue <- numeric(days)

Recovery <- numeric(days)

MicroDamage <- numeric(days)

InjuryRisk <- numeric(days)

Availability <- numeric(days)

TrainingLoad <- numeric(days)

# ==========================
# Simulation Begins
# ==========================

for(day in 1:days){
  
  ##############################################
  # Daily Training Load
  ##############################################
  
  load <- round(runif(1,40,100),1)
  
  TrainingLoad[day] <- load
  
  ##############################################
  # Fatigue Update
  ##############################################
  
  fatigue <- fatigue + load*0.07
  
  fatigue <- fatigue - recovery_capacity*0.04
  
  fatigue <- max(0,min(100,fatigue))
  
  ##############################################
  # Recovery Capacity
  ##############################################
  
  recovery_capacity <- recovery_capacity -
    
    load*0.015 +
    
    runif(1,-0.5,0.8)
  
  recovery_capacity <- max(40,
                           
                           min(100,
                               
                               recovery_capacity))
  
  ##############################################
  # Structural Integrity
  ##############################################
  
  structural_integrity <-
    
    structural_integrity -
    
    load*0.020 +
    
    recovery_capacity*0.010
  
  structural_integrity <-
    
    max(0,
        
        min(100,
            
            structural_integrity))
  
  ##############################################
  # Micro Damage
  ##############################################
  
  micro_damage <-
    
    micro_damage +
    
    load*0.025 -
    
    recovery_capacity*0.012
  
  micro_damage <-
    
    max(0,
        
        min(100,
            
            micro_damage))
  
  ##############################################
  # Health Capital Score
  ##############################################
  
  health <-
    
    0.40*structural_integrity +
    
    0.30*recovery_capacity +
    
    0.20*(100-fatigue) +
    
    0.10*(100-micro_damage)
  
  ##############################################
  # Injury Probability
  ##############################################
  
  injury_probability <-
    
    0.02 +
    
    fatigue*0.002 +
    
    micro_damage*0.002 -
    
    recovery_capacity*0.0015
  
  injury_probability <-
    
    max(0.01,
        
        min(0.95,
            
            injury_probability))
  
  ##############################################
  # Random Injury Event
  ##############################################
  
  injury <- rbinom(1,1,injury_probability)
  
  if(injury==1){
    
    structural_integrity <-
      
      structural_integrity -
      
      runif(1,5,15)
    
    fatigue <-
      
      fatigue +
      
      runif(1,8,18)
    
    recovery_capacity <-
      
      recovery_capacity -
      
      runif(1,5,12)
    
    micro_damage <-
      
      micro_damage +
      
      runif(1,8,20)
    
  }
  
  ##############################################
  # Availability
  ##############################################
  
  availability <-
    
    max(0,
        
        min(100,
            
            health -
              
              injury_probability*100))
  
  ##############################################
  # Store Results
  ##############################################
  
  Health[day] <- health
  
  Integrity[day] <- structural_integrity
  
  Fatigue[day] <- fatigue
  
  Recovery[day] <- recovery_capacity
  
  MicroDamage[day] <- micro_damage
  
  InjuryRisk[day] <- injury_probability*100
  
  Availability[day] <- availability
  
}

####################################################
# Results Data Frame
####################################################

results <- data.frame(
  
  Day = 1:days,
  
  TrainingLoad,
  
  Health,
  
  Integrity,
  
  Fatigue,
  
  Recovery,
  
  MicroDamage,
  
  InjuryRisk,
  
  Availability
  
)

####################################################
# Python Summary Statistics
####################################################

py$health_values <- Health

average_health <-
  
  py$calculate_mean(py$health_values)

standard_deviation <-
  
  py$calculate_std(py$health_values)

####################################################
# Display Summary
####################################################

cat("====================================\n")

cat("Health Capital Simulation Complete\n")

cat("====================================\n\n")

cat("Athlete :",athlete$Name,"\n")

cat("Simulation Length :",days,"days\n\n")

cat("Average Health Capital :",
    
    round(average_health,2),"\n")

cat("Health Standard Deviation :",
    
    round(standard_deviation,2),"\n")

cat("Average Injury Risk :",
    
    round(mean(InjuryRisk),2),"%\n")

cat("Average Availability :",
    
    round(mean(Availability),2),"%\n")

####################################################
# Export CSV
####################################################

write.csv(
  
  results,
  
  "Health_Capital_Simulation.csv",
  
  row.names=FALSE
  
)

####################################################
# Plot 1
####################################################

ggplot(results,
       
       aes(Day,Health))+
  
  geom_line(color="blue")+
  
  labs(title="Health Capital Over Time")

####################################################
# Plot 2
####################################################

ggplot(results,
       
       aes(Day,Fatigue))+
  
  geom_line(color="red")+
  
  labs(title="Fatigue Over Time")

####################################################
# Plot 3
####################################################

ggplot(results,
       
       aes(Day,InjuryRisk))+
  
  geom_line(color="darkorange")+
  
  labs(title="Injury Risk (%)")

####################################################
# Plot 4
####################################################

ggplot(results,
       
       aes(Day,Availability))+
  
  geom_line(color="darkgreen")+
  
  labs(title="Athlete Availability")

####################################################
# End
####################################################