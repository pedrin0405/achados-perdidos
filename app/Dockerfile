FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 1) Dependências primeiro: se só o app.py mudar, esta camada vem do cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) Código por último (muda com frequência)
COPY app.py .

# 3) Uploads + usuário sem privilégios, dono do diretório
RUN mkdir -p /app/uploads && \
    useradd --create-home appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

# Forma exec (colchetes), escutando em 0.0.0.0:5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--worker-class", "gthread", "--timeout", "60", "--graceful-timeout", "30", "--access-logfile", "-", "app:app"]
