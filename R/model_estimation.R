# POMP v6-compatible state-space estimator.
#
# This implementation deliberately uses R model functions rather than C snippets.
# It is slower than compiled code, but avoids toolchain-dependent compilation and
# is consequently reliable on a standard RStudio installation on Windows.

hcf_standardize <- function(x) {
  x <- as.numeric(x)
  s <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-8) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

fill_optional_inputs <- function(d, cfg = hcf_config()) {
  defaults <- cfg$default_optional
  names_needed <- c("high_intensity_distance", "sprint_count", "bowling_speed",
                    "session_rpe", "muscle_soreness", "recovery_score", "rest_days", "z_team")
  for (name in names_needed) {
    if (!name %in% names(d)) d[[name]] <- NA_real_
    value <- defaults[[name]] %||% 0
    d[[name]][is.na(d[[name]])] <- value
  }
  required <- c("training_minutes", "match_minutes", "overs_bowled", "sleep_hours", "wellness_score", "age", "prior_injury")
  if (any(!required %in% names(d)) || any(vapply(d[required], function(x) any(is.na(x)), logical(1)))) {
    stop("Missing compulsory player-day inputs. Training, match minutes, overs, sleep, wellness, age, and prior-injury history are required.")
  }
  d$injury_event <- as.integer(d$injury_event %||% 0)
  d$injury_event[is.na(d$injury_event)] <- 0L
  d
}

construct_forcing <- function(d, cfg = hcf_config()) {
  d <- fill_optional_inputs(d, cfg)
  fixed_index <- function(fields, means, sds, weights, reverse = character()) {
    z <- vapply(fields, function(field) (as.numeric(d[[field]]) - means[[field]]) / sds[[field]], numeric(nrow(d)))
    if (length(reverse)) z[, reverse] <- -z[, reverse, drop = FALSE]
    as.numeric(z %*% weights[fields])
  }
  workload_index <- fixed_index(names(cfg$workload_weights), cfg$workload_means, cfg$workload_sds, cfg$workload_weights)
  recovery_index <- fixed_index(names(cfg$recovery_weights), cfg$recovery_means, cfg$recovery_sds, cfg$recovery_weights, reverse = "muscle_soreness")
  data.frame(w = pmax(0, cfg$workload_base + cfg$workload_scale * workload_index),
    r = pmax(0, cfg$recovery_base + cfg$recovery_scale * recovery_index), zteam = as.numeric(d$z_team))
}

pomp_params <- function(cfg = hcf_config()) {
  c(kF=cfg$kappa_F, kR=cfg$kappa_R, kS=cfg$kappa_S,
    aF=cfg$alpha_F, aR=cfg$alpha_R, bR=cfg$beta_R,
    gD=cfg$gamma_D, dD=cfg$delta_D, lS=cfg$lambda_S,
    sF=cfg$sigma_F, sR=cfg$sigma_R, sS=cfg$sigma_S,
    jump0=cfg$jump_lambda_0, jumpw=cfg$jump_lambda_workload,
    jumpt=cfg$jump_lambda_team, jumpmean=cfg$jump_mean,
    Sbar=cfg$baseline_S, Rbar=cfg$baseline_R,
    inj0=cfg$injury_lambda_0, tS=cfg$theta_S, tF=cfg$theta_F,
    tR=cfg$theta_R, tD=cfg$theta_D, tAge=cfg$theta_age, tHist=cfg$theta_hist)
}

make_pomp_model <- function(player_panel, cfg = hcf_config()) {
  if (!requireNamespace("pomp", quietly = TRUE)) {
    stop("The pomp package is not installed. Run source('scripts/install_packages.R') first.")
  }
  d <- as.data.frame(player_panel)
  d <- d[order(as.Date(d$date)), , drop = FALSE]
  d <- fill_optional_inputs(d, cfg)
  forcing <- construct_forcing(d, cfg)
  n <- nrow(d)
  covariates <- data.frame(
    time = 0:n,
    w = c(forcing$w[1], forcing$w),
    r = c(forcing$r[1], forcing$r),
    zteam = c(forcing$zteam[1], forcing$zteam),
    age = c(d$age[1], d$age),
    prior = c(d$prior_injury[1], d$prior_injury)
  )

  rinit <- function(...) c(S = rnorm(1, 0, .25), F = rnorm(1, 0, .25),
                            R = rnorm(1, 0, .25), D = abs(rnorm(1, 0, .08)))

  rprocess <- function(S, F, R, D, w, r, zteam, kF, kR, kS, aF, aR, bR,
                       gD, dD, lS, sF, sR, sS, jump0, jumpw, jumpt,
                       jumpmean, Sbar, Rbar, ..., delta.t) {
    jump_count <- rpois(1, max(0, (jump0 + jumpw * w + jumpt * zteam) * delta.t))
    jump <- if (jump_count == 0) 0 else -sum(rexp(jump_count, rate = 1 / jumpmean))
    next_F <- F + (-kF * F + aF * w) * delta.t + sF * sqrt(delta.t) * rnorm(1)
    next_R <- R + (kR * (Rbar - R) + aR * r - bR * F) * delta.t + sR * sqrt(delta.t) * rnorm(1)
    next_D <- max(0, D + (gD * max(0, F - R) - dD * D) * delta.t)
    next_S <- S + (kS * (Sbar - S) - lS * D) * delta.t + sS * sqrt(delta.t) * rnorm(1) + jump
    c(S = next_S, F = next_F, R = next_R, D = next_D)
  }

  ref <- cfg$state_reference
  limit <- cfg$hazard_z_limit
  dmeasure <- function(injury_event, wellness_score, sleep_hours, muscle_soreness,
                       recovery_score, S, F, R, D, age, prior, inj0, tS, tF,
                       tR, tD, tAge, tHist, ..., log) {
    zs <- pmax(-limit, pmin(limit, -(S - ref$S["mean"]) / ref$S["sd"]))
    zf <- pmax(-limit, pmin(limit,  (F - ref$F["mean"]) / ref$F["sd"]))
    zr <- pmax(-limit, pmin(limit, -(R - ref$R["mean"]) / ref$R["sd"]))
    zd <- pmax(-limit, pmin(limit,  (D - ref$D["mean"]) / ref$D["sd"]))
    age_z <- (age - cfg$age_reference) / cfg$age_sd
    lambda <- inj0 * exp(tS * zs + tF * zf + tR * zr + tD * zd + tAge * age_z + tHist * prior)
    injury_probability <- pmin(pmax(1 - exp(-lambda), 1e-12), 1 - 1e-12)
    log_likelihood <- stats::dbinom(injury_event, 1, injury_probability, log = TRUE) +
      stats::dnorm(wellness_score, 6.5 + .4 * R - .55 * F, 1.2, log = TRUE) +
      stats::dnorm(sleep_hours, 7.5 + .4 * R - .35 * F, .65, log = TRUE) +
      stats::dnorm(muscle_soreness, 2.2 + .6 * F + .35 * D, .75, log = TRUE) +
      stats::dnorm(recovery_score, 60 + 6 * R - 7 * F, 9, log = TRUE)
    if (log) log_likelihood else exp(log_likelihood)
  }

  positive_parameters <- c("kF", "kR", "kS", "aF", "aR", "bR", "gD", "dD", "lS", "sF", "sR", "sS", "jump0", "jumpw", "jumpt", "jumpmean", "inj0")
  pomp::pomp(
    data = data.frame(time = seq_len(n), injury_event = d$injury_event,
                      wellness_score = d$wellness_score, sleep_hours = d$sleep_hours,
                      muscle_soreness = d$muscle_soreness, recovery_score = d$recovery_score),
    times = "time", t0 = 0,
    rinit = rinit,
    rprocess = pomp::discrete_time(step.fun = rprocess, delta.t = 1),
    dmeasure = dmeasure,
    covar = pomp::covariate_table(covariates, times = "time", order = "constant"),
    statenames = c("S", "F", "R", "D"),
    paramnames = names(pomp_params(cfg)),
    params = pomp_params(cfg),
    partrans = pomp::parameter_trans(log = positive_parameters)
  )
}

fit_player_pomp <- function(player_panel, cfg = hcf_config(), particles = 500,
                            mif_iterations = 10, run_mif = TRUE) {
  model <- make_pomp_model(player_panel, cfg)
  start <- pomp_params(cfg)
  if (run_mif) {
    fit <- pomp::mif2(
      model, params = start, Np = particles, Nmif = mif_iterations,
      cooling.fraction.50 = 0.5,
      rw.sd = pomp::rw_sd(kF = .02, kR = .02, kS = .01, aF = .02, aR = .02,
                           bR = .02, gD = .01, dD = .01, lS = .01, inj0 = .02,
                           tS = .02, tF = .02, tR = .02, tD = .02)
    )
    parameters <- pomp::coef(fit)
  } else {
    fit <- NULL
    parameters <- start
  }
  filter <- pomp::pfilter(model, params = parameters, Np = particles, filter.mean = TRUE)
  # Extract each state explicitly. This avoids depending on the presentation shape
  # of POMP's filter_mean(data.frame) method, which differs between POMP releases.
  state_history <- vapply(c("S", "F", "R", "D"), function(variable) {
    values <- pomp::filter_mean(filter, vars = variable, format = "array")
    as.numeric(values)
  }, numeric(nrow(player_panel)))
  state_history <- as.data.frame(state_history)
  current_state <- unlist(state_history[nrow(state_history), c("S", "F", "R", "D"), drop = FALSE], use.names = TRUE)
  filtered_states <- state_history
  filtered_states$time <- seq_len(nrow(filtered_states))
  list(model = model, fit = fit, params = parameters, pfilter = filter,
       filtered_states = filtered_states, state_history = state_history,
       current_state = current_state,
       loglik = as.numeric(pomp::logLik(filter)))
}

simulate_then_recover <- function(cfg = hcf_config(), n_players = 15, days = 200,
                                  seed = cfg$seed, particles = 500, mif_iterations = 10) {
  simulation <- simulate_season(n_players, days, cfg, seed)
  # Estimation intentionally receives observable data only. Latent columns are removed.
  observed_names <- setdiff(names(simulation$panel), c("S", "F", "R", "D", "jump", "hazard_true", "health_score_true", "severity_tier", "days_out", "w_true", "r_true"))
  observed <- simulation$panel[, observed_names, drop = FALSE]
  player <- observed[observed$player_id == simulation$profiles$player_id[1], , drop = FALSE]
  estimate <- fit_player_pomp(player, cfg, particles, mif_iterations, run_mif = TRUE)
  truth <- pomp_params(cfg)
  recovered <- estimate$params[names(truth)]
  recovery <- data.frame(parameter = names(truth), truth = unname(truth),
                         estimate = unname(recovered), bias = unname(recovered - truth),
                         relative_error = abs(unname(recovered - truth)) / pmax(abs(unname(truth)), 1e-8),
                         stringsAsFactors = FALSE)
  recovery$within_30_percent <- recovery$relative_error <= .30
  list(simulation = simulation, estimate = estimate, recovery = recovery,
       pass = is.finite(estimate$loglik),
       note = "Simulation-to-recovery report: MIF2 estimates use only observed inputs; latent truth remains hidden.")
}
