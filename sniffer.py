import time, signal, os
from datetime import datetime
from loragw import *

# defaults are for Embit gateways or RaspberryPi3/4 with Embit cape and radio module
SX1302_RESET_PIN=4       # SX1302 reset
SX1302_POWER_EN_PIN=17   # SX1302 power enable
SX126X_NRESET_PIN=12     # SX126X nreset

FETCH_SLEEP_MS = 10
REPLY_TO_PINGS = True

os.chdir(os.path.realpath(os.path.dirname(__file__)))
json_cfg = open("global_conf.json", "r").read()

running = True
def signal_handler(sig, frame):
    global running
    print("Stopping...")
    running = False
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGHUP, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

modem = SX1302(json_cfg, debug=True, reset_pin=SX1302_RESET_PIN, power_pin=SX1302_POWER_EN_PIN, sx126x_nreset_pin=SX126X_NRESET_PIN)
scanner = modem.spectral_scan()
modem.start()

def decode(key, val):
    if key == "status":
        return {STAT_NO_CRC: "NO CRC", STAT_CRC_BAD: "BAD CRC", STAT_CRC_OK: "CRC OK"}.get(val, "UNDEF")
    elif key == "modulation":
        return {MOD_CW: "CW", MOD_LORA: "LORA", MOD_FSK: "FSK"}.get(val, "UNDEF")
    elif key == "bandwidth":
        return {BW_500KHZ: "500kHz", BW_250KHZ: "250kHz", BW_125KHZ: "125kHz"}.get(val, "UNDEF")
    elif key == "coderate":
        return "4/%d" % (val + 4)

while running:
    for pkt in modem.receive():
        tstamp = datetime.now().strftime("%X.%f")
        print(
            "[%s] received packet: count μs %u, status %s, size %u, modulation %s, channel RSSI %.1f" % (
             tstamp, pkt.count_us, pkt.status, pkt.size, decode("modulation", pkt.modulation), pkt.rssic))
        print(
            "\tchannel %1u, rf chain: %1u, freq: %.6lf, modem id: %d" % (
            pkt.if_chain, pkt.rf_chain, pkt.freq_hz / 1e6, pkt.modem_id))
        if pkt.modulation == MOD_LORA:
            print(
                "\tDR SF%d, BW %s, CR %s, signal RSSI %.0f, LoRa SNR: %.1f, freq offset: %d" % (
                pkt.datarate, decode("bandwidth", pkt.bandwidth), decode("coderate", pkt.coderate),
                round(pkt.rssis), pkt.snr, pkt.freq_offset))
        elif pkt.modulation == MOD_FSK:
            print("\tdatarate %d" % pkt.datarate)

        print("\tpayload: ", pkt.payload)

        if REPLY_TO_PINGS:
            if pkt.payload[:4] == b'PING':
                ans = TxPacket()
                for key in ["freq_hz", "modulation", "bandwidth", "datarate", "coderate"]:
                    setattr(ans, key, getattr(pkt, key))
                ans.rf_power = 14
                ans.payload = b'PONG: ' + pkt.payload
                modem.send(ans)

    else:
        if scanner:
            scan = next(scanner)
            if scan:
                freq_hz, levels, results = scan
                print("SPECTRAL SCAN - %u Hz: %s" % (freq_hz, " ".join([f"{r}" for r in results])))
        time.sleep(0.001 * FETCH_SLEEP_MS)
        continue

modem.stop()
