import os
import shutil

import pytest


def _java_available() -> bool:
    return bool(shutil.which("java") or os.getenv("JAVA_HOME"))


def pytest_collection_modifyitems(config, items):
    if _java_available():
        return
    skip = pytest.mark.skip(reason="Java not found: run Spark tests in the dev container or `docker compose run --rm platform pytest`")
    for item in items:
        if "spark" in item.keywords:
            item.add_marker(skip)


@pytest.fixture(scope="session")
def spark():
    from zingyestates.spark import get_spark

    session = get_spark("zingyestates-tests")
    session.sparkContext.setLogLevel("ERROR")
    yield session
    session.stop()
