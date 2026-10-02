import sys, os, time, signal
from loragw import SX1302

SX1302_RESET_PIN=4      # SX1302 reset
SX1302_POWER_EN_PIN=17  # SX1302 power enable

FETCH_SLEEP_MS = 10

if len(sys.argv) < 2:
    print("Usage: %s conf.json" % os.path.basename(sys.argv[0]))
    sys.exit(1)

conf_file = sys.argv[1]
try:
    json_cfg = open(conf_file).read()
except:
    print("ERROR: %s not found or unreadable" % conf_file)
    sys.exit(1)

running = True
def signal_handler(sig, frame):
    global running
    print("Stopping...")
    running = False
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGHUP, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

modem = SX1302(json_cfg, debug=True, reset_pin=SX1302_RESET_PIN, power_pin=SX1302_POWER_EN_PIN)
modem.start()

while running:
    for pkt in modem.receive():
        print(
            "received packet: status %u, size %u, modulation %u, BW %u, DR %u, CR %u, channel RSSI %.1f" % (
             pkt.status, pkt.size, pkt.modulation, pkt.bandwidth, pkt.datarate, pkt.coderate, pkt.rssic
        ))
        print(
            "\tchannel %1u, rf chain: %1u, freq: %.6lf, modem id: %2u" % (
            pkt.if_chain, pkt.rf_chain, pkt.freq_hz / 1e6, pkt.modem_id
        ))
        print("\tpayload: ", pkt.payload)
    else:
        time.sleep(FETCH_SLEEP_MS)
        continue

modem.stop()
