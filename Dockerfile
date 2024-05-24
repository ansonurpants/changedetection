# pip dependencies install stage
FROM python:3.10-slim-bookworm as builder

# See `cryptography` pin comment in requirements.txt
ARG CRYPTOGRAPHY_DONT_BUILD_RUST=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    gcc \
    libc-dev \
    libffi-dev \
    libjpeg-dev \
    libssl-dev \
    libxslt-dev \
    make \
    zlib1g-dev

RUN mkdir /install
WORKDIR /install

COPY requirements.txt /requirements.txt

RUN pip install --target=/dependencies -r /requirements.txt

# Playwright is an alternative to Selenium
# Excluded this package from requirements.txt to prevent arm/v6 and arm/v7 builds from failing
# https://github.com/dgtlmoon/changedetection.io/pull/1067 also musl/alpine (not supported)
RUN pip install --target=/dependencies playwright~=1.41.2 \
    || echo "WARN: Failed to install Playwright. The application can still run, but the Playwright option will be disabled."

# Final image stage
FROM python:3.10-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxslt1.1 \
    # For pdftohtml
    poppler-utils \
    zlib1g \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# https://stackoverflow.com/questions/58701233/docker-logs-erroneously-appears-empty-until-container-stops
ENV PYTHONUNBUFFERED=1

# Re #80, sets SECLEVEL=1 in openssl.conf to allow monitoring sites with weak/old cipher suites
RUN sed -i 's/^CipherString = .*/CipherString = DEFAULT@SECLEVEL=1/' /etc/ssl/openssl.cnf

# Create a non-root user with a specific UID
RUN adduser --uid 10001 --disabled-password --gecos '' appuser \
    && mkdir -p /app /datastore

# Copy modules over to the final image and add their dir to PYTHONPATH
COPY --from=builder /dependencies /usr/local
ENV PYTHONPATH=/usr/local

# Copy the application code as the root user first
COPY changedetectionio /app/changedetectionio
COPY changedetection.py /app/changedetection.py

# Ensure all files in /app are owned by the non-root user
RUN chown -R appuser:appuser /app /datastore

# Switch to non-root user
USER 10001

EXPOSE 8080

# Github Action test purpose(test-only.yml).
# On production, it is effectively LOGGER_LEVEL=''.
ARG LOGGER_LEVEL=''
ENV LOGGER_LEVEL "$LOGGER_LEVEL"

WORKDIR /app
CMD ["python", "./changedetection.py", "-d", "/datastore"]
