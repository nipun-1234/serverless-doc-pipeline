"""S3-triggered Lambda: processes uploaded images / PDFs / text files.

- image -> 256x256 thumbnail saved to the processed bucket
- pdf   -> text extracted (first MAX_TEXT chars) saved to DynamoDB
- text  -> text preview saved to DynamoDB
"""
import io
import logging
import os
import time
import urllib.parse

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

THUMB_SIZE = (256, 256)
MAX_TEXT = 5000
IMAGE_EXT = {"jpg", "jpeg", "png", "gif", "webp"}
TEXT_EXT = {"txt", "md", "csv"}


def classify(key: str, content_type: str) -> str:
    ext = key.rsplit(".", 1)[-1].lower() if "." in key else ""
    content_type = (content_type or "").lower()
    if content_type.startswith("image/") or ext in IMAGE_EXT:
        return "image"
    if content_type == "application/pdf" or ext == "pdf":
        return "pdf"
    if content_type.startswith("text/") or ext in TEXT_EXT:
        return "text"
    return "unsupported"


def make_thumbnail(data: bytes) -> bytes:
    from PIL import Image  # imported lazily so unit tests don't need Pillow

    with Image.open(io.BytesIO(data)) as img:
        img = img.convert("RGB")
        img.thumbnail(THUMB_SIZE)
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=85)
        return out.getvalue()


def extract_pdf_text(data: bytes) -> str:
    from pypdf import PdfReader

    reader = PdfReader(io.BytesIO(data))
    parts = []
    for page in reader.pages:
        parts.append(page.extract_text() or "")
        if sum(len(p) for p in parts) >= MAX_TEXT:
            break
    return "\n".join(parts).strip()[:MAX_TEXT]


def process_object(bucket: str, key: str) -> dict:
    table = dynamodb.Table(os.environ["TABLE_NAME"])
    processed_bucket = os.environ["PROCESSED_BUCKET"]

    head = s3.head_object(Bucket=bucket, Key=key)
    content_type = head.get("ContentType", "")
    kind = classify(key, content_type)

    item = {
        "id": key,
        "filename": key.split("/", 1)[-1],
        "content_type": content_type,
        "kind": kind,
        "size": head["ContentLength"],
        "processed_at": int(time.time()),
        "status": "processed",
    }

    try:
        if kind == "unsupported":
            item["status"] = "unsupported"
        else:
            data = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
            if kind == "image":
                thumb_key = f"thumbnails/{key}.jpg"
                s3.put_object(
                    Bucket=processed_bucket,
                    Key=thumb_key,
                    Body=make_thumbnail(data),
                    ContentType="image/jpeg",
                )
                item["thumbnail_key"] = thumb_key
            elif kind == "pdf":
                item["text_preview"] = extract_pdf_text(data)
            else:
                item["text_preview"] = data.decode("utf-8", errors="replace")[:MAX_TEXT]
    except Exception as exc:  # keep going; record the failure instead of retrying forever
        logger.exception("Processing failed for %s", key)
        item["status"] = "failed"
        item["error"] = str(exc)[:300]

    table.put_item(Item=item)
    logger.info("Stored %s (%s, %s)", key, kind, item["status"])
    return item


def lambda_handler(event, context):
    results = []
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        logger.info("New object: s3://%s/%s", bucket, key)
        results.append(process_object(bucket, key)["id"])
    return {"processed": results}
