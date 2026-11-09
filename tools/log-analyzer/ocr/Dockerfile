# tesseract for the OCR of playground analyze logs --ocr (tools/log-analyzer/ocr.py) when neither the Vision framework of
# macOS nor a local tesseract is there: built on first use, tagged with the checksum of this file
FROM debian:stable-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["tesseract"]
