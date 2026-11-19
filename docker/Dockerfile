FROM python:3.13-slim
RUN useradd --create-home appuser
COPY . /app
RUN pip install --no-cache-dir -r /app/requirements.txt
EXPOSE 8000
USER appuser
HEALTHCHECK CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000')" || exit 1
CMD ["python", "/app/app.py"]