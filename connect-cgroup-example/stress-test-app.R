#
# app.R – CPU-Only Stress Tester for Posit Connect
#

library(shiny)
library(parallelly)
library(future)
library(promises)

# Use separate R processes for true parallel CPU burning
plan(multisession, workers = 3)

ui <- fluidPage(
  titlePanel("Posit Connect CPU Stress Test"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Detected CPU Resources"),
      verbatimTextOutput("detected"),
      
      tags$hr(),
      
      numericInput(
        "seconds",
        "Stress duration (seconds)",
        value = 10, min = 5, step = 5
      ),
      
      tags$hr(),
      actionButton("start", "Start CPU Stress", class = "btn-danger"),
      actionButton("stop",  "Stop (best-effort)", class = "btn-warning"),
      
      tags$br(), tags$br(),
      helpText("Stopping workers is best-effort. Workers run in separate R processes.")
    ),
    
    mainPanel(
      h4("Run Status"),
      verbatimTextOutput("status"),
      
      tags$hr(),
      
      h4("Worker Logs"),
      verbatimTextOutput("logs")
    )
  )
)

server <- function(input, output, session) {
  
  # This is cgroup-aware on Posit Connect
  avail_cores <- 3
  
  output$detected <- renderText({
    paste0(
      "parallelly::availableCores(): ", avail_cores, "\n",
      "future::nbrOfWorkers():       ", future::nbrOfWorkers()
    )
  })
  
  # Shared reactive state
  rv <- reactiveValues(
    running    = FALSE,
    stop_flag  = FALSE,
    logs       = character(),
    started_at = NULL,
    futures    = list()
  )
  
  log_line <- function(...) {
    rv$logs <- c(rv$logs,
                 paste0(format(Sys.time(), "%H:%M:%S"), " | ",
                        paste(..., collapse = " "))
    )
    if (length(rv$logs) > 200)
      rv$logs <- tail(rv$logs, 200)
  }
  
  output$logs <- renderText(paste(rv$logs, collapse = "\n"))
  
  output$status <- renderText({
    if (!rv$running) return("Idle.")
    elapsed <- round(
      as.numeric(difftime(Sys.time(), rv$started_at, units = "secs")), 1
    )
    paste0(
      "RUNNING\n",
      "Started:   ", format(rv$started_at), "\n",
      "Elapsed:   ", elapsed, " sec\n",
      "Workers:   ", length(rv$futures), "\n",
      "Stop flag: ", rv$stop_flag
    )
  })
  
  #
  # Worker that burns CPU for N seconds
  #
  cpu_worker <- function(id, seconds) {
    logs <- character()
    add <- function(msg) logs <<- c(logs, paste0("[worker ", id, "] ", msg))
    
    add(paste0("starting; duration=", seconds, "s"))
    
    start <- Sys.time()
    x <- 0.0
    iter <- 0L
    
    # Tight compute loop
    while (as.numeric(difftime(Sys.time(), start, units = "secs")) < seconds) {
      for (i in 1:5e6) {
        x <- x + sin(i) * cos(i)
      }
      iter <- iter + 1L
      if (iter %% 2 == 0)
        add(paste0("cpu chunk iter=", iter))
    }
    
    add(paste0("finishing; checksum=", format(x, digits = 6)))
    list(id = id, logs = logs)
  }
  
  #
  # Start button — launches futures
  #
  observeEvent(input$start, {
    req(!rv$running)
    
    rv$running    <- TRUE
    rv$stop_flag  <- FALSE
    rv$logs       <- character()
    rv$started_at <- Sys.time()
    rv$futures    <- list()
    
    # Freeze reactive inputs so workers don't see input$... inside futures
    seconds  <- isolate(input$seconds)
    
    worker_count <- 3 # soft cap
    
    log_line("START requested")
    log_line("available cores:", avail_cores, "-> workers:", worker_count)
    
    # Launch worker futures
    for (i in seq_len(worker_count)) {
      
      if (rv$stop_flag) break
      
      f <- future({
        cpu_worker(id = i, seconds = seconds)
      }) %...>% (function(res) {
        for (l in res$logs) log_line(l)
        res
      }) %...!% (function(e) {
        log_line("[worker", i, "ERROR]", conditionMessage(e))
        NULL
      })
      
      rv$futures[[i]] <- f
    }
    
    # When all futures complete
    promise_all(.list = rv$futures) %...>% (function(res) {
      log_line("ALL WORKERS COMPLETE")
      rv$running <- FALSE
      rv$futures <- list()
    }) %...!% (function(e) {
      log_line("Future aggregation error:", conditionMessage(e))
      rv$running <- FALSE
      rv$futures <- list()
    })
  })
  
  #
  # Stop button — cancel futures (best effort)
  #
  observeEvent(input$stop, {
    if (!rv$running) return()
    rv$stop_flag <- TRUE
    log_line("STOP requested")
    
    for (f in rv$futures)
      try(future::cancel(f), silent = TRUE)
  })
  
  #
  # Clean up on session end
  #
  session$onSessionEnded(function() {
    rv$stop_flag <- TRUE
    for (f in rv$futures)
      try(future::cancel(f), silent = TRUE)
  })
}

shinyApp(ui, server)
