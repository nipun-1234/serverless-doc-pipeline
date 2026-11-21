# Serverless Event-Driven Image & Document Processing Pipeline



## Architecture

```
 ┌──────────┐  1. POST /upload-url   ┌─────────────┐   ┌────────────┐
 │  React   │ ─────────────────────► │ API Gateway │──►│ API Lambda │
 │   UI     │ ◄───── presigned URL ──│  (HTTP API) │   └────────────┘
 └────┬─────┘                        └─────────────┘
      │ 2. PUT file (presigned)
      ▼
 ┌───────────────┐  3. ObjectCreated  ┌──────────────────┐
 │ S3: uploads   │ ─────────────────► │ Processor Lambda │
 └───────────────┘                    └───┬──────────┬───┘
                                          │          │
                          image thumbnail ▼          ▼ metadata + extracted text
                               ┌────────────────┐  ┌──────────────┐
                               │ S3: processed  │  │  DynamoDB    │
                               └────────────────┘  └──────┬───────┘
                                                          │ 4. GET /files
                                              React UI ◄──┘
```

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | React 18 + Vite |
| API | AWS API Gateway (HTTP API) + Lambda (Python 3.12) |
| Storage | Amazon S3 (uploads + processed buckets) |
| Processing | AWS Lambda (Pillow for thumbnails, pypdf for PDF text) |
| Database | Amazon DynamoDB (on-demand) |
| IaC | Terraform |
| CI/CD | GitHub Actions (OIDC auth to AWS, no stored keys) |

## Security highlights

- Browser uploads directly to S3 using short-lived **presigned URLs** (5 min); files never pass through Lambda.
- **Least-privilege IAM**: each Lambda can only touch the exact buckets/table it needs.
- Both buckets block all public access and use server-side encryption; raw uploads expire after 30 days.
- API validates content type and sanitizes filenames; API throttling enabled.

## Project structure

```
backend/      Lambda code (processor/, api/), tests, build.sh
terraform/    All AWS infrastructure
frontend/     React + Vite UI
.github/      CI/CD workflow
```

## Setup

### Prerequisites
AWS account, AWS CLI configured (`aws configure`), Terraform >= 1.5, Python 3.12 + pip, `zip`, Node 20+.

### 1. Run tests
```bash
pip install -r backend/requirements-dev.txt
pytest backend/tests -q
```

### 2. Build & deploy the backend
```bash
./backend/build.sh
cd terraform
terraform init
terraform apply
```
Note the `api_url` output.

### 3. Run the frontend
```bash
cd frontend
cp .env.example .env     # paste api_url as VITE_API_URL
npm install
npm run dev
```
Open http://localhost:5173, upload a file, and watch it get processed.
Check Lambda logs in **CloudWatch** (`/aws/lambda/doc-pipeline-processor`).

### 4. CI/CD (GitHub Actions)
1. Create an IAM role in AWS that trusts GitHub's OIDC provider for your repo and has permissions to manage these resources.
2. Add the role ARN as repo secret `AWS_ROLE_ARN`.
3. Create an S3 bucket for Terraform state and uncomment the `backend "s3"` block in `terraform/versions.tf` (otherwise each CI run starts with empty state).
4. Push to `main` → tests run → Terraform deploys. 

### Tear down (avoid costs)
```bash
cd terraform && terraform destroy
```

## Cost
Everything used here is pay-per-use and fits comfortably in the AWS free tier for demo traffic.

## Ideas to extend
- Cognito auth, so each user sees only their files
- S3 static hosting + CloudFront for the frontend
- Textract / Rekognition for OCR and image labels
- Dead-letter queue (SQS) for failed processing
