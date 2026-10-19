FROM python:3.13-slim
RUN useradd --uid 10001 --create-home mono
WORKDIR /app
COPY server.py /app/server.py
USER mono
ENV MONO_BIND=0.0.0.0 MONO_CATALOG=/data/catalog.json PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["python", "server.py"]
