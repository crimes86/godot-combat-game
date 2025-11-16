#!/usr/bin/env python3
"""
Sound Processing Script - Trim and speed up combat sounds

This script will:
1. Trim sounds to first 0.3-0.5 seconds
2. Speed them up slightly (1.2x-1.5x)
3. Fade in/out to prevent clicks
4. Normalize volume

Usage:
    python process_sounds.py input.wav output.wav [duration] [speed]

Example:
    python process_sounds.py weakpoint_hit.wav weakpoint_hit_processed.wav 0.3 1.3
"""

import sys
import wave
import array
import math

def process_sound(input_file, output_file, target_duration=0.3, speed_multiplier=1.3):
    """
    Process audio file: trim, speed up, and normalize

    Args:
        input_file: Input WAV file path
        output_file: Output WAV file path
        target_duration: Target duration in seconds (default 0.3)
        speed_multiplier: Speed multiplier (default 1.3 = 30% faster)
    """
    print(f"Processing: {input_file}")
    print(f"Target duration: {target_duration}s, Speed: {speed_multiplier}x")

    # Read input file
    with wave.open(input_file, 'rb') as wav_in:
        params = wav_in.getparams()
        n_channels = params.nchannels
        sample_width = params.sampwidth
        framerate = params.framerate
        n_frames = params.nframes

        # Read all frames
        frames = wav_in.readframes(n_frames)
        samples = array.array('h', frames)  # 16-bit signed integers

        print(f"Input: {n_channels}ch, {framerate}Hz, {n_frames} frames ({n_frames/framerate:.2f}s)")

    # Calculate target number of samples
    target_samples = int(target_duration * framerate * n_channels)

    # Speed up by skipping samples
    if speed_multiplier > 1.0:
        print(f"Speeding up by {speed_multiplier}x...")
        new_samples = []
        step = speed_multiplier
        i = 0.0
        while int(i) < len(samples) and len(new_samples) < target_samples:
            new_samples.append(samples[int(i)])
            i += step
        samples = array.array('h', new_samples)

    # Trim to target duration
    if len(samples) > target_samples:
        print(f"Trimming from {len(samples)} to {target_samples} samples...")
        samples = samples[:target_samples]

    # Apply quick fade in (5ms) and fade out (20ms)
    fade_in_samples = int(0.005 * framerate * n_channels)  # 5ms
    fade_out_samples = int(0.020 * framerate * n_channels)  # 20ms

    print("Applying fades...")
    for i in range(min(fade_in_samples, len(samples))):
        factor = i / fade_in_samples
        samples[i] = int(samples[i] * factor)

    for i in range(min(fade_out_samples, len(samples))):
        idx = len(samples) - 1 - i
        if idx >= 0:
            factor = i / fade_out_samples
            samples[idx] = int(samples[idx] * factor)

    # Normalize to 90% of max to prevent clipping
    print("Normalizing volume...")
    max_val = max(abs(s) for s in samples)
    if max_val > 0:
        target_max = int(32767 * 0.9)  # 90% of max 16-bit value
        scale_factor = target_max / max_val
        samples = array.array('h', [int(s * scale_factor) for s in samples])

    # Write output file
    print(f"Writing to: {output_file}")
    with wave.open(output_file, 'wb') as wav_out:
        wav_out.setparams(params)
        wav_out.writeframes(samples.tobytes())

    output_duration = len(samples) / (framerate * n_channels)
    print(f"✅ Done! Output duration: {output_duration:.3f}s\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        print("\nQuick process all sounds in current directory:")
        print("    python process_sounds.py --batch")
        sys.exit(1)

    if sys.argv[1] == "--batch":
        # Batch process common sound files
        import os
        import glob

        print("Batch processing all .wav files in current directory...\n")

        # Create output directory
        os.makedirs("processed", exist_ok=True)

        # Process each WAV file
        for input_file in glob.glob("*.wav"):
            if input_file.startswith("processed_"):
                continue

            output_file = f"processed/{input_file}"

            # Determine duration based on filename
            if "weakpoint" in input_file.lower() or "critical" in input_file.lower():
                duration = 0.3  # Short and punchy
                speed = 1.4
            elif "death" in input_file.lower():
                duration = 0.5  # Slightly longer
                speed = 1.2
            elif "hit" in input_file.lower() or "hurt" in input_file.lower():
                duration = 0.25
                speed = 1.3
            else:
                duration = 0.3
                speed = 1.3

            try:
                process_sound(input_file, output_file, duration, speed)
            except Exception as e:
                print(f"❌ Error processing {input_file}: {e}\n")

        print("✅ Batch processing complete! Check the 'processed' folder.")

    else:
        input_file = sys.argv[1]
        output_file = sys.argv[2]
        duration = float(sys.argv[3]) if len(sys.argv) > 3 else 0.3
        speed = float(sys.argv[4]) if len(sys.argv) > 4 else 1.3

        process_sound(input_file, output_file, duration, speed)
