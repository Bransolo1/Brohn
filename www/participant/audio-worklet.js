/* Original bounded input observations. Output is silent; no audio samples leave this worklet. */
class BrohnInputMeter extends AudioWorkletProcessor {
  constructor() {super(); this.blocks=0;this.samples=0;this.until=0;this.sum=0;this.count=0;this.peak=0;this.invalid=false;}
  process(inputs, outputs) {
    for(const channel of outputs[0]||[])channel.fill(0);
    const channels=inputs[0]||[];
    if(channels.length && channels[0].length){
      this.blocks++;
      for(const channel of channels)for(const x of channel){this.samples++;this.count++;if(!Number.isFinite(x)){this.invalid=true;continue;}this.sum+=x*x;this.peak=Math.max(this.peak,Math.abs(x));}
      this.until+=channels[0].length;
      // Finite accumulation can round RMS a few ulps above the observed peak;
      // preserve the mathematical RMS <= peak invariant for constant buffers.
      if(this.until>=sampleRate/10){this.port.postMessage({blocks:this.blocks,samples:this.samples,channels:channels.length,context_time_s:currentTime,rms:this.invalid?null:Math.min(this.peak,Math.sqrt(this.sum/this.count)),peak:this.invalid?null:this.peak});this.until=0;this.sum=0;this.count=0;this.peak=0;this.invalid=false;}
    }
    return true;
  }
}
registerProcessor("brohn-input-meter",BrohnInputMeter);
