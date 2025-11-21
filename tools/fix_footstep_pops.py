#!/usr/bin/env python3
"""
Fix audio popping by adding fade-in and fade-out to WAV files
Requires: pip install numpy scipy
"""

import os
import numpy as np
from scipy.io import wavfile

def apply_fade(audio_data, sample_rate, fade_ms=5):
    """Apply linear fade-in and fade-out to audio data"""
    fade_samples = int(sample_rate * fade_ms / 1000.0)

    # Create fade curves
    fade_in = np.linspace(0.0, 1.0, fade_samples)
    fade_out = np.linspace(1.0, 0.0, fade_samples)

    # Apply fade-in
    if audio_data.ndim == 1:  # Mono
        audio_data[:fade_samples] = audio_data[:fade_samples] * fade_in
        audio_data[-fade_samples:] = audio_data[-fade_samples:] * fade_out
    else:  # Stereo
        audio_data[:fade_samples, :] = audio_data[:fade_samples, :] * fade_in[:, np.newaxis]
        audio_data[-fade_samples:, :] = audio_data[-fade_samples:, :] * fade_out[:, np.newaxis]

    return audio_data

def process_file(input_path):
    """Process a single WAV file"""
    try:
        print(f"Processing: {input_path}")

        # Read WAV file
        sample_rate, audio_data = wavfile.read(input_path)

        # Convert to float for processing
        audio_float = audio_data.astype(np.float32)

        # Apply fades
        audio_faded = apply_fade(audio_float, sample_rate, fade_ms=5)

        # Convert back to original dtype
        audio_output = audio_faded.astype(audio_data.dtype)

        # Create output filename
        output_path = input_path.replace('.wav', '_fixed.wav')

        # Save processed file
        wavfile.write(output_path, sample_rate, audio_output)

        print(f"  ✅ Saved: {output_path}")
        return True

    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False

def main():
    print("🔧 Fixing footstep audio pops...\n")

    base_path = r"C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\sounds\footsteps"

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
            print(f"⚠️ File not found: {filepath}")

    print(f"\n✅ Done! Processed {success_count}/{len(files)} files.")
    print("Replace the original files with the _fixed versions if they sound better.")

if __name__ == "__main__":
    main()
