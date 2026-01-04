#!/bin/bash
# Load test script - spawns multiple bot clients against the game server

SERVER_IP="${1:-127.0.0.1}"
SERVER_PORT="${2:-7777}"
NUM_BOTS="${3:-5}"
DURATION="${4:-60}"

echo "============================================"
echo "  Ashbane Load Test"
echo "============================================"
echo "  Server: $SERVER_IP:$SERVER_PORT"
echo "  Bots: $NUM_BOTS"
echo "  Duration: ${DURATION}s"
echo "============================================"

# Get baseline stats
echo ""
echo "=== Baseline Stats ==="
python3 -c "
import psutil
proc = psutil.Process($(pgrep -f 'ashbane-server'))
print(f'CPU: {proc.cpu_percent(interval=0.5):.1f}%')
print(f'Memory: {proc.memory_info().rss / (1024**2):.1f} MB')
print(f'Threads: {proc.num_threads()}')
"

# Array to track bot PIDs
BOT_PIDS=()

# Start bots
echo ""
echo "=== Starting $NUM_BOTS bots ==="
cd /opt/ashbane-game/source

for i in $(seq 1 $NUM_BOTS); do
    BOT_NAME="LoadBot_$i"
    echo "  Starting $BOT_NAME..."

    # Run headless Godot with bot flags
    /usr/local/bin/godot45 --headless -- --bot --bot-server $SERVER_IP --bot-port $SERVER_PORT --bot-name $BOT_NAME &
    BOT_PIDS+=($!)

    # Stagger bot starts to avoid connection flood
    sleep 1
done

echo ""
echo "=== All bots started, monitoring for ${DURATION}s ==="
echo ""

# Monitor during test
SAMPLES=0
TOTAL_CPU=0
MAX_CPU=0
MAX_MEM=0

SERVER_PID=$(pgrep -f 'ashbane-server')

for i in $(seq 1 $DURATION); do
    STATS=$(python3 -c "
import psutil
try:
    proc = psutil.Process($SERVER_PID)
    cpu = proc.cpu_percent(interval=0.5)
    mem = proc.memory_info().rss / (1024**2)
    threads = proc.num_threads()
    print(f'{cpu:.1f},{mem:.1f},{threads}')
except:
    print('0,0,0')
")

    CPU=$(echo $STATS | cut -d',' -f1)
    MEM=$(echo $STATS | cut -d',' -f2)
    THREADS=$(echo $STATS | cut -d',' -f3)

    # Track max values
    if (( $(echo "$CPU > $MAX_CPU" | bc -l) )); then
        MAX_CPU=$CPU
    fi
    if (( $(echo "$MEM > $MAX_MEM" | bc -l) )); then
        MAX_MEM=$MEM
    fi

    TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU" | bc)
    SAMPLES=$((SAMPLES + 1))

    # Print progress every 10 seconds
    if (( i % 10 == 0 )); then
        echo "  [$i/${DURATION}s] CPU: ${CPU}% | Mem: ${MEM}MB | Threads: $THREADS"
    fi

    sleep 1
done

# Calculate averages
AVG_CPU=$(echo "scale=1; $TOTAL_CPU / $SAMPLES" | bc)

echo ""
echo "=== Stopping bots ==="
for pid in "${BOT_PIDS[@]}"; do
    kill $pid 2>/dev/null
done

# Wait for cleanup
sleep 2

# Final stats
echo ""
echo "============================================"
echo "  Load Test Results"
echo "============================================"
echo "  Bots: $NUM_BOTS"
echo "  Duration: ${DURATION}s"
echo "  ---"
echo "  Avg CPU: ${AVG_CPU}%"
echo "  Max CPU: ${MAX_CPU}%"
echo "  Max Memory: ${MAX_MEM} MB"
echo "============================================"

# Post-test server stats
echo ""
echo "=== Post-test Server Stats ==="
python3 -c "
import psutil
try:
    proc = psutil.Process($SERVER_PID)
    print(f'CPU: {proc.cpu_percent(interval=0.5):.1f}%')
    print(f'Memory: {proc.memory_info().rss / (1024**2):.1f} MB')
    print(f'Threads: {proc.num_threads()}')
except Exception as e:
    print(f'Error: {e}')
"
