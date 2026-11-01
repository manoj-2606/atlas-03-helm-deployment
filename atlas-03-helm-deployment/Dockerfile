# =============================================================================
# atlas-platform-app — Multi-stage production build
# Build context: atlas-platform-app/ (via multi-repo checkout)
# Dockerfile location: atlas-03-helm-deployment/ (this repo)
#
# Pipeline builds with:
#   docker build \
#     -f <project-repo>/Dockerfile \
#     -t $ACR_SERVER/atlas-platform-app:$TAG \
#     <app-repo>/
# =============================================================================

# Stage 1: Install dependencies (thrown away after)
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --timeout=120 --retries=10 \
    --prefix=/install -r requirements.txt

# Stage 2: Production image — clean, minimal, non-root
FROM python:3.12-slim

# Create non-root user (no shell, no home dir)
RUN groupadd -r atlas && useradd -r -g atlas -d /app -s /sbin/nologin atlas

WORKDIR /app

# Copy installed packages from builder (no pip, no cache in final image)
COPY --from=builder /install /usr/local

# Copy application source
COPY app/ ./app/

# Drop privileges
USER atlas

EXPOSE 8000

# Health check for container runtime (not K8s — K8s uses its own probes)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]