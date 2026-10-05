import time, signal
from loragw import SX1302

SX1302_RESET_PIN=4      # SX1302 reset
SX1302_POWER_EN_PIN=17  # SX1302 power enable

FETCH_SLEEP_MS = 10

json_cfg = """
{
    "SX130x_conf": {
        "com_type": "SPI",
        "com_path": "/dev/spidev0.0",
        "lorawan_public": false,
        "clksrc": 0,
        "full_duplex": false,
        "radio_0": {
            "enable": true,
            "type": "SX1250",
            "freq": 867500000,
            "rssi_offset": -215.4,
            "rssi_tcomp": {"coeff_a": 0, "coeff_b": 0, "coeff_c": 20.41, "coeff_d": 2162.56, "coeff_e": 0},
            "tx_enable": false
        },
        "radio_1": {
            "enable": true,
            "type": "SX1250",
            "freq": 868500000,
            "rssi_offset": -215.4,
            "rssi_tcomp": {"coeff_a": 0, "coeff_b": 0, "coeff_c": 20.41, "coeff_d": 2162.56, "coeff_e": 0},
            "tx_enable": false
        },
        "chan_multiSF_All": {"spreading_factor_enable": [ 5, 6, 7, 8, 9, 10, 11, 12 ]},
        "chan_multiSF_0": {"enable": true, "radio": 1, "if": -400000},
        "chan_multiSF_1": {"enable": true, "radio": 1, "if": -200000},
        "chan_multiSF_2": {"enable": true, "radio": 1, "if":  0},
        "chan_multiSF_3": {"enable": true, "radio": 0, "if": -400000},
        "chan_multiSF_4": {"enable": true, "radio": 0, "if": -200000},
        "chan_multiSF_5": {"enable": true, "radio": 0, "if":  0},
        "chan_multiSF_6": {"enable": true, "radio": 0, "if":  200000},
        "chan_multiSF_7": {"enable": true, "radio": 0, "if":  400000}
    }
}
"""

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
            "received packet: count μs %u, status %s, size %u, modulation %s, channel RSSI %.1f" % (
             pkt.count_us, pkt.status, pkt.size, pkt.modulation, pkt.rssic))
        print(
            "\tchannel %1u, rf chain: %1u, freq: %.6lf, modem id: %d" % (
            pkt.if_chain, pkt.rf_chain, pkt.freq_hz / 1e6, pkt.modem_id))
        if pkt.modulation == "LORA":
            print(
                "\tDR SF%d, BW %s, CR %s, signal RSSI %.0f, LoRa SNR: %.1f, freq offset: %d" % (
                pkt.datarate, pkt.bandwidth, pkt.coderate, round(pkt.rssis), pkt.snr, pkt.freq_offset))
        elif pkt.modulation == "FSK":
            print("\tdatarate %d" % pkt.datarate)

        print("\tpayload: ", pkt.payload)
    else:
        time.sleep(0.001 * FETCH_SLEEP_MS)
        continue

modem.stop()
