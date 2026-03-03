FROM python:3.11-slim

WORKDIR /app

# System deps for building native extensions (if needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App source
COPY . .

# Pre-populate the solution cache using the mock solver.
# When TexasSolver binary is available at build time, replace --limit
# or mount the binary to get real solutions.
RUN python batch_solve.py --limit 50

# Expose the FastAPI port
EXPOSE 8000

# Environment defaults (can be overridden at runtime)
ENV DATABASE_URL="sqlite+aiosqlite:///./poker_hands.db"
ENV CACHE_DB_PATH="gto_cache.db"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
