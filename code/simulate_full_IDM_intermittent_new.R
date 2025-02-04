#' Markkula Intelligent Driver Model.
#'
#' @param df A dataframe with lead vehicle and following vehicle information.
#' @param Tg Time gap in IDM
#' @param A Max. acceleration in IDM. 
#' @param b Comfortable deceleration in IDM.
#' @param v_0 Desired speed in free-driving in IDM.
#' @param small_delta Exponent in IDM.
#' @param s_0 Standstill spacing in IDM.
#' @param response_gain K in Markkula model.
#' @param accumulator_gain k in Accumulator model.
#' @param A_plus Threshold of positive activation.
#' @param A_minus Threshold of negative activation.
#' @param lambda Controls the amount of leakage in evidence.
#' @param epsilon_0 Minimum gating below which accumulation does not start.
#' @param tau_s Delay at perceptual stage.
#' @param tau_m Delay at motor stage.
#' @param sigma_n Standard deviation in Gaussian noise in Accumulator model.
#' @param sigma_m Standard debviation in Gaussian noise due to imperfect motor control.
#' @param G_Duration Delta T parameter in the shape of control adjustment.
#' @param G_StdDev Standard deviation in the shape of control adjustment. 
#' @param H_Time_error_starts_disappearing Delta Tp0 in the shape of predicted control error.
#' @param H_Time_error_disappeared Delta Tp1 in the shape of predicted control error.
#' @param H_error_pred_sd_to_include Standard deviation in the shape of predicted control error.
#'
#' @return A tibble with simulation results.
simulate_full_IDM_intermittent_new <- function(df,
                                               Tg,
                                               A,
                                               b,
                                               v_0,
                                               small_delta,
                                               s_0,
                                               response_gain,
                                               accumulator_gain,
                                               A_plus,
                                               A_minus,
                                               lambda,
                                               epsilon_0,
                                               tau_s,
                                               tau_m,
                                               sigma_n,
                                               sigma_m,
                                               G_Duration,
                                               G_StdDev,
                                               H_Time_error_starts_disappearing,
                                               H_Time_error_disappeared,
                                               H_error_pred_sd_to_include) {
  # Create empty lists---------------------
  SControlModelStates <- list()
  SControlModelParameters <- list()


  # simulation settings--------------------------
  vx <- head(df$ED_speed_mps, 1)
  c_startTime <- head(df$Time, 1)
  c_timeStep <- df$Time[2] - df$Time[1]
  c_endTime <- tail(df$Time, 1)
  VTimeStamp <- seq(c_startTime, c_endTime, by = c_timeStep)
  nSamples <- length(VTimeStamp)



  # Lead Vehicle Data------------------------
  c_povWidth <- unique(df$LV_width_m)
  c_povWidth <- c_povWidth[!is.na(c_povWidth)]
  c_povLength <- unique(df$LV_length_m)
  c_povLength <- c_povLength[!is.na(c_povLength)]
  povPosition <- df$LV_position_m_new
  povSpeed <- df$LV_speed_mps
  povAcceleration <- df$LV_acc_mps2_lag



  # Calibration parameters-------------------------
  ## Free-driving

  Tg <- Tg
  A <- A
  b <- b
  v_0 <- v_0
  small_delta <- small_delta



  ## response gain
  SControlModelParameters[["K"]] <- response_gain

  ## accumulator gain
  SControlModelParameters[["k"]] <- accumulator_gain

  ## thresholds
  SControlModelParameters[["Apthreshold"]] <- A_plus
  SControlModelParameters[["Anthreshold"]] <- A_minus

  ## leakage
  SControlModelParameters[["lambda"]] <- lambda

  ## noise
  SControlModelParameters[["sigma_n"]] <- sigma_n
  SControlModelParameters[["sigma_m"]] <- sigma_m

  ## gating
  SControlModelParameters[["epsilon_0"]] <- epsilon_0

  ## continuous model parameter
  SControlModelParameters[["bThresholdModel"]] <- FALSE

  ## delays
  SControlModelParameters[["tau_s"]] <- tau_s
  SControlModelParameters[["tau_m"]] <- tau_m

  ## first value of control 'C' CHANGE
  SControlModelParameters[["C_0"]] <- df$ED_acc_mps2_lag[1]

  ## delta min
  SControlModelParameters[["Delta_min"]] <- 0




  # store delays as number of samples------------------
  SControlModelParameters[["nSensoryDelaySamples"]] <- pracma::ceil(SControlModelParameters[["tau_s"]] / c_timeStep)
  SControlModelParameters[["nMotorDelaySamples"]] <- pracma::ceil(SControlModelParameters[["tau_m"]] / c_timeStep)


  # c_inputDelay <- 0.0
  # c_nInputDelaySamples <- max(1, pracma::ceil(c_inputDelay / c_timeStep))


  # G(t) parameters---------------------
  c_GDuration <- G_Duration
  c_GStdDev <- G_StdDev


  # H(t) parameters----------------------
  ## - how long after brake adjustment decision do we expect the prediction error to start disappearing
  c_errorStartsDisappearingTime <- H_Time_error_starts_disappearing # delta Tp0
  ## - ... and when do we expect it to have disappeared
  c_errorDisappearedTime <- H_Time_error_disappeared # delta Tp1
  ## - also the error prediction function is constructed from a truncated Gaussian
  c_errorPredictionStdDevsToInclude <- H_error_pred_sd_to_include

  # Empty vectors-----------------------------------------
  # oveRequestedAcceleration = rep(0, nSamples)
  oveJerk <- rep(0, nSamples)
  oveAcceleration <- rep(0, nSamples)
  oveAcceleration[1] <- df$ED_acc_mps2_lag[1]

  oveSpeed <- rep(0, nSamples)
  oveSpeed[1] <- vx
  ovePosition <- df$ED_position_m_new


  headwayDistance <- rep(0, nSamples)
  headwayDistance[1] <- df$LV_frspacing_m[1]
  relativeSpeed <- rep(0, nSamples)
  relativeSpeed[1] <- df$LV_speed_mps[1] - df$ED_speed_mps[1]

  povOpticalSize <- rep(0, nSamples)
  povOpticalSize[1] <- 2 * atan(c_povWidth / (2 * headwayDistance[1]))
  povOpticalExpansion <- rep(0, nSamples)
  povOpticalExpansion[1] <- -4 * c_povWidth * relativeSpeed[1] / (4 * headwayDistance[1]^2 + c_povWidth^2)
  povInverseTau <- rep(0, nSamples)
  povInverseTau[1] <- povOpticalExpansion[1] / povOpticalSize[1]



  sn_star <- rep(0, nSamples)
  sn_star_second_part <- rep(0, nSamples)
  sn_star_second_part[1] <- Tg * oveSpeed[1]

  sn_star_third_part <- rep(0, nSamples)
  sn_star_third_part[1] <- ((-relativeSpeed[1]) * oveSpeed[1]) / (2 * sqrt(A * b))

  sn_star[1] <- s_0 + max(0, (sn_star_second_part[1] + sn_star_third_part[1]))


  bn <- rep(0, nSamples)
  bn_second_part <- rep(0, nSamples)
  bn_second_part[1] <- ((oveSpeed[1] / v_0)^small_delta)
  bn_third_part <- rep(0, nSamples)
  bn_third_part[1] <- ((sn_star[1] / headwayDistance[1])^2)
  bn[1] <- A * (1 - bn_second_part[1] - bn_third_part[1])


  # Calculate G and H:

  ## function for burst rate
  GetTruncatedGaussianBurstRate <- function(VTimeStamp,
                                            burstCenterTime,
                                            burstDuration,
                                            nBurstGaussianStdDevs) {
    gaussianStdDev <- (burstDuration / 2) / nBurstGaussianStdDevs
    VBurstRate <- dnorm(VTimeStamp, burstCenterTime, gaussianStdDev)
    gaussianValueAtTruncationCutoff <- dnorm(-burstDuration / 2, 0, gaussianStdDev)
    VBurstRate <- VBurstRate - gaussianValueAtTruncationCutoff
    VBurstRate[VBurstRate < 0] <- 0
    areaOfTruncatedGaussian <- pracma::trapz(VTimeStamp, VBurstRate)
    VBurstRate <- VBurstRate / areaOfTruncatedGaussian
  }


  c_nGStdDevsOnEachSide <- (c_GDuration / 2) / c_GStdDev
  c_VGTimeStamp <- seq(0, c_GDuration, c_timeStep) # 0:c_timeStep:c_GDuration;
  SControlModelParameters[["VGdot"]] <- GetTruncatedGaussianBurstRate(
    c_VGTimeStamp,
    c_GDuration / 2,
    c_GDuration,
    c_nGStdDevsOnEachSide
  )
  c_VGdot <- cumsum(SControlModelParameters[["VGdot"]] * c_timeStep)
  SControlModelParameters[["VG"]] <- c_VGdot



  # -- error prediction (H)
  # - how long after brake adjustment decision do we expect the prediction error to start disappearing
  ## function definition
  GetErrorPredictionFunction <- function(t,
                                         errorStartsDisappearingTime,
                                         errorDisappearedTime,
                                         errorPredictionStdDevsToInclude) {
    errorDisappearanceRateFunction <- dnorm(
      x = t,
      mean = mean(c(errorStartsDisappearingTime, errorDisappearedTime)),
      sd = (errorDisappearedTime - errorStartsDisappearingTime) / (2 * errorPredictionStdDevsToInclude)
    )

    errorDisappearanceRateFunction <- errorDisappearanceRateFunction - errorDisappearanceRateFunction[head(which(t >= errorStartsDisappearingTime), 1)]

    errorDisappearanceRateFunction[errorDisappearanceRateFunction < 0] <- 0

    errorDisappearanceRateFunction <- errorDisappearanceRateFunction / pracma::trapz(t, errorDisappearanceRateFunction)

    # errorDisappearanceRateFunction
    VErrorPredictionFunction <- 1 - pracma::cumtrapz(t, errorDisappearanceRateFunction)
    VErrorPredictionFunction
  }


  tt <- seq(0, (c_errorStartsDisappearingTime + c_errorDisappearedTime), 0.1)

  c_errorPredictionFunction <- GetErrorPredictionFunction(
    tt, # VTimeStamp,
    c_errorStartsDisappearingTime,
    c_errorDisappearedTime,
    c_errorPredictionStdDevsToInclude
  )

  c_errorPredictionFunction <- as.vector(t(c_errorPredictionFunction))


  c_errorPredictionFunction[1] <- 0

  SControlModelParameters[["VH"]] <- c_errorPredictionFunction

  timeStampAtLastAdjustment <- NaN
  nAdjustments <- 0

  set.seed(0)

  # For-loop
  for (i in 1:nSamples) {
    if (i == 1) {
      # initialise internal model states
      SControlModelStates[["VA"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VC"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VCdot_undelayed"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VCdot"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VP_undelayed"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VP"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["VP_p"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["Vepsilon"]] <- rep(0, length(VTimeStamp))
      SControlModelStates[["nAdjustments"]] <- 0
      SControlModelStates[["ViAdjustmentOnsetSamples"]] <- vector(mode = "integer")
      SControlModelStates[["Vt_i"]] <- vector(mode = "double")
      SControlModelStates[["Vepsilon_i"]] <- vector(mode = "double")
      SControlModelStates[["Vepsilontilde_i"]] <- vector(mode = "double")
      SControlModelStates[["Vg_i"]] <- vector(mode = "double")
      SControlModelStates[["Vgtilde_i"]] <- vector(mode = "double")


      perceptualControlError <- 0



      # just set initial control value
      SControlModelStates[["VP_undelayed"]][1] <- perceptualControlError
      SControlModelStates[["VC"]][1] <- SControlModelParameters[["C_0"]]
    } else {
      oveSpeed[i] <- max(0, oveSpeed[i - 1] + c_timeStep * oveAcceleration[i - 1])

      if (oveSpeed[i] > v_0) {
        oveSpeed[i] <- v_0
      }

      ovePosition[i] <- ovePosition[i - 1] + c_timeStep * oveSpeed[i - 1]


      # driver model
      headwayDistance[i] <- povPosition[i] - ovePosition[i] - c_povLength
      relativeSpeed[i] <- povSpeed[i] - oveSpeed[i]



      if (is.na(headwayDistance[i]) == TRUE) {
        oveAcceleration[i] <- A * (1 - ((oveSpeed[i] / v_0)^small_delta))



        if (oveAcceleration[i] > 4) {
          oveAcceleration[i] <- 4
        } else if (oveAcceleration[i] < -10) {
          oveAcceleration[i] <- -10
        }

        oveJerk[i] <- (oveAcceleration[i] - oveAcceleration[i - 1]) / 0.1
      } else {
        # get perceptual control error
        povOpticalSize[i] <- 2 * atan(c_povWidth / (2 * headwayDistance[i]))

        povOpticalExpansion[i] <- -4 * c_povWidth * relativeSpeed[i] / (4 * headwayDistance[i]^2 + c_povWidth^2)
        povInverseTau[i] <- povOpticalExpansion[i] / povOpticalSize[i]


        sn_star_second_part[i] <- Tg * oveSpeed[i]


        sn_star_third_part[i] <- ((-relativeSpeed[i]) * oveSpeed[i]) / (2 * sqrt(A * b))

        sn_star[i] <- s_0 + max(0, (sn_star_second_part[i] + sn_star_third_part[i]))




        bn_second_part[i] <- ((oveSpeed[i] / v_0)^small_delta)

        bn_third_part[i] <- ((sn_star[i] / headwayDistance[i])^2)

        bn[i] <- A * (1 - bn_second_part[i] - bn_third_part[i])


        perceptualControlError <- (bn[i] - oveAcceleration[i - 1])


        # do control model update
        res <- DoControlModelTimeStep_new(
          VTimeStamp, c_timeStep, i,
          perceptualControlError, SControlModelParameters,
          SControlModelStates
        )


        oveJerk[i] <- res[["controlRate"]]



        if (is.na(headwayDistance[i]) == TRUE | SControlModelStates[["nAdjustments"]] == 0) {
          oveAcceleration[i] <- A * (1 - ((oveSpeed[i] / v_0)^small_delta))
        } else {
          oveAcceleration[i] <- res[["control"]]
        }


        if (oveAcceleration[i] > 4) {
          oveAcceleration[i] <- 4
        } else if (oveAcceleration[i] < (-10)) {
          oveAcceleration[i] <- (-10)
        }


        SControlModelParameters <- res[["SParameters"]]
        SControlModelStates <- res[["SControlModelStates"]]
      }
    }
  }


  final_table <- tibble::tibble(
    Time = VTimeStamp,
    # Speed
    LV_speed_mps = df$LV_speed_mps,
    ED_speed_mps = df$ED_speed_mps,
    ED_pred_speed_mps = oveSpeed,

    # Acceleration
    LV_acc_mps2 = povAcceleration,
    ED_acc_mps2 = df$ED_acc_mps2_lag,
    sn_star_second_part,
    sn_star_third_part,
    sn_star,
    bn_second_part,
    bn_third_part,
    bn,
    povInverseTau,
    ED_pred_acc_mps2 = oveAcceleration,

    # Spacing
    LV_length_m = c_povLength,
    LV_width_m = c_povWidth,
    LV_spacing_m = df$LV_spacing_m,
    LV_frspacing_m = df$LV_frspacing_m,
    LV_pred_frspacing_m = headwayDistance,

    # Jerk
    ED_jerk_mps3_lag = df$ED_jerk_mps3_lag,
    ED_pred_jerk_mps3 = oveJerk,


    # Model calculations
    VP = SControlModelStates[["VP"]],
    VP_p = SControlModelStates[["VP_p"]],
    Vepsilon = SControlModelStates[["Vepsilon"]],
    VA = SControlModelStates[["VA"]],
    VC = SControlModelStates[["VC"]],
    VCdot = SControlModelStates[["VCdot"]],
    SControlModelStates = list(SControlModelStates),
    SControlModelParameters = list(SControlModelParameters)
  )


  final_table
}