import pytest

from zingyestates.cli import config_from_args, parse_args
from zingyestates.entities import ENTITIES
from zingyestates.quality import RULES
from zingyestates.sample_data import generate


def test_sample_data_is_deterministic():
    assert generate("2026-09-25") == generate("2026-09-25")


def test_sample_rows_match_entity_columns():
    data = generate("2026-09-25", n_properties=40, n_agents=5)
    for name, rows in data.items():
        expected = set(ENTITIES[name].column_names)
        assert rows, name
        for row in rows:
            assert set(row) == expected, name


def test_every_entity_has_quality_rules():
    assert set(RULES) == set(ENTITIES)


def test_cli_defaults_run_date_and_builds_azure_config():
    args = parse_args(["--env", "uat", "--storage-account", "stzingyuatze01dl"])
    assert len(args.run_date) == 10
    assert config_from_args(args).table_path("gold", "dim_date").startswith("abfss://gold@stzingyuatze01dl")


def test_cli_rejects_bad_run_date():
    with pytest.raises(ValueError):
        parse_args(["--env", "dev", "--run-date", "25/09/2026"])
