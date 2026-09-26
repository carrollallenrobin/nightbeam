"""
Procedural one-shot sounds for view FX (GDD section 7), no external assets. Each sound is synthesised
once at startup into a 22050 Hz mono 16-bit AudioStreamWAV and played from a small voice pool.
Audio randomness (noise) uses its own RNG and never touches the sim. Owner: view (GJ-13).
Sounds: shade fade 'sigh', shade reef hit 'gulp', flare-dissolve 'pop', ship wreck 'foghorn'.
"""
class_name SynthAudio extends Node

const MIX_RATE: int = 22050
const VOICE_COUNT: int = 6
const PCM_MAX: float = 32767.0

const FX_SIGH: StringName = &"sigh"
const FX_GULP: StringName = &"gulp"
const FX_POP: StringName = &"pop"
const FX_FOGHORN: StringName = &"foghorn"

# --- Sound recipes (GDD 7) ---
const SIGH_TIME: float = 0.5
const SIGH_FREQ_START: float = 900.0
const SIGH_FREQ_END: float = 300.0
const SIGH_GAIN: float = 0.35
const GULP_TIME: float = 0.35
const GULP_FREQ_START: float = 70.0
const GULP_FREQ_END: float = 45.0
const GULP_SPLASH_TIME: float = 0.08
const GULP_GAIN: float = 0.8
const POP_TIME: float = 0.12
const POP_FREQ_START: float = 1400.0
const POP_FREQ_END: float = 500.0
const POP_GAIN: float = 0.45
const FOGHORN_TIME: float = 0.8
const FOGHORN_FREQ_LOW: float = 110.0
const FOGHORN_FREQ_HIGH: float = 165.0
const FOGHORN_VIBRATO_HZ: float = 5.0
const FOGHORN_VIBRATO_DEPTH: float = 0.015
const FOGHORN_GAIN: float = 0.5
const BANDPASS_Q: float = 0.9
## Headless runs use the Dummy driver, which never releases playbacks (ObjectDB leak warning at exit).
const DUMMY_DRIVER: String = "Dummy"

var _streams: Dictionary = {}   # StringName -> AudioStreamWAV
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _audio_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _enabled: bool = true


func _ready() -> void:
	_enabled = AudioServer.get_driver_name() != DUMMY_DRIVER
	_audio_rng.randomize()
	for i: int in VOICE_COUNT:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	_streams[FX_SIGH] = _to_wav(_make_sigh())
	_streams[FX_GULP] = _to_wav(_make_gulp())
	_streams[FX_POP] = _to_wav(_make_pop())
	_streams[FX_FOGHORN] = _to_wav(_make_foghorn())


# Stop and drop streams on exit: a voice still playing at quit otherwise leaks its playback objects.
func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
	_streams.clear()


"""Plays one of the FX sounds (FX_SIGH, FX_GULP, FX_POP, FX_FOGHORN) on the next free voice."""
func play(sound: StringName) -> void:
	if not _enabled or not _streams.has(sound) or _voices.is_empty():
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[sound]
	voice.play()


# --- Synthesis ------------------------------------------------------------------

# Noise through a state-variable bandpass whose centre falls 900 -> 300 Hz: a soft breathy "sigh".
func _make_sigh() -> PackedFloat32Array:
	var n: int = int(SIGH_TIME * MIX_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var low: float = 0.0
	var band: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(n)
		var freq: float = lerpf(SIGH_FREQ_START, SIGH_FREQ_END, t)
		var f: float = 2.0 * sin(PI * freq / MIX_RATE)
		var high: float = _audio_rng.randf_range(-1.0, 1.0) - low - BANDPASS_Q * band
		band += f * high
		low += f * band
		out[i] = band * SIGH_GAIN * sin(PI * t)
	return out


# Sine sweeping 70 -> 45 Hz with a fast decay, plus a short noise splash at the start: a low "gulp".
func _make_gulp() -> PackedFloat32Array:
	var n: int = int(GULP_TIME * MIX_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var splash_n: int = int(GULP_SPLASH_TIME * MIX_RATE)
	for i: int in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(GULP_FREQ_START, GULP_FREQ_END, t) / MIX_RATE
		var body: float = sin(phase) * exp(-3.0 * t)
		var splash: float = 0.0
		if i < splash_n:
			splash = _audio_rng.randf_range(-1.0, 1.0) * 0.3 * (1.0 - float(i) / float(splash_n))
		out[i] = (body + splash) * GULP_GAIN
	return out


# Short falling chirp with a click of noise: the Shade bursting in the flare.
func _make_pop() -> PackedFloat32Array:
	var n: int = int(POP_TIME * MIX_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(POP_FREQ_START, POP_FREQ_END, t) / MIX_RATE
		var click: float = _audio_rng.randf_range(-1.0, 1.0) * maxf(0.0, 1.0 - t * 6.0)
		out[i] = (sin(phase) * 0.7 + click * 0.3) * exp(-5.0 * t) * POP_GAIN
	return out


# Two detuned sines with a 5 Hz vibrato and a soft attack/release: the ship wreck foghorn.
func _make_foghorn() -> PackedFloat32Array:
	var n: int = int(FOGHORN_TIME * MIX_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var phase_low: float = 0.0
	var phase_high: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(n)
		var vib: float = 1.0 + FOGHORN_VIBRATO_DEPTH * sin(TAU * FOGHORN_VIBRATO_HZ * float(i) / MIX_RATE)
		phase_low += TAU * FOGHORN_FREQ_LOW * vib / MIX_RATE
		phase_high += TAU * FOGHORN_FREQ_HIGH * vib / MIX_RATE
		var env: float = minf(t * 10.0, 1.0) * minf((1.0 - t) * 5.0, 1.0)
		out[i] = (sin(phase_low) + 0.6 * sin(phase_high)) * 0.6 * env * FOGHORN_GAIN
	return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * PCM_MAX))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
