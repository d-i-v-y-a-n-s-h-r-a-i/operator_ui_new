import socket
import struct
import time
import math
import sys

TARGET_IP = "127.0.0.1"
TARGET_PORT = 9001

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

magic = 0x544E4456
seq = 0
start_time = time.time()

target_roll = 15.0 if "--roll15" in sys.argv else None
static_trim = True if "--static-trim" in sys.argv else False

print(f"Starting mock vessel HIL blaster on {TARGET_IP}:{TARGET_PORT} @ 50Hz...")

try:
    while True:
        t = time.time() - start_time
        seq += 1

        if static_trim:
            roll = 0.0
            pitch = 2.1
            yaw = 42.0
            heading = 42.0
            lat = 12.971600
            lon = 77.594600
            speed = 0.0
            bat_v = 25.2
            bat_a = 0.8
            bat_pct = 98
            bat_temp = 24.5
            th_l = 0.0
            th_r = 0.0
            depth = 1.8
            w_temp = 22.0
            leak = 0
            armed = 0
            mode = 1
            link_q = 99
        elif target_roll is not None:
            roll = target_roll
            pitch = 4.0
            yaw = (t * 12.0) % 360.0
            heading = yaw
            lat = 12.971600 + (t * 0.00002)
            lon = 77.594600 + (t * 0.00002)
            speed = 12.0 + math.sin(t * 0.5) * 2.5
            bat_v = 24.8
            bat_a = 14.5
            bat_pct = max(10, int(98 - (t * 0.05)))
            bat_temp = 29.5
            th_l = 0.65
            th_r = 0.65
            depth = 8.2 + math.sin(t * 0.3) * 0.8
            w_temp = 23.5
            leak = 0
            armed = 1
            mode = 2
            link_q = 99
        else:
            roll = math.sin(t * 1.5) * 15.0
            pitch = math.cos(t * 1.0) * 6.0
            yaw = (t * 12.0) % 360.0
            heading = yaw
            lat = 12.971600 + (t * 0.00002)
            lon = 77.594600 + (t * 0.00002)
            speed = 12.0 + math.sin(t * 0.5) * 2.5
            bat_v = 24.8
            bat_a = 14.5
            bat_pct = max(10, int(98 - (t * 0.05)))
            bat_temp = 29.5
            th_l = 0.65
            th_r = 0.65
            depth = 8.2 + math.sin(t * 0.3) * 0.8
            w_temp = 23.5
            leak = 0
            armed = 1
            mode = 2
            link_q = 99

        bin_pkt = struct.pack(
            '<IIfffddffffBfffffBBBB',
            magic, seq,
            float(pitch), float(roll), float(yaw),
            float(lat), float(lon),
            float(speed), float(heading),
            float(bat_v), float(bat_a),
            int(bat_pct), float(bat_temp),
            float(th_l), float(th_r),
            float(depth), float(w_temp),
            int(leak), int(armed), int(mode), int(link_q)
        )
        sock.sendto(bin_pkt, (TARGET_IP, TARGET_PORT))

        if seq % 2 == 0:
            rpm = 0 if static_trim else int(3200 + math.sin(t) * 400)
            coolant = 24 if static_trim else int(68)
            can_payload_200 = bytes([(rpm >> 8) & 0xFF, rpm & 0xFF, coolant + 40, 0, 0, 0, 0, 0])
            can_pkt_200 = struct.pack('<IB8sI', 0x200, 8, can_payload_200, int(t * 1000) & 0xFFFFFFFF)
            sock.sendto(can_pkt_200, (TARGET_IP, TARGET_PORT))

            raw_v = int(bat_v / 0.01)
            can_payload_300 = bytes([0, 0, 0, 0, (raw_v >> 8) & 0xFF, raw_v & 0xFF, 0, 0])
            can_pkt_300 = struct.pack('<IB8sI', 0x300, 8, can_payload_300, int(t * 1000) & 0xFFFFFFFF)
            sock.sendto(can_pkt_300, (TARGET_IP, TARGET_PORT))

        if seq % 100 == 0:
            print(f"[HIL TX] seq={seq:06d} | roll={roll:+05.1f}deg | pitch={pitch:+05.1f}deg | spd={speed:04.1f}kts | hdg={heading:03.0f}deg | 50Hz OK")

        time.sleep(0.020)
except KeyboardInterrupt:
    print("\nBlaster stopped.")
