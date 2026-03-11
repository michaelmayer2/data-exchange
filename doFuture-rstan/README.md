#doFuture with rstan

This folder contains an example of using doFuture with rstan.

A user wants to run multiple STAN models in a `foreach` loop via `%dofuture%`. 

While the loop is over `n_tasks` models, the `doFuture` environment is limiting the concurrent exection of STAN models to `n_tasks_concurrent`. Additionally each `rstan` call will run `n_chains` chains, distributed across `n_chains_concurrent` cores. 

This implies that for a given set of parameters
- `n_tasks` STAN models will be run 
- at any given time a maximum of `n_tasks_concurrent` models will be concurrently executed
- Each running model will consume up to `n_chains_concurrent` cores and run `n_chains` individual chains. 
- If `n_chains_concurrent < n_chains`, the chains will be run partially in sequential mode. 

Example: For a run with `n_tasks=10`, `n_chains=4`, `n_chains_concurrent=4` and `n_tasks_concurrent=2`, the code will run 10 stan models with 2 running concurrently and each stan model executing 4 chains distributed across 4 cores. In case you set `n_chains_concurrent_1`, the execution of each stan model will run 4 chains sequentially on a single core. 

When it comes to SLURM and you want to run the sample code via `sbatch`, the recommendation is to use 

```
sbatch -n 1 --cpus-per-task=$(n_tasks_concurrent*n_chains_concurrent) --wrap="Rscript your-code.R" 
````

where the `--wrap` is a bit of a abbreviation that makes the need to have a submit script obsolete. You however need to ensure that `Rscript` (and the one with the correct R version) is in your `$PATH`. Alternatively you can specify the full path like `/opt/R/4.5.2/bin/Rscript` as well - YMMV on your system. 


