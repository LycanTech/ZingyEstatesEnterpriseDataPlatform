resource "datadog_dashboard" "data_platform" {
  title       = "ZingyEstates - Enterprise Data Platform (${var.environment})"
  description = "ADF, Databricks, data quality, freshness and platform health."
  layout_type = "ordered"

  widget {
    timeseries_definition {
      title = "Pipeline Executions"
      request {
        q            = "sum:zingyestates.data.pipeline.execution{env:${var.environment}}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    query_value_definition {
      title     = "Data Quality Rejection Rate"
      autoscale = true
      request {
        q          = "avg:zingyestates.data.quality.rejection_rate{env:${var.environment}}"
        aggregator = "avg"
      }
    }
  }

  widget {
    query_value_definition {
      title     = "Data Freshness Minutes"
      autoscale = true
      request {
        q          = "max:zingyestates.data.freshness_minutes{env:${var.environment}}"
        aggregator = "max"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Records Processed vs Rejected"
      request {
        q            = "sum:zingyestates.data.quality.records_processed{env:${var.environment}} by {source}.as_count()"
        display_type = "bars"
      }
      request {
        q            = "sum:zingyestates.data.quality.records_rejected{env:${var.environment}} by {source}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Databricks Job Failures"
      request {
        q            = "sum:zingyestates.databricks.job.failed{env:${var.environment}}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Pipeline Duration"
      request {
        q            = "avg:zingyestates.data.pipeline.duration_seconds{env:${var.environment}} by {pipeline}"
        display_type = "line"
      }
    }
  }
}
