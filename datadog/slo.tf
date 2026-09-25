resource "datadog_service_level_objective" "pipeline_success" {
  name        = "ZingyEstates Data Pipeline Success (${var.environment})"
  type        = "metric"
  description = "Scheduled data pipeline executions succeed."
  timeframe   = "30d"
  tags        = ["company:${var.company}", "env:${var.environment}", "service:data-platform"]

  thresholds {
    timeframe = "30d"
    target    = 99.5
    warning   = 99.9
  }

  query {
    numerator   = "sum:zingyestates.data.pipeline.success{env:${var.environment}}.as_count()"
    denominator = "sum:zingyestates.data.pipeline.execution{env:${var.environment}}.as_count()"
  }
}

resource "datadog_service_level_objective" "data_freshness" {
  name        = "ZingyEstates Data Freshness (${var.environment})"
  type        = "metric"
  description = "Data meets the agreed freshness window."
  timeframe   = "30d"
  tags        = ["company:${var.company}", "env:${var.environment}", "service:data-platform"]

  thresholds {
    timeframe = "30d"
    target    = 99.0
    warning   = 99.5
  }

  query {
    numerator   = "sum:zingyestates.data.freshness.satisfied{env:${var.environment}}.as_count()"
    denominator = "sum:zingyestates.data.freshness.check{env:${var.environment}}.as_count()"
  }
}
