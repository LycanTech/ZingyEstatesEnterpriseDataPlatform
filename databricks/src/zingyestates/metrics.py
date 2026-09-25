"""Datadog metrics following datadog/metrics-contract.md.

Backends, chosen from the environment:
  * DogStatsD  - DD_AGENT_HOST is set (local docker compose, clusters with the agent init script)
  * HTTP API   - DD_API_KEY is set (Databricks job clusters read it from a secret scope)
  * log only   - neither is set (unit tests, offline local runs)
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from time import monotonic

log = logging.getLogger(__name__)

PREFIX = "zingyestates"


@dataclass
class Metrics:
    environment: str
    pipeline: str
    backend: str = "log"
    emitted: list[tuple[str, float, list[str]]] = field(default_factory=list)
    _client: object | None = None

    @classmethod
    def from_env(cls, environment: str, pipeline: str) -> Metrics:
        if os.getenv("DD_AGENT_HOST"):
            from datadog.dogstatsd import DogStatsd

            client = DogStatsd(host=os.environ["DD_AGENT_HOST"], port=int(os.getenv("DD_DOGSTATSD_PORT", "8125")))
            return cls(environment, pipeline, backend="dogstatsd", _client=client)
        if os.getenv("DD_API_KEY"):
            from datadog import api, initialize

            initialize(api_key=os.environ["DD_API_KEY"], api_host=f"https://api.{os.getenv('DD_SITE', 'datadoghq.com')}")
            return cls(environment, pipeline, backend="api", _client=api)
        return cls(environment, pipeline)

    def tags(self, **extra: str) -> list[str]:
        base = {
            "company": "zingyestates",
            "env": self.environment,
            "service": "data-platform",
            "pipeline": self.pipeline,
        }
        base.update({k: v for k, v in extra.items() if v is not None})
        return [f"{k}:{v}" for k, v in base.items()]

    def gauge(self, name: str, value: float, **tags: str) -> None:
        self._send(name, value, tags, kind="gauge")

    def count(self, name: str, value: float = 1, **tags: str) -> None:
        self._send(name, value, tags, kind="count")

    def _send(self, name: str, value: float, tags: dict[str, str], kind: str) -> None:
        metric = f"{PREFIX}.{name}"
        tag_list = self.tags(**tags)
        self.emitted.append((metric, float(value), tag_list))
        log.info("metric %s=%s %s", metric, value, ",".join(tag_list))
        try:
            if self.backend == "dogstatsd":
                send = self._client.gauge if kind == "gauge" else self._client.increment
                send(metric, value, tags=tag_list)
            elif self.backend == "api":
                self._client.Metric.send(metric=metric, points=value, tags=tag_list, type=kind)
        except Exception:  # metrics must never fail a data pipeline
            log.warning("failed to send metric %s", metric, exc_info=True)

    @contextmanager
    def pipeline_run(self) -> Iterator[None]:
        """Emit execution/success/duration around a pipeline step, and job.failed on error."""
        started = monotonic()
        self.count("data.pipeline.execution")
        try:
            yield
        except Exception:
            self.count("databricks.job.failed")
            raise
        else:
            self.count("data.pipeline.success")
        finally:
            duration = monotonic() - started
            self.gauge("data.pipeline.duration_seconds", duration)
            self.gauge("databricks.job.duration_seconds", duration)
