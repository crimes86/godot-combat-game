#!/usr/bin/env python3
"""
Fix audio popping by adding fade-in and fade-out to WAV files
Uses only built-in Python libraries (no dependencies)
"""

import wave
import struct
import os

def apply_fade(audio_data, sample_rate, channels, fade_ms=5):
    """Apply linear fade-in and fade-out to audio data"""
    fade_samples = int(sample_rate * fade_ms / 1000.0)

    # Unpack audio data
    sample_width = 2  # 16-bit
    format_char = 'h'  # signed short
    num_samples = len(audio_data) // (sample_width * channels)

    # Unpack samples
    samples = []
    for i in range(num_samples):
        frame = []
        for ch in range(channels):
            offset = (i * channels + ch) * sample_width
            sample = struct.unpack_from(format_char, audio_data, offset)[0]
            frame.append(sample)
        samples.append(frame)

    # Apply fade-in
    for i in range(min(fade_samples, num_samples)):
        fade_factor = i / fade_samples
        for ch in range(channels):
            samples[i][ch] = int(samples[i][ch] * fade_factor)

    # Apply fade-out
    fade_start = max(0, num_samples - fade_samples)
    for i in range(fade_start, num_samples):
        fade_factor = (num_samples - i) / fade_samples
        for ch in range(channels):
            samples[i][ch] = int(samples[i][ch] * fade_factor)

    # Pack samples back
    output_data = bytearray()
    for frame in samples:
        for sample in frame:
            output_data.extend(struct.pack(format_char, sample))

    return bytes(output_data)

def process_file(input_path):
    """Process a single WAV file"""
    try:
        print(f"Processing: {input_path}")

        # Read WAV file
        with wave.open(input_path, 'rb') as wav:
            params = wav.getparams()
            audio_data = wav.readframes(params.nframes)

        # Apply fades
        audio_faded = apply_fade(audio_data, params.framerate, params.nchannels, fade_ms=5)

        # Create output filename
        output_path = input_path.replace('.wav', '_fixed.wav')

        # Save processed file
        with wave.open(output_path, 'wb') as wav_out:
            wav_out.setparams(params)
            wav_out.writeframes(audio_faded)

        print(f"  Saved: {output_path}")
        return True

    except Exception as e:
        print(f"  Error: {e}")
        return False

def main():
    print("Fixing footstep audio pops...\n")

    base_path = r"C:\Users\kevin\OneDrive\fantom\mmo\wasteland\assets\sounds\footsteps"

    files = [
        "player_step_1.wav",
        "player_step_2.wav",
        "player_step_3.wav",
        "skeleton_step_1.wav",
        "skeleton_step_2.wav",
        "skeleton_step_3.wav",
    ]

    success_count = 0
    for filename in files:
        filepath = os.path.join(base_path, filename)
        if os.path.exists(filepath):
            if process_file(filepath):
                success_count += 1
        else:
            print(f"File not found: {filepath}")

    print(f"\nDone! Processed {success_count}/{len(files)} files.")
    print("Replace the original files with the _fixed versions if they sound better.")

if __name__ == "__main__":
    main()
