# This function is based on the MATLAB code (DoControlModelTimeStep.m) 
# by Gustav Markkula, found here: https://osf.io/4du3k
# For more details about the logic and application of the original
# code, visit this page: https://gmarkkula.github.io/posts/2018-biolcyb-model/

# The original license (reproduced below) is also applicable to this code.

# Copyright 2018 Gustav Markkula
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the
# following conditions:
  #
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#' Update the state of the intermittent control framework
#'
#' @param VTimeStamp A vector of time stamps on which the simulation is run.
#' @param timeStep Time step e.g., 0.1 s.
#' @param iSample ith step.
#' @param perceptualControlError Perceptual control error.
#' @param SParameters List of model parameters.
#' @param SControlModelStates List of control model states.
#'
#' @return List of control, control rate, model parameters, and control model states.
DoControlModelTimeStep_new <- function(VTimeStamp, 
                                       timeStep, 
                                       iSample, 
                                       perceptualControlError,
                                       SParameters,
                                       SControlModelStates){
  
  
  # store undelayed perceptual control error
  SControlModelStates[['VP_undelayed']][iSample] <- perceptualControlError
  
  # get delayed perceptual control error
  if (iSample > SParameters[['nSensoryDelaySamples']]){
    SControlModelStates[['VP']][iSample] <- SControlModelStates[['VP_undelayed']][(iSample - SParameters[['nSensoryDelaySamples']])]
  }
  
  # update epsilon
  SControlModelStates[['Vepsilon']][iSample] <- SControlModelStates[['VP']][iSample] - SControlModelStates[['VP_p']][iSample]
  
  if (SParameters[['bThresholdModel']] == TRUE){
    # set accumulator to epsilon + a random noise term
    SControlModelStates[['VA']][iSample] <- SControlModelStates[['Vepsilon']][iSample] + rnorm(1) * SParameters[['sigma_n']]
  } else {
    
    # gating function
    gammaGatingFcn <- function(epsilon, epsilon_0){
      
      gamma = sign(epsilon) * max(0, abs(epsilon) - epsilon_0)
      gamma
    }
    
    # do accumulator update
    accumulatorChange <- (gammaGatingFcn(SParameters[['k']] * SControlModelStates[['Vepsilon']][iSample], SParameters[['epsilon_0']]) - SParameters[['lambda']] * SControlModelStates[['VA']][iSample-1]) * timeStep + (rnorm(1) * SParameters[['sigma_n']] * sqrt(timeStep))
    SControlModelStates[['VA']][iSample] <- SControlModelStates[['VA']][iSample-1] + accumulatorChange
  }
  # print(SControlModelStates[['VA']][iSample])
  # get elapsed time since last adjustment
  if (SControlModelStates[['nAdjustments']] > 0){
    timeSinceLastAdjustmentOnset <- VTimeStamp[iSample] -  SControlModelStates[['Vt_i']][SControlModelStates[['nAdjustments']]]
  } else {
    timeSinceLastAdjustmentOnset <- Inf
  }
  
  # new adjustment?
  if ((SControlModelStates[['VA']][iSample] >= SParameters[['Apthreshold']] &   timeSinceLastAdjustmentOnset >= SParameters[['Delta_min']]) | (SControlModelStates[['VA']][iSample] <= SParameters[['Anthreshold']] &   timeSinceLastAdjustmentOnset >= SParameters[['Delta_min']])){
    
    # reset accumulator
    SControlModelStates[['VA']][iSample] <- 0
    
    # some basic housekeeping
    SControlModelStates[['nAdjustments']] <- SControlModelStates[['nAdjustments']] + 1
    SControlModelStates[['ViAdjustmentOnsetSamples']][SControlModelStates[['nAdjustments']]] <- iSample
    SControlModelStates[['Vt_i']][SControlModelStates[['nAdjustments']]] <- VTimeStamp[iSample]
    
    # get magnitude of new adjustment, with and without motor noise
    epsilon_i <- SControlModelStates[['Vepsilon']][iSample]
    g_i <- SParameters[['K']] * epsilon_i
    epsilontilde_i <- (1 + rnorm(1) * SParameters[['sigma_m']]) * epsilon_i
    gtilde_i <- SParameters[['K']] * epsilontilde_i
    
    # store this info
    SControlModelStates[['Vepsilon_i']][SControlModelStates[['nAdjustments']]] <- epsilon_i
    SControlModelStates[['Vepsilontilde_i']][SControlModelStates[['nAdjustments']]] <- epsilontilde_i
    SControlModelStates[['Vg_i']][SControlModelStates[['nAdjustments']]] <- g_i
    SControlModelStates[['Vgtilde_i']][SControlModelStates[['nAdjustments']]] <- gtilde_i
    
    # add new control adjustment to superposition
    ViGdotRange <- iSample : min(length(VTimeStamp), iSample+length(SParameters[['VGdot']])-1)
    SControlModelStates[['VCdot_undelayed']][ViGdotRange] <- SControlModelStates[['VCdot_undelayed']][ViGdotRange] + (gtilde_i * SParameters[['VGdot']][1:length(ViGdotRange)])
    
    # add new control error prediction to superposition
    ViHRange <- iSample : min(length(VTimeStamp), iSample+length(SParameters[['VH']])-1)
    SControlModelStates[['VP_p']][ViHRange] <- SControlModelStates[['VP_p']][ViHRange] +      epsilontilde_i * SParameters[['VH']][1:length(ViHRange)]
    
  } # if accumulator reached threshold
  
  # get delayed control rate
  if (iSample > SParameters[['nMotorDelaySamples']]){
    SControlModelStates[['VCdot']][iSample] <- SControlModelStates[['VCdot_undelayed']][iSample - SParameters[['nMotorDelaySamples']]]
  }
  
  # get control
  SControlModelStates[['VC']][iSample] <- SControlModelStates[['VC']][iSample-1] + (SControlModelStates[['VCdot']][iSample-1] * timeStep)
  
  
  # return control information for this time step
  control <- SControlModelStates[['VC']][iSample]
  controlRate <- SControlModelStates[['VCdot']][iSample]
  
  
  res <- list('control' = control,
              'controlRate' = controlRate,
              'SParameters' = SParameters,
              'SControlModelStates' = SControlModelStates)
  
  res
}


