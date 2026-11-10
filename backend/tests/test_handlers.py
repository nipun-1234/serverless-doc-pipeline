import importlib.util
import json
import os

import pytest

ROOT = os.path.dirname(os.path.dirname(__file__))


def load(name, folder):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, folder, "handler.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


processor = load("processor_handler", "processor")
api = load("api_handler", "api")


@pytest.mark.parametrize(
    "key,ctype,expected",
    [
        ("abc/photo.JPG", "", "image"),
        ("abc/x", "image/png", "image"),
        ("abc/doc.pdf", "application/pdf", "pdf"),
        ("abc/notes.txt", "text/plain", "text"),
        ("abc/archive.zip", "application/zip", "unsupported"),
    ],
)
def test_classify(key, ctype, expected):
    assert processor.classify(key, ctype) == expected


def test_safe_filename():
    assert api.safe_filename("../../etc/pass wd.png") == "etc_pass_wd.png"
    assert api.safe_filename("") == "file"


def test_upload_url_rejects_bad_type():
    event = {"routeKey": "POST /upload-url", "body": json.dumps({"filename": "a.exe", "contentType": "application/x-msdownload"})}
    assert api.lambda_handler(event, None)["statusCode"] == 400


def test_upload_url_ok(monkeypatch):
    monkeypatch.setenv("UPLOAD_BUCKET", "test-bucket")
    event = {"routeKey": "POST /upload-url", "body": json.dumps({"filename": "a.png", "contentType": "image/png"})}
    res = api.lambda_handler(event, None)
    assert res["statusCode"] == 200
    assert "uploadUrl" in json.loads(res["body"])


def test_unknown_route():
    assert api.lambda_handler({"routeKey": "GET /nope"}, None)["statusCode"] == 404
