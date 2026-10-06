FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY amtab_gtfsrt.py .
ENV PORT=8080 CACHE_SECONDS=20
EXPOSE 8080
USER nobody
HEALTHCHECK --interval=60s --timeout=5s CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health',timeout=4).status==200 else 1)"
CMD ["python", "amtab_gtfsrt.py"]
