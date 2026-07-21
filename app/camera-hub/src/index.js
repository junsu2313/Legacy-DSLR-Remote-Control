function json(data, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  return new Response(JSON.stringify(data), {
    ...init,
    headers,
  });
}

function normalizeFileName(name) {
  return String(name || "unnamed.jpg")
    .replace(/[^A-Za-z0-9._-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 120) || "unnamed.jpg";
}

function normalizeCameraId(cameraId, fallbackPrefix) {
  return String(cameraId || fallbackPrefix || "camera")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64) || "camera";
}

function isoLike(raw) {
  const value = raw ? new Date(raw) : new Date();
  if (Number.isNaN(value.getTime())) {
    return new Date();
  }
  return value;
}

function makeObjectKey(cameraId, capturedAt, filename) {
  const year = String(capturedAt.getUTCFullYear());
  const month = String(capturedAt.getUTCMonth() + 1).padStart(2, "0");
  const day = String(capturedAt.getUTCDate()).padStart(2, "0");
  const stamp = capturedAt.toISOString().replace(/[:.]/g, "-");
  return `${cameraId}/${year}/${month}/${day}/${stamp}_${filename}`;
}

function metadataFromObject(object) {
  const custom = object.customMetadata || {};
  return {
    id: object.key,
    key: object.key,
    size: object.size,
    uploadedAt: object.uploaded?.toISOString?.() || null,
    etag: object.httpEtag || null,
    cameraId: custom.cameraId || "",
    filename: custom.filename || "",
    capturedAt: custom.capturedAt || "",
    contentType: custom.contentType || "",
  };
}

function readBearerToken(request) {
  const auth = request.headers.get("authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function authorize(request, env) {
  const expected = String(env.CAMERA_UPLOAD_TOKEN || "").trim();
  if (!expected) {
    return true;
  }
  return readBearerToken(request) === expected;
}

async function handleUpload(request, env) {
  if (!authorize(request, env)) {
    return json({ ok: false, error: "unauthorized" }, { status: 401 });
  }

  const url = new URL(request.url);
  const filename = normalizeFileName(
    request.headers.get("x-file-name") || url.searchParams.get("filename")
  );
  const cameraId = normalizeCameraId(
    request.headers.get("x-camera-id") || url.searchParams.get("cameraId"),
    env.CAMERA_PREFIX
  );
  const capturedAt = isoLike(
    request.headers.get("x-captured-at") || url.searchParams.get("capturedAt")
  );
  const contentType = request.headers.get("content-type") || "image/jpeg";

  if (!contentType.toLowerCase().startsWith("image/jpeg")) {
    return json({ ok: false, error: "jpeg_only" }, { status: 415 });
  }

  const body = request.body;
  if (!body) {
    return json({ ok: false, error: "empty_body" }, { status: 400 });
  }

  const key = makeObjectKey(cameraId, capturedAt, filename);
  await env.CAMERA_BUCKET.put(key, body, {
    httpMetadata: {
      contentType: "image/jpeg",
    },
    customMetadata: {
      cameraId,
      filename,
      capturedAt: capturedAt.toISOString(),
      contentType: "image/jpeg",
    },
  });

  const stored = await env.CAMERA_BUCKET.head(key);
  return json({
    ok: true,
    file: {
      id: key,
      key,
      cameraId,
      filename,
      capturedAt: capturedAt.toISOString(),
      size: stored?.size || null,
      contentType: "image/jpeg",
    },
  });
}

async function handleList(request, env) {
  const url = new URL(request.url);
  const cameraId = normalizeCameraId(
    url.searchParams.get("cameraId"),
    env.CAMERA_PREFIX
  );
  const limitParam = Number(url.searchParams.get("limit") || "50");
  const limit = Math.min(Math.max(limitParam || 50, 1), 200);

  const listed = await env.CAMERA_BUCKET.list({
    prefix: `${cameraId}/`,
    limit,
  });

  const files = listed.objects
    .map(metadataFromObject)
    .sort((a, b) => String(b.uploadedAt || "").localeCompare(String(a.uploadedAt || "")));

  return json({
    ok: true,
    files,
    truncated: listed.truncated,
    cursor: listed.cursor || null,
  });
}

async function handleDownload(_request, env, key) {
  const object = await env.CAMERA_BUCKET.get(key);
  if (!object) {
    return json({ ok: false, error: "not_found" }, { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "no-store");
  headers.set(
    "content-disposition",
    `attachment; filename="${normalizeFileName(object.customMetadata?.filename || key.split("/").pop() || "image.jpg")}"`
  );

  return new Response(object.body, {
    status: 200,
    headers,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/api/camera/upload") {
      return handleUpload(request, env);
    }

    if (request.method === "GET" && url.pathname === "/api/camera/files") {
      return handleList(request, env);
    }

    const downloadMatch = url.pathname.match(/^\/api\/camera\/files\/(.+)\/download$/);
    if (request.method === "GET" && downloadMatch) {
      return handleDownload(request, env, decodeURIComponent(downloadMatch[1]));
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "underlab-camera-hub" });
    }

    return json({ ok: false, error: "not_found" }, { status: 404 });
  },
};
