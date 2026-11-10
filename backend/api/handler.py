"""HTTP API Lambda.

POST /upload-url  -> presigned S3 PUT url for the browser to upload directly
GET  /files       -> list processed files (with presigned thumbnail urls)
"""
import json
import os
import re
import uuid
from decimal import Decimal

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

ALLOWED_TYPES = {
    "image/jpeg", "image/png", "image/gif", "image/webp",
    "application/pdf", "text/plain", "text/markdown", "text/csv",
}
MAX_FILENAME = 100
URL_TTL = 300


def _json_default(o):
    if isinstance(o, Decimal):
        return int(o) if o % 1 == 0 else float(o)
    raise TypeError


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=_json_default),
    }


def safe_filename(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._-]", "_", name or "")[:MAX_FILENAME]
    return name.strip("._") or "file"


def create_upload_url(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON"})

    content_type = body.get("contentType", "")
    if content_type not in ALLOWED_TYPES:
        return _response(400, {"error": f"Unsupported type. Allowed: {sorted(ALLOWED_TYPES)}"})

    key = f"{uuid.uuid4().hex}/{safe_filename(body.get('filename'))}"
    url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": os.environ["UPLOAD_BUCKET"],
            "Key": key,
            "ContentType": content_type,
        },
        ExpiresIn=URL_TTL,
    )
    return _response(200, {"uploadUrl": url, "key": key})


def list_files(_event):
    table = dynamodb.Table(os.environ["TABLE_NAME"])
    items, kwargs = [], {}
    while True:
        page = table.scan(**kwargs)
        items.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

    for item in items:
        if item.get("thumbnail_key"):
            item["thumbnail_url"] = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": os.environ["PROCESSED_BUCKET"], "Key": item["thumbnail_key"]},
                ExpiresIn=URL_TTL,
            )
    items.sort(key=lambda i: i.get("processed_at", 0), reverse=True)
    return _response(200, {"files": items})


def lambda_handler(event, context):
    route = event.get("routeKey", "")
    if route == "POST /upload-url":
        return create_upload_url(event)
    if route == "GET /files":
        return list_files(event)
    return _response(404, {"error": "Not found"})
