library(future)

# Clean up any existing plans
plan(sequential)

# Simple and reliable approach: Control cores at the Stan level
library(doFuture)
library(foreach)
library(future)
library(future.mirai)
library(progressr)

# Let's ensure our model is downloaded
if (!file.exists("model.stan")) {
  write(
    RCurl::getURI(
      "https://raw.githubusercontent.com/stan-dev/cmdstanr/master/vignettes/articles-online-only/opencl-files/bernoulli_logit_glm.stan"
    ),
    "model.stan"
  )
}

# number of concurrent STAN models being run
n_tasks_concurrent <- 2

# number of concurrent/parallel chains executed
n_chains_concurrent <- 4 

# number of chains per model
n_chains <- 4

# Set up outer parallelization only
plan(mirai_multisession, workers = n_tasks_concurrent)

cat(
  "Starting a future object with",
  n_tasks_concurrent,
  "concurrently run STAN models\n"
)
cat(". running", n_chains_concurrent, "chains in parallel.")
cat(
  ". This will consume ",
  n_tasks_concurrent,
  "x",
  n_chains_concurrent,
  "=",
  n_tasks_concurrent * n_chains_concurrent,
  "cpu's\n"
)


# Stan function that uses 4 cores internally
run_stan <- function(i, p = NULL) {
  library(rstan)

  # Set Stan to use n_chains_concurrent cores
  options(mc.cores = n_chains_concurrent)
  rstan_options(auto_write = TRUE)

  # Generate some fake data
  n <- 25000
  k <- 20
  X <- matrix(rnorm(n * k), ncol = k)
  y <- rbinom(n, size = 1, prob = plogis(3 * X[, 1] - 2 * X[, 2] + 1))
  mdata <- list(k = k, n = n, y = y, X = X)

  # Run Stan - it will automatically use 4 cores due to mc.cores option
  fit <- stan(
    file = "model.stan",
    data = mdata,
    chains = n_chains,
    cores = n_chains_concurrent,
    iter = 4000,
    verbose = FALSE,
    refresh = 0
  )

  # Signal progress after task completes
  if (!is.null(p)) {
    p()
  }

  return(list(
    iteration = i,
    worker_pid = Sys.getpid(),
    cores_used = n_chains_concurrent,
    fit = fit
  ))
}

# Run function using foreach + %dofuture%
n_tasks <- 10

cat("Starting the loop over ", n_tasks, "Stan models\n")

start_time <- Sys.time()

# progressr handler: prints a real-time progress bar to the console
with_progress({
  p <- progressor(steps = n_tasks)

  results <- foreach(
    i = 1:n_tasks,
    .options.future = list(seed = TRUE, packages = "rstan")
  ) %dofuture%
    {
      run_stan(i, p)
    }
})

total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(
  "\n✅ All",
  n_tasks,
  "iterations completed in",
  round(total_time, 1),
  "seconds!\n"
)
