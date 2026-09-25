import os

from datadog import api, initialize

initialize(api_key=os.environ["DD_API_KEY"], api_host=f"https://api.{os.getenv('DD_SITE', 'datadoghq.com')}")
tags = ["company:zingyestates", "env:prod", "service:data-platform", "pipeline:property-ingestion"]
api.Metric.send(metric="zingyestates.data.quality.records_processed", points=100000, tags=tags)
api.Metric.send(metric="zingyestates.data.quality.records_rejected", points=320, tags=tags)
api.Metric.send(metric="zingyestates.data.quality.rejection_rate", points=0.0032, tags=tags)
