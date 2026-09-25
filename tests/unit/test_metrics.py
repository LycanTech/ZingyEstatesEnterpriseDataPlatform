import pytest

from zingyestates.metrics import Metrics


@pytest.fixture
def metrics(monkeypatch):
    monkeypatch.delenv("DD_AGENT_HOST", raising=False)
    monkeypatch.delenv("DD_API_KEY", raising=False)
    return Metrics.from_env("qa", "silver-transformation")


def test_log_backend_without_datadog_config(metrics):
    assert metrics.backend == "log"


def test_required_contract_tags(metrics):
    metrics.gauge("data.quality.rejection_rate", 0.02, source="crm")
    name, value, tags = metrics.emitted[0]
    assert name == "zingyestates.data.quality.rejection_rate"
    assert value == 0.02
    for tag in ("company:zingyestates", "env:qa", "service:data-platform", "pipeline:silver-transformation", "source:crm"):
        assert tag in tags


def test_pipeline_run_success(metrics):
    with metrics.pipeline_run():
        pass
    names = [m[0] for m in metrics.emitted]
    assert "zingyestates.data.pipeline.execution" in names
    assert "zingyestates.data.pipeline.success" in names
    assert "zingyestates.data.pipeline.duration_seconds" in names
    assert "zingyestates.databricks.job.failed" not in names


def test_pipeline_run_failure_is_reraised_and_counted(metrics):
    with pytest.raises(RuntimeError), metrics.pipeline_run():
        raise RuntimeError("boom")
    names = [m[0] for m in metrics.emitted]
    assert "zingyestates.databricks.job.failed" in names
    assert "zingyestates.data.pipeline.success" not in names
