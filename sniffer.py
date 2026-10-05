import time, signal
from loragw import *

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
            "tx_enable": true,
            "tx_freq_min": 863000000,
            "tx_freq_max": 870000000,
            "tx_gain_lut":[
                {"rf_power": 12, "pa_gain": 0, "pwr_idx": 15},
                {"rf_power": 13, "pa_gain": 0, "pwr_idx": 16},
                {"rf_power": 14, "pa_gain": 0, "pwr_idx": 17},
                {"rf_power": 15, "pa_gain": 0, "pwr_idx": 19},
                {"rf_power": 16, "pa_gain": 0, "pwr_idx": 20},
                {"rf_power": 17, "pa_gain": 0, "pwr_idx": 22},
                {"rf_power": 18, "pa_gain": 1, "pwr_idx": 1},
                {"rf_power": 19, "pa_gain": 1, "pwr_idx": 2},
                {"rf_power": 20, "pa_gain": 1, "pwr_idx": 3},
                {"rf_power": 21, "pa_gain": 1, "pwr_idx": 4},
                {"rf_power": 22, "pa_gain": 1, "pwr_idx": 5},
                {"rf_power": 23, "pa_gain": 1, "pwr_idx": 6},
                {"rf_power": 24, "pa_gain": 1, "pwr_idx": 7},
                {"rf_power": 25, "pa_gain": 1, "pwr_idx": 9},
                {"rf_power": 26, "pa_gain": 1, "pwr_idx": 11},
                {"rf_power": 27, "pa_gain": 1, "pwr_idx": 14}
            ]
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
        "chan_multiSF_7": {"enable": true, "radio": 0, "if":  400000},
        "chan_Lora_std":  {"enable": true, "radio": 1, "if": -200000, "bandwidth": 250000, "spread_factor": 7,
                           "implicit_hdr": false, "implicit_payload_length": 17, "implicit_crc_en": false, "implicit_coderate": 1},
        "chan_FSK":       {"enable": true, "radio": 1, "if":  300000, "bandwidth": 125000, "datarate": 50000}

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
        print(
            "received packet: count μs %u, status %s, size %u, modulation %s, channel RSSI %.1f" % (
             pkt.count_us, pkt.status, pkt.size, decode("modulation", pkt.modulation), pkt.rssic))
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

    else:
        time.sleep(0.001 * FETCH_SLEEP_MS)
        continue

modem.stop()
