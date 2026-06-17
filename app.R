library(shiny)
library(bslib)
library(httr2)
library(jsonlite)
library(reactable)

# ── Config ─────────────────────────────────────────────────────────────
SUPABASE_URL      <- Sys.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY <- Sys.getenv("SUPABASE_ANON_KEY")
APP_USERNAME      <- Sys.getenv("APP_USERNAME")
APP_PASSWORD      <- Sys.getenv("APP_PASSWORD")

# ── Auth UI ─────────────────────────────────────────────────────────────
login_ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background-color: #1a1a2e; }
    .login-box {
      max-width: 380px; margin: 120px auto; padding: 40px;
      background: #16213e; border-radius: 12px;
      border: 1px solid #0f3460; box-shadow: 0 8px 32px rgba(0,0,0,0.4);
    }
    .login-box h2 { color: #e94560; font-family: 'Georgia', serif;
      text-align: center; margin-bottom: 8px; }
    .login-box p  { color: #ccc; text-align: center; margin-bottom: 28px;
      font-size: 13px; }
    .login-box .form-control { background: #0f3460; border: 1px solid #e94560;
      color: white; border-radius: 6px; }
    .login-box .form-control:focus { box-shadow: 0 0 0 2px rgba(233,69,96,0.3); }
    .login-box label { color: white; font-size: 13px; }
    .btn-login { background: #e94560; border: none; color: white;
      width: 100%; padding: 10px; border-radius: 6px; font-size: 15px;
      margin-top: 10px; cursor: pointer; }
    .btn-login:hover { background: #c73652; }
    .error-msg { color: #e94560; text-align: center; font-size: 13px;
      margin-top: 10px; }
  "))),
  div(class = "login-box",
    h2("🔥 Burn Notice"),
    p("Columbia County SMS Alert System"),
    textInput("username", "Username", placeholder = "Enter username"),
    passwordInput("password", "Password", placeholder = "Enter password"),
    actionButton("login_btn", "Sign In", class = "btn-login"),
    uiOutput("login_error")
  )
)

# ── Main UI ─────────────────────────────────────────────────────────────
main_ui <- page_navbar(
  title = "🔥 Burn Notice",
  theme = bs_theme(
    bootswatch = "darkly",
    primary    = "#e94560"
  ),
tags$head(tags$style(HTML("
    .form-label, label, .control-label { color: white !important; }
    .form-check-label { color: white !important; }
    .card p, .card span, .card div { color: white; }
    .card-header { color: white !important; }
    .char-count { color: white !important; }

    /* Dropdown / select styling (scoped to cards only) */
    .card .selectize-input, .card .selectize-dropdown,
    .card select.form-select, .card select.form-control {
      background-color: #0f3460 !important;
      color: white !important;
      border: 1px solid #e94560 !important;
    }
    .card .selectize-dropdown-content .option,
    .card .selectize-dropdown-content .active {
      background-color: #16213e !important;
      color: white !important;
    }

    /* Notification / alert styling */
    .shiny-notification {
      background-color: #16213e !important;
      color: white !important;
      border: 1px solid #e94560 !important;
    }
    .shiny-notification-message,
    .shiny-notification-error,
    .shiny-notification-warning {
      color: white !important;
    }
  "))),

  # ── Compose page ──────────────────────────────────────────────────
  nav_panel("Compose",
    layout_columns(
      col_widths = c(5, 7),

      card(
        card_header("Compose Alert"),
        textAreaInput("message", "Message",
                      placeholder = "Type your alert message for Columbia County...",
                      rows = 6, width = "100%"),
        uiOutput("char_count"),
        hr(),
        checkboxInput("approved",
                      strong(span(style = "color:white;",
                        "✅ I approve this message and confirm it is ready to send")),
                      value = FALSE),
        uiOutput("send_btn_ui"),
        hr(),
        verbatimTextOutput("send_result")
      ),

      card(
        card_header("Message Preview"),
        div(style = "
          background: #111;
          border-radius: 18px;
          padding: 20px 16px;
          max-width: 320px;
          margin: 0 auto;
          border: 6px solid #333;
          min-height: 200px;
        ",
          div(style = "font-size: 11px; color: white; margin-bottom: 8px;
                       text-align: center;",
            "From: +1 (844) 917-3897"
          ),
          div(style = "
            background: #2a2a2a;
            border-radius: 12px 12px 12px 2px;
            padding: 12px 14px;
            color: white;
            font-size: 14px;
            line-height: 1.5;
            min-height: 60px;
          ",
            uiOutput("preview_text")
          )
        )
      )
    )
  ),

  # ── Sent Messages page ────────────────────────────────────────────
  nav_panel("Sent Messages",
    card(
      card_header("Recent Sent Messages"),
      reactableOutput("sms_logs_table")
    )
  ),

  # ── Subscribers page ──────────────────────────────────────────────
  nav_panel("Subscribers",
    layout_columns(
      col_widths = c(4, 4, 4),

card(
        card_header("Add Subscriber"),
        textInput("new_name", "Name", placeholder = "Jane Doe"),
        textInput("new_phone", "Phone Number", placeholder = "+15091234567"),
        helpText(span(style = "color:white;", "Format: +1XXXXXXXXXX")),
        uiOutput("phone_validation_msg"),
        uiOutput("add_subscriber_btn")
      ),

      card(
        card_header("Remove Subscriber"),
        uiOutput("remove_select_ui"),
        actionButton("remove_subscriber_btn", "Remove Subscriber",
                     class = "btn-danger w-100", icon = icon("user-minus"))
      ),

      card(
        card_header("Active Subscribers"),
        reactableOutput("subscribers_table")
      )
    )
  ),

  nav_spacer(),
  nav_item(actionLink("logout", "Sign Out", icon = icon("sign-out-alt")))
)

# ── UI wrapper ──────────────────────────────────────────────────────────
ui <- uiOutput("app_ui")

# ── Server ──────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  logged_in <- reactiveVal(FALSE)

  output$app_ui <- renderUI({
    if (logged_in()) main_ui else login_ui
  })

  # ── Login ──────────────────────────────────────────────────────
  observeEvent(input$login_btn, {
    if (input$username == APP_USERNAME && input$password == APP_PASSWORD) {
      logged_in(TRUE)
    } else {
      output$login_error <- renderUI(
        div(class = "error-msg", "Invalid username or password")
      )
    }
  })

  # ── Logout ─────────────────────────────────────────────────────
  observeEvent(input$logout, { logged_in(FALSE) })

  # ── Show/hide send button based on checkbox ────────────────────
  output$send_btn_ui <- renderUI({
    if (isTRUE(input$approved)) {
      actionButton("send", "Send Alert to All Subscribers",
                   class = "btn-danger w-100 mt-2",
                   icon  = icon("paper-plane"))
    }
  })

  # ── Live preview ───────────────────────────────────────────────
  output$preview_text <- renderUI({
    msg <- input$message
    if (is.null(msg) || nchar(trimws(msg)) == 0) {
      span(style = "color: #777; font-style: italic;",
           "Your message will appear here...")
    } else {
      p(style = "margin: 0; color: white;", msg)
    }
  })

  # ── Character count ────────────────────────────────────────────
  output$char_count <- renderUI({
    n <- nchar(input$message %||% "")
    color <- if (n > 160) "#e94560" else "white"
    div(class = "char-count",
        style = paste0("text-align: right; font-size: 12px; color: ", color, ";"),
        paste0(n, " characters", if (n > 160) " (multi-part SMS)" else ""))
  })

  # ── Send alert ─────────────────────────────────────────────────
  observeEvent(input$send, {
    req(input$message)

    if (nchar(trimws(input$message)) == 0) {
      output$send_result <- renderText("⚠️ Message cannot be empty.")
      return()
    }

    result <- tryCatch({
      resp <- request(paste0(SUPABASE_URL, "/functions/v1/send_alert")) |>
        req_headers(
          "Content-Type"  = "application/json",
          "Authorization" = paste("Bearer", SUPABASE_ANON_KEY)
        ) |>
        req_body_json(list(
          region  = "columbia_county",
          message = input$message
        )) |>
        req_perform()
      resp_body_json(resp)
    }, error = function(e) list(error = e$message))

    if (!is.null(result$error)) {
      output$send_result <- renderText(paste("❌ Error:", result$error))
    } else {
      output$send_result <- renderText(
        paste0("✅ Sent: ", result$sent, " | Failed: ", result$failed)
      )
      updateTextAreaInput(session, "message", value = "")
      updateCheckboxInput(session, "approved", value = FALSE)
      logs_data(fetch_logs())
    }
  })

  # ── Supabase helpers ───────────────────────────────────────────
  fetch_logs <- function() {
    tryCatch({
      resp <- request(paste0(SUPABASE_URL, "/rest/v1/sms_logs")) |>
        req_headers("apikey"        = SUPABASE_ANON_KEY,
                    "Authorization" = paste("Bearer", SUPABASE_ANON_KEY)) |>
        req_url_query(select = "phone,message,status,sent_at",
                      order  = "sent_at.desc", limit = "50") |>
        req_perform()
      resp_body_json(resp, simplifyVector = TRUE)
    }, error = function(e) data.frame())
  }

fetch_subscribers <- function() {
    tryCatch({
      resp <- request(paste0(SUPABASE_URL, "/rest/v1/subscribers")) |>
        req_headers("apikey"        = SUPABASE_ANON_KEY,
                    "Authorization" = paste("Bearer", SUPABASE_ANON_KEY)) |>
        req_url_query(select = "id,name,phone,status,created_at",
                      order  = "created_at.desc") |>
        req_perform()
      resp_body_json(resp, simplifyVector = TRUE)
    }, error = function(e) data.frame())
  }

  # ── Reactive data ──────────────────────────────────────────────
  logs_data        <- reactiveVal(fetch_logs())
  subscribers_data <- reactiveVal(fetch_subscribers())

  autoInvalidate <- reactiveTimer(30000)
  observe({
    autoInvalidate()
    logs_data(fetch_logs())
    subscribers_data(fetch_subscribers())
  })

  # ── Phone validation (reactive) ────────────────────────────────
  phone_status <- reactive({
    phone    <- trimws(input$new_phone %||% "")
    existing <- subscribers_data()

    if (nchar(phone) == 0)
      return(list(valid = FALSE, msg = NULL))
    if (!startsWith(phone, "+1"))
      return(list(valid = FALSE, msg = "⚠️ Must start with +1"))
    if (!grepl("^\\+1[0-9]{10}$", phone))
      return(list(valid = FALSE, msg = "⚠️ Format must be +1 followed by 10 digits"))
    if (is.data.frame(existing) && nrow(existing) > 0 && phone %in% existing$phone)
      return(list(valid = FALSE, msg = "⚠️ This number is already subscribed"))

    return(list(valid = TRUE, msg = "✅ Valid number"))
  })

  output$phone_validation_msg <- renderUI({
    ps <- phone_status()
    if (is.null(ps$msg)) return(NULL)
    color <- if (ps$valid) "#00bc8c" else "#e94560"
    div(style = paste0("color:", color, "; font-size: 13px; margin: 6px 0 10px;"),
        ps$msg)
  })

  output$add_subscriber_btn <- renderUI({
    if (isTRUE(phone_status()$valid)) {
      actionButton("add_subscriber", "Add Subscriber",
                   class = "btn-success w-100",
                   icon  = icon("user-plus"))
    }
  })

  # ── Remove subscriber dropdown ──────────────────────────────────
  output$remove_select_ui <- renderUI({
    df <- subscribers_data()
    if (is.data.frame(df) && nrow(df) > 0) {
      labels  <- ifelse(is.na(df$name) | df$name == "", df$phone,
                        paste0(df$name, " (", df$phone, ")"))
      choices <- setNames(df$phone, labels)
    } else {
      choices <- character(0)
    }
    selectInput("remove_phone_select", "Select subscriber to remove",
                choices = choices)
  })

  # ── Add subscriber ─────────────────────────────────────────────
  observeEvent(input$add_subscriber, {
    phone <- trimws(input$new_phone)

name <- trimws(input$new_name %||% "")

    result <- tryCatch({
      resp <- request(paste0(SUPABASE_URL, "/functions/v1/manage_subscriber")) |>
        req_headers("Content-Type"  = "application/json",
                    "Authorization" = paste("Bearer", SUPABASE_ANON_KEY)) |>
        req_body_json(list(action = "add", phone = phone, name = name)) |>
        req_perform()
      resp_body_json(resp)
    }, error = function(e) list(error = e$message))

    if (!is.null(result$error)) {
      showNotification(paste("❌ Error:", result$error),
                       type = "error", duration = 5)
    } else {
      showNotification(paste0("✅ ", phone, " added successfully!"),
                       type = "message", duration = 4)
      updateTextInput(session, "new_phone", value = "")
      updateTextInput(session, "new_name", value = "")
      subscribers_data(fetch_subscribers())
    }
  })

  # ── Remove subscriber ──────────────────────────────────────────
  observeEvent(input$remove_subscriber_btn, {
    phone <- input$remove_phone_select
    req(phone)

    tryCatch({
      request(paste0(SUPABASE_URL, "/functions/v1/manage_subscriber")) |>
        req_headers("Content-Type"  = "application/json",
                    "Authorization" = paste("Bearer", SUPABASE_ANON_KEY)) |>
        req_body_json(list(action = "remove", phone = phone)) |>
        req_perform()

      showNotification(paste0("🗑️ ", phone, " removed."),
                       type = "warning", duration = 4)
      subscribers_data(fetch_subscribers())
    }, error = function(e) {
      showNotification(paste("❌ Error:", e$message), type = "error")
    })
  })

  # ── Render SMS logs table ──────────────────────────────────────
  output$sms_logs_table <- renderReactable({
    df <- logs_data()
    if (is.null(df) || nrow(df) == 0) {
      return(reactable(data.frame(Message = "No messages sent yet")))
    }

    reactable(
      df,
      columns = list(
        phone    = colDef(name = "Phone", minWidth = 130),
        message  = colDef(name = "Message", minWidth = 250),
        status   = colDef(name = "Status", maxWidth = 90,
          cell = function(value) {
            color <- if (value == "sent") "#00bc8c" else "#e94560"
            span(style = paste0("color:", color, "; font-weight:bold;"), value)
          }),
        sent_at  = colDef(name = "Sent At", minWidth = 160)
      ),
      theme = reactableTheme(
        color           = "white",
        backgroundColor = "#1a1a2e",
        borderColor     = "#0f3460",
        stripedColor    = "#16213e",
        highlightColor  = "#0f3460",
        cellPadding     = "10px 14px",
        headerStyle     = list(color = "white", fontWeight = "bold",
                               borderBottom = "2px solid #e94560")
      ),
      striped         = TRUE,
      highlight       = TRUE,
      searchable      = TRUE,
      defaultPageSize = 15
    )
  })

  # ── Render subscribers table ───────────────────────────────────
  output$subscribers_table <- renderReactable({
    df <- subscribers_data()
    if (is.null(df) || nrow(df) == 0) {
      return(reactable(data.frame(Message = "No subscribers yet")))
    }

    reactable(
      df[, c("name", "phone", "status", "created_at"), drop = FALSE],
      columns = list(
        name       = colDef(name = "Name", minWidth = 120),
        phone      = colDef(name = "Phone Number", minWidth = 140),
        status     = colDef(name = "Status", maxWidth = 100,
          cell = function(value) {
            color <- if (value == "active") "#00bc8c" else "#e94560"
            span(style = paste0("color:", color, "; font-weight:bold;"), value)
          }),
        created_at = colDef(name = "Date Added", minWidth = 160)
      ),
      theme = reactableTheme(
        color           = "white",
        backgroundColor = "#1a1a2e",
        borderColor     = "#0f3460",
        stripedColor    = "#16213e",
        highlightColor  = "#0f3460",
        cellPadding     = "10px 14px",
        headerStyle     = list(color = "white", fontWeight = "bold",
                               borderBottom = "2px solid #e94560")
      ),
      striped         = TRUE,
      highlight       = TRUE,
      searchable      = TRUE,
      defaultPageSize = 15
    )
  })
}

shinyApp(ui, server)