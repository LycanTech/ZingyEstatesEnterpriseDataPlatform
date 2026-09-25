# Local Spark + Delta runtime matching Databricks Runtime 15.4 LTS
# (Python 3.11, Spark 3.5, Delta 3.2). Used by docker-compose.yml and CI parity.
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/workspace/databricks/src

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jre-headless procps \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "/usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture)" /usr/lib/jvm/java-17

ENV JAVA_HOME=/usr/lib/jvm/java-17

WORKDIR /workspace
COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install -r /tmp/requirements-dev.txt jupyterlab==4.2.5

# Pre-fetch the Delta jars so the first run works offline.
RUN python -c "from delta import configure_spark_with_delta_pip; from pyspark.sql import SparkSession; \
configure_spark_with_delta_pip(SparkSession.builder.master('local[1]')).getOrCreate().stop()"

CMD ["python", "-m", "zingyestates.local_run", "--base-dir", "/workspace/.local-lake"]
