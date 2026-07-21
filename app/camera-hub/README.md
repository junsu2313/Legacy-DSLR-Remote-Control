# Underlab Camera Hub

JPEG-only camera hub for practical field use.

## Endpoints

- `POST /api/camera/upload`
- `GET /api/camera/files?cameraId=d810`
- `GET /api/camera/files/{id}/download`

## Upload request

Send the JPEG bytes as the raw body.

Required headers:

- `Content-Type: image/jpeg`
- `X-File-Name: DSC_1234.JPG`
- `X-Camera-Id: d810`
- `X-Captured-At: 2026-07-01T08:30:00Z`

Optional auth:

- `Authorization: Bearer <token>`

If `CAMERA_UPLOAD_TOKEN` is not configured, auth is skipped.

## Local dev

```bash
npm install
npm run dev
```

## Deploy

```bash
npm run deploy
```

## Required Cloudflare resources

- R2 bucket: `underlab-camera-hub`
- Worker secret: `CAMERA_UPLOAD_TOKEN` (optional for first test)
