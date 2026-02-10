# Whisper.cpp Integration Patterns for Python ASR Services

**Research Document** - Adding whisper.cpp as an ASR Provider  
**Date**: February 2026  
**Status**: Research Summary

---

## Executive Summary

This document provides a comprehensive analysis of integration patterns for incorporating `whisper.cpp` into Python-based ASR (Automatic Speech Recognition) services. We examine four primary integration approaches, macOS Metal/GPU acceleration strategies, streaming capabilities, and provide concrete implementation recommendations.

---

## 1. Integration Options

### 1.1 Python Bindings (pywhispercpp)

**Overview**: Native Python bindings using pybind11 that wrap the C++ whisper.cpp API.

#### Installation

```bash
# Pre-built wheels (CPU only)
pip install pywhispercpp

# From source with optimizations
pip install git+https://github.com/abdeladim-s/pywhispercpp

# With Metal support (macOS)
WHISPER_METAL=1 pip install git+https://github.com/abdeladim-s/pywhispercpp --no-cache --force-reinstall

# With CoreML support (macOS Neural Engine)
WHISPER_COREML=1 pip install git+https://github.com/abdeladim-s/pywhispercpp --no-cache --force-reinstall

# With CUDA support (NVIDIA)
GGML_CUDA=1 pip install git+https://github.com/abdeladim-s/pywhispercpp --no-cache --force-reinstall
```

#### Basic Usage

```python
from pywhispercpp.model import Model

# Initialize model (auto-downloads if needed)
model = Model('base.en', n_threads=4)

# Transcribe audio file
segments = model.transcribe('audio.wav')
for segment in segments:
    print(f"[{segment.start:.2f} -> {segment.end:.2f}] {segment.text}")
```

#### Advanced Usage with Callbacks

```python
from pywhispercpp.model import Model

class TranscriptionHandler:
    def __init__(self):
        self.results = []
    
    def on_new_segment(self, segment):
        """Called for each new segment during transcription"""
        self.results.append({
            'start': segment.start,
            'end': segment.end,
            'text': segment.text,
            'tokens': segment.tokens
        })
        print(f"New segment: {segment.text}")

# Use callback for real-time-like processing
handler = TranscriptionHandler()
model = Model(
    'base.en',
    print_realtime=False,
    print_progress=False,
    n_threads=6
)

segments = model.transcribe(
    'audio.wav',
    new_segment_callback=handler.on_new_segment,
    language='en',
    translate=False
)
```

#### Direct C-API Access (Advanced)

```python
import _pywhispercpp as pwcpp

# Low-level access to whisper.cpp C API
ctx = pwcpp.whisper_init_from_file('path/to/ggml-model.bin')

# Access full whisper.h API
params = pwcpp.whisper_full_default_params(pwcpp.WHISPER_SAMPLING_GREEDY)
params.n_threads = 4
params.language = b'en'

# Process audio (numpy array required)
# pwcpp.whisper_full(ctx, params, audio_data, len(audio_data))
```

**Pros**:
- Native performance (no subprocess overhead)
- Full access to whisper.cpp parameters
- Support for callbacks during transcription
- Model reuse across multiple transcriptions
- Works with multiple backends (Metal, CUDA, CoreML)

**Cons**:
- Requires compilation from source for GPU acceleration
- Version compatibility issues with whisper.cpp updates
- Limited error handling for C++ exceptions
- Memory management considerations

---

### 1.2 Subprocess Communication

**Overview**: Execute whisper.cpp CLI as a subprocess and communicate via stdin/stdout.

#### Basic Implementation

```python
import subprocess
import os
import json
from pathlib import Path
from typing import Optional, Dict, Any

class WhisperCppSubprocess:
    """whisper.cpp integration via subprocess"""
    
    def __init__(
        self,
        binary_path: str = "./whisper-cli",
        model_path: str = "./models/ggml-base.en.bin",
        n_threads: int = 4
    ):
        self.binary_path = binary_path
        self.model_path = model_path
        self.n_threads = n_threads
        
        # Verify binary and model exist
        if not os.path.exists(binary_path):
            raise FileNotFoundError(f"Binary not found: {binary_path}")
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model not found: {model_path}")
    
    def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
        output_format: str = "json",
        **kwargs
    ) -> Dict[str, Any]:
        """
        Transcribe audio file using whisper.cpp CLI.
        
        Args:
            audio_path: Path to audio file (WAV, 16-bit, 16kHz)
            language: Language code (e.g., 'en', 'auto')
            output_format: Output format ('json', 'txt', 'srt', 'vtt')
            **kwargs: Additional whisper.cpp parameters
        """
        # Build command
        cmd = [
            self.binary_path,
            "-m", self.model_path,
            "-f", audio_path,
            "-t", str(self.n_threads),
            "--output-json" if output_format == "json" else f"--output-{output_format}"
        ]
        
        # Add optional parameters
        if language:
            cmd.extend(["-l", language])
        
        if kwargs.get("translate"):
            cmd.append("--translate")
        
        if kwargs.get("no_timestamps"):
            cmd.append("-nt")
        
        if kwargs.get("print_special"):
            cmd.append("-ps")
        
        # Execute
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=kwargs.get("timeout", 300)
            )
            
            if result.returncode != 0:
                raise RuntimeError(f"whisper.cpp error: {result.stderr}")
            
            # Parse JSON output
            if output_format == "json":
                # Output is written to file by whisper-cli
                json_path = f"{audio_path}.json"
                if os.path.exists(json_path):
                    with open(json_path, 'r') as f:
                        return json.load(f)
                else:
                    # Fallback: parse stdout
                    return self._parse_stdout(result.stdout)
            
            return {"text": result.stdout, "raw_output": result.stdout}
            
        except subprocess.TimeoutExpired:
            raise RuntimeError("Transcription timed out")
        except Exception as e:
            raise RuntimeError(f"Transcription failed: {e}")
    
    def _parse_stdout(self, stdout: str) -> Dict[str, Any]:
        """Parse stdout when JSON file is not available"""
        lines = stdout.strip().split('\n')
        segments = []
        
        for line in lines:
            # Parse format: [00:00:00.000 --> 00:00:05.000] text
            if line.startswith('[') and '-->' in line:
                parts = line.split(']', 1)
                if len(parts) == 2:
                    timestamps = parts[0][1:]  # Remove [
                    text = parts[1].strip()
                    
                    time_parts = timestamps.split('-->')
                    if len(time_parts) == 2:
                        segments.append({
                            'start': self._time_to_seconds(time_parts[0].strip()),
                            'end': self._time_to_seconds(time_parts[1].strip()),
                            'text': text
                        })
        
        return {
            'segments': segments,
            'text': ' '.join(s['text'] for s in segments)
        }
    
    @staticmethod
    def _time_to_seconds(time_str: str) -> float:
        """Convert HH:MM:SS.mmm to seconds"""
        parts = time_str.split(':')
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        return 0.0
```

#### Streaming Output Implementation

```python
import subprocess
import threading
import queue
from typing import Callable, Optional

class StreamingWhisperSubprocess:
    """Subprocess-based whisper.cpp with streaming output"""
    
    def __init__(
        self,
        binary_path: str = "./whisper-cli",
        model_path: str = "./models/ggml-base.en.bin"
    ):
        self.binary_path = binary_path
        self.model_path = model_path
        self._process: Optional[subprocess.Popen] = None
        self._output_queue: queue.Queue = queue.Queue()
        self._error_queue: queue.Queue = queue.Queue()
    
    def transcribe_streaming(
        self,
        audio_path: str,
        callback: Callable[[str], None],
        language: str = "en"
    ):
        """
        Stream transcription results line by line.
        
        Args:
            audio_path: Path to audio file
            callback: Function called with each line of output
            language: Language code
        """
        cmd = [
            self.binary_path,
            "-m", self.model_path,
            "-f", audio_path,
            "-l", language,
            "--print-realtime", "true",
            "--print-progress", "true"
        ]
        
        self._process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # Line buffered
            universal_newlines=True
        )
        
        # Start reader threads
        stdout_thread = threading.Thread(
            target=self._read_stream,
            args=(self._process.stdout, callback)
        )
        stderr_thread = threading.Thread(
            target=self._read_stream,
            args=(self._process.stderr, lambda x: None, True)
        )
        
        stdout_thread.start()
        stderr_thread.start()
        
        # Wait for completion
        self._process.wait()
        stdout_thread.join()
        stderr_thread.join()
    
    def _read_stream(
        self,
        stream,
        callback: Callable[[str], None],
        is_error: bool = False
    ):
        """Read from stream line by line"""
        for line in iter(stream.readline, ''):
            line = line.strip()
            if line:
                if is_error:
                    self._error_queue.put(line)
                else:
                    callback(line)
        stream.close()
    
    def terminate(self):
        """Terminate the subprocess"""
        if self._process and self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
```

**Pros**:
- Simple implementation, no compilation required
- Full isolation (process crash doesn't affect main app)
- Easy to upgrade whisper.cpp independently
- Works with any whisper.cpp build/configuration

**Cons**:
- High overhead per transcription (process startup)
- Complex inter-process communication
- No shared model state between calls
- Requires careful process lifecycle management
- JSON output files need cleanup

---

### 1.3 Server Mode (HTTP API)

**Overview**: Run whisper.cpp as a persistent HTTP server with OpenAI-compatible API.

#### Building the Server

```bash
# Clone whisper.cpp
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

# Build with server example
cmake -B build -DWHISPER_BUILD_EXAMPLES=ON
cmake --build build -j --config Release

# Download model
./models/download-ggml-model.sh base.en

# Start server
./build/bin/whisper-server \
    --model models/ggml-base.en.bin \
    --host 127.0.0.1 \
    --port 8080 \
    --threads 4 \
    --convert  # Auto-convert audio formats
```

#### Python Client Implementation

```python
import requests
import json
from typing import Optional, Dict, Any, BinaryIO
from pathlib import Path


class WhisperCppClient:
    """OpenAI-compatible client for whisper.cpp server"""
    
    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8080",
        api_key: Optional[str] = None
    ):
        self.base_url = base_url.rstrip('/')
        self.headers = {}
        if api_key:
            self.headers["Authorization"] = f"Bearer {api_key}"
    
    def transcribe(
        self,
        audio_file: BinaryIO,
        model: str = "whisper",
        language: Optional[str] = None,
        prompt: Optional[str] = None,
        response_format: str = "json",
        temperature: float = 0.0,
        timestamp_granularities: Optional[list] = None
    ) -> Dict[str, Any]:
        """
        Transcribe audio using OpenAI-compatible API.
        
        Matches OpenAI's /v1/audio/transcriptions endpoint.
        """
        url = f"{self.base_url}/v1/audio/transcriptions"
        
        files = {
            'file': ('audio.wav', audio_file, 'audio/wav')
        }
        
        data = {
            'model': model,
            'response_format': response_format,
            'temperature': temperature
        }
        
        if language:
            data['language'] = language
        if prompt:
            data['prompt'] = prompt
        
        response = requests.post(
            url,
            files=files,
            data=data,
            headers=self.headers,
            timeout=300
        )
        
        response.raise_for_status()
        
        if response_format == "json":
            return response.json()
        elif response_format == "verbose_json":
            return response.json()
        elif response_format in ["text", "srt", "vtt"]:
            return {"text": response.text}
        
        return response.json()
    
    def transcribe_file(
        self,
        file_path: str,
        **kwargs
    ) -> Dict[str, Any]:
        """Convenience method to transcribe a file path"""
        with open(file_path, 'rb') as f:
            return self.transcribe(f, **kwargs)
    
    def health_check(self) -> bool:
        """Check if server is healthy"""
        try:
            response = requests.get(
                f"{self.base_url}/health",
                timeout=5
            )
            return response.status_code == 200
        except requests.RequestException:
            return False


# Alternative: Using official OpenAI client
from openai import OpenAI

class WhisperCppOpenAIClient:
    """Use official OpenAI client with whisper.cpp server"""
    
    def __init__(self, base_url: str = "http://127.0.0.1:8080/v1"):
        self.client = OpenAI(
            base_url=base_url,
            api_key="not-needed"  # whisper.cpp doesn't require auth
        )
    
    def transcribe(self, audio_path: str, **kwargs):
        """Transcribe using OpenAI client"""
        with open(audio_path, 'rb') as audio:
            transcript = self.client.audio.transcriptions.create(
                model="whisper",  # Ignored by whisper.cpp
                file=audio,
                **kwargs
            )
        return transcript
```

#### Advanced Server Configuration

```python
import subprocess
import time
import requests
from typing import Optional

class WhisperCppServer:
    """Manage whisper.cpp server lifecycle"""
    
    def __init__(
        self,
        binary_path: str = "./whisper-server",
        model_path: str = "./models/ggml-base.en.bin",
        host: str = "127.0.0.1",
        port: int = 8080,
        threads: int = 4,
        gpu_layers: Optional[int] = None
    ):
        self.binary_path = binary_path
        self.model_path = model_path
        self.host = host
        self.port = port
        self.threads = threads
        self.gpu_layers = gpu_layers
        self._process: Optional[subprocess.Popen] = None
    
    def start(self, timeout: int = 30):
        """Start the whisper.cpp server"""
        cmd = [
            self.binary_path,
            "--model", self.model_path,
            "--host", self.host,
            "--port", str(self.port),
            "--threads", str(self.threads),
            "--convert"  # Auto-convert audio
        ]
        
        self._process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Wait for server to be ready
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                response = requests.get(
                    f"http://{self.host}:{self.port}/health",
                    timeout=1
                )
                if response.status_code == 200:
                    print(f"Server ready on {self.host}:{self.port}")
                    return
            except requests.RequestException:
                time.sleep(0.5)
        
        self.stop()
        raise RuntimeError("Server failed to start within timeout")
    
    def stop(self):
        """Stop the server"""
        if self._process:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
    
    def __enter__(self):
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()


# Usage example
if __name__ == "__main__":
    with WhisperCppServer(
        model_path="models/ggml-base.en.bin",
        port=8080
    ) as server:
        client = WhisperCppClient("http://127.0.0.1:8080")
        
        result = client.transcribe_file("audio.wav")
        print(result["text"])
```

**Pros**:
- Process isolation with persistent model
- OpenAI-compatible API (drop-in replacement)
- Supports multiple clients
- Language-agnostic (any HTTP client works)
- Auto-convert audio formats

**Cons**:
- Network overhead (localhost HTTP)
- Requires server process management
- Limited streaming support (HTTP chunked)
- No native callback mechanism

---

### 1.4 ctypes/CFFI Direct Binding

**Overview**: Direct FFI binding without Python wrapper library (roll your own).

```python
import ctypes
import os
import numpy as np
from pathlib import Path

class WhisperCTypes:
    """Direct ctypes binding to whisper.cpp shared library"""
    
    def __init__(self, lib_path: str = "./libwhisper.so"):
        """
        Load whisper.cpp shared library.
        
        Build shared library first:
        cmake -B build -DBUILD_SHARED_LIBS=ON
        cmake --build build
        """
        self.lib = ctypes.CDLL(lib_path)
        self._setup_types()
        self.ctx = None
    
    def _setup_types(self):
        """Configure ctypes type signatures"""
        # whisper_init_from_file
        self.lib.whisper_init_from_file.argtypes = [ctypes.c_char_p]
        self.lib.whisper_init_from_file.restype = ctypes.c_void_p
        
        # whisper_full
        self.lib.whisper_full.argtypes = [
            ctypes.c_void_p,  # ctx
            ctypes.c_void_p,  # params
            ctypes.POINTER(ctypes.c_float),  # samples
            ctypes.c_int      # n_samples
        ]
        self.lib.whisper_full.restype = ctypes.c_int
        
        # whisper_free
        self.lib.whisper_free.argtypes = [ctypes.c_void_p]
        self.lib.whisper_free.restype = None
        
        # whisper_full_n_segments
        self.lib.whisper_full_n_segments.argtypes = [ctypes.c_void_p]
        self.lib.whisper_full_n_segments.restype = ctypes.c_int
        
        # whisper_full_get_segment_text
        self.lib.whisper_full_get_segment_text.argtypes = [
            ctypes.c_void_p,  # ctx
            ctypes.c_int      # i_segment
        ]
        self.lib.whisper_full_get_segment_text.restype = ctypes.c_char_p
    
    def load_model(self, model_path: str):
        """Load a model"""
        self.ctx = self.lib.whisper_init_from_file(
            model_path.encode('utf-8')
        )
        if not self.ctx:
            raise RuntimeError("Failed to load model")
    
    def transcribe(self, audio: np.ndarray) -> list:
        """
        Transcribe audio samples.
        
        Args:
            audio: float32 array of samples, 16kHz
        """
        if self.ctx is None:
            raise RuntimeError("Model not loaded")
        
        # Convert to ctypes
        samples = audio.astype(np.float32)
        samples_ctypes = samples.ctypes.data_as(ctypes.POINTER(ctypes.c_float))
        n_samples = ctypes.c_int(len(samples))
        
        # TODO: Setup params struct (complex in ctypes)
        params = None
        
        # Run inference
        result = self.lib.whisper_full(
            self.ctx,
            params,
            samples_ctypes,
            n_samples
        )
        
        if result != 0:
            raise RuntimeError(f"Transcription failed: {result}")
        
        # Extract results
        n_segments = self.lib.whisper_full_n_segments(self.ctx)
        segments = []
        
        for i in range(n_segments):
            text = self.lib.whisper_full_get_segment_text(self.ctx, i)
            segments.append(text.decode('utf-8') if text else "")
        
        return segments
    
    def close(self):
        """Free resources"""
        if self.ctx:
            self.lib.whisper_free(self.ctx)
            self.ctx = None
```

**Pros**:
- Maximum control and minimal overhead
- No external Python dependencies
- Direct memory management

**Cons**:
- Complex to implement and maintain
- Type safety issues
- Platform-specific (shared library building)
- Not recommended for production use

---

## 2. Metal/GPU Acceleration on macOS

### 2.1 Build Options

#### Basic Metal Support

```bash
# Standard Metal build
cmake -B build -DGGML_METAL=ON
cmake --build build -j --config Release

# Verify Metal is active
./build/bin/whisper-cli -f samples/jfk.wav 2>&1 | grep -E "(Metal|GPU)"
# Should show: Metal device: Apple M*
```

#### CoreML Support (Neural Engine)

```bash
# 1. Install dependencies
pip install ane_transformers openai-whisper coremltools

# 2. Generate CoreML encoder model
./models/generate-coreml-model.sh base.en
# Creates: models/ggml-base.en-encoder.mlmodelc

# 3. Build with CoreML
cmake -B build -DWHISPER_COREML=ON
cmake --build build -j --config Release

# 4. Run (auto-detects CoreML model)
./build/bin/whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav
```

### 2.2 Python Integration with Metal

```python
import subprocess
import platform

def get_metal_build_flags():
    """Get CMake flags for macOS Metal builds"""
    system = platform.system()
    machine = platform.machine()
    
    flags = ["-DGGML_METAL=ON"]
    
    if system == "Darwin" and machine == "arm64":
        # Apple Silicon specific optimizations
        flags.extend([
            "-DCMAKE_OSX_ARCHITECTURES=arm64",
            "-DGGML_METAL_USE_BF16=ON"  # BF16 for M2/M3
        ])
    
    return flags


class MetalWhisperCpp:
    """whisper.cpp with Metal acceleration on macOS"""
    
    def __init__(self, model_path: str, n_threads: int = 4):
        self.model_path = model_path
        self.n_threads = n_threads
        self.binary = "./whisper-cli"
        
        # Verify Metal is available
        self._verify_metal()
    
    def _verify_metal(self):
        """Check Metal support"""
        result = subprocess.run(
            [self.binary, "-h"],
            capture_output=True,
            text=True
        )
        # Check if built with Metal
        if "Metal" not in result.stderr and "metal" not in result.stdout:
            print("Warning: Binary may not have Metal support")
    
    def transcribe(self, audio_path: str) -> dict:
        """Transcribe with Metal"""
        cmd = [
            self.binary,
            "-m", self.model_path,
            "-f", audio_path,
            "-t", str(self.n_threads),
            "--output-json"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        # Parse output
        # Metal builds show: "Metal device: Apple M*" in stderr
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "using_metal": "Metal device" in result.stderr
        }
```

### 2.3 Performance Expectations

| Model | CPU (M1 Pro) | Metal GPU | CoreML (ANE) | Speedup |
|-------|-------------|-----------|--------------|---------|
| tiny | 0.3x RTF | 0.8x RTF | 1.5x RTF | 5x |
| base | 0.6x RTF | 1.2x RTF | 2.5x RTF | 4x |
| small | 2.0x RTF | 4.0x RTF | 7.0x RTF | 3.5x |
| medium | 6.0x RTF | 12.0x RTF | 20.0x RTF | 3.3x |
| large-v3 | 15.0x RTF | 30.0x RTF | 50.0x RTF | 3.3x |

*RTF = Real-Time Factor (lower is faster). RTF < 1.0 means faster than real-time.*

### 2.4 Memory Usage Patterns

| Model | Disk Size | RAM (CPU) | VRAM (Metal) |
|-------|-----------|-----------|--------------|
| tiny | 75 MB | ~273 MB | ~300 MB |
| base | 142 MB | ~388 MB | ~450 MB |
| small | 466 MB | ~852 MB | ~1.0 GB |
| medium | 1.5 GB | ~2.1 GB | ~2.5 GB |
| large | 2.9 GB | ~3.9 GB | ~4.5 GB |

---

## 3. Streaming/Realtime Support

### 3.1 whisper.cpp Streaming Mode

whisper.cpp includes a streaming example (`whisper-stream`) for real-time transcription:

```bash
# Build with SDL2 for audio capture
cmake -B build -DWHISPER_SDL2=ON
cmake --build build -j --config Release

# Run streaming transcription
./build/bin/whisper-stream \
    -m ./models/ggml-base.en.bin \
    -t 8 \
    --step 500 \      # Process step in ms
    --length 5000     # Audio buffer length in ms
```

### 3.2 Python Streaming Implementation

```python
import asyncio
import websockets
import json
import numpy as np
from collections import deque
from typing import Callable, Optional

class WhisperStreamingClient:
    """
    WebSocket client for whisper.cpp streaming server.
    
    Uses sliding window approach for real-time transcription.
    """
    
    def __init__(
        self,
        ws_url: str = "ws://127.0.0.1:8080",
        chunk_duration: float = 1.0,  # seconds
        overlap: float = 0.5  # seconds overlap between chunks
    ):
        self.ws_url = ws_url
        self.chunk_duration = chunk_duration
        self.overlap = overlap
        self.sample_rate = 16000
        self.ws = None
        
        # Audio buffer
        self.buffer = deque(maxlen=int(self.sample_rate * 10))  # 10s max
        self.confirmed_text = ""
        self.pending_text = ""
    
    async def connect(self):
        """Connect to WebSocket server"""
        self.ws = await websockets.connect(self.ws_url)
    
    async def send_audio_chunk(self, audio_data: np.ndarray):
        """Send audio chunk to server"""
        if self.ws is None:
            raise RuntimeError("Not connected")
        
        # Convert to int16 PCM
        pcm_data = (audio_data * 32767).astype(np.int16).tobytes()
        
        # Send as base64 or binary
        await self.ws.send(pcm_data)
        
        # Receive result
        response = await self.ws.recv()
        result = json.loads(response)
        
        return result
    
    async def stream_transcribe(
        self,
        audio_generator,
        callback: Optional[Callable[[str, bool], None]] = None
    ):
        """
        Stream transcribe from audio generator.
        
        Args:
            audio_generator: Async generator yielding audio chunks
            callback: Called with (text, is_final) for each update
        """
        await self.connect()
        
        try:
            async for chunk in audio_generator:
                # Add to buffer
                self.buffer.extend(chunk)
                
                # Process when we have enough data
                if len(self.buffer) >= self.chunk_duration * self.sample_rate:
                    # Extract window
                    window = np.array(self.buffer)[-int(self.chunk_duration * self.sample_rate):]
                    
                    result = await self.send_audio_chunk(window)
                    
                    # Handle incremental transcription
                    text = result.get("text", "")
                    is_final = result.get("is_final", False)
                    
                    if is_final:
                        self.confirmed_text += text
                        self.pending_text = ""
                    else:
                        self.pending_text = text
                    
                    if callback:
                        full_text = self.confirmed_text + self.pending_text
                        callback(full_text, is_final)
                    
        finally:
            await self.ws.close()


# Alternative: Using LocalAgreement algorithm for incremental transcription
class LocalAgreementStreaming:
    """
    Implement LocalAgreement policy for streaming transcription.
    
    Based on: "Turning Whisper into Real-Time Transcription System"
    https://arxiv.org/abs/2307.14743
    """
    
    def __init__(
        self,
        model,
        min_chunk_size: float = 1.0,
        agreement_count: int = 2
    ):
        self.model = model
        self.min_chunk_size = min_chunk_size
        self.agreement_count = agreement_count
        self.audio_buffer = np.array([], dtype=np.float32)
        self.previous_outputs = []
        self.confirmed_output = ""
    
    def process_chunk(self, new_audio: np.ndarray) -> dict:
        """
        Process new audio chunk with LocalAgreement policy.
        
        Returns confirmed text and any updates.
        """
        # Append new audio
        self.audio_buffer = np.concatenate([self.audio_buffer, new_audio])
        
        # Run transcription on full buffer
        segments = self.model.transcribe(self.audio_buffer)
        current_output = segments[0].text if segments else ""
        
        # Store output history
        self.previous_outputs.append(current_output)
        if len(self.previous_outputs) > self.agreement_count:
            self.previous_outputs.pop(0)
        
        # Apply LocalAgreement: find longest common prefix
        if len(self.previous_outputs) >= self.agreement_count:
            confirmed = self._longest_common_prefix(self.previous_outputs)
            
            # Check if we can confirm more text
            if len(confirmed) > len(self.confirmed_output):
                new_confirmed = confirmed[len(self.confirmed_output):]
                self.confirmed_output = confirmed
                
                # Trim buffer at sentence boundary if possible
                self._trim_buffer()
                
                return {
                    "confirmed": self.confirmed_output,
                    "new": new_confirmed,
                    "pending": current_output[len(confirmed):]
                }
        
        return {
            "confirmed": self.confirmed_output,
            "new": "",
            "pending": current_output[len(self.confirmed_output):]
        }
    
    def _longest_common_prefix(self, strings: list) -> str:
        """Find longest common prefix of multiple strings"""
        if not strings:
            return ""
        
        prefix = strings[0]
        for s in strings[1:]:
            while not s.startswith(prefix):
                prefix = prefix[:-1]
                if not prefix:
                    return ""
        return prefix
    
    def _trim_buffer(self):
        """Trim audio buffer to keep only unconfirmed portion"""
        # Implementation depends on word-level timestamps
        pass
```

### 3.3 VAD Integration

```python
import numpy as np
from typing import Callable, Optional

try:
    import webrtcvad
    HAS_WEBRTC_VAD = True
except ImportError:
    HAS_WEBRTC_VAD = False


class VADProcessor:
    """
    Voice Activity Detection for streaming transcription.
    
    Uses WebRTC VAD or Silero VAD.
    """
    
    def __init__(
        self,
        aggressiveness: int = 2,  # 0-3, higher = more aggressive
        frame_duration: int = 30,  # ms (10, 20, or 30)
        silence_threshold_ms: int = 1000
    ):
        if not HAS_WEBRTC_VAD:
            raise ImportError("webrtcvad required. pip install webrtcvad")
        
        self.vad = webrtcvad.Vad(aggressiveness)
        self.frame_duration = frame_duration
        self.silence_threshold_ms = silence_threshold_ms
        self.sample_rate = 16000
        
        self.is_speaking = False
        self.silence_duration = 0
        self.speech_buffer = []
    
    def process_frame(self, audio_frame: bytes) -> Optional[bytes]:
        """
        Process audio frame and detect speech segments.
        
        Returns speech segment when silence is detected after speech.
        """
        is_speech = self.vad.is_speech(audio_frame, self.sample_rate)
        
        if is_speech:
            if not self.is_speaking:
                self.is_speaking = True
                self.silence_duration = 0
            self.speech_buffer.append(audio_frame)
        else:
            if self.is_speaking:
                self.silence_duration += self.frame_duration
                
                if self.silence_duration >= self.silence_threshold_ms:
                    # Speech segment complete
                    segment = b"".join(self.speech_buffer)
                    self.speech_buffer = []
                    self.is_speaking = False
                    self.silence_duration = 0
                    return segment
                else:
                    # Include silence in buffer (for natural pauses)
                    self.speech_buffer.append(audio_frame)
        
        return None
    
    def flush(self) -> Optional[bytes]:
        """Get remaining speech buffer"""
        if self.speech_buffer:
            segment = b"".join(self.speech_buffer)
            self.speech_buffer = []
            self.is_speaking = False
            return segment
        return None


# Integration with whisper.cpp
class VADWhisperStreamer:
    """Streaming transcription with VAD"""
    
    def __init__(
        self,
        whisper_model,
        vad_aggressiveness: int = 2,
        on_transcription: Optional[Callable[[str], None]] = None
    ):
        self.model = whisper_model
        self.vad = VADProcessor(aggressiveness=vad_aggressiveness)
        self.on_transcription = on_transcription
    
    def process_audio(self, audio_chunk: bytes):
        """Process incoming audio chunk"""
        segment = self.vad.process_frame(audio_chunk)
        
        if segment:
            # Convert to numpy
            audio_np = np.frombuffer(segment, dtype=np.int16).astype(np.float32) / 32767.0
            
            # Transcribe
            result = self.model.transcribe(audio_np)
            text = result[0].text if result else ""
            
            if self.on_transcription:
                self.on_transcription(text)
            
            return text
        
        return None
```

---

## 4. Implementation Approaches Comparison

### 4.1 Pros/Cons Summary

| Approach | Latency | Throughput | Complexity | Maintainability | Best For |
|----------|---------|------------|------------|-----------------|----------|
| **Python Bindings** | Low | High | Medium | Medium | Production services, repeated transcriptions |
| **Subprocess** | High | Low | Low | High | One-off transcriptions, scripting |
| **Server Mode** | Medium | High | Low | High | Multi-client services, microservices |
| **ctypes/CFFI** | Lowest | Highest | High | Low | Custom requirements, research |

### 4.2 Recommended Approach for Production

**For most production ASR services**, we recommend:

1. **Primary: Python Bindings (pywhispercpp)**
   - Best performance-to-complexity ratio
   - Native integration with Python async frameworks
   - Support for all acceleration backends

2. **Alternative: Server Mode**
   - When service isolation is required
   - For multi-language clients
   - When OpenAI API compatibility is needed

### 4.3 Error Handling and Recovery

```python
import logging
from enum import Enum
from dataclasses import dataclass
from typing import Optional
import time

logger = logging.getLogger(__name__)


class ASRError(Exception):
    """Base ASR error"""
    pass


class ModelLoadError(ASRError):
    """Failed to load model"""
    pass


class TranscriptionError(ASRError):
    """Transcription failed"""
    pass


@dataclass
class ASRResult:
    """Structured ASR result"""
    text: str
    segments: list
    language: str
    duration: float
    confidence: Optional[float] = None
    error: Optional[str] = None


class RobustWhisperProvider:
    """
    Production-ready whisper.cpp provider with error handling.
    """
    
    def __init__(
        self,
        model_path: str,
        n_threads: int = 4,
        max_retries: int = 3,
        retry_delay: float = 1.0
    ):
        self.model_path = model_path
        self.n_threads = n_threads
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.model = None
        self._load_model()
    
    def _load_model(self):
        """Load model with retry logic"""
        from pywhispercpp.model import Model
        
        for attempt in range(self.max_retries):
            try:
                logger.info(f"Loading model (attempt {attempt + 1})...")
                self.model = Model(
                    self.model_path,
                    n_threads=self.n_threads,
                    print_progress=False,
                    print_realtime=False
                )
                logger.info("Model loaded successfully")
                return
            except Exception as e:
                logger.error(f"Model load failed: {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(self.retry_delay * (attempt + 1))
                else:
                    raise ModelLoadError(f"Failed to load model after {self.max_retries} attempts")
    
    def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
        **kwargs
    ) -> ASRResult:
        """
        Transcribe with comprehensive error handling.
        """
        if self.model is None:
            raise TranscriptionError("Model not loaded")
        
        for attempt in range(self.max_retries):
            try:
                segments = self.model.transcribe(
                    audio_path,
                    language=language,
                    **kwargs
                )
                
                # Build result
                text = " ".join(s.text for s in segments)
                return ASRResult(
                    text=text,
                    segments=[
                        {
                            "start": s.start,
                            "end": s.end,
                            "text": s.text
                        }
                        for s in segments
                    ],
                    language=language or "auto",
                    duration=segments[-1].end if segments else 0
                )
                
            except Exception as e:
                logger.error(f"Transcription error (attempt {attempt + 1}): {e}")
                
                if attempt < self.max_retries - 1:
                    time.sleep(self.retry_delay * (attempt + 1))
                    # Try to reload model on certain errors
                    if "memory" in str(e).lower() or "corrupted" in str(e).lower():
                        self._load_model()
                else:
                    return ASRResult(
                        text="",
                        segments=[],
                        language=language or "auto",
                        duration=0,
                        error=str(e)
                    )
    
    def health_check(self) -> bool:
        """Verify provider is healthy"""
        return self.model is not None
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        # Cleanup if needed
        self.model = None
```

---

## 5. Integration Example for EchoPanel

```python
# server/asr/whisper_cpp_provider.py

from typing import AsyncIterator, Optional
import numpy as np
from .base import BaseASRProvider


class WhisperCppProvider(BaseASRProvider):
    """
    whisper.cpp ASR provider for EchoPanel.
    
    Supports both file-based and streaming transcription.
    """
    
    def __init__(self, config: dict):
        super().__init__(config)
        
        self.model_path = config.get("model_path", "models/ggml-base.en.bin")
        self.n_threads = config.get("n_threads", 4)
        self.language = config.get("language")
        self.use_metal = config.get("use_metal", True)
        
        # Initialize model
        self._init_model()
    
    def _init_model(self):
        """Initialize whisper.cpp model"""
        try:
            from pywhispercpp.model import Model
            
            # Build parameters based on config
            params = {
                "n_threads": self.n_threads,
                "print_progress": False,
                "print_realtime": False
            }
            
            self.model = Model(self.model_path, **params)
            self.logger.info(f"Loaded whisper.cpp model: {self.model_path}")
            
        except ImportError:
            self.logger.error("pywhispercpp not installed")
            raise
        except Exception as e:
            self.logger.error(f"Failed to load model: {e}")
            raise
    
    async def transcribe_file(self, file_path: str) -> str:
        """Transcribe audio file"""
        segments = self.model.transcribe(
            file_path,
            language=self.language
        )
        return " ".join(s.text for s in segments)
    
    async def transcribe_stream(
        self,
        audio_stream: AsyncIterator[bytes]
    ) -> AsyncIterator[str]:
        """
        Stream transcribe from audio chunks.
        
        Uses sliding window approach with overlap.
        """
        buffer = np.array([], dtype=np.float32)
        chunk_samples = int(16000 * 5)  # 5 second chunks
        overlap_samples = int(16000 * 1)  # 1 second overlap
        
        async for chunk in audio_stream:
            # Convert bytes to float32
            audio = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32767.0
            buffer = np.concatenate([buffer, audio])
            
            # Process when buffer is full
            while len(buffer) >= chunk_samples:
                window = buffer[:chunk_samples]
                
                # Write to temp file (whisper.cpp needs file input)
                import tempfile
                import wave
                
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                    temp_path = f.name
                    with wave.open(f, 'wb') as wav:
                        wav.setnchannels(1)
                        wav.setsampwidth(2)
                        wav.setframerate(16000)
                        wav.writeframes((window * 32767).astype(np.int16).tobytes())
                
                try:
                    segments = self.model.transcribe(temp_path, language=self.language)
                    text = " ".join(s.text for s in segments)
                    yield text
                finally:
                    import os
                    os.unlink(temp_path)
                
                # Slide window
                buffer = buffer[chunk_samples - overlap_samples:]
        
        # Process remaining audio
        if len(buffer) > 0.5 * 16000:  # At least 0.5 seconds
            # Process final chunk...
            pass
```

---

## 6. References

1. **whisper.cpp Repository**: https://github.com/ggml-org/whisper.cpp
2. **pywhispercpp**: https://github.com/abdeladim-s/pywhispercpp
3. **Whisper Streaming Paper**: https://arxiv.org/abs/2307.14743
4. **CoreML Support**: https://github.com/ggml-org/whisper.cpp/pull/566
5. **Metal Performance**: https://github.com/ggml-org/whisper.cpp/discussions/603
6. **Server Example**: https://github.com/ggml-org/whisper.cpp/tree/master/examples/server
7. **Streaming Example**: https://github.com/ggml-org/whisper.cpp/tree/master/examples/stream

---

## 7. Conclusion

For integrating whisper.cpp into EchoPanel:

1. **Use pywhispercpp** for direct Python integration with optimal performance
2. **Enable Metal** on macOS for 3-5x speedup
3. **Implement LocalAgreement** for streaming transcription
4. **Add VAD** to reduce processing of non-speech audio
5. **Use server mode** as fallback for isolated deployments

The combination of these approaches provides a robust, high-performance ASR solution suitable for real-time transcription services.
