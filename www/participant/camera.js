/* Optional, explicitly consented recording. Encoded time is not inferred from callback time. */
(() => {
  "use strict";
  const CHUNK_BYTES = 2 * 1024 * 1024, BUFFER_BYTES = 64 * 1024 * 1024;
  const uid = () => `camera-${crypto.randomUUID()}`;
  const finite = value => typeof value === "number" && Number.isFinite(value) ? value : null;
  const decimal = value => Number(value).toFixed(6);
  const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), value => value.toString(16).padStart(2, "0")).join("");
  const base64 = bytes => {
    let text = ""; const source = new Uint8Array(bytes);
    for (let i = 0; i < source.length; i += 32768) text += String.fromCharCode(...source.subarray(i, i + 32768));
    return btoa(text);
  };
  class BrohnCamera {
    constructor({policy, runId, api, instanceId, timeOrigin, getStep = () => null, onFailure = () => {}, monitor = false}) {
      Object.assign(this, {policy, runId, api, instanceId, timeOrigin, getStep, onFailure, monitor});
      this.stream = null; this.recorder = null; this.segment = null; this.video = null; this.db = null;
      this.writeChain = Promise.resolve(); this.uploading = null; this.stopPromise = null;
      this.frames = []; this.unretainedFrames = 0; this.damaged = false; this.stopping = false;
      this.prepareGeneration = 0;
      this.previewFrames = 0; this.lastFrame = null; this.previewTimes = [];
      this.audioObservation = null; this.audioHistory = []; this.listeners = new Set();
    }
    subscribe(fn) {this.listeners.add(fn); fn(this.snapshot()); return () => this.listeners.delete(fn);}
    notify() {for (const fn of this.listeners) {try {fn(this.snapshot());} catch (_) {}}}
    snapshot() {
      const video = this.stream?.getVideoTracks()[0], audio = this.stream?.getAudioTracks()[0], a = this.audioObservation;
      return {capture_id: this.segment?.capture_id || null, track_generation: this.prepareGeneration,
        video: {live: video?.readyState === "live", enabled: video?.enabled === true, muted: video?.muted ?? true,
          frames: this.previewFrames, last_frame_ms: this.lastFrame?.now_ms ?? null, width: this.lastFrame?.width ?? this.settings?.width ?? null, height: this.lastFrame?.height ?? this.settings?.height ?? null},
        audio: {requested: this.policy.audio === true, live: audio?.readyState === "live", enabled: audio?.enabled === true, muted: audio?.muted ?? true,
          state: this.audioContext?.state || "unavailable", blocks: a?.blocks || 0, samples: a?.samples || 0, last_block_ms: a?.last_block_ms ?? null,
          sample_rate: this.audioContext?.sampleRate ?? null, channels: a?.channels || 0, rms: a?.rms ?? null, peak: a?.peak ?? null},
        recording: {browser_sequence: (this.segment?.next_sequence || 1)-1, browser_bytes: this.segment?.total_bytes || 0,
          acked_sequence: this.segment?.acked_sequence || 0, acked_bytes: this.segment?.acked_bytes || 0}};
    }
    async monitorAudio(generation) {
      if (!this.monitor || !this.policy.audio) return;
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) return;
      const context = new Context(); this.audioContext = context;
      try {
        await context.audioWorklet.addModule("audio-worklet.js");
        if (generation !== this.prepareGeneration) {await context.close(); return;}
        const source = context.createMediaStreamSource(this.stream), meter = new AudioWorkletNode(context, "brohn-input-meter", {outputChannelCount: [1]});
        this.audioSource = source; this.audioMeter = meter;
        meter.port.onmessage = ({data}) => {
          if (generation !== this.prepareGeneration || !this.stream) return;
          // Preserve processing-clock age when main-thread message delivery is delayed.
          this.audioObservation = {...data, last_block_ms: Math.max(0,performance.now()-Math.max(0,context.currentTime-data.context_time_s)*1000)};
          this.audioHistory.push(this.audioObservation); if (this.audioHistory.length > 50) this.audioHistory.shift(); this.notify();
        };
        source.connect(meter); meter.connect(context.destination); await context.resume();
      } catch (_) {if (context.state !== "closed") await context.close();}
    }
    clock() {return {id: "browser-monotonic", unit: "ms", value: decimal(performance.now()), instance_id: this.instanceId, time_origin_ms: Number(this.timeOrigin).toFixed(3)};}
    async open() {
      if (this.db) return;
      this.db = await new Promise((resolve, reject) => {
        const request = indexedDB.open("brohn-camera-journal", 1);
        request.onupgradeneeded = () => {
          const segments = request.result.createObjectStore("segments", {keyPath: "capture_id"}); segments.createIndex("run_id", "run_id");
          const chunks = request.result.createObjectStore("chunks", {keyPath: "key"}); chunks.createIndex("capture_id", "capture_id");
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(new Error("Camera recording needs local browser storage. Free some storage or contact the researcher."));
      });
    }
    transaction(stores, mode, action) {
      return new Promise((resolve, reject) => {
        const tx = this.db.transaction(stores, mode); let result;
        try {result = action(tx);} catch (error) {tx.abort(); reject(error); return;}
        tx.oncomplete = () => resolve(result?.result);
        tx.onerror = tx.onabort = () => reject(new Error("Camera data could not be saved in this browser. The recording has been stopped; previously received data remain saved."));
      });
    }
    async saveSegment() {
      const copy = structuredClone(this.segment);
      await this.transaction(["segments"], "readwrite", tx => tx.objectStore("segments").put(copy));
    }
    async prepare(video) {
      const generation = ++this.prepareGeneration;
      const cancelled = () => new DOMException("Camera setup was cancelled.", "AbortError");
      await this.open();
      if (generation !== this.prepareGeneration) throw cancelled();
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder || !crypto.subtle) throw new Error("This browser cannot record this study's camera data. Use a supported secure browser or contact the researcher.");
      const types = this.policy.audio ? ["video/webm;codecs=vp8,opus", "video/webm;codecs=vp9,opus", "video/webm"] : ["video/webm;codecs=vp8", "video/webm;codecs=vp9", "video/webm"];
      this.mimeType = types.find(type => MediaRecorder.isTypeSupported(type));
      if (!this.mimeType) throw new Error("This browser does not support the study's WebM recording profile.");
      // Called only by the participant's explicit Enable camera action.
      try {
        const stream = await navigator.mediaDevices.getUserMedia({video: {width: {ideal: this.policy.width, max: this.policy.width}, height: {ideal: this.policy.height, max: this.policy.height}, frameRate: {ideal: this.policy.frame_rate, max: this.policy.frame_rate}}, audio: this.policy.audio === true});
        // Permission can resolve after Stop or Decline. Never attach those late tracks.
        if (generation !== this.prepareGeneration) {for (const track of stream.getTracks()) track.stop(); throw cancelled();}
        this.stream = stream;
        const track = this.stream.getVideoTracks()[0];
        if (!track || track.readyState !== "live") throw new Error("No live camera track is available.");
        const observed = track.getSettings();
        this.settings = {width: finite(observed.width), height: finite(observed.height), frame_rate: finite(observed.frameRate), audio: this.stream.getAudioTracks().length > 0};
        if (!this.settings.width || !this.settings.height || !this.settings.frame_rate || this.settings.audio !== this.policy.audio) throw new Error("The camera did not provide the study's requested channel configuration.");
        this.video = video; video.muted = true; video.playsInline = true; video.srcObject = this.stream; await video.play();
        if (generation !== this.prepareGeneration) throw cancelled();
        if (this.monitor) {
          this.previewFrames = 0; this.previewTimes = []; this.lastFrame = null; this.audioObservation = null; this.audioHistory = [];
          this.stopping = false; this.collectFrames();
          for (const t of this.stream.getTracks()) for (const name of ["mute", "unmute", "ended"]) t.addEventListener(name, () => this.notify());
          await this.monitorAudio(generation); if (generation !== this.prepareGeneration) throw cancelled(); this.notify();
        }
      } catch (error) {if (generation === this.prepareGeneration) this.releaseTracks(); throw error;}
    }
    async acknowledgeStart() {
      const receipt = await this.api(`/api/camera_start/${encodeURIComponent(this.runId)}`, this.segment.start_request);
      const status = this.segment.start_request.consented ? "recording" : "declined";
      if (receipt.capture_id !== this.segment.capture_id || receipt.status !== status) throw new Error("The camera setup receipt does not match this recording decision.");
      this.segment.start_receipt = receipt;
      if (this.segment.status === "starting") this.segment.status = status;
      await this.saveSegment(); return receipt;
    }
    async makeSegment(consented, reason = null) {
      await this.open();
      if (this.segment) {
        if (this.segment.start_request.consented !== consented || this.segment.start_request.reason !== reason || this.segment.finish_request)
          throw new Error("This visit already has a different camera decision. Contact the researcher before restarting.");
        if (this.segment.start_receipt) return this.segment.start_receipt;
        return this.acknowledgeStart();
      }
      const captureId = uid();
      this.segment = {capture_id: captureId, run_id: this.runId, status: "starting", next_sequence: 1, total_bytes: 0, acked_sequence: 0, acked_bytes: 0,
        start_request: {capture_id: captureId, consented, clock: this.clock(), mime_type: consented ? this.mimeType : null,
          settings: consented ? this.settings : null, reason, operation_id: crypto.randomUUID()}, finish_request: null, receipt: null};
      await this.saveSegment();
      return this.acknowledgeStart();
    }
    async decline(reason = "participant_declined") {this.releaseTracks(); return this.makeSegment(false, reason);}
    collectFrames() {
      if (!this.video?.requestVideoFrameCallback || this.stopping) return;
      this.frameHandle = this.video.requestVideoFrameCallback((now, metadata) => {
        if (this.stopping) return;
        const step = this.getStep();
        const frame = {now_ms: finite(now), media_time_s: finite(metadata.mediaTime), presentation_time_ms: finite(metadata.presentationTime),
          expected_display_time_ms: finite(metadata.expectedDisplayTime), capture_time_ms: finite(metadata.captureTime),
          presented_frames: finite(metadata.presentedFrames), width: finite(metadata.width), height: finite(metadata.height),
          step_id: step?.id || null, phase: step?.phase || null};
        this.previewFrames++; this.lastFrame = frame; this.previewTimes.push(now);
        while (this.previewTimes.length > 300 || this.previewTimes[0] < now-5000) this.previewTimes.shift();
        if (this.recorder?.state === "recording") {if (this.frames.length < 500) this.frames.push(frame); else this.unretainedFrames++;}
        this.collectFrames();
      });
    }
    async start() {
      if (!this.stream) throw new Error("Enable the camera before beginning the study.");
      try {
        if (this.recorder) throw new Error("This camera recording has already begun.");
        await this.makeSegment(true);
        if (!this.stream || this.segment.finish_request) throw new DOMException("Camera setup was cancelled.", "AbortError");
        this.recorder = new MediaRecorder(this.stream, {mimeType: this.mimeType, videoBitsPerSecond: 600000, ...(this.policy.audio ? {audioBitsPerSecond: 64000} : {})});
        this.stopping = false; this.damaged = false;
        this.recorder.addEventListener("dataavailable", event => this.acceptBlob(event));
        this.recorder.addEventListener("error", event => this.fail(event.error || new Error("Camera recording failed.")));
        for (const track of this.stream.getTracks()) track.addEventListener("ended", () => {if (!this.stopping) this.fail(new Error("A camera or microphone track stopped during the study."));});
        const started = new Promise((resolve, reject) => {
          this.recorder.addEventListener("start", resolve, {once: true}); this.recorder.addEventListener("error", reject, {once: true});
        });
        this.frames = []; this.unretainedFrames = 0;
        this.recorder.start(1000); if (!this.monitor) this.collectFrames();
        this.durationTimer = setTimeout(() => this.fail(new Error("The recording reached the study's camera duration limit.")), this.policy.max_duration_s * 1000);
        await started;
      } catch (error) {this.releaseTracks(); throw error;}
    }
    acceptBlob(event) {
      if (!event.data?.size) return;
      const observed = {callback_ms: decimal(performance.now()), event_timecode_ms: finite(event.timecode), frames: this.frames.splice(0), unretained_frame_callbacks: this.unretainedFrames};
      this.unretainedFrames = 0;
      // One recorder Blob may exceed a timeslice target. Split bytes, not independent containers.
      const work = this.writeChain.then(async () => {
        if (this.segment.total_bytes + event.data.size > this.policy.max_bytes || this.segment.total_bytes - this.segment.acked_bytes + event.data.size > BUFFER_BYTES)
          throw new Error("Camera recording exceeded its data or offline storage limit. Previously saved chunks are retained; the recording is incomplete.");
        const chunks = [];
        for (let offset = 0; offset < event.data.size; offset += CHUNK_BYTES) {
          const blob = event.data.slice(offset, offset + CHUNK_BYTES), bytes = await blob.arrayBuffer();
          const sequence = this.segment.next_sequence + chunks.length;
          chunks.push({key: `${this.segment.capture_id}:${sequence}`, capture_id: this.segment.capture_id, sequence, blob,
            sha256: await hash(bytes), size: blob.size, operation_id: crypto.randomUUID(),
            observation: offset === 0 ? observed : {...observed, frames: [], unretained_frame_callbacks: 0}});
        }
        const next = {...this.segment, next_sequence: this.segment.next_sequence + chunks.length, total_bytes: this.segment.total_bytes + event.data.size};
        await this.transaction(["segments", "chunks"], "readwrite", tx => {
          for (const chunk of chunks) tx.objectStore("chunks").add(chunk);
          tx.objectStore("segments").put(next);
        });
        this.segment = next; this.notify();
      });
      this.writeChain = work.catch(error => {this.fail(error);});
      void work.then(() => this.flush()).catch(error => {if (error.permanent) this.fail(error);});
    }
    fail(error) {
      if (this.failureNotified) return;
      this.failureNotified = true; this.damaged = true;
      // Stop capture immediately; UI callback retains study interruption and retries.
      this.releaseTracks();
      try {this.onFailure(error);} catch (_) { /* Preserve journal even if UI reporting fails. */ }
    }
    releaseTracks() {
      this.prepareGeneration++;
      clearTimeout(this.durationTimer);
      if (this.frameHandle !== undefined && this.video?.cancelVideoFrameCallback) this.video.cancelVideoFrameCallback(this.frameHandle);
      this.frameHandle = undefined;
      if (this.stream) for (const track of this.stream.getTracks()) track.stop();
      this.stream = null;
      this.audioSource?.disconnect(); this.audioMeter?.disconnect();
      if (this.audioContext && this.audioContext.state !== "closed") void this.audioContext.close();
      this.notify();
    }
    async stop(outcome = "completed", reason = null) {
      if (this.stopPromise) return this.stopPromise;
      this.stopPromise = (async () => {
        if (!this.segment || this.segment.start_request.consented === false) {this.releaseTracks(); return;}
        if (this.segment.finish_request) {this.releaseTracks(); return;}
        this.stopping = true; clearTimeout(this.durationTimer);
        if (this.recorder && this.recorder.state !== "inactive") {
          await new Promise(resolve => {
            this.recorder.addEventListener("stop", resolve, {once: true});
            try {this.recorder.stop();} catch (_) {this.damaged = true; resolve();}
          });
        }
        this.releaseTracks();
        const finalise = this.writeChain.then(async () => {
          const next = {...this.segment, status: "stopped", finish_request: {capture_id: this.segment.capture_id, final_sequence: this.segment.next_sequence-1, total_bytes: this.segment.total_bytes,
            outcome: this.damaged && outcome === "completed" ? "interrupted" : outcome, container_complete: !this.damaged && this.segment.total_bytes > 0,
            clock: this.clock(), reason, operation_id: crypto.randomUUID()}};
          await this.transaction(["segments"], "readwrite", tx => tx.objectStore("segments").put(next));
          this.segment = next;
        });
        this.writeChain = finalise.catch(error => {this.fail(error);}); await finalise;
        // Upload errors do not change the frozen finish request or erase local bytes.
      })();
      return this.stopPromise;
    }
    closeDelivery() {
      // Keep the journal and any final recorder blob. A researcher decision is
      // neither a participant finish receipt nor permission to purge local data.
      this.deliveryClosed = true;
      this.releaseTracks();
    }
    async flush() {
      if (this.deliveryClosed) return;
      if (!this.segment || this.segment.receipt) return this.segment?.receipt;
      if (this.segment.status === "declined" && this.segment.start_receipt) return this.segment.start_receipt;
      if (this.uploading) return this.uploading;
      this.uploading = (async () => {
        if (!this.segment.start_receipt) {
          await this.acknowledgeStart();
        }
        if (this.segment.start_request.consented === false) return this.segment.start_receipt;
        while (!this.deliveryClosed && this.segment.acked_sequence < this.segment.next_sequence-1) {
          const sequence = this.segment.acked_sequence + 1;
          const chunk = await this.transaction(["chunks"], "readonly", tx => tx.objectStore("chunks").get(`${this.segment.capture_id}:${sequence}`));
          if (!chunk) throw new Error("A camera chunk is missing from this browser's journal. The study cannot claim complete recording.");
          const body = {capture_id: chunk.capture_id, sequence, sha256: chunk.sha256, data_base64: base64(await chunk.blob.arrayBuffer()), observation: chunk.observation, operation_id: chunk.operation_id};
          const receipt = await this.api(`/api/camera_chunk/${encodeURIComponent(this.runId)}`, body);
          if (!Number.isSafeInteger(receipt.acked_sequence) || receipt.acked_sequence < sequence) throw new Error("The service did not acknowledge this camera chunk.");
          if (this.monitor && (receipt.capture_id !== this.segment.capture_id || receipt.status !== "saved" ||
              receipt.acked_sequence >= this.segment.next_sequence || !Number.isSafeInteger(receipt.total_bytes) ||
              receipt.total_bytes < this.segment.acked_bytes + chunk.size || receipt.total_bytes > this.segment.total_bytes))
            throw new Error("The recording receipt has inconsistent identity or byte totals. Local bytes remain saved.");
          // Serialize metadata updates with incoming recorder blobs to avoid losing a counter.
          const update = this.writeChain.then(async () => {
            const next = {...this.segment, acked_sequence: sequence, acked_bytes: this.segment.acked_bytes + chunk.size};
            await this.transaction(["segments", "chunks"], "readwrite", tx => {tx.objectStore("chunks").delete(chunk.key); tx.objectStore("segments").put(next);});
            this.segment = next; this.notify();
          });
          this.writeChain = update.catch(error => {this.fail(error);}); await update;
        }
        if (!this.deliveryClosed && this.segment.finish_request && !this.segment.receipt) {
          this.segment.receipt = await this.api(`/api/camera_finish/${encodeURIComponent(this.runId)}`, this.segment.finish_request);
          await this.saveSegment();
        }
        return this.segment.receipt;
      })();
      try {return await this.uploading;} finally {this.uploading = null;}
    }
    async recover() {
      await this.open();
      const records = await this.transaction(["segments"], "readonly", tx => tx.objectStore("segments").index("run_id").getAll(this.runId));
      if (!records.length) return {found: false};
      let interrupted = false, declined = false;
      for (const saved of records) {
        this.segment = saved;
        if (saved.start_request.consented === false) {await this.flush(); declined = true; continue;}
        if (!saved.finish_request) {
          interrupted = true; this.segment.status = "stopped";
          // The original clock instance remains explicit; a new page must not invent an ending time in that clock.
          this.segment.finish_request = {capture_id: saved.capture_id, final_sequence: saved.next_sequence-1, total_bytes: saved.total_bytes,
            outcome: "interrupted", container_complete: false, clock: saved.start_request.clock, reason: "page_reload_recording_end_unobserved", operation_id: crypto.randomUUID()};
          await this.saveSegment();
        } else if (saved.finish_request.outcome !== "completed") interrupted = true;
        await this.flush();
      }
      return {found: true, interrupted, declined};
    }
    async purge() {
      if (!this.db) return;
      const records = await this.transaction(["segments"], "readonly", tx => tx.objectStore("segments").index("run_id").getAll(this.runId));
      for (const saved of records) if (saved.receipt || (saved.status === "declined" && saved.start_receipt))
        await this.transaction(["segments"], "readwrite", tx => tx.objectStore("segments").delete(saved.capture_id));
      this.db.close(); this.db = null;
    }
  }
  window.BrohnCamera = BrohnCamera;
})();
