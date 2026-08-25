package com.example.underlab_camera

import android.annotation.SuppressLint
import android.content.Context
import android.content.ContentValues
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVEVIEW_CHANNEL)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            LIVEVIEW_VIEW_TYPE,
            LiveViewFactory(channel),
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAYOUT_CHANNEL)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences(LAYOUT_PREFERENCES, Context.MODE_PRIVATE)
                when (call.method) {
                    "load" -> {
                        val ids = preferences.getStringSet(LAYOUT_IDS, emptySet()).orEmpty()
                        result.success(
                            ids.associateWith { id ->
                                listOf(
                                    preferences.getFloat("$id.x", 0f).toDouble(),
                                    preferences.getFloat("$id.y", 0f).toDouble(),
                                )
                            },
                        )
                    }
                    "save" -> {
                        val positions = call.arguments as? Map<*, *>
                        if (positions == null) {
                            result.error("invalid_layout", "Layout positions are missing", null)
                            return@setMethodCallHandler
                        }

                        val editor = preferences.edit()
                        val ids = mutableSetOf<String>()
                        positions.forEach { (rawId, rawPosition) ->
                            val id = rawId as? String ?: return@forEach
                            val coordinates = rawPosition as? List<*> ?: return@forEach
                            val x = coordinates.getOrNull(0) as? Number ?: return@forEach
                            val y = coordinates.getOrNull(1) as? Number ?: return@forEach
                            ids.add(id)
                            editor.putFloat("$id.x", x.toFloat())
                            editor.putFloat("$id.y", y.toFloat())
                        }
                        editor.putStringSet(LAYOUT_IDS, ids)
                        if (editor.commit()) {
                            result.success(true)
                        } else {
                            result.error("save_failed", "Could not save layout", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val args = call.arguments as? Map<*, *>
                val bytes = args?.get("bytes") as? ByteArray
                val filename = (args?.get("filename") as? String)
                    ?.replace(Regex("[^A-Za-z0-9._-]"), "_")
                    ?.ifBlank { "D810_image.jpg" }
                    ?: "D810_image.jpg"
                val key = (args?.get("key") as? String).orEmpty()
                if (bytes == null || bytes.isEmpty()) {
                    result.error("invalid_image", "Image bytes are missing", null)
                    return@setMethodCallHandler
                }
                val preferences = getSharedPreferences(DOWNLOAD_PREFERENCES, Context.MODE_PRIVATE)
                val dedupeKey = "image_${key.ifBlank { filename }}"
                if (preferences.getBoolean(dedupeKey, false)) {
                    result.success(mapOf("saved" to false, "alreadyExists" to true))
                    return@setMethodCallHandler
                }
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Underlab")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                    }
                    val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    }
                    val uri = contentResolver.insert(collection, values)
                        ?: throw IllegalStateException("Could not create media entry")
                    try {
                        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            ?: throw IllegalStateException("Could not open media entry")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentResolver.update(uri, ContentValues().apply {
                                put(MediaStore.Images.Media.IS_PENDING, 0)
                            }, null, null)
                        }
                        preferences.edit().putBoolean(dedupeKey, true).apply()
                        result.success(mapOf("saved" to true, "alreadyExists" to false))
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                } catch (error: Exception) {
                    result.error("save_failed", error.message, null)
                }
            }
    }

    companion object {
        const val LIVEVIEW_CHANNEL = "underlab/liveview"
        const val LIVEVIEW_VIEW_TYPE = "underlab/liveview-web"
        const val LAYOUT_CHANNEL = "underlab/layout"
        const val DOWNLOAD_CHANNEL = "underlab/downloads"
        const val LAYOUT_PREFERENCES = "underlab_layout"
        const val LAYOUT_IDS = "ids"
        const val DOWNLOAD_PREFERENCES = "underlab_downloads"
    }
}

private class LiveViewFactory(
    private val channel: MethodChannel,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        LiveViewPlatformView(context, channel)
}

private class LiveViewPlatformView(
    context: Context,
    channel: MethodChannel,
) : PlatformView {
    private val webView = createWebView(context, channel)

    override fun getView(): View = webView

    override fun dispose() {
        webView.evaluateJavascript("window.__underlabStop && window.__underlabStop();", null)
        webView.postDelayed({
            webView.removeJavascriptInterface("Underlab")
            webView.loadUrl("about:blank")
            webView.stopLoading()
            webView.destroy()
        }, 100)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(context: Context, channel: MethodChannel): WebView =
        WebView(context).apply {
            setBackgroundColor(android.graphics.Color.BLACK)
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = false
            settings.cacheMode = WebSettings.LOAD_NO_CACHE
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            addJavascriptInterface(LiveViewJavascriptBridge(channel), "Underlab")
            loadDataWithBaseURL(
                "http://192.168.8.1/",
                LIVEVIEW_HTML,
                "text/html",
                "UTF-8",
                null,
            )
        }
}

private class LiveViewJavascriptBridge(
    private val channel: MethodChannel,
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun reportFps(value: String) {
        val fps = value.toDoubleOrNull() ?: 0.0
        mainHandler.post { channel.invokeMethod("fps", fps) }
    }

    @JavascriptInterface
    fun reportFramePulse(value: String) {
        Log.i("EVF_PULSE", value.take(1000))
    }

    @JavascriptInterface
    fun reportBenchmark(value: String) {
        val chunks = value.chunked(3000)
        chunks.forEachIndexed { index, chunk ->
            Log.i("EVF_BENCH", "${index + 1}/${chunks.size} $chunk")
        }
    }

}

private const val LIVEVIEW_HTML = """
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
    #evf,#fallback{position:absolute;inset:0;display:block;width:100%;height:100%;background:#000}
    #evf{object-fit:contain}
    #fallback{object-fit:contain;visibility:hidden}
  </style>
</head>
<body>
  <canvas id="evf" width="640" height="424"></canvas>
  <img id="fallback" alt="">
  <script>
    (function () {
      var canvas = document.getElementById('evf');
      var fallback = document.getElementById('fallback');
      var socket = null;
      var pending = null;
      var decodedQueue = [];
      var lastQueuedFrameId = 0;
      var decodeBusy = false;
      var currentUrl = '';
      var frameTimes = [];
      var lastReportAt = 0;
      var reconnectTimer = 0;
      var renderTimer = 0;
      var nextRenderAt = 0;
      var TARGET_FRAME_MS = 1000 / 59.94;
      var stopped = false;
      var gl = null;
      var temporalProgram = null;
      var displayProgram = null;
      var currentTexture = null;
      var historyTextures = [];
      var historyFramebuffers = [];
      var positionBuffer = null;
      var texCoordBuffer = null;
      var historyIndex = 0;
      var historyValid = false;
      var sourceWidth = 0;
      var sourceHeight = 0;
      var fallbackMode = false;
      var lastMetadata = null;
      var renderedFrameCount = 0;
      var overwrittenFrameCount = 0;
      var repeatedFrameCount = 0;
      var benchmarkSamples = [];
      var benchmarkSent = false;
      var previousBenchmarkFrameId = 0;
      var benchmarkFrameGaps = 0;
      var BENCHMARK_WARMUP_FRAMES = 30;
      var BENCHMARK_SAMPLE_FRAMES = 60;

      var vertexShaderSource = `
        attribute vec2 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
          gl_Position = vec4(aPosition, 0.0, 1.0);
          vTexCoord = aTexCoord;
        }
      `;
      var temporalShaderSource = `
        precision mediump float;
        varying vec2 vTexCoord;
        uniform sampler2D uCurrent;
        uniform sampler2D uHistory;
        uniform float uHistoryValid;
        uniform float uDenoise;
        void main() {
          vec3 current = texture2D(uCurrent, vTexCoord).rgb;
          vec3 history = texture2D(uHistory, vTexCoord).rgb;
          vec3 delta = abs(current - history);
          float difference = max(delta.r, max(delta.g, delta.b));
          float stable = 1.0 - smoothstep(0.025, 0.115, difference);
          float historyWeight = stable * uDenoise * uHistoryValid;
          gl_FragColor = vec4(mix(current, history, historyWeight), 1.0);
        }
      `;
      var displayShaderSource = `
        precision mediump float;
        varying vec2 vTexCoord;
        uniform sampler2D uFrame;
        uniform vec2 uTexel;
        uniform float uSharpen;
        void main() {
          vec2 uv = vec2(vTexCoord.x, 1.0 - vTexCoord.y);
          vec3 center = texture2D(uFrame, uv).rgb;
          vec3 north = texture2D(uFrame, uv + vec2(0.0, -uTexel.y)).rgb;
          vec3 south = texture2D(uFrame, uv + vec2(0.0, uTexel.y)).rgb;
          vec3 west = texture2D(uFrame, uv + vec2(-uTexel.x, 0.0)).rgb;
          vec3 east = texture2D(uFrame, uv + vec2(uTexel.x, 0.0)).rgb;
          vec3 blur = (north + south + west + east) * 0.25;
          vec3 sharpened = center + (center - blur) * uSharpen;
          gl_FragColor = vec4(clamp(sharpened, 0.0, 1.0), 1.0);
        }
      `;

      function compileShader(type, source) {
        var shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
        return shader;
      }

      function createProgram(fragmentSource) {
        var program = gl.createProgram();
        gl.attachShader(program, compileShader(gl.VERTEX_SHADER, vertexShaderSource));
        gl.attachShader(program, compileShader(gl.FRAGMENT_SHADER, fragmentSource));
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
        return program;
      }

      function bindQuad(program) {
        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        var position = gl.getAttribLocation(program, 'aPosition');
        gl.enableVertexAttribArray(position);
        gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
        gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
        var texCoord = gl.getAttribLocation(program, 'aTexCoord');
        gl.enableVertexAttribArray(texCoord);
        gl.vertexAttribPointer(texCoord, 2, gl.FLOAT, false, 0, 0);
      }

      function configureTexture(texture) {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      }

      function initializeWebGl() {
        try {
          gl = canvas.getContext('webgl', {
            alpha:false,
            antialias:false,
            depth:false,
            stencil:false,
            preserveDrawingBuffer:false,
            desynchronized:true
          });
          if (!gl || !window.createImageBitmap) throw new Error('webgl unavailable');
          temporalProgram = createProgram(temporalShaderSource);
          displayProgram = createProgram(displayShaderSource);
          positionBuffer = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
          texCoordBuffer = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0,0, 1,0, 0,1, 0,1, 1,0, 1,1]), gl.STATIC_DRAW);
          currentTexture = gl.createTexture();
          configureTexture(currentTexture);
          gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
          gl.clearColor(0, 0, 0, 1);
          canvas.addEventListener('webglcontextlost', function (event) {
            event.preventDefault();
            useFallback();
          });
          return true;
        } catch (_) {
          useFallback();
          return false;
        }
      }

      function allocateHistory(width, height) {
        sourceWidth = width;
        sourceHeight = height;
        historyTextures = [];
        historyFramebuffers = [];
        for (var i = 0; i < 2; i++) {
          var texture = gl.createTexture();
          configureTexture(texture);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
          var framebuffer = gl.createFramebuffer();
          gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
          gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
          historyTextures.push(texture);
          historyFramebuffers.push(framebuffer);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        historyIndex = 0;
        historyValid = false;
      }

      function renderBitmap(bitmap) {
        if (!gl || fallbackMode) {
          bitmap.close();
          return;
        }
        if (sourceWidth !== bitmap.width || sourceHeight !== bitmap.height) {
          allocateHistory(bitmap.width, bitmap.height);
        }
        configureTexture(currentTexture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, bitmap);
        bitmap.close();

        drawCurrentTexture();
      }

      function drawCurrentTexture() {
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.clear(gl.COLOR_BUFFER_BIT);
        var sourceAspect = sourceWidth / sourceHeight;
        var outputAspect = canvas.width / canvas.height;
        var viewportWidth = canvas.width;
        var viewportHeight = canvas.height;
        if (sourceAspect > outputAspect) {
          viewportHeight = Math.round(canvas.width / sourceAspect);
        } else {
          viewportWidth = Math.round(canvas.height * sourceAspect);
        }
        gl.viewport(
          Math.round((canvas.width - viewportWidth) / 2),
          Math.round((canvas.height - viewportHeight) / 2),
          viewportWidth,
          viewportHeight
        );
        gl.useProgram(displayProgram);
        bindQuad(displayProgram);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, currentTexture);
        gl.uniform1i(gl.getUniformLocation(displayProgram, 'uFrame'), 0);
        gl.uniform2f(gl.getUniformLocation(displayProgram, 'uTexel'), 1 / sourceWidth, 1 / sourceHeight);
        gl.uniform1f(gl.getUniformLocation(displayProgram, 'uSharpen'), 0.18);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        gl.flush();
      }

      window.__underlabStop = function () {
        stopped = true;
        Underlab.reportFps('0');
        clearTimeout(reconnectTimer);
        clearTimeout(renderTimer);
        pending = null;
        decodedQueue.forEach(function (decoded) { decoded.bitmap.close(); });
        decodedQueue = [];
        if (socket) {
          socket.onclose = null;
          socket.onerror = null;
          try { socket.close(); } catch (_) {}
          socket = null;
        }
        if (currentUrl) {
          URL.revokeObjectURL(currentUrl);
          currentUrl = '';
        }
      };

      function report(now) {
        while (frameTimes.length && now - frameTimes[0] >= 1000) frameTimes.shift();
        if (now - lastReportAt >= 1000) {
          lastReportAt = now;
          Underlab.reportFps(String(frameTimes.length));
          Underlab.reportFramePulse(JSON.stringify({
            fps: frameTimes.length,
            frameId: lastQueuedFrameId,
            rendered: renderedFrameCount,
            overwritten: overwrittenFrameCount,
            decodedQueue: decodedQueue.length,
            pending: !!pending,
            fallback: fallbackMode
          }));
        }
      }

      function useFallback() {
        fallbackMode = true;
        canvas.style.visibility = 'hidden';
        fallback.style.visibility = 'visible';
      }

      function renderFallback(item) {
        var nextUrl = URL.createObjectURL(item.blob);
        var previousUrl = currentUrl;
        fallback.onload = function () {
          currentUrl = nextUrl;
          if (previousUrl) URL.revokeObjectURL(previousUrl);
          finishFrame(true, item);
        };
        fallback.onerror = function () {
          URL.revokeObjectURL(nextUrl);
          finishFrame(false, item);
        };
        fallback.src = nextUrl;
      }

      function percentile(values, ratio) {
        if (!values.length) return 0;
        var sorted = values.slice().sort(function (a, b) { return a - b; });
        return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * ratio))];
      }

      function mean(values) {
        if (!values.length) return 0;
        var total = 0;
        for (var i = 0; i < values.length; i++) total += values[i];
        return total / values.length;
      }

      function rounded(value) {
        return Math.round(value * 1000) / 1000;
      }

      function reportBenchmarkIfReady() {
        if (benchmarkSent || benchmarkSamples.length < BENCHMARK_SAMPLE_FRAMES) return;
        benchmarkSent = true;
        var fields = ['captureMs', 'transportAfterCaptureMs', 'queueMs', 'decodeMs', 'rafWaitMs', 'renderSubmitMs', 'clientMs', 'endToEndMs'];
        var summary = {};
        fields.forEach(function (field) {
          var values = benchmarkSamples.map(function (sample) { return sample[field]; });
          summary[field] = {
            mean: rounded(mean(values)),
            p50: rounded(percentile(values, 0.50)),
            p95: rounded(percentile(values, 0.95)),
            max: rounded(Math.max.apply(Math, values))
          };
        });
        var first = benchmarkSamples[0];
        var last = benchmarkSamples[benchmarkSamples.length - 1];
        var durationMs = Math.max(0.001, last.displayPerf - first.displayPerf);
        Underlab.reportBenchmark(JSON.stringify({
          version: 1,
          sampleFrames: benchmarkSamples.length,
          warmupFrames: BENCHMARK_WARMUP_FRAMES,
          outputFps: rounded((benchmarkSamples.length - 1) * 1000 / durationMs),
          frameIdGaps: benchmarkFrameGaps,
          overwrittenFrames: overwrittenFrameCount,
          repeatedFrames: repeatedFrameCount,
          fallbackMode: fallbackMode,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          outputWidth: canvas.width,
          outputHeight: canvas.height,
          summary: summary,
          frames: benchmarkSamples
        }));
      }

      function finishFrame(rendered, item) {
        if (rendered !== false) {
          var now = performance.now();
          frameTimes.push(now);
          report(now);
          renderedFrameCount++;
          if (item && renderedFrameCount > BENCHMARK_WARMUP_FRAMES && benchmarkSamples.length < BENCHMARK_SAMPLE_FRAMES) {
            var meta = item.meta || {};
            var frameId = Number(meta.frameId || 0);
            if (previousBenchmarkFrameId > 0 && frameId > previousBenchmarkFrameId + 1) {
              benchmarkFrameGaps += frameId - previousBenchmarkFrameId - 1;
            }
            previousBenchmarkFrameId = frameId;
            benchmarkSamples.push({
              frame: benchmarkSamples.length + 1,
              frameId: frameId,
              bytes: Number(meta.bytes || item.bytes || 0),
              captureMs: rounded(Number(meta.captureMs || 0)),
              transportAfterCaptureMs: rounded(item.receivedEpoch - Number(meta.captureDoneAt || item.receivedEpoch)),
              queueMs: rounded(item.decodeStartPerf - item.receivedPerf),
              decodeMs: rounded(item.decodeDonePerf - item.decodeStartPerf),
              rafWaitMs: rounded(item.renderStartPerf - item.decodeDonePerf),
              renderSubmitMs: rounded(item.renderDonePerf - item.renderStartPerf),
              clientMs: rounded(now - item.receivedPerf),
              endToEndMs: rounded(Date.now() - Number(meta.startedAt || Date.now())),
              displayPerf: rounded(now)
            });
            reportBenchmarkIfReady();
          }
        }
        if (fallbackMode) {
          decodeBusy = false;
          renderLatest();
        }
      }

      function renderLatest() {
        if (decodeBusy || !pending || stopped) return;
        decodeBusy = true;
        var item = pending;
        pending = null;
        item.decodeStartPerf = performance.now();
        if (fallbackMode) {
          renderFallback(item);
          return;
        }
        createImageBitmap(item.blob).then(function (bitmap) {
          item.decodeDonePerf = performance.now();
          decodeBusy = false;
          decodedQueue.push({bitmap: bitmap, item: item});
          if (decodedQueue.length > 3) {
            decodedQueue.shift().bitmap.close();
            overwrittenFrameCount++;
          }
          renderLatest();
        }).catch(function () {
          useFallback();
          renderFallback(item);
        });
      }

      function renderLoop() {
        var loopNow = performance.now();
        report(loopNow);
        if (!stopped && !fallbackMode && decodedQueue.length) {
          var decoded = decodedQueue.shift();
          try {
            decoded.item.renderStartPerf = performance.now();
            renderBitmap(decoded.bitmap);
            decoded.item.renderDonePerf = performance.now();
            finishFrame(true, decoded.item);
          } catch (_) {
            decoded.bitmap.close();
            useFallback();
          }
        }
        if (!stopped) {
          nextRenderAt += TARGET_FRAME_MS;
          var now = performance.now();
          if (nextRenderAt < now - TARGET_FRAME_MS) nextRenderAt = now;
          renderTimer = setTimeout(renderLoop, Math.max(0, nextRenderAt - now));
        }
      }

      function queueFrame(data) {
        var metadata = lastMetadata;
        lastMetadata = null;
        var frameId = Number(metadata && metadata.frameId || 0);
        if (frameId > 0 && frameId <= lastQueuedFrameId) return;
        if (frameId > 0) lastQueuedFrameId = frameId;
        if (pending) overwrittenFrameCount++;
        pending = {
          blob: new Blob([data], {type:'image/jpeg'}),
          bytes: data.byteLength || 0,
          meta: metadata,
          receivedPerf: performance.now(),
          receivedEpoch: Date.now(),
          decodeStartPerf: 0,
          decodeDonePerf: 0,
          renderStartPerf: 0,
          renderDonePerf: 0
        };
        renderLatest();
      }

      function isMetadata(data) {
        if (!(data instanceof ArrayBuffer) || data.byteLength !== 52) return false;
        var view = new Uint8Array(data, 0, 4);
        return view[0] === 0x44 && view[1] === 0x38 && view[2] === 0x4c && view[3] === 0x35;
      }

      function readU64(view, offset) {
        return view.getUint32(offset, false) * 4294967296 + view.getUint32(offset + 4, false);
      }

      function parseMetadata(data) {
        var view = new DataView(data);
        return {
          frameId: view.getUint32(8, false),
          startedAt: readU64(view, 12),
          captureDoneAt: readU64(view, 20),
          totalMs: view.getUint32(28, false),
          captureMs: view.getUint32(32, false),
          bytes: view.getUint32(36, false),
          wireTotalUs: view.getUint32(40, false),
          firstPacketUs: view.getUint32(44, false),
          parseUs: view.getUint32(48, false)
        };
      }

      var httpBase = 'http://192.168.8.1';

      function connect() {
        if (stopped) return;
        clearTimeout(reconnectTimer);
        try {
          socket = new WebSocket('ws://192.168.8.1:8191/');
          socket.binaryType = 'arraybuffer';
          socket.onmessage = function (event) {
            if (typeof event.data === 'string') return;
            if (isMetadata(event.data)) {
              lastMetadata = parseMetadata(event.data);
              return;
            }
            queueFrame(event.data);
          };
          socket.onclose = function () {
            Underlab.reportFps('0');
            if (!stopped) {
              reconnectTimer = setTimeout(recoverAndReconnect, 500);
            }
          };
          socket.onerror = function () { try { socket.close(); } catch (_) {} };
        } catch (_) {
          if (!stopped) reconnectTimer = setTimeout(recoverAndReconnect, 500);
        }
      }

      function recoverAndReconnect() {
        if (stopped) return;
        fetch(httpBase + '/cgi-bin/action-v21?action=recover', {cache:'no-store'})
          .then(function (response) { return response.json(); })
          .then(function (payload) {
            if (stopped) return;
            if (payload && (payload.liveView === true || payload.status === 'liveview_on')) {
              connect();
            } else {
              // LIVE_STOP is global.  Do not let this WebView revive a session
              // that another client intentionally stopped.
              stopped = true;
              Underlab.reportFps('0');
            }
          })
          .catch(function () {
            if (!stopped) reconnectTimer = setTimeout(recoverAndReconnect, 1000);
          });
      }
      initializeWebGl();
      nextRenderAt = performance.now();
      renderTimer = setTimeout(renderLoop, 0);
      // Flutter creates this view only after status-v21 confirms that the
      // server is already live. Opening the app must never issue live-on.
      connect();
    }());
  </script>
</body>
</html>
"""
