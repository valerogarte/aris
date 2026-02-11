FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml poetry.lock README.md /app/
COPY youtube_transcript_api /app/youtube_transcript_api

RUN pip install .

ENTRYPOINT ["youtube_transcript_api"]
CMD ["--help"]
