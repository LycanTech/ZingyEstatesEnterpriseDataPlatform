import pytest

from zingyestates.config import ZONES, PlatformConfig


def test_azure_paths_use_one_filesystem_per_zone():
    cfg = PlatformConfig.for_azure("prod", "stzingyprodze01dl")
    assert cfg.table_path("silver", "properties") == "abfss://silver@stzingyprodze01dl.dfs.core.windows.net/properties"
    assert set(cfg.zone_roots) == set(ZONES)


def test_landing_and_export_paths_are_partitioned_by_date():
    cfg = PlatformConfig.for_azure("dev", "acct")
    assert cfg.landing_path("crm", "agents", "2026-09-25").endswith("/crm/agents/ingest_date=2026-09-25")
    assert cfg.export_path("fact_sales", "2026-09-25") == "abfss://gold@acct.dfs.core.windows.net/_exports/fact_sales/run_date=2026-09-25"


def test_local_paths(tmp_path):
    cfg = PlatformConfig.for_local(tmp_path)
    assert cfg.environment == "local"
    assert cfg.zone("gold") == (tmp_path / "gold").resolve().as_posix()


def test_rejects_unknown_environment():
    with pytest.raises(ValueError, match="Unknown environment"):
        PlatformConfig.for_azure("staging", "acct")


def test_azure_requires_storage_account():
    with pytest.raises(ValueError, match="storage_account"):
        PlatformConfig.for_azure("dev", "")
