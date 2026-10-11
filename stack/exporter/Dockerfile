# build: docker build --build-arg PYTHON_IMAGE=<digest> -t graylog-exporter:<tag> stack/exporter   (precisa de ./rclone ao lado)
ARG PYTHON_IMAGE=python:3.12-slim
FROM ${PYTHON_IMAGE}
COPY rclone /usr/local/bin/rclone
COPY glexport /app/glexport
COPY entrypoint.sh /entrypoint.sh
WORKDIR /app
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "glexport.main"]
